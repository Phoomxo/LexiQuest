# S11 — คำตัดสินอิสระเรื่องแรงจูงใจและวิวัฒนาการ workflow

วันที่ 8 กันยายน 2026 — รายงานวิเคราะห์และแผนตัดสินใจ ยังไม่มี implementation, prototype ใหม่, test/build, device/UAT หรือ rollout จากรอบนี้
Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch: `codex/pair-matching-pm0-pm8`; HEAD: `788e90e62b1694c20945734787723c168b6a6ab2` รวม UI/contextual ที่ยังไม่ commit
S11 เป็นผู้สังเคราะห์คนที่สิบเอ็ด อ่าน initial และ cross-review ทั้งสิบหลังจบรอบโต้แย้ง อ่าน briefing/history/design/process และตรวจจุดชี้ขาดใน working tree เอง
SHA256 ของรายงานทั้งสิบตรงกับ `build/verification/motivation-workflow-review-20260908/ten-review-inputs.json` ตอนตรวจ; จำนวนผู้เห็นด้วยไม่ใช่เหตุผลแทนหลักฐาน

## คำตัดสิน

**เลือกส่งทีละขอบเขต: ทำวงจรเริ่ม–เลือก–ฝึก–เข้าใจผล–กลับมาให้เรียบร้อยก่อน แล้วตัดสิน domain ใหม่จากปัญหาที่เหลือ** เป้าหมายคือแรงจูงใจในการเรียนและการแก้ปัญหาของเด็กไทย ไม่ใช่รายได้หรือเพิ่มเวลาหน้าจอ
ระยะ A รวม P1 ส่วนข้อมูลเป้าหมาย/วันเวลาเดิม, P2 ผลจริง, P4 recovery/เตือนครั้งเดียว และ P5 ภาพเล็กในร้านเมื่อแยกส่งได้; P3 เปิดทางเลือกกิจกรรมเดิมตามสิทธิ์ได้ แต่ยังไม่มี Quest objective ใหม่
**ยังไม่เรียกระยะ A ว่า adaptive weekly plan:** title/deadline/preferences ไม่ได้ระบุว่าเนื้อหาใดช่วยเป้าหมายใด การวางสองการ์ดใกล้กันไม่สร้างความสัมพันธ์นี้
P1 แผนถาวร/P4 recurrence/P3 Quest ใหม่ต้องมีสัญญาและวงจรข้อมูลเฉพาะ; P6 เป็น capability ใหม่ที่เลือกทำ เลื่อน หรือไม่ทำได้ ไม่ใช่หนี้ว่าต้องเพิ่มให้ครบหกข้อ
เทียบสามทางเลือก: ปรับหน้าตาอย่างเดียวไม่พอแก้ความหมายเวลา/ผล/ทางกด; เพิ่มทั้งหกพร้อมกันรวมความเสี่ยงเกินจำเป็น; ทางเลือกที่รับคือ polish พร้อมเชื่อม workflow เดิม แล้วค่อยขยายความสามารถ
อายุหลักยังไม่ยืนยัน: ใช้สมมติฐาน ป.4–ป.6 และมัธยมแยกกันเพื่อทดสอบภาษา/ความเป็นเด็กเกินวัย ไม่ถือว่ากลุ่มใดได้รับอนุมัติหรือเป็นตัวแทนเด็กไทยแล้ว

## สิบบทบาท: รับอะไร เปลี่ยนอะไร และไม่รับอะไร

