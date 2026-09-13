# LexiQuest — Workflow สำหรับชุดงาน

Revision `2026-09-13-bundles-4` · Astra (`gpt-6-astra`) / `medium`

## สิทธิ์และหน่วยงาน

ผู้ใช้เปลี่ยนวิธีส่งต่อหลัง G0.5 เสร็จ: **หนึ่ง task ต่อชุดงานที่ใช้ code/context/tests ร่วมกัน**. คง9phases/64requirement packages และ acceptanceทั้งหมด. G0.1–G0.5 เป็นประวัติ accepted; 59packagesที่เหลืออยู่ใน20bundles B01–B20 ตาม [index](full-system-task-index.json). G/P ยังเป็น aliases ของ requirement unit เดียวกัน; B คือหน่วย dispatch. `nextPackage` ไม่ใช่คำสั่งสร้าง task

คำอนุมัติใหม่ผ่าน origin task `01a095a8-40ba-7031-817d-406822b5d3aa` ให้ master แก้ workflow หลัง G0.5 completionจริง และเริ่ม B01/G0.6–G0.8 เมื่อ consistency checksผ่าน. ค่า executionAuthorized=false ใน run-state revision17 หยุด successionแบบเก่าเท่านั้น และถูกแทนด้วย grouped authorizationที่บันทึกในmigration. คำสั่ง pause/stopใหม่จากผู้ใช้ยังมีลำดับสูงสุด

แต่ละ bundle มี application writerหนึ่งตัว; ทำ packagesภายในตามลำดับ ห้าม parallel implementers/subagents/background implementation workers. Masterแก้ orchestrationในworktreeแยกและไม่รับสิทธิ์ทำ applicationจากการแก้workflow. ไม่เปิด taskทุกcommit ไม่สร้าง59หรือ64tasksล่วงหน้า. ทุก taskใช้ `model: gpt-6-astra`, `thinking: medium`; ไม่มี deployment/cost/research authorityเพิ่ม

## รับ source และ claim writer

1. อ่าน creation prompt, AGENTS, [Active Index](full-system-active-index.md), own bundle brief, current run-state และ predecessor bundle handoff. อ่าน package brief เฉพาะเมื่อถึงข้อนั้น ไม่ preloadทุกbrief/history/log
2. ยืนยัน `executionMode=bundles`, plan revision, bundle ID และ receipt. ตรวจว่าไม่มี taskอื่นของbundleนี้. หากยังsetup-pendingให้ resolve IDจริงจากreceipt/state/app ไม่เรียกcreateซ้ำ. ตรวจสถานะwriterจริงก่อนclaim; เวลาเก่าอย่างเดียวไม่ใช่เหตุข้ามwriter
3. ตรวจ cwd/common Git directory/branch/HEAD/dirty/collisions. Native worktreeอาจเริ่มจากdefaultbranch จึงรับ **acceptedSourceShaจริงจาก predecessor handoff** อย่างปลอดภัยก่อนเขียน. B01รับจาก orchestration handoff bundles-4 ซึ่งมี G0.5 SHA `9125ae7b9ccff15bb44ebbab455b8b0251c8fcfe` เป็นparent. B02+รับacceptedcommitของbundleก่อนหน้า. ไม่ทับด้วย seed7712 และไม่แก้ sourceต้นทาง/reset/clean userfiles
4. Read set: own package Master section + required COV/MODE/MG/FORM rows + relevant callers/tests และ prior evidence. Requirement dependencies และphase gateเดิมยังต้องครบ แม้packagesอยู่ในtaskเดียวกัน
5. Claim writerด้วย bundleId/currentPackageId/threadId/worktree/sourceSHA. รายการ G0.1–G0.5 ที่acceptedแล้วไม่ย้อนทำเป็นpackageใหม่; ถ้าdefectใหม่กระทบให้ทำremediationพร้อมอ้างownerpackageและรักษาประวัติ

## ทำงานภายใน bundle

ทำทีละpackage: ตรวจdelta → ออกแบบเฉพาะส่วนเปลี่ยน → regressionที่พิสูจน์behaviorเมื่อจำเป็น → implementation → affected checks → reviewdelta → accepted sub-result → commitที่มีสาระ → package receipt. ถ้าข้อก่อนยังไม่ผ่านให้แก้ภายในbundle ไม่ข้ามไปข้อใหม่เพื่อหนีfailure

