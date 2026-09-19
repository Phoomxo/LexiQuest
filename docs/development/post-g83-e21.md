# E2.1 / F01 — personal vocabulary sets

## Checkpoint C01 — crosswalk foundation (2026-09-20)

**E2.1 remains incomplete.** This checkpoint adds a versioned `SenseRef` and a strict `SenseCrosswalk` decoder/admission policy. It does not add a user-facing set feature or approve a production sense corpus.

- Exact corpus, word, sense revision and lexical artifact hashes remain distinct from historical word SRS identity. Draft crosswalks can resolve references but cannot admit scored activities.
- Scored admission checks reviewed crosswalk bytes, current approved/published packaged vocabulary, category availability, exact lexical manifest identity/hash and the existing strict lexical decoder. Ambiguous duplicate bindings, changed versions, retired content and forged verified wrappers fail closed.
- Local self-review found two gaps (duplicate semantic identity with different artifact hashes; checksum-valid malformed lexical JSON). New failing tests demonstrated both before fixes. No independent/subagent review.

Verification: **37 tests passed across four bounded targets**, including 13 new crosswalk cases; equal pre/post verifier fingerprint. Targeted Dart analysis reports no issues. Structured evidence: [C01 receipt](post-g83-e21/crosswalk-checkpoint.json). No full suite, build, device, live provider or release verification was run.

## Remaining E2.1 work

1. Bind saved revisions to the exact crosswalk pin and sense refs using the C02 authority below. Retain old crosswalk readers and reject changed mappings under an existing immutable identity. Editorial AI-review does not confer scored admission.
2. Add owner-scoped immutable personal set revisions/members, expected-revision save, durable operation identity/payload collision checks, archive and exact revision reads. Recheck schema 28 before assigning the next migration.
3. Integrate owner lifecycle manifest/export/delete, transactional guest upgrade, coherent restore/idempotency and the complete migration matrix. Discover actual restore capabilities rather than assuming the export archive is restorable.
4. Connect real accessible list/edit/preview/activity UI through `lib/screens/learning_pack_catalog_screen.dart` and `lib/screens/study_planning_hub_screen.dart`. Existing planning presentation is under `lib/screens`, not a feature-local presentation directory.
5. Launch an admitted subset through canonical learning/session authority with pinned revisions and no direct SRS/reward/history mutations. Check owner changes at durable/async boundaries. Run fixture, lifecycle, restart, navigation and accessibility regressions and review before accepting E2.1.

Continue **E2.1**, not E2.2. All E6 integration and E7 G8.4–G8.9 obligations remain. Application implementation and one-at-a-time continuation are authorized by the external `post-g83-v3-implementation-authorization.json`, superseding historical analysis-only statements in E0/E1.

## Checkpoint C02 — packaged content authority (2026-09-20)

เพิ่ม crosswalk จริงสำหรับ 12 ความหมายคำนามของ starter เดิม โดยตรึง word revision/checksum และ lexical artifact ทุกตัว. Bootstrap ลงทะเบียนผ่าน `ContentQualityPolicy`/manifest authority เดิม; `SenseCrosswalkPin` และ reader อ่านเฉพาะ corpus/revision/hash ที่ขอ. การจับคู่ตรวจจากเนื้อหา starter ที่ approved อยู่แล้ว เป็น local agent review ไม่ใช่ human/independent review. [ขอบเขตและ corpus pins](post-g83-e21/starter-crosswalk-admission.json) แยกจาก editorial 5,500 รายการซึ่งยังไม่ได้รับ scored admission; hash เดิมทั้ง 9 ไฟล์ตรงครบ.

**164 tests ผ่านใน 5 bounded targets**, รวม 8 tests ใหม่และ bootstrap จริง. ครอบคลุม exact pins, corrupted/retired/missing artifacts, เปิดฐานข้อมูลใหม่, replay และ immutable manifest collision. ไฟล์ใหม่ Dart analysis ไม่มีปัญหา; ตรวจรวม runtime พบ info เดิม 6 จุดที่พิสูจน์ว่า source ไม่เปลี่ยน. [C02 receipt](post-g83-e21/content-authority-checkpoint.json) เก็บ fingerprint ก่อน/หลังที่ตรงกันและ RED/ข้อแก้ไข fixture. รีวิวเองเท่านั้น; ไม่รัน full suite, device, live provider หรือ release gate.

