# Engineering Spec v3 reconciliation — POST-G83-E0-E1

2026-09-20. Reviewable analysis/design, not feature implementation or release acceptance. Actual task `01a0bb5d-3c67-7032-bd26-2b49715321e5`; branch `lexiquest/post-g83-e0-e1`. Single documentation writer; no subagents. Standard/default requested; effective tier unverified.

## 1. Authority and baseline (E0)

The authorized route is accepted G8.3 → E0/E1 reconciliation. Route A is the proposed later delivery sequence: authorized feature slices → integrated review/freeze → G8.4–G8.9. This report does not authorize feature implementation, create tasks, or dispatch B19. The [boundary copy](post-g83-v3-boundary.json) preserves the exact controlling instruction. Obsolete `nextBundle` and continuation pointers cannot grant implementation scope.

Accepted source is `09a4d747903b1624e80fea8b1f9b605830858ebc`; reviewed application source is `47507d93df06a68353ab38f61c6514aa57bda013`. The fresh worktree originally contained clean `7b8ac6cc029c0df43f9d4e7d161da3502e6f557b`; it was safely switched to the accepted commit. Common Git directory is `C:/Users/Phet/Documents/LexiQuest/.git`. Writer claim was OS-exclusive lock/CAS 220→221, documentation only, `applicationSourceWritesAllowed=false`.

The [accepted receipt](../full-system/evidence/bundles/B18/G8.3-acceptance.json) closes 69 known findings, with zero known unresolved in-scope functional defects. All 99 handoff evidence pins and 202 approved source delta pins matched. The final freeze has 3,657 files: 3,610 original plus 47 new, including 155 modified original files and three policy amendments. Approved current hashes supersede historical hashes. Fresh checkout caused 236 EOL-only differences: normalized equality and exact accepted Git-blob SHA-256 were proved before restoring exact bytes; no semantic source changes. See [baseline verification](baseline-verification.json).

Inherited evidence: 480 tests/21 targets in two bounded verifier runs, each with 3,780 equal pre/post inputs; prior acceptance records verification of 15 manifests/3,695 artifacts. This task checks pins and source, and does not repeat those test runs or re-audit 1,429 observations. Test-source inspection is explicitly distinguished from inherited execution in [traceability](source-test-trace.json). Local current-task and owner reviews only; no independent reviewer.

Retain all G8.3 F01–F06 invariants: owner/session/transaction binding, exact idempotent retry identities, captured close/cleanup barriers; SDK untagged completion fails closed; schema 28 first-send sync snapshots, strict receipts, weak-database volatile hints and current-authority fences; input-aware bounded verification. Here `F01`–`F09` means **v3 product features**, not the historical G8.3 remediation slice names.

## 2. Actual code versus v3 assumptions

