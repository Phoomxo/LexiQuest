# Wave16: Saved Words ในเครื่องและการกลับมาฝึกจากข้อมูลจริง

วันที่2026-10-30; source `597187e58049a57d3266191b1310f9d71a56693b`,
branch `codex/remaining-system-readiness`, worktree cycle12-release เดิม
schema **v19/36 tables**; v20+ ยังไม่จอง
Flutter3922, analysis0, CLI23/23, backend390/หนึ่ง opt-in skip และ normal debug APK ผ่าน
712 Dart,54 CLI และ92 backend inputs ตรงกับ manifest ที่ตรึงไว้
นี่คือ local engineering checkpoint ไม่ใช่ production/UAT หรือการปิดทั้งผลิตภัณฑ์

## สิ่งที่เชื่อมแล้ว

VocabList save/unsave → Saved Words → restart/offline → current owned word →
QuizScreen ที่ระบุ sourcePractice และ expectedOwnerId → canonical answer/finish เดิม
คำที่ soft-delete แสดง unavailable และนำออกจาก saved ได้; same-ID recreation เคารพ tombstone
ไม่มี fallback word/deck หรือ learning/reward authority ใหม่
save/read/unsave ไม่สร้าง learning/SRS/reward/Research/outbox และไม่อ้างว่า synced

ตาราง saved_words มี7ฟิลด์และ composite owner/word key พร้อม restrictive FKs
เก็บ unsaved tombstone, positive revision, first-save time และ latest mutation receipt
exact retry ใช้ ID/time/revision เดิม; conflict ไม่สร้างคำสั่งใหม่ด้วย revision ล่าสุดเอง
same-DB/ambient guard และ final owner/fence/owned-parent/readback ตรวจหลัง SQL
receipt replay/conflict เป็น read-only หลัง parent soft-delete ได้; save ใหม่ยังต้องมี active parents

owner merge ตรวจข้อมูลก่อน category remap และรวม saved intent ก่อนลบ duplicate guest word จริง
saved union/minimum first-save/max revision+1 ทำให้คำสั่งเดิมไม่ทับสถานะหลัง merge
export เก็บทั้ง7ฟิลด์; reverse purge/core proof ครอบคลุม tombstone และรักษาอีกเจ้าของ
same-owner bind/replay และ logout คงข้อมูล; guest rollback ไม่ลบ saved state ใหม่
UI ตรึง pending command, ปิด stale owner/route/lifecycle/dependency delivery และรักษา delete-confirm/cancel เดิม

## หลักฐานและ review

Evidence root: `D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`

| หลักฐาน | ผล |
| --- | --- |
| saved-words-capture-schema-v18.log / test/fixtures/schema_v18.sql | genuine18/35 ก่อน reservation69f9f176; SQL SHA2569cff95c607a68bf6960ec451148280526bf902e3249d2767b7ebee2925c221c1 |
| saved-words-storage-data-owner-integration.log |109ผ่าน รวม populated-v18/reopen, ทุก35ตาราง/DDLเดิม, Assessment pin18, quiz/pending presentation/deletion intent |
| saved-words-soft-delete-receipt-red.log / saved-words-data-final-green.log |4 actual word/category×replay/conflict RED ก่อนแก้;56ผ่าน พร้อม new-save denial และ10 post-SQL rollback controls |
| saved-words-owner-behavior-red.log / saved-words-owner-first-green.log |13 actual RED/10 controls ก่อนรวม;101 lifecycle/export/purge/core checks ผ่าน |
| saved-words-owner-done-real-close.log / saved-words-ui-integrated-green.log | fixture รอ stream close จริง;1 focused และ72 UI/bootstrap/journey ผ่าน |
| saved-words-expanded-final-green.log / saved-words-ui-database-final-green.log |538 expanded และ95 final DB/UI/bootstrap ผ่าน |
| wave16-full-flutter-initial.log |0a4eecc5 จบ3920ผ่าน/2 stale phase-minus-one schema assertions ไม่ใช่ final pass |
| saved-words-phase-schema-guard-green.log / saved-words-final-analysis.log |แก้เฉพาะ test เป็น19/migration19 และคง negative20;39ผ่าน, analysis0 |
| wave16-full-flutter-final.log |source597187e5:3922ผ่าน,10m48s; log SHA256d1de3b5e92c77d963281f2a04f8d14d72375c19b4f93e310ac21406e44e3fb80 |
| wave16-final-cli-manifest.json / wave16-root-validation-review.json |23/23บน Windows PowerShell5.1; root อ่าน/hash ทุก log |
| wave16-final-backend-manifest.json / wave16-final-validation-review.json |AI186+Voice64+LM140=390ผ่าน;391 JUnit cases รวมหนึ่ง opt-in E2E skip เดิม |
| wave16-artifact-source-verification-final.json |หลัง build:0/712 Dart,0/54 CLI,0/92 backend mismatches; ไม่มี untracked Dart |

