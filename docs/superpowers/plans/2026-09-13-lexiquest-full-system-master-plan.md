# LexiQuest Full-System Master Development Plan

> **Current execution authority:** หลังG0.5 ผู้ใช้อนุมัติหนึ่งtaskต่อชุดงานที่ใช้code/context/testsร่วมกัน ตาม [Bundle Workflow](../../development/full-system-package-workflow.md). คง64requirement packages; Astra/Medium; writerหนึ่งตัว ไม่มีsubagents/parallel implementation

**Revision:** 2026-09-13 / bundles-4
**Status:** GROUPED EXECUTION AUTHORIZED — G0.1–G0.5 accepted; 59packagesใน20bundles
**Goal:** ทำให้ LexiQuest เรียนภาษาอังกฤษแบบ local-first ได้จริง ปิด known coverage gaps โดยใช้ authority เดิม ตรวจโค้ดทั้งแอป แล้วทดสอบระบบที่พัฒนาเสร็จพร้อมเก็บปัญหาและผล retest  
**Architecture:** view → controller/use case → canonical repository/event/receipt → read model → view; AI/voice/camera/sync เป็น adapters ที่มี cancellation และ failure boundaries การเรียนหลักใช้ได้โดยไม่ต้องมี AI/cloud/การจ่ายเงิน  
**Tech Stack:** Flutter/Dart, Drift/SQLite, existing LiteRT/voice/AI gateways, Python camera tooling, existing backend/policy emulators และ `tool/cli/verify-scope.ps1`

คำสั่งใหม่หลังG0.5 เปลี่ยนจากหนึ่งtaskต่อpackageเป็นหนึ่งtaskต่อbundle. Accepted G0.5 SHA `9125ae7b9ccff15bb44ebbab455b8b0251c8fcfe` เป็นฐานrevisionนี้; 5ข้อแรกเก็บประวัติไม่ย้อนทำ. [Task/Bundle Index](../../development/full-system-task-index.json) แยก64requirementsจาก20futuredispatches. รับsourceจริงจากhandoff ไม่ใช้seed7712. [Rule Register](../../development/2026-09-13-rule-supersession-register.md) ยกเลิกper-packageauto-dispatchและบันทึกgroupedauthorizationที่แทนpause17; runtimePASSยังต้องมีหลักฐาน

## สารบัญและจำนวนงาน

แผนมี **9 หัวข้อหลัก (G0–G8), 64 หัวข้อย่อย (P0.1–P8.9)**. จำนวนนี้เป็น work packages ไม่ใช่จำนวน features หรือ tests. แต่ละ package ปิดช่องว่างตามข้อมูลจริง; ของที่ทำแล้วและหลักฐานยังตรง source ได้รับ baseline credit

| หัวข้อหลัก | จำนวนหัวข้อย่อย | ต้องผ่านก่อน | ผลส่งมอบหลัก |
| --- | ---: | --- | --- |
| G0 รวมฐานโค้ดและจัดระเบียบแผน | 8 | อนุมัติเริ่มแล้ว; G0.1 รับ source/ownership | source และ authority ที่เลือกมีเหตุผลครบ; baseline fixes, coverage, delivery decisions และข้อมูลเก่ามีทะเบียน |
| G1 ความถูกต้องของการเรียนและข้อมูล | 7 | G0 | owner/session/history/reward/time/SRS ถูกต้องหลัง retry, restart และไม่มี cloud |
| G2 บทเรียน มินิเกม และ UI foundation | 8 | G1 | 14 LessonModes และ 2 journeys มี interaction/availability/accessibility contract แยกกัน |
| G3 เนื้อหา การทบทวน และความก้าวหน้า | 7 | G1, G2 | content version, explanations, review, analytics และ assessment constraints ตรวจย้อนกลับได้ |
| G4 Today การนำทาง และแรงจูงใจ | 6 | G2, G3 | เริ่มฝึกง่าย มีอิสระเลือก; timer/goals/rewards/preferences ไม่สร้างข้อมูลซ้ำ |
| G5 กล้องและการประเมินโมเดล | 6 | G1, G4 | camera lifecycle และ uncertainty ใช้งานได้; candidate มีหลักฐานหรือคง baseline พร้อมข้อจำกัด |
| G6 AI Tutor และเสียง | 6 | G3, G4 | บริบทและ cancellation ปลอด stale state; no-key/no-audio fallback ใช้งานได้และบันทึก usage ตามจริง |
| G7 Backend, sync, policy และการเตรียมส่งมอบ | 7 | G1, G3, G5, G6 | owner lifecycle, offline recovery, runtime edition และ backend boundaries ผ่าน local acceptance |
| G8 รีวิวโค้ดทั้งแอป Test Plan และตรวจใช้งานจริง | 9 | G0, G1, G2, G3, G4, G5, G6, G7 | review ledger ครบ, Test Plan หลัง review, actual test/defect/retest evidence และ release ledger ที่ระบุข้อจำกัด |

ลำดับทำงานจริงเป็น serial G0 → G1 → G2 → G3 → G4 → G5 → G6 → G7 → G8 แม้บาง dependency จะอนุญาตขนานได้. G8 แบ่งเป็น freeze → whole-app review → review fixes → **ออก System Test Plan หลัง review** → execute → defect/fix/retest → final ledger. การทดสอบเฉพาะจุดระหว่างพัฒนาเป็นกิจกรรมของ package ไม่ต้องรอ Test Plan ฉบับสุดท้าย

## เอกสารและ source ที่มีอำนาจอ้างอิง

- [Current-system analysis และ source readiness](../../development/2026-09-13-current-system-and-plan-readiness.md) บันทึกข้อค้นพบ PLAN-01–PLAN-13 และข้อจำกัดการตรวจรอบนี้
- [Coverage audit](../../development/2026-09-13-master-plan-coverage-audit.md) มี COV-f01–f44, 14 LessonModes, Adventure/Ghost, exclusions และ observation gaps
- [Minigame contract](../specs/2026-09-13-minigame-coverage-contract.md) กำหนด MG-01–MG-14; MG-01 คือ WordQuest/wordScramble เดิม
- [Engineering spec](../specs/2026-09-12-r15-engineering-spec.md), [acceptance contract](2026-09-12-r15-acceptance-contract.md), [source register](../specs/2026-09-12-r15-source-register.md) และ [49-image manifest](../specs/2026-09-12-r15-evidence-manifest.json) เป็นข้อกำหนด/หลักฐานรอง
- [Work and coverage ledger](../../development/2026-09-13-full-system-work-ledger.json) เป็นดัชนี package/status/test targets และ coverage 74 records; ข้อความ acceptance เต็มอยู่ใน audit/spec/plan ไม่สร้าง catalog ใหม่
- R15.1–R15.10 และ [roadmap เดิม](2026-09-12-r15-autonomous-development-roadmap.md) เป็น milestone ที่ต้องรับงานเดิม ไม่ใช่คำสั่งทำซ้ำหรือสร้าง R15.11
- ต้นทาง application ที่อ่าน: `C:/Users/Phet/.codex/worktrees/842c/LexiQuest`, branch `feature/r15-integration-continuation`, HEAD `f4eebb895836349fbf8e9960312a78bad524d462` + F1–F4 working diff
- Worktree task นี้: `C:/Users/Phet/.codex/worktrees/7712/LexiQuest`, detached `7b8ac6cc029c0df43f9d4e7d161da3502e6f557b`. สอง HEAD มี unique commits 58/382 และไม่เป็น fast-forward; P0 ต้อง reconcile ก่อน code changes
- paths ของ source/test ในแต่ละ package อิง R15 ยกเว้น `functions/` และ `tool/cli/tests/verify-scope.tests.ps1` ที่เป็น input จากสาย main/7712. Planning documents ใหม่อยู่ 7712. ห้ามใช้ path list นี้เป็นคำสั่งคัดลอกไฟล์ทั้ง directory

## การตัดสินใจออกแบบจากหลักฐาน

ใช้แนวทาง **คำแนะนำพร้อมอิสระเลือกฝึก และแก้ delta ตาม authority เดิม**. ทางเลือก rewrite ทั้งระบบเพิ่มความเสี่ยง migration/history และงานซ้ำ; ทางเลือกปรับ UI ก่อนความถูกต้องข้อมูลทำให้ผลที่ผู้เรียนเห็นไม่น่าเชื่อถือ จึงเรียง data correctness ก่อน experience และเพิ่ม UI เมื่อ phase พร้อม

| Evidence ที่เก็บไว้ | การออกแบบที่จะตรวจรับ | Owner packages |
| --- | --- | --- |
| Duolingo correct/wrong/retry, E-D04/D05/D08 | feedback ที่อ่านได้, durable first/repair แยก, next action | P1.2, P2.1–P2.4, P3.4 |
| ALLTCAS Pair/flashcard/quiz/cloze, E-A05–A15 | controls ตามชนิดงาน, คืน tile ได้, explanation อยู่ใน viewport, keyboard/tap alternatives | P2.2–P2.7 |
| ALLTCAS short dialogue/explanation และ first5/6→repair1/1, E-A18–A25 | authored context/distractor revision, ผลไม่ทับประวัติ, review เสมอ | P3.1–P3.6 |
| Onboarding/path/catalog ของทั้งสองแอป | Today action มีเหตุผล, pack readiness และ manual practice | P3.1, P4.1, P4.6 |
| ALLTCAS AI follow-up และข้อความบางส่วนหาย, E-AI152–161 | bounded context, readable plain text, cancel/owner reset | P6.1–P6.3 |
| ALLTCAS timer/stat gate, E-SYS164/165 | active effort จริง, ไม่ล็อกสถิติพื้นฐานตามยอดชั่วโมง | P1.6, P3.5, P4.3 |
| WordQuest adaptation ตาม user clarification | wordScramble tiles→empty blocks, occurrence identity, tap/drag/คืน tile | P2.5 |

ผู้ใช้ยืนยันว่า “AuthiCast” หมายถึง ALLTCAS. หลักฐาน 49 ภาพ/4 วิดีโอและ reports เป็นข้อมูลการเก็บก่อนหน้า ไม่ใช่การทดลองใหม่รอบนี้. แยก observed / public-reference / inferred / not-verified; timing, caps, colors และ thresholds ที่ทีมเลือกเป็น engineering decisions ไม่อ้างว่าเป็นค่าที่วัดจากคู่เทียบ. ข้อเสนอ missing-letter mask ถูกยกเลิกและไม่มีงานเกมใหม่จากความเข้าใจผิดนั้น

## Global constraints

- Catalog 44 capabilities / 8 domains, 14 LessonModes, 2 journeys และ 14 MG groups เป็น coverage baseline ที่ตรวจแล้ว ไม่ใช่เพดานการพัฒนา. Scope/contract ที่ต้องปรับมี change record ใน master เดียว พร้อม version, compatibility และ acceptance; ไม่ให้ข้อจำกัดรุ่นเก่าปิดกั้นระบบที่จำเป็น
- ใช้ owner/history/evidence/reward/content authorities เดิม; widget/animation ไม่เขียนฐานข้อมูลหรือออก receipt เอง และไม่สร้าง dashboard calculator ซ้ำ
- หาก reconciliation พบ writer/schema สองสาย ให้ปิด semantic conflict ก่อนใช้ร่วมกัน; ไม่เชื่อม writer ซ้อนหรือทิ้ง main-only fixes โดยถือว่าเก่า
- Historical policy/receipt/evidence ไม่เปลี่ยนความหมายย้อนหลัง. การเปลี่ยน contract ใช้ versioned adapter/migration พร้อม export/delete/sync/policy coverage
- ใช้ free-first/local-first และ synthetic data/local emulators. ไม่มี real participant data, credentials, production writes หรือ API spending จากแผนนี้
- Research activation/synchronization/study assignment/statistical reporting อยู่ภายนอก production packages; ทดสอบขอบเขตด้วย synthetic fixtures ได้แต่ไม่เปิด research
- Shipped camera baseline คงอยู่จน candidate ผ่าน coverage/open-set/resource/physical/rollback gates ที่กำหนด; ไม่ train วนตาม fresh-test result
- ทำทีละpackageภายในbundle/taskเดียว มีwriterหนึ่งตัว. ตรวจและcommitผลย่อยได้; all-packageacceptance → bundlehandoff → releasewriter → สร้างnextbundleหนึ่งtask. ไม่dispatchต่อpackage/commitและไม่ใช้subagents/background implementation workers
- ใช้ verify-scope สำหรับ bounded targeted/subsystem checks; full release verifier เฉพาะ frozen PR/release SHA; Flutter/backend/Android/GPU ไม่รันพร้อมกัน
- ห้าม rerun passed gate เมื่อ recorded relevant source/dependency/config fingerprint ไม่เปลี่ยน. การเปลี่ยนเอกสารเพียงอย่างเดียวไม่เป็นเหตุ rerun application suite
- same command failure ซ้ำ, filesystem error ซ้ำ หรือไม่มี measurable progress 10 นาที: หยุดขั้นที่ผิดและรายงานพร้อมหลักฐาน; ห้ามวนคำสั่งเดิมโดยไร้ diagnosis
- ผู้ใช้อนุญาตปรับ UI/กติกาเดิมที่เป็น workaround เมื่อ evidence/decision/acceptance รองรับ; Prototype 3 ไม่ใช่ design lock
- Human/device/live evidence ที่ยังไม่มีเป็น NOT RUN/external-pending; แยก engineering completion กับ release acceptance และเปิดเผย edition ที่ยังไม่ครบ44runtime

## หน่วยข้อกำหนด64ข้อ และชุดงานสำหรับdispatch

G0–G8 มีข้อย่อย **8 / 7 / 8 / 7 / 6 / 6 / 6 / 7 / 9 = 64**. G/Pเป็นrequirement aliases; Bเป็นbundle/task. G0.1–G0.5 acceptedแล้ว; remaining59อยู่ใน20bundlesตาม [ตารางชุดงาน](../../development/full-system-bundle-map.md) และ [index](../../development/full-system-task-index.json). ทุกข้อ/acceptance/dependencyยังครบ

