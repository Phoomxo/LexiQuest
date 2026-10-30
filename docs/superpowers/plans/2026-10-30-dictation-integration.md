# One-word Dictation integration

Final integration: source `bfa766b3`, Flutter3350, analysis0, CLI23,
backend390 pass/one existing opt-in E2E skip and normal debug APK pass.
All661 Dart hashes remain unchanged through checks/build. The actual owned route
uses existing ChooseMode tests, avoiding a duplicate integration test file.
See [wave12 evidence](../../field/2026-10-30-remaining-systems-wave12.md).

Execution checkpoint2026-10-30: the owned entry, immutable capability, projection
floor and actual UI are integrated. Focused learning/sync377 and UI/voice238
checks pass. Independent review accepted the generic-path, corrupt-carry,
remote-SRS, voice-retirement and clock-recovery corrections. Full regression,
analysis and normal APK attestation are the next integration gate; this is not
a production-readiness claim. Grounding below records the pre-execution source.

2026-10-30. Authorized continuation of the remaining-system plan. The Research
checkpoint is complete at application fabc990f and attestation cbdd4969.
Production native code is unchanged from the db065b2f grounding below.
Root serializes all Flutter/analyze/build commands in the existing worktree;
workers own disjoint D drafts and root integrates them. Initial current-API
projection baseline has8 actual RED/4 compatibility PASS; this is not readiness.
No schema, rollout authority or separate Pair Matching task is added.

## Outcome and boundary

One real ChooseMode entry opens one owned local vocabulary target, plays it
through VoiceUseCases, saves one immutable typed-response result and explicitly
finishes one `dictation` session. Slow playback is sticky assistance. Assisted
practice remains visible in its session/history but creates no mastery/SRS, XP,
coin, achievement, Quest or Streak contribution. Existing inferred evidence and
existing ordinary prompts retain their current behavior.

This card covers Dictation only. It does not restore the archived mode gateway,
introduce a mode registry or another learning/reward writer, add schema, change
the frozen 8/44 catalog or EvidenceContext/EventEnvelopeV2, certify durable
restart/resume, or start Scramble/Cloze/Pair Matching work.

## Current executable edges

- `screens/dictation_quiz_screen.dart` is still an orphan: raw targetWord,
  optional VoiceUseCases, automatic 1.0x/optional 0.75x, local correctness only.
  Its three widget tests have no production route or save/finish proof.
- `LearningUseCases` has canonical ordinary start/answer/finish, but generic
  recordAnswer/finishSession re-read the active owner instead of taking the
  captured owner. `_startWordPractice` also builds irrelevant quiz distractors.
  Existing configured-quiz capability ports are the precedent for a small
  Dictation capability reusing the same private canonical writers.
- `DriftLearningRepository.listQuizWords` supplies actual owner-filtered words
  and `local-vocabulary-v1:<localRevision>`. `_recordAnswer` checks owner, session
  and nondeleted word, but not that revision; its replay compares immutable
  context. Plain start/answer/finish do not use the configured-quiz owner gate.
- `EvidenceProjectionDecision` already has the required policy; no production
  consumer currently calls it. The learning rebuilder uses one ordinary list
  for SRS, XP and achievements. The reward rebuilder uses correct ordinary
  answers plus legacy XP carry. `_finishSession` separately unlocks
  first_session/perfect_session. `_afterRecordedAnswer` separately forwards
  shadow rewards, Quest and Streak after the first inserted ACK.
- `DriftProgressQueries` computes accuracy/skills/weaknesses from its ordinary
  list, and dashboard streak from every timestamp. Changing only SRS or the
  Streak sink leaves visible mastery/streak leakage.
- History already labels `dictation`, counts its ordinary facts, and offers
  resume only for accepted configured quiz/weakness/sourcePractice sessions.
  Preserve that distinction; a bare Dictation container has no quiz checkpoint.

## One scoped projection gate

