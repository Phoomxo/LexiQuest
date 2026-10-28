# R4b Research sync — verified baseline / integration handoff

Snapshot: 2026-09-05 08:02 UTC (15:02 Asia/Bangkok).
Worktree: `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`
Branch: `feature/adventure-research`; HEAD: `6968ce97ff9b383e244b17b77cf0ed0f61eaaf3d`.

**Production frozen for MAIN integration/review. Dart/Flutter slot RELEASED.**
No task-owned command/process is running. The latest bounded sync batch passed
209/209; this is not full engineering/production readiness. Known liveness gaps
below still need explicit regression/review. No production edits after that batch.

## Exact verification and chronology

1. Initial implementation preceded any executed Dart RED; the concrete usable API
   reached MAIN after production patching began. Do not claim preimplementation RED.
2. First explicitly granted slot: the following two-file command compiled and ran
   **44 tests: 29 passed / 15 behavioral failures, exit 1**. Slot released immediately.
3. After fixes, the same command ran **46 tests: 45 passed / 1 fixture error**.
   The new round-trip test JSON-encoded Firestore Timestamp; its conversion was
   corrected without changing the payload/identity assertions.
4. Adding `test/features/sync/assessment_run_sync_test.dart` produced **73 passed /
   1 failed, exit 1**: schema 23 had accidentally been replaced by 24. This was
   observed RED before restoring 23, preserving every accepted schema 15–24.
5. Latest exact seven-file command below: **209/209 passed, exit 0**, including the
   15 originally failing paths, constructor identity, canonical round-trips,
   assessment/ordinary store/engine regressions. Slot explicitly released.
6. Current scoped `git diff --check` passed; only normal LF/CRLF warnings.

Initial RED / focused research command:

```text
flutter test --no-pub test/features/sync/research_measurement_sync_test.dart test/features/sync/research_sync_contract_test.dart --reporter expanded
```

Latest GREEN command (all seven exact paths):

```text
flutter test --no-pub test/features/sync/research_measurement_sync_test.dart test/features/sync/research_sync_contract_test.dart test/features/sync/assessment_run_sync_test.dart test/features/sync/firestore_sync_gateway_test.dart test/features/sync/sync_contract_test.dart test/features/sync/drift_sync_store_test.dart test/features/sync/sync_engine_test.dart --reporter expanded
```

**Formatting and targeted Dart/Flutter analyzer remain pending.** MAIN may run
them after all relevant writers pause; refresh hashes and verification afterward.
No pub get, generators, full analysis/scans, commits, deployment or task creation
were performed by this worker. MAIN's real-P256/runtime integration and independent
review are separate evidence, not included in the 209-test claim.

## Current integration API

Both store and gateway retain constructor names `researchMeasurementRollout`
(default `ResearchMeasurementSyncRollout.off()`) and nullable `researchAuthorizer`.
Normal research denies missing/throwing authorization. MAIN supplies the real
gate-aware authorizer; no production stub was installed.

```dart
Future<int> DriftSyncStore.enqueueResearchForOwner({
  required String ownerId,
  required DateTime nowUtc,
  int limit = 50,
});

abstract interface class ResearchMeasurementSyncRolloutGateway {
  ResearchMeasurementSyncRollout get researchMeasurementSyncRollout;
  ResearchSyncAuthorizer? get researchSyncAuthorizer;
}
```

Use the SAME hook after capture or local withdrawal commit. It acquires its own
gate, does local enqueue only, and claim repeats recovery. No second withdrawal API.
Firestore getters return the exact injected objects; MAIN can compare
`identical(...)` using one captured callback tear-off. Request fields remain phase
(enqueue/claim/push/pull), ownerId, firebaseUid, collection, entityId, payload,
evaluatedAtUtc and nullable process-local ownerGateToken; no token is serialized.
A global sync lease alone is NOT an owner fence: validate its token and deny an
actual live owner-fence marker. The architectural comment has been corrected.

Only `ResearchMeasurementSyncRollout.localEmulatorV1(deployedRulesRevision: ...)`
can enable the path; revision must exactly equal `research-measurement-v1-r1`.
Firestore additionally requires a loopback/emulator endpoint. The existing
assessment rollout remains separate and unchanged.

## Implemented / bounded evidence

- Four v24 tables use payloadVersion 1: motivationMeasurementRun,
  motivationResponse, researchParticipationPermit, measurementOpportunity, with
  snake_case collection wire names.
