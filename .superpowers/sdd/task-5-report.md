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
- Required scenario GREENs: `file_backed_sync_recovery_test.dart` proves vocabulary and learning requests are durably applied by the fake before a retryable acknowledgement is lost, then requested again under the same `(uid, operationId)` after deadline/reopen while applying once; it persists acknowledgement/checkpoint/IDs and makes zero pushes on a second reopen. `guest_upgrade_restart_test.dart` uses two handles and completers to prove old-UID sync completes before upgrade, a request made during upgrade waits, and only the committed UID is called afterward.
- Focused GREENs: owner-upgrade repository 16/16, `SyncTrigger` 3/3, both required scenarios individually, and the final combined Task 5 surface 123/123.

### Final invariant audit additions

- Acknowledgement-predicate RED: after the fake provider replied, the test removed the run token before the acknowledgement transaction; the engine incorrectly reported one completed push and continued. GREEN honors the predicate result, reports zero completed pushes, performs zero pulls, and leaves the reserved row crash-stale/reclaimable without later local completion.
- Direct UID-binding REDs: `DriftLocalOwnerRepository.bindFirebaseUid` did not accept a shared gate and could write during sync. GREEN waits for the fixed persisted gate, heartbeats while held, and requires the token in the actual binding transaction predicate. The focused local-owner suite passes 8/8.

## Initial Task 5 verification (superseded by reopened verification below)

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

## Reopened Ultra review findings

Task 5 was reopened from `2eb1214a043694724663638379524e252091e21a`. The following are the two final reviewer messages, appended as normalized exact finding summaries before repair work.

### General final reviewer

- Critical: none.
- Important — exhausted crash-stale reservation: `claimPending` applies `attemptCount < 5` before expired `inFlight` recovery, while `beginAttempt` can durably increment to five. A crash/lease loss before acknowledgement leaves the row permanently unclaimable. Normalize it under the owner gate to a terminal unknown-delivery state, clear leases, retain a precise diagnostic, and prove fifth-reservation crash/reopen.
- Important — permanent pull: the `SyncEngine` pull catch continues later collections regardless of `retryable`. Permission/auth/cursor/payload/schema failures can make six more calls. Stop after the first nonretryable pull and prove exactly one call.
- Important — merged-existing orphan SRS/unlock work: word collision remaps `word` outbox IDs but not `srsState`; natural-key de-duplication deletes guest SRS/unlock rows without retiring their outbox. Reconstruction later throws and wedges. Remap SRS IDs, supersede source operations before deletion, and prove merge/reopen/sync.
- Important — missing complete anonymous-bound evidence: the existing guest restart scenario seeds an old anonymous UID plus an existing account owner and proves `mergedExisting`, not same-owner `anonymousBound` or the complete `ownerUpgradeInventory`. Add a no-prior-UID-owner complete inventory path with stable IDs/counts across bind/reopen/replay.
- Important — recovery scenario lacks lost acknowledgement and learning: it seeds one category, fails before fake-cloud apply, and later pushes once. Seed vocabulary and learning work, durably apply then surface a retryable lost acknowledgement, reopen after deadline, prove two requests/one `(uid, operationId)` apply, then zero pushes after a second reopen.
- Important — trigger duplicate: a second request during the inner `alreadyRunning` wait sets follow-up demand, so the first post-release success is followed by a redundant second success. Distinguish pre-success demand from demand arriving during an actual successful run.
- Important — disposal: triggers are unawaited, have no cancel/drain lifecycle, and SQLite can close under queued/active work. Add awaited idempotent disposal that rejects new requests, cancels gate waits, drains active provider work, is ordered before database close, and has a blocked-sync bootstrap disposal proof.
- Minor: none. Assessment: not ready at `2eb1214`.

### Stable concurrency reviewer

- Critical — ambiguous lost-ack coalescing: `DriftSyncStore` groups a stale attempted operation with later pending revisions, selects the last, and supersedes the attempted row. Trace: operation 1 was committed remotely but its acknowledgement was lost; local operation 2 is created; claim coalesces both and sends operation 2 with minimum base revision zero; Firestore sees remote revision one and returns conflict; cloud-wins resolution discards operation 2. Treat every reserved row as a coalescing barrier, replay its immutable ID first, then deterministically reconcile/rebase later never-reserved edits. Prove with a file-backed idempotent `(uid, operationId)` fake.
- Important — exhausted attempt five: `beginAttempt` can persist attempt five, but `claimPending` excludes that expired `inFlight` row. Normalize it to terminal unknown-delivery without another provider call.
- Important — duplicate SRS/unlock outbox: owner-upgrade de-duplication deletes rows before rehome, which only visits survivors; orphan outbox reconstruction then fails. Retire those operations before deletion.
- Important — mutable SRS uploads only once: learning uses the fixed `$entityType:$entityId:1` operation ID with `insertOrIgnore`, and reconstruction hard-codes base/local `0/1`. Give every review a stable unique operation/revision and prove two acknowledged reviews plus restart/lost-ack ordering.
- Important — permanent pull failures continue: break the collection loop on nonretryable failure.
- Minor — ordered cursors may advance beyond delivered rows: require non-empty `nextCursor` to equal the final delivered tuple; an empty page may only preserve the stored cursor.
- Minor — trigger demand arriving during gate polling causes two post-transition runs: coalesce all pre-success demand, while demand arriving during an actual successful run schedules one follow-up.
- No other final issues.

