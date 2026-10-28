# Independent review — R2/R3 capture data integrity after SQL guard fix

ผล: **Approve สำหรับ bounded static review นี้** — ไม่พบ actionable finding ใน product files 6 ไฟล์ที่ตรวจ ไม่มี Critical / Important / Minor finding และไม่มีข้อเสนอแก้โค้ดจากรอบนี้

## ขอบเขตและ source snapshot

- Worktree: `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`
- Branch: `feature/adventure-research`
- HEAD / base: `6968ce97ff9b383e244b17b77cf0ed0f61eaaf3d`
- ตรวจวันที่ 2026-09-05; hash checkpoint เวลา 14:39 Asia/Bangkok
- Implementation ยังเป็น uncommitted/untracked จึงอ่านไฟล์จริงทั้งหมดใน product scope และตรวจ tracked diff เทียบ HEAD; commit-to-commit diff ว่างไม่ใช่หลักฐานของ implementation
- อ่าน `AGENTS.md`, approved plan `docs/superpowers/plans/2026-09-05-adventure-research-implementation.md` ทั้งฉบับ และ historical checkpoint `docs/development/2026-09-05-research-paused-checkpoint.md`
- ใช้ `requesting-code-review/SKILL.md` และ `code-reviewer.md` เป็นกรอบ independent review; อ่าน `receiving-code-review/SKILL.md` เพื่อประเมินข้อแก้ไขเดิมกับโค้ดจริง และใช้ `verification-before-completion/SKILL.md` ตรวจหลักฐานก่อนสรุป ไม่ dispatch agent หรือสร้าง task เพิ่ม
- อ่าน `.superpowers/sdd/research-schema-review-fixes.md` เพื่อระบุ prior fix/test evidence หลังจากอ่าน actual guard และ repository code; ไม่ใช้รายงานนั้นแทนการตรวจโค้ด
- Product read-only; ไฟล์ที่เขียนในรอบนี้มีรายงานฉบับนี้เท่านั้น ไม่มี implementation/test edits, commit, production operation หรือ process จากการรันเทสต์

Product files ที่อ่านครบ พร้อม SHA-256 (ตรงกันระหว่างก่อนและหลังตรวจ):

| ไฟล์ — path สัมพัทธ์จาก worktree ข้างต้น | SHA-256 |
| --- | --- |
| `lib/data/local/research_schema_guards.dart` | `0383195AB5D429A157638A595EEE0FAA46D8BDC908AEF0C88B167CB106DC70FC` |
| `lib/data/local/tables/research_tables.dart` | `E1D67EDA052A338AA05B8277194A2D8D91C0AAFC1763135DB2A9C837007EBA69` |
| `lib/features/research/data/drift_motivation_measurement_repository.dart` | `78618EA0BA599C3E963B0A93D216A7B5D59A700C6345ACDCE51B828700C3A441` |
| `lib/features/research/data/drift_measurement_opportunity_repository.dart` | `54A7AAD85A8891706000C54AB082C1DA9A7C6DB086F9495351CB40029F9F31D3` |
| `lib/features/research/data/drift_research_participation_repository.dart` | `2706249E48298C5BAB3FE241A5D4F950625348303D1CD07E7A291822D36AB3C7` |
| `lib/features/consent/data/drift_research_consent_repository.dart` | `EBCD4AAADCE1F8E4D64C36EADA0AFA23AA630CF1880C9DD33E76AC706F777376` |

ขอบเขตใน `research_tables.dart` คือ shared metadata และ 4 ตารางใหม่ บรรทัด 70–221; อ่าน declarations เดิมบรรทัด 1–68 เพื่อเข้าใจ assignment/session references แต่ไม่ขยาย review ไป subsystem เดิม

## หลักฐานและผลตรวจ invariants

เลขบรรทัดด้านล่างอ้างถึง source hashes ข้างต้น คำว่า “ตรวจ” หมายถึง source inspection ไม่ใช่ test execution