ทำpackagesตามลำดับในtask/worktreeเดียว อ่านbriefเมื่อถึงข้อและcommitacceptedsub-resultsตามเหมาะสม. ใช้MDหนึ่งรายงานต่อbundleกับstructuredlogs/receipts; ไม่เปิดtaskต่อcommitหรืออ่านประวัติทั้งหมด. สร้างsuccessorเฉพาะbundleจบตาม [workflow](../../development/full-system-package-workflow.md); nextPackageคือลำดับภายในเท่านั้น

## Workflow ของทุก package

1. **รับเข้า:** อ่าน checkpoint/current source เฉพาะส่วน, verify owner/branch/hash, ขอบเขตไฟล์, requirements, canonical interfaces, fixtures และ existing evidence. Gate ก่อนหน้าต้องพร้อม
2. **ตัดสิน delta:** แยก verified-existing / needs-verification / defect / delivery-gap / external-pending / deliberately-excluded. มี test file ไม่ใช่ PASS. สิ่งที่ทำแล้วไม่ต้องสร้างใหม่
3. **ออกแบบ delta:** ระบุ old behavior → evidence → new behavior → interfaces → lifecycle/error/owner effects → acceptance. ถ้าต้องแก้ contract/schema บันทึก version/migration. แก้ implementation เฉพาะที่พิสูจน์ว่าจำเป็น
4. **เตรียมตรวจรับ:** ใช้ tests เดิมเมื่อครอบคลุม; behavior/bug ที่เปลี่ยนเพิ่ม regression ที่ล้มเพราะอาการจริงก่อน fix. กรณี docs-only/ย้ายเอกสารที่ย้อนกลับได้ใช้ path/hash/link verification ไม่สร้าง test ที่เลียน implementation
5. **ดำเนินงาน:** แก้ owner files ของ package เดียว. การ setup/codegen/cleanup ที่จำเป็นอยู่กับ package นั้น; source/test ที่ไม่เกี่ยวข้องคงไว้
6. **ตรวจ:** focused GREEN → scoped analyzer/affected subsystem/visual states เมื่อเกี่ยวข้อง. ถ้า relevant inputs ยังตรง reuse result พร้อมหลักฐาน. บันทึก failure ตั้งแต่ครั้งแรก; expected negative case ไม่เปิดเป็น application defect
7. **Package review:** ตรวจ diff, callers, authority, regression oracle และ remaining limitations ด้วยตนเองแยกจาก implementation pass. ไม่อ้างเป็น independent external review
8. **ส่งออก:** requirements covered, source SHA+fingerprint, files, command/exit/count/time/log, content/model/config pins, findings/decisions, external gates, rollback และ next package. Commit เฉพาะไฟล์ที่ตรวจแล้วเมื่อเข้าสู่ execution และไม่มี unrelated changes ติดมา
9. **Phase close:** เทียบ coverage ทุก package ใน phase และ run affected integration เท่าที่จำเป็น. ปิด G เมื่อ required local acceptance มีหลักฐาน; failure ส่งกลับ package เจ้าของ ไม่เริ่ม roadmap ใหม่

สถานะ package ใน run-state: waiting-predecessor → ready → in-progress → verified → accepted; phaseStatus แยกต่างหาก. Ledger เก็บข้อกำหนดและสถานะตั้งต้น ส่วน run-state/handoffs เก็บสถานะ execution จริง. `blocked`/external-pending ต้องมีเหตุผลและ next condition; ไม่ใช้ blank แทนเสร็จ. Gate ที่ผ่านอยู่แล้วกลับมารับ delta เฉพาะเมื่อ change/defect กระทบจริง

**Dependency interfaces ที่ห้ามทำซ้ำ:** LearningUseCases/CurrentActivityEvidenceAdapter → acknowledged learning operations; owner repository/gate → active owner identity; content manifests → exact revision/readiness; reward use cases → transaction/receipt identity; progress/history/Today readers → read-only snapshots; AI/media gateways → request/attempt identity + typed failure. ใช้ signatures จาก reconciled source ขณะเข้า package ไม่สร้าง API จากชื่อที่คาดเดา

## ทะเบียนสูตรและกฎคำนวณ 12 กลุ่ม

ตัวเลขในตารางนี้มาจาก source ที่อ่านหรือเป็น expected fixture ตาม acceptance ไม่ใช่ข้อเสนอ efficacy/สถิติวิจัย. P0.7 pin authority/policy version อีกครั้งหลัง reconcile; P1/P3/P4/P5/P6 ทดสอบตาม owner package

| ID | Authority และกฎที่ต้องรักษา | Boundary fixtures / expected result | Package |
| --- | --- | --- | --- |
| FORM-01 | first-answer accuracy = correct first eligible answers / first eligible n; repair/exposure/self-report แยก | first5/6 + repair1/1 ยังคง5/6; n=0=noEvidence; duplicateackไม่เพิ่มn | P1.2, P1.3, P3.5 |
| FORM-02 | PairStarPolicy v1 เป็น descriptive projection: ยังไม่terminalack→null; perfect first/no support→3; independent×4≥matched×3→2; ที่เหลือ→1 | finalpairpendingไม่มีstars; boundary75%; firstwrongแล้วrepairไม่กลายเป็นperfect; starsไม่grantrewards | P2.2 |
| FORM-03 | BinarySm2SrsPolicy v2: correct intervals1,3,7,14 แล้วdouble cap36500; wrong interval1/repetitions0/lapse+1; difficulty correct−0.03 floor0.1 / wrong+0.12 cap1 | UTCrequired; correct5ครั้ง→28days; wrongreset1; overdue/timezone/largeintervalไม่overflow; dueAt=nowUtc+interval | P1.5 |
| FORM-04 | Reward receipt/event identity + AvatarProgressionPolicy v1: level=floor(lifetimeXP/20)+1; xpIntoLevel=XP mod20; next=level×20 | XP0/19/20/39/40→levels1/1/2/2/3; coins spendไม่ลดlifetimeXP; duplicategrant/unlock/purchaseไม่ซ้ำ | P1.2, P4.4, P4.5 |
| FORM-05 | StreakPolicy v2 / timezone policy ใช้ eligible local day; same day idempotent; one missed dayใช้freezeตามpolicy; clockย้อนกลับถูกปฏิเสธ | daydiff0/1/2/>2; freeze0/1; longestคงไว้; ไม่คำนวณวันด้วย UTC24h อย่างเดียว | P4.4 |
| FORM-06 | ActiveLearningTimeController + repository segments; monotonic durationเฉพาะactive; idle default5minและpause/backgroundไม่นับ | active30s+pause60s+active30s→60s; duplicate/overlapไม่เพิ่มซ้ำ; restart/clockrollbackไม่ติดลบ | P1.6, P4.3 |
| FORM-07 | Calendar/goals/countdown ใช้ timezone-aware reader ของแต่ละowner; weekly accuracy/effortมาจากsourcesเดียวกับdashboard | Bangkok23:59→00:01, week boundary, เปลี่ยนtimezone, due yesterday/today/tomorrow; missing≠zero | P3.5, P4.2 |
| FORM-08 | AssessmentComparison: compatible instrument/form/content/policy/build/owner metadata; c/n และ post−pre แยก unit | pre5/6=83.333…%,post6/6=100%→+16.667percentage points; missingpair/incompatible/duplicateitemไม่คำนวณ | P3.6 |
| FORM-09 | camera_accuracy.py: explicit raw→mapped baseline + accepted bool; known/unknown denominators, Wilson95; zero n→null | baselineunmapped=inputerror, acceptedunknownยังเป็นfalseaccept; NaN/bool threshold invalid; testdataไม่ใช้tune; acceptance thresholdตามspec | P5.2, P5.4, P5.5 |
| FORM-10 | Speech/Shadowing use cases: recognized-text comparison ตามexistingnormalization; separate scored activityกับunscoredpanel | emptyreference/no-speech/cancel/latefinal; ไม่มีacousticpronunciation claimและไม่มี0%skillจากdevicefailure | P6.4, P6.5 |
| FORM-11 | Word/Sentence mode adapters + evidence profiles; occurrence IDs คุมtile/tokenซ้ำ; correctnessอยู่adapter | letterมีt/eซ้ำ,คืนtile,duplicatesentenceword,punctuation; letterbankเป็นconstructionsupportไม่ใช่independentrecallโดยอัตโนมัติ | P2.5 |
| FORM-12 | AI use cases / DriftAiUsageRepository / central cost policy; attemptid, pending→finalized once, providerusage/cost versus estimateแยก | duplicatefinalizeไม่เพิ่มusageซ้ำ; cancel/retryตามattemptจริง; missingtokens/costไม่ตีเป็น0; ไม่มีราคาliveที่คาดเดา | P6.1, P6.3, P6.6 |

## หัวข้อย่อยและเกณฑ์ตรวจรับ

ทุก `Owner files` คือจุดเริ่มตรวจ/แก้ตาม delta ไม่ใช่คำสั่งเขียนทุกไฟล์. `Test targets` เป็น targets ที่มีอยู่ใน source ที่ระบุและต้องตรวจความตรงหลัง reconcile; ไม่ใช่ผลรันทดสอบ. Package ที่ทดสอบแบบ device/backend/review ใช้ protocol เฉพาะในตอนท้ายแทนการแสร้งระบุ Flutter test แทนสิ่งที่มันพิสูจน์ไม่ได้

## G0 — รวมฐานโค้ดและจัดระเบียบแผน (8 หัวข้อย่อย)

**Dependency:** ผู้ใช้อนุมัติเริ่มแล้ว; bootstrap source/ownership ใน G0.1 · **Gate outcome:** source และ authority ที่เลือกมีเหตุผลครบ; baseline fixes, coverage, delivery decisions และข้อมูลเก่ามีทะเบียน

### P0.1 ยืนยัน worktree และสิทธิ์เขียน

- [ ] **งานและการออกแบบ:** ตรวจ HEAD/branch/dirty files ของ own worktree, 7712 และ 842c รวม status ของ tasks ที่เกี่ยวข้อง; รับเอกสาร seed ตาม bootstrap manifest หลังตรวจ hash/collision; ระบุ writer เดียวและตั้ง isolated branch `codex/` จากฐานที่ตรวจจริง. Commit เอกสาร/bootstrap manifest ที่รับแล้วและระบุ source candidate + pending reconciliation ให้ G0.2; การรับ repairs อยู่ G0.2 และ main/R15 semantic reconciliation อยู่ G0.3
- **Owner files:** `AGENTS.md`, `docs/development`, `docs/superpowers/plans`, `docs/superpowers/specs`, `docs/superpowers/task-briefs/full-system` (bootstrap เฉพาะ paths ใน manifest; ไม่แก้ application ใน G0.1)
- **Requirements:** PLAN-01, G0 · **รับเข้าจาก:** คำสั่งอนุมัติของผู้ใช้
- **ตรวจรับ:** มี own/source manifest, collision dispositions, current authority revision, accepted bootstrap commit และ writer ownership ที่ตรวจได้. ไม่มีการเขียน source842c หรือเริ่ม implementation ของ package อื่น; G0.1–G0.2ได้ส่งต่อและacceptedในประวัติแล้ว ไม่ใช้ข้อนี้dispatchซ้ำ; งานต่อใช้bundleworkflow
- **Verification:** ตรวจตาม source-inspection protocol; ไม่ใช้การรัน Flutter แทนหลักฐานชนิดนี้

### P0.2 รับ F1–F4 และแยก generated files

- [ ] **งานและการออกแบบ:** เทียบ six-file manifest กับ 842c, diff กับ f4eebb89, อ่าน RED/GREEN logs แบบเจาะจง; รับเฉพาะ repair files และ docs ที่อธิบายจริง บันทึก disposition ของ platform registrants 7 ไฟล์และเก็บต้นฉบับ
- **Owner files:** `lib/screens/ai_tutor_screen.dart`, `tool/cli/verify-scope.ps1`, `tools/camera_accuracy.py`
- **Requirements:** PLAN-02, PLAN-03, G0 · **รับเข้าจาก:** P0.1
- **ตรวจรับ:** F1–F4 ไม่ถูกแก้ซ้ำ; reuse ผลได้เมื่อ source/dependencies/config pins ครบและตรงเท่านั้น; ถ้าไม่ตรงรันเฉพาะ impacted targets ผ่าน verify-scope เมื่อรองรับ ไม่อ้าง hash 6 ไฟล์แทนทั้ง suite
- **Verification:** `test/screens/ai_tutor_screen_test.dart`, `tool/cli/tests/r15-scope.tests.ps1`, `tools/test_camera_accuracy.py`

### P0.3 แจกแจง Git สองสายและเลือก authority

- [ ] **งานและการออกแบบ:** จัด non-merge changes ของ main-only 58 commits และ R15-only 382 commits เป็น equivalent/applicable/conflict/superseded; ตรวจ runtime init, storage, trusted progress/economy, Android identity, dependency และ release changes เป็นพิเศษ
- **Owner files:** `lib/runtime/app_bootstrap.dart`, `lib/data/local`, `functions`
- **Requirements:** PLAN-01, G0 · **รับเข้าจาก:** P0.2
- **ตรวจรับ:** ทุก semantic change ที่เกี่ยวกับ edition มี disposition และ owner package; ปิดความขัดแย้ง writer/schema/bootstrap ก่อน G0; ไม่ cherry-pick หรือ merge ทั้งสองสายอัตโนมัติและไม่ทิ้ง main fixes เพราะชื่อเก่า
- **Verification:** ตรวจตาม source-inspection protocol; ไม่ใช้การรัน Flutter แทนหลักฐานชนิดนี้

### P0.4 ยืนยันตัวตรวจแบบมีขอบเขตและการ reuse ผล

