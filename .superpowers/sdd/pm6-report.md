# PM6 implementation handoff

Date: 2026-09-06. Worktree: C:/Users/Phet/.codex/worktrees/02fa/LexiQuest. Branch: codex/pair-matching-pm0-pm8.
Baseline: PM5 source b79515a8c112de498be24a9f632417924797a6fe / documentation HEAD 7919cb860bc37d6d2d2811e4f6633340eca94010.
Status: implementation submitted for fresh independent PM6 review; this report does not self-approve PM6 or PM7/PM8.

## Delivered behavior

- Internal Pair host covers real configured setup, both directions, shared typed board, wrong/repair/guided learner confirmation, timeout choices, canonical result, Review handoff, fresh Practice Replay and actual History entry point. Default legacy matching/registry and production navigation remain unchanged/off.
- Actual SessionConfiguration policy precedes measured admission and each fresh configured controller. Failed canonical attachment exposes retained exact-session retry, never an interactive unattached board.
- Route lifecycle reserves the actual coordinator, fences new actions, drains accepted work with a narrow continuation lease, awaits background flush and retains exact pending/terminal work through parent ProductionFeatureGate disposal and recovery-only reopen.
- Real configured effort maximum is independent of the optional challenge timer. At cap, completed accepted work takes normal three-receipt completion; incomplete work is canonically abandoned with its first cutoff timestamp retained across before/after-write uncertainty. Reopened abandoned data gets a truthful generic stopped/incomplete surface.
- Full interactive elapsed uses the same PairActiveClock and pause leases. Codec4 progressed checkpoints carry nullable coverage; codec1–3/missing coverage remains unavailable. New measured atomic admission inserts immutable revision1 and virgin zero revision2 only for genuinely new canonical insertion. Existing historical starts are never retrofitted. Null coverage is sticky; clock/capacity loss still allows legal answers and completion.
- Pure board retains typed IDs/orderFor, separate learner-confirmed guided support revision, focus/keyboard/semantics and bounded responsive layout. Legacy screen body is mechanically extracted; existing constructor, loader typedef and accessibility feedback forwarding survive.
- Voice uses route-owned VoiceUseCases/RouteVoiceSessionMixin, user initiation, opaque metadata, localOnly policy and positively verified installed non-network native voice. Unavailable audio leaves visible text fallback. Default other Voice requests keep existing routing.
- History reads only displayed canonical sessions, separately projects normal/replay best/latest within that loaded page, and uses a typed Pair replay callback. Generic replay remains separate. Immutable plan owner namespace is not mistaken for current canonical row authentication.

## Exact source and test write set

43 Dart files; no generated Dart, database migration, dependency manifest or controller source change was required:

- lib/features/history/application/learning_history_use_cases.dart
- lib/features/learning/application/lesson_mode_registry.dart
- lib/features/learning/application/matching_mode_adapter.dart
- lib/features/learning/data/drift_learning_repository.dart
- lib/features/learning/domain/learning_repository.dart
- lib/features/learning/pair_matching/application/pair_matching_atomic_start.dart
- lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart
- lib/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart
- lib/features/learning/pair_matching/domain/pair_active_clock.dart
- lib/features/learning/pair_matching/domain/pair_matching_checkpoint_budget.dart
- lib/features/learning/pair_matching/domain/pair_matching_engine.dart
- lib/features/learning/pair_matching/domain/pair_matching_session_purpose.dart
- lib/features/learning/pair_matching/presentation/pair_board_view.dart
- lib/features/learning/pair_matching/presentation/pair_matching_copy.dart
- lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart
- lib/features/learning/pair_matching/presentation/pair_matching_result_view.dart
- lib/features/learning/presentation/legacy_matching_mode_screen.dart
- lib/features/learning/presentation/unified_lesson_shell.dart
- lib/screens/learning_history_screen.dart
- lib/screens/matching_mode_screen.dart
- lib/voice/native_tts_provider.dart
- lib/voice/voice_models.dart
- lib/voice/voice_orchestrator.dart
- lib/voice/voice_policy.dart
- test/features/learning/pair_matching/pair_active_timer_test.dart
- test/features/learning/pair_matching/pair_board_accessibility_test.dart
- test/features/learning/pair_matching/pair_board_golden_test.dart
- test/features/learning/pair_matching/pair_board_view_test.dart
- test/features/learning/pair_matching/pair_matching_atomic_start_test.dart
- test/features/learning/pair_matching/pair_matching_checkpoint_codec_test.dart
- test/features/learning/pair_matching/pair_matching_configuration_test.dart
- test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart
- test/features/learning/pair_matching/pair_matching_experience_host_test.dart
- test/features/learning/pair_matching/pair_matching_host_golden_test.dart
- test/features/learning/pair_matching/pair_matching_result_view_test.dart
- test/features/learning/pair_matching/pair_timeout_race_test.dart
- test/features/learning/pair_matching/pair_timeout_recovery_test.dart
- test/screens/learning_history_screen_test.dart
- test/voice/native_tts_provider_test.dart
- test/voice/voice_models_test.dart
- test/voice/voice_orchestrator_test.dart
- test/voice/voice_policy_test.dart
- test/voice/voice_service_factory_test.dart

