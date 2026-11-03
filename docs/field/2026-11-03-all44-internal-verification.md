# Internal verification ledger for all 44 capabilities

Worktree `C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest`, branch
`codex/remaining-system-readiness`, starting commit `a56e80d2` plus this run's
changes. Catalog revision1.3.0 retains eight domains and exactly f01-f44.
Catalog rollout metadata remains unverified; this report does not change it.

Internal completion requires a reviewed implementation, passing required checks
on the current source, and an explicit evidence boundary for each capability.
This ledger covers 44 existing capabilities, not 44 exhaustive device UATs.
All44 capabilities are reviewed and internally accepted within the row-specific
boundaries below. Host5620 and clean analysis attest the corrected source;
Native45 covers the expanded synthetic Android workflows at320dp. Signed30
artifact checks, three actual first-grant/Home-return rounds, notification
delivery, return and final cancellation pass. Feature f27 is closed for this
bounded internal workflow. Earlier signed28 contention and signed29 form-race
failures remain recorded, not replaced by isolated-fixture claims. This is not
44 exhaustive physical-device UATs or authority to publish, charge or enroll
participants. Host5619, Host5614 and source998171bc's5,598 pass remain historical.

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
- **Native45** is `complete-extended-native-gate-final3.log`,45/45 PASS at320dp
  and density160, after the reminder serialization/route changes. It covers34
  durable-resume/history cases across five exercise kinds, nine recall-route
  cases and two canonical streak/reward journeys on synthetic Android data.
  Generated content and voice dependencies in these fixtures are synthetic.
  The earlier `complete-extended-native-final.log` also passes45/45 on its
  captured source and wider viewport. Neither run is45 independent features.
  The new320dp sequence preserves both failed runs: `complete-extended-native-gate-final.log`
  finishes43/45 with two sentence-draft scroll failures; replacing center drags
  with bounded gutter drags fixes those. `complete-extended-native-gate-final2.log`
  finishes43/45 after exposing two later retry-button misses when the error text
  wraps taller. Re-revealing Save before the second tap fixes those. Final3
  retains all draft ACK, serialization, revision and answer-count assertions.
- **Permission1** is `complete-reminder-permission-red.log`,1/1 PASS despite its
  provisional filename. Real Android permission grant, first Save ACK revision2,
  disable ACK revision3 and SQLite quick_check passed without a second Save.
  This isolated fixture does not close the signed-app failure described below.
- **Reminder gate32/2** means `complete-reminder-gate-host.log`,32/32 PASS, and
  `complete-reminder-gate-native.log`,2/2 PASS. The native cases cover contention
  serialization and current WAL revision/write durability. Expected stale-owner
  rejection in the boundary test is not a failed check. Counts overlap existing
  suites and are not additional distinct capabilities.
- **Permission final1** is `complete-reminder-permission-final2.log`,1/1 PASS
  with the actual Android Allow action after density reset to160 and a320dp
  viewport. The first `complete-reminder-permission-final.log` fails before
  permission handling with the emulator effectively107dp wide; it remains
  evidence of that invalid test setup. A minimum320dp fixture precondition now
  rejects that setup. This passing fixture still does not attest signed29.
- **Reminder27 follow-up** reproduces request-unconfirmed after permission grant
  in the signed app (`complete-316-delivery-state.xml`). Explicit retry obtains
  ACK (`complete-317-reminder-retry.xml`). A later updated alarm posts actual
  notification2701 at08:50 UTC with the generic reminder body, shown in
  `complete-delivery-notification.txt` and `complete-322-delivered.xml` while the
  app is on Home. Delivery after recovery does not establish first-Save success.
- **Diagnostic28** first obtains ACK in `complete-338-diagnostic28-settled.xml`,
  then repeats request-unconfirmed in `complete-347-repeat-failure.xml`.
  `complete-diagnostic28-native-repeat.txt` records `bindScope` at 16:14:20.343
  and `SQLiteDatabaseLockedException` at 16:14:22.557, followed by
  `UNAVAILABLE` and `platformUnavailable`. This establishes the native writer
  lock failure while Drift and the provider share the database.
  The coordinator records source `487f6faf` and diagnostic APK SHA-256
  `06F5FDED86FD7BC8A3E57D3E2255824E50CF9780934EEF5A3C0D77C8AFF7B75B`.
  `complete-diagnostic28-build.log` records successful packaging and model
  runtime integrity. This diagnostic package is not the final accepted artifact.
- **Reminder resume62** is `complete-reminder-resume-green.log`, 62/62 PASS after
  `complete-reminder-resume-red.log` reproduced two actual ChooseMode failures.
  A separate owner epoch preserves identity rejection across background changes.
  A fresh settings State and lease on resume replace lifecycle-invalidated state.
  These host tests cover the route repair; signed29 exposes a further form-state
  restoration defect below.
