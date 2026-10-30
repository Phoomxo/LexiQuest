# Sentence Scramble integration plan — P34

**State:** Reviewed implementation plan after [Wave17](../../field/2026-10-30-remaining-systems-wave17.md). Baseline application `158d2115a2eee800e0a5dfe5a97d1c77d0c9eb26`, schema20/37, Flutter4029/analysis0/backend390+one existing opt-in skip/CLI23 and normal debug APK verified. Commit/push that predecessor checkpoint before C implementation. No new table, field, dependency or v21 reservation is required. Grounding `sentence-scramble-grounding.md` SHA461BBFC913BB6A4F60FA51EDBD9EC2913A27BB6CCD790026C474AAC4E2FD8437 remains in the D maintenance evidence root.

## Outcome and limits

P18 → owned category → actual provider-generated sentence → arrange words or type → canonical save ACK → explicit finish ACK → real outcome/history. Replace the orphan raw SentenceScrambleScreen; do not reintroduce delayed P33/speech navigation. TOR P34 specifies arranging words, not a translation provider. P23 returns a real summary without duplicate progress.

This is recreational ordinary learning. f13 stays Partial: durable native restart/resume and shared results/shell remain separate. f21 remains Partial/local queued reports; this unit adds no AI-sentence reporting, transport, enrollment or Research authority.

## Content and exact types

Reuse existing nullable ContentProvider and Cloze preparation shape: bounded count1 owned-word keyset selection, exactly one actual sentence request per prepare through the same configured client, no ambient transaction/provider IO inside SQLite, final owner/current checks after every awaited boundary. Never generate in a per-word loop or issue fallback network requests. Missing provider/target, invalid content or superseded launch returns unavailable without a session. Preserve returned kind/language/CEFR/modelVersion/cached; request A2 is a request, not validation of generated level.

Add only:
```dart
SentenceScrambleContent.parse({
  required String targetSpelling, required ContentResponse response,
});
SentenceScrambleSession({
  required LearningSessionDraft session,
  required QuizWord word,
  required SentenceScrambleContent content,
}); // extends AcceptedNativeExercise
SentenceScrambleAnswerInput({
  required SentenceScrambleSession exercise,
  required String response, required Duration responseTime,
}); // extends NativeAnswerInput
Future<SentenceScrambleSession?> prepareSentenceScramble({
  String? categoryId, required bool Function() stillCurrent,
});
```

The owned word is an **anchor**, not the whole answer. Content exposes the canonical full sentence, immutable ordered chunks and actual metadata; session exposes immutable bank indices, namespaced content hash and bounded hashed model provenance. Use activity/prompt `sentenceScramble`, skill `sentence-scramble`, prefix `session:sentence-scramble-v1:`. Hash anchor ID/category/spelling/meaning/POS/local revision, canonical sentence/chunks/bank and returned metadata; no fake sentence ID or alias word.

Reuse Cloze bounds: raw sentence1024runes/2048UTF8bytes, seed spelling120, opaque model version256runes/256UTF8bytes. Admit kind sentence/language en and a genuine bounded lexical anchor occurrence using conservative boundary rules; a repeated anchor is not automatically a Cloze-style duplicate-gap error. Preserve every original whitespace chunk as an indexed piece, including standalone punctuation; require2–64 total chunks, at least2 chunks containing a Unicode letter/number, and a visibly different ordering. These are resource limits, not linguistic validation.

Bound raw input before normalization. Normalize Unicode White_Space separators, including tabs/newlines, once to ASCII spaces and trim before rejecting other controls. Retain Cloze's conservative format/bidi/zero-width/surrogate/markup exclusions; no ZWJ or Thai-segmentation support claim. Keep punctuation attached to its original chunk; preserve apostrophes, hyphens, ordinary combining sequences and case. Do not split code units or strip punctuation. Typed comparison uses the same input bounds/whitespace normalization and otherwise exact canonical text. Label punctuation/case expectations. Duplicate-text chunks have distinct indices; a stable bounded rotation/permutation is computed once, never rerandomized on Clear/retry. Reject an unchanged bank rather than inventing content.

