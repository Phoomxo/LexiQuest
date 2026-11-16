# TOR/SE การส่งมอบ UI และ Clickable Prototype — LexiQuest Revision 5

สถานะ: ข้อกำหนดการออกแบบ การตรวจรับ และตารางสอบย้อนกลับสำหรับ Figma Revision 5

อัปเดต: 2026-10-18

แพลตฟอร์มเป้าหมาย: Android-first; iOS เป็นงานอนาคต

บัญชีเจ้าของงาน LexiQuest: `petch954100@gmail.com`

## 1. จุดประสงค์ของเอกสาร

เอกสารนี้กำหนดงานออกแบบ LexiQuest Revision 5 ให้ตรวจรับได้แบบงานวิศวกรรมซอฟต์แวร์ โดยครอบคลุมตั้งแต่การเริ่มใช้แอป การเข้าสู่ระบบ เมนูหลัก แบบฝึกทุกชนิด ผู้ช่วยเรียนด้วย AI เกม ความก้าวหน้า โปรไฟล์ การตั้งค่า สถานะผิดพลาด และ responsive/adaptive layout

ผลส่งมอบต้องเป็นต้นแบบที่มีหน้าตาครบ อ่านเป็นภาษาคน กดเดินเส้นทางสำคัญได้ และระบุหลักฐานว่าความสามารถทั้ง 44 รายการปรากฏที่หน้าจอหรือข้อกำหนดระบบใด งานออกแบบนี้ใช้ตัดสินโครงสร้าง ประสบการณ์ และความครบถ้วนก่อนพัฒนา แต่ไม่ใช่หลักฐานว่า Flutter, OAuth, AI, ฐานข้อมูล หรือบริการภายนอกทำงานจริงแล้ว

## 2. แหล่งอ้างอิงที่มีอำนาจ

ให้ยึดแหล่งต่อไปนี้ตามลำดับเมื่อข้อมูลขัดกัน:

1. แค็ตตาล็อกผลิตภัณฑ์ 8 หมวด 44 ความสามารถ Revision `1.3.0` และ hash `41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4`
2. สัญญา responsive/adaptive ใน [`lexiquest-revision-5-responsive-contract.md`](lexiquest-revision-5-responsive-contract.md)
3. แผนเส้นทางต้นแบบใน [`figma-prototype-flow-map.md`](figma-prototype-flow-map.md)
4. ทิศทางภาพและภาษาใน [`lexiquest-revision-5-direction.md`](lexiquest-revision-5-direction.md)
5. วงจรส่งมอบ Intent → Ground → Plan → Execute → Review → Attest → Integrate → Learn ใน [`../development/agentic-development-life-cycle.md`](../development/agentic-development-life-cycle.md)

รายการ 8/44 เป็นขอบเขตความสามารถ ไม่ใช่จำนวนตารางฐานข้อมูล และห้ามเพิ่มหมายเลข `f45` เพื่อรองรับหน้าจอที่ยังไม่มีรหัส สถานะ `existing`, `partial` และ `new capability` ในแค็ตตาล็อกบอกระดับความครอบคลุมของผลิตภัณฑ์ ไม่ได้อนุญาตให้เปิดใช้จริงโดยอัตโนมัติ

ฐานความครอบคลุมตาม Revision 1.3.0 คือ `existing 8`, `partial 23` และ `new capability 13` รวม 44 รายการ ตัวเลขนี้ใช้วางแผนและสอบย้อนกลับเท่านั้น ไม่ใช่สถานะว่าทั้ง 44 รายการเปิดใช้ใน runtime แล้ว

## 3. ขอบเขตและหลักส่งมอบ

### 3.1 อยู่ในขอบเขต

- หน้าจอและสถานะตั้งแต่เปิดแอป สมัคร เข้าสู่ระบบ เริ่มใช้งาน จนถึงออกจากระบบ
- จุดหมายหลัก 4 รายการ: **เรียน**, **คลังคำ**, **ก้าวหน้า**, **โปรไฟล์**
- ทุกหน้าหลัก หน้าย่อย เมนู dialog bottom sheet snackbar และสถานะ loading/empty/error/offline/permission denied ที่มีผลต่อการเดินงาน
- ตัวอย่าง compact phone, tablet, foldable และหน้าต่างความสูงจำกัดตามสัญญา responsive
- interaction ระหว่างหน้าจอ พร้อม Back, Cancel, Retry, Confirm และเส้นทาง fallback
- ตารางสอบย้อนกลับ `f01–f44` ไปยังหน้าจอ สถานะ หรือสัญญาระบบ
- เกณฑ์ accessibility, privacy, optional research และการตรวจรับต้นแบบ

### 3.2 อยู่นอกขอบเขตของการรับรองรอบนี้

- การเผยแพร่ขึ้น Store, production deployment หรือ public rollout
- การยืนยันว่า Google OAuth, Gemini, กล้อง ไมโครโฟน push notification และ cloud sync ทำงานจริง
- การรับรอง iOS
- การอ้างว่าทดสอบบนอุปกรณ์จริง Samsung/Huawei/Vivo แล้ว หากไม่มี runtime evidence record
- การเปิดรับผู้เข้าร่วมวิจัยจริงหรืออัปโหลดข้อมูลวิจัยจริง

## 4. แนวทางภาพ ภาษา และองค์ประกอบ

### 4.1 บุคลิกของงาน

งานต้องให้ความรู้สึกเป็นการเดินทางเรียนรู้ที่มีพลัง แต่ไม่เหมือนเกมคาสิโน ใช้ระบบเข็มทิศ เส้นทาง ดวงดาว หรือแผนที่เป็นลวดลายประกอบแบบพอดี การ์ดหลักมีชั้นความสำคัญชัด พื้นหลังสร้างบรรยากาศได้โดยไม่ลดความคมชัดของข้อความ ผลลัพธ์ของกิจกรรมต้องให้ความรู้สึกว่างานสำเร็จ ก่อนแสดงรายละเอียดรอง

หน้าเรียนใช้กลิ่นอายเส้นทางและภารกิจแบบ Duolingo ผสมการจัดกลุ่มข้อมูลและตัวกรองที่เป็นระบบแบบ AllTCAS ส่วนผู้ช่วยเรียนด้วย AI ใช้รูปแบบสนทนาที่คุ้นเคยคล้าย LINE/Messenger โดยยังแสดงแหล่งที่มา ข้อจำกัด และทางเลือกกลับไปเรียนแบบ local

