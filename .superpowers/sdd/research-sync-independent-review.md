# Independent review — R4 research sync

ผล: **With fixes — P1 หนึ่งข้อ, P2 หนึ่งข้อ**. เป็น static review จาก actual source/tests ไม่ใช่ผลรัน reproduction. แจ้ง MAIN ทั้งสองข้อระหว่างตรวจแล้ว; reviewer ไม่แก้ product/test

Worktree `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`; branch `feature/adventure-research`; HEAD/base `6968ce97ff9b383e244b17b77cf0ed0f61eaaf3d`. ตรวจ dirty/untracked implementation ตาม approved R4 plan และ latest bounded request. ใช้ `requesting-code-review` + `code-reviewer.md`, `receiving-code-review`, `systematic-debugging` สำหรับการไล่ async/recovery boundaries และ `verification-before-completion` เพื่อแยก inspected evidence ออกจาก reported GREEN

## Findings

### 1. P1 — ตรวจ research authority อีกครั้งหลัง transaction reads ก่อนเขียน

**Primary:** `lib/features/sync/data/firestore_sync_gateway.dart:197–215` (authorization ล่าสุดอยู่ `185–186`; write อยู่ `215–228`).

Gateway ตรวจ local authority ก่อนอ่าน operation และ entity แต่ทั้งสอง read เป็น asynchronous. ถ้า local consent ถูกถอนระหว่าง read, callback เดินต่อไป `transaction.set` โดยไม่ตรวจ owner/fence/consent/permit อีกครั้ง. Ordinary Sync lease ไม่ได้ล็อก local withdrawal: actual integration test `test/features/research/research_runtime_sync_integration_test.dart:493–501` เรียก runtime withdrawal ขณะถือ lease และยืนยันว่า deny-marker enqueue ต้องรอ gate. ดังนั้น ณ ขณะนี้ backend ยังมี active receipt และไม่มี withdrawal marker (`firestore.rules:983, 1004–1006`); rules จึงไม่ได้ปิดช่อง local race นี้

**Reproduction สำหรับ MAIN (ยังไม่ได้รัน):** ใช้ valid coded-response mutation ที่ beginAttempt สำเร็จและ remote parent/authority พร้อม; ให้ gateway ผ่าน `_authorizeResearch` ที่ต้น transaction แล้วหน่วง `transaction.get(entity)` หลัง operation lookup ไม่พบ receipt. เรียก `runtime.withdraw(owner)` ให้ commit ขณะ ordinary sync lease ยังอยู่ โดยยังไม่ส่ง deny marker จากนั้นปล่อย entity read. Current code เรียก entity/operation `set` ทั้งคู่ แม้ fresh authorizer จะคืน false. ควรยืนยัน zero staged/committed research writes หลัง withdrawal นี้; ทำ delayed-read owner-fence case เพิ่มได้ในเทสต์เดียวกันแบบ parameterized

**Recommendation:** คง preflight/transaction-entry checks และเพิ่ม fresh research authorization + current Firebase binding check หลัง network reads ทันที ก่อน staging writes ภายใน transaction callback (รวมเมื่อ Firestore retry callback). ห้ามใช้ global Sync lease บล็อก withdrawal/ordinary learning. เทสต์ปัจจุบันตรวจ race ภายใน receipt lookup (`research_sync_authorizer_test.dart:357–435`) และระหว่าง claim/reservation แต่ยังไม่ครอบคลุม network-read gap นี้; integration `checkDelivery:211–229` ใช้ transaction sentinel ไม่ได้เข้า gateway transaction จริง

### 2. P2 — Signed renewal ทำให้ lost-ACK event recovery และ historical pulls ค้าง

**Primary:** `lib/features/sync/data/drift_research_sync_adapter.dart:173–175` (ใช้ current permit-reference equality กับ pull ด้วย). Related: `111–119`, `232–242`, `337–340`, `479–481`; `lib/features/research/data/drift_research_sync_authorizer.dart:153, 649–654` ใช้ reference equality เช่นกัน

