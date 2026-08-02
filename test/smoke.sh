#!/bin/bash
# The runtime smoke test: builds nothing, assumes the image is already built (see
# Dockerfile's own build-time gate for the linkage/boot check). Runs the image the way
# Cloudron does -- root entrypoint, gosu drop to cloudron -- and asserts real behaviour,
# for BOTH auth branches (SSO and no-SSO), since the entrypoint takes a different path
# in each and the definition of done is both green, not just the default one.
#
# Usage: test/smoke.sh [IMAGE]
set -uo pipefail
cd "$(dirname "$0")/.."

IMAGE="${1:-ghcr.io/orcvole/dbgate-cloudron:7.2.3-1}"
CRI="$(command -v podman || command -v docker)"

fail=0
assert() {  # $1 = description, $2 = shell truth (0 pass)
  if [[ "$2" -eq 0 ]]; then
    echo "  PASS: $1"
  else
    echo "  FAIL: $1"
    fail=1
  fi
}

run_scenario() {
  local scenario="$1"; shift
  local name="dbgate-smoke-${scenario}-$$"
  local data_vol port
  data_vol="$(mktemp -d)"
  port=$(( 31300 + RANDOM % 1000 ))

  cleanup() {
    "$CRI" rm -f "$name" >/dev/null 2>&1 || true
    "$CRI" unshare rm -rf "$data_vol" 2>/dev/null || rm -rf "$data_vol" 2>/dev/null || true
  }
  trap cleanup RETURN

  echo "=== scenario: ${scenario} ==="
  echo "=== starting ${name} from ${IMAGE} ==="
  # Deliberately NO --userns=keep-id: Cloudron starts the container as root and the
  # entrypoint itself drops to cloudron via gosu. keep-id forces the process straight into
  # the mapped uid from the start, which skips the root-only mkdir/chown step entirely --
  # caught here as a real harness defect (Permission denied on /run/dbgate), not the
  # package's, on the first real run of this test.
  "$CRI" run -d --name "$name" \
    -p "127.0.0.1:${port}:3000" \
    -v "${data_vol}:/app/data:Z" \
    --tmpfs /run --tmpfs /run/secrets --tmpfs /tmp \
    -e CLOUDRON_HTTP_PORT=3000 \
    "$@" \
    "$IMAGE" >/dev/null

  echo "=== waiting for readiness (retry-all-errors: rootless port forwarder resets before the app listens, gotcha #117) ==="
  if ! curl -fsS --retry 30 --retry-all-errors --retry-delay 1 "http://127.0.0.1:${port}/health" >/dev/null; then
    echo "  FAIL: app never became ready"
    "$CRI" logs "$name" | tail -60
    fail=1
    return
  fi

  echo "=== assertions (${scenario}) ==="

  # the real server process runs as cloudron. NOT `exec whoami`: podman exec enters as the
  # image's default user (root), a NEW process unrelated to the actual running app
  # (gotcha #157). Inspect the real process tree instead.
  local node_user
  node_user="$("$CRI" exec "$name" ps -eo user,comm 2>/dev/null | awk '$2=="node"{print $1; exit}')"
  assert "[${scenario}] the node server process runs as cloudron (got: ${node_user})" $([[ "$node_user" == "cloudron" ]]; echo $?)

  local pid1_comm
  pid1_comm="$("$CRI" exec "$name" ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]')"
  assert "[${scenario}] tini is PID 1 (got: ${pid1_comm})" $([[ "$pid1_comm" == "tini" ]]; echo $?)

  local health_code
  health_code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/health")"
  assert "[${scenario}] /health returns 200 unauthenticated (got: ${health_code})" $([[ "$health_code" == "200" ]]; echo $?)

  # GET / is always 200 and proves nothing about auth -- documented, not a defect; assert
  # the fact so a future edit expecting it to gate auth fails loudly instead of silently.
  local root_code
  root_code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/")"
  assert "[${scenario}] GET / is 200 regardless of auth state, by design (got: ${root_code})" $([[ "$root_code" == "200" ]]; echo $?)

  local rpc_code
  rpc_code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${port}/connections/list" -H 'Content-Type: application/json' -d '{}')"
  assert "[${scenario}] unauthenticated RPC call is fenced, not 200 (got: ${rpc_code})" $([[ "$rpc_code" != "200" ]]; echo $?)

  local log_leak
  log_leak="$("$CRI" logs "$name" 2>&1 | grep -c "password=" || true)"
  assert "[${scenario}] no credential value present in logs (matches: ${log_leak})" $([[ "$log_leak" == "0" ]]; echo $?)

  local boot_mode
  boot_mode="$("$CRI" exec "$name" cat /run/dbgate/boot-mode 2>/dev/null | tr '\n' ' ')"
  assert "[${scenario}] boot-mode marker present (got: ${boot_mode})" $([[ -n "$boot_mode" ]]; echo $?)

  if [[ "$scenario" == "nosso" ]]; then
    # seeded credential file exists, 0600, BEFORE it is usable (gotcha #114 ordering).
    # Stat it from INSIDE the container: the host-side bind mount is owned by a rootless
    # subuid the host user cannot read, so a host-side stat fails for permission reasons
    # unrelated to whether the package did the right thing.
    local cred_mode
    cred_mode="$("$CRI" exec "$name" stat -c '%a' /app/data/.secrets/admin-credentials 2>/dev/null)"
    assert "[${scenario}] seeded admin credential file is 0600 (got: ${cred_mode})" $([[ "$cred_mode" == "600" ]]; echo $?)
    assert "[${scenario}] boot-mode reports sso=0" $([[ "$boot_mode" == *"sso=0"* ]]; echo $?)
    assert "[${scenario}] boot-mode reports first_run=1 on a fresh credential" $([[ "$boot_mode" == *"first_run=1"* ]]; echo $?)
  else
    assert "[${scenario}] boot-mode reports sso=1" $([[ "$boot_mode" == *"sso=1"* ]]; echo $?)
    local sso_log
    sso_log="$("$CRI" logs "$name" 2>&1 | grep -c "auth: Cloudron single sign-on" || true)"
    assert "[${scenario}] entrypoint logs the SSO mapping branch (matches: ${sso_log})" $([[ "$sso_log" -ge 1 ]]; echo $?)
    local cred_absent
    "$CRI" exec "$name" test -f /app/data/.secrets/admin-credentials >/dev/null 2>&1; cred_absent=$?
    assert "[${scenario}] no local admin credential is seeded under SSO" $([[ "$cred_absent" -ne 0 ]]; echo $?)
  fi

  # timed stop during a pre-serve step exits promptly, not 137 (gotcha #89); the fixed
  # window here is the boot sequence itself since there is no long migration step
  local stop_start stop_code stop_elapsed
  stop_start=$(date +%s)
  "$CRI" stop -t 20 "$name" >/dev/null 2>&1
  stop_code=$("$CRI" inspect "$name" --format '{{.State.ExitCode}}' 2>/dev/null)
  stop_elapsed=$(( $(date +%s) - stop_start ))
  assert "[${scenario}] stop exits promptly and not SIGKILL/137 (code: ${stop_code}, ${stop_elapsed}s)" \
    $([[ "$stop_code" != "137" && "$stop_elapsed" -lt 15 ]]; echo $?)
}

run_scenario "nosso"

run_scenario "sso" \
  -e CLOUDRON_OIDC_AUTH_ENDPOINT="https://example.com/auth" \
  -e CLOUDRON_OIDC_TOKEN_ENDPOINT="https://example.com/token" \
  -e CLOUDRON_OIDC_CLIENT_ID="smoke-test-client" \
  -e CLOUDRON_OIDC_CLIENT_SECRET="smoke-test-secret"

echo "==================================================="
if [[ "$fail" -ne 0 ]]; then
  echo "smoke FAILED"
  exit 1
fi
echo "smoke OK, both auth branches"