New golden baselines, all under test/features/learning/pair_matching/goldens/pair_board/:

- thai_regular_standard6.png
- thai_regular_compact4.png
- english_reverse_selected.png
- thai_long_narrow_text_200.png
- thai_long_narrow_text_200_scrolled.png
- thai_wide_bounded.png
- thai_dark_high_contrast_wrong_repair.png
- thai_guided_reduced_motion_no_audio.png
- host_setup_thai_guardian.png
- host_timeout_thai.png
- host_result_thai_measured.png
- host_replay_result_english.png

Seven pre-existing native registrant line-ending status entries (linux 3, macOS 1, windows 3) were preserved, not included as PM6 implementation. Index remains empty; no stage/commit/push/merge performed.

## Final current-source verification

All Flutter/Dart processes were serialized. No source changed after the following final checks.

1. `flutter test --no-pub --update-goldens test/features/learning/pair_matching/pair_board_golden_test.dart test/features/learning/pair_matching/pair_matching_host_golden_test.dart --reporter expanded`
   - GREEN 10 tests, 12 PNG; .superpowers/sdd/pm6-final-golden-generate.log.
2. `flutter test --no-pub test/features/learning/pair_matching test/features/learning/matching_mode_adapter_test.dart test/screens/matching_mode_screen_test.dart test/features/learning/unified_lesson_controller_test.dart test/features/learning/session_configuration_store_test.dart test/features/learning/session_configuration_sheet_test.dart test/features/learning/session_configuration_policy_test.dart test/screens/learning_history_screen_test.dart test/features/history/learning_history_replay_test.dart test/features/history/learning_history_reader_test.dart test/runtime/production_feature_gate_test.dart --reporter expanded`
   - GREEN 494 tests, including actual host, all Pair tests, separate accessibility tests and golden comparison without update; .superpowers/sdd/pm6-final-pair-regression.log.
3. `flutter test --no-pub test/voice/voice_models_test.dart test/voice/voice_policy_test.dart test/voice/voice_orchestrator_test.dart test/voice/native_tts_provider_test.dart test/voice/voice_service_factory_test.dart --reporter expanded`
   - GREEN 163 tests; .superpowers/sdd/pm6-final-voice-regression.log.
4. `flutter analyze --no-pub`
   - No issues found; .superpowers/sdd/pm6-final-analyze.log.
5. `git diff --check`
   - Exit 0, only known LF/CRLF conversion notices. Branch/index/task-owned process checks found correct branch, empty index and no task-owned Flutter/Dart process.

Formatting: exact target manifest .superpowers/sdd/pm6-formatted-files.txt; pm6-format.log and pm6-format2.log. Initial analyzer found 39 local style/unused diagnostics; scoped fixes recorded in pm6-analyze-fix2.log. The first dart-fix invocation incorrectly supplied multiple files and exited64 before edits; corrected to a serialized per-file loop. No warnings were suppressed.
The focused result semantics test initially failed because its test SemanticsHandle used late teardown; explicit disposal fixed the harness, and pm6-final-result-green.log is GREEN1. All assertions remain in final GREEN494.

## Real-host and canonical fault matrix

