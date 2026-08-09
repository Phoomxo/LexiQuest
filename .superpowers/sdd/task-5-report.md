# Task 5 Implementation Report

## Rollback point

- Stable rollback SHA: `ef68bc2c48b7e44b12716bbdd46b267445db53ef`.
- Verified before edits: worktree root `C:/Users/Phet/Documents/LexiQuest/.worktrees/p0-integration`, branch `codex/runtime-convergence`, clean index and tracked tree.
- Required schema invariant: `AppDatabase.schemaVersion == 12`; no Drift schema or generated-file change is authorized.

## Verified root causes

1. `SyncEngine` reads the active owner and Firebase UID before acquiring its persisted run lease, and the existing lease is fixed-duration with no renewal.
2. `DriftSyncStore.tryAcquireRunLease` uses an owner-scoped `syncRunLease:<owner>` key, while owner upgrade relies on an instance-local `_writeGate`; independent database connections therefore do not exclude sync from identity transitions.
3. `claimPending` increments `attempt_count`, clears retry/failure metadata, and claims the whole batch before any provider call; `SyncEngine` has no controlled-exit path that restores unstarted claims.
4. Acknowledgement, retry, terminal, and conflict transitions validate only the outbox lease token, not a still-valid global owner-operation token, so late workers can write after lease loss.
5. Every fresh `SyncEngine` calls `requeuePermissionDeniedFailures`, automatically resurrecting permanent permission denial.
6. No durable five-reservation ceiling exists; retryable failures can remain claimable indefinitely.
7. `applyPullPage` mutates entities before checking the stored `(serverUpdatedAtUtc, documentId)` cursor and accepts equal/regressing/no-progress `hasMore` pages.
8. `_requeueOwnerForNewCloudNamespace` enumerates only five collections, omitting `srsState` and `achievementUnlock`; the original acceptance wording also conflated a send budget scoped to one Firebase UID namespace with global operation lifetime.
9. The legacy concrete `DriftLocalOwnerRepository.bindFirebaseUid` writes a UID transition without the persisted owner-operation gate, even though the production upgrade adapter uses that gate.
10. `SyncEngine` ignores the boolean result from token-conditioned acknowledgement/conflict/failure transitions, so a token stolen after provider completion but before the SQLite predicate can still be counted as completed and followed by pulls.

## Closed decisions

- Reuse schema 12 and one fixed global gate row in `runtime_flags`; do not regenerate Drift.
- Five means five durable reservations per Firebase UID namespace, committed immediately before `gateway.push`; a crash may consume one reservation, and exact provider receipt is not claimed. Rehome preserves `operationId` but resets reservation/backoff/failure metadata for the new `(firebaseUid, operationId)` namespace.
- Pull one page per collection per run. Advancing `hasMore` commits and returns `retryRecommended`; no-progress `hasMore` is invalid.
- Sync and every active-owner/Firebase-UID transition share the persisted gate. Sync rereads authoritative owner and UID after acquisition.
- Heartbeat and all completion paths are token-conditioned; only the owning token releases; crash-stale state is reclaimable; lease loss fences later gateway/local completion.
- Claim leases only. `beginAttempt` consumes a reservation. Coalescing first atomically retires superseded rows and durably stores the survivor's minimum base revision; release restores the survivor byte-equivalently to that post-coalescing/pre-lease logical state, including unchanged attempts/retry/failure metadata. Every claimed row reaches ack/retry/terminal/superseded/released.
- The first permanent failure performs one push, zero pulls, terminalizes that row, releases unstarted rows, and is never automatically reopened.
- `operationId` is immutable across retry/reopen/reclaim/rehome; coalesced minimum base revision is durable.
- Checkpoints are transactionally monotonic by `(serverUpdatedAtUtc, documentId)` before entity mutation; equal replay is an idempotent no-op.
- All SQLite owner-transition work is one transaction: `local_owners` identity/active flags, inventory, conflicts/projections, rehome, and checkpoints. External secret deletion alone is deliberately non-transactional and is not restorable by SQLite rollback.
- Rehome supports exactly seven sync collections, with `srsState.entityId == word_id` and `achievementUnlock.entityId == row.id`, while preserving row/operation IDs, resetting per-namespace attempt/backoff/failure state, and resetting checkpoint/base-revision state. An operation exhausted at attempt five receives a fresh five-reservation budget only after UID-namespace rehome.
- Direct `SyncEngine.run` returns immediate `alreadyRunning` while the gate is held. `SyncTrigger.request` queues one bounded/cancellable run, waits without a hot loop, and executes exactly once after the owner transition commits; no old-UID call is allowed.
- Gate validation and the operation token are checked atomically inside every outbox transition transaction/predicate; an `isOwned` precheck is insufficient. Owner transitions renew their shared gate while held beyond its lease duration.
- MaxPlus advisory is unavailable after two identical `invalidKey` failures; no retry is permitted without demonstrably changed external configuration.

