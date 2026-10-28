# PM6 final review correction

Read .superpowers/sdd/pm6-review-report.md in full. Root verified I1/I2/I3 against actual source and accepts these findings. Fix all three Important issues and the bounded M1/M2/M3; M4 inherited Drift fixture warnings remain disclosed, do not suppress or start unrelated cleanup.

Same worktree C:/Users/Phet/.codex/worktrees/02fa/LexiQuest; branch codex/pair-matching-pm0-pm8; HEAD7919cb860bc37d6d2d2811e4f6633340eca94010. Index retains original43 Dart+12 PNG review snapshot; do not stage/reset/commit it. Only working-tree deltas from this snapshot are review fixes. Root owns all Git mutations.

## Authorized exact source/test ownership

- lib/features/learning/pair_matching/presentation/pair_board_view.dart
- lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart
- lib/features/history/application/learning_history_use_cases.dart
- lib/screens/learning_history_screen.dart
- test/features/learning/pair_matching/pair_board_accessibility_test.dart
- test/features/learning/pair_matching/pair_board_view_test.dart
- test/features/learning/pair_matching/pair_matching_experience_host_test.dart
- test/screens/learning_history_screen_test.dart

Main implementer has sole Flutter/Dart/tool ownership for this correction. No other writers active. You may give a helper the two board test/source files only after exact disjoint ownership and API assignment, no helper tooling. If a necessary change lies outside this set, name the concrete file and reason to root first; no rework of PM7/PM8. Existing goldens are frozen and should compare unchanged for semantics/recovery fixes; if visible History copy has no existing baseline, verify the bounded actual widget at narrow200 without claiming a new golden already exists.

## Fix and evidence

I1: Keep guided content meaning and one real actionable Confirm node in semantics; disabled/busy/pending has no action. Send SemanticsAction.tap to the actual node in regular/focused board tests; exactly one typed learner confirmation with correct word/support revision. Focus/build/reading alone still writes nothing. Preserve existing keyboard behavior and layout.

I2: Use typed coordinator recovery, not just canRetry. On same actual host/controller retry canonical close before/after commit ACK loss with same close timestamp/bytes/IDs; retry a failed authenticated result read after close without premature presented receipt. Result must render before acknowledgePresentation. Do not bypass owner/gate/lease or instantiate a new controller. Focused actual-host failures must end with unique answers and exact terminal receipts.

I3: Hydrate valid completed results without treating a valid incomplete/unacknowledged/abandoned Pair in the same bounded page as a batch error. Keep identity/current-owner/strict purpose authentication and no stars/replay for incomplete. Use actual canonical completed normal + replay + cap-abandoned rows on one History page; completed results/typed Replay remain usable.

M1: Announce crossing 30s/10s exactly once per appropriate round/timer phase despite nonaligned 250ms samples, e.g. 30050→29800 and 10050→9800; no per-tick announcement or new timer authority. Preserve elapsed/extension/restart behavior.

M2: Remove opaque sourceSessionId from product text. Keep typed exact replay lineage and use human-readable loaded-page source date/name if available, generic truthful source explanation otherwise. No lifetime hydration, extra source query or changed replay identity. Update only assertions affected by copy.

M3: Expected timed-capacity pause during post-frame resume must remain the existing Continue UI without uncaught framework exception; do not swallow arbitrary domain/persistence failures. Add actual restored timed-capacity host reproduction. Prefer existing typed readiness/availability over broad try/catch; preserve PM4 mandatory reserve.

Start with meaningful focused RED evidence for the defects, implement, run those focused GREEN, then final full Pair+legacy/shell/config/History/gate selection from pm6-report.md on frozen source, Voice regression only if inputs changed (none authorized here), and analyzer. Full Pair regression includes unchanged golden comparison; do not regenerate to hide drift. Record failures/corrections, exact commands/counts/logs and unchanged-source evidence in .superpowers/sdd/pm6-review-fix-report.md. Reconcile real state after failed tools, bounded recovery, no claims until actual output. Release source/tools/processes after handoff. Root will package working-tree fix diff, request same reviewer to verify closure, and only then commit PM6 locally.
