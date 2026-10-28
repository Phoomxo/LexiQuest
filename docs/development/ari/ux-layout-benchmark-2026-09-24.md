# LexiQuest UI layout benchmark — 2026-09-24

## Decision context

User feedback from the demo: most participants found the app difficult to use and unlike familiar learning apps. The 215-criterion R3 acceptance run is paused by user priority; previous evidence remains retained. This is a layout and task-discovery study, not evidence that any competitor's design will work for LexiQuest users.

## Public product references

| Product | Publicly documented mobile structure | Useful pattern for LexiQuest |
| --- | --- | --- |
| Duolingo | A guided lesson path makes the next activity explicit; practice and quests are reachable from bottom tabs. Its recent tab refresh aligned headings, type, and spacing across sections. | One obvious next action and a consistent shell; avoid turning the home screen into a long catalog. |
| Babbel | Mobile bottom navigation separates Learn, Practice, Speak, and Progress. Learn surfaces upcoming lessons; Practice organizes vocabulary, listening, speaking, and grammar. | Separate everyday learning from the full practice catalog. AI speaking is a distinct optional capability. |
| Busuu | Course lessons follow a timeline; Review groups vocabulary and grammar; a Speak entry and Me/settings remain separate. | Give review an obvious entry without making users select a technical mode first. |
| Memrise | Home groups work into Learn, Immerse, and Communicate, with language, level, and points summarized above. | Group many activities by learner goal rather than implementation-specific mode names. |
| Quizlet | Mobile home feed emphasizes short activities, recent progress, and relevant recommendations; other study content lives in Library. | Resume recent work and provide a short activity before showing the whole collection. |
| AllTCAS (Thai exam-prep reference) | Its public site presents exam practice by subject/type, interactive worked answers, a separate vocabulary/flashcard area, play-with-friends, and study-time statistics. The App Store listing describes the companion Allie. Public materials do not establish the exact current in-app bottom-navigation arrangement. | Use familiar Thai task labels and a visible path into practice; keep detailed explanations close to each answer. Avoid borrowing exam-only information architecture wholesale. |
| Astra AI | Its Thai product page leads with an immediate ask/speak/photo input, then offers flashcards, quiz, review, study plans, and visible streak/progress. These are marketing/product views, not a verified logged-in mobile navigation map. | Give the learner a clear first action and offer alternate input methods contextually. Keep LexiQuest's AI optional because its manual learning baseline is a product requirement. |

Sources (official product/help material, accessed 2026-09-24):

- Duolingo: https://blog.duolingo.com/new-duolingo-home-screen-design/ and https://blog.duolingo.com/core-tabs-redesign/
- Babbel: https://support.babbel.com/hc/en-gb/articles/360029715892-Using-the-Babbel-app-on-a-mobile-device
- Busuu: https://help.busuu.com/hc/en-us/articles/16941990776593-How-can-I-review-my-vocabulary and https://help.busuu.com/hc/en-us/articles/21862192336402-What-are-Busuu-Conversations-and-how-can-they-help-me-learn-a-language
- Memrise: https://www.memrise.com/blog/major-update-a-new-version-of-the-app-is-coming
- Quizlet: https://help.quizlet.com/hc/en-ca/articles/38999971996301-Navigating-your-home-feed-on-mobile-devices
- AllTCAS: https://alltcas.com/ and https://apps.apple.com/th/app/alltcas/id6789263820
- Astra AI (confirmed by user): https://astra-ai.co/th/ and https://apps.apple.com/th/app/astra-ai-study-exam-prep/id6751030141

This sample describes representative large apps, not a market-share ranking. Public pages may show platform or account variants; no logged-in competitor usability sessions were conducted.

## Current LexiQuest contrast

`lib/screens/main_navigation_screen.dart` currently provides five primary destinations (learning, vocabulary, mastery, achievements, profile) plus a long drawer. Its learning destination embeds `ChooseModeScreen`. `lib/screens/choose_mode_screen.dart` starts with a short-practice card, then Today/planning cards, then a grid of up to 14 modes in three groups. Today is secondary rather than the default entry. This exposes breadth but asks a new learner to choose a method before knowing the next useful action.