**E2.1 ยังไม่ accepted.** Content authority เชื่อม bootstrap แล้ว แต่ยังไม่มี personal set persistence/UI/launch. Schema ยัง 28. ต่อ C03 ด้วย immutable owner revisions และ lifecycle/restore ก่อน UI; ไม่ส่ง E2.2 จากผลตรวจ checkpoint นี้.

## Checkpoint C03 — immutable revision codec (2026-09-20)

เพิ่ม `PersonalSetRevision` เก็บ exact crosswalk pin, ordered SenseRefs, expected prior revision, operation ID, archive state และ canonical payload hash. ป้องกันข้อมูลซ้ำ/ต่าง corpus/เกินขอบเขตและการแก้ collection จากภายนอก. Owner ต้องตรวจโดย repository/envelope ภายนอกเพื่อรองรับ transactional guest remap; codec ไม่ใช่ authorization หรือ scored admission.

**32 tests ผ่านใน 3 bounded targets (11 ใหม่)** พร้อม fingerprint ก่อน/หลังตรงกัน และ Dart analysis ไม่มีปัญหา. Local review พบและแก้ schemaVersion ทศนิยมที่เคยผ่าน decoder; เก็บ RED และการแก้ EOL/import error ใน [C03 receipt](post-g83-e21/personal-set-codec-checkpoint.json). ไม่มี independent review.

**E2.1 ยังไม่ accepted.** C03 เป็น value/codec เท่านั้น: schema ยัง 28, ไม่มี personal-set table/repository/lifecycle/restore/UI/launch. ต่อ C04 ที่ persistence และ lifecycle ตามรายการค้างด้านบน; ห้ามใช้ผล 32 tests นี้แทน migration หรือ feature acceptance.

## Checkpoint C04 — durable personal sets (2026-09-20)

เพิ่ม schema **29** และ owner-scoped immutable revisions/members. Repository ทำ expected-revision CAS, durable operation replay/collision และบันทึก revision พร้อมสมาชิกใน transaction เดียว. การสร้าง/แก้ไขตรวจ exact crosswalk; historical read และ retry เดิมเปิดได้เมื่อ artifact ไม่อยู่แล้ว. Archive เก็บ pin/members/title/filters เดิม. Canonical owner lease ถูกตรวจทั้งก่อนโหลดและก่อน/หลังการเขียน; A→B→A ระหว่างโหลดไม่รับ token เก่า.

เชื่อม lifecycle manifest, coherent export, child-before-parent deletion และ guest remap จริงโดยรักษา payload hash. การชน key ระหว่าง owner ยกเลิก transaction ทั้งชุด. Local review พบ SQLite cascade แตะ key ที่ค่าไม่เปลี่ยน จึงแก้ immutability trigger ให้ตรวจ OLD/NEW จริง; ไม่ยกเลิก guard. Export ยังไม่ใช่ full restore และ repository ยังไม่เชื่อม runtime/UI.

**346 tests ผ่านใน 26 bounded targets (14 ใหม่)** ครอบคลุม migration matrix, persistence/restart/replay, rollback, owner isolation/merge/export/delete; fingerprint ก่อน/หลังตรงกัน. Implementation analysis ไม่มีปัญหา; integration test มี info เดิมหนึ่งจุดที่ตรวจ source ตรง baseline. Generated data classes เดิมและ corpus pins ทั้ง 9 ไม่เปลี่ยน. [C04 receipt](post-g83-e21/persistence-checkpoint.json) เก็บหลักฐานและ recovery. การหยุดเพราะ path ผิดก่อนหน้านี้ได้รับการแก้ไขตามคำสั่งผู้ใช้และบันทึก recovery ใน AGENTS.md แล้ว.

