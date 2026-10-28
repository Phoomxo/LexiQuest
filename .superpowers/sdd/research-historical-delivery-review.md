# Independent P2 historical-delivery review

วันที่ 2026-09-05 — **APPROVE เฉพาะ scope ด้านล่าง**; ไม่พบ actionable finding คงเหลือ ปิด P2 lost ACK + signed renewal จาก `research-sync-independent-review.md` โดยตรวจ actual source/tests ไม่ใช้ผล GREEN แทนการอ่านโค้ด

Worktree: `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`  
Branch: `feature/adventure-research`  
HEAD/base: `6968ce97ff9b383e244b17b77cf0ed0f61eaaf3d` (implementation ยัง uncommitted/untracked)

## Scope และผลตรวจ

- Primary: `lib/features/sync/data/drift_research_sync_adapter.dart`, RESEARCH branches ของ `lib/features/sync/data/drift_sync_store.dart`, `lib/features/research/data/drift_research_sync_authorizer.dart`; อ่าน tests `test/features/research/research_sync_authorizer_test.dart` และ `test/features/research/research_runtime_sync_integration_test.dart` รวม fixture/helper ภายในสองไฟล์นี้
- Context เท่านั้น: renewal/ACK/checkpoint cases ใน `test/features/sync/research_measurement_sync_test.dart`; typed-marker contract ใน `sync_entity.dart`; research authorization/server-read boundary ใน `firestore_sync_gateway.dart`; `ResearchSyncRequest`/reference contract ใน `research_sync.dart`
- Clock composition แบบจำกัด: `AdventureResearchRuntime.fromConfig` บรรทัด 28–77 และ bootstrap บรรทัด 835–894 ไม่ได้ review bootstrap ทั้งไฟล์
- ไม่ขยายไป capture/Host/provider/learning/sync ส่วนอื่น ไม่แก้ production/test code และไม่รัน Dart/Flutter/tests/analyzer/scanner/network

### หลักฐานปิด P2

1. **แยก delivery proof ออกจาก upload authority.** Adapter `455–501` และ authorizer `333–406` ยอมรับ wrapper เก่าเฉพาะ pull, permit ID เดิม, revision บวกและต่ำกว่าปัจจุบัน: unmarked history ต้องตรงกับ local fact ทุก field ที่ไม่ใช่ wrapper และมี exact durable outbox admission identity; unknown history ต้องมี marker ตรง UID/collection/entity/payload ไม่ใช่เพียง hash รูปแบบถูกต้อง การ enqueue/claim/push ด้วย wrapper เก่ายังถูกปฏิเสธ ดู authorizer tests `554–637` และ `439–463`
2. **Lost ACK ไม่กลายเป็น conflict loop หรือ event upload ซ้ำ.** Adapter `774–785`, `880–952` บันทึก delivery เมื่อ fact ตรงกัน โดย ACK เฉพาะ incoming operation และ current-wrapper twin ที่ fact revision เท่ากัน; event ที่ import บนเครื่องใหม่สร้าง acknowledged ledger row ถาวรด้วย outbox เดิม (`907–925`) ไม่แก้ envelope หรือ signed permit Store `1203–1252` ยังเทียบ claimed fact ทั้งก้อนและ revision ก่อนถือว่า conflict เป็น delivery Integration `772–923` จำลอง E1 commit/ACK หาย/renewal/E2 ทั้ง conflict และ pull พร้อมตรวจ E1 upload ถูกปฏิเสธ, E2 ACK และไม่เกิด event/remote fact ซ้ำ
3. **เครื่องใหม่คืนข้อมูลครบสี่ collection ตาม parent-first.** Run/response/opportunity/neutral event ผ่าน current authority และ dependency/pin checks ตามเดิม ก่อน insert/record delivery (`adapter:729–852`, `authorizer:165–330,472–704`) Integration `1047–1251` ใช้ database เครื่อง B แยกจาก A ไม่มี local facts/outbox proof เริ่มต้น: marked history คืนข้อมูลและ checkpoint ได้, unmarked history ถูกปฏิเสธ; สร้าง store ใหม่แล้ว claim ไม่ส่ง research facts ซ้ำและพบ event ACK ledger หนึ่งแถว ทั้งนี้เป็น synthetic server-boundary fixture ไม่ใช่ SDK/network E2E
4. **Marker bind outer entity และไม่ข้าม current authority.** Adapter `673–677,743–758` ตรวจ `matchesEntity` ก่อนส่งต่อและหลัง authorization; contract `sync_entity.dart:1737–1751` รวม revision/deletion/payloadVersion/client/server timestamps นอกเหนือจาก UID/collection/id/payload hash Authorizer `35–67,107–118,318–330,409–448` โหลด current owner/gate/fence/consent/assignment/permit/pins ก่อนและหลัง receipt await พร้อมตรวจ signature, expiry และ clock ปิดท้าย; ordinary Sync lease ไม่ใช่ owner fence Tests `authorizer:415–551,673–836` และ `integration:1253–1324` ตรวจ binding/races และ checkpoint rollback ที่เกี่ยวข้อง Marker เป็น process-local trust contract จาก gateway/server admission ไม่ใช่ cryptographic signature หรือสิทธิ์ upload
5. **ไม่มี checkpoint ข้าม failed delivery.** Adapter `750–753` throw เมื่อ authority ใช้ไม่ได้; store `1439–1457,1509–1524,1556–1570` ใช้ transaction เดียวสำหรับ apply/checkpoint Integration `985–1045` ตรวจ conflicting response ไม่ ACK/ไม่เปลี่ยน answer/ไม่ advance checkpoint ไม่มีการเพิ่ม learning-projection writes ในเส้นทาง P2
6. **Clock composition ผ่าน static review.** Runtime `38–46,59–73` floor เฉพาะ valid UTC/nonnegative process clock เป็น milliseconds และใช้ closure ร่วมกัน; bootstrap `864–869` ส่ง clock จาก runtime ให้ authorizer; `research_sync.dart:36–56` canonicalize request context เท่านั้น ไม่แก้ payload/signature และคง invalid/non-UTC/negative input ให้ถูก deny Integration `689–770` ใช้ raw clock +321µs ผ่าน genuine runtime/P-256/store/authorizer ตรวจ claim/reservation/push request พร้อมยืนยัน signed permit เดิมไม่เปลี่ยน