## Recommended first UX increment

1. Prototype a task-first home: a single primary action (`เรียนต่อ` when a session is resumable, otherwise `เริ่มฝึกสั้น ๆ`), followed by `ทบทวนวันนี้` and `คำศัพท์ของฉัน`. Preserve the no-login/no-AI baseline.
2. Put the complete 14-mode list behind a clearly labeled `เลือกวิธีฝึก` destination, still reachable in one tap from home. Group it by learner goal (remember, read/write, listen/speak); preserve all existing route IDs and feature gates.
3. Keep primary navigation to a small, stable set such as `วันนี้`, `ฝึก`, `คำศัพท์`, `ฉัน`. Surface progress/rewards within `ฉัน` or a secondary destination; keep AI help optional and visibly separate. Confirm this information architecture with users before removing any existing primary tab.
4. Use one header hierarchy, consistent Thai labels, spacing, and button styles across the pilot screens. Do not modify scoring, ownership, storage, or lesson authority for a visual change.

## Pilot acceptance

With a fresh local profile and no provider, a learner can identify and start the next activity, find a specific practice mode, add a word, and find progress without explanation. Test these tasks with the same kind of demo users and record success, wrong turns, and where they hesitate. Compare with the existing demo before expanding the visual system. UI-specific acceptance rows affected by changed routes must be revalidated later; unchanged domain/storage evidence can be reused only when its recorded dependencies and fingerprint still match.

## First implementation checkpoint

The first small UI increment uses `ChooseModeScreen.focusHome` only in the primary learning destination. It keeps the existing short-practice start and Today/planning entries, while placing the full mode grid behind the clearly labeled `ดูโหมดฝึกทั้งหมด` button. Direct mode-picker routes retain the full list. No lesson, score, storage, owner, or AI interfaces changed.

Test-first evidence: the new main-navigation widget test failed before implementation because the cloze tile was visible immediately; it then passed after the change. `verify-scope.ps1` targeted runs passed 45 main-navigation tests and 70 mode-picker tests; `dart analyze` of the three touched Dart files reported no issues. The exact verification receipts are `build/verification/2ea4d407e7d5b1d41af65a533691b8aafe019ac5/targeted-learning-6feddb3ffd30d2063ad1974162da345c6ac132a46c685a3d71d37df5667d48cd.json` and `build/verification/2ea4d407e7d5b1d41af65a533691b8aafe019ac5/targeted-learning-eaf57345f079d1a8426799df64d9da516c3af578feefe031c3998d07c1a61b4b.json`.

The full shell/tab restructuring and visual polish are not complete, and no fresh user or native usability test has been run on this increment. The R3 acceptance run remains paused at four closed of 215 criteria; do not count this UX test as closure of an R3 row. Next: observe the four pilot tasks, refine the primary navigation and visual hierarchy from those results, then run only UX-affected checks before resuming broader acceptance on a stable layout.

## User feedback and task-first redesign sequence

The demo feedback now clarifies the problem: menus feel hard to use, the overall system looks complex, and ordinary learners cannot see how the features answer their immediate need. The prior mode-collapse change reduces visual load but does not by itself prove that the workflow is understandable. Do not declare the UX problem solved from widget tests.

The user jobs to validate are:

1. First visit, no login or AI: identify how to start a short English↔Thai lesson and complete it.
2. Return after interruption: find the current lesson or today's due review without choosing an internal mode name.
3. Add or find a personal word, then practice it.
4. Find a simple account of progress and history, with rewards and advanced settings reachable but not competing for the first action.

Work one UX increment at a time:

