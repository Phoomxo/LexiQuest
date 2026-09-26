# LexiQuest R3 — แผนดำเนินงานต่อเนื่อง แบ่ง task ตามหัวข้อหลัก
**สถานะล่าสุด 2026-09-24:** ผู้ใช้สั่งพักการตรวจรับ 215 เกณฑ์แบบไม่มีกำหนด เพราะอาจปรับเกณฑ์ใหม่ กติกาการทำต่ออัตโนมัติ/ส่งต่อ successor ในเอกสารนี้ถูกระงับสำหรับงานตรวจรับ R3-05 และงานปลายทางที่พึ่งผลนี้ ห้ามเริ่มการตรวจ 215 เกณฑ์หรือสร้าง successor เองจนกว่าผู้ใช้สั่งชัดเจน ก่อนเริ่มใหม่ต้องทบทวนและกำหนดเกณฑ์ฉบับใหม่แล้วเทียบหลักฐานเดิมตาม source fingerprint; ยอด 4/215 เป็นเพียง snapshot เก่า ไม่ใช่ผลของเกณฑ์ใหม่ ระบบติดตาม `lexiquest-r3` คงสถานะ PAUSED งาน UX/UI แยกจากการตรวจรับนี้

2026-09-23 · อนุมัติจากคำสั่งล่าสุด: แก้ปัญหาเฉพาะหน้าและทำต่อ ไม่หยุดเพียงเพราะวิธีเดิมล้ม; แบ่งแชตตามหัวข้อหลัก; ใช้ Jev (ผู้ใช้ยืนยันว่า Jeff เป็นการถอดเสียงผิด) เลือกโมเดลตามแผนเดิม

## 1. ผลที่ต้องได้และอำนาจ
เอกสารนี้แทนกติกา “ไม่ซ้ำ/timebox” ที่อาจถูกตีความเป็นหยุดงานใน R2 และเสริม Jev revision7 D0–D7 โดยไม่ลบ acceptance เดิม. เป็นแผนปฏิบัติที่มีผู้รับงานและส่งต่อจริง ไม่รอให้ผู้ใช้กลับมากดเริ่มแต่ละหัวข้อ.
คง single application writer, ไม่ deploy/ซื้อเครดิต/เปิด research, รักษาบัญชีและข้อมูลผู้ใช้, Standard/default ห้าม Fast/priority. Coordinator ใช้ Astra/medium; worker model ให้ Jev เลือกตาม eligible pool ของ revision7 รวม GPT-6/Gemini ที่ผู้ใช้อนุมัติสำหรับงานพัฒนา ไม่ใช่ fallback ในผลิตภัณฑ์ Free route.
R2 G1–G6/T01–T08 ยังใช้กับ original Free/no-companion route; debug USB/MCP ไม่ทำให้ gate นี้ผ่าน. งาน optional AI ต้องไม่ขวาง manual baseline. ไม่แก้ผลเก่าเป็น PASS และไม่เปิด V2 ต้นทางก่อน gate.

