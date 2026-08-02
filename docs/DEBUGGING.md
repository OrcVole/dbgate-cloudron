# Debugging and gate evidence

Gate ladder evidence tables land here as each gate resolves: one row per invariant, a proof
cell containing the actual evidence (hash prefixes, counts, modes, log lines), an explicit
PASS or FAIL, and enough recipe to repeat the gate at the next version bump.

## Gate 0: install, health, first-run, test-what-you-ship

(pending)

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
