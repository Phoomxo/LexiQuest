# P2 Firebase Sync, Background Work, and Guest Upgrade Plan

**Goal:** Synchronize the existing Drift source of truth to a new versioned
Firestore field schema without duplication, preserve local data through guest
upgrade and account switching, and keep every local learning path usable when
cloud work is disabled or unavailable.

**Starting conditions:**

- Firebase contains no participant data that must be migrated.
- Drift schema version 1 and local vocabulary are frozen by the P1 gate.
- The existing legacy Firestore collections remain isolated; P2 does not make
  them the source of truth and does not import them into the new field schema.
- The UI continues to report success after a local transaction. No screen waits
  for a sync acknowledgement.

## Delivery packages

| Package | Outcome | Gate |
|---|---|---|
| P2-A Contracts and migration | Drift v2 stores leases, remote revisions, conflict evidence, and cached cloud policy | Migration tests |
| P2-B Sync engine | Deterministic claim, push, pull, retry, checkpoint, and conflict behavior behind a fake gateway | Engine tests |
| P2-C Firestore gateway | Versioned per-user cloud documents, idempotent operation acknowledgements, and cursor-safe pull | Gateway/emulator tests |
| P2-D Guest ownership | Anonymous binding and existing-account merge preserve all local owner-scoped rows | Migration tests |
| P2-E Android scheduling | Unique network-constrained WorkManager job plus foreground triggers and kill switch | Adapter tests + debug APK |
| P2 Gate | Offline → restart → reconnect → sync is exact-once; cloud-off remains local-first | One bounded CLI gate |

## Execution status

| Package | Status | Evidence |
|---|---|---|
| P2-A schema migration | Complete | v1 fixture migrates to v2 without row loss |
| P2-A sync contracts | Complete | Cursor, schema, payload, failure, acknowledgement, and policy tests pass |
| P2-B Drift sync store | Complete | Lease, coalescing, retry, owner isolation, checkpoint, and conflict tests pass |
| P2-B sync engine | Complete | Offline/reconnect exact-once, kill switch, push conflict, and mutex tests pass |
| P2-C Firestore gateway and rules | Complete | Codec/gateway tests and 17 Firestore emulator rules tests pass |
| P2-D guest ownership | Complete | 14-table inventory, collision remap, rollback, replay, logout, and anonymous binding tests pass |
| P2-E Android scheduling | Complete | Connected unique periodic work, callback result mapping, scheduler tests, and debug APK pass |
| P2 gate | Complete (automated) | 7/7 phases pass; real Android journey remains field certification evidence |

## Development discipline

- Use RED-GREEN-REFACTOR inside the owning package.
- Run one focused test file while implementing a behavior.
- Run the affected package once at its boundary.
- Run the complete P2 gate once after all packages are composed.
- Never rerun an unchanged failing command.
- A lower-priority legacy UI failure does not interrupt active sync work unless
  it prevents the current acceptance test.
- Do not use repository-wide recursive PowerShell scans. Use scoped `rg`.
- Do not expose document payloads, vocabulary text, UID, email, tokens, or
  provider exception messages in logs.
- Do not invoke Codex Security or any Security Scan workflow.

## Firestore field schema

All synchronized data is under `field_users/{uid}`. Access is authorized by the
path UID; clients cannot select a different owner in a document field.

```text
field_users/{uid}
  schemaVersion: 1
  createdAt: server timestamp

field_users/{uid}/categories/{categoryId}
field_users/{uid}/words/{wordId}
field_users/{uid}/operations/{operationId}

app_control/field
  cloudSyncEnabled: bool
  schemaVersion: 1
```

Category and word documents contain:

- `schemaVersion`
- stable entity ID
- canonical entity fields
- `revision`
- `isDeleted`
- `clientUpdatedAtUtcMs`
- `serverUpdatedAt`
- for words, `categoryId`

Operation acknowledgement documents contain:

- stable operation ID
- entity type and ID
- operation kind
- requested base revision
- resulting revision
- server acknowledgement time

Pull cursors are a JSON pair of `serverUpdatedAt` plus document ID. Queries
order by both fields and use `startAfter`, so documents sharing one server
timestamp cannot be skipped.

## Conflict rules

- An operation whose ID already has an acknowledgement returns the same
  acknowledgement without rewriting the entity.
- A push applies only when its base revision equals the current cloud revision.
- A higher acknowledged cloud revision wins over an unacknowledged local edit;
  the losing local and cloud snapshots are recorded in `sync_conflicts`.
