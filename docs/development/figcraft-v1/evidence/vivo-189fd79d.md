# Vivo v32 ทดสอบ migration และเส้นทางกล้องถึงผลฝึก

Android 13, vivo V2041, 1080×2408 ที่ 440 dpi. ใช้ APK release ARM64 จาก
`189fd79d89d38711b9b7bbcf708b0a4c3b1c7bf9` versionCode 32 ขนาด 65,987,809 ไบต์.
APK SHA-256 `e8e04089e4e2bc821be18bec2714065fe0ff29f66dfc6a01314d6e53d6fa2154`
ตรงกับ base.apk ที่ดึงจากอุปกรณ์. SHA-256 ของใบรับรอง
`e1b00e17896bfb73fe0dc42429768b966465213d49a8a5165de06688cc8fdc1f`
ตรงกับ v31. ตรวจ build ID และข้อความ migration ของ v26 ใน arm64 Dart AOT.
Cloud sync ปิดด้วย build flag และใช้ Research authorizer แบบ deny-all.

ติดตั้งด้วย `adb install -r --no-streaming` และ firstInstallTime เดิม.
ไม่ถอนแอป ล้างข้อมูล หรืออ่านฐาน release. APK และหลักฐานดิบที่ใช้ตรวจอยู่ใน
`build/figcraft-189fd79d/`. เก็บภาพกล้องดิบในเครื่องเท่านั้น.

| เส้นทางที่กดจริง | ผลและหลักฐาน |
| --- | --- |
| เปิดหลังอัปเดตจาก v31 → คลัง → A → ผลเดิม → Android Back | A มี mug, station, ticket และผลเดิม 67% ถูก 2/3. กดย้อนสู่ A. B ยังว่างและไม่มีผล. ภาพและ XML 01–07 |
| ปิด Wi-Fi ขณะที่ mobile data ปิด → ปิดเฉพาะโปรเซส LexiQuest → เปิดใหม่ | A แสดงผลและสามคำเดิม. XML 03 และ 09 ตรงกัน `053f7d3b546037ff0fadfd55d94edf9eaae36f032c2f19a662b6de7adea3abdf` |
| เริ่มรอบสามคำจาก A → ตอบผิด → ไปข้อ 2 → พัก → ปิดและเปิดแอป → ฝึกต่อ | กลับมาที่ข้อ 2 จาก 3. จบรอบได้ 33% ถูก 1/3. ย้อนกลับ A. หลักฐาน 10–19 |
| A → เพิ่มคำ → ถ่ายภาพ → ขอสิทธิ์เฉพาะครั้งนี้ → ถ่ายจริง → กรอกเอง | กล้องแสดงข้อความระบุวัตถุไม่ได้. กรอกคำสังเคราะห์ `notebook` / `book for writing` / `noun` และกดบันทึก. A มีคำเพิ่มหนึ่งคำ. หลักฐาน 20–26 |
| A → ฝึก 4 คำรวม notebook → ดูผล → กลับชุด | notebook, ticket, mug ถูก. station ผิด. ผล 75% ถูก 3/4. กลับ A และยังมี notebook. หลักฐาน 27–30 |
| เปิดแอปใหม่ออฟไลน์ → คลัง → A → ผลเดิม → กลับ | A4/B0. notebook กับผล 75% ยังอยู่. UI แสดงตัวเลือกที่ตอบทั้ง 4 ข้อจากรอบที่บันทึกไว้. หลักฐาน 31–33 |
| 200% → A/ผลรอบล่าสุดในธีมมืด → เลื่อน → แตะกลับชุด → ธีมสว่าง → Android Back | แตะปุ่มกลับชุด 548×132 px ได้หลังเลื่อน ได้ปลายทาง A และย้อนคลังได้. หลักฐาน 34–40 |