- [ ] **งานและการออกแบบ:** ทำ command registry ของ Targeted/Subsystem/Release, ตรวจ parameter และ input closure ของ F2; บันทึก source/dependency/config/test selection พร้อม log directory; เลือก gate ที่ยังไม่เคยผ่าน source เดียวกัน
- **Owner files:** `tool/cli/verify-scope.ps1`, `tool/final_test_plan/generate_final_test_plan.dart`
- **Requirements:** PLAN-02, PLAN-11, G0 · **รับเข้าจาก:** P0.3
- **ตรวจรับ:** Resume ไม่ยอมรับผลเมื่อ relevant inputs เปลี่ยนและ skip ผลที่ตรงจริง; ขั้น plan-only ตรวจ schema/path เท่านั้น; full release verifier รอ frozen PR/release SHA
- **Verification:** `tool/cli/tests/r15-scope.tests.ps1`, `tool/cli/tests/verify-scope.tests.ps1`

### P0.5 ปิดทะเบียน coverage และ traceability

- [ ] **งานและการออกแบบ:** เชื่อม 44 features / 8 domains, 14 modes, Adventure/Ghost และ 14 MG groups กับ requirement, route/config, content readiness/version, authority, package และ evidence; เติมรายละเอียดหลังเลือก source จริง
- **Owner files:** `docs/generated/alltcas-idea-integration-feature-map.json`, `lib/features/learning/domain/lesson_mode.dart`, `docs/superpowers/specs/2026-09-13-minigame-coverage-contract.md`
- **Requirements:** COV-f01–f44, MODE-all, MG-01–MG-14, G0 · **รับเข้าจาก:** P0.4
- **ตรวจรับ:** coverage 74 records ไม่มี unassigned row; foundation ที่ไม่มี route อธิบาย consumer boundary; status needs-verification/delivery-gap/external-pending ไม่ถูกแปลงเป็น verified-existing จากการมีไฟล์
- **Verification:** `test/architecture/alltcas_idea_feature_contract_test.dart`, `test/features/learning/lesson_mode_registry_test.dart`

### P0.6 จัดเอกสารเก่าและไฟล์ซ้ำอย่างย้อนกลับได้

- [ ] **งานและการออกแบบ:** ทำ Active index ที่ชี้ Master Plan เดียว; รายงาน observations คง historical และ old source claims มี supersession note. ตรวจ inbound refs ของ cleanup candidates รวม tracked failure PNG 76 ไฟล์; ทำ dry-run, hash manifest, archive/restore map ก่อนลบเฉพาะไฟล์ที่พิสูจน์ว่าไม่ใช้
- **Owner files:** `docs/development/r15-package-workflow.md`, `docs/development`, `docs/superpowers`
- **Requirements:** PLAN-04, PLAN-10, G0 · **รับเข้าจาก:** P0.5
- **ตรวจรับ:** ไม่มีข้อมูลเรียน/history/receipts/consent/migrations/goldens/provenance ถูกลบ; references ยัง resolve; active queue ไม่มี R15 auto-spawn/R15.11/old branch rule ชนคำสั่งใหม่; G0.1–G8.9 ส่งต่อได้ตาม sequential workflow; รายการที่ต้องเก็บมีเหตุผล ไม่ลบตามอายุไฟล์
- **Verification:** ตรวจตาม cleanup-review protocol; ไม่ใช้การรัน Flutter แทนหลักฐานชนิดนี้

### P0.7 ทำทะเบียนสูตรและข้อมูลอ้างอิง

- [ ] **งานและการออกแบบ:** ตรวจ formula register 12 กลุ่มใน Master Plan เทียบ source ที่ reconcile แล้ว; จด policy version, inputs, denominator, missing behavior, writer/reader, boundary fixtures และ package ทดสอบ ไม่เพิ่ม calculator ใหม่
- **Owner files:** `lib/features/learning/domain/srs_policy.dart`, `lib/features/rewards/domain/avatar_progression_policy.dart`, `lib/features/learning/pair_matching/domain/pair_star_policy.dart`
- **Requirements:** FORM-01–FORM-12, G0 · **รับเข้าจาก:** P0.6
- **ตรวจรับ:** ทุกสูตรมี authority และ expected cases ที่คำนวณได้; ถ้าพบ behavior ต่างจากเจตนามี defect แยกจาก proposal; เปลี่ยนสูตรต้อง version/adapter และรักษาการตีความประวัติ
- **Verification:** ตรวจตาม formula-inspection protocol; ไม่ใช้การรัน Flutter แทนหลักฐานชนิดนี้

### P0.8 ตกลง edition และปิด gate เริ่มพัฒนา

- [ ] **งานและการออกแบบ:** กำหนด local preview edition, target device, content availability และ activation matrix; ยืนยัน f23 ที่ bootstrap เปิด internal เมื่อ learningPreviewEnabled และตัดสิน f12 ที่ยัง implementedOff; f28 คง research fail-closed และแสดงข้อจำกัดจนมี personal-assessment decision ที่ไม่เปลี่ยน research authority
- **Owner files:** `lib/runtime/app_dependencies.dart`, `lib/features/learning/application/lesson_mode_registry.dart`, `lib/features/time_tracking/application/focus_timer_rollout.dart`
- **Requirements:** COV-f12, COV-f23, COV-f28, COV-f41, G0 · **รับเข้าจาก:** P0.7
- **ตรวจรับ:** G0 ปิดได้เมื่อ source ownership/authority conflict/coverage assignment/cleanup disposition พร้อม; ผู้ใช้ทราบกรณี edition ยังไม่ครบ 44 runtime; ไม่มีการเปิด cloud/research/paid/model rollout จาก gate นี้
- **Verification:** `test/runtime/runtime_feature_controls_test.dart`, `test/features/learning/lesson_mode_registry_test.dart`

## G1 — ความถูกต้องของการเรียนและข้อมูล (7 หัวข้อย่อย)

**Dependency:** G0 · **Gate outcome:** owner/session/history/reward/time/SRS ถูกต้องหลัง retry, restart และไม่มี cloud

### P1.1 วงจร owner และ session ที่มี authority เดียว

- [ ] **งานและการออกแบบ:** ติดตาม Today→launch→activity→result บน owner A/B พร้อม owner switch ระหว่าง await; ให้ callbacks ตรวจ session/owner identity และใช้ use case เดิม
- **Owner files:** `lib/features/learning/application/learning_use_cases.dart`, `lib/features/identity`, `lib/runtime/learning_dependencies.dart`
- **Requirements:** COV-f05, COV-f13, COV-f40, G1 · **รับเข้าจาก:** G0
- **ตรวจรับ:** stale callback ไม่บันทึกให้ owner ใหม่; session ถูกเปิด/ปิดครั้งเดียวและ ordinary learning ยังใช้ได้เมื่อ account/cloud ไม่พร้อม
- **Verification:** `test/features/learning/learning_use_cases_test.dart`, `test/features/identity/upgrade_guest_owner_test.dart`, `test/features/learning/unified_lesson_controller_test.dart`

### P1.2 first attempt, repair และ retry ที่ไม่เพิ่มรางวัลซ้ำ

- [ ] **งานและการออกแบบ:** ตรวจ repeated tap, lost ack, retry write, final callback และ partial success ระหว่าง evidence/reward; first/repair/support/exposure ใช้ identity กับ eligibility เดิม
- **Owner files:** `lib/features/learning/application/current_activity_evidence.dart`, `lib/features/learning/pair_matching/domain`, `lib/features/rewards/application/reward_use_cases.dart`
- **Requirements:** COV-f17, COV-f24, COV-f43, FORM-01, FORM-04, G1 · **รับเข้าจาก:** P1.1
- **ตรวจรับ:** fixture first5/6+repair1/1 คง first5/6; repeated operation มี durable effect ครั้งเดียว; widget/animation ไม่เพิ่ม XP/coins/SRS เอง
- **Verification:** `test/features/learning/current_activity_evidence_test.dart`, `test/features/learning/learning_side_effect_reconciler_test.dart`, `test/features/rewards/reward_use_cases_test.dart`

### P1.3 History และ replay บน content version เดิม

- [ ] **งานและการออกแบบ:** ตรวจ result→History→replay→Today ด้วย content revision เก่า/หาย/ถูกแทนและ owner เปลี่ยน; ใช้ historical metadata pin
- **Owner files:** `lib/features/history`, `lib/screens/learning_history_screen.dart`
- **Requirements:** COV-f43, FORM-01, G1 · **รับเข้าจาก:** P1.2
- **ตรวจรับ:** replay ไม่เปลี่ยน first result หรือ grant ซ้ำ; metadata หายแสดง unavailable แทนดึง title/answer ล่าสุดมาปลอมประวัติ
- **Verification:** `test/features/history/learning_history_reader_test.dart`, `test/features/history/learning_history_replay_test.dart`, `test/screens/learning_history_screen_test.dart`

### P1.4 restart, migration และการกู้จาก partial write

- [ ] **งานและการออกแบบ:** ใช้ temporary file-backed store ปิด/เปิดใหม่ก่อนและหลัง commit/lost ack; ตรวจ migrations เฉพาะที่สองสาย Git หรือ schema delta กระทบ; เปิดกลับด้วย dependency instance ใหม่
- **Owner files:** `lib/data/local`, `lib/features/learning/data`, `lib/features/sync`
- **Requirements:** COV-f40, COV-f43, G1 · **รับเข้าจาก:** P1.3
- **ตรวจรับ:** durable state ตรง ledger หลัง reopen; ไม่มี migration ที่ทำข้อมูลหายหรือ silently reset DB; test fixtures แยกจากข้อมูลผู้ใช้
- **Verification:** `test/scenarios/file_backed_sync_recovery_test.dart`, `test/features/learning/learning_recovery_foundation_test.dart`, `test/features/learning/drift_learning_repository_test.dart`

### P1.5 evidence eligibility และตารางทบทวน SRS

- [ ] **งานและการออกแบบ:** ตรวจ recognition, typed recall, guided support, self-report, delayed review และ assessment มี classification ตามสัญญา; policy v2 ใช้ UTC และ interval boundaries
- **Owner files:** `lib/features/learning/domain/evidence_context.dart`, `lib/features/learning/domain/srs_policy.dart`, `lib/features/learning/application`
- **Requirements:** COV-f06, COV-f11, COV-f15, FORM-03, G1 · **รับเข้าจาก:** P1.4
- **ตรวจรับ:** due intervals 1/3/7/14 แล้ว double ไม่เกิน 36500, wrong reset1day; ไม่ยกระดับ self-rating เป็น independent recall และไม่เอา assessment ไปเพิ่ม engagement
- **Verification:** `test/features/learning/evidence_eligibility_policy_test.dart`, `test/features/learning/srs_policy_test.dart`, `test/features/learning/assessment_evidence_isolation_test.dart`

### P1.6 เวลาเรียนและตัวเลขจาก read models

- [ ] **งานและการออกแบบ:** ตรวจ active/pause/idle/background, monotonic rollback, duplicate segment, overlapping captures และ owner/timezone; เทียบ dashboard/calendar จาก segment authority เดียว
- **Owner files:** `lib/features/time_tracking`, `lib/features/progress/data`, `lib/features/progress/domain`
- **Requirements:** COV-f24, COV-f25, COV-f36, FORM-06, FORM-07, G1 · **รับเข้าจาก:** P1.5
- **ตรวจรับ:** พัก 60s ไม่เพิ่ม effort; n=0 เป็น noEvidence; manual timer กับ lesson ไม่ถูกนับสองครั้ง; display totals มี numerator/denominator/source
- **Verification:** `test/features/time_tracking/active_learning_time_controller_test.dart`, `test/features/time_tracking/learning_time_repository_test.dart`, `test/features/progress/learning_calendar_reader_test.dart`

### P1.7 cold start แบบ local และ runtime fixes ที่เกี่ยวข้อง

- [ ] **งานและการออกแบบ:** นำเฉพาะ main runtime/storage fixes ที่ P0.3 ตัดสินว่าจำเป็นมารวมกับ R15; ตรวจ offline/new install/no key/installed content/dependency missing; ห้าม eager initialize remote client จนทำ local start ล้ม
- **Owner files:** `lib/runtime/app_bootstrap.dart`, `lib/runtime/app_dependencies.dart`, `lib/runtime/production_feature_gate.dart`
- **Requirements:** COV-f40, COV-f41, G1 · **รับเข้าจาก:** P1.6
- **ตรวจรับ:** เปิดแอปและเรียนจากเนื้อหาที่ติดตั้งได้โดยไม่มี AI/cloud; ถ้าไม่มี pack แสดง readiness/ทางเลือกตรงจริง; main delta ที่ใช้มี regression และ source pin
- **Verification:** `test/screens/production_shell_navigation_test.dart`, `test/scenarios/runtime_kill_switch_journey_test.dart`, `test/screens/offline_vocabulary_journey_test.dart`

## G2 — บทเรียน มินิเกม และ UI foundation (8 หัวข้อย่อย)

**Dependency:** G1 · **Gate outcome:** 14 LessonModes และ 2 journeys มี interaction/availability/accessibility contract แยกกัน

### P2.1 UI tokens และ shell ร่วมทุกโหมด

- [ ] **งานและการออกแบบ:** ปรับ templates T-01–T-07/tokens UI-01–UI-12 จาก spec เดิมด้วย state-driven feedback; header/progress/CTA เชื่อม acknowledged activity; ตรวจ 320/390/840 widths, light/dark, textScale2, focus และ reduced motion
- **Owner files:** `lib/config/m3_theme.dart`, `lib/features/learning/presentation/unified_lesson_shell.dart`, `lib/features/accessibility`
- **Requirements:** COV-f05, COV-f38, COV-f39, A-UI, G2 · **รับเข้าจาก:** G1
- **ตรวจรับ:** ไม่มี overflow/ข้อความเฉลยนอก viewport; touch target≥48; feedback มีข้อความและสัญลักษณ์; layout เปลี่ยนได้ตาม decision trace และไม่รอ animation เพื่อ commit ผล
- **Verification:** `test/features/learning/unified_lesson_controller_test.dart`, `test/features/learning/r15_learning_feedback_visual_test.dart`

### P2.2 Pair Matching ทุก state และความหนาแน่น