## Reopened repair matrix

| Review finding | Semantic RED / validation | Repair and GREEN evidence |
|---|---|---|
| Ambiguous lost-ack coalescing | A file-backed operation applied remotely without a local acknowledgement was superseded when a later local edit was claimed, exposing that the attempted ID could be lost. | Any `attemptCount > 0` row is now a coalescing barrier and is replayed first under its immutable ID. One token-fenced acknowledgement transaction advances entity cloud state and deterministically rebases or retires later attempt-zero rows. File-backed tests cover both an existing older remote acknowledgement (later content remains claimable) and a new replay carrying the latest revision (later row is superseded without conflict). |
| Expired fifth reservation | A fifth reserved `inFlight` row remained excluded by the `< 5` claim predicate after lease expiry. | Claim startup, under the valid owner gate transaction, normalizes it to `permanentFailure/deliveryUnknownAfterReservationLimit`, clears the lease, and never calls the provider again. File-backed close/reopen is GREEN. |
| Unknown-delivery same-entity barrier | Parameterized RED expected only the unrelated operation to send after fifth-call ambiguity, but two sends occurred because a later same-entity edit bypassed the terminal row. | Exhausted unknown delivery now blocks only later work for the same owner/entity. Remote-applied/no-ack and remote-not-applied fifth calls both make exactly five raw calls, never a sixth; later same-entity work remains pending, unrelated work syncs, and UID rehome resets the namespace budget. |
| Mutable SRS operation reuse | Two real reviews produced only the fixed revision-one operation, so the second state could not upload. | Every inserted answer derives a durable per-owner/word revision and enqueues an immutable event-specific operation ID. The final codec is `srsState:v2:<sha256(ownerId\0wordId\0answerAttemptId)>:r<revision>`, with coherent base/local revisions. Two real `recordAnswer` calls upload revisions one and two across reopen; replaying the same answer creates no third operation; lost acknowledgement replays the older ID first; rehome preserves the ID and reconstructs `localRevision > baseRevision`. |
| Merged-existing orphan work | Pending SRS/unlock operations survived after their natural-key source rows were deleted, then reconstruction could not find the entity. | Word collision remaps `srsState` outbox/conflict entity IDs to the winning word. Natural-key SRS and achievement duplicates retire source outbox rows as superseded evidence before deletion. File-backed merge/reopen/claim completes without orphan reconstruction. |
| Permanent pull continuation | A nonretryable first pull still advanced through later collections. | The pull loop now stops immediately on the first nonretryable auth/permission/schema/cursor/payload failure; the focused test observes exactly one pull and no later collection calls. |
| Anonymous-bound inventory evidence | The original scenario proved only `mergedExisting` and did not exercise a no-prior-UID owner. | The retained two-handle merged scenario is joined by a file-backed `anonymousBound` path covering all 25 direct inventory tables, vocabulary import rows, quest objective progress, all seven sync types, stable IDs/counts, and no duplicates. A complete inactive foreign-owner graph is fingerprinted before bind and remains value/type-equivalent through bind, reopen, and sync. |
| Recovery evidence | The original fake failed before apply and seeded no learning work, so it did not prove idempotent lost-ack replay. | The scenario seeds vocabulary plus learning work, applies the first request before surfacing a retryable lost acknowledgement, advances the injected clock beyond the retry deadline, reopens, requests the same `(uid, operationId)` a second time, applies it once, then proves zero pushes and stable IDs/attempts/ack/checkpoint after another reopen. |
| Trigger pre-success duplication | Two requests during persisted-gate polling caused an extra successful follow-up. | A request generation is sampled at each actual run. All demand accumulated before the first successful post-release run coalesces into it; demand arriving during an active success schedules exactly one follow-up. The held-gate two-request count and success-run follow-up tests are GREEN, as is a request at the success/teardown boundary. |
| Trigger lifecycle | Bootstrap could close SQLite under queued or active unawaited trigger work. | `dispose` is awaited/idempotent, rejects new requests, wakes bounded gate waits, and drains provider work. Detached requests contain late errors. Bootstrap registers trigger disposal after database ownership so LIFO cleanup drains it first; the blocked-sync bootstrap test proves database-close ordering without claiming hard-process-kill safety. |
| Cursor contract | REDs accepted `(T,z)` after final delivered `(T,a)`, descending `(T,z),(T,a)` changes, duplicate entity IDs, and a mixed-collection page whose first row reached SQLite before rejection. | Non-empty pages require strictly increasing unique `(serverUpdatedAtUtc, entityId)` changes and a cursor exactly equal to the final tuple. Empty/no-checkpoint accepts only null; empty/existing accepts only the stored cursor. Collection, cursor, and progress validation precede entity mutation. The one pre-existing reward fixture was normalized from descending to ascending equal-time document order. |
| ACK boundary audit | Characterization removes the owner token before acknowledgement with an attempted row plus a later edit, and replays a duplicate acknowledgement with an older revision/time. | Both are GREEN without further production change: token loss leaves the attempted row `inFlight`, entity cloud revision unchanged, and later row/base untouched; duplicate acknowledgement cannot regress the stored acknowledgement, entity revision/time, or later-row rebase. |

