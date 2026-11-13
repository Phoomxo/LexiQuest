# FigCraft Flutter execution

Worktree `C:/Users/Phet/.codex/worktrees/figcraft-flutter-v1/LexiQuest`.
Branch `codex/figcraft-flutter-prototype`. Plan baseline `6a31964693f673b030a8c2a5d998a0a6da278e42`.
Flutter baseline `e05e8a6c`. Design baseline `21b34eaa` in the design-reset worktree.

## Outcome and authority

The active continuous Goal includes all S1–S7 work below. Completing the first card does not complete the Goal.

The first milestone is two visible comparison images, one for practice home and one for the library. Each pairs the pinned FigCraft render with the current Flutter Android render in the same state and proportions. Record source SHA, device model, real device versus emulator, synthetic data state, Thai typography/diacritics, spacing, button behavior, and independent Impeccable findings.

For the first Android journey, start in selected set A with a distinct set B also present. Capture an actual photo, confirm its proposed word into A, practice from A to a persisted result, and return to A. Verify A's name/ID, the added word, and the linked session result. Restart the app and read both the same word and result. Preserve the before/result/after screens or a video. Add a regression check against returning to B. An unavailable real device leaves only that evidence pending while emulator and local work continue.

Implement S1 through S7 in dependency order. Preserve the denominators of 48 screens, 44 features, and 64 work packages. A screen opening does not prove its feature works. Engineering acceptance, release readiness, research authority, and publication remain separate. No merge, deployment, real enrollment, or real research upload is authorized.

The end-to-end predicate is app → library → camera → confirm → practice the selected set → result → return to that set → restart and read the saved data. Use synthetic records and existing owners, use cases, repositories, and reward authorities.

## Execution board

1. Read the poteto-mode Principles. Ground the plan against source and design evidence.
2. Frame. Capture the baseline and identify real device/service constraints.
3. Design the workflow. Use the approved S1–S7 cards rather than another product planning cycle.
4. Run the loop. For each card, write a focused failing behavior check, implement, verify, and obtain independent review.
5. Keep the audit trail in `decisions.tsv` and preserve per-card evidence.
6. Verify and hand back. Inspect the final diff, serialize full checks and APK build, verify CI against the PR head, and report every unverified item.

| Card | Write owner and boundary | Acceptance | Status |
| --- | --- | --- | --- |
| S1 | Root owns shell, practice home, and progress read projection. Test agent owns shell/home tests. Independent critic owns no production files. | Four Thai tabs, actual due preview/count, distinct new/empty/error states, library entry, contextual return, feature gating, large text. | Executing |
| S2 | `s1_tests` owns library summaries, search, destination selection and set UI. | Search, add/import, preserve selected set and filters, reopen persisted words. | Executing; async owner/scope review corrections pending |
| S3 | `ground_routes` owns progress category context and latest-set result; root integrates learning evidence. | Real answers, feedback, result context, durable and idempotent outcomes. | Executing; selected-set SQLite regression passed on previous source, new projection checks pending |
| S4 | `ground_routes` owns editable manual correction from camera results and its tests. | Explicit confirmation into selected set, failure recovery, known-object device evidence. | Executing; real captures recorded, correction GREEN/device retry pending; known-object accuracy not checked |
| S5 | `s1_tests` owns Settings/Profile; `ground_routes` owns progress/export/account boundary cases; root integrates. | Owner isolation, export/deletion, offline learning, research default-off. | Executing; stale-scope REDs reproduced and fixes await final focused GREEN/review |
| S6 | Existing motivation and advanced modes. | Single reward authority, honest availability, contextual return. | Pending |
| S7 | All writers paused for integration. | Current-SHA regression, 48/44/64 disposition, Android APK/hash/CI, independent runtime critique. | Pending |

## Grounded constraints