- [ ] **งานและการออกแบบ:** รับ R15 Pair feedback เป็นฐาน; ตรวจ 4/6 pairs, selected/correct/wrong/support/repair/final pair, keyboard/focus และ restart/timeout; ใช้ engine เป็นตัวตัดสิน
- **Owner files:** `lib/features/learning/pair_matching/presentation`, `lib/features/learning/pair_matching/domain`
- **Requirements:** COV-f10, COV-f17, MG-05, A-PAIR, FORM-02, G2 · **รับเข้าจาก:** P2.1
- **ตรวจรับ:** final durable state ไม่รอ animation; support ไม่ถูกอ่านเป็น correct animation; stars/first/repair ตรง projection และ replay ไม่เพิ่ม evidence/reward
- **Verification:** `test/features/learning/pair_matching/pair_star_policy_test.dart`, `test/features/learning/matching_mode_adapter_test.dart`

### P2.3 Meaning, Definition และ Typed Recall

- [ ] **งานและการออกแบบ:** ตรวจ Thai→English/English→Thai, English definition จริง, typed input/IME/normalization/alternative answer; unsupported/missing content ต้องปฏิเสธก่อน start; แยก recognition จาก production evidence
- **Owner files:** `lib/screens/quiz_screen.dart`, `lib/features/learning/application`, `lib/features/learning/presentation`
- **Requirements:** COV-f07, COV-f08, COV-f11, MG-02, MG-06, MG-07, G2 · **รับเข้าจาก:** P2.2
- **ตรวจรับ:** โหมดที่เลือกตรง prompt และ evidence; submitted answer ทำ progress ตาม durable ack; wrong/skip/help/duplicate ไม่กลายเป็นคะแนนแรกปลอม
- **Verification:** `test/screens/quiz_screen_test.dart`, `test/features/learning/definition_quiz_mode_adapter_test.dart`, `test/features/learning/native_mode_adapters_test.dart`

### P2.4 Cloze แบบเลือกและพิมพ์

- [ ] **งานและการออกแบบ:** ตรวจ single/multiple blank, selection change, typed answer, valid alternatives, grouped question count และ explanation revision; ล็อก answer ตาม submit policy
- **Owner files:** `lib/screens/quiz_screen.dart`, `lib/features/learning/application/cloze_mode_adapter.dart`, `lib/features/learning/presentation`
- **Requirements:** COV-f09, COV-f17, MG-03, MG-04, G2 · **รับเข้าจาก:** P2.3
- **ตรวจรับ:** selected และ typed ใช้ evidence profile ต่างกัน; blank/ambiguous answer ไม่ผ่าน readiness; help ที่เผยคำตอบบันทึก support และ count ไม่เพิ่มตามจำนวน widgets
- **Verification:** `test/features/learning/cloze_mode_adapter_test.dart`, `test/screens/quiz_screen_test.dart`

### P2.5 WordQuest block spelling และ Sentence Scramble

- [ ] **งานและการออกแบบ:** ใช้ wordScramble เดิม: tiles→empty blocks, tap/drag/คืน tile; ตรวจคำ letter ที่มี t/e ซ้ำด้วย occurrence index, punctuation/duplicate tokens ของ sentence, pending writes, owner/dispose/resize/keyboard
- **Owner files:** `lib/screens/word_scramble_screen.dart`, `lib/screens/sentence_scramble_screen.dart`, `lib/features/learning/application/current_activity_evidence.dart`
- **Requirements:** COV-f13, MG-01, MG-08, FORM-11, G2 · **รับเข้าจาก:** P2.4
- **ตรวจรับ:** ผ่าน MG-01-A–F รวม repeated-letter widget interaction และ no per-tile reward; ไม่สร้าง missing-letter mask game; no content มี unavailable; response lock/retry ตรง durable evidence
- **Verification:** `test/screens/word_scramble_screen_test.dart`, `test/screens/sentence_scramble_screen_test.dart`

### P2.6 Flashcard และ scratchpad ที่ไม่สร้างคะแนนเทียม

- [ ] **งานและการออกแบบ:** ตรวจ flip/reveal/self-rating/due SRS; พิจารณา local delivery ของ scratchpad ตาม P0.8 โดยใช้ component/controller เดิม; เขียน/undo/clear/rotate/exit/typed alternative อยู่ใน memory
- **Owner files:** `lib/screens/srs_flashcards_screen.dart`, `lib/features/learning/presentation/handwriting_scratchpad.dart`, `lib/features/learning/application/lesson_mode_registry.dart`
- **Requirements:** COV-f06, COV-f12, MG-11, G2 · **รับเข้าจาก:** P2.5
- **ตรวจรับ:** เปิด scratchpad เฉพาะ edition ที่มี route/cleanup tests ครบ; ไม่มี OCR/autograde/reward จาก self-check; retire/controller replacement ล้างข้อมูล ephemeral และไม่ล้างคำศัพท์
- **Verification:** `test/screens/srs_flashcards_screen_test.dart`, `test/features/learning/handwriting_scratchpad_test.dart`, `test/features/learning/lesson_mode_registry_test.dart`

### P2.7 Session configuration และ interaction contract 14 โหมด

- [ ] **งานและการออกแบบ:** จัด matrix จำนวนข้อ/เวลา/direction/mode/content readiness; ตรวจ launch/pause/resume/exit/back/skip หรือ not-supported ต่อโหมด, IME/keyboard/safe area และ content เปลี่ยนระหว่างตั้งค่า
- **Owner files:** `lib/features/learning/presentation/session_configuration_sheet.dart`, `lib/features/learning/application/lesson_mode_registry.dart`, `lib/features/learning/domain/lesson_mode.dart`
- **Requirements:** COV-f05, COV-f16, COV-f19, MODE-all, G2 · **รับเข้าจาก:** P2.6
- **ตรวจรับ:** invalid/unsupported config ถูกปฏิเสธก่อน session; default enabled ไม่ถูกใช้แทน actual registry readiness; 14 mode records มี lifecycle/result contract แยกกัน
- **Verification:** `test/features/learning/session_configuration_policy_test.dart`, `test/features/learning/session_configuration_sheet_test.dart`, `test/features/learning/session_configuration_store_test.dart`

### P2.8 Reading, Adventure และ Ghost journeys

- [ ] **งานและการออกแบบ:** ตรวจ associative/CEFR reading, Adventure mixed review→result→next/replay และ Ghost identity/time/result ตาม engine ที่มี; trace route จริงจาก production contract
- **Owner files:** `lib/features/adventure`, `lib/screens`, `lib/features/learning/application/native_mode_adapters.dart`
- **Requirements:** COV-f13, COV-f15, MG-10, MG-13, MG-14, G2 · **รับเข้าจาก:** P2.7
- **ตรวจรับ:** การอ่านเป็น exposure ตาม policy; ghost/Adventure ไม่สร้าง writer ใหม่; content unavailable ไม่ fake session; journey records แยกจาก enum และไม่เพิ่ม feature count
- **Verification:** `test/features/adventure/application/adventure_mixed_review_controller_test.dart`, `test/features/adventure/presentation/adventure_mixed_review_screen_test.dart`, `test/features/learning/native_mode_adapters_test.dart`

## G3 — เนื้อหา การทบทวน และความก้าวหน้า (7 หัวข้อย่อย)

**Dependency:** G1, G2 · **Gate outcome:** content version, explanations, review, analytics และ assessment constraints ตรวจย้อนกลับได้

### P3.1 Catalog และ pack detail จาก metadata จริง

- [ ] **งานและการออกแบบ:** ตรวจ CEFR/topic/skill/goal filters, revision/checksum, lesson count, available modes, pack selection change; ใช้ catalog/content authority เดิม
- **Owner files:** `lib/features/learning_packs`, `lib/screens/learning_pack_catalog_screen.dart`, `lib/screens/learning_pack_detail_screen.dart`
- **Requirements:** COV-f01, COV-f02, COV-f04, G3 · **รับเข้าจาก:** G1, G2
- **ตรวจรับ:** unknown/empty/missing revision มี readiness state; detail กับ launch ตรง pack/version; ไม่มี fake content และ progress ของ pack เก่าค้างใน pack ใหม่
- **Verification:** `test/screens/learning_pack_catalog_screen_test.dart`, `test/screens/learning_pack_detail_screen_test.dart`, `test/features/learning_packs/learning_pack_detail_test.dart`

### P3.2 Rich lexical card และคุณภาพเนื้อหา

- [ ] **งานและการออกแบบ:** ตรวจ meaning/POS/CEFR/IPA/audio/example/synonym/antonym ทีละ field, authored versus AI, CEFR approximation, reviewed publication/checksum และ asset provenance
- **Owner files:** `lib/widgets/rich_lexical_card.dart`, `lib/features/learning_packs/domain/content_quality_policy.dart`, `lib/features/vocabulary`
- **Requirements:** COV-f03, COV-f04, G3 · **รับเข้าจาก:** P3.1
- **ตรวจรับ:** missing fields ไม่แต่งข้อมูล; rejected/unreviewed content ไม่ถูกแสดงเป็น approved; ภาพ/เสียงมี provenance; flip card ไม่เพิ่ม mastery
- **Verification:** `test/widgets/rich_lexical_card_test.dart`, `test/features/learning_packs/content_quality_policy_test.dart`, `test/features/vocabulary/cefr_sense_review_test.dart`

### P3.3 เฉลย คำใบ้ Bookmark และ Report

- [ ] **งานและการออกแบบ:** เฉลยเจาะตัวลวงที่เลือกและ revision เดิม; expand/collapse รักษา scroll; save/unsave/report ผ่าน use cases, local pending/error/success; hint-reveals มี provenance
- **Owner files:** `lib/features/learning/presentation`, `lib/features/review`, `lib/screens/quiz_screen.dart`
- **Requirements:** COV-f18, COV-f19, COV-f20, COV-f21, G3 · **รับเข้าจาก:** P3.2
- **ตรวจรับ:** ไม่มี AI fallback อัตโนมัติมาปลอม reviewed explanation; report ไม่แสดงส่งสำเร็จเมื่อแค่ค้าง local; bookmark/report idempotent และไม่เพิ่มคะแนน; lifecycle เต็มต่อใน P7.4
- **Verification:** `test/features/learning/contrastive_feedback_test.dart`, `test/features/learning/hint_policy_test.dart`, `test/features/review/content_report_use_cases_test.dart`

### P3.4 Review Center และประวัติหลังฝึก

- [ ] **งานและการออกแบบ:** เชื่อม result→due/mistake/saved review จาก canonical eligibility; delayed review ต่างจาก immediate repair; ตรวจ new/returning learner, no items, restart และ stale content
- **Owner files:** `lib/features/review`, `lib/features/history`, `lib/screens/review_center_screen.dart`
- **Requirements:** COV-f06, COV-f14, COV-f15, COV-f22, COV-f43, G3 · **รับเข้าจาก:** P3.3
- **ตรวจรับ:** first5/6+repair1/1 ยังแสดงแยก; replay ไม่มี reward ซ้ำ; recommendation มีเหตุผลและ manual choice ยังใช้ได้
- **Verification:** `test/features/review/review_center_reader_test.dart`, `test/screens/review_center_screen_test.dart`, `test/features/history/learning_history_replay_test.dart`

### P3.5 Dashboard, calendar และสูตรความก้าวหน้า

- [ ] **งานและการออกแบบ:** แยก accuracy+n, active effort, mastery/SRS, XP/streak; ตรวจ same data ที่ Today/calendar/dashboard, Bangkok midnight/week boundary, noEvidence และ owner switch
- **Owner files:** `lib/features/progress`, `lib/screens/mastery_dashboard_screen.dart`, `lib/screens/learning_calendar_screen.dart`
- **Requirements:** COV-f24, COV-f25, COV-f36, COV-f37, FORM-01, FORM-06, FORM-07, G3 · **รับเข้าจาก:** P3.4
- **ตรวจรับ:** ตัวเลขย้อนกลับ ledger ได้; n=0 ไม่เป็น 0% skill; XP/streak ไม่ใช้กล่าว efficacy; percentage point และ percent ไม่ใช้สลับกัน
- **Verification:** `test/features/progress/personal_learning_profile_test.dart`, `test/features/progress/learning_calendar_reader_test.dart`, `test/screens/mastery_dashboard_screen_test.dart`

### P3.6 Assessment และ before/after ที่มี metadata ครบ

- [ ] **งานและการออกแบบ:** ตรวจ setup→items→submit→result→comparison ด้วย synthetic instrument/version; missing pre/post, incompatible form/content/build, duplicate items และ no engagement. ถ้า edition ต้องการ personal assessment ให้ออก versioned design แยกจาก research contract ก่อน code
- **Owner files:** `lib/features/assessment`, `lib/screens/pre_post_assessment_screen.dart`, `lib/runtime/production_feature_contract.dart`
- **Requirements:** COV-f28, FORM-08, G3 · **รับเข้าจาก:** P3.5
- **ตรวจรับ:** ไม่ถอด consent/assignment gates; ไม่เก็บ participant data; ordinary learning ไม่พึ่ง research readiness; f28 ที่ยังไม่มี personal runtime path แสดง delivery limitation ไม่อ้างครบ 44 runtime
- **Verification:** `test/features/assessment/assessment_comparison_test.dart`, `test/features/assessment/assessment_isolation_test.dart`, `test/screens/pre_post_assessment_screen_test.dart`

### P3.7 Offline content readiness และการเปลี่ยน revision

- [ ] **งานและการออกแบบ:** ตรวจ installed/missing/downloading/cancel/hash mismatch/storage pressure/version replace/remove/reopen; catalog ชี้ readiness จาก installed manifest; history pin ต้องอ่านได้ตาม storage contract
- **Owner files:** `lib/features/offline_content`, `lib/features/learning_packs`, `lib/screens/offline_content_manager_screen.dart`
- **Requirements:** COV-f04, COV-f44, G3 · **รับเข้าจาก:** P3.6
- **ตรวจรับ:** cache delete ไม่ลบ canonical vocabulary/history; interrupted install ไม่เผย half-installed pack; UI บอก required storage/ready state จริงและไม่มี download บริการเสียเงินโดยอนุมาน
- **Verification:** `test/features/offline_content/offline_content_manager_test.dart`, `test/screens/offline_content_manager_screen_test.dart`, `test/screens/offline_content_settings_entry_test.dart`