ContentProvider has no sentence translation. Show the owned word's meaning explicitly as vocabulary meaning, not a sentence translation. Optional existing voice may read the actual frozen sentence; that reveals order and does not change recreational classification.

## Canonical lifecycle and boundaries

Use existing `startNativeExercise<T>`, `prepareNativeAnswer`, `commitNativeAnswer`, `prepareNativeFinish`, `finishNativeExercise`; add sealed cases, not another repository/registry/writer.

Extend reserved-prefix checks in all three generic start/record/finish gateways. Native SQL verifies original session owner/activity/start/app/build, acknowledged in-process handle, owned active category/word/full snapshot and content revision. Keep sameDB/ambient rejection, owner/deletion-fence verification before and after awaited SQL, persisted readback and final synchronous stillCurrent. Generated content stays in the immutable original handle; bare ID/fresh repository/copied handle cannot adopt persisted work.

Freeze answer ID/time/result/context once before save; freeze end once before finish. Start/save/finish ACK loss retries those exact objects. Historical committed ACKs reconcile original facts after later target edits without new hooks, timestamps or projections. Preserve one-answer cardinality and inserted-only notification/sinks.

Declare recreational, hint0, engagement false, no Research pins, using existing EvidenceContext fields. Add prompt to `nativeProjectionPromptModes` and capture/validation cases. Existing policy allows only outcome/history: no effort, mastery/SRS, Assessment, Quest/Streak/achievement/XP/coins. Keep inferred legacy rows and frozen EventEnvelopeV2/EvidenceContext key sets unchanged.

## Write set and delivery order

1. **Core/content:** new `lib/features/learning/domain/sentence_scramble_content.dart`; existing `learning_models.dart`, `application/learning_use_cases.dart`, `application/current_activity_evidence.dart`, `domain/learning_evidence_contract.dart`, `data/drift_learning_repository.dart`. Extend existing capability; `learning_repository.dart` needs no new API.
2. **UI/callers:** existing `lib/screens/sentence_scramble_screen.dart`, `choose_mode_screen.dart`, `learning_history_screen.dart` and the existing `score_screen.dart`; reuse current bootstrap content/voice dependencies without another service. Screen receives accepted session+LearningUseCases+owner stream+optional existing voice. Remove raw target/translation constructor after migrating its only test caller. The P34 caller alone forwards its canonical completed summary to P23; ScoreScreen gains an optional guarded Back callback used by this flow. Preserve the original launch epoch across the owned category/game/result routes, invalidate it on owner/dependency/lifecycle/foreign-cover changes, and hide stale results permanently.
3. **Proof:** dedicated content/models/usecases/repository/projection/carry tests and synthetic realDB harness, actual sync alias/replay coverage, screen/hub/history/reduced-motion and owner/export/purge fixtures. Use existing Cloze/WordScramble test patterns; keep old assertions. Stage API/behavior RED before production promotion, focused GREEN before broader integration.

UI reuses native starting/saving/saved/finishing/error states, original-command retry and route/dependency/owner/lifecycle invalidation. Supply indexed tap, focusable Tab/Enter, drag/drop and typed alternative, Undo/Clear, duplicate-safe slots and disabled frozen inputs. Stop optional playback on invalidation/disposal; no raw TTS text as identity or autoplay-after-hidden callback.

Existing LearningSessions/AnswerAttempts and ordinary attempt outbox/export/purge suffice; generated text is not a new wire field. No schema/generator changes. History is truthful completed outcome, with no native-resume button. Owner merge/alias pull must preserve existing evidence and projection floor.

## Acceptance and attestation