เมื่อ server รับ event ด้วย permit revision 1 แต่ ACK หาย แล้ว local permit ต่ออายุเป็น revision 2, adapter สร้าง operation identity ใหม่จาก wrapper ใหม่. Operation เก่า retry ไม่ผ่าน current snapshot identity. Gateway หา receipt ของ operation ใหม่ไม่พบและพบ event revision 1 แทน base 0 จึงคืน conflict (`firestore_sync_gateway.dart:187–212`). Store ส่ง cloud event wrapper revision 1 เข้า `_research.apply` (`drift_sync_store.dart:1153–1155`) ซึ่งปฏิเสธ stale permit reference ก่อนตรวจว่า immutable event envelope ตรงกัน และโยน retryable ProviderUnavailable. ไม่มีเส้นทาง acknowledge delivery เดิม; retry/pull จะชนเงื่อนไขเดิมต่อไป

**Reproduction สำหรับ MAIN (ยังไม่ได้รัน):** capture Presented; ส่ง event mutation E1 จน remote event+operation commit แต่ไม่ acknowledge local outbox (จำลอง lost ACK). Import authentic permit revision 2 ทั้ง local/trusted remote โดยไม่แก้ event ที่ create-once. Recover queue แล้ว claim E2 ซึ่งมี envelope เดิมและ wrapper ใหม่. ให้ gateway คืน existing remote E1 เป็น conflict หรือป้อน E1 ใน pull page: current adapter ปฏิเสธ refs และไม่ปิด outbox/checkpoint. ควรได้หนึ่ง immutable event เท่าเดิมพร้อม durable delivered reconciliation ไม่ใช่งาน retry ถาวร. แม้ ACK เดิมไม่หาย historical run/response/event wrappers ที่ถูก pull หลัง renewal ก็ชน current-reference check เดียวกัน

**Recommendation:** แยก new-upload authority จาก trusted historical-delivery reconciliation. พิสูจน์ current owner/consent/permit/pins ตามเดิม แล้ว reconcile receipt/immutable fact ที่ส่งสำเร็จก่อน renewal ด้วย identity/envelope ที่ตรงจริง; อย่ารับ conflicting pins, อย่าอัปโหลดด้วย stale authority, อย่าแก้ signed permit หรือ create-once event. ให้ historical pull อยู่ภายใต้ policy เดียวกันโดยไม่ข้าม failed checkpoint. Backend ตั้งใจเก็บ historical parent wrappers (`firestore.rules:1049–1052`) และห้าม event/response update (`1818–1823`, `1833–1838`) จึงแก้ด้วยการ rewrite cloud wrapper ไม่ได้

**Existing test boundary:** `research_measurement_sync_test.dart:224–255` ครอบคลุม renewal ก่อน beginAttempt และกรณี ACK แล้วเท่านั้น; `research_runtime_sync_integration_test.dart:633–685` ใช้ held claims + preflight sentinel; rules test `firestore-rules.test.cjs:242–272` ตรวจ new delivery หลัง renewal ไม่ใช่ delivery ก่อน renewal ที่ ACK หาย

## Reviewed scope / source hashes

SHA-256 ของไฟล์เต็ม (line refs อ้าง snapshot นี้); rechecked ก่อนเขียนรายงานและยังตรง initial read. Formatter ภายหลังอาจเปลี่ยน hash/lines โดยไม่ได้เปลี่ยน semantics

| Product path จาก worktree | ขอบเขตที่ตรวจ | SHA-256 |
| --- | --- | --- |
| `lib/features/sync/domain/research_sync.dart` | ทั้งไฟล์ | `02758A16C5EC47AA4D6A7C9560D35B50B122841E735697DB8985FF0FE187DFF1` |
| `lib/features/sync/data/drift_research_sync_adapter.dart` | ทั้งไฟล์ | `5A9FAA38957D36F75253C251E3A8CA855213CF537EC880941592A759F341BC08` |
| `lib/features/research/data/drift_research_sync_authorizer.dart` | ทั้งไฟล์ | `339E49B5F06F8AB520ECD894ADF41C930AAE587DBAF37C53489C3CAC1F96C7DF` |
| `lib/features/sync/data/firestore_sync_gateway.dart` | research rollout/auth/push/pull/preflight, withdrawal, permit ACK, codec/envelope/operation linkage; ไม่ review ordinary collection policies | `B99DAA7BC3CD36BE3467F76ADF172EBFBD360DD5B499133A161D99AB991B1D4F` |
| `lib/features/sync/data/drift_sync_store.dart` | research enqueue/claim priority/beginAttempt/ACK/conflict/applyPull/checkpoint integration เท่านั้น | `407F2CE3D3383135B658DDA355800F6C0497C3BC6951A1341CE0EEEAB1845E26` |
| `lib/features/sync/application/sync_engine.dart` | existing lease, send, retry, research pull order/failure/checkpoint integration `105–397` | `58A39E43E06E15AB4255B5FEFDFF45C2E13A44F214B13888B4DC0D127E1B075C` |
| `firestore.rules` | research helpers `963–1190`, research matches `1781–1838`, reciprocal operation dispatch + shared envelope/auth/link helpers ที่จำเป็น | `90D7E02039EBB42094509939875113FA96587CED5B048FD7764B90FF5B8865A5` |

