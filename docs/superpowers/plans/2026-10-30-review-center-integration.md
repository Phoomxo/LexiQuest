# Review Center and owner-bound progress reads

Status: Root-approved next implementation card after [Wave20](../../field/2026-10-30-remaining-systems-wave20.md). The user authorized continued completion of remaining systems; scope, write set and acceptance checks are concrete. Root is the sole C writer; disjoint D test-first drafts may begin. No implementation or readiness upgrade is claimed at publication.

Baseline: cycle12-release, branch codex/remaining-system-readiness. Pushed attestation 8dd721ab28aff7dbdf8631d8f59010cf4b518dbc binds application dd45f8626add6d08c8e442fd3b54752023e30323: Flutter4372/analysis0/CLI23/backend390+one existing opt-in skip/normal APK and independent reviews. Schema20/37, frozen8/44 and all current contracts remain unchanged. Metadata HEAD has the identical verified lib/test/android trees. D grounding58ac2cf3, reviewed plan83ed926e and API sketchb0dbbe52 are design inputs, not implementation evidence.

## Outcome and boundaries

Implement the frozen f22 purpose: compose saved, ordinary incorrect, due-SRS, and local reported items while retaining every reason. Add real P06 ChooseMode and P08 Mastery entries required by TOR:251. Keep the approved 8/44 catalog, executable schema20/37, frozen evidence contracts, and all existing writers.

W20 supplies the explicit six-method SRS capability and guarded owned/preview screen; its engineering completion does not establish that all progress-host reads are owner-safe. This card must finish the hub's read boundaries and the three affected host read boundaries before claiming those surfaces ready. Research enrollment, transport, measurement, motivation scores, durable SRS resume, and broader AI/chat/document report targets remain outside this card. Local reports remain stored on this device and not sent.

## Current facts that determine the design

- Current SRS listDueWords at drift_learning_repository.dart:1925 joins the owned active category and orders by due time then ID. Review loading must not call prepareSrsReview/startSrsReview, or the removed ownerless wrappers, merely to obtain a count. The new SRS repository capability is an approved writer-specific exception; this hub needs no new repository port or writer.
- Ordinary History joins attempt and session on both IDs/owner, excludes activity assessment, and applies LearningEvidenceContract.validEvidenceMetadata (drift_learning_history_queries.dart:30/63/116/128). Incorrect means an actual valid ordinary isCorrect=false fact. Existing Weakness is narrower masterySrs-eligible ranking (drift_progress_queries.dart:40/51/212); do not broaden that projection to populate this list.
- SavedWordsUseCases.watchOwner and DriftSavedWordsRepository preserve saved intent with LEFT JOINs. Missing/deleted words or categories remain unavailable saved items. isSaved=false rows are tombstones/state, not queue entries. Reuse decoded SavedWordItem/StoredSavedWordState, including original CAS facts for the separate management screen.
- WordReportUseCases.watchOwner returns immutable StoredWordReport receipts with original target/revision/hash/reason/comment/time. Reports remain separate by report ID after edit/delete/merge; never substitute a current spelling match or train from receipt.target/snapshotJson. WordReportDetails already renders the receipt.
- Concrete host gap: ChooseMode caches _load before owner binding (:107/224); Clinic changes _generation/_ownerId but leaves _load (:78/117/143); Mastery caches loader results without an owner subscription (:34-70). Existing ProgressUseCases.load calls getOrCreateActiveOwner (:23). Guarded W20 launch callbacks do not clear these old counts/spellings. MainNavigation keeps these hosts mounted with IndexedStack/Visibility.maintain (:155).
- Existing AppBootstrap.initialize constructs DriftLocalOwnerRepository and explicitly awaits getOrCreateActiveOwner before host/progress composition (app_bootstrap.dart:401-406). Preserve that initialization boundary. Owner-bound hub/host reads require no new bootstrap owner authority and must not repeat owner creation merely to load a view.
- Current DriftProgressQueries due count and weakness word joins still omit active-category eligibility. Align only these joins with current canonical SRS/vocabulary eligibility; keep their evidence filters, ranking and numerical authorities unchanged.

## Exact read API and immutable composition

New files under features/progress, using the same AppDatabase:

1. domain/review_center_models.dart: ReviewQueue {due, incorrect, saved, reported}; immutable ReviewCenterSnapshot(ownerId, evaluatedAtUtc, wordRows, reportRows, queueStates). ReviewQueueState distinguishes loading, ready(count), and unavailable(code); unavailable has no zero count. Copy every list/set/map.
2. A ReviewWordRow retains wordId, optional current owned VocabularyWord/categoryName, and immutable reasons. DueReason carries dueAtUtc; IncorrectReason carries actual incorrectCount/lastIncorrectAtUtc; SavedReason carries the existing StoredSavedWordState. One current word can have all three reasons. A missing current word can retain saved/incorrect intent, is unavailable for practice, and displays no invented historical spelling. Unsaved tombstones never add a reason.
3. ReviewReportRow retains one existing StoredWordReport, keyed by report ID. It is not folded into the word row, even when word IDs coincide. Historical details say not sent. Report rows expose receipt details and the existing reports-history route, not practice from the snapshot.
4. data/drift_review_center_queries.dart: watchOwner({required String expectedOwnerId, required DateTime evaluatedAtUtc, required bool Function() stillCurrent}) returns immutable due/incorrect read facts and current owned word/category snapshots. Due uses owner+word+active-category eligibility and dueAt<=evaluatedAt. Incorrect uses the actual History owner/session/metadata predicate before aggregation; LEFT JOIN current vocabulary so unavailable historical IDs survive. Stable ID/time ordering; no hidden 20-card hub truncation.
5. application/review_center_use_cases.dart: watchOwner({required String expectedOwnerId, required bool Function() stillCurrent}) composes that query with existing saved/report streams. Subscribe to the real ProgressUseCases.watchActiveOwnerId before reading, reject initial mismatch/null/error/done, and keep a sticky generation for that subscription. Validate active owner with read-only SELECT before and after each awaited read/emission; check the captured caller generation too. Never call getOrCreateActiveOwner or an owner-write transaction for loading. A read-only SQL snapshot transaction is acceptable; it must not mutate any of37 tables.

Section failures remain explicit: if the due/incorrect query fails, those sections are unavailable while ready saved/reported sections may remain visible. Drop the failed section's old facts; do not relabel failure as an empty queue. Owner invalidation clears every section. Show per-reason counts, distinct current/unavailable word counts, and report-receipt count separately; summing reasons is not a unique-word total.

Use the same captured evaluatedAtUtc for one read generation and show its evaluation time. Explicit refresh, return from practice, and a newly accepted foreground generation recapture the clock. Do not add background scheduling merely for this card. Use lazy rows for the full local result, preserve all local intents, and avoid a new cache or copied persistent queue.

## Required host read correction

Add to existing ProgressUseCases, not a second statistics usecase:

    Future<ProgressSnapshot> loadForOwner({
      required String expectedOwnerId,
      required bool Function() stillCurrent,
    });

It checks the same database's current active owner before and after awaited queries.load(ownerId: expectedOwnerId, nowUtc: capturedNow), checks stillCurrent at each boundary, and returns no result on mismatch. It has no owner creation, mutation callback, learning write, or recomputation with a new authority. Keep other load/loadHistory consumers outside this bounded migration.

Migrate ChooseMode, Mastery and Clinic production loaders to loadForOwner. Reuse Choose/Clinic owner bindings; add optional ownerChanges injection plus a real runtime subscription to Mastery. Do not start a load until an actual owner is observed. Keep a readEpoch for rows, counts, filters, pending reads and pre-push row actions. Any cover, including the screen's own child push, increments readEpoch and clears private read rows/actions synchronously; only redraw is deferred/coalesced. Hidden panes, owner null/ABA/error/done, background and dependency/source replacement also clear those reads. Every awaited read response checks its captured owner/readEpoch/dependency. A FutureBuilder must not display cached old data while a new owner future is pending; use an epoch key or explicit cleared state.

Keep a separate owner/dependency/lifecycle launchGeneration for an explicitly owned child push and its guarded return intent. Before pushing, require the parent route current plus a current readEpoch/row, then capture immutable IDs, owner, same ownerChanges stream and same LearningUseCases. After the own push covers the parent, child builders and canonical-operation predicates must not depend on the parent's route.isCurrent, cleared rows or readEpoch. Follow SavedWordsViewBinding.ownerGeneration distinct from its read generation and SavedWordsScreen._practice's launch checks (saved_words_screen.dart:46-47/641-665). This is transient launch ownership, not another cache or authority. Only that tracked own push is exempt from burning launchGeneration; a foreign cover, hidden pane, owner change/ABA/error/done, lifecycle loss or dependency/source replacement burns the return intent. Each child retains its own existing route/owner/write guards. Never preserve an intent merely because the parent was already covered.