1. **Home clarity.** Keep exactly one visually dominant primary action; promote resume/review when canonical current-owner data supports it, otherwise offer a safe starter. Add a plain-language path to personal vocabulary. Use existing Today, lesson, owner and storage authorities. Loading or provider failure must leave a working manual route.
2. **Navigation prototype.** Trial a four-destination shell (`วันนี้`, `ฝึก`, `คำศัพท์`, `ฉัน`) with a task-based drawer for less frequent actions. Keep existing route IDs, deep links, feature gates and accessible labels. Do not remove progress/rewards access while moving it. Confirm the prototype with users before replacing the current five-tab shell.
3. **Visual consistency.** Establish a shared header, card, spacing and button hierarchy on Home, Practice, Vocabulary and My/Progress. Keep Thai text readable at larger text scale and on narrow phones. Avoid technical status wording during healthy operation; show local-data problems prominently and keep details accessible.
4. **Pilot.** Use the four tasks above with fresh and returning local profiles, including disconnected AI. Record task completion without prompting, wrong turns, time and user wording; compare to the current demo. Do not infer usability from a passing widget test. Iterate on observed failures before broad UI rollout.
5. **Verification.** Test changed navigation/semantics and no-login journeys through bounded `verify-scope.ps1` runs, then a native UX smoke on an isolated build with backup/restore. The 215-row R3 acceptance run is paused indefinitely by user direction; do not reopen or resume its rows automatically when the layout stabilizes. Await explicit user direction and rebaseline any revised criteria first.

Second implementation checkpoint: when local data is healthy, the shell header now shows `LexiQuest` instead of `ข้อมูลในเครื่องพร้อมใช้`; degraded or unavailable local data still displays a warning, and the details dialog remains available. The new status-header widget test failed before the change and passed after it. The targeted main-navigation suite passed again and `dart analyze` of the touched Dart files reported no issues. This is a copy/hierarchy improvement, not a completed information-architecture redesign.

Third implementation checkpoint: the Today entry on the learning home now says `เรียนต่อหรือทบทวน` and explains the two user tasks in plain Thai, while retaining the same `home/today` route and feature gate. Its focused widget test failed on the old `วันนี้` title and passed after the copy change. The current targeted main-navigation suite passes 47 tests; analysis of the three touched Dart files is clean. The app has not yet been installed or tested with demo users on this source.

## UX feedback checkpoint — menu confusion

The user clarified that the demo felt built around features rather than ordinary learners' goals: the menu was confusing, the system seemed complex, and the first useful action was unclear. This confirms that hiding the 14-mode grid alone is insufficient. The next increment should be judged by whether a new learner can start, resume/review, manage personal words, and find progress without explanation.

A trial home change added a personal-word shortcut and collapsed planning. Its new task tests failed RED as expected, but the full main-navigation test then failed twice on the same accessibility assertion: both the shortcut and the vocabulary tab matched the tab's semantics lookup. The trial code and tests were removed; no known failing UI source from that trial remains. Per project guardrails, stop this work package and report the repeated failure rather than iterate blindly. The last passing targeted main-navigation receipt remains the 47-test run above; it has not been rerun after the revert. Next: inspect the tab semantics helper and design the shortcut with a distinct accessible action, then make a focused RED/GREEN test before a single bounded suite run. A native/user usability pilot is still required before calling the layout improved.

## Standalone design draft

The follow-up visual draft is at [`../../design/lexiquest-ux-concept.html`](../../design/lexiquest-ux-concept.html), with decision notes and preview images in [`../../design/README.md`](../../design/README.md). It proposes a four-destination task-first shell and is deliberately separate from Flutter production source and R3 acceptance. No 215-criterion test is resumed by this design work.

The expanded Thai-first draft is [`../../design/lexiquest-full-ux-prototype.html`](../../design/lexiquest-full-ux-prototype.html). It covers the 14 workflow-group inventory and 14 nested modes through 33 design views, with new/returning/offline and optional-AI states. Its coverage and limitations are documented in [`../../design/README.md`](../../design/README.md). This is still a design artifact for user walkthroughs, not evidence that the production app's UX or R3 acceptance passed.
