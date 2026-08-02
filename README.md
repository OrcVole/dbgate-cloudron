# DbGate for Cloudron

[DbGate](https://www.dbgate.io/) community edition (GPL-3.0) packaged as a Cloudron community
app: a web-based SQL and NoSQL client for the databases already running behind your Cloudron
apps. Upstream: [dbgate/dbgate](https://github.com/dbgate/dbgate).

## What you get

- Thirteen bundled engines: PostgreSQL, MySQL, MariaDB, SQL Server, Oracle, MongoDB, Redis,
  SQLite, CockroachDB, ClickHouse, Cassandra, DuckDB, Firebird.
- Schema browser, query editor, editable data grid, CSV/Excel/NDJSON import and export,
  NDJSON archives on the app's own storage.
- Cloudron single sign-on (OpenID Connect) out of the box; installs without SSO get a
  generated local `admin` login instead.
- Optional read-only MCP server (upstream 7.2.3 feature) so AI agents can browse and query:
  set `MCP_TOKEN` in `/app/data/env` and restart.

## Extending access control

Set `LOGIN_PERMISSIONS_<login>` in `/app/data/env` (restart to apply) to grant a specific
user a non-default permission set inside DbGate; `<login>` is whatever your identity
provider's `preferred_username` claim resolves to for that user (or `email` if your
provider does not supply `preferred_username`). Upstream also ships `OAUTH_ALLOWED_LOGINS`
and `OAUTH_ALLOWED_GROUPS` as a second, app-level access restriction independent of
Cloudron's own per-app user list; the package does not set either by default, since
Cloudron's own Access Control panel is the primary mechanism.

## The one honesty note

DbGate community edition is a SINGLE SHARED WORKSPACE. Every user permitted into the app
sees the same saved connections, including stored credentials. Per-user role-based access
control, the admin UI and multi-user storage are upstream commercial features and are not in
this package. Use the Cloudron dashboard's user access control to decide who can open the
app, and treat it as an administrator's tool.

## Architecture

One Node.js process (the upstream Docker bundle, run unmodified) serving the UI, an RPC API
and a server-sent-events stream on port 3000. Database connections, query sessions and
import/export jobs run in forked child processes. The upstream application tree is preserved
verbatim at its own expected path; this package adds only an entrypoint conforming to the
Cloudron contract.

- Auth topology: the app's own OAuth 2.0 support wired to Cloudron's `oidc` addon; no
  `proxyAuth` anywhere, so the MCP endpoint and the RPC API remain reachable by their own
  auth. Details in `docs/decisions/0001-auth-topology.md`.
- State: the DbGate workspace (saved connections, settings, the connection-password
  encryption key, archives, logs) lives under `/app/data/workspace` via `WORKSPACE_DIR`.
  Backups therefore carry everything, including the encryption key.
- Health: `healthCheckPath` is the app's own unauthenticated `/health`.
- Operator extension point: `/app/data/env` is sourced at boot for extra upstream variables
  (`LOGIN_PASSWORD_<name>`, `PERMISSIONS`, `MCP_TOKEN`, connection definitions and so on).
  The package refuses to start if it finds `SKIP_ALL_AUTH`, `SHELL_CONNECTION` or
  `SHELL_SCRIPTING` set: those disable or weaken authentication.

## Building and testing

`Dockerfile` copies the pinned upstream community image tree onto the pinned
`cloudron/base` and adds `start.sh`. `test/smoke.sh` runs the image the way Cloudron does
and asserts the auth fence, the seeded credential path, signal handling and health.
`test/secret-scan.sh` is the pre-publish anonymity gate. Gate evidence lives in
`docs/DEBUGGING.md`.

## Documents

- `docs/decisions/`: architecture decision records.
- `docs/PACKAGING-NOTES.md`: the verified-versus-assumed log.
- `docs/FOR-CLOUDRON.md` and `docs/FOR-UPSTREAM.md`: notes for the two teams this package
  sits between.

## Licence

The package ships DbGate community edition unmodified; `LICENSE` is upstream's GPL-3.0. The
packaging layer (Dockerfile, start.sh, tests, docs) is provided under the same licence.
DbGate is a project of its upstream authors; this package is community-maintained and not
affiliated with them.