- Equal revisions use server UTC time, then entity ID as a deterministic final
  tie-break.
- A tombstone wins over an edit based on the same or an older revision.
- Category pulls apply before word pulls to preserve foreign keys.
- Immutable learning/ledger events added in P3 will union by stable ID rather
  than use mutable-entity conflict resolution.

## Failure classes and retry policy

| Failure | Outbox result | Retry |
|---|---|---|
| Offline / timeout / provider unavailable | `retryWaiting` | Bounded exponential backoff with injected jitter |
| Unauthenticated | `blockedAuth` | Resume after account binding |
| Permission denied | `permanentFailure` | Manual/operator intervention |
| Invalid payload/schema | `permanentFailure` | Code/data repair |
| Quota/resource exhausted | `retryWaiting` | Longer bounded backoff |
| Cloud kill switch off | no claim | Resume only when policy enables |

No worker retries forever in one execution. One run claims at most 50
operations and pulls at most 100 changes per collection.

---

## Task 1: Migrate Drift from schema 1 to schema 2

**Files:**

- Modify: `lib/data/local/tables/vocabulary_tables.dart`
- Modify: `lib/data/local/tables/sync_tables.dart`
- Create: `lib/data/local/tables/runtime_tables.dart`
- Modify: `lib/data/local/app_database.dart`
- Regenerate: `lib/data/local/app_database.g.dart`
- Create: `test/data/local/app_database_migration_test.dart`

**Schema changes:**

- Categories and words add `cloudRevision`,
  `lastAcknowledgedAtUtcMs`, and `serverUpdatedAtUtcMs`.
- Outbox adds `leaseToken`, `leaseExpiresAtUtcMs`, and
  `lastAttemptAtUtcMs`.
- Conflicts add nullable `localSnapshotJson` and `cloudSnapshotJson`.
- `runtime_flags` caches `cloudSyncEnabled`, source, and update/expiry times.

**Acceptance tests:**

1. A schema-1 fixture upgrades without losing category, word, import, or
   outbox rows.
2. New columns receive safe defaults.
3. The upgrade can reopen repeatedly.
4. Foreign keys and unique keys remain active.
5. A failed migration rolls back.

**Focused command:**

```powershell
flutter test test/data/local/app_database_migration_test.dart
```

**Commit:**

```text
feat(data): migrate local sync state to schema two
```

---

## Task 2: Define provider-neutral sync contracts

**Files:**

- Create: `lib/features/sync/domain/sync_entity.dart`
- Create: `lib/features/sync/domain/sync_failure.dart`
- Create: `lib/features/sync/domain/sync_gateway.dart`
- Create: `lib/features/sync/domain/sync_result.dart`
- Create: `lib/features/sync/domain/cloud_sync_policy.dart`
- Create: `test/features/sync/sync_contract_test.dart`

**Interfaces:**

```dart
abstract interface class SyncGateway {
  Future<PushResult> push(PushMutation mutation);
  Future<PullPage> pull({
    required String firebaseUid,
    required SyncCollection collection,
    required SyncCursor? after,
    required int limit,
  });
  Future<CloudSyncPolicy> fetchPolicy();
}

enum SyncCollection { categories, words }

sealed class SyncFailure implements Exception {
  const SyncFailure();
}
```

DTOs contain scalar fields and maps only. They never import Firebase, Flutter,
Drift, WorkManager, or HTTP types.

**Acceptance tests:**

- Cursor JSON round-trips and rejects malformed values.
- Entity payload versions fail closed.
- Failure classes expose stable privacy-safe codes only.
- Push acknowledgements require non-negative revisions and UTC timestamps.

**Focused command:**

```powershell
flutter test test/features/sync/sync_contract_test.dart
```

**Commit:**

```text
feat(sync): define provider-neutral synchronization contracts
```

---

## Task 3: Implement the Drift sync store

**Files:**

- Create: `lib/features/sync/data/drift_sync_store.dart`
- Create: `test/features/sync/drift_sync_store_test.dart`

**Responsibilities:**

- Claim a deterministic FIFO batch with a unique lease.
- Recover only expired leases.
- Reconstruct category/word payloads from authoritative Drift rows.
- Mark acknowledgement, retry wait, blocked auth, or permanent failure.
- Apply category/word pull pages transactionally.
- Advance a collection checkpoint only after the full page commits.
- Persist conflict metadata and both losing snapshots.

