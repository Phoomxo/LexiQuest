# Integrate one owned Word Scramble round

Grounded 2026-10-30 at frozen `2702e0080937147e396b79cc290b0d1fb5deadf0`, worktree `C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest`, branch `codex/remaining-system-readiness`. This implements the Word Scramble card in `docs/superpowers/plans/2026-10-30-remaining-feature-sequence.md` after Quest attestation. Quest at this baseline is verified: Flutter3700, analysis0, CLI23, offline backend390/one opt-in skip and normal debug APK. The existing authorization covers this next card. Core, floor and UI drafts are isolated on D and not promoted; root owns pubspec/lock and all serialized execution.

## Current behavior and target

`word_scramble_screen.dart` still accepts a raw word and scores in widget state. Cloze integration already removed its delayed next-screen hop. Its only production raw caller is the non-source success branch of `SpeakToTextScreen`; `SourcePracticeScreen` passes `sourceOwnerId` and uses separate save/finish/exit behavior. Preserve that source branch.

`createStableScramble` splits graphemes, rotates by a deterministic rune checksum, and swaps the first differing tile if rotation reproduces the original word. It preserves duplicate letters. For one grapheme or all-identical graphemes there is no differing tile, so it returns the original order. Existing tests explicitly require `a → [a]` and `aaa → [a,a,a]`. Keep that helper behavior. Preparation rejects an unchanged permutation, skips unusable words only within the chosen owned category, and returns unavailable when none qualifies. Do not fabricate letters, words, revisions, or another-category targets. Add periodic-repeat and mixed-grapheme checks rather than treating every repeated-letter word as unusable.

The route is quiz-gated ChooseMode → actual owned category → one immutable accepted round → save → explicit finish → actual stored summary. Back leaves an unfinished session. No client, AppDependencies field, schema, registry, external content, or durable restart/resume is needed.

## Closed native API and evidence

Add exactly one exercise and one input case to the existing sealed lifecycle:

```dart
final class WordScrambleSession extends AcceptedNativeExercise {
  List<String> get letters; // copied stable permutation of the pinned word
}
final class WordScrambleAnswerInput extends NativeAnswerInput {
  WordScrambleSession get exercise;
  String get response; // transient, from typed input or selected tile indices
}
Future<WordScrambleSession?> prepareWordScramble({
  String? categoryId, required bool Function() stillCurrent,
});
```

Use `session:word-scramble-v1:` and activity/prompt `wordScramble`. The constructor derives its immutable letter order once from the captured word and rejects unchanged output. Keep `wordContentRevision` as the actual SQL revision. Derive `evidenceContentRevision` as `word-scramble-v1:SHA256(canonical JSON)` over version, exact word snapshot/revision, and accepted letter order. Never compare that digest to the SQL revision. Preserve existing Dictation/Cloze digest bytes.

Reuse generic-T start, prepareNativeAnswer, commitNativeAnswer, prepareNativeFinish, and finishNativeExercise unchanged. Extend exhaustive switches, original Expando binding, native-prefix generic-writer rejection, owned nondeleted word/category/meaning proof, final owner/fence/visibility checks, and historical ACK replay. Answer correctness uses the captured target and existing trim/case comparison. Store no raw response or tile-selection text. Provider provenance is null.

Declare `recreational`, skill `word-scramble`, hint 0, current declared policy, false engagement, and an actual content pin. Add only `wordScramble` to `nativeProjectionPromptModes`. The existing policy permits session/history and denies mastery/SRS, active-learning effort, XP, coins, Quest, Streak, achievements, and efficacy. Keep inferred/other ordinary evidence compatible. Reuse malformed-native carry exclusions and the genuine prior/remote SRS baseline path; no parallel reward authority or Research events.

## Disjoint implementation units

| Unit | Exact production write set | Deliverable |
| --- | --- | --- |
| Core, one writer | `lib/features/learning/domain/learning_models.dart`; new `domain/word_scramble_letters.dart`; `lib/features/learning/application/learning_use_cases.dart`; `lib/features/learning/data/drift_learning_repository.dart` | Move the helper without changing its algorithm; add immutable exercise/input, read-only owned preparation, digest, and one shared canonical writer case. `learning_repository.dart` is read-only because its generic port already suffices. |
| Floor, independent writer | `current_activity_evidence.dart`; `learning_evidence_contract.dart`; `lib/features/rewards/data/drift_reward_projection_rebuilder.dart`; `lib/features/progress/data/drift_progress_queries.dart` | Pin recreational metadata and extend the existing explicit prompt set/corrupt-source handling only. No learning-rebuilder or SyncStore source change unless a real focused RED proves a gap. |
| UI/callers, after contract freeze | `lib/screens/word_scramble_screen.dart`; `choose_mode_screen.dart`; `learning_history_screen.dart`; `speak_to_text_screen.dart` | Require the accepted round/use cases, reuse Chooser owner/epoch/overlay handling, add a Thai entry after existing native entries and a saved-history label. Remove the raw speech-to-scramble hop; its non-source button returns to the existing quiz instead. Keep its permission-center route and source behavior. |

Keep the helper pure Dart with `package:characters/characters.dart`. Root owns declaring the already-installed locked `characters: 1.4.1` directly in pubspec and serialized offline resolution after Quest attestation. This exposes the existing dependency; it adds no package/version/download. The screen re-exports `createStableScramble` so existing helper test imports remain valid. Do not retain a raw-word screen constructor.

## Interaction and proof

Retain optional dragging and the existing reduced-motion color behavior. Add indexed tappable/focusable letter buttons with keyboard activation, Undo/Clear, and a typed alternative. Give the pinned meaning as the target cue, masking the whole target in text/semantics. Duplicate glyphs have distinct source indices; reject reused/out-of-range indices at acceptance, including rapid drag/tap races. Joining selected original tiles and typed input feed the same recreational answer type. Clear/reset preserves the accepted order; disable edits/reset after a command freezes. Show target/correctness only after save ACK and close only after finish ACK. Reuse the current native owner null/error/done/ABA, route, lifecycle, dependency, and disposal invalidation pattern.

Start with current-API RED tests for unchanged permutations, periodic duplicates, grapheme multiset/order, immutable pins, same-object start, generic API bypass, wrong word/revision/fence, lost ACKs, and no raw persistence. Preserve both existing helper assertions. Migrate `reduced_motion_consumers_test.dart` to a real accepted round without dropping its drag-color assertion; add tap/keyboard/typed/repeated-index and Thai/English 320px/200% save/finish checks. Cover the actual ChooseMode route and raw speech-edge removal.

Use new `word_scramble_native_test.dart`, projection isolation/carry tests, an actual SyncStore alias/replay/baseline test, and one real category→round→answer→finish integration. Compare SRS/points/rewards/Quest/Streak/Research snapshots, retain session/history outcomes, and test no-session unavailable paths. Keep prior Dictation/Cloze/Assessment controls.

Root first runs the focused new tests and existing `word_scramble_screen_test.dart`, `reduced_motion_consumers_test.dart`, ChooseMode/history/speech tests. Then run `flutter test test/features/learning/ test/features/sync/ test/features/quest/ test/features/assessment/assessment_projection_isolation_test.dart`, analysis, and a full frozen-source regression/build at the integration checkpoint. Update readiness only for this one-word game; Sentence Scramble, restart/resume, hardware accessibility, and physical UAT remain separate work.
