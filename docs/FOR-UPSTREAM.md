# Notes for the DbGate team

Observations from packaging DbGate community edition 7.2.3 for a container platform
(Cloudron), offered gratefully and with source references. The package runs the Docker
bundle unmodified; none of these blocked packaging.

- **`WORKSPACE_DIR` works and is undocumented.** The env-variables documentation page does
  not list it, but `packages/api/src/utility/directories.js` honours it, and it is exactly
  what a platform that mandates a writable data directory needs. Documenting it (and
  `PORT`, `AUTH_PROVIDER`, `MCP_TOKEN`, `MCP_PUBLIC_URL`) would help every packager.
- **The workspace `.key` is wrapped with a hard-coded passphrase**
  (`packages/api/src/utility/crypting.js`, `defaultEncryptionKey`), so possession of the
  file is equivalent to possession of the stored connection passwords. An environment
  variable alternative to the `--encryption-key` CLI argument would let deployments supply
  their own wrapping secret without exposing it in the process list.
- **`/health` always answers 200 while the process lives.** A variant (or query parameter)
  that returns 5xx when the event loop is saturated or the process is degraded would make
  platform health monitoring meaningfully diagnostic; today only a connection failure
  signals trouble.
- **The docker entrypoint's `dockerhost` `/etc/hosts` write assumes a writable rootfs.**
  On read-only-rootfs platforms the entrypoint cannot run as shipped; the package replaces
  it. Guarding the write (or making it optional by env) would let the stock entrypoint work
  read-only.
- **Language table omission.** The env-variables page's language table lists ten languages;
  the product also ships Korean (`ko`, present in `translations/` and the site's own
  language switcher).

(If a contribution policy on AI-assisted patches exists, none was found in CONTRIBUTING or
the repository; these notes are findings, not patches, and are offered as such.)
