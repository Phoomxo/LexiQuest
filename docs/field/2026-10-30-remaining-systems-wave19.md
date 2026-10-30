# Wave19: พื้นที่ขีดเขียนชั่วคราวใน Typed Cloze

วันที่2026-10-30; application source `f33014037073c97ff039a9427a7402504f980571`,
branch `codex/remaining-system-readiness`, worktree cycle12-release เดิม.
Schema **v20/37 tables**, v21+ ยังไม่จอง; frozen8/44 และ contracts เดิมคงอยู่.
Flutter **4297ผ่าน/10นาที59วินาที**, analysis0, CLI23/23,
offline backend390ผ่าน/หนึ่ง opt-in skip เดิม และ normal debug APK ผ่าน.
ตรวจ748 Dart/54 CLI/92 backend ตรง source freeze หลังตรวจและ build.
นี่เป็น local engineering checkpoint; ไม่ใช่ production/physical-device UAT.

## สิ่งที่เชื่อมแล้ว

P18 → เลือก Typed Cloze/หมวดหมู่ → accepted session เดิม → P35 TextField เดิม
พร้อมพื้นที่เขียนร่างที่เริ่มพับอยู่ → วาด/ย้อนเส้น/ล้างเส้น → พิมพ์คำตอบ →
canonical typed answer ACK → เปรียบเทียบลายมือด้วยตนเอง → finish ACK เดิม.
Choice Cloze ไม่เพิ่ม scratchpad. Drawing alone เปิด Save ไม่ได้.
ล้างเส้นไม่แตะข้อความ; เส้นไม่กลายเป็นคำตอบ/คะแนน/word IDs หรือเหตุการณ์ใหม่.
หลัง ACK เก็บร่างแบบอ่านอย่างเดียวและระบุชัดว่าผลตรวจเฉพาะคำที่พิมพ์.

Widget เป็น local memory-only:64strokes/4096points, normalized finite coordinates,
single pointer, clipped180px canvas, actual dots/paths และ immutable paint snapshots.
Undo/Clear กับ pointer callbacks อ่าน live canEdit/expanded ทุกครั้ง;
ObjectKey ของ accepted session ป้องกันการยกร่างข้ามรอบ.
IME/rebuild หรือ closure instance ใหม่ไม่ล้างร่างในรอบเดิม.
Collapse หยุด pointer แต่คงเส้น; ออกจาก scope/dispose ล้าง state.
ไม่มี OCR, raster export, storage/restoration, network/model call, permission,
table, dependency, repository port, evidence field/profile หรือ learning writer ใหม่.
clozeTyped ยังเป็น guidedPractice/hint1 และใช้ pins/projections/outbox เดิม.
การวาด/Undo/Clear ไม่เพิ่ม SRS/mastery/effort/reward/Research facts.

## ข้อบกพร่องที่พิสูจน์และแก้

- Actual parent frame RED: stable sync owner stream ส่ง null→A ระหว่าง sibling build;
  TextEditingController.clear ใน _invalidate ทำ markNeedsBuild during build
  และช่องตอบเก่ายังค้าง enabled. ตั้ง sticky invalidation/epoch/selection ก่อน listener
  แล้วเลื่อน clear/redraw เฉพาะ persistentCallbacks และเริ่ม owner-bound work หลัง frame.
  กรณีเดิม GREEN โดยไม่ suppress exception; ไม่แก้ framework หรือ native sibling อื่น.
- Actual canvas pan RED: outer list offset84กลายเป็น124ระหว่างวาด60px.
  Canvas-only EagerGestureRecognizer ชนะ gesture arena ตั้งแต่ down;
  readonly canvas ใช้ map ว่าง. Relative-offset equality และ outside-scroll control
  ผ่านทั้งคู่; ไม่ปิด page physics ทั้งหน้า.
- Widget API RED1 เกิดก่อน promote. Raster toImage/toByteData ใน fake zone ค้าง;
  ย้ายเฉพาะ awaits ไป bounded real async zone. Pixel comparisons crop canvas จริง
  จึงไม่ใช้ status/count เปลี่ยนแทนภาพวาด. ไม่สร้าง PNG files ใหม่.
- First integrated75ผ่าน/5fail เป็น fixture scrolling/wait: legacy helper เลือก scroll
  ของ EditableText และ held-ACK helper รอ pumpAndSettle ขณะ progress ตั้งใจยังหมุน.
  ใช้ actual outer P35 list, layout flush/padding drag และ bounded pump.
  คง assertions/actual gestures; clean4modulesผ่าน80โดยไม่มี warnings.
  รวม18 widget/17 owned integration และ existing Cloze/chooser checks.
- Six test-only lint infos แก้ braces/import/interpolation; final analysis0.
  Full4297ผ่านบน source ที่ตรึง. Focused counts ซ้อนกัน ไม่รวมเป็นจำนวน test ใหม่.

