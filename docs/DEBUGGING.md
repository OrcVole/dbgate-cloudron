# Debugging and gate evidence

## Shipping digest and the gate-ladder digest-consistency finding

**Shipping digest: `ghcr.io/orcvole/dbgate-cloudron@sha256:9ce6667f1361e190cb66bb2e3ccd9326cc3d7c67a55d6950eb370d1ed330e59c`
(`7.2.3-2`).** Gates 0-2 below were first proven against `7.2.3-1`; gate 3 built `7.2.3-2`
(the `.key` mode fix) to prove the update path, and gate 4 then ran against `7.2.3-2`
without gates 0-2 having been re-run against it first, a real gap against the ladder's own
rule ("a rebuild restarts the ladder at Gate 0"), caught at the pre-publish audit rather
than earlier. Closed as follows, at the audit (2026-08-02, reasoning tier):

- The exact diff between the two digests was verified (not assumed): a 12-line additive
  block in `start.sh` re-asserting `.key`'s mode, touching no auth, routing, health, or
  Dockerfile logic. `git diff 6895bb0..4584e44 -- start.sh Dockerfile`.
- Both throwaway installs were updated to `7.2.3-2` and the swap verified by hash
  (`sha256sum /app/code/start.sh` before and after), matching the digest #7.2.3-2 image
  exactly on both. Health re-confirmed 200 on both post-update.
- Gate 2's functional-flow claims carry over: the RPC/data path is identical regardless of
  auth branch, and was independently re-exercised against this exact digest during gate 3's
  update leg (the byte-exact data check ran against `7.2.3-2`).
- Gate 0's rendering screenshot was not retaken: the captured page is Cloudron's own IdP
  login (SSO) or DbGate's static login form (no-SSO), neither of which the diff touches.
- **Gate 1's live human SSO sign-in remains proven only against `7.2.3-1`.** Put to the
  operator explicitly at the audit rather than assumed either way: re-test live, or accept
  the verified-diff argument. **Operator decision: accept the diff argument.** Recorded here
  as an explicit, reasoned exception, not a silent gap. Residual risk: effectively zero. The
  added block runs unconditionally, before the SSO/no-SSO branch is even reached, and it
  only `chown`/`chmod`s the `.key` file; it reads no auth state and writes nothing the OAuth
  flow consults, so it cannot influence sign-in behaviour by construction, not merely by
  observation.

This gap and its closure are logged in `../HARVEST.md` as a process-doctrine addition: track
the currently-proven shipping digest explicitly through the round, not only per-gate.



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

Run 2026-08-02 against `dbgate-nosso-testing`, carrying real data from gate 2 as the canary
(3-row table, an NDJSON archive export, and a connection with a real encrypted password
deliberately saved to trigger `.key` creation, see below).

**Pre-op discovery**: gate 2's flow used a password-less SQLite connection and never
triggered DbGate's own `.key` generation, so gate 3 first saved a connection WITH a password
to exercise it. This surfaced a real defect: DbGate creates `.key` at mode `0644`; `start.sh`
had no explicit re-assertion for it. Fixed before shipping (see the packaging notes and
`docs/decisions/0003-key-file-posture.md`); the fixed image (`7.2.3-2`) is also what proves
the update leg below, since a version bump was needed anyway for a real digest change.

### Update leg: `7.2.3-1` to `7.2.3-2`, via `cloudron update --app ... --image ...`

