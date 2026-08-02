# ADR 0002: build shape, upstream tree preserved verbatim at its own path

Status: accepted (phase 2, 2026-08-02). Build gate evidence lands in `../DEBUGGING.md`.

## Context

The upstream community Docker image (`dbgate/dbgate`, debian variant, Node 22) ships a
prebuilt single-file bundle plus a plugins directory at `/home/dbgate-docker`. Two facts in
the source make that path load-bearing: `platformInfo` detects Docker mode by
`fs.existsSync('/home/dbgate-docker/public')`, and `packagedPluginsDir()` returns the
hardcoded `/home/dbgate-docker/plugins` in that mode
(`packages/api/src/utility/{platformInfo,directories}.js` at tag v7.2.3). Relocating the
tree to `/app/code` would defeat the docker-mode detection, misresolve the plugins path
through the `isBuiltWebMode` relative branch, and require either patches or a symlink farm,
all to satisfy a convention the platform does not actually mandate.

## Decision

Multi-stage Dockerfile: stage one is the digest-pinned upstream community image; the final
stage is the digest-pinned `cloudron/base`, copying `/home/dbgate-docker` to the SAME path,
which is read-only at runtime exactly as the Cloudron contract requires. `/app/code` carries
only the package's `start.sh`. The process runs under the base image's Node 22.14 LTS
(`/usr/local/node-22.14.0/bin`), matching the upstream bundle's Node 22 native-module ABI;
the base's default Node 24 is not used. The upstream entrypoint is not carried: its
`dockerhost` `/etc/hosts` convenience write is impossible on a read-only rootfs and
meaningless on this platform.

A build-time gate boots the bundle with a scratch `WORKSPACE_DIR` and requires `/health` to
answer 200 before the layer is accepted; `ldd` alone cannot prove the native modules load.

## Consequences

- Zero upstream patches; an upstream version bump is one build argument plus one digest.
- The unconventional read-only path is documented here and in `AGENTS.md` so no later round
  "tidies" it into `/app/code` and breaks plugin resolution.
- The alpine upstream variant (Node 18, musl) is explicitly rejected; it is a different
  runtime generation and would reintroduce the musl-on-glibc problem for no gain.
