# Wave17: รายงานปัญหาคำศัพท์แบบ local queue

วันที่2026-10-30; source `158d2115a2eee800e0a5dfe5a97d1c77d0c9eb26`,
branch `codex/remaining-system-readiness`, worktree cycle12-release เดิม
schema **v20/37 tables**; v21+ ยังไม่จอง
Flutter4029, analysis0, CLI23/23, backend390/หนึ่ง opt-in skip และ normal debug APK ผ่าน
731 Dart,54 CLI และ92 backend inputs ตรง manifest ที่ตรึงไว้
นี่คือ local engineering checkpoint ไม่ใช่ production/UAT หรือการปิดทั้งผลิตภัณฑ์
หลักฐาน [Wave16 Saved Words](2026-10-30-remaining-systems-wave16.md) คงเดิม

## สิ่งที่เชื่อมแล้ว

VocabList overflow → report owned word → เลือกเหตุผล/เขียนคำอธิบาย →
ตรวจรายงานและแก้ไขก่อนยืนยัน → canonical queue ACK → ประวัติรายงานในเครื่อง
restart จาก file DB แล้วยังอ่าน receipt/content/version เดิมได้
UI ระบุชัดว่าบันทึกในเครื่องและยังไม่ได้ส่ง ไม่มีสถานะ sent ปลอมหรือ transport ใหม่
เหตุผล/comment ที่เห็นตอน review ถูกตรึง; ครั้งแรกที่ confirm จึงสร้าง ID/time
หลังส่งครั้งแรกหรือ ACK ไม่แน่นอน ห้ามแก้ payload/ออก ID ใหม่; retry ใช้คำสั่งเดิม
stale target/collision ไม่ถูกแก้โดย reprepare ด้วยข้อมูลล่าสุดเอง

WordReports มี10 fields: reportID/currentOwner/historicalWordID/categoryID/revision/
canonical ownerless snapshot/hash/reason/comment/queuedUTC
มี restrictive owner FK เท่านั้น ไม่มี live word/category FK
submit ใหม่ต้องมี active owned parents และ revision/hash ที่ตรงก่อนและหลัง SQL
committed-ID replay ตรวจ payload/owner/fence/readback ได้แม้ target ถูกแก้หรือลบแล้ว
sameDB/ambient guard และ final owner/deletion-fence/readback ครอบคลุมทุก return path
ไม่มี learning/SRS/reward/Research/outbox/notifier จากการ queue หรืออ่านรายงาน

## Migration และ owner lifecycle

จอง v20 ก่อน DDL และเก็บ genuine v19/36 DDL+populated data ก่อน bump
migration/reopen รักษาทุก row/DDL ของ36ตารางเดิม; report queue เริ่มว่าง
SavedWords saved+tombstone, Assessment schema pin19, pending quiz,
presentation switch10/suppressed2/pending13 และ persistent deletion fence คงเดิม
owner merge parse/validate ก่อน business mutation; เปลี่ยนเฉพาะ current owner ของ report
อีก9 fields รวม historical IDs/revision/snapshot/hash/time ไม่ remap ตาม duplicate word
ตรวจ final report set หลัง owner update; malformed/foreign/tampered/missing row rollback ทั้ง TX
same-owner bind/replay/logout คง facts; restrictive owner FK ป้องกัน rollback guest ที่มี report
personal export ครบ10 fields; purge ลบ reports/residual ได้และรักษา owner อื่น byte-for-byte

## ข้อบกพร่องที่พิสูจน์และแก้

actual late-IME RED: controller เปลี่ยนหลัง review แล้วคำสั่งเก่าอ่านค่าที่ไม่ได้ review
แก้ด้วย frozen reason/comment snapshot; regression เดิมผ่านโดยไม่ลด assertions
actual coalesced-owner RED: null→ownerเดิมระหว่าง persistentCallbacks ทำ review เดิมกลับมา
แก้เฉพาะ Sheet ด้วย captured ownerGeneration และ sticky invalidation; regression ผ่าน
ไม่เปลี่ยน scope-global หรือ parent Vocab/history fresh-reload behavior
first UI run73ผ่าน/2fail เป็น fixture timing: รอ forwarded owner event ให้ settle;
320px/200% เลือก reason ก่อน IME และรอ layout220px inset ก่อนเลื่อนถึง Review
4 legacy menu REDs ย้าย interaction ผ่าน overflow ตาม API จริง
ยังคง delete confirm/cancel, pending-disabled และ previous-owner visibility assertions
real Tab/Enter, narrow/large-text และ file-DB restart journey ผ่าน; ไม่อ้าง hardware TalkBack/UAT

