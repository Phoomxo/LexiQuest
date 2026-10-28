# Spec Compliance — Issues Found

- ❌ Issues Found: พบ Important 2 ข้อใน strict preflight และ owner-lifetime authentication ด้านล่าง; verdict จำกัด frozen four-file subset นี้
- ⚠️ ยังไม่ตรวจ whole-PM8/whole-branch/G4P: concrete repository/coordinator/host first-write admission, stale leases, tracked research-await invalidation, reopen/retry/terminal/export/deletion และ alias projection เป็น integration ที่ main/root ต้องตรวจแยก

## Strengths

- `lib/features/identity/data/drift_owner_upgrade_repository.dart:144`, `:215`, `:359`, `:500`: sole-active-owner preflight, paged terminal history, destination completion reserve ก่อน cutover/remap และ reauthentication หลัง move อยู่ใน transaction เดิม; strict accepted pins เข้าสู่ preservation/fence เดิม (`:1043`, `:1096`) โดยไม่สร้าง ledger/schema ใหม่
- `lib/features/learning/pair_matching/domain/pair_matching_session_purpose.dart:95`, `:197`, `:227`, `:254`: actor-derived checkpoint keys, revision-1 actor P, contiguous transition validation และ exact durable reservations ครบ prefix; immutable P ไม่ถูกแทนด้วย R
- `lib/features/learning/pair_matching/domain/pair_matching_session_purpose.dart:321`, `:361`: configuration projection ส่งทุก field ของ `SessionConfiguration.validated` ยกเว้น owner ที่เปลี่ยนเป็น R และเทียบทั้ง bytes/identity; ตรวจ constructor จริงที่ `lib/features/learning/domain/session_configuration.dart:325`
- `lib/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart:344`, `:433`, `:461`: reserve ใช้ exact encoded R และ max ของ historical pending bytes/future bound; default same-owner bound ยังเดิมใน supported envelope range. `learning_evidence_contract.dart:18`, `:30` ยืนยัน scalar limits และ event-second flooring. การเก็บ fractional frozen bytes เดิมและไม่เพิ่ม plan-start clock floor สอดคล้อง precision/immutable-occurrence contract; ไม่พบข้อบกพร่องในสองการตัดสินใจนี้
- `test/features/learning/pair_matching/pair_matching_owner_upgrade_auth_test.dart:139`, `:212`, `:335`, `:404`, `:543`: real-upgrade collision/config/long-owner tests และ SQL rollback assertions มี meaningful positive/negative controls

## Issues

### Critical

- ไม่พบจากขอบเขตที่ตรวจ

### Important

1. **Malformed present checkpoints fall through without valid legacy classification.** `lib/features/identity/data/drift_owner_upgrade_repository.dart:577`, `:582`: catch กลืน JSON/cast failure แล้วคืน `null` เมื่อไม่มี row อื่นบ่งชี้ strict. Trigger ที่แคบที่สุด: สร้าง accepted Pair จริงผ่าน `PairHarness.initialize()` (เลือก schema2 matching/density configuration ได้), สร้าง category-only collision target, แล้วเปลี่ยน sole initial `payload_json` เป็น `'{'` โดยเก็บ canonical session/config, event key, actor, owner, aggregate และ event type/version เดิม. Preflight ไม่เพิ่ม session ลง `pairPins`; category-only path ไม่มี word-collision legacy fence และ postflight วนเฉพาะ `pairPins.sessionIds`, จึง remap/rehome แล้ว commit ทั้งที่ accepted checkpoint อ่านไม่ได้. ประวัติการเรียก canonical start ใน fixture พิสูจน์ว่าเดิมเป็น v6; หลัง JSON เสียทั้งก้อน generic matching metadata เพียงอย่างเดียวไม่ได้พิสูจน์ strict และก็ไม่ได้พิสูจน์ valid legacy1–5 เช่นกัน. ข้อนี้จึงเป็น fail-open classification ของ checkpoint ที่มีอยู่และเสียหาย ไม่ใช่การเสนอให้เปลี่ยน valid legacy semantics. ควรปฏิเสธ present undecodable checkpoint (หรือจำแนก legacy ได้สำเร็จก่อนข้าม strict validation), เก็บ existing no-checkpoint/valid-legacy policy. เพิ่ม actual category-only upgrade regression: snapshot หลัง corruption, expect throws, แล้วเทียบ owner/category/word/session/attempt/event/outbox rows ว่าไม่เปลี่ยน; เก็บ valid legacy positive control. Existing corrupt-plan-fingerprint test (`test/features/learning/pair_matching/pair_matching_owner_upgrade_auth_test.dart:404`) ยังอ่าน JSON ได้และไม่ครอบคลุมช่องนี้

