# Spec compliance: Needs fixes

- พบข้อขาดหนึ่งจุดในข้อกำหนด «reserve outstanding mandatory pause flush before active resume»: `lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart:270` เปิด active segment อัตโนมัติหลัง durable operation โดยไม่ตรวจ reserve ของ flush ถัดไป
- ส่วนที่ตรวจผ่านจาก diff: authority ของ timer/answer/close อยู่ coordinator เดียว, expiry ไม่สร้าง answer/completion, entitlement +30 และ round lineage คงอยู่, codec3 ตรวจ transition/terminal receipt และอ่าน codec1/2 ต่อได้ (`pair_matching_session_coordinator.dart:520`, `pair_matching_checkpoint_codec.dart:178`)

# Strengths

- `lib/features/learning/pair_matching/domain/pair_active_clock.dart:168` ใช้ identity lease และ monotonic folding พร้อม fractional carry; token เก่าปลด token ใหม่ไม่ได้
- `lib/features/learning/pair_matching/domain/pair_repair_policy.dart:53` แยก distinct OTHER words หลัง failure ของแต่ละ ticket ออกจาก matched set ของ round; integration tests ครอบคลุม compact4/standard6 หลัง restart (`test/features/learning/pair_matching/pair_timeout_race_test.dart:318`)
- `lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart:679` coalesce pending-close append ของ host/coordinator; tests ใช้ canonical SQL authority พร้อม before/after faults ของสาม receipts และ canonical close
- `test/features/learning/pair_matching/pair_timeout_recovery_test.dart:114` reopen SQLite จริงและตรวจ last-durable elapsed, initial pause, entitlement/round, unchanged checkpoint bytes และไม่ mint owner/evidence

# Important — P2

- **Automatic resume bypasses mandatory flush reserve** — `lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart:270`. `_admit` ปลด persistence lease ทุกครั้งที่ไม่มี pending/close โดยเรียก `_clock.release(pause)` ตรง ๆ; ต่างจาก public `resumeInteraction`/`releasePause` ที่ตรวจ cost=1 ก่อนเปิด interval (`:488`, `:507`). Reproduction ที่อนุมานตรงจาก policy: fresh timed standard6, zero attempts/support, `A=18−3=15`, `G=6`, `T=2`, terminal=3 จึงมี remaining reserve `30+6+2+3=41`. เริ่ม revision1 แล้ว resume; ทำ `micros += 1000; await c.flush()` 22 ครั้งโดยไม่มี external pause lease. ครั้งสุดท้ายรับได้ที่ revision23 (`23+41=64`) และ finally เปิด clock อีกครั้ง แต่หลัง active เพิ่ม 1ms การ flush ถัดไปต้อง `23+1+41=65` จึงถูกปฏิเสธ. ระบบเริ่ม interval ที่เก็บ mandatory lifecycle boundary ไม่ได้ ขัด preflight และทำให้ lifecycle acknowledgement ล้มเหลวที่ capacity. ให้ automatic resume ใช้ admission เดียวกับ public resume และคง capacity-owned pause เมื่อ reserve ไม่พอ โดยไม่โยน failure หลัง operation ถูก durable acknowledge แล้ว; Continue untimed ต้องปลด capacity hold ได้. เพิ่ม focused fake-clock coordinator regression สำหรับ direct flush sequence นี้ โดยยืนยัน revision23 paused, elapsed ไม่เพิ่ม, แล้ว Continue + full PM3 tail + real three receipts สำเร็จภายใน64.

# Checks and limits

- อ่าน twelve-file staged diff against cc0ec26b / accepted PM3 bccb7735. Output แรกถูก tool truncate จึงอ่านส่วนที่ถูกตัดใหม่แบบ bounded chunks; อ่าน engine reducer เฉพาะส่วนที่ hunk ตัดกลางฟังก์ชันเพื่อประเมิน completed repair ticket หลัง restart. Correct tile completion ยังเป็นไปได้และรักษา support classification จึงไม่รายงาน issue เพิ่ม
- ไม่รัน Git, Flutter/Dart, build หรือเปลี่ยน source/index/HEAD. Root ยืนยัน final542 impacted tests และ focused analysis no issues; เป็น root-provided execution evidence ไม่ใช่การรันทดสอบซ้ำโดย reviewer. Existing tight-capacity tests ใช้ external modal lease จึงไม่ครอบคลุม automatic-resume bypass ข้างต้น (`pair_timeout_race_test.dart:19`)
- ไม่มี independent check นอก diff เพิ่ม. ข้อกำหนด PM6 actual UI/audio/setup, PM5 stars replay และ PM8 real owner rehome/release อยู่นอก PM4; diff นี้ไม่รับรอง production/UAT/device readiness. DB/schema/catalog/frozen contract/production switches ไม่มีการแก้ใน twelve-file delta

# Task quality: Needs fixes

- การแบ่ง authority, exact recovery และ real persistence tests เหมาะสม แต่ต้องปิด automatic-resume capacity bypass ก่อนรับ PM4. ไม่พบ Critical หรือข้อบกพร่องอื่นที่ยืนยันได้ในขอบเขต review นี้

# Targeted fix re-review — final verdict

- **Spec compliance: Approved. Task quality: Approved.** ผลนี้แทน Needs fixes ด้านบน; P2 automatic-resume capacity bypass ปิดแล้ว
- `lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart:273` เรียก `_prepareClockResume(failIfFull: false)` ก่อนปลด persistence lease. Shared helper ที่ `:544` ตรวจ cost=1 ผ่าน `_hasCapacity` และถือ exact capacity lease เมื่อไม่มี reserve จึงไม่เปิด interval หรือโยน failure หลัง durable acknowledgement. Public resume/release ใช้ predicate เดียวกัน
- `lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart:597` Continue ลบ capacity/clockFault จาก candidate reasons; หลัง ack helper ปลดเฉพาะ coordinator-owned capacity token ขณะ external modal/narration/background tokens ยังคงอยู่
- `test/features/learning/pair_matching/pair_timeout_race_test.dart:18` เพิ่ม direct-flush22/revision23 ทั้ง normal และ lost-ack retry: ต้อง paused, elapsed ไม่เพิ่ม, Continue รักษา external leases และ full PM3 tail + actual terminal receipts สำเร็จภายใน64. Worst-restart fixture หยุดที่ capacity hold อย่างถูกต้อง โดยยังตรวจ unchanged revision, explicit resume denial และครบ canonical completion (`:288`)
- อ่าน fix diff สามไฟล์และ final report addendum หนึ่งครั้ง; ไม่รัน Git/tests/build หรือแก้ source/index. Root ยืนยัน current228 affected tests pass และ current focused analysis no issues. Broader542 เป็นหลักฐานก่อน targeted fix เท่านั้น. ไม่พบ remaining actionable finding ในขอบเขต PM4; scope/production limitations ด้านบนยังมีผล