data/storage/owner/UI ผ่าน independent review; historical failed logs คงไว้
ชื่อไฟล์ลงท้าย green บางไฟล์เป็นรอบที่ยังล้มเหลว จึงใช้เฉพาะผล PASS ที่ตรวจจริงข้างต้น
initial3920+2 และ final3922 แยก source/manifest; production lib/backend/CLI ไม่เปลี่ยนจากการแก้ phase test

- root validation review SHA256 `db0fd857f90bed22ed228da266c4918d0393b1ccb5e43d3f6104ab5aef224441`
- final backend/CLI source proof SHA256 `ebc7e67efc4d31d3b8d1bb43ddc13fd65cb3392ec1d3a232f34d31b0be05d716`
- frozen Dart manifest SHA256 `4fc986d4ce03591b0b2948866d9257fef9f9fe9978449d4ac2a0923942ae286f`
- post-build artifact source proof SHA256 `58ad6d4132fb1e06f609d410796c1acdac06d4a1d98f3412cc198fa4876f7f54`

artifact-proof helper ใช้ filename ของ initial receipt ผิดหนึ่งครั้ง
กู้ literal ที่อ่านไว้เป็น609ไบต์ hashตรงต้นฉบับAF79D095AE24A74520DA4CF702B9EE4CA9CCACD929A7F411583CADF4B5D031A7
แล้ว root คืน wave16-source-verification-final.json เดิมโดยตรวจ hash; ไม่มี evidence loss เหลือ
หลักฐาน current อยู่ชื่อ artifact-source แยกต่างหาก; helper เพิ่ม exclusive/identical guard และผ่าน review
(script SHA prefix0fc46ec, review receipt prefixBCD48832) ไม่คำนวณ fields/timestamp ของ receipt เก่าใหม่

## APK ที่ตรวจจริง

`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest\build\app\outputs\flutter-apk\app-debug.apk`

- normal lib/main.dart, debug1.0.0+1; compiled kernel build ID **597187e5** ตรวจแล้ว
- build122.6s;252080432bytes; SHA256 `429019bb82de6da9d76cc45e84ce05392387236f2cf77c23a3314b7bef4aa979`
- lib tree `bec04be6d572a58b055f58e44a6a3f2144ca7003`
- test tree `47f86a383d83807f279c85b7cc0b93845d958a3c`
- Android tree `c9abd4fd1187a4af13b306f1f077127f96884bac`
- APK manifest SHA256 `f72d8ad5d9f424567edc1d018654a2e0f03b80883ca504050a8f49ac441464c2`
- process-local heap3G/workers2/daemonfalse; คำเตือน Kotlin/SDK XML เดิมยังอยู่
- ใช้ output path เดิมแทน Wave15; metadata/หลักฐาน [Wave15](2026-10-30-remaining-systems-wave15.md) คงไว้ ไม่สร้างสำเนา binary; ไม่ติดตั้งหรือเผยแพร่

## Coverage และงานต่อ

f20 **Connected local**; matrixเป็น12Connected/18Partial/14Missing
f22ยังPartial: saved path เชื่อมแล้ว แต่ unified due/saved/reported/mistake center ยังไม่ครบ
f13ยังPartial: Sentence Scramble/durable native resume/shared results ยังแยกงาน
ถัดไปคือ revision-bound owned-word report/review/local queue f21; ยังไม่มี report table หรือ migration20

backend ใช้ runtime/deps เดิมและ synthetic CPU fixtures ไม่มี installs/downloads/GPU/live credentials
113 sockets เป็น stdlib socketpairs; external calls ที่ถูกปฏิเสธ0; CLI เป็น fixture/config checks
หนึ่ง real Firebase/OmniVoice E2E ยัง opt-in และไม่ได้เปิด; policy45/3/15เป็นหลักฐานเดิม ไม่ใช่ live scan ใหม่
Research/default production authority/enrollment/upload และ Quest activation/recurrence/grants ยังไม่เปิด
ไม่มี physical-device UAT, efficacy, deployment หรือ production readiness claim
ไม่ได้ทำ cleanup รอบใหม่หรือกลับไปลบ artifacts ที่เคยถูกปฏิเสธ และไม่นับพื้นที่คืนเพิ่ม
