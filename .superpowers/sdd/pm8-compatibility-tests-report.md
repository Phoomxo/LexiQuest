# PM8 compatibility test handoff

Exact worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch: `codex/pair-matching-pm0-pm8`.

Owned files only:

- `test/features/learning/pair_matching/pair_matching_compatibility_rollout_test.dart`
- `test/features/learning/pair_matching/pair_matching_owner_command_test.dart` (subsequently assigned bounded command controls)
- `.superpowers/sdd/pm8-compatibility-tests-report.md`

No production code, existing tests, Git/index, Flutter/Dart/pub/build/generator commands, or generated registrants were changed by this helper. The existing seven platform registrant changes predated this assignment and were preserved. Main implementer owns all serialized tooling and source fixes.

## Focused compatibility coverage (21 cases passed within first combined run)

- Five explicit legacy activity schema1–5 fixtures are converted from the real canonical legacy writer's initial receipt, then restored through `MatchingModeAdapter.prepareSession`. Version1 also uses the historical activity-event envelope1. Assertions preserve identity, labels/word order, bounded original two-minute deadline, zero fabricated attempts, append-only historical bytes and default schema5 output. Current registration remains matching implemented-off.
- Four progressed Pair codec1–4 fixtures preserve a real committed correct answer, evidence identity and a selected next prompt. Every progressed receipt in the canonical chain is represented using the historical exact shape. The real current `preparePairSession` recovers the chain; the next correct answer uses codec4 with elapsed coverage still null. This explicitly prevents retrospective measured-time invention.
- Strict initial activity schema6 has no codecVersion; actual measured atomic start adds separate codec4 zero-coverage admission. Restore preserves initial and operation bytes.
- Actual legacy reader rejects current initial, frozen-pending, and terminal-presented Pair checkpoints without changing session/event/attempt/outbox bytes. A current reader still recovers the same state. This exercises the current explicit legacy API; it is not evidence about a deployed historical binary.
- Unknown activity7, unknown progressed codec5, unknown key and a legacy-shaped map falsely labeled6 are rejected without durable rewrites.
- Default internal capability refuses an actual fresh Pair write with no durable changes. A real unrelated Meaning Quiz answer succeeds through the unchanged default registry; explicitly enabled internal capability then writes the new Pair state. Repeating an exact accepted start after internal-off preserves bytes and creates no new session.
- Actual `DriftSyncStore.claimPending` with the default attempts writer1 must reject a declared Pair answer and roll back the entire claim while retaining ordinary outbox data. Explicit `SyncPayloadRollout.answerAttemptV2()` then claims that same canonical answer as payload2. This is independent of activity6/codec4/start-envelope versions and uses no network.
- Two actual `ProductionFeatureGate(Feature.quiz)` widget cases hold the canonical answer or terminal close, disable the parent gate and internal starts, verify disposal and accepted-operation drain, then reopen `PairMatchingExperienceHost.recover` directly while starts remain off. The original evidence/terminal identities survive; completion has exactly four attempts and one session.

The new file reuses public `PairHarness`, `PairFaultRepository` and lexical composer fixtures. A small barrier wrapper forwards host capabilities to the real Drift repository; it does not implement alternate learning/evidence authority.

## Existing complementary coverage retained

Do not duplicate the full Adventure fixture. `test/features/adventure/presentation/adventure_pair_experience_test.dart` already has `Adventure off replaces decoration on same Pair host without new identity`, which exercises the actual mounted Adventure wrapper and Standard fallback. `test/features/learning/pair_matching/pair_matching_experience_host_test.dart` already tests actual parent-gate disposal during held reveal/timer capture and reopening; the new cases cover the missing answer/close stages. Existing atomic-start tests also prove measured admission and gate-off idempotency. Include these unchanged files in main's compatibility selection.

## Commands for main (sequential; not run by helper)

```powershell
dart format test/features/learning/pair_matching/pair_matching_compatibility_rollout_test.dart
flutter test --no-pub test/features/learning/pair_matching/pair_matching_compatibility_rollout_test.dart --reporter expanded
flutter test --no-pub test/features/learning/matching_mode_adapter_test.dart test/features/learning/pair_matching/pair_matching_checkpoint_codec_test.dart test/features/learning/pair_matching/pair_matching_atomic_start_test.dart test/features/learning/pair_matching/pair_matching_experience_host_test.dart test/features/adventure/presentation/adventure_pair_experience_test.dart test/runtime/production_feature_gate_test.dart --reporter expanded
```

## First combined run evidence

Main executed the following command against the current in-progress PM8 source:

```powershell
flutter test --no-pub --reporter expanded test/features/learning/pair_matching/pair_matching_owner_upgrade_auth_test.dart test/features/learning/pair_matching/pair_matching_owner_upgrade_test.dart test/features/learning/pair_matching/pair_matching_compatibility_rollout_test.dart *> .superpowers/sdd/pm8-integration-first.log
```

Retained output: `.superpowers/sdd/pm8-integration-first.log`. Main reports exit1; the log finishes at `00:17 +39 -2: Some tests failed.` The compatibility file contributes 21 successful cases, beginning at `00:10 +18 -2` and finishing with the accepted-close gate case followed by the aggregate `+39 -2`. This helper independently read the log and counted exactly 21 compatibility case entries, with no compatibility `[E]` or failing-case entry. The two combined-run failures are the anonymous-bind auth fixture assertion and loading/compiling `pair_matching_owner_upgrade_test.dart`; they are outside the compatibility file and remain main-owned recovery work.

