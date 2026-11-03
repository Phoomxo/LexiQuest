# Internal verification ledger for all 44 capabilities

Worktree `C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest`, branch
`codex/remaining-system-readiness`, starting commit `a56e80d2` plus this run's
changes. Catalog revision1.3.0 retains eight domains and exactly f01-f44.
Catalog rollout metadata remains unverified; this report does not change it.

Internal completion requires a reviewed implementation, passing required checks
on the current source, and an explicit evidence boundary for each capability.
This ledger covers 44 existing capabilities, not 44 exhaustive device UATs.
The full host suite now passes5,614 cases on its captured source inputs, with
clean analysis. Final artifact attestation remains pending. Feature f27 is
OPEN because the signed app reproduces the first-permission failure despite
the isolated Permission1 fixture passing. The earlier5,598 host pass belongs
to source `998171bc` and remains historical evidence.

## Evidence key

All local logs below are under
`D:/LexiQuest-Storage/maintenance/2026-11-03/emulator44/`.
Test paths in the table are relative to the repository's `test/` directory.

- **Host baseline** means the representative test appears in the existing
  [all44 acceptance ledger](2026-11-03-all44-acceptance.md), with the subsequent
  full5,598 pass recorded in [remediation27](2026-11-03-emulator44-remediation.md).
- **Host5614** is `complete-full-tests.log`,5,614/5,614 PASS.
  `complete-full-result.json` records `testExit: 0`,1,030 input files and no
  changed inputs during the run. `complete-analysis-final.log` reports no issues.
  These receipts attest that captured source, not subsequent diagnostic edits
  or a signed artifact that has not yet been verified.
- **Observed26** means the bounded signed-app workflow in
  [emulator44 acceptance](2026-11-03-emulator44-acceptance.md). Its failures and
  partial coverage remain historical evidence.
- **Observed27** means a specific corrected signed-app workflow in remediation27,
  including navigation/share, Thai locale and database/cache restart durability.
- **Native45** is `complete-extended-native-final.log`,45/45 PASS. It covers34
  durable-resume/history cases across five exercise kinds, nine recall-route
  cases and two canonical streak/reward journeys on synthetic Android data.
  Generated content and voice dependencies in these fixtures are synthetic.
- **Permission1** is `complete-reminder-permission-red.log`,1/1 PASS despite its
  provisional filename. Real Android permission grant, first Save ACK revision2,
  disable ACK revision3 and SQLite quick_check passed without a second Save.
  This isolated fixture does not close the signed-app failure described below.
- **Reminder27 follow-up** reproduces request-unconfirmed after permission grant
  in the signed app (`complete-316-delivery-state.xml`). Explicit retry obtains
  ACK (`complete-317-reminder-retry.xml`). A later updated alarm posts actual
  notification2701 at08:50 UTC with the generic reminder body, shown in
  `complete-delivery-notification.txt` and `complete-322-delivered.xml` while the
  app is on Home. Delivery after recovery does not establish first-Save success.
- **Focused9** is `complete-boundary-focused.log`,9/9 PASS for corrected date
  boundaries, canonical journeys and the two formerly missed History taps.
  The earlier failing logs remain available.
- **Accessibility6** is the six passing login/register/common-shell cases in
  `complete-journeys-host2.log`. That combined run also contains other failures;
  it is not a wholly passing suite. The checks cover large text and labeled,
  minimum-size tap targets on those surfaces only.
- **Scratchpad repeat** is `complete-scratchpad-native-repeat.log`,12/12 PASS:
  four scenarios repeated three times on Android, not12 distinct scenarios.

## Capability ledger

