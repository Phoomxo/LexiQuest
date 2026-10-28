# Task PM0 — Baseline characterization and f10 boundary lock

Requirements: FR-105/106/130, NFR-040/046, BR-024/034.

Inspect first:
- lib/screens/matching_mode_screen.dart
- lib/features/learning/application/matching_mode_adapter.dart
- lib/features/learning/application/lesson_mode_registry.dart
- lib/features/learning/domain/lesson_mode.dart
- lib/navigation/app_routes.dart
- lib/runtime/registries/feature_registry.dart

Tests to add/update:
- test/architecture/pair_matching_f10_boundary_test.dart
- test/screens/matching_mode_screen_test.dart
- test/features/learning/matching_mode_adapter_test.dart
- test/scenarios/production_feature_navigation_test.dart

1. Record current f10 route, adapter, session/evidence path, restart/checkpoint behavior and screen output as characterization fixtures.
2. Write failing architecture test proving no f45/new main destination/new star table and Pair launch resolves f10. Existing true invariants can pass as characterization; verify negative mutation fixtures rather than inventing a production change just to see RED.
3. Add hidden delivery contract only if tests require it; preserve visible behavior.
4. Run TC-PMT-001, existing exact 8/44 map tests, feature-off navigation regression.
5. Review diff: no schema/event/evidence payload changes.

Exit: reproducible baseline, f10 locked, rollback target identified, no prototype UI visible.

Read AGENTS.md and spec M12 / section 21 at docs/superpowers/specs/2026-09-01-adventure-motivation-mode-design.md. Existing plan approved; no design approval cycle. Research baseline ca123ddd (source ed89efaf), schema v24 with 48 tables. Preserve 8/44 and frozen evidence/event contracts. Do not change other worktrees, rollout or research. No Codex Security. Use apply_patch, focused TDD, bounded recovery.

Write set: above tests, optional narrowly necessary hidden Pair contract under learning/pair_matching/domain, and docs/development/2026-09-05-pair-matching-pm0-characterization.md. Ask root before other production edits. No branch changes or commits: root integrates. You alone may run serial Flutter/Dart commands during PM0; do not run full suite/build. Setup pub get completed.

Report to .superpowers/sdd/pm0-report.md with paths, exact commands/counts/RED-GREEN or characterization evidence, constraints and integration seams for PM1–PM8. Return concise status and release tool ownership.
