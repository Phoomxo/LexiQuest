# LexiQuest — Sequential Package Task Workflow

Revision `2026-09-13-sequential-3` · current master task `01a09888-61dd-7680-9b19-c33035043d59`

ผู้ใช้อนุมัติ “เริ่ม G0.1 แล้วส่งต่อทีละ task” และกำหนดโมเดล Astra / Medium; อนุญาตใช้วิจารณญาณแก้ข้อขัดข้องเพื่อให้งานต่อเนื่อง. Workflow นี้แทนคำสั่งเก่าที่ให้หยุดหลังแผนหรือจำกัดงานถึง R15.10

## 1. รูปแบบ task และความเป็นเจ้าของ

- ใช้ชื่อ `LexiQuest · G<phase>.<package> · <package title>`; G0.1–G8.9 ตรงกับ P0.1–P8.9 ใน Master Plan และ ledger. มี64package tasks ตาม [task index](full-system-task-index.json)
- แต่ละ task ทำเฉพาะ package ของตนและ dependencies/fixes ที่จำเป็นต่อการปิด package นั้น; บันทึกการขยาย write set ตาม rule register
- ทุกการสร้าง task ใช้ `model: gpt-6-astra` และ `thinking: medium`. ไม่เพิ่ม reasoning/model/cost เองเพียงเพราะ task ยาว; วินิจฉัยและลดขนาดงาน/การอ่านก่อน
- สร้างทีละ task: accepted source → durable handoff → release application writer → create successor. ไม่สร้าง64tasksพร้อมกัน ไม่ใช้ subagents/background implementation workers
- Master task ทำหน้าที่คุม revision/สถานะและรับคำสั่งผู้ใช้; package task เป็นผู้เขียน source เพียงตัวเดียว. การอัปเดต coordination metadata หลังส่งต่อไม่ใช่สิทธิ์แก้ source ต่อ
- Initial project: `C:/Users/Phet/Documents/LexiQuest`, projectIdที่ค้นพบ `e0d28f74-0d26-40bc-b126-4cfebe4ff7a0`, Git repository. ก่อนสร้าง successor ใช้ list_projects ยืนยัน project/path/isGitRepository อีกครั้ง; ถ้าIDเปลี่ยนใช้IDที่ค้นพบจริง

## 2. Durable control state

Control directory ที่มีอยู่บนเครื่องนี้:

`C:/Users/Phet/.codex/visualizations/2026/09/13/01a09888-61dd-7680-9b19-c33035043d59/full-system-orchestration`

- `run-state.json`: executionAuthorized, status, model, current writer/dispatch reservation, task IDs/statuses และ accepted source ล่าสุด
- `bootstrap-manifest.json`: hash และ source root ของเอกสารเริ่มต้นสำหรับ G0.1
- `handoffs/Gx.y.json`: ผล package จริง รวม accepted commit, source/config/input/evidence pins และ successor ID
- `dispatches/Gx.y.json`: creation receipt เช่น threadId หรือ clientThreadId, parent และเวลา; ใช้ตรวจ duplicate/uncertain creation

Task index ใน repository เป็นลำดับและ brief definitions; run-state เป็นสถานะ runtime ของการส่งต่อ. ใช้ atomic replace ใน control directory และรักษา previous revision/updatedBy. ไม่เขียน handoff ที่อ้าง SHA ของ commitที่ต้องบรรจุ handoffนั้นเอง; commit source/checkpointก่อน แล้วบันทึก acceptedSHA ใน external handoff

ไม่ใช้ timing-only lock. ระบุ packageId/threadId/worktree/sourceSHA ของ writer และตรวจ task status จริงก่อนรับต่อ. หากมี writer อื่นยังรัน ให้หยุดการเขียนและตรวจว่าเป็น task เดิม/งานซ้ำ ไม่ข้าม lock ด้วยการเดา

## 3. ขั้นรับงาน — ทุก task ต้องทำก่อน implementation

