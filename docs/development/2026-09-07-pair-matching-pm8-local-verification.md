# Pair Matching PM8 local verification

Status: PM0–PM8 local engineering verification complete. External device/UAT acceptance and G4P decisions remain pending. This record is not a signed G4P decision or production authorization.

Approved scope is PM0–PM8, design B — Playful Quest. Worktree is `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`, whole-branch base `ca123dddc1349acc4ed67bdd8f5476b02165307c`. Earlier phase evidence remains in the [Pair engineering record](2026-09-05-pair-matching-engineering-status.md).

## Source and artifact identity

Final implementation commit is `1875a61854490e0493cc084bffb705f5d3bd4b0b`, following PM8 source `94c1e97fea5097af144b63adfdf9ab2e5f277bee`. The generated plan records 104 canonical source entries and raw source fingerprint `50ddab9318080e5dd7cd4b640cfb63dbbf52fb9613d7d61fa8064a59132d22fc`. Its JSON SHA-256 is `c65044056712af21e22ff1f340d55bc5bf4c41470b1f9d0eb55d9d43b14ee7f5`. The earlier PM7 commit `631b518b` and PM8 intermediate affected runs are historical evidence, not the final release snapshot. Final documentation and the exact synthetic scanner policy correction are committed separately without changing these canonical source inputs. The scanner policy is independently hashed and verified below.

The verified internal debug APK is `com.lexiquest.app`, versionName `1.0.0`, versionCode `14`; the build uses `LEXIQUEST_VERSION=1.0.0+14` and `LEXIQUEST_BUILD_ID=pair-1875a61854490e0493cc084bffb705f5d3bd4b0b`. It contains 223,956,089 bytes with SHA-256 `4a7ac0ff4e7e5da0189962e7f91628e5654fe21f16585a0e8f20a6d9b06bd4e3`. The [archived APK](../../build/verification/1875a61854490e0493cc084bffb705f5d3bd4b0b/LexiQuest-Pair-PM8-1875a618-debug.apk) has the identical hash. `pm8-apk-identity.json` records the actual manifest, artifact and native-verifier evidence. A shared version string alone does not establish compatible source or artifact identity.

The database remains v24 with 48 tables. The product catalog remains revision 1.3.0, 8 domains / 44 product features, semantic hash `41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4`. These catalog counts are independent of the table count. EvidenceContext and EventEnvelopeV2 contracts remain frozen.

## Engineering behavior and compatibility

Pair remains f10 / `LessonMode.matching` / activity `matching` / route `learning/matching`. Standard and Adventure retain the same canonical engine, captured source, session, evidence and elapsed-time authority. Recognition does not authorize recall SRS; stars are descriptive. Practice Replay does not create a second learning, reward or research-primary authority. Ordinary session/answer/event and sync bookkeeping may grow during replay; global outbox zero is not asserted.

Owner rehome distinguishes immutable plan/command namespace P from authenticated runtime owner R. Existing accepted source pins, fingerprints, command IDs, pending evidence bytes and original actor identities are preserved; new captures use R. A historical actor is accepted only for its exact durable reservation and canonical inactive merged-into-R lineage. Upgrade checks run in the actual transaction before/after row movement, including bounded checkpoint inspection, destination-specific byte capacity, collision aliases and retained tombstones. Stale panes cannot bind a replacement owner during disposition recovery. Export and deletion use current canonical ownership and preserve unrelated owners.

| Version axis | Current behavior |
| --- | --- |
| Matching activity state | Legacy schemas1–5 retain their reader and default schema5 writer; strict Pair uses schema6 |
| Progressed Pair codec | Readers support1–4; codec4 retains measured full interactive elapsed; historical unmeasured values remain unavailable |
| Pinned start envelope | Unconfigured1 / configured2; accepted source/configuration pins stay immutable |
| Attempts sync payload | Default writer1 fails closed for declared Pair answers; explicit internal `SyncPayloadRollout.answerAttemptV2()` is required to upload payload2 |
| Database | v24 / 48 tables; no PM8 migration |

