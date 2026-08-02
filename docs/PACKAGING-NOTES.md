# Packaging notes (verified-versus-assumed log, newest first)

Anonymised. Box-specific detail lives in the maintainer's local notes, not here.

---

## 2026-08-02: recon and scaffold

Recon read the upstream source at tag v7.2.3 directly (cloned, not summarised) plus the
docs site, release APIs and both Cloudron store APIs. The round's working records carry the
full source citations; the load-bearing results are below.

**Validated (decisions that held up):**

- **The community/premium boundary is structural, not a flag.** Premium lives in a separate
  private repository merged at upstream's CI; the public image's premium code paths are no-op
  stubs (`checkLicense.js` returns `type:'community'`, `storage.js` returns nulls). Shipping
  the open core requires only using `dbgate/dbgate` and not setting `STORAGE_*`,
  `DBGATE_LICENSE` or `ROLE_*`.
- **The OAuth redirect URI is the app root.** The SPA sends
  `location.origin + location.pathname` (`clientAuth.ts`), so the OIDC callback registers as
  `/`. Live confirmation is an auth-gate deliverable.
- **The upstream path is load-bearing.** Docker mode is detected by
  `fs.existsSync('/home/dbgate-docker/public')` and the plugins path is hardcoded in that
  mode, so the package preserves the tree verbatim rather than relocating it (ADR 0002).
- **`/health` and `/__health` are unauthenticated by design** (`SKIP_AUTH_PATHS` in the auth
  middleware), which makes the platform health check free. `GET /` serves the SPA with 200
  regardless of login state, so status-code probes of `/` prove nothing about auth; the auth
  gate probes an RPC route instead.
- **The next upstream release was checked, not assumed** (tree diff v7.2.3 to the 7.2.4
  beta): auth, workspace layout and Docker context untouched; the env additions are
  premium-only role provisioning. Nothing packaging-relevant changes.

**Surfaced (and handled):**

- **`WORKSPACE_DIR` is real but undocumented upstream** (source: `directories.js`); the
  package relies on it to move state under `/app/data`. Flagged to upstream in
  `FOR-UPSTREAM.md`.
- **The workspace `.key` is wrapped with a public hard-coded passphrase** unless a CLI flag
  overrides it (`crypting.js`), so the file itself is the secret. The package treats it as
  data-loss-critical: 0600 in a 0700 directory re-asserted every boot, byte-identical across
  update and restore as a standing gate invariant.
- **`SKIP_ALL_AUTH`, `SHELL_CONNECTION`, `SHELL_SCRIPTING` exist and disable or weaken
  auth**; the entrypoint refuses to start if any is set.

**Still open:**

- The identity claim for `OAUTH_LOGIN_FIELD` (`preferred_username` expected, `email` the
  fallback) and enforcement of the platform's per-app access list at the identity provider:
  both are auth-gate evidence, unverified until then.
- Whether `LOGIN_PERMISSIONS_<login>` applies to OAuth-authenticated logins: source read
  scheduled with the entrypoint work.

---

## Conventions for this file

- Newest first. Every claim carries its evidence; verified and assumed are distinguished
  explicitly. Gate evidence tables live in `DEBUGGING.md`; this file records what the work
  taught.
