# PM6 configured effort cap advisory audit

## Verdict

พบ **P1 / Important: configured normal Pair ที่ยังจับคู่ไม่ครบเมื่อ f16 effort หมด ไม่มีทางจบหรือ retire จาก UI อย่างมี disposition ชัดเจน และ reopen ไม่คืนสิทธิ์เล่น** ใน source snapshot ด้านล่าง การหยุดรับคำตอบตาม f16 ถูกต้อง; defect คือ Pair lifecycle/UI ไม่จัดการผลลัพธ์ของ hard limit ไม่ใช่ตัว policy limit

## Evidence and minimal reproduction

1. `lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart:172` ใช้ policy defaults แล้วเปลี่ยนเฉพาะ itemCount/direction. `matching_mode_adapter.dart:516` รองรับ timed จึงได้ `SessionTiming.timed(600 seconds clamped to real protocol)` จาก `application/session_configuration_policy.dart:166–174`; standard protocol ช่วง 60–1800 seconds (`domain/session_configuration.dart:201`). Pair challenge OFF ไม่ได้เปลี่ยนค่านี้
2. เริ่ม normal configured Pair ผ่าน real host, เลือก OFF (หรือ timed แล้ว Continue) และเหลืออย่างน้อยหนึ่งคู่; ให้ active configured effort ถึง pinned limit. Controller persist/clamp effort และ `_reachConfigurationLimit` ปิด `configurationAcceptsOperations` พร้อม pause (`application/unified_lesson_controller.dart:207`, `:1705–1713`, `:1777–1794`)
3. Route ปิด new operations (`presentation/unified_lesson_shell.dart:302–304`, `:353–359`); host coordinator callback ใช้ route continuation (`pair_matching_experience_host.dart:330`), จึง `hostStatus.canDispatch` false และ board disabled (`:485–488`). Continue/restart/extend ก็เป็น new operations จึงไม่แก้ hard limit และต้องไม่ถูกใช้ข้าม limit
4. Shell แสดงเพียง `Session limit reached` (`unified_lesson_shell.dart:1517–1527`). Pair host มีเพียง board/timeout choices และ pending retry button (`pair_matching_experience_host.dart:510–530`); ไม่มี effort-limit disposition. `PairMatchingSessionCoordinator._finishRecovery` ปฏิเสธ incomplete board ที่ `application/pair_matching_session_coordinator.dart:786`; จึงห้ามเรียก finish เพื่ออ้างว่าจับคู่ครบ
5. Back/dispose เข้าทาง retire ซึ่ง settle accepted work แล้ว preserve incomplete Pair โดย dispose coordinator และ return แทน abandon (`unified_lesson_shell.dart:670–707`). Reopen โหลด durable consumed effort (`unified_lesson_controller.dart:343–354`) แล้ว `_beginConfigurationEffort` reach limit อีกเมื่อ restored >= pinned limit (`:1581–1584`). ไม่ได้เกิด budget ใหม่; learner จึงกลับมาที่ unfinished session ซึ่งเล่นต่อไม่ได้

นี่เป็น static control-flow reproduction ไม่ใช่ผลรัน widget test; ไม่มี Flutter/Dart/test tools ถูกรันในงานนี้

## Accepted work is a different case

