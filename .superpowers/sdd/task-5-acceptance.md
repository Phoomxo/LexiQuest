# Task 5 Acceptance Capsule

## Closed controller decisions

- Use one fixed global persisted owner-operation gate backed by the existing
  `runtime_flags` table. Do not bump schema 12 or regenerate Drift files.
- Five means five durable send reservations committed immediately before
  `gateway.push`. A crash may consume a reservation before invocation; exact
  provider receipt is not locally provable.
- Pull at most one page per collection per run. An advancing `hasMore` page is
  committed and returns `retryRecommended`; `hasMore` without cursor progress
  is invalid.
- All active-owner/Firebase-UID transitions and sync runs participate in the
  same persisted gate. Sync rereads the authoritative owner and UID only after
  acquiring it.
- Only `ownerUpgradeInventory` SQLite mutations are all-or-nothing. External
  secret deletion remains explicitly non-transactional and must not be called
  atomic.
- MaxPlus is unavailable after two `invalidKey` failures. Do not retry unless
  external credential/configuration state demonstrably changes.

## Root causes and invariants

1. The fixed 10-minute run lease is not renewable although a legal run can
   exceed it. Renewal must be token-conditional; a lost/expired token cannot
   resurrect, release, or finish work. Crash-stale ownership is reclaimable.
2. Sync snapshots owner/UID before acquiring its lease, while owner upgrade
   has only an instance-local serializer. A persisted cross-connection gate
   must exclude sync from every owner/UID transition.
3. Batch claim currently consumes attempts, all rows are claimed before push,
   and controlled exits can leak `inFlight` rows. Claim must only lease;
   `beginAttempt` reserves the send. Every controlled exit releases unstarted
   claims without changing attempts, retry deadline, failure code, or ID.
4. Every ack/retry/terminal/release update must predicate on the actual
   operation token and valid owner-gate token. Late stale workers cannot
   overwrite reclaimed work.
5. The first permanent failure attempts one row, marks it terminal, stops the
   batch, performs zero pulls, and releases all unstarted claims. A new engine
   never automatically requeues permission denial.
6. Retryable failure at reservation five becomes durably non-claimable while
   retaining the last failure code. `operationId` is immutable across retry,
   reopen, reclaim, acknowledgement replay, and namespace rehome.
7. Checkpoints compare `(serverUpdatedAtUtc, documentId)` transactionally
   before applying entities. Older cursors roll back; equal replay is
   idempotent; advancing pages commit checkpoint and entities together.
8. Namespace rehome covers all seven supported collections, including
   `srsState` keyed by `word_id` and `achievementUnlock`, while preserving
   operation IDs and resetting attempt/backoff/failure metadata plus
   namespace-specific checkpoints/base revisions for the new Firebase UID.

## Ordered RED slices

### 1. Persisted owner-operation gate

- Use two independent `AppDatabase` handles on one temporary SQLite file.
- Exactly one token acquires; wrong-token release is inert.
- Renewal extends ownership past the original expiry.
- Reclaim succeeds exactly at renewed expiry after close/reopen.
- A stale token cannot renew, release, or finish work.

Implement a small gate port plus Drift adapter with token-conditional
`tryAcquire`, `renew`, `isOwned`, and `release`. Never await a provider, timer,
secure-storage call, or gate acquisition inside a database transaction.

### 2. Heartbeat, fencing, and identity reread

- Block the first push with a completer and drive heartbeat using injected
  clock and scheduler; a second engine remains excluded beyond nominal expiry.
- Simulate ownership loss, finish the late push, and prove zero later gateway
  calls, pulls, or stale acknowledgements.
- Change owner/UID before gate acquisition and prove sync uses the post-gate
  authoritative identity.

Start heartbeat immediately and renew at no more than one-third of the lease.
Stop and await it before token-only release. Release operation claims before
releasing the owner gate.

### 3. Claims, reservations, and terminal exits

