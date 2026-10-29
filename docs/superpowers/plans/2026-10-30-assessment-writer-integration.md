# Assessment writer and paired comparison

2026-10-30. Execution plan under the user's approved remaining-system request. Grounded at verified application source `853d4c13` and attestation `3810b265` in the existing cycle12-release worktree. Current executable schema is v17/34; v18 is reserved separately in the ledger before migration implementation. No production enrollment, upload or deployment is authorized.

## Preserve the approved flow and separate the instruments

The original approved master plan at `b9184e8a:docs/superpowers/plans/2026-08-14-alltcas-8-44-capability-implementation-master-plan.md`, Flow D and f28, states this order:

`enrollment → versioned consent → stable assignment → pinned pre-assessment → versioned learning intervention → pinned post-assessment → comparison/export`.

Its f28 entry assigns the screen to `AssessmentUseCases`, with f42 showing only an assigned Assessment action. Pre-assessment must not teach the content, expose answers, or grant rewards. The archived actual caller is `lib/screens/main_navigation_screen.dart::_openTodayAssessment`, which opens `PrePostAssessmentScreen` from an assigned run. The archived Quiz routes to Score without an automatic Assessment interception.

The separate 2026-09-05 Research plan requires Motivation baseline before first treatment exposure and Motivation post within 30 minutes of the first canonical index completion. The current Study flow additionally offers Motivation post before Score. Neither source fixes Assessment's position relative to the Motivation forms or Score. Preserve these partial orders. Do not invent Assessment timing windows, replace Motivation scores, or claim an approved Assessment-before-Score requirement. The concrete UI composition must state its chosen order and verify pre-before-intervention and post-after-intervention while retaining ordinary continuation.

## Add one local table with the complete original pins

Create `assessment_runs`, using the existing `AssessmentRun` model and canonical `learning_sessions` and `answer_attempts`. Add no Assessment response, score, reward, sync, or cycle table for this unit. With the single new table, the expected inventory becomes 35 after a separately reserved v18 migration.

The current model has 30 fields. Persist those fields unchanged:

- Identity and state are `id`, `owner_id`, `learning_session_id`, `study_cycle_id`, `phase`, and `state`.
- Study pins are `protocol_id`, `protocol_version`, `experiment_id`, `experiment_version`, `assignment_id`, and `cohort`.
- Consent pins are `consent_version` and `consent_decided_at_utc_ms`.
- Instrument pins are `instrument_id`, `instrument_version`, `form_id`, `form_version`, `instrument_checksum_sha256`, and `form_checksum_sha256`.
- Build and contract pins are `app_version`, `build_id`, `database_schema_version`, `content_revision`, `evidence_policy_version`, `feature_contract_revision`, and `feature_contract_hash`.
- Times are `started_at_utc_ms`, `completed_at_utc_ms`, and `abandoned_at_utc_ms`.

Add seven durable provenance fields. A restarted process must not reinterpret a stored run through replacement configuration:

| New field | Required source and meaning |
| --- | --- |
| `assignment_revision` | Exact positive integer from the configured R1 requirements and verified operation permit. |
| `protocol_revision` | Exact positive R1 protocol revision. This is distinct from the string protocol version. |
| `instrument_revision` | Exact positive R1 instrument revision. Never parse the string instrument version. |
| `form_content_revision` | Exact positive revision requested from `AssessmentFormContentAuthority`. |
| `participation_permit_id` | Exact original R2 permit identity. |
| `participation_permit_revision` | Original matching local/cloud signed R2 revision. |
| `participation_permit_payload_sha256` | Original verified canonical R2 payload hash. |

The minimum run therefore has 37 fields. The two existing content hashes already supply instrument/form SHA-256; do not add duplicate content-hash columns. Extend constructor validation, equality/hash, terminal copying, row codec, exact retries, and comparison compatibility together.

Use real foreign keys to `local_owners.id`, `learning_sessions.id`, `experiment_assignments.id`, and `research_participation_permits.id`. Use the existing R3 run FK for `study_cycle_id` as specified below. Enforce the matching owner and all original pins in the writer. Keep unique `learning_session_id` and unique `(owner_id, study_cycle_id, phase)`. Validate phase/state, positive revisions, lowercase hashes, UTC milliseconds, consent-before-start, and exclusive terminal timestamps. A terminal run can only replay its exact state/time. Its original pins cannot change.

