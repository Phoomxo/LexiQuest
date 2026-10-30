# Cloze integration plan

Baseline: `bfa766b3`, branch `codex/remaining-system-readiness`, worktree
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`. The Native
checkpoint records 3350 full Flutter tests passing, analysis 0 and a successful
debug APK. This is the single executable Cloze plan; earlier design sketches
are historical. Isolated D prototypes may progress while C is frozen. Promote
source only after root completes Native attestation and pushes that checkpoint.

## Execution board

Unit1 is integrated after the pushed wave12 attestation. Migrated caller tests
first failed on missing APIs, then the shared Dictation-only lifecycle passed417
learning/sync/UI checks and analysis found no issues. Independent source review
accepted it. The mechanical proof preserves465 test assertions/string literals
and six canonical DTO declarations. No Cloze behavior, new schema or content
provider has been introduced; parser/projection/core and UI remain queued.
Evidence: cloze-native-lifecycle-api-red.log,
cloze-native-lifecycle-parity-green.log, cloze-native-lifecycle-analysis.log.

## Outcome and boundaries

Add one quiz-gated ChooseMode entry: owned category → one accepted generated
contextual gap → one canonical answer → explicit finish and actual summary.
Typed and selected variants have distinct evidence. Reuse the existing learning
writer, owner lifecycle, ContentProvider and tables. No new schema, registry,
provider framework, reward authority, frozen metadata field or Research gate.
No Pair Matching or restart/resume is included.

Current `FillInTheBlanksScreen` takes a raw word, generates a sentence, shuffles
every token and scores locally. Its only caller is WordScramble's obsolete
automatic next-screen edge. Canonical QuizWord/VocabularyWord/SQL word rows have
no example sentence. Unlinked CEFR examples are not an owned content reference.

## Accepted content and evidence

The pure `ClozeContent.parse({required String targetSpelling, required
ContentResponse response})` prototype imports only `ai_models.dart` and
`dart:convert`, with a private constructor and immutable primitive fields:
sentence, half-open UTF-16 gapStart/gapEnd, actual kind/cefr/language/modelVersion/
cached, plus derived prefix/gapText/suffix. It has no content hash or authority.

Local admission requires kind=sentence and exact language=en; one ASCII lexical
target of at most 120 characters, allowing internal apostrophe/hyphen; exactly
one case-insensitive whole-token occurrence and another lexical context token.
ASCII-only folding preserves offsets. Conservative explicit delimiters reject
subwords beside Latin accents, Greek, digits or lexical connectors, while
allowing quoted targets. Bound the original sentence to 1024 runes/2048 UTF-8
bytes and modelVersion to 120 runes/256 bytes. Reject empty data, markup,
controls/bidi/invisible formatting and invalid surrogate scalars with a fixed
safe FormatException. Trim outer spaces; preserve inner text and exact gap case.
Preserve actual CEFR, including unknown, and cached status. None of these checks
claims grammatical quality, validated A2 content or curriculum approval.

Read generation through the existing ContentProvider outside the owner
transaction. Request its sentence/en/A2 parameters using the real spelling;
retain the actual ContentResponse metadata. Missing configuration, unsupported
content, request failure, missing target or insufficient choices produces an
explicit unavailable/empty state and no session. No invented sentence/template,
unlinked example, different-category target or raw-word fallback. Do not
regenerate or replace accepted content after the session starts.

Choose the variant before preparation. Selected mode freezes the target plus
two distinct actual same-category owned distractors, their revisions and order;
with fewer choices selected mode is unavailable while typed can still prepare.
Declare generated `clozeTyped` as guidedPractice/hint1 and `clozeChoice` as
recognition/hint0, skill `cloze-context`, engagementAllowed=false. Both retain
session/history/effort, with no SRS, XP, coins, achievements, Quest or Streak.
Do not promote generated typed responses to independent recall or invent a
trusted reference. Keep the frozen catalog and EvidenceContext/EventEnvelopeV2.

## Shared closed domain and exact API

Unit 1 introduces only the existing Dictation case. Unit 2 adds Cloze cases
after the parser is verified; no future-case stubs.

```dart
sealed class AcceptedNativeExercise {
  LearningSessionDraft get session;
  QuizWord get word; // retain the existing public name
  String get wordContentRevision;
  String get evidenceContentRevision;
}
final class DictationSession extends AcceptedNativeExercise { /* existing data */ }
sealed class ClozeSession extends AcceptedNativeExercise { ClozeContent get content; }
final class TypedClozeSession extends ClozeSession { /* typed gap */ }
final class ChoiceClozeSession extends ClozeSession { List<QuizWord> get choices; }
```

Collections are immutable copies. `NativeAnswerInput` is sealed: Dictation input
carries its DictationSession, response, assisted and responseTime; typed Cloze
input carries its TypedClozeSession, response and responseTime; choice input
carries its ChoiceClozeSession, optionId and responseTime. This couples the
concrete exercise to valid input without nullable mode fields. Raw responses
remain transient. Callers never supply correctness, evidence class or approval.
One NativeFinishIntent holds exercise, original answer and original endedAtUtc.

Both NativeExerciseRepository and LearningUseCases expose this lifecycle:

```dart
Future<T> startNativeExercise<T extends AcceptedNativeExercise>(T exercise,
    {required bool Function() stillCurrent});
Future<AnswerRecordResult> commitNativeAnswer(AcceptedNativeExercise exercise,
    RecordAnswerCommand command, {required bool Function() stillCurrent});
Future<LearningSessionSummary> finishNativeExercise(NativeFinishIntent intent,
    {required bool Function() stillCurrent});
