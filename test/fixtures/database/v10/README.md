# Frozen v10 fixture

`schema.sql` is the installed Drift CLI's SQLite export of `lib/data/local/app_database.dart` at `e432fa0574d209de9086c329775bf1b85716b558`, before any v11 schema change. Only line endings are normalized to LF. It contains 29 real v10 tables and no user rows. `runtime_indexes.sql` preserves the five exact indexes created by v10 `beforeOpen`, which the static exporter omits.

Generate from the pinned v10 source with `dart run drift_dev schema export lib/data/local/app_database.dart`; capture stdout separately from build-hook stderr. The accompanying source dump is preserved locally at `build/s6-schema-v10/drift_schema_v10.json`, SHA256 `2562dd37d29a31d4d821fdc5719201101daf058e47ab1bc2d79b1c7f21dc3c26`.

Tests execute both scripts on a new file, set `PRAGMA user_version = 10`, seed explicitly synthetic records, and close it before opening the current AppDatabase. They must not create a current-schema database and merely relabel it as v10. Historical lifetime Quest uniqueness and cascading objective FK are intentionally retained in this fixture.