Release A is reader-first with default legacy registration/writer. A schema6 reader is present without enabling the new Pair entry point. An internal Release B writer requires explicit Pair capability and accepted configuration; research upload additionally requires its existing independent rollout/consent/permit authority. No production default is widened by the tests or debug build.

The compatibility matrix restores legacy 1–5 and progressed Pair 1–4, rejects malformed/unsupported states, and verifies an old reader rejects actual schema 6 without rewriting it. It exercises feature/Pair/parent-Quiz off, Adventure-only fallback, accepted pending and close recovery, and unrelated Quiz behavior. These are current source fixtures using the actual readers, not execution of historical APKs. Once schema 6 exists, retain the schema-6-capable source/build identified above as the minimum verified internal compatibility baseline; an older reader cannot be promised to resume newer state. Recovery still requires its valid owner/configuration/capability conditions. This does not enable the new writer or certify device rollout of the APK.

## Review and corrected defects

PM8 task review covered owner lineage, category/word collision preservation, exact reservations, strict legacy classification, bounded migration, tracked research-await reads, export/deletion and compatibility. Whole-branch review partitioned all 122 then-current source/test/image paths once across engine, boundary and UI reviewers, with named cross-boundary reads. Later correction reviews included the two previously unchanged Voice facade/test paths and the composition architecture guard. The final `lib`/`test` diff from the whole-branch base contains 125 paths: 110 Dart files and 15 PNGs.

The final correction addresses normal Pair close authorization inside the canonical database transaction, route return while an accepted write remains busy, and narration completion versus playback-start acknowledgement. Pair waits for actual playback completion or confirmed stop before releasing its narration pause. A failed stop retains the pause, blocks board commands and exposes a dedicated stop-and-continue retry. General `VoiceSession.speak` retains its start-acknowledgement contract.

Native TTS callbacks do not identify utterances. After an interrupted utterance, completion proof is conservatively unavailable for the rest of that adapter instance; the route-owned completion path confirms stop before returning unavailable/text fallback. This avoids treating a late callback as proof that a newer utterance ended. Physical native playback has not been validated in this worktree. The added failed-stop affordance has widget behavior coverage, without a separately inspected new screenshot.

The initial affected correction run passed1371 and failed1: unconditional strict-purpose decoding incorrectly rejected a permitted generic legacy checkpoint on close. The bounded classifier correction preserved valid generic legacy behavior, reserved strict Pair identities and rejected missing/downgraded authority. A subsequent overflow regression proved that a Pair marker beyond the query's65-row window could otherwise escape classification; the final guard rejects the overflow sentinel before interpreting any candidate. Independent correction review approved the resulting V3 source,142 focused tests passed and analysis was clean. The preceding V2 affected selection passed1376 with nine inherited Drift warnings; these overlapping counts are not added together.

The first complete default run at source `94c1e97fea5097af144b63adfdf9ab2e5f277bee`, fingerprint `7eb2c2bbcf3e09f4586e26a6db5fb534cb03881309a2b5aac523af5c22e20d1e`, passed4848 and failed2, with zero skips. It exposed new Pair adapter constructors that discarded the bootstrap-composed rollout/research providers, plus a screen guard that still inspected the pre-extraction Matching path. That source is a retained failed release checkpoint, not the final accepted artifact. The correction requires the caller-composed same-learning adapter and retains the single-composition-root assertion while explicitly checking wrapper delegation and the moved renderer.

The composition correction passed51 architecture/host checks. Its affected selection passed624 and failed8 measurement assertions that had expected all ordinary recognition rewards to be absent. The actual canonical policy permits protocol-controlled engagement rewards for eligible correct recognition while denying recall SRS. The final measurement oracle checks exact existing source/decision receipts and enforced pins, preserves prior SRS/point rows, permits only those canonical eligible point rows, and retains the whole Replay zero-delta and no-Motivation checks. No production eligibility or reward policy changed. All17 measurement checks then passed; analysis found no issues. The final12-file correction received independent Spec PASS / Quality PASS, with all reviewed raw hashes matching. These overlapping focused results are not added to the final full inventory.

