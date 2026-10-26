# LQ-04 — I3b saved feedback and explicit Quiz hint/reveal

## Section 13.5 handoff / intent and authority

- Chat/card: LQ-04 / I3b, the accepted smallest remaining I3 card in the active Astra-led integrated plan, section I3.
- Worktree: `C:\Users\Phet\Documents\LexiQuest`; branch `feature/associative-reading-loop`; base HEAD `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`. Existing dirty source/test work is preserved. The final SHA256 manifest below, not HEAD alone, identifies the verified snapshot.
- Source coordinator explicitly transferred sole six-path production writer/Flutter slot after S1b local acceptance/process0. LQ-00 integration chat reconciled the same transfer; this is one grant, not two concurrent slots.
- State: **bounded I3b engineering-complete, submitted for root acceptance**. Root decides whole-I3 closure and the next card. No I4 or later implementation started.
- Scope: SRS saved-feedback→explicit Next/Finish and Quiz explicit hint/reveal using existing learning contracts. No schema, migration, dependency, route, registry, event-envelope, EvidenceContext, 8/44 feature catalog, learning/reward authority, enrollment or upload change.
- Budget: existing LQ-04 cap38 / program250 retained; no reset or actual-spend claim because spend telemetry is unavailable.

## Ground and actual changes

Read the latest root ledger/active I3 plan, previous XP/SRS and C-COIN handoffs, current Quiz/SRS/Score/Weakness, LearningUseCases/repository and connected tests. Existing Quiz save/feedback/Next, stable retry, Score/Weakness targeted practice and sole coin authority were already present; they were not rewritten.

Exactly six paths changed in this card:

1. `lib/screens/srs_flashcards_screen.dart`: successful save keeps the same card, shows truthful saved/self-rating feedback with its existing word/meaning, and exposes explicit Next or Finish. Failed save retains original rating, ID, UTC time and response time; opposite rating stays disabled. Finish failure/lost acknowledgement retries only session finishing, not recordAnswer. Ordinary flip is still no-write, not a wrong answer. Compatibility decks explicitly say they do not save results. Scrollable content replaces the constrained Expanded card; ratings are stacked with 52dp minimum and a visible 48dp flip control supplements the existing tap gesture.
2. `lib/screens/quiz_screen.dart`: hint exposes existing partOfSpeech, can be hidden, and is unavailable when absent; hint creates no learning evidence. Reveal freezes an incorrect intent through the same recordAnswer/ID/time path; it does not compare a fabricated answer with the correct meaning. On acknowledged success, feedback honestly says the user requested reveal rather than supplied an answer, includes the correct answer, and supports existing Score/mistake practice. Pending/error controls cannot change the frozen answer/reveal intent. Next resets hint/reveal state. Existing acknowledged Quiz layout/golden remains unchanged.
3. `test/screens/srs_flashcards_screen_test.dart`: preserves existing Good/Again × failed-write/lost-ack identity/SRS/XP/outbox assertions, adapts gestures to explicit Next, strengthens Finish retry to exactly one answer dispatch, and adds canonical coin, pending-ack double-tap/no-advance/no-write Next and long-text 2× checks.
4. `test/screens/quiz_screen_test.dart`: preserves existing tests, adds reveal failed-write/lost-ack full-command retry with no XP/coin, delayed-ack double-tap and mistake-practice flow, repeated hint no-write, correct-answer canonical +1 coin/full-command checks, and 2× dark-theme hint/reveal/error/retry/CTA/live-region coverage. The existing failure wrapper records commands/optionally delays acknowledgement while retaining real Drift writes.
5. `test/screens/learning_loop_layout_test.dart`: adds behavioral Score/Weakness checks at 2×; retains existing 1.8× golden assertions. Score/Weakness production source is unchanged.
6. This new checkpoint. No equivalent I3 feedback checkpoint existed at discovery.

All other dirty changes belong to the baseline/other accepted cards. In particular, no consent/account/shared learning/rewards/sync/bootstrap/Score/Weakness production files were written. No golden image was updated. The previous SRS source hash was `811ACDD04383D0227679AE8C0CDB584E6AB0A912711B009E57F231224EDAA74C`, matching the earlier accepted stable-retry handoff before this card.

## Acceptance evidence / RED→GREEN

- Initial modified whole Quiz/SRS widget command: **exit1, 10 passed / 10 failed**, expected missing SRS saved feedback and explicit Quiz hint/reveal. No production code preceded these behavioral RED cases.
- Focused SRS long-text 360×800/2× reproduction: **exit1, 0 passed / 1 failed**, RenderFlex overflowed by **504px** on the bottom. The constrained Expanded card could not grow; scrollable intrinsic-height content removes that root cause.
- First implementation had one missing collection comma, identified by formatter/compiler and corrected from the parse diagnostic. This was a bounded compile correction, not an authority blocker. Subsequent focused run passed21, then expanded coverage passed26.
- Added landscape/semantics harness checks exposed two test setup issues: a tap used an offscreen long-text center, and SemanticsHandle teardown occurred after the framework's disposal verification. Corrected to scroll to/use the visible flip control and dispose the semantics handle in try/finally. No assertion was skipped/weakened. Expanded focused command then passed29.
- Correct answer retries produce one `creditQuizCorrectV1` +1, one attempt and unchanged idempotent SRS/XP. Reveal retries produce one incorrect attempt and no XP/coin. Hint toggles preserve the outbox baseline and create no attempt/XP/coin. The baseline learning session creation is not falsely counted as a hint mutation.
- Non-final SRS Next adds no evidence/outbox write; final Finish legitimately closes the existing session, without submitting the answer again. Both finish failure and lost-ack cases assert one answer dispatch and unchanged SRS evidence.

## Final current-source checks