Fixture ประวัติ assessment ตรึง schema 28 พร้อม assertions ว่าประวัติยังเป็น 28 ในฐานข้อมูล 29; ไม่เปิด research หรือขยาย remote wire admission. Research schema 29 rollout ยังอยู่นอก scope นี้. ไม่มี full suite/build/device/live/release gate และไม่มี independent review.

**E2.1 ยังไม่ accepted.** ต่อด้วย restore envelope/codec/idempotency และ old/new archive compatibility, application owner generation ก่อน acquire lease, runtime wiring, catalog/planning UI และ canonical exact-revision activity launch พร้อม navigation/accessibility/research-off oracles. ส่งต่อเฉพาะ E2.1; ไม่ส่ง E2.2 จน feature acceptance ครบ.

## Checkpoint C05 — restore และ owner generation (2026-09-20)

เพิ่ม owner-bound `PersonalSetArchive` และ coherent repository export/restore สำหรับประวัติ personal sets ทั้งหมด: strict schema/manifest/hash, revision/operation collision, replay หลัง restart และ rollback ทั้ง transaction. Restore เก็บ exact pins แม้ content ไม่พร้อม โดยไม่ให้สิทธิ์เริ่มกิจกรรม. Envelope v1 ที่ไม่มี extension groups อ่านเป็นชุดว่าง; v2 มี revision history; รุ่นใหม่กว่าปฏิเสธก่อนเขียน. นี่เป็น backup ของ personal sets แยกจาก redacted `OwnerLifecycleArchiveExporter` เดิม ซึ่งยังไม่ใช่ full database restore; checksum ไม่ใช่หลักฐานยืนยันตัวตน.

เพิ่ม `PersonalSetsUseCases` และเชื่อม `AppDependencies.personalSets` ผ่าน canonical owner coordinator สำหรับ save/read/list/export/restore. Token ผูก runtime, owner และ durable epoch; ตรวจทั้งก่อนรอ lease หลังรับ lease และก่อน/หลัง transaction write. Epoch ใน namespace ภายใน `runtime_flags` เปลี่ยนพร้อม owner transaction รวม direct binding, guest upgrade/logout/rollback และ erasure; ไม่เพิ่ม schema จาก 29 และไม่ export epoch. ตรวจ A→B→A ทั้ง runtime เดียวและ repository อีกตัวที่ใช้ฐานข้อมูลเดียวกันแล้ว. Local review พบช่องว่าง generation ในหน่วยความจำและเพิ่ม durable guard พร้อม RED ก่อนแก้.

**318 tests ผ่านใน 11 bounded targets (22 ใหม่)**, fingerprint ก่อน/หลังตรงกัน. โค้ดใหม่และ tests ที่เพิ่ม analysis ไม่มีปัญหา; integration มี info เดิม 10 จุดซึ่งพิสูจน์ source เท่ากับ baseline. Corpus 9 hashes ไม่เปลี่ยน; generated platform files 7 รายการเท่ากับ Git blob เดิม. [C05 receipt](post-g83-e21/restore-generation-checkpoint.json) เก็บ RED/verification/recovery และหลักฐาน review เอง ไม่มี independent review. Fixture global-state retention แยก epoch ที่ต้องเปลี่ยน พร้อมยืนยัน global อื่น/owner อื่นเหมือนเดิมทั้งหมด.

**E2.1 ยังไม่ accepted.** C06 ต้องทำ list/edit/preview/activity UI ที่เข้าถึงได้จริงจาก catalog/planning, canonical launch จาก exact saved revision/pin/current quality/owner generation, รวม UI restore affordance/compatibility และ navigation/accessibility/research-off oracles. ยังไม่มี personal-set UI หรือ activity launch และยังไม่อ้าง full database restore. ไม่เปลี่ยน research schema29 admission/remote rollout; ไม่มี full suite/build/device/live/release gate. ส่งต่อเฉพาะ E2.1 ตาม implementation authorization และ mandatory recovery เดิม.