## G4 — Today การนำทาง และแรงจูงใจ (6 หัวข้อย่อย)

**Dependency:** G2, G3 · **Gate outcome:** เริ่มฝึกง่าย มีอิสระเลือก; timer/goals/rewards/preferences ไม่สร้างข้อมูลซ้ำ

### P4.1 Today และ navigation ที่มีเหตุผล

- [ ] **งานและการออกแบบ:** ใช้ canonical Today snapshot เลือก resume/review/recommendation/planning; มี primary action กับ choose practice; ตรวจ back/deep link/loading/empty/stale/unavailable และอ่านระดับเริ่มต้นถึงเนื้อหาระดับสูง
- **Owner files:** `lib/features/today_hub`, `lib/screens/today_hub_screen.dart`, `lib/widgets/recommendation_panel.dart`
- **Requirements:** COV-f01, COV-f02, COV-f14, COV-f37, COV-f42, G4 · **รับเข้าจาก:** G2, G3
- **ตรวจรับ:** primary action ไม่เปิด session/content ปลอม; stale recommendation ไม่ปิด manual practice; owner switch ไม่แสดง next action ของคนเก่า
- **Verification:** `test/screens/today_hub_screen_test.dart`, `test/widgets/recommendation_panel_test.dart`, `test/screens/production_shell_navigation_test.dart`

### P4.2 Goal, countdown และ reminder แบบ opt-in

- [ ] **งานและการออกแบบ:** ตรวจ target date ก่อน/ตรง/หลังวันนี้, local timezone, edit/delete, permission denied/revoked, reschedule/cancel และ restart; UI อธิบายว่าเป็นเป้าหมายส่วนตัว
- **Owner files:** `lib/features/goals`, `lib/screens/learning_goals_screen.dart`, `lib/screens/study_reminder_settings_screen.dart`
- **Requirements:** COV-f26, COV-f27, FORM-07, G4 · **รับเข้าจาก:** P4.1
- **ตรวจรับ:** ไม่มี notification ซ้ำหรือ opt-in แฝง; countdown ไม่เป็นคะแนน admission; ข้อมูล goal/reminder มี owner และ lifecycle ใน P7.4
- **Verification:** `test/features/goals/learning_goal_use_cases_test.dart`, `test/screens/learning_goals_screen_test.dart`, `test/screens/study_reminder_settings_screen_test.dart`

### P4.3 Focus Timer และ automatic effort

- [ ] **งานและการออกแบบ:** รับ local preview ที่ bootstrap เปลี่ยน timer เป็น internal อยู่แล้วเป็น baseline; ยืนยัน actual composition/route/active-time dependency ตาม P0.8 และปรับเฉพาะ gap. start/pause/resume/finish/background/idle/restart ใช้ existing controller/segments
- **Owner files:** `lib/features/time_tracking`, `lib/runtime/app_dependencies.dart`, `lib/features/learning/presentation/unified_lesson_shell.dart`
- **Requirements:** COV-f23, COV-f24, FORM-06, G4 · **รับเข้าจาก:** P4.2
- **ตรวจรับ:** พัก 60s ไม่เพิ่ม active effort; เปิดแอปค้างไม่ให้เวลาเรียนเทียม; manual/automatic overlap ไม่ double count; สถิติพื้นฐานไม่ล็อกด้วยยอดชั่วโมง
- **Verification:** `test/features/time_tracking/focus_timer_controller_test.dart`, `test/features/time_tracking/focus_timer_widget_test.dart`, `test/features/time_tracking/active_learning_time_controller_test.dart`

### P4.4 Quest และ Gentle Streak

- [ ] **งานและการออกแบบ:** consume eligible event identity เดิม; ตรวจ replay/duplicate/clock rollback/day boundary/freeze inventory; เคารพ policy version และ history
- **Owner files:** `lib/features/quest`, `lib/features/motivation`, `lib/widgets/gentle_streak_card.dart`
- **Requirements:** COV-f29, COV-f30, FORM-04, FORM-05, G4 · **รับเข้าจาก:** P4.3
- **ตรวจรับ:** day เดียวไม่เพิ่ม streak ซ้ำ; missed day ไม่ล้าง knowledge; quest receipt ไม่เกิดจาก animation; ภาษา UI ไม่ลงโทษหรือปิดการเรียน
- **Verification:** `test/features/motivation/streak_use_cases_test.dart`, `test/features/motivation/timezone_policy_test.dart`, `test/widgets/gentle_streak_card_test.dart`

### P4.5 Achievements, avatar, companion และ share card

- [ ] **งานและการออกแบบ:** ใช้ receipt/lifetime XP/cosmetic policy; companion ตอบ state โดยไม่บัง prompt; share เป็น local preview/export ผูก receipt และตรวจ owner/filename/cancel
- **Owner files:** `lib/features/achievements`, `lib/features/rewards`, `lib/widgets/reward_avatar_preview.dart`
- **Requirements:** COV-f31, COV-f32, COV-f33, COV-f34, FORM-04, G4 · **รับเข้าจาก:** P4.4
- **ตรวจรับ:** XP19/20/39/40 ได้ level ตาม policy; spend coins ไม่ลด lifetimeXP; reopen/rebuild ไม่ปลดรางวัลซ้ำ; ไม่มีการส่งไปโซเชียลอัตโนมัติ
- **Verification:** `test/features/rewards/avatar_progression_policy_test.dart`, `test/features/achievements/achievement_share_card_use_cases_test.dart`, `test/widgets/reward_avatar_preview_test.dart`

### P4.6 Preferences, onboarding, theme และ motion

- [ ] **งานและการออกแบบ:** skip/edit/owner switch/restart สำหรับ preference questionnaire; theme light/dark/system และ reduced motion ใช้ controller/storage เดิม; ลำดับ onboarding ไม่ซ้ำหลังเริ่มเรียน
- **Owner files:** `lib/features/preferences`, `lib/screens/learning_preference_quiz_screen.dart`, `lib/config/m3_theme.dart`
- **Requirements:** COV-f35, COV-f38, COV-f39, G4 · **รับเข้าจาก:** P4.5
- **ตรวจรับ:** preferences ไม่ถูกเรียกว่า validated placement/CEFR score; platform disableAnimations มีผลจริง; ไม่มีเสียงหรือ motion ก็ทำ task หลักครบ
- **Verification:** `test/screens/learning_preference_quiz_screen_test.dart`, `test/features/preferences/learner_preferences_use_cases_test.dart`, `test/features/preferences/display_preferences_controller_test.dart`

## G5 — กล้องและการประเมินโมเดล (6 หัวข้อย่อย)

**Dependency:** G1, G4 · **Gate outcome:** camera lifecycle และ uncertainty ใช้งานได้; candidate มีหลักฐานหรือคง baseline พร้อมข้อจำกัด

### P5.1 Camera permission และ model lifecycle

- [ ] **งานและการออกแบบ:** แยก permission denied/permanently denied, model missing/downloading/invalid, processing/cancel/error; lifecycle pause/resume/dispose/owner switch; ใช้ gateway/controller เดิม
- **Owner files:** `lib/screens/object_scanner_screen.dart`, `lib/features/media_practice/application/object_scanner_use_cases.dart`, `lib/features/device_model`
- **Requirements:** COV-f13, A-CAM, G5 · **รับเข้าจาก:** G1, G4
- **ตรวจรับ:** ไม่มี stuck spinner/stale result; ordinary vocabulary entry ยังใช้ได้; error state ไม่แสดงผลสแกนปลอมและไม่ดาวน์โหลด model โดยไม่มี policy
- **Verification:** `test/screens/object_scanner_screen_test.dart`, `test/features/media_practice/object_scanner_use_cases_test.dart`, `test/features/device_model/model_manifest_test.dart`

### P5.2 Uncertainty, label mapping และ accept decision

- [ ] **งานและการออกแบบ:** ตรวจ notConfident/unsupported/mapped และการใช้ primary label; raw/mapped/confidence/accepted ต้องแยก; ไม่เลือก label รองเพื่อบังคับ save
- **Owner files:** `lib/features/media_practice/application/object_scanner_use_cases.dart`, `lib/screens/object_scanner_screen.dart`, `lib/features/device_model`
- **Requirements:** A-CAM, FORM-09, G5 · **รับเข้าจาก:** P5.1
- **ตรวจรับ:** คำศัพท์ถูกเพิ่มเฉพาะ accept ที่ controller อนุมัติและคำมี mapping; rejected/unsupported ไม่ให้ evidence/reward; UI บอกความไม่มั่นใจจริง
- **Verification:** `test/features/media_practice/object_scanner_use_cases_test.dart`, `test/screens/object_scanner_screen_test.dart`

### P5.3 บันทึกคำจากกล้องและกู้คืน

- [ ] **งานและการออกแบบ:** ตรวจ scan→preview→save→saved→vocabulary→restart, duplicate accept, disk failure/lost ack และ owner change; event/source provenance คงอยู่
- **Owner files:** `lib/features/media_practice`, `lib/features/vocabulary`, `lib/screens/object_scanner_screen.dart`
- **Requirements:** COV-f13, COV-f20, COV-f40, A-CAM, G5 · **รับเข้าจาก:** P5.2
- **ตรวจรับ:** save เดียวเกิดคำ/receipt ครั้งเดียว; retry ไม่มีข้อมูลค้างข้าม owner; failure มีทางทำซ้ำและไม่กล่าว saved ก่อน durable ack
- **Verification:** `test/features/media_practice/object_scanner_use_cases_test.dart`, `test/screens/object_scanner_screen_test.dart`, `test/screens/offline_vocabulary_journey_test.dart`

### P5.4 Dataset provenance และ validation freeze

- [ ] **งานและการออกแบบ:** รับ F3 v2 เป็น baseline; audit license/hash/source-group/splits/model identity, known/unknown natural images และ validation coverage; freeze threshold ก่อนเปิด fresh test; dataset ไม่ครบให้ reportgap และ retainbaseline
- **Owner files:** `tools/camera_accuracy.py`, `tools/test_camera_accuracy.py`, `lib/features/device_model/domain/model_manifest.dart`
- **Requirements:** A-MODEL, FORM-09, G5 · **รับเข้าจาก:** P5.3
- **ตรวจรับ:** validation predictions/hash/counts/IDs/metrics recompute ตรงกัน; malformed/nonfinite/missingdata fail closed; เคยเปิด test แล้วคง development label ไม่ทำเป็น fresh
- **Verification:** `tools/test_camera_accuracy.py`

### P5.5 Metrics, latency และ resource budget

- [ ] **งานและการออกแบบ:** รับ F4 explicit baseline acceptance; คำนวณ per-class/known reject/unknown false accept/Wilson bounds, latency/memory/model size; threshold0.25 หรือค่าที่ไม่ rejectunknown ต้องไม่ผ่านจาก softmax illusion
- **Owner files:** `tools/camera_accuracy.py`, `lib/features/device_model`, `docs/superpowers/specs/2026-09-12-r15-engineering-spec.md`
- **Requirements:** A-MODEL, FORM-09, G5 · **รับเข้าจาก:** P5.4
- **ตรวจรับ:** zero denominator รายงาน null; rawlabel นอก mapping เป็น inputerror; metrics เทียบ paired sample ถูกต้อง; resource/physical ที่ยังไม่วัดเป็น NOT RUN
- **Verification:** `tools/test_camera_accuracy.py`, `test/features/device_model/model_manifest_test.dart`

### P5.6 Baseline retention และ device/rollback evidence

- [ ] **งานและการออกแบบ:** สรุป candidate decision จาก coverage/open-set/resources/physical/rollback; previewdevice ตรวจเมื่ออยู่ใน scope, natural-scene/human evidence เก็บ external; ไม่ train วนตาม test
- **Owner files:** `lib/features/device_model/domain/model_manifest.dart`, `tool/cli/verify-apk-model-runtime.ps1`, `tool/cli/verify-camera-speech.ps1`
- **Requirements:** A-CAM, A-MODEL, COV-f41, G5 · **รับเข้าจาก:** P5.5
- **ตรวจรับ:** shippedbaseline ไม่เปลี่ยนถ้า requiredgates ไม่ครบ; source/model/hash/rollback report ระบุชัด; G5 localcomplete ไม่อ้าง candidateproductionready
- **Verification:** `test/features/device_model/model_manifest_test.dart`

## G6 — AI Tutor และเสียง (6 หัวข้อย่อย)

**Dependency:** G3, G4 · **Gate outcome:** บริบทและ cancellation ปลอด stale state; no-key/no-audio fallback ใช้งานได้และบันทึก usage ตามจริง

### P6.1 AI context, level และ intent

- [ ] **งานและการออกแบบ:** รับ R15.9 bounded session context; ตรวจ role/order/turn limits/Thai readability/level/scenario/intent, summary provenance และ reset เมื่อ owner/provider/model/scenario/newchat เปลี่ยน
- **Owner files:** `lib/features/ai_tutor/domain/ai_tutor_contracts.dart`, `lib/features/ai_tutor/application/ai_tutor_use_cases.dart`, `lib/features/ai_tutor/data`
- **Requirements:** A-AI, G6 · **รับเข้าจาก:** G3, G4
- **ตรวจรับ:** ทุก gateway ได้ requestcontract เดียวกัน; ไม่มีบทสนทนา owner เก่าหรือ persistentarchive เพิ่มโดยอนุมาน; outputcaps เป็น engineeringpolicy ไม่ใช่หลักฐาน quality
- **Verification:** `test/features/ai_tutor/ai_tutor_use_cases_test.dart`, `test/features/ai_tutor/ai_gateway_adapters_test.dart`

### P6.2 Cancellation, late results และข้อความอ่านได้

