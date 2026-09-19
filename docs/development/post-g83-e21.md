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
