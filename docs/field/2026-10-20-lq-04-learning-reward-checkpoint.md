# LQ-04 learning/reward compatibility checkpoint

- Date: 2026-10-20 (Asia/Bangkok)
- Chat/card: LQ-04 / bounded XP compatibility and SRS retry
- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch/HEAD: `feature/associative-reading-loop` / `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`
- Authority: LQ-00 section `LQ-02 acceptance and LQ-04 slot transfer` grants exclusive production writer and serialized Flutter slot.
- State: engineering-complete for XP-read isolation / SRS retry; reviewed, locally attested, ready for LQ-00 integration acceptance.
- Budget: original LQ-04 cap 38 / program cap 250 retained; no new budget/reset.

## Compatibility policy recorded before reward writes

Raw answer attempts and reward purchase/equip transactions remain unchanged. No new schema, transaction payload/type, grant rate, shadow-policy activation, or retrospective repricing is authorized in this slice.

| Synthetic legacy fixture | Before | Required after |
| --- | --- | --- |
| Owner A learning credits 200, ocean purchase 80, ocean equip | displayed spendable balance 120; ocean owned/equipped; mixed ledger sum 120 | XP 200 / level 11; balance 120; ocean owned/equipped |
| Same fixture rebuilt/reopened/replayed | one purchase and equip evidence; same rights | identical raw rows, balance, rights; no duplicate grant/answer/SRS update |
| Owner B learning credits 10, attempted ocean purchase 80 | old rebuilder skips unaffordable purchase; balance 10, no ocean ownership | owner A unaffected; preserve valid old treatment or stop conversion for a policy decision |
| Duplicate raw purchase of the same item | old rebuilder accepts only one debit/ownership | do not blindly SUM duplicate raw debits into a lower balance |
| Invalid catalog/amount or conflicting idempotency | rejection in existing validation | rejection remains; no relaxed validation |

### Concrete conversion dependency

Current positive earnings exist only in `PointsLedgerEntries`; `RewardTransactions` contains purchase/equip records. For the first fixture its raw SUM is **-80**, not the valid legacy balance **120**. A direct balance-source switch loses 200 credits. Representing credits in RewardTransactions requires a new positive transaction contract, but sync currently permits only purchase/equip (`drift_sync_store.dart`, transaction validation). Duplicate/unaffordable raw purchase records also cannot simply be summed because the old projection skips them.

Therefore full sole-coins-authority conversion is held for LQ-00/LQ-07 contract and shared-file approval. This is a bounded decision on conversion, not a stop to independent work. No reward write/rebuild is changed until that decision. This slice can exclude legacy `rewardPurchase` debits from XP reads while retaining their historical rows and current reward behavior.

LQ-00 disposition received during execution: **C-COIN is a separate follow-up with LQ-07**. Sync and Firestore rules both permit only purchase/equip. This slot is narrowed to XP read isolation and SRS retry; no local credit transaction may be added without complete transport/policy coverage. LQ-05 purchase/equip integration stays gated on C-COIN, not on this XP fix.

## Cards and acceptance

1. **Done — XP read compatibility:** exclude legacy rewardPurchase debits from progress XP/level. Real-DB tests cover valid purchase/equip, replay/rebuild/reopen, other-owner isolation, and invalid/conflicting legacy rejection. Existing reward balance/ownership behavior remains the baseline.
2. **Done — SRS retry:** allocate ID/UTC timestamp/response time/rating before write, preserve the exact payload through failure-before-write and lost acknowledgement, clear only after acknowledged success and card transition. Do not change session/result/streak/event/catalog semantics. Real-DB widget tests assert one attempt, one SRS update and one correct-answer reward, plus repository conflict rejection.
3. **Done — Review/attest:** inspected connected callers and final diff, ran serialized subsystem checks and targeted analysis/formatting, recorded hashes/process release and section 13.5 handoff.

## Scope