- [ ] **งานและการออกแบบ:** รับ F1 speech-attempt epoch; ตรวจ newchat/reset/settings/cancel ระหว่าง permission/start/network, latefinal/status/error, cancellation failure, malformedformattedtext และ plain-textfallback
- **Owner files:** `lib/screens/ai_tutor_screen.dart`, `lib/features/ai_tutor/application`, `lib/features/ai_tutor/data`
- **Requirements:** A-AI, PLAN-02, G6 · **รับเข้าจาก:** P6.1
- **ตรวจรับ:** ข้อความเก่าไม่แทน draft ใหม่; cancel หนึ่งครั้งไม่ทำ nativecancel ซ้ำโดยไร้เหตุ; assistanttext ไม่หายจาก renderer และไม่มี hiddenanswer
- **Verification:** `test/screens/ai_tutor_screen_test.dart`, `test/features/ai_tutor/ai_gateway_loopback_test.dart`

### P6.3 Provider errors, keys, retry และ usage

- [ ] **งานและการออกแบบ:** ทดสอบ loopback401/402/429/5xx/malformed/timeout/retry/cancel, provider/model switch, quota และ usageaccounting; securestorage/logredaction และ no-keyUI
- **Owner files:** `lib/features/ai_tutor/data`, `lib/runtime/central_cost_policy.dart`, `lib/features/ai_tutor/application`
- **Requirements:** A-AI, FORM-12, G6 · **รับเข้าจาก:** P6.2
- **ตรวจรับ:** ไม่มี retryloop/duplicatechargeclaim; providerusage กับ estimate แยกและ missing≠zero; ไม่เรียก liveprovider หรือจ่ายเงินเพื่อผ่าน localgate
- **Verification:** `test/features/ai_tutor/ai_gateway_loopback_test.dart`, `test/features/ai_tutor/secure_ai_tutor_settings_store_test.dart`, `test/runtime/central_cost_policy_test.dart`

### P6.4 Speech gateways และ fallback

- [ ] **งานและการออกแบบ:** ตรวจ permissions/no-speech/unavailable recognizer/timeout/cancel/error/retry/startcompletion, TTS/noaudio และ dictationfallback; ไม่แก้ sharedspeechpolicy จาก screen-onlyworkaround โดยไม่ตรวจ consumer
- **Owner files:** `lib/features/media_practice`, `lib/screens/speak_to_text_screen.dart`, `lib/screens/shadowing_challenge_screen.dart`
- **Requirements:** A-SYS, VOICE-01, MODE-dictation, MODE-speaking, MODE-shadowing, G6 · **รับเข้าจาก:** P6.3
- **ตรวจรับ:** ไม่มี lateassessment หลังหน้าจอแสดง failure; text/manualpractice ยังได้; inputlocks ตรง session และไม่บันทึกเสียงจริงโดยอนุมาน
- **Verification:** `test/features/media_practice/speech_practice_use_cases_test.dart`, `test/features/media_practice/plugin_speech_recognition_gateway_test.dart`, `test/screens/shadowing_challenge_screen_test.dart`

### P6.5 Speaking, shadowing และ dictation evidence

- [ ] **งานและการออกแบบ:** ตรวจ recognizedtext similarity/normalization/emptyreference, repeatedsubmit, unscoredsupplementalpanel versus scoredactivity; audio replay ไม่ถูกนับ hint ผิดชนิด
- **Owner files:** `lib/features/media_practice/application`, `lib/screens/shadowing_challenge_screen.dart`, `lib/features/learning/application/native_mode_adapters.dart`
- **Requirements:** COV-f13, MG-09, MG-12, FORM-10, G6 · **รับเข้าจาก:** P6.4
- **ตรวจรับ:** ไม่เรียก recognizedtext เป็น acousticpronunciation score; noaudio/nospeech ไม่สร้าง 0%skill หรือ fakePASS; evidence/rewardprofile ตรง mode
- **Verification:** `test/screens/shadowing_challenge_screen_test.dart`, `test/screens/speak_to_text_screen_voice_test.dart`, `test/features/learning/native_mode_adapters_test.dart`

### P6.6 AI quality rubric และ no-key journey

- [ ] **งานและการออกแบบ:** ใช้ authoredqualitycases และ synthetictransport ตรวจ request/outputpolicy/rendering, normallearning เมื่อไม่มี key/network; livehumanquality/cost แยก ledger
- **Owner files:** `docs/development/2026-09-11-ai-tutor-quality-cases.md`, `lib/features/ai_tutor`, `lib/screens/today_hub_screen.dart`
- **Requirements:** A-AI, A-SYS, FORM-12, G6 · **รับเข้าจาก:** P6.5
- **ตรวจรับ:** localtransportPASS ไม่แทน liveaccuracy/latency; answerwrongcase มี rubricrecord เมื่อทดสอบจริง; corelearning ไม่ถูก subscription/providerlock
- **Verification:** `test/scenarios/ai_voice_fallback_journey_test.dart`, `test/scenarios/runtime_kill_switch_journey_test.dart`

## G7 — Backend, sync, policy และการเตรียมส่งมอบ (7 หัวข้อย่อย)

**Dependency:** G1, G3, G5, G6 · **Gate outcome:** owner lifecycle, offline recovery, runtime edition และ backend boundaries ผ่าน local acceptance

### P7.1 Offline queue, lost ack และ reopen

- [ ] **งานและการออกแบบ:** ทดสอบ queue→send→lostack→retry→reopen ด้วย synthetictransport/file-backedstore; canonicaloperationidentity และ localtruth ไม่ถูก remoteavailability ทับ
- **Owner files:** `lib/features/sync`, `lib/data/local`, `lib/progress`
- **Requirements:** COV-f40, G7 · **รับเข้าจาก:** G1, G3, G5, G6
- **ตรวจรับ:** ไม่มี duplicatewrite/receipt หรือ pending หาย; offlinelearning ต่อได้; sync unavailable แสดงตรงจริงและมี boundedretry
- **Verification:** `test/scenarios/file_backed_sync_recovery_test.dart`, `test/features/sync/cloud_sync_policy_test.dart`

### P7.2 Owner switch, conflict และ migration compatibility

- [ ] **งานและการออกแบบ:** ตรวจ guest→account, ownerA/B, conflicting revisions, replay/reward/SRS projection, main/R15schema compatibility ตาม P0.3; newownertable ต้องมี lifecycle ครบ
- **Owner files:** `lib/features/identity`, `lib/features/sync`, `lib/data/local`
- **Requirements:** COV-f40, COV-f43, G7 · **รับเข้าจาก:** P7.1
- **ตรวจรับ:** ไม่มีข้อมูลข้าม owner หรือ last-write-wins ที่ทำ history/rewardauthority หาย; migration/export/delete contracts ผ่านก่อนใช้ schema ใหม่
- **Verification:** `test/features/identity/upgrade_guest_owner_test.dart`, `test/features/sync/srs_state_sync_test.dart`, `test/features/sync/reward_transaction_sync_test.dart`

### P7.3 Backend access policy และ research boundaries

- [ ] **งานและการออกแบบ:** ตรวจ auth/owner/guest/denied claims และ requestvalidation ด้วย localemulator/syntheticidentities; ordinarylearning กับ research fail-closed แยก; ตรวจ trustedwriter จากสองสาย Git
- **Owner files:** `firestore.rules`, `supabase`, `functions`
- **Requirements:** COV-f28, COV-f40, COV-f41, G7 · **รับเข้าจาก:** P7.2
- **ตรวจรับ:** negativeaccess ถูกปฏิเสธและ positivepath ใช้ได้; ไม่มี realcloudwrite/enrollment/participantupload; policy ไม่เปิดเพราะต้องการให้ catalog ผ่าน
- **Verification:** `test/security/firestore-rules.test.cjs`, `test/features/research/research_runtime_sync_integration_test.dart`, `test/features/sync/research_withdrawal_reopen_test.dart`

### P7.4 Export/delete และ lifecycle ของข้อมูลทั้งหมด

- [ ] **งานและการออกแบบ:** ตรวจ save/report/preferences/share/reminder/offlinecontent ทั้ง restart/owner/export/delete; ทำ retention/cachecleanup แยก canonicaldata และหยุด resurrection จาก pendingqueue
- **Owner files:** `lib/features/account`, `lib/features/review`, `lib/features/offline_content`, `lib/features/preferences`
- **Requirements:** COV-f20, COV-f21, COV-f27, COV-f34, COV-f35, COV-f44, G7 · **รับเข้าจาก:** P7.3
- **ตรวจรับ:** delete/export มี ownerboundary และ redaction ถูกต้อง; exportcancel ไม่ทิ้งไฟล์มีข้อมูลเกิน scope; cachecleanup ไม่ลบ history; unreferencedcode ลบได้หลังไม่มี import/route/schema/generatorconsumer และมี rollback
- **Verification:** `test/features/account/local_data_deletion_test.dart`, `test/features/sync/learner_preferences_sync_test.dart`, `test/features/offline_content/offline_content_manager_test.dart`

### P7.5 Activation matrix และ edition ที่ซื่อสัตย์

- [ ] **งานและการออกแบบ:** ทดสอบ off/unavailable/implementedOff/internal/enabled/killswitch แยก; ตรวจทุก catalogentry ใน localpreviewedition และการเปิด f12/f23 ตาม design; f28research ยังต้อง authority จริง
- **Owner files:** `lib/runtime/production_feature_contract.dart`, `lib/runtime/production_feature_gate.dart`, `lib/runtime/app_dependencies.dart`, `lib/features/learning/application/lesson_mode_registry.dart`
- **Requirements:** COV-f12, COV-f23, COV-f28, COV-f41, G7 · **รับเข้าจาก:** P7.4
- **ตรวจรับ:** matrix แสดง route+deps+content+flag+edition ครบ; feature ที่ยังปิดมี explicitlimitation; ไม่อ้าง 44runtime ครบเมื่อบางรายการเป็น externalpending
- **Verification:** `test/runtime/runtime_feature_controls_test.dart`, `test/features/learning/lesson_mode_registry_test.dart`, `test/scenarios/runtime_kill_switch_journey_test.dart`

### P7.6 AI/voice/backend contracts และภาระทรัพยากร

- [ ] **งานและการออกแบบ:** ตรวจ request schema/error mapping/timeouts/size/quotas/cancellation/liveness/dependencyfailure ใน backend ที่ edition ใช้; รัน BackendAI→BackendVoice→BackendLM แบบ serial ตาม verify-scope เฉพาะ inputs ที่ยังไม่ผ่าน
- **Owner files:** `backend`, `functions`, `lib/runtime/central_cost_policy.dart`
- **Requirements:** A-AI, A-SYS, COV-f40, G7 · **รับเข้าจาก:** P7.5
- **ตรวจรับ:** ไม่มี unboundedwork หรือ secret ใน logs; localbackendunavailable มี fallback; backend ที่ไม่ได้ใช้ใน edition มี reason และห้ามเรียกทั้งหมดว่าผ่าน
- **Verification:** `test/features/ai_tutor/ai_gateway_loopback_test.dart`, `test/runtime/central_cost_policy_test.dart`

### P7.7 Dependency, native config และ release tooling readiness

- [ ] **งานและการออกแบบ:** ตรวจ toolchain/lockfiles/nativepermissions/appidentity/modelcontentpackaging, mainreleasefixes และ generatorcompatibility; oldfrozenmanifest คง historical จน P8.4 ออก revision ใหม่
- **Owner files:** `pubspec.yaml`, `pubspec.lock`, `android`, `tool/cli`, `tool/final_test_plan/generate_final_test_plan.dart`
- **Requirements:** COV-f38, COV-f40, COV-f41, G7 · **รับเข้าจาก:** P7.6
- **ตรวจรับ:** ไม่ลด assertion ของ historicalcontract เพียงเพื่อเขียว; toolchain/configpins ชัด; ยังไม่ buildrelease เต็มหรือ sign/distribute จน sourcefreeze และอยู่ใน scope
- **Verification:** `test/architecture/final_8_44_test_plan_contract_test.dart`, `test/architecture/final_8_44_test_plan_review_contract_test.dart`

## G8 — รีวิวโค้ดทั้งแอป Test Plan และตรวจใช้งานจริง (9 หัวข้อย่อย)

**Dependency:** G0, G1, G2, G3, G4, G5, G6, G7 · **Gate outcome:** review ledger ครบ, Test Plan หลัง review, actual test/defect/retest evidence และ release ledger ที่ระบุข้อจำกัด

### P8.1 ปิด development gates และ freeze inventory

- [ ] **งานและการออกแบบ:** รับ G0–G7 พร้อม coverage/status/knownlimitations แล้ว freeze source; สร้าง git-trackedreviewinventory รวม Dart/backend/native/policy/tooling/tests/config และ localuntrackedsource ที่ต้องรับ; แยก generatedcode/assets/docs ด้วย reason
- **Owner files:** `docs/development`, `lib`, `backend`, `functions`, `tool`
- **Requirements:** G0–G7, G8 · **รับเข้าจาก:** G0, G1, G2, G3, G4, G5, G6, G7
- **ตรวจรับ:** writer หยุด; มี fullSHA+workingdiff หรือ cleancommit ตาม gate, config/model/contentpins, packageevidence และ reviewscope ไม่มี ownedsource ที่ตกหล่น; ไม่ใช้ count611 แทน inventory ณ freeze จริง
- **Verification:** ตรวจตาม freeze-inventory protocol; ไม่ใช้การรัน Flutter แทนหลักฐานชนิดนี้

### P8.2 รีวิวโค้ดทั้งแอปบน source ที่ freeze

- [ ] **งานและการออกแบบ:** รีวิว semantic ทุก handwrittensource ใน inventory แบบ serial12reviewzones ตาม MasterPlan; ตรวจ architecture/controlflow/dataflows/auth/contracts/async/lifecycle/formulas/error/resource/UI และ tests ที่เป็น oracle. Generatedfiles ตรวจ generator/manifest/reproducibility แทนอ่านไฟล์ซ้ำทีละบรรทัด
- **Owner files:** `lib`, `backend`, `functions`, `android`, `ios`, `linux`, `macos`, `windows`, `tool`, `tools`, `test`, `firestore.rules`, `supabase`
- **Requirements:** G8, REVIEW-ALL · **รับเข้าจาก:** P8.1
- **ตรวจรับ:** ทุก file/zone มี reviewstatus+SHA+findings หรือ noactionablefinding; whole-appreview ครอบคลุม source ปัจจุบันไม่ใช่เฉพาะ R15diff; ไม่มีการใช้ workflow หรือ worker ที่ AGENTS ห้าม
- **Verification:** ตรวจตาม whole-code-review protocol; ไม่ใช้การรัน Flutter แทนหลักฐานชนิดนี้