| บทบาท | ข้อเห็นต่าง/ตำแหน่งที่เปลี่ยนหลัง cross-review | คำตัดสิน S11 และเหตุผล |
| --- | --- | --- |
| U1 ผู้เริ่มต้น | เดิมให้แผนมาก่อนภาพ; รับ SA ว่า deadline ไม่ใช่แผน และรับ U5 ให้ภาพเล็กทำคู่ได้ | รับหนึ่ง next action และการข้ามตั้งเป้า; ไม่รับการซ่อนข้อจำกัดหรือเติมขั้นตอนก่อนเริ่มเพื่อให้ดูครบ |
| U2 ผู้เตรียมสอบ | รับ U3 ให้ลดคิวล้นและรับ U5 เรื่องความสนุก; ยังยืนยันต้องดูวันสอบ/งานจริงได้ | เก็บ deadline กางได้และ review priority; ไม่รับคำว่า “พร้อมสอบ” หรือแผน 15 นาทีเพื่อสอบจากข้อมูลที่ยังไม่ bind |
| U3 ผู้กลับมา | ยอมให้ goal/deadline อยู่รองจากทางกลับมาและรับภาพร้านคู่ระยะแรก | รับ recovery จาก phase จริง; ไม่รับการลบ due/เลื่อนวันสอบเอง; persona ผู้ใหญ่ใช้ท้าทายข้อจำกัดเวลา ไม่แทนเสียงเด็ก |
| U4 การเข้าถึง | เปลี่ยนจากเลื่อน P5 มาเป็นภาพ local เล็ก และรับ motion สั้นเมื่อปิดได้ | รับ polish เป็นเกณฑ์จบงานด้วย; ไม่รับการย่อฟอนต์/ซ่อน label หรืออ้างไฟล์เล็กเท่ากับเครื่องลื่น |
| U5 สำรวจ/เพื่อน | รับ next action ก่อนตัวเลือก ตัดภาพเต็มหน้า/loop และยอมเลื่อนเฉพาะ P5 ถ้าแย่งงานหลัก | รับสิทธิ์สำรวจและภาพของที่สวมจริง; ไม่รับ quest credit จากการเลือกหรือเพื่อนที่ทำให้เกิดหนี้ทีม |
| BA ปัญหาผู้ใช้ | ลดข้ออ้าง goal→งานเมื่อยังไม่มี mapping และยอมให้แก้ UI คู่การรับฟัง | รับปัญหาเด็กมาก่อนรายได้; เกณฑ์ “บอกว่างานช่วยเป้านี้อย่างไร” ใช้หลัง linkage จริงเท่านั้น ไม่ใช่ acceptance ของ A |
| PM ส่งมอบ | แยกแผน/recurrence ออกจาก UI และเพิ่ม D0–D3 หลัง QA ทัก | รับส่งเป็นชิ้นและเลื่อนเฉพาะ dependency ที่ขาด; ไม่ยกระดับ interviews/efficacy เป็นข้อห้ามพัฒนาท้องถิ่นที่อนุมัติแล้ว |
| SA สถาปัตยกรรม | รับภาพเล็กและ route integration แต่คง typed binding/Quest pins | รับว่าแม้ read-only ก็เปลี่ยนความหมายการวัด/การเลือกได้; proposed suggested-action API ยังไม่ใช่ interface ที่มีจริง |
| DEV เชื่อมระบบ | จำกัด P5 เป็น base+ของเดิมหนึ่งชนิด; รวม delegate change ภายใต้ integrator | รับ reuse authority; เพิ่ม implementers ที่ S11 พบเองเพื่อไม่ให้แผนมองข้าม Pair contextual router |
| QA ตรวจรับ | เพิ่ม prototype/visual/flow ข้าง data oracle; ยอม scroll ที่ text200 แทนบังคับพอดีจอ | รับ final-system หลัง UI ทั้งชุดเสร็จ; ไม่รับ golden/host/four exclusions/ผลเดิมเป็น device หรือ learner acceptance |

ข้อเห็นต่างที่ยังคงอยู่คือสัดส่วนความสำคัญของแผนกับการสำรวจและความชอบภาพตามวัย จึงให้ต้นแบบกับเสียงผู้ใช้ตัดสินการขยาย ไม่ใช้คะแนนโหวตของสิบ persona

## ประวัติ → ปัจจุบัน → ความเข้ากันได้

