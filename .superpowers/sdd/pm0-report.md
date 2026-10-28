# PM0 report — Pair Matching f10 characterization

Status: complete on worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, detached baseline `ca123ddd`. Flutter/Dart tool ownership is released.

## Changed paths

- `test/architecture/pair_matching_f10_boundary_test.dart`
- `test/screens/matching_mode_screen_test.dart`
- `test/features/learning/matching_mode_adapter_test.dart`
- `test/scenarios/production_feature_navigation_test.dart`
- `docs/development/2026-09-05-pair-matching-pm0-characterization.md`
- `.superpowers/sdd/pm0-report.md`

No production source, schema, event or evidence payload changed. No hidden Pair production contract was required.

## Evidence

- `flutter test test/architecture/pair_matching_f10_boundary_test.dart` — 2/2 passed. TC-PMT-001 locks f10, default-hidden delivery, quiz parent entry, matching child route, four existing app routes and 48 tables. Three negative mutation fixtures prove that f45, a Pair main route and a Pair star table are rejected.
- `flutter test test/features/learning/matching_mode_adapter_test.dart` — 60/60 passed. Characterizes recognition classification, activity identity, checkpoint limit, deterministic pins, exact retry/restart, checkpoint schema/bounds and terminal recovery.
- `flutter test test/screens/matching_mode_screen_test.dart` — 7/7 passed. Characterizes current screen output, absence of visible stars, resume behavior, evidence behavior and implemented-off/live-off fencing.
- `flutter test test/scenarios/production_feature_navigation_test.dart` — 25/25 passed. Characterizes feature-off Pair resolution and existing production navigation. Drift emitted its existing multiple-database debug warning; tests exited 0.
- `flutter test test/architecture/alltcas_idea_feature_contract_test.dart test/architecture/alltcas_idea_feature_contract_models_test.dart` — 20/20 passed. Exact 8-domain/44-feature catalog remained intact.

TDD/characterization recovery: the architecture negative fixtures passed by observing the validator reject all three invalid mutations. Two fixture-only compile/assertion corrections were made after focused failures: `HintUsageSnapshot.available` was corrected to the real `known(0)` API, and rendered progress was asserted through its semantic label. The navigation fixture was moved off a later local variable dependency. All affected files passed after correction.

## Constraints and seams

- Baseline/rollback target: `MatchingModeScreen` and `MatchingModeAdapter` at `learning/matching`, commit `ca123ddd`.
- Delivery remains `implementedOff`; no prototype UI is production-visible.
- Schema stays v24/48 tables; checkpoint schema stays 5 with reader support 1–5, 64 revisions and 64 KiB.
- Evidence remains `matchingPair` recognition or guided practice through the existing gateway; `EvidenceContext` and `EventEnvelopeV2` are unchanged.
- PM1–PM8 should use the existing atomic `startCheckpointedQuiz` / `startExactPinnedSessionWithCheckpoint` seam, add Pair delivery and content-quality checks, freeze lost-ack launch identity, evolve checkpoints reader-first, share reducer/timer/repair logic, derive stars without persistence, preserve Standard fallback, and retain default-hidden rollback tests.
- Pre-existing native generated registrant line-ending churn remains preserved and excluded from PM0 changes.
- No full suite/build, commit, branch change, other worktree, rollout, research write or security scan was performed.