ผู้ตรวจอิสระเปิด PNG/XML จากเส้นทางจริงและภาพคู่เดิมของ FigCraft.
ข้อความไทยและวรรณยุกต์ที่ตรวจอ่านได้ในธีมมืดและสว่าง. ชื่อ A ขึ้นหลายบรรทัด
ที่ 200% และข้อมูลใต้ viewport ต้องเลื่อน. ปุ่มกลับที่เห็นเต็มสูง 48 dp.
แถบจัดการ notebook ถูกขอบตัดในบางภาพจึงไม่ใช้เป็นหลักฐานพื้นที่แตะเต็ม.
ภาพอ้างอิง Home/Library เป็นข้อมูลและขนาดข้อความต่างจาก vivo v32.
ข้อความและปุ่มหลักที่วัดมี contrast 5.54:1–14.66:1. ขอบช่องค้นหาและ
ปุ่มเพิ่มคำในธีมสว่างอยู่ราว 1.3:1. พบแถวผลเดิมระบุคำที่เลือกโดยไม่มีสถานะ
ถูกหรือผิดใน XML. ข้อบกพร่องนี้แก้ที่ Score หลังทดสอบ v32 และเทสต์ Flutter
ยืนยัน semantics แล้ว. ดู [ภาพคู่และ Impeccable critique](android-08ce39bc/README.md).

ผลของกล้องเป็น **manual fallback ผ่าน** และ known-object recognition
`not_checked`. ไม่มี ground truth ของวัตถุในภาพ. ยังต้องฟัง TalkBack
และตรวจลำดับโฟกัสจริง. UI ไม่เปิดเผย UUID ของรอบ. การตรวจ ID และ owner
คนละบัญชีอยู่ใน Flutter/SQLite สังเคราะห์. รอบนี้ไม่ได้ทดสอบบัญชีจริง
หรืออัปโหลด Research.

คืนค่าหลังทดสอบแล้ว font 1.0, night mode yes, Wi-Fi 1, mobile data 0,
accessibility disabled. แอปอยู่ชุด A กับผล 75%. XML 32 และ 41 ตรงกัน
`64671d063d5b1064fe83cfb9544549e4c871fcd8f652e1b5fc1b03f20dd61a76`.

[CI ของซอร์สเดียวกัน](ci-189fd79d.txt) · [ผลทดสอบสคีมาในเครื่อง](s7-v26-bridge.txt)

หลักฐานที่มีเฉพาะข้อมูลสังเคราะห์จากหน้าที่เปิดตรวจ

- [ผลเดิม 67%](vivo-189fd79d/04-original-score-retained.png) · [จุดกลับมาฝึกข้อ 2](vivo-189fd79d/13-resume-after-process-restart.png)
- [คำที่ยืนยันแล้วอยู่ใน A](vivo-189fd79d/26-camera-word-committed-a.png) · [ผลใหม่ 75%](vivo-189fd79d/29-camera-practice-score.png)
- [A4/B0 หลังเปิดออฟไลน์](vivo-189fd79d/31-offline-library-after-new-round.png) · [ผลเดิมหลังเปิดออฟไลน์](vivo-189fd79d/33-offline-new-score.png)
- [ปุ่มกลับหลังเลื่อน 200%](vivo-189fd79d/37b-dark-200-score-end-1.png) · [คลังธีมสว่าง 200%](vivo-189fd79d/40-light-200-library.png) · [SHA-256 ของ PNG/XML](vivo-189fd79d/SHA256SUMS.txt)
- [สถานะถูก/ผิดใน XML ของ v33](vivo-189fd79d/v33-score-correctness.xml) · [หน้าหลังปฏิเสธกล้องหนึ่งครั้งบน v34](vivo-189fd79d/v34-camera-denied.png)
- [ตรวจคำสังเคราะห์ก่อนบันทึกบน v34](vivo-189fd79d/v34-26-delivery-reviewed-word.png) · [ผล 80% หลังเปิดออฟไลน์](vivo-189fd79d/v34-35-delivery-offline-score.png) · [A5 และ B0](vivo-189fd79d/v34-33-delivery-offline-library.png)
