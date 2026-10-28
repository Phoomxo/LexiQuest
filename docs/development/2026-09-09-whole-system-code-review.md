# LexiQuest — ผลตรวจโค้ดทั้งระบบ วันที่ 9 กันยายน 2026

ตรวจตามคำขอให้ review ก่อน และตรวจอย่างรอบคอบ รายงานนี้เป็นผลตรวจของ working tree ปัจจุบัน ไม่ใช่ผลหลังแก้บั๊ก และไม่ใช่การรับรองว่าไม่มีข้อบกพร่องอื่น

- Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`
- Branch: `codex/pair-matching-pm0-pm8`
- HEAD: `788e90e62b1694c20945734787723c168b6a6ab2`
- Snapshot เริ่มตรวจ: `2026-09-09T01:49:53.636857+00:00` รวมไฟล์ tracked/untracked ที่มีอยู่และไม่ถูก ignore 1,602 ไฟล์
- ตรวจ working tree รวมงานที่ยังไม่ commit ไม่ได้จำกัดเฉพาะ diff จาก HEAD
- ไม่มีการแก้ production code, schema, configuration หรือเทสต์เดิม ไม่มี commit/deploy ผลที่เพิ่มคือรายงานนี้และ probes/logs ในโฟลเดอร์ build ที่ถูก ignore

## ผลที่ควรนำไปแก้

พบ **29 ประเด็น**: P1 จำนวน 1 ประเด็น, P2 จำนวน 26 ประเด็น และ P3 จำนวน 2 ประเด็น

- **R = จำลองได้:** 22 ประเด็น รวม 24 สถานการณ์เฉพาะจุด ใช้ฐานข้อมูลในหน่วยความจำ, widget tests, method-channel mock และ Python mocks/TestClient ในเครื่อง
- **S = ตรวจจากเส้นทางโค้ด:** 7 ประเด็น ระบุต้นทาง/ปลายทางและเงื่อนไขที่เกี่ยวข้อง ยังไม่มี reproduction ใหม่ครบเส้นทางในรอบนี้
- P1: เส้นทางใช้งานหลักไปต่อไม่ได้ ควรแก้ก่อนทดสอบเส้นทางนั้นอีกครั้ง
- P2: พฤติกรรมหรือข้อมูลผิดภายใต้เงื่อนไขที่ระบุ ควรแก้ตามลำดับผลกระทบ
- P3: ความถูกต้องของการแสดงผลในขอบเขตจำกัด

### 01. [P1 · R] เปิดทบทวนจากหน้าวันนี้แล้วไม่มีวิธีตอบหรือจบกิจกรรม

เส้นทาง **วันนี้ → ศูนย์ทบทวน → เริ่มทบทวน** เปิดเซสชันจริง แต่ renderer ที่ [main_navigation_screen.dart:1053](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/screens/main_navigation_screen.dart:1053) แสดงเพียงคำศัพท์กับคำแปล ไม่มีตัวรับคำตอบหรือคำสั่ง complete ตัวครอบ UnifiedLessonShell เพิ่ม progress/hints/feedback แต่ไม่ได้สร้างกิจกรรมให้ เส้นทางถัดไปจาก Adventure Result เรียกปลายทางเดียวกัน

Widget probe ใช้ navigation และ renderer จริง โดยฉีดคิวคำศัพท์สังเคราะห์: พบ session `active`, answer attempts 0 และตัวควบคุมตอบ/จบในส่วนกิจกรรม 0 ปุ่ม ปุ่มย้อนกลับยังทำงานได้ การทดสอบเดิมส่วนใหญ่หยุดที่เปิด ReviewCenter หรือใช้ปลายทางจำลอง

**แนวทางแก้/ตรวจรับ:** ต่อ renderer กับกิจกรรมที่ส่งคำตอบและจบผ่าน learning authority เดิม ตรวจตั้งแต่กดเริ่ม → ตอบ → บันทึกหลักฐาน → จบ → คิว/SRS เปลี่ยน พร้อมย้อนกลับและเปิดใหม่ หลักฐาน: `review-route-verified.log`

### 02. [P2 · R] ภารกิจรายวันเริ่มรอบใหม่ไม่ได้หลังทำสำเร็จครั้งแรก

[quest_tables.dart:86](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/data/local/tables/quest_tables.dart:86) กำหนด UNIQUE `(ownerId, questId)` ครอบทั้ง active และ completed ขณะที่ `startQuest` ตรวจเฉพาะ active และสร้าง instance ID ใหม่ [drift_quest_repository.dart:55](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/quest/data/drift_quest_repository.dart:55) จึงข้ามการ insert instance ด้วย `insertOrIgnore` แล้ว insert progress ของ ID ที่ไม่มีอยู่จนติด foreign key

จำลองทำครบ 5 ข้อวันที่ 4 สิงหาคม แล้วเปิดรอบใหม่วันที่ 5: ได้ Sqlite 787, `renewed=null`, active quest 0 Bootstrap จับข้อผิดพลาดนี้ไว้ จึงอาจไม่แสดง error แต่ไม่มีภารกิจรอบใหม่ **ไม่ได้เกิดการรับรางวัลรายวันซ้ำตามข้อสงสัยแรก**

**แนวทางแก้/ตรวจรับ:** กำหนด identity ของรอบวันและข้อบังคับ active ให้ตรงกัน โดยรักษาประวัติและ reward idempotency เดิม ต้องมี migration ตาม schema ledger ตรวจวันเดิม/วันใหม่/expired/abandoned และ owner upgrade หลักฐาน: `quest-notification-verified.log`

### 03. [P2 · R] กดหยุดพูดแล้วทิ้งผลรู้จำเสียงสุดท้าย

[speech_practice_use_cases.dart:131](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/media_practice/application/speech_practice_use_cases.dart:131) เปลี่ยน attempt identity ก่อนรอ `gateway.stop()` ทำให้ final callback ที่เกิดระหว่าง stop ถูกมองว่าเก่า หน้าพูดและ shadowing ยังเปลี่ยน listen epoch ก่อน stop เช่นกัน Plugin ที่ติดตั้งแยก stop ซึ่งอาจส่ง final result ออกจาก cancel ที่ยกเลิกผล

Probe ส่ง partial แล้วให้ gateway ส่ง final ระหว่าง stop: gateway ส่ง final 1 ครั้ง แต่ผู้รับได้รับ final 0 ครั้ง จึงเสียคำตอบเมื่อผู้เรียนใช้ปุ่มหยุดเอง

**แนวทางแก้/ตรวจรับ:** แยกการจบการฟังแบบรับ final ออกจากการยกเลิก session ตรวจ manual stop, natural final, cancel, เปลี่ยนหน้า และ callback ล่าช้า หลักฐาน: `reproductions-verified.log`

### 04. [P2 · R] เสียงคลาวด์ของตัวอย่างประโยคถูกหยุดหลังเริ่มเล่น

[synthesized_voice_route_handler.dart:115](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/voice/synthesized_voice_route_handler.dart:115) คืนผลโดยไม่มี `playbackCompleted` ทั้งการอ่านจากแคชและสังเคราะห์ใหม่ ส่วน [voice_use_cases.dart:156](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/voice/application/voice_use_cases.dart:156) หยุดเสียงและคืน unsupported capability ถ้าผู้เรียกต้องการรอเล่นจบ หน้าฝึกประโยคเรียก `speakUntilCompleted` และอนุญาต cloud route

Probe เชื่อม handler จริงกับ use case: play 1 ครั้ง ตามด้วย stop 1 ครั้งและ error แม้สังเคราะห์สำเร็จ เงื่อนไขนี้เกิดเมื่อใช้ cloud route; Pair Matching ที่ระบุ `localOnly: true` ไม่เข้าเงื่อนไขเดียวกัน

**แนวทางแก้/ตรวจรับ:** ส่งต่อเหตุการณ์เล่นจบจริงของ audio player ผ่าน handler และ orchestrator ตรวจ fresh/cache/cancel/error ห้ามสร้าง completion ที่สำเร็จทันทีทั้งที่ยังเล่นไม่จบ หลักฐาน: `additional-reproductions.log`

### 05. [P2 · R] Shadowing แสดง 100% จากเสียงที่ยังไม่รู้จำเสร็จ

[shadowing_challenge_screen.dart:252](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/screens/shadowing_challenge_screen.dart:252) คำนวณ assessment จาก partial result และไม่ได้ล้างเมื่อเกิด failure ถัดมา UI จึงแสดงคะแนนเหมือนเป็นผลสำเร็จ

Widget probe ส่ง partial ที่ตรงประโยคแล้วส่ง `noMatch`: หน้าจอยังมี `100%` ทั้งที่ไม่มีการบันทึกคำตอบสำเร็จ

**แนวทางแก้/ตรวจรับ:** คะแนนผลลัพธ์ต้องอ้าง final ที่ยอมรับแล้ว หรือระบุชัดว่าเป็น preview และล้างเมื่อผิดพลาด ตรวจ partial → failure, partial → cancel และ final สำเร็จ หลักฐาน: ส่วน shadowing ใน `derived-reproductions.log`

### 06. [P2 · S] กลับเข้า associative reading กลางทางแล้วสรุป recall เป็น 0/N

[associative_reading_session_screen.dart:291](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/screens/associative_reading_session_screen.dart:291) เริ่มรายการ recall results ว่าง เมื่อ resume โหลด stage/completed state กลับ แต่ไม่ได้กู้ผล recall ที่ใช้ใน summary บรรทัด 1401 เป็นต้นไป

เงื่อนไข: ตอบ recall ใน stage 3 แล้ว checkpoint ไป stage 4 → ออก → เปิดใหม่ → ทำส่วนที่เหลือ หน้าสรุปนับจากรายการในหน่วยความจำใหม่จึงกลายเป็น 0/N แม้มีคำตอบเดิม เส้นทาง resume สร้าง canonical session ใหม่ด้วย จึงต้องพิจารณา linkage ของผลเดิมอย่างชัดเจน

**แนวทางแก้/ตรวจรับ:** กู้ผลจากหลักฐาน/เซสชันที่ checkpoint อ้างถึงอย่างถูกต้อง หรือแสดงว่าผลส่วนเดิมไม่พร้อมใช้แทนคะแนนศูนย์ ตรวจ resume ก่อน/หลัง recall และเปรียบเทียบ summary กับ durable attempts

### 07. [P2 · R] สถิติทักษะไม่นับชื่อโหมดคำตอบที่ adapter ปัจจุบันส่ง

[drift_progress_queries.dart:449](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/progress/data/drift_progress_queries.dart:449) จัดกลุ่ม pronunciation/retention ด้วยรายการชื่อเก่า ไม่ครอบ `pronunciationTranscript`, `typedRecall`, `associativeRecall` ที่ producers ปัจจุบันใช้ ผลรวม attempts เพิ่ม แต่ทักษะเฉพาะยัง 0 และ personal profile อาจตัดทักษะนั้นออกเพราะไม่มี sample

ทดสอบ query ด้วยคำตอบสังเคราะห์ที่ยอมรับแล้ว 2 กรณี: total sample 1 แต่ pronunciation/retention sample 0 ตรวจชื่อ producer จาก adapter แยกประกอบแล้ว Probe นี้ยืนยันชั้น mapping ไม่ใช่ native speech ทั้งเส้นทาง

**แนวทางแก้/ตรวจรับ:** ใช้ mapping ของประเภทหลักฐานร่วมกัน และเพิ่ม test จาก adapter จริงถึง progress/profile หลักฐาน: `data-reproductions.log`

### 08. [P2 · R] ลบคำศัพท์แล้วจำนวนคำถึงกำหนดยังรวมคำนั้น

[drift_progress_queries.dart:63](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/progress/data/drift_progress_queries.dart:63) นับ SRS state โดยไม่กรองคำที่ถูกลบ ต่างจากคิวทบทวนที่กรอง availability ของคำ การเก็บ SRS history หลัง soft delete เป็นพฤติกรรมที่มีอยู่แล้ว

Probe สร้างคำถึงกำหนดแล้วลบผ่าน vocabulary repository จริง: คิวทบทวนว่าง แต่ dashboard due count ยังเป็น 1

**แนวทางแก้/ตรวจรับ:** ใช้ predicate ของคำที่ยังทบทวนได้กับตัวเลข actionable due โดยรักษาประวัติเดิม ตรวจ personal/deleted/packaged words หลักฐาน: `data-reproductions.log`

### 09. [P2 · R] SRS เพิ่มช่วงทบทวนไม่จำกัดจนวันนัดล้นย้อนอดีต

[srs_policy.dart:35](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/learning/domain/srs_policy.dart:35) เพิ่ม interval เป็นสองเท่าโดยไม่มีเพดาน เส้นทางบันทึกคำตอบไม่ได้บังคับว่าต้องรอถึง due ก่อนจึงจะเพิ่มช่วงนี้ได้

Probe ตอบถูกต่อเนื่อง 27 ครั้งได้ interval 117,440,512 วัน และ due date `-260987-11-03T15:58:10.448384Z` ใน Dart runtime ที่ทดสอบ เป็นการล้นจนวันผิด **ไม่ได้เกิด exception/transaction rollback ตามข้อสงสัยแรก**

**แนวทางแก้/ตรวจรับ:** กำหนดเพดาน interval/date ที่มีความหมายกับการเรียน และตรวจ long sequence, correct/incorrect สลับกัน, replay หลักฐาน: `reproductions-verified.log`

### 10. [P2 · R] ภารกิจอายุ 24 ชั่วโมงยังรับคำตอบของอีกสองวันถัดไป

[quest_use_cases.dart:178](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/quest/application/quest_use_cases.dart:178) ตรวจเวลาหลัง assignment แต่ไม่ตรวจ expiry เส้นทาง bootstrap เรียก `startQuest` โดยไม่เรียก `expireStale`; helper `seedOnStartup` ที่เรียก expiry ไม่มี production caller ที่พบ

Probe สร้าง daily quest วันที่ 4 แล้วจำลองเปิดแอปและตอบ 5 ข้อวันที่ 6: instance เดิมยัง complete ได้ ทั้งที่ catalog กำหนด 24 ชั่วโมง ประเด็นนี้ต่างจากข้อ 02 เพราะเกิดกับ instance ที่ยังไม่จบ

**แนวทางแก้/ตรวจรับ:** บังคับช่วงเวลาที่รับหลักฐานในเส้นทางจริง พร้อมรักษาการ replay เหตุการณ์ที่เกิดภายในช่วงเดิม ตรวจ expiry boundary ตามเวลาที่เกิดคำตอบ หลักฐาน: `quest-notification-verified.log`

### 11. [P2 · R] เลือกความชอบแบบอ่าน แต่ production recommendation ตัดโหมดอ่านออก

[app_bootstrap.dart:1365](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/runtime/app_bootstrap.dart:1365) สร้าง availability เฉพาะ `ActiveRecallLadder.canonicalModes` ซึ่งไม่มี CEFR/associative reading แม้ registry เปิดโหมดอ่าน และ recommendation รองรับ reading preference

Probe เดียวกันเมื่อใช้ availability ครบได้ CEFR reading เป็นอันดับแรก แต่เมื่อใช้รูปแบบ map ของ bootstrap ได้ flashcard และไม่มี reading ใน alternatives เป็นข้อผิดของการประกอบ dependency ไม่ใช่ความชอบที่ผู้เรียนบันทึกหาย

**แนวทางแก้/ตรวจรับ:** สร้าง availability จากโหมดที่ recommendation รองรับและสถานะ registration/feature จริง ตรวจผ่าน runtime factory และ TodayHub รวมโหมดถูกปิด หลักฐาน: `final-boundary-reproductions.log`

### 12. [P2 · S] หน้าแจ้งเตือนรายงานว่าเปิดแล้วทั้งที่ยังรอ schedule ใหม่

[study_reminder_settings_screen.dart:179](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/screens/study_reminder_settings_screen.dart:179) ใช้ `reminder.isEnabled` แสดงสถานะเปิดเตือน แต่ค่านี้เป็น desired state ที่ถูกบันทึกก่อนเรียก OS เมื่อ schedule ล้ม use case คืน `pendingRetry` และยังเก็บ enabled ไว้

เมื่อเปิดหน้ากลับมาใหม่ ข้อความผิดพลาดชั่วคราวหาย แต่แถวรายการยังแสดงเหมือนพร้อมเตือน การตรวจจาก use case และเทสต์ schedule failure เดิมยืนยันว่ามี desired-enabled/pending-retry state นี้จริง ยังไม่ได้ทำ widget reproduction ใหม่ครบการเปิดกลับในรอบนี้

**แนวทางแก้/ตรวจรับ:** ให้ UI แสดง desired/scheduled/pending retry/permission จากสถานะที่ตรวจได้จริง ตรวจ schedule failure → ปิดหน้า → เปิดใหม่ → retry สำเร็จ

### 13. [P2 · R] ถอนสิทธิ์แจ้งเตือนใน OS แล้ว gateway ยังคืน granted

[platform_reminder_scheduler.dart:167](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/reminders/data/platform_reminder_scheduler.dart:167) เมื่อ OS คืน notifications disabled กลับใช้ `_lastRequestedPermission` ที่เคยเป็น granted ตัว cache จึงชนะสถานะปัจจุบัน

Probe ผ่าน production gateway และ Android plugin method channel จำลอง: request permission ได้ true จากนั้น OS status เป็น false แต่ผลยัง `granted` ไม่ได้ทดสอบเปลี่ยน permission บนเครื่องจริง และไม่ได้หมายความว่าแอปส่ง notification ฝ่าฝืน OS ได้

**แนวทางแก้/ตรวจรับ:** ให้ผล OS ที่ชัดเจนมีสิทธิเหนือ cache แยก denied ออกจากอ่านสถานะไม่ได้ ตรวจ grant → revoke → กลับแอปใน process เดิม หลักฐาน: `quest-notification-verified.log`

### 14. [P2 · R] Worker อาจสร้าง reminder ของเจ้าของเดิมกลับมาระหว่างเปลี่ยนเจ้าของ

[study_reminder_use_cases.dart:307](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/reminders/application/study_reminder_use_cases.dart:307) ยกเลิก source notifications ก่อนรอ owner operation โดยไม่มี durable fence ครอบช่วงนี้ และไม่กวาด source ซ้ำหลังสำเร็จ Target reconcile ข้าม entry ต่าง owner Worker มีเส้นทาง bootstrap reminder ก่อนเข้า sync-engine gate

จำลองสอง repository/use-case instances บนฐานข้อมูลเดียว: A ถูกยกเลิก → อีก instance reconcile ขณะที่ A ยัง active → เปลี่ยนเป็น B → A notification ยังอยู่ เป็นการจำลอง interleaving ไม่ใช่การรัน Workmanager บน Android จริง ข้อความเตือนปัจจุบันเป็นข้อความทั่วไป จึงไม่อ้างว่าพบการเปิดเผยข้อมูลส่วนตัว

**แนวทางแก้/ตรวจรับ:** ให้ canonical owner lease/fence ครอบ source cleanup และ transition พร้อม final sweep ที่ใช้ ID เดิม ตรวจ worker ก่อน/ระหว่าง/หลัง transition และ rollback หลักฐาน: `final-boundary-reproductions.log`

### 15. [P2 · R] กู้ bookmark เดียวกันให้คนละบัญชีในเครื่องเดียวแล้วชน primary key

[drift_sync_store.dart:3147](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/sync/data/drift_sync_store.dart:3147) ใช้ wire entity ID เป็น local saved-item primary key โดย wire ID ของ public content/revision ไม่รวม owner แต่ local table ใช้ `id` เดี่ยวเป็น primary key

Probe ให้สอง owner pull bookmark ของเนื้อหาเดียวกัน: owner แรกสำเร็จ คนที่สองติด Sqlite 1555 UNIQUE `saved_learning_items.id` ทำให้ restore/pull ไม่สำเร็จ **ไม่ได้พบการเขียนทับหรืออ่านข้อมูลข้าม owner**

**แนวทางแก้/ตรวจรับ:** แยก local identity ที่รวม owner ออกจาก wire identity โดยรักษา sync contract ตรวจ multi-account restore และ round trip/deletion/export หลักฐาน: `data-reproductions.log`

### 16. [P2 · R] ถอน research consent แล้วยอมรับใหม่ก่อนส่ง withdrawal ทำให้ส่งคำถอนเดิมไม่ได้

[drift_research_consent_repository.dart:78](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/consent/data/drift_research_consent_repository.dart:78) ล้าง withdrawn timestamp เมื่อ accept ใหม่ ส่วน [drift_research_sync_adapter.dart:1174](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/sync/data/drift_research_sync_adapter.dart:1174) ต้องอาศัย withdrawn consent หรือ withdrawn run ปัจจุบันเพื่อให้ claim งาน withdrawal ได้

Probe import permit โดยยังไม่มี measurement run → withdraw มีงานค้าง 1 → accept ใหม่ → claim withdrawal ได้ 0 ผลคือ remote denial/tombstone ไม่ถูกส่งตาม intent เดิม ขอบเขตสำคัญ: local permit เดิมถูกปฏิเสธอยู่แล้วเพราะ consent ใหม่ใหม่กว่า permit; **ไม่ได้เป็นการ bypass consent ในเครื่องนี้** ปัญหาคือการกระจายคำถอนให้ปลายทาง/อีกเครื่อง

**แนวทางแก้/ตรวจรับ:** เก็บ withdrawal intent ที่คงอยู่ได้โดยไม่พึ่ง consent read model ที่เปลี่ยนภายหลัง ตรวจ offline withdraw → reaccept → reconnect ทั้งมี/ไม่มี run และสองอุปกรณ์ด้วย synthetic authority หลักฐาน: `reproductions-verified.log`

### 17. [P2 · R] Research mission events กู้ลงเครื่องใหม่ไม่ได้เพราะ session ที่ sync มามีข้อมูลไม่ครบ

[drift_research_sync_authorizer.dart:710](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/research/data/drift_research_sync_authorizer.dart:710) ต้องใช้ canonical session start/end/state ตรวจ Started/Completed แต่ [drift_sync_store.dart:4146](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/sync/data/drift_sync_store.dart:4146) สร้าง session placeholder จาก answer evidence ด้วยสถานะ `syncedEvidence`, เวลา first answer และไม่มี end time ไม่มี session collection ที่นำข้อมูลครบมาเติมในเส้นทางที่ตรวจ

Differential probe: Completed event ที่ canonical session ครบได้รับอนุญาต เมื่อเปลี่ยน session ให้ตรงรูปแบบที่ pull สร้าง กลับถูกปฏิเสธ Started มีความคลาดเคลื่อน start/first-answer จากเส้นทางโค้ดเช่นกัน การปฏิเสธเป็น fail-closed ที่ถูกต้องเมื่อหลักฐานไม่ครบ; ปัญหาอยู่ที่ contract ของข้อมูลสำหรับ restore ไม่ใช่ควรลดความเข้มของ authorizer

**แนวทางแก้/ตรวจรับ:** ทำให้ข้อมูลที่ restore เพียงพอและตรวจสอบที่มาได้ แล้วทดสอบ fresh-device pull ทั้ง Presented/Started/Completed พร้อม pin/consent rejection หลักฐาน: mission case ใน `additional-reproductions.log`

### 18. [P2 · R] ดาวน์โหลดโมเดลครบแต่ยังเป็น .partial แล้วกู้ต่อไม่สำเร็จ

[model_download_manager.dart:347](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/device_model/application/model_download_manager.dart:347) ตรวจเฉพาะ partial ที่ใหญ่กว่า expected เมื่อขนาดเท่ากันยังส่ง Range เริ่มที่ EOF หากเซิร์ฟเวอร์คืน 416 จะปฏิเสธและคง partial เดิมไว้

เกิดได้เมื่อ process หยุดหลังเขียนครบก่อน verify/rename Probe เรียกซ้ำสองครั้งได้ offset `[20,20]`, `invalidResponse` ทั้งคู่ และ partial ยังอยู่ ไม่เหมารวมกับ offline content manager ที่มีกลไกกู้ไฟล์เต็ม หรือ voice catalog แบบ bundled ที่รองรับ EOF อยู่แล้ว

**แนวทางแก้/ตรวจรับ:** ตรวจ checksum/activate ไฟล์ครบที่มีอยู่ก่อนเริ่ม network และจัดการ 416 ตามขนาดจริง ตรวจครบ/เกิน/เสียหาย/ถูกยกเลิก หลักฐาน: model case ใน `derived-reproductions.log`

### 19. [P2 · R] AI และ Voice API ข้าม body-size limit ได้เมื่อไม่มี Content-Length

[AI app.py:60](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/backend/ai_api/src/lexiquest_ai/app.py:60) และ [Voice app.py:44](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/backend/voice_api/src/lexiquest_voice/app.py:44) ตรวจขนาดเฉพาะ header ไม่ได้นับ body ที่รับจริง คำขอแบบ chunked จึงผ่านขีดจำกัด และ field-length validator ไม่ป้องกัน whitespace จำนวนมากท้าย JSON

Local TestClient probes ใช้ JSON ที่ถูกต้องเติม whitespace เกิน 100 KB และไม่มี Content-Length: AI 100,033 bytes / Voice 100,081 bytes ได้ HTTP 200 ทั้งสอง แทน 413 ใช้ fake providers ไม่มีการโจมตีบริการจริง FastAPI โหลด JSON ก่อน auth ภายใน handler จึงควรจำกัดตั้งแต่การรับ body

**แนวทางแก้/ตรวจรับ:** บังคับจำนวน byte ของ streamed body ก่อน parse ตรวจ chunked, header หาย/โกหก, body ขาดช่วง และ token ไม่ถูกต้อง หลักฐาน: `ai-body-probe.log`, `voice-body-probe.log`

### 20. [P2 · R] AI HTTP adapter ทิ้ง Retry-After ของผู้ให้บริการ

[llm_content_service.py:143](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/backend/ai_api/src/lexiquest_ai/services/llm_content_service.py:143) เก็บ response เฉพาะ status/body ทำให้ parser ที่อ่าน header ไม่เห็น Retry-After เมื่อ upstream ตอบ 429 เส้นทางจริงจึงใช้ fallback 5 วินาที

Probe mock urllib HTTPError พร้อม Retry-After 3600: parser ได้ 0 และเวลารอที่เลือกเป็น 5 ไม่มีการเรียกผู้ให้บริการจริง

**แนวทางแก้/ตรวจรับ:** เก็บ headers ใน HTTP adapter และตรวจ 429/503 ตามรูปแบบที่บริการรองรับ โดยมี fallback เมื่อ header ใช้ไม่ได้ หลักฐาน: `retry-after-probe.log`

### 21. [P2 · R] Validation error ตอนตั้งค่า AI อาจพิมพ์ credential ที่ฝังใน URL

[config.py:97](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/backend/ai_api/src/lexiquest_ai/config.py:97) ไม่ตั้ง `hide_input_in_errors` แม้ validator ปฏิเสธ userinfo ใน URL ข้อความ Pydantic ValidationError ยังมี input ต้นฉบับ และ traceback ระหว่าง startup จึงอาจแสดง credential ที่ผู้ดูแลใส่ผิดตำแหน่ง

Probe ใช้ credential canary สังเคราะห์ใน URL สั้น พบ canary ใน `str(ValidationError)` รายงานเฉพาะ boolean ไม่มีการตรวจหรือเปิดเผย secret จริง Test เดิมที่ใช้ข้อความยาวอาจไม่พบเพราะ representation ถูกตัดสั้น

**แนวทางแก้/ตรวจรับ:** ปิดการแสดง input ใน validation errors และตรวจ startup/error output ด้วย canary ทั้งสั้น/ยาว โดยยังปฏิเสธ URL ที่ไม่อนุญาต หลักฐาน: `config-canary-probe.log`

### 22. [P2 · S] คู่มือ deploy LM ต่อ Flutter เข้ากับ API คนละ contract

[DEPLOY.md:128](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/backend/lexiquest_lm/scripts/DEPLOY.md:128) ให้ตั้ง `LEXIQUEST_AI_API_URL` เป็น LM Space โดยตรง แต่ [content_provider.dart:80](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/ai/content_provider.dart:80) เรียก `/v1/content` ส่วน Space ประกาศ `/v1/chat/completions` และคืน response คนละรูปแบบ

ทำตามคู่มือแล้ว content provider จะเรียก route ที่ไม่มีอยู่ ไม่ได้ต่อผ่าน AI API adapter ที่รองรับ contract นี้ การอ่าน local server routes/Docker ไม่พบ proxy แปลงให้ ไม่ได้ deploy หรือเรียก Space จริงในรอบนี้

**แนวทางแก้/ตรวจรับ:** ให้คู่มือและ deployment topology เชื่อม content API → LM อย่างถูกต้อง หรือมี adapter ที่ตรวจรับครบ พร้อม contract test ของ Flutter request/response

### 23. [P2 · S] ตัวเซ็นหลักฐาน Android อ่านรูปแบบไฟล์จาก collector ไม่ตรงกัน

[sign-android-field-evidence-result.ps1:79](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/tool/cli/sign-android-field-evidence-result.ps1:79) อ่าน `$device.physical` จากเอกสารทั้งก้อน แต่ [collect-android-field-evidence.ps1:532](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/tool/cli/collect-android-field-evidence.ps1:532) เขียนค่าภายใต้ `device.physical` เมื่อเปิด StrictMode จึงเกิด property-not-found ก่อนถึงขั้นใช้ certificate

กระทบการเซ็นผล Journey/CPU/GPU/Endurance จาก collector ชุดนี้ Tests ปัจจุบันบริเวณที่เกี่ยวข้องตรวจข้อความใน source จึงไม่พบ producer/consumer mismatch ไม่ได้ใช้ certificate store หรือเซ็นหลักฐานจริงในการ review

**แนวทางแก้/ตรวจรับ:** อ่าน envelope ให้ตรง schema และทำ synthetic collector-record → signer validation round trip ก่อนเข้าขั้น cryptographic signing

### 24. [P2 · R] คำตั้งต้นของแอปหลุดจาก pipeline เตรียมข้อมูลฝึก LM

[expand_wordlist.py:2189](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/backend/lexiquest_lm/dataset/expand_wordlist.py:2189) ลบคำ seed ออกจาก expansion แล้ว [enrich_dictionary.py:252](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/backend/lexiquest_lm/dataset/enrich_dictionary.py:252) วนเฉพาะ expansion โดยไม่เพิ่ม seed-only words กลับ การ merge ค่าจาก seed จึงไม่ทำงานตาม default pipeline คำและความหมายไทยที่ตั้งใจรักษาไว้หลุดก่อน generate

Probe ใช้ main ของ enrich จริงแต่ mock API/I/O: seed `dog`, expansion ก่อน dedupe `dog,cat` → output มีเพียง `cat` และ exit 0 การ generate/merge ปกติไม่ได้อ่าน seed กลับมาเอง ข้อนี้ไม่ได้หมายความว่าคำดังกล่าวหายจาก vocabulary DB ในแอป

**แนวทางแก้/ตรวจรับ:** รวม seed และ expansion แบบรักษาฟิลด์ curated ก่อน enrich ตรวจ collect → expand → enrich → generate → merge ด้วย fixture ชุดเล็ก หลักฐาน: `lm-pipeline-reproductions.log`

### 25. [P2 · R] ตัวสร้างข้อมูลฝึกนำ pronoun ไปใส่ช่องคำนามจนประโยคผิด

[generate_synthetic.py:198](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/backend/lexiquest_lm/dataset/generate_synthetic.py:198) ตรวจ substring `noun` ก่อน `pronoun` จึงจัด Pronoun เป็น noun คำจริงใน bundled input เช่น `he`, `she`, `they` เข้ากรณีนี้

Probe `he/Pronoun/A1` สร้าง positive training responses เช่น `The he is here.` และ `Ana sees a he.` แล้วเส้นทาง generate ปกติเขียน rows เหล่านี้ส่งเข้าชุดฝึก

**แนวทางแก้/ตรวจรับ:** จัดชนิดคำให้ไม่ชน substring และตรวจ output ตามชนิดคำ/รูปคำ รวม review คุณภาพภาษาของ template ก่อนฝึกใหม่ ผลนี้ยังไม่ใช่การวัดความแม่นยำของโมเดล หลักฐาน: `lm-pipeline-reproductions.log`

### 26. [P2 · R] ระบุ adapter ที่ไม่มีอยู่ แต่ผลประเมินอ้างว่าได้ประเมิน adapter นั้น

[evaluate.py:213](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/backend/lexiquest_lm/train/evaluate.py:213) ใช้ base model ถ้า adapter path ไม่มีอยู่ แต่บรรทัด 249 ยังบันทึกชื่อ adapter ที่ระบุเป็น checkpoint และจบด้วย exit 0

Probe mock model loaders/report writer: adapter loads 0, ประเมิน base model จริงใน control flow แต่ report checkpoint เป็น `review-missing-adapter` ไม่ได้โหลดโมเดลหรือดาวน์โหลด artifact

**แนวทางแก้/ตรวจรับ:** ถ้าระบุ adapter แล้วหาไม่พบต้องหยุดก่อนประเมิน และผูก report กับ artifact ที่โหลดจริง ตรวจไม่ระบุ adapter/ระบุถูก/ระบุผิด/ไฟล์เสีย หลักฐาน: `lm-pipeline-reproductions.log`

### 27. [P2 · S] ปุ่มลองใหม่ของหน้าหมวดหมู่ไม่ทำอะไร

[categories_page.dart:29](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/screens/categories_page.dart:29) ส่ง `onRetry: () {}` ให้ failure state ปุ่มที่แสดงจึงไม่มีการ reload หรือ subscribe ใหม่ ผู้เรียนที่กดหลังโหลดหมวดหมู่ผิดพลาดไม่สามารถกู้ด้วยปุ่มนี้ได้

**แนวทางแก้/ตรวจรับ:** ผูกปุ่มกับการโหลด stream ใหม่ ตรวจแหล่งข้อมูล error ครั้งแรกแล้วสำเร็จเมื่อกดลองใหม่ เป็นข้อยืนยันจาก callback โดยตรง ยังไม่ได้ทำ widget reproduction ใหม่

### 28. [P3 · S] Goal countdown อาจคลาดหนึ่งวันบนเครื่องที่ใช้เขตเวลา DST

[learning_goal_use_cases.dart:120](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/goals/application/learning_goal_use_cases.dart:120) ใช้ `difference.inDays` ของค่าที่ [timezone_policy.dart:34](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/motivation/domain/timezone_policy.dart:34) สร้างเป็น system-local DateTime ถ้าสองเที่ยงคืนห่าง 23 ชั่วโมงจากการเปลี่ยน DST จะได้ 0 วัน เช่น New York 8→9 มีนาคม 2026

เงื่อนไขนี้ขึ้นกับ timezone ของเครื่อง; ไม่ได้จำลองบนอุปกรณ์ DST และไม่เปลี่ยน timezone เครื่องผู้ใช้ในการตรวจ ระบบใน Asia/Bangkok ไม่ได้มีการเปลี่ยน DST ลักษณะนี้

**แนวทางแก้/ตรวจรับ:** คำนวณวันปฏิทินจาก UTC date fields หรือ day ordinal หลังแปลงตาม timezone ที่ pin ไว้ ตามแบบที่ StreakPolicy ใช้ ตรวจ spring/fall transition และ timezone ของเครื่องต่างจากเป้าหมาย

### 29. [P3 · S] จำนวน token ที่ไม่ทราบถูกแสดงเป็นศูนย์

[drift_ai_usage_repository.dart:184](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/lib/features/ai_tutor/data/drift_ai_usage_repository.dart:184) รวม `totalTokens ?? 0` โดยไม่เก็บความไม่ครบของข้อมูล Gemini adapter ปัจจุบันคืนเฉพาะข้อความ ไม่มี token metadata จึงแสดง `N คำขอ · 0 หน่วยข้อความ` ในหน้าสถิติ

ไม่ใช่ข้อกล่าวหาว่าหน้าจอรับรองค่าใช้จ่ายเป็นศูนย์ เพราะ UI แยก unknown cost อยู่แล้ว ประเด็นคือจำนวนหน่วยข้อความถูกนำเสนอเป็นค่าที่ทราบ

**แนวทางแก้/ตรวจรับ:** รักษา unknown/partial aggregate ถึง UI หรืออ่าน usage metadata ที่มีอยู่ ตรวจ success ที่ไม่มี token data และชุดข้อมูลผสม known/unknown

## หลักฐานที่รันใหม่ในรอบนี้

หลักฐานทั้งหมดอยู่ที่ [โฟลเดอร์ตรวจ](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/code-review-20260909) ไม่มีการแก้ assertion ของ test suite เดิม Probes ใหม่ตั้ง expectation ของพฤติกรรมที่ควรเป็น จึง **ตั้งใจให้ fail เมื่อยืนยันบั๊กปัจจุบัน** ไม่ใช่บั๊กที่เกิดจากการแก้แอปในรอบนี้

| หลักฐาน | ผลที่ใช้สรุป |
| --- | --- |
| [analysis.log](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/code-review-20260909/analysis.log) | `flutter analyze --no-pub lib test integration_test test_driver assets tool tools` exit 0, No issues found |
| [reproductions-verified.log](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/code-review-20260909/reproductions-verified.log) | 3 failing expectations: SRS, stop/final, withdrawal |
| [data-reproductions.log](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/code-review-20260909/data-reproductions.log) | 4 failing expectations: skill mapping 2 แบบ, due count, saved ID |
| [derived-reproductions.log](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/code-review-20260909/derived-reproductions.log) | ใช้ shadowing และ model partial รวม 2 กรณี; mission ที่ซ้ำใน fixture รุ่นแรกไม่นับเพิ่ม |
| [additional-reproductions.log](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/code-review-20260909/additional-reproductions.log) | 2 failing expectations: mission differential ที่แยกเดี่ยวแล้ว และ cloud voice |
| [ai-body-probe.log](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/code-review-20260909/ai-body-probe.log), [voice-body-probe.log](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/code-review-20260909/voice-body-probe.log) | HTTP 200 แทน 413 จำนวน 2 กรณี; ไม่ใช้ diagnostic providerCalls ของ Voice ซึ่ง fake ไม่ได้เก็บ counter |
| [retry-after-probe.log](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/code-review-20260909/retry-after-probe.log) | Retry-After 3600 ถูกลดเป็น fallback 5 |
| [config-canary-probe.log](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/code-review-20260909/config-canary-probe.log) | syntheticCredentialVisibleInValidationError=true |
| [quest-notification-verified.log](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/code-review-20260909/quest-notification-verified.log) | 3 failing expectations: daily renewal, expiry และ cached notification permission |
| [lm-pipeline-reproductions.log](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/code-review-20260909/lm-pipeline-reproductions.log) | 3 failing expectations: missing adapter, Pronoun และ seed loss |
| [final-boundary-reproductions.log](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/code-review-20260909/final-boundary-reproductions.log) | 2 failing expectations: recommendation availability และ reminder owner transition |
| [review-route-verified.log](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/code-review-20260909/review-route-verified.log) | active lesson, attempts 0, answer/finish controls 0 |

รวม **24 สถานการณ์ที่มี failing expectation ตรงกับข้อบกพร่อง 22 ประเด็น** ไม่รวม loader/setup/teardown, fixture failures, duplicate cases หรือการรันทวนเพื่อปรับเครื่องมือจำลอง ไม่มีการนับผลชุดใหญ่ใน checkpoint เก่าเป็นการรันใหม่ของรอบนี้

Flutter probes รันแบบ `--no-pub --reporter expanded --concurrency 1 --plain-name 'REVIEW:'` และ serialize toolchain ใน worktree นี้ Python probes ใช้ mock loaders/HTTP หรือ backend TestClient ไม่ดาวน์โหลดโมเดลและไม่เรียก upstream จริง ไม่มี build APK, full regression, emulator/physical-device UAT หรือการทดสอบต่อเนื่อง 3 ชั่วโมงใหม่ในรอบ review นี้

## ข้อสงสัยที่ตรวจแล้วถอนหรือจำกัดขอบเขต

- **ถอน daily reward farming:** UNIQUE ใน schema ปัจจุบันป้องกันการสร้างรอบซ้ำ ผลจริงคือเริ่มรอบใหม่ไม่ได้ตามข้อ 02
- **ถอน quest recovery หลัง 64 instances:** trigger ที่เสนอสร้างหลาย completed instances ของ quest เดิมไม่ได้ภายใต้ UNIQUE ปัจจุบัน และ catalog lookup มีขอบเขต 64 ไม่เปลี่ยน schema เพื่อบังคับให้ reproduction เกิด
- **ไม่อ้าง local consent bypass:** consent ใหม่ทำให้ permit เดิมไม่ผ่าน local decision อยู่แล้ว ข้อ 16 เป็น durable withdrawal delivery
- **ไม่อ้าง saved-item leakage:** ข้อ 15 พบ constraint failure ไม่ใช่การอ่านหรือเขียนทับอีกเจ้าของ
- **จำกัด model partial:** offline content manager หลักมี complete-orphan recovery และ bundled voice source รองรับ EOF ไม่รวมเป็นบั๊กเดียวกันโดยไม่มีหลักฐาน
- **ไม่ยก helper ที่ไม่มี production caller เป็นบั๊กใช้งานจริง:** mirror/voice helper บางเส้นทาง และ Adventure Pair helper ที่พบแต่ test callers ระบุเป็นข้อจำกัด integration coverage
- **แก้ fixture ก่อนใช้สรุป:** notification probe รุ่นแรกยังไม่ register platform; quest probe รุ่นแรกสมมติ schema ผิด; mission probe รุ่นแรกถูกวางใน loop; review route probe รุ่นแรกนับ Material 3 back button เป็น answer control รายงานใช้ผลที่แก้การวัดและระบุไว้ข้างต้นเท่านั้น

## ขอบเขตการตรวจและข้อจำกัด

อ่านแผน/checkpoint/guardrails ปัจจุบัน ทำ inventory และตรวจรอยต่อของโค้ดที่เขียนเองร่วมกับ reviewer 3 คน โดยตัวหลักทวนข้อค้นพบและรัน reproduction แยกจาก reviewer ครอบคลุม:

- Runtime/bootstrap/feature composition, navigation/lesson shell, learning modes และหลักฐานคำตอบ
- Progress/SRS, vocabulary/starter content, review/bookmark/report, associative reading, history, recommendation/Today, Adventure entry/result
- Quest/rewards/motivation/streak, goals/preferences/reminders, active learning/focus time
- Identity/account/owner upgrade, local deletion/export, schema/migration guards, sync/outbox/policies, consent/assessment/research authorization
- Camera/model lifecycle/download, speech practice, voice routing/cache/playback, AI content/AI Tutor, credential version/index/owner cleanup, offline packs
- AI/Voice backend HTTP/auth/config/providers, LM serving/deploy/dataset/train/evaluation และเทสต์ pipeline
- Android runtime/build/signing configuration, CI และ CLI collector/signing/field evidence validation

ไม่ได้รับรองว่าอ่าน generated code/dependency locks ทุกบรรทัด หรือเนื้อหาศัพท์/ทรัพยากรภาพทุกชิ้นถูกต้องทั้งหมด ยังไม่มีผลวัดประสิทธิภาพหรือความแม่นยำโมเดลใหม่ ไม่มีข้อสรุปเรื่องความแม่นยำมากกว่า 90% และไม่ได้แทนที่การทดสอบกล้อง/เสียง/TalkBack ด้วยคนจริง

## Checkpoint และขั้นตอนถัดไป

รายงานนี้จบงาน review โดยคงข้อบกพร่องไว้ให้เห็นและตรวจซ้ำได้ ไม่มี production fixes หรือ test-suite edits และไม่มี process ทดสอบของรอบนี้ค้างอยู่ ตรวจ SHA-256 ของไฟล์เดิม 1,602 ไฟล์เทียบ baseline แล้วตรงกันทั้งหมด; HEAD ไม่เปลี่ยน

ลำดับการแก้ที่เสนอเมื่อเข้าสู่งาน implementation:

1. แก้เส้นทางทบทวนให้จบจริง (01) แล้ววงจรภารกิจรายวัน (02,10) และผลคำตอบ/เสียง/สถิติ (03–09,11)
2. แก้ reminder status/permission/owner transition (12–14) และ bookmark/research restore/withdrawal (15–17) โดยคง owner/consent/signature checks
3. แก้ model download และ backend/data-training boundaries (18–26) ก่อนใช้ผลโมเดลหรือ field evidence ประกอบการปล่อยเวอร์ชัน
4. ปิด retry/countdown/usage presentation (27–29) และเพิ่ม regression ที่ตรวจพฤติกรรมปลายทางจริงของแต่ละข้อ
5. หลังรวมการแก้จึงรัน full regression/policy tests/analysis/build บน snapshot เดียว แล้วทดสอบเส้นทาง UI, อุปกรณ์จริง และชุดต่อเนื่องตามแผนเดิม การผ่าน static analysis เพียงอย่างเดียวยังไม่ใช่หลักฐานว่าข้อค้นพบเหล่านี้ถูกแก้

รายการนี้เป็นแนวทางจาก review ไม่ได้เปลี่ยน approved feature catalog 8/44 หรือ frozen EvidenceContext/EventEnvelopeV2 และไม่ได้อนุมัติ real research enrollment/upload/rollout
