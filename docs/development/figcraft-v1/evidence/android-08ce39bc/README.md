# Android evidence at 08ce39bc

ภาพจาก Android จริงบน emulator `emulator-5590` สำหรับ source `08ce39bcca697d903ec79ca15c52d9ac66b0d391`. Independent reviewer ควบคุมเฉพาะ emulator นี้. ไม่แตะ vivo และไม่แก้ production, Dart, Flutter หรือ Gradle.

## ภาพคู่ที่ส่งให้ผู้ใช้

| งาน | ภาพคู่ | ภาพและ hierarchy ดิบ |
| --- | --- | --- |
| Home มีคำถึงคิว | [home-comparison.png](home-comparison.png) | [home.png](home.png), [home.xml](home.xml) |
| คลังสองชุด | [library-comparison.png](library-comparison.png) | [library.png](library.png), [library.xml](library.xml) |

FigCraft มาจาก native export 390×844 ของ design `21b34eaa` ที่ `../design-home.webp` และ `../design-library.webp`. ภาพ Android ดิบเป็น 624×1350, density 256, เท่ากับ 390×843.75 dp. `tool/figcraft/compare_android.py` วางภาพคู่บน canvas 828×1020 และย่อ Android เป็น 390×844. ไม่มีการแต่งภาพดิบหรือสร้างภาพ Flutter ด้วย AI.

สถานะข้อมูลตรงกับ reference ทั้งสองภาพ คือ การเดินทาง 3 คำ, ของใช้ในครัว 0 คำ และ platform ถึงคิวหนึ่งคำ. Preview ในแอปเรียง platform/station/ticket ตามข้อมูลที่อ่านได้ จึงต่างลำดับจากแบบ. รูปประจำชุดและประโยคตัวอย่างใน FigCraft ไม่ใช่ข้อมูลที่ runtime มีใน fixture นี้.

## รุ่นและการติดตั้ง

- APK `build/figcraft-08ce39bc/lexiquest-08ce39bc-v28-x64-debug.apk`, 130,334,553 ไบต์, versionCode 28, versionName 1.0.0.
- SHA-256 ของ archive และ `/data/app/.../base.apk` ที่ติดตั้งจริงตรงกัน คือ `25b76cb6e177616c42c7855d103d612bdd009ad62bca7e69beef38a69c8c7528`.
- ติดตั้งด้วย `adb -s emulator-5590 install -r --no-streaming`. ได้ `Success`. ไม่มี uninstall หรือ clear data.
- อุปกรณ์รายงาน BVL-AN16, Android 9. เป็น LDPlayer 9.5.17.0 instance 18 ไม่ใช่โทรศัพท์จริง.
- ข้อมูลฉบับเครื่องและการคืนค่าอยู่ใน [metadata.json](metadata.json). Hash และขนาดของภาพ/XML/log ข้อมูลอยู่ใน [manifest.json](manifest.json).

## สิ่งที่กดตรวจจริง

| Action | ผลที่เห็น | หลักฐาน |
| --- | --- | --- |
| เปิด Home หลังอัปเดตและ reboot | เห็น platform, ถึงคิว 1 คำ, ชุดการเดินทาง และทางฝึกจากชุด. ไม่แสดง weakness ที่ไม่มีประวัติ | `home.png`, `home.xml` |
| Library → เพิ่มคำ | เปิดตัวเลือกชุดเดิมสองชุดและสร้างชุดใหม่ | `library-add-destination.png`, `.xml` |
| เลือกการเดินทาง | เปิดชุดการเดินทางพร้อมเมนูพิมพ์/ถ่ายภาพ/นำเข้า. กด Back ออกจากเมนูและชุดโดยไม่บันทึก | `library-add-menu.png`, `.xml`, `library-return-from-add.png`, `.xml` |
| ค้น platform ภายในชุด | เห็น platform พร้อมความหมายในชุดการเดินทาง | `set-filter.png`, `.xml` |
| ค้น platform จาก Library | เห็นผล platform พร้อมชื่อชุด. กดผลแล้วเข้าเฉพาะชุดการเดินทาง. Back แล้วยังมีคำค้น platform | `library-global-search.png`, `.xml`, `search-selected-set.png`, `.xml`, `library-search-return.png`, `.xml` |
| Home → ฝึกจากชุดคำ ที่ 200% ธีมมืด | สลับไป Library ได้จริง | `home-dark-200-scrolled.png`, `.xml`, `library-dark-200.png`, `.xml` |
| Font 200%, light/dark | อ่าน Home ด้านบนและเลื่อนถึงกิจกรรมทั้งหมดได้. Library ยังเห็นชื่อสองชุด/จำนวน/ตัวเลือกและเพิ่มคำ | `home-light-200.png`, `home-light-200-scrolled.png`, `library-light-200.png`, `home-dark-200.png`, `home-dark-200-scrolled.png`, `library-dark-200.png` พร้อม XML คู่กัน |

