# LQ-06 / I5a Tutor handoff — 2026-10-23

## State and custody

- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- HEAD: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1` (unchanged; pre-existing dirty work preserved).
- Disposition: **bounded I5a local implementation verified; independent review accepted; integration-root acceptance pending**.
- RETURN sole production/Flutter slot at handoff. No next-card execution, commit, merge, deployment or cleanup is implied.
- Caps LQ-06 30 / program 250 unchanged; actual spend unavailable.

## Latest authority and intentional difference from the old I5b proposal

Source coordinator's Oct23 scope correction:

> 8-turn budget is per visible tutor session and may reset when the screen is reopened; keep it in AiTutorScreen unless current code proves a lifecycle owner elsewhere. Do not add durable/global quota state.

Integration root subsequently accepted this correction explicitly: **8 attempts per visible session, counted at controller invocation, not HTTP/gateway/provider receipt**. The historical unimplemented I5b proposal (controller-owned count surviving page reopen and reserved at the gateway boundary) is superseded for this bounded I5a milestone, not silently satisfied.

- Counter is RAM state of `AiTutorScreen`; explicit idle new round clears visible draft/chat/count, without owner invalidation, credential mutation or consent regrant.
- Closing/reopening the page may reset the counter even with the same controller. This is tested.
- Preflight rejects blank/over-500 input, missing key/launch consent/scope and exhausted count without calling the controller. After speech cleanup and current-scope/epoch checks, each controller invocation consumes one attempt, including a later failure/cancel.
- This is conservative conversation-attempt UX, **not** an authoritative gateway count, daily quota, billing cap or cross-page/cross-restart quota.

## Implemented behavior

1. Guided `คิดทีละขั้น` is the default; direct `อธิบายให้เลย` is selectable. A typed `GeminiTutorMode` passes UI → existing controller/use case → REST gateway. Guided system instruction requests one hint/leading question and withholds the full answer; direct requests an answer and brief reason. Learner text stays user data, not injected mode instructions.
2. Existing scenario selection, input500, maxOutputTokens120, 20-second default timeout, provider/model provenance, T1 owner/auth epoch/per-launch provider+summary activation and STT explicit-send behavior remain.
3. A send latch stays busy until its original future settles, even if cancel/background/settings invalidates its visible result. A late result cannot create a reply or TTS; reset/send/mode/mic are gated while pending.
4. Failed/cancelled sends keep the editable draft and expose explicit retry. No automatic retry or canned success; unsuccessful user bubbles are removed, so resubmission does not accumulate fake successful turns. Retry uses the currently visible draft/mode/scenario; no durable failed-turn identity or source-context contract is added.
5. Ninth attempt is rejected with draft retained and no controller/TTS dispatch. Idle explicit new round is available.
6. `กลับไปฝึกคำศัพท์` cancels Tutor audio/work and uses existing `AppNavigator` → `ChooseModeScreen`, with no AI payload or learning/reward authority added.
7. Existing Material vocabulary is preserved. Mode/action groups wrap, the bounded conversation/composer is scrollable, and the composer has a visible label. Layout tests cover 360×800 and 800×360, 2× text, IME inset, light/dark and reduced-animation setting; mode/round/practice targets are at least48dp.

No production settings, secure store, bootstrap, main-navigation, source practice, schema, dependency, research or learning/reward writer was changed. No raw passage, document metadata or prior chat history is sent; no transcript persistence or new provider is added.

## Exact I5a write set

Four production files and five tests/fake migrations, plus this checkpoint (10 paths total).

- Contracts: enum and optional mode argument only.
- Use cases: mode argument/forwarding only; no budget or credential-state rewrite.
- Gateway: mode-dependent system instruction only.
- Tutor screen: bounded visible session, modes, recovery, practice CTA and responsive controls.
- Use-case/REST/Tutor tests: corresponding behavior and synthetic fixtures.
- Settings/bootstrap tests: compatible fake signatures only; their production modules remain untouched.

## TDD and review disposition

Baseline focused suite: **76 passed, exit0**.

Observed behavioral RED cases before their fixes:

- Current default system instruction lacked guided hint/no-reveal instruction.
- Guided/direct requests produced identical system instructions.
- Screen ninth send reached the controller (expected8 calls, actual9).
- Cancel discarded the draft; mode choices/retry/practice action were absent.
- Reviewer-found delayed-microphone-start race: permission remains pending, typed send takes over and advances interaction epoch, so the old startup finally cannot clear `_startingSpeech`; new-round/mic controls remain disabled. Regression RED **0pass/1fail**, then minimal fix clears startup state when send takes ownership, GREEN **1/1**.

Early provisional use-case quota/input tests written before the explicit scope correction were removed as out-of-scope new tests, not to weaken an existing assertion. The accepted screen-local ninth-send behavior has its own observed RED and final coverage. Existing predecessor tests/assertions were retained.

Independent read-only reviewer `/root/i5a_review`: initial Important1 above; verified minimal fix/regression and returned **accepted, Critical0/Important0/Minor0 remaining**. Reviewer did not run Flutter or mutate files. Final checks below were run by the implementer after the fix.

## Final current-source verification

Focused:

```text
flutter test --no-pub test/features/gemini test/screens/ai_tutor_screen_test.dart test/screens/gemini_settings_screen_test.dart test/runtime/app_bootstrap_test.dart --reporter expanded
```

**Exit0, 93 passed, 8 seconds.**

Connected regression (serialized; stdout tail only for compact reporting, native exit propagated):

```text
flutter test --no-pub test/features/account test/features/identity test/features/gemini test/features/media_practice test/voice test/screens/ai_tutor_screen_test.dart test/screens/gemini_settings_screen_test.dart test/screens/speak_to_text_screen_voice_test.dart test/screens/shadowing_challenge_screen_test.dart test/screens/choose_mode_screen_test.dart test/features/learning/learning_use_cases_test.dart test/features/learning/drift_learning_repository_test.dart test/screens/quiz_screen_test.dart test/runtime/app_bootstrap_test.dart test/architecture --reporter expanded | Select-Object -Last 8
```

**Exit0, 449 passed, 22 seconds.** Includes real Drift identity/learning, M1a/T1, practice chooser and architecture boundaries. Earlier448 was before the final delayed-mic regression/fix and is historical, not final evidence.

```text
flutter analyze --no-pub lib/features/gemini lib/screens/ai_tutor_screen.dart test/features/gemini test/screens/ai_tutor_screen_test.dart test/screens/gemini_settings_screen_test.dart test/runtime/app_bootstrap_test.dart
```

**Exit0, no issues, 5.1 seconds.**

Final formatting uses `dart format --output=none --set-exit-if-changed` on exactly the nine paths below; scoped `git diff --check` checks those paths plus this checkpoint. Final hash reconciliation and task-runtime inventory are recorded at handoff; no relevant source/test edit may follow the final verification.

Final attestation: formatter **exit0, 9 files/0 changed**; scoped diff **exit0**; checkpoint trailing-whitespace assertion clean; source/test manifest **9/9 matches**; Win32 Dart/dartvm/dartaotruntime/flutter_tester/gen_snapshot process inventory **0**. No source/test changes followed final tests/analyzer; this documentation-only attestation does not change their inputs.

## Final source/test SHA-256 manifest

| Path | SHA-256 |
| --- | --- |
| `lib/features/gemini/domain/gemini_contracts.dart` | `3B5B1FF474BA7C517C783023621FD1427438DF4BCA91D5D4DD9D0F596F762679` |
| `lib/features/gemini/application/gemini_tutor_use_cases.dart` | `C52DDA6457D73F6093FA1E5616C908965ED922D7A9D7A88C57697ADABD07941A` |
| `lib/features/gemini/data/gemini_rest_gateway.dart` | `09EDAE22D4C82498942D64A15DC804F014A44D8624C2771EB8E489301B7CB141` |
| `lib/screens/ai_tutor_screen.dart` | `C45222B99D79C19310307EDD6F639CC08C8A68875AD868470B02E57CB73D5CE9` |
| `test/features/gemini/gemini_tutor_use_cases_test.dart` | `1A7E2E0E69FC6F14C00030DD11D70CBF865C7FF1538BB00BF3FB8C0B62DEB0F8` |
| `test/features/gemini/gemini_rest_gateway_test.dart` | `7D095BCC68783C0697B20782FA820DDA7D693A461E2C07B85D597111E1A12810` |
| `test/screens/ai_tutor_screen_test.dart` | `BCE3FBB3CD5314B9095ABF2EBCE6B5BBEB079D91D8E228EEDD59BBB13B568B4D` |
| `test/screens/gemini_settings_screen_test.dart` | `F083168C82313E50A51B7CF56E99D6E3B1FAC0FFB9CE2F26F4502734B59A48CC` |
| `test/runtime/app_bootstrap_test.dart` | `729824394323661C0CCBC6966B9AFE56049E82E954913E07E901EC0E826BED94` |

The manifest pins current complete files, including accepted predecessor content; it is not a claim that the entire HEAD diff belongs to I5a. This document is hashed separately and never embeds its own hash.

## Boundaries and next step

- Not run: whole-repository suite or APK build for this bounded card; prior1308 predecessor results are not current I5a full-regression evidence.
- No emulator/native screenshot or physical-device/TalkBack/real IME/TTS/STT check; layout evidence is Flutter widget testing, not hardware or final visual attestation.
- No live Gemini/key/secret access, cost measurement, model compliance/pedagogy efficacy, research authority or real upload.
- Full I5/source-aware practice, persistent/history context, durable failed-turn identity and wider Messenger flows remain open. Existing native untagged late-callback limitation from M1a remains, not reclassified as fixed.
- No runtime/test process is intentionally retained. Preserve all dirty edits; next executable step is integration-root review/hash reconciliation, then its own grant of a dependency-ready card.
