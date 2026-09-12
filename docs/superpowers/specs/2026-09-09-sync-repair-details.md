# Bookmark and research transport repair decisions — R15–R17

Implementation authority: approved review remediation plan Task6. Research enrollment/upload remains default-off; all acceptance uses synthetic data and emulator transport. EvidenceContext and EventEnvelopeV2 remain frozen.

## R15: local bookmark identity

At `_applySavedLearningItem`, find an existing row by owner/content natural identity first and preserve its local ID. A new restored row receives a stable namespaced hash of the encoded array `[ownerId, wireEntityId]`. Do not change the owner-independent wire identity or conflate local IDs between owners. Existing claim code maps local to wire IDs; verify acknowledgments and tombstones still resolve correctly. No migration is required.

Test two-owner restore of identical content, repeated pull, legacy local IDs, unsave/push/ack, owner merge, deletion and export.

## R16: durable withdrawal intent

Inside the existing consent withdrawal transaction, insert one idempotent `researchWithdrawal` outbox intent for each existing permit, even offline or with rollout disabled. No permit means no intent. Payload remains `{permitId, ownerId}`, revision1, using the existing canonical operation ID formula. Factor an identity helper into domain code if needed to avoid consent depending on transport implementation. Preserve existing retry/ack state.

Claim an exact durable denial operation by owner, permit, kind, payload/version and operation identity independently of mutable current consent. Keep legacy backfill from withdrawn consent/run when available. Reaccepting must not erase denial intent or mark the newly accepted consent withdrawn. Do not forge permit revocation, weaken permit validation or invent evidence for old withdrawals whose complete history was already erased before enqueue.

Test withdrawal before enqueue, after enqueue, with/without run, reaccept, restart/offline, ack loss, repeat withdrawal, newer permit ID and owner switch; two synthetic devices should observe denial. Existing denial-priority barriers remain.

## R17: historical session proof

Both opportunities and mission events require authentic session authority. Answer pull placeholders lack session times/state; zero-answer sessions have no answer placeholder. Pair purpose additionally requires a validated initial checkpoint/configuration and owner lineage. Accepting arbitrary mission timestamps or answer placeholders is prohibited.

Introduce a versioned bounded research session-proof transport referencing the existing canonical learning session: owner/session identity, activity, start/end/state, app/build pins, and accepted configuration identity/serialization. A Pair proof includes immutable initial checkpoint revision1/start operation/purpose/configuration. On the source, validate the full local checkpoint prefix using the existing Pair purpose decoder. Never transport the full potentially multi-megabyte checkpoint history or create a second learning authority.

Authenticate same-UID server provenance and current permit/signature/revision/revocation/consent/protocol/instrument pins at collection and upload/pull boundaries. Reject contradictory proofs, placeholder conflicts and cross-owner lineage. Transport order is permit → run → session proof → opportunity → neutral events; proof cannot depend on an opportunity and create a cycle. Preserve retry/cursor behavior for incomplete dependencies and support legacy transport explicitly.

Store imported proof as a historical mirror rather than hydrating a resumable canonical session with only its first checkpoint. It must not create resumable lessons, answer attempts, SRS/reward effects or reward authority. If a new owner-scoped mirror table is necessary, reserve the next version after Task4 (expected26, verify first) and include migration, merge, export, deletion and rules/policy coverage. Runtime and rules transport revisions must agree; no deployment is authorized.

Exact contract keys, table/index identities and proof revision semantics must be recorded after inspecting serializer limits and local session revisions, before schema/contract edits. Changes are limited to restoring the authority already required by the existing research gates.

### Resolved proof contract and migration map

Read-only design verified that `MeasurementOpportunities.learningSessionId` currently has both a FK to LearningSessions and owner triggers. A mirror table alone cannot restore opportunities. Rebuild opportunities without that specific FK and replace it with an owner-scoped guard accepting either the existing canonical session or a live proof with matching owner/run/permit/session. Keep all other FKs, checks, indexes and old rows. Install corresponding parent mutation/deletion guards so removing the sole authority cannot orphan an opportunity. Fresh install and upgrade must install the same guards.