1. อ่าน creation prompt, own brief, AGENTS, Active Index และ run-state/current handoff เฉพาะส่วนของตน. ถ้ามี user pause/stop ใหม่หรือ executionAuthorized=false ให้หยุด ไม่สร้าง successor
2. ตรวจ task ID/package ID กับ index และ dispatch receipt. ถ้ามี task อื่นรับ package เดียวกันแล้ว ให้ไม่เริ่ม writer และรายงาน duplicate
3. ตรวจ cwd, Git common directory, branch, HEAD และ dirty files. Native task creation อาจเริ่มจาก project default branch จึง **ห้ามถือว่า checkout ใหม่มี R15 หรือ source จาก predecessor แล้ว**
4. G0.1 อ่าน bootstrap manifest จาก control directory; ยืนยัน hash ก่อนรับเอกสารจาก `C:/Users/Phet/.codex/worktrees/7712/LexiQuest`. รับเฉพาะ paths ใน manifest แบบตรวจ collision; preserve ต้นฉบับ. เก็บ source candidate R15 `f4eebb895836349fbf8e9960312a78bad524d462` + uncommitted F1–F4 ใน842cเป็นข้อมูลตั้งต้น ยังไม่แก้ทั้งสี่ซ้ำ
5. ตั้งแต่ G0.2 ใช้ acceptedSourceSha/branch/worktree จาก predecessor handoff ที่มีอยู่จริง. เตรียม isolated branch ตาม native environment หรือ Gitอย่างปลอดภัย; dirty/untracked collisionsต้อง reconcileก่อน checkout. ไม่ reset/clean user filesและไม่ merge branchอื่นโดยเดา
6. ตรวจว่า docs ใน accepted source มี revisionปัจจุบัน; G0.1ต้องรับ seedแล้ว commitเป็นส่วนของ bootstrap output. ต่อจากนั้นใช้ docsจาก accepted source ไม่ทับด้วย seed7712เก่า. หากเอกสารอยู่คนละsourceกับcodeให้ระบุสองpinและแก้ความสอดคล้องก่อน implementation
7. อ่าน Masterเฉพาะ own package/dependency/gate, ledgerเฉพาะ related COV/MODE/MG/FORM rows และ contracts/source/tests ที่เกี่ยวข้อง. ตรวจ upstream evidence ก่อนตัดสินว่าต้องทำใหม่
8. Claim writerในrun-stateแล้วทำ package; หากยังเตรียมsourceไม่เสร็จ อย่าเริ่มแก้ application หรือรัน expensive gate

G0.1 เป็น source/ownership/bootstrap package จึงไม่ต้องสร้างfeaturesหรือรันfullregression. G0.2รับrepairs, G0.3แจกแจงmain/R15semanticdifferencesตามMaster; ไม่ย้ายงานทั้งหมดมาทำในG0.1

## 4. ขั้นทำงานและเก็บปัญหา

ใช้ workflowในMaster: inspect gap → design delta → meaningful regression เมื่อแก้behavior → implementation → focused verification → package review → checkpoint. Existing verified inputsได้รับcredit; ไม่สร้าง testที่เลียน implementationและไม่ rerununchangedpassedgate

ปัญหาที่แก้ได้ในlocalscopeให้ดำเนินการเอง: wrong path/fixture/tool setup, conflicts, related interface change, recoverable tests, stale documentation และdependencyเหตุจำเป็น. บันทึกsteps/expected/actual/source/log/rootcause/fix/retest; ไม่ขออนุมัติเดิมซ้ำ. ถ้าคำสั่งหรือfilesystemล้มซ้ำให้หยุดคำสั่งนั้นตามAGENTS แล้วdiagnoseก่อนเลือกทางแก้ ไม่ใช้blindretry

เมื่อพบ requirementใหม่ที่จำเป็น ให้จัดเข้าpackage/phaseเดิมพร้อมchange recordและversionedcompatibility ไม่ใช้ข้อจำกัดR15เก่าปฏิเสธงานMaster. 64packagesยังเป็นคิวหลัก; หากต้องแก้defectย้อนหลัง ทำremediationในtaskปัจจุบันพร้อมownerpackage reference ไม่สร้างworkersหรือtaskซ้ำโดยอัตโนมัติ

Real costs, external account authority, destructive user-data operations, real enrollment/deployment และสิ่งที่ทำเองไม่ได้ต้องบันทึก external dependency/required action. งานlocalที่ไม่พึ่งสิ่งนั้นเดินต่อได้ตามgate; ห้ามใช้externalpendingเป็นPASS

## 5. Package handoff ที่บังคับ

ก่อนสร้าง successorต้องมีหลักฐานต่อไปนี้ใน `handoffs/Gx.y.json`:

| Field | ข้อมูลจริงที่ต้องบันทึก |
| --- | --- |
| schemaVersion / planRevision / packageId / displayId / ordinal | packageและrevisionที่ทำจริง |
| threadId / worktree / branch / acceptedSourceSha | taskและcommitที่รับได้; SHAเต็ม40ตัว ตรวจด้วยGit |
| initialSourceSha / changedFiles / dirtyDisposition | รายการไฟล์/เหตุผลเกี่ยวกับgenerated/unrelated/uncommittedfiles |
| requirements / coveredRows / decisions | COV/MODE/MG/FORMและrule/designchangesที่ทำ |
| verification | command, exit/count/duration, source/dependency/configfingerprint, logs และ reused evidenceพร้อมเหตุผล |
| defects / externalGates | ปัญหาใหม่/ที่แก้/retest/open และสิ่งที่ยังNOT RUN |
| checkpointPath / contentModelPins / rollback | paths ที่ successorอ่านได้จริงและวิธีย้อนเฉพาะpackage |
| gateStatus / phaseStatus | package acceptedจริง; phase-last packageปิดG0…G8ตามcoverage |
| writerReleased / nextPackageId | true หลังหยุดsourcewrites; nextจากindexเท่านั้น หรือnullที่G8.9 |