| Conflict or ambiguity | Reconciled decision |
|---|---|
| Spec §2 uses post-F01 `b386b5b…` | Replace its analytical baseline with accepted `09a4d747…`. Retain the original document as history; this report is the delta, not a rewritten acceptance receipt. |
| Catalog existence suggests personal set editing exists | `LearningPackFilter` and `StudyPlanningUseCases.listPacks/loadPinnedVersion` are read-only; add owner-local immutable personal revisions without another vocabulary store. |
| 5,500 editorial records imply a complete reviewed sense corpus | `CefrEditorialCatalog.fromBytes` explicitly serves presentation; accepts `primary-v1`, `ai-reviewed`, nullable `sourceMeaningIndex`. Sense-review files list source-meaning indices, not independently versioned scored sense IDs. Add an explicit crosswalk and quality admission. Never label these Oxford senses or human-reviewed content. |
| Goals imply a time-budget planner exists | `LearningGoalUseCases` has owner-bound commands, deadlines and timezone calendar countdown. Proposal allocation, diff and one active plan revision are additions. |
| Tutor reply is a diagnosis/rubric | `AiTutorUseCases.reply` returns generated text/provider usage through owner and credential controls. It is not a calibrated assessor. Reviewed contrastive explanation already exists, but is optional, post-commit and implemented-off by default. |
| `SentencePracticePanel` supplies writing scores | It is ephemeral listening/speaking rehearsal with no persistence/evidence/reward dependency. Preserve it. A written-answer rubric needs a new activity/result contract. |
| Existing Adventure graph supplies branching dialogue | `AdventureNodeDefinition.prerequisiteNodeIds` and `AdventureWorldCatalogValidator` validate a map DAG; `CanonicalAdventureSessionComposer.compose` pins canonical Today work. Dialogue nodes, language consequences and resumable branch decisions are additional semantics. Reuse map validation patterns, not the map as a dialogue engine. |
| Voice service implies long-form pause/seek | `VoiceSession` owns speak/stop/release and completion barriers. Segment checkpoint/resume and transcript presentation need new orchestration. Do not promise sample-accurate seek or word alignment. |
| F09 equals existing SRS/research post-test | `ReviewCenterUseCases` orchestrates canonical queue/launch. A delayed distinct-context probe needs eligibility metadata; it must not create a second scheduler or use research assessment instruments. |
| Every F needs a lesson enum/table/tab | F01/F02 are organization; F03 is feedback; F08 is exposure. Prefer adapters and versioned supplemental records. Preserve existing 8/44 catalog identity and all 67 packages. |

## 3. F01–F09 reuse / extend / new / drop matrix

Exact declaration locations, source hashes, test paths and test names are in [source-test-trace.json](source-test-trace.json). “Existing test” below means inspected source unless its record explicitly names an inherited execution receipt. No new feature PASS is claimed.

| Feature | Reuse and existing evidence | Extend / new behavior | Drop and acceptance boundary |
|---|---|---|---|
| F01 My vocabulary sets | `LearningPackFilter`, `LearningPackDetailUseCases.loadVersion`, `VocabularyWord`, `ContentQualityPolicy`; pack catalog/detail and vocabulary tests | Owner-local set draft/save/archive, immutable member sense references, reviewed crosswalk, activity launch with frozen revisions | No document/OCR/upload/RAG; reject empty/duplicate/unknown senses; editing r2 cannot alter an r1 session; reopen/export/delete/upgrade required |
| F02 My study plan | `LearningGoalUseCases.prepareCreate/executeCreate/countdown`, `TimezonePolicy`, canonical due queue; goal tests cover owner replay and DST | Versioned time budget, due-first proposal, carry-over, diff/accept/replan with optimistic concurrency | No exam pass probability or arbitrary locked path; rejected/stale proposals leave active plan and progress unchanged |
| F03 Explain this | `ContrastiveFeedbackUseCases.resolveAfterCommit`, `HintPolicy`, `UnifiedLessonController`, `AiTutorUseCases.reply`; contrastive/hint/controller tests | Bounded diagnosis→hint→repair coordinator; authored fallback, assistance lineage across retries | No second answer commit or AI grading from fluent text; timeout is unavailable, never wrong; post-answer help cannot rewrite original evidence |
| F04 Use the word | Unified session lifecycle and optional rehearsal panel; controller and sentence panel tests | Written prompt, versioned meaning/use/form rubric, spans, alternate valid responses, durable supplemental result and revisions | No general language/CEFR score; uncertain/unassessable never converted to binary correctness; assessment acceptance remains pending calibration |
| F05 Speaking scenario | `SpeechPracticeUseCases.acquireSession`, `SpeechPracticeSession.start/cancel/release`, voice ownership; speech tests cover late callbacks after stop/cancel | Practice/assessment selector, bounded scenario, mic readiness, transcript uncertainty, result summary, retry identity | Text fallback labeled written practice, not oral result; no acoustic pronunciation score from ASR; real mic/provider validation remains separate |
| F06 Collocations/confusables | Verified lexical rationale, existing prompt modes, `ReviewCenterUseCases`; contrastive/detail/review tests | Reviewed context/distractor inventory and launch adapter; explanation after canonical answer; repair uses existing review authority | No new scheduler; don't infer reviewed activity coverage from legacy `CollocationService` or its UI alone; ambiguous items fail admission |
| F07 Dialogue mission — ORIGINAL DESIGN | Canonical Adventure composer, learning bridge/checkpoints, map validator; composer/restart/authority tests | Authored dialogue graph, objective on every choice, finite repair, immutable decision log and resume | No second reward writer; back/replay cannot award again; every admitted node reaches terminal/exit within configured budget |
| F08 Audio lesson | `VoiceUseCases`, `VoiceSession.speakUntilCompleted`, route ownership; voice cleanup/completion tests | Reviewed segmented script, format choice, transcript, bounded cache and segment checkpoint resume | No automatic mastery for listening; no invented word timing; stop/cancel drains ownership before takeover; text-only remains useful but is not audio acceptance |
| F09 New-context recall — ORIGINAL DESIGN | `ReviewCenterUseCases`, `EvidenceEligibilityPolicySet`, `LearningUseCases`, binary SRS; eligibility/review/learning tests | Origin refs, delay policy, distinct item/context hashes, clock checks and exactly-once result link | No research pre/post rows; no same-item immediate repair called transfer; insufficient content shows unavailable |

