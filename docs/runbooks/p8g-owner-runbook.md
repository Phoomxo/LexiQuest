# P8-G Owner Runbook — Release และ Closed Rollout

สถานะ: รอ immutable RC ที่ผ่าน P8-E/P8-F และ owner approval

## เงื่อนไขก่อน rollout

- ใช้ signing certificate เดิมเท่านั้น ห้าม rotate อัตโนมัติ
- `upgradeInstall` ผ่านจาก APK รุ่นก่อนโดยไม่ถอนแอป
- อุปกรณ์จริง low/mid/high ผ่าน 14/14 ด้วย APK SHA-256 เดียวกัน
- real-key smoke ของ Gemini, OpenAI, OpenRouter, Claude และ MaxPlus ผ่าน
- App Check, Cloud controls, private references และ owner smoke ครบ
- `verify-field-release.ps1` ผ่าน

สร้าง release package ด้วย:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/package-field-release.ps1
```

ไฟล์ `build/field-release/release-manifest.json` ต้องตรงกับ
`field/evidence/release-evidence.json` ทั้ง APK hash, signing certificate,
package, version, build ID และ model hash

## Owner smoke

ตรวจบน clean install และ upgrade install: consent/guest, learning core,
account conversion, TTS/STT/cancellation, AI provider BYOK, export, migration,
background/resume และ Cloud kill switch บันทึกผลแบบ private reference โดยไม่
เก็บ secret หรือเนื้อหาสนทนา

## Closed rollout

ใช้ RC เดิมตามลำดับ `3% → 10% → 30% → 100%` แต่ละ stage ต้องบันทึก:

- version, commit SHA, dependency-lock SHA-256 และ APK SHA-256
- เวลาเริ่ม/จบ, metrics, จำนวนผู้ใช้ และผู้อนุมัติ
- crash/ANR, authentication, migration, provider error และ data-loss signal

หยุด rollout ทันทีเมื่อ crash/ANR เพิ่มผิดปกติ, authentication/migration ล้มเหลว,
provider error สูงผิดปกติ, secret leak หรือข้อมูลสูญหาย การแก้ source ทำให้ RC
เดิมสิ้นสุด ต้องสร้าง APK ใหม่และ re-gate ห้ามรวม evidence คนละ hash

Rollback ต้องใช้ artifact ที่ certificate เดียวกันและ database-compatible
ห้าม downgrade schema แบบทำลายข้อมูล

## Gate ledger

บันทึกผล gate หลังคำสั่งจบจริงเท่านั้น:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/record-gate-result.ps1 -Gate integration -Command "flutter test" -Result pass

powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/record-gate-result.ps1 -Gate release -Command "verify-field-release.ps1" -Result pass -ApkSha256 "<SHA-256>"
```

ledger ปฏิเสธการบันทึก tuple เดิมซ้ำเมื่อ commit, dependency locks, APK และคำสั่ง
ไม่เปลี่ยน หาก failure เดิมเกิดสามรอบ ให้หยุดแก้เฉพาะหน้าและทบทวน architecture

Direct client-side BYOK จำกัดเฉพาะ controlled/closed rollout รุ่นนี้ การเปิด
public production ต้องมี backend proxy และ key-isolation architecture ก่อน