**Acceptance tests:**

- Concurrent claimers never receive the same operation.
- A crash before acknowledgement becomes reclaimable after lease expiry.
- Acknowledging the same operation twice is a no-op.
- Retry timestamps follow injected bounded backoff.
- Pull rollback leaves the checkpoint unchanged.
- Owner isolation holds for claim, acknowledge, pull, and conflicts.

**Focused command:**

```powershell
flutter test test/features/sync/drift_sync_store_test.dart
```

**Commit:**

```text
feat(sync): persist leased outbox and pull checkpoints
```

---

## Task 4: Implement the deterministic sync engine

**Files:**

- Create: `lib/features/sync/application/sync_engine.dart`
- Create: `lib/features/sync/application/sync_mutex.dart`
- Create: `lib/features/sync/application/sync_backoff.dart`
- Create: `test/features/sync/sync_engine_test.dart`

**Run order:**

1. Read the active owner and cached policy.
2. Stop with a typed skipped result when cloud is disabled or UID is absent.
3. Acquire the per-owner mutex.
4. Claim and push at most 50 outbox operations.
5. Pull categories, then words, at most 100 each.
6. Release the mutex in `finally`.
7. Return counts and stable failure codes without payloads.

**Acceptance tests:**

- Replaying a completed run makes zero additional cloud mutations.
- Offline mutations push exactly once after reconnection.
- Push acknowledgement followed by process interruption is replay-safe.
- Pull interruption does not advance the cursor.
- Conflicts follow the declared revision/tombstone policy.
- Two foreground/background runs for one owner cannot overlap.
- Different owners can run independently.
- Kill switch leaves outbox rows untouched and local reads usable.

**Focused command:**

```powershell
flutter test test/features/sync/sync_engine_test.dart
```

**Commit:**

```text
feat(sync): add bounded idempotent push-pull engine
```

---

## Task 5: Implement the Firestore sync gateway

**Files:**

- Create: `lib/features/sync/data/firestore_sync_gateway.dart`
- Create: `test/features/sync/firestore_sync_gateway_test.dart`
- Modify: `firestore.rules`
- Extend: `test/security/firestore-rules.test.cjs`

**Push transaction:**

1. Require the authenticated UID to equal the mutation UID.
2. Read `operations/{operationId}`.
3. Return its stored acknowledgement if present.
4. Read the entity document and validate the exact base revision.
5. Write the mutation's higher local revision and server timestamp. Consecutive
   offline revisions may be coalesced into one payload because P1 intentionally
   reconstructs payloads from the authoritative latest entity.
6. Write the immutable operation acknowledgement in the same transaction.

**Pull:**

- Query one entity collection ordered by server update time and document ID.
- Start after the exact two-part cursor.
- Map Firebase exceptions to typed sync failures.
- Reject unknown schema versions without logging provider payloads.

**Rules tests:**

- Alice cannot read/write Bob's field path.
- Anonymous and registered users can access only their own field path.
- Entity field allow-lists and size bounds are enforced.
- Revision must advance above the exact base, cannot regress, and cannot
  overwrite a mismatched base.
- Operation acknowledgement is create-only and immutable.
- `app_control/field` is client read-only.
- Every unlisted field collection remains denied.

**Focused commands:**

```powershell
flutter test test/features/sync/firestore_sync_gateway_test.dart
npm run test:rules
```

**Commit:**

```text
feat(sync): add versioned Firestore gateway and rules
```

---

## Task 6: Implement lossless guest upgrade

**Files:**

- Create: `lib/features/identity/domain/owner_upgrade.dart`
- Create: `lib/features/identity/application/upgrade_guest_owner.dart`
- Create: `lib/features/identity/data/drift_owner_upgrade_repository.dart`
- Extend: `lib/services/guest_session_service.dart`
- Create: `test/features/identity/drift_owner_upgrade_repository_test.dart`
- Create: `test/features/identity/upgrade_guest_owner_test.dart`

**Behavior:**

- Anonymous sign-in binds its UID to the active local owner.
- Linking credentials and retaining the same UID changes account state only.
- Signing into an existing UID merges the active guest into the local owner
  already associated with that UID in one transaction.
- Pending outbox operations are reassigned with their stable operation IDs.
- Natural-key collisions use deterministic target ownership and record a local
  merge conflict; data is never silently dropped.