## 2. หัวข้อหลักและหัวข้อย่อย — หนึ่ง task ต่อชุด
| ID / ชื่อ task | งานย่อย | Output และ exit | Dependency |
|---|---|---|---|
| R3-01 รับแผนและกระทบยอดหลักฐาน | 01.1 รับ R2/R3/Jev7 และ source dirty manifest; 01.2 map 14 workflows/14 modes กับหลักฐาน; 01.3 ยืนยัน writer/backup/next work | acceptance ledger ราย criterion, accepted source receipt, ownership และ handoff; แยก completed/pending จริง | เริ่มได้ read-only ทันที |
| R3-02 กู้คืนและตรวจอุปกรณ์ | 02.1 ตรวจ isolated backup/fixture; 02.2 catalog/detail/filter/context/owner; 02.3 restore และตรวจ durable data | native/provider/storage แยกหลักฐาน; restore สำเร็จ หรือ external pending พร้อมเจ้าของ; ไม่แตะ original account | 01; หากอุปกรณ์ไม่พร้อมทำ host ส่วนนี้แล้วจัดคิวรอ |
| R3-03 Jev ledger และการเลือกโมเดล | 03.1 migration รักษา live calls เดิม; 03.2 incident/cache/budget guards; 03.3 route selection และ fallback audit | offline guards ผ่าน, valid route receipt หรือ explicit deterministic fallback; ห้ามอ้าง Jev เลือกเมื่อไม่ได้เรียก | 01; ไม่ต้องรอ USB |
| R3-04 Context และ dispatcher | 04.1 GODKILLER A/B bounded; 04.2 read-only worker dry-run; 04.3 sequential sole-writer/review/recovery | source/cwd/model match, diff review, no parallel writer; ถ้า context tool ไม่ผ่านใช้ canonical reads; D3 efficiency ไม่เป็น blocker งานผลิตภัณฑ์ | 03; tooling ที่ยังไม่ผ่านใช้ coordinator ปกติ |
| R3-05 ปิด acceptance ของ optional AI/MCP | 05.1 owner/data loss/duplicate/baseline; 05.2 14 workflows และ14 nested modes ตาม ledger; 05.3 affected native/provider/durable retests | criterion matrix ครบ พร้อม source applicability และ external-pending รายข้อ; ไม่มี false whole-app PASS | 01 และ safety readiness; ทำได้แม้ Jev/tooling พัก |
| R3-06 สิทธิ์บัญชีและเส้นทาง standalone | 06.1 G1/G2/G4 route/UX/entitlement; 06.2 G3/G5 quota-only/revoke; 06.3 G6/live readiness และ decision | claim→evidence→decision ครบ; ผ่านจึง V2.1–V2.3; ไม่ผ่านคง pending และทำงานอิสระอื่นต่อ | 01; ไม่ใช้ผล USB แทน no-companion |
| R3-07 ตรวจทั้งโครงการและแก้ข้อบกพร่อง | 07.1 post-mcp-project-review-plan coverage; 07.2 fixes ทีละ increment; 07.3 regressions/data/rollback | defect ledger พร้อม repro/root cause/fix/retest; final closure รอ relevant D5 acceptance | เริ่มเตรียม/read-only ที่ไม่ขึ้นกับ pending ได้; ปิดหลัง 05 |
| R3-08 ตรวจรับรอบสุดท้ายและส่งมอบ | 08.1 frozen source/affected regression; 08.2 endurance จริง180นาที/remaining verifier; 08.3 pilot/decision/release dossier | ผลตามขอบเขต ไม่ deploy; pilot5คนหลัง prerequisites, Free route/E7 แยก; unresolved external ไม่ปิดปลอม | relevant 05–07; 06 จำเป็นต่อ original Free acceptance |

ไม่เปิดแปด task พร้อมกัน. สร้างเฉพาะ task ถัดไปที่ทำได้หลัง checkpoint; หนึ่งหัวข้อหลักมีหลายงานย่อย ไม่สร้าง chat ต่อ test/command. ถ้าหัวข้อใหญ่เกินหนึ่ง context ให้ใช้ R3-05 part02 พร้อม predecessor/remaining IDs เดิม ไม่เริ่มใหม่.
D0→01,D1→02,D2→03,D3/D4→04,D5→05,D6→07,D7→08; 06 รักษา gate ต้นทาง ไม่เพิ่ม provider fallback.
ลำดับพร้อมทำ: 01→02; ถ้า02ติดอุปกรณ์และงาน host หมด ให้03→04→05ที่ไม่พึ่งอุปกรณ์/06เอกสาร→07ส่วนอิสระ; revisit02เมื่ออุปกรณ์พร้อม. งาน pending ยังคงอยู่ ห้ามตัด scope เพื่อให้หัวข้อถัดไปดูผ่าน.

