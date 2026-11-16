# Frozen actual v11 schema

Captured from the real fresh `AppDatabase` while source was schema11, verified
against commit `34e628a711b730b049777a51b3440d4b61338f14` (f31). This is schema
only:34 tables,10 explicit runtime indexes, zero user rows. `schema.sql` includes
the runtime indexes and user_version11; it was not relabelled from a later schema.

SHA256: `5590fbafc72a6ece7ef07bd823b0b8fe5a48baf4482caece8e4f9e2d1fa3406d`.
Source input manifest: `docs/development/figcraft-v1/evidence/s7-achievements-inputs.tsv`.

Capture runner: `tool/figcraft/capture_v11_schema_test.dart`; execute it with the
recorded v11 source and its locked dependencies. It intentionally rejects any
other AppDatabase version. The runner opens only synthetic memory databases and
writes `build/schema_v11.sql`. Preserve this fixture when developing v12.

The capture passed1 Flutter test. Python SQLite replay with foreign keys ON
verified user_version11, all34 tables/10 explicit indexes, zero rows and zero FK
violations. The runner's second test compared columns, nullability/defaults/PKs,
FK actions and index semantics against an actual upgrade loaded from frozen v10
schema/runtime-index SQL; it passed1 test. It does not prove populated-data
retention or compare raw CHECK constraints/CREATE TABLE text. Migration tests
must seed meaningful rows and inspect those constraints separately.

Raw preparation evidence remains in `build/s7-v11-schema-capture.txt` and
`build/s7-v11-schema-parity.txt`. Independent memory executors emitted Drift's
generic multiple-instance warning; no executor or live database was shared.