## หลักฐานการตรวจ

ตัวเลขแต่ละชุดอาจซ้อนกัน จึงไม่รวมเป็นจำนวน test ใหม่:
storage3; legacy migrations95; data59; owner97;
UI/bootstrap+oldSaved/journey86; expanded regression756; export regression48
logs: word-reports-schema-corrected-green, legacy-target-first-green,
data-corrected-import, owner-first-green, ui-integrated-green,
expanded-regression และ export-regression (`.log`) ทั้งหมดผ่าน
full `wave17-full-flutter-final.log`: **4029ผ่านใน10:52**
final analysis: **0 issues**; backend JUnit391 =390ผ่าน/1 opt-in E2E skip/0 failure/error
CLI23 suites ผ่าน; Python audit มี113 stdlib internal socketpairs/0 external attempts
package origins29แห่งตรง active worktree; ไม่มี install/download/GPU/live credentials ในรอบ CPU
independent storage/UI review และ root data/owner integration review รับแล้ว; ไม่มี Codex Security workflow
root review: `wave17-root-validation-review.json` SHA d4c4905a8e98afeb6eff76e00ed0dadc8f89a5bd630688174eb6563dccc12f61
independent review: `wave17-independent-validation-review.json` SHA4a22fb04480e108de728329d055c8c37aa9341bef0cbc912f71cd17a6036162e
source receipt: `wave17-backend-cli-source-verification.json` SHA0ba69f5b5d57aa077ae38c978937087ae62779e1b1b89f478406f031920c1886

## APK และ source binding

`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest\build\app\outputs\flutter-apk\app-debug.apk`

normal `lib/main.dart`, debug1.0.0+1, BUILD `158d2115`; assembleDebug125.7s
APK252164502 bytes SHA `8c25607d830cb91372c9ba183634f051e0f012e1a6e27f5122d04fea7fc43bea`
actual kernel102546264 bytes มี marker158d2115; reviewerอ่าน ZIP/hash จริงแยกจาก root
APK manifest SHA `13cb2d01bb4ded04ac46c361ecd5d99c8a953bd13697bccf7d8fdcf2b3181c76`
new artifact proof SHA `ef11d9428fa538c23e2740aff230a4ac04b0c6f5c3f8ee81c5e678c1edc72b3a`
frozen731 Dart manifest SHA `5992457aac5c2cbc4d5432c79717e991e808ead6ba7201f0c500b94194415a6d`
full log SHA `6dd5d3f38dabfdd9dfaa013698d8c911e128860785584bd26160011135c3a561`
lib tree fc11d0d98b79f9c8df01042ea5e90abbb646bf01; test ccbc369a28d3d3b510706a3a7bd5973eb583bf5a
Android c9abd4fd1187a4af13b306f1f077127f96884bac; ทุก source hash731/54/92คงเดิม
artifact review `wave17-artifact-proof-review.md` SHA EFC9FE6F1CA6466395FC2BC9CA06F7385D7BB7ADBBB6D51DAA81657E00EFA349
หลักฐานอยู่ D remaining-systems; output ใหม่ใช้ exclusive/identical guard ไม่ทับ Wave16 receipts

## สถานะและงานถัดไป

matrix **12 Connected /19 Partial /13 Missing**; f20Connected, f21Partial, f22Partial
f21ครอบคลุม owned local word เท่านั้น; AI/chat/document targets และ production transport ยังแยกงาน
f13ยังPartial: Sentence Scramble, durable native resume/shared shell และ physical UAT ยังไม่ครบ
Researchยัง default-off; ไม่มี enrollment/upload/rollout/device validation หรือ efficacy claim
APKยังไม่ติดตั้งหรือเผยแพร่; release-only dependencies ไม่ถูกแทนด้วย synthetic tests
P34มี D-only grounded plan/APIเตรียมไว้; เริ่ม C implementation หลัง checkpointนี้ attested/pushed
ไม่เพิ่มตารางหรือจอง v21 และไม่เปิด Pair Matching จากการปิด unit นี้
Catalog8/44 และ EvidenceContext/EventEnvelopeV2 fields คงเดิม
ใช้ output path เดิมแทน Wave16 ไม่สร้างสำเนา APK; คำเตือน Kotlin/SDK XML เดิมยังอยู่
ไม่ retry การลบ emulator/preview หรือ PNG4ไฟล์ที่ automatic approval เคยปฏิเสธด้วย blocked by policy
ไม่มีการนับพื้นที่คืนเพิ่มในรอบนี้