| Invariant | Baseline (`7.2.3-1`) | Post-update (`7.2.3-2`) | Result |
|---|---|---|---|
| Swap actually happened | `start.sh` sha256 `ea38a1e4...` | `start.sh` sha256 `e6abf8a3...` (verified by hash, not the CLI's own message, per gotcha #54/#83) | PASS |
| `dockerImage` in app record | — | `...@sha256:9ce6667f...`, exact match to the pushed digest | PASS |
| `admin-credentials` sha256 | `4e5f4b03...` | `4e5f4b03...` | PASS, byte-identical |
| `admin-credentials` mode | `600 cloudron:cloudron` | `600 cloudron:cloudron` | PASS |
| `.key` sha256 | `1a099a91...` | `1a099a91...` | PASS, byte-identical |
| `.key` mode | `644` (upstream default, pre-fix) | `600 cloudron:cloudron` (the fix, now live) | PASS, the fix works |
| Archive export sha256 | `d48a3b95...` | `d48a3b95...` | PASS, byte-identical |
| Boot path | — | `existing local admin credential found` (not regeneration) | PASS |
| Data, byte-exact | 3 rows (sprocket/12, cog/7, gear/3) | same 3 rows, same values, queried live through the API | PASS |
| Health | — | 200 externally | PASS |
| Platform task | — | `Downloading image` line present; auto-took a pre-update backup | PASS, clean |

### Restore leg: fresh backup, in-place restore

| Invariant | Proof | Result |
|---|---|---|
| Backup task clean | no syncer errors, completed in 12.7s | PASS |
| Restore task | completed (CLI foreground connection dropped under box-side flakiness, gotcha #105; verified box-side completion, not assumed) | PASS |
| `admin-credentials` sha256 | `4e5f4b03...`, unchanged from update-leg baseline | PASS, byte-identical |
| `admin-credentials` mode | `600 cloudron:cloudron` | PASS |
| `.key` sha256 | `1a099a91...`, unchanged | PASS, byte-identical |
| `.key` mode | `600 cloudron:cloudron`, **re-asserted correctly after a real restore**, not merely surviving an update | PASS, the exact scenario gate 3's own reference warns can drift |
| Archive export sha256 | `d48a3b95...`, unchanged | PASS, byte-identical |
| Boot path | `existing local admin credential found` | PASS |
| Health | 200 externally | PASS |

**Gate 3 verdict: PASS**, both legs. The `.key` mode fix (found by this gate) is proven not
just present but functioning correctly across both a real update and a real restore, which
is the actual invariant that matters: an every-boot re-assertion that only worked once would
have been a false confidence.

One CLI-connection flake during the restore leg (a plain `echo` through `cloudron exec`
timed out at 25s while the restore itself completed correctly server-side, confirmed via a
later successful connection): gotcha #105 territory, a box-side/CLI-connection transient,
not a package defect. Retried on a fresh connection rather than treated as a failure.

## Gate 4: memory

Run 2026-08-02 against `dbgate-nosso-testing`, digest `7.2.3-2`. DbGate's primary store is
**not memory-mapped** (a Node.js process with per-connection forked child driver
processes, plain read/write SQLite access, no LMDB/mmap engine), so the direct
`memory.peak` at 80 percent of `memoryLimit` check applies without the memory-mapped
special case. Measured via cgroup v2 counters read from inside the container
(`/sys/fs/cgroup/memory.*`), which the gate reference confirms is fully sufficient without
host access. `memory.max` confirmed 1,610,612,736 bytes, matching the manifest's 1.5 GiB
`memoryLimit` exactly.

Idle baseline (post-restart, clean `memory.peak`): `memory.current` 56,623,104 B (~54 MiB),
`memory.peak` 67,407,872 B (~64 MiB), `oom_kill` 0.

Load: 5 concurrent SQLite connections (DbGate forks a child driver process per connection,
so this exercises 5 concurrent worker processes plus the main API process), each running a
sustained insert-then-count loop for 90 seconds against its own database file.

| Invariant | Idle | Loaded |
|---|---|---|
| `memory.current` | 56,623,104 B (~54 MiB) | 66,920,448 B (~64 MiB, settled post-drain) |
| `memory.peak` | 67,407,872 B (~64 MiB) | 352,124,928 B (~336 MiB) |
| `oom_kill` | 0 | 0 |
| `memory.swap.current` | — | 0 |
| per-process RSS | node 100,464 KB (sampled ~1s after restart, still warming) | main API 109,772 KB; 2 active child driver processes ~99,000 KB each (of 5 spawned; DbGate recycles idle connection children) |
| app health | 200 | 200, response time 1.2s during load |
| load verifiably landed | — | worker 1: 519 rows; worker 2: 522 rows (~5.7-5.8 ops/sec sustained per worker over 90s, confirmed live via the API, not inferred from the load script's own exit code) |

`memoryLimit` = 1,610,612,736 B (1.5 GiB). 80 percent threshold = 1,288,490,188 B (~1.2 GiB).
Loaded peak (352,124,928 B) is **21.9 percent of the cap**, comfortably clear.

**Worst-case bound**: DbGate has no bundled service to add to the arithmetic (no addon
beyond `localstorage`+`oidc`, no bundled database). The worst case is more concurrent
connections than this test drove; per-connection overhead observed at ~99 MiB gives headroom
for roughly 11 further concurrent connections before approaching the 80 percent line from
this load shape alone, which is generous for an admin tool not expected to serve dozens of
simultaneous heavy sessions.

**Verdict: PASS.** All three checks hold: `oom_kill` zero throughout, `memory.peak` at 22
percent of `memoryLimit` (well under the 80 percent line), and the worst-case bound clears
with hundreds of MiB of margin. `memoryLimit` stays at the current **1.5 GiB (1,610,612,736
bytes)**; no change indicated. DbGate's store is not memory-mapped, so `memory.peak` is the
correct pass/fail counter as read (no anon+swap special case applies).

**Operational note**: `cloudron exec` was unreliable throughout this gate (multiple
`AggregateError [ETIMEDOUT]`, gotcha #105), including on a plain `echo`, while the app
itself answered its public health endpoint in 1.2s throughout — confirming the flakiness
was in the CLI/box connection, not the package. Switched to direct SSH plus `docker exec`
on the box host for the remainder of the gate, which was reliable throughout; cgroup path
confirmed as `/sys/fs/cgroup/docker/<container-id>` (cgroupfs driver, matching platform
facts, not the systemd-driver path some references assume).

## Gate 5: stranger path

Run 2026-08-02 via the Cloudron dashboard's community-app flow (the local CLI 8.3.1 cannot
do `--versions-url` installs against box 9.2.0, a known CLI/box version mismatch; the
operator chose the dashboard route rather than upgrading a CLI shared with other projects).

**Attempt 1: FAILED on a manifest gap, package's fault, fixed.**
`Invalid manifest: website is missing in manifest`. The `website` field is not in the
manifest reference's own "Required fields" table, but the community install validator
enforces it. Fixed (see the pre-publish audit section above); this is exactly what gate 5
exists to catch, since no earlier gate exercises the community validator at all.

**Attempt 2: FAILED on a platform transient, not the package's fault.**
`Unable to detect ipv6. API server (ipv6.api.cloudron.io) unreachable`. Diagnosed from the
box's own per-app task log rather than the dashboard message: the install reached
`dns.js registerLocations` → `getIPv6`, which timed out after 30 seconds against Cloudron's
own IP-detection endpoint. Two things this proves in the package's favour: the manifest
**passed validation** this time (the `website` fix worked), and the task got far enough to
successfully download the package icon from its raw GitHub URL. It died before container
creation, so nothing package-related was ever reached. Both `ipv4.` and `ipv6.
api.cloudron.io` answered in ~0.5s when tested from the box immediately afterwards,
confirming a genuine transient. Known behaviour: DNS-touching operations hard-depend on
that endpoint even when the domain uses external DNS, and the documented remedy is to
retry. The failed install still holds its location registration, so it must be uninstalled
before retrying.

**Attempt 3: PASS.** (The failed attempt-2 install had to be uninstalled first: a failed
install still holds its location registration and a retry would otherwise hit
`409 primary location in use`.)

| Invariant | Proof | Result |
|---|---|---|
| Installs from the published feed | Dashboard community-app flow, raw `CloudronVersions.json` URL, completed | PASS |
| Runs the shipping digest | `docker inspect --format '{{.Config.Image}}'` → `...@sha256:9ce6667f...`, exact match | PASS |
| Healthy | `/health` 200 from inside the container; platform reports `health: healthy`, `runState: running` | PASS |
| **`versionsUrl` non-empty** | `https://raw.githubusercontent.com/OrcVole/dbgate-cloudron/main/CloudronVersions.json` recorded on the install | **PASS, the decisive check** |
| Auth topology holds on a stranger install | boot marker `sso=1`, entrypoint logged the OIDC mapping branch | PASS |
| Icon renders | task log shows the community icon downloaded from the raw URL during install | PASS |

The `versionsUrl` check is why this gate exists as its own rung. Contrast, measured on the
same box at the same moment: our own two dev installs (`dbgate-testing`,
`dbgate-nosso-testing`), both created with `cloudron install --image`, show
`versionsUrl: ""` while `enableAutomaticUpdate: true`. That combination is inert: they can
never receive a published release. Only the feed path sets the field, and only a real
stranger-path install proves it.

A note for the round's own cleanup: the two dev installs are therefore NOT representative
of what a user gets, and should not be mistaken for canaries. Both are uninstalled at the
end of the round; a kept canary would need to be installed via the feed.

## Operational notes for future debugging

- `GET /` returning 200 does not mean logged-in or healthy-authenticated; it is the SPA
  catch-all. Probe `/connections/list` (RPC) for the auth fence and `/health` for liveness.
- The app cleans `jsl/`, `run/` and `uploads/` under the workspace on every boot; do not
  read their absence after a restart as data loss.
- Boot markers are written under `/run/dbgate/` (mode file: sso or nosso, first-run flag);
  read those before grepping logs.