## 4. Architecture and ADR decisions (E1)

**ADR-01: content identity.** Keep existing `ContentIdentity(id,type,revision)` and checksum meaning unchanged. Define a supplemental `SenseRef(corpusManifestHash, wordId, senseKey, senseRevision, lexicalArtifactHash)` with an explicit reviewed crosswalk to the existing word/content identity. Do not concatenate gloss text into identity or infer a sense from a headword. Two senses may map to the same historical word; do not merge their evidence or silently upgrade word-level mastery into sense-level mastery. Existing word SRS retains its meaning. New sense proficiency, if required, is a separate projection pending a versioned compatibility decision.

The corpus pin set is [corpus-pins.json](corpus-pins.json): six editorial and three sense-review files, manifest hash, actual counts and review classification; the loader is pinned in the source trace. It identifies accepted bytes, not scored-content approval. Initial activities may admit only crosswalk entries backed by verified approved/published content under `ContentQualityPolicy`; all remaining editorial entries stay browseable/draft. User selection does not confer editorial approval. Proposed field/index/lifecycle contracts are in [contracts.json](contracts.json).

**ADR-02: one write authority.** View → feature coordinator → canonical `LearningUseCases` / repositories → projections. Use `UnifiedLessonController` for supported lesson attempts and `LearningUseCases.startPinnedReviewSession`, checkpoint and captured finish APIs for lifecycle. Coordinators never update SRS, XP, coins, quests or research directly. Commit attempt/checkpoint/result-link atomically when a canonical attempt is involved. A network request occurs outside the transaction; capture owner generation/session/content/operation ID first, revalidate current authority immediately before persistence, and reject late results.

**ADR-03: graded results and evidence.** `BinarySm2SrsPolicy.review` consumes a Boolean, not a three-dimensional rubric. Preserve frozen `EvidenceContext`, `EventEnvelopeV2`, their codecs and historical policy. Store rubric dimensions in a separate versioned supplemental result; do not squeeze uncertainty or a scalar mean into `isCorrect`. F04/F05 deliver useful assessed/uncertain/unassessable results only after rubric calibration; a fallback alone does not close their scored requirement. Future canonical eligibility extensions require new policy identity, replay fixtures and explicit compatibility review; never reinterpret old receipts.