Actual writes: `lib/features/progress/data/drift_progress_queries.dart`, `lib/screens/srs_flashcards_screen.dart`, `test/features/progress/legacy_reward_xp_compatibility_test.dart` (new), `test/screens/srs_flashcards_screen_test.dart`, this checkpoint (new). No reward write/rebuild module changed. Existing dirty learning and account/import work is preserved. Shared bootstrap/routes/schema/sync/registries/dependencies remain outside this writer window.

## Behavioral evidence

- XP RED: `flutter test --no-pub test/features/progress/legacy_reward_xp_compatibility_test.dart --reporter expanded` → exit 1, **0 pass / 4 fail**, each expected XP 200 but observed 120. Valid coins 120 and ocean ownership/equipment assertions had already passed.
- XP GREEN: same test plus `test/features/progress/progress_projector_test.dart` → exit 0, **6 tests passed**.
- SRS test-fixture correction: first run had no due-state fixtures and timed out at the empty deck; seeded due states. Another harness correction let the snackbar entry animation settle before advancing its dismissal timer, eliminating an obscured retry tap. These are test-setup failures, not product RED evidence.
- SRS behavioral RED: `flutter test --no-pub test/screens/srs_flashcards_screen_test.dart --reporter expanded` → exit 1, **2 pass / 2 fail**, retry expected `attempt:1` but observed `attempt:2` for both failed write and lost acknowledgement. A separate assertion also exposed the enabled opposite rating during uncertain commit.
- SRS GREEN after implementation and expanded coverage: same command → exit 0, **8 tests passed**. Good/Again are both covered for before-write/lost-ack; last-card finish failure/lost-ack are covered too. Tests compare full submission metadata, real Drift attempts/SRS/XP, unchanged lost-ack outbox rows, new identity on the next card, and rejection of changed-rating payload using the same identity.
- No production change was made before the corresponding behavioral RED test.

## Final serialized checks

```text
flutter test --no-pub test/features/learning test/features/progress test/features/rewards test/features/sync/reward_transaction_sync_test.dart test/features/sync/srs_state_sync_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart test/features/export/export_use_cases_test.dart test/screens/srs_flashcards_screen_test.dart test/screens/quiz_screen_test.dart test/screens/weakness_clinic_screen_test.dart test/screens/mastery_dashboard_screen_test.dart test/screens/achievements_screen_test.dart test/screens/profile_settings_screen_test.dart test/screens/offline_vocabulary_journey_test.dart test/architecture/learning_screen_boundary_test.dart --reporter expanded
```

Exit 0, **125 tests passed** (`00:15 +125: All tests passed!`). Expected synthetic shadow-provider error output is caught by its existing no-propagation test; it is not a failed test.

```text
flutter analyze --no-pub lib/features/learning lib/features/progress lib/features/rewards lib/screens/srs_flashcards_screen.dart test/features/learning test/features/progress test/features/rewards test/screens/srs_flashcards_screen_test.dart
```

Exit 0, **No issues found! (ran in 4.7s)**. The initial targeted analysis identified two missing test-only braces; they were fixed before the final run.

```text
dart format --output=none --set-exit-if-changed lib/features/progress/data/drift_progress_queries.dart lib/screens/srs_flashcards_screen.dart test/features/progress/legacy_reward_xp_compatibility_test.dart test/screens/srs_flashcards_screen_test.dart
```

Exit 0, **Formatted 4 files (0 changed)**.

## Review and limitations

Independent reviewer is read-only; it may not run Flutter/build/codegen or write files. Claude review is **fresh for the earlier proposal only** (Sonnet 5.5 UI, accept-with-changes, after one failed CLI 401 and one permitted UI retry); it is not a fresh review of this implementation. Implementation review evidence is recorded separately. No additional Claude retry/request or secret/PII transmission was made in this execution slot.

Independent implementation reviewer `/root/lq04_bounded_review` inspected the actual dirty diff, untracked compatibility test and connected repository/projection/callers. Disposition: **accepted with limitations; no actionable P1/P2 finding** for this bounded slice. Reviewer changed no files and ran no Flutter/Dart/build commands. Root verified the implementation and final tests against the manifest below; review is not a merge/release approval.

