# Notes for the Cloudron team

Verified observations from packaging DbGate, offered in case they are useful. Everything
here was measured or read from source during this round; nothing is speculation.

- **The `oidc` addon's injected `CLOUDRON_OIDC_AUTH_ENDPOINT` and
  `CLOUDRON_OIDC_TOKEN_ENDPOINT` are exactly what an env-configured generic OAuth2 client
  needs.** DbGate's `OAUTH_AUTH`/`OAUTH_TOKEN` mapped one-to-one with no discovery fetch at
  boot. Apps in this class (generic OAuth2 by env var, no OIDC discovery support) are a good
  fit for the addon and worth mentioning in the addon documentation.
- **A platform-level story for "look inside my addon database" keeps coming up.** Measured
  while preparing this package: 147 of 257 apps across the two stores wire postgresql,
  mysql, mongodb or redis addons, and the dashboard exposes credentials but no client. A
  pointer from the addon documentation to whatever database client apps exist in the stores
  would close a gap users have asked about on the forum since 2018 (topic 1397).
- **`optionalSso` interacts with env-detected auth providers.** DbGate selects its auth
  provider by environment detection at boot; because the platform's SSO choice is fixed at
  install time, the package must branch on the presence of `CLOUDRON_OIDC_*` every boot.
  Documented platform-side behaviour (the stickiness) is accurate; a line in the packaging
  docs noting that env-detecting apps pair well with `optionalSso` would help packagers.

## Added after the full gate ladder, all verified on a live box

- **The community install validator requires a non-empty `website` field, and the manifest
  documentation's own "Required fields" table does not list it.** That table names only
  `manifestVersion`, `version`, `healthCheckPath` and `httpPort`. A package can therefore
  build, pass every local check, and install perfectly via `cloudron install --image`, then
  fail for every stranger with `Invalid manifest: website is missing in manifest`. This is
  the third field we have hit with the same shape (after `packagerName` and `tags`), and the
  pattern is worth addressing generally: **anything the install-time validator enforces
  should be listed as required in the manifest documentation**, or, better, checked at build
  time so packagers find it before publishing rather than after.

- **`versionsUrl` is silently empty on `--image` installs, which makes `enableAutomaticUpdate`
  inert.** Measured on one box at one moment during this round: a dashboard community-app
  install carried a populated `versionsUrl`, while two `--image` installs of the identical
  package carried `""` with `enableAutomaticUpdate: true`. Nothing in the dashboard
  distinguishes these two states, so an operator sees "automatic updates: on" and reasonably
  believes the app will update. A visible indicator (or a warning when auto-update is enabled
  on an install with no feed URL) would prevent a class of silent staleness that an audit
  found affecting eleven of eighteen installs on this estate.

- **`cloudron exec` becomes unreliable under box load in a way that is hard to distinguish
  from an application fault.** During one gate it returned `AggregateError [ETIMEDOUT]`
  repeatedly, including on a trivial `echo`, while the application's own public health
  endpoint answered in 1.2 seconds throughout. `ssh` plus `docker exec` on the host worked
  reliably for the same checks at the same time. A clearer error, distinguishing "the CLI
  could not reach the box" from "the command failed", would save packagers real diagnosis
  time. Related: a `cloudron exec` whose output is truncated by such a timeout can still
  report exit code 0, so the result proves neither success nor failure.

- **The per-app task log is excellent and under-advertised.** `platformdata/logs/<appId>/
  apptask.log` turned an opaque dashboard error into a precise diagnosis in one read: it
  showed which stages had completed, that manifest validation had passed, that the icon had
  downloaded, and exactly where the failure occurred (a 30-second timeout in `dns.js
  registerLocations` → `getIPv6`). Surfacing a link to this log from the dashboard's error
  display would help packagers self-diagnose considerably.

- **`ipv6.api.cloudron.io` remains a live failure point for DNS-touching operations**, even
  when the domain uses external DNS. It failed one install with a 30-second timeout, before
  container creation; both `ipv4.` and `ipv6.` endpoints answered in about 0.5 seconds when
  tested from the same box minutes later. The failure also leaves the location registered, so
  a retry needs an uninstall first. A retry-with-backoff on that lookup, or treating an ipv6
  detection failure as non-fatal when ipv4 succeeded, would remove a recurring papercut.

- **This package needed no addon beyond `localstorage` and `oidc`**, and the `oidc` addon's
  injected `CLOUDRON_OIDC_AUTH_ENDPOINT` and `CLOUDRON_OIDC_TOKEN_ENDPOINT` mapped one-to-one
  onto a generic OAuth2 client with no discovery fetch. Worth noting in the addon
  documentation that apps with plain env-var OAuth2 support (no OIDC discovery) are a clean
  fit; it is not obvious from the addon's name.