This is focused compatibility success inside a failing combined run, not standalone suite GREEN, final frozen-source verification, or whole-PM8 acceptance. The compatibility Dart file is frozen/released; its SHA256 at this handoff is `9ee2e52939abdae0ea5626d544508460df664fbeb4229a63a0a38d5ea1745028`. Main still owns formatting and all later serialized checks. The helper made no further Dart edits and ran no Flutter/Dart commands. Relevant later source changes require affected checks again.

## Read-only R/P command coverage audit for main

- `pair_matching_engine_test.dart:78` already tests exact tile duplicate returning the same state, changed-word same-operation fingerprint conflict, and foreign owner/session/round rejection. This is pure engine coverage with P==runtime owner; it does not establish the actual P→R upgrade boundary.
- `pair_matching_idempotency_test.dart:206` already tests a canonical committed tile command duplicated without new evidence/checkpoints, a changed target under the same operation ID, and a disposed callback. There is no owner merge in that case.
- Current `pair_matching_owner_upgrade_test.dart:139` exercises a real merge, a newly restored coordinator bound to R admitting a P-scoped tile, R-owned new evidence, unchanged original plan/start and stale P-coordinator rejection. The file's pending/clear/file-reopen cases additionally preserve original frozen actors; they do not dispatch forged R-scoped commands or post-merge reveal/guided/timer commands.
- `pair_timeout_recovery_test.dart:443` retries an exact persisted extension decision without repeating its entitlement, and the file's disk-reopen matrix covers pause/expire/extend/restart/continueUntimed with measured/null coverage and before/after-write faults. `pair_timeout_recovery_test.dart:227` rejects a detached timer identity. `pair_timeout_race_test.dart:345` fences restart during admitted answer persistence. These use P==R and do not prove changed-action same-ID rejection after owner merge.

Missing PM8-specific controls to add under main's existing owner-upgrade test ownership:

1. After actual P→R upgrade, construct a new tile command with ownerId=R and otherwise valid operation/session/round/revision. Both the pure reducer with plan P and the newly authenticated R coordinator must reject it; compare engine bytes, evidence ID count and canonical SQL snapshots before/after. Accept an otherwise equivalent P command as a positive control.
2. Preserve an exact old P tile/answer command across merge/reopen, dispatch its exact duplicate through live R, and prove no new evidence/rows. Reuse the same operation ID with a changed target or response time to change its fingerprint and require rejection without writes. Rewriting that command's owner to R must also reject, never normalize silently.
3. Exercise post-merge P-scoped reveal and guided confirmation through live R, with real support/spacing prerequisites and canonical R evidence for the guided answer; add R-scoped and same-ID changed-payload negatives where applicable.
4. Use a real timed accepted session and actual P→R upgrade. Verify P-scoped timer commands retain plan/start/hash/round semantics through expire/extend/restart/continueUntimed and recovery, while ownerId=R is structurally rejected. Exact timer duplicate is idempotent and the same operation ID with a changed action/fingerprint is rejected without changing timer entitlements or SQL.

`pair_matching_engine.dart:502` already requires command.ownerId==plan.ownerId before duplicate comparison, and coordinator `_decideTimer` retains that structural requirement. This audit identifies missing acceptance evidence, not a demonstrated production defect; no engine/source edit was made or recommended solely from the audit.

## Assigned follow-up: R/P command test file prepared

Main subsequently assigned a separate new `pair_matching_owner_command_test.dart` to close those four specific evidence gaps. Five cases are authored and API-inspected, but have not yet been run by this helper or reported passing:

- Actual canonical merge, real R coordinator, pure-reducer plus coordinator rejection of R-scoped prompt/answer; equivalent P commands succeed and the new canonical event actor/owner are R.
- Canonical committed P answer, actual merge, physical SQLite close/reopen and fresh authenticated coordinator. Plan/start/attempt/resolution fingerprints remain exact, old P duplicate creates no writes/capture, changed target/responseTime/owner all reject; a subsequent valid P answer still succeeds through R.
- Actual merge then P reveal and explicit guided confirmation with real support revision. R-scoped commands and changed same-ID payloads reject in both pure reduction and canonical coordinator, while exact duplicates remain idempotent and guided evidence is owned/acted by R.
- Two timed cases (historical-null and measured elapsed) preserve an accepted pre-merge expiry, then prove P-scoped extend/expire/restart/continue after merge. Every accepted action has R-owner and changed-action negatives, exact duplicate checks, SQL/capture/engine/timer immutability checks, and final restore with a new paused clock. Full measured elapsed stays150000ms; historical coverage stays null.

This file imports stable public `mergePairOwner`/`planTap` from main's owner-upgrade fixture and `timedPlan`/`clocked`/`decision` from the existing timer fixture. It introduces no runtime source changes, copied upgrade implementation, or synthetic lineage shortcut. Main retains the only Flutter/Dart tool slot and should run:

```powershell
dart format test/features/learning/pair_matching/pair_matching_owner_command_test.dart
flutter test --no-pub --reporter expanded test/features/learning/pair_matching/pair_matching_owner_command_test.dart
```

Both helper Dart files are released/frozen after this preparation. Main may format them and report focused results; this section is not GREEN evidence.

Any later production failure must be reported with the assertion and smallest required source target; this helper is not authorized to change runtime or weaken assertions. Source/build/minimum-reader artifact identities remain root-owned release evidence; no deployed rollout, G4P signatures, physical UAT or production readiness is asserted.
