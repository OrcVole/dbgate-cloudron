#!/bin/bash
set -euo pipefail

# Re-exec the whole script under tini as the first executable line. This fixes the PID 1
# signal-disposition window for the ENTIRE boot, including migrations/seeding below, not
# just the final exec. Guard variable keeps the re-exec to one level. -g signals the whole
# process group, which is what actually reaches a child process mid-step. Field guide §8,
# gotcha #89.
if [[ "${DBGATE_TINI_PID1:-}" != "1" ]]; then
  export DBGATE_TINI_PID1=1
  exec /usr/bin/tini -g -- "$0" "$@"
fi

CODE=/home/dbgate-docker
DATA=/app/data
RUN=/run/dbgate
WORKSPACE="${DATA}/workspace"
SECRETS_DIR="${DATA}/.secrets"
ADMIN_CRED="${SECRETS_DIR}/admin-credentials"
ENV_FILE="${DATA}/env"

echo "==> [start] DbGate ${DBGATE_VERSION:-unknown} booting"

# 1. Security floor. Refuse to boot with the auth wall disabled or weakened. These are
#    upstream escape hatches meant for local development, never for a shared instance.
for v in SKIP_ALL_AUTH SHELL_CONNECTION SHELL_SCRIPTING; do
  if [[ -n "${!v:-}" ]]; then
    echo "==> [start] FATAL: ${v} is set in the environment. This package refuses to run with it." >&2
    exit 1
  fi
done

# 2. Ownership and layout first. A restore can reset both, so fix before any app logic.
mkdir -p "${WORKSPACE}" "${SECRETS_DIR}" "${RUN}"
chown -R cloudron:cloudron "${DATA}"
chmod 0700 "${SECRETS_DIR}"

# 3. Map Cloudron addon variables to the app's own names, every boot (they can change).
SSO_MODE=0
if [[ -n "${CLOUDRON_OIDC_AUTH_ENDPOINT:-}" ]]; then
  SSO_MODE=1
  export OAUTH_AUTH="${CLOUDRON_OIDC_AUTH_ENDPOINT}"
  export OAUTH_TOKEN="${CLOUDRON_OIDC_TOKEN_ENDPOINT}"
  export OAUTH_CLIENT_ID="${CLOUDRON_OIDC_CLIENT_ID}"
  export OAUTH_CLIENT_SECRET="${CLOUDRON_OIDC_CLIENT_SECRET}"
  export OAUTH_SCOPE="openid profile email"
  export OAUTH_LOGIN_FIELD="${DBGATE_OAUTH_LOGIN_FIELD:-preferred_username}"
  echo "==> [start] auth: Cloudron single sign-on (oidc addon)"
else
  echo "==> [start] auth: no SSO addon present, falling back to a local login"
fi

# 4. No-SSO fallback: seed a generated admin credential, first-run only, idempotent.
#    The operator-readable copy is written BEFORE the credential is exported, so a failed
#    write leaves no live credential nobody can read (gotcha #114 ordering).
FIRST_RUN="n/a"
if [[ "${SSO_MODE}" == "0" ]]; then
  if [[ ! -f "${ADMIN_CRED}" ]]; then
    FIRST_RUN=1
    echo "==> [start] first run: generating the local admin credential"
    GEN_PASSWORD="$(openssl rand -hex 20)"
    ( umask 077
      {
        printf 'username=admin\n'
        printf 'password=%s\n' "${GEN_PASSWORD}"
      } > "${ADMIN_CRED}"
    )
    unset GEN_PASSWORD
  else
    FIRST_RUN=0
    echo "==> [start] existing local admin credential found"
  fi
  chown cloudron:cloudron "${ADMIN_CRED}"; chmod 0600 "${ADMIN_CRED}"   # re-assert every boot
  export LOGIN=admin
  export PASSWORD
  PASSWORD="$(sed -n 's/^password=//p' "${ADMIN_CRED}")"
fi

# 5. Operator extension point: extra upstream variables the package does not set itself
#    (LOGIN_PASSWORD_*, PERMISSIONS, MCP_TOKEN, CONNECTIONS, ...). Never overwritten by us.
if [[ -f "${ENV_FILE}" ]]; then
  echo "==> [start] loading operator extensions from ${ENV_FILE}"
  set -a
  # shellcheck source=/dev/null
  . "${ENV_FILE}"
  set +a
else
  : > "${ENV_FILE}"
  chown cloudron:cloudron "${ENV_FILE}"; chmod 0600 "${ENV_FILE}"
fi

# 6. Package-forced settings. Always applied, regardless of what the operator sets above.
export WORKSPACE_DIR="${WORKSPACE}"
export HOME="${DATA}"
export PORT="${CLOUDRON_HTTP_PORT:-3000}"

# Boot-mode marker for support and for the gate ladder, log-independent (rootless podman's
# journald log driver flushes lazily; field guide gotcha #77). first_run reflects whether
# the local admin credential was just created (no-SSO branch) or "n/a" under SSO, where this
# package seeds nothing of its own and DbGate manages its own workspace first-boot state.
{
  printf 'sso=%s\n' "${SSO_MODE}"
  printf 'first_run=%s\n' "${FIRST_RUN}"
} > "${RUN}/boot-mode"

echo "==> [start] http 0.0.0.0:${PORT}  workspace ${WORKSPACE_DIR}  sso ${SSO_MODE}"
cd "${CODE}"
exec gosu cloudron:cloudron node bundle.js --listen-api