2. **Direct historical marker may predate destination creation.** `lib/features/learning/pair_matching/domain/pair_matching_session_purpose.dart:295`: ตรวจ `currentCreated <= destinationUpgraded` และ `historical.upgraded <= destinationUpgraded` แต่ไม่ตรวจ `currentCreated <= historical.upgraded`. ตัวอย่าง P plan/checkpoint 00:00, R created 00:01, R latest upgrade 00:02, inactive P `mergedInto:R` upgraded 00:00:30 ผ่านทุกเงื่อนไข ทั้งที่ P อ้างว่า merge เข้า R ก่อน R มีอยู่. นี่เป็น canonical-lifetime inconsistency ที่ตรวจได้จาก supplied rows ไม่ใช่ข้อกล่าวอ้างว่าสามารถตรวจ database forgery ทั้งชุด. เพิ่ม lower bound จาก R.created ไปยัง historical upgraded และ regression หลัง real P→R merge: ตั้ง R.created ระหว่าง plan กับ real merge ตั้ง P.upgraded ระหว่าง plan กับ R.created แล้วให้ scoped purpose read ปฏิเสธโดย SQL snapshot ไม่เปลี่ยน. คง positive cases ที่ R ถูกสร้างหลัง plan แต่ก่อน actual merge และ repeated direct-link rewrite ไว้

### Minor

- ไม่พบเพิ่มเติมในขอบเขตนี้

## Checked evidence and boundaries

- Read-only Git ระบุ worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`; base `3bdb5f5605e670e8b30628f3f237cd9c0d660ad9`; head เป็น uncommitted four-file snapshot ตาม report ไม่ใช่ commit
- อ่าน flattened diff ครบครั้งเดียว (แบ่ง output 4 ช่วง); SHA256 `1673383654F0E6032B2C6BE3BC8FC8F3B7D1FC98F2A8E0368594F49BC8A81281`. ตรวจ hash ของทั้ง 4 source/test files ตรงตารางใน `pm8-owner-auth-upgrade-report.md:130`
- อ่านเฉพาะ continuation ที่ diff ตัดฟังก์ชัน: purpose decode envelope/transition guards `:35–174`, `:215–249`; codec completion projection/frozen decode `:359–444`, `:583–660`; owner upgrade transaction ordering `:90–219`, `:295–374`. ไม่ reread changed files ทั้งไฟล์
- Named cross-boundary checks: identifier/event precision (`learning_evidence_contract.dart:18`, `:30`), all configuration constructor fields (`session_configuration.dart:325`), canonical purpose-reader transaction/query use (`drift_pair_matching_session_purpose_reader.dart:13`, `:39`). Reader ใช้ expanded owner query จริง; external-await tracked `_Reads` consumers ยัง pending main/root review
- ตรวจ retained `.superpowers/sdd/pm8-auth-runtime-green2.log` tail เห็น `00:19 +56: All tests passed!`; ไม่รัน Flutter/Dart/test/scanner หรือ Git mutation. GREEN56 เป็น existing focused evidence ไม่ใช่ผล regression ของ findings นี้; analyzer/full legacy/release checks ยังไม่ตรวจ
- เขียนเฉพาะรายงานนี้; ไม่มี process ของ reviewer ค้างอยู่

## Assessment

**Task quality: Needs Fixes.** โครงสร้าง TX, immutable P/runtime R, configuration และ destination-byte handling สอดคล้อง scope แต่สองช่องการปฏิเสธข้อมูลผิดข้างต้นต้องแก้และเพิ่ม focused regressions ก่อน subset นี้จะผ่าน Spec/Quality review. ไม่ใช่ข้อสรุป readiness ของ PM8 หรือ G4P
