# PM5 implementation handoff

Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`.
Branch: `codex/pair-matching-pm0-pm8`. HEAD `c3b389e6` (root documentation); accepted source baseline `09ef33a1` (PM4).
Source changes are unstaged and uncommitted. Independent final review/acceptance is still required before PM6 dispatch. No production enrollment/upload, deployment, scanner, schema migration, frozen EvidenceContext/EventEnvelope key change, or new reward/learning authority was introduced.

## Implemented behavior

- Star policy 1 is derived from the acknowledged terminal engine ledger. First-attempt all-correct/no-support yields 3; independent >= 3/4 (including 5/6) yields 2; other complete boards yield 1; incomplete/pending/unacknowledged yields null. Delayed independent repair counts as independent but never restores the first-attempt criterion. Timer/layout/replay purpose are not scoring inputs.
- Result view separates matched, independent, assisted, stars, timer outcome and Review next. Thai/English copy and 320px/200% text are widget-tested. Elapsed is explicitly **challenge-timer elapsed**, not full play/study time; off mode omits unavailable elapsed. Continue-untimed does not pretend its unmeasured tail is timed.
- Shared persisted-purpose decoding authenticates initial/latest v6 plans and transition prefix, canonical session/owner/start/config identities, source linkage and immutable retry bytes. Empty matching checkpoints are unknown/unavailable, never ordinary authority; 6-to-5 disguises, malformed envelopes, mismatched actors/keys and partial prefixes fail closed. Supported legacy states use the actual legacy decoder. Historical guest actors require inactive canonical `mergedInto:<currentOwner>` lineage and the original actor-derived event key; fake/missing/active/wrong-target markers fail.
- Canonical answer first-write admission, Today selection, research attachment/reconciliation/upload and host time/configuration admission consume that same persisted purpose. Checkpoint-less historical matching may remain read-only in History with `pairPurposeUnavailable`, no Pair summary, and exclusion from normal-only selectors. Canonical answer/event corruption still fails History validation.
- Explicit Practice Replay creates a fresh session/seed with exact source lexical pins, direction/density, sourceSessionId and supplied configuration; atomic start revalidates current owner/content/reports/source and rejects dropped source configuration. Existing generic History repeat remains unchanged. Exact accepted operations survive repeat/recovery; replay answer and terminal lost-ack recovery are exercised against real SQL writes.
- Typed replay capture/restore emits declared policy-v1 recreational evidence with legacy rollout matrix and engagement=false, plus exact no-research event context. This is **not legacyCompatibility inference** and does not alter frozen contracts. Mutable research/rollout providers are bypassed for this explicit path. Exact-context validation rejects injected consent during restore and at canonical pending admission. Engine support-at-attempt classification remains independent for descriptive stars.
- History has typed Pair summaries, normal latest/best selectors and replay groups/latest/best by direct immutable source. Normal filters are applied before list limits. A newer 3-star replay cannot replace a 2-star normal best/latest.
- Real UnifiedLessonController authenticates purpose before activeTime.start/focus.attachSession, including zero taps. Replay/unknown cannot record pointer/keyboard/semantic interactions, direct focus commands, configuration effort or study time. The canonical configuration-effort repository also rejects replay directly.
- Research skips replay before the next genuine session; direct attach/complete checks purpose before idempotent returns. Upload purpose and historical-owner queries run through tracked `_Reads`, including absent/new checkpoint rows. Mutations, insertion and all-row deletion during actual external receipt await reject authorization; normal signed synthetic control remains allowed.

## Verification and measured deltas

Main real replay harness uses canonical SQL sessions/answers/checkpoints, real progress queries/rebuild, real time/focus controllers, and the real side-effect reconciler. It snapshots all columns of:

`srs_states`, `points_ledger_entries`, `achievement_unlocks`, `reward_transactions`, `owned_reward_items`, `equipped_reward_items`, `quest_instances`, `quest_objective_progress`, `streak_states`, `learning_day_log`, `learning_time_segments`, `session_configurations`, `assessment_runs`, `motivation_measurement_runs`, `motivation_responses`, `measurement_opportunities`.

Observed replay delta is zero for those tables and for SRS/mastery/due, weakness list, global/skill accuracy, XP/level, achievements, streak/completed-learning count and response-time summary projections. Baselines include nonempty SRS, XP, coin, ownership/equipment, streak/day and achievement rows. Quest baseline is created/projected through actual QuestUseCases/DriftQuestRepository. Research/Today use separate nonempty real repository fixtures with explicit synthetic canonical-purpose inputs; these are not represented as real enrollment or normal Pair mission UI proof.

Sink proof does not rely on throwing exceptions: normal baseline is drained, replay invocation counters stay zero, no pending projection remains, and each replay answer has exactly four canonical `LearningProjectionSkipped/notApplicable` receipts (coins/quest/streak/reward), no blocked receipt. Quest sink uses real projection/reward reconciliation; non-quest injected sinks return explicit notApplicable only when draining the normal fixture, and are never invoked for replay. Raw replay sessions, answers, events, projection receipts and ordinary sync bookkeeping are expected to grow; **global outbox zero is not asserted**.

Actual shell widget coverage: zero-tap mount/start, pointer tap, Enter, semantics tap, direct focus start, background/resume and terminal close. Real focus stays unattached/notStarted/zero duration; learning-time rows stay unchanged. Configured replay direct effort write is rejected before UPDATE, exact configured completion/retry/recovery preserves zero effort.

## Commands and evidence

All commands ran locally with `--no-pub`, serialized, on synthetic fixtures. Logs are under `.superpowers/sdd/`.

- `flutter analyze --no-pub`: `pm5-analyze.log` — No issues found (12.9s), after final source changes. Final post-test-only-edit run `pm5-analyze-final.log` — **No issues found (11.7s)**.
- Broad regression command below: `pm5-final-regression.log` — **883 passed**, no failures (46s). Earlier run found the read-only legacy History compatibility issue (882 pass/1 fail); fixed without weakening canonical answer validation, focused History/result run passed 17.
- Latest replay test file after added answer/close lost-ack injection: `pm5-replay-final.log` — **9 passed**. No production source changed after the 883-case run.
- `flutter test --no-pub test/features/learning/pair_matching/pair_matching_configuration_test.dart --reporter expanded`: `pm5-config-source-green.log` — 2 passed; includes config byte reserve/preinsert rejection, actual-policy configured completion/replay/retry, dropped-config rejection and direct effort denial. `pm5-config-capacity.log` independently records the same byte-bound fixture.
- `flutter test --no-pub test/features/learning/pair_matching/pair_matching_session_purpose_test.dart --reporter expanded`: `pm5-envelope-green.log` — 10 passed, including advisory envelope negatives and historical actor marker negatives. These also passed in the final 883 run.
- `flutter test --no-pub test/features/research/research_sync_authorizer_test.dart --plain-name 'tracked normal Pair mission' --reporter expanded`: `pm5-upload-tracked.log` — 4 passed: control, mutation, insertion and all-checkpoint deletion during external await. Full authorizer/sync tests are included below.
- `flutter test --no-pub test/features/research/measurement_opportunity_repository_test.dart --plain-name 'direct seeded replay' --reporter expanded`: `pm5-research-idempotent.log` — 1 passed, including already-linked/already-completed attacks and unchanged primary/event/outbox rows. SQLite total_changes was deliberately replaced with durable row snapshots because it includes rolled-back work.
- Result Thai/English 320px/200% test: `pm5-result-final.log` — 1 passed. Remaining RED/GREEN topic logs preserve stars, replay capture, history, research, Today, config, context-tampering and sink-receipt development evidence.
- Dart format was restricted to changed Dart files; `pm5-format.log`, `pm5-format-final.log`, `pm5-retry-format.log`. `git diff --check -- lib test` passed; Git only reports its configured LF-to-CRLF checkout warnings.

```powershell
flutter test --no-pub test/features/learning/pair_matching test/features/learning/current_activity_evidence_test.dart test/features/learning/drift_learning_repository_test.dart test/features/learning/matching_mode_adapter_test.dart test/features/learning/unified_lesson_controller_test.dart test/features/learning/learning_side_effect_reconciler_test.dart test/features/learning/session_configuration_store_test.dart test/features/learning/session_configuration_policy_test.dart test/features/history test/features/today_hub test/features/research/measurement_opportunity_repository_test.dart test/features/research/motivation_measurement_use_cases_test.dart test/features/research/research_sync_authorizer_test.dart test/features/sync/research_measurement_sync_test.dart test/features/rewards test/features/quest test/features/motivation/streak_learning_integration_test.dart test/features/time_tracking test/features/progress --reporter expanded
```

## Exact source/test write set

```text
lib/features/history/data/drift_learning_history_reader.dart
lib/features/history/domain/learning_history_models.dart
lib/features/learning/application/current_activity_evidence.dart
lib/features/learning/application/matching_mode_adapter.dart
lib/features/learning/application/unified_lesson_controller.dart
lib/features/learning/data/drift_learning_repository.dart
lib/features/learning/pair_matching/application/pair_matching_atomic_start.dart
lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart
lib/features/learning/pair_matching/application/pair_practice_replay.dart
lib/features/learning/pair_matching/data/drift_pair_matching_session_purpose_reader.dart
lib/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart
lib/features/learning/pair_matching/domain/pair_matching_history_projection.dart
lib/features/learning/pair_matching/domain/pair_matching_session_purpose.dart
lib/features/learning/pair_matching/domain/pair_star_policy.dart
lib/features/learning/pair_matching/presentation/pair_matching_result_view.dart
lib/features/learning/presentation/unified_lesson_shell.dart
lib/features/research/application/motivation_measurement_use_cases.dart
lib/features/research/data/drift_measurement_opportunity_repository.dart
lib/features/research/data/drift_research_sync_authorizer.dart
lib/features/today_hub/data/drift_today_hub_reader.dart
test/features/history/learning_history_reader_test.dart
test/features/learning/pair_matching/pair_matching_configuration_test.dart
test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart
test/features/learning/pair_matching/pair_matching_result_view_test.dart
test/features/learning/pair_matching/pair_matching_session_purpose_test.dart
test/features/learning/pair_matching/pair_practice_replay_test.dart
test/features/learning/pair_matching/pair_star_policy_test.dart
test/features/research/measurement_opportunity_repository_test.dart
test/features/research/motivation_measurement_use_cases_test.dart
test/features/research/research_sync_authorizer_test.dart
test/features/today_hub/today_hub_reader_test.dart
test/support/pair_purpose_fixture.dart
```

Pre-existing Linux/macOS/Windows generated plugin registrant line-ending changes were not included in this write set and were preserved. Root documentation/guardrails were not edited. This report and topic logs are handoff notes, not source commits.

## Remaining explicit phase boundaries

- PM6 owns actual Pair board/setup/navigation/History UI integration and complete host accessibility/device proof. The result component and actual generic shell purpose admission are implemented/tested here. The existing legacy Matching registration only supports **forward** SessionConfiguration; it was not broadened. Reverse configured Pair requires PM6's authorized internal Pair registration seam. Unconfigured PM1 bytes remain version1/exact; provided config uses optional version2 envelope only.
- f16 SessionConfiguration effort timing retains its real policy and is separate from Pair challenge clock. No invented policy limits/protocols/defaults. Oversized configured plans fail before INSERT; no configuration is dropped to fit.
- PM7 still owns normal Pair research mission/measurement UI linkage with real supplied policy configuration. A configured canonical Pair start/complete is proven locally, and signed synthetic authorizer controls pass; a generic/seeded control is not claimed as end-to-end normal Pair measurement UI completion.
- PM8 owns actual v6 owner rehome/export/deletion/release integration. Plan and frozen actor identities remain immutable; legacy rehome compatibility is covered, v6 rehome is not claimed complete.
- No physical-device UAT, backend deployment/build, live participant enrollment, real research upload or research efficacy claim. Real research remains default-off. Independent final PM5 review is pending root orchestration.

Final handoff: analyzer passed; fresh `git -c core.safecrlf=false diff --check -- lib test` passed with no output. Read-only `Get-Process dart,flutter,dartaotruntime -ErrorAction SilentlyContinue` returned no processes. No task-owned test/build processes remain. Source writes and serialized tooling ownership are released to root for independent final review; no further edits are underway. Next executable step: root independent review of this exact write set, then authorized PM6 dispatch after acceptance.

## Independent review P2 pagination correction

Root reopened only History reader/tests after `.superpowers/sdd/pm5-review-report.md` identified lifetime `_entry` hydration. This section supersedes the earlier handoff status for that bounded fix; the root-staged 32-file review snapshot was not staged again or changed in the index by this worker.

Exact additional write set:

- `lib/features/history/data/drift_learning_history_reader.dart`
- `test/features/history/learning_history_reader_test.dart`
- This report and `.superpowers/sdd/pm5-pagination-*.log` evidence.

`list()` now selects canonical global terminal order in SQL, incorporating completed/abandoned assessment terminal timestamps even while the generic session is still active. Candidate transport is bounded to 20–100 rows per keyset batch (terminal descending, start descending, session ID ascending). It advances through excluded matching purposes until the eligible page is filled, then stops. Only selected entries hydrate answer/event/content/time projections. Purpose decoded for filtering is reused; default History does not purpose-decode or hydrate older off-page entries. Assessment duplicate/missing session or canonical answer/event validation is retained when the affected entry is selected. Read-only unavailable matching metadata and normal-only exclusion remain unchanged. Explicit `pairOverview()` behavior is outside this P2 change.

Regression evidence:

- RED: `flutter test --no-pub test/features/history/learning_history_reader_test.dart --plain-name 'page hydrates only' --reporter expanded` → `pm5-pagination-red.log`: old implementation failed with `history contains an answer event without attempt` from an old entry outside limit1.
- GREEN same focused command → `pm5-pagination-green.log`: 1 passed. Fixture has a valid recent normal, 21 newer excluded replay sessions (crosses a batch boundary), and an older orphan canonical answer event. Limit1 returns the recent normal and the real time-repository hydration observer sees exactly that session. Limit2 reaches the corrupt old entry and still throws. Default include-replay limit1 hydrates exactly one entry.
- Added completed and abandoned assessment cross-source controls with generic/assessment terminal ties, later-start tie and session-ID tie; limits1/3/4/6 return the exact canonical order and hydrate only that prefix.
- `dart format lib/features/history/data/drift_learning_history_reader.dart test/features/history/learning_history_reader_test.dart` → `pm5-pagination-format.log`.
- `flutter test --no-pub test/features/history test/features/learning/pair_matching/pair_practice_replay_test.dart test/features/today_hub test/features/assessment --reporter expanded` → final `pm5-pagination-regression.log`: **101 passed, zero failures, 12s**. No 883-case rerun was needed for this isolated History fix. The 883 result above describes the prior reviewed snapshot; 101 is the fresh affected-subsystem result.
- The regression log is **not warning-free**: Drift emits its debug multiple-AppDatabase-instance warning. Its final stack points to the unchanged `assessment_use_cases_test.dart:1901` `_Harness.create` called twice in the existing complete/abandon test (`:1839`). Each default harness creates a distinct `AppDatabase(NativeDatabase.memory())`, registers teardown, and intentionally coexists for the test. This P2 change does not create database connections or alter assessment fixture lifecycle. Similar debug fixture warnings exist in the earlier broad regression; this is not a newly introduced shared QueryExecutor or a suppressed test failure.
- Final `flutter analyze --no-pub` → `pm5-pagination-analyze.log`: **No issues found (8.9s)**. Fresh `git -c core.safecrlf=false diff --check -- lib/features/history/data/drift_learning_history_reader.dart test/features/history/learning_history_reader_test.dart` passed without output. Process check returned no Dart/Flutter/dartaotruntime processes. All bounded-fix writes are finished, source/tool ownership is released to root, and the index remains untouched. Next step is the same reviewer's recheck of root's saved unstaged fix diff before any commit/PM6 dispatch.