- Replaying the same upgrade marker is a no-op.
- Logout creates or activates a local guest without deleting account-owned
  rows.

**Acceptance tests:**

- All owner-scoped tables are included in the migration inventory.
- Vocabulary, imports, learning events, SRS, reading, points, achievements,
  conflicts, checkpoints, consent, and outbox rows remain reachable.
- Duplicate entity IDs and natural keys resolve deterministically.
- Failure at any table rolls back the whole upgrade.
- No UID, email, or credential value appears in diagnostics.

**Focused commands:**

```powershell
flutter test test/features/identity/drift_owner_upgrade_repository_test.dart
flutter test test/features/identity/upgrade_guest_owner_test.dart
```

**Commit:**

```text
feat(identity): migrate guest ownership without data loss
```

---

## Task 7: Add cloud policy and foreground triggers

**Files:**

- Create: `lib/features/sync/application/sync_trigger.dart`
- Create: `lib/features/sync/data/drift_cloud_policy_cache.dart`
- Modify: `lib/runtime/app_dependencies.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Modify: `lib/main.dart`
- Create: `test/features/sync/cloud_sync_policy_test.dart`
- Extend: `test/runtime/app_bootstrap_test.dart`

**Policy order:**

1. `LEXIQUEST_CLOUD_SYNC_ENABLED=false` is an unconditional local off switch.
2. A valid cached remote off switch stops work.
3. An expired/missing remote policy is refreshed when reachable.
4. Policy refresh failure fails closed for cloud work and never blocks local
   vocabulary.

Foreground-safe sync triggers after local mutation, successful UID binding, app
resume, and manual retry. Triggers coalesce through the per-owner mutex.

**Focused command:**

```powershell
flutter test test/features/sync/cloud_sync_policy_test.dart test/runtime/app_bootstrap_test.dart
```

**Commit:**

```text
feat(sync): compose cloud policy and foreground triggers
```

---

## Task 8: Add Android WorkManager synchronization

**Files:**

- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/features/sync/platform/background_sync_scheduler.dart`
- Create: `lib/features/sync/platform/workmanager_sync_scheduler.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `test/features/sync/background_sync_scheduler_test.dart`

**Behavior:**

- Register one unique job per owner.
- Require a connected network.
- Use WorkManager backoff; do not spin inside the callback.
- Callback initializes Flutter, Firebase, Drift, and the same sync engine used
  in foreground.
- Success, retry, and permanent failure map to WorkManager results.
- Android deferral never blocks foreground local usage.
- Non-Android platforms use a no-op scheduler.

**Focused command:**

```powershell
flutter test test/features/sync/background_sync_scheduler_test.dart
flutter build apk --debug --no-pub --dart-define=LEXIQUEST_CLOUD_SYNC_ENABLED=true
```

**Commit:**

```text
feat(sync): schedule constrained Android background work
```

---

## Task 9: Add the bounded P2 gate

**Files:**

- Create: `tool/cli/verify-sync.ps1`
- Create: `docs/development/p2-sync-gate-2026-07-30.md`
- Update this plan with execution status.

**One gate command:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-sync.ps1
```

The script runs once, fail-fast:

1. scoped format check;
2. scoped analyzer;
3. P1 regression gate excluding its duplicate APK build;
4. sync and owner-upgrade tests;
5. Firestore emulator rules tests;
6. Android debug APK with sync enabled;
7. `git diff --check`.

## P2 completion gate

- [x] Schema-1 databases migrate to schema 2 without data loss.
- [x] Offline operations synchronize exactly once after reconnection.
- [x] Push replay and process restart cannot duplicate cloud entities.
- [x] Pull checkpoint advances only after a full transaction.
- [x] Conflict and tombstone behavior is deterministic and recorded.
- [x] Guest upgrade preserves every owner-scoped table.
- [x] Cloud kill switch leaves local vocabulary usable.
- [x] Foreground and background sync cannot overlap for one owner.
- [x] Firestore rules prevent cross-user access and malformed writes.
- [x] Focused analyzer/tests, emulator tests, and Android debug build pass.
- [ ] Real Android background/reconnect journey is recorded when hardware is
      attached.

## Next plan

After the automated P2 gate passes, create
`docs/superpowers/plans/2026-07-30-p3-learning-core.md`. P3 consumes the sync
engine as-is and adds immutable learning events before enabling Quiz, SRS,
Reading, weakness, mastery, streak, or rewards.