### P8.3 แก้ผล review และปิด development review

- [ ] **งานและการออกแบบ:** triageP0–P3 พร้อม reproduction/rootcause; เปิด package เจ้าของ defect, เพิ่ม regression ก่อน fix และ re-reviewdelta กับ affectedcallers; freezeSHA ใหม่เมื่อแก้และ updatecoverage
- **Owner files:** `lib`, `backend`, `functions`, `tool`, `tools`, `test`
- **Requirements:** G8, REVIEW-ALL · **รับเข้าจาก:** P8.2
- **ตรวจรับ:** ไม่มี critical/high หรือ knownin-scopefunctionaldefect ค้างเพื่อกล่าวว่าพัฒนาครบ; unresolvedexternal มีเหตุผล; reviewpass เกิดก่อนออก SystemTestPlan ฉบับรัน
- **Verification:** ตรวจตาม review-remediation protocol; ไม่ใช้การรัน Flutter แทนหลักฐานชนิดนี้

### P8.4 จัดทำ System Test Plan หลัง code review

- [ ] **งานและการออกแบบ:** ใช้ reviewedsource และ currentgenerator สร้าง executableplanrevision: TestCaseID→COV/MODE/MG/FORM→preconditions/data/steps/expected→command/device/evidence; กรอบ 16testfamilies และ faultmatrix ใน MasterPlan เป็น input ไม่ใช่ผลทดสอบ
- **Owner files:** `tool/final_test_plan/generate_final_test_plan.dart`, `docs/generated/alltcas-8-44-final-test-plan.json`, `docs/development`
- **Requirements:** G8, TEST-PLAN · **รับเข้าจาก:** P8.3
- **ตรวจรับ:** planpin ตรง freezeSHA และ inputhash; เคสครบ 74coveragerecords และ 12formulagroups โดยไม่ duplicatecommand; มี entry/exitcriteria, reusepolicy, incidentdatafields, expectednegativecases และ NOT RUN ledger
- **Verification:** `test/architecture/final_8_44_test_plan_contract_test.dart`, `test/architecture/final_8_44_test_plan_review_contract_test.dart`

### P8.5 รัน local automated gates ตาม Test Plan

- [ ] **งานและการออกแบบ:** รัน targeted/subsystem ตาม dependency แบบ serial; reusepassed เฉพาะ fingerprint ตรง; fullreleaseverifier เฉพาะ frozenPR/releaseSHA. เก็บ stdout/stderr/exit/duration/command/input/outputartifact และ firstfailure
- **Owner files:** `tool/cli/verify-scope.ps1`, `test`, `backend`, `functions`
- **Requirements:** G8, TEST-EXECUTION · **รับเข้าจาก:** P8.4
- **ตรวจรับ:** ผล PASS/FAIL/BLOCKED/NOT RUN แยก; ไม่มี suite ที่รันซ้ำเพราะเปลี่ยนเอกสารอย่างเดียว; failure ที่เกิดจริงเปิด defectrecord หรือระบุ expectednegativecase
- **Verification:** ตรวจตาม frozen-test-execution protocol; ไม่ใช้การรัน Flutter แทนหลักฐานชนิดนี้

### P8.6 Build, install และเส้นทางใช้งานจริง

- [ ] **งานและการออกแบบ:** สร้าง artifact ครั้งเดียวต่อ relevantfrozeninput; ตรวจ APK/source/model/contentSHA; ติดตั้ง emulator ที่ระบุด้วย syntheticdata และตรวจ coldstart/firstlesson/allavailablemodes/history/replay/offline/restart; physicaldevice เฉพาะที่ authorized
- **Owner files:** `android`, `tool/cli/run-android-smoke.ps1`, `tool/cli/verify-apk-model-runtime.ps1`, `integration_test`
- **Requirements:** G8, TEST-DEVICE · **รับเข้าจาก:** P8.5
- **ตรวจรับ:** มี screenshot/video/log ตาม testcase และผล durableafterreopen; ไม่มี uninstall/clear-app-data ที่ทำข้อมูลผู้ใช้หาย; actualAPK ตรง source ที่ reviewed และทดสอบ
- **Verification:** ตรวจตาม device-acceptance protocol; ไม่ใช้การรัน Flutter แทนหลักฐานชนิดนี้

### P8.7 Fault injection, accessibility และ resource checks

- [ ] **งานและการออกแบบ:** ทำ faultmatrix permission/network/timeout/disk/contenthash/owner/session/restart/timezone/locale/textscale/reducedmotion; สำรวจ latency/memory/overflow/focus ตาม device และ measurementmethod ที่ TestPlan กำหนด
- **Owner files:** `integration_test`, `test`, `tool/cli`, `lib/features/accessibility`
- **Requirements:** G8, TEST-FAULT, COV-f38, COV-f40 · **รับเข้าจาก:** P8.6
- **ตรวจรับ:** allcriticalflows มี recoverableexit และ no-data-corruption; UIvisual ผ่านไม่ใช้แทน humanTalkBack/audio; latency/performance ที่ยังไม่วัดเป็น NOT RUN ไม่ใส่ค่าคาดเดา
- **Verification:** ตรวจตาม system-fault-acceptance protocol; ไม่ใช้การรัน Flutter แทนหลักฐานชนิดนี้

### P8.8 Defect → fix → retest → regression

- [ ] **งานและการออกแบบ:** เก็บทุก unexpectedfailure ด้วย DefectID, testcase, source/device/config, steps, expected/actual, evidence, severity, rootcause, ownerpackage, fixSHA, retest และ impactedregression; แก้แล้วกลับ reviewdelta/freeze และ regenerate เฉพาะ planpins ที่กระทบ
- **Owner files:** `docs/development`, `test`, `lib`, `backend`, `tools`
- **Requirements:** G8, DEFECT-LEDGER · **รับเข้าจาก:** P8.7
- **ตรวจรับ:** close ได้เมื่อ originalrepro ไม่เกิดบน fixSHA และ regression ที่เกี่ยวข้องผ่าน; ถ้าคำสั่งเดิมล้มซ้ำ/filesystemerror ซ้ำ/no-progress10min ให้หยุดงานส่วนนั้นและ report ไม่ retryblindly
- **Verification:** ตรวจตาม defect-retest protocol; ไม่ใช้การรัน Flutter แทนหลักฐานชนิดนี้

### P8.9 ตรวจรับสุดท้ายและ release ledger

- [ ] **งานและการออกแบบ:** สรุป engineeringcompletion, local/emulator/device/human/liveacceptance แยก พร้อม coverageallrecords, reviewfilecoverage, testpass/fail/notrun, cleanupmanifest, artifacthash, knownlimitations และ nextauthorizedaction
- **Owner files:** `docs/development`, `docs/generated`, `tool/cli`
- **Requirements:** G8, MASTER-COMPLETION · **รับเข้าจาก:** P8.8
- **ตรวจรับ:** ประกาศครบได้เฉพาะ scope ที่หลักฐานครบ; externalrequired ที่ยังไม่ผ่านไม่ใช่ releasePASS; ไม่มี deployment/signing/publishing/researchrollout จากการปิด localgate
- **Verification:** ตรวจตาม release-ledger protocol; ไม่ใช้การรัน Flutter แทนหลักฐานชนิดนี้

## Coverage ledger และ edition decisions

Ledger มี 74 records: 44 `COV-fNN` + 14 `MODE-<enum>` + Adventure/Ghost 2 journeys + `MG-01–MG-14` 14 groups. เป็นมุมมองซ้อนกันของระบบ ไม่ใช่ 74 features. แต่ละ row ระบุ package, requirements, route หรือ foundation boundary, source pin, content contract/readiness, test targets, evidence state และ external dependencies

**สถานะปัจจุบันเป็น planning coverage เท่านั้น.** G0.5 ต้องเติม actual edition/config/content revision จาก reconciled source ก่อนรับ implementation gate; G8 ต้องมีผลจริง ไม่ใช้ `planned` เป็น `verified-existing`. Record ที่ไม่ให้คะแนนตรวจว่าไม่สร้างคะแนน แทนการแต่ง correct/wrong expectation

| Decision | ฐานการดำเนินงานหลังผู้ใช้อนุมัติ; ปรับได้ตาม rule register | Gate ป้องกันการอ้างเกินหลักฐาน |
| --- | --- | --- |
| Source | ใช้ R15+F1–F4 เป็น baseline candidate และรับ main semantic fixes หลัง disposition | ความต่าง58/382commitsต้องจัดปลายทาง; ไม่ merge/rebase ทั้งหมดโดยเดา |
| f12 Scratchpad | ส่งเป็น local ephemeral tool ผ่าน component เดิม เมื่อ route/cleanup/no-evidence tests ครบ | ยัง implementedOff ต้องตัดสินและยืนยัน actual composition |
| f23 Focus timer | รับ preview internal ที่มีอยู่ ตรวจ route + active-time dependencies และ fault cases | defaultในDIไม่ใช่สถานะของpreviewทุกbuild |
| f28 Assessment | คง synthetic contract verification และ research fail-closed; ถ้าต้องการ personal assessment เปิด design change แยกโดยไม่ถอดresearchgate | editionที่ไม่มีpersonalruntimeต้องเปิดเผย ไม่เรียกครบ44runtime |
| Camera | baseline เป็นตัวส่งมอบ; candidate เป็นการประเมินที่ต้องมีdata/model/resource/deviceevidence | coverage/physicalไม่ครบ→retainbaseline ไม่retrainตามtest |
| AI/voice/cloud | optional integrations, local/no-key fallbackเป็นrequired | localfake/loopbackPASSไม่แทนlivequality, acoustic scoreหรือtwo-devicesync |
| OUT/EXP | รายการเดิมเป็น backlog disposition ของรอบก่อน ไม่ใช่ข้อห้ามถาวร. เมื่อจำเป็นต่อ current full-system scope ให้บันทึก design delta, owner package และ acceptance; ไม่เพิ่มทุกสิ่งเพียงเพราะเลิกเพดาน | exact competitor imitation/real services/paid rollout ไม่ได้มีหลักฐานหรือสิทธิ์เพิ่มขึ้นจากการยกเลิก scope cap |

## การจัดข้อมูลเก่าเพื่อลดความซ้ำซ้อน

ทำใน **G0.6 / P0.6 และ G7.4 / P7.4** ซึ่งได้รับอนุมัติให้เดินตามลำดับแล้ว. Revision นี้ยกเลิก authority ของกฎเก่าที่ขัดแย้งใน active docs; ยังไม่ได้ลบไฟล์ application/ข้อมูลเก่าใน842cหรืออัปเดต GitHub. แผนก่อนแก้ถูกเก็บไว้ที่ `C:/Users/Phet/.codex/visualizations/2026/09/13/01a09888-61dd-7680-9b19-c33035043d59/plan-review/master-plan-before-user-review.md` และเอกสารต้นทาง4366ยังคงอยู่

| ประเภท | การดำเนินการหลังตรวจ references | หลักฐาน/rollback |
| --- | --- | --- |
| Master/spec/acceptance/catalogที่ยังใช้ | Active indexชี้masterเดียว; spec/acceptanceเดิมใช้เฉพาะcontractsที่ยังมีผล | linkcheck + authority precedence |
| R15 completed roadmap / old source claims / auto-successor workflow | markHistorical/Supersededและชี้replacement; คงobservations/commit/evidenceเดิม | before/afterhash, replacementpath, reason |
| test/**/failures PNG candidates76ไฟล์ | ตรวจว่าเป็นevidenceของopen/closeddefectหรือถูกdocsอ้าง; archiveที่ยังต้องเก็บ, ลบเฉพาะreproducible/unreferencedหลังdryrun | exactpath/hash/refs/defectID/archivepath/restorecommand; ห้ามแตะgoldensโดยเหมารวม |
| Generated registrants / generated docs / caches | ตรวจgenerator/config/inputhash; regenerateหรือreclassifyตามpolicy, ไม่ลบจากdirtyflag | source/content/modelpinsและreproductioncommand |
| Unused code/duplicate services | traceimports/routes/DI/featureflags/migrations/testsและdynamicconsumers; แทนด้วยauthorityเดิมหลังregression | callerinventory + deprecation/migration/rollbackrecord |
| Canonical learning/history/rewards/owner/consent/datasetprovenance | เก็บตามpolicy; การลบเฉพาะintent/lifecycleที่userสั่งและมีexport/deletecontract | never-age-baseddelete; schema/referentialintegrity checks |

ก่อน recursive move/delete ต้อง resolve absolute path ให้อยู่ใน workspace/target ที่ตั้งใจ และใช้ PowerShell native operations. ห้าม `git clean -fdx`, bulk-delete docs/build/worktrees, ลบโปรไฟล์แอปจริง หรือ reset ฐานข้อมูลเพื่อทำให้ test ผ่าน. Active execution index อ่านสั้น ๆ ได้และไม่ส่ง historical instructions มาคุมงานใหม่

## แนวทางตรวจโค้ดทั้งแอปใน P8.2

ทำหลัง development packages ผ่านและ freeze source แล้ว. รีวิว **source ปัจจุบันทั้งหมดใน review inventory** ไม่ใช่เฉพาะ diff R15 และไม่รื้อประวัติทุก commit. ทำทีละ zoneโดยคนทำงานเดียว; ชื่อ zone เป็นการจัดคิว ไม่ใช่ subagents