The top-level hosts may accept a new observed owner only as a fresh read generation; old callbacks never become valid again after A/null/A. The hub route remains bound to its captured expectedOwnerId and requires an explicit fresh read/open after invalidation. Preserve the existing optional test loaders but require explicit owner fixtures and apply the same before/after generation guards; do not relax production missing-owner behavior to retain old fixtures.

## Screen and actual routes

New screens/review_center_screen.dart constructor: required expectedOwnerId; optional reviewCenter, ownerChanges, learning, savedWords, wordReports, voice, featureRegistry and languageCode='th', resolved once from AppDependencies when omitted. The screen binds the same instances for its lifetime; replacement invalidates. All/each-reason filters, loading/error/empty/unavailable rows, truthful counts, refresh, real details and practice must work offline.

- Add P06/P08 Review Center entry using AppNavigator route learning/review-center. Capture observed owner/generation and require the host route current before push. New entry counts come from owner-bound hub facts, never a cached old ProgressSnapshot. Existing host navigation/feature visibility remains; practice checks the existing srs/quiz flags. No new FieldFeature enum or catalog row is needed.
- Due action explicitly reviews the current due queue (up to the canonical20-card practice batch) through SrsFlashcardsScreen(expectedOwnerId, ownerChanges, same learning, borrowed voice). Do not label a full-queue launch as review of one chosen word. Do not replace due recall with Meaning Quiz.
- Saved targets use existing QuizScreen sourcePractice selection; incorrect targets use QuizWordSelectionMode.weakness, which maps to canonical weaknessPractice. Pass the captured expectedOwnerId, same ownerChanges stream and same LearningUseCases to that child, following SavedWordsScreen's guarded launch; validating only the hub click or IDs does not pin awaited child preparation. Resolve current owned IDs/content and preserve canonical plan/start/answer/finish writers. Label any canonical20-target practice batch explicitly while retaining the full hub list. A historical recreational mistake may be displayed without becoming mastery-eligible; a separately requested new practice produces only its own canonical evidence.
- Display current word meaning/POS/category in the hub. Reuse SavedWordsScreen for removal/management, WordReportsScreen/WordReportDetails for receipts, and ordinary History for historical activity. No new detail writer, unsave implementation, report submission, or sent/resolved transition.
- Per-row retained callbacks capture immutable row identity/revision and owner/readEpoch; they must be valid at the initial tap. On an own practice/detail cover, hide private parent rows/actions and retain only the separate launchGeneration-bound child/return intent. Pass the same real owner stream, captured owner and same LearningUseCases to SRS/configured Quiz; do not feed a parent route-current/readEpoch predicate into the child's accepted operations. A valid own return requires the expected parent route current and launchGeneration still valid, then starts a fresh readEpoch and canonical read. Foreign covers or owner/lifecycle/dependency loss burn the return intent and cannot auto-pop another route, resurrect stale results or replay a pending command.

## Write set and test-first cards

New production: the three progress files above and screens/review_center_screen.dart. Existing production: runtime/app_dependencies.dart, runtime/app_bootstrap.dart, progress/application/progress_use_cases.dart, progress/data/drift_progress_queries.dart, screens/choose_mode_screen.dart, mastery_dashboard_screen.dart, weakness_clinic_screen.dart. Bootstrap injects the existing database/saved/report/progress instances and preserves its existing owner initialization; add no new owner-creation path. No table, migration, dependency, outbox type, sync payload, owner inventory, event envelope, repository port or parallel learning/reward authority.

New tests: test/features/progress/review_center_queries_test.dart, review_center_use_cases_test.dart, test/screens/review_center_screen_test.dart; optional unique test/support/review_center_harness.dart reusing the existing real database/owner fixtures. Update current progress-owner/deleted-vocabulary and three host test modules only for the new guarded contracts. Preserve existing History/Saved/Report/SRS assertions.

Run these meaningful RED cases before implementation:

1. One word due+incorrect+saved retains three independent source facts; two reports for different revisions stay separate after edit/delete/guest dedup. Unavailable saved/incorrect rows survive; unsaved tombstones do not enter the queue; due excludes deleted/foreign categories and has stable tie order.
2. Ordinary valid recreational wrong answers appear as historical mistakes without changing mastery/SRS/XP/rewards/effort. Assessment, malformed evidence, orphan/foreign session joins and other-owner rows are excluded. Do not use Weakness ranking as the ordinary incorrect queue.
3. Exact before/after snapshots of all37 tables for open/filter/refresh/reopen, all section failures and missing-owner/dependency paths. Zero mutation/quest/streak/research events. Include a database with no active owner and prove no implicit new owner. Reports stay not sent; read never prepares a mutation identity.
4. Actual owner A/null/A and A/B/A during awaited reads/emissions; synchronous invalidation from a sibling persistent-frame Builder; stale row/entry callbacks; stream error/done; hidden IndexedStack; foreign route; lifecycle; dependency replacement; old response after a newer refresh. No old private row/count or foreign navigation survives. All three hosts must clear cached old-owner data and use fresh guarded read generations.
5. Real P06/P08 entry and each practice/detail route. Prove the own child cover clears private parent rows/actions while the child still confirms canonical start/rating/finish ACKs on its own scope; a parent readEpoch change alone cannot cancel it. Recognition uses the existing configured writer once. Prove foreign cover/owner ABA/lifecycle/dependency loss burns the separate return intent and old callbacks, without popping a foreign route. Opening/filtering does not start a session, unsave a word or alter report receipts. A valid own return reloads actual reasons/counts in a fresh readEpoch.
6. Thai/English320px/200%, long labels, IME-safe reachability, actual keyboard activation/focus and Reduced Motion where relevant. Use host-scoped actual scrollables and layout/route readiness; keep timer invariants. Any real Drift stream fixture must subscribe/cancel in its captured I/O zone. Preserve caller transaction values in the synthetic notification probe scheduler; retain its actual SQL positive control.

Serialize focused queries/usecases, then hub/host UI and touched History/Saved/Report/SRS regressions. At the integration checkpoint freeze current source, review, run required analysis/full/backend/CLI/build checks, and bind receipts to that source. No W20 evidence automatically attests this later card. Keep engineering completion, local feature coverage, physical-device/UAT, rollout permission and research authority separate.

## Root execution board

Root reviewed actual sources and both D proposals and accepts this card. f22 remains Partial and the matrix remains13Connected/19Partial/12Missing until later evidence changes it. This fixes the confirmed three-host stale-owner read gap and adds the missing combined runtime; it does not certify production, Research or hardware/UAT.

The core D worker owns new progress models/query/composer, existing ProgressUseCases/DriftProgressQueries and new unit fixtures. The UI D worker owns only the new ReviewCenterScreen and its new screen tests after the model/API freeze. Root owns AppDependencies/bootstrap, the three host screens and existing fixture migrations. Root promotes all C edits and serializes Flutter/pub/codegen/analysis/full/build. One writer per file.

Freeze the public contract below before dependent tests. First prove actual old-owner rows/counts and retained callbacks fail on old hosts. Query/usecase negatives use the real database, ordinary receipts and explicitly historical corrupt fixtures. API compile RED is distinct from behavioral failure. Focused checks precede current-source review, full regression and release attestation. No new deployment or research authority is introduced.

## Contract coordination: immutable public data

These types belong in lib/features/progress/domain/review_center_models.dart. VocabularyWord means the existing domain type from features/vocabulary/domain/vocabulary_word.dart, not Drift's generated row. Every list/set/map is defensively copied and unmodifiable.

| Type | Exact public fields or getters |
| --- | --- |
| ReviewQueue enum | due, incorrect, saved, reported |
| sealed ReviewWordReason | ReviewQueue get queue |
| DueReason | DateTime dueAtUtc; queue=due |
| IncorrectReason | int incorrectCount; DateTime lastIncorrectAtUtc; queue=incorrect |
| SavedReason | StoredSavedWordState state; queue=saved |
| ReviewWordRow | String ownerId; String wordId; VocabularyWord? word; String? categoryName; List<ReviewWordReason> reasons; bool get isEligible; Set<ReviewQueue> get queues |
| ReviewReportRow | StoredWordReport report; String get reportId |
| ReviewReadFacts | String ownerId; DateTime evaluatedAtUtc; List<ReviewWordRow> wordRows |
| sealed ReviewQueueState | No generic count getter |
| ReviewQueueLoading | No fields |
| ReviewQueueReady | int count |
| ReviewQueueUnavailable | ReviewReadFailureCode code |
| ReviewReadFailureCode enum | dependencyUnavailable, readFailed, ownerInvalidated |
| ReviewCenterReadException | ReviewReadFailureCode code, with no raw SQL/owner/content message |
| ReviewCenterSnapshot | String ownerId; DateTime evaluatedAtUtc; List<ReviewWordRow> wordRows; List<ReviewReportRow> reportRows; Map<ReviewQueue,ReviewQueueState> queueStates; int get distinctWordCount; int get eligibleWordCount; int get unavailableWordCount; int get reportCount |