- ไม่ใช่ blanket failure ของการ recovery: `unified_lesson_shell.dart:364–384` ยังให้ exact recovery เข้า tracked lease ขณะ route accepting; `acceptsPairContinuation` ยอมเฉพาะ inside accepted lease เมื่อ cap ปิด new operations
- หาก last answer รับก่อน cutoff แล้ว completion ถูกต้องแล้ว, accepted work/close มีเส้นทาง settle และ `completeCapturedSessionAtCutoff` รับ active/paused โดยไม่เพิ่ม effort entitlement (`unified_lesson_controller.dart:817–844`). Retirement เรียก `_settlePair` ภายใต้ lease แล้ว finish เมื่อ board complete (`unified_lesson_shell.dart:342–350`, `:670–697`). ต้องทดสอบ race นี้จริงก่อน claim recovery acceptance
- UI `canRetry` ปกติอาจ false เมื่อ cap ปิด outside lease แม้มี retained pending; จึงต้องให้ typed limit surface เรียกเฉพาะ recovery authority ที่มีอยู่เพื่อ settle accepted bytes ไม่ใช่ reopen arbitrary learner commands
- Practice Replay แยกต่างหาก: `_beginConfigurationEffort` return เมื่อ `_practiceReplay` (`unified_lesson_controller.dart:1565–1566`) ตาม accepted PM5 zero-effort contract; อย่าแก้ normal session ให้กลายเป็น replayเพื่อเลี่ยง cap

## Smallest truthful options

- แสดงก่อน start ว่า OFF/Continue หมายถึงเฉพาะ Pair challenge; configured session ยังมี maximum effort ตาม immutable validated configuration. แสดง actual pinned duration และเหตุผลที่หยุดเมื่อหมด ไม่ใช้ generic save-failure copy หรือ promise ว่ายังทำต่อได้
- เมื่อ limit ถึง ให้หยุด interactive presentation, settle exact already-accepted pending answer/close ผ่าน recovery lease และแสดงผลจริง. Completed board เท่านั้นที่ใช้ existing successful Pair finish/three receipts
- สำหรับ incomplete board จำเป็นต้องมี explicit **incomplete/end-at-limit disposition** ที่ออกจาก active-session conflict ได้อย่างถูก authority โดยคง accepted evidence/checkpoints/effort. ใช้ canonical lifecycle retirement/abandon seamได้เฉพาะเมื่อ Pair strict recovery/History contracts รองรับจริง; audit นี้ไม่ได้ยืนยันว่า generic abandon ปัจจุบันเพียงอย่างเดียวเพียงพอ และไม่อนุญาต fabricate terminal success. Root ควรกำหนด narrow disposition contract ก่อน implement ถ้ายังไม่มีใน approved plan
- “ออกและเก็บความคืบหน้า” พร้อมคำอธิบายว่า session นี้หมดสิทธิ์แล้ว เป็น interim honest UI แต่ไม่แก้ stranded-active-session ให้ครบ. การสร้าง session ใหม่ต้องผ่าน new canonical admission และ policy ปกติหลัง disposition เดิม ไม่ reset/extend budget เดิมหรือเปลี่ยน configuration ย้อนหลัง
- ห้ามถอด configuration, เปลี่ยน timed600 เป็น fake unlimited, เพิ่ม maximum, map f16 timing จาก Pair OFF/60/90/120, หรือเปิด route acceptsOperation แบบ unconditional. integration brief `:12`, `:28` ยืนยัน authority สองส่วนแยกกัน

## Focused test target

เพิ่มใน `test/features/learning/pair_matching/pair_matching_experience_host_test.dart` ข้าง real configured setup test (`:209–240`): ใช้ real policy/provider พร้อม synthetic valid short maximum หรือ pump ถึง actual pinned600; normal Pair OFF และ Continue คงคำตอบค้างหนึ่งคู่ → cap → assert no new answer/timer command admitted, explicit limit UI, exact pending recovery succeeds, truthful incomplete disposition, reopen ไม่มี budget reset และ active-session handling ถูกต้อง. เพิ่ม race last accepted answer crossing cap → successful finish exactly three receipts; assert persisted effort <= pinned cap และ unchanged configuration bytes. Existing `test/features/learning/unified_lesson_controller_test.dart:255–295` ตรวจ generic cap refusal แต่ไม่ได้พิสูจน์ Pair disposition

## Snapshot and scope

Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch `codex/pair-matching-pm0-pm8` ตาม parent. Advisory เท่านั้น ไม่ใช่ final PM6 review. Main implementer ยังแก้ host/shell; SHA256 ด้านล่างตรงกันที่เริ่ม/จบการอ่านครั้งนี้:

