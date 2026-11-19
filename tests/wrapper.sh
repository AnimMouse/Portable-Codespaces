#!/usr/bin/env bash
# tests/wrapper.sh — what lib/docker-wrapper lets through, adds and refuses.
#
# Runs anywhere, with no Docker: a stub `docker` prints the arguments it
# receives. The refusals are what keep a repo's devcontainer.json from
# reaching a production host (CLAUDE.md §5), so every one has a case here.
#
#   tests/wrapper.sh        exits non-zero on the first failure

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
W="$HERE/../lib/docker-wrapper"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/data/workspaces/demo" "$T/editor"
cat > "$T/docker" <<'EOF'
#!/bin/sh
if [ "$1 $2" = "image inspect" ]; then echo "${STUB_ARCH:-amd64}"; exit 0; fi
printf 'DOCKER:'; for a in "$@"; do printf ' [%s]' "$a"; done; echo
EOF
chmod +x "$T/docker"

export CODESPACE_DOCKER="$T/docker" CODESPACE_NAME=demo CODESPACE_PORT=9001 \
  CODESPACE_EDITOR_PORT=13370 CODESPACE_CGROUP_PARENT=portablecodespaces.slice \
  CODESPACE_OOM_SCORE_ADJ=500 CODESPACE_PIDS_MAX=4096 CODESPACE_NETWORK=portable-codespaces \
  CODESPACE_RESTART=no CODESPACE_EDITOR_DIR="$T/editor" CODESPACE_DATA="$T/data" \
  CODESPACE_ARCH=amd64 CODESPACE_ALLOW_HOST_ACCESS=0

# The shape of the devcontainer CLI's main run (0.90.0).
BASE=(run --sig-proxy=false -a STDOUT -a STDERR
  --mount "type=bind,source=$T/data/workspaces/demo,target=/workspaces/demo,consistency=cached"
  -l portable-codespaces=demo -l 'devcontainer.metadata=[{"a":1,"b":2}]'
  --init --entrypoint /bin/sh)

pass=0
fail() { echo "FAIL: $*" >&2; exit 1; }

# allowed <description> <args...>: reaches docker, with every cap added.
allowed() {
  local d=$1 out; shift
  out=$("$W" "$@" 2>&1) || fail "$d: refused: $out"
  local want
  for want in "[--cgroup-parent] [portablecodespaces.slice]" "[--oom-score-adj] [500]" \
              "[--pids-limit] [4096]" "[--network] [portable-codespaces]" "[--restart] [no]" \
              "[--label] [portable-codespaces=demo]" "[--publish] [127.0.0.1:9001:13370]" \
              "target=/opt/code-server,readonly]"; do
    [[ "$out" == *"$want"* ]] || fail "$d: missing $want in: $out"
  done
  pass=$((pass + 1))
}

# refused <description> <args...>: never reaches docker.
refused() {
  local d=$1 out; shift
  if out=$("$W" "$@" 2>&1); then fail "$d: let through: $out"; fi
  [[ "$out" == *"refused"* ]] || fail "$d: failed without refusing: $out"
  [[ "$out" != *"DOCKER:"* ]] || fail "$d: docker was called: $out"
  pass=$((pass + 1))
}

# passed <description> <args...>: handed to docker unchanged.
passed() {
  local d=$1 out; shift
  out=$("$W" "$@" 2>&1) || fail "$d: $out"
  [[ "$out" == "DOCKER: $(printf '[%s] ' "$@" | sed 's/ $//')" ]] || fail "$d: changed: $out"
  pass=$((pass + 1))
}

allowed "main run" "${BASE[@]}" -e FOO=bar img:1 -c 'echo started; -p 1:1 --privileged'
allowed "SYS_PTRACE + seccomp=unconfined" "${BASE[@]}" --cap-add=SYS_PTRACE --security-opt seccomp=unconfined img
allowed "named volume" "${BASE[@]}" --mount type=volume,source=claude-x,target=/home/vscode/.claude img
allowed "-v named volume" "${BASE[@]}" -v cache:/cache img
allowed "bind inside data/" "${BASE[@]}" -v "$T/data/workspaces/demo:/w" img
allowed "container run" container "${BASE[@]}" img

refused "--privileged" "${BASE[@]}" --privileged img
refused "cap SYS_ADMIN (lowercase)" "${BASE[@]}" --cap-add sys_admin img
refused "cap CAP_SYS_ADMIN" "${BASE[@]}" --cap-add=CAP_SYS_ADMIN img
refused "cap ALL" "${BASE[@]}" --cap-add ALL img
refused "--device" "${BASE[@]}" --device /dev/kvm img
refused "--gpus" "${BASE[@]}" --gpus all img
refused "docker.sock via --mount" "${BASE[@]}" --mount source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind img
refused "/ via -v" "${BASE[@]}" -v /:/host img
refused "relative bind" "${BASE[@]}" -v ./x:/x img
refused "../ out of data/" "${BASE[@]}" -v "$T/data/../../x:/x" img
refused "--volumes-from" "${BASE[@]}" --volumes-from prod img
refused "--network host" "${BASE[@]}" --network=host img
refused "--net other" "${BASE[@]}" --net prod-net img
refused "--pid host" "${BASE[@]}" --pid host img
refused "--ipc host" "${BASE[@]}" --ipc=host img
refused "--userns host" "${BASE[@]}" --userns host img
refused "apparmor=unconfined" "${BASE[@]}" --security-opt apparmor=unconfined img
refused "-p (appPort)" "${BASE[@]}" -p 3000:3000 img
refused "clustered -itp" "${BASE[@]}" -itp3000:3000 img
refused "-P" "${BASE[@]}" -P img
refused "--publish=" "${BASE[@]}" --publish=127.0.0.1:1:1 img
refused "own --cgroup-parent" "${BASE[@]}" --cgroup-parent=/ img
refused "own --oom-score-adj" "${BASE[@]}" --oom-score-adj -1000 img
refused "own --restart" "${BASE[@]}" --restart always img
refused "another codespace's run" run -l portable-codespaces=other img
refused "a run without our label" run img
STUB_ARCH=arm64 refused "foreign architecture" "${BASE[@]}" img
refused "docker create" create img
refused "docker container create" container create img
refused "docker compose up" compose up

# Outside `codespace up`: no CODESPACE_* at all.
if out=$(env -u CODESPACE_NAME "$W" "${BASE[@]}" img 2>&1); then fail "run without env: let through"; fi
[[ "$out" == *"outside \`codespace up\`"* ]] || fail "run without env: $out"
pass=$((pass + 1))

# ALLOW_HOST_ACCESS=1 (the Pi) lets privileged through, never a published port.
CODESPACE_ALLOW_HOST_ACCESS=1 allowed "privileged with ALLOW_HOST_ACCESS" "${BASE[@]}" --privileged img
CODESPACE_ALLOW_HOST_ACCESS=1 refused "-p with ALLOW_HOST_ACCESS" "${BASE[@]}" -p 1:1 img

passed "ps" ps -a
passed "exec" exec -u vscode abc sh -c 'echo hi'
passed "compose version" compose version --short
passed "buildx build" buildx build -t x .

echo "ok: $pass cases"
