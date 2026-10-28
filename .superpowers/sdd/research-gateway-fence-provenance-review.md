# Focused independent re-review — gateway fence / typed provenance

**Verdict: Approve เฉพาะ P1 transaction-race fix และ additive typed provenance ใน scope ด้านล่าง.** ไม่พบ actionable finding ใหม่จาก static source/test review. ปิด P1 เดิมในขอบเขตนี้ได้; **ไม่ปิด P2 historical-delivery recovery โดยรวม** เพราะ adapter/authorizer ยังอยู่ระหว่างการแก้ของ Mencius และไม่ได้เปิดอ่านในรอบนี้

Worktree `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`; branch `feature/adventure-research`; HEAD/base `6968ce97ff9b383e244b17b77cf0ed0f61eaaf3d`. อ่าน current AGENTS.md และ current `requesting-code-review` + `code-reviewer.md`, `receiving-code-review`, `verification-before-completion` แล้ว. ใช้กรอบเหล่านี้ตรวจ actual control flow และแยก inspected evidence ออกจาก reported GREEN; ไม่ dispatch task/agent ใหม่

## Evidence / strengths

- **P1:** `firestore_sync_gateway.dart:113–121` เรียก fresh authority และตรวจ Firebase UID หลัง authority await. Callback แต่ละ transaction retry ตรวจตอนเข้า (`240`), หลัง operation read (`241–242`), และหลัง entity read (`252–256`), ก่อน synchronous staging ทั้งสอง writes (`278–291`). จึงไม่มี network read ที่คั่นระหว่าง final validation กับ staging เหมือน finding เดิม. Permit read-only branch ตรวจซ้ำหลัง server read (`199–215`)
- **Behavioral regression source:** `research_gateway_transaction_fence_test.dart:13–76` เข้า gateway transaction จริงผ่าน SDK-shaped test double ไม่ใช่ preflight sentinel; ครอบคลุม consent หลังแต่ละ read, owner-fence denial, Firebase เปลี่ยนหลัง read/ระหว่าง final authority และ callback retry. Driver (`210–227`, `301–323`) แยก staged/committed writes; success ตรวจสอง writes และ denial ตรวจไม่มี commit (retry ตรวจ `[2, 0]`)
- **Provenance creation:** gateway helper `124–138` ตรวจ auth UID และ reject cache/pending metadata ก่อนติด marker; conflict path `264–274` ใช้ transaction snapshot; pull `464–487` ใช้ `Source.server`, ตรวจ query metadata/UID และตรวจ document metadata แต่ละรายการ. Permit server read ใช้ helper เดียวกัน. ไม่มีการติด marker จาก codec decode
- **Binding:** `sync_entity.dart:1654–1764` เพิ่ม nullable typed marker, private constructor, SHA-256 ของ canonical sorted nested payload และ identity/UID binding; `matchesEntity` ตรวจ revision/tombstone/payloadVersion/client/server timestamps ด้วย. Nested mutation ทำให้ fingerprint ไม่ตรง; map order ไม่มีผล. `research_sync.dart:36–58` ส่ง marker เป็น process-local typed field แยกจาก payload; push request ของ gateway (`94–106`) ไม่ส่ง marker เป็น upload authority
- **Codec boundary:** `firestore_sync_gateway.dart:833–865`, `868–897`, `1006–1018`, `1271–1280` ยังใช้ explicit wire fields; decoder คืน `SyncEntity` ที่ไม่มี marker และ research envelope ปฏิเสธ unknown keys. Marker จึงไม่ได้ถูกสร้างหรือ serialize โดย JSON codec
- **Provenance tests:** gateway test `78–144` มี 8 conflict/pull × server/cache/pending/UID-changed cases และยืนยัน codec-only decode ไม่มี marker. `sync_server_read_provenance_test.dart:22–98` ตรวจ default absence, explicit creation, binding mismatch, nested content mutation และ map-order independence

Trust interpretation: marker นี้เป็น process-local transport provenance ตามที่อนุมัติ ไม่ใช่ cryptographic signature/capability หรือสิทธิอัปโหลด. `withServerReadProvenance` เป็น public API ที่ trusted gateway ต้องเรียกตาม contract; private constructor ไม่ได้ทำให้ application code อื่นเรียก public method นี้ไม่ได้. ใน production call sites ที่อยู่ใน scope นี้ gateway ติด marker เฉพาะหลัง authenticated committed server read. Current consent/signed permit/pins และการใช้ marker ฝั่ง adapter/authorizer ต้องตรวจแยกต่อไป; ไม่ถือว่า marker เพียงอย่างเดียวพิสูจน์ P2 closure

