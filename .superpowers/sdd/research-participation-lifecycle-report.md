# R3 research participation lifecycle — รายงานส่งมอบ

สถานะ: ส่งมอบ bounded lifecycle implementation; focused final **54/54 ผ่าน**, analyzer **No issues found**.
คืน exclusive Flutter/Dart test/analyzer slot และแจ้ง main แล้วหลังทุก command จบ exit 0 (2026-09-05 ประมาณ 13:55 Asia/Bangkok).
ไม่มี process ของ worker นี้ค้างอยู่. หลังคืน slot ทำเฉพาะ read-only review และเขียนรายงานนี้.

## Worktree / authority / write scope

- Worktree: `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`.
- Branch: `feature/adventure-research`; HEAD: `6968ce97ff9b383e244b17b77cf0ed0f61eaaf3d`.
- อ่าน AGENTS.md ฉบับ recovery, active implementation plan/progress, repository/validator/consent APIs, schema guards และ actual event/outbox mappings.
- ใช้ TDD และ systematic-debugging; เตรียม tests ก่อนและรอ explicit test-slot grant จาก main แล้วจึงรัน RED และแก้ production.
- แจ้ง API decision ก่อน patch; main ยอมรับ พร้อมกำชับ delete jobs, signed revisions, exact neutral event types และ frozen EventsV2 DateTime mapping.

ไฟล์ที่แก้ไข/สร้างทั้งหมดในงานนี้:

1. `lib/features/research/data/drift_research_participation_repository.dart`
2. `lib/features/research/application/research_participation_permit_validator.dart`
3. `lib/features/consent/data/drift_research_consent_repository.dart`
4. `test/features/research/research_participation_lifecycle_test.dart` (ใหม่)
5. `.superpowers/sdd/research-participation-lifecycle-report.md` (ใหม่)

ไม่ได้แก้ crypto, shared fixture, measurement/opportunity, main service/UI/sync, schema หรือ generated source.
ไม่มี commit, task creation, dependency resolution, generators, repo-wide tests/analyzer/scans หรือ deployment.

## พฤติกรรมและ API

- APIs เดิมของ `importPermit`, `requireParticipant`, `readActivePermit`, validator `validate` และ consent repository ยังคง signature เดิม.
- เพิ่ม synchronous `ResearchParticipationPermitValidator.validateAuthenticity(permit, expectedOwnerId:, expectedAssignmentId:, evaluatedAtUtc:)` คืน `ResearchPermitDenialReason`; `none` หมายถึง authenticity ผ่านเท่านั้น ไม่ใช่ active participation.
- Authenticity ตรวจ canonical fields/UTC, owner/assignment/protocol, equal positive signed revisions, minor receipt references, revocation >= issuance, payload SHA-256 และ issuer signature. Signature-authority exceptions ปฏิเสธแบบ fail-closed.
- `validate` ตรวจ activity/expiry/revocation และ receipt authority ต่อจาก authenticity. อ่าน required receipts สองรอบเพื่อไม่ใช้ snapshot ที่ค้างจาก await รอบแรก; ตรวจ signature authority ซ้ำหลัง await. Receipt-authority exceptions คืนผล denial.
- Active import ยังคงตรวจ local owner/consent/assignment ก่อนและหลัง asynchronous validation, ตรวจเวลาปัจจุบันหลัง lookup และเทียบ persisted permit อีกครั้งก่อนเขียน เพื่อปฏิเสธ stale source state.
- Signed update ต้องใหม่กว่า revision เดิม หรือเป็น exact replay ที่ payload/hash/signature ตรงกันทุกค่า. Immutable pins: id, owner, assignment, protocol/version, treatment, participant class/age band, consent/guardian/assent receipt references และ issuedAt.
- `localRevision` / `cloudRevision` เป็น signed fields: คัดลอกค่าจาก issuer ตรง ๆ ไม่ increment ระหว่าง import หรือ local withdrawal.
- Signed revocation ของ permit ที่มีอยู่รับได้แม้หมดอายุหรือถอน consent/receipt แล้ว โดยไม่เรียก active validation เพื่ออนุมัติ participation. Unknown permit ที่ส่งมาเป็น inactive state ไม่สร้าง enrollment row.
- ปฏิเสธ rollback, same-revision conflicting payload, forged/missing signature authority, un-revoke และการย้าย revocation timestamp เดิม. Exact revocation replay ไม่เปลี่ยน row.
- Consent withdrawal ใช้ transaction เดียว: เปลี่ยน consent, เปลี่ยน nondeleted `started`/`completed` runs ของ owner+consentVersion เป็น `withdrawn`, ปิด open opportunities ที่เกี่ยวข้อง และระงับ pending research upserts.
- Preserve existing completed close timestamps; สำหรับ open rows ใช้เวลาปิดไม่ต่ำกว่า started/opened timestamp. Increment เฉพาะ unsigned run/opportunity local revisions เมื่อเปลี่ยน state จริง.
- ไม่เขียน signed permit fields และไม่ลบ/แก้ response evidence, denominator counts, event rows, learning rows หรือ event timestamps.
- Reaccept ต้องใหม่กว่า withdrawal; backdated/same-time reaccept ถูกปฏิเสธ. Local consent/issuance/assignment pins เดิมทำให้ old permit/signature/receipt ไม่ฟื้น capture หลัง reaccept.

