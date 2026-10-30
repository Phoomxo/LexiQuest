# Wave18: เกมเรียงประโยคจากข้อมูลที่รับรองใน native lifecycle

วันที่2026-10-30; application source `29038b4add94bb83df19188b2562ed3ea7f11d1f`,
branch `codex/remaining-system-readiness`, worktree
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`.
Schema **v20/37 tables**, v21+ ยังไม่จอง; frozen8/44 และ contracts เดิมคงอยู่.
Flutter **4262ผ่าน/11นาที12วินาที**, analysis0, CLI23/23,
offline backend390ผ่าน/หนึ่ง opt-in skip เดิม และ normal debug APK ผ่าน.
ตรวจ745 Dart/54 CLI/92 backend ตรง source freeze หลังตรวจและ build.
นี่เป็น local engineering checkpoint; ไม่ใช่การรับรองทั้งผลิตภัณฑ์หรือ physical UAT.

## สิ่งที่เชื่อมแล้ว

P18 → เลือกหมวดหมู่ของเจ้าของ → ContentProvider เดิมสร้างประโยคจริงหนึ่งครั้ง
นอก SQL transaction → P34 เรียงชิ้นคำหรือพิมพ์ → canonical answer ACK →
explicit finish ACK → P23 ใช้คะแนนที่บันทึกจริง → ประวัติในเครื่อง.
แทน raw orphan widget เดิม; ไม่สร้างตัวอย่าง/คำแปลประโยคหรือ default voice ปลอม.
ความหมายที่แสดงระบุว่าเป็นของคำศัพท์ต้นทาง. A2 เป็นค่าที่ขอ ไม่ใช่การรับรองระดับภาษา.

ตรึงประโยค ชิ้นคำ ดัชนีซ้ำ metadata และ hash ของคำต้นทางกับ accepted session.
จำกัด raw text1024runes/2048UTF8bytes ก่อน normalize Unicode White_Space;
เก็บเครื่องหมายวรรคตอนเป็นชิ้นคำ ใช้2–64ชิ้นและอย่างน้อย2ชิ้นที่มีตัวอักษร/ตัวเลข.
คำตอบเต็มแยกจาก owned-word anchor; provider provenance ใช้ bounded hash.
ไม่มี table, dependency, repository port หรือ wire field ใหม่.

ใช้ sealed native writer เดิมกับ original object/sameDB/independent transaction,
owner/deletion fence, revision/category/currentness และ final SQL readback.
generic start/answer/finish ปฏิเสธ reserved prefix/activity/prompt.
Lost start/save/finish ACK ส่งคำสั่งและเวลาชุดเดิม; ไม่สร้างคำตอบหรือ outbox ซ้ำ.
กิจกรรมเป็น recreational/hint0/engagementfalse: เก็บ outcome/history ได้
แต่ไม่เพิ่ม SRS/mastery/effort/XP/coins/achievement/Quest/Streak/Research.

UI มี indexed tap/drag, keyboard/typed alternative, Undo/Clear และ input freeze.
Back รอบที่เริ่มแล้วขอคำยืนยัน; ระหว่างรอ start/save/finish ACK ปิด Back ชั่วคราว.
เสียง optional ยืม service เดิม ไม่มี autoplay/default construction/disposal;
Stop/Replay จัดลำดับผ่าน pending stop และ live audio intent.
ประโยคเกินขอบเขตเสียง500UTF16ยังตอบด้วยข้อความได้.
P23 ใช้ summary ของ session ที่จบจริง; owner/dependency/lifecycle/foreign cover
ทำผลเก่าใช้ไม่ได้ถาวร. Back เก่าปิดหน้าอื่นไม่ได้. History ไม่มี native-resume ปลอม.

## ข้อผิดพลาดและหลักฐานที่แก้

- Projection RED19/controls10 และ pure API RED2 เกิดก่อน promote.
  Core รอบแรก176ผ่าน/6fail: synthetic nonlegacy fixtures ขาด mandatory pins4กรณี
  และ outbox selection รวม category/word rehome2กรณี.
  เติม synthetic pins ที่บังคับและตรวจ attempt operation ทั้ง row;
  เพิ่ม full-owner second-bind idempotence โดยคง assertions. Core182ผ่าน.
- Constructor RED2 เกิดก่อนเปลี่ยน UI.
  Actual audio RED2 พิสูจน์ manual Stop→Replay และ Stop ระหว่าง queued Replay;
  เก็บ pending stop future และตรึง intent ก่อน await แล้ว focused3ผ่าน.
- ชุด UI/caller/history5 modules ผ่าน96โดยไม่มี hit-test warning.
  ทดสอบ actual correct/incorrect P23, committed owner null→เดิมระหว่าง provider/Score,
  stale callbacks/foreign cover, lost ACK, real Tab/Enter/drag และ Thai+English320px/200%/IME.
  Helper รอ layout หลังเลือกชิ้นคำยาว เลือก outer list ของ route จริง และเลื่อนจาก padding;
  watcher teardown ใช้ real async zone. ไม่ลด assertions หรือปิด warnings.
- Analyzer infos3จุดใน tests แก้เฉพาะ interpolation/import; final analysis0.
  Full4262ผ่านบน commit ที่ตรึง. ตัวเลข focused ซ้อนกัน จึงไม่รวมเป็นจำนวน test ใหม่.

## การตรวจและ artifact

Integrated production review **ACCEPT** อ่าน source ทั้ง10ไฟล์และ connected callers.
Review baseline ก่อน commit ผูกกับ committed bytes ผ่าน source-binding receipt;
independent backend/CLI และ artifact review แยกจากผู้เขียน.
หลักฐานอยู่ `D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`:

| หลักฐาน | SHA-256 |
| --- | --- |
| wave18-frozen-dart-source-final.json | `a55b1e96a4bb6f16bb7829e5c204ef193801bf3a430e31fe6be75793ee4e56ca` |
| wave18-full-flutter-final.log | `e9e7913bdcf635529ea241494d48d63804400b7516fb70f1922f8b22c0a32561` |
| sentence-scramble-integrated-review.md | `b9e4e2e20470db4fb2414d88ded33cb2d2a7c7379c7d467d1f690ee0e0dd7af9` |
| wave18-integrated-review-source-binding.json | `adc02b3314ca452dd1fb99ef8c38f2db51a46fafd864af8548945194ec132d2e` |
| wave18-root-validation-review.json | `5f5fd884657a0009be0536c0f01dad967ab1524bfa57759ccb2010ce09040a01` |
| wave18-independent-validation-review.json | `fba3386ad53f42c3ac157f3ec88b0ae42cf16441e0268592b2e532f9fb17c9e5` |
| wave18-normal-debug-apk-manifest.json | `118ccf21e02a6995edb46e5009f4aef57c78213fd2bcb24cffc4cfd283272c5a` |
| wave18-artifact-proof-review.md | `06a88ff08c4e49dddc6c2e12a505981aa8c3c1eba3a446bd6352f0caf19849bb` |
| wave18-artifact-source-verification-final.json | `b3a9edf6162724f1a0fd195adf0989350db3a346d430c5daccd61632fed88c93` |

Normal `lib/main.dart`, debug1.0.0+1, buildID `29038b4a`;
build122.2s, `252213345`bytes,
SHA `43b1aebccae4d1c8ae930e672cd5cf904e166c405e774e6cd5a49e9cfbfdaf34`.
Actual ZIP kernel entry `assets/flutter_assets/kernel_blob.bin`/`102673184`bytes
มี marker ตรงกัน. Start `2026-10-30T11:22:04.9056730Z`;
modified `2026-10-30T11:24:07.300363+00:00` และใหม่กว่า build start.
lib tree `09914282e776f37674a16d57b5e83f90a40ee591`;
test tree `9be97ce21d0642e642e3782915e9d054201c1f13`;
android tree `c9abd4fd1187a4af13b306f1f077127f96884bac`.
ใช้ output เดิมแทน normal debug รุ่นก่อน ไม่ทำสำเนา APK เพิ่มด้วยตนเอง ไม่ install/publish.
Gradle จำกัด process-local3G/workers2/daemonfalse และคืนค่า environment เดิม.
คำเตือน KGP ของ plugins และ SDK XML3/4 เดิมยังอยู่; build ปัจจุบันผ่าน.

## งานต่อและขอบเขตที่ยังไม่ครบ

Coverage คง12Connected/19Partial/13Missing.
f13 ยัง Partial: durable native restart/resume และ shared shell/results ของทุก mode ยังไม่ครบ.
f11/f21/f22 และ backlog อื่นคงแยกตาม matrix; ไม่ปิด capability กว้างด้วยเกมเดียว.
หน่วยถัดไปเป็น f12 scratchpad ชั่วคราวบน P35 Typed Cloze พร้อม Undo/Clear/typed fallback,
ตาม frozen purpose; ไม่มี OCR, ink persistence หรือ learning writer ใหม่.

Production Research/real gateway/collection/upload/authority artifacts,
real service availability, provider grammar/CEFR efficacy, signed release rollout
และ physical-device/TalkBack/stylus/UAT ยังไม่มีหลักฐานในรอบนี้.
Research default-off. ไม่สร้าง separate Pair Matching task.

ยังคง unique WIP ของ primary checkout, untracked critiques2ไฟล์ และ feedback PNG4ไฟล์.
Automatic approval ปฏิเสธการลบ PNG4ไฟล์และงาน stop/delete emulator/preview เดิม
ด้วยเหตุผล blocked by policy; เก็บไว้ ไม่ retry และไม่อ้างคืนพื้นที่เพิ่มใน Wave18.
ไม่มี task-owned verification process ค้างเมื่อจบ checkpoint.