Add one pure ordinary-projection predicate in
`features/learning/domain/learning_evidence_contract.dart`, using the existing
EvidenceProjectionDecision. First retain existing ordinary metadata admission.
Only when promptMode is exactly `dictation`, classificationSource is declared
and policyVersion is the current declared version, apply the requested
LearningProjection decision. Every other admitted prompt/context follows the
existing compatibility path. Do not apply the entire matrix to meaningChoice,
pronunciation, unknown prompts or old inferred Dictation as an incidental fix.

Add the Dictation declaration to current_activity_evidence: skill
`dictation-spelling`; normal is independentRecall/hintLevel0, support is
guidedPractice/hintLevel1. Keep local ordinary rollout and the existing default
engagementAllowed=false. A new declared Dictation call missing its real content
revision must fail instead of falling back to the inferred sentinel. Other
existing fallback behavior stays intact.

The existing approved matrix, without inventing an engagement flag, gives:

| Projection | Normal declared Dictation | Assisted declared Dictation |
| --- | --- | --- |
| sessionOutcome/history | allow | allow |
| masterySrs | allow | deny |
| activeLearningEffort | allow | allow |
| XP/coins/Quest/Streak/achievement | protocolControlled, therefore deny with the current false flag | deny |

No production issuer or protocol activation is added to change that result.

Apply this single predicate at these existing consumers:

1. Learning rebuild: keep ordinary admission separate from per-projection
   subsets. SRS uses masterySrs, points uses xp, achievements uses achievement;
   session counts/score use sessionOutcome. Do not filter the shared candidate
   list once and accidentally erase assisted session outcomes. An assisted-only
   word returns absent SRS; an existing valid SRS remains unchanged. No fake
   zero-state row is created.
2. Ordinary repository: make AnswerRecordResult.srs nullable and migrate its
   actual uses/tests. The current direct result.srs/replay.srs dereferences are
   five assertions in drift_learning_repository_test.dart; no lib consumer
   dereferences that field. Existing fake constructors still accept real states.
   Remove the current unconditional null-SRS failure only
   for a legitimately ineligible native answer. Enqueue the immutable attempt
   with context payloadVersion2, but enqueue SRS only when the new attempt is
   mastery-eligible and a real state exists. Exact replay never enqueues again.
   Gate first_session/perfect_session using native attempts' achievement
   eligibility as well as the existing old-session path; assisted-only or
   empty Dictation completion must not unlock a session achievement.
3. Reward rebuild: use coins eligibility and put all ineligible native answer
   IDs, plus native-only ineligible session source IDs, into excludedSources
   before legacy XP carry. Keep mixed/old ordinary session sources eligible
   according to their original facts. A forged/legacy points row
   backed by an excluded native answer must not become creditLegacyCarryV1.
   Preserve independent legacy carry and current corruption/provenance checks.
4. LearningUseCases hooks: gate Quest/Streak separately; do not adapt excluded
   native answers into the old class-agnostic shadow reward event. Retain the
   ordinary local-mutation notification and inserted=false replay short circuit.
   Do not change EventEnvelopeV2 or create a parallel event/reward authority.
5. Progress reader: use mastery-eligible attempts for mastery accuracy,
   skills/weaknesses/recommendations; streak-eligible timestamps for dashboard
   streak; exclude native-ineligible source IDs from XP totals/carry. Keep
   completed session visibility and LearningHistory's assisted answer counts.

Sync is a mandatory behavior check, not an automatic production edit. Current
`DriftSyncStore._applyAttempt` already calls the same rebuilders and ignores a
nullable rebuildWord result. Pull/replay and natural-key aliases must preserve
declared metadata and the floor. In `_applySrsState`, the existing alias branch
rebuilds from local evidence, then accepts an independent remote SRS snapshot
if there is no eligible local state. Preserve the Assessment isolation lesson:
an assisted/Assessment-only local word is not permission to suppress a genuine
ordinary remote SRS baseline. Test that such a baseline is independent of the
native answer, rather than treating its existence as an assisted contribution.
Do not globally reject SRS pulls or gate them by the presence of assisted rows.

## Owner, target and retry contract

