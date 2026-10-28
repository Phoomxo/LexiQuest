# Contextual Practice Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development for bounded implementation and requesting-code-review at integration. Root owns serialized tests/builds; no commits.

**Goal:** Blend WordQuest card-based spelling with a Duolingo-inspired sentence-completion and optional listen/speak sequence in existing LexiQuest activities.

**Architecture:** Existing cloze and spelling authorities continue to own answers and session completion. A reusable ephemeral media panel plays the reviewed complete sentence after a cloze answer is committed; it never records another learning attempt, raw speech row, reward, research event or SRS update. Word spelling gains meaningful context and reversible letter placement while retaining its current session lifecycle.

**Tech Stack:** Flutter/Dart, existing VoiceUseCases/SpeechPracticeUseCases, Drift, existing M3Theme/accessibility and current test tooling.

## Global Constraints

- Worktree C:/Users/Phet/.codex/worktrees/02fa/LexiQuest; branch codex/pair-matching-pm0-pm8. Preserve all current dirty work; baseline is the previously tested UI, not HEAD.
- Latest user approves blending English-Game-For-Kids / WordQuest with Duolingo. Use the proposed optional listen-and-speak default; microphone can be skipped.
- Preserve 8/44, serialized mode names, EvidenceContext/EventEnvelopeV2, owner/content/session gates and learning/reward authorities. No schema/dependency additions.
- Do not copy third-party source/assets/vocabulary. Reference WordQuest commit42f2ec3873ba12df02be94858c833a957dddbbc1 conceptually; implement within existing Flutter code.
- Do not add another hearts/coin economy or make microphone failure cost a life. Existing HintPolicy and timer remain authoritative.
- No deploy/install/uninstall/data reset/real enrollment/upload/commits. Device validation remains conditional on actual ADB availability.
- Freeze writers during each Flutter run; use apply_patch; retain RED and GREEN evidence.

## Task 1 — Optional after-answer listening and speaking

**Files:** create lib/features/learning/presentation/sentence_practice_panel.dart; create test/features/learning/sentence_practice_panel_test.dart.

**Interface:**
```dart
class SentencePracticePanel extends StatefulWidget {
  const SentencePracticePanel({super.key, required this.identity,
    required this.text, required this.canInteract});
  final String identity;
  final String text;
  final bool Function() canInteract;
}
```
Consumes AppDependenciesScope.voice/speechPractice and optional UnifiedLessonSessionLifecycleScope. No direct plugin construction. Child must register EphemeralLessonState to cancel/clear on shell retirement.

- [x] Add failing widget tests using fake existing media gateways: listen complete/stop, speak final transcript, empty/silence, failure/retry, cancel/skip, item replacement, route cover, background, pending permission then retirement, late/duplicate final callbacks; no percentage/pronunciation accuracy claim. Test narrow200% physical/semantic controls.
- [x] Run focused RED with `flutter test --no-pub --reporter expanded test/features/learning/sentence_practice_panel_test.dart` and retain actual failures.
- [x] Implement RouteVoiceSessionMixin, owned SpeechPracticeSession and identity epoch. Playback uses `speakUntilCompleted`; listening cancels playback first; replay cancels recognition. Skip/retire/dispose invalidates callbacks and releases only owned handles. Do not hold lifecycle.runAcceptedOperation while waiting for speech. Check parent predicate before every start and callback, not only build.
- [x] UI shows sentence, ฟังประโยค/หยุดเสียง, ฝึกพูด/หยุด/ลองอีกครั้ง/ข้ามการพูด and ระบบได้ยินว่า…; speech feedback is in-memory practice only, explicitly stated in UI. Missing services retain next/skip in parent and show readable Thai status.
- [x] Run GREEN, analyzer on the two files and independent focused diff review; freeze.

## Task 2 — Sentence and spelling cards integrated with current authorities

**Files:** lib/features/learning/application/cloze_mode_adapter.dart; lib/screens/fill_in_the_blanks_screen.dart; lib/screens/word_scramble_screen.dart; lib/screens/choose_mode_screen.dart; lib/screens/game_launcher_screen.dart; corresponding existing test/features/learning/cloze_mode_adapter_test.dart and test/screens/fill_in_the_blanks_screen_test.dart, word_scramble_screen_test.dart, choose_mode_screen_test.dart, production_feature_navigation_test.dart if traversal is affected.