No controller or risk-advisor contract conflict was found. Schema remains 12; no Drift table, migration, or generated file changed. The five-send budget remains per Firebase UID namespace, external secret deletion remains outside SQLite atomicity, and no exact provider-receipt or hard-process-kill claim is made.

## Reopened RED/GREEN execution notes

- Cursor order and uniqueness RED: both constructors returned `PullPage`; GREEN rejects both invalid lists. Mixed-collection prevalidation RED surfaced SQLite foreign-key error 787 from the first row; GREEN throws `InvalidSyncPayloadFailure` before applying it.
- Exhausted ambiguity barrier RED: after attempt five, the next run made two provider calls instead of the one unrelated call; both remote-applied and remote-not-applied variants are GREEN after the barrier predicate.
- The stronger ACK, duplicate-answer, SRS rehome, empty-cursor, trigger-quiescence, disposal-wakeup, and foreign-owner invariance additions were characterization GREENs, confirming the repaired transaction/lifecycle contracts without speculative production changes.
- The first complete anonymous-bound foreign fixture used obsolete test-only import-row column names; schema inspection identified `payload_hash/status/word_id`, the fixture was corrected once, and the scenario passed. This was a fixture correction, not a production defect.
- The first full Task 5 selection exposed one legacy reward test whose equal-timestamp changes were ordered `reward-second, reward-first`. The strict cursor contract correctly rejected it; ordering the fixture by document ID made the focused regression and the 145-test selection GREEN.
- Execution stopped and was reported when a Windows wildcard `rg` path repeated an invalid-filename error, then resumed only after explicit authorization with literal paths/`rg -g`. A later verifier format complaint repeated because its format phase is non-writing; execution again stopped, and explicit authorization prescribed the one-file `dart format` repair. The subsequent verifier passed with zero format changes. Neither stopped method recurred after its authorized correction.

## Reopened final verification

All commands below ran sequentially on the substantive repair head. No repository-wide security analysis, MaxPlus retry, or Codex Security workflow ran.

| Gate | Result |
|---|---|
| Focused affected repair selection | GREEN, 126/126 |
| Plan Task 5 selection: `flutter test test/features/sync test/features/identity ...` | GREEN, 145/145 |
| File-backed recovery scenario | GREEN, 1/1 |
| Guest-upgrade restart scenarios | GREEN, 2/2 |
| Acceptance sync engine/store gate | GREEN, 52/52 |
| Acceptance identity/service gate | GREEN, 38/38 |
| Acceptance bootstrap gate | GREEN, 22/22 |
| Acceptance scoped `flutter analyze` | GREEN, no issues |
| `verify-sync.ps1` | GREEN, 7/7 phases in 01:44; 102 scoped files already formatted, scoped analysis clean, 267 Flutter tests and 31 Firestore rules tests passed, debug APK built, whitespace clean |
| Checkpoint A vocabulary/learning/associative/recovery/upgrade scenarios | GREEN, 13/13 |
| Full `flutter analyze` | GREEN, no issues |
| Final `git diff --check` before documentation finalization | GREEN; line-ending conversion notices only |

The verifier emitted non-blocking existing Android Kotlin-plugin migration notices. MaxPlus advisory remains unavailable after the two prior `invalidKey` failures and was not retried because no external configuration changed.