- **Host5619** is `complete-final-full-tests.log`,5,619/5,619 PASS in15:42.
  `complete-final-full-result.json` records `analysisExit: 0`, `testExit: 0`,
  1,031 inputs, `changedInputs: []` and completion at2026-11-03T10:09:51.1720570Z.
  The coordinator froze code/test inputs in `complete-final-source-before.json`
  before this clean analysis and regression. Host5619 replaces Host5614 as the
  host receipt for source later packaged as signed29. It does not attest edits
  made after the signed29 form-restoration finding.
- **Signed29** is offlineTrial29 from `b573113578dd6f5c49241d41cfd4a4836d7bcf5b`.
  Packaging/model-runtime/provenance checks pass, with independent artifact review.
  The manifest is `completion-package/lexiquest-1.0.0+29/release-manifest.json`;
  APK SHA256 is `81DB36A132C56FE22A8E53D3AA895557BA7DECF5B7970981F7A96EDCD3E200E2`.
  `complete29-apk-runtime.log` records APK release model integrity PASS.
  The initial invalid-viewport snapshot is excluded. Display correction to
  1080x1920 at density480 establishes360x640dp for the retained UI observations.
  Round1 artifacts008-012 show off/denied, actual permission, first-Save ACK,
  successful Home return and cancellation ACK. After cold restart013, artifacts
  015-017 show a second first-Save ACK after actual permission, without retry.
  However, `complete29-018-home-return2.xml` and019 settled show saved-enabled
  state with blank time/zone selectors. `complete29-020-reopened.xml` restores
  stored08:50/Africa/Abidjan after Back/reopen;021 cancels successfully.
  `complete29-round2-log.txt` contains no reminder errors. The observed form
  restoration failure remains open; these artifacts alone do not prove its cause.
  Actual notification delivery29 was not run. Signed29 is not accepted as the
  completed f27 workflow despite successful first grants and artifact identity.
- **Hydration74** is `complete30-reminder-green.log`,74/74 PASS after the
  deterministic failure in `complete30-hydration-red.log`. The test holds initial
  inspection while actual runtime foreground reconciliation emits a refresh;
  that newer read overtakes initial loading and previously left the form draft
  uninitialized. `_load` now initializes the draft on its first accepted view,
  after the current-read/owner guard, even when that read is a refresh. Later
  refreshes preserve unsaved edits. The test keeps an unsaved OFF draft while
  stored state stays ON at revision1. Independent gpt-6-astra review accepts
  the correction. This focused host pass does not attest signed30 UI.
- **Host5620** is `complete30-full-tests.log`,5,620/5,620 PASS in14:55 after the
  form-race correction. `complete30-analysis.log` reports no issues.
  `complete30-full-result.json` records exits0/0,1,031 inputs, `changedInputs: []`
  and completion2026-11-03T10:44:53.8944723Z. This is the current source receipt
  from `verify-source30.ps1`. Signed artifact and UI evidence are recorded below.
- **Signed30** is offlineTrial30 from `dd436704f54748c095bfbe9f261202205c11adfe`,
  tree `6661ecd703170178d30eb172900b8f6ff5b3548b`. Packaging/runtime/signature/
  provenance checks pass with independent artifact review. Manifest:
  `completion-package/lexiquest-1.0.0+30/release-manifest.json`.
  APK SHA256: `76CF19560D2F2CE82FB1B3CC5155855CF51922AB26A06E5DBCCA4251B6BBFDED`.
  AAB SHA256: `4D488C80DF82581B30B3CBCD30B9FA18B6F7A7D453A73D31F4F10012B2C8ECB5`.
  `complete30-apk-runtime.log` records release model integrity PASS. Artifact
  review identifies only the generated Android plugin registrant changing among
  1031 captured inputs: test hash
  `FF1F2C90343AFC99684625883ADF67DD3327F0A7F91F518C35FB16EE98A444E1`,
  release hash `780B14A81692848DC5ADC98D8B9694665A5641049555715781CEC6C82F0621AD`.
  Preserve that regeneration delta rather than claiming identical packaged/test
  input hashes.
- **Signed30 reminder UI** has three actual first-grant ACK/Home-return rounds:
  `complete30-012` baseline,013 permission,015 settled ACK,017 Home,018 off;
  020 baseline,021 permission,022 ACK,023 Home,024 off;
  026 baseline,027 permission,028 ACK,029 Home. The XML files retain descriptive
  suffixes. Each Home return keeps switchON and08:50/Africa/Abidjan in the form.
  Exploratory003-008 pressed Home while Save was running and are excluded from
  these three ACK rounds; settled007 restored the form and008 reset it off.
  Round3 is enabled for delivery. `complete30-035-delivery-ack.xml` and the full
  `complete30-alarm-before-delivery.txt` establish accepted11:04 UTC scheduling,
  18:04 device-local time, with the app on Home at036. Actual delivery was pending
  at that point; the following receipt closes it. A scheduled alarm alone is not
  notification receipt.