| Zone | ขอบเขต semantic review |
| --- | --- |
| REV-01 | bootstrap, DI, feature gates, entry/navigation, lifecycle, owner/session identity |
| REV-02 | learning/evidence/storage/transactions/migrations/recovery/history/replay |
| REV-03 | 14 lesson modes, Pair, Adventure, Ghost, reading, input/feedback/accessibility |
| REV-04 | vocabulary/content/CEFR/pack versions/quality/hints/review/bookmarks/reports/offlinecontent |
| REV-05 | SRS/progress/calendar/assessment/time/recommendations และสูตร FORM-01–FORM-12 |
| REV-06 | goals/reminders/quest/streak/achievements/avatar/companion/share/preferences |
| REV-07 | camera/preprocessing/model manifest/downloader/evaluator/datasetidentity/rollback |
| REV-08 | AI gateways/context/keys/cost/usage และvoice/TTS/recognizer/cancellation/fallback |
| REV-09 | sync/conflict/export/delete/backend endpoints/auth/ownerpolicy/researchboundaries |
| REV-10 | Android/iOS/desktopconfig, permissions, artifacts, packaging, offlinecoldstart |
| REV-11 | CLI/generators/CI/lockfiles/dependencyusage/resourcebounds/logprivacy/operationalrecovery |
| REV-12 | test assertions/oracles/fixtures/negativecases/manifestpins/coverage; generatedsourceตรวจผ่านgeneratorและreproducibility |

Review ledger ต่อไฟล์มี path, blob/hash, zone, status, reviewerpassdate, findingIDs หรือ `no-actionable-finding`, exclusion/generator rationale. ทุก tracked/untracked owned executable source ต้องมี disposition. Static review ไม่แทน runtime acceptance; reviewที่ไม่พบปัญหาไม่ใช่คำรับรองzero-unknowndefect. เมื่อแก้reviewfindingsให้เพิ่มregressionและreviewdelta+callersก่อน freeze ใหม่ ไม่ต้อง reviewทุกไฟล์ซ้ำหากไม่มีผลกระทบ

## กรอบ System Test Plan ที่จะจัดทำหลัง review

ขั้นนี้เป็น **ข้อกำหนดของ Test Plan ใน P8.4** ไม่ใช่การออก executable Test Plan หรือเริ่มทดสอบก่อนพัฒนาเสร็จ. ใช้ generator/manifest ของเดิมหลังตรวจความเข้ากันได้และปรับ revision/source pins อย่างถูกต้อง; ไม่ลด historical assertions เพื่อให้ผ่าน

**Entry criteria:** G0–G7 accepted, full code reviewครบinventory, reviewdefectsที่อยู่ในscopeแก้แล้ว, source freeze/fullSHA/config/model/contentpinsชัด, synthetic fixtures และtoolsพร้อม, ไม่มี writerอื่น. ถ้าขาดrequiredinputให้BLOCKEDพร้อมreason ไม่เปิดreleaseverifierก่อนfreeze

**Case schema:** CaseID, TestPlanRevision, COV/MODE/MG/FORM IDs, objective/risk, fixture+owner+content revision, environment/device/locale/timezone, preconditions, ordered actions, expected visible and durable results, positive/negative category, command/automation/manual owner, source/config fingerprint, evidence paths, cleanup/recovery, actualresult/status/DefectID

| กลุ่ม | เส้นทาง/สถานะที่ต้องทดสอบ | หลักฐานที่ต้องเก็บ |
| --- | --- | --- |
| ST-01 Start/owner/runtime | newinstall, coldstartoffline, guest/account, ownerA/B, no-key, kill-switch | launchlog, configuration, resultingowner/route |
| ST-02 Catalog/content | filter/detail/launch, missing/stale/hashwrong/unreviewedpack, A1และadvanced | contentmanifest/revision, UIreadiness, nofakesession |
| ST-03 Lesson modes | 14modes; correct/wrong/help/skipหรือunsupported, selectedvs typed, submit/retry | mode/config/evidenceprofile, renderedstates, durableledger |
| ST-04 Games/journeys | MG01–14, blocktileduplicates, Pair4/6/final, Adventure/Ghost | steps/screenshots/episodeIDs/rewardidentity |
| ST-05 Transactions/formulas | duplicateinput/lostack/partialfailure/replay, FORMboundaryfixtures | before/afterDBcounts/receipts, independentexpectedvalues |
| ST-06 Review/SRS | first5/6→repair1/1→delayedreview, dueUTC, noitems | first/repairreadmodels, dueinstants, noextraXP |
| ST-07 History/assessment | exactrevision/restart/replay, compatiblepre/post/missingpair/ineligible | source/content/protocolpins, nofabricatedcomparison |
| ST-08 Progress/time | noEvidence, week/day/timezone, active/pause/idle/overlap | numerator/denominator, segmenttotals, calendar/dashboardagreement |
| ST-09 Motivation/preferences | goals/countdown/reminders/quest/streak/avatar/share/skiponboarding | receipts, permissionstate, persistence, localshareartifact |
| ST-10 Data lifecycle | save/unsave/report/export/delete/cacheinstall/remove/reopen | fileshash, ownerisolation, nohistoryloss/resurrection |
| ST-11 Camera/model | permission/modelmissing/uncertainty/accept/save/rollback, evaluatornegativecases | model/data/configSHA, raw/mapped/accepted, metrics/limitations |
| ST-12 AI | context/reset/cancel/401/402/429/malformed/timeout/no-key/usage | sanitizedrequest/response/attemptIDs/usage, readableUI |
| ST-13 Voice | TTS/noaudio/micdenied/no-speech/error/latefinal/retry, textfallback | session/attempttimeline, recognizedtextlabel, noacousticclaim |
| ST-14 Backend/sync/policy | offlinequeue/conflict/lostack/ownerdelete, authnegativecases, researchfailclosed | syntheticidentity, emulatorlogs, reconciliationcounts |
| ST-15 UI/accessibility/resource | 320/390/840, light/dark/text200, Thai/English, keyboard/focus/reducedmotion, latency/memory | visualcaptures, semantics/focus checks, device/measurementmethod |
| ST-16 Artifact/end-to-end | reviewedSHA→APK→install→firstlesson→result→History→review→restart/offline | APK/model/contentSHA, sourcefingerprint, smokevideo/logs, finalledger |

**Fault matrix ข้ามกลุ่ม:** cancel/dispose, owner/session change, rapid duplicate, delayed/reordered callback, permission denied/revoked, network timeout/offline, malformeddata/hash mismatch, disk/save failure, restart, clock/timezone/locale changes, low-memory/layout scale. เลือก valid combinations ตามarchitectureและrisk; ใส่ unsupportedพร้อมreason ไม่สร้างCartesian testsที่ไม่ช่วยพิสูจน์ระบบ

**ตัวอย่าง case ที่ต้องมี:** ST-05-FIRST-REPAIR ใช้ownerสังเคราะห์กับ6items ตอบแรกถูก5/6และrepair1/1 → ผลแรกยัง5/6, Historyคงrevision, reward receiptไม่เพิ่มเมื่อreplay; ST-04-WORD-REPEAT ใช้word `letter` แตะ/ลาก t/eแต่ละoccurrenceเข้าช่อง คืน/วางใหม่ และsubmitซ้ำ → ไม่มีtileซ้ำหายและมีdurableoperationตามpolicyครั้งเดียว

**Device evidence:** emulatorที่ระบุserial/version/config, syntheticaccount, installedcontentและbackup/hashก่อน-หลัง. Physicalcamera/audio/TalkBack/two-devicesync/liveproviderที่ต้องใช้สิทธิ์หรือคนตรวจแยกmanual/external. ไม่ใช้emulator/mockPASSแทนphysical/humanPASSและไม่สร้างข้อมูลชั่วโมงเรียนหรือผู้เข้าร่วมปลอมเพื่อปลดล็อก

**Exit criteria:** required casesมีผลจริงบนcompatiblefreeze, coveredrequirementsไม่มีunassigned/untestedrequiredrow, ไม่มีopencritical/highหรือin-scopefunctionaldefect, lower-severityacceptedlimitationsระบุชัด, changedinputsผ่านretest/affectedregression, requiredexternalที่ยังpendingทำให้releaseacceptanceยังไม่PASS

## คำสั่งและการจัดหลักฐานขณะ execution

คำสั่งต่อไปนี้เป็น recipe ในแผน **ยังไม่ได้รันรอบนี้**. Flutter targets ต่อpackageอยู่ในledger `plannedCommands`; ใช้จากreconciledworktreeเท่านั้น. G0ตรวจว่าtargetจากmainที่ไม่มีในR15ได้รับdispositionแล้ว

```powershell
# ตัวอย่าง P2.5: เลือก explicit targets โดยใช้ wrapper เดิมและ reuse ผลที่ inputs ตรง
& .\tool\cli\verify-scope.ps1 -Level Targeted -Area Learning -TestTargets @(
  'test/screens/word_scramble_screen_test.dart',
  'test/screens/sentence_scramble_screen_test.dart'
) -Resume

# F2 bounded CLI contract และ F3/F4 bounded evaluator ตาม protocol เดิม
powershell -NoProfile -File tool/cli/tests/r15-scope.tests.ps1
python -B -m unittest discover -s tools -p test_camera_accuracy.py

# P8.4 หลัง code review/freeze: generator เดิม ไม่ใช้ date หรือ branch name แทน full SHA
$reviewedSourceSha = (git rev-parse HEAD).Trim()
dart run tool/final_test_plan/generate_final_test_plan.dart --write --source-commit $reviewedSourceSha
dart run tool/final_test_plan/generate_final_test_plan.dart --check --source-commit $reviewedSourceSha
```

CLI/Python recipes เป็น targeted exceptions ที่มีในR15 protocol; รันserialพร้อมsource/logmanifestและไม่ใช้แทนfullbackend. BackendAI/BackendVoice/BackendLMใช้ `verify-scope.ps1 -Level Subsystem -Area <existing area> -Resume` ตามeditionและinputchanges. Full release command/deviceinstall argumentsต้องมาจากP8.4manifestที่freezeจริง ไม่เรียกจากplan draft

บันทึกใต้ `build/verification/<source-sha>/<package-or-testcase>/<run-id>/` เมื่อtoolรองรับ หรือคงexistingwrapperdirectoryและเก็บpointerในledger. Logrecordsมี command, start/end/duration, exitcode, target/testcount, source/dependency/confighash, stdout/stderr, screenshot/video/artifactpaths และ result. **ไม่รวมยอดtestsจากคนละSHAเป็นผลรันเดียว**

## การเก็บปัญหาและวงจรแก้ไข

เก็บ unexpected failure ตั้งแต่packageแรกและต่อเนื่องถึงSystemTest ไม่รอท้ายโครงการ. ใช้ run logสำหรับ expected negativecases เพื่อไม่ปนกับdefects. UI/logic/data/environment/fixture/tooling/content problemsแยกประเภทและมีหลักฐาน; secrets/PII/rawhumanrecordingsไม่ใส่log

```json
{
  "defectId": "DEF-<sequence>",
  "phasePackage": "P8.8",
  "caseId": "actual-case-id",
  "category": "logic|data|ui|lifecycle|environment|fixture|tooling|content",
  "severity": "P0|P1|P2|P3",
  "status": "open|reproduced|fixing|fixed-awaiting-retest|closed|external-pending",
  "sourceSha": "full-source-sha-from-run",
  "inputFingerprint": "actual-input-hash",
  "testPlanRevision": "actual-revision",
  "deviceAndConfig": "sanitized-environment-pointer",
  "fixture": "synthetic-owner-content-revision-pointer",
  "steps": ["record exact actions"],
  "expected": "case expectation",
  "actual": "observed result",
  "evidencePaths": ["actual-log-or-capture-path"],
  "rootCause": "diagnosis-or-explicit-not-yet-established",
  "ownerPackage": "actual-package-id",
  "fixSha": "record after fix",
  "retestRunId": "record after retest",
  "affectedRegression": ["record impacted gates"],
  "closureReason": "record only after evidence"
}
```

ด้านบนเป็น **schema example** ไม่ใช่ defectจริงหรือข้อมูลที่เติมสำเร็จแล้ว. Defectจริงห้ามใส่exampleplaceholderเป็นหลักฐาน. ลำดับ: reproduce → diagnose → regression RED → smallest fix → GREEN → scoped review → newfreeze → originalcase retest → affectedregression → close. ReopeneddefectคงID/ประวัติเดิม. ถ้าระบบ/environmentติดขัดต้องเก็บfailedrunและเหตุหยุด ไม่เปลี่ยนเป็นPASS

## Deliverables และเกณฑ์จบงาน

1. Source/authority reconciliation manifest พร้อม main/R15 dispositions และ F1–F4 evidence provenance
2. Active documentation index + cleanup/archive/restore ledger ที่ไม่มีข้อมูลสำคัญสูญหาย
3. 9 phase gates / 64 package checkpoints และ coverage74records + formula12groups บน sourceที่ตรวจได้
4. Whole-app code-review inventory/findings/remediation ledger; ทุกownedsourceมีdisposition
5. System Test Plan revisionที่สร้างหลังreview พร้อมcase/requirement/source/config/device/evidence mapping
6. Actual automated/device/manual results, defect/retest history และperformance/accessibility evidenceตามscope
7. Artifact hashes, model/content/config identity, rollback instructions และrelease ledgerแยกengineering/local/emulator/physical/human/live

R15.1–R15.10เสร็จไม่ได้แปลว่าMasterเสร็จ; codeมีอยู่ไม่ได้แปลว่าruntimeเปิดหรือผ่าน. “ครบถ้วน” หมายถึงknown-agreed-scopeมีปลายทางและrequiredacceptanceมีหลักฐานตามedition ไม่ใช่รับรองว่าได้เล่นทุกfeatureของคู่เทียบหรือไม่มีunknowndefect. หากexternalrequiredยังไม่ผ่านต้องเปิดเผยและไม่เรียกfullreleasePASS

**การดำเนินงานปัจจุบัน:** groupedexecutionหลังG0.5: 5accepted history +59requirementsใน20bundles. Astra/Medium, writerหนึ่งตัว, dispatchเมื่อbundleผ่านเท่านั้น. G8.2–G8.3 review/fixesต้องจบก่อนG8.4 Test Plan/execution. Pauseใหม่หยุดsuccession