Add `ResearchSessionProofs` to the existing research tables file, using `ResearchOwnedRecord` delivery/tombstone metadata. Columns: id, ownerId, measurementRunId (run FK), permitId (permit FK), learningSessionId (text without learning-session FK), proofRevision, activityType, sessionState, startedAtUtcMs, endedAtUtcMs nullable, appVersion, buildId, sessionConfigurationIdentity, sessionConfigurationJson, pairStartOperation nullable, pairCheckpointEventVersion nullable, pairOwnerLineageJson nullable. Unique owner/run/permit/session/proofRevision. Canonical fields immutable; only delivery/tombstone metadata may change. Revision1 requires active/null end, revision2 completed/end>=start. Pair fields are all present only for matching. SQL guards require matching owner/run/permit.

Use immutable phase documents because LearningSessions has no source revision and the outbox does not retain changing payload snapshots. `proofRevision=1` represents started facts; `2` completed facts including the same immutable start core. Each document uses wire revision1. ID is `research-session-proof:` plus SHA256 of encoded `[ownerId, permitId, measurementRunId, learningSessionId, proofRevision]`. Completed-first is valid; later Started must match its core and cannot downgrade it. Client update time is start for phase1 and end for phase2. Same ID/different fact is a conflict, not last-write-wins.

Persist required `permitPayloadSha256` (strict64lowercasehex text, NUL-safe) and `permitRevision` (strict positive integer) on each proof as well. These immutable source pins are distinct from delivery localRevision/cloudRevision. Include them in insert/decode/snapshot and immutable update guards. A proof snapshot must not use the adapter's generic current-permit header overlay: later permit renewal must preserve the original proof bytes, identity and outbox fingerprint. Parent renewal is allowed without rewriting stored proof pins; current permit authentication/revocation/revision is still checked separately through the existing historical-reference/provenance policy. A later phase with contradictory start-core permit pins fails closed; never rewrite an older phase to match a new permit. Add persisted snapshot stability and parent-renewal acceptance before migration closure.

Collection: `SyncCollection.researchSessionProofs`, wire name `research_session_proofs`, entity type `researchSessionProof`, payloadVersion1. Exact keys:

```
schema id ownerId measurementRunId learningSessionId proofRevision
activityType sessionState startedAtUtcMs endedAtUtcMs appVersion buildId
sessionConfigurationIdentity sessionConfigurationJson pairStartOperation
pairCheckpointEventVersion pairOwnerLineage
permitId permitPayloadSha256 permitRevision
```

Schema string `lexiquest.research-session-proof.v1`. Bound this collection to131072 UTF-8 bytes, configuration JSON16384 bytes and reconstructed initial Pair state65536 bytes; retain16384-byte limits for existing research collections. Reuse strict configuration/start serializers and reject unknown keys. Do not increase global payload limits.

Source-compatible configuration clarification: both sessionConfigurationIdentity and sessionConfigurationJson keys are required, but their values and mirror columns may be jointly null for an authentic unconfigured canonical session. Reject only-one-null and validate exact existing identity/serialization when present; never invent a configuration for legacy history. Pair initial purpose/start validation remains mandatory and its projected optional configuration must equal the canonical/proof pair, including joint null. This preserves the existing PairMatchingSessionPurpose.authorizeSnapshot contract; it does not bypass permit/protocol checks or authorize a configuration absent from required study policy.

Compact Pair fields: exact `PairMatchingStartOperation.stableSerialization`, actual initial checkpoint eventVersion1/2, and sorted lineage array of at most current owner plus initial plan actor. Each lineage entry contains only ownerId/createdAtUtcMs/upgradedAtUtcMs/mergedIntoOwnerId. Current owner has no merge destination; historical actor must point to it. Never include Firebase UID, name or other PII.

Source validation reads the full checkpoint prefix via tracked reads, requires `PairMatchingSessionPurpose.decode().allowsLearningAuthority`, verifies exact revision1 initial state from the decoded start operation, and compares `projectConfigurationOwner()` identity/serialization against canonical session. Receiver reconstructs the initial checkpoint and owner projections only in memory with the existing pure initial-state/key/time serializers, then uses the same purpose decoder. Do not insert imported lineage, checkpoint, session or session configuration rows. Same-UID server provenance bound to the full payload plus valid current permit remains the trust boundary, not a new invented session signature.

New focused files, after checking for equivalents: `lib/features/research/domain/research_session_proof.dart` for strict codec/core comparison/pure session projection and Pair validation; `lib/features/research/data/drift_research_session_proof_repository.dart` for bounded preparation from existing accepted opportunities and atomic proof/outbox insertion. Do not scan all sessions or generate proofs for nonparticipants.