| Feature/result | Canonical SRS/mastery | XP/reward | Recorded meaning |
|---|---|---|---|
| F01 save / F02 accept | None | None | Organization only |
| F03 hint/repair | Guided practice denies masterySrs under v1 | Guided practice denies XP/coins/quest/streak/achievement | Preserve original answer; assistance applies to repair lineage |
| F04 rubric / F05 lexical rubric | Supplemental only until validated adapter; no current Boolean coercion | None from supplemental rubric | Dimensions and uncertainty, not global proficiency |
| F06 independent typed recall | Existing independentRecall may update SRS through canonical policy | Existing protocol-controlled decisions only | Reviewed exact item; hints downgrade under `HintPolicy` |
| F06 choice/recognition | Existing recognition denies masterySrs | Existing protocol-controlled decisions only | Recognition, not independent recall |
| F07 choices/repair | Same classification as underlying language item | Canonical receipts only, once per accepted identity | Scene progress itself is not mastery |
| F08 listen/transcript | Exposure denies masterySrs | Exposure denies rewards | Consumption separate from later scored practice |
| F09 probe | Independent verified recall can use existing word SRS; no sense-level/efficacy claim | Canonical policy only | Origin, elapsed time, distinct context and assistance retained |

Unknown assistance fails conservatively to guided practice. Personal “assessment” in F05 is a UI intent, not permission to classify it as protocol-controlled research `EvidenceClass.assessment`.

**ADR-04: storage and lifecycle.** Accepted `AppDatabase.currentSchemaVersion=28`. Do not reserve a migration number in this design. At implementation recheck the ledger and add the next version, never overwrite 28. Proposed normalized groups: `personal_set_revisions` + `personal_set_members`; `study_plan_revisions` + active-plan pointer; `activity_extension_results` + revisioned payload; `activity_extension_checkpoints`. Reviewed scenario/audio/item content belongs in verified content artifacts, not owner tables. A supplemental association pins existing session/attempt IDs rather than modifying frozen event payloads. Exact proposed files are recorded per slice.

Keys include ownerId and immutable identity/revision. Set archive hides discovery, not pinned sessions. Private-data deletion is real deletion through the canonical owner lifecycle; history preservation does not excuse retained personal content. Integrate every new table with `ownerLifecycleManifest`, `OwnerLifecycleArchiveExporter`, existing deletion and guest-owner transfer; owner references must be remapped transactionally on guest upgrade. Include new structures in coherent archive manifests and restore codecs. New local-only tables create no remote outbox. This is an explicit initial scope choice; remote sync would require a separate versioned entity/receipt design and must retain schema-28 first-send snapshot semantics.

Migration matrix: empty→new; populated 28→new; interrupted upgrade→rollback/no partial schema; old archive→new with empty extension groups; new archive→old rejected before writes; cross-owner restore rejected; repeated same archive identity idempotent; missing pinned content leaves resumable-unavailable, never substitutes current content. No SQL downgrade or database deletion as rollback. Keep a compatible reader when flags are disabled; avoid launching an older binary against a newer unsupported schema. Backup/restore tests must establish the supported recovery path first.

**ADR-05: concurrency and uncertainty.** Save/replan uses expected prior revision; only one active accepted plan per owner. A double tap uses one operation ID. Lost ACK reconciles the exact identity before retry; collision with different payload fails closed. Owner switch cancels async work and clears ephemeral responses/audio; its late result cannot persist for either owner. App background/route cover releases media handles and awaits retained cleanup. An untagged completion is not proof the current audio segment ended.

**ADR-06: content and finite operation policy.** The design candidate `v3-design-policy-1` proposes two hints (matching current `HintPolicy`), at most three repair attempts per item, six dialogue turns, and 24 hours minimum for a delayed probe. These are configurable engineering fixtures, not empirically validated learning constants. UTC controls delay; timezone is display/planning only. If now precedes the originating timestamp or a session's monotonic elapsed time conflicts with wall time, mark timing uncertain and withhold probe eligibility. A forward clock jump without trusted time cannot establish a validated-delay claim; local personal practice may continue with timing-unverified labeling.