| ฐานการตัดสินใจ | สิ่งที่ต้องรักษาเมื่อปรับแรงจูงใจ |
| --- | --- |
| Local schema เดิมและ V2 3 ส.ค. | เก็บ session/คำตอบ/SRS/คะแนน/ทรัพย์สินเดิม; learning evidence กับ reward authority ชุดเดียว ไม่สร้าง progress ซ้ำ |
| Runtime convergence 8–9 ส.ค. | เรียนในเครื่องเป็นหลัก; cloud/social/ภาพไม่เป็นข้อบังคับ; ผลตรวจผูก source/flags/APK รุ่นจริง |
| Catalog 8 domains/44 capabilities | feature catalog, runtime gate และ research assignment เป็นคนละเรื่อง; ไม่เพิ่ม social แล้วนับว่าอยู่ใน 8/44 เดิมโดยอัตโนมัติ |
| Adventure 1–4 ก.ย. | เป็นทางเลือกเหนือข้อมูลเดิม มี Standard escape; ไม่มี progress authority ใหม่และไม่เพิ่ม bottom tab; no-social เดิมต้องมี extension decision หากเปลี่ยน |
| Research 5 ก.ย. | engineering complete ไม่เท่ากับอนุญาต enroll/upload/efficacy; UI exposure/assignment/snapshot ต้องยังตรง protocol/instrument pins |
| Pair PM0–PM8 5–7 ก.ย. | เรียนต่อ/repair/timeout/replay ใช้ coordinator และ pinned session เดิม; replay ไม่กลับเป็นหลักฐานเรียนครั้งแรก |
| Thai UI 8 ก.ย. | รักษาห้าแท็บ ชื่อไทย ทางเดิม และ primary/secondary actions; ไม่วาง hero ของทุก P แย่งปุ่มเริ่ม |
| Contextual ล่าสุด 8 ก.ย. | spelling/cloze แยกกิจกรรม เลือกก่อนตรวจ; ฟัง/ลองพูดหลัง commit เป็น optional ephemeral unscored; ไม่มี follow-on session อัตโนมัติ |

ตรวจฐานจริง: `lib/data/local/app_database.dart:82` เป็น schema **v24**; `docs/database/schema_ledger.md:463` ระบุ **48 tables** แยกจาก 44 capabilities
`QuestCatalogProvider.version` เป็น **1** ส่วน `RewardCatalog.version` เป็น **2**; เลขเหล่านี้ไม่ใช่ migration version เดียวกัน
ledger v24 ยังเขียน RESERVED แต่ runtime และ checkpoint ล่าสุดเดินถึง v24 แล้ว: เป็นประวัติที่ไม่สอดคล้อง ไม่ใช่ runtime blocker และไม่ใช่เลขว่างให้ใช้ซ้ำ

## ผลกระทบหกข้อและจุดกึ่งกลาง

| ข้อ | ของเดิม/ช่องว่าง | ผลกระทบและความเสี่ยง | ขอบเขตที่รับ / ขอบเขตถัดไป |
| --- | --- | --- | --- |
| P1 เป้าหมาย–สัปดาห์–วันนี้ | Today โหลด goals/reminders แต่ planning view ข้าม; goal ไม่มี content binding | UI/composition ปานกลาง; อ้าง personalization ผิดเป็น semantic risk สูง; แผนข้ามวันเพิ่ม durable state | A แสดงเป้าหมาย/วันกำหนดแยกจากงานวันนี้; B ต้อง explicit goal→content/revision/coverage และแผนที่แก้/ข้าม/คืนค่าได้ |
| P2 พัฒนาการจริง | Profile/History/mastery/SRS/accuracy มีแล้ว แต่บริบทกระจัดกระจาย | เปลี่ยนข้อความก็ทำให้ recognition ถูกเข้าใจเป็น recall หรือ XP เป็นผลเรียนได้ | A สรุป field เดิมพร้อมช่วงเวลา/จำนวน/availability; การนิยาม trend/score ใหม่ต้อง policy/version แม้ไม่เพิ่มตาราง |
| P3 ภารกิจให้เลือก | หลายโหมดพร้อม safe alternatives; Quest v1 ตอบถูก 5/วันและ20/สัปดาห์ | เปลี่ยนทางเลือกไม่เท่ากับเปลี่ยน eligibility; Quest selection/swap/objective กระทบ instance/receipt/economy | A ทางฝึกเดิมจำนวนน้อย; B Quest ใหม่ผ่าน catalog/instance pins, assignment time, expiry และ source receipts เท่านั้น |
| P4 กลับมา–เตือน | มี recovery/longest และ opt-in/cancel/reconcile; UI ยังหนักด้านเวลา | ซ่อนคิวจนงานหาย, streak สื่อผิด, UTC/quiet hours ผิด, OS เตือนคนเก่า | A ยุบ preview โดยคงคิวเต็ม/phase จริงและเตือนครั้งเดียว; B recurrence/exception/cancellation/version แยกจาก deadline |
| P5 ภาพอุปกรณ์ | ownership/equipped มีแล้ว ภาพยังไม่มี | mapping/version ผิด, preview ซื้อเอง, ภาพค้างข้าม owner, memory/motion เพิ่ม | A base+`headgear_ipa` ที่ร้านหนึ่งพื้นที่พร้อมชื่อสำรอง; ไม่เพิ่มสินค้า/ราคา/เลเวล/ธีมทั้งแอป; ขยายภาพหลังวัดจริง |
| P6 เพื่อนสมัครใจ | share card และ Pair Matching ไม่ใช่ friend network | capability/online/data authority ใหม่และภาระดูแลเด็ก; opt-in ไม่ลบแรงกดดันจากกลุ่ม | C เริ่มปัญหา/สถานการณ์สังเคราะห์; ก่อน online ต้องนิยาม identity/invite/leave/block/visibility/lifecycle/cost และ solo parity |