## 3. วิธีทำต่อเมื่อเกิดเหตุ
คำว่าไม่ซ้ำ = ไม่ blind retry วิธีเดิมโดยไม่มีข้อมูลใหม่. ไม่ได้ห้าม targeted retest, อ่านไฟล์ที่เปลี่ยน หรือแก้ defect ซ้ำจนผ่าน.
| เหตุ | ลงมืออัตโนมัติ | เงื่อนไขส่งต่อ/พักเฉพาะจุด |
|---|---|---|
| path/command/tool error | ค้น path/symbol จริง ตรวจ version/args/permissions เปลี่ยนวิธี แล้วทำต่อ | ไม่จบ task เพราะ error ซ้ำ |
| test RED | เก็บ repro แยก product/test/environment cause แก้ bounded diff รัน affected tests และ native retest ที่จำเป็น | assertion/acceptance ห้ามลด |
| สมมุติฐานเดิมไม่คืบ | บันทึกสิ่งที่ตัดทิ้ง เปลี่ยน hypothesis/tool/scope inspection; ถ้าต้องใช้โมเดลความสามารถสูงขึ้นให้ Jev เลือก eligible | attempt limit จำกัดวิธีหนึ่ง ไม่ใช่จำนวนโอกาสแก้ทั้งงาน |
| Jev timeout/billing unknown | หยุดส่ง Jev ซ้ำ รักษา reservation/reconcile request; deterministic fallback ทำงานโครงการต่อ | ห้าม network retry จน billing ชัด |
| worker quota/unsupported model | refresh eligible pool; Jev reroute ภายใต้ policy; หากไม่ได้ใช้ coordinator ที่อนุมัติและบันทึก fallback | ไม่เลือก paid route หรือ risk ต่ำกว่าที่ต้องการ |
| context tool ตัดข้อมูลสำคัญ | ปิดเฉพาะ tool นั้น อ่าน canonical files แบบเจาะจง | acceptance/source truth ไม่เปลี่ยน |
| device/login/คนจริงไม่พร้อม | ตรวจ transport/สถานะที่อ่านได้ เตรียม host tests/fixture/protocol ต่อ; ไป independent package | ระบุ prerequisite/action ที่ผู้ใช้ต้องทำจริง ห้าม mock PASS |
| owner leak/data loss/restore mismatch | หยุด mutation ที่เสี่ยงทันที snapshot/redact กู้เฉพาะ authorized isolated data ตรวจสาเหตุและ retest | งาน read-only/อิสระทำต่อได้; ไม่เดินข้าม defect |
| source เปลี่ยน | invalidate เฉพาะ evidence ที่ dependency กระทบ repin/review แล้วตรวจใหม่ | ห้ามใช้แค่ชื่อไฟล์หรือ HEAD ตัดสิน reuse |
| successor creation ไม่ชัด | ตรวจ task ID/state ก่อน retry; ไม่สร้างซ้ำ | เก็บ dispatch receipt และเปิด successor เดียว |

ใช้ incident record: symptom, affected criterion, source pin, attempted method, evidence, rejected hypothesis, next different method, owner, nextCheckpoint. retry_once/reroute_once ของ Jev เป็นหนึ่ง incident decision; หลังวินิจฉัยและมีเหตุใหม่สร้าง decision ใหม่ได้ ไม่ใช่เพดานหยุดโครงการ.
พักทั้ง workflow ได้เฉพาะผู้ใช้สั่งหยุด หรือทุกงานที่มีประโยชน์และอนุญาตถูกปิดกั้นด้วย prerequisite ภายนอกจริง. ต้องบอกสิ่งที่ขาดและ action ชัด ไม่ให้ผู้ใช้เดาว่าหยุดตรงไหน.

## 4. Jev เป็นผู้เลือกโมเดลภายในขอบเขต
ใช้ tool/experiments/jev_review และ jev-development-plan revision7 เป็นฐาน ห้ามสร้าง router ซ้ำ. Flow:
1. Coordinator สร้าง structured task card จาก metadata ที่คัดกรองแล้ว: objective/risk/required capability/eligible model IDs/effort/authorization/acceptance/source fingerprint.
2. Deterministic code ตรวจ capability, runtime availability, source, one-writer, quota/cost; shortlist ต้องตรวจสด ไม่ตั้งชื่อ alias เอง.
3. เรียก Jev Choice ภายใต้ guard ที่ผ่านแล้ว; รับเฉพาะ candidate ID/action ใน enum และ confidence ตาม policy ที่มีการทดสอบ. Jev เลือก worker model ไม่ยืนยัน PASS ไม่ลด tests ไม่อนุมัติค่าใช้จ่าย.
4. ตรวจ output/schema/policy อีกครั้ง; bind model/effort ไป worker และบันทึก actual runtime เท่าที่เครื่องมือแสดง. mismatch ต้องแก้ก่อนงาน source ไม่แอบ substitute.
5. ถ้า unavailable/abstain/invalid/billing unclear ให้ routeStatus=DETERMINISTIC_FALLBACK, reason, selectedModel=Astra/medium ที่ได้รับอนุมัติ หรือ eligible route เดิมตาม guard. ห้ามรายงานว่าเป็น Jev decision.
6. หลัง worker ส่ง patch controller ตรวจ diff และหลักฐานก่อน VERIFIED; Jev confidence ไม่แทนการตรวจ.