สรุปให้อ่านได้ในหนึ่งหน้าโดยใช้linksไปlogs/source ไม่dumpreportsทั้งหมด. Commitเฉพาะacceptedsource/tests/docs/seedที่จำเป็น; `git add .`โดยไม่ตรวจไม่ใช้. ถ้าpackageไม่มีsourcechangeให้ใช้existingacceptedSHAได้และบันทึกno-code-changeพร้อมevidence/checkpoint ไม่สร้างemptycommitเพื่อเพิ่มเลข

## 6. สร้าง successor แบบไม่ซ้ำ

1. ตรวจacceptanceและhandoff, currentuserinstruction, nextPackageId และrun-state ว่ายังไม่เคยdispatchnext. ถ้าปัญหาจำเป็นยังไม่ปิดห้ามข้ามpackage
2. ปล่อยapplicationwriter, เขียนhandoffและdispatchreservationสำหรับnextแบบatomic; บันทึกmodel/Mediumและsourcepinที่ต้องรับ
3. เรียก list_projects แล้ว create_thread กับprojectGitrepositoryและ environment worktreeตามtooldefaults. ไม่ใช้fork_full_history. ไม่ระบุstartingStateที่toolไม่อนุญาต; creationpromptต้องระบุactualpredecessorSHAและreceivercheckoutverificationเสมอ
4. ใช้ exact title/briefจากtaskindex, `model: gpt-6-astra`, `thinking: medium`. Promptแนบเฉพาะauthorization, packageID, source/handoff/controlpaths, docsrevision และสิทธิ์สร้างsuccessorหนึ่งตัวหลังจบ
5. บันทึกtoolreceiptทันที. ถ้าได้threadIdให้บันทึกIDจริง; ถ้ามีแค่clientThreadIdคงpendingสถานะและอย่าเอาไปเรียกread/waitที่ต้องใช้threadId. ใช้list_threadsเพื่อresolveโดยเทียบpackage/title/creationpromptและproject; อย่าretrycreateเพราะsetupยังไม่เสร็จ
6. ถ้าcreateผลไม่ชัด ตรวจdispatchreceiptและlist_threads/readของcandidateก่อน. หากยังตัดสินไม่ได้ให้รายงานuncertain-dispatchและหยุดเพิ่มtask เพื่อไม่ให้เกิดสองwriter
7. ใช้wait_threadsหลังcreateเพื่อรับprogressหนึ่งครั้งด้วยboundedwaitไม่เกิน60วินาทีต่อcall; เมื่อไม่มีการเปลี่ยนแปลงให้backoff ไม่pollถี่และไม่เล่าผลเดิม
8. แจ้งsource/ผลpackage/ชื่อtaskถัดไปและemit created-thread directiveตามtoolresult. Parentหยุดsourcewritesและจบturn; successorเป็นผู้ทำpackageถัดไป

เครื่องมือสร้างtaskเป็นงานasynchronous. ไม่กล่าวว่าทำpackageแล้วเพียงเพราะสร้างtaskสำเร็จ และไม่กล่าวว่าสร้าง64taskครบตั้งแต่เริ่ม. จำนวนที่สร้างจริงดูrun-state/receipts; ที่เหลือเป็นpreparedbriefs

## 7. Context discipline และการหยุด/กลับมาทำต่อ

- First read: own brief + compact handoff + active rules. ไม่อ่านhistorytaskทั้งหมด/ทุก64briefs/fullcatalogJSON/fulllogsเพียงเพื่อหาpackageปัจจุบัน
- ใช้targetedJSONprojectionหรือsectionextractกับledgerที่ยาว. หากoutputtruncateให้ลดขอบเขต/readเป็นparts ไม่ทำparseจากpartialoutputและไม่วนอ่านไฟล์ทั้งก้อน
- อ่านrelevantcallers/sourceเมื่อจำเป็นต่อความถูกต้อง; contextbudgetไม่ใช่เหตุข้ามtests/review/acceptance
- ยืนยันข้อเท็จจริงก่อนเปิดdefect: oldreportedPASS, sourceinspected และruntimeverifiedเป็นคนละสถานะ
- ถ้าcontextใกล้เต็มก่อนpackageจบ ให้checkpointในtaskเดิมและใช้compactionตามปกติ. ไม่สร้างpackageถัดไปเพื่อหนีdefect และไม่เพิ่มtaskลำดับที่65โดยไม่เปลี่ยนmasterอย่างชัดเจน
- Userpause/stopใหม่: updatecontrolstateและหยุดdispatch; resumetaskเดิมตามsource/handoffโดยไม่สร้างduplicate. การพิจารณาปัญหาระหว่างทางที่ผู้ใช้อนุญาตไม่แทนสิทธิ์เพิกเฉยต่อpause
- G8.9จบคิว: nextPackageId=null, executionState=completedเฉพาะmasteracceptanceครบตามedition, เก็บrelease/test/review/defectledger; ถ้าrequiredexternalค้างให้รายงานสถานะจริงไม่สร้างsuccessorนอกแผน