ข้อพบอิสระเพิ่มเติม: `TodayHubActionDelegate` มีห้า methods เดิมและไม่มี `openGoals/openReminders`; การเพิ่มปุ่มจัดการจึงไม่ใช่แค่ render ข้อความ
นอก shortlist DEV ยังมี `_ContextualPairActions` ใน `lib/features/adventure/presentation/adventure_pair_experience.dart:367` และ test doubles ใน `adventure_pair_experience_test.dart`/`pair_measurement_boundary_test.dart`; integrator ต้องดูครบก่อนเปลี่ยน signature
`AdventurePairTodayActions._open` ตรวจ `listEquals(work, action.today.reviewWork)` ก่อนใช้เส้นทาง Pair; การส่งเฉพาะ preview subset จะเปลี่ยนเป็น fallback แม้ไม่เขียนฐานข้อมูล จึงต้องยุบเฉพาะภาพและส่ง `snapshot.reviewWork` เต็มให้ `openReview` พร้อมตรวจ destination เดิม
Today snapshot ยังไม่มี preferences; A ไม่เพิ่มการอ่านเวลาว่างเพื่ออ้างว่าคัดงานตามนาทีแล้ว และไม่ query DB ใน widget build

## ข้อตัดสินระหว่างคุณค่าที่ชนกัน

1. **แผนของ U2 กับภาระของ U3:** แสดงเป้าหมาย/เส้นตายกางได้ รายการทบทวนย่อได้แต่คง exact IDs/order/due dates; หนึ่ง next action มาจากข้อมูลพร้อมใช้และลำดับเดิมของ surface นั้น ไม่บังคับงานหลายชุด
2. **คำแนะนำกับอิสระของ U5:** ผู้เรียนเลือกกิจกรรมเดิมที่ gate/protocol อนุญาตได้; งานที่ไม่ได้เลือกยังคงอยู่ ความชอบไม่ทำให้กิจกรรมที่ไม่ได้สิทธิ์กลายเป็นหลักฐานหรือรางวัล
3. **คุ้นเคยกับหลักสูตรปลอม:** ใช้ลำดับปุ่ม/feedback/พื้นที่ว่างแบบคุ้นเคยจาก Duolingo/ALLTCAS; ไม่วาด path/ด่านปลดล็อกหรือเปอร์เซ็นต์พร้อมสอบที่เนื้อหาไม่รองรับ
4. **ความสวยกับการเข้าถึง:** ภาพมีหน้าที่สื่อผลและตัวตนในพื้นที่รอง ใช้ motion สั้นเมื่อจำเป็น; text200/TalkBack/reduced motion/จอเล็ก/ภาพหายต้องให้สารและทางเรียนครบ
5. **ความเป็นมิตรกับหลักฐาน:** ชมการกระทำที่ commit จริง แยก learning/motivation/retention/reward; “จำได้เอง” ใช้เมื่อ evidence class และ assistance รองรับเท่านั้น
6. **เริ่มเร็วกับ gate:** เมื่อ Today/planning hidden หรือ dependency ไม่พร้อม Learn ยังใช้ quickstart/โหมดเดิมโดยไม่รอโหลด Today; starter quiz ตาม availability ไม่ใช่ personalized recommendation