## Evidence และขอบเขตการอนุมัติ

ตรวจ source hashes ต้น/ท้าย review ตรงกันทั้งหมด ข้อมูลจาก MAIN/worker เท่านั้น: P2 RED 57 (`+44/-13`) → 57 GREEN, affected regression 191/191 รวม raw-clock case, final five-file analyzer no issues; MAIN clock 2 RED → 11 GREEN และ bootstrap 7 GREEN ผู้รีวิว **ไม่ได้รันหรือรับรองซ้ำ** ผลเหล่านี้ และไม่ได้รับรอง R6 full analysis/regression ที่ MAIN กำลังทำ

ผลนี้ปิด P2 ที่ค้างของ bounded research review และใช้ร่วมกับ prior reports: `research-capture-independent-review.md`, `research-runtime-host-independent-review.md` (รวมสถานะปิด Host fixes), `research-gateway-fence-provenance-review.md` (P1 + marker), `research-receipt-authority-review.md` ไม่ได้เปิด review ใหม่หรือรับรองทุกไฟล์ปัจจุบันนอก scope รายงานนี้ ไม่มี remaining actionable finding ใน pass นี้; ไม่ใช่ production/enrollment/upload authorization

## SHA-256 ของ snapshot ที่ตรวจ

Hash ของไฟล์ context เป็น whole-file identifier ไม่ได้หมายถึง review ทั้งไฟล์

```text
6CA7B15C7F0230EAC2A7B9B735A26603C15934B68CCC5D2106D728186F31CE77  lib/features/sync/data/drift_research_sync_adapter.dart
24CD3DC7706B1BF2911E23AEED24E0BF9BB1AB1DE72BACC3F7B23EF404D233AD  lib/features/sync/data/drift_sync_store.dart
5FD896444B625210FCB2F429E342002708C2CFEB7022484DB56CBECA5E7751D4  lib/features/research/data/drift_research_sync_authorizer.dart
E45C6FE4442EB2B80A6119376279AECC19BE09C05709DB24AC94EA81EE42995D  test/features/research/research_sync_authorizer_test.dart
89AB3D2986E921E176C2302D1D2B6A2E84E00DA8189965E8C8C2C382F7D4EFE1  test/features/research/research_runtime_sync_integration_test.dart
267D881685FD0207883CB70441A57FC1FDAC725AAE277E7B7E19DAB1C8964B95  test/features/sync/research_measurement_sync_test.dart
9C5B60E90D8BCA4A213EE7A67CE23BC3779FA8CFA3404A40B105986A59DD34F5  lib/features/sync/domain/sync_entity.dart
FF091A27433721AC47F7F055DF00A7E2C34BD9518523AE963C37A99BE6D53F5A  lib/features/sync/domain/research_sync.dart
3F031CCAD6131034778C1D28508A36B3C465D3CB97A8DC4C9AE72762C869D428  lib/features/sync/data/firestore_sync_gateway.dart
49B19BA28A52E8950EA62931D31E47296BAA77BC9AF9D0758916B5A58294FE31  lib/features/research/application/adventure_research_runtime.dart
4708A7BC0A1F13C4C7C7FD6BA04E993FA75DA1B36A9F1612DBCFA3ED3BA67EBC  lib/runtime/app_bootstrap.dart
```
