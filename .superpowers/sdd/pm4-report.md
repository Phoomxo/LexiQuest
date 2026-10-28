# PM4 implementation handoff — 2026-09-05

## สถานะและ ownership

- Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch `codex/pair-matching-pm0-pm8` verified read-only. Accepted PM3 source baseline `bccb7735`; root's later docs-only HEAD `cc0ec26b` was acknowledged. No worker stage/commit, Git mutation, other checkout, schema, generation, pub, build, scanner, rollout or deployment.
- PM4 implementation พร้อม independent review; ไม่ใช่ production/PM6/UI acceptance. Root owns status/RTM docs and review. Only the twelve source/test files below plus worker report/logs changed. Existing native generated-registrant LF/CRLF status was preserved, not reset.
- All task-owned Flutter/Dart commands finished. Source/Flutter/Dart tooling ownership **RELEASED to root** with this handoff; no running process.

## สิ่งที่ส่งมอบ

1. `PairActiveClock` เป็น monotonic port ที่ inject ได้, เปิด active segment หลัง host readiness, ใช้ owned pause leases สำหรับ recovery/board/background/modal/persistence/narration/clock fault. Token ใช้ object identity; stale/duplicate token ปลด lease ใหม่ไม่ได้แม้ reason เดียวกัน. Reasons immutable; sub-millisecond remainder เก็บใน process ระหว่าง pause/resume เพื่อไม่สะสม drift จากการปัดลงทุก pause. Renderer ticks ไม่เขียน checkpoint.
2. Coordinator เป็น writer/decision authority เดียว. `timer`, `timerPaused`, `resumeInteraction`, `pause`/`releasePause`, `flush`, `expire` และ typed `PairTimerDecision` ให้ PM6 ใช้ร่วมทั้ง renderers. Host acquire pause ทันที แล้ว await `flush` ก่อน acknowledge lifecycle boundary; overlapping runtime leases remain active during an uncertain append. Exact retry must complete before a conflicting flush/decision is admitted. Duplicate callbacks/unchanged elapsed+engine do not append.
3. OFF stays OFF for the pinned fresh plan; supported presets 60/90/120. Timer fields are remaining/elapsed active milliseconds, mode, extensionUsed, canonical effective reasons and latest bound decision identity. No wall-clock deadline/downtime charging. Restore starts paused and returns exact persisted elapsed/remaining/decision. Clock fault allows durable Continue and clears only the fault-owned runtime lease after ack. Complete board stops the active clock before delayed summary presentation and cannot resume interaction.
4. Expiry persists timeoutDecision and never captures an AnswerAttempt, incorrect, completion or terminal envelope. Continue retains current board/session/evidence and turns timing off. +30 uses the same bound command on exact retry, adds 30 active seconds only after ack and remains used across restarts/reopen. New decision conflicts/second use fail before mutation. Busy answer/persistence lease serializes timeout/restart and preserves accepted evidence before decisions.
5. Restart increments a deterministic round ordinal/seed with same immutable plan/session/purpose/set/revisions/direction. Engine `roundSeed` and `orderFor` expose deterministic round presentation without modifying plan fingerprint. Historical attempts/evidence IDs/support acquisition/first-opportunity history remain intact; current matched set derives only from current-round attempts. Strict decoder validates ordered rounds and global operation chronology.
6. PM3 repair projection now counts distinct correct OTHER IDs since each original failure, including correct words previously matched in an older round. Current-round matched progress, per-ticket spacing and one-ticket-per-session history remain separate. A repeated failure cannot mint another ticket; support and historical roles remain session scoped. Both compact delay2 and standard delay3 actual-coordinator partial-round→restart scenarios pass alongside accepted PM3 tests.
7. Real canonical completion: `finish`/recovery freezes `PendingLearningSessionClose`, writes pending terminal checkpoint, invokes the existing canonical completer, writes terminal acknowledgement, then `markSummaryPresented` writes one presentation receipt. All three carry exact identity and retained ledger/timer data. `MatchingModeAdapter.preparePairSession` now passes monotonic clock, existing host `ownClose` and `completeSession` ports. Concurrent host ensureDurable and coordinator close share one in-flight pending-close append. Completed recovery exposes canonical summary while ordinary commands remain blocked.
8. One strict codec: v6 outer schema, codecVersion3 progress snapshots for timer/roundSeed/terminal; PM1 initial bytes remain unchanged and codec1/2 reads remain. Old-codec writer downgrade from accepted timer state is rejected. Decoder/repository authenticate timer decision fingerprint and operation revision/session/round, no silent elapsed/remaining/entitlement mutation, exact round transition, no support/progress change via timer command, terminal envelope and receipt progression. Existing canonical attempt/pending/support prefix checks remain active. Generic EventsV2/EvidenceContext contracts and DB are unchanged.
9. One candidate-state revision/attempt admission predicate `PairMatchingCheckpointBudget.canTransition`. Coordinator answers, hints, lifecycle flush/resume, timer decisions and restart use remaining PM3 attempts plus *unmatched unsupported* reveals, timer decision reserve (running2, decision1, untimed0) and terminal3. Byte projection adds worst encoded bounded timer/round fields to retained plan/history, all remaining PM3 answers/full frozen occurrence and terminal metadata. No ceilings raised and no historical data discarded.