## หลักฐานและ artifact

Production review2ไฟล์และ clean follow-up **ACCEPT**;
เชื่อม raw hashes EBB1AFD7…(widget)/EBD98CFD…(P35) กับ committed source.
Independent backend/CLI และ artifact review แยกจากผู้เขียน.
หลักฐานอยู่ `D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`:

| หลักฐาน | SHA-256 |
| --- | --- |
| wave19-frozen-dart-source-final.json | `a382626027fa547176ec66d4603c1711a0750c14d9874fa1ed03b4992777ad0e` |
| wave19-full-flutter-final.log | `436acac7214c7725602afa276d5b425b8e57a1493831637240937470be70021d` |
| scratchpad-integrated-review.md | `ddae6511c917e6ca7ab2f0fe0c2279faef728ecf3593c2a46163bc974a108dbc` |
| scratchpad-clean-validation-review.md | `cdb118a42397a8a61a84fcc35e899509fe1cc8c3fb6682ebb509d8d967bb3afc` |
| wave19-integrated-review-source-binding.json | `540d62e11d8c165a99e172c36c686798800fb0f103f1e872e1536bd66fbbf2c0` |
| wave19-root-validation-review.json | `b261ea2c6ce78f920d216f15a5b0c6184edc1843827e5cb48f2d719e522d70e2` |
| wave19-independent-validation-review.json | `89c3dcfcda85961fbca41b0faeaaef4ad54a028e144c5295b1153b11602dc8d6` |
| wave19-normal-debug-apk-manifest.json | `06f9709f672f6f802487a7d69d5a985b53b5536581da363233761d985b9e37cf` |
| wave19-artifact-source-verification-final.json | `2b555b5c69e844fbf64c6bdfe18d41b659fd2100ad8b58f5417a96091d5c1f94` |
| wave19-artifact-proof-review.md | `7f817f5e4cf78e91f3f238bbcdb6b0c614c026c3674bcc377e6b351683988726` |

Normal `lib/main.dart`, debug1.0.0+1, buildID `f3301403`;
build120.3s, `252224228`bytes,
SHA `dcda685693ade33439e56239ab7693fa9960e7912676fc1126d765a634e03fb3`.
Actual ZIP kernel `assets/flutter_assets/kernel_blob.bin`/`102705424`bytes
มี marker ตรงกัน. Start `2026-10-30T12:10:12.1751603Z`;
modified `2026-10-30T12:12:12.691978+00:00` และใหม่กว่า build start.
lib tree `4b3dabf0449702483b3c27ddffddadf4727ef197`;
test tree `2f0293473d0bb1ed944e64224f4ff94afccc8010`;
android tree `c9abd4fd1187a4af13b306f1f077127f96884bac`.
ใช้ output เดิมแทน normal debug รุ่นก่อน ไม่ทำสำเนา APK เพิ่มด้วยตนเอง ไม่ install/publish.
Gradle จำกัด process-local3G/workers2/daemonfalse และคืน environment เดิม.
คำเตือน plugin KGP และ SDK XML3/4 เดิมยังอยู่; build ปัจจุบันผ่าน.

## งานต่อและข้อจำกัด

f12 เป็น **Connected เฉพาะ local Typed Cloze aid** ตาม frozen purpose/TOR:
เขียน/Undo/Clear/typed fallback/manual self-check; ไม่อ้างรู้จำหรือให้คะแนนลายมือ.
Coverage **13Connected/19Partial/12Missing**. f03/f05/f11/f13 คง Partial;
cross-mode shell/durable native resume และ physical stylus/TalkBack ยังไม่รับรอง.

หน่วยถัดไปคือ owner-bound SRS safety ก่อน Review Center.
f22 ต้องรวม due/incorrect/saved/local-report พร้อมเหตุผลจริง;
due คง self-rated SRS, ไม่เปลี่ยนเป็น recognition และไม่ฝึกจาก historical report snapshot.
SRS/Review API ยังต้องอ่าน source และยืนยันแผน bounded ก่อน implementation;
ไม่จอง v21 หรือสร้าง authority/table ใหม่เพียงเพื่อแสดงคิว.

Production Research/real gateway/collection/upload/trusted artifacts,
provider efficacy/real-service availability, signed rollout และ physical UAT ยังแยกไว้.
Research default-off; ไม่สร้าง separate Pair Matching task.
คง primary unique WIP, critiques2ไฟล์ และ feedback PNG4ไฟล์.
Automatic approval ปฏิเสธ PNG4ไฟล์และ stop/delete emulator/preview เดิม
ด้วยเหตุผล blocked by policy; เก็บไว้ ไม่ retry ไม่อ้างคืนพื้นที่เพิ่มใน Wave19.
ไม่มี task-owned verification process ค้างเมื่อจบ checkpoint.