ไม่มีการเปิด quiz, ส่งคำตอบ, Save, import, ลบ, เปลี่ยนบัญชี หรือเลือกเข้าวิจัยในรอบนี้. Research dialog ไม่ปรากฏบนเส้นทาง guest ที่มีอยู่แล้ว. ไม่อ้างว่าได้ปฏิเสธ dialog ใหม่ในรอบนี้.

อ่าน Native SQLite แบบ SELECT ก่อนและหลังการตรวจ. ไม่ได้ rerun seed. [state-verification.txt](state-verification.txt) ยืนยัน categories 2, words 3, due-at-1 1, research consents 0, learning sessions 0, answer attempts 0 และ outbox 0. คำทั้งสามยังมี source `synthetic:figcraft-reference`.

## ขอบเขตภาพ 200%

ผู้วิจารณ์เปิดดู PNG จริงทั้งหมดที่ใช้สรุปการอ่าน. ไม่พบสระ/วรรณยุกต์ไทยหรือเนื้อหาแอปถูกตัดในสถานะที่ตรวจ. ชื่อ Library ขึ้นสองบรรทัด และ Home ต้องเลื่อนเพื่ออ่านกิจกรรมด้านล่าง. นาฬิกา status bar ของ Android 9 emulator ถูกตัดที่ 200% ตามภาพ จึงไม่อ้างว่า system status bar ผ่าน.

ไม่ได้เปิด TalkBack. XML แสดง labels และ bounds ได้ แต่ไม่พิสูจน์เสียงพูด ลำดับ focus หรือความเข้าใจของผู้ใช้. ไม่ได้ตรวจ native empty/new/error states, ocean theme, long user text, camera accuracy หรือ full learning journey จาก emulator รอบนี้. หลักฐาน vivo รุ่นเดียวกันอยู่คนละงานและไม่ใช่ผลตรวจของเอกสารนี้.

## Recovery และคืนอุปกรณ์

หลัง install สำเร็จ ตรวจ hash/version/fixture ได้ แต่ Activity Manager ค้าง. `dumpsys -t 3 activity activities` timeout และ `ps` พบ `system_server` เป็น zombie. จึงใช้ `adb reboot` แล้ว LDPlayer `reboot --index 18` โดยเก็บ data disk เดิม. Host instance restart ทำงานและ Android กลับมา `boot_completed=1`. ตรวจ versionCode 28 อีกครั้งก่อนเปิดแอป. ไม่รีติดตั้งซ้ำและไม่แตะ instance อื่น.

หยุดเฉพาะ host clients ของคำสั่งเปิด/ปิดแอปที่ค้าง. ไม่หยุด transaction ฐานข้อมูล. Capture แรกหลังเปิดแอปใหม่ไม่มี XML พร้อมใช้งาน จึงตรวจ foreground/idle แล้ว capture ใหม่. SELECT verifier ครั้งแรกเจอ SQLite banner/prompt จึงปรับการอ่าน output และตรวจค่าเดิมซ้ำ. เหตุเหล่านี้ไม่ใช่ผลทดสอบผลิตภัณฑ์ผ่านหรือไม่ผ่าน.

คืน physical 1280×720, density 240 โดยไม่มี wm overrides, ลบ font override จน `font_scale=null`, night mode no, accessibility services null และ accessibility enabled 0. อ่านยืนยันใน `metadata.json`. [restored-physical.png](restored-physical.png) และ XML แสดงแอปในกรอบ landscape เดิม. การคืน wm ทำให้ระบบเขียน font default 1.0 กลับมาชั่วครู่ จึงลบ override อีกครั้งหลังเปลี่ยน wm เสร็จ.

คืน exclusive emulator ownership ให้ root แล้วก่อนเขียน critique. ไม่มีการใช้ ADB ต่อหลังบันทึก final metadata. ถ้าต้องการ fixture 390×844 ต่อ root ต้องตั้ง overrides ใหม่. การตรวจครั้งนี้ไม่เปลี่ยนสถานะ S5/S6 หรือ denominator 48/44/64.

Independent native design disposition อยู่ใน [critique.md](critique.md).