Use a bounded authored item pool first. Generated drafts retain inputHash, prompt/schema/provider revision and validation status; never auto-promote generated examples to approved content. Proposed audio cache is owner-scoped, maximum 20 MiB/10 lessons with deterministic LRU and explicit delete, resumable at a completed segment boundary. Provider length limits determine segment size; pause may stop/replay the incomplete segment. Expose this in UI instead of claiming exact seek.

## 5. LexiQuest routes, wireflows and screen states

Existing navigation uses `AppNavigator.pushPage`/`AppPage` with route-owned media observation. Named top-level routes are login/register/email-verification/home, not nine feature routes. Existing planning pages are `study-planning/catalog`, `study-planning/catalog/detail`, `study-planning/goals`, `study-planning/learning-preferences`. Reuse `MainNavigationScreen` Today/review/Adventure entries, `StudyPlanningHubScreen`, Material 3 theme and shared lesson shell. Names below marked “proposed” are design identifiers, not existing routes.

| Feature / screen IDs | Entry → proposed wireflow | Required state/interaction decisions |
|---|---|---|
| F01 SET-LIST / SET-EDIT / SET-PREVIEW | Existing catalog → My sets → corpus filters → sense selection → preview revision → save → activity chooser | Empty: create; loading: no duplicate save; invalid: inline missing/duplicate sense; stale corpus: resolve before save; saved: reopen rN; archive: hide; referenced deletion: explain owner deletion route |
| F02 PLAN-EDIT / PLAN-DIFF / PLAN-TODAY | Planning hub/goals → time/deadline → proposal with due/carry-over → compare → accept → Today | Zero time: save zero-capacity plan with carry-over; past deadline: replan, no erased progress; conflict: reload latest and regenerate diff; reject: active plan unchanged |
| F03 HELP / REPAIR | Committed lesson feedback → reviewed explanation → optional hint → assisted retry → next/review | No reviewed explanation: authored unavailable message; AI timeout: fallback; exhausted budget: exit/review; back: preserve original committed outcome |
| F04 WRITE / RUBRIC / REVISE | Set activity chooser → target senses/context → write → evaluate → dimensions/spans → revise/finish | Multiple valid answers accepted by fixture rubric; uncertain: explanation, no confident aggregate; invalid provider payload: unassessable; cancellation: no late result |
| F05 SPEAK-READY / SPEAK-TURN / SPEAK-RESULT | Set chooser → practice/assessment → mic readiness → scenario turns → summary | Permission denied: settings/retry/text fallback; interruption: cancel owned handles; empty/uncertain ASR: ask repeat, no lexical penalty; text mode visibly distinct |
| F06 CONTEXT / WHY | Set/review activity → collocation or confusable context → answer → reviewed rationale → canonical review | Ambiguous distractor/content not reviewed: unavailable; assisted repair labeled; restart reopens pinned activity, not a newly generated item |
| F07 SCENE / CONSEQUENCE / RESUME — ORIGINAL DESIGN | Existing Adventure → dialogue mission → scene/choice → consequence or bounded repair → terminal → existing result | Saved branch checkpoint; replay reads same decision receipt; exit available everywhere; stale/missing catalog: recover or abandon through canonical lifecycle |
| F08 AUDIO-FORMAT / PLAYER / TRANSCRIPT | Set chooser → reviewed format/script → play/transcript → pause/stop/resume → optional practice | Loading synthesis, unavailable/text-only, interruption/cleanup pending, segment resume; no autoplay after owner switch; listening completion is not learning mastery |
| F09 PROBE-OFFER / PROBE / PROBE-RESULT — ORIGINAL DESIGN | Review → eligible new-context offer → independent attempt → result with assistance/delay metadata → existing review | Too early, clock uncertain, missing origin or distinct item: unavailable; skip leaves due work; immediate repair stays labeled repair |