## Five-slice RED matrix

| Slice | Focused test surface | Required RED evidence | GREEN evidence | Status |
|---|---|---|---|---|
| 1. Persisted owner-operation gate | `test/features/sync/drift_sync_store_test.dart` | Two file-backed handles exposed the owner-scoped key: token B acquired concurrently for another owner (`Expected false, Actual true`). | Focused two-handle/reopen gate tests green; included in 21-test store suite. | GREEN |
| 2. Heartbeat, fencing, identity reread | `test/features/sync/sync_engine_test.dart` | Valid gate-boundary RED used the pre-gate UID (`firebase-before-gate`); expiry RED let engine B complete; loss RED made two pushes. | Full `sync_engine_test.dart`: 13/13 | GREEN |
| 3. Claims, reservations, terminal exits | `test/features/sync/drift_sync_store_test.dart`, `test/features/sync/sync_engine_test.dart` | Claim/reclaim changed attempt metadata; a sixth provider call remained possible; permanent failure pushed three rows; fresh permission denial reopened; stale-token transitions completed. | Store 21/21 and engine 13/13. | GREEN |
| 4. Cursor monotonicity and bounded pulls | `test/features/sync/drift_sync_store_test.dart`, `test/features/sync/sync_engine_test.dart` | `(T,a)` completed after stored `(T,b)`; equal pages inserted entities; null/equal `hasMore` completed; advancing `hasMore` returned `retryRecommended == false`; a late pull wrote after gate loss. | Combined focused suites passed 41 tests. | GREEN |
| 5. Owner upgrade and seven-type rehome | identity/service/bootstrap tests plus both required scenarios | Existing upgrade completed while the sync gate was held; the inventory assertion found only five rehome types; a trigger request returned `alreadyRunning` instead of waiting; the first full restart proof exposed a duplicate owner/collection checkpoint ID. | Owner-upgrade 16/16, trigger 3/3, local-owner gate 8/8, both file-backed scenarios GREEN, and final combined Task 5 suite 123/123. | GREEN |

## Slice log

Evidence is appended here immediately after each focused RED and GREEN.

### Slice 1: persisted owner-operation gate

- RED command: `flutter test test/features/sync/drift_sync_store_test.dart --plain-name "owner-operation lease is one global gate across file-backed handles" --reporter expanded`
- RED result: exit 1 for the expected behavioral reason. Independent file-backed handle B acquired while handle A owned the gate under another owner, proving the persisted key was not global.
- Secondary RED: the renewal/fencing test failed with missing `isOwned`, then proved the new API was required before implementation.
- GREEN commands: the two focused plain-name invocations for the global two-handle gate and reopen renewal/fencing tests; both exited 0.

### Slice 2: heartbeat, fencing, and identity reread

