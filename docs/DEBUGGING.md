# Debugging and gate evidence

Gate ladder evidence tables land here as each gate resolves: one row per invariant, a proof
cell containing the actual evidence (hash prefixes, counts, modes, log lines), an explicit
PASS or FAIL, and enough recipe to repeat the gate at the next version bump.

## Gate 0: install, health, first-run, test-what-you-ship

Run 2026-08-02 against digest `sha256:9b9c1862c1f6c65d527b47a24434364724bd6b0dce83332a9e67953ceebb7a7e`,
two throwaway installs, provisioned concurrently (SSO and no-SSO, per the sticky-choice
scheduling rule): `dbgate-testing` and `dbgate-nosso-testing`.

| Invariant | SSO install | No-SSO install | Proof | Result |
|---|---|---|---|---|
| Install task succeeds | yes | yes | `cloudron install` task log, "App is installed" | PASS |
| `installationState` / `runState` | installed / running | installed / running | `cloudron inspect` | PASS |
| Shipping digest matches what was tested | yes | yes | `.manifest.dockerImage` == pinned digest, both installs | PASS |
| `/health` reachable, unauthenticated | 200 | 200 | external `curl`, not from inside the box | PASS |
| Boot-mode marker reflects install choice | `sso=1 first_run=n/a` | `sso=0 first_run=1` | `cloudron exec ... cat /run/dbgate/boot-mode` | PASS |
| Seeded credential correctly present/absent | n/a (correctly absent under SSO, verified at gate 1) | present, `0600 cloudron:cloudron` | `cloudron exec ... stat` | PASS |
| Rendering step: a human-equivalent view of the app | login page renders (Cloudron's own IdP page, since OAuth is the sole method) | DbGate's own login page renders correctly, logo and form visible | puppeteer screenshot, visually reviewed, not just captured | PASS |

One `cloudron exec` call died with `AggregateError [ETIMEDOUT]` mid-check (gotcha #105, a
CLI-connection transient); the retry succeeded immediately. Not a package defect.

Screenshot handling note: the SSO install's login page shows the BOX'S OWN branding (real
box, real identity), so it is kept in gitignored `phase-notes/screenshots/`, never in this
repo. The no-SSO install's page (`docs/screenshot-1.png`) is DbGate's own generic UI and is
the one used for the public mediaLinks asset and the announcement.

## Gate 1: auth, SSO end to end, fences

Run 2026-08-02 against the same digest as gate 0.

| Invariant | Proof | Result |
|---|---|---|
| Real sign-in, SSO | operator confirmed, browser: immediate redirect to Cloudron's login, landed inside DbGate logged in | PASS |
| Callback path | token exchange succeeded (`DBGM-00002` payload log), which only happens if `redirect_uri` matched Cloudron's registered `loginRedirectUri: "/"`; a mismatch fails the exchange itself. Matches ADR 0001's prediction, no divergence | PASS |
| Claim mapping | `OAUTH_LOGIN_FIELD=preferred_username` present and populated in the identity payload; `email` fallback not needed | PASS, resolves question B |
| Account/session row | none created, by design: the community edition has no persistent user store (`storage.js` is stubbed in the public image); auth is a stateless per-request JWT | PASS (architectural, not a gap) |
| Public paths stay open under SSO | `/health` 200 without a session | PASS |
| Protected paths fenced | `POST /connections/list` 401 without a session | PASS |
| No unintended `proxyAuth` | manifest addons are `localstorage` + `oidc` only | PASS |
| `optionalSso` both branches work | SSO: real login above. No-SSO: full scripted round trip on `dbgate-nosso-testing` — correct credential returns an `accessToken` that authorises `/connections/list` (200); an intentionally wrong password is rejected. Credential value never left the container or appeared in any log or terminal output | PASS |

Question C (platform per-app access-list enforcement at the IdP) is not directly testable
from a single permitted account; deferred, noted as unverified rather than assumed, low risk
since it is Cloudron's own platform behaviour, not package-specific.

Real evidence (the raw OAuth identity payload, which carries the operator's actual email and
username) is kept in gitignored `phase-notes/gate-1-evidence-raw.md`, never in this file.

## Gate 2: functional flows

Run 2026-08-02 against `dbgate-nosso-testing`, driven end to end through the real RPC API
with a real session token (no internals poked). Scope decision: engine breadth beyond SQLite
is upstream's own concern, not this package's; the flow proves the workspace/persistence
path and the RPC surface, which is what packaging can break.

| Invariant | Proof | Result |
|---|---|---|
| Create database | `POST /connections/new-sqlite-database` returns a connection id | PASS |
| DDL | `CREATE TABLE` via `/database-connections/run-script`, no error | PASS |
| Write | 3-row `INSERT` via the same endpoint | PASS |
| Read, exact values | `SELECT` via `/database-connections/query-data` returns exactly 3 rows, values byte-exact (sprocket/12, cog/7, gear/3) | PASS |
| Export (NDJSON archive) | `POST /archive/save-rows` writes to `/app/data/workspace/archive/default/*.jsonl` | PASS |
| Export file exists on disk | confirmed by an independent `stat`/read outside the API | PASS |
| Export byte-level integrity | sha256 identical across two independent reads of the file | PASS, `d48a3b9...` |
| Round trip | `GET /archive/get-archive-data` returns the same 3 rows read back through the API | PASS |
| Addons/services | none declared beyond `localstorage`+`oidc`; nothing to exercise | N/A by design |
| Routing | main domain already proven external (gates 0/1); no `httpPorts` declared | N/A |

Own probe defect found and fixed before trusting the result: an early row-count check
counted the literal substring `"name"` in the response, which also matches the column
metadata key (`"columnName":"name"`, since one of the columns is itself named `name`),
inflating 3 real rows to a false count of 5. Fixed by counting `"id":N` occurrences
instead, unique per row in this response shape. A probe bug, not an application defect.

## Gate 3: update and restore survival

(pending; `.key` sha256 byte-identical across both, connections intact, modes re-asserted)

## Gate 4: memory

(pending; idle versus multi-connection load, `memory.stat` anon+file+swap from inside the
container)

## Gate 5: stranger path

(pending; runs after publish)

## Operational notes for future debugging

- `GET /` returning 200 does not mean logged-in or healthy-authenticated; it is the SPA
  catch-all. Probe `/connections/list` (RPC) for the auth fence and `/health` for liveness.
- The app cleans `jsl/`, `run/` and `uploads/` under the workspace on every boot; do not
  read their absence after a restart as data loss.
- Boot markers are written under `/run/dbgate/` (mode file: sso or nosso, first-run flag);
  read those before grepping logs.
