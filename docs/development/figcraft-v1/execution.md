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
| S1 | Root integrates shell, home and progress; all production writers currently frozen. | Four Thai tabs, actual due preview/count, distinct new/empty/error states, contextual return, gating and large text. | Current local source accepted; P2 native visuals/a11y pending |
| S2 | Root integrates library/search/set scope guards and accepted independent reviews. | Search, add/import, selected-set/filter context and persisted words. | Current local source accepted in full1903; new-APK retest pending |
| S3 | Root integrates Quiz/Score/Weakness/source/history fixes. | Real answers, honest assessment, durable outcomes and origin-specific return. | Full1903 and review accepted; remaining catalogue/native criteria remain open |
| S4 | Existing scanner/manual-correction authority and its tests. | Explicit save into original set, recovery and separate accuracy evidence. | v28 actual-photo/manual journey accepted; known-object accuracy not_checked; other service criteria open |
| S5 | Existing Settings/Profile/export/account boundaries. | Owner isolation, export/deletion, offline learning, research default-off. | Full-export adapter committed; new logout/freshness/scope subcards accepted; remaining catalogue/composition/release criteria open |
| S6 | Existing motivation and advanced modes. | Single reward authority, honest availability, contextual return. | S6-A/B/C and D1 accepted; D2 read/claim/XP locally accepted in final2021/analysis/review; D3 Streak/Settings and D4 surface remain |
| S7 | Root integrates the frozen source. | Current-SHA regression, 48/44/64 disposition, APK/hash/CI and native critique. | Baseline04c19a93 full1903/CI/build accepted; vivo v29 observations accepted; new emulator P2 images, subsequent S6 integration and catalogue reconciliation pending |

## Grounded constraints

### S6 architecture task board

- [x] Ground: three read-only source explorers and a separate explainer traced committed answers through Quest, Streak, XP/coins and schema/owner inventory. Working artifacts: build/architect-s6/grounding.txt and how.txt; no S6 production changes.
- [x] Sketch: both whole packages and alternatives read; reconstruction selected, independent judge A23/B24of30. See s6-architecture.md for grafts and constraints.
- [x] Agree: existing implementation authorization applies; no new discussion-only approval gate. UI baseline04c19a93 now has successful full CI and vivo v29 evidence.
- [ ] Implement: S6-A/B/C and D1 accepted; CIfd22b778 full1999/AI107/build succeeded. D2 reconstruction/explicit claim/XP locally accepted in full2021/analysis/review with550 stable inputs. D3 Streak/zone scheduling and D4 surface remain open; D2 local evidence does not certify native/UI or the whole catalogue.
- [ ] Scrap: conditional review step if the selected shape cannot protect its invariants; never patch around an invalid ownership model.

Arena checklist: original frame, both candidates, cross-judge, pick and graft complete; implementation verification is per unit. Actual models: gpt-6-astra/high, gpt-6.1-sol/high, cross-judge gpt-6.1-terra/high. The single-interval calendar premise was disproved by a rerunnable St Johns test; a directed comparison chose exact segments over honest refusal (18/15of20). D2 writers are frozen after verification; root owns integration and the Flutter queue. Canonical UI remains existing Mastery; committed schema is11 with no rollout. Claude/Grok defaults are unavailable; no provider or model identity is invented.

- Baseline vivo V2041 had versionCode26. Signed v28 is now installed with existing data retained; read actual device/signing/schema state before the next update. Do not clear or uninstall it.
- Flutter dependencies resolve using the existing lockfile. No dependency upgrade is part of this task.
- Baseline progress lacked vocabulary count/due preview; the current read projection supplies them without a migration. Never infer empty vocabulary from zero answers.
- Baseline library lacked selected-set camera/Quiz entry; the implemented destination pin and manual correction passed the v28 core journey. Retain that context during further changes.
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
