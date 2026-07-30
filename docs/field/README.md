# LexiQuest field release runbook

กระบวนการนี้เป็น gate เดียวต่อ release candidate ไม่ใช่วงจรทดสอบไม่สิ้นสุด
เมื่อขั้นใดไม่ผ่าน ให้แก้เฉพาะสาเหตุที่ gate รายงาน แล้วเริ่ม release candidate
ใหม่หาก APK เปลี่ยน hash เท่านั้น ห้ามคัดลอกผลจาก APK รุ่นอื่น

## 1. เตรียมลายเซ็นและสร้างชุดติดตั้ง

สร้าง release key หนึ่งครั้งด้วยคำสั่งด้านล่าง ระบบจะสุ่มรหัสผ่านด้วย
cryptographic RNG เก็บ keystore แยกจาก repository และป้องกัน recovery secret
ด้วย Windows DPAPI:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/initialize-release-signing.ps1
```

สำรองโฟลเดอร์ `%USERPROFILE%\.lexiquest\signing` แบบออฟไลน์ก่อนแจก APK
จากนั้นรัน:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/package-field-release.ps1 -Version 1.0.0+1
```

คำสั่งจะไม่สร้าง key ปลอม ไม่ใช้ debug signing และจะหยุดหาก source Android
ที่เกี่ยวข้องยังไม่ commit ผลลัพธ์อยู่ใน `build/field-release/` พร้อม hash
และ certificate digest

## 2. เก็บหลักฐานมือถือจริง

เชื่อมต่อมือถือจริงครั้งละหนึ่งเครื่อง เปิด USB debugging แล้วรันให้ครบ
low, mid และ high tier:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/collect-android-field-evidence.ps1 `
  -Tier low -NetworkProfile offline-mixed
```

ตัว collector จะปฏิเสธ emulator, hash serial ก่อนบันทึก, ติดตั้งและเปิด APK
จริง และสร้างรายการอื่นเป็น `pending` โดยตั้งใจ ผู้ทดสอบต้องทำ journey
ตาม `docs/superpowers/specs/2026-07-31-p8-hybrid-voice-field-release-design.md`
พร้อม evidence reference แล้วกรอกผลจริง ห้ามเปลี่ยน `pending` เป็น `pass`
โดยไม่ได้ทำการทดสอบ

## 3. รวม evidence

หลังตั้ง App Check, budget alert 50/80/100 (หรือยืนยันว่า Cloud Billing
ไม่ได้เปิด), asset links, kill switch,
ช่องทาง feedback/support และ owner smoke test จริงแล้ว ใช้:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/new-field-release-evidence.ps1 `
  -FeedbackChannelRef 'private:configured-feedback-record' `
  -SupportChannelRef 'private:configured-support-record' `
  -ResearchProtocolRef 'private:approved-research-protocol' `
  -AppCheckConfigured -AppCheckValidTrafficObserved -AppCheckEnforced `
  -NoBillingAccount -AssetLinksVerified `
  -CloudKillSwitchVerified -OwnerApproved `
  -AppCheckEvidenceRef 'private:app-check-record' `
  -BudgetAlertsEvidenceRef 'private:budget-record' `
  -AssetLinksEvidenceRef 'private:app-link-record' `
  -CloudKillSwitchEvidenceRef 'private:kill-switch-record' `
  -OwnerApprovalEvidenceRef 'private:owner-smoke-record'
```

ไฟล์ evidence อยู่ในโฟลเดอร์ที่ git ignore เพื่อไม่เผยข้อมูลการปฏิบัติการ
หรือผู้เข้าร่วม

## 4. Final gate

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/verify-field-release.ps1
```

Final gate ตรวจลายเซ็นและ hash, ความตรงกันของ manifest, เอกสารผู้เข้าร่วม,
หลักฐานสามเครื่อง, journey ทุกข้อ, benchmark CPU/XNNPACK, สถานะ GPU
ที่ไม่กล่าวอ้างเกินจริง, endurance 30 นาที, Cloud controls และ owner approval
จากนั้นรัน software regression gate หนึ่งครั้ง ถ้า APK เปลี่ยนแม้หนึ่ง byte
หลักฐานอุปกรณ์และ owner approval เดิมใช้ต่อไม่ได้