The final correction packet is `pm8-composition-correction12-20260907T0434.manifest.json`, SHA-256 `a480d80738f5e443dfb35304c1da587399ac9cbf14ced6e306c6b5df339560d8`; its diff SHA-256 is `027c729e74003d5ff155a2eb024d8601e336caad55d1177609f22bc892a6c158`. Retained review reports include `pm8-composition-oracle-final-review.md`, `pm8-auth-classification-final-review.md`, `pm8-branch-ui-correction-review.md` and `pm8-close-limit-final-review.md` beneath the final evidence folder's `reviews/` directory.

## Verification and planned-case mapping

Local evidence is retained under `build/verification/1875a61854490e0493cc084bffb705f5d3bd4b0b/`. Each captured gate has separate stdout/stderr and metadata recording exact arguments, UTC times, native/gate exits, unchanged HEAD/plan and before/after raw hashes of all104 canonical source inputs. Flutter3.44.7 / Dart3.12.2 were used on Windows. Test, dependency and build commands were serialized; no source writer overlapped the final gates.

| Local gate | Current result | Evidence beneath the final source folder |
| --- | --- | --- |
| Generated feature map / final plan | PASS before release suites | `pm8-20260907T043835410Z-final-feature-map-check.*`; `pm8-20260907T043839261Z-final-test-plan-check.*` |
| Generator contracts | 18 passed | `pm8-20260907T043850150Z-generator-contracts.*` |
| Full default | 4,852 passed; 0 failed / skipped; reporter374.997s, gate380.783s | `pm8-20260907T043906946Z-full-default.*`; `pm8-full-default.summary.json` / `.inventory.json` |
| Full serial / actual inventory reconciliation | 4,852 passed; 0 failed / skipped; reporter1,439.444s, gate1,445.873s; identical named inventory | `pm8-20260907T044754902Z-full-serial.*`; `pm8-full-serial.summary.json` / `.inventory.json`; `pm8-pmt-inventory-reconciliation.json` |
| Three host integration journeys | Core, feature controls and media smoke: 1 passed each; gate52.479s /37.067s /40.952s | `pm8-20260907T051226194Z-host-core-journey.*`; `pm8-20260907T051318725Z-host-feature-controls.*`; `pm8-20260907T051355838Z-host-media-smoke.*` |
| Analyzer | No issues; analyzer7.4s, gate11.796s | `pm8-20260907T051436839Z-analyze.*` |
| Privacy-authority / catalog-navigation | 209 /68 passed; gate52.378s /23.739s | `pm8-20260907T051448679Z-privacy-authority.*`; `pm8-20260907T051541103Z-runtime-catalog-navigation.*` |
| Static policies | Firestore21 /OSV configuration38 passed | `pm8-20260907T051604889Z-firestore-static-policy.*`; `pm8-20260907T051607142Z-osv-config-policy.*` |
| Demo Auth / Firestore | 3 /123 passed; gate13.953s /26.096s; no skips; both emulators shut down | `pm8-20260907T051610902Z-demo-auth-policy.*`; `pm8-20260907T051624901Z-demo-firestore-policy.*` |
| Bounded Gitleaks | All 9 scopes passed under reviewed exact synthetic policy; original 3 findings classified below | `pm8-gitleaks-finding-disposition.json`; latest per-scope metadata in `pm8-local-release-evidence.json` |
| Six literal OSV locks | PASS under existing time-limited exceptions; gate16.491s | `pm8-20260907T052358909Z-osv-literal-locks.*` |
| Debug APK / native integrity / package metadata | Build PASS, gate167.976s; integrity PASS, gate8.535s; manifest matches `com.lexiquest.app` /`1.0.0` /`14` | `pm8-20260907T052415461Z-debug-apk-build.*`; `pm8-20260907T052703492Z-apk-native-integrity.*`; `pm8-apk-identity.json` |
| Final generated contracts / document inventory | PASS; 258 unique RTM rows, 188 planned cases including44 PMT, 50 UAT scripts; no missing references | Latest `final-feature-map-check` /`final-test-plan-check` metadata; `pm8-document-inventory.json` |

