# Wave15: Word Scramble ที่บันทึกผลจริงและการค้นคำข้ามหน้า

วันที่2026-10-30, application source `d995ffc2040ba2019a09542be4db549ad92094eb`,
branch `codex/remaining-system-readiness`, worktree cycle12-release เดิม
ทดสอบ Flutter3820, analysis0, CLI23, backend390/หนึ่ง opt-in skip และ normal debug APK ผ่าน
hash ของ695 Dart,54 CLI และ92 backend คงเดิมตลอดรอบตรวจและ build

## พฤติกรรมที่เชื่อมแล้ว

ChooseMode ที่ผ่าน quiz gate → หมวดของเจ้าของจริง → Word Scramble หนึ่งคำที่ตรึง
word/revision/ลำดับ grapheme → บันทึกคำตอบ → กดจบ → summary/history จากข้อมูลจริง
ใช้ sealed native lifecycle เดิมร่วมกับ Dictation/Cloze ไม่เพิ่มตารางหรือ mode registry
คำที่สลับแล้วเหมือนเดิมถูกข้าม โดยคงพฤติกรรม helper เดิมสำหรับ a/aaa ไว้
อักษรซ้ำ อักขระผสม และ ZWJ ใช้ดัชนีต้นฉบับแยกกัน ลาก กดเลือก ใช้แป้นพิมพ์
หรือพิมพ์คำตอบได้ Undo/Clear คงลำดับโจทย์เดิม

คำสั่งตอบและจบตรึงก่อน await และใช้ตัวเดิมเมื่อลองใหม่หลัง ACK หาย
ตรวจ original handle, เจ้าของ, deletion fence, คำ/หมวด/revision และสถานะหน้าจอ
ทั้งก่อนและหลังขอบเขต SQL ไม่รับช่วงด้วย raw ID หรือ generic writer
ไม่เก็บคำตอบดิบ และแสดงเฉลยหลัง ACK เท่านั้น
ข้อความใบ้และ semantics ซ่อน whole target แบบ Unicode โดยไม่แทนคำที่เป็นเพียงส่วนหนึ่งของคำอื่น

หลักฐานเป็น recreational, skill word-scramble, hint0 และ false engagement
อนุญาต session/history/outcome แต่ไม่เพิ่ม SRS/mastery/active-learning effort,
XP/coins/Quest/Streak/achievement หรือ Research
carry ที่ผิดรูปและ Sync alias/replay คงการกั้นเดิม พร้อมรักษา remote SRS baseline จริง
non-source speech กลับ quiz เดิม; เส้นทาง source/permission center คงเดิม
characters1.4.1 เป็น dependency ที่ติดตั้งและล็อกอยู่แล้ว เปลี่ยนเป็น direct ผ่าน pub get --offline
ไม่มี package/version ใหม่

เพิ่ม optional afterWordId ให้ read port เดิม พร้อม SQL id>cursor, owner/category/selected-ID/deletion
และ limit1–100 เดิม Scramble และ Cloze จึงข้ามหน้าแรก100คำที่ใช้ไม่ได้ไปยังคำจริงได้
เก็บเพียงหนึ่ง/สาม candidate ตามกิจกรรม และไม่ยืมคำจากหมวดอื่นเมื่อระบุหมวด
Cloze คง target/order/content hash และ final ambient probe → owner → current → provider
กรณีไม่ระบุหมวดจำหมวดที่ตรวจแล้วไม่ครบ เพื่อไม่อ่านหมวดเดิมซ้ำสำหรับทุกคำ

## หลักฐานและ review

Evidence root: `D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`

| ไฟล์หลักฐาน | ผลที่ตรวจแล้ว |
| --- | --- |
| word-scramble-floor-red.log / floor-green.log |14 actual RED/7 controls แล้ว56 combined checks ผ่าน |
| word-scramble-core-first-run.log |61 core checks ผ่านก่อนเพิ่ม regression ข้ามหน้า |
| word-scramble-unicode-cue-red.log | คำไทยและ ZWJ หลุดจริง2กรณีก่อนแก้ |
| word-scramble-ui-corrected-fixture.log |111 UI/caller/helper/reduced-motion checks ผ่าน รวม320px/200%/IME/keyboard |
| native-word-pagination-corrected-red.log |5 actual behavior RED และ1 exhaustion control หลังแก้ fixture uniqueness |
| native-word-pagination-querycount-red.log | paging draft แรกอ่าน vocabulary SELECT จริง302ครั้ง เกินเพดาน6 |
| native-word-pagination-first-green.log |99 combined core/pagination/native UI/final-owner-probe checks ผ่าน; query ceiling6 ผ่าน |
| word-scramble-learning-projection-regression.log |829 Learning/Sync/Quest/Assessment checks ผ่าน |
| word-scramble-integration-analysis.log |0 issues; แก้ multiline-test braces5จุดก่อนตรึง source |
| wave15-full-flutter-final.log |3820ผ่าน,11m35s บน source ที่ตรึงไว้ |
| wave15-cli-manifest.json / wave15-root-validation-review.json |23/23 suites บน Windows PowerShell5.1; root อ่านทุก log และตรวจ hash |
| wave15-backend-manifest.json / wave15-validation-review.json | AI186+Voice64+LM140=390ผ่าน; JUnit391กรณีมีหนึ่ง opt-in skip เดิม |
| wave15-source-verification-final.json |0/695 Dart,0/54 CLI,0/92 backend mismatches; ไม่มี untracked Dart |
| wave15-normal-debug-build.log | normal debug build ผ่าน141.1s, process-local heap3G/workers2/daemonfalse |