- Claim/reclaim without `beginAttempt` keeps `attemptCount == 0`, metadata, and
  `operationId` unchanged.
- Five reservations plus retryable failures become exhausted; a sixth run
  makes zero provider calls.
- First permanent failure: one push, zero pulls, one terminal row, every
  unstarted row restored byte-equivalently, no leaked `inFlight` rows.
- A fresh engine never resurrects permission-denied work.
- Token B reclaim cannot be overwritten by token A's late completion.
- Coalescing durably preserves the minimum base revision before retiring rows.

Introduce a sync-store port; remove `SyncEngine`'s concrete Drift dependency.
Split claim from `beginAttempt`; make all transitions token-conditional.

### 4. Cursor monotonicity and bounded pulls

- Stored `(T, "b")` rejects `(T, "a")` before entity mutation.
- Equal replay is an idempotent no-op.
- Advancing `hasMore` commits and sets `retryRecommended`.
- Null/equal/regressing `hasMore` is transactionally invalid.
- Each collection is pulled exactly once per run.

### 5. Owner upgrade and seven-type rehome

- Anonymous bind with no prior UID owner retains exactly one local owner.
- Seed the complete owner inventory and every sync collection; bind, reopen,
  replay upgrade, and assert stable owner ID, row IDs, counts, operation IDs,
  and post-rehome attempt counts through reopen/replay with no duplicates.
- `srsState.entityId` equals `word_id`; achievement unlock uses its row ID.
- Namespace checkpoint/revision state resets.
- Inject inventory failure and prove all SQLite inventory changes roll back,
  while explicitly recording that prior secret deletion is not restored.
- An active old-UID sync finishes before upgrade; sync requested during upgrade
  waits and then uses only the committed UID.

## Required new scenario evidence

- `test/scenarios/file_backed_sync_recovery_test.dart`: vocabulary and learning
  work is durably applied by the fake before a retryable acknowledgement is
  lost; after the retry deadline/reopen, the same `(uid, operationId)` request
  is replayed, applied only once, and persists its acknowledgement/checkpoint;
  a second reopen makes zero new pushes while IDs and attempts remain stable.
- `test/scenarios/guest_upgrade_restart_test.dart`: complete anonymous-bound
  inventory, bind/reopen/replay, stable counts/IDs, all seven collection types,
  and active-sync/upgrade ordering.

## Likely production surfaces

- `lib/features/sync/application/sync_engine.dart`
- sync-store port plus `lib/features/sync/data/drift_sync_store.dart`
- persisted owner-operation gate port/Drift adapter
- `lib/features/sync/domain/sync_entity.dart` and `sync_result.dart`
- `lib/features/identity/application/upgrade_guest_owner.dart`
- `lib/features/identity/data/drift_owner_upgrade_repository.dart`
- `lib/services/guest_session_service.dart`
- `lib/runtime/app_bootstrap.dart`

## Bounded final gates

```powershell
flutter test test/scenarios/file_backed_sync_recovery_test.dart --reporter compact
flutter test test/scenarios/guest_upgrade_restart_test.dart --reporter compact
flutter test test/features/sync/sync_engine_test.dart test/features/sync/drift_sync_store_test.dart --reporter compact
flutter test test/features/identity/drift_owner_upgrade_repository_test.dart test/features/identity/upgrade_guest_owner_test.dart test/services/guest_session_service_test.dart --reporter compact
flutter test test/runtime/app_bootstrap_test.dart --reporter compact
flutter analyze lib/features/sync lib/features/identity lib/services/guest_session_service.dart lib/runtime/app_bootstrap.dart test/scenarios
git diff --check
```

## Non-goals

- No schema bump, migration, generated Drift rewrite, provider receipt
  protocol, multi-page pull loop, operation-ID regeneration, automatic
  permission-denial reopening, repository-wide refactor, MaxPlus retry, or
  physical/provider evidence claim.