**Additional copy boundary:** lib/features/adventure/application/adventure_mixed_review_prompt_catalog.dart must preserve completeSentence in _freezeClozeQuestion; no serialized evidence or schema change.

**Additional traversal migration:** test/screens/accessibility_smoke_test.dart now uses the approved Thai letter semantics and scrolls by the stable letter key before asserting semantics/tapping. All original motion, size and filled-slot assertions remain.

**Interfaces:** ClozeQuestion exposes canonical reviewed completeSentence, captured with the exact selected lexical example before masking. Add optional WordScrambleScreen.meaning/partOfSpeech, populated from the pinned QuizWord at both existing callers; no example invented from QuizWord.

- [x] Add RED for canonical sentence preservation (case, original underscore strings, content pinning) and after-answer-only media eligibility. Add integration check that media interactions leave committed answer count unchanged and next still closes through the original controller.
- [x] Capture selected canonical example alongside masked prompt in _PinnedClozeCandidate and ClozeQuestion. Do not rebuild with `prompt.replaceAll('_____', answer)`.
- [x] Render cloze sentence in a spacious card, selected answer preview + chip word bank, a single explicit ตรวจคำตอบ button and a secondary typed mode. Selecting/changing chips must not grade before confirmation. Preserve mode-choice timing so a typed answer cannot first inspect the full word bank while still claiming independent recall.
- [x] Place SentencePracticePanel after committed feedback with identity `${session.ownerId}/${session.id}/${question.wordId}/${question.contentRevision}`. Parent allows only current answered phase with no pending persistence/abandonment/completion and current lifecycle acceptance. Existing next disposes/rekeys panel, advances normally. Silence/service unavailability cannot disable next.
- [x] Improve spelling prompt with available real meaning/part-of-speech, clear instruction, separated cards, letter-count status (not mastery), tap/drag alternatives and per-slot undo keyed by original letter index. Preserve duplicate letters exactly; cannot reuse a consumed index or mutate after commit/pending save. Translate remaining letter semantic labels to Thai.
- [x] Keep spelling session close behavior unchanged. Existing spelling and sentence cloze remain distinct exercise types with shared visual language; do not silently launch a second lesson after spelling completion.
- [x] Update existing traversal tests only for deliberate selection→confirm step, preserving SQL/evidence/owner/retry assertions. Run focused screen/adapter/media tests and independent review.

## Task 3 — Verify the final combined experience

**Files:** documentation and build/verification/contextual-practice-20260908 evidence; existing generated test plan via normal generator only.

- [x] Freeze writers. Capture actual cloze choice/feedback/speech and spelling screens at390x844 and360x800/text200% using synthetic fixtures, inspect all captures and real taps. Treat simulated media as host-only.
- [x] Regenerate/check canonical final test plan using current HEAD; check feature map. Analyze all current source roots (lib test integration_test test_driver assets tool tools), excluding archived copies by explicit command scope without changing lint rules.
- [x] Run `flutter test --no-pub --exclude-tags release-excluded --reporter json`, retain parser inventory and current-source gate. Existing four excluded native/platform cases stay disclosed. Run affected host integration after final UI, then normal debug APK build on consistent sources.
- [x] Review incremental changes against this task's preserved baseline, hashes, test failures/fixes and final results; save concise Thai result and next device/UAT steps. Earlier UI test evidence is historical, not proof of this new code.

## Self-review

The approved idea is implemented through existing exercise types. Full-sentence playback uses reviewed pinned text, not reconstructed content. Speech practice is explicitly ephemeral and unscored; durable evidence remains with the original answer controller. No duplicate session, hidden follow-on route, new economy, learning authority, schema or repository-code copying is introduced. WordQuest hearts/item names are reference concepts, not promises to ship an unapproved second reward system.

Final status 2026-09-08: implementation and available automated verification COMPLETE. Full4,964PASS, all9current-source gates passed, normal debug APK archived and independently hash-verified. Independent final-system-review APPROVE; no important findings remain. Result docs/development/2026-09-08-contextual-practice-results.md. ADB empty; physical-device/UAT remains outside the completed host evidence.
