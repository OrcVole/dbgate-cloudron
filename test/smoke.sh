#!/bin/bash
# The runtime smoke test: builds nothing, assumes the image is already built (see
# Dockerfile's own build-time gate for the linkage/boot check). Runs the image the way
# Cloudron does -- root entrypoint, gosu drop to cloudron -- and asserts real behaviour.
#
# Usage: test/smoke.sh [IMAGE]
set -uo pipefail
cd "$(dirname "$0")/.."

IMAGE="${1:-ghcr.io/orcvole/dbgate-cloudron:7.2.3-1}"
CRI="$(command -v podman || command -v docker)"
NAME="dbgate-smoke-$$"
DATA_VOL="$(mktemp -d)"
PORT=31300

fail=0
assert() {  # $1 = description, $2 = shell truth (0 pass)
  if [[ "$2" -eq 0 ]]; then
    echo "  PASS: $1"
  else
    echo "  FAIL: $1"
    fail=1
  fi
}

cleanup() {
  "$CRI" rm -f "$NAME" >/dev/null 2>&1 || true
  "$CRI" unshare rm -rf "$DATA_VOL" 2>/dev/null || rm -rf "$DATA_VOL" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== starting $NAME from $IMAGE ==="
# Deliberately NO --userns=keep-id: Cloudron starts the container as root and the
# entrypoint itself drops to cloudron via gosu. keep-id forces the process straight into
# the mapped uid from the start, which skipped the root-only mkdir/chown step entirely and
# was caught here as a real defect in the harness (Permission denied on /run/dbgate), not
# the package, on the first real run of this test. Plain rootless default userns matches
# what the platform actually does.
"$CRI" run -d --name "$NAME" \
  -p "127.0.0.1:${PORT}:3000" \
  -v "${DATA_VOL}:/app/data:Z" \
  --tmpfs /run --tmpfs /run/secrets --tmpfs /tmp \
  -e CLOUDRON_HTTP_PORT=3000 \
  "$IMAGE" >/dev/null

echo "=== waiting for readiness (retry-all-errors: rootless port forwarder resets before the app listens, gotcha #117) ==="
if ! curl -fsS --retry 30 --retry-all-errors --retry-delay 1 "http://127.0.0.1:${PORT}/health" >/dev/null; then
  echo "  FAIL: app never became ready"
  "$CRI" logs "$NAME" | tail -60
  exit 1
fi

echo "=== assertions ==="

# runs as cloudron. NOT `exec whoami`: podman exec enters as the image's default user
# (root here), a NEW process unrelated to the actual running app (gotcha #157). Inspect the
# real process tree instead.
node_user="$("$CRI" exec "$NAME" ps -eo user,comm 2>/dev/null | awk '$2=="node"{print $1; exit}')"
assert "the node server process runs as cloudron (got: ${node_user})" $([[ "$node_user" == "cloudron" ]]; echo $?)

# tini is PID 1
pid1_comm="$("$CRI" exec "$NAME" ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]')"
assert "tini is PID 1 (got: ${pid1_comm})" $([[ "$pid1_comm" == "tini" ]]; echo $?)

# /health 200 unauthenticated
health_code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/health")"
assert "/health returns 200 unauthenticated (got: ${health_code})" $([[ "$health_code" == "200" ]]; echo $?)

# GET / is always 200 and proves nothing about auth -- documented, not a defect; assert the
# fact so a future edit that expects it to gate auth fails loudly instead of silently.
root_code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/")"
assert "GET / is 200 regardless of auth state, by design (got: ${root_code})" $([[ "$root_code" == "200" ]]; echo $?)

# seeded credential file exists, 0600, BEFORE it is usable (gotcha #114 ordering). Stat it
# from INSIDE the container: the host-side bind mount is owned by a rootless subuid the
# host user cannot read, so a host-side stat fails for permission reasons unrelated to
# whether the package did the right thing.
cred_mode="$("$CRI" exec "$NAME" stat -c '%a' /app/data/.secrets/admin-credentials 2>/dev/null)"
assert "seeded admin credential file is 0600 (got: ${cred_mode})" $([[ "$cred_mode" == "600" ]]; echo $?)

# an authenticated RPC call is fenced without a session, and no secret value ever appears
# in the logs regardless of outcome
rpc_code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${PORT}/connections/list" -H 'Content-Type: application/json' -d '{}')"
assert "unauthenticated RPC call is fenced, not 200 (got: ${rpc_code})" $([[ "$rpc_code" != "200" ]]; echo $?)

log_leak="$("$CRI" logs "$NAME" 2>&1 | grep -c "password=" || true)"
assert "no credential value present in logs (matches: ${log_leak})" $([[ "$log_leak" == "0" ]]; echo $?)

# timed stop during a pre-serve step exits promptly, not 137 (gotcha #89); the fixed
# window here is the boot sequence itself since there is no long migration step in this app
stop_start=$(date +%s)
"$CRI" stop -t 20 "$NAME" >/dev/null 2>&1
stop_code=$("$CRI" inspect "$NAME" --format '{{.State.ExitCode}}' 2>/dev/null)
stop_elapsed=$(( $(date +%s) - stop_start ))
assert "stop exits promptly and not SIGKILL/137 (code: ${stop_code}, ${stop_elapsed}s)" \
  $([[ "$stop_code" != "137" && "$stop_elapsed" -lt 15 ]]; echo $?)

echo "==================================================="
if [[ "$fail" -ne 0 ]]; then
  echo "smoke FAILED"
  exit 1
fi
echo "smoke OK"