- Existing EventsV2, no extra table: neutral_events_v2 stores the frozen envelope
  inside a current-permit-reference wrapper. Local outbox entityTypes are exactly
  TodayExperiencePresented / TodayExperiencePresentationChanged /
  TodayExperienceMissionStarted / TodayExperienceMissionCompleted.
- Current owner/Firebase/gate/consent/permit/pins are revalidated for ordinary
  enqueue, claim/reservation and gateway push. Actual owner fences deny.
- Permit client delivery reads/compares a trusted server-issued document; it never
  writes a permit, receipt or issuer authority. Signed canonical fields, signature,
  digest and revisions survive ACK and pull unchanged.
- Existing authenticated newer permit renewal/revocation/deletion can advance;
  stale replay cannot unrevoke/undelete; inactive unknown permits cannot enroll.
  Outer revision/tombstone binding remains transport responsibility.
- Unavailable pull authorization rolls back page/checkpoint. Local withdrawal
  suppresses resurrection. Responses are coded, events do not rewind projections.
- Opportunity upload has no completed-baseline prerequisite. Baseline/Presented
  capture eligibility remains the domain author's responsibility.
- Pending event renewal creates a new operation identity/current wrapper without
  changing the envelope; locally acknowledged events are not re-enqueued.
- Withdrawal recovery uses existing outbox entityType `researchWithdrawal`,
  transport enum `researchWithdrawals`, exact payload `{permitId, ownerId}`.
  It is excluded from optional research pulls. No local table was added.
- Withdrawal does not require active participation authorization, including
  expired/revoked/deleted permits. Store checks current owner/Firebase/token/fence
  and durable withdrawn consent (withdrawn-run fallback); gateway checks Firebase
  ownership against its trusted read-only permit and creates a denial once.
  It never updates/deletes a marker or grants authority. Existing markers are
  read-only ACK receipts after a lost response.
- Claim ordering prioritizes withdrawal, preserves ordinary operation order, and
  orders research parents before children. Outstanding denial blocks ordinary
  research upserts, not ordinary learning/delete operations.
- Ordinary learning/reward authority and the owner gate implementation were not
  edited. External lifecycle/deletion/export files remain owned by MAIN's workers.

## Current Firebase rules evidence

```text
firebase emulators:exec --project demo-lexiquest-rules-test --only firestore "node --test --test-name-pattern=R4b test/security/firestore-rules.test.cjs"
firebase emulators:exec --project demo-lexiquest-rules-test --only firestore "node --test test/security/firestore-rules.test.cjs"
```

Historical focused R4b: 37/37 (07:19 UTC); full file 122/122 (07:27 UTC).
Added active-permit-renewal regression was observed RED before its rules fix.
**Current full rules file: 123/123 tests, 12 suites, zero failures/skips, exit 0
(07:32 UTC).** Emulator shut down cleanly. Current rules/test hashes below match
the unchanged files from that run.

Read-only authority documents: research_participation_permits,
research_sync_authorities (including exact runPins/eventPins and coded option
catalog), research_receipts. Only trusted server/emulator setup writes them.
Entity and reciprocal atomic operation checks split authority predicates to fit
Firestore's expression budget; neither write alone establishes delivery.
Owner-only create-once research_withdrawals/{permitId} blocks new research writes
even while remote receipts remain active. Marker update/delete and client
permit/receipt/authority writes are denied. Personal reads remain possible.
Rules permit new current-wrapper deliveries against unchanged historical parents
with the same permit identity and immutable study pins; acknowledged events stay
immutable. No issuer or real deployment configuration is supplied or implied.

## Remaining known issues / review targets

These are source-inspection findings, NOT newly executed failing regressions:

1. **Historical wrapper / lost cloud ACK after renewal:** if an event already
   exists remotely under an older wrapper but its local ACK was lost, the current
   job can conflict with that immutable remote event. Adapter/callback exact
   current-reference checks can reject the old wrapper and stall reconciliation.
   Historical run/opportunity pulls after renewal have the same strict-reference
   tension. Need explicit authenticated same-envelope/current-authority
   reconciliation tests before changing this boundary.
2. **Withdrawal retry exhaustion:** the existing five-send-reservation cap still
   applies. A permanently failed withdrawal is durable, but recovery excludes an
   already-existing identity and does not automatically restart it. Repeated
   offline failures can therefore leave remote denial undelivered. Need an
   explicit bounded-per-run retry/recovery regression for this idempotent marker
   without weakening ordinary operation reservation limits.