| ID | Capability | Representative host acceptance | Additional evidence and remaining boundary |
|---|---|---|---|
| f01 | Curriculum and learning pack catalog | `screens/learning_pack_catalog_screen_test.dart` | Observed26; bundled catalog, no live publisher approval claim. |
| f02 | Learning pack detail | `screens/learning_pack_actions_screen_test.dart` | Observed26; retained provenance/version. |
| f03 | Rich lexical card | `screens/rich_lexical_actual_callers_test.dart` | Observed26; no invented lexical facts. |
| f04 | Content version and quality control | `features/learning_packs/rich_lexical_codec_test.dart` | Observed26; validation does not certify editorial quality. |
| f05 | Unified lesson shell | `widgets/lesson_scaffold_test.dart` | Observed26; Accessibility6 for shared shell. |
| f06 | Flashcard mode | `screens/srs_review_callers_test.dart` | Observed26; prior bounded physical speech/reveal confirmation is separate. |
| f07 | Meaning quiz | `screens/configured_quiz_recovery_screen_test.dart` | Observed26; shared SRS overflow corrected, current full regression pending. |
| f08 | Definition quiz | `screens/definition_quiz_screen_test.dart` | Observed26; authored-content boundary remains. |
| f09 | Cloze test | `screens/fill_in_the_blanks_screen_test.dart` | Earlier synthetic Android pass plus Native45 typed/choice resume; no live generation claim. |
| f10 | Matching mode | `screens/matching_entry_history_flow_test.dart` | Observed26; Native45 actual matching entry, recognition is not recall mastery. |
| f11 | Typed recall/writing | `screens/learning_pack_definition_flow_test.dart` | Observed26; Native45 actual catalog entry, drafts are not accepted evidence. |
| f12 | Handwriting scratchpad | `screens/typed_cloze_scratchpad_test.dart` | Late-inset host test and Scratchpad repeat pass. Original intermittent Save hit-test cause remains unconfirmed. No OCR or physical stylus certification. |
| f13 | Native modes integration | `screens/native_durable_resume_screen_test.dart` | Native45 covers dictation, word scramble, sentence scramble and both Cloze kinds through restart/history. Actual provider/audio excluded. |
| f14 | Flashcard-first recommendation | `screens/recall_ladder_entry_flow_test.dart` | Observed26 and Native45 selected-word route; reads do not create answer/research facts. |
| f15 | Active-recall ladder | `widgets/recall_ladder_panel_test.dart` | Native45 actual seven-stage entries/availability and return. Cloze/dictation stage tests reach category entry; separate mode tests cover exercise resume. |
| f16 | Session configuration | `screens/lexical_quiz_setup_dialog_test.dart` | Observed26; configuration pinned before session start. |
| f17 | Immediate answer feedback | `screens/quiz_screen_test.dart` | Observed26; acknowledged answers remain the authority. |
| f18 | Contrastive distractor explanation | `features/learning/lexical_configured_quiz_test.dart` | Observed26; pedagogical efficacy is not certified. |
| f19 | Hint, strategy and context | `screens/definition_quiz_screen_test.dart` | Observed26; assistance remains recorded. |
| f20 | Bookmark/save | `screens/saved_words_screen_test.dart` | Observed26; Observed27 repaired nested return and retained saved word after restart. |
| f21 | Flag/report content | `screens/content_report_sheet_test.dart` | Observed26 local report/restart; server transport remains disabled. |
| f22 | Review center | `screens/review_center_entries_test.dart` | Observed27 Review/Saved/Back/Calendar route works. |
| f23 | Focus timer | `screens/focus_timer_screen_test.dart` | Observed27 Thai UI; timer is not recorded learning time. |
| f24 | Automatic learning-time capture | `screens/native_learning_time_test.dart` | Host baseline and Observed26 with locale issue; root Thai locale corrected27. Opt-in capture remains separate from waiting time. |
| f25 | Learning calendar/weekly analytics | `screens/learning_calendar_screen_test.dart` | Observed27 Thai UI and retained20 answers/18 correct/seven sessions. |
| f26 | Goal/test countdown | `screens/learning_profile_editor_screen_test.dart` | Observed26 invalid-duration rejection, valid goal/countdown and exit guards. |
| f27 | Opt-in study reminder | `features/study_reminders/reminder_settings_flow_test.dart` | OPEN. Permission1 passes in isolation, but Reminder27 follow-up reproduces first-permission request-unconfirmed. Retry ACK and actual notification delivery pass. Root cause/fix remains pending; reboot/OEM battery behavior is a separate boundary. |
| f28 | Learning assessment/progress comparison | `screens/pre_post_assessment_screen_test.dart` | Earlier synthetic Android pass; real authority, enrollment and research efficacy remain unapproved. |
| f29 | Evidence-based quest | `features/motivation/quest_screen_test.dart` | Observed26; canonical eligible facts only. |
| f30 | Gentle streak | `features/motivation/streak_learning_integration_test.dart` | Native45 canonical two-day Today UI and gap reset; controlled fixture clock, not elapsed real days. |
| f31 | Achievement/milestone | `screens/achievements_screen_test.dart` | Observed26/27 unlocked cards; owner/evidence guards remain. |
| f32 | Avatar level-up/cosmetic unlock | `screens/avatar_equipment_screen_test.dart` | Native45 earns80 coins from real canonical writes, buys/equips Ocean and reopens DB with matching provenance. No seeded credit or real money. |
| f33 | Contextual companion | `features/motivation/avatar_companion_flow_test.dart` | Observed26; temporary hide remains temporary. |
| f34 | Achievement share card | `features/motivation/achievement_native_share_test.dart` | Observed27 real chooser and return to Dashboard; no image sent or recipient delivery claimed. |
| f35 | Learning preference/goal quiz | `screens/learning_profile_editor_screen_test.dart` | Observed26; optional skip remains available. |
| f36 | Personal learning profile | `features/learning_profile/learning_profile_repository_test.dart` | Observed26; one owner-scoped profile authority. |
| f37 | Recommendation panel | `screens/choose_mode_screen_test.dart` | Observed26 plus Native45 route/owner guards; existing rules, no proficiency certification. |
| f38 | Accessibility | `screens/accessibility_smoke_test.dart` | Accessibility6 and existing screen checks; whole-app physical TalkBack/audio/stylus acceptance is not established. |
| f39 | Motion/theme controls | `screens/reduced_motion_consumers_test.dart` | Observed26; OS reduced motion and free-theme behavior checked. |
| f40 | Local-first operation | `screens/offline_vocabulary_journey_test.dart` | Observed27 WAL, quick_check, owner data and cold-restart durability; Native45 exercise/reward reopen. No cross-device service activation. |
| f41 | Feature flag/controlled rollout | `runtime/field_feature_registry_test.dart` | Observed26; unsupported services fail closed. No rollout authorized by this ledger. |
| f42 | Today hub | `screens/today_resume_panel_test.dart` | Observed26 plus Native45 actual streak display; retained bounded resume policy. |
| f43 | Learning history | `screens/learning_history_screen_test.dart` | Observed26 and Native4534 mode/resume cases preserve original session/owner. |
| f44 | Offline content manager | `screens/learning_pack_boundary_screen_test.dart` | Observed27 delete/restart retains learning data and does not restore removed cache. |

## Pending final checks and exclusions

Host5614, clean analysis and Scratchpad repeat are complete. Feature f27 remains
OPEN until the actual signed-app first-permission failure is diagnosed, fixed
and retested. Root is preparing diagnostic version28. Its results and subsequent
changes require their own verification; the isolated fixture cannot substitute
for this failing workflow. Attest the final signed artifact and record its source
identity before claiming the run is complete. Scratchpad repeats establish the
tested behavior, not the unobserved cause of its original intermittent failure.

The shared SRS overflow has a reproduced failure and corrected arithmetic with
focused checks. Other added tests close workflow gaps without adding another
learning, reward or research authority. Ordinary nonparticipant journeys must
leave research rows/events/outbox/uploads empty; the new canonical journeys
explicitly check zero research rows.

Cloud A/Billing, public deployment, real payment and real provider integration
remain outside scope. Real research enrollment/upload stays default-off until
its authority and explicit rollout conditions are met. Prior physical Vivo
confirmation covers only the documented speech/replay and TalkBack reveal flow;
this run does not broaden that physical-device evidence.
