# Independent review — Firestore research receipt authority

**Verdict: Approve เฉพาะ provider/test scope นี้.** ไม่พบ concrete actionable finding จาก actual source และ corresponding tests. ไม่มี product/test edit หรือคำกล่าวว่า research พร้อม production

Worktree `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`; branch `feature/adventure-research`; HEAD/base `6968ce97ff9b383e244b17b77cf0ed0f61eaaf3d`. ใช้ current AGENTS และ `requesting-code-review` + `code-reviewer.md`, `receiving-code-review`, `verification-before-completion` ที่อ่านแล้วใน review session นี้; ตรวจ actual behavior ไม่อาศัย GREEN report เป็นข้อพิสูจน์แทนโค้ด

## Evidence / strengths

- **Real SDK read boundary:** `firestore_research_receipt_authority.dart:40–66` compose `auth.currentUser?.uid` แบบ live และ `.get(Source.server)` ที่ exact receipt path. รับ reference path และ snapshot cache/pending metadata จริง ไม่ใช้ default cached read. Test `firestore_research_receipt_authority_test.dart:365–409` ตรวจ factory options/path, metadata rejection และ auth เปลี่ยนระหว่าง server await
- **Current local authority ซ้ำหลัง await:** provider `152–177`, `199–246` ตรวจ UID ก่อน/หลัง reads และ query เดียว snapshot exactly one active owner พร้อม configured consent version/accepted state/decision/withdrawal. ผลก่อน–หลังต้องเท่ากัน; consent decision ต้องไม่เกิน evaluation time. เปลี่ยน owner binding, withdrawal, reaccept decision หรือ auth ระหว่าง await ไม่ใช้ approval เก่าต่อ. Tests `201–259` ตรวจ real in-memory DB state mutations ทั้งก่อนและระหว่าง read
- **Bounded exact receipt shape:** provider `109–115`, `178–197` รับ 6 fields สำหรับ consent หรือ 4 สำหรับ guardianPermission/learnerAssent เท่านั้น; kind/owner/active ต้องตรง, expiry เป็น bounded integer, consent version/decision ตรง local accepted record. ไม่มี raw answer/PII/extra authority fields. Tests `109–199` ตรวจทุก kind, missing/extra fields, wrong types/pins, absent/null/wrong-path/cache/pending/outage
- **Time/failure handling:** provider `76–81`, `118–143`, `167–177`, `199–208`, `268–272` จำกัด timeout บวกไม่เกิน 10s (default 5s), fail closed ทั้ง timeout/SDK/DB errors โดยไม่ log data. Late SDK result หลัง timeout ไม่เริ่ม local binding read ต่อหรือเปลี่ยนผลเป็น true. Expiry ต้องมากกว่า finish milliseconds; clock rollback/future evaluation/non-UTC ถูกปฏิเสธ. Tests `260–302`, `328–363` ตรวจ exact expiry, crossing during read, rollback, timeout และ late result
- **Read-only separation:** provider มีเพียง SELECT และ Firestore get; ไม่สร้าง/renew receipt, ไม่เปลี่ยน consent/permit, ไม่มี outbox/learning mutation หรือ ownership transaction คร่อม network. Signature/protocol/assignment/permit revocation ยังเป็นหน้าที่ validator/caller. Interface `research_participation_permit_validator.dart:16–23`, receipt invocations `74–105`, `185–200` สอดคล้องกับ provider. Rules context `firestore.rules:970–1010`, `1789–1791` ใช้ receipt owner/kind/active/expiry และ consent version/decision พร้อมห้าม client receipt writes

`withReader` เป็น explicit injected I/O trust boundary ตาม contract (`provider:9–15`, `68–100`), ไม่ใช่ cryptographic attestation. SDK factory เป็น normal composition path; review นี้ไม่รับรอง custom reader ของผู้เรียกอื่นหรือ runtime/bootstrap composition ที่อยู่นอก scope

## Exact scope / hashes

อ่าน product 273 lines และ test 486 lines ครบ. SHA-256 ของ reviewed full-file snapshots ตรงกันก่อน–หลังอ่าน

| Path จาก worktree | Scope | SHA-256 |
| --- | --- | --- |
| `lib/features/research/data/firestore_research_receipt_authority.dart` | ทั้งไฟล์ | `2A210D39BE1AB4BE1DECEE9CE12A4F25D6D2DD524CF1AB598564D13CA3A3C5ED` |
| `test/features/research/firestore_research_receipt_authority_test.dart` | ทั้งไฟล์; in-memory Drift + synthetic reader/SDK doubles | `07C5CA1E95C9F731D0134C830F6A0DA779C74849528146DFA0E5FA7B5A94A2BF` |
| `lib/features/research/application/research_participation_permit_validator.dart` | context-only: receipt interface/invocation/validator responsibility | `B25FF89C9DFF03300F54D37460F64941934541878202B879B07A770B95ABA357` |
| `firestore.rules` | context-only: receipt helpers/matches ที่ระบุข้างต้น | `90D7E02039EBB42094509939875113FA96587CED5B048FD7764B90FF5B8865A5` |

อ่านเพิ่มเติมเพียง enum `ResearchReceiptKind` ที่ `lib/features/research/domain/research_participation_permit.dart:7` เพื่อยืนยันสามชนิด; ไม่ขยายเป็น domain implementation review. Full-file SHA-256 context: `159D2D732B937EACE0E5479C0AA73FC8577101391813784733A1422A3FBA8B34`

## Verification / completion

MAIN/provider reported **72/72 GREEN และ clean two-file analyzer** ก่อน freeze. Reviewer ไม่รัน Dart/Flutter/tests/analyzer/scan หรือ external network; actual tests ที่อ่านเป็น synthetic SDK/in-memory DB ไม่ใช่ live Firestore/emulator verification. ไม่มีการยืนยันผลรัน 72/72 อย่างอิสระ

เสร็จสิ้น bounded review นี้; ไม่มี finding ที่ต้องให้ provider แก้. Write set มีเฉพาะ `.superpowers/sdd/research-receipt-authority-review.md`. ไม่แก้ห้าไฟล์ gateway/provenance รอบก่อน, adapter/authorizer P2, runtime clock, bootstrap หรือ prior reports; ไม่ commit/create task และไม่มี reviewer-owned process ค้าง. Runtime clock 2 behavioral RED → 11 GREEN เป็น MAIN-reported งานแยก ไม่อยู่ใน verdict; ไม่ปิด P2 overall หรืออนุญาต production enrollment/upload
