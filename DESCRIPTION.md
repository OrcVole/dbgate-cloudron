<upstream>7.2.3</upstream>

DbGate is a web-based SQL and NoSQL database client. This package brings the community
edition (GPL-3.0) to Cloudron, giving you a schema browser, query editor, data grid and
import/export tools for the databases already running behind your apps.

**Why on Cloudron.** Cloudron provisions PostgreSQL, MySQL, MongoDB and Redis for well over
half the apps in its stores, and hands you credentials but no way to look inside them. DbGate
is that window: point it at any addon database, browse the schema, run queries, edit rows,
and export to CSV, Excel or NDJSON.

**Engines.** PostgreSQL, MySQL, MariaDB, SQL Server, Oracle, MongoDB, Redis, SQLite,
CockroachDB, ClickHouse, Cassandra, DuckDB and Firebird, all bundled. SQLite files can live
directly on the app's own storage.

**Sign-in.** Cloudron single sign-on out of the box (OpenID Connect), or a generated local
login when installed without SSO. An MCP server (new upstream in 7.2.3) can optionally be
enabled with a token so AI agents can browse and query read-only.

**One workspace, shared.** The community edition has a single shared workspace: every user
you permit into the app sees the same connection list and stored credentials. Per-user
role-based access control is an upstream commercial feature and is not part of this package.
Treat the app as a tool for the Cloudron owner and trusted administrators, and use the
Cloudron dashboard's user access list to control who can open it.

Connection passwords saved in the workspace are encrypted at rest, and the workspace,
including the encryption key, rides Cloudron's backups.