## RED → GREEN และข้อผิดพลาดที่แก้

- Initial missing timer API/clock/decision/close/round-aware ports recorded as feature RED (`pm4-timer-red.log`, `pm4-clock-red.log`, `pm4-recovery-red.log`, `pm4-spacing-red.log`). First dynamic enum getter assertion needed a typed receiver once the API existed; it was a test harness issue, not a timer defect.
- Real repository negative tests initially allowed forged elapsed/remaining/entitlement/round/terminal transitions (`pm4-lineage-red.log`); added pure transition validation and named repository envelope checks. First envelope patch hit the adjacent answer check, then the failed terminal assertion identified the missing checkpoint check; both boundaries now enforce it.
- Codec detached timer identity initially decoded (`pm4-codec-identity-red.log`); current decoder reconstructs and validates the exact bound decision fingerprint/revision/round.
- Standard6 restart initially overreserved 18 future answers because a temporary round-specific shortcut removed PM3's proven minimum-spacing deduction. Refreshed the bound using the same ticket-local spacing across rounds; actual standard6 scenario passed (`pm4-race-green.log`). No byte ceiling or assertion weakened.
- Repeated 0.5 ms pauses lost fractional time; immutable-reasons test also failed (`pm4-rounding-red.log`). Added local fractional carry and defensive immutable copy; focused9 GREEN.
- Root-requested clock fault→Continue path exposed a retained fault lease; stale release at capacity hit admission before the identity no-op (`pm4-fault-continue-red.log`, `pm4-stale-capacity-red.log`). Fixed those precise paths; actual repair/close success verified.
- Complete board continued accumulating active time and restored complete board could resume (`pm4-complete-clock-red.log`, `pm4-complete-resume-red.log`). Completion now holds a board pause and resume checks exact completion.
- Concurrent host `ownClose` ensureDurable raced the coordinator's same pending append and raised null assertion (`pm4-owned-close-race-red.log`). One close-checkpoint in-flight future now coalesces these exact calls (`pm4-owned-close-race-green.log`).
- Root found mismatch between optional-action reveal reserve and later answer gate: already matched independent words could be counted as future reveals. Focused five-independent-matches→capacity pause→Continue→last correct RED reproduced the denial. All gates now use the same candidate projection; GREEN completes all three receipts at revision62 (`pm4-reveal-reserve-red.log`, `pm4-reveal-reserve-green.log`).
- Historical codec1/2 positive fixtures initially retained new codec3-only timer keys when reconstructed from current snapshots. Updated only fixture shape removal; exact PM3 chronology rejection and positive delayed-repair assertions remain intact.
- Analysis brace infos corrected. No current failing test or analysis item remains in the executed scope.

## Verification ก่อน independent review (ดูผล source ล่าสุดใน addendum)

**Impacted subsystem: 542 passed, exit0**, after the shared candidate-reserve correction and before the independent-review automatic-resume fix below:

```text
flutter test --no-pub test/features/learning/pair_matching test/features/review/review_center_reader_test.dart test/features/learning/srs_policy_test.dart test/features/learning/hint_policy_test.dart test/features/learning/evidence_eligibility_policy_test.dart test/features/learning/matching_mode_adapter_test.dart test/features/learning/current_activity_evidence_test.dart test/features/learning/drift_learning_repository_test.dart test/features/learning/unified_lesson_controller_test.dart test/features/recommendation test/services/srs_service_test.dart test/services/weakness_clinic_service_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart test/features/identity/upgrade_guest_owner_test.dart test/features/sync/srs_state_sync_test.dart test/architecture/pair_matching_f10_boundary_test.dart --reporter expanded
```

