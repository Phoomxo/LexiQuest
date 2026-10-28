# PM8 close limit V3 — final bounded review

**Verdict: Approved for the close/classification correction.** Resolved the last Important overflow finding. No open Critical, Important or Minor finding in this bounded correction. Earlier reports remain preserved as historical findings; this is not whole-branch release, merge or rollout approval.

## Verified identity

- Exact worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch `codex/pair-matching-pm0-pm8`; HEAD independently verified `3bdb5f5605e670e8b30628f3f237cd9c0d660ad9` plus frozen V3.
- Independently verified raw SHA256: minimal limit delta `0e8847dfe5e24f39f789317d10124ba8d719749e604b7b30f53c68f04ecc4c25`; full V3 wave diff `750f2253b3e165ee87e581ab6f815e465faa89c94321b6e67e8f3a25db274988`; frozen V3 manifest `4e10a9424ddfa8848b6257b69f01f269fed4ced7e70f11f9e16e209fbd156cfc`; wave V3 manifest `7ad34c4213face848cce413eff00102112360a856739cdbdf3890a55de853911`.
- All 23 current file hashes match frozen V3, with only repository and actual-host test changed from V2. All 10 current/saved-before entries match wave V3. Repository SHA256 `27df9287500eebda29fb45603b190630cace88417f1dcc65ed87eacd64f552af`; host test `aabb635e5f10fffe8e583b0f1d7a10112818efa00af4ed9c26a308d0dc758bc3`.
- Read only the minimal three-line guard and actual regression delta, plus evidence/hash checks. Previous close and classification analyses stand for unchanged code. No repeat of original 122-path review; no independent Voice/UI re-review.

## Resolved final Important

`drift_learning_repository.dart:2408` now rejects `candidates.length > maxActivityRecoveryCheckpoints` immediately after the bounded canonical query and before interpreting states. The shared limit is 64 and the query returns at most 65. Therefore any overflow visible through the sentinel rejects; no truncated candidate set can be classified as generic merely because strict markers occur later. The query stays bounded and valid generic state is unchanged.

The real Drift regression `pair_matching_experience_host_test.dart:344` renames the session to a nonreserved ID, keeps its original strict event, and inserts 65 generic candidates sorting before that event. It explicitly proves 66 stored events, a returned window of exactly 65, and no schema6 marker inside the window. It then requires `finishSession` to throw, preserves the session row and verifies no achievement unlock. This directly exercises the reported hole, not a mock classifier assertion.

The V2 legacy generic completion fix, reserved missing/downgraded history rejection, all returned candidate inspection, full strict terminal authentication and in-transaction owner checks are unchanged. Current focused verification includes the entire host, legacy adapter, purpose and repository files. The original shared owner-close Important, introduced legacy compatibility Important and final overflow Important are all resolved within this correction chain. No new severity finding remains in scope.

## Exact evidence inspected

- RED `pm8-branch-limit-red-20260907T040250448.metadata.json` and complete log: one failure, exit 1, 7.0066942 seconds. The actual pre-guard close returned a LearningSessionSummary instead of throwing, confirming the reported overflow bypass.
- V3 GREEN `pm8-branch-final-focused-20260907T040344127.metadata.json` and actual log: **142 passed, exit 0**, reporter 43 seconds / wrapper 49.4380382 seconds. Exact four files: Pair experience host, matching mode adapter, Pair session purpose and Drift learning repository tests. Includes overflow regression and retained owner-close/retry controls. Metadata records 1,045 inputs and `inputDifferences: []`; both raw manifest files independently hash to `7aea13e1313474105967c1bed57ca9708325794fccaebbf2e6cc6d919deb4408`.
- V3 analyzer `pm8-branch-analyze4-20260907T040514405.metadata.json` and actual log: `flutter analyze --no-pub lib test`, exit 0, no issues, reporter 13.1 seconds / wrapper 16.1368197 seconds. Analyzer completed before this verdict.
- Prior V2 affected evidence independently inspected: `pm8-branch-affected2-20260907T035752491.metadata.json` plus final log, **1,376 passed, exit 0**, wrapper 255.817088 seconds, exact 19-entry affected argv. All 1,045 inputs unchanged; before/after raw manifests independently hash to `72c048f341c91ad3b5c0e0ab25f3ce5ca1d8c8791bff1de15b475b9ce04abe41`. This run precedes the guard and is supporting V2 coverage, not a claim that all 19 entries were rerun on V3.

## Handoff

Proceed to root's final current-source default/serial and release verification. No third broad affected rerun is requested solely for this bounded guard: the actual RED and V3 four-file GREEN cover the correction, while root's final suites will supersede partial evidence. Full final release suites, APK, physical-device/learner UAT, G4P signatures and rollout authority are not established here.

No source/test edits, Flutter/Dart/pub/build/scanner execution, Git mutation or production activity by this reviewer. This ignored report is the sole new write; both previous reports remain unchanged. No reviewer-owned process remains.
