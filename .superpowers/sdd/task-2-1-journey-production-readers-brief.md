# Task 2.1 corrective brief — production Journey readers and partial degradation

## Objective

Close the audited Task 2.1 production gap without inventing Adventure-owned progress:

- production `AdventureJourneyUseCases` must receive canonical supplemental readers for Achievement, Reward, History, and pack completion;
- every supplemental read must be deterministic and owner-scoped;
- one supplemental failure must not crash the projection or suppress a still-valid primary mission;
- only nodes that depend on the failed supplemental authorities may become unavailable/corrupt;
- Adventure must remain read-only and must not add any table, row, cache, or `adventure_progress` state.

## Approved contracts

- SRS `AMM-FR-026`–`AMM-FR-033`, especially FR-026 and FR-033.
- SDS 3.4 steps 5–9: canonical readers, catalog mapping, dependent-node degradation, exactly one primary mission, immutable fingerprints.
- World v1 has exactly `resume-review`, `today-mission`, and `next-preview`; no durable branching choice exists.
- Do not fabricate a completed Adventure node from generic historical activity. Supplemental facts may affect dependency state and deterministic fingerprint; completed-node mapping is allowed only where a canonical source proves the exact catalog node identity.

## Canonical source seams

- Achievement: existing canonical progress read model (`ProgressUseCases.loadForOwner`) or an equally narrow read-only interface.
- Reward: `RewardAccountReader.loadForOwner`.
- History: `LearningHistoryReader.list(HistoryFilter)`; reuse the production `DriftLearningHistoryReader` instance already created at bootstrap.
- Pack completion: derive only from canonical terminal history with a pinned pack identity; do not infer Adventure origin.

## Required behavior

1. Add focused red tests before implementation.
2. Expose a read-only way for composition/architecture tests to prove that exactly the four supplemental authorities are configured; do not expose mutable reader collections.
3. Add deterministic adapters with bounded source reads and canonical fingerprint serialization/order.
4. Empty canonical sources return `empty`; valid nonempty sources return `ready`.
5. Source read failure is converted to a bounded supplemental dependency state and deterministic fingerprint. Wrong-authority/corrupt fact output must be contained as `corrupt`, not crash the Host.
6. A failed supplemental authority degrades `next-preview` only in world v1. A current Today snapshot still retains its primary resume/review/recommendation mission. A stale/corrupt required Today dependency still blocks the affected mission as before.
7. Production bootstrap must wire all four supplemental authorities using the same canonical instances already composed there.
8. Add/extend bootstrap and architecture tests proving production wiring and no Drift import in the Adventure domain/application projection files.
9. Do not alter research, Pair Matching, schema, generated files, or Standard behavior.

## Likely files

- Modify `lib/features/adventure/application/adventure_journey_reader.dart`
- Add a focused application adapter file under `lib/features/adventure/application/`
- Modify `lib/runtime/app_bootstrap.dart`
- Modify `test/features/adventure/application/adventure_journey_reader_test.dart`
- Add adapter tests under `test/features/adventure/application/`
- Modify `test/runtime/app_bootstrap_test.dart`

## Global constraints

- Work only in `C:\Users\Phet\Documents\LexiQuest\.worktrees\adventure-motivation-plan`.
- Use `apply_patch` for edits.
- Never edit or stage these stat-only/content-equal paths:
  - `lib/features/sync/domain/sync_entity.dart`
  - `lib/learning/storage/learning_database.g.dart`
- Preserve unrelated/user changes.
- Run `dart format` only on touched Dart files.
- Run focused tests and `flutter analyze` on the changed scope.
- Commit only the focused task files and write a report listing changed paths, tests, analyzer output, and commit hash.
