# LexiQuest layout synthesis: Duolingo, Astra AI, and AllTCAS

วันที่สังเคราะห์: 2026-10-18
ขอบเขต: ลำดับข้อมูล สัดส่วนหน้าจอ เส้นทางเรียน และสถานะตอบกลับที่นำมาปรับใช้กับ LexiQuest โดยไม่คัดลอกภาพ โลโก้ ข้อความ หรือทรัพย์สินของผลิตภัณฑ์ต้นแบบ

## หลักฐานที่ใช้

| แหล่ง | วิธีเก็บ | สิ่งที่ยืนยันได้ | ข้อจำกัด |
| --- | --- | --- | --- |
| Duolingo บน Android | REA runtime capture และ Android artifact inspection | หน้าแรกแบบ path-first, ปุ่มทำต่อ, practice hub, section overview, question/feedback และคำศัพท์ | สิ่งที่เปิดได้ขึ้นกับบัญชี ภาษา และ entitlement; ไม่ได้ตรวจ backend หรือ A/B test |
| AllTCAS บน Android | REA runtime capture, Android package inspection และ Hermes string inventory | catalog งานเรียน, setup ก่อนฝึก, คำถามทีละข้อ, action ด้านล่าง, feedback, คลังคำ และเครื่องมือเสริม | Hermes bytecode 98 วิเคราะห์เชิงความหมายได้ไม่ครบ; ไม่ได้ตรวจ backend หรือสูตร AI |
| Astra AI public landing | REA controlled browser replay ที่ `https://astra-ai.co/th/` | input จากเอกสาร, study plan, กิจกรรม 10 ขั้น, mock exam, AI tutor, scan, game/streak และ progress | เป็นหน้า public ที่อธิบายผลิตภัณฑ์ ไม่ใช่หลักฐานว่าทุกฟีเจอร์เปิดในทุกบัญชี |
| Astra AI onboarding | REA controlled browser replay ที่ `https://app.astra-ai.co/th-TH/onboarding` | role selection, progress indicator, one-question-per-screen และลำดับ progressive disclosure | หยุดก่อนกรอกชื่อหรือสร้างบัญชี; ไม่มี APK Astra อยู่บนมือถือที่เชื่อมต่อ |

REA evidence ที่ใช้กับ Astra:

- Landing ก่อนจัดการคุกกี้: `ev_7845471627f2d52228ede53acd15ac00863f7887d05e560cabf11a65548da9e9`
- Landing หลังยอมรับคุกกี้: `ev_5124648b44a8cd1d05cf082f3b0a8f431709f5e191dab7e9f9a2c95e40697040`
- Onboarding role selection: `ev_dbe401338ab13c8e34ce156873960366957fff9665a53f74ab335b4c3361cce8`
- Onboarding หลังเลือกนักเรียน: `ev_372d961582273bbb8e65f74d45ac5873c7090a61e11bd2d92875e2af3d7ffc09`

หลักฐาน Duolingo และ AllTCAS อยู่ใน `C:\Users\Phet\.codex\tools\rea\evidence\mobile-study-2026-10-18` โดยมี 63 เฟรม และชุดคัดเลือก 39 เฟรมใน `gallery.html`

## ลำดับอิทธิพลที่ใช้ใน Revision 4

1. **AllTCAS เป็น layout/system authority** สำหรับ home hierarchy, activity catalog,
   setup, question flow, fixed action, feedback, library, list-detail และ settings
2. **Astra เป็น context/AI authority** สำหรับ context source, progressive disclosure,
   grounded explanation, provenance และทางไปฝึกต่อ
3. **Duolingo เป็น learning-loop authority** สำหรับ resume, immediate feedback,
   visible progress, path unlock และ reward โดยส่วน path/game/reward ต้องเป็นทางเลือก

ลำดับนี้ใช้ตัดสินข้อขัดแย้งระหว่างต้นแบบ: ถ้าโครงหน้าไม่ตรงกันให้ยึด AllTCAS,
ถ้าเป็นพฤติกรรม AI ให้ยึด Astra และถ้าเป็น feedback/motivation ให้ใช้ Duolingo
โดยไม่ให้กลไกแรงจูงใจเปลี่ยนความจริงด้าน mastery

## สิ่งที่พบร่วมกัน

ทั้งสามผลิตภัณฑ์ไม่ได้เริ่มด้วยรายการฟีเจอร์ที่มีน้ำหนักเท่ากัน แต่สร้างลำดับจากบริบทไปสู่การกระทำ:

1. บอกว่าผู้เรียนอยู่ตรงไหนหรือกำลังเตรียมอะไร
2. แสดงงานหลักที่ควรทำต่อเพียงหนึ่งงาน
3. ให้เลือกตัวช่วยหรือโหมดรองเมื่อผู้เรียนต้องการ
4. ฝึกทีละข้อหรือทีละขั้น
5. แสดงผลตอบกลับในบริบทเดิม
6. ปิดวงจรด้วยขั้นถัดไปที่ชัดเจน

ลักษณะที่นำมาใช้ได้โดยตรง:

- **Duolingo:** ปุ่ม Resume, feedback และผลลัพธ์ช่วยลดเวลาตัดสินใจ; path/reward ใช้เป็นแรงจูงใจรอง
- **Astra AI:** เริ่มจากสิ่งที่ผู้เรียนมี เช่น โน้ต วันสอบ และเป้าหมาย แล้วสร้างแผนทีละขั้น; onboarding ถามทีละเรื่องและใช้ progress บอกตำแหน่ง
- **AllTCAS:** เหมาะกับการเลือกวิชา/ชุดข้อสอบ และใช้ fixed bottom action ในหน้าทำโจทย์ก่อนแสดง feedback