| Boundary | Evidence |
| --- | --- |
| Real policy, both directions, failed attach and exact retry | Full actual-host test; pm6-host-attachment-green2.log, final494 |
| Parent gate dispose while frozen checkpoint/answer/close accepted | Three held-stage cases; recovery-only reopening with new starts off, unique answers and three terminal receipts; pm6-host-gate-matrix.log, final494 |
| Parent gate pending reveal/timer checkpoint | Reopen retains support/timer; reveal creates no answer; explicit guided confirmation required; pm6-host-gate-support-timer2.log, final494 |
| Focused layout 412→320 while selected | One target activation yields one canonical answer; pm6-host-focused2.log, final494 |
| Wrong→repair→guided→Review | Separate supported confirmation and actual read-only deferred Review provenance; pm6-host-guided-review.log, final494 |
| Background pause and elapsed | Awaited flush excludes hidden duration; same clock resumes; pm6-host-background-clock.log, final494 |
| Near-capacity timeout and Voice failure | Opening timeout makes no extra receipt; Continue, visible audio fallback and remaining answer still close; pm6-host-timeout-capacity.log, final494 |
| Real effort cap and uncertainty | Incomplete OFF/continued sessions abandon canonically; before/after lost ACK retries same cutoff; last accepted complete answer receives successful close instead; pm6-host-cap-retry-green.log, pm6-host-cap-last-answer.log, pm6-host-continue-hard-cap.log, final494 |
| Normal and replay elapsed/authority | Actual result→fresh replay controller; 2s normal and 3s replay, study/economy/research tables unchanged by replay; pm6-host-replay-elapsed.log, final494 |
| Actual History→Pair host | Canonical reader and History surface launch fresh measured replay, generic launcher zero calls; pm6-host-history-green2.log, final494 |
| Presentation replacement/decor failure | Same owner/controller/coordinator, sync and explicit late failure fallback, no generated answer; pm6-host-presentation-fallback.log, final494 |
| Atomic measured provenance | Real first/second insert and transaction rollback, exact committed bytes after lost ACK/gate-off, no historical retrofit, forged initialization rejected; pm6-admission-adversarial.log GREEN28, final494 |
| Physical database reopen | Both old and measured codec4: pause/expiry/extend/restart/Continue, before/after lost ACK; exact persisted bytes, elapsed or unavailable preserved; final494 (expanded recovery file has34 tests) |
| Clock/capacity loss | Measured OFF coverage becomes sticky null, remains dispatchable, reopens and finishes all four answers/three receipts; pm6-elapsed-coverage-loss.log and final494 |
| Native/remote privacy | Actual Voice factory online remote providers and auth/HTTP spies: localOnly zero remote/auth calls, ordinary same-facade control still succeeds; valid pack and real missing/corrupt pack→proven native, unsupported proof fails closed; final163 |

The held host checkpoint stage uses the actual repository append path; it does not claim physical-device/process-kill testing or independently exercise every research evidence-provider failure inside the UI. Existing canonical capture/owner/uncertain-byte tests remain in final494. Normal accepted-answer learning/economic effects are preserved at cap; only fabricated completion effects are forbidden.

## Visual inspection and accessibility

Actual final PNGs viewed via view_image: setup guardian/source/count/max, Thai timeout, Thai normal measured result, English replay result, scrolled long Thai at200%, dark wrong/repair. Earlier inspected regular6, reverse selected, bounded wide and guided states; root has independent observations in pm6-visual-qa.md.
Final images show visible arrow glyphs, opaque surfaces, primary Return with secondary Replay and no-progress/rewards explanation, three star icons, timeout X/total and single primary Continue, long Thai wrapping with combining marks and legible dark feedback. Result test verifies one accessible star score label and both Thai/English320px at200%; board semantics/keyboard tests run separately from goldens.
Golden Thai framework strings use test-only localization delegates because the repository has no flutter_localizations dependency. Pair copy is real; inherited generic shell feedback remains its current English copy. The guided golden name is not physical audio proof; actual route failure tests establish visible fallback.

## Limits and next step

- Full repository regression and reader-first rollback/owner-move checks belong to PM8; not run here.
- PM7 must wire presentation/mounting and handle already accepted research-configured sessions after withdrawal before attachment. See pm7-configured-withdrawal-preflight.md: planned/unattached controller abandonment is local-only, so explicit owner-pinned canonical loaded-session disposition is necessary. Do not bypass revoked pending guards.
- DB v24/48 tables, 8/44 feature catalog, frozen evidence/envelope and initial schema6 remain unchanged. No new learning/reward/research authority, production navigation, enrollment, upload or rollout enabled.
- Physical TalkBack, Switch Access, installed-device native voice verification, human UAT: NotRun. No efficacy or production-readiness claim.
- No build/deploy, scanner, source stage/commit or external messages/uploads.
- All helper write sets released. No task-owned Flutter/Dart process is running. Source/tool ownership is released to root for fresh independent review after this handoff.

