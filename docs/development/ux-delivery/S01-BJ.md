# S01-BJ — อายุการยืนยันลบข้อมูลในเครื่อง

## ผลตรวจรับเฉพาะ host

**HOST_PASS157**, เพิ่ม 19 widget tests; ไม่เหลือ RED ในขอบเขตนี้ และ `dart analyze` สองไฟล์ที่แก้ไม่พบปัญหา ทั้งหมดใช้ fake หรือฐานข้อมูล Drift ในหน่วยความจำ ไม่มีข้อมูลผู้ใช้จริงหรือ provider จริง

โค้ดเดิมเก็บ eraser/owner repository ตั้งแต่ bind ครั้งแรก ตรวจเพียง mounted หลังอ่าน owner และ owner ID ก่อนลบ จึงอาจเปิดคำยืนยันเก่าหรือเรียก eraser เก่าหลังเปลี่ยน dependency/แท็บ/หน้า/พักแอป ชุดจำลองที่แก้การรอ spinner แล้วพิสูจน์ RED 14 จาก 15 กรณีบน production source เดิม อีกสองกรณีพบ callback รอบก่อนยังเปิดคำยืนยันรอบใหม่ได้ระหว่างตรวจการแก้ขั้นแรก

แก้เฉพาะ `SettingScreen`: bind dependency ปัจจุบัน, เก็บ generation ของปุ่มและคำยืนยัน, ตรวจสถานะหน้า/แท็บ/lifecycle ก่อนและหลัง async boundary, ถอน dialog ที่หมดอายุโดยอ้าง route ของตัวเอง และเลิกใช้ callback เมื่อจบรอบ การตรวจ owner ID ก่อนเรียก canonical eraser ยังคงอยู่ ผู้ใช้กลับมาเริ่มคำยืนยันใหม่ได้

ไม่เปลี่ยน canonical erasure/storage/schema, research consent flow, activation, scoring, SRS, rewards, routes/deep links หรือ feature gates การลบที่ส่งไป canonical eraser แล้วไม่ได้ถูกยกเลิกหรือ rollback โดย UI; การแก้นี้ควบคุมสิทธิ์เริ่มคำสั่งและการแจ้งผลของหน้าที่หมดอายุ

## หลักฐาน

- [Validation](evidence/S01-BJ-validation.json): hashes, gate, source fingerprint และขอบเขตการตรวจ
- [Checkpoint](evidence/S01-BJ-checkpoint.json): writer release และขั้นตอนถัดไป
- [Delta](evidence/S01-BJ-source.patch): สองไฟล์ที่แก้จาก source ก่อน BJ
- `evidence/S01-BJ-runs/`: source ก่อน/หลัง, RED, stdout/stderr และ final verifier receipt
- Final gate: `verify-scope.ps1 -Level Targeted -Area Learning -TestTargets` erasure widget, settings, display/logout/password recovery, offline settings entry และ canonical local deletion รวม 7 ไฟล์; **157 ผ่าน** บน source ปัจจุบัน
- ตรวจ final input closure 1,563 paths, BI source/artifact hashes และไฟล์ generated เดิม 7 ไฟล์ตรงกัน; ตรวจ diff แบบ `cr-at-eol` ผ่าน

การแก้ fixture: `pumpAndSettle` รอ spinner ระหว่าง pending owner ไม่สิ้นสุด จึงเปลี่ยนเป็น bounded pump ก่อนคืน future; lifecycle case ต้อง resume แล้ว pump จึงตรวจการถอน dialog ได้จริง เก็บผลรอบแรกไว้ ไม่ใช้ timeout เหล่านั้นอ้างเป็น product defect รูปแบบเดิมของ tests ก่อน BJ ถูกเก็บไว้

## ขอบเขตที่ยังรอ

Native/device/real restart, visual/keyboard/screen reader/user, reviewed media/qualified trial และ release ยัง pending; UX-D01–25 OPEN และ S01 IN_PROGRESS ไม่อ้าง end-to-end หรือ production readiness ไม่ได้รัน full release/build หรือบริการภายนอก

ใช้ current model เป็น deterministic fallback ไม่ใช่ Jev-selected; ขอ Standard/default และไม่อ้างว่ายืนยัน runtime tier ได้ ไม่มี billing/login/inference probes, commit/push/deploy/cleanup หรือ successor dispatch

## ส่งต่อ controller

Writer ของ BJ RELEASED หลังบันทึกหลักฐาน รักษา dirty BD–BI และ generated ทั้ง 7 ไฟล์ใน worktree เดิม

ขั้นต่อไปที่มี source รองรับ: ตรวจ entry ของ `SettingScreen._openOfflineContent` (UX01/UX12) และ tests `offline_content_settings_entry_test.dart` ก่อนเลือก package ใหม่ ปัจจุบัน entry ตรวจ feature/composition แต่ไม่มี display lifetime guard; `canInvoke` จับ `dependencies` เดิมไว้และเปรียบเทียบ manager กับ object เดิมนั้น เป็น **ข้อสงสัยจาก source ไม่ใช่ RED** ทดสอบ retained entry/การแทนที่ dependency ด้วย offline fake ก่อนแก้ ไม่ขยาย catalog/download/cancel matrix ของ BD–BI หากไม่พบข้อบกพร่องให้บันทึก coverage แล้วกลับประเมิน backlog ห้ามขยายไป research flow หรือ instructional Flutter ที่ยังติด trial/media gates