The full default command is `flutter test --no-pub --exclude-tags release-excluded --reporter json`; serial adds `--concurrency=1`. Both runs passed the same 4,852 named tests, verified by comparing the actual result multisets. Visible named `testDone` results are counted, excluding hidden loader/group events. Each output contains 86 inherited Drift multiple-database fixture print warnings and ten narrowly recognized non-JSON `Shell:` lines from generator-contract fixtures, including deliberate negative drift checks; their exact text is retained. Neither run has an unexpected parse line, error event, failure or skip. Warning output is not suppressed, and overlapping focused/host tests are not added to the full-suite total.

Exactly four existing `release-excluded` cases are Not Run:

- `test/architecture/notification_platform_contract_test.dart`: `iOS notification integration is CocoaPods-backed at iOS 13`.
- `test/features/device_model/litert_image_classifier_test.dart`: `opens the checksum-pinned model and runs real XNNPACK inference` and `verifier rejects a manifest with the wrong output contract`.
- `test/features/device_model/litert_benchmark_test.dart`: `runs bounded real CPU and XNNPACK benchmarks`.

Other unexecuted prerequisites remain explicit: the unchanged Supabase policy contract has no available Docker daemon; the three unchanged CPU backends have no local virtual environments. No optional backend/GPU environment was installed. The generated plan's Android device smoke is Not Run because no `LEXIQUEST_ANDROID_DEVICE_ID` is configured; host-fake journeys and an APK build do not satisfy that device gate. No device installation or physical acceptance is inferred from artifact inspection.

The generated plan contains 42 gates. Independent reconciliation in `pm8-generated-gate-coverage.json` finds 33 Flutter test gates covered by the full suite, including exact matches for all nine named migration/off/rollback filters. The other nine gates require separate direct evidence; the Android device smoke remains Not Run. Suite coverage is not described as executing every individual command separately, and these overlapping gate counts are not added together. `pm8-runtime-source-configuration.json` records source-defined runtime states, rules revisions and content revision authorities; actual test content/configuration pins are synthetic and specific to each named fixture.

The initial test-scope Gitleaks run returned exit1 for three fixed local lease identities in the Pair compatibility/measurement tests. They are not authentication credentials: the strings are supplied to `DriftOwnerOperationGate` and local claim operations in synthetic database fixtures. The final correction adds two file-and-exact-secret AND allowlists restricted to `generic-api-key`; it does not disable a detector or exclude either file. Existing policy entries remain unchanged.

