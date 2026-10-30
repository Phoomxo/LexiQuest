# Make owned SRS review safe before Review Center

**State:** Root-approved bounded API after [Wave19](../../field/2026-10-30-remaining-systems-wave19.md). Application `f33014037073c97ff039a9427a7402504f980571` is attested (Flutter4297/analysis0/CLI23/backend390+one existing opt-in skip/normal APK120.3s); checkpoint `e22f9f638a7c7c9ff67e6ade1f4d3d7ac5a27b6f` is pushed. Worktree cycle12-release, branch `codex/remaining-system-readiness`. D-only test-first drafts follow this API; root owns C promotion and serialized checks. Schema20/37 and v21+ stay unchanged/unreserved.

## Review board

Root accepted shape B and the six-method API below after source review. This revision records the explicit capability-interface exception and preserves the existing autoplay UX under current-scope guards. The D implementation has not started. Root owns publishing the C plan with W19 metadata and will release bounded D test-first work after the predecessor push. This document does not authorize a parallel C writer.

## Grounded choice

Keep the existing20-card due/source deck, flip, self-rated srsRecall, independentRecall/srs-recall profile, original learning/reward projections, and source-result semantics. This is not recognition practice.

| Shape | Actual fit | Decision |
| --- | --- | --- |
| Extend AcceptedNativeExercise | learning_models.dart:147 requires one word. DAO _sameNativeAnswer:714 requires exactly one attempt; _validateNativeAnswer:734 requires attemptNumber1. _NativeBinding stores one answer/close. Extending it changes every sealed mode switch and existing native proofs. | Reject for this unit. |
| Add a narrow SRS capability to the existing repository file and Drift DAO | Existing _startSession/_recordAnswer/_finishSession already own canonical session, attempt, SRS, rewards, outbox, and observers. Wrap them with one owner/current/target transaction boundary and an in-process deck handle. | Choose. No parallel repository implementation or owner store. |

Paths above are under lib/features/learning/domain and data. Add the explicit SrsReviewRepository capability interface in existing learning_repository.dart, alongside NativeExerciseRepository and ConfiguredQuizRepository. This is a justified exception to the initial Review Center grounding suggestion to avoid new ports by default. It follows the house capability pattern and avoids adding SRS-only requirements to the16 unrelated generic test wrappers found in the current tree. Only the existing DriftLearningRepository implements the production capability, using its private canonical writes and existing owner coordinator/store. SRS-specific test decorators explicitly delegate it; there is no unsafe generic fallback or parallel writer.

## Accepted API shape, implementation pending

Add immutable SRS types to existing learning_models.dart:

- SrsReviewSession contains its LearningSessionDraft, ordered copied QuizWords, and due/source selection. Owned decks have1..20 unique IDs. The canonical activity remains srsReview; use session:srs-review-v1: as the capability ID prefix. Word/category/content revision and full current word bytes are pinned. No options, fake planID, persisted configuration, or new EvidenceContext fields.
- SrsReviewAnswerIntent contains the original session object, zero-based cardIndex, and complete frozen RecordAnswerCommand. Its attemptNumber is index+1.
- SrsReviewFinishIntent contains the original session object and original millisecond UTC end.
- Internal start/finish results indicate whether a canonical row/state was newly changed, so replay does not repeat mutation notifications.

LearningUseCases public shape:

```dart
Future<SrsReviewSession?> prepareSrsReview({
  required String expectedOwnerId,
  Iterable<String>? sourceWordIds, // null means current due queue
  int limit = 20,
  required bool Function() stillCurrent,
});
Future<SrsReviewSession> startSrsReview(
  SrsReviewSession review, {required bool Function() stillCurrent});
SrsReviewAnswerIntent prepareSrsRating({
  required SrsReviewSession review,
  required int cardIndex,
  required bool recalled,
  required int? responseTimeMs,
});
Future<AnswerRecordResult> commitSrsRating(
  SrsReviewAnswerIntent intent, {required bool Function() stillCurrent});
SrsReviewFinishIntent prepareSrsFinish(SrsReviewSession review);
Future<LearningSessionSummary> finishSrsReview(
  SrsReviewFinishIntent intent, {required bool Function() stillCurrent});
```

The repository capability supplies prepare/start/commit/finish counterparts. Prepare receives the captured LearningSessionDraft and selection, not an ownerless QuizSession. It performs the actual same-database owner/fence and target reads, so a forged expected owner cannot read another owner's deck. It creates no learning fact. It is an explicit practice command, never the future hub's read loader. It does not call getOrCreateActiveOwner.

After all production callers migrate, remove unused startDueReview and startSourceReviewForWords application wrappers. Keep other generic activities intact. Read-only Review Center loading remains separate.