- ตรวจและcommitตามผลย่อยที่รับได้ ไม่บังคับหนึ่งcommitต่อpackageหรือเปิดtaskทุกcommit. ถ้าผลเดิมยังผ่านและsource/dependency/config/input fingerprintไม่เปลี่ยน ให้ reuseพร้อมevidence
- ใช้ `tool/cli/verify-scope.ps1` ตาม capability/obligation manifestของ G0.4; missing Economy/Integration automation ไม่ใช่PASSหรือเหตุข้ามacceptance. Fullrelease verifierเฉพาะ frozenPR/releaseSHA; Flutter/backend/build/GPU heavy gatesไม่รันพร้อมกัน
- G0.3 D01–D12 dispositions, G0.4 obligations และ G0.5 source/content/activation pinsยังเป็นinputs. ไม่ย้อนรันG0.5ทั้งชุดเพียงเพราะ orchestrationmetadataเปลี่ยน; runtimeยังNOT RUNตามหลักฐานเดิม
- Failureตั้งแต่ครั้งแรกมี defect/run record: expected/actual, source/config/input/evidence, cause, fix/retest/affected regression. คำสั่งหรือfilesystemล้มซ้ำ/ไม่มีprogress10นาทีให้หยุดวิธีนั้นแล้วdiagnose ไม่blindretry. แก้ recoverable blockersเองตามสิทธิ์เดิม; external-required ที่ยังไม่ผ่านแสดงNOT RUN/external-pending
- ปรับ write set/implementationที่จำเป็นได้ตาม [Rule Register](2026-09-13-rule-supersession-register.md) พร้อมversion/compatibilityและacceptance; ไม่ลดเกณฑ์เพื่อให้bundleปิดเร็ว

## รายงานและผลย่อย

ใช้ Markdownหนึ่งไฟล์ต่อbundle: `docs/development/full-system/bundles/Bxx.md` อัปเดตระหว่างทำงาน. เนื้อหามีเพียงผลที่ทำ / ผลตรวจพร้อมlinks / งานค้างและข้อจำกัด. ไม่เล่าcommand historyซ้ำ ไม่สร้างรายงานMarkdownต่อทุกpackage. เก็บrawlogs, manifests, defects และละเอียดเชิงเครื่องใน structured evidence directoryตาม bundle brief; หลักฐานเก่าไม่ถูกลบ

คำสั่งผู้ใช้ล่าสุด: ทั้งแชตและรายงานหลักต้องกระชับ เน้นผลลัพธ์/การเปลี่ยนแปลง ผลตรวจ ปัญหา/งานค้าง และลิงก์หลักฐาน ไม่เกริ่นหรือสรุปซ้ำ; ส่งต่อแนวทางนี้ใน prompt/handoff ของทุก bundle โดยไม่ลดการตรวจสอบ

หลังaccepted sub-result commit ให้บันทึก package receipt ที่ external `packages/Gx.y.json` พร้อม packageId, bundleId, actualacceptedSHA, requirement/evidence/verification/fingerprint/defects/phaseStatus. อัปเดต packageStates และ currentPackageId แล้ว **ทำข้อต่อไปในtaskและworktreeเดิม**. Package receiptไม่ปล่อยbundle writerและไม่อนุญาตdispatch. SHAต้องเป็นcommitจริงหลังcommit; ไม่สร้างcommitที่ต้องบรรจุSHAตัวเอง

## Control state และ handoff

Control directory:
`C:/Users/Phet/.codex/visualizations/2026/09/13/01a09888-61dd-7680-9b19-c33035043d59/full-system-orchestration`

- `run-state.json` schema2: executionMode, authorization/revision, packageStates64, acceptedHistory5, bundles20, currentWriter/currentPackageId, dispatchReservation และ accepted sourceล่าสุด
- `migrations/bundles-4/`: revision17 snapshot และ migration evidence; bootstrap7712/G0.1–G0.5 receiptsคงเป็นประวัติ
- `packages/Gx.y.json`: package acceptanceใหม่ภายในbundle; อ่านแทนold per-package task handoff
- `handoffs/orchestration/bundles-4.json`: accepted workflow commit + G0.5parent + validationสำหรับ B01
- `handoffs/bundles/Bxx.json`: bundle acceptanceและsource pinที่ส่งให้taskถัดไป
- `dispatches/bundles/Bxx.json`: task creation receipt; clientThreadIdระหว่างsetupและthreadIdจริงหลังresolve

