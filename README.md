# Portable-Codespaces

A GitHub Codespaces-like system for any Ubuntu VPS or Raspberry Pi. The whole
install is one folder in `~`: clone it, run `codespace setup`, and open
code-server editors in your browser through an SSH tunnel.

> **Status: scaffold.** The design is settled ([CLAUDE.md](CLAUDE.md)); the
> commands below are not implemented yet. See [HANDOFF.md](HANDOFF.md).

This is the third sibling of
[NixOS-Codespaces-VirtualBox](https://github.com/AnimMouse/NixOS-Codespaces-VirtualBox)
(a VM on a Windows PC) and
[Sprites-Codespaces](https://github.com/AnimMouse/Sprites-Codespaces)
(Fly.io Sprites).

| | NixOS-Codespaces-VirtualBox | Sprites-Codespaces | **Portable-Codespaces** |
|---|---|---|---|
| Runs on | a NixOS VM on your PC | Fly.io Sprites | **any Ubuntu host** (x86_64 or arm64) |
| A codespace is | a container on the VM | a sprite | **a container on the host** |
| Editor at | `https://localhost:800x` | `https://cs-<name>-<org>.sprites.app` | **`http://localhost:<port>`, via `ssh -L`** |
| Installed as | the whole OS | a CLI on your PC | **one folder in `~`** |

## Designed for shared servers

The main use is borrowing the idle CPU of servers that already run production
work, without disturbing it:

- All codespaces together are capped (by default 50% of the CPUs and 40% of
  the RAM), get a low CPU priority, and are the first thing the kernel kills
  when memory runs out.
- Nothing global on the host's Docker is touched; everything created is
  labelled, and only labelled things are ever removed.
- Editors listen on `127.0.0.1` only. Nothing starts at boot unless you ask.
- `codespace uninstall` removes everything it created.

## Setup (planned)

You need Docker (`codespace install-docker` can install it from apt, with a
warning) and sudo. Everything else is downloaded into the folder, pinned and
checksummed in [`manifest`](manifest).

```bash
git clone https://github.com/AnimMouse/Portable-Codespaces ~/portable-codespaces
cd ~/portable-codespaces
mkdir -p .portable-codespaces && cp config.example .portable-codespaces/config   # then edit
./codespace setup
./codespace up owner/repo
./codespace tunnel          # prints the ssh -L line to run on your PC
```

## License

[MPL-2.0](LICENSE), as the siblings.
