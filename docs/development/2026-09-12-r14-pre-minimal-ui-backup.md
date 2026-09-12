# LexiQuest backup — 2026-09-12 R14 ก่อนปรับ UI minimal

Backup ID: `backup-2026-09-12-r14-pre-minimal-ui`

Branch: `codex/backup-2026-09-12-r14-pre-minimal-ui`

สำรองตามคำสั่งผู้ใช้ วันที่ 12 กันยายน 2026 (พ.ศ. 2569) แยกจาก main และสาขาเก่าทั้งหมด ไม่ใช่รุ่นปี 2024 และไม่ใช่ production release

## สิ่งที่สำรอง

ซอร์สล่าสุดทั้งหมดที่ Git ติดตามและไฟล์ใหม่ที่ไม่ได้ถูก ignore ก่อนเริ่มเปลี่ยน UI minimal รวมเนื้อหา CEFR เอกสารและ tests ที่พัฒนาต่อจาก `788e90e62b1694c20945734787723c168b6a6ab2` ตลอดจนไฟล์ผลทดสอบภาพที่อยู่ในชุดงานเดิม ไม่ลบหรือปรับย้อนหลังเพื่อให้ snapshot ดูสะอาด

ค่ารุ่นใน pubspec: `1.0.0+14` ชื่อ R14 เป็นรอบส่งตรวจภายใน ไม่ใช่ versionCode ของ APK ทุกชนิด: รุ่น manual QA บน vivo ใช้ versionCode 23 ตาม checkpoint ส่วน APK debug ปกติใช้ versionCode 28

จุดนี้มีธีมและ UI ที่แก้มาก่อนวันที่สำรองอยู่แล้ว คำว่า “ก่อนปรับ UI” หมายถึงก่อนงาน minimal ที่ผู้ใช้สั่งในรอบนี้ ภาพร่างใหม่ที่อ้างในเอกสารยังไม่ถูกนำไปใช้ในซอร์ส

## หลักฐานเดิม

- รายละเอียดผลทดสอบ: `2026-09-12-system-followup-r14-checkpoint.md` (826 selected tests ตามรายงานเดิม ไม่ใช่ผลรันทดสอบใหม่ในขั้น backup)
- SHA-256 manual QA APK: `dc033748259db882aaf8a194ddbc7a1b4756e34b3cb23801dbe8d954cdabcd6e`
- SHA-256 ordinary debug APK: `8248c928c1ee4ea579b0ac5b37ff1fa1de899ebbb91b64663db87da705ff278b`
- ขั้น backup ตรวจ Gitleaks staged ประมาณ 14.82 MB และประวัติ origin/main..HEAD 368 commits ประมาณ 24.24 MB ไม่พบข้อมูลลับตามกฎที่ใช้ ตรวจชื่อไฟล์ไม่พบ private key, keystore หรือฐานข้อมูลจริงใน tracked tree; มีเพียง .env.example

## ขอบเขต backup

GitHub สำรองซอร์สที่อยู่ใน snapshot นี้ ไม่รวม ignored build outputs, APK, ฐานข้อมูลจากเครื่องจริง, credentials, dependency caches หรือภาพอ้างอิง ALLTCAS ใน Downloads ไฟล์เหล่านั้นยังอยู่ในเครื่องเดิม ดังนั้น GitHub snapshot ไม่ใช่การสำรองข้อมูลทั้งเครื่อง vivo หรือทั้งดิสก์

## เปรียบเทียบรุ่น minimal

ให้เริ่มสาขา `codex/minimal-ui-2026-09-12` จาก backup นี้ คง domain behavior, routes, feature gates และเนื้อหาเดิม แล้วตรวจหน้าหลักที่ขนาด/ข้อมูลเดียวกัน ใช้การจัดกลุ่ม ระยะห่าง สี และชื่อเมนูเป็นตัวแปรเปรียบเทียบ แยกผลตรวจภาพออกจาก usability test ของผู้ใช้จริง

ไม่มีการ merge เข้า main เปลี่ยนรุ่นเก่า ลงทะเบียนผู้เข้าร่วม หรือเผยแพร่บริการ production จากคำสั่ง backup นี้