### 4.2 ภาษาไทยสำหรับคนทั่วไป

- ใช้ชื่อที่บอกสิ่งที่จะเกิดขึ้น เช่น `เรียงคำให้เป็นประโยค`, `เติมคำในช่องว่าง`, `ทบทวนคำที่ยังไม่แม่น`
- หลีกเลี่ยงชื่อที่ผู้ใช้ต้องเดา เช่น `Activity Catalog`, `S`, `Ghost Battle` หรือศัพท์เทคนิคที่ไม่มีคำอธิบาย
- ถ้าจำเป็นต้องคงชื่อเทคนิค ให้มีคำไทยนำหน้าและคำอธิบายสั้น เช่น `ระดับคำศัพท์ CEFR — ใช้จัดเนื้อหา ไม่ใช่ใบรับรอง`
- ปุ่มใช้กริยาเฉพาะเจาะจง เช่น `เริ่มทบทวน 12 คำ`, `บันทึกและไปต่อ`, `ส่งลิงก์ตั้งรหัสใหม่`
- ข้อผิดพลาดต้องบอกว่าเกิดอะไรขึ้น ข้อมูลถูกบันทึกหรือไม่ และผู้ใช้ทำอะไรต่อได้

### 4.3 ระบบภาพขั้นต่ำ

| รายการ | ข้อกำหนด |
| --- | --- |
| Spacing | ฐาน 4dp; ระยะใช้งานหลัก 8, 12, 16, 20, 24, 32 และ 48dp |
| Touch target | อย่างน้อย 48×48dp และห่างจาก target ข้างเคียงอย่างน้อย 8dp |
| Typography | ลำดับ Display/Headline/Title/Body/Label ชัด; ไม่ใช้ตัวเล็กเพื่อยัดข้อมูล |
| Form | ความกว้างสูงสุด 560dp; label ไม่หายเมื่อพิมพ์; error อยู่ติด field |
| Prose | ความกว้างสูงสุด 640dp |
| งานหลัก | ความกว้างสูงสุด 720dp; มี primary action เด่นเพียงหนึ่งรายการต่อจังหวะ |
| ผู้ช่วยเรียนด้วย AI | ความกว้างสูงสุด 760dp; bubble อ่านง่ายและแยกผู้พูดด้วยสี รูปทรง และ label |
| สีและสถานะ | ห้ามใช้สีเป็นสัญญาณเดียว ต้องมี icon/ข้อความ/รูปทรงร่วมด้วย |
| Motion | การเปลี่ยนหน้า 180–240ms เป็นค่าเป้าหมาย; Reduced Motion ต้องตัด animation ที่ไม่จำเป็น |

## 5. โครงสร้างไฟล์ Figma หน้าเดียว

ภายใน Page เดียวให้แบ่ง section จากซ้ายไปขวาและบนลงล่าง เพื่อค้นหาและส่งมอบได้โดยไม่ต้องย้ายข้ามหลาย Page:

1. `00 Cover & Delivery Index` — ชื่อ revision, เจ้าของ, legend และสถานะหลักฐาน
2. `01 Foundations` — สี ตัวอักษร spacing icon states และ component variants
3. `02 Account & Onboarding` — ชุดหน้าบัญชี A01–A12
4. `03 Phone · Core Flows` — หน้าหลัก P06–P59 และหน้าความสามารถ 8/44
5. `04 System States & Overlays` — loading, empty, offline, error, permission และ dialog
6. `05 Adaptive Models` — compact, medium, expanded, large, fold และ compact-height
7. `06 Flow Map & Traceability` — ลูกศร เส้นทางเริ่ม และตาราง f01–f44
8. `07 Delivery Evidence` — route audit, test matrix, known limitations และ revision history

ชื่อ frame ใช้รูปแบบ `Axx/Auth/ชื่อสถานะ`, `Pxx/ชื่อหน้า/สถานะ`, `Oxx/ชื่อ overlay`, `Sxx/ชื่อ system state` และ `Txx/ชื่อ adaptive frame` ทุกชื่อ action layer ที่กดได้ต้องใช้ prefix ที่ตรวจสอบได้ เช่น `CTA/`, `Nav/`, `Menu/`, `Choice/`, `Setting/`, `Filter/`, `Word/` หรือ `AppBar/`

## 6. ชุดบัญชีและการเริ่มใช้งาน