3. **Large-queue fairness:** bounded scans can revisit the same low-ID pending or
   ineligible dirty rows. Fair advancement beyond a full blocked candidate window
   is not implemented/verified; add >limit/restart/withdrawn-row regressions.
4. SDK-level withdrawal fault injection (commit succeeds/response lost), full
   runtime-to-real-P256-to-store integration, analyzer/format and independent
   review remain outstanding. Current coverage combines store/codec/preflight
   tests and actual Firestore rules emulator tests, not whole-device transport.
5. Real issuer/receipt service, deployed rules authorization, production rollout,
   physical-device/UAT and research efficacy are external release evidence.
   Production remains OFF.

Next action: MAIN's frozen-source integration/review. No further production writes
or Dart commands here until MAIN grants them. Subsequent fixes must add/observe
focused RED, preserve the existing 209 baseline and obtain a fresh test slot.

## Changed files and SHA-256 snapshot

Changed production files: all eight lib/features/sync paths below.
Changed tests: research_measurement_sync_test, research_sync_contract_test,
assessment_run_sync_test, firestore_sync_gateway_test, sync_contract_test.
drift_sync_store_test and sync_engine_test were tested but not edited.
Also changed firestore.rules, its existing rules test file, and this report.
No drift_owner_operation_gate.dart or out-of-scope implementation file was edited.

Paths are relative to the worktree above; SHA-256 hashes are full file bytes
captured at 08:02 UTC, not a repository-wide snapshot.

| Path | SHA-256 |
| --- | --- |
| lib/features/sync/application/sync_engine.dart | 58a39e43e06e15ab4255b5fefdff45c2e13a44f214b13888b4dc0d127e1b075c |
| lib/features/sync/data/drift_research_sync_adapter.dart | 5a9faa38957d36f75253c251e3a8ca855213cf537ec880941592a759f341bc08 |
| lib/features/sync/data/drift_sync_store.dart | 407f2ce3d3383135b658dda355800f6c0497c3bc6951a1341ce0eeeab1845e26 |
| lib/features/sync/data/firestore_sync_gateway.dart | b99daa7bc3cd36be3467f76adf172ebfbd360dd5b499133a161d99ab991b1d4f |
| lib/features/sync/domain/research_sync.dart | 02758a16c5ec47aa4d6a7c9560d35b50b122841e735697db8985ff0fe187dff1 |
| lib/features/sync/domain/sync_entity.dart | 951d34dadb519fc362cbf78974dfe0ae74281d964521aa8dd097c4ea934b74b0 |
| lib/features/sync/domain/sync_gateway.dart | 2983f824bce2e2641e7a0ab5d42fa4fb68240489808948d54dc67f6a319ee78c |
| lib/features/sync/domain/sync_store.dart | 3e548e4839ee6f6a4b2659cbd6ee7ee80bf958850594ee38030b24265c77df73 |
| test/features/sync/research_measurement_sync_test.dart | 267d881685fd0207883cb70441a57fc1fdac725aae277e7b7e19dab1c8964b95 |
| test/features/sync/research_sync_contract_test.dart | 568f587e89c8551b24ccaaba3c092ee3eb28c5e0ff44df78b781b46cfcded99c |
| test/features/sync/assessment_run_sync_test.dart | 2bdbb4854df42d8c19e0b5d8653992c1431f0c6e15066131fd4aae84197ac841 |
| test/features/sync/firestore_sync_gateway_test.dart | d1dda5dde6d9fababbd1fa5799afade6525f91fcdfca4a3175747b12b5a1ff6e |
| test/features/sync/sync_contract_test.dart | 26dd8ce434ef4fedb1ae21cde9dd90e11a600476577debbee76a04c4c5c03f65 |
| test/features/sync/drift_sync_store_test.dart | b2aa5e4ca8ec3564910e58bf69bc2657f139cab3492e4024f73c0fd2515069ea |
| test/features/sync/sync_engine_test.dart | 54d050fc6509154de255e9bd13b89e70ed22b7293921749e78c03e9595b16bfd |
| firestore.rules | 90d7e02039ebb42094509939875113fa96587ced5b048fd7764b90ff5b8865a5 |
| test/security/firestore-rules.test.cjs | 1d9cf2fb17e1b0eb4c4783b7985f3750ef4e827fd12fcd28a8778f37a785ccc5 |
