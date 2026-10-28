# PM8 close correction — bounded review

**Verdict: With fixes.** ช่อง normal-close owner race เดิมแก้ใน canonical transaction แล้ว แต่ correction ปัจจุบันเพิ่ม legacy compatibility regression ที่ต้องแก้ก่อนอนุมัติ. ไม่ใช่ whole-branch/release acceptance.

## Reviewed identity and scope

- Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch `codex/pair-matching-pm0-pm8`; independently verified HEAD `3bdb5f5605e670e8b30628f3f237cd9c0d660ad9` plus frozen uncommitted correction.
- Independently verified raw SHA256: correction diff `3955156c4b3633afc36b43ca4c5e025d2cf6b25fbfece86551122f26088dbec8`; wave manifest `d6d979f1e11ce1d12804962b49923505e1e2dc644d41a6ef13dcc9a5b86ea798`; frozen manifest `6785c321b489f23467d6f9164693e6a0ba93a46b2ec6842fab0bdb0a7dac374e`.
- All 23 current raw source hashes match the frozen manifest. All 10 wave current hashes and 10 saved before hashes match the wave manifest. Reviewed repository hash `ea51e4455dc7ba15fd992f870f2c4089872156031942364a174869e8fee436a4`; actual-host test hash `1670742f8944b9db61256704e904669465374da45bed04134dfc9e2d4029f41b`.
- Applied active AGENTS, requesting-code-review/code-reviewer and receiving-code-review; read current review plan/common brief and prior engine/boundary reports. Scope is the close correction and its actual tests, with named reads of purpose reader/decoder, checkpoint validation, achievement rebuild and actual PairHarness. No repeat of initial 122-path review or independent Voice verdict.
- No source edits, test/build/pub/generation/scanner execution, Git mutation or production action. This ignored report is the sole written file; no reviewer-owned process remains.

## Resolved finding

**Shared prior Important: ordinary strict Pair close after runtime-owner invalidation.** `drift_learning_repository.dart:2323–2386` now reads the accepted strict snapshot and calls `_inspectPairDisposition(requireConfiguration: false)` within the actual finish transaction before both mutation and completed-row idempotent return. The helper requires exactly one active owner matching runtime R (`:1754`), authenticates full checkpoint prefix/actor/configuration and canonical attempts/source decisions (`:2814–2963`), and returns complete only with no outstanding pending occurrence. Finish requires the exact terminal timestamp. Missing terminal fails equality; corrupt purpose throws rather than returning a trusted snapshot. Existing completed-row checks still require the same stored timestamp.

The last owner check after achievement rebuilding (`:2380`) throws inside that same transaction, rolling back the close and projections if a trigger deactivates R. Full accepted engine/terminal authentication occurs before writes; the post-projection check specifically reauthenticates owner. I do not describe the latter as a second full engine/terminal inspection. Canonical achievement rebuilding does not rewrite Pair checkpoint/engine identity. Configured unavailable public APIs retain the default `requireConfiguration: true`; only generic normal close opts out, preserving accepted unconfigured strict Pair.

Meaningful actual tests: `pair_matching_experience_host_test.dart:344` rejects incomplete accepted board with unchanged session/empty achievements. At `:482–550`, the real recovered host solves all four pairs, holds the actual repository finish call, then logs out, switches owner, or installs an AFTER UPDATE completion trigger that deactivates the owner. The before/after snapshot compares learning_sessions, events_v2, answer_attempts, achievement_unlocks, outbox_operations and local_owners; it stays equal after attempted close and host disposal, and no result is shown. This tests rollback at the write boundary rather than only an in-memory lease. Existing `:625–691` closeBefore/closeAfter/resultRead controls recover exact terminal identity and retain four canonical answers. PairHarness defaults to no configuration, so those controls exercise valid unconfigured strict6 completion and idempotency.

## Open findings

### Important — new legacy completion regression

**Location:** `lib/features/learning/data/drift_learning_repository.dart:2340` (unconditional purpose read).

Generic finish now decodes every matching checkpoint prefix through `PairMatchingSessionPurpose.decode`, although the existing generic checkpoint API accepts bounded opaque legacy states. The actual `matching_mode_adapter_test.dart:3788` case prepares legacy matching, verifies owner/bounds rejection, appends the accepted generic state `{'identity': 'accepted'}`, verifies collision rejection, then legitimately calls `learning.finishSession` at `:3873`. The newly unconditional purpose decoder rejects that historical/generic state before normal completion. The running affected log independently shows this exact case failing at lines 684–687 with `Persisted Pair purpose is unavailable or corrupt`, through the purpose reader and decoder line 262.

This is a demonstrated new compatibility failure, not an expected RED case to waive. The correction must determine strict6 participation from authoritative checkpoint history before applying strict Pair purpose/terminal admission, preserving generic/legacy completion semantics. Do not catch a failed strict decode and treat it as legacy: a malformed strict6 or mixed prefix must still reject. Keep this existing test and assertions, rerun it together with strict incomplete/owner-race/normal-success controls, and re-review the changed discriminator against raw source hashes.

### Critical / Minor

None newly found in this bounded correction review. Earlier boundary Minor items remain outside this correction scope and are not implicitly closed.

## Exact evidence inspected

- `pm8-branch-host-red-20260907T033355332.metadata.json` and actual log: exit 1, 12.4767791 seconds; all three queued close owner cases fail before correction, plus the independent covered-route clock case (four failures total).
- `pm8-branch-focused1-20260907T034212483.metadata.json` and actual log: exit 1, 49.1739085 seconds, 114 passed / 2 failed. The three close owner cases and all three normal exact-completion recovery cases pass. The two failures are explicitly the narration failedStop case and Voice provider cleanup case, not close tests. This run is not reported as wholly green.
- `pm8-branch-focused2-20260907T034429021.metadata.json` and actual log: exit 0, 8.5941374 seconds, 2 passed; exact name filter `failedStop|provider failure retains cleanup`. This resolves that focused pair of historical failures but is not a full rerun.
- `pm8-branch-analyze2-20260907T034636401.metadata.json` and actual log: `flutter analyze --no-pub lib test`, exit 0; no issues found, reporter 11.2 seconds / wrapper 14.1077375 seconds.
- Current `pm8-branch-affected-20260907T034837852.log`: observed legacy failure above during the parent's ongoing affected suite. No final exit/count/input-drift evidence was supplied at this review; no pending suite is claimed passed.

## Recommendation / next executable step

Root/main should complete and preserve the running affected evidence, correct the strict6 discriminator without weakening legacy or strict rejection tests, freeze updated source and rerun the affected compatibility + close controls. Re-review that bounded delta before counting this correction approved. Broader final suites, APK, physical-device/learner UAT, G4P signatures and rollout authority remain separate and are not established by this report.