Proposed route families: `study-planning/sets/{id}/revisions/{n}`, `study-planning/plan/proposal`, `learning/{session}/help`, `learning/{session}/write`, `learning/{session}/speak`, `learning/{session}/context`, `adventure/{session}/dialogue`, `learning/{session}/audio`, `review/{session}/probe`. Use opaque typed arguments, not learner answers in route strings; revalidate owner and exact revision at entry. Existing route history remains navigable.

Every screen must account for empty/loading/ready/in-progress/saved/completed/error/cancelled/unavailable where applicable. Async states expose progress and cancellation; uncertain persistence exposes reconcile/retry rather than a second submit. Disable feature during session: retire operations, drain media, checkpoint/close through the existing lifecycle, then return to the parent with a readable saved/unavailable status. No silent deletion or auto-success.

Layout: one-column reading/action order at 320 logical px and 200% text; wrap actions, no fixed-height answer text; 48px interactive targets consistent with rehearsal; keyboard focus returns to the launching control; announce result/error once via semantics; text/list alternatives to map/audio; reduced-motion mode; no color-only correctness. Validate contrast from actual theme, not competitor screenshots. Implementation screenshots and screen-reader/device checks are pending.

## 6. Reference observations and limits

All 12 mapped originals were opened with image tools in this task. [reference-observations.json](reference-observations.json) stores each original path/hash, manifest URL/time, observed visual facts, exclusions and intended adaptation. [screen-reference-matrix.json](screen-reference-matrix.json) gives a record for each screen/state, with implementation image/build/viewport explicitly pending. No original image was modified. No new clips were collected or competitor interactions tested.

R5-02 shows numbered topic cards, source counts, pencil icons and a creation button. R4-03 shows a progress path and lock; unlock behavior is unknown. S01 shows a readiness percentage/date/target/completed lessons; S05 shows three gap severity groups; S11 shows a lesson path. These do not validate learning scores or readiness formulas. A01 visibly mentions sentence completion/context clues; A07 shows explanation above MCQ with 4/7 progress. A04 shows a written response example with oral/written selector, not a lexical rubric. R1-02 shows readiness instructions including three questions/seven minutes; S06 is written/oral/timer marketing. R7-01 shows format choices and estimated durations; R7-02 shows a structured practical-case explanation. Audio quality, alignment and resume remain unobserved.

Adapt grouping, explanation-before-practice, readiness and format selection. Exclude competitor branding, medical/multisubject exam content, upload flows, fixed advertised timing, pass probabilities and inferred lock rules. F06/F07/F09 are original designs; screenshots from other functions are not evidence they exist in the reference product. Visual acceptance compares intended differences and interaction states, not pixel similarity.

## 7. Dependency slices and test design

[slice-plan.json](slice-plan.json) records all 13 slices, exact proposed source/test files, dependencies and focused commands. New filenames are proposals and must be rediscovered before implementation to avoid duplicates. No application files are created by this reconciliation.

| Slice | Deliverable / prerequisite | Completion benchmark |
|---|---|---|
| E0 | Accepted source, writer, defects, route and F matrix | Pins verified; accepted history intact; one writer |
| E1 | Contracts, wireflows, fixtures, test/rollback plan | Nine features traced; ambiguous semantics resolved or explicit readiness gate, never hidden |
| E2.1 / F01 | Crosswalk admission + personal revisions + lifecycle integration | Edit/restart/export/delete/guest-upgrade preserve exact identities; reviewed subset launches existing activity |
| E2.2 / F02 | F01 + goal/due sources | Due-first budget, DST/missed-day/zero-time fixtures, one active revision and visible diff |
| E3.1 / F03 | Existing committed feedback + F01 context | Hints/retries bounded; assistance never reset; original attempt unchanged |
| E3.2 / F06 | F01 + reviewed distractors + F03 feedback | Ambiguity rejected; canonical result/review exactly once |
| E3.3 / F04 | F01 + rubric fixtures/result storage | Alternate answers and uncertainty handled; calibrated output, no Boolean shortcut |
| E4.1 / F05 | F04 result contract + existing media ownership | Mic/cancel/retry/ASR uncertainty + separate text fallback; physical/live evidence classified |
| E4.2 / F08 | F01 + shared voice lifecycle | Reviewed script/transcript, interruption/drain/resume, bounded cache; audio acceptance separate |
| E5.1 / F07 | F01/F03/F06 + canonical Adventure | Graph termination, objective coverage, restart and no duplicate reward |
| E5.2 / F09 | F01/F06 + prior canonical attempt | Delay/distinct-context/clock/assistance policy, no research writes |
| E6 | All authorized slices + lifecycle regression | Re-review changed and dependent code, close defects, integrated freeze SHA; old review not applied to new code |
| E7 | E6 immutable freeze | G8.4–G8.9 retained and extended, no duplicate “extra” full-system pass |

