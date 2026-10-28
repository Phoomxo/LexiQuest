# Checkpoint 3 Finding 6 — atomic Adventure owner/configuration persistence

Fix only the stale-owner configuration-write race during Adventure launch.

## Requirement

Adventure launch must validate the currently active owner and persist the validated `SessionConfiguration` atomically against the production owner authority. A stale old-owner configuration must not be written if ownership changed while launch was awaiting persistence. Standard mode's existing `SessionConfigurationStore.save/read/clear` behavior remains compatible.

Use a narrow production interface (for example `ActiveOwnerSessionConfigurationStore`) implemented by `DriftSessionConfigurationStore`. Its active-owner validation and upsert must occur in one Drift transaction. It must require exactly one active local owner and require that owner's ID to match `configuration.ownerId`; otherwise fail closed before the upsert. Adventure dependency composition and launch must require/use this atomic authority. A plain `SessionConfigurationStore` must not make Adventure appear launchable.

## TDD

1. Extend `test/features/learning/session_configuration_store_test.dart` with real in-memory Drift coverage that proves atomic save succeeds for the sole active matching owner and rejects a stale/non-active owner without writing a row.
2. Observe RED before production interface/method exists, then implement and run full store tests GREEN.
3. Add/adjust dependency/navigation tests proving Adventure fails closed when only a plain store is present and uses the atomic operation when fully composed. Include owner drift during persistence if the fixture can deterministically gate the atomic operation; assert zero stale write/zero launch.
4. Observe RED for the behavior gap, implement the minimal composition/navigation changes, and run the focused main-navigation plus production feature navigation/dependency tests GREEN.

Inspect every `SessionConfigurationStore` implementation with `rg`; update only fixtures intentionally representing a fully composed Adventure production authority. Do not add test-only methods to production classes.

## Constraints

- Use `apply_patch` for edits.
- Do not edit or stage `lib/features/sync/domain/sync_entity.dart` or `lib/learning/storage/learning_database.g.dart`.
- Do not stage or commit.
- Do not run Codex Security.
- No unrelated refactor or Pair/research work.

Write `.superpowers/sdd/checkpoint-3-finding-6-report.md` with status, root cause, RED/GREEN commands and exact results, changed paths, and concerns. Return only a compact status summary.