## Exact reviewed scope / SHA-256

Hashes ด้านล่างคือ full-file snapshots ที่อ่านสำหรับ verdict นี้. Gateway, sync_entity และ gateway test ยังคง hash เดิมตอนปิด review. ResearchSyncRequest/marker-test file มี clock-only งานใหม่ระหว่าง handoff ตาม scope update ด้านล่าง; ไม่รวม clock change ใน verdict. Review จำกัด changed fence/provenance paths และ context ที่เกี่ยวข้อง ไม่ใช่ full sync review

| Path จาก worktree | Reviewed scope | SHA-256 |
| --- | --- | --- |
| `lib/features/sync/data/firestore_sync_gateway.dart` | research authority/transaction reads + staging; server provenance creation; pull/conflict/permit read paths; codec boundaries | `3F031CCAD6131034778C1D28508A36B3C465D3CB97A8DC4C9AE72762C869D428` |
| `lib/features/sync/domain/sync_entity.dart` | additive SyncEntity/SyncServerReadProvenance API + validation helpers; scoped diff context | `9C5B60E90D8BCA4A213EE7A67CE23BC3779FA8CFA3404A40B105986A59DD34F5` |
| `lib/features/sync/domain/research_sync.dart` | typed request field + structural contract context; ไม่ตรวจ changing adapter/authorizer | `C39257C5BF922469524F788BE1C98EA13210B77B2E2D091BA921941262614260` |
| `test/features/sync/research_gateway_transaction_fence_test.dart` | ทั้งไฟล์ 367 lines | `8447B3304EBA6B9F6A44097A2C6475A964CA7D39CF6993BE71BF5A12D462D3A8` |
| `test/features/sync/sync_server_read_provenance_test.dart` | ทั้งไฟล์ 98 lines | `92A59F17ABDF6577E5F79EFD8DF33E3E2A50DBFE0CA3B00107061AA541E54229` |

## Verification / handoff limits

MAIN reported: P1 +2/−5 RED → 57 GREEN; missing marker API RED → 3 GREEN; 8 gateway provenance cases +11/−7 behavioral RED → combined 68/68 (existing 50 + gateway 15 + marker 3); fresh five-file analyzer no issues หลัง mechanical format. Reviewer อ่าน actual production paths และ tests แต่ **ไม่ได้รัน** Dart/Flutter/tests/analyzer/formatter/scans หรือ external service calls และไม่รับรองผลรันดังกล่าวอย่างอิสระ

Write set มีเฉพาะรายงานฉบับนี้. ไม่แก้ product/test/prior reports, ไม่ commit/create task, ไม่มี reviewer-owned process ค้าง. ขั้นต่อไปเป็น P2 adapter/authorizer integration review เมื่อ writer freeze และ MAIN อนุญาต; ไม่ใช่ production-readiness/enrollment/upload approval

## MAIN scope update during handoff — clock work excluded

MAIN แจ้ง raw system-clock microseconds กับ strict research UTC-millisecond composition defect และกำลังเพิ่ม process-local `ResearchSyncRequest.evaluatedAtUtc` canonicalization จาก valid nonnegative UTC เป็น floor milliseconds โดยไม่เปลี่ยน payload/signature. Clock change/new clock test และ bootstrap/runtime-fromConfig adaptation **อยู่นอก review นี้**; สถานะ RED/GREEN ยัง pending ตามข้อความ MAIN ไม่ได้ตรวจหรือรันยืนยัน

Hash check ล่าสุดพบ `research_sync.dart` เปลี่ยนเป็น `FF091A27433721AC47F7F055DF00A7E2C34BD9518523AE963C37A99BE6D53F5A` และ `sync_server_read_provenance_test.dart` เป็น `CE096A2E55DA3BF0A8DF22CE7FA559C123727CC0E3966EF39AF40F1B241649B5`. สอง hash นี้เป็น observed changing snapshots ไม่ใช่ reviewed/approved clock evidence; refs และ test counts ด้านบนอ้าง reviewed snapshots ในตาราง. Gateway/fence/provenance verdict ไม่ขยายเป็นการ approve clock composition หรือ P2 overall