## Transaction and retry rules

1. Reject ambient transactions before preparing or writing. One public SRS command owns its commit. Use the existing same-database coordinator before business writes and after awaited SQL/readback; the coordinator alone currently checks only before its callback at drift_owner_write_coordinator.dart:45.
2. Prepare the exact owned active word/category deck. Due selection uses existing SRS due time with stable tie ordering; source selection preserves its owned requested IDs and must not become due-only. Fix the due query's missing active-category join. Freeze the order once; missing/changed source targets fail rather than substitute words.
3. Use a private bounded Expando keyed by the original SrsReviewSession, following the native original-handle precedent without extending its union. Track attempted start, acknowledged start, original ratings per ordinal, and original closing intent. No raw-ID adoption after process restart.
4. First start validates all deck pins, writes through _startSession, and verifies the exact stored tuple. A same-object lost-ACK retry reuses the same ID/time/deck. Another object with a colliding existing ID fails.
5. Freeze ID, UTC time, rating, latency, index, word, provider provenance, and exact EvidenceContext before the first rating await. Keep the existing attempt:srs:<sessionID>:<index> identity and srsRecall payload/profile. Require the next original card and canonical previous ratings before a new insertion; finish cannot accept missing/foreign/extra attempts.
6. Fresh ratings and first finish verify active owned targets and revisions before and after business SQL. Exact committed ACK replay compares historical stored facts and returns saved SRS/summary without rebuilding projections or requiring a deleted live parent. Owner/fence/current/readback guards still apply. An altered rating, time, ordinal, content, or end is a collision.
7. Call the existing _recordAnswer only for a new valid rating. Exact replay reads the existing SRS receipt and returns inserted=false. Keep all original counts, rewards, immutable outbox, and optional hooks. Finish requires all original ratings, preserves the first stored end, and returns an equal summary after lost ACK.
8. Finish canonical readback and final owner/fence/current checks inside the same transaction. Notify local mutation and optional secondary sinks only after a successful top-level commit, at most once on the first confirmed receipt of each original operation, including a receipt obtained by retry after uncertain ACK. Do not rely only on the replay's inserted=false flag to decide whether its original notification was delivered. No voice, remote IO, or UI-frame await inside that transaction.

Reserve public generic writes for migrated SRS: startSession rejects srsReview, legacy aliases flashcard/flashcards, and the new prefix. Generic recordAnswer rejects srsRecall or an SRS session regardless of its ID. Generic finish rejects a stored SRS activity regardless of prefix. Actual production uses only srsReview/srsRecall; flashcard/flashcards occur as historical display aliases, not live writers. Historical reads, pull, projection rebuild, owner rehome/export/purge remain supported. Test generic-ID+activity, generic-session+srsRecall, and raw finish bypass explicitly.

## UI and all six production call sites

SrsFlashcardsScreen keeps wordList and sourceWordIds, and adds expectedOwnerId/ownerChanges/languageCode. Owned mode captures one current owner/generation from the injected stream or existing AppDependencies progress stream before preparation. A supplied expectedOwnerId must match. No owner/dependency source means unavailable, not an implicit owner creation.

Invalidate flags and epochs synchronously before deferred redraw. Check them after every await and in retained flip/rating/Next/finish/audio/navigation callbacks. Owner null/A or A/B/A, stream error/done, hidden IndexedStack pane, overlay, route/lifecycle or dependency/source replacement hides old content immediately. A failed write keeps the original pending intent; never generate a fresh retry. Start before displaying an owned card, Next only after rating ACK, source result only after valid finish ACK. Previously committed ratings remain if the user exits; this unit adds no abort or restart-resume promise.

Preserve callers:

- ChooseMode recommendation/tile at :311/:366 and WeaknessClinicScreen:201 open the current owner's complete due queue, not a weakness-only subset. Capture owner/generation on the launch path.
- SourcePracticeScreen:435 passes its confirmed captured owner and owned matched IDs, then keeps existing immutable LearningSessionResult validation.
- CefrSelectionScreen:205 and WordbookImportScreen:173 pass raw maps without owned IDs. Snapshot those maps and keep a clearly labelled preview using private presentation data, not a fake QuizSession or SrsReviewSession. It writes no session/attempt/SRS/reward/outbox, returns no persisted result, and must not say “saved.” Do not auto-import or silently delete these active callers. Owned20-card limits do not silently truncate these existing preview inputs.

