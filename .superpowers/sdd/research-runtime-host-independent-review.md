# Independent review — Research runtime / Today Host

ผล: **With fixes** — เหลือ P2 สองข้อ: switch fact ระหว่าง async capture และ permit-expiry timer หลัง renewal. Post-deadline finding แก้แล้วตาม current source และ GREEN ที่ MAIN รายงาน. ไม่มี Critical finding และไม่มี implementation edit จาก reviewer

## Scope / snapshot

Worktree `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`, branch `feature/adventure-research`, HEAD/base `6968ce97ff9b383e244b17b77cf0ed0f61eaaf3d`. ตรวจ actual uncommitted/untracked code ตามแผน R3/R5 และอ่าน corresponding tests; ใช้กรอบ `requesting-code-review` / `code-reviewer.md` ที่อ่านแล้วใน task นี้

Product scope ที่อ่านครบมีเพียง 3 ไฟล์:

| Path จาก worktree | SHA-256 ของ full-review snapshot |
| --- | --- |
| `lib/features/adventure/presentation/today_experience_host.dart` | `F61AF0050B5DB9ADAD379D6C3946D88DACD4EF6D24BE0307A19304CDCBA5BBA6` |
| `lib/features/research/application/motivation_measurement_use_cases.dart` | `82DECA1596B31DF9E5007CF9BC3E3FD16F59C20FF4EB920A7085FDB0E42FE762` |
| `lib/features/research/application/adventure_research_runtime.dart` | `79D9D573D7AC5E56169032EDCEF80B7C69660D0F37F4994553F0558B29E30DF9` |

อ่าน Host ปัจจุบัน `F61A…` ครบทั้ง 688 บรรทัดหลัง MAIN เพิ่ม post timer; service/runtime hashes ยังตรงกับไฟล์ที่อ่านครบก่อนหน้า. Historical Host ก่อน timer คือ `F83636D130017C99FD74F68772A42D6F05C7AFE2A2B3D707DFCF3BD5310345EF`. Finding ที่ยัง open ด้านล่างอ้างเลขบรรทัด current source; รายงานไม่ขอให้ MAIN รอ formatter หรือหยุดงาน

## 1. [P2] Switch ที่แสดงแล้วถูกทิ้งเมื่อ capture ก่อนหน้ายังรอ hook

**ตำแหน่ง:** Host snapshot `F836…` บรรทัด 457 และ 464–486; หลัง timer patch `F61A…` คือ **477, 484–506**. จุด await ที่เพิ่มช่วง race คือ `motivation_measurement_use_cases.dart:26–29` / `36–39`

**เหตุและผล:** `_recordingResearchPresentation` ทำให้ build ของ presentation ใหม่ return ทันทีโดยไม่มี pending work. เมื่อ callback เก่าจบ generation ไม่ตรง จึงข้าม `_refreshResearch`; `finally` เพียงปลด bool โดยไม่ drain/schedule งานใหม่. หน้าจอจึงแสดง Standard แล้ว แต่ opportunity ยังเป็น Adventure และไม่มี `TodayExperiencePresentationChanged`. การบันทึก mission ภายหลังอาจใช้ effective presentation เก่า. Callback ยังตรวจ generation ก่อน `recordPresented` เท่านั้น จึงอาจดำเนิน `changePresentation` ของ snapshot เก่าหลัง await ได้ด้วย

**Reproduction จาก source trace — reviewer ไม่ได้รัน:**

1. ใช้ research Host fixture ที่ baseline ครบ เปิด Adventure และให้ `onLocalMutation` หน่วงเฉพาะครั้งแรกหลัง Presented ถูก commit ด้วย `Completer`; hook ครั้งอื่นให้จบทันที
2. ระหว่าง callback นั้นค้าง ให้สลับ Standard และ pump จน `TodayHubView` แสดง. UUID/Today/opportunity เดิมยังถูกใช้ แต่ recorder ของ generation ใหม่ถูก busy guard ทิ้ง
3. ปลด Completer และรอ callback เดิมจบ โดยไม่กระตุ้น lifecycle/refresh เพิ่ม. ไม่มีการ drain switch: expected หนึ่ง Changed fact และ `effectivePresentation=standard`; source path ปัจจุบันคง Adventure/ไม่มี Changed fact

**Recommendation:** serialize/queue facts ของแต่ละ transition ที่ render จริง พร้อม owner/opening/opportunity identity; drain งานค้างหลัง await และป้องกัน callback เก่าเขียน UI state ของ opening ใหม่. อย่าแก้ด้วย coalesce ทุก switch เหลือค่าล่าสุด เพราะต้องเก็บ first 10 facts และ excess count. เพิ่ม delayed-hook widget regression โดยคง one Today/UUID และตรวจ fact/counter ด้วย

