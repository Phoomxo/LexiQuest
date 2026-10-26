# LQ-07 S2 Local Sync Status checkpoint

- วันที่: 2026-10-23, Asia/Bangkok
- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- HEAD: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1` (unchanged; no commit)
- ADLC: Intent / Ground / Plan / Execute / Review / Attest completed for bounded S2; integration disposition belongs to LQ-00.
- Authority: source coordinator's exclusive S2 production-writer and serialized Flutter-slot transfer after A1 acceptance. Exact write set is the eight code/test paths below plus this checkpoint.
- Status: bounded local S2 engineering accepted by independent review; RETURN writer/Flutter slot to LQ-00. This is not release/deployment/research approval.
- Source state: pre-existing dirty shared checkout. A1, Gemini, source picker, theme and other user/agent changes were retained; `git diff HEAD` is not an S2-only delta.
- Fixtures: in-memory Drift and synthetic owners/status sources only. No live provider, credentials, participant data or production operation.

## Outcome and scope

Settings now shows a read-only, current-owner local sync summary:

| Local fact | UI meaning |
| --- | --- |
| `pending` | รอส่ง |
| `retryWaiting` | รอลองใหม่ |
| `inFlight` | กำลังประมวลผลหรือรอกู้คืน; not proof of online connectivity |
| `blockedAuth` | รอเชื่อมบัญชี |
| `permanentFailure` | ต้องตรวจสอบ |
| `sync_conflicts` count | ประวัติความขัดแย้งที่จัดการแล้ว; audit history, not pending work |

- `acknowledged`, `superseded` and `conflictResolved` are excluded from pending work counts.
- One watched SQL query anchors the active owner and outbox aggregates in the same database snapshot. Conflict history uses an independent scalar subquery, so outbox rows cannot multiply conflict counts.
- The snapshot retains `ownerId` internally for isolation checks, but Settings never renders it. Zero or multiple active owners produce unavailable, not a fabricated zero.
- A changed owner produces an unavailable fence before the replacement snapshot. A single watched query prevents a delayed per-owner aggregate stream from publishing owner A after owner B becomes active.
- Source replacement cancels the old subscription and generation-fences delayed events. Null, error and clean stream completion all fail closed to unavailable without raw payload, identifier, exception or failure-detail disclosure.
- Bootstrap publishes the local status source even when Firebase/Cloud gateway is unavailable. The watcher performs selects only; it does not create an owner, outbox operation, conflict or research row.

Actual S2 writes:

1. `lib/features/sync/application/sync_status.dart` (new): immutable aggregate snapshot and read-only source contract.
2. `lib/features/sync/data/drift_sync_store.dart`: one current-owner watched aggregate query and owner-change unavailable fence.
3. `lib/runtime/app_dependencies.dart`: optional local status dependency.
4. `lib/runtime/app_bootstrap.dart`: reuse one `DriftSyncStore` for status and optional Cloud engine; status remains available offline.
5. `lib/screens/setting_screen.dart`: privacy-safe loading/available/unavailable presentation, accessibility live region, subscription lifecycle and stale-event fencing.
6. `test/features/sync/drift_sync_store_test.dart`: classification, terminal exclusion, independent conflict count, absent/empty owner, live updates and atomic A/B isolation.
7. `test/runtime/app_bootstrap_test.dart`: status wiring without Firebase/Cloud gateway.
8. `test/screens/setting_screen_test.dart`: truthful labels/privacy, null/error/done handling, stale-source rejection, semantics and high-text-scale portrait/landscape coverage.
9. This checkpoint.

No schema/migration/generated source, dependency/lockfile, `main.dart`, account/identity/consent implementation, sync toggle, last-sync claim, deletion flow, queue mutation, v11 contract, remote policy, deployment or research path was changed by S2.

## Test and review evidence

### Baseline and RED/GREEN history

```powershell
flutter test --no-pub test/features/sync/drift_sync_store_test.dart test/runtime/app_bootstrap_test.dart test/screens/setting_screen_test.dart --reporter expanded
```

- Before S2 test additions: exit 0, **46 tests passed**.
- With S2 tests before production implementation: exit 1 as expected because `sync_status.dart`, `SyncStatusSnapshot`, `watchCurrentOwnerSyncStatus` and `AppDependencies.syncStatus` did not exist.
- Initial implementation exposed a widget-fixture timing issue: three status tests observed the frame before async broadcast delivery. `pumpAndSettle` corrected the test timing; production behavior was unchanged.
- Independent review then found a cross-stream owner-switch race and stale UI after clean stream completion. The source-close widget regression failed before the fix. The in-memory atomic owner-switch regression passed under its scheduler before the structural fix, so it is retained as coverage but not represented as a deterministic RED reproduction.
- One focused compile retry failed after `dart:async` was over-removed while replacing the stream implementation; inspection found existing `Completer` use and the import was restored. The corrected retry passed.

### Final formatted-source verification

```powershell
flutter test --no-pub test/features/sync/drift_sync_store_test.dart test/runtime/app_bootstrap_test.dart test/screens/setting_screen_test.dart --reporter expanded
```

Result: exit 0, **55 tests passed**.

```powershell
flutter test --no-pub test/features/sync test/features/identity test/features/account test/features/consent test/runtime/account_startup_restore_test.dart test/runtime/app_bootstrap_test.dart test/screens/setting_screen_test.dart test/screens/production_shell_navigation_test.dart test/architecture --reporter compact
```

Result: exit 0, **205 tests passed**. This covers connected sync, owner isolation, account, consent, startup restore, Settings, shell and architecture checks. Flutter commands were serialized.

```powershell
flutter analyze --no-pub lib/features/sync/application/sync_status.dart lib/features/sync/data/drift_sync_store.dart lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart lib/screens/setting_screen.dart test/features/sync/drift_sync_store_test.dart test/runtime/app_bootstrap_test.dart test/screens/setting_screen_test.dart
dart format --output=none --set-exit-if-changed lib/features/sync/application/sync_status.dart lib/features/sync/data/drift_sync_store.dart lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart lib/screens/setting_screen.dart test/features/sync/drift_sync_store_test.dart test/runtime/app_bootstrap_test.dart test/screens/setting_screen_test.dart
```

- Scoped analysis: exit 0, **No issues found**.
- Final format verification: exit 0, **8 files / 0 changed**.
- Tracked `git diff --check`: exit 0; no whitespace errors. `rg` trailing-whitespace check across all eight paths found none. Git emitted LF-to-CRLF warnings; no line-ending normalization or cleanup was performed.
- Independent read-only reviewer `/root/s2_readonly_review`: initial **Critical 0 / Important 1 / Minor 1**; both owner-switch and stream-completion findings were fixed. Re-review of the current logic/tests: **Critical 0 / Important 0 / Minor 0**, disposition Accept. Reviewer made no writes and ran no competing Flutter/analyze/format commands.

## Verified source manifest (SHA-256)

| Path | SHA-256 |
| --- | --- |
| `lib/features/sync/application/sync_status.dart` | `37DB5A1DE7D1DA83629DF08CD36C8164F2F127521BB65F80AE1A76954292C235` |
| `lib/features/sync/data/drift_sync_store.dart` | `C50D1195EA765559D0E04540EB2E56D9044AB14355CDC36A43E94C2DF1E52900` |
| `lib/runtime/app_dependencies.dart` | `83B00D49025D0D4590D43AA80A973C3CCC13D84EC32E8195FCBE2C15FE6D527B` |
| `lib/runtime/app_bootstrap.dart` | `FA7FDDCE3D74C6709954D69E9B344F65485CEEE001B4567DA812629C3FEC3A0D` |
| `lib/screens/setting_screen.dart` | `A1DEE530176CE2BCF56214E00412C8DA7D88232CC978988E51C070538B3BE7E7` |
| `test/features/sync/drift_sync_store_test.dart` | `6BBB2797BBF52211D4D45E9633329EE38DE28BA78583D26CB233BAE2840F649D` |
| `test/runtime/app_bootstrap_test.dart` | `A1A4A6BF84CE4DD59C656D8AF26EDBDA7ADED71CAA9CECD4605558B324D69E5B` |
| `test/screens/setting_screen_test.dart` | `183F2E312F106B57895EA5A01BE1597017C2D23CF58A85255E6B369A07E2AE35` |

## RETURN, limits and next executable step

- Process check at handoff: zero `dart.exe`, `dartvm.exe`, `dartaotruntime.exe`, `flutter.exe` or `flutter_tester.exe` workers; no task-owned test/build session remains. The one failed source-close RED test process was stopped after its double-close teardown hung, then the fixture was corrected; no unrelated process was killed.
- RETURN: release S2 production-writer/Flutter slot to LQ-00 after manifest reconciliation. No further S2 source edits or Flutter commands after RETURN.
- Next: LQ-00 reconciles this bounded snapshot and controls any later card. This checkpoint does not dispatch or authorize another card.
- Not run: full repository suite/build, physical device/native restart, real Firebase/Cloud provider or long-running multi-process concurrency. The transactional regression plus single-query design covers the identified owner-switch boundary but is not physical-device evidence.
- No last-sync timestamp, connectivity assertion, sync toggle, queue mutation, deletion flow, production rollout, publishing, enrollment, real research upload or security-scan workflow was added or run.