## ข้อตกลง outbox ที่ส่งต่อให้ R4 sync

- ระงับเฉพาะ `operation_kind = upsert` ใน `pending`, `retryWaiting`, `inFlight`, `permanentFailure` โดยเปลี่ยนเป็น `superseded`, ใส่ `failure_code = researchConsentWithdrawn`, ล้าง lease/retry time.
- เก็บ delete jobs, acknowledged jobs, unrelated learning operations, other owners และ run-linked consent versions อื่นไว้เหมือนเดิม.
- Four new entityType names: `motivationMeasurementRun`, `motivationResponse`, `researchParticipationPermit`, `measurementOpportunity`; existing research assignment/assessment operations ใช้ `experimentAssignment` / `assessmentRun` และต้องสัมพันธ์กับ scoped runs.
- `eventsV2` ต้องสัมพันธ์กับ scoped opportunity ผ่าน `correlation_id`, หรือ `aggregate_type = MeasurementOpportunity` + `aggregate_id`; owner ต้องตรงกัน และ event type ต้องเป็นหนึ่งในสี่ค่าด้านล่างเท่านั้น:
  `TodayExperiencePresented`, `TodayExperiencePresentationChanged`, `TodayExperienceMissionStarted`, `TodayExperienceMissionCompleted`.
- ไม่ระงับ generic event outbox ตาม owner อย่างเดียว และไม่เปลี่ยน frozen EventsV2 schema/envelope. Test ใช้ main's UUIDv7 identity helper และยืนยัน event rows ก่อน/หลัง withdrawal เท่ากัน.
- ข้อจำกัด mapping ปัจจุบัน: permit ไม่มี consentVersion โดยตรง. Permit ที่เชื่อมกับ runs ใช้ assignment/protocol linkage; สำหรับ permit ที่ยังไม่มี run ใด ๆ ระงับ permit upsert ของ owner แบบ conservative เพราะยังไม่มี version linkage ให้พิสูจน์. R4 ต้องคง upload gating และกำหนด mapping นี้ให้ตรงกับ runtime protocol catalog ก่อนเปิด transport.
- การ invalidate local inFlight lease ไม่ใช่การยกเลิก network request ที่ส่งออกไปแล้ว. R4 ต้องตรวจ owner/consent/permit อีกครั้งที่ upload boundary และไม่ retry งาน `superseded`.

## RED / GREEN / regression evidence

คำสั่งทั้งหมดรันจาก worktree ข้างต้นโดย serialize Flutter/Dart commands และไม่รัน main opportunity/service/UI tests.