ไม่พบ actionable finding เพิ่มใน bounded pass: authorizer แยก true owner fence จาก ordinary leaseและ snapshot local dependencies ซ้ำหลัง authority await; cutoff pull ต้องเป็น authentic known monotonic update รักษา immutable pins; unknown inactive permit ไม่สร้าง enrollment; rollout default-off/exact revision/actual emulator host; withdrawal เป็น create-once deny-only ผ่าน existing outbox และไม่ต้องมี active research authorizer; permit/receipt/authority ไม่มี client-write branch. Research adapter ไม่สร้าง learning/reward projection authority และ permit references อยู่ transport wrapper ไม่เพิ่มลง frozen event envelope. ข้อนี้ไม่ใช่การ approve สอง gaps ด้านบน

## Actual tests / plan inspected, not executed

| Test / document | ขอบเขตอ่าน | SHA-256 |
| --- | --- | --- |
| `test/features/sync/research_measurement_sync_test.dart` | ทั้งไฟล์ | `267D881685FD0207883CB70441A57FC1FDAC725AAE277E7B7E19DAB1C8964B95` |
| `test/features/sync/research_sync_contract_test.dart` | ทั้งไฟล์ | `568F587E89C8551B24CCAABA3C092EE3EB28C5E0FF44DF78B781B46CFCDED99C` |
| `test/features/sync/firestore_sync_gateway_test.dart` | research injection/default-off และ test discovery ในไฟล์นี้เท่านั้น | `D1DDA5DDE6D9FABABBD1FA5799AFADE6525F91FCDFCA4A3175747B12B5A1FF6E` |
| `test/features/research/research_sync_authorizer_test.dart` | setup; phase/owner/fence/async-boundary, coded response, signed cutoff/renewal/minor/forgery/no-write, four-event cases (`1–106`, `272–436`, `538–885`, `940–999`) | `F64B1D2706C8E02A25DF22D5197AF4C9059FA8292D17CBED2EE47E58A1D5AEB1` |
| `test/features/research/research_runtime_sync_integration_test.dart` | setup/delivery helper, enqueue/claim integration, withdrawal/renewal/recovery/forgery (`40–101`, `143–241`, `292–354`, `480–733`) | `3839280C1F09D27A17A86F91F369E8BAE98A3B87F3514D875A5D9B0727B37848` |
| `test/security/firestore-rules.test.cjs` | research fixtures/tests `32–304`, auth helper | `1D9CF2FB17E1B0EB4C4783B7985F3750EF4E827FD12FCD28A8778F37A785CCC5` |
| `docs/superpowers/plans/2026-09-05-adventure-research-implementation.md` | approved plan; R4 acceptance focus | `36479B6E5ADCD03BF088697623B5BA63C4E7400AE641402AEF1D98709D196843` |

MAIN/worker reported: R4 seven-file 209/209 GREEN, rules 123 GREEN, real authorizer 98 GREEN; runtime→real P256→store integration 8 เป็น next/pending ตามข้อความตอนเริ่ม review. Reviewer ไม่ได้รันหรือรับรองผลดังกล่าวบน snapshot นี้. ไม่มี Dart/Flutter/test/analyzer/formatter/scan/external calls; ไม่มี product/test edits, commits, new tasks หรือ reviewer-owned process ค้าง

Host follow-up เป็น deliverable แยก: เพิ่ม status ปิด P2 ทั้งสองใน `research-runtime-host-independent-review.md` เท่านั้น. Write set รอบนี้มีเพียงสอง review reports. ขั้นถัดไปที่ MAIN ทำได้: เพิ่ม delayed-transaction-read withdrawal regression และ delivered-but-unacknowledged-before-renewal recovery regression แล้วแก้ใน writer slot ของตน. ไม่อ้าง production readiness หรืออนุญาต enrollment/upload