- First RED command: `flutter test test/features/sync/sync_engine_test.dart --plain-name "rereads authoritative owner identity after gate acquisition" --reporter expanded`
- RED result: exit 1 for the expected behavioral reason (`owners.reads` was 1 rather than 2), proving identity was snapshotted before persisted acquisition.
- Instrumentation correction after repeated failure: the first fake mutated identity *during its first repository read*, so even the reordered implementation still returned the pre-mutation value. That method was stopped after the identical `Expected 2, Actual 1` failure repeated. The distinct replacement mutates identity in the gate's `tryAcquire` callback, immediately before acquisition, which directly tests the accepted ordering.
- Valid replacement RED: with the pre-gate implementation temporarily restored, the pushed UID was `firebase-before-gate` instead of `firebase-after-gate`; restoring the post-gate authoritative read passed.
- Heartbeat RED: at the original ten-minute expiry, engine B returned `completed` rather than `alreadyRunning`. GREEN uses an injected scheduler and observes renewal at three minutes, then exclusion at the original expiry.
- Fencing RED: after a token-loss renewal failure and late push completion, the engine made two pushes. GREEN makes one push, zero pulls, and no stale acknowledgement.
- Slice GREEN: `flutter test test/features/sync/sync_engine_test.dart --reporter compact`, exit 0, 10 tests passed.

### Slice 3: claims, reservations, and terminal exits

- Claim/reclaim RED: the existing claim path incremented `attemptCount` (actual 3 versus preserved 2). GREEN separates claim leases from `beginAttempt`, preserving operation ID and retry metadata through expiry reclaim.
- Reservation RED: the sixth run still attempted provider work. GREEN durably reserves immediately before each push and makes attempt five terminal/non-claimable with the final failure code retained.
- Permanent-exit RED: a batch made three pushes instead of one and left later work claimed. GREEN terminalizes the first permanent failure, makes zero pulls, and restores unstarted claims to their post-coalescing/pre-lease state.
- Permission RED: a new engine made one provider call for permission-denied work. GREEN removes automatic permission-denial reopening.
- Coalescing RED: removing the durable survivor update changed the reclaimed minimum base revision from 0 to 1. GREEN persists the minimum before superseding older rows.
- Fencing REDs: stale claim, reservation, acknowledgement, retry, terminal, release, and conflict completion all mutated state after gate loss. GREEN puts the gate token and operation token into the actual SQLite predicates/transactions.
- Fixture normalization: the first full store run had ten test-only failures because the shared setup gate intentionally excluded custom-token fixtures and two assertions still expected claim-time reservation. The fixtures were normalized once; no production defect or repeated command failure occurred.
- Slice GREEN: `flutter test test/features/sync/drift_sync_store_test.dart --reporter expanded` passed 21/21; `flutter test test/features/sync/sync_engine_test.dart --reporter expanded` passed 13/13.

### Slice 4: cursor monotonicity and bounded pulls

- Ordering RED: with stored `(T, "b")`, incoming `(T, "a")` completed and mutated a category. GREEN compares the full tuple before the first entity mutation and throws `InvalidSyncCursorFailure` transactionally.
- Equal-replay characterization initially passed only because entity-level revision checks masked the page replay. The corrected page-level RED seeded an equal checkpoint and then inserted an entity from the replay page; the entity was inserted. GREEN short-circuits equal non-`hasMore` pages before all entity/projection mutation.
- Advancing `hasMore` RED committed its entity/checkpoint but returned `retryRecommended == false`. GREEN commits the one page and recommends a later run without looping.
- No-progress REDs: null-cursor and equal-cursor `hasMore` both completed; GREEN rejects both transactionally. The regressing-`hasMore` proof is covered by the earlier tuple-regression RED and now passes without mutation.
- Pull fencing RED: a late page inserted its entity after token B reclaimed the owner gate. GREEN token-conditions the transaction's opening write lock and returns without entity/checkpoint mutation for token A.
- The existing engine already pulled each of the seven collections once; a focused characterization test now fixes that bound explicitly.
- Slice GREEN: `flutter test test/features/sync/drift_sync_store_test.dart test/features/sync/sync_engine_test.dart --reporter expanded`, exit 0, 41 tests passed.

### Slice 5: owner upgrade, seven-type rehome, and restart ordering