แก้run-stateด้วยread/compare revisionและatomic replaceในdirectoryเดียวกัน ระบุpreviousRevision/updatedBy. ใช้ exclusive OS file lock `run-state.lock` ระหว่างread/validate/replace; existinglockfileไม่แปลว่ายังมีwriter. ในPowerShellให้ใช้backup pathที่ไม่ว่างกับFile.Replace เพื่อเลี่ยงnullถูกส่งเป็นemptystring. ไม่แก้stateทับactorอื่น ไม่clearwriterจากอายุเวลา

ก่อนปล่อยbundle writerต้องมี:
- packagesของbundleครบตามลำดับและacceptedreceiptsจริง; final phase packageตรวจphase gate; required unresolved failureไม่ใช่accepted
- source commitจริง40hex/branch/worktree; start/base SHAและchangedFiles/dirtydisposition/rollback
- reportPath, package receipt links, coverage/requirement outcomes, verification/fingerprints/reused evidence, content/model/config pins, defects/openexternalgates และreviewdelta
- `writerReleased=true`, `nextBundleId`จากindexหรือnullในB20. Handoffเขียนหลังacceptedcommitเพื่อเลี่ยงself-reference. Packaging/reportcommitสุดท้ายอาจต่อจากsub-resultcommitsได้

## Dispatch เฉพาะเมื่อ bundle จบ

ใช้ Standard/default เท่านั้น ห้าม Fast/1.5x หรือ fast/priority คง Astra/medium ตาม external `speed-policy.json`; ส่งต่อใน prompt/handoff ทุกครั้ง. ตรวจ effective tier เมื่อมีช่องทางรองรับ; `create_thread` ไม่มี serviceTier field จึงห้ามอ้าง enforcement จาก prompt/config. หากพบ Fast ให้เปลี่ยนเป็น default ผ่านช่องทางที่รองรับ มิฉะนั้นรายงานข้อจำกัดก่อนทำต่อ

1. ยืนยันlatestuserinstruction, all-packageacceptance, source/handoff และไม่มีdispatchของnextBundle. ปล่อยwriterแล้วreservebundleถัดไปแบบatomic
2. เรียก list_projects ยืนยัน savedGitproject `C:/Users/Phet/Documents/LexiQuest` และใช้IDจริง. create_threadเป็น native `worktree` ตามtooldefaults; ไม่ระบุstartingStateที่userไม่ได้สั่ง และไม่forkfullhistory
3. ใช้title/briefจาก `index.bundles`, modelAstra/medium. Promptระบุbundlepackages, sourceSHAจริง, predecessorhandoff/controlpaths, onebundlewriter,ทำภายในตามลำดับ และสิทธิ์ส่งต่อหนึ่งbundleหลังจบ
4. เก็บreceiptทันที. ตรวจtool isError/structuredContentและtextshapeก่อนparse; error textไม่ใช่JSON. clientThreadIdห้ามส่งเข้าread/waitที่ต้องใช้threadId. Resolveจากreceipt/run-state/app; listแบบboundedตามschema ไม่เดาIDและไม่retrycreateเมื่อผลยังไม่ชัด
5. ใช้wait_threadsกับactualIDหนึ่งครั้งเพื่อยืนยันprogress; boundedwaitไม่เกิน60sและbackoffเมื่อstateไม่เปลี่ยน. ส่งcreated-thread directiveตามtoolresult แล้วparentหยุดsourcewrites
6. B20/G8.9ไม่มีsuccessor; finalledgerแยกengineering/local/emulator/device/human/liveตามหลักฐานจริง. สิ่งrequiredยังค้างต้องเปิดเผย ไม่เรียกfullreleasePASS

## ลำดับ review และ Test Plan

B18ทำ G8.1 freeze → G8.2รีวิวโค้ดทั้งแอปทีละzone → G8.3แก้และปิดreview. B19จึงทำ G8.4 System Test Plan → G8.5 automated → G8.6 build/install/journeys → G8.7fault/accessibility/resources. B20ทำG8.8 defect/retest/regression → G8.9finalledger. การรวมtaskไม่ย้ายtestsก่อนreviewและไม่ลดcoverage/acceptance

ถ้าcontextใกล้เต็มให้checkpointในbundle report + structuredstateและใช้compactionในtaskเดิม. ไม่dispatchกลางbundleเพื่อแก้contextและไม่ย้อนทำacceptedpackages; resumeจากreceipt/currentPackageIdและinputsที่เปลี่ยน. Pause/stopใหม่หยุดdispatchและรักษาcheckpoint
