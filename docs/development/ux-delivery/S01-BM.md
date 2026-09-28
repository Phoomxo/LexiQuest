# S01-BM — isolated native baseline harness

Worktree: `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest`  
Branch: `codex/ux-current-after-s01-bc`; HEAD `4e70a26b0bf3c44c269bbcbaf9d6d37a273b4dd1`  
Writer: `01a0e035-ea22-7621-a9f0-8c6f0b4578d1`; controller: `01a0ce9e-23a6-7931-88e6-6390da748f39`

## ขอบเขต

ทำตาม [BL task card](S01-BL-next-harness.md): debug package ใหม่ `com.lexiquest.app.nativeBaselineBm`, canonical navigation/SQLite/preferences/offline manager และ synthetic run identity. ไม่เปลี่ยน production bootstrap, routes, scoring, SRS, rewards, schema หรือ rollout gates. การ compose harness มีเฉพาะ local dependencies; ไม่ใช่การรับรอง production bootstrap ทั้งระบบ

- `nativeBaselineTest=true` เลือก manifest/activity เฉพาะ debug; ห้ามใช้พร้อม `ariLocalTest` หรือ build release/profile
- ถอน INTERNET และสิทธิ์ camera/audio/notifications/boot; ถอด providers/receivers/services และ deep links จาก manifest ทดสอบ ต้องตรวจ merged APK ซ้ำก่อน install
- Activity ลงทะเบียนเฉพาะ SharedPreferences และ integration-test plugin ไม่เรียก generated registration ของ Firebase/auth/Workmanager/media
- Dart transport guard ปฏิเสธ HttpClient พร้อมนับความพยายาม; ไม่มี account/provider/sync/research gateway ใน composition
- package collision, APK ID/hash, source closure และ physical V2041/API33 ต้องผ่านก่อน install ปกติครั้งเดียว ไม่มี `-r`, clear, uninstall หรือ restore
- restart: N01–03 → snapshot/flush/close/seal → PID → force-stop เฉพาะ package ใหม่ → PID ว่าง → APK hash เดิม → verify-only N04 → PID หลังเปิด
- receipt มีแต่ synthetic IDs, counts, viewport และ case status; ไม่ใช้ logcat, VM endpoint, screenshot หรือ adb UI input

## Host evidence

- Fixture 5 tests: verify-without-seed/path traversal/sandbox rejection, transport guard และ canonical persistence โดยไม่ seed ซ้ำ
- Navigation 3 tests: N01 สี่แท็บ; N02 Settings/offline/กลับ/เปิดซ้ำ; N03 เปลี่ยน theme ผ่าน Settings และสร้างคำด้วย canonical use case
- Runner core 18 cases; executable runner 5 stub cases รวม receipt ที่มาช้าและ process restart; source isolation contract 1 ชุด
- Dart analysis เฉพาะ 5 ไฟล์: no issues
- `verify-scope` Flutter และ CLI gates ผ่านบน snapshot คงที่ก่อน native execute; fingerprints/command logs อยู่ใน validation

Canonical vocabulary สร้าง ordinary outbox 2 แถว (`category`, `word`) และ owner initialization สร้าง `StreakPolicyCutover` 1 event ตามเดิม. Harness ตรวจชนิด/จำนวน/attempt=0 และเก็บไว้ใน persistence digest; ไม่ลบเพื่อทำผลให้ผ่าน. Field `outboxRows` ใน receipt หมายถึง outbox ที่อยู่นอก ordinary local allowlist รวมแถวที่ถูกพยายามส่ง ซึ่งต้องเป็น 0. Research/consent/assignment/measurement/learning-answer/SRS/reward-transaction rows ต้องเป็น 0 เช่นกัน

## Native evidence

**N01–04 PASS** บน physical V2041 / Android 13 API33 / serial `9582188822004C6`, viewport จริง 1080×2292, pixel ratio 2.75. Seed ใช้เวลา 48.73 วินาทีหลัง launch; verify receipt พร้อมหลัง relaunch