- Seven-type RED: the complete inventory assertion failed because only five rehome entity types were present (`Expected true, Actual false`). GREEN adds `srsState` keyed by `word_id` and `achievementUnlock` keyed by its row ID, preserves operation IDs, and resets attempts/backoff/failure metadata for the new Firebase UID namespace. An operation exhausted at reservation five is claimable with a fresh five-reservation budget only after that namespace change.
- Upgrade-gate RED: an owner upgrade completed while another persisted token held the owner-operation gate. GREEN waits with an injected bounded scheduler, renews while held, and puts the token into the opening transaction predicate; a fake gate that returns success without persisting the token is rejected.
- Trigger RED: a request made during upgrade returned immediate `alreadyRunning`. GREEN makes `SyncTrigger.request` wait without a hot loop, coalesce to one bounded/cancellable run, and execute exactly once after commit. Direct `SyncEngine.run` remains immediate `alreadyRunning`.
- Atomicity GREEN: local-owner flags/identity, the entire owner inventory, conflict/projection bookkeeping, rehome, and checkpoint normalization are in one SQLite transaction. Injected inventory failure rolls all of those back. Secret deletion is intentionally performed before that transaction and is explicitly non-transactional/non-restorable.
- Guest restart RED: the complete file-backed inventory initially hit the existing unique `(owner_id, collection_name)` checkpoint constraint after owner move. GREEN normalizes checkpoint IDs inside the same transaction; reopen and replay retain stable owner/row/operation IDs and counts with all seven types and no duplicates.
- Required scenario GREENs: `file_backed_sync_recovery_test.dart` proves offline first open, one apply per operation after reopen, durable acknowledgement/checkpoint/IDs, and zero pushes on a second reopen. `guest_upgrade_restart_test.dart` uses two handles and completers to prove old-UID sync completes before upgrade, a request made during upgrade waits, and only the committed UID is called afterward.
- Focused GREENs: owner-upgrade repository 16/16, `SyncTrigger` 3/3, both required scenarios individually, and the final combined Task 5 surface 123/123.

### Final invariant audit additions

- Acknowledgement-predicate RED: after the fake provider replied, the test removed the run token before the acknowledgement transaction; the engine incorrectly reported one completed push and continued. GREEN honors the predicate result, reports zero completed pushes, performs zero pulls, and leaves the reserved row crash-stale/reclaimable without later local completion.
- Direct UID-binding REDs: `DriftLocalOwnerRepository.bindFirebaseUid` did not accept a shared gate and could write during sync. GREEN waits for the fixed persisted gate, heartbeats while held, and requires the token in the actual binding transaction predicate. The focused local-owner suite passes 8/8.

## Final verification

All commands ran sequentially. No repository-wide or security analysis was run for Task 5.

| Gate | Result |
|---|---|
| `flutter test test/scenarios/file_backed_sync_recovery_test.dart --reporter compact` | GREEN, 1/1 |
| `flutter test test/scenarios/guest_upgrade_restart_test.dart --reporter compact` | GREEN, 1/1 |
| `flutter test test/features/sync/sync_engine_test.dart test/features/sync/drift_sync_store_test.dart --reporter compact` | GREEN, 42/42 |
| `flutter test test/features/identity/drift_owner_upgrade_repository_test.dart test/features/identity/upgrade_guest_owner_test.dart test/services/guest_session_service_test.dart --reporter compact` | GREEN, 37/37 |
| `flutter test test/runtime/app_bootstrap_test.dart --reporter compact` | GREEN, 21/21 |
| Capsule scoped `flutter analyze` | GREEN, no issues |
| `powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-sync.ps1` | GREEN, 7/7 phases in 02:12; schema/local tests, Firestore rules, debug APK, and whitespace gate passed |
| Checkpoint A vocabulary/learning/associative/file-backed/guest scenario selection | GREEN, 12/12 |
| `flutter analyze` | GREEN, no issues |
| Final `git diff --check` | GREEN; only Git line-ending conversion notices |

`verify-sync.ps1` emitted non-blocking existing Android toolchain notices about Kotlin plugin migration and SDK XML version skew. They did not fail analysis, tests, policy verification, or APK assembly. A single recursive discovery attempt earlier encountered transient missing `build/.transforms` directories while Gradle artifacts were changing; that discovery method was stopped immediately and never retried. All subsequent work used explicit paths or `rg`, and the filesystem error did not recur.