Use one immutable DictationSession produced by LearningUseCases with captured
ownerId, sessionId, target QuizWord/contentRevision and original start time.
Add a narrow Dictation capability to learning_repository.dart, implemented in
DriftLearningRepository by reusing `_startSession`, `_recordAnswer` and
`_finishSession`; it is not another persistence authority. The capability owns
the actual `_ownerWrites.writeForActiveOwner` transaction and takes a synchronous
stillCurrent guard. This avoids broad changes to old ordinary method semantics.

The launch path reuses the existing category selector under FieldFeature.quiz,
then selects one real eligible local word in that category. Empty/missing
dependencies or no word shows an explicit unavailable/empty state and creates
no session. No fallback word, random external lesson, raw-word persistence or
meaning-choice distractor scaffolding is needed. Keep one started session per
launch intent; hold its immutable start identity across a lost ACK.

At new start, save and finish, verify the captured active owner and deletion
fence inside the actual owner transaction. Re-read the exact owned/nondeleted
word and compare the canonical local revision string plus original spelling;
reject edits/deletion instead of retargeting. Recheck DB facts and stillCurrent
after awaited work before commit. A matching existing ACK can be returned as
historical original facts; it must not manufacture a new timestamp, projection
or hook. No new Research pin, receipt, row or outbox is introduced.

The screen binds the actual owner stream, route visibility and foreground state
to a monotonic epoch. Owner null/error/done, A→B→A, hidden route, background,
binding replacement and disposal invalidate outstanding audio/save/navigation
work. A final UI continuation requires the same epoch and binding after every
await. A completed original-owner write is retained if the owner changes only
after commit; its private feedback is never delivered to the replacement owner.

Before the first save await, freeze one pending command: attempt ID, owner,
session/word, original occurrence time, bounded response latency, normalized
comparison result, exact revision and sticky assistance context. Use the
screen's existing trim/case-insensitive spelling semantics; no AI/fuzzy scorer
or validated learning instrument is invented. Disable input and support changes
while that command is unresolved. Retrying after lost ACK reuses every field.
Incorrect response is one saved result, followed by explicit completion; it is
not another fresh scored attempt revealed by local feedback.

Capture finish time once in a pending close intent. Retry uses that same time
and the canonical existing completed ACK; a different new close intent must
not rewrite the end. Finish occurs only after saved-answer ACK, checks the same
owner/target/lifecycle boundary and exactly the expected single saved response,
and returns the real LearningSessionSummary.
Back/cancel/disposal never automatically marks completion. An interrupted bare
session remains visible as unfinished and is not offered configured-quiz resume.

## Voice boundary

Inject VoiceUseCases from AppDependenciesScope (and a fake in tests), keeping
owned/default disposal rules. Never import VoiceProvider into production UI.
Use VoiceMode.practice, contentType dictation_quiz and an ID derived from actual
word ID/revision rather than the answer text as an identifier. Reuse existing
native fallback/cancellation; no engine download or voice service rewrite.
The current VoicePlaybackResult describes engine/fallback/cache outcome, not
physical proof that a learner heard the word.

Mark assistance sticky BEFORE requesting speed<1, including request failure;
normal replay cannot clear it. Stop/serialize playback before save/finish and
on invalidation. Discard stale completions. If no current playback request
succeeds, offer retry/back and do not silently score a text-only listening task.
Do not disclose the target or correctness until the save ACK. Preserve normal
and slow playback tests and test disposal of owned versus shared voice.

## Exact disjoint write sets

All implementation/test paths below are relative to the worktree above.
Agree on the small capability/model signatures first; one writer per file.
Serialize Flutter/analyze/build and run them only after a consistent snapshot.

