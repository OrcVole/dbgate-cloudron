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

(pending; predictions on record: redirect URI `/`, claim `preferred_username`, non-permitted
user rejected at the identity provider, RPC fenced logged-out with 401 while `GET /` stays
200 by design, seeded credential path on a no-SSO install)

## Gate 2: functional flows

(pending; SQLite file under `/app/data` as the flow target, byte-level export verification)

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
