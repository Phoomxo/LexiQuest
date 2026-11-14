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
| S6 | Existing motivation and advanced modes. | Single reward authority, honest availability, contextual return. | S6-A/B/C and D1/D2 accepted; D3 Streak/Settings and D4 Mastery/Profile locally accepted in full2089/analysis/review; other catalogue journeys remain |
| S7 | Root integrates the frozen source and reconciles remaining catalogue journeys. | Current-SHA regression, 48/44/64 disposition, APK/hash/CI and native critique. | Practice9371b434 full2150/CI/build accepted; f31 locally accepted in full2176/focused354/analysis/review; its new-head CI, remaining journeys and final native/current APK remain pending |

## S7 remaining persistence and recovery plan

This unit follows integration of f31. Practice commit9371b434 has successful exact-head CI43571302282; dirty achievement evidence is separate. The next migration candidate is v12, still **unreserved**. Re-read the ledger and reserve its concrete scope before migration code. Existing local implementation authority applies; no rollout or live-data permission follows.

Task board: Ground and Sketch complete from current v11 source and pinned21b34eaa; existing authority supplies Agree. Implement, Review, Attest and Integrate remain pending. Scrap the sketch only if implementation disproves its invariants. Compare normalized relations, an embedded owner profile and a narrow hybrid: select the hybrid below. A local word bit replaces a saved-word table; independent reports, timers and preferences remain separate. Actual f43 requires the selected wrong response, and f24 requires measured active/pause ranges; boolean correctness and a total duration cannot reconstruct those approved displays.

| Data | Selected contract |
| --- | --- |
| Existing session, two nullable columns | Immutable versioned `question_plan_json` pins ordered text/options and original lexical/source revisions. CAS `continuation_json` holds cursor revision/slot, awaiting/feedback/finished phase, last committed attempt and active response elapsed. Legacy/remote NULL is unknown. |
| Existing attempt, one nullable column | Versioned `answer_evidence_json` contains slot and selected option/reveal or required self-rating. Freeze it atomically with the answer; compare on local replay. Collect no raw typed text/audio here. |
| Existing word, default-false bit | `is_bookmarked` is local-only. Toggle does not revise content/edit time or queue word sync. Inbound upserts preserve it; exact-sense guest/target duplicates OR before source deletion. Hide deleted words/categories. |
| New `local_content_reports` owner scope | Stable ID, actual source/revision, bounded reviewed excerpt, approved reason and creation time. Only locally stored/not delivered exists; cancel writes nothing, replay compares the same draft. No invented sentence, recipient or delivery worker. |
| New `focus_sessions` owner scope | Stable ID, owner/origin, target, captured start home-calendar/week, state/revision and compact closed measured active/pause spans. Foreground duration uses a monotonic clock; UTC endpoints explain display. Background checkpoints; restart recovers paused/interrupted without estimating a lost tail. |
| New `learning_preferences` owner scope | Explicit onboarding purpose/minutes/method or skipped/unset. Independent goal date distinguishes active/closed/unset, including a closed tombstone on merge. Planned time is separate from measured focus. |

Candidate physical count34→37 must be checked against generated schema; catalogue counts stay48/44/64. Preserve frozen EvidenceContext/EventEnvelopeV2 and public sync payloads. Use existing destinations/child panels, with no49th screen.

Execute in dependency order:

