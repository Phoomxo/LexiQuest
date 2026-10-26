# LexiQuest Revision 5 — UI/UX Critique

วันที่ตรวจ: 18 ตุลาคม 2026
ขอบเขต: `tmp/figma/lexiquest_master_ui_v5.js` และ `docs/design/lexiquest-revision-5-responsive-contract.md`

## คำตัดสิน

Revision 5 **ผ่านการตรวจแบบมีเงื่อนไขในระดับ design source** และพร้อมเข้าสู่การตรวจใน Figma Present กับ runtime test harness ขั้นถัดไป โครงปัจจุบันมีลำดับข้อมูลชัดขึ้น ใช้ภาษาไทยทั่วไปมากขึ้น คุมงานหลักให้เด่นหนึ่งงานต่อหน้าจอ และมีกติกา adaptive ที่อิงพื้นที่ใช้งานจริงแทนการเดาจากชื่อรุ่นอุปกรณ์

คะแนนชั่วคราวจากหลักฐานแบบนิ่ง: **35/40**

| มิติ | คะแนน | ข้อสังเกต |
| --- | ---: | --- |
| ลำดับชั้นของข้อมูลและงานหลัก | 4.5/5 | งานถัดไป ผลลัพธ์ และ CTA หลักอ่านได้ก่อนรายละเอียดรอง |
| ภาษาและความเข้าใจง่าย | 4.5/5 | เมนูหลักใช้ภาษาไทยทั่วไปและอธิบายผลของการกระทำได้ตรงขึ้น |
| Layout, spacing และความหนาแน่น | 4.5/5 | compact มีจังหวะที่สมดุลขึ้น; tablet จำกัดความกว้างเนื้อหาแทนการยืด card |
| Interaction และ feedback | 4.5/5 | แยกการเลือกคำตอบออกจากการยืนยัน และมีผลลัพธ์หลังการกระทำที่มองเห็นได้ |
| Responsive และ adaptive behavior | 4.5/5 | ใช้ width/height class, pane minimum และ safe region เป็นกติกากลาง |
| Accessibility | 3.5/5 | มีเป้าหมาย touch 48dp และ specimen ข้อความ 200% แต่ยังไม่มีหลักฐาน TalkBack, focus และ IME จาก runtime |
| ความสม่ำเสมอตาม Material Design 3 | 4.5/5 | ใช้ tonal surfaces, role colors, navigation bar/rail และ modal overlays สอดคล้องกัน |
| ความครบถ้วนของหลักฐาน | 4.0/5 | generator มี route audit แต่ยังต้องยืนยันใน Present, LDPlayer, foldable emulator และอุปกรณ์จริง |

คะแนนนี้ไม่ใช่การรับรอง Flutter implementation, usability กับผู้ใช้จริง หรือ hardware compatibility

## สิ่งที่พบในรอบแรกและการแก้ไข