Jev ใช้ tranche free credits USD5 ที่อนุมัติเดิมเท่านั้น เงินจริง0, no top-up; ตรวจยอดจริงและ reservation ledger ไม่ใช้ snapshot5ดอลลาร์เก่า. ไม่มี live calls จากการเขียนแผนครั้งนี้. Call budget เป็นของ Jev ไม่ใช่สิทธิ์หยุดงาน LexiQuest. Source/raw logs/secrets/ข้อมูลผู้เรียนไม่ส่ง; งาน worker ผ่าน provider ใช้เฉพาะขอบเขตที่ authorized routing plan อนุญาตจริง.
GODKILLER เป็น optional optimization; ตัวเลข character/4 ไม่ใช่ billed tokens. ไม่ผ่าน efficiency gate ให้ bypass แล้วพัฒนาต่อ ไม่รอ optimization เพื่อปิด product defect.

## 5. การส่งต่อ chat และควบคุม context
ต้น task อ่านเพียง R3, current checkpoint, package card, evidence index และคำสั่งปัจจุบัน; เปิด source/evidence เพิ่มตาม claim. ไม่ preload log/transcript ทั้งหมด.
checkpoint หลังผลสำคัญ ก่อน long check และก่อนส่งต่อ: done IDs, remaining IDs, exact next action, known failures/hypotheses, source/build/config hashes, dirty manifest, owned processes, device state, backup/restore, Jev ledger/route, gate states.
handoff ต้องมี predecessor task ID, successor ID, writer transfer, accepted source, worktree, revision, validation result และ external pending. Dirty changes ต้อง preserve ด้วย reviewed commit หรือ verified patch+manifest ตาม repository policy; ห้ามเปิด worktreeใหม่จาก HEAD แล้วอ้างรวมงานค้าง.
เมื่อจบหัวข้อหรือถึงขอบเขต context ตามธรรมชาติ ให้บันทึก handoff ปล่อย writer แล้วสร้าง successor project-bound เพียงหนึ่ง task ตั้ง title ตาม R3-ID, model policy, plan/handoff paths; ไม่ fork transcript. ตรวจเริ่มงานด้วย bounded wait. หากยังไม่จบหัวข้อใช้ part suffix และ keep pending IDs ไม่ mark complete.
สิทธิ์ writer เปลี่ยนหลัง predecessor ปิด source writes/owned jobs และ successor ACK source+checkpoint; task idle ไม่เท่ากับ lease released. ACK ไม่ต้องรอผู้ใช้ เป็นเครื่องมือ/หลักฐานภายใน workflow.
Branch ใหม่ใช้ feature/ เท่านั้น ไม่ใช้ codex/ หรือ codeic/; ตรวจและแก้ชื่อก่อน source writes. Default project worktree อาจไม่ใช่ accepted branch: ห้ามแก้ source ใน checkout ผิด. ตรวจ list_projects/branch/source ก่อน source write. งานเอกสารเริ่ม read-only ได้ในขณะที่ตรวจ writer ownership.

