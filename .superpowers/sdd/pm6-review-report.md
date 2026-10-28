# PM6 independent spec and quality review

## Spec Compliance

- **❌ Issues found — PM6 ยังต้องแก้ 3 เรื่องก่อนรับรอง:** guided confirmation ไม่เปิด semantic action, host ไม่มี recovery action สำหรับ canonical close/result-read failure บางสถานะ, และ valid incomplete Pair ทำให้ผล History ทั้งหน้าหายไป รายละเอียด I1–I3 ด้านล่าง
- **ขอบเขตตรวจ:** staged snapshot ใน `pm6-review.diff` เทียบ HEAD `7919cb860bc37d6d2d2811e4f6633340eca94010`, 43 Dart + 12 PNG, worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8` ตาม review package; ไม่เรียก Git และไม่เปลี่ยน source/index/branch
- **⚠️ แยกงานถัดไปถูกต้อง:** actual Adventure/research composition และ accepted research-configured withdrawal disposition เป็น PM7; runtime-owner R/original-plan P rehome และ release matrix เป็น PM8 ไม่จัดเป็นข้อบกพร่องที่ PM6 ต้องทำเพิ่ม
- **⚠️ ไม่ยืนยันจาก diff:** physical TalkBack/Switch Access/native device voice/UAT, full repository/release runs และภาพจริงทั้งหมด ผู้ตรวจอ่าน tests และรับทราบ root ตรวจ PNG ทั้ง 12 ใน `pm6-visual-qa.md`; ไม่อ้างว่าผู้ตรวจทำ physical/visual QA ซ้ำ

## Strengths

- **Admission มี provenance จริง:** `drift_learning_repository.dart:593–635` คืนผล exact existing initial ก่อนทาง measured insert จึงไม่ retrofit historical initial-only; `:669–784` เตรียมและ reserve virgin zero checkpoint ใน transaction เดียวกับ initial insert; `pair_matching_checkpoint_codec.dart:183` จำกัด null→zero เฉพาะ approved admission และตรึง terminal duration ไม่ใช่ UI boolean
- **ใช้ clock และ evidence authority เดิม:** `pair_active_clock.dart:220–278` ทำ full interactive coverage เป็น sticky nullable พร้อม clock-fault degradation; `pair_matching_session_coordinator.dart:615` ไม่ใช้ optional OFF elapsed flush กิน mandatory answer/close reserve การทดสอบ SQL rollback, lost ACK และ OFF capacity-to-completion ตรวจ canonical rows จริง
- **Route continuation มีขอบเขต:** `unified_lesson_shell.dart:327–415` reserve coordinator เดิมและแยก admitted/recovery operation; named check ที่ `:436–465` ยืนยัน continuation lease เป็น Zone ของ route พร้อม active lifetime ไม่ใช่ global always-true admission; cap disposition คง accepted answers และปล่อย incomplete canonical conflict โดยไม่สร้าง success receipt
- **Local-only Voice เป็นเงื่อนไขก่อน speech:** `voice_policy.dart:136–203`, `native_tts_provider.dart:124–194` และ `voice_orchestrator.dart:151` กรอง remote routes, คง flag ข้าม request copy และต้องได้ installed non-network voice + selection ACK ก่อนส่ง text; `voice_service_factory_test.dart:244` ทดสอบ actual facade และ ordinary remote control บน service เดียวกัน
- **Tests มี canonical integration จริง:** host fixtures ใช้ actual repository/controller/gate และตรวจ unique answers/three receipts, configured starts ทั้งสองทิศ, fresh replay, background elapsed และ safe cap disposition; wrapper ยังคง constructor/typedef/default legacy และ comparison ของ extracted legacy State body พบต่างเฉพาะ shell-feedback insertion

## Issues

### Critical (Must Fix)

- ไม่พบ confirmed Critical issue ในขอบเขต PM6 นี้

### Important (Should Fix)

**I1 [P1] Guided confirmation ถูกลบออกจาก semantics tree**

- `lib/features/learning/pair_matching/presentation/pair_board_view.dart:536` หุ้มทั้ง guided card ด้วย `ExcludeSemantics` รวม `FilledButton` ที่ `:582`; outer `Semantics` ที่ `:533` มีเพียงข้อความ label ไม่มี tap action/button role เมื่อ learner ต้องใช้ guided confirmation ตัว tile ปกติของคู่นั้นก็ถูกซ่อนแล้ว จึงไม่มี semantic action ให้ TalkBack/Switch ยืนยันและทำรอบให้จบ
- แยกส่วนข้อความที่ exclude ออกจากปุ่ม หรือเปิด semantic action ที่ถูกต้องและเพียงหนึ่ง action พร้อม busy/disabled state อย่าสร้างคำตอบจาก focus/render
- เพิ่ม test ที่หา guided confirm ใน semantics tree แล้วส่ง `SemanticsAction.tap`, ตรวจ exact word ID + shown support revision เพียงครั้งเดียว และ disabled state ไม่มี action ทั้ง regular/focused flow; `pair_board_view_test.dart:394–428` ปัจจุบันใช้ `tester.tap` จึงยังผ่านได้แม้ semantics ถูกซ่อน

**I2 [P2] Close/result recovery ที่ไม่ใช่ pending answer ไม่มีปุ่ม Retry ใน host**

- `lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart:1326` แสดง Retry เฉพาะ `_error && status.canRetry` แต่ coordinator `:151–163` แยก recovery เป็น `finish`/`acknowledgePresentation` ซึ่งไม่ทำให้ `canRetry` เป็น true
- Trigger จริง: หลัง final answer และ intent checkpoint ACK แล้ว `pair_matching_session_coordinator.dart:866` เรียก canonical close แล้ว throw ก่อนหรือหลัง commit โดย ACK สูญหาย ตอนนี้ `_close` ค้างแต่ไม่มี retained answer/append; host `_run` ที่ `:868` จับ error, `_result` ยัง null, board complete และทุก tile ใช้งานไม่ได้ โดยไม่มี action ให้ retry close บน route เดิม
- กรณีเดียวกันเกิดเมื่อ close ACK สำเร็จ แต่ canonical result read ใน host `:943–959` ล้มเหลว: status เป็น `acknowledgePresentation` แต่ยังไม่มี authenticated `_result` ให้ render จึงไม่ควรข้ามไปเขียน presented receipt
- ใช้ typed `status.recovery` เลือก exact recovery action แล้ว finish/reload authenticated projection ตามลำดับ ก่อน acknowledge presentation หลัง render คง close timestamp/bytes/operation เดิม เพิ่ม actual-host tests สำหรับ close failure before/after commit และ result-reader failure โดย retry บน host/controller เดิมจนได้ unique answers และ exact three receipts ไม่บังคับ exit/reopen

**I3 [P2] Valid incomplete Pair ทำให้ completed History อื่นทั้งหน้าหายและ Replay ถูกปิด**

- `lib/features/history/application/learning_history_use_cases.dart:68–70` throw เมื่อ snapshot ไม่มี acknowledged terminal ทั้งที่ valid abandoned/incomplete Pair จาก cap disposition มี snapshot จริงและไม่มี success terminal ตามสัญญา จากนั้น `lib/screens/learning_history_screen.dart:70` ทิ้ง projections ทั้ง batch และตั้ง `pairReadFailed`
- Named outside-diff check: canonical `drift_learning_history_reader.dart:107` เลือกทั้ง completed/abandoned และ `:444–466` คืน abandoned Pair พร้อม `pairSummary` ดังนั้นเพียงรอบหนึ่งหยุดที่ effort cap ก็ทำให้ completed Pair อื่นใน displayed page ถูกแสดง unavailable และหมดปุ่ม Replay
- แยก valid incomplete/unacknowledged entry ออกจาก completed-result hydration หรือคืนสถานะต่อ session โดยไม่ลด owner/purpose authentication; เก็บ incomplete เป็น stopped/not-scored/no-replay และคงผล + Replay ของ completed อื่น เพิ่ม actual canonical History test ที่มี completed normal/replay และ cap-abandoned entry ใน bounded page เดียวกัน

### Minor (Nice to Have)

**M1 [P3] Timer announcement อาศัยการ sample ตรง millisecond พอดี**

- `lib/features/learning/pair_matching/presentation/pair_board_view.dart:752–755` เปิด live region เฉพาะ `remainingActiveMs == 30000 || == 10000` แต่ actual host sample ทุก 250 ms (`pair_matching_experience_host.dart:850`) และมี pause/resume ที่ไม่ลงจังหวะเดียวกัน จึงข้าม 30,000/10,000 ได้โดยไม่มี announcement; test `pair_board_view_test.dart:479` ป้อนค่าตรง threshold จึงไม่ครอบคลุมเหตุการณ์นี้
- ใช้การข้าม threshold/rounded-second พร้อม deduplication ตาม round/timer phase และทดสอบ 30,050→29,800, 10,050→9,800 โดยยังไม่ประกาศทุก tick

**M2 [P3] History แสดง internal sourceSessionId โดยตรงใน product copy**

- `lib/screens/learning_history_screen.dart:379–380` แสดง `Direct source: <opaque session id>` ไม่มี link หรือข้อมูลที่ช่วย learner รู้ว่าเป็นรอบไหน เป็น implementation detail ที่ยังไม่ช่วยตัดสินใจ ไม่พบหลักฐานว่าเป็น PII leak
- คง exact source ID ใน typed projection/command แต่แสดงชื่อ/วันที่หรือคำอธิบายรอบต้นทางที่มีใน bounded loaded page และใช้ข้อความทั่วไปเมื่อไม่ได้โหลดต้นทาง ไม่เพิ่ม lifetime query เพื่อแก้ presentation

**M3 [P3] Expected capacity exception อาจหลุดจาก post-frame resume**

- `lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart:845` เรียก `c.resumeInteraction()` ใน post-frame callback โดยไม่รับ failure ขณะที่ coordinator `:673–682` เรียก `_prepareClockResume()` แบบ fail-if-full; `pair_timeout_race_test.dart:286` ยืนยัน capacity pause เป็นสถานะที่เกิดได้และ resume จะ throw
- จัดการ typed resume readiness/capacity ให้เข้าหน้า Continue ที่มีอยู่โดยไม่ปล่อย expected `StateError` เข้า Flutter error handler เพิ่ม focused restored timed-capacity host check; ข้อนี้เป็น recoverable error/noise finding ไม่ได้อ้างว่า crash หรือข้อมูลสูญหาย

**M4 [P3, pre-existing] Verification output ยังมี Drift fixture warnings**

- `.superpowers/sdd/pm6-final-pair-regression.log:431` มี duplicate `AppDatabase` warning ซึ่ง root ระบุเป็น inherited fixture debt ไม่ถือเป็นหลักฐานว่า current production DB corruption เกิดขึ้น และไม่ควรบรรยาย run ว่า warning-free
- เก็บ warning นี้ในข้อจำกัด verification และปรับ fixture lifetime/isolation เมื่อแตะ fixtures ที่เกี่ยวข้องโดยไม่ suppress warning หรือ weaken assertions ไม่เป็นเหตุให้เปิดการ audit ทั้ง repository ใน PM6

## Checks and review limits

- อ่าน task-reviewer template, `pm6-brief.md`, ทุก section ของ `pm6-integration-brief.md`, `pm6-binding-refresh.md`, `pm6-report.md` และ flattened snapshot แบบ bounded chunks; ส่วน output ที่ถูกตัดอ่านเฉพาะช่วงที่ขาดต่อ ไม่มี suite rerun
- Legacy extraction: reconstruct old matching body จาก minus/context lines และ new legacy body จาก plus linesใน diff แล้ว compare หลังชื่อ class normalization; State body ต่างเฉพาะ feedback placement ไม่อ่าน source checkout อื่น
- Focused checks เพราะ hunk ตัด function: measured-admission existing-session return (`drift_learning_repository.dart:580–635`), coordinator `_admit`/`resumeInteraction`/`_finishRecovery` (`:406–441`, `:673–682`, `:846–928`) เพื่อประเมิน provenance และ I2/M3
- Focused outside-diff named risks: route lease isolation (`unified_lesson_shell.dart:436–465`); valid abandoned History membership/projection (`drift_learning_history_reader.dart:85–130`, `:421–466`); search completion retry call sites ใน shell/controller เพื่อไม่รายงาน I2 ซ้ำกับ recovery UI ที่มีอยู่ ไม่พบ action อื่นที่ปิดช่องว่างนี้
- ไม่รัน Flutter/Dart/tests/build/scans/network และไม่แก้ implementation/index/branch; write เดียวคือรายงานนี้ Final 494 Pair-related tests + 163 Voice และ analyzer clean เป็นหลักฐาน implementer/root ที่มีอยู่ ไม่มีการอ้างเป็น reviewer rerun

## Assessment

**Task quality: Needs fixes.**

**Reasoning:** ส่วน admission, elapsed compatibility, lease ownership และ local-only Voice มีขอบเขตและหลักฐานดี แต่ I1 ทำให้ assistive guided path จบไม่ได้, I2 ขาด recovery บน route ปัจจุบัน และ I3 ทำให้ valid incomplete session ปิดผล/Replay ของ session อื่น ต้องแก้พร้อม focused regression ก่อนยอมรับ PM6; ไม่ต้องขยายเป็น PM7/PM8 หรือ production rollout