Exact verifier syntax verified from accepted script: `& ./tool/cli/verify-scope.ps1 -Level Targeted -Area Learning -BaseSha <reviewed-base-sha> -TestTargets @('test/features/learning/unified_lesson_controller_test.dart','test/features/learning/hint_policy_test.dart') -Resume`. The placeholder must be replaced with the actual reviewed slice base. Use `-PlanOnly` to inspect selected inputs before a future run. Voice targets use `-Area Voice`; cross-owner/migration composition uses `-Area Runtime`. New tests are listed in the slice file and must exist before execution. Reuse recorded passes only if fingerprint and intent still match. Serialize Flutter/build/codegen/heavy work. Full Release only at a frozen PR/release SHA via the verifier's `-FrozenSha`; no release execution here.

Fixtures in [design-fixtures.json](design-fixtures.json) are concrete input/expected-output design cases, not executed tests or human-reviewed teaching material. The content plan targets A1–B2, with level coverage to verify at admission, and seeds nine real editorial IDs; it requires four authored contexts per admitted sense (base, repair, delayed A, delayed B), two accepted writing responses and one ambiguous response, two confusable candidates with rationale, one speaking scenario, one audio script and one dialogue graph. This yields a minimum 36-context development inventory if all nine senses are admitted. Scored admission can be smaller until reviewed; do not claim all levels/5,500 records supported. Human content reviewer is unassigned; current review is source/AI-assisted design only. Reject POS/sense mismatch, ambiguous key, unsupported translation, duplicate “new” context, unbounded branch and unknown provenance.

Acceptance fixtures include happy/invalid/ambiguous inputs, same-operation replay, changed-payload collision, owner A→B, lost ACK, restart, export/delete/restore, guest upgrade, research-off, offline/quota/timeout, mic deny, route cover, SDK untagged completion, content withdrawn and feature flags on/off. Local next-item p95 ≤300ms after load requires ≥30 measured samples on a named device; provider latency is measured separately. No performance result is claimed.

| Gate retained | Existing scope plus extension requirement |
|---|---|
| G8.4 | Executable System Test Plan on E6 SHA; trace all original requirements plus F→screen/state→data→test→evidence; actual prerequisites and expected results |
| G8.5 | Unit/widget/integration for original and affected extension behavior: revisions, timezone, assistance, rubric, graph, delay, media, idempotency, research-off |
| G8.6 | Supported platform build/install/upgrade/restore and journeys set→plan→lesson→feedback→review; speaking/audio/Adventure. Mocks do not substitute for devices |
| G8.7 | Offline/quota/timeout/lost ACK/owner switch, mic/audio interruptions, 320px/text200/keyboard/screen reader/reduced motion, measured storage/audio resources |
| G8.8 | Original and new defect register: reproduction, severity, fix SHA, targeted retest and dependency regression; unresolved required defects cannot disappear into a handoff |
| G8.9 | Final ledger preserves 67 original package identities and separate F01–F09 extension mapping; separate local/emulator/device/provider/research/release statuses |

