FROM docker.io/dbgate/dbgate:7.2.4@sha256:38f4af9ab85d4aa112acc2e24d3e12c07c38e1e9727022e4387567cd3ec718a1 AS upstream

FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c

ARG DBGATE_VERSION=7.2.4
ENV DBGATE_VERSION=${DBGATE_VERSION}

# The upstream tree is preserved at its own expected path deliberately: DbGate's own
# platformInfo detects Docker mode by checking for /home/dbgate-docker/public, and its
# packaged-plugins resolver hardcodes /home/dbgate-docker/plugins in that mode. Relocating
# the tree would defeat both. See docs/decisions/0002-build-shape.md.
COPY --from=upstream /home/dbgate-docker /home/dbgate-docker

COPY start.sh /app/code/start.sh
RUN chmod 0755 /app/code/start.sh

# Build-time gate: prove the copied tree actually boots on this base, not merely that it
# links. Native modules from the upstream image's Node 22 build must load under the base's
# own Node 22.14 LTS (already first on PATH on this base digest, verified empirically).
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
    export WORKSPACE_DIR=/tmp/dbgate-buildcheck HOME=/tmp/dbgate-buildcheck PORT=3000; \
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