## Bind the pair to the actual intervention

There is no generic cycle table. For the minimum current Study composition, make `study_cycle_id` reference the existing R3 `motivation_measurement_runs.id`. This uses the real configured cycle as an intervention anchor, not its Motivation instrument or scores as Assessment authority. Do not create a synthetic or substitute Motivation run when the cycle is absent. Missing configuration leaves Assessment unavailable and ordinary learning available.

Add a typed `AssessmentCycleReader` with a data adapter over the existing strict R3 timing/opportunity proof. It resolves an exact owner/cycle ID and checks shared protocol/assignment revisions, cohort, and original participation ID/hash. The R3 cycle's own Motivation instrument pins remain separate from the Assessment instrument pins; never equate their revision numbers. Pre proof requires no opportunity row for that exact cycle and no index. A persisted unpresented opening can already have rendered and is unknown, not proof of no exposure. Reject that state, any pending change, or ambiguity. Post proof requires the one exact first Presented opportunity, its original canonical first index ID/accepted plan/start, and actual completed state/end. An abandoned or incomplete first index cannot be replaced by a later completed session.

Repeat the phase-specific read at start, response, and new completion boundaries after authority awaits. The Assessment run's own `learning_session_id` is only its answer container, never the intervention index. Do not resolve an intervention from global owner/time queries, a matching arbitrary string, or the latest session. At paired read, require pre completion no later than the first Presented/Started and post start no earlier than that index's original canonical end. Verify the original events, pending state, and first-index identity again. An exact terminal ACK replay creates no new capture and must preserve its original times.

The existing R3 parent and immutable first-opportunity/index contract make 37 run fields sufficient for this explicit composition. The FK and strict reader are essential. If a later scope requires independent non-R3 cycle IDs, 37 fields with a free-text cycle ID are insufficient. That scope needs a typed immutable cycle authority and durable cycle/intervention identity pins before schema reservation. Do not silently treat its current configuration as the original run binding.

## Supply Assessment authority without constructing Motivation authority

Reuse `ResearchAuthorityScope` for the authenticated binding. It already contains owner, Firebase subject, auth generation, exact `ResearchPermitRequirements`, protocol version, and consent version. Supply an explicit allowlisted mapping from its numeric instrument revision to the catalog's string instrument/form versions, both content hashes, and `formContentRevision`. This mapping is configuration input, not a guessed conversion or an approval inferred from a catalog label.

Add this narrow port in the Assessment domain:

```dart
abstract interface class AssessmentAuthority {
  Future<AssessmentAuthorityReceipt> requireCurrent({
    required ResearchAuthorityScope expectedScope,
    required AssessmentInstrumentDefinition definition,
    required String expectedParticipationPermitId,
    AssessmentRun? pinnedRun,
  });
}
```

The concrete `DriftAssessmentAuthority` factory returns a private verified receipt implementation after all checks. Its public read shape contains the exact scope, assignment, consent decision time, `AuthorizedResearchOperation`, original P256 permit identity/revision/hash, and trusted evaluation/deadline. The receipt is a completed check's snapshot, never continuing permission. Missing authority or an ambiguous participation identity denies capture. A supplied cycle configuration cannot override persisted pins on restart.

R1 and R2 prove different things. `SignedPermitResearchOperationAuthorizer` with the real Ed25519 verifier checks collect permission, current state/revision/revocation, issuer/key/algorithm, owner, assignment revision, protocol revision, and Assessment instrument ID/revision. A current R1 permission lease can renew while these exact semantic pins remain unchanged. P256 participation pins owner, assignment, assigned treatment, protocol ID/version, consent/guardian/assent receipt references, and its signed revision. It does not pin an Assessment instrument. Verify the full P256 document and active receipts with the existing validators, then require its original stored ID/revision/payload hash for an existing run.

Use the five existing local authority ports/cache with explicit Assessment scope. Do not manufacture a `MotivationStudyProtocol` or `MotivationInstrument` to access the current Motivation-specific admission binding. A separate cache instance can hold a different explicit instrument scope. Gateway refresh remains outside SQLite transactions; all collection-time reads remain local. The external CURRENT-state/freshness gateway and approved issuer/artifact mapping remain real dependencies.