| ประเด็น | หลักฐานจาก actual code / tests และผลตรวจ |
| --- | --- |
| Current owner และ owner fence | `drift_research_participation_repository.dart:40` ทำ owner write fence ตรวจ active owner ต้องมีคนเดียวและเรียก `isOwnerFenced` ที่บรรทัด 55–57; ในไฟล์นี้ไม่มีการปฏิเสธ capture เพียงเพราะมี ordinary outbox/sync lease. ตัว implementation ของ gate อยู่นอก product scope จึงไม่ถือว่าได้ตรวจ internals ของ gate ซ้ำ |
| ตรวจ authority ซ้ำหลัง await | Participation บรรทัด 123–130 ตรวจเวลาหลัง async validation; import บรรทัด 185–197 อ่าน consent/assignment ซ้ำ เทียบ permit row กับ snapshot และ lock owner อีกครั้ง; capture บรรทัด 262–284 เทียบ permit row ใหม่และอ่าน local context ใหม่. Measurement บรรทัด 84–105 อ่าน state และ pins หลัง authority await; record บรรทัด 116–117 โหลด responses/timing ใหม่; opportunity บรรทัด 118–125 ทิ้ง snapshot ก่อน await และตรวจ linkage ใหม่ |
| Closed run และ coded responses | Measurement บรรทัด 37–39 คืน existing run โดยไม่ reopen; บรรทัด 94–105 ปฏิเสธ run ที่ไม่ started; close บรรทัด 174–184 ป้องกัน reopen และตรวจ active run สำหรับ terminal states ที่ไม่ใช่ withdrawal. Record บรรทัด 118–163 resolve item/response จาก catalog, ปฏิเสธ changed-answer retry และ persist code/ordinal/catalog version แทน free text. Test `drift_motivation_measurement_repository_test.dart:114` ครอบคลุม skip/restart/response denial |
| Baseline/post และเวลา | Measurement บรรทัด 133–145 ปฏิเสธ baseline หลัง exposure และให้ post อยู่ในช่วง completion ถึง completion+30m รวมปลายช่วง; บรรทัด 246–277 reconstruct exposure กับ canonical session จาก committed rows. Opportunity tests บรรทัด 297–313 มี exact +30m acceptance, 419–441 มี +30m+1ms denial, 364–381 มี subsecond exposure/reload, 384–412 มี baseline เกิน 24h แล้วยังคง denominator แต่ primary analysis ineligible. Formula 24h อยู่ใน domain model นอก product scope: ไม่อ้างว่าได้ตรวจ implementation สูตรนั้นหรือ exact 24h±1ms ซ้ำในรอบนี้ |
| First accepted index | Measurement บรรทัด 264 เลือก first linked canonical session ด้วย `ORDER BY s.started_at_utc_ms,e.event_id LIMIT 1` ก่อนตรวจ `state == completed` ที่บรรทัด 273–279. ไม่ filter เฉพาะ completed ก่อนเลือก index. Opportunity test บรรทัด 317–348 ยืนยัน expected behavior เมื่อ session แรกยังไม่จบแต่ session หลังจบแล้ว |
| One UUID / denominator / switch facts | Opportunity บรรทัด 34–46 ตรวจ UUID v4 และ deterministic owner/run/permit/entry identity; schema บรรทัด 208–210 มี unique denominator. บรรทัด 167–189 ตรวจ expected revision, บันทึก ordinal 1–10 แล้วเพิ่ม suppression count สำหรับครั้งถัดไป; update บรรทัด 354–363 มี revision CAS. Event และ linkage update อยู่ transaction เดียวกัน; open เป็น transaction แยกก่อน Presented. Tests บรรทัด 116–154 และ 185–223 ครอบคลุม retry, event insertion failure และ concurrent stale switch retries |
| Neutral events / learning projections | Opportunity บรรทัด 403 ใช้ payload policy และ 412–443 สร้าง existing `EventEnvelopeV2`; บรรทัด 444–472 insert เฉพาะ neutral EventsV2 fact โดยไม่เรียก learning event store ที่ rewind projection cursors. ไม่มี learning/reward/projection writes ในไฟล์นี้. Tests บรรทัด 156–182 ตรวจ bounded Presented payload สำหรับ Standard/Adventure. Frozen 22-key serializer และ policy definition อยู่นอก scope; ไม่อ้างว่าได้ตรวจ serializer ทั้งฉบับหรือ runtime projection behavior ซ้ำ |
| Withdrawal preserves evidence / blocks outbox | Consent บรรทัด 86–120 เปลี่ยน run/opportunity lifecycle โดยเก็บ original completion timestamp และ responses; ไม่มี permit update. บรรทัด 131–184 จำกัด owner/version/entity และยกเลิก matching upsert leases รวม 4 research entity types และ neutral events ทั้ง `eventsV2`/typed names. Delete operations, unrelated learning และ other-version runs ไม่เข้าเงื่อนไข. Lifecycle tests บรรทัด 338–400, 404–530, 534–569 และ 573–707 มี preservation, lease invalidation, atomic rollback และ exact typed neutral suppression assertions |
| SQL parent pins / receipt restrictions หลัง fix | Guard บรรทัด 41–65 ใช้แยก INSERT/UPDATE triggers ตรวจ ASCII receipt 1–128 ตัว, NULL rules และ embedded NUL. บรรทัด 68–115 คุ้มครอง referenced run/permit/assignment/session pins รวม tombstoned children ด้วย null-safe `IS NOT`. Permit immutable list ตรงกับ repository `_sameImmutablePins` บรรทัด 331–347. Signed revision/expiry/revocation/issuer/hash/signature และ acknowledgement/lifecycle fields ไม่ถูก freeze โดย guard. Migration tests บรรทัด 260–689 ตรวจ rejection ด้วย constraint code 19 และ snapshot preservation, lifecycle full-row updates, ordinary unreferenced rekeys และติดตั้งเพิ่มบน v24 ที่มี legacy triggers อยู่แล้ว |

## Findings

ไม่มี finding ที่ยืนยันได้ใน product scope ที่กำหนด จึงไม่มี severity/line/reproduction/recommendation entry สำหรับ defect และไม่มีคำขอแก้โค้ดจาก review นี้