Core, Unicode UI และ pagination ผ่าน independent review
การแก้ fixture คง assertions เดิม: เติม responseTimeMs ที่ required, เอา const ที่ SDK ไม่รองรับออก,
ใช้ meaning สังเคราะห์ไม่ซ้ำตาม unique constraint, เลือก vertical scrollable จริง
และเลื่อน cue ให้มองเห็นก่อนตรวจ semantics ไม่ปิดคำเตือนหรือข้าม hit-test
การย้าย12 adapters เพิ่มเพียง12 optional parameters/11 forwards พร้อม proof ว่า
ไบต์เดิม/string literals/assertions คงเดิม

Backend ใช้ Python/pytest เดิม, imports จาก C ปัจจุบัน และ offline synthetic fixtures
ไม่มี installs/downloads/GPU/live credentials; socket113รายการเป็น Windows stdlib socketpairs,
external calls ที่ถูกปฏิเสธ0 หนึ่ง Firebase/OmniVoice E2E ยัง opt-in และไม่ได้เปิด
raw backend scope label สืบทอดข้อความ Quest จาก runner เดิม; review receipt ระบุ source/tree/hash
ของ Word Scramble ปัจจุบันชัดเจน CLI เป็น fixture/config checks ไม่ใช่ scanner/deployment
policy source ไม่เปลี่ยน;45/3/15เป็นหลักฐานเดิม ไม่ใช่การตรวจ live policy ใหม่

## APK ที่ตรวจแล้ว

`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest\build\app\outputs\flutter-apk\app-debug.apk`

- normal lib/main.dart, debug1.0.0+1, build ID d995ffc2; ยังไม่ติดตั้งหรือเผยแพร่
- 251991271bytes; SHA256 `1991a2db75ea5380fa24f3bd0d2dab1d679452fed8a5f1ed25b87aa4a6d85702`
- ตรวจ build ID จาก compiled assets/flutter_assets/kernel_blob.bin จริง
- lib tree `30eff09412fb76c91a386064fa1f76b4b44e7270`
- test tree `62f3d199168520588df18f07c594b2c198fe2e4a`
- Android tree `c9abd4fd1187a4af13b306f1f077127f96884bac`
- APK manifest SHA256 `c2a7055d5cace30b391ca74b7a7bb1f9a157ccf7d54ea7e06fcd11293b59f945`
- frozen Dart manifest `390539e374bedcd2db3e5b7400b972e59901a275fea1952d2e22b6366a98bd2b`
- final source proof `2e73b71566843b907047da61e3583428a3eca7110dfc19a381bda67abb83b613`

ใช้ output path เดิมแทน binary wave14 ไม่สร้างสำเนา APK อีกชุด
ยังมีคำเตือน future-KGP และ SDK XML3/4 เดิม

## งานถัดไปและข้อจำกัด

schema18/35, catalog8/44 และ EvidenceContext/EventEnvelopeV2 fields คงเดิม
coverage ยัง11 connected/18 partial/15 missing; f13ยัง partial เพราะ Sentence Scramble,
durable native restart/resume และ shared results/shell ยังไม่ครบ
Quest activation/recurrence/grants/Today, production Research authority/collection/upload,
trusted external artifacts, content efficacy และ physical UAT ยังเป็นงานแยก
Research default-off และ primary checkout ที่มี unique WIP ยังเก็บไว้

ต่อ [Saved Words](../superpowers/plans/2026-10-30-saved-words-integration.md)
ตาม [remaining-feature sequence](../superpowers/plans/2026-10-30-remaining-feature-sequence.md)
v19+ ยังไม่จอง ณ checkpoint นี้ ต้องเก็บ genuine v18 fixture และจอง ledger ก่อนเขียน migration

การลบ emulator/preview และ feedback PNG4ไฟล์ที่เคยถูก automatic approval ปฏิเสธ
ด้วยเหตุผล blocked by policy ยังเก็บไว้และไม่ลองลบซ้ำ ไม่มีการนับเป็นพื้นที่ที่คืนได้ในรอบนี้