Approved pure codec API for maintained tests: immutable `ResearchSessionProof.decode(Map<String,Object?> payload)`, `fromCanonicalSnapshot({required ownerId, required permitId, required permitPayloadSha256, required permitRevision, required measurementRunId, required proofRevision, required Map<String,Object?> session, List<Map<String,Object?>> checkpoints = const [], List<Map<String,Object?>> historicalOwners = const []})`, `toJson()`, named-argument `identityFor({ownerId,permitId,measurementRunId,learningSessionId,proofRevision})`, `hasSameStartCore(ResearchSessionProof other)` and `toSessionProjection()`. Use a private validating constructor and immutable nested values. Sibling core comparison includes permit digest/revision, excludes only phase identity/state/end; contradictory current permit metadata must not be silently accepted. Decode validates internal consistency only, never trusted provenance or participant authority. The projection is an in-memory SQLite-shaped map, never a draft or insertion command. Source validation uses the complete existing Pair prefix; receiving reconstruction uses existing serializers/decoder and must prove compatibility for both active and completed phase facts without inventing terminal checkpoint history. Maintained pure tests belong in the new `test/features/research/research_session_proof_test.dart` after checking absence. See task-6-proof-codec-preparation.md for existing API/row-shape details.

Source phase projection clarification: a completed canonical session may supply its earlier Started phase, but validate the actual completed source and full checkpoint prefix before projecting active/null-end facts. Never project first and validate a truncated prefix. Compact lineage contains at most current owner and initial actor, even when source reads include unrelated owners. Preserve the immutable original actor/start operation and use the existing configuration owner projection for merged history; unconfigured schema1 starts remain supported where the existing decoder authorizes them.

The same Started derivation is supported for an authentic canonical `abandoned` session, including the nullable end produced by the existing learning repository. Validate the actual abandoned source and full Pair prefix first; it cannot supply Completed. Wire phase states remain active/null-end and completed/end only. This preserves the existing started-mission authority without inventing a new canonical or wire state.

Source phases require canonical session plus full local Pair prefix. Pull-only `_sessionAuthority(owner,run,permit,sessionId,phase,trackedReads)` can use the admitted mirror; capture use cases and enqueue/push of new events cannot use mirror fallback. Both `_opportunity` and `_event` consume the same helper. A real canonical conflict denies; an owner-matching `syncedEvidence` placeholder without times/config is not contradictory authority and remains untouched. Track missing and present proof phases/session rows/prefix/lineage across async receipt validation so races deny.

Preparation may consult source opportunity linkage, but pull proof depends only on run/permit: permit → run → response/proof → opportunity → event. Missing proof is retriable with existing page/cursor rollback; bad proof fails closed with bounded metadata, never raw Pair payload logs. Legacy Presented/session-free evidence remains compatible; legacy missions on a fresh device await source backfill rather than deriving authority from answers. Update local-emulator rules revision only; do not deploy.

Additional integration files: `lib/data/local/research_schema_guards.dart`, app database/generated source, `owner_lifecycle_manifest.dart`, owner upgrade `_requireNoPinnedResearchRows()` guard, `research_lifecycle_export_reader.dart`, consent suppression, sync adapter/store/entity/engine/gateway and Firestore rules. Export aliases, phase/activity/state/times/config identity/purpose, never raw start/lineage. Deletion order: opportunities → proofs → runs/permits → owner. Do not rewrite pinned proof owner/lineage during upgrade; use existing research quarantine/fence policy. Withdrawal suppresses pending uploads without deleting historical facts.

Additional tests: migration orphan guards with either parent kind, no learning/reward/resume mutations after proof-only restore, completed-before-start, lost phase1 ack while phase2 is prepared, sibling conflicts, tampered initial purpose/config/actor/time/app/build/lineage, corrupt source later prefix, oversized/unknown/full-history payload, source/proof/owner races during awaited receipts, proof-only owner export/delete/upgrade fence.

## Required acceptance

### Reserved schema26 implementation identities

After StageA closed with1296tests and independent10-file review, root verified the
current25/48 inventory and reserved26/49. StageB1 follows the separately reviewed
migration mechanics. New named indexes are
`research_session_proofs_owner_phase_v26` (unique owner/run/permit/session/phase,
without a duplicate anonymous unique constraint) and
`measurement_opportunities_session_authority_v26` (owner/session/run/permit,
partial on nonnull session). Retire the old opportunity owner insert/update
triggers and the run/permit `referenced_pins_v24_update` triggers explicitly.

