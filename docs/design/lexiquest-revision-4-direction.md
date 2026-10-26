# LexiQuest Revision 4: visual direction and layout authority

Revision 4 แก้ปัญหาที่ต้นแบบรอบก่อนให้ความสำคัญกับจำนวนหน้าจอและความครบของเส้นทางมากกว่าคุณภาพขององค์ประกอบที่ผู้เรียนเห็นจริง ผลคือหน้าจออ่านง่ายแต่โล่ง แบน และไม่มีจังหวะของการเรียนแบบเกม

## ลำดับอิทธิพลในการออกแบบ

การผสมต้นแบบใช้บทบาทที่แยกจากกันชัดเจน ไม่เฉลี่ยหน้าตาของสามผลิตภัณฑ์เข้าด้วยกัน

1. **AllTCAS เป็นโครงเลย์เอาต์หลัก**
   - ใช้ลำดับข้อมูลแบบ catalog → setup → task → fixed action → feedback
   - ใช้รายการและหมวดเพื่อรองรับคลังคำ โหมดฝึก เครื่องมือ และ settings
   - ใช้ list-detail บนหน้าจอกว้าง เพื่อเพิ่มข้อมูลโดยไม่ทำให้ navigation เปลี่ยนความหมาย
   - รักษาความหนาแน่นที่มีหน้าที่จริง ไม่ปล่อยพื้นที่ว่างเกินครึ่งหน้าจอ
2. **Astra เสริมบริบทและ AI**
   - เริ่มจากสิ่งที่ผู้เรียนมี: คำในคลัง เป้าหมาย โน้ต หรือวันสอบ
   - เปิดเผยข้อมูลทีละขั้น และบอกแหล่งบริบทก่อนส่งคำถาม
   - AI Tutor ใช้ context source → question → explanation → verify/continue
3. **Duolingo เสริมวงจรเรียนและแรงจูงใจ**
   - ใช้ Resume, waypoint, milestone, immediate feedback และผลลัพธ์ที่เห็นการเปลี่ยนแปลง
   - ใช้เฉพาะ Home, learning path, feedback, result, unlock และเกม
   - ไม่ใช้ภาพลักษณ์หรือโครง path-first ครอบทุกหน้าของแอป

## ทิศทางภาพ: Calm Journey / Evidence Trail

- พื้นหลัก `#F5F6FA`; surface สีขาวใช้จัดกลุ่มรายการหรือบริบทที่สัมพันธ์กัน
- `#111522` เป็น dark anchor เฉพาะ welcome, mission/result peak และ reward reveal
- `#5A4CF2` ใช้กับ primary action และ current waypoint
- `#0E8176` ใช้กับคำตอบที่บันทึกสำเร็จและหลักฐานการเรียน
- `#D98213` ใช้กับ due state, momentum และคำเตือนที่ไม่เป็น error
- route thread และ compass mark เป็นลายเซ็นของ Home/Path/Result เท่านั้น
- ใช้ radius 24dp กับ hero, 16dp กับ grouped surface และ 14dp กับ control
- ใช้ Noto Sans Thai ตามบทบาท Quest display, task, screen title, body และ meta โดยมีข้อความหนาหลักหนึ่งจุดต่อ viewport

## สัดส่วน

### โทรศัพท์ 390×844

- system/app bar 84dp
- usable body 656dp
- bottom navigation และ safe area 104dp
- ภายใน body ใช้ primary task 28–34%, context/path 28–32%, secondary action 18–22% และพื้นที่พัก 12–20%
- หน้าทำโจทย์ใช้ progress → prompt → choices → fixed action; feedback เปลี่ยนพื้นที่ action เป็น mastery panel และ next action

### Tablet portrait 800×1280

- navigation rail 88dp
- content column กว้าง 616–648dp และจัดกึ่งกลาง
- ใช้พื้นที่แนวตั้งที่มีสาระ 70–78%; ช่วงที่เหลือเป็น breathing room ไม่ใช่พื้นที่ว่างจากการขาดเนื้อหา
- เรียง mission → path context → activity catalog ตามลำดับเดียวกับมือถือ

### Tablet landscape 1280×800

- navigation rail 88dp
- list/gap/detail ใกล้เคียง 34/3/63
- รายการแสดง 5–7 แถวเมื่อข้อมูลมีจริง และ detail แสดงความหมาย บริบท หลักฐานล่าสุด และ action

### Foldable 840×900

- rail 88dp และ hinge 32dp
- พื้นที่หลังหัก gutter/hinge แบ่งซ้าย/ขวาประมาณ 42/58
- ภารกิจหลักอยู่ pane ซ้าย; path และสรุปที่สัมพันธ์กับงานอยู่ pane ขวา

## Canonical clickable flow

วงจรเรียนหลัก:

`Home → Quiz selected → Correct/Wrong feedback → Result → Repair หรือ Home updated`

วงจรแรงจูงใจเป็นทางเลือก:

`Result → Path unlock → Home updated หรือ Ghost Duel → Win → Reward reveal → Home updated`

เส้นทางรองที่ต้องกดได้:

- Home → activity catalog → Quiz / SRS / Reading / Ghost Duel
- Wrong feedback → retry หรือเฉลยแบบ no-save → retry; บันทึก mastery หลังตอบถูกจริงเท่านั้น
- Library → word detail → practice
- Progress → repair weak words
- Profile → Settings → AI Tutor
- Bottom navigation และ tablet rail เชื่อมสี่ปลายทางหลัก

## Acceptance gate

- AllTCAS เป็นโครงลำดับข้อมูลที่มองเห็นได้บน Home, catalog, Quiz, Library และ Settings
- Astra มีบทบาทชัดใน AI Tutor และการเลือกบริบท โดยไม่ยืมหน้าตา landing page มาเป็น app shell
- Duolingo ปรากฏเป็น learning loop และ payoff ไม่ครอบหน้าจอ utility
- Path, Ghost Duel และ reward เป็น optional branch; การเรียนหลักไม่ถูกบังคับให้เล่นเกมก่อนกลับ Home
- แต่ละหน้าของ canonical flow มีบทบาททางอารมณ์ต่างกัน
- ไม่มีศัพท์สถาปัตยกรรม เช่น authority หรือ pipeline บน play surface
- reward เป็นของตกแต่งและไม่แก้ mastery
- phone, tablet และ foldable รักษา focal task เดียวกัน
- navigation rail มี 200% text-scale specimen ที่ label wrap และ item ขยายสูงตามข้อความโดยไม่ clip
- interactive frame ในต้นแบบทุกชิ้นมีปลายทาง และไม่มี dead navigation

## หลักฐานต้นทาง

- `docs/research/2026-10-18-duolingo-alltcas-feature-study.md`
- `docs/research/2026-10-18-duolingo-astra-alltcas-layout-synthesis.md`
- REA evidence gallery ที่ระบุในเอกสารวิจัย
- `docs/design/lexiquest-canva-master-ui.html` และ Revision 3 PDF เป็น baseline ด้านจังหวะภาพ
