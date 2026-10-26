# LQ-06 I5b Tutor targeted-practice checkpoint

## Status and authority

- Date: 2026-10-23, Asia/Bangkok
- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- HEAD: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1` (unchanged; no commit)
- Authority: `I5b-SOURCE-TUTOR-TARGETED-PRACTICE-LOCAL-1`, sole writer for the four source/test files named below and this checkpoint.
- ADLC: Intent, Ground, Plan, Execute and Attest complete for this bounded local card. Independent review disposition is recorded below.
- Source state: pre-existing dirty shared checkout. `source_practice_screen.dart` and its test were already untracked accepted work; unrelated changes were preserved.

## Outcome

Source Practice → Ask Lexi now carries only an in-memory target word ID and spelling beside the existing visible, unsent draft. The Tutor shows a Thai target card, a truthful `ดูข้อมูลที่ AI ใช้` disclosure and a local `ฝึกคำนี้` action.

The local action:

1. cancels active generation, STT and TTS through the existing lifecycle cancellation path;
2. rechecks the pinned controller, owner scope and owner epoch after cancellation;
3. opens the existing `QuizScreen` with exactly `wordIds: [target.wordId]` and `QuizWordSelectionMode.sourcePractice`;
4. performs no extra Gemini call and remains usable after an offline provider failure;
5. blocks provider Send while global learning-summary sharing is enabled, so the disclosure cannot be contradicted by the shared controller;
6. revalidates the current owner plus exact non-deleted word ID and spelling before navigation; deleted or renamed targets are cleared with no Quiz or learning session.
7. uses a synchronous one-flight guard, so rapid target taps cannot push duplicate Quiz routes or create duplicate sessions.

The target is cleared on controller replacement, scope/epoch invalidation, a new conversation and owner ABA. Tutor opened from the main menu has no target card or target action.

The provider boundary is unchanged. Gemini still receives only the learner-visible text plus the selected scenario and response mode. The source filename, raw passage, category/owner ID, word ID, meaning and answer history are not added to the gateway request.

## Bounded change

1. `lib/screens/ai_tutor_screen.dart`
   - Extended the existing one-shot `TutorWordDraft` with optional RAM-only word ID/spelling.
   - Reused the existing owner/controller/epoch fence and cancellation path.
   - Added the target card, disclosure dialog and exact local Quiz route.
2. `lib/screens/source_practice_screen.dart`
   - Passed the already validated current word ID/spelling and existing `LearningUseCases` into Tutor.
3. `test/screens/ai_tutor_screen_test.dart`
   - Covers absence on main-menu Tutor, clearing on new round/controller/scope/ABA, and 200% text at 360x800 and 800x360.
4. `test/screens/source_practice_screen_test.dart`
   - Covers visible unsent draft, disclosure, exact single source-practice session, provider failure, summary-sharing privacy, cancellation before navigation, invalidation, deletion/rename rejection and the unchanged gateway boundary.
5. This checkpoint.

No schema, migration, dependency, bootstrap, gateway, repository, sync, reward, research or Cloud behavior changed. No source passage or account identifier is persisted in the target handoff.

## TDD evidence

RED was observed before the production change:

```powershell
flutter test --no-pub test/screens/source_practice_screen_test.dart --plain-name "Ask Lexi target opens one exact local source-practice session"
```

Result: exit 1 because `ai-tutor-data-disclosure` did not exist. After the bounded implementation the same test passed 1/1.

The independent review then found privacy, stale-spelling and rapid-tap gaps. RED evidence reproduced all three: summary sharing reached the gateway, deleted/renamed targets still opened `QuizScreen`, and two immediate target callbacks opened two Quiz routes. After the local guards, the post-review focused set passed 4/4, cancellation of an in-flight AI token plus STT/TTS cleanup passed, and the rapid-tap regression passed 1/1 with one Quiz and one session.

## Final verification on current source

```powershell
flutter test --no-pub test/screens/ai_tutor_screen_test.dart
```

Result: exit 0, **40/40 passed**.

```powershell
flutter test --no-pub test/screens/source_practice_screen_test.dart
```

Pre-review full regression result: exit 0, **80/80 passed** in 7m12s. It covered the then-current target paths plus existing Source Reading/Quiz/Flashcards/Voice/Result/repair regressions.

Post-review focused verification on the final source:

```powershell
flutter test --no-pub test/screens/source_practice_screen_test.dart --name "(blocks answer-history|rejects (deleted|renamed) target|cancels active AI)"
```

Result: exit 0, **4/4 passed**. A second full Source suite was not repeated because the review patch only tightened provider admission and the target pre-navigation read; the directly affected paths and the full AiTutor suite were rerun.

```powershell
flutter test --no-pub test/screens/source_practice_screen_test.dart --plain-name "rapid Ask Lexi target taps open one local Quiz session"
```

RED: exit 1 with two `QuizScreen` instances. GREEN after the one-flight guard: exit 0, **1/1 passed**.

```powershell
flutter analyze --no-pub lib/screens/ai_tutor_screen.dart lib/screens/source_practice_screen.dart test/screens/ai_tutor_screen_test.dart test/screens/source_practice_screen_test.dart
dart format lib/screens/ai_tutor_screen.dart lib/screens/source_practice_screen.dart test/screens/ai_tutor_screen_test.dart test/screens/source_practice_screen_test.dart
git diff --check -- lib/screens/ai_tutor_screen.dart lib/screens/source_practice_screen.dart test/screens/ai_tutor_screen_test.dart test/screens/source_practice_screen_test.dart
```

- Scoped analyzer: exit 0, no issues.
- Formatter: exit 0; the final pass changed no production file.
- Scoped diff check: exit 0 for tracked files; Git emitted existing LF-to-CRLF warnings only. The two Source files remain pre-existing untracked files, so Git has no index diff for them.
- Flutter commands were serialized. The next writer was explicitly given the slot after verification.

## Independent review disposition

The first two read-only reviews returned Not Ready and identified the learning-summary privacy gap, stale/deleted spelling validation and rapid-tap re-entry. Each finding received RED evidence and a bounded fix. Final read-only re-review reports **Critical 0 / Important 0, Ready**. Its remaining minor observation is evidentiary only: the cancellation regression proves the in-flight AI token and STT/TTS cancel/stop calls before Quiz is observed, while the production path itself awaits their `Future.wait`; it does not run real microphone or speaker hardware in this card.

## Verified source manifest (SHA-256)

| Path | SHA-256 |
| --- | --- |
| `lib/screens/ai_tutor_screen.dart` | `AD7BBF857FF23142933C22DCD3E0ED1920C12B296C785B82C0E91C1E59407340` |
| `lib/screens/source_practice_screen.dart` | `A804CC9D663047E00E866E884421605C19D2DE3D047EF769583F3B04D2F41831` |
| `test/screens/ai_tutor_screen_test.dart` | `37F2C77BB40922B324C739D81B087061491E29C6B1F90AAC5425103D8361B944` |
| `test/screens/source_practice_screen_test.dart` | `F4CFEB3CBDB8A8D5C8C3CBD1F61AD87F19857185D6456F237092A24F50E7F999` |

## RETURN and remaining evidence

- RETURN: release the I5b source-writer and serialized Flutter slot to LQ-00 after review disposition.
- Not run for this card: repository-wide suite, APK build, emulator/physical-device replay, live Gemini, Cloud/Firebase or deployment. Earlier integration evidence remains separate and is not claimed as I5b evidence.
- The target handoff is intentionally RAM-only. Leaving Tutor, starting a new conversation or invalidating the owner discards it; there is no resume/history feature in this card.