## ทิศทางภาพและ anatomy ของหน้าจอที่เสนอ

เลือก “เป็นมิตร มีโครงสร้างชัด”: ใช้ฐานสีน้ำเงินและภาษาไทยเดิม ลำดับข้อความน้อยระดับ ระยะห่างสม่ำเสมอ พร้อมภาพเล็กที่มีความหมาย ไม่ทำให้ดูดิบหรือเด็กเล็กเกินวัยโดยสมมติเอง
S11 เปิดสี่ภาพด้วย `view_image` เอง; ทั้งหมดเป็น renderer fixtures เดิม ไม่ใช่ภาพโทรศัพท์หรือ prototype ของข้อเสนอ:

| ภาพที่เปิดจริง | สิ่งที่เห็นและผลต่อข้อเสนอ |
| --- | --- |
| [Learn 390](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/ui-implementation-20260908/visual/390x844-01-learning.png) | CTA สีน้ำเงินเด่นและห้าแท็บชัดอยู่แล้ว; status ปกติอยู่เหนือเรื่องเรียนและรายการการ์ดกินพื้นที่ จัดน้ำหนักใหม่โดยรักษาทางเดิม |
| [Shop 390](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/ui-implementation-20260908/visual/390x844-06b-shop.png) | หลายกล่องเงา/สถิติ ไม่มีตัวละคร และมีคำ Material 3; ลดกรอบรอง เติม preview จริงหนึ่งแห่ง และใช้คำบอกผลที่ผู้เรียนเห็น |
| [Cloze selected](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/contextual-practice-20260908/visual/390-text100-02-selected.png) | ลำดับโจทย์→เลือก→คำที่เลือก→ตรวจชัด; ขอบโจทย์หนักกว่าหน้า Learn ต้องเทียบ state/theme เดียวก่อนปรับ ไม่ลด contrast ตามรสนิยมอย่างเดียว |
| [Learn text200](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/ui-implementation-20260908/visual/360x800-text200-01-learning.png) | CTA ยังอ่านได้แต่ข้อความกินแนวตั้งและชื่อแท็บตัดบรรทัด; ใช้ scroll/focus ที่ดี ไม่ปิด scaling หรือบังคับทุกอย่างพอดีจอ |

| หน้าจอ | Anatomy และ interaction ที่เป็นเป้าต้นแบบ ยังไม่ได้สร้าง |
| --- | --- |
| Learn | ชื่อหน้า/สถานะที่มีผลต่อการตัดสินใจ → action เด่นตามข้อมูลพร้อมใช้ → เลือกฝึกเอง → ทางรอง วันนี้/แผน/Adventure ตาม gate; คง recovery ที่จำเป็นก่อนเริ่มงานใหม่ |
| Today | resume/assigned/review/recommendation ตาม canonical order → review summary พร้อมปุ่มเปิดรายการเต็มใกล้ summary → goals/reminders กางได้ → continuity; ไม่มี weekly debt ใหม่ |
| Goal/reminder | ชื่อ/ชนิดเป้าหมาย → ปฏิทิน+นาฬิกาท้องถิ่น → สรุป timezone/instant ที่เลือก → บันทึก/ยกเลิก; quiet hours เป็นช่วงนาฬิกาและแยกเตือนครั้งเดียวจาก deadline |
| Lesson/result | progress → โจทย์ → input/selected → ตรวจ → pending/committed feedback → ถัดไป/จบ; ข้ามเสียงเสริมได้ ปุ่มไม่ถูก keyboard บัง ผลกับรางวัลแยกและไม่ฉลองก่อน commit |
| Progress | ข้อเท็จจริงสำคัญหนึ่งเรื่อง → ช่วงเวลา/จำนวนตัวอย่าง/ขอบเขต → details/review/weakness เดิม; empty/unavailable/เทียบไม่ได้พูดตรง ไม่วาดกราฟบังคับขึ้น |
| Shop/avatar | ภาพ base+ของที่รองรับและชื่อ → แยกกำลังลองดู/สวมจริง → ownership/ราคา/เงื่อนไข → ลองดู/ซื้อ/ใช้งาน; ยกเลิก preview กลับของจริง ไม่สัญญาธีมทั้งแอป |