The exact original brief scope/acceptance and hashes are retained in [retained-gates.json](retained-gates.json). Specifically preserve G8.4's 74 overlapping coverage records, 12 formula groups, 16 test families, TestCaseID→COV/MODE/MG/FORM mapping, negative cases, entry/exit criteria, incident fields and NOT RUN ledger without duplicate commands. G8.6 still requires actual APK/source/model/content pins, cold start, first lesson, all available modes, history/replay, offline/restart and durable reopen, with no destructive uninstall/clear-data. G8.7 retains disk/content-hash/locale/timezone faults, latency/memory/focus measurement and human TalkBack/audio separation. G8.8 re-reviews/refreezes changed code and regenerates only affected plan pins. G8.9 retains cleanup manifest and artifact hashes as well as review/test coverage. These requirements are additions to, not replacements for, the extension rows above.

Cross-feature journeys: F01→F02→F03/F06→review; F04/F05→rubric→evidence guard; F07→restart→one reward receipt; F08→interrupt→resume→practice; prior attempt→F09→review. Inject owner switch/restart at each durable/async boundary, not only at entry.

## 8. Readiness, rollback and evidence limits

This package completes the requested analysis/design deliverables. It does **not** assert every E2–E5 slice is implementation-ready. Required readiness gates are explicit: reviewed sense crosswalk/content admission (E2.1), calibrated rubric and assigned content review (E3.3/E4.1), provider capabilities/budget and actual target-device availability (E4), and trustworthy timing classification (E5.2). Design policies are fixed as candidates with fixtures, not claims of empirical validation. These gates can be resolved within later authorized slices; do not start implementation from this report alone.

Rollout is per-capability default-off followed by bounded internal exercise with flags both on and off. Default-off implementation does not count as functional acceptance. Rollback disables entry/coordinator, cancels work and preserves compatible stored revisions and original canonical receipts; does not downgrade schema or erase data. If semantic mappings change, retain old decoder/policy and pin new identity. Reconcile outstanding operations before retry, never repeat an uncertain write with a new ID.

Android JVM/SDK and Windows Win32 harness evidence remains bounded, not installed/device proof. iOS/macOS/Linux/web scaffolds are not supported-release/offline proof. Gradle distribution SHA-256 is unpinned: retain a provenance release gate, not a tampering allegation. No physical/native-assistive/acoustic/live-provider/hosted/cloud/deployment/full-release claim. No research activation, remote research sync, study assignment, statistical reporting, seed execution, training/B11A/GPU, or prohibited security workflow.

## 9. Concise teaching notes

| Stage / objective | Reason and tradeoff | Worked example | Completion benchmark |
|---|---|---|---|
| E0: establish reality | A filename is not a capability; inspecting behavior costs time but prevents duplicate systems | A map prerequisite graph cannot evaluate dialogue choices | Each reuse claim has a symbol and bounded evidence |
| E1: make requirements testable | Precise states prevent happy-path designs from losing data | “Save” with a lost ACK first reconciles operation 42, not creates 43 | Input, expected result and failure recovery defined |
| E2: protect identity | Immutable revisions cost storage but preserve meaning | Edit set r1→r2; yesterday's session still refers to r1 | Reopen/replay/export retains pinned content |
| E3: distinguish learning evidence | Fluent feedback is cheaper than calibrated scoring but proves less | A hinted correct answer is guided practice, not independent recall | Rubric/assistance/policy fixtures agree without inflated SRS |
| E4: own async resources | Cancellation requires cleanup, not only a UI flag | Owner B cannot receive owner A's late transcript or completion | Late callback and takeover tests show no cross-owner write |
| E5: bound complex mechanics | Finite authored graphs are less flexible but reviewable | Each repair consumes a turn and always exposes exit | All paths terminate and resume cannot award twice |
| E6/E7: tie claims to evidence | More platforms and providers increase verification cost | A mock microphone test does not establish real mic permission behavior | Ledger states exactly what ran on which SHA/device |

The next coordination action is review of this package and its readiness decisions under the preserved boundary. Master is notified; no automatic feature or B19 dispatch is performed.
