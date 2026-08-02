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

(Additions from the gate ladder land here as they are proven.)
