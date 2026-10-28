# PM8 whole-branch review — engine partition

Verdict: **With fixes / not yet approved**. One Important issue; no Critical or Minor findings. This is the engine partition verdict, not a whole-branch release or G4P decision.

## Reviewed state and scope

- Exact worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch `codex/pair-matching-pm0-pm8`.
- Base `ca123dddc1349acc4ed67bdd8f5476b02165307c`; HEAD `3bdb5f5605e670e8b30628f3f237cd9c0d660ad9` plus frozen uncommitted PM8 files.
- Packet `.superpowers/sdd/pm8-branch-20260907T031355833-engine.diff`, SHA256 `4dc4b58341d8099272e618bc75611f33d97b7c94f0a86ff439f6ce3dcfafc0d1`; all 27 assigned files read in nonoverlapping 700-line chunks through EOF. The packet's Git stat describes 26 tracked files; its appended new owner-command test is the 27th assigned file.
- Manifest `.superpowers/sdd/pm8-branch-20260907T031355833.manifest.json`: independently checked all 27 current raw file hashes against the engine entries; zero mismatches.
- Applied requesting-code-review/code-reviewer.md, the common final-review brief, PM8 integration/owner contracts including addenda, Checkpoint 7 PM0–PM8 and approved design sections 21.1–21.6.
- Covered source composition, exact 4/6 deterministic plan, atomic start, pure reducer and evidence identities, repair/support/star policies, active clock, checkpoint codec/budgets and runtime-R/immutable-P coordinator, plus all 15 assigned test files.
- Narrow external reads only: actual Pair answer/checkpoint/recovery/close repository admissions; purpose actor/configuration authorization interface; actual `PairHarness`/`PairFaultRepository` and `mergePairOwner`/`planTap` helpers; captured-close use-case chain. No source/test/build/scanner execution or Git mutation. This report is the sole written file.

## Strengths

- Immutable source and start serialization bind exact content, direction, order, seed and owner namespace. Source filtering merges provenance before ranking, rejects ambiguous visible labels and preserves explicit density fallback rather than silently filling a board.
- The coordinator persists frozen pending evidence before canonical answer insertion, preserves exact IDs/contexts/timestamps through retry and commits the clear receipt separately. The inspected actual test helpers wrap real Drift persistence, including file reopen and before/after-write fault injection.
- Runtime R and immutable command P remain separate. The new owner-command tests exercise actual owner upgrade, changed duplicate rejection, R evidence capture and unchanged P fingerprints across disk reopen.
- Clock leases, decision fingerprints, nullable full elapsed, bounded repair and completion reserves have meaningful current tests. Timer expiry is neutral, extension entitlement survives restart, optional persistence cannot consume required answer/terminal capacity, and stars stay a derived descriptive result.

## Issues

### Critical

None found in the assigned partition.

### Important

1. **Normal completion can persist after its authenticated runtime owner is invalidated.**

   - Primary location: `lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart:903–906` (`_finishRecovery`).
   - Trigger: a complete Pair board has persisted its terminal intent; the user switches away from runtime owner R while the subsequent close is awaiting owner binding or a queued repository transaction. A normal owner switch can deactivate R while leaving the session owned by R. The coordinator invokes `completeSession` or `close.finish()/retry()` and checks `_requireLive()` only after that call returns.
   - Actual downstream path: `PendingLearningSessionClose._executeFinish` awaits the cached owner binding at `lib/features/learning/application/learning_use_cases.dart:177`, then `_finishCapturedSessionClose` directly invokes the generic `repository.finishSession` at line 1331. `lib/features/learning/data/drift_learning_repository.dart:2323–2367` looks up the supplied owner/session and writes `completed`, terminal time and achievement projections without checking the sole active owner or strict accepted Pair terminal/lineage inside its transaction. A post-await coordinator rejection cannot roll back that committed write. The optional coordinator runner is a function callback, not an internal canonical transaction/owner guard.
   - Impact: a stale close can mutate R's durable completion/projections after runtime authorization changes. This violates the binding PM8 requirement to reauthenticate runtime R at collection/close boundaries and inside writes. The configured-unavailable completion path already supplies this protection (`completeUnavailablePairSession`), but ordinary completion does not use that path.
   - Fix: route ordinary Pair close through a canonical transaction that authenticates current R and the exact accepted complete/terminal snapshot before mutation and rechecks before commit, while preserving existing legacy close semantics and exact idempotent receipts. A caller-side check alone leaves the queued-write race open.
   - Verification needed: a real Drift close-boundary owner-switch race must leave session state, terminal identity and projections unchanged on rejection; retain live-R success and lost-ack/rehome controls. This reviewer did not run a reproduction, in accordance with sole-tool-owner restrictions. The boundary reviewer independently confirmed the downstream source trace. The UI reviewer confirmed the host lease is in-memory and `completeRecovery` delegates through controller/learning without an enclosing database owner transaction; it does not remove this race.

### Minor

None.

## Current covering evidence and remaining gates

- Inspected `.superpowers/sdd/pm8-host-race-affected-20260907T031244596.metadata.json` and the actual log tail: **971 tests passed**, exit 0, 239.3704179 seconds, complete Pair directory plus the listed touched boundary/UI/identity suites. Metadata records 1,045 inputs and no differences; before/after manifest SHA256 both `3271873c56aacfd7666dc6b734e2c7517e5926eed7c6347288fcb856c7764a1e`. The log contains nine inherited Drift warnings.
- Inspected `.superpowers/sdd/pm8-host-race-analyze-20260907T031131371.metadata.json` and log: `flutter analyze --no-pub lib test`, exit 0, `No issues found!` (analyzer-reported 15.3 seconds; wrapper duration 18.1092873 seconds).
- These current passes do not prove the normal-close race above. Earlier PM1–PM7 counts and the older PM8 implementation-report total are supporting history only.
- Root's frozen-source full default/serial suites, policy/dependency gates and verified APK remain pending after review. External physical-device/learner UAT, five G4P role signatures, research authority/provisioning and rollout remain pending/NotRun. No production readiness, activation, merge or deployment approval is implied.

## Assessment

The assigned engine implementation is cohesive and the recovery/budget tests are substantial. Fix or conclusively disprove the normal-close owner race before approving the engine partition; then run the focused real-boundary regression on the corrected source and include it in root's final frozen-source verification.