| ID | หน้า/สถานะ | เนื้อหาและ action ที่ต้องมี | เส้นทางรับรอง |
| --- | --- | --- | --- |
| A01 | ยินดีต้อนรับ | คุณค่าหลักแบบสั้น, `เริ่มใช้งาน`, `ฉันมีบัญชีแล้ว`, ลิงก์นโยบาย | เริ่มใช้งาน → A02; มีบัญชี → A03 |
| A02 | เลือกวิธีเริ่ม | `ใช้บัญชี Google`, `สมัครด้วยอีเมล`, `ทดลองใช้ก่อน` พร้อมผลของแต่ละทาง | Google → A04; อีเมล → A07; ทดลอง → A12 |
| A03 | เข้าสู่ระบบ | Google, อีเมล, รหัสผ่าน, แสดง/ซ่อนรหัส, `ลืมรหัสผ่าน?`, สร้างบัญชี | Google → A04; submit → busy/ผลลัพธ์; ลืม → A09; สมัคร → A07 |
| A04 | เลือกบัญชี Google | chooser จำลองที่ระบุว่าเป็นหน้าของ Google และแสดงสิทธิที่ LexiQuest ขอ | เลือกบัญชี → A05 หรือหน้าเรียน; ยกเลิก → A02/A03 |
| A05 | ยืนยันการเชื่อมบัญชี | ใช้เมื่ออีเมลเดิมมีวิธีเข้าระบบอื่น; อธิบายว่าข้อมูลใดจะรวมและไม่รวม | ยืนยัน → หน้าเรียน; ใช้อีเมลแทน → A03 |
| A06 | เข้าสู่ระบบไม่สำเร็จ | สาเหตุที่ปลอดภัย ไม่เปิดเผยว่ามีบัญชีหรือไม่; `ลองอีกครั้ง`, `ตั้งรหัสใหม่` | ลอง → A03; ตั้งใหม่ → A09 |
| A07 | สร้างบัญชีด้วยอีเมล | ชื่อที่แสดง, อีเมล, รหัสผ่าน, **ยืนยันรหัสผ่าน**, ข้อตกลงที่จำเป็นแยกจากงานวิจัย | ผ่าน validation → A08; มีบัญชี → A03 |
| A08 | แนะนำรหัสผ่าน | เงื่อนไขที่อ่านง่าย, strength feedback, mismatch error, แสดง/ซ่อนทั้งสอง field | ปิด/ผ่าน → A07; ห้ามสร้างบัญชีเมื่อสองช่องไม่ตรง |
| A09 | ลืมรหัสผ่าน | อีเมลและข้อความตอบแบบกลาง เพื่อไม่เปิดเผยสถานะบัญชี | ส่ง → A10; ยกเลิก → A03 |
| A10 | ส่งลิงก์แล้ว | บอกให้ตรวจ Inbox/Spam, resend แบบมี cooldown, เปลี่ยนอีเมล | เปิดลิงก์ → A11; กลับเข้าสู่ระบบ → A03 |
| A11 | ผลการยืนยันอีเมล/ตั้งรหัสใหม่ | loading, success, expired, invalid และ action ที่เหมาะกับแต่ละสถานะ | success → A03/หน้าเรียน; expired → A09 |
| A12 | ตั้งเป้าหมายเริ่มต้น | เป้าหมาย ระยะเวลาต่อวัน ความสนใจ รูปแบบที่ชอบ และข้ามได้ | บันทึก/ข้าม → หน้า `เรียน` |

### 6.1 Google Sign-in ที่ถูกต้อง

คำว่า “เข้าด้วย Gmail” ใน UI ให้ใช้ `ใช้บัญชี Google` และการพัฒนาจริงบน Android ต้องใช้ Credential Manager/Sign in with Google ตามแนวทางของ Google ผู้ใช้เลือกบัญชีและทำการยืนยันตัวตนในพื้นผิวที่ Google ดูแล LexiQuest ห้ามขอรหัสผ่าน Google หรือรหัส Google Authenticator โดยตรง หากบัญชีเปิดการยืนยันสองขั้นตอน Google จะเป็นผู้ดำเนินการใน flow ของตน

