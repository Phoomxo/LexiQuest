# S01-BK — อายุทางเข้าหน้าเนื้อหาออฟไลน์

## ผลเฉพาะ host

**HOST_PASS236**, เพิ่ม 8 widget tests; focused entry 11 tests ผ่าน และ scoped analyzer ไม่พบปัญหา ใช้ offline fake และฐานข้อมูลในหน่วยความจำเท่านั้น

บน source ก่อนแก้พบ RED ทั้ง 8 กรณี: retained entry หลัง route/tab/pause/dispose, การแทน manager/ถอน dependency/เปลี่ยน registry เป็น disabled และการกดซ้ำเปิดสอง route กรณี dispose พบการใช้ context หลัง unmount; กรณีอื่นพบการเปิดหรือสิทธิ์ที่ควรถูกถอนแต่ยังใช้งานได้ หลักฐานอยู่ใน `evidence/S01-BK-runs/red.*`

แก้เฉพาะ SettingScreen ให้ entry มี generation ตาม dependency, visibility และ feature availability; lifecycle ถอน generation โดยตรง การเปิดใช้สิทธิ์ได้ครั้งเดียวและป้องกันเปิดซ้อน หน้าที่เปิดแล้วตรวจ dependency scope ปัจจุบันและแสดง shared unavailable view เมื่อ scope เปลี่ยน แทนการเรียก manager เก่า กลับ Settings แล้วเริ่มใหม่ใช้ manager ปัจจุบัน รวมถึงซ่อน entry เมื่อ dependency ถูกถอน

การแก้รอบแรกเหลือ pause/resume RED หนึ่งกรณี เพราะวางการเพิ่ม generation ผิด callback แก้ให้เพิ่มใน lifecycle callback แล้วผ่าน เก็บ intermediate log ไว้ Analyzer พบ style info ใน test หนึ่งจุด; เพิ่ม braces และรัน final gate อีกครั้งบนไฟล์สุดท้าย ไม่มี RED ค้าง

Canonical offline manager, owner/storage/schema/scoring/SRS/rewards และ route names ไม่เปลี่ยน การตรวจ lifetime ของงานภายใน offline screen ใช้กลไกเดิม ไม่ขยาย catalog/download/cancel matrix ของ BD–BI

## หลักฐานและขอบเขต

- [Validation](evidence/S01-BK-validation.json): source/artifact hashes, final gate และ fingerprint
- [Checkpoint](evidence/S01-BK-checkpoint.json): writer release, pending และขั้นต่อไป
- [Delta สองไฟล์](evidence/S01-BK-source.patch): เปรียบเทียบกับก่อน BK
- Final `verify-scope.ps1 -Level Targeted -Area Learning -TestTargets` ครอบคลุม offline entry/manager, Settings, erasure, display/logout/password recovery และ canonical local deletion รวม 8 ไฟล์: **236 ผ่าน**
- Final fingerprint `8ce05f691048da7e3240c64fb7ce07eedc031c2a71a9acd9259d79a2dc699abe` ตรง pre/post; input closure 1,563 paths ตรงไฟล์จริง
- BJ source/artifacts และ input closure ตรวจครบก่อนรับ writer; dirty files ที่อยู่นอกขอบเขตและ generated ทั้ง 7 ไฟล์ตรง hashes เดิม ตรวจ final diff แล้ว
- มี dependency/Drift warning เดิมใน log; ไม่ suppress ไม่อ้าง native/device หรือ full release จาก host tests

## ทบทวนกลุ่มอื่นและส่งต่อ

เทียบ plan v5 §§15.4–15.5, state ledger และ readiness-12-groups ที่ backup commit `c22cdaa3a11b83c8e3ce84151672ed8dab11a4e1` แบบ read-only แล้ว:

- UX01/04/08/12 มี host recovery/interface งานก่อนหน้า; ขั้นรับรองจริงยังเป็น native persistence/restart, visual/keyboard/screen-reader และ user review ยังไม่มี finding ใหม่ที่เลือกเป็น package ต่อในการทบทวนครั้งนี้
- UX02/03/05/06/07/11 ยังต้อง reviewed media/rubric และ qualified trial สำหรับการขยายการสอน; ไม่เลือก instructional Flutter เพิ่ม
- UX09/10 ยังรอ device/model/provider/budget/age evidence ที่เกี่ยวข้อง ไม่มีสัญญาณใหม่ให้เปิดบริการหรือ probe

ขั้นต่อไปที่ทำได้ทันทีคือ controller ตรวจ BK receipt/source/gate และคง prerequisite เหล่านี้ใน backlog เลือก implementation ต่อเมื่อมี finding ที่เจาะจงหรือ prerequisite ใหม่ ไม่สร้าง coverage candidate เพิ่มเพื่อให้มีงานต่อ ไม่ได้สรุปว่าทุกกลุ่มสมบูรณ์

Writer `01a0e00b-c36a-7901-a381-42796b559bcf` RELEASED หลังบันทึก checkpoint; ไม่มี successor dispatch ใช้ current model deterministic fallback ไม่ใช่ Jev-selected ขอ Standard/default แต่ runtime tier ไม่ได้ยืนยัน ไม่มี provider/billing/login probes, commit/push/deploy/cleanup หรือ nested ZIP

**S01 IN_PROGRESS; UX-D01–25 OPEN.** Native/device/real restart, visual/keyboard/screen-reader/user, reviewed media/qualified trial และ release ยัง pending