1. **Migration/lifecycle foundation.** Root owns ledger, `lib/data/local/app_database.dart`, generated Drift and shared inventories. Capture an actual v11 SQL fixture with serialized tooling before migration. Test populated upgrade/reopen, NULL/default semantics, fresh/upgraded parity, FK integrity and rollback/re-entry without reset or fabricated facts. Extend `lib/features/identity/domain/owner_upgrade.dart`, owner merge, full export/delete contracts/fixtures and backend version-specific local export scope validation together; preserve old versions and fixed cloud scopes. Every new owner table must be exported and deleted.
2. **f05/f43 durable round/history.** Extend existing learning domain/repository/use cases and Quiz lifecycle. Start pins the plan; answer and feedback cursor share the existing answer/SRS/XP/coin transaction. Lost acknowledgement restores saved feedback; deliberate retry uses a new attempt at the same slot. Pause reconciles the admitted attempt first. Fresh facts/finish reject paused and remote-only sessions. Owner/cursor/revision fences run inside the transaction. Test two-word pause/restart, wrong→retry→next, original selected response after edit/delete, duplicate commands, stale owner and merge FK remaps. Resume requires verified current owner/word/revision; unavailable resumption must retain honest historical viewing. Preserve inbound/outbound sync shape and local evidence on replay.
3. **f20/f21 bookmarks/reports.** Add owner-bound desired-state bookmark and reviewed-draft queue operations at existing vocabulary/content boundaries. Verify restart, same-spelling/different-sense isolation, stale owner, cancel/retry, merge OR and local-only sync. Open the actual saved word/source; an unlinked reader token or unavailable authored sentence cannot fabricate a report.
4. **f23/f24/f26/f35/f36 focus/preferences.** Add a small local study domain/data/application slice with injectable monotonic/wall clocks. One open timer per owner, expected-revision transitions and bounded target completion prevent duplicate time. Preserve original measured active/pause ranges; mark unverifiable crash gaps unknown. Attribute a session to its captured start civil week across home-zone changes/merge. Test background, rollback, restart, repeat finish, concurrent routes, owner changes and merge of two open timers. Focus alone must create no attempts, XP, coins, achievements, Streak attendance or research rows. Verify preference skip/edit/reopen, closed-goal tombstone and countdown using current home civil date.
5. **Review/integration.** Serialize focused real-DB/UI/export/delete/backend checks, analysis/format and independent review; freeze compiled inputs for full regression and compare manifests. Update only evidenced catalogue dispositions, commit/push, read exact draft-PR head/body and follow exact-head CI. Build a current-SHA signed APK with explicit research/cloud-off flags and retain device data. Native workflows, TalkBack and known-object accuracy need their own actual observations.

Focused commands include `flutter test --no-pub test/database`, touched learning/vocabulary/identity/sync/progress/account-deletion and screen tests, existing backend account-deletion contract tests, `flutter analyze --no-pub`, format verification and full Flutter regression at integration. Use meaningful RED/real-file checks before new nontrivial behavior. All Flutter/pub/codegen share one root-owned queue; disjoint writers stop before repository-wide checks.

f44 remains manifest-bound offline camera-model verify/repair/cancel/confirmed-remove through the existing manager/Settings, preserving learning history. Its exact-file restart recovery and cached-interpreter lifetime need synthetic-file tests; it requires no learning table. No separate Pair Matching task is created. Known-object accuracy remainsnot_checked without another request; uncertain emulator1837 remains untouched.

## Grounded constraints

### S6 architecture task board

- [x] Ground: three read-only source explorers and a separate explainer traced committed answers through Quest, Streak, XP/coins and schema/owner inventory. Working artifacts: build/architect-s6/grounding.txt and how.txt; no S6 production changes.
- [x] Sketch: both whole packages and alternatives read; reconstruction selected, independent judge A23/B24of30. See s6-architecture.md for grafts and constraints.
- [x] Agree: existing implementation authorization applies; no new discussion-only approval gate. UI baseline04c19a93 now has successful full CI and vivo v29 evidence.
- [x] Implement the selected motivation core: S6-A/B/C and D1/D2 accepted; CIe1d7a5e9 full2021/backend237/build succeeded. D3 Streak/zone scheduling and D4 Mastery/Profile locally accepted in full2089/analysis/review with555 stable inputs. Receipt: evidence/s6-d3-d4-streak-surfaces.txt. Exact-head CI/native and other S6 catalogue journeys remain separate.
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
