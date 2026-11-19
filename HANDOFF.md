# HANDOFF

Where things stand. CLAUDE.md is the design authority; this file is state.

## Done

- **Design** (CLAUDE.md), agreed with the user 2026-11-08.
- **Scaffold** (2026-11-19).
- **Phase 1 code** (2026-11-19), host mode, **not yet run on a real host**:
  - `setup`: checks commands, architecture, Docker access, the cgroup driver
    (`systemd 2` required), the port range and the disk floor. It records
    pre-existing images, installs the manifest's tools (sha256-verified,
    renamed into place, code-server made immutable) and writes the
    `bin/devcontainer` shim.
  - `up` (repo or existing name, `--name`), `new`, `rebuild`, `down`, `rm`
    (`--repo` asks first), `list`, `shell` (`-- cmd` too), `logs`, `status`,
    `tunnel`.
  - The slice `portablecodespaces.slice`: `systemctl set-property --runtime`
    with CPUQuota, CPUWeight, MemoryMax, MemorySwapMax=0, TasksMax and
    IOWeight, applied by every `up` before any container starts, then read
    back.
  - `lib/docker-wrapper`: adds the caps, the label, our network, the
    loopback-only editor port and the read-only code-server mount to the one
    `docker run`. It refuses whatever would reach the host (CLAUDE.md §5).
  - After `devcontainer up`, `up` checks the container (label, cgroup parent,
    OOM score, not privileged, only `127.0.0.1:<port>` published, and the
    kernel's `/proc/<pid>/cgroup`). A container that fails is stopped.
  - The editor is code-server from `/opt/code-server`, started with `docker
    exec -d` as the remote user and probed on `/healthz`.

## Verified here (dev container: Ubuntu 26.04 x86_64, no Docker, no systemd)

- shellcheck clean. `tests/wrapper.sh`: 43 cases. A deliberately broken
  wrapper fails it.
- Tool install for real: the three downloads verified and unpacked, the
  reinstall is a no-op, a wrong sha256 is refused with no leftovers, and
  `bin/devcontainer --version` prints 0.90.0.
- `chattr +i` fails here (no `CAP_LINUX_IMMUTABLE`), and setup stops with a
  clear error.
- With a stub docker, through the real devcontainer CLI: a generated config
  and a repo's own config are accepted, and a compose config is refused.
- Config validation, port allocation, URL to name, `list`, `tunnel`, and the
  caps math.

## Next: run Phase 1 on the Pi, then one production VPS per architecture

On the Pi (Ubuntu 24.04 arm64):

```bash
git clone https://github.com/AnimMouse/Portable-Codespaces ~/portable-codespaces
cd ~/portable-codespaces
mkdir -p .portable-codespaces && cp config.example .portable-codespaces/config
# set PORT_BASE=9101 there
./codespace setup
./codespace up AnimMouse/Portable-Codespaces    # a public repo
./codespace status
./codespace tunnel                               # then open the URL on the PC
```

Things to watch, from CLAUDE.md §9 "still to verify":

1. `set-property --runtime` on a slice that doesn't exist yet. If it fails,
   `up` stops at "could not set the caps".
2. `docker info` reporting `systemd 2`.
3. `cat /proc/<code-server pid>/oom_score_adj` inside the container should
   be 500.
4. `cat /sys/fs/cgroup/portablecodespaces.slice/{cpu.max,memory.max,pids.max}`.
5. A CPU load test inside a codespace while something else on the host is
   busy: the other process should keep its share.

## Then

- Phase 2: secrets, PAT, credential helper, dotfiles, `ssh-auth`, `sync`.
- Phase 3: isolated mode, `install-docker`, `gc`, `update`, `uninstall`.
- `AUTOSTART=1`: needs the caps in place before Docker restarts anything at
  boot.