Current implementation retains automatic SRS advancement. Saved-feedback/explicit-Next, durable result redesign, event/quest dedupe, streak/mastery/catalog redesign and full coin conversion remain outside this slot. Stable SRS retry is verified in the live screen state; physical-device process-kill recovery is not claimed.

Frozen EvidenceContext/EventEnvelopeV2, schema v10, routes and the 8-domain/f01–f44 catalog are unchanged. These changes map to f06/f17/f22 (SRS evidence/retry) and protect existing f25/f32 consumers' XP semantics; they do not claim full feature runtime readiness.

## Evidence manifest and section 13.5 handoff

| Code/test file | SHA-256 after final tests/review |
| --- | --- |
| `lib/features/progress/data/drift_progress_queries.dart` | `6360E10AD81164ACB70F09574990752DC3918FF8113D59437C3D9D534450F71E` |
| `lib/screens/srs_flashcards_screen.dart` | `811ACDD04383D0227679AE8C0CDB584E6AB0A912711B009E57F231224EDAA74C` |
| `test/features/progress/legacy_reward_xp_compatibility_test.dart` | `C75497B11525B1269885C3491261C77F758A56806D71D13A7B7CB1C7A35B38A5` |
| `test/screens/srs_flashcards_screen_test.dart` | `279D462208BABDC6DDCBFA7CD323F7B109AEE3B24DC57630CE9E8C8AEB098F04` |

Final configured `git diff --check` returned **exit 0**, no non-line-ending messages. Git emits existing LF→CRLF advisory warnings; no unrelated line-ending normalization was performed. `Get-CimInstance Win32_Process` filtered workspace Dart/runtime/tester/gen_snapshot and global flutter_tester: **0 processes at 2026-10-20T20:20:21+07:00**. No kill, cleanup, dependency resolution or generation was used.

```text
Chat / card / source branch and snapshot
LQ-04 / XP read isolation + SRS stable retry
feature/associative-reading-loop @ f43aa0fff2155ca29d6a26f2695191dd44a2d6d1
Existing shared dirty worktree preserved; four-file verified SHA-256 manifest above.

Outcome and user-visible behavior
Legacy purchases preserve existing spendable balance/rights while no longer
reducing displayed XP/level. SRS retries the original rating/time/identity through
write or acknowledgement failure, including last-card finish failure.

Changed files and shared-file touches
Four code/test paths in manifest plus this new checkpoint only.
No shared learning/reward signature change; no reward writer/rebuilder mutation.

Contracts/schema/route/feature IDs affected
Read-only XP semantics and SRS caller use of existing attemptId/occurredAtUtc API.
No schema/migration, sync/policy, owner-upgrade, bootstrap, dependency, route,
registry, research or frozen envelope changes. 8/f01-f44 unchanged.

Focused checks with exact result
Behavioral RED/GREEN evidence and exact final commands above.
Final: 125 tests passed; targeted analyze exit 0; four-file format check exit 0;
configured diff check exit 0. Current source hashes recorded above.

Claude review: evidence-derived (implementation); fresh (earlier proposal only)

Review disposition: accepted for this bounded engineering slice
Independent read-only implementation review found no actionable P1/P2 issue.
C-COIN is a separate pending contract/integration card, not silently completed.

Device/external/release dependencies
No physical-device kill/background/IME/insets/200%-text evidence; no APK build,
full repository suite, Firestore emulator, deployment, publish, enrollment or
research upload. Whole I3, sole-coins authority and release readiness not claimed.

Next executable step
LQ-00 verifies this checkpoint hash and four-file manifest, accepts the bounded
slice, and owns subsequent slot assignment. C-COIN awaits LQ-07 transport/policy
contract review; LQ-05 purchase/equip integration remains gated on C-COIN.
LQ-04 releases its production writer/Flutter slot with no task-owned process.
No new LQ-05 task is created or started here; current branch/worktree retained.
```
