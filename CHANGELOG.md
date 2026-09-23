[1.1.0]

- Update DbGate community edition 7.2.6 to 7.3.0
- Cloudflare D1 support (new feature, Premium tier)
- Google sign-in with optional access restrictions and role synchronisation based on Google groups
- Optional anonymous usage analytics with a consent prompt and toggle in Settings
- Improved protection of database connection credentials
- No packaging changes: auth topology, workspace layout and secrets handling unchanged; base and built images digest-pinned

[1.0.3]

- Update DbGate community edition 7.2.5 -> 7.2.6
- Upstream: routine features and fixes
- No breaking or migration changes in this release
- No packaging changes: auth topology, workspace layout and secrets handling unchanged; base and built images digest-pinned

[1.0.2]

- DbGate 7.2.5, which is a security release despite not saying so: export file writes are restricted to managed directories and symlink-based path escapes are blocked, SSRF and local file reads are prevented in remote text and JSON Lines downloads, plugin package names and command dispatch are validated, and generated script comments and directives are sanitised against code injection
- Also fixed upstream: SQLite and LibSQL bigint values keep their precision, and an npm install failure from a dbgate-pg-dumper version mismatch

[1.0.1]

- Update DbGate community edition 7.2.3 -> 7.2.4 (upstream release 2026-08-04)
- Upstream: built-in PostgreSQL backup and restore without external tools; improved Firebird metadata loading; fixes for MySQL/MariaDB system views and MongoDB filters
- No packaging changes: auth topology, workspace layout and secrets handling unchanged; base and built images digest-pinned

[1.0.0]

- Initial release
- DbGate community edition 7.2.3 (upstream release 2026-07-20)
- Cloudron single sign-on via OpenID Connect, with a generated local login when installed without SSO
- Thirteen bundled database engines: PostgreSQL, MySQL, MariaDB, SQL Server, Oracle, MongoDB, Redis, SQLite, CockroachDB, ClickHouse, Cassandra, DuckDB, Firebird
- Workspace, saved connections and encryption key persisted under /app/data and covered by Cloudron backups
- Optional read-only MCP server for AI agents (set MCP_TOKEN in /app/data/env)