## Consolidated Ultra stable review at `c18b1dd`

Verdict: **NOT READY**. The exact findings accepted for semantic RED validation are:

1. **CRITICAL — SRS operation IDs collide across offline devices.** Current `srsState:<wordId>:<attempt-count>` lets two devices at revision five create the same revision-six ID, so the second request can receive the first device's receipt. Use a stable answer/event identity plus explicitly parseable revision (recommended `srsState:<answerAttemptId>:r<revision>`), keep `entityId == wordId`, preserve the ID across retry/rehome, and prove with two independent file-backed devices under the same UID that distinct answers at the same base use distinct IDs and the raw second request cannot receive the first receipt. Trace conflict outcome honestly; do not silently drop it.
2. **CRITICAL — complete `mergedExisting` inventory can fail.** Add deterministic collision handling before owner rewrite for `streak_states`, `learning_day_log`, `association_records`, `associative_memory_states`, quest instances/objective progress, and every owner-unique table; remap `speech_evidence.word_id` before deleting a colliding guest word. Seed both owners with complete inventory and overlapping natural keys/IDs, then merge/reopen/replay with stable target/foreign data and no constraint or foreign-key failure.
3. **IMPORTANT — mutable SRS pull/conflict uses immutable validation.** Add mutable SRS validation: revision at least one, nondeleted, `entityId == payload.wordId`, and valid payload version/types. Prove revision-two pull and revision-two push-conflict.
4. **IMPORTANT — `_remapEntityReferences` is cross-owner.** Pass the source owner and predicate both outbox and conflict updates by owner. Add a three-owner same-ID collision RED proving foreign bookkeeping remains byte-equivalent.
5. **IMPORTANT — legacy schema-12 SRS work can be missing.** A database may contain one acknowledged `srsState:<word>:1` while later durable answers changed local SRS without another outbox row. Add an idempotent, owner-gate-fenced, bounded normalization that ensures the latest durable answer-derived SRS revision has the new outbox operation on reopen, with no duplicate/resend; prove using a file-backed legacy fixture. Keep schema 12 and document the performance bound.
6. **IMPORTANT — direct Firebase UID A→B rebinding retains old namespace state.** Reject a non-null different UID in `DriftLocalOwnerRepository` and require `UpgradeGuestOwner`; null→UID and same-UID calls remain idempotent. Prove A→B rejection leaves every row unchanged.

The review also requires revalidation of the prior lost-ack coalescing barrier, five-reservation terminal barrier, cursor contract, trigger disposal, anonymous-bound upgrade, and the full Task 5 selection before a new non-amend stable commit.

## Consolidated review RED/GREEN matrix

Rollback SHA for this review cycle: `c18b1ddcdc65cd965dd3e748dc9bd5550244d9fc`.

