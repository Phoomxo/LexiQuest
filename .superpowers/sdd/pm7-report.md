# PM7 implementation handoff

Status: implementation and required engineering verification submitted for root's fresh independent review; not self-approved, staged or committed. Final non-overlapping selections: 1,550 integrated tests plus 17 measurement tests, 1,567 passed; final analyzer has no issues.

Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`
Branch: `codex/pair-matching-pm0-pm8`
Base HEAD: `cbc4541ff4ad058e11f056f2d06f7eada201e3f9`
Accepted PM6 source: `41d96c332963e2a105ea3389ba06991595b3a240`

## Implemented behavior

The internal Adventure adapter uses the actual captured Today opening and a genuine review mission. Both presentations retain `PairSourceSurface.today`, the original snapshot reference and reviewed content. Standard uses the optional synchronous contextual delegate factory around the real `openReview` action; null retains the original delegate and its early return without journey/reward reads. Actual Adventure uses `onStartMission`. No production navigation or registry default changes were made.

The route owns one launch identity. Captured owner, entry generation, snapshot and mission checks reject stale setup before the host reserves its exact start operation. Unsupported Standard actions forward unchanged. Double clicks share one pending navigation. After reservation, fallback and retry retain the accepted operation rather than allocating another session.

Playful Quest wraps the canonical board. It adds no answer, clock, repair, star, research or economy authority. Adventure-off, synchronous decoration construction failure and explicit typed late resource health failure retain the same host/controller. Arbitrary descendant Flutter build exception interception is not claimed. Thai/English large text uses the existing board scrolling/semantics; optional header narrative is omitted when it cannot fit.

The accepted configured-session disposition authenticates current owner, exact serialized operation/configuration, latest checkpoint, attempts, source events and existing immutable decision receipts in the canonical Drift transaction. It distinguishes incomplete, frozen uncommitted, committed/lost-ACK, complete and stopped. Missing or partial receipts are corruption, not proof of absence. Historical receipt validation never materializes a missing decision.

Revoked uncommitted evidence remains frozen and unrecorded after explicit canonical abandonment; its stopped session cannot accept later answers/checkpoints. Committed evidence replays its immutable receipt through the existing coordinator and acknowledges the exact checkpoint. A committed final answer or complete active session finishes through the normal three terminal receipts. Already acknowledged completion renders verified results without interactive attachment or new commands/time. No accepted configuration is rewritten to baseline or replay. Temporary provider unavailability retains exact saved-session retry.

The explicit disposition retains the first cutoff across before/after-commit acknowledgement failures. The transaction rereads latest state immediately before abandonment; an intervening canonical answer rejects the stale decision and is retained on retry. Owner drift rejects mutation. Local disposal drains an already admitted operation through its final awaited authentication before releasing its coordinator.

Unattached shell retirement preserves frozen work before attempting settlement, so it cannot blindly retry revoked first writes. Real owner invalidation invokes a payload-free presentation cleanup callback through the existing Pair owner subscription. Experience discards its private diagnostics instance and makes old decoration closures inert. Shell retirement returns an existing terminal future before pausing and avoids calling owner-guarded pause under an invalid owner, while retaining accepted-operation drain and canonical guards.

## Exact write set

Eleven source files:

- `lib/features/adventure/presentation/adventure_pair_experience.dart` (new)
- `lib/features/adventure/presentation/adventure_pair_renderer.dart` (new)
- `lib/features/adventure/presentation/today_experience_host.dart`
- `lib/features/learning/application/learning_use_cases.dart`
- `lib/features/learning/data/drift_learning_event_store.dart`
- `lib/features/learning/data/drift_learning_repository.dart`
- `lib/features/learning/domain/learning_repository.dart`
- `lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart`
- `lib/features/learning/pair_matching/application/pair_matching_unavailable_session.dart` (new)
- `lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart`
- `lib/features/learning/presentation/unified_lesson_shell.dart`

Seven test/support files:

- `test/features/adventure/adventure_pair_renderer_parity_test.dart` (new)
- `test/features/adventure/presentation/adventure_pair_experience_test.dart` (new)
- `test/features/adventure/presentation/adventure_pair_renderer_test.dart` (new)
- `test/features/adventure/presentation/today_experience_host_test.dart`
- `test/features/learning/pair_matching/pair_configured_disposition_test.dart` (new)
- `test/features/learning/pair_matching/pair_measurement_boundary_test.dart` (new)
- `test/support/pair_measurement_fixture.dart` (new)

Three new render baselines, all under `test/features/adventure/presentation/goldens/`:

- `adventure_pair_th_regular.png`
- `adventure_pair_th_narrow_text200.png`
- `adventure_pair_en_narrow_text200.png`

No PM6 PNG was regenerated. The seven pre-existing native registrant paths showing line-ending status remain excluded; their actual Git diff is empty. Report/log/manifest files under `.superpowers/sdd/` are local implementation evidence; root owns portable acceptance documentation and staging.

## Named API additions and ownership

- `ContextualTodayActionsFactory`, optional `TodayExperienceHost.contextualStandardActions`, optional `AdventureMissionLaunchContext.isCurrent`.
- `AdventurePairExperience`, `.standard`, stable `AdventurePairTodayActions.contextualize`, `AdventurePairRenderer`, `AdventurePairDecorationHealth.reportFailure`.
- Optional host `canAdmitLaunch` until retained pending-start reservation; optional `onOwnerInvalidated` for presentation cleanup only, reused through the pane's existing owner signal.
- `PairAcceptedDispositionKind`, `PairAcceptedDispositionSnapshot`, `PairAcceptedSessionDispositionRepository` with `inspectPairDisposition`, `abandonUnavailablePairSession`, `completeUnavailablePairSession`, `replayAcceptedPairAnswer`, and corresponding LearningUseCases wrappers.
- `DriftLearningEventStore.requireExistingDecisionSetForAttempt`, sharing existing immutable validation with unchanged default ensure behavior.
- `PairMatchingSessionCoordinator.retryCommittedPending`; route-owned `PairMatchingUnavailableSession.resolve`, `markPresented`, `deferredReview`, `dispose` exposes no engine commands.
- Test helper `PairMeasurementFixture`, optional `initialize(loseCloseAckOnce: ...)`, `recordPriorRecall`, `PairMeasurementCloseFaultRepository`.

Main PM7 implementer owned every Flutter/Dart/format/analyze/test command and all shared Learning/Pair source. Helper `adventure_composition` owned the three Adventure source files and four Adventure tests until release; main subsequently corrected parity spacing, owner cleanup and lint. Helper `measurement_fixture` owned exactly the measurement test/support pair until release. Helpers ran no Flutter/Dart tools. There were no overlapping source writers. All helpers released their write sets before combined verification.

## Real measurement and policy boundaries

The fixture uses the production P256 verifier with a clearly synthetic, nonproduction test key isolated in test support. The base Motivation fixture supplies study/receipt data; its string-signature fake is not used as cryptographic proof. Positive validation and tampered-payload/wrong-public-key controls use the actual validator/verifier. Recomputed payload digest with retained original signature must still fail.

The signed normal matrix uses actual TodayExperienceHost, baseline/post forms, AdventureResearchRuntime, protocol providers, internal configured Pair, canonical completion, reconciliation and real result Replay. Four cases cover both presentation values and both directions. They preserve one original entry attempt, one opportunity, one mission start and one mission completion through wrong/repair, timer restart, rebuild/reconciliation and post submission within the existing 30-minute window. Standard enToTh additionally loses the real SQL close acknowledgement and retries with the same owner/session/cutoff, controller and answers.

Pair is recognition. Production `effectiveProjectionDisposition` denies mastery SRS for recognition in every rollout mode; the existing matchingPair Legacy matrix has `engagementAllowed:false`, and recognition points are protocol-controlled. Pair itself is not claimed to create recall SRS/points. The positive replay baseline therefore includes genuine prior unassisted SRS recall, recorded/closed through canonical APIs with the actual persisted rollout and assigned research-state providers. It occurs before the captured Today opening and cannot consume that opening's opportunity. Tests require independentRecall/enforced/engagementAllowed context and nonempty SRS/points, then exact preservation through normal Pair and real Replay. No SQL projection seeding or Pair reclassification occurs.

The persisted evidence rollout catalog binds assignment/consent independently of the Motivation participation permit. Mapped expired and denied Motivation controls in both presentations retain the real persisted research configuration instead of faking baseline by removing mapping. They separately assert the actual ordinary Pair answer context remains Legacy/recognition. Motivation-specific runs, responses, opportunities, events and upload/outbox deltas remain zero. Separate fresh absent/denied/expired/withdrawn controls use the genuine baseline catalog. Ordinary learning/sync bookkeeping may grow. Existing withdrawal lifecycle outbox operations are compared unchanged rather than falsely asserting the entire database outbox is empty.

## Verification evidence

All commands ran from the worktree above; logs below are under `.superpowers/sdd/`. Every Flutter command used `--no-pub`. No dependency resolution/build/generator/security scanner was run.

| Evidence | Command / selection | Result |
| --- | --- | --- |
| `pm7-today-context-red.log` | Today contextual focused RED | Expected missing factory API before implementation |
| `pm7-today-context-green.log` | Today focused Standard controls | 9 passed |
| `pm7-disposition-service-green.log` | Focused disposition service | 5 passed |
| `pm7-withdrawal-host-green2.log` | Actual withdrawn incomplete host | 1 passed |
| `pm7-withdrawal-pending1.log` | Signed pending/terminal/core | 10 passed |
| `pm7-disposition-expanded-green1.log` | Full initial disposition file | 22 passed |
| `pm7-parity-first.log` | `flutter test --no-pub --timeout 90s test/features/adventure/adventure_pair_renderer_parity_test.dart --plain-name 'canonical renderer parity compact4 enToTh off' --reporter expanded` | 1 passed |
| `pm7-parity-six-green.log` | Same file, `--plain-name 'canonical renderer parity standard6 enToTh off'` | 1 passed after fixture spacing correction |
| `pm7-parity-matrix-green.log` | Same complete parity file | 25 passed: 16 matrix + 9 pending fallback |
| `pm7-adventure-composition-green.log` | `flutter test --no-pub test/features/adventure/presentation/today_experience_host_test.dart test/features/adventure/presentation/adventure_pair_experience_test.dart test/features/adventure/presentation/adventure_pair_renderer_test.dart --reporter expanded` | 36 passed before owner-cleanup addition |
| `pm7-adventure-golden-final.log` | `flutter test --no-pub --update-goldens test/features/adventure/presentation/adventure_pair_renderer_test.dart --reporter expanded` | 4 passed, 3 new PNG inspected by main and root |
| `pm7-owner-diagnostics-green3.log` | Experience test, `--plain-name 'same mounted Adventure route clears decoration diagnostics on real owner invalidation'` | 1 passed before later idempotent-retire reorder; covered again below |
| `pm7-measurement-composed-scope.log` | Measurement file, exact Standard enToTh normal case | 1 passed before prior-recall/close-retry additions |
| `pm7-measurement-prior-recall-green.log` | `flutter test --no-pub --timeout 90s test/features/learning/pair_matching/pair_measurement_boundary_test.dart --plain-name 'real Today measurement Pair standard enToTh keeps one denominator through restart repair rebuild and replay' --reporter expanded` | 1 passed, real recall baseline and close retry |
| `pm7-final-disposition-host-green2.log` | `flutter test --no-pub --timeout 90s test/features/learning/pair_matching/pair_configured_disposition_test.dart test/features/learning/pair_matching/pair_matching_experience_host_test.dart test/features/adventure/presentation/adventure_pair_experience_test.dart --reporter expanded` | 60 passed; includes 25 disposition, 8 composition, 27 existing host tests |
| `pm7-format-final.log` | `dart format` on exact `pm7-dart-file-manifest.txt` | 18 files, final manual lint corrections formatted |
| `pm7-final-analyze-green.log` | `flutter analyze --no-pub` | No issues, 7.2 seconds |
| `pm7-final-analyze-17-green.log` | `flutter analyze --no-pub` on final 17-test source | No issues, 6.6 seconds |
| `pm7-final-measurement-matrix.log` | `flutter test --no-pub --timeout 90s test/features/learning/pair_matching/pair_measurement_boundary_test.dart --reporter expanded` | Intermediate 4 pass / 11 fail; superseded by final GREEN17 after the documented fixture corrections |
| `pm7-final-integrated-regression.log` | `$pm7Selection = Get-Content -LiteralPath .superpowers/sdd/pm7-integrated-test-selection.txt`; `flutter test --no-pub --timeout 90s @pm7Selection --reporter expanded`, exact 46 entries in that file | 1,550 passed in 1m55s; all its inputs unchanged during execution |
| `pm7-measurement-adventure-sync-green.log` | `flutter test --no-pub --timeout 90s test/features/learning/pair_matching/pair_measurement_boundary_test.dart --name 'real Today measurement Pair adventure enToTh\|fresh absent standard' --reporter expanded` | 2 passed in 30s after real Adventure scroll/compatible synthetic sync-writer correction |
| `pm7-final-measurement-matrix-green.log` | Full measurement file, same command above | 15 passed in 2m37s, before addition of mapped-denied controls |
| `pm7-mapped-denied-green.log` | Measurement file with `--name 'preserves active evidence'` | 4 passed in 33s: real mapped expired/denied in both presentations |
| `pm7-final-measurement-17-green.log` | `flutter test --no-pub --timeout 90s test/features/learning/pair_matching/pair_measurement_boundary_test.dart --reporter expanded` | 17 passed in 2m52s on final source: 1 cryptographic control + 4 signed flows + 8 fresh baseline controls + 4 mapped expired/denied controls |

The integrated selection includes all Pair tests except the separately executed measurement file, all Adventure/research/Today feature tests, Today screen, PM6 host/configuration/history/gate selection and touched Learning repository/event store/use-case/evidence/projection regressions. Golden comparisons use existing PNGs without updating them. The passing integrated log contains 27 inherited Drift multiple-AppDatabase warnings from existing identity/assignment, Today and History fixtures; it is not warning-free. These were neither suppressed nor used to broaden cleanup scope. Prior PM6 502/Voice163 evidence is historical, not substituted for PM7 execution.

## Retained failures and corrections

- Missing source/API REDs in `pm7-disposition-composition-red.log`, `pm7-composition-red2.log`, `pm7-adventure-context-red.log`, `pm7-disposition-service-red.log` were expected implementation REDs. An unintended flutter_localizations test import was removed in favor of the existing localization override; no dependency was added.
- `pm7-disposition-composition-green1.log` was 13 pass / 2 fail, not GREEN. Renderer semantics handles were leaking at teardown; fixed with explicit disposal in `try/finally`.
- `pm7-withdrawal-host-red.log` reproduced the missing explicit disposition UI. `pm7-withdrawal-host-green1.log` exposed an offscreen test tap; ensureVisible corrected the fixture. `pm7-withdrawal-ui-matrix1.log` was 4 pass / 1 fail because stopped reopen omitted the truthful unrecorded-pending copy; the host now reads the retained snapshot.
- `pm7-disposition-consistency-red.log` exposed inconsistent canonical answer counts and an abandoned row with committed pending evidence. Both now fail closed before mutation.
- `pm7-parity-matrix1.log` was 17 pass / 8 fail. The six-pair fixture incorrectly expected repair after two intervening successes; the actual unchanged policy requires three. The script now uses three for six pairs, two for four, retaining explicit guided/reveal behavior and full canonical comparison. Failed-fixture cleanup was moved into finally.
- Initial three renders passed generation but visual inspection found optional text200 narrative clipped. `pm7-adventure-visual-red.log` records the layout regression. The final renders omit only optional narrative and keep complete task instructions/title and scrollable board.
- `pm7-measurement-first.log` did not complete. Only validated task-owned flutter_tester PID 24668 (parent 10728, exact worktree package configuration) was stopped after 2:34, preserving logs/source. This was not presented as proof of a cryptographic deadlock. `pm7-measurement-diagnostic.log` isolated a real-zone permit read awaiting Today SQLite work in the widget fake-async zone; bounded alternating real/fake scheduler pumps corrected the fixture.
- `pm7-measurement-scheduler.log` exposed a lazy-list review button; actual scrolling replaced the unavailable test tap. `pm7-measurement-launch.log` and `pm7-measurement-admission-diagnostic.log` then showed Today still mounted/current, one accepted configured session and two checkpoints, but missing AppDependenciesScope caused the production feature gate to deny the shell. The real synthetic scope now contains the same database, runtime, providers and composed dependencies. No gate/currentness guard was weakened.
- `pm7-measurement-close-retry-green.log` failed its newly added nonempty SRS assertion. Actual recognition policy intentionally denies SRS/points for this Pair input. Genuine canonical prior recall supplies a meaningful positive baseline; the Pair policy/providers remain unchanged.
- `pm7-owner-diagnostics-red.log` reproduced missing cleanup. The first correction still used raw SQL, which did not emit Drift table notifications. Real typed Drift owner update then exposed synchronous stale-owner pause during final unmount (`pm7-owner-diagnostics-green2.log`); owner-checked pause and idempotent retirement corrected the actual teardown.
- `pm7-final-disposition-host-green.log` was 59 pass / 1 fail: an admitted disposition returned its final Future without awaiting before `finally` disposed its coordinator. `return await _inspect()` now drains the final authentication before local disposal; GREEN60 follows.
- `pm7-final-analyze.log` found 16 multiline-if brace lints and two unused test imports. Manual scoped fixes produced the clean final analyzer log. No assertions were removed or skipped.
- `pm7-final-measurement-matrix.log` was 4 pass / 11 fail. All seven Adventure cases reached an unbuilt mission-sheet button beneath the lazy map; the fixture now scrolls the actual vertical Adventure list before tapping. Four enabled synthetic sync controls reached the default v1 attempt writer, which correctly rejects declared Pair evidence. The fixture now opts that local claim store into the existing `SyncPayloadRollout.answerAttemptV2()`; it retains the default-off control, real research authorizer, ordinary outbox and research-claims-zero assertion. No production writer or claim guard changed.
- Fresh independent review identified a missing mapped-denied control: baseline-denied cases did not substitute for a retained mapping. Two cases were added to the existing measurement test (17 total); mapped expired/denied now directly verify persisted Pair configuration, actual evidence context and Motivation collection/claim denial in both presentations.

## Frozen identity and remaining boundaries

Current 21-file manifest: `pm7-frozen-sha256.txt`; SHA256 `690469c6fcf4eb3497d5e782e2d8f20644d74c8085e6bbce8011a87e70f93177`. It contains the exact 18 Dart and three PNG hashes after formatting/lint and measurement-fixture corrections. Only the separately excluded measurement test changed after the prior `df1074668691d8228dd13e7afd1d697b2e905408f640a6a7429245d9e957e2bf` snapshot; all 1,550 integrated inputs are unchanged. After final 17 tests and analyzer, `pm7-final-manifest-check.log` verified all 21 files with zero mismatches. `git diff --check` exited zero (`pm7-final-diff-check.log`); only known line-ending notices occurred. HEAD/branch were reconfirmed unchanged.

DB v24/48 tables, catalog 8/44, f10/matching/learning/matching, frozen EvidenceContext/EventEnvelopeV2, initial activity schema6 and progressed codec4 remain unchanged. No migrations, dependencies, generated schema, production registry/default navigation, or ordinary provider policies changed.

This is synthetic engineering evidence/UAT-050 fixture rehearsal only. Physical Thai/English device rendering, TalkBack, Switch Access, native voice, learner/guardian UAT and research efficacy are NotRun. Real issuer/ethics/instrument authorization, enrollment/upload/rollout remain disabled and external. PM8 authentic runtime R versus immutable plan P owner rehome, full release checks and deployment decisions remain separate; the current owner guard deliberately uses the pre-PM8 immutable plan owner and must be updated only through PM8's authenticated mapping contract.

All helper write sets and all serialized Flutter/Dart tooling are released. Every owned command completed; `pm7-process-release.log` records zero worktree-bound dart/dartaotruntime/flutter_tester processes after final analysis. No source writer remains active. No stage/commit/push/merge/deploy occurred. Root performs independent review/staging/commit; this report does not approve PM7 or complete PM0–PM8.