Borrow injected/runtime voice; do not construct a new default service or dispose a borrowed one. If no borrowed voice is available, audio is unavailable and ordinary review continues. Preserve existing autoplay only after canonical start ACK while the owner, route, lifecycle, and dependency binding are current and visible. Play once for each valid current card; the next card requires the previous rating ACK and a valid Next transition. A retry, rebuild, or late callback must not replay it. Keep explicit Listen/Replay/Stop using the proven pending-stop join/audio-intent epoch pattern. Preview retains the existing voice UX with route/lifecycle guards and owner-scope guards when an owner source is available, without claiming a canonical start or persisted result. Stop only playback owned by this screen on invalidation/dispose. Never let a late callback speak the previous owner's card or stop the next route's audio.

## Write set and executable acceptance

Production: existing learning_models.dart, learning_repository.dart, learning_use_cases.dart, drift_learning_repository.dart; screens/srs_flashcards_screen.dart, choose_mode_screen.dart, weakness_clinic_screen.dart, source_practice_screen.dart, cefr_selection_screen.dart, wordbook_import_screen.dart. No new runtime store, bootstrap authority, evidence contract, sync field, table, or migration. Update only stale SRS API diagnostic text in architecture fitness/deprecation references when necessary.

New tests: test/features/learning/srs_review_repository_test.dart, srs_review_use_cases_test.dart, test/support/srs_review_harness.dart, and test/screens/srs_review_safety_test.dart. Keep existing srs_flashcards_screen_test and all five caller test modules. Migrate the non-quiz SRS branch in configured_quiz_use_cases_test. Existing export/progress fixtures using generic srsRecall must use the new legitimate path or clearly labelled historical SQL; keep their evidence assertions.

Stage meaningful RED first: real SQL executor interception after INSERT/UPDATE changes owner, installs a valid deletion fence, edits/deletes the current target/category, or invalidates current scope. Require whole-operation rollback and zero premature notifications. Also test ambient denial, forged owner/deck/copy, wrong ordinal/extra word/partial finish, and all generic bypasses. Replay tests cover every stage before write and after commit, both ratings,20 cards, original command/context/end equality, exact projections/outbox snapshots, and no duplicate secondary hooks.

Then run focused repository/usecase tests, SRS and six-callsite UI tests, learning/progress/export/sync and old native/configured regressions. Preserve source zero-due review, Again/Got ACK behavior, one immutable two-card result, existing eligible reward amounts, Thai/English320px/200%, keyboard/Reduced Motion, owner ABA, guarded autoplay/late voice tests, and preview-zero-facts checks. Keep the existing autoplay test meaningful; add start-ACK, rating-ACK/Next, repeated-rebuild, pending-stop, and invalidated-scope cases rather than deleting its assertion. Root serializes Flutter/analysis/full/build at integration. No tests or implementation ran for this D plan.

Research remains optional/default-off. No new grant, Research event, or efficacy claim is introduced; ordinary nonparticipants create no Research rows. Durable SRS resume and shared-shell completion remain separate f13 work.



## Root review and execution board

- Root read the current SRS UI, actual start/rating/finish calls, generic DAO boundaries, the frozen srsRecall classifier and all six caller references. Shape B is approved; the narrow SrsReviewRepository capability interface is an explicit refinement of the initial no-extra-ports grounding suggestion. It uses the house Native/Configured capability pattern and the same DAO/private canonical writer, without a second store or unsafe generic fallback.
- Freeze public fields for UI/test coordination: SrsReviewSession.session/words/selection with id/ownerId/startedAtUtc getters; SrsReviewSelection.due/source; SrsReviewAnswerIntent.review/cardIndex/command; SrsReviewFinishIntent.review/endedAtUtc. Collections are copied and immutable; the repository registers original prepared instances. Exact capability method signatures are frozen on D before dependent UI fixtures are written.
- Replay preserves immutable attempt identity/context/outbox and creates no projection writes. There is no persisted per-attempt posterior SRS receipt: a returned SRS state is the current saved canonical projection, which may legitimately include later facts. Do not invent a frozen posterior cache or rebuild projections merely to acknowledge replay.
- Cover commit-then-lost-ACK before application notification, not only after the whole usecase returned. Deliver mutation/optional hooks at most once on the first confirmed original operation receipt, even when that receipt arrives through retry; never notify before top-level commit. The original in-process handle bounds this delivery state. No cross-process/external exactly-once-delivery promise or new event store is introduced.
- Keep the original prepare/usecase scope for that in-process handle; replacing LearningUseCases is a dependency invalidation, not permission to adopt its pending operations or redispatch effects. Delivery tracking may use weak original-handle state; it must not become a second learning/reward authority.
- Root owns final C integration/caller migration. Core and UI D workers have disjoint paths; repository/usecase tests precede actual UI and source/preview caller checks. Current source is unchanged at this planning checkpoint; no implementation, new table, migration reservation or production authority exists yet.