Install `measurement_opportunities_owner_v26_insert/update`,
`motivation_measurement_runs_referenced_pins_v26_update`,
`research_participation_permits_referenced_pins_v26_update`,
`research_session_proofs_owner_v26_insert/update`,
`research_session_proofs_immutable_v26_update`,
`research_session_proofs_sibling_core_v26_insert`,
`research_session_proofs_last_authority_v26_delete/update`, and
`learning_sessions_last_authority_v26_delete`. Preserve strict receipts and the
existing assignment/session pin update guards. Protect tombstoned opportunities
too; a tombstoned sibling is not live authority, and a deleting proof must not
authorize itself. Sibling immutable core includes tombstoned phases. Keep
restrictive proof run/permit FKs and the original opportunity run cascade.

During the opportunity rebuild, the unchanged
`learning_sessions_referenced_pins_v24_update` may be temporarily dropped and
reinstalled inside the same migration transaction so its reference does not make
the DROP/rename gap invalid. Its exact semantics and definition must be present
at commit. The four retired names above are the permanently superseded guards;
temporary removal is not permission to weaken the retained parent defense.

The B1 schema checkpoint may register the manifest alias and physical deletion
order with the existing count-only archive fallback. This is an intermediate
implementation boundary, not completion of proof export. Full allowlisted export,
upgrade fencing, withdrawal suppression and transport are mandatory in the later
StageB gate. New maintained migration/helper paths are
`test/database/migration_v25_to_v26_test.dart` and
`test/support/schema_v25_fixture.dart`; use frozen actual25 table/guard/index DDL
from the pre-reservation capture layered on the existing raw24 fixture chain.

### Full transport acceptance

### Source preparation protocol (B2)

The independently reviewed `task-6-stage-b-source-preparation-brief.md` and
`task-6-stage-b-source-design-review.md` select a repository constructor receiving
database, required rollout, nullable `authorizeCandidate` using the existing
`ResearchSyncAuthorizer` request type, and required `nowUtc`. Its
`prepareForOwner(ownerId, firebaseUid, ownerGateToken, limit)` derives candidates
only from persisted accepted opportunity links and complete canonical source;
there is no caller-supplied session/proof or per-call approval parameter.

The adapter privately composes admission through its existing `allowed` path,
including local pre/post checks and its real external authorizer once. Do not
call the raw authorizer directly and lose the adapter's latest-consent-across-
versions rule. A missing original authorizer remains null, and disabled rollout
returns before candidate discovery. A proof-specific missing-row enqueue branch
must reconstruct exact canonical source; do not relax `_existing` globally or
insert provisional proof rows before authorization. Pull remains independent of
local opportunity existence. The repository rechecks the complete deterministic
source/consent/lineage/sibling/outbox read set and fresh owner/token/fence/time
after awaits, then inserts proof and exact outbox atomically in the caller's
existing transaction without another lease. Candidate count and insertions share
the existing bounded budget. Ordinary learning/reward tables receive no writes.

Add optional `researchNowUtc` to store→adapter composition with a real UTC clock
default; bootstrap passes the existing `runtimeFeatureNowUtc`, and the repository
uses that same function. Never replace post-await checks with the original request
timestamp. Fixtures inject coherent clocks and test time-only expiry/backwards
time as well as a newer consent-version withdrawal before/during admission.

Known renewal boundary: a new phase uses the current authenticated permit pins.
If those conflict with a stored sibling, defer that phase without rewriting old
bytes, outbox identity or ACK/retry metadata. Current historical-reference policy
authorizes old-pin pull, not arbitrary new outbound writes. Thus pending old-pin
delivery or a new Completed phase spanning renewal is not guaranteed by this
repair. Supporting that additional case requires a coordinated historical-write
client/server admission contract; do not invent trust or silently widen policy.

### Personal proof lifecycle export (B3)

The proof archive uses the existing allowlisted personal-export authority. Its
summary exposes only `recordCount`; each validated detail has exactly
`proofAlias`, `sessionAlias`, `runAlias`, `permitAlias`, `proofRevision`,
`activityType`, `sessionState`, `startedAtUtc`, `endedAtUtc`, `appVersion`,
`buildId`, `sessionConfigurationIdentity`, `purpose`, and `isDeleted`.
Deterministic local ordinal aliases `research-proof-N` and `research-session-N`
link phases without exporting raw IDs; reuse existing run/permit aliases. Both
phases of one session share its alias. The configuration identity is the existing
validated content identity, never raw configuration JSON. `purpose` is `learning`
only for matching proofs that pass the actual strict codec/purpose validation;
it is null for other activities. Malformed matching evidence fails export as
unavailable instead of inferring purpose from its activity label. Do not expose
raw session/owner IDs, Pair start data/lineage, permit digests or signatures.

