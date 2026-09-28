# งาน engineering ถัดไป — isolated native navigation/persistence harness

สถานะ: READY_FOR_ENGINEERING_REVIEW; ยังไม่มี implementation หรือ native PASS. ที่มา: S01-BL พบ physical V2041 พร้อม แต่ package หลักและ `.ariTest` มีอยู่แล้ว และ smoke ปัจจุบันไม่รองรับ scope นี้ Controller เป็นผู้จัด fresh successor; BL ไม่ dispatch

## เป้าหมายและ write set ที่เสนอ

สร้างทางรัน debug แบบ local/synthetic สำหรับ BL-N01–04 โดยใช้ canonical navigation, preferences, owner, vocabulary และ offline manager เดิม ไม่สร้าง learning/reward authority ใหม่

ก่อนสร้างไฟล์ค้น equivalent ด้วย `rg --files`; ชื่อต่อไปนี้เป็นไฟล์เสนอ ยังไม่มีอยู่:

- `integration_test/native_baseline_acceptance_test.dart`: navigation/Settings/offline assertions แยก test cases; local fixture และ real viewport
- persistent debug entrypoint/fixture runner สำหรับ seed/verify ข้าม OS process พร้อม receipt ที่ไม่มี secret; เลือกที่ตั้งหลังสำรวจ `tool/`/`integration_test/` ไม่ใช้ test teardown ลบ persistent fixture
- `tool/cli/run-native-baseline-acceptance.ps1` และ contract tests: device/package preflight, source/APK pins, bounded phase selection, per-phase logs/exit codes
- `android/app/build.gradle.kts` และ test-only manifest ถ้าจำเป็น: debug-only identity ใหม่ที่ไม่ชนสองแพ็กเกจเดิม; ไม่แก้ release ID/signing หรือ existing ariLocalTest behavior
- `tool/cli/verify-scope.ps1` เฉพาะเมื่อจำเป็นต้องเพิ่ม explicit native bounded selection; เก็บความหมาย `flutter-tester` เดิมและ evidence layer ให้ชัด
- เอกสาร/receipt ใน `docs/development/ux-delivery/`; หนึ่ง writer, ไม่แก้ ready-backlog ของ controller โดยพลการ

## ข้อกำหนด implementation

1. ใช้ package identity ใหม่เฉพาะงาน ตรวจไม่ติดตั้งอยู่ก่อน build/install และตรวจ actual APK ID จาก artifact ก่อน install ห้ามใช้ `install -r` เพื่อกลบ collision ห้าม clear/uninstall ทั้งสองแพ็กเกจเดิม
2. ApplicationId suffix อย่างเดียวไม่พิสูจน์ offline/privacy: ตรวจ merged manifest/native startup providers รวม Firebase initialization, deep links/notifications และ test bootstrap ปิด external gateways จริง ใช้ fake transport/local content; เก็บ outbound invocation counters โดยไม่บันทึก credentials
3. กำหนด run identity และ synthetic owner/content IDs เดียวกันระหว่าง seed/verify ใช้ canonical SQLite/preferences กับ persistent directory ใน test package เท่านั้น ปฏิเสธ path ที่ชี้ออกนอก sandbox ของ test package
4. แยก navigation/local persistence จาก quiz/rewards/export/logout/research mutation. ไม่เรียก research withdraw เพื่อทำ fixture ให้ปลอดภัย; compose research off และตรวจ research rows/outbox ไม่ถูกสร้าง
5. Native viewport ต้องเป็นจอจริง ไม่ override เป็น desktop size และไม่เปิด authenticated VM endpoint receipt โดยอัตโนมัติ Logs ต้องไม่มี token/endpoint/ข้อมูลแอปเดิม
6. Process restart ต้องใช้ seed → flush/close → ยืนยัน process exit → relaunch APK เดิม → verify-only. ห้าม reinstall, clear, reseed หรือใช้ database reopen/pumpWidget/hot restart เป็น substitute. ถ้า runner ทำไม่ได้ให้รายงาน NOT_RUN เฉพาะขั้นนั้น
7. ใช้ adb เฉพาะ development/package/process control ที่ได้รับอนุญาต; ไม่ทำ screen scraping/tap/input เพื่ออ้อมข้อจำกัด native UI automation. Visual/keyboard/TalkBack คง pending หากช่องทางที่อนุญาตยังไม่มี
8. ไม่ restore/copy historical QA APK หรือข้อมูลจาก old worktrees; ไม่ cleanup หลังรันอัตโนมัติ เก็บ test package และ synthetic evidence ไว้โดยระบุเจ้าของ

## Acceptance ของ harness ก่อนรัน native

- Contract tests แบบ stub ต้อง reject device ที่ไม่ใช่ Android, package collision, production/ariTest ID, APK ID mismatch, phase failure และ verify ที่ไม่มี seed; ตรวจว่าไม่มี install/clear/uninstall ใน rejected case
- Fixture tests ต้องแสดง reopen แบบไม่ seed ซ้ำ, owner/row identity คงเดิม, external-call count=0 และ research rows/outbox=0; สิ่งนี้เป็น host evidence เท่านั้น
- ตรวจ final diff และ run targeted CLI/Flutter checks ผ่าน verify-scope บน fingerprint ปัจจุบัน; ห้ามรัน full release บน dirty HEAD
- ก่อน native run ต้องตรวจ device/package ใหม่และ APK source manifest: HEAD อย่างเดียวไม่พอเพราะ BD–BK เป็น dirty source
- รัน native ทีละ phase เฉพาะ N01–04; เก็บ device/OS/APK hash/commit+dirty hashes, actual command, exit status, timing, per-case result และ artifacts
- หลักฐาน preserved existing packages: บันทึก package/version/update metadata ก่อน–หลัง ไม่มี write command target ไป package เดิม ไม่อ่านหรือ export private learner dataเพื่อพิสูจน์ preservation
- ถ้า native test ล้มเหลว ให้แยก fixture/runner/product defect และแก้เฉพาะ finding; ไม่เพิ่ม offline coverage matrix ที่ปิดแล้วหรือขยาย instructional scope

## การแยกผล

Readiness = device discovery + isolation inspection; host = stub/unit tests; native = physical-device execution; restart = OS process evidence; user/trial = actual participant/reviewer evidence; release = frozen-source gates. ห้ามเลื่อนผลข้ามชั้น

Jev ไม่มี fresh billing จึงใช้ current-model deterministic fallback, Standard/default ตามนโยบาย ไม่ probe/login ซ้ำ. งานนี้ไม่ต้องติดต่อผู้ทดลองหรือเปิด provider/research/deployment