| Finding | Semantic RED | Repair and focused GREEN evidence |
|---|---|---|
| Cross-device SRS operation collision | Two independent file-backed databases under the same Firebase UID, at the same base revision, produced the same legacy revision-derived operation ID. The second raw request could therefore receive the first device's receipt. | A shared anchored codec now emits `srsState:v2:<sha256(ownerId\0wordId\0answerAttemptId)>:r<N>`. The two devices emit distinct bounded, non-sensitive IDs. The first request acknowledges; the raw second request reaches the provider independently and returns an explicit conflict rather than the first receipt. The immutable second answer remains local, conflict evidence records `localEvidenceWins/immutableAnswerEvidence`, and retry/rehome never rewrites an existing ID. Rehome-generated SRS work uses the same codec. |
| Complete `mergedExisting` collision handling | A fully populated guest/account overlap first failed while deleting a word still referenced by speech evidence; after that ordering fix, an overlapping immutable event ID failed the owner rewrite uniqueness constraint. Final adversarial REDs then showed that already-occupied generated import/reward fallback keys failed owner rewrite, and a guest-only quest objective retained its source child ID. | The fenced transaction now resolves every owner-unique/natural-key family before owner rewrite: word references (including speech), SRS, streak, learning day, association, memory, quest/objectives, event identities, AI usage, imports, conflicts, checkpoints, and outbox work. Import/reward fallback keys are selected deterministically against the finite occupied-key set, and a moved objective receives `<targetInstanceId>:<objectiveId>`. The file-backed two-owner fixture merges, reopens, replays once, and then has zero pushes; canonical target IDs remain stable, source ownership is gone, and a third foreign owner's complete fingerprint remains byte-equivalent. |
| Mutable revision-two SRS validation/conflict | Revision-two pull and push-conflict payloads were rejected by the immutable revision-one validator. A cloud SRS cache could also overwrite a projection supported by local answer evidence. | Mutable SRS validation accepts nondeleted revisions `>= 1`, requires `entityId == payload.wordId`, and validates version and payload types. Revision-two pull and conflict are GREEN. When immutable local attempts exist, the projection is rebuilt from their union; cloud cache state is only a no-local-evidence fallback. |
| Cross-owner bookkeeping remap | A three-owner same-entity-ID fixture showed that remapping one source owner also changed the foreign owner's outbox/conflict entity IDs. | Both bookkeeping updates are now explicitly predicated by source owner and entity ID. The target merge completes and the foreign owner's bookkeeping fingerprint is byte-equivalent. |
| Legacy schema-12 SRS normalization | A file-backed legacy database with acknowledged `srsState:<word>:1` plus later durable answers reopened with no claimable operation for the latest projection. Opaque legacy IDs also derived a spurious revision from arbitrary embedded digits. | Claim startup performs an owner-gate-fenced, idempotent normalization. It scans that owner's SRS/answer/outbox evidence once, groups by word, and inserts at most 20 missing latest answer-derived operations per invocation; later invocations continue the bound. Existing attempted/acknowledged IDs remain immutable, terminal rows are not reopened, and exact legacy suffixes remain compatible. Opaque legacy IDs use `baseRevision + 1`. The reopen fixture produces exactly one missing operation and no duplicate/resend. This bounds writes, not the owner-scoped read scan; schema 12 and generated files remain unchanged. |
| Direct UID A-to-B rebind | `bindFirebaseUid` emitted a changed local owner while retaining the old namespace's data. | Binding now rejects a different non-null UID and directs callers through `UpgradeGuestOwner`; null-to-UID and same-UID remain idempotent. The RED/GREEN snapshot proves the rejected call leaves the owner and all inventory rows unchanged. |

Additional risk-audit checks are GREEN: achievement rebuild inserts missing threshold unlocks without deleting/recreating existing unlock identity; no claimable dangling unlock outbox remains; answer replay creates no third SRS operation; SRS rehome retains `localRevision > baseRevision`; adversarial pre-existing merged event/import/reward keys are resolved deterministically; and guest-only quest progress is canonicalized to the target child identity inside the fenced owner transaction. No risk-advisor contract conflict was found.

The merge policies are explicit and deterministic. Combined answer evidence rebuilds SRS; absent evidence, the newest whole snapshot wins. Streak uses the later learned/updated state with maximum longest/freeze counters and enforces `longest >= current`. Learning-day collisions union by day with the earliest first session and canonical target ID. Association/memory retain the newest whole row after exact word remap. Quest status ranks completed over active over expired over abandoned, then catalog/timestamp/stable ID; compatible objectives union source IDs and bounded maximum progress, while incompatible objective sets retain the winning quest and record conflict evidence. All SQLite identity, active-owner, inventory, projection, conflict, rehome, and checkpoint work remains one token-fenced transaction. External secret deletion remains intentionally non-transactional.

## Consolidated review final verification

All commands ran sequentially after the substantive changes. No repository-wide security analysis, MaxPlus retry, or Codex Security workflow ran.

| Gate | Result |
|---|---|
| Focused learning-event suite | GREEN, 15/15 |
| Focused mutable-SRS suite | GREEN, 5/5 |
| Focused owner-upgrade suite | GREEN, 19/19 |
| Focused guest-upgrade restart scenarios | GREEN, 3/3 |
| Plan Task 5 selection: sync, identity, recovery, guest | GREEN, 154/154 |
| File-backed recovery scenario | GREEN, 1/1 |
| Acceptance sync engine/store gate | GREEN, 52/52 |
| Acceptance identity/service gate | GREEN, 40/40 |
| Acceptance bootstrap gate | GREEN, 22/22 |
| Final-head `verify-sync.ps1` | GREEN, 7/7 phases in 01:24; 102 scoped files already formatted, scoped analysis clean, Flutter selection passed, 31 Firestore rules tests passed, debug APK built, whitespace clean |
| Checkpoint A vocabulary/learning/associative/recovery/upgrade scenarios | GREEN, 14/14 |
| Full `flutter analyze` | GREEN, no issues in 10.1 seconds |
| Final `git diff --check` | GREEN; line-ending conversion notices only |

The verifier emitted only the existing non-blocking Android Kotlin-plugin migration notice. MaxPlus advisory remains unavailable after the two prior identical `invalidKey` failures and was not retried because external configuration did not change. This remains file-backed host/fake-provider evidence: it does not claim physical process-kill durability, device certification, or exact provider receipt.
