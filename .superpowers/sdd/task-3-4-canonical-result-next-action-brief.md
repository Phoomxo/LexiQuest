# Task 3.4 corrective brief — canonical Result next action

## Objective

Replace the hard-coded `AdventureNextAction.reviewCenter` with a read-only projection of the canonical Review/SRS queue. Result rendering must remain truthful if no review work exists and must not create, defer, grant, or mutate any queue item.

## Binding contracts

- SRS `AMM-FR-064`–`AMM-FR-070`.
- Task 3.4 step 3: render Review/SRS next action from canonical authority.
- UAT-007/008/011: incorrect needs are owned by Review/SRS, tail repair does not pad, and Result keeps Learning/Effort/Engagement separate.
- Existing `ReviewCenterReader`, `ReviewOwnerIdentityReader`, `ReviewQueueFilter`, and provenance reasons are the canonical source.

## Required behavior

1. Add red tests before production changes.
2. Introduce a narrow Adventure read interface for Result next action and a production adapter over the existing canonical Review Center read interfaces. No Review package may import Adventure.
3. Validate one active owner and reject owner drift before presenting another owner's queue.
4. Deterministic mapping:
   - empty canonical queue -> `AdventureNextAction.none`;
   - queue containing due-SRS work -> `AdventureNextAction.spacedRepetition`;
   - otherwise nonempty canonical review work -> `AdventureNextAction.reviewCenter`.
5. `AdventureResultLifecycleScreen` must resolve this independently of reward-receipt reconciliation. A reward projection failure must not erase a successfully resolved Review/SRS action, and a review read failure must fail closed (`none`) without erasing accepted learning/reward state.
6. Fence stale async results across widget updates/owner/session changes.
7. Production bootstrap/AppDependencies and mission completion must inject the same canonical Review reader/active-owner authority already used by `ReviewCenterUseCases`.
8. The existing navigation callback may open the canonical Review Center for either review action; `none` remains disabled and must not navigate.
9. Keep result axes, supportive copy, receipt behavior, schema, and Standard paths unchanged.

## Likely files

- Add `lib/features/adventure/application/adventure_result_next_action_reader.dart`
- Modify `lib/features/adventure/presentation/adventure_result_lifecycle_screen.dart`
- Modify `lib/runtime/app_dependencies.dart`
- Modify `lib/runtime/app_bootstrap.dart`
- Modify `lib/screens/main_navigation_screen.dart`
- Add application tests and modify lifecycle/bootstrap/navigation tests

## Global constraints

- Work only in `C:\Users\Phet\Documents\LexiQuest\.worktrees\adventure-motivation-plan`.
- Use `apply_patch` for edits.
- Never edit or stage:
  - `lib/features/sync/domain/sync_entity.dart`
  - `lib/learning/storage/learning_database.g.dart`
- Preserve unrelated changes. No research, Pair, schema, generated-code, reward grant, or Review mutation.
- Format only touched Dart files; run focused tests and analyzer; commit only focused files; provide a report with exact evidence and commit hash.