- **Signed30 delivery/containment** closes the pending observation.
  `complete30-delivery-notification2.txt` contains active app notification2701
  with the generic reminder body, and `complete30-037-delivered-shade.xml` shows
  the actual notification. Timestamp1793703918275 is11:05:18.275 UTC,78.275 seconds
  after requested11:04 UTC. The recorded Android alarm window is77.752 seconds;
  this supports inexact delivery, not an exact-time or OEM battery guarantee.
  Return038 preserves11:04/Africa/Abidjan; off039 obtains cancellation ACK.
  Full post-off alarm/notification dumps show zero active app alarms and zero
  active notification records before final containment. The three completed
  grant/Home rounds are asserted PASS in `complete30-ui-rounds-result.json`.
  Calendar041 retains20 answers,18 correct, seven sessions and15 interaction
  seconds. `complete30-database.json` has quick_check=ok, no FK violations,
  WAL/schema25,20 answers, reminder off/minute664/zoneAfrica/Abidjan/revision25,
  and cache still absent. Final package state confirms version30 and denied
  notification permission. Root verified shell UID2000 after unroot and stopped
  only All44 at11:07:55 UTC. Physical Vivo and the original AVD were untouched.
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
| f07 | Meaning quiz | `screens/configured_quiz_recovery_screen_test.dart` | Observed26; shared SRS overflow correction is covered by current Host5620. |
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
| f27 | Opt-in study reminder | `features/study_reminders/reminder_settings_flow_test.dart` | INTERNALLY ACCEPTED. Native gate32/2, Permission final1, resume62, Hydration74 and Host5620 support the fixes. Signed30 passes three first-grant/Home rounds, actual notification, return and final cancellation with retained data. Reboot/OEM battery behavior remains outside this bounded acceptance. |
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
| f43 | Learning history | `screens/learning_history_screen_test.dart` | Observed26 and the34 mode/resume cases within Native45 preserve original session/owner. |
| f44 | Offline content manager | `screens/learning_pack_boundary_screen_test.dart` | Observed27 delete/restart retains learning data and does not restore removed cache. |

## Final disposition and exclusions

`complete30-attestation.json` consolidates the measured artifact/source identity,
host, UI, delivery and database/containment receipts. Independent final review
accepts this bounded disposition with no must-fix. Only documentation changed
after release source `dd436704f54748c095bfbe9f261202205c11adfe`.

Host5620 and its clean analysis attest the corrected source before signed30; Scratchpad
repeat remains complete for its captured inputs. Diagnostic28 identifies native
writer contention in the first-grant path.
The adapter repair requires `ownerWrites`, rejects an ambient transaction and
holds `database.exclusively` around native IPC. It does not extend timeouts or add
retries. Reminder gate32/2 and Permission final1 now pass; Native45 also passes
on the corrected320dp emulator setup. Review accepted the serialization repair.
Signed29's second Home return exposed blank time/zone despite saved-enabled
status. Hydration74 confirms a refresh overtaking initial form initialization
and verifies the correction without overwriting subsequent unsaved edits.
Source30 full verification passes5620 cases. Signed30 passes three actual
first-grant/Home-return rounds, actual notification delivery, notification return
and final cancellation. Feature f27 is internally accepted within these checks;
the original failed artifacts remain evidence of the corrected problems.

The captured full host run and signed30 packaging/provenance/workflow pass.
All44 entries are internally accepted with their stated evidence limits. This
does not mean44 exhaustive device UATs. Signed29 remains an unaccepted historical
workflow and delivery29 was not run. Scratchpad repeats establish tested behavior,
not the unobserved cause of its original intermittent failure. JavaScript boundary
arithmetic verification is not browser UI acceptance. OEM/reboot reminder
behavior and whole-app physical accessibility remain outside the checked scope.

The shared SRS overflow has a reproduced failure and corrected arithmetic with
focused checks and Host5620 coverage. Other added tests close workflow gaps
without adding another learning, reward or research authority. Ordinary nonparticipant journeys must
leave research rows/events/outbox/uploads empty; the new canonical journeys
explicitly check zero research rows.

Cloud A/Billing, public deployment, real payment and real provider integration
remain outside scope. Real research enrollment/upload stays default-off until
its authority and explicit rollout conditions are met. Prior physical Vivo
confirmation covers only the documented speech/replay and TalkBack reveal flow;
this run does not broaden that physical-device evidence.
