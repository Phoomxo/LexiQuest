# Current-source capability ledger

Baseline `d03d8eaf`; implementation is reviewed; artifact verification is in progress.
The frozen catalog remains `docs/design/feature-catalog-1.3.0.json` (8 domains,
44 capabilities). Each row is a behavior boundary, not a claim of exhaustive UAT.
Final run receipts belong in the adjacent task report. Test names below are
existing executable evidence targets; listing a test does not claim it ran today.

| ID | Implemented behavior and acceptance target | Primary checks | Limit or current work |
|---|---|---|---|
| f01 | Browse/filter catalog and explicitly install bundled starter | bundled_starter_pack_flow; learning_pack_catalog_screen | Fresh guest route and actual APK pending |
| f02 | Inspect pack content and provenance before install | learning_pack_actions_screen | Authored metadata is not external endorsement |
| f03 | Display current rich lexical entry and examples | rich_lexical_actual_callers | Reject stale owner/content |
| f04 | Validate pack/version/hash and keep source provenance | bundled_starter_pack; learning pack repository/codec | Editorial efficacy is not certified |
| f05 | Shared lesson progress, exit and reachable controls | lesson_scaffold | Native 320px/2x checks are bounded |
| f06 | Rate flashcards through canonical SRS lifecycle | srs_review_callers; srs_review_safety | Native voice has separate acceptance |
| f07 | Meaning recognition with pinned forward/reverse direction | configured_quiz_recovery_screen; accepted_quiz_plan; offline_trial_learning | Reverse selection and persistence pass on Android |
| f08 | Authored definition choice with durable accepted plan | definition_quiz_screen; bundled_starter_pack_flow | Requires suitable authored content |
| f09 | Choice and typed Cloze from installed examples | authored_native_starter; fill_in_the_blanks_screen | Authored lifecycle and stale-source rejection pass on Android |
| f10 | Matching, scoring, retry and History resume | matching_entry_history_flow | Recognition is not independent recall |
| f11 | Typed authored definition and typed Cloze | learning_pack_definition_flow; typed_cloze_scratchpad | Canonical answer is typed text |
| f12 | Optional ink, undo/clear, frozen comparison after answer ACK | typed_cloze_scratchpad; emulator_scratchpad_repeat | No handwriting recognition or physical stylus claim |
| f13 | Native modes use one answer/history lifecycle | native_durable_resume_screen; native_learning_time; authored_native_starter | Authored sentence lifecycle passes on Android; real provider unavailable |
| f14 | Flashcard-first suggestion opens the matching destination | recall_ladder_entry_flow | Recommendation does not assert measured efficacy |
| f15 | Recall ladder opens supported modes and explains unavailable routes | recall_ladder_entry_flow; recall_ladder_panel | Installed examples now supply offline Cloze preparation |
| f16 | Configure real count/direction/hints/time/input within accepted plan | lexical_quiz_setup_dialog; lexical_configured_quiz | New direction/hints; CEFR is selected pack metadata |
| f17 | Show feedback from acknowledged answer | quiz_screen; definition_quiz_screen | No optimistic score on failed write |
| f18 | Show authored contrastive distractor explanation | definition_quiz_screen | Available only when supplied by the authored entry |
| f19 | Hint/strategy/context and separately recorded reveal | definition_quiz_screen; accepted_quiz_plan | Disabled hint policy enforced in durable checkpoint |
| f20 | Save/remove owner-scoped vocabulary and practice saved words | saved_words_screen; saved_words_owner_boundary | No cross-owner list or callback reuse |
| f21 | Review/report selected source and retain local report | content_report_sheet; content_report_lifecycle | Offline APK queues locally; authored source uses packEntry |
| f22 | Review Center opens saved/due/weakness destinations | review_center_entries | Nested navigation retains legitimate route lease |
| f23 | Configure/pause/resume/finish Focus Timer | focus_timer_screen; focus_timer | Timer is separate from automatic learning time |
| f24 | Capture opted-in active learning interaction time | native_learning_time; learning_time_use_cases | Does not count arbitrary wall time or background duration |
| f25 | Calendar daily/weekly totals and separate skill accuracy | learning_calendar_screen; learning_calendar; mastery dashboard | No extra trend chart is required by accepted A1 scope |
| f26 | Store goal and civil target date/countdown | learning_profile_editor_screen | User-selected target, not prediction |
| f27 | Explicit reminder permission/save/ACK/reschedule/cancel | reminder_settings_flow; reminder_permission_flow; reminder_database_boundary | Native alarm proof, not every OEM battery policy |
| f28 | Score-free assessment and linked comparison under authority | pre_post_assessment_screen; study assessment/runtime tests | Synthetic authority only; real enrollment/upload default-off |
| f29 | Quest progress from canonical learning evidence | quest_screen; quest_learning_integration; app_bootstrap_motivation | APK31 exposed a missing adapter; correction passes immediate Quiz/SRS, replay and owner checks; APK32 proof pending |
| f30 | Gentle streak from dated canonical activity | earned_cosmetic_streak_flow; streak_learning_integration | Multi-day tests use synthetic clocks |
| f31 | Stored achievement and milestone evidence | achievements_screen; canonical motivation readers | Empty account has no fabricated badges |
| f32 | Earn coins, buy/equip cosmetic and restore after reopen | earned_cosmetic_streak_flow | Fixture earns via 80 canonical answers, not 80 UI taps |
| f33 | Contextual companion and visibility preference | avatar_companion_flow | No claim of conversational provider integration |
| f34 | Privacy-scoped achievement card and native share handoff | achievement_native_share; achievement_share_scope | Chooser return tested without sending to another person |
| f35 | Optional learning preferences/onboarding save or skip | learning_profile_editor_screen | No coerced Research enrollment |
| f36 | Owner-scoped persistent learning profile | learning_profile_repository; profile editor SQLite reopen | Owner ABA/retry covered separately |
| f37 | Recommendation from current evidence and honest empty state | choose_mode_screen; recall_ladder_entry_flow | No claimed research efficacy |
| f38 | Labelled controls, large text and reachable primary actions | lesson_scaffold; profile/pack/quest/quiz semantics/layout | Emulator coverage cannot certify whole-app physical TalkBack |
| f39 | Apply theme/reduced motion only after save ACK | appearance_settings_screen; reduced_motion_consumers | Verify actual APK persistence |
| f40 | Local learning and durable restart without network | offline_vocabulary_journey; native durable/reopen tests | Remote provider intentionally absent |
| f41 | Runtime flags and fail-closed Research/provider composition | field_feature_registry; app_bootstrap; app_bootstrap_motivation; research_transport_bootstrap | Hidden V2 placeholders are not ordinary route blockers |
| f42 | Today suggestions, activity and direct session resume | today_resume_panel; choose_mode_motivation | Stale rendered epochs cannot reopen sessions |
| f43 | Canonical history, summary and resumable drafts | learning_history_screen; native_learning_history | Completed historical summaries survive supported content removal |
| f44 | Inspect/pin/remove cached pack bytes without deleting learning | learning_pack_actions_screen; learning_pack_boundary_screen | Verify cache removal across APK restart |

Research rows/events/outbox/uploads must remain absent for ordinary
nonparticipant learning. Engineering checks of Research use explicitly synthetic
fixtures and do not confer consent, ethical approval, efficacy or rollout rights.
Cloud A/Billing, public deployment and real charging remain outside this task.
