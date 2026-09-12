# R15 execution checkpoint

Worktree: `C:/Users/Phet/.codex/worktrees/fff3/LexiQuest`
Branch: `feature/r15-autonomous-fff3`
Approved baseline: `8c160f87d77d8beb8ace2d8f2b7b0e92acb297ac`.
Initial task checkout was clean/detached at `7b8ac6cc`; created this task-owned
branch at the approved baseline without modifying another worktree.

## R15.0 reconciliation

Imported exactly the five approved R15 source documents; SHA-256 matches the
originals in 4366 (originals retained). Inventory of every worktree, branch,
HEAD and changed path is in `2026-09-12-r15-worktree-inventory.json`.

Disposition:
- 02fa / 4366: same approved implementation, already incorporated. The five
  untracked documents from 4366 are now incorporated byte-for-byte.
- complete-field-trial-release navigation delta: overlapping older shell and
  FieldFeatureRegistry; current source has its successor registries and Today
  replay. Do not merge its 158 insertions/75 deletions into the newer shell.
- adventure-motivation-plan sync/generated database: no textual sync entity
  delta in current diff; generated/history branch material is not an R15 fix.
- e559 and release worktrees: platform/plugin generation is unrelated to the
  current local package, not imported. Main checkout documents/auth image,
  f00a release inputs/configuration, pr3 OSV material are unrelated, not imported.
- Clean historical worktrees: retained as historical branches, no inferred
  integration from names or commit recency.
- Useful unique tooling: `verify-scope.ps1` exists at initial checkout commit
  7b8ac6cc but is absent from approved Prototype 3. Imported only that runner,
  adding explicit validated test paths and broad shared-input fingerprints for
  the feature architecture. No backend/release suite was invoked.

Prototype 3's unchecked commit/push checkbox is historical: 8c160f87 exists;
remote state was not fetched or verified. Historical 826/891 results do not
count as verification here. Competitor observations/limitations are preserved
in the imported source register and manifest; no competitor assets ship.

## R15.1 actual baseline defect and verification

Requirements: DATA-03/04/05, SYS-01/02; targeted navigation/history, owner deletion,
profile semantics and file-backed lost-ack recovery. Existing replay integration
is retained, not reimplemented. No schema/interface/authority change.

RED: initial five-suite run: 70 passed, 4 failed. Failure was
`ContentQualityFailure(invalidByteLength)` before packaged replay admission.
Windows `core.autocrlf=true` converted signed/pinned JSON LF into CRLF:
starter-book was 235 bytes instead of 234; SHA was dbc11652..., expected a92b4c2e....
Fix: `.gitattributes` pins content JSON to LF; 25 checked-out JSON files restored
to LF and individually verified byte-identical to their HEAD Git blobs. Content
validators, manifests and historical data remain unchanged.

GREEN: `./tool/cli/verify-scope.ps1 -Level Targeted -Area Learning -Resume
-TestTargets @('test/screens/main_navigation_screen_test.dart',
'test/screens/learning_history_screen_test.dart',
'test/features/progress/personal_learning_profile_test.dart',
'test/scenarios/file_backed_sync_recovery_test.dart',
'test/features/account/local_data_deletion_test.dart')`
returned exit 0, 74 tests passed, Flutter reported 24 seconds (runner 30 seconds).
Source HEAD above; input fingerprint
`f2335e636377327fee4533d4c31c73c060b022981b46b7d5aee89c6029f1e094`.
Logs: `build/verification/8c160f87d77d8beb8ace2d8f2b7b0e92acb297ac/`:
`r15-baseline-red.stdout.log`, `r15-baseline-red.stderr.log`,
`Explicit-Flutter-tests.stdout.log`, `targeted-learning.json`.
Runner contract RED rejected old target selection; GREEN validates exact targets,
shared asset/source fingerprint boundary and missing-target rejection.
`git diff --check` passed. Generated platform files have line-ending-only status
churn and are excluded from commits. No UI changed, so no new visual claim.

## Queue and external acceptance

R15.0/1 baseline/reconciliation accepted at the bounded scope above. Next is
R15.2 Pair feedback (A-PAIR-01–09), followed by R15.3–10 in order; these are NOT
complete. Later package-specific acceptance supplements this baseline.
External-not-run: live AI teaching quality, physical camera scenes/resources,
human speech/TalkBack/usability and two-device live sync. Real research enrollment,
upload, deployment, paid calls, push and merge remain off. No task-owned process
remains after the baseline command. Rollback: revert the package commit; no data
migration or user-data repair is required.