Perform content-authority access and exact identity/hash/byte verification before the owner transaction. After every content or authority await, recheck scope/generation and the original pins. Under `DriftOwnerWriteCoordinator`, inspect fresh active owner/UID, deletion fence, local consent version/decision/withdrawal, assignment, R1 state, R2 document/receipts, and monotonic trusted time. Recheck after mutation, then inspect actual run/session/cycle DB state before the final owner/consent/time and synchronous visible-binding guard. Reuse the current final DB-inspection ordering; do not put a new gateway await after that inspection or add authorization loops.

## Keep all writes inside the dedicated Assessment repository

Adapt the archived `DriftAssessmentRepository`, `AssessmentUseCases`, and `AssessmentComparison` algorithms, not their transport or ordinary-writer wiring. The archive calls `LearningUseCases.resolveEvidenceForRecording` and `recordResolvedEvidence`, creates Assessment outbox operations, and supports remote snapshots. Omit those paths here. Current `LearningEvidenceContract.validAttempt` and ordinary sync admission must continue rejecting Assessment.

The data repository owns atomic session/run start, controlled answer insert, completion, abandonment, and replay. The application use case receives only an item ID and a bounded controlled option. It obtains correctness and response code from the exact verified catalog. The screen supplies neither correctness nor a score. Use a small dedicated `recordResponse` repository port rather than routing SQL through application code or reopening the ordinary learning gateway.

Create the Assessment session and run together. Require `activity_type = assessment`, active owner, exact run/session identity, and no accepted quiz plan/checkpoint. Reuse canonical `answer_attempts` with strict Assessment EvidenceContext, hint level zero, enforced rollout, engagement false, exact item/scoring/context pins, non-null bounded latency, and trusted UTC milliseconds. Each catalog word must be an existing non-deleted word owned by that participant; reject foreign or missing vocabulary rather than creating or aliasing words from an instrument. No raw submitted text is stored.

Use deterministic response identity over a canonical JSON tuple of run/item IDs, or explicitly validate the archived delimiter format before reuse. The archived pipe-joined helper must not admit ambiguous IDs. In the same owner transaction, reject a second identity/changed response for an answered item and globally colliding source IDs. Exact replay preserves original code, correctness, latency, occurrence, and context. Completion requires exactly one valid response for every pinned item, fresh authority, and terminal time at least the latest response time. Derive only the Assessment session's aggregate counts/score. Invoke no ordinary projections, learning lifecycle observer, event adapter, time-controller hooks, Quest, Streak, reward, or outbox code.

Expose existing `AssessmentPresentation` and score-free `AssessmentSubmissionReceipt` to UI. Keep correctness and response codes internal. Use the canonical item order and sorted response-key order already bound by form bytes. Preserve a pending command's exact identity/time across lost ACK; a retry cannot capture a new occurrence or replace a response.

## Return three precise paired-read states

Reuse `AssessmentComparisonReady`, `AssessmentComparisonMissingPair`, and `AssessmentComparisonIncompatibleMetadata` from the archived comparison shape. Missing pair means one completed pre and one completed post do not exist. Incompatible means the pair or its evidence cannot be proven. Ready returns each run's sample size, correct/incorrect counts, accuracy, and their count/accuracy deltas. It is a descriptive pair, not evidence of efficacy.

Require one pre and one post for the same owner/cycle; match all shared original study, consent, R1/R2, instrument/form/content, build/schema, and feature-contract pins. Run/session IDs, phase/state, and run times differ by design. Require `pre.completedAt <= post.startedAt <= post.completedAt <= comparedAt`. Reject missing, duplicate, extra, foreign, malformed, out-of-run, incorrectly scored, or mismatched-item evidence. Validate every catalog item and strict DTO shape again. Missing scores remain unavailable, never zero. Motivation scores and ordinary Progress stay separate.

## Bound the implementation and acceptance set

Core files are the three existing Assessment domain files, proposed `assessment_authority.dart` including the cycle-read port, proposed `data/drift_assessment_authority.dart`, `data/drift_assessment_repository.dart`, and application `assessment_use_cases.dart` and `assessment_comparison.dart`. The data adapter owns the R3 cycle-read implementation. Add scoped authority/repository/use-case/comparison tests and keep the existing 33-case isolation component intact.