## 6. หลักฐานและการใช้ผลเดิม
Evidence reuse ตรวจ closure ของ changed files + shared interfaces/config/schema/dependency/runtime relevant + tested build/device/provider. PASS เก็บ observed configuration; changed input ทำให้ NEEDS_REVALIDATION ไม่ลบผลเก่า.
แต่ละ criterion มี ownerTaskId, requirement, applicable tracks/platforms, expected, requiredEvidenceLevels, sourceFingerprint, result, evidencePath, failureReason, nextAction.
NOT_APPLICABLE ต้องมีเหตุผลว่าข้อกำหนดไม่เกี่ยวจริงและ reviewer decision ห้ามใช้กับ Free/billing/revoke ที่ทำไม่ได้.
Free gate ใช้ official applicable evidence; runtime gate ใช้ exact live scope. Simulation ตรวจ app handling ไม่พิสูจน์ provider policy. ทั้งสองจำเป็นตาม case.
ก่อนต้นทุน hosted ทดลองจริงต้องมีงบ/เพดานทรัพยากรที่อนุมัติ ไม่รอ pilot. เชื่อมต่อ AI logout ต้อง invalidate tutor/provider session ไม่ทำให้บัญชีแอปหลักหรือ manual workflow ใช้ไม่ได้.
No duplicate UI ไม่ใช่ no duplicate quota. outcome_unknown ห้าม auto-resubmit; reconcile หรือเก็บ pending ตามจริง. cancellation ไม่อ้าง refund.
Rubric สำหรับ bottle: ความหมายและตัวอย่างถูก, เข้าใจง่าย, ตรงคำขอ, ไม่มีการอ้างแก้คะแนน; reviewer ระบุ pass/fail ราย dimension พร้อมตัวอย่าง. Accessibility ใช้ keyboard/focus/large text/screen reader และ platform จริง. Pilot4/5ไม่ใช่ production/learning outcome.

## 7. การติดตามเมื่อผู้ใช้ไม่อยู่
ตั้ง follow-up ใน task coordinator เพื่อตรวจสถานะ successor/checkpoint แบบ bounded ไม่เป็น source writer. แจ้งเฉพาะหัวข้อจบ, ปัญหาที่ต้องให้ผู้ใช้ทำจริง, ข้อผิดพลาดต่อเนื่องที่ recovery ทำต่อไม่ได้, หรือทั้งโครงการจบ; ไม่ส่งข้อความรายงานเดิมซ้ำ.
ถ้า task idle แต่มี authorized independent next action และไม่มี writer อื่น ให้ resume/dispatch ตาม handoff; ถ้ายัง running ไม่ส่ง prompt ซ้ำ. เคารพ user pause/stop และ credit constraints. Monitor ไม่เรียก Jev/inference แทน worker.
บันทึก lastProgressAt/checkpoint/nextAction ไม่ถือว่า tool เรียกนานเท่ากับ hung; ดู process/owned job ก่อน interrupt. หาก app/host offline หรือ usage หมด scheduler อาจรันต่อไม่ได้ ให้รายงาน limitation ตามจริง ไม่สัญญาทำงาน24ชั่วโมงหรือเสร็จในจำนวนวันก่อนวัดงาน.
หลัง R3-01 สร้าง effort forecast จาก remaining criteria, host/device/provider dependencies และเวลาที่สังเกตได้; แยก active work กับ external wait และปรับทุกหัวข้อ ไม่ให้วันที่เดาส่งผลต่อ acceptance.

## 8. แผนเริ่มใช้งานทันที
สร้าง R3-01 เป็น project task ใหม่สำหรับ adoption/read-only reconciliation และส่งตำแหน่ง R3 ให้ coordinator เดิมทราบ. R3-01 ต้องตรวจ coordinator เดิม/current writer ก่อน acquire lease; ห้าม implement ขนาน. Output adoption receipt ต้องผูก R2/R3/Jev7, source/dirty backup, criterion ledger, next package และ successor.
การรับแผนไม่รอผู้ใช้ยืนยันซ้ำ. ขั้น source/ledger/network ใช้ guard และ prerequisite ตามจริง. หาก task source ผิดให้ใช้ actual authorized worktree หลัง ownership ถูกต้อง ไม่ rebuild baseline ใหม่.
ผู้รับผิดชอบปัจจุบันและ IDs อยู่ execution-r3.json; scheduler status และ dispatch IDs จากเครื่องมือเท่านั้น. แผนนี้ไม่อ้างว่า Jev routing, autonomous monitor หรือ execution สำเร็จก่อนมี receipt.