ใช้ `M3Theme`/NotoSansThai/semantic colors เดิม; spacing candidate 4/8/12/16/24/32, page/card เริ่ม16, กลุ่มใหญ่24, body16, title20–24, radius16; ปรับตามภาษา/จอและ OS scaling
เติมช่องว่างภาษา companion ใน Phase A: `ContextualCompanionWidget` ยังแสดง `current.copy` และ semantic label อังกฤษจาก catalog v1 ขณะที่ Adventure มีการเลือกภาษาแล้ว; integrator ปรับเฉพาะ presentation localization ให้ตรงภาษา UI พร้อมตรวจ live-region/input/reduced motion โดยคง reaction signal, catalog identity, commit timing และ evidence/reward semantics เดิม
เป้ากดอย่างน้อย48×48 logical pixels, icon-only มี label, สถานะไม่ใช้สีอย่างเดียว; motion candidate150–200msผ่าน `motionDuration` และ `applyReducedMotionPreference` เดิม เมื่อ reduce motion เปิดได้ final state ทันที
ไม่มี idle loop/เสียง auto/auto scroll/รอฉลองก่อนกดต่อ; ขนาดไฟล์ decode memory และ frame ต้องวัดจริงก่อนกล่าวว่าเบา ไม่ตั้งงบตัวเลขที่ไม่มี baseline
เหตุผลเรื่อง consistency/control/minimalism ใช้ [Nielsen heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/); autonomy/competence/relatedness ใช้ [Ryan–Deci 2000](https://selfdeterminationtheory.org/SDT/documents/2000_RyanDeci_SDT.pdf) เป็นคำถามออกแบบ ไม่ใช่ผลทดลอง LexiQuest
แบบอย่าง [Duolingo tabs](https://blog.duolingo.com/core-tabs-redesign/) และ [home redesign](https://blog.duolingo.com/new-duolingo-home-screen-design/) ใช้ hierarchy/next action; [ALLTCAS](https://alltcas.com/) ใช้บริบทฝึกโจทย์/คำอธิบาย/สถิติ ไม่คัดลอกแบรนด์หรืออ้างว่าเดิน native app ทุกหน้า
recognition ใน UX ช่วยจำเมนูและวิธีใช้ **ไม่อนุญาตเติมเฉลยหรือตัวเลือกใน independentRecall แล้วคง evidence class เดิม**; [W3C motion](https://www.w3.org/WAI/WCAG22/Understanding/animation-from-interactions.html) เป็นแนวทางเว็บ AAA ไม่ใช่ใบรับรองแอปผ่านทุกข้อ

## ปัญหาเด็กไทย หลักฐานสาธารณะ และการรับฟังจริง

อาศัยแหล่ง E1–E5 ที่ BA ค้นเมื่อ8ก.ย.และระบุขอบเขตการเข้าถึงไว้แล้ว S11 ไม่อ้างว่าค้นเว็บ/สัมภาษณ์ใหม่หรืออ่าน PDF เต็มทุกฉบับในรอบสังเคราะห์
E1 [PISA Thailand](https://www.oecd.org/en/publications/pisa-2022-results-volume-i-and-ii-country-notes_ed6fbcc5-en/thailand_6138f4af-en.html): self-report ของเด็กอายุ15ในบริบท remote learning ช่วยตั้งโจทย์คำสั่ง/การช่วยเหลือ ไม่ยืนยันว่าเด็กไทยขาดแรงจูงใจภาษาอังกฤษ
E2 [MICS 2022](https://www.unicef.org/thailand/media/11356/file/Thailand%20MICS%202022%20full%20report%20%28English%29.pdf): internet/เครื่องต่างกันระหว่างครัวเรือน ช่วยตั้งโจทย์ offline/เครื่องร่วม; ข้อมูลปี2022ไม่ใช่สิทธิ์ใช้เครื่องรายคนหรือสถานะปี2026
E3 [งาน ป.5 สกลนคร](https://so03.tci-thaijo.org/index.php/journal-la/article/view/301513): classroom action study28คนโรงเรียนเดียวจาก abstract ช่วยตั้งสมมติฐานเรื่องกลัวผิด/ตัวช่วย ไม่ใช่ causal evidence ของ avatar/ASR/LexiQuest
E4 [การอ่านอังกฤษผ่าน SDT](https://so05.tci-thaijo.org/index.php/reflections/article/view/265147): ม.5สายวิทย์169คนโรงเรียนเดียว เก็บปี2018เผยแพร่2023; self-report ชี้ว่าต้องฟังคุณค่าที่ผู้เรียนเห็น ไม่เหมารวมทุกวัย
E5 [EEF Mobile School](https://en.eef.or.th/2024/09/25/eef-launches-mobile-school-bringing-education-and-certification-rights-to-out-of-school-children-and-youth/): ตัวอย่างบริการยืดหยุ่นจากผู้ดำเนินงาน ไม่ใช่การประเมินผลอิสระหรือหลักฐานว่าแอปแก้ความเหลื่อมล้ำลำพังได้
รับฟังภายหลังด้วยคำถามประสบการณ์ล่าสุดก่อนโชว์ฟีเจอร์: ติดตรงไหน ทำอะไรต่อ อยากฝึกอะไร ใครช่วย และเวลา/เครื่องเปิดโอกาสเมื่อใด; เด็ก ครู ผู้ดูแลให้ข้อมูลคนละมุม ไม่ให้ผู้ใหญ่ตอบเหตุผลแทนเด็ก
รอบเชิงคุณภาพที่เสนอคือเด็ก8–12คน ครู3–4 ผู้ดูแล3–4 แยกวัย/ระดับ/เครื่อง/การเข้าถึง/ชอบเกมหรือไม่; ตัวเลขเป็นขนาดงาน ไม่ใช่ตัวแทนประชากรหรือเกณฑ์พิสูจน์ efficacy
เก็บคำพูดจริง/สิ่งสังเกต/การตีความ/ข้อเสนอแยกกัน พร้อมกรณีคัดค้าน; ภายใต้การอนุญาต/assentที่เหมาะกับกิจกรรม ใช้ข้อมูลจำเป็น เด็กข้าม/หยุดได้ ไม่บันทึกเสียงหรือเปิด Research โดยอัตโนมัติ
อายุ/interviews/UAT ที่ขาดจำกัดคำอ้างความเหมาะสมและ rollout แต่ไม่ห้าม local synthetic prototype หรือ bounded improvement ที่ได้รับอนุมัติ; ความยากจน/เครื่องร่วม/พักเรียนไม่ใช่ข้อวินิจฉัยความขี้เกียจ
ความยั่งยืนมีสามทางเลือกในอนาคต: ทุนเพื่อเนื้อหา/การเข้าถึง, บริการติดตั้ง/เนื้อหา/อบรมโรงเรียน, ชุมชนร่วมพัฒนา/บริจาค; ต้องชั่งผู้ดูแลระยะยาว คุณภาพและต้นทุนจริง โดยไม่ผูกสิทธิ์เด็กกับยอดซื้อ/ทุน/การเก็บข้อมูล

## ระยะส่งมอบ การตรวจรับ และสิ่งที่ยังอ้างไม่ได้

| ระยะ | Deliverable/เกณฑ์ตัดสิน | การถอยเมื่อไม่ผ่าน |
| --- | --- | --- |
| D0 ก่อนทุก slice | ภาพ/prototype ของหน้าที่เลือกครบ ready/empty/pending/error/retry/disabled พร้อม semantic action/content truth และสองขนาดหลัก; review ภายในก่อนลง code | ปรับต้นแบบเฉพาะชิ้น ไม่มี source implementation ที่เสร็จแล้วให้อนุมาน |
| A ของเดิมที่ใช้ได้จริง | workflow/เวลา/ผล/ภาพร้านตามขอบเขตข้างต้น; ฝึกเดิมยังเริ่มได้โดยไม่ตั้งเป้า/ซื้อของ/เปิดไมค์/ออนไลน์ | ถอด incremental UI/asset ใน binary ที่รองรับฐานปัจจุบัน เก็บงานและหลักฐานเดิม |
| B domain ที่จำเป็นจริง | แยก binding+week plan, recurrence, Quest objectives เป็น decision/version/lifecycle ที่ตรวจได้ก่อนแต่ละ implementation | หยุด writer ใหม่ ใช้ forward-compatible/repair release; ไม่ downgrade ฐานหรือ retrofit เครดิตอดีต |
| C เพื่อน | problem evidence และสถานการณ์สมัครใจ/ไม่มา/ออก/soloก่อน; online มี scope/data/ดูแล/cost decisionของตน | เลื่อนหรือไม่ทำได้โดยไม่ลดคุณภาพการเรียนเดี่ยว |
| D1–D3 ตรวจความเหมาะสม | รับฟัง prototype เมื่อพร้อม → ตรวจภาพ/flow/dataหลังทำ → native/device/TalkBack/UATตามรุ่นและสิทธิ์เปิดใช้ | pendingเฉพาะ gate ที่ขาด ไม่ยืมผลเดิมเป็นผลใหม่หรือเปิดวิจัยเพื่อวัด UI |

Acceptance ข้อมูลต้องครอบคลุม resume+assigned+120due, hidden gate, noEvidence, recognition/recall/hint, retry/revisit/replay, owner A→B→callback A, offline/ภาพหาย, UTCข้ามวัน/DST/quiet hours และ denied/cancel/pending OS reminders
ตรวจ exact session/content IDs, canonical attempts/events/SRS/mastery/Quest/streak/XP/Coins และ notification ownership; การเปิด/ยุบ/preview/เปลี่ยนทางไม่สร้าง learning/reward delta ส่วนกิจกรรมจริงได้ผลตาม eligibility เดิม
Research default-off: nonparticipant ไม่มี research rows/events/outbox/uploads; synthetic participant ต้องผ่าน owner/consent/assignment/permit authenticity+revision+expiry+revocation/protocol/instrument ทั้ง collect และ upload
หลัง UI ทุกชิ้นเสร็จและแก้ภาพ/flow แล้วจึง freeze writers+fingerprint และรัน focused/accessibility→analysis→full→host3→backend/policy/8–44→APK/hash บน source เดียว; native/device, TalkBack/UAT และสามชั่วโมงเป็นคนละ gate
ผล4,964 automated PASS/APKและสี่ native exclusions เป็นหลักฐาน contextual รุ่นก่อน ไม่ใช่ผล review นี้หรือความพร้อม UI ที่ยังไม่พัฒนา; testsไม่พิสูจน์แรงจูงใจ การจำระยะยาว retention หรือคะแนนสอบ
rollback ไม่ลบฐาน/ประวัติ/ทรัพย์สิน ไม่ใช้ binary เก่าเปิด v24+ ไม่ตัด Quest reconciliation; recurrence ในอนาคตต้อง cancel/reconcile OS entries ก่อนปิด entrypoint
แผนส่งมอบอยู่ที่ [motivation-workflow-evolution](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/docs/superpowers/plans/2026-09-08-motivation-workflow-evolution.md); ทุกงานยัง unchecked ไม่มีการอนุมัติ deploy/enroll/upload หรือผลทดลองที่สร้างขึ้นเอง
