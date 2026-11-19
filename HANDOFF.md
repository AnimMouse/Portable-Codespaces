# HANDOFF

Where things stand. CLAUDE.md is the design authority; this file is state.

## Done

- **Design** (CLAUDE.md), agreed with the user 2026-11-08.
- **Scaffold** (2026-11-19):
  - `codespace`: usage, config loading and validation, architecture
    detection, manifest lookup, name validation, and command dispatch.
    Every command stops with "not implemented yet (Phase N)".
  - `lib/docker-wrapper`: passes everything through to the real docker, but
    **refuses `run`/`create`** until the caps exist, so it fails closed.
  - `manifest`: Node 26.13.1 (LTS), devcontainer CLI 0.90.0, code-server
    4.145.2, with publisher sha256s for amd64 and arm64.
  - `config.example`, `templates/devcontainer.json`, `.gitignore`, `LICENSE`
    (MPL-2.0, as the siblings).

## Next: Phase 1 (CLAUDE.md §9)

1. `setup`: download and verify the manifest's tools into `apps/`, make
   code-server immutable, and check Docker, the cgroup driver, the port range
   and the disk floor. Record pre-existing images.
2. The docker wrapper's caps, and the shared cgroup.
3. `up`/`new`/`down`/`rm`/`list`/`shell`/`logs`/`status`/`tunnel` in host mode.

## Untested

Everything that touches a real host. This codespace (Ubuntu 26.04 x86_64
container) has no Docker and no systemd. Only shellcheck and pure-bash
checks run here. The test bed is the Pi, then one production VPS of each
architecture.
