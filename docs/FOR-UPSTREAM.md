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

## Added after packaging was complete, all observed on a live installation

- **`.key` is created at mode 0644.** DbGate generates the connection-password encryption key
  lazily, at `<workspace>/.key`, the first time a connection with a password is saved
  (`packages/api/src/utility/crypting.js`). It lands world-readable. On a single-user desktop
  install that is unremarkable; on a shared or containerised deployment the file protecting
  every stored database password being readable by any process running as another user on the
  same host is worth tightening. `0600` at creation would cost nothing and would be the
  expected posture for a secret. Our package now re-asserts the mode on every boot, but the
  first window between creation and the next restart is not something a packager can close.

- **The `--encryption-key` override is CLI-argument only.** Because there is no environment
  variable equivalent, a deployment wanting to supply its own wrapping secret must put it on
  the process command line, where anything able to read `/proc` on the host can see it. An
  env-var alternative (or a `--encryption-key-file` reading from a path) would let platforms
  do this safely. As things stand the safest option is to accept the built-in default, which
  means the wrapping passphrase in the public source is what protects the key file.

- **`/health` always returns 200 while the process is alive.** It reports rich diagnostics
  (connection counts, memory, CPU) but never a non-2xx status, so a platform health check can
  only detect a hung or dead process by connection failure or timeout, not by status code. A
  query parameter or companion endpoint that returned 5xx when the process is degraded (event
  loop blocked, driver subprocesses unresponsive) would let platforms react correctly rather
  than waiting for a total failure.

- **`WORKSPACE_DIR`, `PORT`, `AUTH_PROVIDER`, `MCP_TOKEN` and `MCP_PUBLIC_URL` all work and
  are absent from the environment-variables documentation page.** `WORKSPACE_DIR` in
  particular is exactly what a container platform needs, and we found it only by reading
  `packages/api/src/utility/directories.js`. Documenting these would save future packagers a
  source dive.

- **The Docker entrypoint assumes a writable root filesystem.** It appends a `dockerhost`
  entry to `/etc/hosts` when that name does not resolve, which fails on a read-only rootfs
  (a common container-platform default). Our package substitutes its own entrypoint, so this
  was not a blocker, but guarding that write, or making it opt-in via an environment
  variable, would let the stock entrypoint work unmodified in more environments.

- **Small documentation inconsistency:** the environment-variables page's language table
  lists ten languages, while `translations/` and the site's own language switcher both
  include Korean (`ko`) as an eleventh.

- **Thank you for the plugin architecture and the prebuilt bundle.** Thirteen engines
  preinstalled, a single `bundle.js`, and no build step in the image made this one of the
  cleanest packaging jobs we have done. The whole package is a Dockerfile that copies your
  tree onto a base image plus an entrypoint; we carry no patches at all.

(If a contribution policy on AI-assisted patches exists, none was found in CONTRIBUTING or
the repository; these notes are findings, not patches, and are offered as such.)