All Flutter/Dart checks ran serialized in this worktree. Source/test changes stopped before final format/analyze/connected checks; only this checkpoint was subsequently written.

```text
dart format --output=none --set-exit-if-changed lib/screens/srs_flashcards_screen.dart lib/screens/quiz_screen.dart test/screens/srs_flashcards_screen_test.dart test/screens/quiz_screen_test.dart test/screens/learning_loop_layout_test.dart
```

**Exit0, Formatted5 files (0 changed), 0.07s.**

```text
flutter analyze --no-pub lib/screens/srs_flashcards_screen.dart lib/screens/quiz_screen.dart test/screens/srs_flashcards_screen_test.dart test/screens/quiz_screen_test.dart test/screens/learning_loop_layout_test.dart
```

**Exit0, No issues found, 2.5s.** Initial two sort_child_properties_last infos were corrected by moving child below style; no behavior changed.

```text
flutter test --no-pub test/features/learning test/features/progress test/features/rewards test/features/sync/reward_transaction_sync_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart test/screens/srs_flashcards_screen_test.dart test/screens/quiz_screen_test.dart test/screens/weakness_clinic_screen_test.dart test/screens/learning_loop_layout_test.dart test/screens/offline_vocabulary_journey_test.dart test/runtime/app_bootstrap_test.dart test/screens/production_shell_navigation_test.dart test/architecture --reporter expanded
```

**Exit0, +180 All tests passed, 16s.** Whole named files/subsystems and all architecture tests, not a name-filtered run. Expected synthetic shadow-provider exception output is caught by its no-propagation test; no failed test remains.

```text
flutter test --no-pub test/screens/srs_flashcards_screen_test.dart test/screens/quiz_screen_test.dart test/screens/learning_loop_layout_test.dart --reporter expanded
```

Final independent whole-file rerun after connected checks: **exit0, +29 All tests passed, 7s**. No source/test edit between these two runs.

`git -c core.safecrlf=false diff --check` over the tracked four source/test paths: **exit0**. Manual final scope/diff check includes the existing untracked layout test and this new checkpoint. No unrelated line-ending normalization or cleanup performed.

Runtime inventory at **2026-10-21T03:19:23+07:00**: `task_runtime_process_count=0`, using Get-CimInstance Win32_Process filtered for workspace Flutter/Dart/tester/frontend/Firestore Java processes. All exec test sessions completed; reviewer finished read-only work. No process was killed.

## Review and UI evidence limits

- Independent reviewer `/root/lq04_i3b_review` read current Quiz/SRS/tests and LearningUseCases→Drift paths, changed no files and ran no Flutter/Dart checks. Disposition **accepted; no must-fix**. After style-only correction, reviewer verified both final production hashes below and reaffirmed accepted. Test evidence is root-run, not invented reviewer execution.
- Claude review: **not available for this I3b implementation**; no new request, provider access or 401 retry was attempted. Earlier proposal critiques are historical, not a fresh code verdict for this card.
- Ponytail kept the existing authorities and screen state; Impeccable/UI-UX Pro Max checks informed scrollable long-text content, native visible controls, 48/52dp targets, textual self-rating and live feedback. Existing Material3/product/design identity was preserved. Local search did not provide a verified specific Flutter text-scroll match; the implementation uses the incumbent Flutter pattern/general guidance, not a claimed database recommendation.
- Widget evidence covers SRS 360×800/light and 800×360/dark at 2× with long spelling/Thai meaning, failed save/retry and saved Next; Quiz 360×800/dark at 2× hint/reveal/error/retry, live-region property and reachable CTA; Score/Weakness 360×800 at 2× plus unchanged1.8× golden comparisons. This is not measured contrast certification, native pixel review, actual TalkBack, Reduce Motion, physical-device or process-kill evidence.

## Release dependencies / next executable step

This is an in-memory-screen retry/feedback change; restart/process-kill persistence of pending UI intent is not introduced or claimed. Frozen answer/event contracts are unchanged. No all-activity event/quest/streak dedupe redesign or new efficacy claim is made. C-COIN local-only carry and old mixed-client downgrade limits remain exactly as previously accepted.

No device/emulator UI run, APK/full-repository build, live provider, production access, deployment/publication, real participant enrollment or research upload. This card does not grant those permissions or claim release readiness. No Codex Security worker or new subagent beyond the single authorized independent reviewer was used.

**Next:** root compares the actual current diff and five-file manifest, accepts/rejects bounded I3b/whole-I3 local closure, and assigns the next writer. LQ-04 returns the exclusive production-writer/Flutter slot with this handoff and starts no next card. Existing branch/worktree and unrelated edits remain intact.

## Final SHA256 manifest

| Source/test path | SHA256 |
| --- | --- |
| `lib/screens/srs_flashcards_screen.dart` | `9C48ED5C48CB123E7ECBCBEC8E7B1129075E027CCAF62AD6C266AA13C5576383` |
| `lib/screens/quiz_screen.dart` | `3C587F8E351D19BE52D48E6BB28EC837E6422197AA97D21C9C3D817F21B1F18F` |
| `test/screens/srs_flashcards_screen_test.dart` | `2BB1A3EE9FDA9F04FCA9C4F3DBC93BA16CE4B186623996D1C96A4C5C448EB3B3` |
| `test/screens/quiz_screen_test.dart` | `997A378FDF48CA95593A52DDCE6BD83A2346A86C642196CE275BFC3915F24F61` |
| `test/screens/learning_loop_layout_test.dart` | `E7571D61486D7B882D7DE4C39515B9EDF5E137B88F33A200565AED316959C708` |

Checkpoint hash is sent separately to both authorized source/root coordinators to avoid self-reference. No commit/merge/push or destructive cleanup performed.