Scanner controls retained an initial unsuitable suffix sentinel, then exposed that global path allowlists skipped an entire matching fixture file. The final rule restriction follows the [official Gitleaks configuration documentation](https://github.com/gitleaks/gitleaks#configuration). The unchanged seven-detection baseline versus final four-detection result proves that exactly the three approved values are suppressed; a one-character mutation in the same file and the original three values in another file remain detectable. `pm8-gitleaks-controls-v3.metadata.json` records the passing controls, expected scanner exit1, actual reports and policy/ignore hashes. Earlier failed control attempts and the original three-finding scan are retained, not relabeled as passes. These scanner-only edits do not change any of the 104 runtime/test source inputs verified by both full suites.

The independently reviewed scanner policy SHA-256 is `e7a3624f0c1f7cc8eb9e076103ae6f521d1778ba77e9d488997cd4e7fb2f22a0`; its exact copy and classification review are archived. Gitleaks8.30.1 scanned only `lib`, `test`, `docs`, `tool/final_test_plan`, `tool/feature_contract`, `pubspec.yaml`, `pubspec.lock`, `firestore.rules` and `AGENTS.md`, with redacted reports and the existing ignore policy. No repository-history or private/build-directory scan is claimed. Final documentation receives a fresh narrow `docs` scan after edits.

OSV2.4.0 evaluated `pubspec.lock`, `package-lock.json`, `backend/ai_api/uv.lock`, `backend/voice_api/uv.lock`, `backend/lexiquest_lm/uv.lock` and `backend/lexiquest_lm/deploy/hf_space/requirements.txt`. Its result retains one existing uuid advisory exception through2026-10-26 and eight optional Voice/Torch exceptions through2026-09-11. Those exceptions are not dependency fixes or permission to enable the uncertified GPU/remote-Voice path. No OSV exception was added or extended here.

The Android build retained warnings about Kotlin Gradle Plugin use by `firebase_app_check`, `flutter_tts`, `speech_to_text` and `workmanager_android`, the SDK XML3/4 tool mismatch, and deprecated/unchecked plugin APIs. The current build passed; future Flutter compatibility is not claimed. Native verification retained the pinned LiteRT2.1.5 AAR SHA-256 `a162d1ddbdad87c002b7ec7eb31a703f2761335e693f292f94091b3569d8aa37`, exact native/custom-op integrity policy and prohibited-accelerator checks without loosening them.

`pm8-local-release-evidence.json` binds the 30 required local gate results to their actual metadata/log hashes, source, schema/table inventory, runtime states, rules revisions and auxiliary evidence. It retains earlier nonzero attempts separately. This local engineering package leaves the explicitly unexecuted device, UAT and external authority gates open.

The following mapping was reconciled against both final named inventories: 14 groups, all 44 planned PMT cases exactly once, 49 unique existing test paths, and no missing or failed mapped result. Independent reconciliation identifies 749 named tests in those unique files, a subset of the 4,852 full tests. Paths without a prefix are beneath `test/features/learning/pair_matching/`.

| Planned cases | Local automated evidence sources | Evidence boundary |
| --- | --- | --- |
| TC-PMT-001 | `test/architecture/pair_matching_f10_boundary_test.dart`; `test/scenarios/production_feature_navigation_test.dart`; `test/screens/matching_mode_screen_test.dart` | Catalog/navigation and default-hidden behavior |
| TC-PMT-002–005 | `pair_matching_source_composer_test.dart`; `pair_matching_source_property_test.dart`; `test/features/today_hub/today_hub_reader_test.dart`; `test/features/adventure/presentation/today_experience_host_test.dart` | Captured synthetic sources and deterministic composition |
| TC-PMT-006–010,012 | `pair_matching_plan_test.dart`; `pair_matching_source_composer_test.dart`; `pair_matching_source_property_test.dart`; `pair_matching_density_preference_test.dart`; `pair_matching_configuration_test.dart`; `pair_matching_atomic_start_test.dart` | Pinned density/direction/locale/collisions and atomic admission |
| TC-PMT-011,013–016 | `pair_matching_engine_test.dart`; `pair_matching_idempotency_test.dart`; `pair_matching_evidence_contract_test.dart`; `pair_matching_owner_command_test.dart`; `pair_matching_owner_upgrade_test.dart` | Recognition identity, canonical commands and owner recovery |
| TC-PMT-017–023 | `pair_repair_policy_test.dart`; `pair_support_classification_test.dart`; `pair_review_deferral_test.dart`; `pair_matching_engine_test.dart`; `pair_star_policy_test.dart` | Repair chronology, guided confirmation, support and Review authority |
| TC-PMT-024 | `pair_matching_experience_host_test.dart`; `pair_board_view_test.dart`; `test/features/voice/voice_use_cases_test.dart`; `test/voice/native_tts_provider_test.dart`; `test/voice/voice_orchestrator_test.dart`; `test/voice/voice_policy_test.dart`; `test/voice/voice_service_factory_test.dart` | Completion/stop/fallback and local-only policy; physical audio Not Run |
| TC-PMT-025–031 | `pair_active_timer_test.dart`; `pair_timeout_recovery_test.dart`; `pair_timeout_race_test.dart`; `pair_matching_checkpoint_codec_test.dart`; `pair_matching_experience_host_test.dart` | Active clock, durable decisions, one extension and same-session new-round restart |
| TC-PMT-032–037 | `pair_star_policy_test.dart`; `pair_matching_result_view_test.dart`; `pair_matching_engine_test.dart`; `pair_matching_session_purpose_test.dart`; `pair_configured_disposition_test.dart` | Descriptive result axes, purpose and authenticated terminal disposition |
| TC-PMT-038–039 | `pair_practice_replay_test.dart`; `pair_measurement_boundary_test.dart`; `pair_matching_owner_upgrade_test.dart`; `test/features/history/learning_history_reader_test.dart`; `test/screens/learning_history_screen_test.dart`; `test/features/today_hub/today_hub_reader_test.dart` | Canonical projection isolation, Replay and History |
| TC-PMT-040 | `pair_matching_compatibility_rollout_test.dart`; `pair_matching_owner_upgrade_auth_test.dart`; `pair_matching_checkpoint_codec_test.dart`; `test/features/learning/matching_mode_adapter_test.dart` | Reader-first/default-old writer and explicit old-reader rejection |
| TC-PMT-041 | `pair_matching_checkpoint_codec_test.dart`; `pair_matching_engine_test.dart`; `pair_matching_idempotency_test.dart`; `pair_timeout_recovery_test.dart`; `pair_matching_owner_upgrade_auth_test.dart` | Revision, byte and terminal capacity, including destination owner |
| TC-PMT-042 | `test/features/adventure/adventure_pair_renderer_parity_test.dart`; `test/features/adventure/presentation/adventure_pair_experience_test.dart`; `pair_measurement_boundary_test.dart` | Same-host normalized parity and optional signed synthetic measurement |
| TC-PMT-043 | `pair_board_accessibility_test.dart`; `pair_board_view_test.dart`; `pair_board_golden_test.dart`; `pair_matching_host_golden_test.dart`; `test/features/adventure/presentation/adventure_pair_renderer_test.dart` | Widget keyboard/focus/semantics/text200 and15 golden comparisons; physical accessibility Not Run |
| TC-PMT-044 | `pair_matching_compatibility_rollout_test.dart`; `pair_configured_disposition_test.dart`; `pair_matching_owner_upgrade_test.dart`; `test/features/adventure/adventure_pair_renderer_parity_test.dart`; `test/runtime/production_feature_gate_test.dart`; `test/runtime/runtime_feature_controls_test.dart` | Off/fallback and accepted-operation recovery; no remote rollout |

The258 unique RTM rows,188 planned test cases (including44 PMT) and50 UAT scripts are planning inventories. A mapped automated fixture does not turn a mixed manual requirement into external acceptance. UAT-039–050 all remain Not Run. The Pair comprehension target11/12 has no measured numerator or denominator.

## External acceptance and rollout

| Required G4P role | Decision | Name / date | Required external evidence |
| --- | --- | --- | --- |
| Product | Unrecorded | Unrecorded | Learner UAT and product decision |
| Learning/Data | Unrecorded | Unrecorded | Recognition/Replay review and measured comprehension |
| UX/Accessibility | Unrecorded | Unrecorded | Physical accessibility, localization and interaction validation |
| QA | Unrecorded | Unrecorded | Applicable device/UAT acceptance of the verified build |
| Tech | Unrecorded | Unrecorded | Review of final compatibility, rollback and artifact evidence |

G4P remains pending external evidence; no signed Accept/Revise/Reject is invented. Physical TalkBack/Switch Access, native Voice, camera/model performance and learner UAT are Not Run. Real Research additionally requires approved protocol/instruments, trusted issuer and consent receipts, privacy/ethics provisioning and explicit rollout authority. Synthetic P256 tests are engineering evidence and do not establish research efficacy.

Research collection/upload stays default-off; unavailable authority fails closed for research while ordinary learning continues. No push, merge, deployment, real enrollment/upload, production enablement, signed field package or other-worktree change is part of this local verification.