- A vivo V2041 is connected. Its existing `com.lexiquest.app` is versionCode 26. Inspect signing and data compatibility before any replacement. Do not clear or uninstall it.
- Flutter dependencies resolve using the existing lockfile. No dependency upgrade is part of this task.
- Existing progress has no vocabulary count or due-word preview. Extend its read projection without a schema migration rather than infer empty vocabulary from zero answers.
- Existing library lacks selected-set camera and quiz entry. Camera acceptance currently chooses a mapped category. These must share an explicit destination before the core journey can pass.
- Baseline screenshots and new Android screenshots are distinct from FigCraft design renders. TalkBack and known-object accuracy require their own observations.

## First S1 code slice

The focused shell/home/progress check passes 41 tests. This includes a real Drift-memory due review that writes one answer and completes one session, then returns to the same shell. The library shortcut retains the existing tab and scroll position. The independent source reviewer found no blocking issue in the five production files. The Windows large-text render was inspected before its golden was updated.

This is not whole-S1 acceptance. The separate practice menu, explicit library-mutation refresh case, Android runtime images, 200% device checks, and TalkBack observation remain open. Linux font rendering must be inspected from CI. The first baseline test run overlapped test-file edits and is not used as a clean baseline result.

## Core journey milestone source

The practice menu now has its own route. The library retains set/word search context and offers a single add-word menu. Camera confirmation receives the selected category and expected owner, returns the saved word to that category, and prevents duplicate confirmation while saving. Quiz results retain the selected set name and session ID. Due review opens its persisted result before returning. Progress reads the latest 20 completed sessions and re-reads a selected session by current owner before displaying it.

The current source passes 136 focused tests and `flutter analyze lib`. A further nine-test run passes the complete synthetic camera → confirmation → quiz → result → set-A return → SQLite close/reopen regression, large-Thai-text layout, and accessibility smoke checks. In that regression the camera/model boundary is synthetic; persistence, scanner acceptance, vocabulary, and learning use the real authorities. Set B's entire word record remains unchanged.

These are local engineering results. Android capture, process restart, known-object camera evidence, device 200%, TalkBack, final full regression, and current-head CI remain pending. The first PR run on `67a68518` passed formatting, analysis, Firestore, and Supabase checks but failed an old home-label assertion and the Linux home golden. The assertion is updated in this source; inspect the new Linux render before updating its golden.

The installed vivo APK certificate SHA-256 matches the configured release key. Its versionCode is 26. The active source and original checkout both declare database schema 10. The existing APK was copied to `build/android-baseline/` for local evidence. No app data was cleared or uninstalled. Signing configuration is ignored and must never be staged.

The independent milestone reviewer found two boundary defects after the first source commit. Both were reproduced before correction. Live quiz results now respect the quiz/weakness repair gate and preserve the registry in child routes. Scanner confirmation pins the expected owner through category and word creation, rejecting a changed owner before calling the repository. Synthetic lookup races verify that the second owner receives no category, word, or outbox write. The corrected boundary suite passes 101 tests and full `flutter analyze --no-pub` reports no issues. The reviewer accepted both corrections. Native evidence is still pending.

## Corrected native milestone at 08ce39bc

The corrected source passed all 1,821 local Flutter tests and clean full analysis. Signed v28 updated vivo with existing sets preserved. Actual photo capture returned no confident proposal; the tester entered synthetic mug/แก้ว/noun in the camera correction form and explicitly saved into A. Practice included mug, produced 67% (2/3), returned to A, then read the same words and result after offline process restart. B remained empty. See `evidence/vivo-08ce39bc/README.md` and its manifest. This demonstrates manual camera workflow and persistence, without claiming model recognition accuracy or a native session UUID.

Corrected FigCraft/Android comparison images for home/library were captured on the same source and shown in the chat. Emulator verification found the exact synthetic reference state without reseeding. The independent native critique is being completed separately; S1–S4 source/native core evidence does not close every advanced, accessibility or service criterion in those cards. All S5–S7 work and every 48/44/64 row remain tracked.

CI on `08ce39bc` passed formatting, analysis and Firestore/Supabase checks but failed only the old Linux home golden. The actual Linux render and diff were opened before updating the expected image. Its source is the CI artifact from run `43486122536`, not a recreated Windows or design image. New-head CI remains required.