| File | SHA256 |
| --- | --- |
| pair_matching/presentation/pair_matching_experience_host.dart | 184E64FA8EF5FF54EB8C4C03A6E9F5BAFE1C7C0E8227731856C73B7D70F73F80 |
| presentation/unified_lesson_shell.dart | EF8987A3F4A3B2233F9B9F3214E4D34E6289C6F41332AB4BBF1474B3E2B38E14 |
| application/unified_lesson_controller.dart | 885E80B4D799698ED45B61AE8AC3CCC65E5867C82BC99DD1F00B91ECCC43265A |
| application/session_configuration_policy.dart | 19125A5AFE07C5799EE68149E55F23A79CD9712DF263B2EC4963D66EA4507624 |

ทุก file ในตาราง relative ต่อ `lib/features/learning/`. อ่านเฉพาะ named configuration/limit/host/recovery paths และ tests ที่เกี่ยวข้อง; write เดียวคือรายงานนี้ ไม่มี source/index/Git mutation, test run, scanner หรือ process ค้าง

## Follow-up: canonical incomplete exit is sufficient

**ยืนยันตาม bounded follow-up: ใช้ existing `abandonAtCutoff` สำหรับ incomplete Pair ได้ ไม่ต้องเพิ่ม terminal/evidence schema.** ข้อนี้แทนที่ความไม่แน่ใจเรื่อง generic abandon ใน Smallest truthful options ข้างบน; successful Pair completion ยังคงใช้สาม receipts เฉพาะเมื่อ board complete

- `unified_lesson_controller.dart:867–905` รับ exact owned cutoff, serialize abandonment และยอม active/paused; `_abandon` ที่ `:1117–1156` ปิด canonical time/configured effort แล้วเรียก `learning.abandonSession` ด้วย `_sessionOwnerId` และ session เดิม ก่อนเปลี่ยน controller status เป็น abandoned. ไม่เรียก Pair finish หรือ successful completion callback
- `application/learning_use_cases.dart:1219–1242` ส่ง pinned owner/session/timestamp เข้า lifecycle repository. `data/drift_learning_repository.dart:2591–2638` เป็น transaction ที่เปลี่ยนเฉพาะ `learning_sessions.state = abandoned` และ `endedAtUtcMs`; ไม่มี DELETE, answer/checkpoint rewrite, score grant หรือ completion operation. Accepted answers และ economic/research effects ที่เกิดอย่างถูกต้องก่อนหยุดยังอยู่ ไม่ควร rollback หรืออ้างว่าไม่มีผลเหล่านั้น
- Repository return summary state เป็น abandoned และเก็บ correct/wrong counts เดิม (`drift_learning_repository.dart:2689–2704`); ไม่ได้กลายเป็น matching success. `pair_matching_session_purpose.dart:221–225` ต้องการ completed เฉพาะกรณี latest terminal acknowledged; incomplete ledger ที่ไม่มี terminal จึงอ่านผ่าน strict purpose decoder ได้เมื่อ owner/ledger pins อื่นถูกต้อง
- `pair_star_policy.dart:36–48` ให้ stars null หากไม่มี acknowledged complete. `pair_matching_history_projection.dart:41–42` ไม่จัด entry ที่ไม่มี terminalAtUtc เข้า successful latest/best overview และ repository History queries เลือกเฉพาะ completed (`drift_learning_repository.dart:2647–2650`, `:2669–2674`). ดังนั้น stopped result ต้องเป็น dedicated truthful presentation; อย่าส่งเข้า success result/stars/mission-completion callback. Existing History จะไม่แสดง abandoned entry โดยอัตโนมัติ และ audit นี้ไม่ขยายงานเป็น History schema/UI ใหม่
- Active admission conflict ตรวจเฉพาะ rows state=active (`drift_learning_repository.dart:747–758`); canonical abandon ปล่อย conflict จึงยอม fresh policy-validated start ตาม gate ปกติได้ โดยไม่ reset session เดิม