| ระดับเดิม | ประเด็น | ผลกระทบต่อผู้ใช้ | การแก้ใน Revision 5 | สถานะจาก design source |
| --- | --- | --- | --- | --- |
| P1 | Home chip ล้นกรอบ | ข้อความสถานะชนขอบและทำให้การ์ดหลักดูไม่เสถียรบน compact screen | จำกัดความกว้างและจัดตำแหน่ง chip ให้อยู่ใน content bounds ของหน้า Home | แก้แล้ว; ต้องยืนยันที่ 360, 393 และ 412dp ใน Present |
| P1 | AI bubble ชน metadata | ข้อความตอบกับแหล่งอ้างอิง/เวลาแย่งพื้นที่ อ่านยาก และดูไม่เหมือนบทสนทนาที่คุ้นเคย | คำนวณความสูง bubble จากจำนวนบรรทัดและเผื่อพื้นที่ metadata แยกด้านล่าง พร้อมจัดรูปแบบบทสนทนาแนว Messenger | แก้แล้ว; ต้องยืนยัน text scale และ IME ที่ runtime |
| P2 | หน้า Result ให้ payoff และคำอธิบายไม่ชัด | ผู้ใช้ไม่รู้ว่าทำสำเร็จแค่ไหน ได้อะไร และควรทำอะไรต่อ | ยกผลลัพธ์ขึ้นก่อนรายละเอียดรอง ใช้ข้อความอธิบายผลที่เป็นภาษาคน และทำ next action ให้ชัด | แก้แล้วในลำดับภาพและ copy |
| P2 | Settings มีจุดสีตกแต่งและ typography แข็งเกินไป | เกิด visual noise และให้ความสำคัญกับองค์ประกอบที่กดไม่ได้มากกว่าชื่อรายการ | ตัดจุดสีที่ไม่มีความหมาย ปรับน้ำหนักตัวอักษรและคำอธิบายให้เป็นลำดับ title–supporting text ตามรายการตั้งค่า | แก้แล้วใน component ปัจจุบัน |
| P2 | Flashcard มีพื้นที่ว่างมากและไม่สื่อผลหลังเลือกระดับ | การ์ดดูไม่เต็มความหมาย ผู้ใช้ไม่แน่ใจว่าระบบบันทึกแล้วหรือยัง | เพิ่มคำแนะนำและบริบท ปรับความหนาแน่น และเพิ่มสถานะ “บันทึกระดับแล้ว” พร้อมทางเลือกทดสอบหรือไปคำถัดไป | แก้แล้ว; เส้นทาง reveal → rate → saved มีปลายทางชัด |
| P1 | Fold 840dp ถูกบังคับให้เป็นสอง pane | หลังหัก rail, gutter และ hinge แล้ว pane อาจแคบกว่าขั้นต่ำ ทำให้ข้อความและ CTA อัดแน่น | specimen 840dp ใช้ centered single-pane fallback; เปิด two-pane เฉพาะ specimen 1024dp ที่ list ≥320dp และ detail ≥480dp | แก้แล้วตามกติกา usable bounds |
| P1 | Mate XT dual/triple ถูกเติมหลาย pane ตามจำนวนแผง | เนื้อหาถูกแบ่งเพื่อเติมพื้นที่ แม้แต่ละ safe region ไม่พอ และเสี่ยงวางงานหลักข้าม seam | dual/triple ใช้ runtime class และ safe regions จริง โดยมี single primary task pane เป็น fallback; ไม่สมมติว่าแผงกว้างเท่ากัน | แก้แล้วใน specimen; hardware evidence ยังขาด |
| P2 | Tablet landscape มีสัดส่วน list/detail ไม่สมดุล | รายการกินพื้นที่เกินความจำเป็น ขณะที่รายละเอียดซึ่งเป็นงานหลักแคบ | ตัวอย่าง 1280×800 ใช้สัดส่วนใกล้ 42:58 กับ gutter 24dp ภายใน shell ที่จำกัดความกว้าง | แก้แล้ว; 42:58 เป็น visual target ไม่ใช่ fixed formula |
| P1 | Prototype ใช้ fallback route กว้าง, overlay ไม่ครบ และ Back สูญบริบท | บางปุ่มดูเหมือนกดได้แต่ไปหน้าผิด วนกลับหน้าเดิม หรือย้อนกลับไม่ตรงจุดเริ่ม | เปลี่ยนเป็น explicit route ต่อ action, แยก `OVERLAY`, ทำ parent-specific Back และเพิ่ม audit สำหรับ interactive node ที่ยังไม่ถูกเชื่อมหรือเกิด semantic self-loop | แก้แล้วใน generator; ต้องเล่นทุกเส้นทางใน Present |

หลังแก้ไม่พบประเด็น P0 จากการอ่าน design source ประเด็นคงเหลือเป็นงานยืนยันพฤติกรรมและ accessibility ไม่ใช่เหตุให้ย้อนโครง Revision 5

## การประเมินตามหลัก UI/UX และ Material Design 3

### 1. Information hierarchy

