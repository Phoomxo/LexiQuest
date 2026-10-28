# PM8 close classification V2 — bounded final review

**Verdict: With fixes.** Legacy completion regression และ missing-checkpoint downgrade ที่ทดสอบแก้แล้ว แต่ยังพบ Important หนึ่งรายการใน overflow classification. รายงานก่อนหน้า `pm8-close-correction-review.md` คงไว้ไม่เปลี่ยนแปลง.

## Verified source and scope

- Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch `codex/pair-matching-pm0-pm8`; HEAD independently verified `3bdb5f5605e670e8b30628f3f237cd9c0d660ad9` plus frozen V2.
- Raw SHA256 independently verified: classification delta `375e77e8c70bc1f28a9f81bc25673bada8d4d54ef64494710cd0d84adfe6eef6`; full correction V2 diff `fc18c4e7c91b17f77ca3d138ea038349abf91926895e447d77804e115664399b`; discovered wave V2 manifest `26ee30738bdd874a7f7321b6cf9a7874d6fce759b96cea25cb53d68f3f67c91a`; frozen V2 manifest `671d436da1ae36edad2e9d124fb5e33384d898a3ec19850b82125bc91375f505`.
- All 23 raw current hashes match frozen V2; only repository and actual-host test differ from V1, other 21 unchanged. All 10 wave current and saved-before hashes match wave V2. Repository `53d9719e8cff1477f75bd71d899c905b5eaf2cf6112b1b0c354929b449b22b5b`; host test `d00f1237c77e746358739eac3ec94f9fad1ce6a4f4def1662789026d2341525d`.
- Read complete bounded repository/test delta; narrow named context reads: canonical checkpoint query, Pair session-ID function, current finish method and existing recovery bounds. Reused previous close/transaction review; did not repeat original branch review or independently approve UI/Voice.
- No source/test edits, executable test/build/pub/Dart/scanner tools, Git mutations or production activity. Sole write is this ignored report. No reviewer-owned process remains.

## Resolved

1. **Legacy generic checkpoint completion regression:** `_requiresPairCloseAuthentication` now classifies before calling the strict purpose decoder. Valid generic map state without strict markers returns false, preserving the existing unchanged `matching_mode_adapter_test.dart:3788` accepted-state/collision/finish case. There is no catch-and-reinterpret-as-legacy fallback. The focused GREEN run below confirms this case passes.
2. **Reserved Pair missing/downgraded checkpoint:** `pair:` session IDs always require strict authentication, before the activity-type guard. `pairSessionId` reserves this prefix. Purpose snapshot absence explicitly throws. New tests remove every checkpoint, replace state with generic data or a legacy marker, and require no completion/achievement mutation.
3. **Earlier strict markers under generic latest state:** for nonreserved matching IDs the classifier examines every returned canonical candidate for schema6, startOperation or plan keys. New nonReservedId test leaves the initial strict checkpoint and replaces latest state with generic data; close rejects. This is stronger than looking only at latest checkpoint.
4. **Original owner-close race remains corrected:** V2 keeps canonical in-transaction full accepted-state and sole-owner authentication, exact terminal-time equality, idempotent receipt validation and post-projection owner check. Focused tests retain held logout/switch/inside-close-trigger rollback plus closeBefore/closeAfter/resultRead positive controls. The latter use valid unconfigured strict Pair.

## Open Important — reject candidate overflow before classifying as generic

**Location:** `lib/features/learning/data/drift_learning_repository.dart:2402–2424`; shared query `lib/features/learning/pair_matching/domain/pair_matching_session_purpose.dart:411–423`.

The classifier reuses `checkpointQuery`, which sorts candidates by event_id and returns `LIMIT 65` as the sentinel for the permitted 64-checkpoint bound. Unlike `PairMatchingSessionPurpose.decode:51` and the ordinary recovery reader (`drift_learning_repository.dart:1235–1238`), the classifier does not reject a result exceeding 64. For a nonreserved matching session with at least 66 canonical candidate rows, a strict marker can occur after the first 65 generic candidates. The loop never sees it and returns false, so finish bypasses strict authentication. The bounded source trace establishes the condition; this reviewer did not execute a synthetic reproduction. Normal admission cannot create an over-budget valid chain, but the requested corrupted/nonreserved-history admission must fail closed rather than trust an incomplete candidate set.

**Correction:** after the bounded query, reject `candidates.length > maxActivityRecoveryCheckpoints` before interpreting any state. Keep the bounded query; no unlimited scan is needed. Add a real Drift overflow case with generic candidates before a hidden strict candidate (or directly prove overflow rejection), assert unchanged session/projections, and retain the valid generic completion control. Do not relax generic state assertions or catch strict decode failures as legacy.

**Critical / Minor:** none newly found in this delta. Earlier unrelated branch Minor items are not closed by this review.

## Evidence inspected

- `pm8-branch-classification-red-20260907T035418297.metadata.json` + actual log: exit 1, 7.0769142 seconds, 3 passed / 2 failed. Missing Pair checkpoints wrongly returned a LearningSessionSummary; unchanged valid generic legacy finish threw purpose corruption. These are concrete pre-fix failures.
- `pm8-branch-classification-green-20260907T035511655.metadata.json` + complete actual log: exit 0, 15.0345061 seconds, **11 passed**. Exact filter `cannot downgrade authority|generic checkpoints fail closed|queued normal Pair close|same host retries exact canonical completion`: four corruption cases, unchanged generic compatibility case, three owner races, three exact recovery controls.
- `pm8-branch-analyze3-20260907T035606327.metadata.json` + actual log: `flutter analyze --no-pub lib test`, exit 0; no issues, reporter 10.3 seconds / wrapper 13.1735888 seconds.
- Main's new frozen 19-entry affected suite remains pending at dispatch/review. No final count, exit or no-drift result is claimed. The focused GREEN does not cover the overflow condition above.

## Recommendation

Resolve the bounded overflow admission issue and provide its focused result/new source identity for re-review, then complete the main-owned frozen affected suite and release checks. This verdict is scoped to close/classification; it does not grant merge, G4P, physical-device/UAT or rollout approval.
