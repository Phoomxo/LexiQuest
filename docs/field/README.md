# LexiQuest field release runbook

Gate นี้ผูก source, signed APK/AAB, เอกสาร และหลักฐานจริงเป็น release candidate
เดียวกัน ห้ามคัดลอกผลจาก artifact รุ่นอื่นหรือเปลี่ยน `pending` เป็น `pass`
โดยไม่ได้ทดสอบจริง

## 1. สร้าง versioned release package

สร้าง release key ครั้งเดียวด้วย `tool/cli/initialize-release-signing.ps1` และสำรอง
`%USERPROFILE%\.lexiquest\signing` แบบออฟไลน์ จากนั้นใช้ path รุ่นที่ชัดเจน:

```powershell
$version = '1.0.0+27'
$releasePackage = "build/field-release/lexiquest-$version"
$releaseManifest = "$releasePackage/release-manifest.json"
$evidenceRoot = "field/evidence/lexiquest-$version"

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/package-field-release.ps1 `
  -Version $version -ReleaseProfile fieldTrial
```

Packager ปฏิเสธ source ที่ยังไม่ checkpoint, staging ที่มีไฟล์เก่า, certificate
ที่ไม่ตรง trust record, model pin ที่ไม่ตรง source, APK/AAB provenance ที่ไม่ตรง
และ AAB ที่มี payload entry ไม่ถูก signed โดยอ่าน application ID/version จาก
AAB manifest จริงผ่าน bundletool ใน Gradle cache + Android SDK เอกสารผู้เข้าร่วม
ถูก allowlist และ hash ทีละไฟล์ใน manifest

## 2. เก็บ device evidence จริง

เชื่อมต่ออุปกรณ์จริงครั้งละหนึ่งเครื่อง แล้วรัน low/mid/high ให้ครอบคลุม phone,
tablet และ foldable:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/collect-android-field-evidence.ps1 `
  -Tier low -FormFactor phone -NetworkProfile offline-mixed `
  -ReleaseManifestPath $releaseManifest `
  -EvidenceRootPath $evidenceRoot
```

Collector ตรวจ hash, package/version/build/model pin และ upload certificate ก่อนติดตั้ง
แล้ววัด installed base APK, signer และ installer ซ้ำหลังติดตั้ง สำหรับ
`publicProduction` จะไม่ sideload และต้องพบ installer `com.android.vending` จริง
ค่า `-Tier`/`-FormFactor` เป็น expected assertions เท่านั้น: collector คำนวณ tier
จาก RAM/API (`low` ≤4 GB + API 30–32, `high` ≥8 GB + API 34+, อื่น ๆ เป็น
`mid`) และคำนวณ phone/tablet จาก physical smallest-width; Fold ต้องมี hinge
sensor หรือ fold/window feature จริง ห้ามอนุมาน Fold จากขนาดจอ และ emulator
หรือ label ที่ไม่ตรง measurement จะถูกปฏิเสธ
ไฟล์ draft ลงท้าย `.device.json`; journey, orientation, text scale, TalkBack,
Fold postures, UAT, benchmark และ endurance ยังคง `pending` จนมีผลจริง

ทุก `*EvidenceRef` ต้องเป็น object ต่อไปนี้ และ path ต้องอยู่ใต้ `$evidenceRoot`:

```json
{"path":"records/example.json","sha256":"<64_HEX>"}
```

## 3. รวมหลักฐานที่ตรวจสอบย้อนกลับได้

สร้าง JSON สอง record จากผลจริง ไม่ใช้ command-line switch เพื่ออ้างว่าอนุมัติแล้ว:

- `release-controls.json`: `recordType=lexiquestReleaseControls`, profile และ artifact
  เดียวกับ manifest พร้อม cloud/profile controls และ hashed evidence refs
- `owner-approval.json`: `recordType=lexiquestOwnerApproval`, exact APK/AAB hashes,
  เวลา บทบาท และ hashed approval evidence ref

ฟิลด์เอกสารใน `participantPackage` ต้องเป็น `{path, sha256}` ที่ชี้ไปยัง
`docs/...` ตาม allowlist แบบ exact เท่านั้น ไม่รับชื่อไฟล์อื่น absolute path หรือ
hash ที่ไม่ตรงเนื้อหา

สำหรับ public profile, control record ต้องผูก exact AAB hash/version/package,
Play app-signing certificate และหลักฐาน Play acceptance/privacy/account deletion/
Data Safety/rollback สำหรับ field trial ต้องมี ethics/protocol/เครื่องมือวิจัย/
trusted issuer/trusted time/rollout record จริง โดยแต่ละรายการต้องมี hashed
`*EvidenceRef` ที่อยู่ใต้ `$evidenceRoot` ระบบจะ fail closed หาก record, path หรือ
hash ใดหาไม่พบ

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/new-field-release-evidence.ps1 `
  -ReleaseManifestPath $releaseManifest `
  -EvidenceRootPath $evidenceRoot `
  -ControlRecordPath 'records/release-controls.json' `
  -OwnerApprovalRecordPath 'records/owner-approval.json'
```

## 4. Final gate

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/verify-field-release.ps1 `
  -ParticipantPackagePath $releasePackage `
  -EvidenceRootPath $evidenceRoot
```

Firebase SHA และ hosted Asset Links ต้องรับ manifest รุ่นเดียวกันแบบ explicit:

```powershell
node tool/cli/configure-firebase-release-sha.cjs $releaseManifest
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/verify-hosted-asset-links.ps1 `
  -ReleaseManifestPath $releaseManifest
```

Final gate ไม่ได้สร้าง ethics approval, Play acceptance, TalkBack/UAT หรือผลอุปกรณ์
ที่ขาดอยู่ หาก APK/AAB หรือ record เปลี่ยน hash ต้องเก็บหลักฐานและอนุมัติใหม่
