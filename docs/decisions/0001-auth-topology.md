# ADR 0001: auth topology, app-native OAuth via the oidc addon, no proxyAuth

Status: accepted (phase 0 recon, operator-approved 2026-08-02). Live verification of the
redirect URI, claim mapping and access-list enforcement lands at the auth gate and is
recorded in `../DEBUGGING.md`.

## Context

DbGate community edition carries a complete authentication system of its own: anonymous,
login/password (single and per-user), HTTP basic, generic OAuth 2.0, and AD/LDAP, selected
by environment detection in `packages/api/src/auth/authProvider.js`. The same port serves
the SPA, an RPC API, a server-sent-events stream, and (optionally) an MCP endpoint intended
for non-browser clients. A `proxyAuth` wall in front of that surface would break every
non-browser client with a 302-to-login, double-authenticate humans, and discard the app's
own session model. The platform's decision rule for apps with native auth is the `oidc` (or
`ldap`) addon, not `proxyAuth`.

## Decision

1. Declare the `oidc` addon with `loginRedirectUri: "/"`. The redirect URI is the app root
   because the SPA constructs it as `location.origin + location.pathname`
   (`packages/web/src/clientAuth.ts`), which at the app root is `https://<fqdn>/`.
2. Map at every boot: `OAUTH_AUTH` and `OAUTH_TOKEN` from the addon's injected
   `CLOUDRON_OIDC_AUTH_ENDPOINT` and `CLOUDRON_OIDC_TOKEN_ENDPOINT`; client id and secret
   likewise; `OAUTH_SCOPE="openid profile email"`; `OAUTH_LOGIN_FIELD=preferred_username`
   (claim verified at the auth gate; documented fallback `email`).
3. `optionalSso: true`. Installs without SSO fall back to the app's `logins` provider with a
   generated `admin` credential, whose operator-readable copy is written, mode 0600, BEFORE
   the credential takes effect, and is never reseeded.
4. Nothing is walled at the proxy. `/health` is unauthenticated upstream by design; the RPC
   surface enforces the app's own session; MCP is off unless the operator sets `MCP_TOKEN`.
5. The boot refuses to start when `SKIP_ALL_AUTH`, `SHELL_CONNECTION` or `SHELL_SCRIPTING`
   is present in the environment: each disables or weakens the auth boundary this topology
   relies on.

## Question D, resolved from source (phase 4)

`LOGIN_PERMISSIONS_<login>` applies to OAuth-authenticated logins, not only the `logins`
provider: `getCurrentPermissions` lives on the shared `AuthProviderBase` class and looks up
`LOGIN_PERMISSIONS_${login}` regardless of which provider authenticated the request, and the
OAuth provider sets `login` to `payload[OAUTH_LOGIN_FIELD]` (`packages/api/src/auth/
authProvider.js`, `OAuthProvider.oauthToken`). An operator who wants to grant a specific
Cloudron user elevated permissions inside DbGate sets `LOGIN_PERMISSIONS_<their-username>` in
`/app/data/env`, keyed by whatever claim `OAUTH_LOGIN_FIELD` resolves to.

Bonus finding from the same read: upstream ships its own `OAUTH_ALLOWED_LOGINS` and
`OAUTH_ALLOWED_GROUPS`, a second access-control layer independent of Cloudron's own per-app
user list. Not wired by the package by default (Cloudron's own access control is the primary
mechanism and is what gate 1 verifies), but documented in the README as an available
operator extension for anyone wanting to restrict further inside the app itself.

## Consequences

- All permitted users share one workspace; the platform's per-app user access control is the
  admission mechanism, and the shared-workspace reality is stated in every user-facing
  document.
- Auth mode is decided at install time by the platform's sticky SSO choice; converting an
  install between SSO and no-SSO is a reinstall, which the platform imposes, not the
  package.
- The login page is skipped when only one auth method exists, so SSO installs land directly
  on the identity provider, which is the intended experience.