**Coverage:** Host switch test (`test/features/adventure/presentation/today_experience_host_test.dart:110–125`, hash ด้านล่าง) ใช้ `pumpAndSettle` ให้งานเดิมจบก่อนสลับ และ runtime fixture ไม่มี delayed hook จึงไม่ครอบคลุมลำดับนี้. Runtime hook test `:22–38` ทดสอบ hook throw แต่ไม่ได้ overlap กับ Host switch

## 2. [P2] Permit renewal ไม่ย้าย expiry timer ไป deadline ใหม่

**ตำแหน่ง current Host `F61A…`:** `211–215` ตั้ง permit timer เฉพาะ `_load`; `437–445` อ่าน permit ใหม่ใน `_refreshResearch` แต่ตั้งใหม่เฉพาะ post timer โดยไม่ rearm `_researchExpiry`

**Reproduction จาก source trace — reviewer ไม่ได้รัน:** เปิด participant Adventure ที่ baseline ครบและยังไม่มี index completion ด้วย permit expiry T1; import authentic renewal ของ permit เดิมที่ expiry T2 > T1 แล้วปล่อย watcher refresh ให้จบ. Timer เดิมยังยิงที่ T1; `_refreshResearch` เห็น permit ใหม่ยัง active จึงไม่ `_load` และไม่สร้าง timer T2. เปิดแอปค้างจน T2 โดยไม่มี interaction/lifecycle/DB change: treatment ยังแสดง แม้ permit หมดอายุแล้ว. Capture authority ยังตรวจ expiry ได้ ปัญหาคือ presentation ไม่ถูก invalidate ณ deadline ใหม่

**Recommendation:** ใช้ permit-expiry scheduling ที่ cancel/rearm จาก validated permit snapshot ทุกครั้งทั้ง `_load` และ `_refreshResearch`, พร้อม owner/opening guard; เมื่อ permit หายให้ cancel. เพิ่ม renewal T1→T2 widget regression และคง Today/UUID เดิม. กรณี issuer ลด expiry ให้เร็วกว่ากำหนดเดิมก็ต้องใช้ deadline ใหม่เช่นกัน

## Resolved: Post form ไม่หมดอายุเองเมื่อเปิดแอปค้าง

**ตำแหน่งเดิม:** Host `F836…:209–212` ตั้งเฉพาะ permit-expiry timer; `375–382` ตรวจ post +30m เฉพาะตอน getter ถูกอ่าน; `395–430` ไม่มี post-deadline scheduling

**Reproduction:** ให้ canonical completion เปิด post form แล้ว advance clock และ pump `30m + 1ms` โดย permit ยัง active และไม่มี DB/lifecycle change. ไม่มี callback สั่ง rebuild จึงยังแสดง form ที่ตอบไม่ได้; capture boundary ปฏิเสธคำตอบถูกต้อง ปัญหานี้เป็น UI deadline ไม่ใช่หลักฐานว่ามีการยอมรับ late answer

**หลักฐาน:** อ่าน assertion ใหม่จริงที่ `test/features/adventure/presentation/today_experience_host_test.dart:69–74`. MAIN รายงาน observed RED ที่บรรทัด 72: actual form ยังอยู่ แต่ expected none; อีก 19 Host cases ผ่าน. เป็นผล execution ที่ MAIN แจ้ง ไม่ใช่ reviewer-run result

**Correction status: resolved สำหรับ defect นี้.** อ่าน current Host แล้วพบ scheduler ที่ `388–402` ใช้ completion+30m+1ms; เรียกจาก loaded/refreshed snapshot (`207,441`), cancel ตอน reset/dispose (`159,514`), และ timer ตรวจ mounted/generation ก่อน local rebuild โดยไม่โหลด Today ใหม่. MAIN รายงาน observed GREEN ใน batch 174 tests (Host20 + runtime5 + service7 + consent3 + lifecycle42 + instrument97) และ bootstrap5 GREEN. Reviewer ไม่รัน duplicate test และไม่อ้างเป็นผล execution ของตน

## ส่วนที่ตรวจแล้วไม่พบ finding เพิ่ม

