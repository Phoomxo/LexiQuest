# U4 — จอเล็ก การเข้าถึง ออฟไลน์ และเครื่องร่วม

วันที่ 8 กันยายน 2026; ตรวจ working tree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest` บน `codex/pair-matching-pm0-pm8` รวม source ที่ยังไม่ commit
นี่คือ design persona ของเด็กไทยที่ใช้ Android ทรัพยากรจำกัด/เครื่องร่วม/เน็ตไม่ต่อเนื่อง และอาจใช้ TalkBack/ข้อความใหญ่/ไม่ใช้เสียง ไม่ใช่คำวินิจฉัย บทสัมภาษณ์ หรือ UAT จริง
อ่าน briefing/history และโค้ดจริง; รอบนี้เขียนเอกสารเท่านั้น ไม่รัน test/build ไม่เปลี่ยน gate หรือ authority
จุดหมายคือเด็กเริ่มและกลับมาเรียนได้ตามข้อจำกัดชีวิต ไม่ใช้รายได้ ยอดเชิญเพื่อน หรือเวลาหน้าจอเป็นเหตุผลเพิ่มภาระ

## Workflow ที่มีอยู่และสิ่งที่จะเปลี่ยน

Guest → เจ้าของข้อมูลในเครื่อง → Learn → กิจกรรม/เรียนต่อ → คำตอบหลัก → feedback → ทางเลือกฝึกเสริม → ผลเดิม คือเส้นทางที่ต้องรักษา
Guest บันทึก entry แล้วผูก anonymous cloud แบบไม่รอ; จึงไม่ควรเพิ่มด่าน account/social ให้การเริ่มเรียน (`lib/services/guest_session_service.dart:172`, `:176`, `:180`, `:190`)
แถบหลักมี Learn/คำศัพท์/พัฒนาการ/ความสำเร็จ/โปรไฟล์; Today/แผนเป็นทางเข้าแยกตาม gate (`lib/screens/main_navigation_screen.dart:156`, `:227`, `:232`)
Today reader อ่าน session/review/recommendation/goals/reminders/quests/streak เดิม และตรวจ owner ก่อน–หลัง compose (`lib/features/today_hub/data/drift_today_hub_reader.dart:33`, `:43`, `:62`, `:77`)
รายการ Today เป็น ListView และมีสถานะข้อมูลไม่พร้อม แต่ planning ยัง `break` (`lib/screens/today_hub_view.dart:204`, `:219`, `:233`)
การมีโค้ดไม่เท่ากับเปิดใช้งาน: production ซ่อน studyPlanning/dailyContinuity/offlineContent/Adventure และ speech เป็น limited (`lib/runtime/registries/feature_registry.dart:54`, `:59`, `:62`, `:63`)

| ข้อเสนอ | ก่อน → หลังที่ U4 ยอมรับ | ขอบเขต |
| --- | --- | --- |
| P1 แผน→Today | แผนมีข้อมูลแต่ไม่ render → สรุปงานถัดไปสั้น ๆ ใต้เรียนต่อ พร้อมรายละเอียดกางอ่านได้ | เชื่อม presentation เดิม; ไม่เพิ่ม planner service หรือเปิด gate เอง |
| P2 พัฒนาการ | ผู้เรียนต้องเปิดหลายหน้า → ประโยคอธิบายหลักฐานส่วนตัว+ทางไปดูรายละเอียด | ไม่ยุบ “ไม่มีข้อมูล/รอตรวจสอบ” เป็น 0 หรือคะแนนรวมใหม่ |
| P3 ภารกิจเลือกได้ | กิจกรรมขึ้นกับ capability → เสนอทางเลือกที่ใช้ข้อความและเวลาไม่บังคับคู่กับกิจกรรมสื่อ | เปลี่ยนกิจกรรมต้องให้ผู้เรียนเลือก; ไม่แต่งหลักฐานว่าอ่านเท่ากับฝึกพูด |
| P4 กลับมา/เตือน | งานค้างและ reminder เดิม → เรียนต่อ/เริ่มสั้น ๆ แล้วค่อยจัดเวลา | ไม่มี countdown กดดันหรือเตือนชื่อ/ผลเรียนบนเครื่องร่วมโดยปริยาย |
| P5 ภาพอวาตาร์ | แสดงชื่อของที่เลือก → ภาพนิ่งขนาดเล็กจากสิทธิ์ถือครองเดิมและคำบรรยาย | โหลดภาพภายหลัง; เรียนต่อได้เมื่อภาพขาด/เน็ตขาด; ไม่ซื้อซ้ำจาก preview |
| P6 เพื่อนสมัครใจ | ยังไม่มี friend workflow ที่ตรวจรับ → ทดลองแนวคิดการฝึกคู่แยกจากทางเรียนคนเดียว | บัญชีเพื่อนออนไลน์เป็น capability ใหม่ ต้องแยกตัดสินขอบเขตและวงจรข้อมูล |

## ความขัดแย้งที่กระทบสูงสามเรื่อง

1. **ครบทุกสิ่งบน Today vs แตะเรียนต่อได้เร็วและอ่านด้วย TalkBack**
   P1–P5 พร้อมกันเสี่ยงดัน resume ลงจอและเพิ่มการปัดอ่าน; ข้อจำกัดเกิดจากจำนวนการ์ด ไม่แก้ด้วยย่อ font หรือซ่อน semantic labels
   เลือกคงลำดับงานค้าง/งานเรียนสำคัญ แล้วรวมแผนและคำอธิบายหนึ่งส่วนที่กางได้; ของแต่งและเพื่อนอยู่ทางรอง ไม่มี bottom tab ใหม่
   หลักฐาน: `lib/features/today_hub/data/drift_today_hub_reader.dart:86`; `lib/screens/main_navigation_screen.dart:156`; `lib/screens/today_hub_view.dart:219`
   เกณฑ์ยอมรับต้องตรวจ scroll/focus จริงที่ข้อความ 200% ไม่กำหนดว่า “ทุกอย่างต้องพอดีหนึ่งจอ” ซึ่งผลักภาระไปผู้ใช้ข้อความใหญ่

2. **ความสนุกของสื่อ/อวาตาร์ vs เวลา แบต ความจำ และการไม่ใช้เสียง**
   P3 ห้ามผูกความสำเร็จภารกิจกับแผงลองพูดเสริม; เด็กที่ไม่ได้ยิน/ไม่สะดวกพูด/ปฏิเสธไมค์ต้องเรียนและรับผลจากคำตอบหลักได้เหมือนเดิม
   Cloze เปิดแผงหลังตอบแล้ว และมีปุ่มข้อต่อไปแยก; แผงระบุสมัครใจ ไม่มีคะแนน พร้อมข้อความเมื่อบริการไม่พร้อม (`lib/screens/fill_in_the_blanks_screen.dart:454`, `:473`; `lib/features/learning/presentation/sentence_practice_panel.dart:358`, `:391`)
   P5 เริ่มภาพนิ่งใน asset ที่มีขนาดจำกัด ไม่ preload ของทั้งร้าน/เล่นเสียงอัตโนมัติ/บังคับดาวน์โหลดเพื่อเห็น CTA; fallback เป็นชื่อเดิมโดยไม่เปลี่ยน entitlement
   ระบบรับ textScale/highContrast/reducedMotion จาก OS อยู่แล้ว; Adventure มี static path แต่ companion ทั่วไปยัง AnimatedSwitcher 180ms คงที่ จึงห้ามอ้างว่าภาพใหม่เข้าถึงได้อัตโนมัติ
   หลักฐาน: `lib/features/accessibility/presentation/accessibility_scope.dart:32`; `lib/features/adventure/presentation/widgets/adventure_companion_panel.dart:244`; `lib/features/companion/presentation/contextual_companion_widget.dart:30`

3. **สมัครใจมีเพื่อน vs เรียนออฟไลน์และความเป็นส่วนตัวบนเครื่องร่วม**
   Opt-in เพียงปุ่มเดียวไม่แก้ข้อมูลของเด็กก่อนหน้าค้างบนจอ/แจ้งเตือน หรือคำเชิญที่ส่งค้างแล้วกลับออนไลน์ใน owner ใหม่
   P6 ต้องไม่บังคับออนไลน์เพื่อจบงานเดี่ยว ไม่เสีย streak/reward เมื่อคู่ไม่มา และไม่แสดง contact discovery/ชื่อเพื่อน/ผลส่วนตัวบนหน้าแรกโดยปริยาย
   ความร่วมมือจริงที่ต้องมี friend graph/invite/outbox/identity ใหม่เกิน UI ปัจจุบัน; ให้เลื่อนส่วนเครือข่ายจนมี scope/privacy/offline/delete/export decision ไม่แอบเพิ่ม domain service ในแพ็กนี้
   มี guard เดิมให้ต่อยอด ไม่ใช่ใบรับรองทุกจอ: Today action ตรวจ active owner, host ล้าง pending preference เมื่อ owner เปลี่ยน และ logout สร้าง local guest ผ่าน authority
   หลักฐาน: `lib/screens/main_navigation_screen.dart:989`; `lib/features/adventure/presentation/today_experience_host.dart:149`; `lib/features/account/application/account_use_cases.dart:97`

## ข้อประนีประนอมและสิ่งที่ไม่ยอมแลก

ส่ง P1/P2/P4 เป็นชั้น UI ที่อ่านข้อมูลเดิมพร้อม P5 ขนาดเล็กในร้าน ตามข้อโต้แย้ง U5/DEV ด้านล่าง; P3 ตรวจ eligibility เดิม และ P6 ทดสอบความเข้าใจแนวคิดก่อน implementation เครือข่าย
ไม่เพิ่ม service/table/preferences store เพื่อแค่ย้ายหรือยุบการ์ด; สถานะกาง/ยุบในหน้าคงเป็น ephemeral ได้ ถ้าต้องจำต่อ owner ให้ตรวจ preference authority เดิมก่อนขยายสัญญา
ใช้ข้อความ+ไอคอนและ focus order เดิม; การซ่อนภาพต้องยังอ่านชื่อของที่เลือกได้ การลด motion ต้องได้ผลความสำเร็จเดียวกัน ไม่มีรางวัลเพิ่มจากเล่น animation
หน้า equipment ยอมรับเองว่ายังไม่มีภาพและมี responsive layout สำหรับจอแคบ/ข้อความใหญ่ จึงต่อเติมจากจุดนี้ได้ (`lib/screens/avatar_equipment_screen.dart:225`, `:301`)
ดาวน์โหลดต้องเลือกเอง แสดงขนาด/สถานะและซ่อมเมื่อ interrupted; อย่าใช้ offline manager ที่ถูกซ่อนเป็นเงื่อนไขเริ่มเรียน (`lib/screens/offline_content_manager_screen.dart:137`, `:213`, `:220`; `lib/runtime/registries/feature_registry.dart:62`)
การเตือนบนเครื่องร่วมเริ่มจากให้เลือกเวลาและข้อความทั่วไป ไม่เปิดเผยผลเรียน/เพื่อน; ถ้าต้องมี privacy setting ใหม่ต้องเข้าขอบเขตข้อมูลแยก ไม่อ้างว่า UI เปลี่ยนคำทำให้ปลอดภัยแล้ว
ทางเลือกกิจกรรมไม่ใช้สื่อมีข้อความว่า learning ที่บันทึกไม่เปลี่ยน; รักษาทางกลับนี้ (`lib/screens/media_dependency_unavailable.dart:28`, `:36`)
ภาพหรือเพื่อนต้องไม่แสดงผลสำเร็จจาก pending และไม่เปลี่ยน canonical answer/Quest/XP/Coins/Research; voice เสริม ephemeral unscored เสมอ

## สถานการณ์ตรวจรับที่ต้องทำเมื่ออนุมัติ implementation

- **จอเล็ก:** 320×640 และ 360×800, text 200%, keyboard เปิด → อ่านชื่อกิจกรรม/เวลาได้ครบ ปุ่มหลักไม่ overlap และเข้าถึงด้วย scroll; ไม่ลด text scaling เพื่อให้ผ่าน
- **TalkBack:** ไล่ context→prompt→input→feedback→navigation; resume/ข้าม/ลองใหม่/ดูรายละเอียดแตะ semantic action ได้ ภาพแต่งไม่ถูกอ่านซ้ำและ progress ไม่อาศัยสีอย่างเดียว
- **ลด motion:** เปิด disableAnimations ก่อนเข้าและระหว่างใช้งาน → ภาพนิ่ง/ข้อความให้สารเดียวกัน ไม่มี animation loop; ตรวจทั้ง Standard companion และ Adventure
- **ออฟไลน์:** Guest เริ่มกิจกรรมที่มีข้อมูลในเครื่อง, เปิด Today/P5 โดย network ล่ม → ไม่รอ social/assets และไม่ตีความ error เป็นความคืบหน้า 0; reconnect ไม่สร้างหลักฐานหรือรางวัลซ้ำ
- **เนื้อหาไม่พร้อม:** ดาวน์โหลด interrupted/พื้นที่ไม่พอ/ภาพหาย → สถานะตรงจริง มีทางกลับเรียนข้อความที่มีแล้ว; ไม่บังคับให้ลบข้อมูลเรียนเพื่อโหลดของแต่ง
- **ไม่ใช้เสียง:** ปฏิเสธไมค์/บริการหาย/ฟังไม่ได้ → ข้ามเสริมและจบ cloze เดิมได้; transcript/การลอง/การข้ามไม่เพิ่ม mastery/quest/reward/research และไม่แทนการทดสอบ speaking
- **เครื่องร่วม:** A เปิดภาพ/Today/เสียงค้าง → logout/เปลี่ยน owner เป็น B → callback เก่าไม่แสดงข้อมูล A/ไม่ติดตั้ง entitlement A/ไม่ยิงคำเชิญหรือเตือนของ A ในนาม B
- **เพื่อน:** ไม่ opt-in, offline, คู่ถอนตัว/ไม่มา → เส้นทางคนเดียวและสิทธิ์รางวัลเดิมยังอยู่; ข้อเสนอตัววัดความสำเร็จคือจบงานที่เลือกได้ ไม่ใช่จำนวนเชิญหรือเวลาออนไลน์
- **ขอบเขต:** production gate ปิด, research ไม่เข้าร่วม, retry/double tap/revisit → ยังเข้าการเรียนเดิมได้; ไม่มีการเปิด feature/วิจัย หรือ reward delta จากการตกแต่งและแผงพูด

## ประวัติที่รองรับและข้อจำกัดหลักฐาน

Convergence กำหนด local เป็น authority และ cloud เป็นส่วนเสริม (`docs/superpowers/specs/2026-08-08-lexiquest-complete-field-trial-convergence-design.md:24`)
Adventure เดิมเป็นทางเลือก ไม่ถือ progress authority และระยะแรกไม่มี social/network multiplayer; P6 จึงต้องมีการตัดสิน capability ใหม่ (`docs/superpowers/specs/2026-09-01-adventure-motivation-mode-design.md:13`, `:18`, `:24`)
Thai UI ล่าสุดลดเหลือห้าทางหลัก; contextual ล่าสุดคงตอบหลักก่อนเสียงเสริม—การเพิ่มแรงจูงใจต้องไม่ย้อนกลับไปบังคับอ่านหลายเมนูหรือให้เสียงเป็นคะแนน
รายงาน contextual เดิมมี automated 4,964 ผ่าน แต่เว้น native/platform 4 กรณี และยังไม่มี APK รุ่นนี้ผ่าน TalkBack/ไมค์/performance/UAT บนอุปกรณ์จริง (`docs/development/2026-09-08-contextual-practice-results.md:26`, `:31`, `:57`)
รอบนี้ไม่รันซ้ำและไม่ใช้ตัวเลขนั้นอ้างประสิทธิผลแรงจูงใจ; device/profile/UAT ของรุ่นใหม่เป็นงานตรวจรับที่ยังต้องทำ ไม่มีข้อมูลประชากรหรือข้ออ้างจากผู้ใช้จริงที่สร้างขึ้นเอง

## Cross-review และข้อสรุปหลังโต้แย้ง

อ่าน `03-cross-review-brief.md`, `02-design-evidence.md`, `U5-play-social.md`, `DEV-integration.md` และ `QA-acceptance.md`; รับคำชี้แจงว่าความสวยและรูปแบบคุ้นเคยต้องอยู่ในเกณฑ์จบงานด้วย
**ยอมปรับตาม U5 (C2):** เดิม U4 ให้ P5 เป็นการทดลองตามหลังวงจรหลัก แต่ร้านสัญญาเรื่องของที่ใส่โดยยังไม่มีภาพ; รับภาพ base+ของเดิมในร้านหนึ่งแห่งพร้อมระยะแรก ไม่รอแผนสัปดาห์ครบ
U4 เปิดดูจริงสองภาพเดิม: `build/verification/ui-implementation-20260908/visual/360x800-text200-01-learning.png` และ `build/verification/ui-implementation-20260908/visual/390x844-06b-shop.png`; เป็น renderer fixtures ไม่ใช่ device/UAT
ภาพ Learn แสดง CTA เริ่มได้ชัดแต่หัวข้อ/คำอธิบายกินพื้นที่มากที่ 200%; ภาพร้านมีกล่องสถิติ/รายการเงาหลายชุดและไม่มี preview—จึงเพิ่มภาพเล็กพร้อมลดน้ำหนักกล่องรอง ไม่เพิ่ม hero อีกใบเหนือเริ่มเรียน
**ยอมปรับตาม DEV (C2/C4):** U4 เน้นภาพนิ่งจนตีความว่าไม่เอา motion ได้; รับการเปลี่ยน selected/equipped/committed feedback สั้นประมาณ 150–200ms เป็นค่าต้นแบบ ผ่าน `M3Theme` helper เดิม ไม่เพิ่ม package/service
เงื่อนไขที่คงไว้: reduce motion ต้องได้ final state ทันที, ไม่มี idle loop/auto sound/auto scroll, กดต่อหรือย้อนทันทีได้ และ motion ไม่สร้าง transaction หรือรางวัล
ตาม DEV ให้ P5 อยู่หน้าร้านก่อน ไม่ขยายเข้าทุก lesson/Today พร้อมกัน; ตรวจ preview/owned/equipped แยกกัน และขนาด asset/decode memory ก่อน reuse renderer ใน companion
**รับข้อท้าทาย QA (C10):** การกดได้และ automated/golden ผ่านยังไม่พอจะเรียก polished; เพิ่ม prototype+ภาพเปรียบเทียบทั้ง flow และการประเมินความเข้าใจ โดยไม่เปลี่ยนรายการ U4 ให้เป็นผล UAT ที่เกิดแล้ว
ความคุ้นเคยจาก Duolingo/ALLTCAS ใช้กับ hierarchy/ตำแหน่งคำสั่ง/ระยะห่าง/feedback; คงห้าแท็บและ canonical next action ไม่คัดลอก asset/เส้นทางด่านที่ไม่มีหลักสูตรรองรับ
**ข้อห้ามที่ยืนยันกับ U5/DEV:** ไม่ใช้ภาพหรือเพื่อนบังคับ login/โหลดก่อนเรียน; ไม่ลดสิทธิ์ solo/offline/ไม่ใช้เสียง; supplemental voice ยัง ephemeral unscored ไม่ใช้เป็น quest หรือ speech achievement
**ระยะแรกที่ยอมรับ:** P1 แสดง goal/deadline/reminder เดิม, P2 ผลจริงหนึ่งเรื่อง, P4 ทางกลับและเวลาท้องถิ่นผ่าน scheduler เดิม, P5 ภาพ local เล็กพร้อม fallback; ไม่เรียกทั้งหมดว่า adaptive weekly plan
P3 เป็นทางเลือกฝึกที่ผ่าน gate/eligibility เดิมก่อนเพิ่ม objective; P6 เก็บความต้องการและทดสอบสถานการณ์สังเคราะห์ ห้ามสร้าง friend graph/outbox/domain service แอบใน UI
**Acceptance ภาพ:** ก่อน implement ต้องมี Learn/Today/lesson/result/shop แบบ ready/empty/pending/error/disabled; เทียบ 390×844/text100 กับ 360×800/text200 และจอแคบ/keyboard; primary action/ชื่อแท็บไม่ถูกซ่อนหรือย่อ font
**Acceptance motion/อุปกรณ์:** ใช้ local assets จำนวนน้อย บันทึก bytes/decode memory/frame จาก profile บนเครื่องเป้าหมายและเทียบรุ่นเดียวกันเมื่อเปิด/ปิดภาพ; offline/asset missing ไม่รอโหลดก่อนเริ่ม และ reduce motion ไม่สูญเสีย feedback
**Acceptance เครื่องร่วม (C6):** A โหลด preview/บันทึกเตือนค้าง→เปลี่ยน B→callback A กลับ; ต้องทิ้งภาพ/preview/สถานะค้างของ A และ cancel/reconcile OS notification ผ่าน owner/reminder authority เดิม ไม่ใช่แค่ซ่อนการ์ด
**Acceptance ใช้งาน:** TalkBack อ่าน action/state ถูกและไม่ซ้ำ ภาพแต่งไม่เบียดการปัดถึง resume; ผู้เรียนตัวแทนเริ่ม/กลับมา/อ่านผล/ปิดเตือนได้โดยไม่มีผู้ตรวจชี้ปุ่ม บันทึกความลังเลและความรู้สึกแยกจากผลเรียน
ตาม QA ตรวจ UX ให้ครบหลัง UI ทั้งหมดเสร็จ แล้วตรึง source ก่อน final-system gates; device/TalkBack/UAT/สามชั่วโมงที่ยังไม่ทำต้องรายงานแยก ห้ามใช้ APK/4,964 tests เดิมปิดช่องว่างรุ่นใหม่
ข้อสรุปหลังโต้แย้ง: เลือกแนว “เป็นมิตร มีโครงสร้างชัด” ของ dossier; อนุญาตความสนุกและ motion เล็กตั้งแต่ระยะแรกเมื่อผ่านเงื่อนไขข้างต้น รอบนี้แก้เพียงเอกสารและไม่รัน app/test/build
