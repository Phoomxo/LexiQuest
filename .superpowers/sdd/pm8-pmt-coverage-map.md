# PM8 planned-case to local evidence map

Prepared from the unchanged44 TC-PMT rows and12 UAT-039–050 scripts. This is a mapping inventory, not execution or learner acceptance. Final root evidence must attach the actual frozen-source full-suite named inventory before labelling automated coverage verified. Physical device, learner comprehension and signatures stay NotRun/pending. Test paths below are relative to test/features/learning/pair_matching/ unless prefixed otherwise.

| Planned cases | Local automated evidence sources | Limit of evidence |
|---|---|---|
| TC-PMT-001 | test/architecture/pair_matching_f10_boundary_test.dart; test/scenarios/production_feature_navigation_test.dart; test/screens/matching_mode_screen_test.dart | Catalog/navigation contracts and hidden/default baseline; no deployed fleet |
| TC-PMT-002–005 | pair_matching_source_composer_test.dart; pair_matching_source_property_test.dart; test/features/today_hub/today_hub_reader_test.dart; test/features/adventure/presentation/today_experience_host_test.dart | Canonical synthetic Today/Review/Learn sources and deterministic composition |
| TC-PMT-006–010,012 | pair_matching_plan_test.dart; pair_matching_source_composer_test.dart; pair_matching_source_property_test.dart; pair_matching_density_preference_test.dart; pair_matching_configuration_test.dart; pair_matching_atomic_start_test.dart | Exact density/direction/locale/collision/pinned setup and atomic admission; no learner comprehension measured |
| TC-PMT-011,013–016 | pair_matching_engine_test.dart; pair_matching_idempotency_test.dart; pair_matching_evidence_contract_test.dart; pair_matching_owner_command_test.dart; pair_matching_owner_upgrade_test.dart | Prompt-side recognition identity, pure commands and durable idempotency/owner recovery |
| TC-PMT-017–023 | pair_repair_policy_test.dart; pair_support_classification_test.dart; pair_review_deferral_test.dart; pair_matching_engine_test.dart; pair_star_policy_test.dart | Spacing/order/guided tail/neutral versus semantic support and Review authority |
| TC-PMT-024 | pair_matching_experience_host_test.dart; pair_board_view_test.dart; test/features/voice/voice_use_cases_test.dart; test/voice/native_tts_provider_test.dart; test/voice/voice_orchestrator_test.dart; test/voice/voice_policy_test.dart; test/voice/voice_service_factory_test.dart | Native/fake voice lifecycle, real completion versus start acknowledgement, confirmed-stop recovery, private text fallback and policy; physical audio/provider/model performance NotRun |
| TC-PMT-025–031 | pair_active_timer_test.dart; pair_timeout_recovery_test.dart; pair_timeout_race_test.dart; pair_matching_checkpoint_codec_test.dart; pair_matching_experience_host_test.dart | Injected active clock, durable decisions/one extension/same-session new-round restart and serialized race recovery |
| TC-PMT-032–037 | pair_star_policy_test.dart; pair_matching_result_view_test.dart; pair_matching_engine_test.dart; pair_matching_session_purpose_test.dart; pair_configured_disposition_test.dart | Independent descriptive stars, incomplete/replay purpose and committed evidence; no mastery or efficacy claim |
| TC-PMT-038–039 | pair_practice_replay_test.dart; pair_measurement_boundary_test.dart; pair_matching_owner_upgrade_test.dart; test/features/history/learning_history_reader_test.dart; test/screens/learning_history_screen_test.dart; test/features/today_hub/today_hub_reader_test.dart | Before/after canonical projection isolation and normal/replay history; ordinary outbox is not globally zero |
| TC-PMT-040 | pair_matching_compatibility_rollout_test.dart; pair_matching_owner_upgrade_auth_test.dart; pair_matching_checkpoint_codec_test.dart; test/features/learning/matching_mode_adapter_test.dart | Supported legacy shapes/new reader/default writer/old-reader rejection; not execution of historical binaries |
| TC-PMT-041 | pair_matching_checkpoint_codec_test.dart; pair_matching_engine_test.dart; pair_matching_idempotency_test.dart; pair_timeout_recovery_test.dart; pair_matching_owner_upgrade_auth_test.dart | Revision/byte/terminal capacity including actual destination owner and preserved old pending actor |
| TC-PMT-042 | test/features/adventure/adventure_pair_renderer_parity_test.dart; test/features/adventure/presentation/adventure_pair_experience_test.dart; pair_measurement_boundary_test.dart | Normalized synthetic same-host Standard/Adventure semantics and optional signed synthetic measurement |
| TC-PMT-043 | pair_board_accessibility_test.dart; pair_board_view_test.dart; pair_board_golden_test.dart; pair_matching_host_golden_test.dart; test/features/adventure/presentation/adventure_pair_renderer_test.dart | Widget keyboard/focus/semantics/text200/goldens/no-audio controls; physical TalkBack/Switch/gesture/device validation remains NotRun |
| TC-PMT-044 | pair_matching_compatibility_rollout_test.dart; pair_configured_disposition_test.dart; pair_matching_owner_upgrade_test.dart; test/features/adventure/adventure_pair_renderer_parity_test.dart; test/runtime/production_feature_gate_test.dart; test/runtime/runtime_feature_controls_test.dart | Synthetic feature/Pair/Quiz/Adventure-off and accepted-operation recovery; no real remote rollout or production activation |

| External UAT script | Related local fixture coverage | Human/device status |
|---|---|---|
| UAT-039 entry/source | TC-PMT-001–005 | NotRun |
| UAT-040 density/guardian | TC-PMT-006–008 and configured host cap fixtures | NotRun |
| UAT-041 EN–TH identity | TC-PMT-009–012 | NotRun |
| UAT-042 repair/tail | TC-PMT-013–021 | NotRun |
| UAT-043 pronunciation/hint | TC-PMT-022–024 | NotRun |
| UAT-044 active timer | TC-PMT-025–027 | NotRun |
| UAT-045 timeout choices | TC-PMT-027–031 | NotRun |
| UAT-046 extension/restart | TC-PMT-029–031,041 | NotRun |
| UAT-047 stars/elapsed | TC-PMT-032–037 | NotRun |
| UAT-048 Practice Replay | TC-PMT-038–039 | NotRun |
| UAT-049 accessibility/localization | TC-PMT-043 | NotRun |
| UAT-050 parity/fallback | TC-PMT-040,042,044 | NotRun |

All258 unique RTM rows,188 planned TC rows (44PMT included) and50 UAT scripts remain planning inventories; mapping a row to an automated fixture does not mark the entire mixed manual requirement accepted. G4P Product, Learning/Data, UX/Accessibility, QA and Tech decisions/names/dates are unrecorded. The comprehension target11/12 has no measured numerator/denominator.