- หน้า Home วางภารกิจที่ควรทำต่อและเวลาที่ใช้ไว้ในครึ่งบน ลดภาระการตัดสินใจ
- Quiz แยก `เลือกคำตอบ` ออกจาก `ตรวจคำตอบ` ทำให้ผู้ใช้เปลี่ยนใจได้ก่อน commit และลดความผิดพลาดจากการแตะครั้งเดียว
- Result แสดงผลหลักก่อนรายละเอียดและทางเลือกซ่อมจุดอ่อน จึงปิด learning loop ได้ชัดกว่าเดิม
- ผู้ช่วยเรียนด้วย AI ใช้รูปแบบบทสนทนาที่คุ้นเคย พร้อมแหล่งบริบทของคำตอบโดยไม่แทรกศัพท์เทคนิคในเนื้อหาหลัก

### 2. Layout และ visual rhythm

- compact baseline 393×876dp ยึด content gutter 20dp และคง single pane เพื่อให้สัดส่วนอ้างอิงใกล้เครื่อง Vivo V2041 ที่ใช้ในระยะแรก
- ขนาด 360×800 และ 412×915 รักษาลำดับชั้นเดิม ไม่เพิ่ม card เพียงเพื่อเติมพื้นที่แนวตั้ง
- หน้าจอกว้างจำกัด prose, form, task และ shell ด้วย max width ทำให้ eye travel อยู่ในช่วงอ่านง่าย
- tablet และ foldable ใช้ pane minimum กับ hinge/seam เป็นเงื่อนไขก่อนเพิ่ม pane ซึ่งสอดคล้องกับแนวคิด adaptive layout ของ Material Design 3

### 3. Component และ visual language

- NavigationBar ใช้กับ compact width และ NavigationRail ใช้ตั้งแต่ medium width โดยคงจุดหมายหลักสี่รายการเดิม: เรียน, คลังคำ, ก้าวหน้า และโปรไฟล์
- สีหลัก สีผลสำเร็จ สีแรงส่ง และสีข้อผิดพลาดทำหน้าที่ตาม semantic role มากกว่าการใช้สีเป็นของตกแต่ง
- Card, list row, button และ dialog ใช้ shape, border และ tonal surface ในภาษาเดียวกัน ลดภาพที่ดูเหมือนประกอบจากหลาย template
- ปุ่มหลักหนึ่งปุ่มต่อช่วงงานเด่นชัดขึ้น ส่วน action รองใช้ outline หรือ row ที่น้ำหนักต่ำกว่า

### 4. Interaction และ state model

- การเลือกคำตอบผิดแต่ละตัวมี selected state ของตนเอง และ commit เฉพาะเมื่อกดตรวจคำตอบ
- Flashcard มีสถานะก่อนเปิดคำตอบ หลังเปิดคำตอบ การเลือกระดับ และผลหลังบันทึกครบวงจร
- Dialog และ sheet สำคัญเปิดเป็น overlay และมีเส้นทางปิด ส่วน Back ของหน้าซ้อนกลับไปยัง parent ที่เกี่ยวข้องแทนการส่งทุกอย่างกลับหน้า hub เดียว
- generator ตรวจ interactive node ที่ประกาศไว้แต่ยังไม่ถูกเชื่อม และตรวจ self-loop ที่ไม่มีความหมาย ยกเว้น navigation state ที่ตั้งใจคงหน้าเดิม

### 5. Responsive และ continuity

- Layout ตัดสินจาก app window, insets, text scale, IME และ display features ณ runtime ไม่ตัดสินจากยี่ห้อ รุ่น หรือ physical pixels
- Width class ใช้ Compact `<600`, Medium `600–839`, Expanded `840–1199` และ Large `1200–1599dp`; พื้นที่กว้างกว่านั้นใช้ large fallback โดยคง shell ≤1200dp
- Height ต่ำกว่า 480dp บังคับ focused single pane; 840dp จึงไม่ถือว่าเหมาะกับ two-pane อัตโนมัติ
- เมื่อ resize, rotate, fold หรือ unfold ต้องคง route, selected destination, scroll, draft, quiz progress และ AI conversation ไว้

## สิ่งที่ยังต้องตรวจใน Figma Present

รายการต่อไปนี้ยังไม่ถือว่าผ่านจนกว่าจะมีการเล่น prototype จริง:

1. ตรวจทุก AppBar action, CTA, navigation item, choice, menu, word row, setting row และ filter ว่าไปปลายทางตรงกับชื่อและไม่มี dead end
2. ตรวจ overlay ทั้งหมดว่าเปิดเหนือ context เดิม ปิดแล้วกลับ state เดิม และ dialog destructive ไม่มีทาง commit จากการแตะพื้นที่ผิด
3. ตรวจ Back จาก Quiz, Result, Flashcard, AI, Settings และ secondary feature ว่ากลับ parent ที่ถูกต้องและไม่รีเซ็ต progress
4. ตรวจ selected → submit → feedback ทั้งคำตอบถูกและผิด รวมถึงการเปลี่ยนตัวเลือกก่อน submit
5. ตรวจ clipping, overflow และพื้นที่กดที่ 360×800, 393×876, 412×915 และ specimen ข้อความ 200%
6. ตรวจ fold fallback 840dp, qualified two-pane 1024dp, tablet 1280×800 และ boundary height 479/480dp ด้วย Present preview ที่ขนาดจริง

## สิ่งที่ยังต้องตรวจใน runtime

### LDPlayer

LDPlayer เหมาะกับการทดสอบ phone/tablet resolution, DPI, orientation, insets, gesture/3-button navigation, keyboard และ text scale แต่การตั้ง manufacturer/model เป็นเพียง fixture metadata ไม่ใช่หลักฐานของ hinge หรือ posture

ต้องบันทึกอย่างน้อย:

- app window ที่ใช้ได้จริงหลังหัก system bars และ cutout
- text scale 100%, 130% และ 200% โดยไม่มีข้อความสำคัญถูกตัดหรือ ellipsis
- แป้นพิมพ์ที่หน้าเข้าสู่ระบบ/สมัครสมาชิก ค้นหา เพิ่มคำ และผู้ช่วยเรียนด้วย AI โดยช่องพิมพ์กับปุ่มหลักอยู่เหนือแป้นพิมพ์
- portrait/landscape และ boundary 599/600, 839/840, 1199/1200 กับ height 479/480 และ 899/900dp
- route, selected tab, draft, answer และ scroll state ก่อนและหลัง resize/rotate

### Foldable emulator และอุปกรณ์จริง

ต้องใช้ Android foldable emulator ที่รายงาน display features หรืออุปกรณ์จริงเพื่อยืนยัน:

- bounds และ occlusion ของ hinge/seam/cutout ถูกหักจาก usable area จริง
- 840dp reflow เป็น single pane เมื่อ pane minimum ไม่ผ่าน และ 1024dp แสดง two-pane เฉพาะเมื่อ list ≥320dp กับ detail ≥480dp หลังหักทุก exclusion zone
- cover → book → tabletop → cover รักษา state ไม่มี duplicate submit และไม่มีข้อความหรือ CTA คร่อม hinge
- Mate XT single/dual/triple คำนวณ safe regions จาก feature list จริง ไม่แบ่งสองหรือสามส่วนเท่ากันจากภาพจำลอง
- TalkBack order, focus restoration, touch target ≥48×48dp, target gap ≥8dp และการโฟกัสหลัง posture transition

## เกณฑ์ปิด critique

Revision 5 ปิด critique รอบนี้ได้เมื่อมีหลักฐานต่อไปนี้จาก source snapshot เดียวกัน:

- Figma Present walkthrough ของเส้นทางหลักและ overlay ครบ โดยไม่มี dead interaction หรือ contextual Back ผิด
- ภาพและ runtime record ของ compact fixtures ทั้งสามขนาด พร้อม text scale และ IME
- foldable emulator record ที่พิสูจน์ fallback/qualified pane และ state continuity
- accessibility pass สำหรับ contrast, TalkBack reading order, focus และ touch target
- Flutter adaptive shell และหน้าหลักทำงานตาม contract; การมี frame ใน Figma เพียงอย่างเดียวยังไม่ถือว่า implementation ผ่าน

จนกว่าจะมีหลักฐานครบ ให้ระบุสถานะงานว่า **design source reviewed; prototype/runtime acceptance pending**