```

Start returns the **same T object after ACK**. LearningUseCases additionally
provides specialized read-only prepareDictation and prepareCloze(categoryId,
variant, stillCurrent), synchronous prepareNativeAnswer(NativeAnswerInput), and
prepareNativeFinish(exercise, answer). Shared preparation derives classification
and correctness, captures ID/time once, bounds latency and checks clock order.
The UI retains the original exercise/answer/finish objects across lost ACKs.

Keep Dictation's current session prefix and persisted values unchanged. Add one
distinct Cloze prefix; the generic startSession/recordAnswer/finishSession APIs
reject both explicitly. One Expando process binding tracks original start,
answer and close identity. A copied/restarted handle cannot adopt an existing
bare row. Migrate callers and delete DictationRepository, DictationFinishIntent
and the old post-preparation Dictation methods in the same unit; no aliases.

SQL proof always compares `wordContentRevision` (and each choice's actual word
revision/category/spelling) with joined owned, nondeleted SQL rows. It must
never compare that value to Cloze's `evidenceContentRevision`. The latter is
`cloze-v1:SHA256(canonical JSON)` over version, target ID/category/spelling/word
revision, accepted sentence/gap/actual metadata, variant and ordered choice
pins. The accepted exercise owns that one digest. Use the existing compact
providerProvenance field within its 120-rune bound; no second parser authority.
Dictation derives both revision getters from its current word pin unchanged.

Generalize the existing private Dictation transaction/binding/session/attempt/
outcome/command/summary helpers once. One writer uses exhaustive concrete-type
validation and the canonical private start/record/finish methods. Preserve
ambient-transaction rejection, owner/deletion fence, before/after SQL target
proofs and final synchronous stillCurrent. No provider I/O enters the transaction.
Historical exact ACKs return saved facts without regenerating content, changing
time or reinterpreting the original answer after later target edits.

## Disjoint units and file ownership

1. **Core migration, one writer:** learning_models.dart, learning_repository.dart,
   learning_use_cases.dart, drift_learning_repository.dart, Dictation screen and
   its actual callers/tests/harness. Add only Dictation's sealed exercise/input
   and shared lifecycle. Preserve current assertions, native prefix, metadata,
   effects and exact-object start return before adding Cloze behavior.
2. **Cloze content/core, same core owner sequentially:** new
   `lib/features/learning/domain/cloze_content.dart` and its pure tests first;
   then Cloze types/input, optional existing ContentProvider injection and
   prepareCloze/proof branches in the core files. Parser and core have separate
   file ownership. Verify the parser's real RED/GREEN before adding those cases.
3. **Projection, disjoint writer:** current_activity_evidence.dart,
   learning_evidence_contract.dart, drift_reward_projection_rebuilder.dart and
   drift_progress_queries.dart, plus projection/carry/sync tests. Explicitly
   admit only current declarations for dictation/clozeTyped/clozeChoice. Update
   malformed native-source carry exclusion for that set. Keep other ordinary,
   inferred, independent remote SRS and Assessment paths unchanged. Draft units
   2/3 in parallel if useful; integrate new Cloze capture and its safety floor
   together before exercising canonical Cloze writes in C.
4. **UI/composition, disjoint after migration:** choose_mode_screen.dart,
   fill_in_the_blanks_screen.dart, app_bootstrap.dart, learning_history_screen.dart
   and the small WordScramble edge removal. Bootstrap owns/disposes the existing
   managed content client; screens use application boundaries. Remove unused
   sentence_service.dart/sentence_model.dart after exact caller migration and
   Git backup. Preserve WordScramble's existing scramble/reduced-motion tests.

UI uses current Material/Thai/English copy, one masked sentence, a typed field
or accessible options, explicit save/finish and truthful saved feedback/summary.
Owner null/error/done/A→B→A, route/lifecycle/binding changes and disposal burn
the epoch; no stale content/feedback/navigation. Freeze answer/finish before
awaits. Back never finishes. No mandatory voice or reward promise. Keep 320px/
200% keyboard reachability and scroll real lazy content before UI assertions.

## Acceptance and integration

- RED first for exact gap/metadata/bounds, wrong kind/language, repeated/missing/
  partial target, immutable choices/hash and no fallback. Failed/stale
  preparation leaves canonical facts unchanged.
- Prove existing Dictation assertions survive the shared-lifecycle migration,
  including same-object generic-T start ACK, normal/assisted projections, clock
  order, generic-API bypasses, original handles and lost start/save/finish ACKs.
- Drive both Cloze variants through actual category/provider fixture/Drift/UI,
  correct and wrong answers, rapid taps/IME and explicit finish: exactly one
  attempt and immutable original times, no raw response persistence.
- Compare SRS/XP/coin/achievement/Quest/Streak state for both new classes,
  exact replay, malformed native carry and actual SyncStore alias/replay.
  Preserve independent remote SRS and old ordinary/Dictation facts byte-for-byte;
  no fabricated zero SRS, duplicate hook or outbox operation.
- Hold content/writer awaits and mutate owner, category/target/choice revision,
  deletion fence, route or lifecycle. Prove rollback before final commit and
  no private delivery afterward; preserve already committed original facts.
- Verify history, owner export/deletion and existing v2 sync metadata; a
  nonparticipant adds no Research/Assessment rows/events/operations. No new
  collection or upload authority is introduced.

Root serializes current-snapshot focused checks, ordinary/Research regression,
analysis and normal build. Real service availability, device UX and any content
or efficacy validation remain separately attested. Engineering tests do not
authorize real research enrollment/upload or mark the whole catalog ready.
