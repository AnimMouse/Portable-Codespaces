# CLAUDE.md

Project context for Portable-Codespaces: a GitHub Codespaces-like system on any
Ubuntu VPS or Raspberry Pi, installed in a single folder in `~`.

This is the third sibling. Most of the design comes from the other two, so read
them before re-solving anything about devcontainers, dotfiles or secrets:

- [NixOS-Codespaces-VirtualBox](https://github.com/AnimMouse/NixOS-Codespaces-VirtualBox):
  read `CLAUDE.md` §3 and §8. It has the devcontainer CLI plumbing, the
  code-server install and the immutable code-server cache.
- [Sprites-Codespaces](https://github.com/AnimMouse/Sprites-Codespaces): read
  `CLAUDE.md` §3, §6 and §7. It has the PAT and secrets model, `ssh-auth`,
  dotfiles and `DOTFILES_TOKEN`.

---

## 1. Goal

`~/portable-codespaces/codespace up owner/repo` on any Ubuntu host gives a
code-server editor on that repo. You reach it from Firefox on Windows through
an SSH tunnel, with `git push`, `gh`, dotfiles and secrets working. Repos with
a `devcontainer.json` are built with the real devcontainer CLI, so
`devcontainer.json` files stay portable to GitHub Codespaces and to the NixOS
VM.

**Success criteria:**

1. `git clone` → `codespace setup` → `codespace up` works on a fresh host.
   Nothing outside the folder is needed except Docker (already there, or
   installed from apt) and sudo.
2. **On a production host, codespaces never take CPU, RAM, disk or network
   away from the jobs already running there.**
3. After `codespace uninstall` and removing the folder, the host is as it was.
   The one exception is the Docker packages, if `install-docker` added them,
   and those are removed only on request.

---

## 2. Environment facts — read before proposing anything

| Fact | Consequence |
|---|---|
| **The main use case is the user's company production VPSes**, to use their idle CPU | Disturbing production is the worst failure. §5 is not optional, and every design choice is judged against it first |
| Production VPSes run Ubuntu 26.04 and **already have Docker**, running real workloads | Never change the host Docker's global state: no `daemon.json`, no `dockerd` restart, no `system prune`, no unlabelled removals (§5) |
| Disposable VPSes (Ubuntu 24.04/26.04) **may have no Docker** | `install-docker` is opt-in and shows a warning first (§6) |
| VPSes are **both x86_64 and arm64** (ARM is cheaper) | Every downloaded tool is pinned for amd64 **and** arm64. No QEMU/binfmt fallback, because that is a global kernel change. An amd64-only image fails on ARM with a clear message |
| Raspberry Pi 4 Model B, **8 GB**, Ubuntu 24.04 arm64 (26.04 later) | Personal, not production. Caps can be looser through the config. Put `data/` on an SSD rather than the SD card |
| The user's PC is Windows with **WSL2 and Hyper-V deliberately disabled** (see the NixOS sibling's §2) | Never suggest WSL. The client side is the built-in Windows OpenSSH plus Firefox |
| The browser is Firefox, and the user dislikes Electron | The editor is code-server in the browser. Never propose VS Code Desktop or Remote-SSH as the primary interface |
| The NixOS VM already uses `localhost:8001-8020` on the PC | Each host needs its own `PORT_BASE` so tunnelled ports don't collide (§3) |
| sudo is available and acceptable | Use it for `chattr`, cgroup setup and uninstall. Keep each use narrow and say why |
| Projects that need Docker inside the codespace stay on the NixOS VM | docker-in-docker inside codespaces is a non-goal (§4) |

---

## 3. Locked architectural decisions

These are settled. Do not re-open them unless the user explicitly asks.

### `@devcontainers/cli` + Docker, code-server inside each container
Same as both siblings. If a repo has `.devcontainer/devcontainer.json` or
`.devcontainer.json`, it is used. Otherwise `templates/devcontainer.json` is
generated outside the checkout and passed with `--override-config
--no-lockfile`. **Never write into the checkout.**

### Scoop-style install: everything not from apt lives in the folder
- Tools go in `apps/<tool>/<version>/`, with an `apps/<tool>/current` symlink
  and shims in `bin/`.
- `manifest` pins each tool's version, plus a URL and sha256 **per
  architecture** (amd64, arm64). Downloads are verified before unpacking.
- The tools:
  - **Node**: official tarball, used only to run the devcontainer CLI. The
    apt `nodejs` package is too old on some releases.
  - **devcontainer CLI**: installed with `npm --prefix` into its own app
    directory.
  - **code-server**: standalone release tarball.
- `codespace update` moves tools to newer pinned versions. Old versions are
  kept until `gc` finds no codespace using them.
- Nothing is added to `~/.bashrc` or `PATH`. You call the CLI by its path, or
  symlink it yourself.

### code-server: unpacked once per version, immutable, mounted
Carried over from the NixOS sibling §8:
- Each version is unpacked under a lock into `apps/code-server/<v>/`, moved
  into place by rename from a staging directory, then locked with `sudo find
  ! -type l -exec chattr +i`. Do not use `chattr -R`, because it fails on
  symlinks.
- It is mounted into every container. The devcontainer CLI's `--mount` cannot
  be read-only, and the immutable bit is what stops a compromised codespace
  from planting an editor for the others.
- `uninstall` clears the bit with `chattr -i` before deleting.

### Editors on `127.0.0.1:<PORT_BASE+n>`, reached only through an SSH tunnel
- code-server runs with `--auth none`. The SSH tunnel is the only lock, so
  **an editor must never bind to anything but loopback.**
- `http://localhost` on the PC side is a browser secure context, which the
  clipboard and parts of code-server need.
- `PORT_BASE` is set per host (for example a VPS at 9001, the Pi at 9101) so
  tunnelled ports don't collide with each other or with the NixOS VM.
- Each codespace keeps its port in `data/state/<name>/`, so a bookmark stays
  valid.
- `setup` and `up` refuse a port that something on the host already uses.
- `codespace tunnel` prints the `ssh -L` line, or a `LocalForward` block for
  `~/.ssh/config`.
- The devcontainer CLI cannot publish ports, so the editor is reached through
  the container IP, as in the siblings. How exactly is decided in Phase 1
  (§9), but the result must bind to loopback only.

### GitHub auth: PAT and secrets files (the Sprites model)
- Secrets come in three scopes, merged broadest first, with the narrower
  scope winning key by key:
  1. `secrets`
  2. `repos/<owner>/<repo>.secrets`
  3. `<name>.secrets`
- **One** token is resolved, first non-empty wins:
  1. `GITHUB_TOKEN` in the secrets
  2. `GH_TOKEN` in the secrets
  3. `GITHUB_TOKEN` in the environment
  4. `GH_TOKEN` in the environment
  5. `gh auth token`
- The winner is exported as both names, so git and `gh` always act as the same
  identity.
- A git credential helper that only reads `$GH_TOKEN` is set at system level
  in the container.
- `DOTFILES_TOKEN` is stored but never exported.
- `SSH_KEY` is unlocked into an ssh-agent with `codespace ssh-auth`. The
  decrypted key lives only in the agent's memory, and only the `.pub` is kept
  on disk.
- The GitHub App broker from the NixOS sibling is not used.

### Two containment modes, chosen per host (`MODE` in the config)

| | **host** (default) | **isolated** |
|---|---|---|
| Docker daemon | the host's own | `docker:dind`, one privileged container started with plain `docker run` (no compose) |
| Images, volumes, build cache | `/var/lib/docker`, labelled `portable-codespaces` | `data/docker/` in the folder |
| Caps on image builds | no, builds run in the host's `dockerd` | yes, builds run inside the capped dind container |
| A codespace escape reaches | the host only through a kernel exploit | the privileged dind container, so effectively root on the host |
| Uninstall | remove labelled resources and the base images we pulled, if nothing else uses them | stop dind, delete `data/docker`, remove the dind image |
| For | **production** | disposable VPSes, or when full containment matters more |

- In isolated mode, the CLI reaches dind through `DOCKER_HOST`, a unix socket
  under `data/`.
- `data/workspaces` is mounted into dind **at the same absolute path**,
  because the devcontainer CLI passes host paths to the daemon.

### Nothing of ours starts at boot (`AUTOSTART=0`)
- After a reboot, production comes up alone, and `codespace up <name>` brings
  a codespace back.
- No systemd units, cron entries or restart policies are written. Setting
  `AUTOSTART=1` gives containers `restart: unless-stopped`, and it's meant for
  the Pi.
- Without a boot hook, the `--runtime` cgroup limits from §5 are gone after a
  reboot. `up` reapplies them **before** starting any container, and
  autostarted containers must not start before the limits exist. Phase 1
  decides how to guarantee that.

### The local half is the only half
- The CLI runs on the host itself: over SSH, or `ssh host
  portable-codespaces/codespace …` from Windows.
- There is no PC-side component beyond `ssh`.
- Logic that runs inside containers lives in `lib/` and is copied in at
  create time.

---

## 4. Non-goals

- Docker inside codespaces (docker-in-docker or docker-outside-of-docker).
  Those projects use the NixOS VM.
- Public HTTPS, mTLS, Cloudflare Tunnel or Tailscale for now. The SSH tunnel
  is the design. If one is added later, it must keep code-server unreachable
  without authentication.
- The GitHub App token broker.
- Idle auto-stop and sleep.
- Coder, Kubernetes, envbuilder and Podman (same as both siblings).
- QEMU/binfmt emulation for foreign-architecture images.
- Anything written outside the folder, except:
  - Docker's own state in host mode (labelled);
  - the `--runtime` cgroup properties under `/run`;
  - the Docker packages, when `install-docker` was used.
- Changing the user's shell startup files.

---

## 5. Production safety — required, not nice-to-have

### One cgroup for everything we run
- All codespace containers (and, in isolated mode, the dind container) go into
  one parent cgroup, so **the limits apply to all codespaces combined**, not
  to each one.
- Defaults, set in the config per host:

  | Setting | Default | Effect |
  |---|---|---|
  | `CPU_MAX` | `50%` of cores | hard ceiling |
  | `CPU_WEIGHT` | low (well under the default 100) | production wins whenever both want the CPU |
  | `MEM_MAX` | `40%` of RAM | hard ceiling |
  | `PIDS_MAX` | finite | contains a fork bomb |
  | `OOM_SCORE_ADJ` | high, positive | when memory runs out across the host, the kernel kills codespaces before production |

- The limits are set with `systemctl set-property --runtime` (or the matching
  cgroupfs files), so they live in `/run` and nothing goes in `/etc`.
- On the Pi, raise them in its config (for example `CPU_MAX=100%`,
  `MEM_MAX=75%`).
- Disk-I/O weight is applied when the block device's scheduler honours it.
  Virtio disks often use `none`, so it is never promised.

### Caps without touching the repo's `devcontainer.json`
- The devcontainer CLI is run with `--docker-path lib/docker-wrapper`.
- The wrapper passes everything through to the real `docker` (or to dind's
  socket). On `run` and `create`, it first adds:
  - `--label portable-codespaces=<name>`
  - `--cgroup-parent=<our cgroup>`
  - `--oom-score-adj`
  - `--pids-limit`
  - the image's platform check
- The repo's config is never edited, and the generated config doesn't need
  `runArgs`.
- Verified at the end of every `up`: the container is in the right cgroup and
  carries the label. A container that missed the wrapper is stopped and
  reported, never left running uncapped.

### Hands off the host's Docker
- **Never:**
  - `docker system prune`, `image prune` or `volume prune` without our label
    filter;
  - editing `/etc/docker/daemon.json`;
  - restarting `dockerd`;
  - creating networks without our label;
  - publishing ports on anything but `127.0.0.1`.
- `setup` records the image IDs already present in `data/state/preexisting-images`.
- `uninstall` and `gc` remove only images that:
  - we pulled or built;
  - are absent from that record;
  - no container uses, whatever its label.

### Disk floor
- `up`, `rebuild` and `update` refuse to run below `DISK_FLOOR`, default:
  whichever is larger of 10 GB free or 15% of the filesystem holding Docker's
  data.
- `gc` removes codespaces idle past `RETENTION_DAYS` (default 30, as in
  Codespaces).
- Last use is recorded by the CLI and never inferred from Docker timestamps
  (NixOS sibling §8).

---

## 6. `install-docker` — opt-in, for disposable hosts

`setup` detects that Docker is missing and points to `codespace
install-docker`. That command first prints a warning:

- Docker is a daemon running as root, and membership of the `docker` group is
  effectively root.
- It changes the firewall: iptables `FORWARD` policy goes to DROP and NAT
  rules are added, which can break VPNs, libvirt bridges and routed traffic.
  It also bypasses ufw for published ports. Ours are loopback-only.
- It prints the current `FORWARD` policy, ufw status and nftables tables, so
  you can see what would change.

Only after you type `yes` does it:
1. run `apt-get install docker.io`;
2. add you to the `docker` group, which needs a new login;
3. write `data/state/docker-installed-by-us`.

`uninstall` offers to remove Docker **only** when that marker exists. Compose
is not needed.

---

## 7. Repository layout

```
codespace                    CLI (bash): setup install-docker up new list shell down rebuild rm
                             logs status sync ssh-auth tunnel update gc uninstall
lib/                         docker-wrapper, credential helper, in-container setup scripts
manifest                     tool → version, url + sha256 for amd64 and arm64
templates/devcontainer.json  default for repos without one (mcr devcontainers base:ubuntu, multi-arch)
config.example
README.md                    user-facing docs
CLAUDE.md                    this file: design authority
HANDOFF.md                   where things stand, what is untested
.gitignore                   apps/ bin/ data/ .portable-codespaces/
```

At run time, inside the same folder:

```
apps/<tool>/<version>/       Scoop area; code-server versions immutable (chattr +i)
apps/<tool>/current          symlink to the active version
bin/                         shims
.portable-codespaces/        config, secrets, repos/<owner>/<repo>.secrets, <name>.secrets (0600)
data/workspaces/<name>/      checkouts; only this is bind-mounted, at /workspaces/<name>
data/refs/                   mounted at /workspaces/refs in every container (NixOS sibling)
data/state/<name>/           port, mode, last-used, generated devcontainer.json, secrets inbox
data/state/                  preexisting-images, docker-installed-by-us, pulled-images
data/dotfiles/<name>/        per-codespace dotfiles snapshot (no shared writable copy)
data/docker/                 isolated mode only: dind's data-root
```

The config is a directory with a distinctive name, not a bare `./config`,
because the CLI *sources* it (Sprites sibling §5).

---

## 8. Known gotchas carried over — encode these as fixes from the start

Found in the siblings and still true here. Their CLAUDE.md files have the
details.

| Gotcha | Handling |
|---|---|
| `devcontainer up` has no `--publish`, and there is no `down` | Reach the editor through the container. `down` is `docker stop` |
| No third-party code-server feature resolves on ghcr | Install code-server ourselves (the immutable mount, §3) |
| `code-server` with no path opens no folder | Pass `remoteWorkspaceFolder` from `up`'s JSON |
| The CLI refuses to guess a `devcontainer.json` | Generate one into `data/state/<name>/` and pass `--override-config --no-lockfile` |
| `--remote-env` and `--secrets-file` don't persist past `up` | Use `--secrets-file` at create, plus a 0600 `~/.codespace-secrets` sourced from `/etc/profile.d`. Start the editor from `bash -l` |
| The dotfiles clone runs before any credential exists | Fetch dotfiles on the host (with `DOTFILES_TOKEN`, else the token) into a per-codespace snapshot, and mount that |
| A shared, writable dotfiles copy is a cross-container hole | One snapshot per codespace |
| `--mount` rejects `readonly` | The immutable bit (code-server), or a directory holding only what is needed |
| Docker named volumes are global to the daemon | `${devcontainerId}` in volume names that hold state |
| Only `/workspaces/<name>` is a mount | `/workspaces` stays root-owned. `rebuild`/`rm` list anything else under it before discarding |
| `pgrep -f` matches itself | Check liveness with an HTTP probe of `/healthz`, never a process listing |
| A subshell left of `\|\|` runs with `set -e` off | Each step gets its own `\|\| exit 1`, and the result is checked afterwards |
| Anything in `install.sh` that waits for input hangs `up` | Non-interactive `ssh-keygen` (`-P ""`), stdin closed |
| A leading-dot name is invisible to globs | Refuse leading-dot names and `refs` |
| `code-server` run from a code-server terminal hands its arguments to the running editor | Test with `env -u VSCODE_IPC_HOOK_CLI` |
| The devcontainer CLI gives the container user the host user's uid (`updateRemoteUserUID`) | This is what lets the container read 0700 mounts. Note it when an image disables it |
| Secrets in command lines show up in `ps` | Values travel only in files (0600), never in argv or URLs |

---

## 9. Build order

### Phase 1 — Foundation
- `manifest` and the Scoop installer for amd64 and arm64, with sha256
  verification.
- `setup`: architecture, Docker, cgroup driver, port range, disk floor,
  pre-existing images.
- Host mode only. The docker wrapper and the combined cgroup with caps, both
  verified.
- `up`, `new`, `down`, `rm`, `list`, `shell`, `logs` and `status` on a
  **public** repo, plus `tunnel`.
- Tested on the Pi, then on one production VPS of each architecture.

**Assumptions to verify in Phase 1, not trusted until tested:**
- That `--docker-path` sees every `docker run`/`create` the devcontainer CLI
  makes, including for Dockerfile- and compose-based configs.
- Whether Ubuntu 24.04 and 26.04 `docker.io` use the `systemd` or `cgroupfs`
  cgroup driver. It decides how the parent cgroup is named and limited.
- That `--oom-score-adj` reaches the processes code-server and the lifecycle
  commands start.
- Whether disk-I/O weighting has any effect on each host's disks.
- That `chattr +i` works on each host's filesystem.
- The loopback-only route to the editor, given the devcontainer CLI cannot
  publish ports.

### Phase 2 — Identity
- Secrets scopes, token resolution, the credential helper.
- Dotfiles with `DOTFILES_TOKEN`, `ssh-auth` and signing.
- `sync`, to push changed secrets or config into existing codespaces.

### Phase 3 — Isolation and cleanup
- Isolated mode (dind, same-path mounts, `DOCKER_HOST`).
- `install-docker`, `gc`, `update`.
- `uninstall`, which is dry-run by default and lists exactly what it would
  remove, then needs `--yes`.

---

## 10. Working agreements

- Run `shellcheck -x codespace lib/*` before every commit. It must come out
  clean.
- **Test against real hosts**, as the siblings do. This container cannot run
  the system. Say what was verified where, and never claim a cap works
  without measuring it (cgroup files, `docker inspect`, a load test).
- **On a production host, a test must not disturb production either.** Load
  tests run inside the caps, and nothing touches the host Docker's global
  state. Never fill a disk to test the floor.
- Throwaway codespaces and VPSes cost money. Remove the ones you created only
  after the user agrees.
- Comments explain *why*, matching the siblings' tone.
- Never print secret values, not even while debugging. Test for presence
  instead (`test -n "$GH_TOKEN" && echo present`).
- If something in §3 or §5 looks wrong given new evidence, say so and explain
  the trade-off. Don't silently substitute an alternative.
