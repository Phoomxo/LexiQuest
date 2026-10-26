# LexiQuest design contract

LexiQuest ใช้ Calm Journey / Evidence Trail เพื่อช่วยให้ผู้เรียนรู้ว่าควรทำอะไรต่อ เหตุผลของคำแนะนำคืออะไร และผลลัพธ์เปลี่ยนเส้นทางเรียนอย่างไร โดยไม่ทำให้รางวัล เมนู หรือข้อมูลรองแย่งความสนใจจากงานเรียน

ลำดับอิทธิพลของ UI คือ AllTCAS เป็นโครงเลย์เอาต์และลำดับงานหลัก, Astra เป็นแบบของบริบทและ AI, และ Duolingo ใช้เฉพาะวงจรฝึก feedback ความก้าวหน้า และแรงจูงใจ รายละเอียดอยู่ที่ [Revision 5 direction](docs/design/lexiquest-revision-5-direction.md) และเกณฑ์ adaptive อยู่ที่ [Revision 5 responsive contract](docs/design/lexiquest-revision-5-responsive-contract.md)

## Product rhythm

ทุกเส้นทางหลักใช้จังหวะเดียวกัน:

`บริบท → งานถัดไป → ลงมือ → ผลตอบกลับที่บันทึกแล้ว → ขั้นถัดไป`

- Learning hub เริ่มด้วยงานแนะนำหนึ่งงาน
- Practice แสดงหนึ่ง prompt และหนึ่ง primary action
- Feedback อยู่ในบริบทเดิมและบอกว่าบันทึกแล้วหรือยัง
- Progress อ้างหลักฐานการเรียน ไม่อ้าง XP, streak หรือเวลาเปิดแอปแทน mastery
- Research, AI provider, microphone, camera และ cloud upload ต้องมีทางเข้าชัดเจนและทำงานตาม authority ของระบบ

## Layout grammar

- Canonical Android ระยะแรกคือ Vivo V2041 ขนาด 393×876dp; ตรวจ compact ที่ 360×800 และ 412×915dp โดยคง hierarchy เดิม
- Compact `<600dp` ใช้ single pane และ NavigationBar 4 จุดหมาย: เรียน, คลังคำ, ก้าวหน้า, โปรไฟล์
- Medium `600–839dp` ใช้ NavigationRail และ focused/centered pane; Expanded `840–1199dp` ใช้ supporting/list-detail เฉพาะเมื่อ usable list ≥320dp และ detail ≥480dp
- Large `1200–1599dp` ใช้ shell ไม่เกิน 1200dp, list-detail ใกล้ 42:58 และเพิ่ม outer space แทนยืด card
- Rail กว้าง 88dp ใน visual specimen; NavigationBar 104dp ใน prototype หมายถึง visual target 80dp รวม synthetic bottom inset ประมาณ 24dp ส่วน implementation ต้องอ่าน inset จริง
- Samsung fold และ Huawei tri-fold ใช้ runtime hinge/display features; รุ่นอุปกรณ์กำหนดชุดทดสอบ ไม่ได้กำหนด breakpoint
- ระยะขอบหน้าจอ 16dp ที่ความกว้าง 320dp และ 20dp ตั้งแต่ 360–599dp; section gap 24–32dp, component gap 8–16dp
- Primary action สูงอย่างน้อย 48dp และมีได้หนึ่งจุดเด่นต่อ viewport
- หน้า hub แบ่งประมาณ app bar 10%, next action 34%, context/support 42%, navigation 14%
- หน้าฝึกแบ่งประมาณ progress 10%, prompt/choices 64%, feedback/action 16%, system area 10%
- เนื้อหาที่มีหน้าที่จริงควรกินพื้นที่ usable body ประมาณ 70–78%; negative space โดยทั่วไปอยู่ที่ 12–22%

## Typography

ใช้ Noto Sans Thai Variable เป็นหลัก และใช้ system fallback เฉพาะเมื่อโหลดฟอนต์ไม่ได้

| บทบาท | ขนาด | น้ำหนัก | ระยะบรรทัด |
| --- | --- | --- | --- |
| Board title | 38–44px | 800 | 1.18–1.25 |
| Screen task | 24–32sp | 700–800 | 1.25–1.38 |
| Screen title | 20–24sp | 700 | 1.30–1.40 |
| Body | 15–17sp | 400–600 | 1.45–1.65 |
| Meta | 12–14sp | 500–700 | 1.35–1.50 |

ข้อความไทยต้องไม่ถูกบีบด้วย letter spacing และไม่ใช้ตัวพิมพ์ใหญ่เพื่อสร้างลำดับชั้น

## Color roles

- `#5A4CF2` Primary: การกระทำหลักและตำแหน่งปัจจุบัน
- `#0E8176` Mastery: หลักฐาน คำตอบถูก และความก้าวหน้าที่ตรวจได้
- `#D98213` Momentum accent: งานถึงกำหนด คำเตือน และแรงส่ง; ใช้ `#6B3E00` เป็นข้อความบนพื้นอ่อน
- `#B3261E` Error: ความผิดพลาดที่ต้องแก้
- `#F5F6FA` Canvas และ `#FFFFFF` Surface
- `#171A2B` Ink และ `#626A80` Supporting text

สีไม่เป็นสัญญาณเดียว ต้องมีข้อความ รูปร่าง หรือไอคอนประกอบ

## Component rules

- Cards ใช้ border บางและแทบไม่มีเงา; ใช้ card เมื่อช่วยจัดกลุ่ม ไม่ใช้ห่อทุกข้อความ
- Chips ใช้กับ metadata/filter/status สั้น ๆ และไม่ใช้แทนปุ่มหลัก
- Bottom sheet/feedback ต้องเว้นพื้นที่จาก NavigationBar และไม่บังคำถาม
- Loading รักษาโครงหน้าจอ; empty/error มีสาเหตุและทางไปต่อ
- Dialog ทำหน้าที่ยืนยันการกระทำที่สำคัญและหลีกเลี่ยงการซ้อน dialog

## Evidence and provenance

กฎเลย์เอาต์มาจาก REA runtime evidence ของ AllTCAS เป็นหลัก, REA browser replay ของ Astra AI สำหรับบริบท/AI, REA runtime ของ Duolingo สำหรับ learning loop, โค้ด/ข้อกำหนดใน repository, Figma Community research และ Android adaptive guidance รายละเอียดอยู่ที่ [layout synthesis](docs/research/2026-10-18-duolingo-astra-alltcas-layout-synthesis.md) และ [Revision 5 community research](docs/research/2026-10-18-figma-community-revision-5.md)

หลักฐานจากคู่แข่งใช้เพื่อเข้าใจลำดับงานและสัดส่วนเท่านั้น ห้ามคัดลอกภาพประกอบ โลโก้ ข้อความเฉพาะ หรือกลไกที่ขัดกับ local-first, learner safety, research consent และ EvidenceContext/EventEnvelopeV2 ของ LexiQuest