- Actual category/provider/native UI flow persists exactly one session/answer and original end through lost start/save/finish ACKs; feedback says saved only after ACK.
- Unicode separators, repeated chunks, contractions/punctuation/combining text, invalid metadata, oversized/one-chunk/unchanged banks and provider failure have deterministic results; no fabricated fallback or failed-preparation writes.
- Intercept actual SQL to prove late owner/fence/target/current invalidation rolls back; ambient transactions and generic-prefix bypass fail. Provider sees no active transaction; delayed generation cannot cross owner/route ABA.
- Local/rebuild/pull/replay preserve recreational floor and prior ordinary SRS/reward bytes; one ordinary v2 attempt payload retains original context/provenance, no duplicate outbox. Nonparticipants produce zero Research rows/events/outbox; optional sidecar denial preserves ordinary play.
- 320px/200%, real IME/Tab/Enter/taps/drag, reduced motion, focus/labels, full-bank duplicates and input freeze pass. Existing modes/history/deletion/export/sync and frozen-contract tests remain green.
- Root serializes analysis/full regression/CLI/backend/APK at the final frozen-source checkpoint after independent review; no production Research, efficacy or physical-UAT claim.

## Review and execution board

- Root read the grounding, current Cloze parser/preparation, accepted native types and this plan. Scope/API accepted: full sentence distinct from its owned-word anchor, original immutable indexed bank and provider metadata, one canonical native writer, recreational floor, actual owned chooser/history and accessible input. This is not a claim that the new mode is implemented.
- One provider.generate request per preparation; no per-word generation loop or invented fallback. Raw bounds apply before Unicode White_Space normalization. Reuse the conservative existing anchor/format policy; do not claim Thai segmentation or ZWJ support. Preserve standalone punctuation pieces and require at least two lexical pieces within2–64 total indexed pieces, rather than rejecting valid spaced em dashes.
- Completed core promotion defines SentenceScrambleContent.targetSpelling/sentence/tokens/tokenOrder/metadata, supportsTarget and matchesResponse; SentenceScrambleSession exposes wordContentRevision/evidenceContentRevision/providerProvenance and tokenOrder; SentenceScrambleAnswerInput keeps exercise/response/responseTime. Public repository ports stay unchanged. Root owns serial C promotion/Flutter checks; D workers have disjoint drafts and independent read-only reviews.
- Core execution: projection RED19 failures/10 controls and pure API RED2 missing-module failures preceded promotion. First integrated core run passed176/failed6; independent diagnosis found four invalid synthetic nonlegacy fixtures (missing required research pins) and two outbox selections that included normal category/word rehome rows. Keep every assertion, provide explicitly synthetic mandatory pins, compare the entire attempt operation and additionally prove full-owner second-bind idempotence. The corrected current core run passes182 tests. No production validation was relaxed.
- UI execution: constructor RED2 preceded replacing the orphan widget. Two actual audio RED cases exposed manual Stop/Replay races; the corrected shared pending-stop future and captured intent pass all3 focused cases. Idle Back confirms; actual start/save/finish ACK disables Back until delivery. Exact committed-ACK retries preserve original handles/IDs/times/bank/end. Optional borrowed voice has no autoplay/default provider/disposal; sentences beyond the existing500UTF16 voice limit remain usable as typed exercises.
- The final5 UI/caller/history modules pass96 tests, including actual correct/incorrect P23 summaries, real committed owner null→same during held provider and after Score, stale Back/foreign cover, 320px/200% Thai+English IME, real keyboard/drag and no extra learning/reward/Research facts. Fixture corrections flush pending long-token layout before scrolling, choose the outer list and drag its padding when the focused text field intercepts gestures; async watcher teardown runs in the real zone. The clean final run has no hit-test warnings after waiting for the actual route transition and scoping the outer P34 list. Keep all substantive assertions. Three analyzer infos in new tests are corrected without changing assertions; final analysis reports0 issues. Current-source full regression/backend/CLI/APK attestations remain pending.
