# LexiQuest — ดัชนีงานอารี

จุดติดตามงานเดียวใน repository · 2026-09-21 · branch `feature/ari-app-device-integration`

**สถานะปัจจุบัน: ต้นแบบแชตและ MCP ผ่านการสาธิตจริงบน Vivo แล้ว — ตอบไทย ถามต่อ อ่านคำศัพท์ เปิดแบบฝึก ยกเลิก และกู้คืนเมื่อออฟไลน์. ยังพึ่งสะพาน USB และยังไม่ใช่การรับรอง production/ทุกเมนู. [รายงาน](app-device-integration.md#chatmcp-live-execution--2026-09-21) · [หลักฐาน](chat-mcp-001.json). V2 เดิมยัง NOT_MET.**

**ผลก่อนหน้า: V1-R1 diagnostic เสร็จแล้ว — fake tests 17/17 และ binary smoke แบบไม่ล็อกอิน PASS** ตาม [รายงาน V1-R1](V1-R1.md); ยังไม่เริ่มต้นแบบเชื่อมบัญชีจริง V2 gate = NOT_MET; pilot = NOT_RUN; E7 ไม่เปลี่ยนสถานะ ผล 77 tests เดิมครอบคลุมการเปลี่ยนชื่อ ไม่ใช่ ChatGPT Free integration

| หัวข้อ | งานย่อย | ผลล่าสุด | รายงาน / handoff |
|---|---|---|---|
| V0 ช่องทางบัญชีและมือถือ | V0.1–V0.3 | ตรวจเอกสารแล้ว ยังมี entitlement/mobile unknowns | [รายงาน](evidence/tasks/V0.md) · [handoff](evidence/tasks/V0-handoff.json) |
| V1 การเชื่อมต่อและค่าใช้จ่าย | V1.1–V1.3 | NOT_MET จากช่องว่างช่องทาง G1–G5; G6 พร้อมออกแบบและทดสอบภายหลัง | [รายงาน](evidence/tasks/V1.md) · [handoff](evidence/tasks/V1-handoff.json) |
| V2 ต้นแบบ | V2.1–V2.3 | NOT_RUN; ยังไม่ได้สร้าง task | รอช่องทางที่รองรับตามแผน |
| V3 ตรวจรับและต่อยอด | V3.1–V3.3 | ปิดงานเอกสาร มีแบบตรวจ T01–T08; ยังไม่ได้ทดลองผู้เรียน | [รายงาน](evidence/tasks/V3.md) · [handoff](evidence/tasks/V3-handoff.json) |

## ไฟล์หลัก

- [แผนและข้อกำหนด](../ari-feasibility.md) · [workflow และกติกาสร้าง task](../ari-task-workflow.md)
- [สถานะปัจจุบันและ task IDs](state.json) · [ผลทดสอบโค้ดเดิม](../ari-feasibility-evidence.json)
- [รายการนำเข้าพร้อม hash](import-manifest.json) · [หลักฐานทดสอบฉบับเต็ม](evidence/verification/targeted-ai.json)

## ตำแหน่ง task

Sidebar กลุ่ม **LexiQuest · อารี** รวมโปรเจกต์หลักกับ task เดิมสามอัน:

| Phase | Task ID |
|---|---|
| V0 | `01a0bf7a-8427-78e3-bc73-ae1d57050622` |
| V1 | `01a0bf7d-e868-7df2-a2cb-db71829cd8d5` |
| V3 | `01a0bf81-3881-7c10-bc29-783868bf6212` |

Task เดิมถูกสร้างแบบ projectless ผิดจากรูปแบบงานของโปรเจกต์ การจัด sidebar ช่วยให้ค้นเจอด้วยกัน แต่ไม่ได้เปลี่ยน project binding เครื่องมือปัจจุบันเปลี่ยน binding นี้ไม่ได้โดยตรง Task ถัดไปต้องสร้างใน LexiQuest project ตาม workflow

นำเข้าหลักฐานเดิม 16 ไฟล์รวม 478,049 bytes โดยคงเนื้อหาและตรวจ SHA-256 ทุกไฟล์ใน `evidence/` ไม่ใช่การรันหรือรับ PASS ใหม่ พาธภายนอกที่ฝังอยู่เป็นประวัติ ใช้ลิงก์ในดัชนีนี้เพื่ออ่านสำเนาใน Git ต้นฉบับภายนอกคงไว้สำหรับตรวจย้อนกลับ ไม่เป็นที่เขียนงานใหม่

การเปิดงานต่อ: ต้องแก้ช่องว่าง route/entitlement/billing/distribution/revoke ตาม V1 ก่อนเริ่ม V2 โดยไม่เอาผล live tests มาเป็น prerequisite ก่อนสร้างต้นแบบ ไม่มีคำสั่งรันงานเก่า G/E จากการจัดเอกสารครั้งนี้

V1-R1 completed; writer released: task `01a0bf9c-3cc6-7a91-8355-6b857c613a75` · branch `feature/ari-app-server-probe` · [แผนและรายงาน](V1-R1.md) · [สถานะ](state.json).

หลักฐานใหม่: [V1-R1 evidence](V1-R1-evidence.json) · [binary smoke](V1-R1-binary-smoke.json) · [handoff](V1-R1-handoff.json). ไม่มี successor/V2 dispatch.

Application foundation completed; writer released: task `01a0bfa7-c450-7f10-8974-3dafeef31c43` · worktree `C:/Users/Phet/.codex/worktrees/bb3c/LexiQuest` · branch `feature/ari-managed-session-foundation`. Device acceptance: deferred-until-implementation-complete. [Design/report](application-foundation.md).

Current amendment: app-device-integration checkpoint in task 01a0bfbd-9961-7da3-982b-77970bdc7027, branch feature/ari-app-device-integration. Writer reacquired for user-authorized physical testing and defect recovery. Order: implementation -> automated tests -> physical device tests -> private user login -> authenticated acceptance. Earlier device deferral is superseded when implementation is ready. V2 remains NOT_MET.

Latest handoff: task `01a0bfbd-9961-7da3-982b-77970bdc7027`, branch `feature/ari-app-device-integration`; native private-login debug APK verified, inference gated, physical installation and device login PASS; inference NOT_RUN. Earlier foundation device deferral is historical.

Autonomous device testing authorized: [coverage and defects](device-test-matrix.json), [observed actions](device-observations.jsonl). Five primary tabs and several submenu flows inspected on installed version23; Quiz shortage recovery fixed with 31 screen tests passing. USB restored; isolated preview testing is active. Quiz shortage and dictation blank-input guards passed physical retests. History alias repair passed source/snapshot checks and the Vivo history screen now loads; remaining coverage is tracked in the matrix.

Latest physical checkpoint: four reproduced defects repaired and retested (quiz shortage, blank dictation, history alias, handwriting feedback). Mixed typed recall, associative reading, cloze/definition completion and all-level reading navigation exercised; exact Anki TSV plus bounded JSON/CSV reconciliation verified. Whole-app acceptance remains open; use the matrix for gaps.

Autonomous testing is now partially executed: **696 host tests in 53 distinct files / 6 bounded batches PASS; one native core journey with 23 phases and five adversarial assertions, plus two native fault cases PASS.** These are different evidence levels, not a whole-app acceptance percentage. [Results and pinned receipts](autonomous-run-001.json) · [14 modes / 64 registered menu-action IDs](autonomous-inventory.json) · [report](app-device-integration.md#autonomous-execution-2026-09-21). Original accounts preserved; ordinary isolated preview restored. Single-choice content, story quality, native accessibility and remaining acceptance are open.

Coverage plan: [structured plan](autonomous-test-plan.json) · [execution approach and acceptance](app-device-integration.md#autonomous-test-plan-2026-09-21). Sixteen domains, sequential P0–P6, explicit evidence levels; current results do not close every domain or the 180-minute endurance requirement.

Latest 2026-09-21: [all-menu MCP debug acceptance and 64-entry matrix](all-menu-mcp-001.json) · [implementation and native results](app-device-integration.md#all-menu-mcp-integration--debug-acceptance-2026-09-21). Live provider-driven menu navigation and current-screen context passed on Vivo; the installed isolated build requires the USB bridge. Earlier login-only/inference-not-run checkpoints above are historical. Writer released; no successor or production release dispatched.

Latest vocabulary continuation: [MCP submenu evidence](vocabulary-mcp-002.json) and [report](app-device-integration.md#vocabulary-mcp-continuation--2026-09-21). 76 host tests passed; final descriptor retest13 passed; representative live-provider journeys passed on Vivo. Personal-owner fencing and category-type ambiguity fixed. Whole-app/typed-form/offscreen-data coverage remains open; no background worker.

Typed word forms continuation: [evidence](typed-word-mcp-003.json). Fill/save transport and real-storage create/edit checks implemented; Flutter99 + affected retest12 and Python44 passed (not additive). Native live-provider acceptance awaits Vivo unlock; writer retained, no background worker.

Latest optional-assistance checkpoint: [native evidence](lesson-assistance-006.json). Visible committed feedback passed on Vivo; provider routing corrected and natural-language word create, duplicate rejection and edit/read-back passed. All14 workflow/mode acceptance remains open. Original app preserved; test fixtures and connection resources cleaned up.

Category forms and late AI attachment: [checkpoint](category-mcp-007.json). Typed category fill/save and independent local-owner binding implemented; 40 host tests and analysis passed. New native APK built but USB authorization is pending; no native PASS or whole-workflow completion claimed.
