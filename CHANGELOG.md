[1.0.1]
* Update DbGate community edition 7.2.3 -> 7.2.4 (upstream release 2026-08-04)
* Upstream: built-in PostgreSQL backup and restore without external tools; improved Firebird metadata loading; fixes for MySQL/MariaDB system views and MongoDB filters
* No packaging changes: auth topology, workspace layout and secrets handling unchanged; base and built images digest-pinned

[1.0.0]
* Initial release
* DbGate community edition 7.2.3 (upstream release 2026-07-20)
* Cloudron single sign-on via OpenID Connect, with a generated local login when installed without SSO
* Thirteen bundled database engines: PostgreSQL, MySQL, MariaDB, SQL Server, Oracle, MongoDB, Redis, SQLite, CockroachDB, ClickHouse, Cassandra, DuckDB, Firebird
* Workspace, saved connections and encryption key persisted under /app/data and covered by Cloudron backups
* Optional read-only MCP server for AI agents (set MCP_TOKEN in /app/data/env)