1. Initial load ของ new suite มีชื่อ `isNull` / `isNotNull` ชนกันระหว่าง Drift กับ matcher; แก้ import `hide isNull, isNotNull` ในไฟล์ test ที่เป็นเจ้าของ. นี่เป็น compile correction ไม่ใช่ RED feature evidence.
2. RED:
   `flutter test --no-pub test/features/research/research_participation_lifecycle_test.dart --reporter expanded`
   **27 passed / 14 failed**, exit 1. Failure สอดคล้องกับ missing signed-update/revocation support, stale receipt acceptance, missing withdrawal/outbox transitions และ backdated reaccept.
3. GREEN หลัง implementation และ targeted formatting: คำสั่งเดิม **41 passed / 0 failed**, exit 0.
4. Focused existing regressions:
   `flutter test --no-pub test/features/research/research_participation_permit_validator_test.dart test/features/consent/research_consent_use_cases_test.dart --reporter expanded`
   **13 passed / 0 failed**, exit 0.
5. Initial focused analyzer พบ 5 informational curly-brace findings ใน owned repository/test; แก้ทั้งหมดโดยไม่เปลี่ยน behavior.
6. Final source verification:
   `flutter test --no-pub test/features/research/research_participation_lifecycle_test.dart test/features/research/research_participation_permit_validator_test.dart test/features/consent/research_consent_use_cases_test.dart --reporter expanded`
   **54 passed / 0 failed**, exit 0; waited for process completion before releasing slot.
7. Final analyzer:
   `dart analyze lib/features/research/data/drift_research_participation_repository.dart lib/features/research/application/research_participation_permit_validator.dart lib/features/consent/data/drift_research_consent_repository.dart test/features/research/research_participation_lifecycle_test.dart`
   **No issues found**, exit 0.
8. `dart format` เฉพาะสี่ owned Dart files: final **0 changed**. Focused `git diff --check` ผ่าน; อ่าน final tracked diff และ untracked participation source ครบก่อนส่งมอบ.

## Self-review / acceptance boundaries

- New lifecycle tests ใช้ actual P-256 signing/verifying ผ่าน PointyCastle และ crypto verifier ที่เสร็จแล้ว. Test-only synthetic private scalar อยู่เฉพาะ test file; ไม่ใช่ production issuer/key/config.
- ทดสอบ real SQLite transaction rollback โดยให้ outbox update ล้มเหลวด้วย synthetic trigger; consent/run/opportunity/outbox snapshots ต้องกลับเหมือนเดิม.
- ทดสอบ response/denominator/signature preservation, exact four-event outbox scope, lease invalidation, delete/ack/unrelated-operation preservation, export after withdrawal, nonparticipant zero capture rows/events/outbox, expiry/receipt/owner/local withdrawal races และ withdrawal/reaccept old permit denial.
- Personal export ผ่าน `ResearchLifecycleExportReader` หลัง withdrawal; delete job preservation ผ่าน. ไม่ได้รัน full physical owner deletion suite ใน slot นี้ และไม่ได้แก้ deletion manifest/schema.
- การอ่าน external receipt authority ซ้ำไม่ได้สร้าง distributed transaction กับ remote issuer. Runtime/transport ยังต้องเรียก gate ที่ mutation/upload boundary และรักษา authority freshness ตาม interface; ไม่ใช่สิทธิ์ enroll/upload จริง.
- ไม่ได้ทดสอบ full Research integration, emulator/rules, real UI/device, APK หรือ production rollout. Main เป็นเจ้าของ integration/restart/baseline-skip tests และ UI/sync slots ถัดไป.

## Verified SHA-256

- Participation repository: `2706249E48298C5BAB3FE241A5D4F950625348303D1CD07E7A291822D36AB3C7`
- Permit validator: `B25FF89C9DFF03300F54D37460F64941934541878202B879B07A770B95ABA357`
- Consent repository: `DD007DC590FB0868654F61034610E6ECCFBF60AA57DE1322804CD88B0FE2A66C`
- Lifecycle tests: `610C838297451E2A1DB3DC6A5D44909B799CAE1C6F75BA9BF89F16A7E0665CD2`

Next executable step: main อ่าน diff/API/outbox mapping ข้างต้น แล้วใช้ slot ที่คืนให้รัน shared/restart/baselineSkipdenominator RED/GREEN ต่อ. Worker นี้หยุด source writes และส่งมอบ report แล้ว.