Constructors use named required fields, except the paired nullable word/categoryName. Rules:

- Each word row has a nonempty unique-kind reason list. word and categoryName are both present or both null. If present, word.id/ownerId match the row, word is active, and the query proves its category is active and owned. isEligible means this current read has that pair; it is not a write grant.
- SavedReason reuses the complete decoded existing state and requires isSaved=true with matching owner/word. Unsaved tombstones never become reasons. The hub does not prepare mutations from this state; management stays in SavedWordsScreen.
- IncorrectReason requires positive actual incorrectCount and the latest stored incorrect timestamp. It does not carry a mastery score or change eligibility.
- ReviewReadFacts permits only DueReason/IncorrectReason. Due keys always have an eligible current word. Incorrect historical IDs survive with a null current pair; display unavailable, not invented historical spelling.
- Snapshot rows are unique by wordId, report rows by report.id. Every owner matches the enclosing ownerId. queueStates contains exactly all four queues. Ready counts are unique word IDs for due/incorrect/saved and receipt IDs for reported. An unavailable queue has no zero count. Derived word totals count the visible union, not the sum of reasons, and exclude report receipts.
- Due/count evaluation uses one nonnegative UTC millisecond evaluatedAtUtc for each subscription generation. Individual saved/report/evidence timestamps remain their actual stored timestamps. This is ordinary local scheduling, not Research trusted time.
- StoredWordReport and its original target/hash/revision/reason/comment/time remain unchanged. Report rows stay separate even when word IDs coincide; UI says stored locally/not sent. No new sent/resolved field exists.

When the ordinary query and SavedWordItem supply the same current word, their full domain facts/category must agree before merging current display data. Do not choose the largest timestamp/revision as a replacement authority. If current snapshots disagree, preserve reasons and temporarily make that word unavailable until a fresh matching read. A failed ordinary section drops its old facts; a ready Saved section can still use its own already-decoded current SavedWordItem. Both read the same canonical vocabulary tables.

## Two exact stream APIs

Existing source seams remain SavedWordsUseCases.watchOwner(String)->Stream<SavedWordsSnapshot> and WordReportUseCases.watchOwner(String)->Stream<List<StoredWordReport>>.

Proposed constructors and read signatures:

```dart
DriftReviewCenterQueries(AppDatabase database);

Stream<ReviewReadFacts> watchOwner({
  required String expectedOwnerId,
  required DateTime evaluatedAtUtc,
  required bool Function() stillCurrent,
});

ReviewCenterUseCases({
  required DriftReviewCenterQueries queries,
  required ProgressUseCases progress,
  required SavedWordsUseCases savedWords,
  required WordReportUseCases wordReports,
  required DateTime Function() nowUtc,
});

Stream<ReviewCenterSnapshot> watchOwner({
  required String expectedOwnerId,
  required bool Function() stillCurrent,
});
```

The first watchOwner belongs to DriftReviewCenterQueries, which exposes final AppDatabase database. The second belongs to ReviewCenterUseCases, whose final constructor fields are queries/progress/savedWords/wordReports/nowUtc. Each call returns a single-subscription stream for one read generation. Explicit refresh cancels/recreates it and captures a new clock value. Composition state exists only inside that subscription and is discarded on close; there is no cross-generation or persistent cache.

The application composer subscribes to the real progress owner stream before data sources. The query and progress usecases must share AppDatabase; bootstrap supplies the same existing saved/report instances. Initial mismatch/null, owner ABA/error/done, caller invalidation, or a mismatched owner payload clears all rows and terminates with ownerInvalidated. A fresh subscription/open is required. It cannot transparently adopt another owner.

Before and after awaited reads/emissions, verify the actual active owner with read-only SELECT and the captured stillCurrent predicate. An absent/ambiguous active owner fails closed. Do not use getOrCreateActiveOwner or an owner-write transaction. A read-only SQL snapshot transaction is allowed.

