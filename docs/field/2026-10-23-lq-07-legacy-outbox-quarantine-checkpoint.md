# LQ-07 legacy outbox quarantine checkpoint

## Status and authority

- Date: 2026-10-23, Asia/Bangkok
- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- HEAD: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1` (unchanged; no commit)
- Authority: `SYNC-LEGACY-OUTBOX-QUARANTINE-LOCAL-1`, sole production writer and serialized Flutter/test/analyze/format slot. Device mutation remained excluded.
- ADLC: Intent, Ground, Plan, Execute, Review and Attest completed for this bounded repair.
- Status: local engineering complete; independent review accepted; RETURN writer and Flutter slot to LQ-00. This is not build, install, deployment or production approval.
- Source state: pre-existing dirty shared checkout. Unrelated user/agent changes were preserved; `git diff HEAD` is not a card-only delta.

## Root cause evidence

The physical Vivo launch failure was caused by forward-compatible data left after installing an older APK with `-r -d`, not by Firebase, network or corrupt JSON.

- A copied diagnostic database was read immutable/read-only. SHA-256: `382E7B3AF744C7534872042E29CA8FF1FD5F03A10492B5D60F12A58CFD720A19`; `PRAGMA quick_check = ok`.
- The copy reports `user_version=10` but still contains the legacy `learning_time_segments` table.
- Pending outbox counts were `achievementUnlock=5`, `attempt=20`, `learningTimeSegment=3`, `rewardTransaction=21`.
- All three `learningTimeSegment` rows used payload version 1, operation `upsert`, attempt count 0, and retained matching source rows 3/3. No owner IDs, entity IDs, payloads or participant data were logged in this checkpoint.
- Current `_reconstructMutation` has no `learningTimeSegment` case. Its default throws `InvalidSyncPayloadFailure`, matching the physical stack at `drift_sync_store.dart:822`.
- `claimPending` previously rethrew that failure for every entity except `rewardTransaction`. The enclosing transaction rolled the attempted claim back to pending, so each later trigger hit the same row before valid work could proceed.

## Bounded change

Actual write set:

1. `lib/features/sync/data/drift_sync_store.dart`
   - Removed only the `rewardTransaction`-only rethrow guard.
   - Existing `on InvalidSyncPayloadFailure` handling now keeps the selected outbox row, marks it `permanentFailure/invalidPayload`, clears its lease and continues to later valid groups in the same transaction.
   - `StateError`, database errors and all other exceptions still escape and roll the transaction back.
2. `test/features/sync/sync_engine_test.dart`
   - Added an end-to-end `SyncEngine.run` regression using a synthetic `learningTimeSegment` row before a valid category row.
   - Proves the legacy row remains present, is quarantined once, is reported for the active owner, never reaches the gateway, and does not retry on a second run; the valid row still pushes and acknowledges once; another owner's row remains pending and untouched.
   - Added the review-requested negative boundary test: a supported category outbox without its backing category still throws `StateError`, and rollback restores pending/attempt 0/no failure/no lease.
3. This checkpoint.

No schema, migration, generated source, dependency, gateway, engine, trigger, startup, UI, source legacy table, real device data or Cloud policy changed. No row was deleted and no broad exception catch was added.

## TDD and review evidence

RED was observed twice before the production change (once before and once after adding the owner-isolation fixture):

```powershell
flutter test --no-pub test/features/sync/sync_engine_test.dart --plain-name "unsupported legacy outbox is quarantined while valid work syncs once" --reporter expanded
```

Both runs exited 1 with the expected `SyncFailure(invalidPayload)` at `_reconstructMutation` line 822 through `claimPending` line 280. After the one-line production repair, the same command exited 0 with 1/1 passed.

Independent read-only reviewer `/root/legacy_quarantine_review` initially reported Critical 0 / Important 1 / Minor 0: the exact `InvalidSyncPayloadFailure` catch boundary needed negative coverage. The added missing-backing-row test closed that finding. Final re-review: Critical 0 / Important 0 / Minor 0, Ready.

## Final verification on current source

```powershell
flutter test --no-pub test/features/sync/drift_sync_store_test.dart test/features/sync/sync_engine_test.dart test/features/sync/reward_transaction_sync_test.dart --reporter expanded
```

Result: exit 0, **32/32 passed**.

```powershell
flutter test --no-pub test/features/sync test/features/identity test/features/account test/features/learning test/features/rewards test/runtime/app_bootstrap_test.dart test/runtime/account_startup_restore_test.dart test/screens/setting_screen_test.dart test/architecture --reporter expanded
```

Result: exit 0, **276/276 passed**. This covers sync, owner isolation and upgrade, account, learning/reward, startup restore, local status UI and architecture. Flutter commands were serialized.

```powershell
flutter analyze --no-pub lib/features/sync/data/drift_sync_store.dart test/features/sync/sync_engine_test.dart
dart format --output=none --set-exit-if-changed lib/features/sync/data/drift_sync_store.dart test/features/sync/sync_engine_test.dart
git diff --check -- lib/features/sync/data/drift_sync_store.dart test/features/sync/sync_engine_test.dart
```

- Scoped analyzer: exit 0, no issues.
- Final formatter: exit 0, 2 files / 0 changed.
- Scoped diff check: exit 0; Git emitted existing LF-to-CRLF warnings only. No line-ending normalization was performed.

## Verified source manifest (SHA-256)

| Path | SHA-256 |
| --- | --- |
| `lib/features/sync/data/drift_sync_store.dart` | `B750691134E7E4809A0E524FF89CF8933EC0577F1BBD696F95AAE7A52BACBD3F` |
| `test/features/sync/sync_engine_test.dart` | `40206D040E9EE548395965C9BD9FA017D9012C86E3B3F66E42452CA4A12FA81F` |

## RETURN and remaining evidence

- Runtime inventory after final Flutter/Dart commands: zero `dart`, `dartvm`, `dartaotruntime`, `flutter`, `flutter_tester` or `gen_snapshot` processes.
- RETURN: release the production-writer and serialized Flutter slot to LQ-00. Do not start another card from this checkpoint.
- Not run: APK build, installation, device launch, physical preserved-data replay, live Cloud/Firebase, full repository suite or deployment.
- Remaining device step requires separate authority: build the repaired APK, install with `-r -d` without clearing app data, launch/retrigger twice, verify no unhandled `invalidPayload`, valid work drains, and the three preserved legacy rows are reported as permanent failures rather than retried.
- Compatibility risk: quarantine is intentionally permanent in this older binary. A later binary that again supports `learningTimeSegment` will need an explicit, reviewed recovery/requeue path; this repair preserves the outbox/source data but does not invent one.