Root owns the later ledger reservation, `research_tables.dart`, AppDatabase/generated source, genuine populated-v17 fixture/migration, inventory, export/purge, and integration. Add `assessment_runs` to `ownerUpgradeInventory` and the signed-research source-transfer guard in `drift_owner_upgrade_repository.dart`. Personal full export derives scopes from that inventory. Reverse purge must remove Assessment runs before their session/assignment/permit parents. Cover both owners, foreign-key checks, reopen, deletion-core proof, and rejection of signed-source rehome.

Do not add a SyncCollection, an Assessment outbox type, cloud policy, or automatic upload here. Applicable sync tests prove zero Assessment outbox and continued rejection through ordinary attempt payloads, including alias/SRS and legacy-credit laundering cases. A later real Research upload implementation must independently gate these facts and withdrawal before any rollout claim.

After core acceptance, implement `pre_post_assessment_screen.dart` and its scoped tests. Add an explicit nullable assigned caller in the current runtime/dependencies/entry. For the R3 composition, the `StudyRuntime`/`LocalStudyRuntime`/`StudyHost` boundary must not prepare/render the treatment before the assigned pre is completed or the participant exits that Research flow. Post uses the exact completed first-index proof. Preserve existing Motivation boundaries and ordinary Score behavior until the concrete caller plan explicitly defines their relative placement. Reuse current accepted-quiz APIs unchanged. Owner watch completion/error, null route, hidden/paused/disposed/expired binding, withdrawal, failed authority, and process restart must never reveal answers or create replacement evidence. Test Thai/English, narrow width, 200% text, semantics, and actual repository-backed flow. No enabled default or synthetic approved instrument is shipped.

Acceptance requires synthetic real Ed/P256 positive and negative paths; owner/UID/auth-ABA/fence/consent/receipt/expiry/revocation races; config rotation after restart; exact start/response/terminal retries and collisions; complete and incompatible pairs; byte-identical ordinary answer/SRS/XP/coin/Quest/Streak/achievement/outbox effects; populated migration, owner export/purge/rehome and default-off/nonparticipant zero writes. Run focused RED/GREEN first, then frozen integration/full regression/analysis/build at the root checkpoint.

The domain/projection foundation is verified separately; concrete writer and UI acceptance below is still required. This plan does not complete f28. Writer, paired comparison, actual UI caller, owner lifecycle, and collection/upload gates remain engineering work. The 8/44 catalog is unchanged; no Research efficacy, production readiness, enrollment, or deployment permission is inferred.


## Execution cards and current boundaries

1. Domain owner: extend all37 original pins, owner-explicit repository operations and opaque authority/cycle snapshots. Remove the unused arbitrary response callback. Domain98 plus isolation11 and cache-generation1 checks pass; this is not a writer result.
2. Authority data owner: implement the two read adapters with real Ed/P256 checks, exact scope/mapping, original consent identity, required receipt expiry caps and the current cache read generation. `inspectReceipt` is verified metadata only; all ordinary authority checks remain required.
3. Root: reserve v18, capture genuine v17 before bump, add one37-field `assessment_runs` table and35-table owner lifecycle. Preserve every old row, quiz checkpoint, pending exposure and deletion intent; run populated migration/export/purge/rehome checks.
4. Data writer owner: implement the sole SQL writer and exact replay; derived trusted mutation times, no caller clocks. Start accepts `AssessmentStartCommand`; response accepts only controlled option and bounded latency. No ordinary hooks or Research outbox.
5. Application owner: derive a score-free presentation and three-state descriptive comparison. Shared `assessmentResponseIdentity` is SHA-256 of canonical UTF-8 JSON `[runId,itemId]`, prefixed `assessment-response:`. The final owner/active-phase read occurs after content awaits and returns the original run plus current verification/deadline metadata. UI receives no continuing grant. Comparison uses the existing trusted-time port, not a caller wall clock.
6. UI/root: wire an explicit assigned route, real owner/lifecycle/route/expiry guards, pre-before-intervention and post-after-exact-index. Retain the approved partial order relative to Motivation and ordinary Score. Then freeze source for full integration/analysis/build and independent review.

`AssessmentPresentation` also carries current verified/deadline UTC dates so the UI can hide expired items. These are transient read metadata, not database columns or collection authority. Every mutation still requires fresh local authority and a final synchronous visible-binding guard.
