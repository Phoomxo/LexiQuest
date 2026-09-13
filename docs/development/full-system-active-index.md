# LexiQuest — Active Full-System Index

Revision `2026-09-14-camera-training-5` · **67 requirement packages (64เดิม+3ใหม่) / accepted history5 / remaining62 in21bundles** · `gpt-6-astra` / `medium`

ผู้ใช้อนุมัติเปลี่ยนเป็นหนึ่งtaskต่อชุดงานหลัง G0.5 เสร็จ. G0.5 accepted SHA `9125ae7b9ccff15bb44ebbab455b8b0251c8fcfe`; run-state revision17พักเฉพาะsuccessionแบบเก่า. การอนุมัติ groupedexecutionแทนpauseนั้นแล้ว. คำสั่งpause/stopใหม่ยังมีผลก่อนเอกสาร

1. อ่าน AGENTS และ [Rule Register](2026-09-13-rule-supersession-register.md)
2. อ่าน [Bundle Workflow](full-system-package-workflow.md), currentrun-state และ acceptedpredecessorhandoff
3. ใช้ [Task/Bundle Index](full-system-task-index.json) เลือก ownbundlebrief; **package.nextPackage ไม่ใช่dispatch**. อ่านbriefของpackageเมื่อถึงข้อนั้น
4. อ่าน [Master Plan](../superpowers/plans/2026-09-13-lexiquest-full-system-master-plan.md) เฉพาะownpackage/dependencies/gate และ [ledger](2026-09-13-full-system-work-ledger.json) เฉพาะrequirements/coverage
5. อ่าน [coverage audit](2026-09-13-master-plan-coverage-audit.md), [minigame contract](../superpowers/specs/2026-09-13-minigame-coverage-contract.md), engineering/acceptance/source register เฉพาะIDsที่ต้องใช้

[ตาราง21ชุดงาน](full-system-bundle-map.md) แสดง59packagesที่เหลือครบตามลำดับ. G0.1–G0.5/checkpoints/receiptsเก็บประวัติaccepted ไม่ย้อนทำ. Briefเดิมเป็นrequirement unitภายในbundle ไม่ใช่tasktemplate. แกนrequirements/acceptance/testsยังครบ

ใช้acceptedsourceจากhandoff: B01รับorchestrationcommitที่ต่อจากG0.5; B02+รับcommitของbundleก่อนหน้า. **ไม่ทับเอกสารด้วย seed7712**. G0.3 authoritydispositions, G0.4verificationobligations และ G0.5traceability/evidenceยังเป็นinputsโดยไม่อ้างruntimePASSเพิ่ม

ทำทีละpackageในbundleworktreeเดียว มีwriterหนึ่งตัว. รายงานMarkdownหนึ่งไฟล์ต่อbundle ผลย่อย/verification/defectsใช้structuredlogsและpackage receipts. สร้างsuccessorเฉพาะbundleผ่านและปล่อยwriterแล้ว. B20ไม่มีsuccessor. `r15-package-workflow.md` เป็นcompatibilitypointerเท่านั้น

G0.6 [document authority registry](full-system/evidence/bundles/B01/G0.6-document-registry.json) แยก active/supporting-contract/historical/superseded พร้อม hash/restore map; [cleanup dry-run](full-system/evidence/bundles/B01/G0.6-cleanup-dry-run.json) ระบุ disposition ของภาพ failure76ไฟล์. Observations/source claims เดิมเป็นประวัติ ณ source ที่บันทึกไว้ โดยเฉพาะ PLAN-04 เรื่อง conversation context/speech identity; รับ authority ปัจจุบันจาก G0.3/G0.5 และตรวจ delta ใน G6 ไม่สร้างงานซ้ำจากคำกล่าวเก่า. มี Master ปัจจุบันเพียงฉบับที่ลิงก์ด้านบน; historical roadmap ไม่ใช่คิว execution.

## Camera training amendment — 2026-09-14

Canonical revision `2026-09-14-camera-training-5`: คง64 requirement IDsเดิม เพิ่ม G5.3a–c รวม67packages/21bundles (B11Aเพิ่มหนึ่งbundle). ลำดับ B11 → B11A → B12 → B13…B20. ใช้ภาพอินเทอร์เน็ตสำหรับ train/development validation ตอนนี้ ไม่รอภาพจากผู้ใช้. เก็บภาพกล้องจริงตอน device testing ภายหลัง; ผลกล้องจริง pending จนทดสอบจริง ห้ามใช้คะแนนเว็บอ้างแทน. Fresh test ห้ามปรับ threshold/เทรน; หากนำภาพกล้องที่ดูแล้วมาแก้/ฝึกให้จัดเป็น development และใช้ชุดกล้อง held-out ใหม่ตรวจรับ. เก็บ unknown-object evaluation แยกชัดเจน. Trainingจริงเป็นrequired deliverable; baseline retentionหรือเอกสารไม่ปิดG5.3c. ใช้ source rights/actual compute และไม่เพิ่มค่าใช้จ่ายโดยอนุมาน.
