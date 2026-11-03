# Acceptance ledger for the 44 catalog capabilities

Scope requested after the version23 critique follow-up: complete and verify the
existing44 capabilities, without duplicating their authorities or adding an
unapproved feature. Source under test: `1e6e896081f9e5f63342f227ec11c936811be3a9`.
The frozen catalog remains revision1.3.0 with eight domains and44 IDs. Its rollout
metadata is intentionally unverified and must not be rewritten as release proof.

Each row below identifies an existing executable acceptance entry. Test presence
alone is not a pass. The full current-source regression receipt supplies execution
status after it finishes. The earlier Wave26 Connected classification means local
implementation, not live-provider, physical accessibility or Research approval.

Test paths are relative to the repository. Retain the detailed source/caller
assessment in the three2026-11-02 critique reports and the runtime readiness
matrix. The five later confirmed presentation findings are implemented in the
[critique follow-up](2026-11-03-critique-follow-up.md).

| ID | Capability | Representative executable acceptance | Additional boundary |
|---|---|---|---|
| f01 | Learning pack catalog | test/screens/learning_pack_catalog_screen_test.dart | Bundled content exists; publisher/editorial review separate |
| f02 | Pack detail | test/screens/learning_pack_actions_screen_test.dart | Original version/provenance retained |
| f03 | Rich lexical card | test/screens/rich_lexical_actual_callers_test.dart | No invented lexical facts |
| f04 | Content quality/version | test/features/learning_packs/rich_lexical_codec_test.dart | Human moderation and live delivery separate |
| f05 | Common lesson shell | test/widgets/lesson_scaffold_test.dart | Real device configurations require bounded checks |
| f06 | Flashcards | test/screens/srs_review_callers_test.dart | Native audio acceptance separate |
| f07 | Meaning quiz | test/screens/configured_quiz_recovery_screen_test.dart | Original answer and finish identity |
| f08 | Definition quiz | test/screens/definition_quiz_screen_test.dart | Valid authored content required |
| f09 | Cloze | test/screens/fill_in_the_blanks_screen_test.dart | Live generation not certified |
| f10 | Matching | test/screens/matching_entry_history_flow_test.dart | Recognition does not grant recall mastery |
| f11 | Typed recall | test/screens/learning_pack_definition_flow_test.dart | Draft is not accepted evidence |
| f12 | Handwriting | test/screens/typed_cloze_scratchpad_test.dart | Ephemeral scratchpad, no OCR; physical stylus separate |
| f13 | Native mode integration | test/screens/native_durable_resume_screen_test.dart | Dictation/audio/provider device checks separate |
| f14 | Flashcard-first recommendation | test/screens/recall_ladder_entry_flow_test.dart | Uses existing owned word |
| f15 | Recall ladder | test/widgets/recall_ladder_panel_test.dart | Recommendation, not a proficiency claim |
| f16 | Session configuration | test/screens/lexical_quiz_setup_dialog_test.dart | Settings pinned before start |
| f17 | Immediate feedback | test/screens/quiz_screen_test.dart | Only after acknowledged answer |
| f18 | Distractor explanation | test/features/learning/lexical_configured_quiz_test.dart | Does not certify pedagogical effectiveness |
| f19 | Hints and context | test/screens/definition_quiz_screen_test.dart | Assistance remains recorded |
| f20 | Saved words | test/screens/saved_words_screen_test.dart | Owner-bound save/export/deletion |
| f21 | Content reports | test/screens/content_report_sheet_test.dart | Offline queue works; server transport remains disabled |
| f22 | Review center | test/screens/review_center_entries_test.dart | Existing learning authority |
| f23 | Focus timer | test/screens/focus_timer_screen_test.dart | Transient timer is not learning evidence |
| f24 | Learning-time capture | test/screens/native_learning_time_test.dart | Opt-in capture, no invented waiting time |
| f25 | Calendar/analytics | test/screens/learning_calendar_screen_test.dart | Selected-date anchor already corrected |
| f26 | Goal/countdown | test/screens/learning_profile_editor_screen_test.dart | Dirty/pending exit guard already implemented |
| f27 | Reminder | test/features/study_reminders/reminder_settings_flow_test.dart | Enabled delivery/reboot/battery acceptance remains |
| f28 | Assessment/comparison | test/screens/pre_post_assessment_screen_test.dart | Real Research authority and efficacy not established |
| f29 | Evidence-based quest | test/features/motivation/quest_screen_test.dart | Only eligible canonical facts |
| f30 | Gentle streak | test/features/motivation/streak_learning_integration_test.dart | Protection is not a learned day |
| f31 | Achievements | test/screens/achievements_screen_test.dart | Only real unlock evidence |
| f32 | Avatar/cosmetics | test/screens/avatar_equipment_screen_test.dart | Existing virtual reward authority, no real charge |
| f33 | Companion | test/features/motivation/avatar_companion_flow_test.dart | Temporary hide remains temporary |
| f34 | Achievement share | test/features/motivation/achievement_native_share_test.dart | No recipient delivery claimed or sent |
| f35 | Preference/goal quiz | test/screens/learning_profile_editor_screen_test.dart | Optional participation |
| f36 | Personal profile | test/features/learning_profile/learning_profile_repository_test.dart | One owner-scoped profile authority |
| f37 | Recommendation panel | test/screens/choose_mode_screen_test.dart | Transparent existing rules |
| f38 | Accessibility | test/screens/accessibility_smoke_test.dart | Full physical TalkBack/audio/stylus UAT remains |
| f39 | Motion/theme | test/screens/reduced_motion_consumers_test.dart | Respect OS reduced motion |
| f40 | Local-first | test/screens/offline_vocabulary_journey_test.dart | Cross-device services not activated |
| f41 | Controlled rollout | test/runtime/field_feature_registry_test.dart | Unsupported services fail closed |
| f42 | Today hub | test/screens/today_resume_panel_test.dart | Resume count bounded to latest50 records |
| f43 | History | test/screens/learning_history_screen_test.dart | Original owner/session retained |
| f44 | Offline content manager | test/screens/learning_pack_boundary_screen_test.dart | Removing cache must preserve learning data |

## Current execution

Full regression on `1e6e8960` passes5581 tests, with zero failures and all1350
input hashes unchanged before/after. The receipt is `full-flutter-result.json`
under `D:\LexiQuest-Storage\maintenance\2026-11-03\critique35`. Every representative
test above is present in those frozen inputs; parallel expanded output does not
name every executed file, so this is whole-suite evidence, not44 separate UATs.
`all44-coverage.json` records that distinction. The312 focused/affected cases and
clean analysis also pass.

Physical version24 inspection then confirmed two filled actions in the hub.
The final correction only changes the generic recommendation to an outlined
button when the existing recall entry is composed. Existing callbacks and the
fallback primary button remain intact. A new assertion reproduces two visible
filled buttons before the fix; the updated six-file hub regression passes60.
This two-Dart-file delta is separately verified, not relabelled as a fresh full
run. Final package/install evidence is recorded after those operations finish.

Signed offlineTrial24 build passed APK/AAB identity and native/model integrity
checks. Device update is reconciled separately before physical acceptance.
The independent artifact worker stopped because its model quota was exhausted;
no independent artifact verdict is claimed for this run. Root verifies retained
artifact identity and device installation directly.

Real payments, Cloud A/Billing, public publication and real Research enrollment
remain excluded. Missing external authority or deferred human listening cannot
be replaced with generated approvals or simulated success.
