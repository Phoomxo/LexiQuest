# Captured Cycle 12 v25 schema

The fixtures contain DDL and `PRAGMA user_version` only. The capture read each database before any synthetic rows were inserted. Each has 45 tables, nine explicit indexes, and no foreign-key violations.

| Fixture | Capture path | SHA-256 |
| --- | --- | --- |
| `schema.sql` | Fresh `AppDatabase` at `00d6c8ea8be9f54acaad15a4ed8ce818bec5461a` with its `beforeOpen` indexes | `bf56548a5fb52e1405ae6e90b944014237fa69a25699381ecc6d3e45f30c3066` |
| `schema_upgraded_from_v23.sql` | `0255f843` schema v23 opened by the actual `00d6c8ea` runtime | `b8bb658722a310b15b02b73beb5acadec183f065987d2acab92ee9ad4b700e59` |
| `schema_relabelled_v10.sql` | Fresh `00d6c8ea` v25 fixture opened by the actual `196d4e22b3e4365fba22d36198cb07762d95b981` runtime | `4750a62415e4a43a835e4208c73c1fb97af183a0fdc8ac81ed221347f7598bf3` |

The third capture read `sqlite_master` and `PRAGMA user_version` from the resulting file in SQLite read-only mode. The historical runtime wrote the observed version 10. The capture ordered table and index names within each object type and retained the original SQL. Tests load the captured SQL into a new file, then seed synthetic records that exercise the historical contract. [Native migration reproduction](../../../../docs/development/figcraft-v1/evidence/s7-v12-native-migration.txt)