- Current Host `153–178,268–281` สร้าง opening ใหม่เฉพาะ refresh/dependency change; switches ใช้ `_entryHost` เดิม. Baseline prompt อยู่ก่อน treatment rendering/Presented (`201–238,550–559`); Skip ใช้ close แล้วกลับ ordinary path โดยไม่สร้าง Today/UUID ใหม่ (`452–470`)
- Owner-changing-during-Today-load fix มี owner check ก่อน/หลัง `host.open` (`187,200`) และ watcher invalidation (`422–431`); test `:33–49` มี pending-loader/owner-switch reproduction จริง. ไม่ยกระดับผลนี้เป็นการรับรองทุก async race
- Service reconcile อ่าน canonical learning rows และ attach/complete ผ่าน research repositories (`58–100`), ไม่สร้าง learning session/answer/reward authority. เลือก session ตามเวลาและหยุดที่ invalid first candidate ไม่ข้ามไป convenient completion
- Watch projection sort + JSON + `distinct()` (`103–117`) กรอง owner write-fence no-op notifications; corresponding test `motivation_measurement_use_cases_test.dart:21–28` ตรวจ observer count. ไม่มี global sync-lease block ที่เพิ่มใน 3 ไฟล์นี้; genuine owner fence ยังคง delegated ไป participation repository
- `_capture` await action ก่อนเรียก notification และ `notifyCommitted` กัก exception (`22–29`). Reconcile wrapper เรียก notification หลัง outer transaction จบ (`58,100`); runtime withdrawal notify หลัง transaction (`50–55`), import notify หลัง import commit (`37–41`). ไม่พบ outbox work ภายใน transaction ใน scope นี้ และ hook throw ไม่ rollback capture ที่ commit แล้ว
- Runtime `currentPermit` ตรวจ authority อีกครั้งใน transaction (`43–48`); document owner mismatch ถูก reject (`37–40`). ไม่ได้อ่านหรือ review participation screen / sync / authorizer / dependencies ที่ worker อื่นกำลังแก้

## Test / plan source และข้อจำกัด

อ่าน corresponding test files ทั้งสาม (รวม Host deadline assertion ล่าสุด), ไม่รัน Dart/Flutter, analyzer, formatter, scan หรือ test command ใด ๆ:

| Path | SHA-256 |
| --- | --- |
| `test/features/adventure/presentation/today_experience_host_test.dart` | `045A7F045D0FC5F235EDB96AB8ED371C9BBC34721919F5C768A5A7E0ACDF6D11` |
| `test/features/research/motivation_measurement_use_cases_test.dart` | `AB4A01B195694AB3F2C8298A55784867AC110180FB44E3F3738654214279C752` |
| `test/features/research/adventure_research_runtime_test.dart` | `09A8E7C718A37959DDEFB46D6F0F4505197F2D3F5A5938CA5DC4AF42CB53F95C` |
| `docs/superpowers/plans/2026-09-05-adventure-research-implementation.md` | `36479B6E5ADCD03BF088697623B5BA63C4E7400AE641402AEF1D98709D196843` |

ผล Host 20/shared service 7 ก่อน hook rerouting เป็น historical evidence; สถานะล่าสุดที่ MAIN แจ้งคือ batch 174 และ bootstrap5 GREEN ตามรายละเอียดข้างต้น. Runtime hook implementation และ test source ถูกอ่านจริง แต่ reviewer ไม่ได้รัน. Consent use-case/API changes อยู่นอก product scope และไม่มีการเปิดอ่าน

เขียนเฉพาะรายงานฉบับนี้ ไม่มี product/test edits, commit, task ใหม่ หรือ reviewer-owned process ค้าง. ขั้นถัดไป: MAIN ตรวจ delayed-hook switch และ renewal-timer reproductions ตาม slot ที่ถืออยู่; finding 1–2 ยัง open และไม่ได้รับการแก้จาก reviewer. ไม่อ้าง production readiness

## Follow-up status — formatted Host P2 fixes (2026-09-05)

**สถานะล่าสุด: Approve สำหรับ Host P2 ทั้งสองข้อ — ปิด findings 1–2 เดิมแล้ว.** เก็บ original findings/hash เป็น historical evidence ไม่ได้เขียนทับผลเดิม และการ recheck นี้ไม่ขยายไป product files อื่น

- FIFO: `today_experience_host.dart:583–706` เก็บแต่ละ rendered transition พร้อม runtime/owner/opportunity/opening identity; drain ตามลำดับ ไม่ coalesce; ตรวจ identity ก่อนและหลัง await; opening ใหม่ล้างคิว (`156–170`), stale callback ไม่เปลี่ยน current snapshot. Behavioral source `today_experience_host_test.dart:93–190` หน่วง post-commit hook แล้ว render 12 switches ตรวจ 10 facts + suppression 2, opportunity/Today/UUID อย่างละหนึ่ง
- Renewal timer: scheduler `today_experience_host.dart:459–470` ยกเลิก timer เดิมและผูก generation; `_refreshResearch` ตรวจ owner/generation แล้ว rearm จาก current permit (`514–523`); reset/dispose ยกเลิก (`163`, `712`). Behavioral source `today_experience_host_test.dart:36–91` import signed revision ใหม่ แล้วข้าม expiry โดยไม่ reload Today
- SHA-256 Host ที่ recheck: `F3D92CB4B76F51FF2F41661BEC6A118385B2085B06610DB73DF9985C8BFD861A`; corresponding Host test: `CB5CC7F1F0E68DFFB9E4D0A03092CCA62822060E9622D674B4BA219AED137F21`
- MAIN รายงาน behavioral RED ก่อนแก้ → Host 22/22 GREEN และ targeted 20-file analyzer clean. Reviewer อ่าน source/tests เท่านั้น ไม่รัน Dart/Flutter/test/analyzer/formatter/scan; ไม่มี source/test edits หรือ production-readiness claim