Query read failure/done makes due and incorrect unavailable and drops their old facts; saved/report source errors affect only their own sections. Other ready sections remain visible. Owner invalidation is global, never a partial section error. Retrying a failed source uses an explicit fresh read generation.

Ordinary incorrect query uses the actual History predicate: attempt/session ID and owner join, non-Assessment session, validEvidenceMetadata, isCorrect=false. Preserve unavailable IDs with LEFT JOIN. Do not reuse the narrower masterySrs Weakness ranking or History's50-session page as a complete queue. Due uses the existing active owned-category eligibility and stable dueAt/ID ordering. No hidden20-row list limit.

## Screen, host, and launch scope

ReviewCenterScreen keeps the plan's constructor: required expectedOwnerId; optional reviewCenter, ownerChanges, learning, savedWords, wordReports, voice, featureRegistry, languageCode='th'. Resolve defaults once from AppDependencies. Missing required runtime dependencies are unavailable, not an empty queue or a new default service.

Capture the resolved actual ownerChanges Stream instance, ownerId, and LearningUseCases once for each launch. Forward those same objects to SrsFlashcardsScreen and QuizScreen. Never replace them with a new usecase, a static Stream.value(owner), or another owner store. Internal application owner validation watches the same ProgressUseCases database authority; it does not authorize a child.

All four surfaces, including ChooseMode, Mastery and Clinic, need two lifetimes:

- readEpoch changes on every cover, including an owned child, and clears private rows/counts/filters/read callbacks synchronously. Rendering may be deferred safely. Old FutureBuilder data cannot satisfy a new pending read; use the binding key or explicit cleared state.
- launchGeneration tracks owner/dependency/lifecycle validity separately. At the initial tap require current parent route and current row/readEpoch. Capture immutable IDs/revision and the exact tracked own child route. That own cover clears reads but does not burn its valid child/return intent. Child builders and operations must not depend on parent readEpoch, retained rows, or parent route.isCurrent after push.
- A foreign cover, hidden pane, owner null/ABA/error/done, lifecycle loss, or dependency replacement burns the launch intent. Being already covered is not an exemption. A valid own return requires the intended parent route current, then creates a fresh readEpoch/read. It cannot auto-pop an unrelated route.

Add the plan's named method to existing ProgressUseCases:

```dart
Future<ProgressSnapshot> loadForOwner({
  required String expectedOwnerId,
  required bool Function() stillCurrent,
});
```

It performs the same pure active-owner checks before/after queries.load. Migrate production loaders of ChooseMode, Mastery and Clinic; Mastery adds optional ownerChanges injection. Existing optional test loaders require explicit owner fixtures and the same before/after read-generation guards. Bootstrap already initializes the actual owner at app_bootstrap.dart:401-406; do not add read-time creation or another bootstrap authority.

Due launches the complete current canonical batch up to20 through the existing SRS path. Saved uses sourcePractice; incorrect uses the existing weakness selection. Labels must distinguish those batches from the full queue. Reports offer existing historical details only, never practice from receipt.snapshotJson. A newly requested practice uses only its own canonical evidence.

## Real database harness seams

Proposed test-only ReviewCenterHarness, constructed through the normal AppDatabase/NativeDatabase executor with an optional QueryInterceptor, not an AppDatabase subclass. Expose database, owners, ownerWrites, progressQueries, progress, savedWords, wordReports, queries, reviewCenter, learningRepository, learning, a captured real ownerChanges stream, injected now/current, snapshotAllTables(), switchOwner(), and close().

Use two synthetic owners with only one active, real owned vocabulary, the current canonical learning/SRS writer, SavedWordsUseCases and WordReportUseCases. Helpers can seed due+ordinary incorrect+saved overlap, an ordinary recreational wrong answer, unavailable saved/history IDs, two immutable report revisions, and explicit corrupt/foreign/Assessment negative rows. No valid Research authority is fabricated. snapshotAllTables compares all37 tables. UI fixtures forward the exact harness learning/owner stream to children and preserve the proven real-I/O subscription/teardown and caller-zone notification probe controls.

Minimum agreement checks before source work: defensive-copy invariants; three reasons on one word; distinct report revisions; unavailable IDs; partial failures versus empty; ordinary History eligibility; zero mutations on read; owner/late-read/ABA across all three hosts; owned child survives parent read clear while foreign cover burns its return; canonical20-card limits only on practice; Thai/English200-percent keyboard layouts. This coordination boundary does not change readiness counts; completion requires the current-source evidence above.