Log `.superpowers/sdd/pm4-impacted.log`. Earlier 541 impacted and 132 Pair-only passed before subsequent narrow fixes; these are superseded by final542, not additional final-source claims.

**Focused analysis: No issues found, exit0**:

```text
dart analyze lib/features/learning/pair_matching lib/features/learning/application/matching_mode_adapter.dart lib/features/learning/data/drift_learning_repository.dart test/features/learning/pair_matching
```

Log `.superpowers/sdd/pm4-analysis.log`. Touched code formatted. Final `git diff --check` exit0, no whitespace errors; LF/CRLF warnings remain visible and are not described as pristine output. Inspected final shared repository/adapter/budget/repair diff and worker source/test scope.

Actual SQLite/file evidence:

- Ten disk reopen cases: pause/expire/extend/restart/Continue × before-write/after-write lost ack. Nonzero persisted elapsed survives, new clock starts paused, long elapsed wall duration creates no new active charge, no ID minting/answers; actual stored checkpoint bytes remain identical on read. `pm4-reopen.log`.
- Eight terminal cases: pending-close/canonical-close/ack/presentation × before/after write fault, restore and exact completion at base revision+3, four canonical answers exactly once. Included in final542.
- Timer/answer admission races, timeout-first command rejection, extension duplicate recovery, detached identity/lineage rejection, owner/admission regressions, reason overlap/stale callback and clock fault real completion included in final542. PM3 real Review/SRS/owner tests remain green.
- No tick writes; durable snapshots coalesce elapsed/engine boundary work. Test clock changes remain process-local unless an explicit boundary is persisted.

## Bounded completion evidence

The runtime predicate is `revision + operationCost + 2*remainingAllowedPM3Answers + remainingPossibleReveals + timerReserve + 3 <= 64`, with attempts<=128 and the codec's full future UTF-8 projection<=65,536. Restart/+30 admission evaluates their *target* round/timer state; denial leaves the acknowledged state/entitlement and Continue/required completion path intact. No fixed restart-count entitlement is implemented.

Pre-review test diagnostics from `pm4-impacted.log` (current observations supersede these in the addendum):

| Allowed synthetic sequence | Observed result |
|---|---|
| compact4 repeatedly timeout/restart until next optional restart is denied, optional extension capacity check, Continue, full adversarial PM3 wrong/repair/guided round, three terminal receipts | 17 admitted restarts, 8 actual answers, terminal revision56 |
| same standard6 sequence | 11 admitted restarts, 13 actual answers, terminal revision54 |
| five independent matches, repeated distinct active pause/flushes to capacity, stale releases, Continue, final correct and three receipts | terminal revision62, six canonical answers |
| allowed maximum Thai256 compact4 IDs/meanings and maximum bounded owner/start/build metadata, valid197-character evidence IDs; timeout/+30/timeout/restart/timeout/Continue/full repair/close | initial worst-future reservation64,621 bytes; max actually written pending/committed snapshot24,317 bytes; 8 answers; terminal revision26 |

The actual frozen baseline contexts are smaller than the codec's conservative supported-schema worst bound. The measured24,317 is the executed valid fixture, not a claim that every possible research context was materialized. PM2/PM3 frozen occurrence checks and initial pre-insert capacity tests remain green. Fixed ceilings and full canonical history remain intact; unlimited sequential restarts are not claimed.

## Exact source/test set

New:

- `lib/features/learning/pair_matching/domain/pair_active_clock.dart`
- `test/features/learning/pair_matching/pair_active_timer_test.dart`
- `test/features/learning/pair_matching/pair_timeout_recovery_test.dart`
- `test/features/learning/pair_matching/pair_timeout_race_test.dart`

Modified:

- `lib/features/learning/pair_matching/domain/pair_matching_engine.dart`
- `lib/features/learning/pair_matching/domain/pair_repair_policy.dart` (root explicitly authorized narrow restart spacing)
- `lib/features/learning/pair_matching/domain/pair_matching_checkpoint_budget.dart`
- `lib/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart`
- `lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart`
- `lib/features/learning/application/matching_mode_adapter.dart`
- `lib/features/learning/data/drift_learning_repository.dart` (named Pair checks only)
- `test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart` (canonical close fault harness, current-round confirmation helper, actual historical codec fixture shape)

## ขอบเขตที่ยังไม่อ้างว่าเสร็จ

