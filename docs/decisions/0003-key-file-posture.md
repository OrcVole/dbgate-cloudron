# ADR 0003: accept upstream's default `.key` wrapping; no override

Status: accepted (phase 5, operator-approved 2026-08-02).

## Context

DbGate protects stored connection passwords with a real random 32-byte key. That key is
itself persisted at `<workspace>/.key`, wrapped with `simple-encryptor` using a **hard-coded
passphrase baked into the open-source client** (`packages/api/src/utility/crypting.js`,
`defaultEncryptionKey`). The wrapping is not real protection: anyone holding the file and the
public source can unwrap it trivially. The only actual boundary is filesystem permission,
0600 inside a 0700 directory, the same trust model as every other secret this package
handles.

Upstream offers exactly one override, `--encryption-key`, read only from
`process.argv` (`processArgs.js`, `getNamedArg('--encryption-key')`) with no environment
variable equivalent. Supplying it would put the passphrase on the container's command line,
readable from `/proc/<pid>/cmdline` by anything that can list processes, which gotcha #16
already rules out as strictly worse than the status quo it would try to fix.

## Decision

Accept the upstream default. The package does not set `--encryption-key` and does not
attempt to re-wrap or relocate `.key` beyond the standard treatment every secret gets:
0600 inside 0700, ownership and mode re-asserted every boot, and byte-identical (sha256)
across both update and restore as a standing gate invariant, on the same footing as the
seeded admin credential.

## Consequences

- `.key`'s real protection is exactly `/app/data`'s own access boundary: admin-readable,
  rides the platform backup, in the same trust domain as an `env://` secret (platform facts,
  confirmed from box source: `appEnvVars` is plaintext in the box database and serialised
  into every per-app backup). This is not a weaker posture than the rest of the package; it
  is the honest ceiling every secret under `/app/data` already has.
- Flagged upstream (`docs/FOR-UPSTREAM.md`): an environment variable equivalent to
  `--encryption-key` would let a platform supply its own wrapping secret without a
  command-line exposure trade-off. Offered as a finding, not assumed to be acted on.
- No package code changes as a result of this ADR; it exists to record that the trade-off
  was considered and rejected, not overlooked.