### Ordering, owner, and lost acknowledgement

1. Explicit policy-limit exit ต้องตรวจ current owner ตรง pinned Pair/controller owner และ session ก่อนยอมรับ action; repository abandon ตรวจ row owner แต่ไม่ได้ยืนยัน current active owner แทน host. หลัง action รับแล้ว recovery ต้องคง pinned owner ไม่ย้ายไป owner ใหม่
2. Retain cutoff ของ exit ครั้งแรก แล้ว fence new commands, pause Pair, รอ tracked accepted operations และ retry exact retained pending bytes ภายใต้ bounded recovery lease. Generic controller `_requireNoUncommittedSubmission` ไม่รู้ Pair pending ทุกชนิด จึงห้ามใช้ controller guard แทน coordinator drain
3. หลัง drain หาก complete ให้ existing Pair finish/three receipts; หาก incomplete ให้ flush accepted recoverable board/checkpoint ก่อน canonical abandonAtCutoff. อย่า abandon ขณะที่ evidence write ยัง uncertain เพราะ subsequent answer/checkpoint append ต้องการ active session
4. Repository abandonment idempotent **เฉพาะ timestamp เดิม** (`drift_learning_repository.dart:2609–2613`): lost ACK หลัง commit ให้ retry cutoff identity เดิม ไม่ใช้ now ใหม่. `_abandonInFlight` deduplicate แค่ concurrent call และ controller status เปลี่ยนหลัง await จึงไม่แทน retained cutoff ใน error path
5. หาก process/presentation หายหลัง abandon committed แต่ ACK หาย ให้ owner-validated load ของ exact session state/endedAt รับรู้ abandoned เป็น stopped result; อย่าพยายาม reopen เป็น active Pair coordinator เพราะ coordinator restore/configured controller start ปฏิเสธ abandoned โดยตั้งใจ. ไม่ต้องเพิ่ม durable receipt ใหม่: abandoned row และ canonical endedAt เป็น persisted reconciliation authority ที่มีอยู่

### Minimal seam and focused acceptance

เพิ่ม narrow route/session-lifecycle `exitPairAtPolicyLimit` (ชื่อเสนอ) ที่ผูก exact reserved coordinator และ pinned session, retain cutoff/future และเรียก drain→complete-or-abandon ตามข้างบน; ไม่เปลี่ยนทั่วไปว่า route retirement ทุกครั้งต้อง abandon Pair เพราะ gate-off recovery ยังต้อง preserve. ให้ host แสดง “หยุดตามเวลาสูงสุด · เก็บคำตอบที่บันทึกแล้ว” หลัง acknowledged/reconciled abandonment โดยไม่มี stars/mission-success/replay-success controls

Focused tests ใน existing Pair host test: OFF/Continue cap + incomplete exit → same accepted checkpoint/answer bytes, abandoned state/retained counts, null Pair stars/terminal, strict purpose reader passes, getActiveSession null และ next fresh validated start ได้; pending answer held ขณะ exit → drain before abandon; pending last answer → three successful receipts; repository commit-then-throw abandonment → retry same endedAt exactly once; wrong owner/session refused และ owner drift ไม่แตะ session ของ owner ใหม่. ทดสอบ lost-ACK reopen แสดง stopped ไม่พยายาม active restore. Generic controller tests `:862` และ `:1982` มี owner/session-targeted abandon evidence แต่ยังไม่พิสูจน์ Pair ordering นี้

Follow-up ไม่รัน test/Flutter/Dart หรือแก้ source. หนึ่ง search ใช้ PowerShell glob ใน rg path ไม่รองรับ (error123); เปลี่ยนเป็น bounded directory + `-g '*.dart'` แล้วสำเร็จ ไม่มี mutation