ตัวเลือก Google ใน Figma เป็นการจำลองเส้นทางและผลลัพธ์เท่านั้น การตรวจรับ runtime ต้องแยกออกไปทำกับ client ID, SHA certificate, nonce/state, token verification และ account-linking policy ที่ตั้งค่าจริง อ้างอิง: [Credential Manager](https://developer.android.com/identity/sign-in/credential-manager) และ [Sign in with Google](https://developer.android.com/identity/sign-in/credential-manager-siwg)

## 7. รายการหน้าจอและเมนูที่ต้องมี

### 7.1 Shell หลัก

| ID | หน้า | งานหลัก | หน้าย่อยที่เปิดได้ |
| --- | --- | --- | --- |
| P06 | เรียน | เริ่มงานวันนี้ ทำต่อ รับคำแนะนำ และเปิดเครื่องมือ | P18, P20, P22, P28, P31, P40–P46 |
| P07 | คลังคำ | ค้นหา หมวด คำล่าสุด เพิ่มและนำเข้า | P10–P17 |
| P08 | ก้าวหน้า | จุดที่แม่น จุดที่ควรทบทวน เวลาเรียน และหลักฐาน | P24–P27, P30R |
| P09 | โปรไฟล์ | บัญชี รางวัล รูปลักษณ์ และการตั้งค่า | P48–P58 |

### 7.2 คลังคำ

- P10 หมวดคำศัพท์
- P11 รายการคำในหมวด
- P12 รายละเอียดคำแบบ rich lexical card
- P13 ค้นหาและตัวกรอง
- P14 เพิ่ม/แก้ไขคำ
- P15 เพิ่มหลายคำ
- P16 เลือกแหล่งนำเข้า
- P17 ตรวจข้อมูลก่อนนำเข้า

ทุกหน้าต้องมี loading, empty, no-result, validation และ write failure ตามงานของหน้า การลบ/ทิ้งข้อมูลที่แก้ค้างต้องมี confirmation

### 7.3 การเรียนและแบบฝึก

- P18 เลือกกิจกรรม โดยใช้ชื่อไทยที่เข้าใจทันที พร้อม badge `ใช้ได้`, `ทดลอง`, `ยังไม่เปิดใช้`
- P19 เลือกหมวดหรือชุดคำ
- P20 แบบฝึกคำถาม: ความหมาย นิยาม เติมคำ จับคู่ พิมพ์คำ และแบบฝึกเฉพาะของ LexiQuest
- P21 ผลตอบกลับทันที: `ถูก/ยังไม่ถูก · บันทึกแล้ว`, เหตุผล ตัวหลอกที่สับสน และคำแนะนำ
- P22 แฟลชการ์ดและการให้ระดับความจำ
- P23 สรุปผล: ความสำเร็จ คำที่ควรซ่อม งานถัดไป และกลับแผน
- P31 บทความ/เนื้อหาอ่าน
- P32 การอ่านเชื่อมโยง 6 ขั้น พร้อมบันทึกตำแหน่ง

โหมดพิมพ์และเขียนด้วยมือมีตัวเลือกแป้นพิมพ์/พื้นที่ขีดเขียนตามความเหมาะสม เมื่อ keyboard เปิดต้องยังเห็น prompt, คำตอบล่าสุด และ CTA

### 7.4 ความก้าวหน้า แผน และการประเมิน

- P24 ภาพรวมความก้าวหน้า
- P25 จุดที่ควรทบทวน
- P26 เหรียญและความสำเร็จ โดยแยก reward ออกจาก mastery
- P27 รายละเอียดหลักฐานและรุ่นข้อมูล
- P28 เส้นทางการเรียน
- P29 คลังเนื้อหาระดับ CEFR
- P30 แบบประเมิน
- P30R ผลประเมิน พร้อมข้อจำกัดของ sample; ห้ามอ้างเป็นใบรับรอง
- หน้าศูนย์ทบทวน, จับเวลาโฟกัส, ปฏิทินการเรียน, นับถอยหลังเป้าหมาย, เตือนเรียนแบบ opt-in และเปรียบเทียบก่อน/หลัง

### 7.5 เกม เสียง กล้อง และผู้ช่วยเรียนด้วย AI

- P33 เรียงตัวอักษรเป็นคำ
- P34 เรียงคำเป็นประโยค
- P35 เติมคำในช่องว่าง
- P36 ฟังแล้วเขียน
- P37 ด่านท้าทาย
- P38 แข่งกับสถิติเดิมของตนเอง
- P39 ผลการท้าทาย
- P40 พูดแล้วแปลงเป็นข้อความ
- P41 ฝึกพูดตาม
- P42 สำรวจเสียงและสัทอักษร
- P43 เพลย์ลิสต์เสียงเพื่อทบทวน
- P44 สแกนสิ่งของ
- P45 ตรวจผลจากกล้องก่อนเพิ่มเข้าคลัง
- P46 ผู้ช่วยเรียนด้วย AI แบบบทสนทนา
- P47 ตั้งค่าผู้ให้บริการ AI/BYOK พร้อม consent, quota, remove และ local fallback

P46 ใช้ลำดับแบบ Messenger: header บอกบริบท, bubble ผู้เรียน, bubble ผู้ช่วย, แหล่งที่มา/ข้อจำกัดใต้คำตอบ และ composer ที่ยกเหนือ IME เมื่อ offline, quota เต็ม หรือ provider ใช้ไม่ได้ ต้องมี `เรียนต่อแบบออฟไลน์` ไป P18

### 7.6 รางวัล โปรไฟล์ การตั้งค่า และข้อมูล

- P48 ร้านรางวัล
- P49 รูปลักษณ์ อุปกรณ์ avatar ธีม และตัวอย่าง Reduced Motion
- P50 สรุปโปรไฟล์และสถานะบัญชี
- P51 หน้ารวมการตั้งค่า
- P52 บัญชี: สถานะอีเมล เปลี่ยนรหัส ออกจากระบบ และยกระดับ Guest
- P53 การเรียนและการช่วยการเข้าถึง
- P54 สิทธิอุปกรณ์: ไมโครโฟน กล้อง และเส้นทางไป Android Settings
- P55 การตั้งค่า AI
- P56 ความเป็นส่วนตัวและความยินยอมงานวิจัย
- P57 ศูนย์ส่งออกข้อมูล
- P58 ความคืบหน้า/ผลการส่งออก
- P59 แดชบอร์ดวิจัยภายใน แสดง `ข้อมูลสังเคราะห์เท่านั้น` และไม่อยู่ในเมนูผู้เรียนทั่วไป

การตั้งค่าหลักต้องมี theme Light/Dark/System, ขนาดตัวอักษร, ลดการเคลื่อนไหว, เสียง/TTS/ความเร็ว, haptic, ภาษา, download/offline, privacy, export, ลบบัญชีตามสัญญาผลิตภัณฑ์ และ sign out โดย action ที่กระทบข้อมูลต้องบอกผลตามจริงก่อนยืนยัน

### 7.7 Overlays และ system-state specimens

Overlays ที่ต้องแยกเป็น component/variant และต่อกลับ flow จริง ได้แก่ เพิ่มหมวดคำ, ยืนยันลบคำ, ทิ้งแบบร่าง, ออกจากรอบเรียน, ตัวช่วยสร้างความเชื่อมโยง, เหตุผลการขอไมโครโฟน, เหตุผลการขอกล้อง, ลบคีย์ผู้ให้บริการ AI, ยืนยันซื้อ, เปลี่ยนรหัสผ่าน, ออกจากระบบ และยอมรับ/ถอนความยินยอมวิจัย ปุ่มยกเลิกต้องเป็นค่าเริ่มต้นของ action ที่ทำลายหรือเปลี่ยนข้อมูลสำคัญ

System-state specimens ใช้รหัส S01–S10 และต้องถูกนำไปใช้กับหน้าจอจริง ไม่ใช่วางเป็นภาพตัวอย่างที่เข้าไม่ถึง:

| ID | สถานะ | สิ่งที่ต้องเห็น | ทางออกหลัก |
| --- | --- | --- | --- |
| S01 | Loading | skeleton รักษา layout และ busy semantics | รอหรือยกเลิกเฉพาะงานที่ยกเลิกได้ |
| S02 | Empty | ขาดข้อมูลอะไร เพราะอะไร | เพิ่มคำ นำเข้า หรือเริ่มเก็บ baseline |
| S03 | Error | งานใดล้มเหลวและข้อมูลถูกแก้หรือยัง | ลองใหม่; กลับ/หน้าแรกเป็นทางรอง |
| S04 | Offline | งาน local ที่ยังทำได้และบริการที่พักไว้ | เรียนต่อแบบออฟไลน์ |
| S05 | Permission denied | เหตุผลที่ขอและสิ่งที่ยังทำได้ | ขออีกครั้งหรือใช้ทางเลือกอื่น |
| S06 | Permanently denied | ต้องเปิดสิทธิจาก Android Settings | เปิดการตั้งค่าหรือยกเลิก |
| S07 | Save pending | ปิด control ต้นทางและยังไม่ขยับ progress | ลองใหม่/ยกเลิกตาม transaction |
| S08 | Save acknowledged | `บันทึกแล้ว` และ feedback ยังคงอยู่ | ไปต่อ |
| S09 | Limited feature | badge และ dependency ที่ขาด | ตั้งค่า ดาวน์โหลด หรือใช้ local fallback |
| S10 | Destructive confirmation | object, consequence และกริยาเฉพาะ | ยืนยัน; ยกเลิกเป็นค่าเริ่มต้น |

## 8. ตารางสอบย้อนกลับ 8 หมวด 44 ความสามารถ

ตารางนี้กำหนด “จุดพิสูจน์ในงานออกแบบ” แต่ไม่เปลี่ยนสถานะ rollout ใน runtime

| หมวด | ID | ความสามารถตามแค็ตตาล็อก | จุดพิสูจน์ UI/ระบบใน Revision 5 |
| --- | --- | --- | --- |
| เนื้อหาและชุดเรียน | f01 | Curriculum & Learning Pack Catalog | P28/P29 รายการชุดเรียน ค้นหา ตัวกรอง CEFR/หัวข้อ/เป้าหมาย |
| เนื้อหาและชุดเรียน | f02 | Learning Pack Detail | หน้ารายละเอียดชุด: เป้าหมาย เนื้อหา รุ่น ดาวน์โหลด และเริ่มเรียน |
| เนื้อหาและชุดเรียน | f03 | Rich Lexical Card | P12/P22 แสดงคำ ความหมาย เสียง ตัวอย่าง ชนิดคำ ภาพ และสถานะจำ |
| เนื้อหาและชุดเรียน | f04 | Content Version & Quality Control | P12/P27/P44–P45 แสดงรุ่น แหล่งที่มา และรายงานเนื้อหา; เป็นสัญญาระบบด้วย |
| ประสบการณ์เรียนร่วม | f05 | Unified Lesson Shell | P20–P23 ใช้ header/progress/checkpoint/finish pattern เดียวกัน |
| ประสบการณ์เรียนร่วม | f06 | Flashcard Mode | P22 question/reveal/rating/save states |
| ประสบการณ์เรียนร่วม | f07 | Meaning Quiz | P20/P21 เลือกความหมายและรับผลทันที |
| ประสบการณ์เรียนร่วม | f08 | Definition Quiz | P20/P21 อ่านนิยามแล้วเลือกคำ |
| ประสบการณ์เรียนร่วม | f09 | Cloze Test | P35 เติมคำในบริบทพร้อม feedback |
| ประสบการณ์เรียนร่วม | f10 | Matching Mode | หน้าจับคู่คำ–ความหมาย รองรับ selected/matched/error/complete |
| ประสบการณ์เรียนร่วม | f11 | Typed Recall / Writing | P20 โหมดพิมพ์คำ ตรวจก่อนส่งและรักษา draft เมื่อ IME เปลี่ยน |
| ประสบการณ์เรียนร่วม | f12 | Handwriting Scratchpad | พื้นที่ขีดเขียน ล้าง ย้อนกลับ และส่งคำตอบแบบมีข้อความทดแทน |
| ประสบการณ์เรียนร่วม | f13 | LexiQuest Native Modes Integration | P31–P45 เข้า shell เดียวและกลับสรุป P23 โดยไม่สร้าง progress ซ้ำ |
| การจำและผลตอบกลับ | f14 | Flashcard-First Recommendation | P06/P22 การ์ดแนะนำทบทวนพร้อมเหตุผลและจำนวนคำ |
| การจำและผลตอบกลับ | f15 | Active-Recall Ladder | P06/P23/P25 แสดงขั้นฝึกจากจำแบบช่วยไปจนตอบเอง |
| การจำและผลตอบกลับ | f16 | Session Configuration | ก่อนเริ่ม: จำนวนคำ เวลา โหมด เสียง และตัวเลือก accessibility |
| การจำและผลตอบกลับ | f17 | Immediate Answer Feedback | P21 บอกผล บันทึกแล้ว/ไม่สำเร็จ และ action ถัดไป |
| การจำและผลตอบกลับ | f18 | Contrastive Distractor Explanation | P21 เปรียบเทียบคำตอบที่เลือกกับคำตอบถูก โดยไม่ยัดข้อความเกินจอ |
| การจำและผลตอบกลับ | f19 | Hint, Strategy & Context | hint sheet และคำแนะนำตามบริบทจาก P20/P21/P46 |
| การจำและผลตอบกลับ | f20 | Bookmark / Save | ปุ่มบันทึกใน P12/P20/P31 พร้อม saved/unsaved/offline state |
| การจำและผลตอบกลับ | f21 | Flag / Report Content | report sheet ระบุชนิดปัญหา รุ่นเนื้อหา และผลส่ง/เก็บคิว |
| ทบทวน เวลา ประเมิน | f22 | Review Center | ศูนย์ทบทวนจาก P06/P08 รวม due, saved, reported และ mistakes |
| ทบทวน เวลา ประเมิน | f23 | Focus Timer | ตั้งเวลา พัก หยุด และ resume โดยไม่บังคับใช้ timer กับ accessibility |
| ทบทวน เวลา ประเมิน | f24 | Automatic Learning-Time Capture | P23/P24 แสดงเวลาที่บันทึกและกฎ pause/background; authority อยู่ในระบบ |
| ทบทวน เวลา ประเมิน | f25 | Learning Calendar & Weekly Analytics | ปฏิทิน/สัปดาห์ใน P08 แยกเวลา ความถี่ และผลการเรียน |
| ทบทวน เวลา ประเมิน | f26 | Goal / Test Countdown | P06/P09 ตั้งวันเป้าหมายและนับถอยหลัง พร้อมแก้/ปิด |
| ทบทวน เวลา ประเมิน | f27 | Opt-in Study Reminder | settings เตือนเรียน default-off กำหนดวัน/เวลาและยกเลิกได้ |
| ทบทวน เวลา ประเมิน | f28 | Learning Assessment & Progress Comparison | P30/P30R แยกแบบประเมินก่อน–หลังจากการฝึกทั่วไป |
| แรงจูงใจ | f29 | Evidence-Based Quest | P06 ภารกิจระบุงาน หลักฐานสำเร็จ และรางวัลที่ไม่แทน mastery |
| แรงจูงใจ | f30 | Gentle Streak | P06/P08 แสดงความต่อเนื่องแบบไม่ลงโทษเมื่อพลาด |
| แรงจูงใจ | f31 | Achievement & Milestone | P26 เงื่อนไขและวันที่ปลดล็อกอ้างอิง evidence |
| แรงจูงใจ | f32 | Avatar Level-Up & Cosmetic Unlock | P48/P49 preview, locked/owned/equipped และ purchase confirmation |
| แรงจูงใจ | f33 | Contextual Companion | companion ตอบสนองต่อเหตุการณ์แบบมีข้อความและ Reduced Motion |
| แรงจูงใจ | f34 | Achievement Share Card | composer การ์ดแชร์ preview/save/share/cancel โดยไม่เปิดเผยข้อมูลเกินจำเป็น |
| ปรับให้เหมาะกับผู้ใช้ | f35 | Learning Preference & Goal Quiz | A12 ตั้งเป้าหมาย เวลา ความสนใจ รูปแบบชอบ และข้ามได้ |
| ปรับให้เหมาะกับผู้ใช้ | f36 | Personal Learning Profile | P50/P53 สรุปข้อมูลที่ใช้ปรับการเรียนและเปิดให้แก้ไข |
| ปรับให้เหมาะกับผู้ใช้ | f37 | Recommendation Panel | P06/P23 บอกงานแนะนำ เหตุผล และทางเลือกอื่น |
| ปรับให้เหมาะกับผู้ใช้ | f38 | Accessibility | P53 และ variants text scale/TalkBack/non-color/untimed/input fallback |
| ปรับให้เหมาะกับผู้ใช้ | f39 | Motion & Theme Controls | P49/P53 Light/Dark/System/Reduced Motion พร้อม preview |
| local/offline/rollout | f40 | Local-First Operation | offline banner, queued/synced/conflict states; P43/history อ่านจาก local ได้ |
| local/offline/rollout | f41 | Feature Flag & Controlled Rollout | P18 แสดง enabled/limited/hidden อย่างซื่อสัตย์; เป็นสัญญาระบบ ไม่ใช่ toggle ผู้ใช้ |
| วันนี้และประวัติ | f42 | Today Hub | P06 รวม assigned, due, resume และ recommended โดยไม่สร้างคะแนนใหม่ |
| วันนี้และประวัติ | f43 | Learning History | ประวัติ session แบบอ่านอย่างเดียว; replay สร้าง session ใหม่ |
| local/offline/rollout | f44 | Offline Content Manager | settings/download manager: download, verify, pin, repair, remove โดยไม่ลบ evidence |

## 9. Responsive และ adaptive contract

ให้เลือก layout จากขนาด window ที่แอปใช้ได้จริงในหน่วย dp หลังพิจารณา insets, IME และ display features ห้ามเลือกจากชื่อรุ่นหรือความละเอียด panel อย่างเดียว

| Width | ช่วง | โครงและ navigation |
| --- | ---: | --- |
| Compact | `<600dp` | single pane, NavigationBar 4 จุดหมาย, gutter 16–20dp |
| Medium | `600–839dp` | centered single pane/2-column บางส่วน, NavigationRail, gutter 24dp |
| Expanded | `840–1199dp` | list-detail เมื่อ list ≥320dp และ detail ≥480dp หลังหักทุก exclusion |
| Large | `1200–1599dp` | two-pane ใน shell สูงสุด 1200dp, gutter 48dp; 1280×800 ใช้สัดส่วนใกล้ 42:58 |
| ≥1600dp | fallback | ใช้ Large shell สูงสุด 1200dp จนกว่าจะมีหลักฐานรับรอง breakpoint ใหม่ |

| Height | ช่วง | กฎ |
| --- | ---: | --- |
| Compact | `<480dp` | single pane + NavigationBar เสมอ, ลด gap และให้ body เลื่อนได้ |
| Medium | `480–899dp` | ใช้ width class เมื่อแต่ละ pane ผ่าน minimum |
| Expanded | `≥900dp` | เพิ่มบริบทได้ แต่ยังมีงานหลักเด่นเพียงหนึ่งอย่าง |

ชุดตรวจขั้นต่ำคือ 360×800, **393×876 Vivo baseline**, 412×915, 600×960, 800×1280, 1024×1366, 1280×800, 800×479 และ 800×480dp การเปลี่ยนขนาดใน LDPlayer พิสูจน์ได้เฉพาะ resolution/DPI/orientation/text scale ไม่พิสูจน์ hinge หรือ posture

สำหรับจอพับ/จอคู่/จอสามพับ ต้องใช้ bounds ที่ runtime รายงาน แบ่ง safe region ตาม geometry จริง ห้ามวางข้อความ CTA dialog center หรือ focus indicator คร่อม hinge/seam เมื่อพื้นที่แต่ละด้านไม่ผ่านขั้นต่ำให้กลับเป็น single primary pane และรักษา route, selection, scroll, draft, quiz progress และการส่งคำตอบไม่ให้ซ้ำหลัง resize/fold/unfold

## 10. Interaction และเกณฑ์ clickable prototype

### 10.1 กฎการต่อเส้น

- ทุก layer ที่ตั้งชื่อด้วย interactive prefix ต้องมี interaction อย่างน้อยหนึ่งรายการ
- ปุ่มหลักต้องไป target ที่สมเหตุผล; ห้ามใช้ self-loop เพื่อทำให้ route audit ผ่าน ยกเว้น control ที่ตั้งใจเปลี่ยน state ใน frame เดิมและระบุไว้
- NavigationBar/Rail ไป P06–P09 ที่ตรงกันและคง selected state
- Back จาก nested task กลับ source เดิม; Back ระหว่าง session เปิด confirmation ก่อนออก
- Dialog/Bottom sheet มี Confirm/Cancel/Back ครบ และ Cancel ไม่เขียนข้อมูล
- Retry ต้องกลับ operation ที่ล้มเหลวโดยไม่สร้างรายการซ้ำ
- finished session ห้าม Back กลับไปยัง active question เก่า
- resize/rotate/fold เปลี่ยน shell โดยไม่ถือเป็น navigation event

### 10.2 Flow starting points ที่ต้องกดจบได้

1. **สมัครด้วยอีเมล:** A01 → A02 → A07 → A08 → A11 → A12 → P06
2. **เข้าด้วย Google:** A01/A03 → A04 → A05 เมื่อจำเป็น → A12/P06; Cancel กลับจุดเริ่มเดิม
3. **ลืมรหัสผ่าน:** A03 → A09 → A10 → A11 → A03
4. **เรียนประจำวัน:** P06 → P20 → P21 → P20/P23 → P06
5. **แฟลชการ์ด:** P06/P18 → P22 → P23 → P06/P25
6. **เพิ่มคำแล้วฝึก:** P07 → P10 → P11 → P14 → P12 → P20 → P21 → P23
7. **นำเข้าคำ:** P07/P11 → P16 → P17 → P11 → P22 → P23
8. **ซ่อมจุดอ่อน:** P08 → P25 → P20/P22 → P23 → P24/P27
9. **เส้นทางและบทอ่าน:** P06 → P28 → P29 → P31 → P32 → P23/P31
10. **ผู้ช่วยเรียนด้วย AI:** P06/P18 → P46 → P47 เมื่อยังไม่ตั้งค่า → P46; offline/quota → P18
11. **กล้องเข้าคลังคำ:** P06/P18 → P44 → permission → P45 → P12/P11
12. **โปรไฟล์และข้อมูล:** P09 → P51 → P52–P58 → กลับ P51/P09
13. **tablet list-detail:** T02 เลือกหมวด → คำ → รายละเอียด; แคบลงเป็น P12 โดยรักษา selection/scroll

### 10.3 Route audit ที่ต้องแนบ

- จำนวน interactive nodes ทั้งหมด
- จำนวน nodes ที่มี reaction และรายชื่อ nodes ที่ไม่มี reaction
- รายการ source → action → target สำหรับ flow ทั้ง 13 ชุด
- รายการ missing target, duplicate layer name, non-navigation self-loop และ unreachable primary frame ต้องเป็นศูนย์
- ทุก `f01–f44` ต้องปรากฏใน traceability map ครั้งละหนึ่งรายการหลัก โดย cross-reference เพิ่มได้

## 11. Accessibility และภาวะใช้งานผิดปกติ

### 11.1 การช่วยการเข้าถึง

- รองรับ text scale 100%, 130% และ 200%; prompt, feedback, error และ primary action ห้ามถูก ellipsis ตัดสาระ
- ลำดับ TalkBack เดินตามลำดับการอ่านและไม่อ่าน decoration
- icon-only action มีชื่อที่สื่อความหมาย และ selected/disabled/error ไม่พึ่งสีอย่างเดียว
- focus indicator มองเห็นชัดทั้ง Light/Dark และไม่คร่อม hinge
- time-based activity มีทางเลือกไม่จับเวลา เว้นแต่เวลาคือสิ่งที่ผู้ใช้เลือกฝึกเอง
- เสียงมี transcript; กล้องมีการตรวจผลด้วยข้อความ; handwriting มี typed alternative
- Reduced Motion ลด parallax, celebration และ transition ที่ไม่จำเป็น โดยยังบอกความสำเร็จครบ

### 11.2 สถานะที่หน้าสำคัญต้องมี

`idle`, `loading/busy`, `empty`, `success`, `inline validation`, `recoverable error`, `offline/local fallback`, `permission denied`, `permanently denied`, `service unavailable`, `limited/hidden feature` และ `saving/retry` ให้ใช้เฉพาะสถานะที่เกี่ยวข้องกับงานของหน้า

ข้อความสถานะต้องตอบสามข้อ: เกิดอะไรขึ้น, งานถูกบันทึกหรือยัง, ทำอะไรต่อได้ ห้ามแสดงหน้าว่างหรือ spinner ค้างโดยไม่มีทางออก

## 12. ขอบเขตข้อมูล ความยินยอม และงานวิจัย

- การเรียนทั่วไปต้องทำงานได้โดยไม่ยอมเข้าร่วมวิจัย
- research enrollment, collection, upload และ P59 เป็น **default-off** จนกว่าจะมี authority, permit, consent revision และ rollout authorization ที่ต้องใช้
- ข้อตกลงบัญชีที่จำเป็นและความยินยอมวิจัยต้องเป็นคนละรายการ ห้าม pre-check ความยินยอมวิจัย
- การถอนความยินยอมต้องบอกผลต่อข้อมูลเดิม/ใหม่ตามสัญญาจริง และไม่ทำลายการเรียนทั่วไป
- unavailable authority ต้อง fail closed เฉพาะงานวิจัย ไม่ปิดการเรียนที่ไม่เกี่ยวข้อง
- งานต้นแบบใช้ข้อมูลสังเคราะห์ ห้ามใส่ credentials, private keys, คำตอบผู้เข้าร่วม หรือ guardian PII
- local-first, sync, export และ delete ต้องแยกสถานะให้เห็นชัดว่าข้อมูลใดอยู่ในเครื่อง รอส่ง ส่งแล้ว หรือส่งไม่สำเร็จ

## 13. Test matrix และหลักฐานตรวจรับ

| ชั้นทดสอบ | ชุดตรวจ | หลักฐานผ่าน |
| --- | --- | --- |
| โครงสร้าง Figma | section/frame/component/variant ตั้งชื่อตามสัญญา | inventory export และไม่มีชื่อซ้ำที่ทำให้ route audit กำกวม |
| Visual | hierarchy, spacing, typography, contrast, states | contact sheet ของ Auth, Core, Secondary, Adaptive และ System States ผ่าน review |
| Content | ภาษาไทย คำกริยา ผลของ action และข้อจำกัด | ตรวจ copy ทุก CTA/error/empty; ไม่มีศัพท์กำกวมที่ไม่ได้อธิบาย |
| Route | 13 starting flows, Back, Cancel, Retry, Confirm | route audit ไม่มี dead interactive, missing target, invalid self-loop หรือ unreachable primary frame |
| Feature coverage | f01–f44 | script/manifest ยืนยันครบ 44 รหัส ไม่มีซ้ำ ไม่มี f45 |
| Compact phone | 360×800, 393×876, 412×915dp | ไม่มี overflow; CTA เหนือ inset; nav label อ่านครบ; hierarchy คงเดิม |
| Compact height | 800×479 และ 800×480dp | boundary ใช้กฎถูกต้อง, single pane เมื่อ <480dp, keyboard ไม่ทับ action |
| Tablet | 600×960, 800×1280, 1024×1366, 1280×800dp | rail/list-detail ตามขั้นต่ำ, prose/form ไม่ยืดเต็มจอ, 1280 ใช้ประมาณ 42:58 |
| Fold/adaptive | resize ผ่าน 599/600 และ 839/840, cover/book/tabletop ด้วย harness ที่มี display features | state ไม่หาย ไม่ส่งซ้ำ ไม่มี control คร่อม exclusion; ถ้ายังไม่มี device evidence ให้ลง `not verified` |
| Accessibility | text 100/130/200%, Light/Dark, Reduced Motion, keyboard และ screen-reader order | screenshot/record + checklist; ไม่มีข้อความสำคัญถูกตัด |
| Auth prototype | email/register/confirm/forgot/verify/Google chooser/account link/error | flow กดครบ; ระบุชัดว่า Google เป็น mock และไม่ขอ Google password/OTP |
| Data/research | offline, sync queue, export, consent/withdraw, research disabled | state copy สอดคล้อง; ผู้ไม่เข้าร่วมยังเรียนได้; ไม่มีข้อมูลจริง |
| Runtime ภายหลัง | Flutter integration, Credential Manager, permissions, persistence, AI provider | automated/integration/emulator evidence แยกจาก Figma; ไม่ใช้ prototype แทนผล runtime |

LDPlayer ใช้ตรวจ window/DPI/orientation ตาม [`lexiquest-revision-5-ldplayer-matrix.md`](lexiquest-revision-5-ldplayer-matrix.md) ส่วน hinge/posture ต้องใช้ Android foldable emulator ที่รายงาน display features หรืออุปกรณ์จริง

## 14. สิ่งที่ต้องส่งมอบ

1. Figma Design หนึ่ง Page ตาม section ในข้อ 5 ภายใต้บัญชีเจ้าของงานที่ระบุ
2. component/variant ที่แก้ไขต่อได้ ไม่ flatten เป็นภาพเดียว
3. หน้าบัญชี A01–A12, หน้าหลัก/ย่อย P06–P59, overlays และ system-state specimens
4. adaptive frames ครบ test matrix ที่ออกแบบไว้ พร้อม fallback ของ fold/dual/triple pane
5. clickable prototype 13 flow พร้อม starting points และ route audit
6. ตาราง f01–f44 ที่ผูกกับ frame/state/system contract
7. contact sheets สำหรับ review ภาพรวม และหลักฐาน critique รอบสุดท้าย
8. manifest ระบุ revision, source catalog hash, frame count, reaction count, dead interactions และข้อจำกัดที่ยังไม่พิสูจน์

## 15. เกณฑ์ยอมรับงาน

งานออกแบบถือว่า **ผ่านการตรวจรับด้านดีไซน์** เมื่อครบทุกข้อ:

- ทุกหน้า เมนู ฟีเจอร์ และสถานะที่ระบุในเอกสารนี้มี frame หรือ system contract ที่ค้นหาได้
- Auth ครบ Google, email/password, สมัครพร้อมยืนยันรหัส, ลืมรหัส, email action และ onboarding
- จุดหมายหลัก 4 รายการและหน้าย่อยใช้ชื่อไทยที่คนทั่วไปเข้าใจ
- f01–f44 ครบและตรง Revision 1.3.0/hash ที่ระบุ ไม่มีรหัสเพิ่มเอง
- route audit ผ่าน และ flow สำคัญกดจากต้นจนจบได้โดยไม่มี dead end
- responsive/adaptive frames ผ่านการตรวจเชิงภาพใน test matrix และมีคำอธิบาย fallback
- accessibility, offline, permission, service failure และ limited/hidden states ถูกออกแบบอย่างชัดเจน
- research ยังคง optional/default-off และผู้ไม่เข้าร่วมเรียนต่อได้
- critique รอบสุดท้ายไม่มี finding ระดับ must-fix; finding ที่ยังไม่พิสูจน์ถูกบันทึกเป็น `not verified`
- owner, revision, source hash, test evidence และ known limitations ปรากฏใน Delivery Evidence

คำว่า “ผ่านการตรวจรับด้านดีไซน์” ไม่เท่ากับ `engineering-complete`, `release-ready` หรือ `production-ready` การรับรองเหล่านั้นต้องมี Flutter implementation, automated tests, emulator/runtime evidence, account/provider configuration, data-policy checks และสิทธิ release แยกต่างหาก

## 16. ข้อจำกัดและสถานะหลักฐาน

- Figma พิสูจน์โครงข้อมูล ภาพ การเดินหน้า และความเข้าใจของ copy แต่ไม่พิสูจน์ network, persistence, token verification, sync idempotency หรือ performance
- LDPlayer profile พิสูจน์ layout ตาม window ที่ตั้งได้ แต่ไม่พิสูจน์ hardware cutout, hinge, fold sensor หรือพฤติกรรม physical device
- หากยังไม่มี runtime evidence record ของ Vivo/Samsung/Huawei ให้ระบุ `not captured` หรือ `not verified` ห้ามอนุมานจากภาพการตลาด
- หน้าความสามารถที่ runtime flag เป็น hidden/limited ต้องใช้สถานะนั้นในงานออกแบบและห้ามเปลี่ยนเป็น enabled เพื่อให้ flow ดูครบ
- ผู้ช่วยเรียนด้วย AI ต้องมี local fallback เสมอ และต้นแบบห้ามอ้างว่าคำตอบ AI มีความถูกต้องหรือพร้อมใช้งานจริง
- การทดสอบผู้ใช้ ความพึงพอใจ ผลการเรียน และประสิทธิผลการวิจัยเป็นหลักฐานคนละประเภทกับการตรวจรับ UI

## 17. แบบบันทึกหลักฐานส่งมอบ

```text
revision: LexiQuest Revision 5
catalog: 8 domains / 44 capabilities
catalog_revision: 1.3.0
catalog_hash: 41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4
owner_account: petch954100@gmail.com
figma_file_key: <record at delivery>
frame_count: <measured>
interactive_node_count: <measured>
reaction_node_count: <measured>
dead_interactions: <must be []>
feature_ids_present: <must be f01..f44 exactly>
visual_review: pass|must-fix|not-verified
route_review: pass|must-fix|not-verified
responsive_review: pass|must-fix|not-verified
runtime_integration: not-run|partial|pass
physical_device_evidence: not-captured|partial|pass
research_state: synthetic / enrollment-off / upload-off
known_limitations: <list>
```

ผู้ตรวจรับต้องอ้างอิงหลักฐานจาก snapshot เดียวกัน ถ้ามีการแก้ frame, route หรือ component หลังตรวจ ให้ถือว่าหลักฐาน route/visual ที่เกี่ยวข้องหมดอายุและต้องตรวจซ้ำก่อนระบุว่าผ่าน