Recovery is exact for the last durable snapshot/decision and its elapsed value. Abrupt process death can lose an unflushed active interval; no physical crash-instant precision, periodic-tick persistence workaround or wall-clock charging is claimed. Host must reacquire current modal/narration/background leases after restore and explicitly admit interaction. Timer elapsed is presentation data, not a second canonical learning-effort authority.

PM6 owns actual shared host/renderers/setup/timeout sheet, lifecycle/voice accessibility binding and physical device tests. PM5 owns actual star/replay/history projections; PM8 owns reader-first rollout, real immutable owner rehome/collision and release integration. These tests do not prove UAT, physical devices, full repository regression/build, production readiness or permission to enroll/upload/deploy. No production activation was performed.

Next executable step: root inspect this final twelve-file source delta against accepted PM3, arrange independent review, then request bounded fixes or accept PM4 before dispatching the next source writer.

## Independent-review P2 followup — automatic resume capacity

อ่าน `pm4-review-report.md` แล้วและยืนยัน P2 ด้วย actual coordinator test: initial standard6, no answers/support, direct active `flush()`22ครั้ง. Both normal acknowledgement and after-write lost-ack retry reached revision23 but remained running (expected paused); `pm4-auto-resume-red.log` records both RED assertions.

แก้เฉพาะ source/test สามไฟล์: `pair_matching_session_coordinator.dart`, `pair_active_clock.dart`, `pair_timeout_race_test.dart`. Root's staged twelve-file baseline remains untouched; worker did not stage/commit or alter root docs/native line-ending noise.

- `_prepareClockResume` uses the same `_hasCapacity(..., cost=1)` for explicit resume, owned pause release and automatic persistence-lease release. Before opening an interval without a future mandatory flush reserve, it acquires a dedicated capacity lease. Automatic path does not throw after an acknowledged write; it remains safely paused.
- Continue's acknowledged state removes only the capacity reason (plus the previously supported clock-fault exit). After ack, coordinator releases its exact capacity lease. Modal/narration/background owners survive until their individual token release. No additional checkpoint or timer authority was introduced; the existing byte projector automatically includes the extra bounded reason.
- New tests assert revision23 paused, no elapsed increase after advancing the fake clock, normal and lost-ack recovery, preserved three external pause owners after Continue, then full adversarial PM3 wrong/repair/guided completion and all three real terminal receipts within64.
- Two old worst-restart fixtures initially failed because they assumed automatic resume after every accepted restart; the corrected capacity hold makes another timeout unreachable at that boundary. Fixtures now assert capacity-held state, explicit resume denial with unchanged revision, no active elapsed increase, then Continue and the full canonical completion. They still test optional restart/extension rejection when the timeout decision is actually reachable; no forced timeout or discarded evidence was added to preserve historical counts.

**Current-source affected tests: 228 passed, exit0**:

```text
flutter test --no-pub test/features/learning/pair_matching test/features/learning/matching_mode_adapter_test.dart test/features/learning/drift_learning_repository_test.dart --reporter expanded
```

Log `pm4-review-fix-tests.log`. The initial affected run had only the two fixture expectation failures described above; final228 supersedes it. Focused new direct-flush tests separately passed2 (`pm4-auto-resume-green.log`). The pre-review542 run is historical broader evidence, not a claim that542 were rerun after this narrow fix.

**Current-source analysis: No issues found, exit0**, same analysis command above; log `pm4-review-fix-analysis.log`. Touched files formatted. Final focused diff inspected and `git diff --check` exit0; existing LF/CRLF warnings preserved.

Updated executed diagnostics superseding the earlier table:

| Sequence | Current observation |
|---|---|
| compact4 maximum admitted restart path -> capacity-held Continue -> full PM3 round + close | 17 restarts, 8 answers, terminal revision55 |
| standard6 equivalent | 11 restarts, 13 answers, terminal revision53 |
| tight five independent matches | terminal revision62 |
| maximum admitted Thai256 compact4 timer/repair/close | initial reserved64,632 bytes; max written24,317 bytes; terminal revision26; 8 answers |

The one-revision reduction in restart paths is the avoided final timeout while the timer is capacity-paused, not a dropped required answer/terminal receipt. Counts are observations under the shared budget, not restart entitlements.

No process remains. Source/Flutter/Dart ownership **RELEASED again to root** for reviewer recheck. No full repository suite/build/deploy/UAT/device claim; prior scope limitations remain unchanged.