SQL fix ใช้ชื่อใหม่เพิ่มจาก 8 guards เดิม ไม่เปลี่ยน legacy predicates และใช้ค่าจริงเปรียบเทียบ pins ทำให้ full-row permit import ที่ส่ง immutable fields เดิมยังผ่าน predicate ได้ ส่วน withdrawal แก้เฉพาะ lifecycle fields จึงไม่ชน referenced-parent guards

## Test source ที่ตรวจ

ค้นหาด้วย `rg`; อ่าน source ของ 7 test files และ 1 shared fixture ด้านล่างทั้งหมด ไม่ได้รันเทสต์:

| ไฟล์ | SHA-256 ณ review checkpoint |
| --- | --- |
| `test/database/migration_v23_to_v24_test.dart` | `5102CF74D0BCE74F871B30737281D0E10CF59D5793B80B46B2A318DEAD65F673` |
| `test/features/research/drift_motivation_measurement_repository_test.dart` | `CFE2CF7587FB43E70C8944C3703C4C35EF26E0835B13204329AED19B40EDB78F` |
| `test/features/research/measurement_opportunity_repository_test.dart` | `7BDC222853FF1FE903FBE3CB5AFB7116C8F30DB5499F68C3356AD87125123FC9` |
| `test/features/research/research_participation_lifecycle_test.dart` | `D93782C98EC4E70CC8F198F19CFE1DEBC6680CAA8933D51FF0D938B7E356EBC0` |
| `test/features/consent/research_consent_use_cases_test.dart` | `AA4EA2F9CA8AAA5BD3932C8230BC37D7BCEC6342EAC2DB6DB889C9360ED5645E` |
| `test/features/research/motivation_measurement_use_cases_test.dart` | `AB4A01B195694AB3F2C8298A55784867AC110180FB44E3F3738654214279C752` |
| `test/features/research/adventure_research_runtime_test.dart` | `09A8E7C718A37959DDEFB46D6F0F4505197F2D3F5A5938CA5DC4AF42CB53F95C` |
| `test/support/motivation_research_fixture.dart` | `757F6CFEA1C3D1A273FCFB9855C8639F3A49F06490D93CD9CBF7A4AD6800099C` |

สอง test files ของ use cases/runtime ใช้เป็น context ของ repository callers เท่านั้น ไม่ได้อ่านหรือ review product use cases/runtime/host ที่ MAIN กำลังแก้ และไม่รับรอง test results ของ source ที่กำลังเปลี่ยน

อ่าน scoring assertion excerpts เพิ่มด้วย bounded `rg -n -C 8` ใน `test/features/research/motivation_instrument_test.dart` (ช่วงผลค้นหาบรรทัด 354–478 และ 710–726); ไม่ได้ review ทั้งไฟล์หรือขยาย product scope ไป R1. SHA-256: `5CDBCB5112845362A2D2E61436A4D1FC600E27E0C427E4B21F7D7EDAB89398FC`

Context document hashes:

```text
5E261F191DED04CEA512BA74DC6E2DA91FA5C46603EF72B765E0E41FE1297FF6  AGENTS.md
36479B6E5ADCD03BF088697623B5BA63C4E7400AE641402AEF1D98709D196843  docs/superpowers/plans/2026-09-05-adventure-research-implementation.md
A25832028B34E33A692AE9EF15DA4E6B76092B58398C378CF1017C9A95863B6C  docs/development/2026-09-05-research-paused-checkpoint.md
FAF50A85F4880931422A5565AE2B6FCAA2C0F7DA463F36734F42D42989A893DB  .superpowers/sdd/research-schema-review-fixes.md
```

## Verification limits / handoff

- ไม่รัน Dart/Flutter, formatter, generator, analyzer, repository-wide analysis หรือ scanner ตามคำสั่ง และไม่มี runtime reproduction ที่รันโดย reviewer
- Prior schema report ระบุ 102 focused migration tests passed, exit 0. ตรวจ hash guard และ migration test แล้วตรงกับรายงานนั้นทั้งคู่; เป็น **prior reported execution evidence** ไม่ใช่ผลเทสต์ใหม่ของ reviewer และไม่ใช้แทนการตรวจ source
- ตรวจ `git diff HEAD` ของ tracked product changes และอ่าน untracked product files จริงครบ; focused `git diff --check HEAD -- lib/data/local/tables/research_tables.dart lib/features/consent/data/drift_research_consent_repository.dart` ไม่มี whitespace error มีเพียง Git LF/CRLF notice
- การตรวจนี้ครอบคลุม 6 product files เท่านั้น ไม่รวม `app_database.dart`, generated schema, gate/validator/domain/serializer internals, sync/upload authorizer, export implementation หรือ UI/runtime/host. ขอบเขตเหล่านี้ไม่ใช่ finding ใหม่และไม่ใช่เหตุให้เพิ่ม implementation scope
- ไม่มี unresolved defect จาก review นี้ และไม่มี reviewer-owned process ค้างอยู่. ขั้นถัดไปของ MAIN คือ integration verification ตาม approved plan เมื่อ source และ Flutter slot พร้อม; การอนุมัติ static review นี้ไม่ใช่การประกาศ Research engineering completion หรืออนุญาต production enrollment/upload/rollout