| Case | ผลที่ตรวจจริง |
| --- | --- |
| N01 | local guest เปิดครบสี่แท็บและกลับ Today |
| N02 | Settings → local offline catalog → กลับ → เปิดใหม่ ไม่มี route ซ้อน |
| N03 | theme dark ผ่าน Settings; canonical owner/word/preference/cache snapshot; external/research=0 |
| N04 | PID `31935` → force-stop → PID ว่าง → relaunch PID `634`; verify-only digest ตรงกัน |

APK SHA256: `e10429750a946171a34ca367639d4e1a26394ffe3152e9f3a73ceaca76f53ee2`. Fixture digest ก่อน–หลัง: `c0048dd14dbff7c717532c1177b19d8498dec059266fbf11c82a9ce17e11aceb`. Install 1 ครั้ง, launch seed/verify อย่างละ 1 ครั้ง, ไม่มี reinstall/reseed/clear/uninstall. Metadata ของ production v23 และ ariTest v14 ตรงกันก่อน–หลัง; ไม่มี write command target ไปสองแพ็กเกจเดิม

Merged APK มี activity ทดสอบ 1 ตัว, provider/service/receiver=0 และไม่มี INTERNET/deep link. Manifest merger ยังเติม READ_EXTERNAL_STORAGE โดย implication จาก camerax; ตรวจ package metadata จริงแล้ว `granted=false`. Harness ไม่ลงทะเบียน camera/storage/media plugins ไม่ร้องขอสิทธิ์และไม่อ่าน external storage

เก็บ package/synthetic sandbox ไว้ตามคำสั่ง; process verify PID634 อาจยังอยู่แต่ DB/manager ปิดแล้ว. [Native receipts](evidence/S01-BM-runs/native-1/result.json) และ [validation](evidence/S01-BM-validation.json) แยกจาก user/trial/release acceptance

คำสั่ง build ที่พิสูจน์แล้วใช้ `--android-project-arg=nativeBaselineTest=true`; อย่าอาศัย environment flag เพียงอย่างเดียว. Runner ปฏิเสธการติดตั้งซ้ำเมื่อ package มีอยู่แล้ว การรันครั้งนี้จึงไม่ควรถูกรันใหม่แบบ blind retry

## Recovery และข้อจำกัด

- แก้ path separator ของ host Windows และการอ่านชื่อ cache ที่ canonical manager เก็บเป็น basename
- ไม่ใช้ count ทุก outbox/event แทน research count; ตรวจ ordinary canonical rows ตามรายการข้างต้น
- เติม canonical learning dependency เพื่อให้สี่แท็บผ่าน composition gate โดยไม่เริ่ม learning session
- ใช้ BackButton ของ UI ภาษาไทยและ bounded pumping ระหว่างรอ SQLite ที่เริ่มจาก widget callbacks
- เปลี่ยน SHA256 helper เป็น .NET เมื่อ nested PowerShell หา Get-FileHash ไม่พบ
- executable stub ใช้ PowerShell หลัง batch stub คืน exit code ของ delayed receipt ผิด
- CLI gate เคยได้ InputDrift เพราะ evidence เปลี่ยนระหว่างตรวจ; ไม่ใช้ผลนั้นอ้าง gate PASS
- APK แรกที่ build ด้วย environment flag ยังเป็น production ID จึงถูกปฏิเสธก่อน install; build ใหม่ด้วย explicit project arg
- แก้ debug-only guard ที่จับ mergeDebugArtProfile ผิด; ทดสอบ debug task graph ก่อน build ใหม่
- เปลี่ยน activity removeAll เป็น explicit removals หลัง merged manifest แสดงว่า harness activity ถูกลบด้วย; ตรวจ actual APK ซ้ำก่อน install
- Full dirty diff มี trailing whitespace จากไฟล์เดิม BD–BK; ไม่แก้งานเดิมเพื่อล้าง warning

UX-D01–25 ยัง OPEN; S01 ยังไม่ accepted. Visual/keyboard/TalkBack, user review, reviewed media/qualified trial และ frozen-source release gates แยกจาก harness นี้และยัง pending. ไม่มี deployment, research activation, participant enrollment, provider call หรือ external contact. Jev ไม่มี fresh billing: current-model deterministic fallback, Standard/default requested; runtime tier ไม่ได้มีหลักฐานยืนยัน
