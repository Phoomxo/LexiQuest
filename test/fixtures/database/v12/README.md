# FigCraft database schema v12

`schema.sql` is a schema-only capture from a fresh in-memory
`AppDatabase` opened at commit `4d8fbca664bafc420e28a8e303085f30d53a4e07`.
The capture reads `sqlite_master` after Drift's `beforeOpen`, orders tables
before their referencing tables and includes runtime indexes. SQLite
reported `user_version = 12` and 37 application tables. The fixture
contains zero user rows.

SHA-256: `fc1cacfd4e8958f0c7b40aee33dadc41b5669c06576a72250dd8f2fcd3d7ed5f`

`test/database/migration_v11_to_v12_test.dart` loads this fixture with
synthetic study rows and checks preservation and schema parity after v26
upgrade and reopen.
