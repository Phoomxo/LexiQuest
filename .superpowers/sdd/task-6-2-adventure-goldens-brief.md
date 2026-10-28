# Task 6.2 corrective brief — deterministic Adventure golden coverage

## Objective

Add real screenshot-golden coverage for the shipped Adventure surfaces. Existing widget/accessibility assertions are valuable but do not satisfy the visual-regression gate because the repository currently contains no `matchesGoldenFile` coverage.

## Required scenes

Create a small, deterministic set that materially covers the visual contracts:

1. Adventure Home/Map in light theme with one current mission, the three-node journey, companion, mission CTA, and always-visible Standard escape.
2. Adventure Home/List in dark + high-contrast + reduced-motion with 200% text at a narrow but supported viewport, proving no clipping/overflow and equivalent node meaning.
3. Adventure Result with separate Learning/Effort/Engagement sections and pending canonical reward state.

## Constraints

- Use the repository's `M3Theme` and bundled `NotoSansThai` font; load fonts deterministically in the test.
- Fix viewport size, device pixel ratio, locale/direction, text scaler, brightness, high-contrast, and animation policy explicitly.
- No network, clock, random seed, platform plugin, async projection, or dynamic system font input may affect pixels.
- Golden files must live beside the focused test under a stable `goldens/` directory and be committed.
- Keep semantics/widget assertions; goldens supplement rather than replace them.
- Generate with `flutter test --update-goldens <focused test>`, rerun without update, inspect each PNG visually, and document image dimensions/hash.
- Do not weaken `goldenFileComparator`, tolerance, or pixel comparison globally.
- Do not change production UI merely to make an unexplained image pass. If an actual layout defect appears, report it for a separate reviewed fix.

## Likely files

- Add `test/features/adventure/presentation/adventure_visual_golden_test.dart`
- Add PNGs under `test/features/adventure/presentation/goldens/`
- Reuse production fixtures/models from existing Adventure presentation tests where practical.

## Global constraints

- Work only in `C:\Users\Phet\Documents\LexiQuest\.worktrees\adventure-motivation-plan`.
- Use `apply_patch` for source edits; the Flutter golden command may generate/update PNG artifacts.
- Never edit or stage:
  - `lib/features/sync/domain/sync_entity.dart`
  - `lib/learning/storage/learning_database.g.dart`
- No research, Pair, schema, generated Dart, feature-catalog, or Standard behavior changes.
- Commit only the focused test and golden PNGs; provide a report with commands, hashes, visual QA notes, and commit hash.