| Owner card | Production files | Focused test files |
| --- | --- | --- |
| A: scoped projection consumers | lib/features/learning/domain/learning_evidence_contract.dart; lib/features/learning/data/drift_learning_projection_rebuilder.dart; lib/features/rewards/data/drift_reward_projection_rebuilder.dart; lib/features/progress/data/drift_progress_queries.dart | test/features/learning/evidence_eligibility_policy_test.dart; test/features/learning/data/drift_learning_projection_rebuilder_test.dart; test/features/rewards/data/drift_reward_projection_rebuilder_test.dart; new test/features/learning/dictation_projection_isolation_test.dart |
| B: canonical capability and retries | lib/features/learning/domain/learning_models.dart; lib/features/learning/domain/learning_repository.dart; lib/features/learning/application/current_activity_evidence.dart; lib/features/learning/application/learning_use_cases.dart; lib/features/learning/data/drift_learning_repository.dart | test/features/learning/current_activity_evidence_capture_test.dart; test/features/learning/learning_use_cases_test.dart; test/features/learning/drift_learning_repository_test.dart; new test/support/dictation_session_harness.dart |
| C: one real UI entry | lib/screens/choose_mode_screen.dart; lib/screens/dictation_quiz_screen.dart | test/screens/choose_mode_screen_test.dart; test/screens/dictation_quiz_screen_test.dart |
| D: integration/review, no production edits | none | test/features/sync/drift_sync_store_test.dart; test/features/progress/learning_history_test.dart; new test/screens/dictation_learning_integration_test.dart |

No initial production write is allocated to SyncStore, VoiceUseCases, Quest or
Streak repositories, history UI, schema, feature catalogs, Research or runtime
composition. Their existing ports are sufficient for this plan. Expand a write
set only after a focused behavioral RED establishes a specific missing edge.

Execution expanded only SyncStore's answer-triggered SRS rebuilds and
HybridVoiceService.stop. Two real remote-baseline regressions and two actual
shared-voice cancellation regressions established these edges before correction.
The canonical rebuilder, alias reconciliation and ownership disposal remain.

## Focused RED checks and completion evidence

1. First make the real Drift assisted-only correct/wrong save succeed, retain
   one answer/session/history row, return null SRS and finish once, while exact
   SRS/points/reward/achievement/Quest/Streak rows remain unchanged. Exercise a
   preexisting SRS as well as no-SRS word. Check dashboard streak and mastery
   skill/weakness counts, plus first_session/perfect_session completion leaks.
2. Prove normal declared Dictation gets its SRS outcome while the current false
   engagement flag denies motivation. Replay all normal/assisted commands and
   completion without new outbox/hook/timestamp changes. Check attempt-only
   outbox for assisted facts and absence of a fabricated SRS operation.
3. Seed mixed frozen-inferred Dictation, current meaningChoice recognition and
   ordinary legacy evidence. Snapshot their SRS, XP, coins, achievements,
   session/history, Quest/Streak and outbox. Introducing the gate must preserve
   those existing results exactly; an unscoped global matrix would fail this.
4. Seed XP carry rows sourced from an ineligible native answer and its session; rebuild/read
   rewards and progress repeatedly and prove no native coin/XP leakage. Keep
   independent legacy carry unchanged. Pull/replay declared native attempts
   through actual SyncStore, including word aliases and mixed eligible evidence;
   prove no SRS contribution or reward from assisted facts. Preserve the valid
   independent remote SRS baseline behavior already covered for Assessment.
5. Hold real owner/word read, save and voice awaits. Switch owner A→B→A, edit or
   delete the target, set deletion fence, hide/pop/background/dispose. Check
   original-owner isolation, rollback before final commit, no stale private
   audio/feedback/navigation, and no newly minted immutable identity on retry.
   Also hold finish after its original intent is captured and lose its ACK.
6. Drive the actual ChooseMode/category entry with synthetic Drift vocabulary.
   Assert exactly one dictation session and selected target revision; rapid taps
   and IME submit save once. Preserve 1.0x/0.75x playback tests; slow assistance
   remains set after failures and later normal replay. Verify Thai/English at
   200% text, keyboard reachability, explicit audio failure and return summary.
7. As a nonparticipant, compare all Research tables/events/outbox before/after
   this ordinary flow; no enrollment, Assessment facts or research operations
   may appear. Run focused consumers first, then ordinary regression, analysis
   and normal build at the integration checkpoint. Physical-device listening,
   production voice availability and restart-resume remain separately attested.

No runtime, audio hardware or test was executed to create this card. It is an
executable plan grounded in the frozen source, not a feature-completion claim.