Include personally owned tombstoned and revoked history. Physical deletion keeps
opportunities before proofs before restrictive parents and must roll back on a
late failure. Withdrawal supersedes scoped non-acknowledged proof uploads while
preserving immutable history, existing ACK metadata, denial intents, other owners
and ordinary learning. Owner upgrade retains the existing explicit reenrollment
policy for pinned research history, including proof-only histories.

### End-to-end transport gate

Real source DB → serialized gateway transport → fresh receiving DB, Started before first answer, Completed and zero-answer sessions, Pair learning/replay purpose, owner lineage and conflict rejection, proof revisions/order/cursor/retry, revoked/expired/tampered permit, withdrawal and export/deletion, nonparticipant no rows/outbox, no learning/reward mutation on proof restore. The old isolated `mission_single_test.dart` must not be made green by trusting its unauthoritative placeholder; strengthen it with authentic transported proof.
# B2 bounded exact-intent selection refinement (2026-09-10)

B3 server lifecycle clarification: a trusted-server tombstoned proof or sibling prevents a new other-phase write. Client proof update/delete remain forbidden, and immutable core comparisons still include all original permit pins. This fail-closed tombstone policy matches source preparation's live-sibling requirement; it does not reinterpret tombstone metadata as part of the immutable codec core. Parent-first run admission is required before the proof batch. Actual emulator coverage must include compatible and conflicting four-write phase/operation batches for adult and minor receipt authority, plus sorted two-row lineage and individual UTF-8 bounds. Server shape validation is not canonical gameplay evidence; source and receiver semantic checks remain mandatory.

The first implementation's SQL excluded any same-entity outbox intent before the exact Dart payload fingerprint could be checked. Maintained integrity testing reproduced the lost-repair case (10 pass, 1 failure). SQLite connections do not provide the application's canonical JSON/SHA-256 function. Replace that exclusion with a durable LOCAL keyset hint in existing `sync_checkpoints`, private collection name `local:research-session-proof-preparation:v1`. This namespace is never a wire collection or server cursor; keep `last_success_at_utc_ms` null. Existing aggregate export, owner deletion and cursor-clearing upgrade coverage applies. No schema or authority contract changes.

Decode a small versioned token strictly; malformed scheduling state restarts the scan and grants no authority. Inspect at most the caller's remaining limit (1..50) phase rows in deterministic opportunity/phase order, with at most one wrap and no duplicate phase in the same invocation. A finite cycle upper key prevents continuously appended opportunities from postponing older completion phases forever. Existing exact pending/retry/in-flight/ACK intents are compared by the real Dart fingerprint and retain all bytes and metadata. Their source still passes the existing composed authorization before advancing the local hint. A different operation ID does not satisfy an exact intent.

Persist the hint only after a successfully authorized phase, under unchanged source/current owner/UID/gate/fence/consent, atomically with any new proof/outbox. Off, null authority, no accepted source, wholly denied windows and ordinary nonparticipants create no hint. Storage failures roll back all three. A fully denied first window may still delay later candidates, as the original bounded design explicitly allowed; do not introduce separate authority to move past that limitation. Calls may inspect acknowledged work and insert zero rows, but valid finite histories progress across repository/process restarts. Wrapping must revisit later canonical completion and newly inserted lower keys.

Also track assignment quarantine rows from `sync_conflicts` in the complete source read set. Catch only expected source-format validation failures around candidate discovery/revalidation; unexpected SQL, executor and clock callback errors propagate. Keep the existing external-authority fail-closed wrapper unchanged. Root owns all toolchains; independent review and focused regressions precede the receiving slice.

B3 final review refinement: an incoming proof with the same ID as a retained local tombstone must still match the full immutable payload before being ignored. Exact deleted-history replay remains a no-op without resurrection or delivery/ACK mutation; changed immutable facts must reject and roll back the page cursor. Preserve the existing current-authority requirements for fresh/live admission. Add the actual gateway receiver regression before the minimal comparison-order repair.
