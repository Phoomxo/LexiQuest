# Learning loop improvements from the mobile app study

Date: 2026-10-18, Asia/Bangkok
Workspace: C:/Users/Phet/Documents/LexiQuest
Branch: feature/associative-reading-loop
Base HEAD: f43aa0fff2155ca29d6a26f2695191dd44a2d6d1
Status: Implemented and verified locally. No commit, deployment, or device install.

## Result

The learning hub now displays real due-review and weakness counts, recommends the next activity, reloads after the complete learning flow returns, and supports retry on a queue-read failure.

Weakness Clinic starts a targeted quiz even when no SRS words are due. A batch selects the top 20 ranked weaknesses before repository filtering. The repository filters target IDs before its result limit, so targets outside the original first 100 words remain available. Owner and deleted-word filters stay in force. Ghost Duel retains its separate session activity semantics.

Quiz displays textual feedback and the stored vocabulary meaning after a successful answer write. Score lists the words answered incorrectly and starts practice for those words through the existing learning authority. Score and practice navigation preserve the original flow completion Future, so hub and clinic refresh after the final return.

Quiz retries preserve attempt identity, timestamp, selected answer, and response time. Tests exercise failure before write and a lost acknowledgement after write; retry leaves one attempt and one points-ledger entry. Haptic failure cannot change a committed answer into a retry. No new schema or parallel reward/SRS authority was introduced.

## Verification

- Baseline: 16 existing focused tests passed before implementation.
- TDD: observed failures for target selection beyond 100, activity semantics, single-target distractors, missing feedback/practice action, hub loading, stable submission retry, premature refresh, and ranked batch selection.
- Final regression: 150 tests passed across learning, progress, rewards, quest, motivation, quiz, clinic, hub, Ghost Duel, SRS and layout.
- Targeted Flutter analyze: 14 source/test files, no issues found.
- Format and focused diff checks completed. Final two test files were formatted after regression; production sources were unchanged.
- Focused read-only code review found three Important issues: premature flow refresh, ID ordering overriding weakness rank, and context lookup before mounted. All three fixed; follow-up review found no residual Important/Critical issue in that scope.
- Inspected rendered Flutter goldens at 360 by 800 with Thai text scale 1.8. Hub, clinic, score and quiz feedback are scrollable and actions remain reachable. These are synthetic widget renders, not physical-device screenshots.
- One new clinic integration fixture initially waited on Drift inside the widget fake clock. Stopped only its identified test-owned runner/compiler/tester processes, moved fixture work to tester.runAsync, and reran successfully with a bounded timeout.

## Files

Production:
- lib/features/learning/application/learning_use_cases.dart
- lib/features/learning/data/drift_learning_repository.dart
- lib/features/learning/domain/learning_repository.dart
- lib/screens/choose_mode_screen.dart
- lib/screens/weakness_clinic_screen.dart
- lib/screens/quiz_screen.dart
- lib/screens/score_screen.dart
- lib/screens/ghost_shadow_duel_screen.dart

Verification:
- test/features/learning/learning_use_cases_test.dart
- test/features/learning/drift_learning_repository_test.dart
- test/screens/choose_mode_screen_test.dart
- test/screens/weakness_clinic_screen_test.dart
- test/screens/quiz_screen_test.dart
- test/screens/learning_loop_layout_test.dart
- test/screens/goldens/learning_hub_large_text.png
- test/screens/goldens/weakness_large_text.png
- test/screens/goldens/score_large_text.png
- test/screens/goldens/quiz_feedback_large_text.png

Plan: [Implementation plan](../superpowers/plans/2026-10-18-evidence-led-learning-loop.md)
Input: [Feature study](../research/2026-10-18-duolingo-alltcas-feature-study.md)
Regression log: C:/Users/Phet/.codex/tools/rea/evidence/lexiquest-learning-loop-2026-10-18/regression-final.log

## Boundaries and next verification

No APK build/install, physical-device run of this change, full repository regression, or production backend validation was performed. Research collection/enrollment/upload and deployment settings remain unchanged. This is engineering verification of the learning-flow change, not evidence of learning efficacy or research rollout readiness.

The meaning feedback comes from the user's local vocabulary. Rich distractor explanations, contextual dictionary lookup, a data-backed curriculum map, durable resume, AI responses, notebooks and multiplayer remain outside this change. The exploratory competitors' APKs, content and raw captures remain external to Git.

Existing unrelated changes were preserved (.gitignore, AGENTS.md, README.md, earlier field notes and untracked work). No task-owned build/test process is intentionally left running.

Next executable step: build the existing approved local test configuration and exercise hub → quiz → feedback → score → mistake practice → hub on a test device, with synthetic vocabulary and research upload disabled. Any broader feature work should use the original approved catalog and current schema ledger.