## กฎเลย์เอาต์ของ LexiQuest

### 1. สัดส่วนบอร์ดดีไซน์ 16:9

- Header อธิบายเป้าหมายหน้า: `14–17%` ของความสูง
- Screen stage ที่ใช้ตรวจหน้าจอจริง: `76–80%`
- Evidence strip: `4–7%`
- พื้นที่คำอธิบายด้านข้างห้ามกินเกิน `28%` ของความกว้างเมื่อหน้าหลักคือการเปรียบเทียบมือถือ
- บอร์ด 3 สถานะใช้ mockup กว้าง `318–338px`; บอร์ด 4 สถานะใช้ `286–300px`

### 2. สัดส่วนหน้าจอมือถือ

- Safe/app bar: `8–12%`
- เนื้อหาหลักที่ตอบว่า “ทำอะไรต่อ”: `28–38%` ในหน้า hub และ `55–68%` ในหน้าฝึก
- เนื้อหารอง: `30–42%`
- Action/nav ที่ตรึงด้านล่าง: `10–14%`
- ระยะขอบแนวนอน `20–24dp`; ช่องว่างหลัก `24–32dp`; ช่องว่างภายในกลุ่ม `8–16dp`

### 3. ลำดับชั้นข้อความ

- Screen title: 20–24sp, 700–800
- Task/prompt: 24–32sp, 700–800
- Body: 15–17sp, line height 1.45–1.65
- Supporting/meta: 12–14sp และใช้สีที่ยังผ่าน contrast
- หนึ่ง viewport มี headline ใหญ่เพียงหนึ่งจุดและ primary action เพียงหนึ่งจุด

### 4. รูปแบบหน้าหลัก

| หน้าของ LexiQuest | โครงสร้างที่ใช้ | หลักฐานต้นทาง |
| --- | --- | --- |
| Learning hub | แผนวันนี้ → route context → activity catalog | AllTCAS task hierarchy + Astra step plan + Duolingo resume |
| Vocabulary | รายการ/หมวด → รายละเอียดคำ → ฝึกคำนี้ | AllTCAS vocabulary hierarchy + LexiQuest word evidence |
| Quiz/SRS | progress → prompt → choice → fixed action → saved feedback | AllTCAS question flow + retrieval practice |
| Curriculum | เป้าหมาย → current node → next reachable node | Duolingo path + Astra target/date framing |
| AI Tutor | context source → question → explanation steps → verify/continue | Astra document-grounded tutor; LexiQuest consent/quota rules |
| Onboarding | หนึ่งคำถามต่อหน้า → progress → back/continue | Astra role/profile flow |

## การปรับจาก Revision 2

Revision 2 ใช้คอลัมน์คำอธิบาย 400px ทางซ้ายทุกหน้า ทำให้พื้นที่ตรวจมือถือเล็กและเกิดจุดศูนย์ถ่วงสองจุด Revision 3 เปลี่ยนเป็น header เต็มความกว้างที่เตี้ยลง แล้วให้ screen stage เป็นพื้นที่หลัก จึงอ่านลำดับจากชื่อหน้าไปยัง UI จริงได้ทันที

การเปลี่ยนสำคัญ:

- ขยาย mockup และจัด baseline/caption ให้ตรงกัน
- ลด card ที่มีน้ำหนักเท่ากันในหน้า hub
- ให้ Quiz/feedback และ onboarding ใช้ลำดับแนวตั้งแบบ task-first
- เพิ่ม evidence strip เพื่อบอกว่าองค์ประกอบใดมาจาก runtime evidence, repository truth หรือแนวทางระบบ
- ใช้ Astra เป็นหลักฐานสำหรับ document-to-plan, progressive onboarding และ tutor flow
- รักษา LexiQuest เป็น local-first และแยก mastery, momentum, reward และ research ออกจากกัน

## งานวิจัยสนับสนุน

- Android adaptive layouts: compact/medium เหมาะกับ single pane; expanded จึงค่อยใช้ list-detail หรือ supporting pane: https://developer.android.com/develop/adaptive-apps/guides/get-started-with-adaptive-apps
- Android responsive navigation: compact ใช้ bottom navigation; medium/expanded ใช้ navigation rail: https://developer.android.com/develop/ui/views/layout/build-responsive-navigation
- Canonical layouts: ใช้ list-detail/supporting pane ตามพื้นที่และงาน ไม่ย่อทุกอย่างลงพร้อมกัน: https://developer.android.com/develop/adaptive-apps/guides/canonical-layouts
- Retrieval practice ช่วยการเรียนระยะยาวเมื่อมีการดึงความรู้กลับมาใช้ซ้ำ: https://doi.org/10.1126/science.1152408
- งานทบทวน cognitive load สำหรับ mobile learning สนับสนุนการแบ่งเนื้อหาเป็นช่วงสั้น คำอธิบายกระชับ และลดรายละเอียดที่ไม่ช่วยงาน: https://www.jite.org/documents/Vol23/JITE-Rv23Art026Toh10811.pdf

## ขอบเขตความถูกต้อง

เอกสารนี้สรุปสิ่งที่สังเกตได้และการอนุมานด้านการออกแบบ ไม่อ้างว่าได้ซอร์สโค้ด แอปพลิเคชันเซิร์ฟเวอร์ สูตรแนะนำ หรือโมเดล AI ของผลิตภัณฑ์ต้นแบบ และไม่ใช้คำกล่าวด้านประสิทธิผลจากหน้าโฆษณาเป็นหลักฐานทางการเรียนรู้ของ LexiQuest
