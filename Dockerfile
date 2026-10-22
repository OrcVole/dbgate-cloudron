FROM docker.io/dbgate/dbgate:7.3.2@sha256:fc68e7c433963bff17af7372ce87f4b94873551a1c1b124220c8c04a22a80311 AS upstream

# cloudron/base 6 ships no Node (base 5 carried 24.19.0 at /usr/local/node-24.19.0). The package
# now brings Node itself, from the official image (24.22.1, the 2026-10-20 security release), at a
# versioned path of its own.
FROM docker.io/library/node:24.22.1-bookworm-slim@sha256:2dd9a4f758e173b65fee15388f7706af6fb01ef50cf7a2c0538711d67a6981ae AS node

FROM docker.io/cloudron/base:6.0.1@sha256:7b1e729960c3ca312d26e886917ba89483241bba0219ff292858e10d9d5768ee

ARG DBGATE_VERSION=7.3.2
ENV DBGATE_VERSION=${DBGATE_VERSION}

# The upstream tree is preserved at its own expected path deliberately: DbGate's own
# platformInfo detects Docker mode by checking for /home/dbgate-docker/public, and its
# packaged-plugins resolver hardcodes /home/dbgate-docker/plugins in that mode. Relocating
# the tree would defeat both. See docs/decisions/0002-build-shape.md.
COPY --from=upstream /home/dbgate-docker /home/dbgate-docker

# Node at the path start.sh has always used. Owned by this package now, not by the base, so a
# future base bump cannot move it (field guide #291). The gate execs the exact runtime path.
COPY --from=node /usr/local/bin/node /usr/local/node-24.22.1/bin/node
RUN set -e; \
    ldd /usr/local/node-24.22.1/bin/node; \
    if ldd /usr/local/node-24.22.1/bin/node 2>&1 | grep -q 'not found'; then echo "FATAL: node links a missing library"; exit 1; fi; \
    test "$(/usr/local/node-24.22.1/bin/node --version)" = "v24.22.1"; \
    echo "BUILD GATE OK: node v24.22.1 at the runtime path"

COPY start.sh /app/code/start.sh
RUN chmod 0755 /app/code/start.sh

# Build-time gate: prove the copied tree actually boots on this base, not merely that it
# links. Native modules from the upstream image's Node build must load under the package's
# Node 24.22.1, at the path start.sh uses.
#
# gotcha #36 in reverse: the SHELL instruction is SILENTLY IGNORED under OCI image format
# ("SHELL is not supported for OCI image format... Must use docker format", observed on
# every step of a first build attempt here), so RUN executes under /bin/sh (dash), not bash.
# A first version of this gate used [[ ]], which dash does not have; the failure
# ("[[: not found") occurred INSIDE an if-condition, where a failing test is read as false
# rather than propagated by set -e, so the gate printed OK unconditionally, regardless of
# whether the app ever answered. Caught by reading the actual build log rather than trusting
# the final line (Endurain rule: a check that reports success without having done its work).
# Fixed by writing the whole gate in POSIX sh, no bash-only syntax, so it cannot silently
# degrade to a no-op under either shell.
RUN set -e; \
    cd /home/dbgate-docker; \
    export WORKSPACE_DIR=/tmp/dbgate-buildcheck HOME=/tmp/dbgate-buildcheck PORT=3000 PATH=/usr/local/node-24.22.1/bin:$PATH; \
    mkdir -p "$WORKSPACE_DIR"; \
    node bundle.js --listen-api & \
    pid=$!; \
    ok=0; \
    i=0; \
    while [ "$i" -lt 30 ]; do \
      i=$((i + 1)); \
      if curl -fsS http://127.0.0.1:3000/health >/dev/null 2>&1; then ok=1; break; fi; \
      sleep 1; \
    done; \
    kill "$pid" 2>/dev/null || true; \
    wait "$pid" 2>/dev/null || true; \
    rm -rf /tmp/dbgate-buildcheck; \
    if [ "$ok" != "1" ]; then echo "BUILD GATE FAILED: /health never returned 200"; exit 1; fi; \
    echo "BUILD GATE OK: /health answered within ${i}s"

EXPOSE 3000
CMD ["/app/code/start.sh"]
