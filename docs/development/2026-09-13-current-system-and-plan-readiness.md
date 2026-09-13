# LexiQuest — Current System and Plan Readiness

วันที่ 13 กันยายน 2026 · source-inspection snapshot revision2; authority update revision3

**สถานะปัจจุบัน: ผู้ใช้อนุมัติเริ่ม G0.1 แล้วส่งต่อทีละ task ผ่าน G8.9.** คำสั่งใหม่นี้แทนจุดหยุดหลังแผนใน revision2; ทุก task ใช้ `gpt-6-astra` / `medium` ตาม [Sequential Workflow](full-system-package-workflow.md). ตาราง source และผลตรวจด้านล่างเป็นหลักฐานขณะวางแผน ไม่ใช่ผล execution ล่าสุด. G0.1 ต้องตรวจ pins/dirty state อีกครั้งก่อนรับงาน

**กฎเก่า/ไฟล์เก่า:** active AGENTS และ [Rule Register](2026-09-13-rule-supersession-register.md) ยกเลิก authority ของ scope/workflow เก่าที่ขัดแย้งแล้ว. การตรวจ references/archive/delete ของ application artifacts อยู่ G0.6 และ G7.4; ยังไม่อ้างว่าลบไฟล์842cหรือแก้ GitHub แล้ว. สถานะ task จริงอยู่ external run-state/handoffs ตาม workflow

เอกสารหลักคือ [Full-System Master Plan](../superpowers/plans/2026-09-13-lexiquest-full-system-master-plan.md); [coverage audit](2026-09-13-master-plan-coverage-audit.md) ยังเป็น acceptance catalog ของ 44 capabilities ส่วนเอกสารนี้บันทึกสิ่งที่ตรวจพบใหม่และข้อจำกัด ไม่ตั้ง roadmap อีกชุด

## 1. วิธีตรวจและฐานที่ใช้

| รายการ | ผลที่ตรวจจริง |
| --- | --- |
| Worktree ของ task นี้ | `C:/Users/Phet/.codex/worktrees/7712/LexiQuest`, detached HEAD `7b8ac6cc029c0df43f9d4e7d161da3502e6f557b` |
| Source R15 ที่อ่าน | `C:/Users/Phet/.codex/worktrees/842c/LexiQuest`, branch `feature/r15-integration-continuation`, HEAD `f4eebb895836349fbf8e9960312a78bad524d462` และ working diff |
| สถานะงานที่เกี่ยวข้อง | snapshot ของ review task และ integration task เป็น idle; ไม่ได้ส่งคำสั่งให้ task อื่นหรือเขียนใน worktree เหล่านั้น |
| ความสัมพันธ์ Git | `git rev-list --left-right --count HEAD...feature/r15-integration-continuation` = 58 / 382; merge base `eb684f0f196d0f3f01abaca9d1e5def160c81109` |
| ขนาดความต่างระหว่างสอง HEAD | 1,596 files; ตัวเลขนี้เป็น diff summary ไม่ใช่จำนวน defect และยังไม่รวม F1–F4 working diff |
| Catalog | revision `1.3.0`, semantic hash `41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4`; 44 records / 8 domains |
| รูปแบบบทเรียน | enum มี 14 LessonModes; Adventure และ Ghost เป็น journey เพิ่มเติม ไม่เพิ่ม catalog เป็น 46 features |
| ขอบเขต code review ในอนาคต | R15 tracked `lib/**/*.dart` 611 ไฟล์ และ `test/**/*_test.dart` 468 ไฟล์ ก่อนแยก generated source; ยังต้องรวม backend/functions/native/policy/tooling ใน inventory ที่ freeze จริง |
| หลักฐานวิจัย | manifest 49 entries; path มีอยู่ 49/49 และ SHA256 ตรง 49/49 ในการตรวจเอกสารรอบนี้; ไม่ได้เปิดตรวจภาพทั้งหมดใหม่หรือเล่นแอปคู่เทียบใหม่ |
| การทดสอบ application รอบนี้ | NOT RUN: Flutter, Python evaluator, analyzer, build, emulator, backend, live provider, physical device |

อ่าน AGENTS.md, Master Plan, audit/minigame contract, สารบัญ spec/acceptance/source register, รายงานทดลอง/วิเคราะห์เดิม, checkpoint และ source/test บางส่วนที่เกี่ยวกับการตัดสินใจ ตารางด้านล่างจึงแยก **ข้อเท็จจริงจาก source**, **ความเสี่ยงที่ต้องตรวจ** และ **งานออกแบบที่เสนอ** ไม่ใช้คำว่าตรวจทั้งแอปแล้ว

## 2. Findings ที่มีผลต่อแผน

| ID | หลักฐาน / ข้อค้นพบ | ผลต่อ workflow และปลายทาง |
| --- | --- | --- |
| PLAN-01 | สองสาย Git ไม่ได้เป็น fast-forward; main มี runtime/storage/economy/backend/release changes ที่ไม่ปรากฏเป็น commit ancestry ของ R15 | P0.1–P0.3 ทำ disposition ราย change: equivalent / applicable port / conflict / superseded with reason; ห้าม merge ทั้งหมดหรือถือว่าขาด 58 ฟีเจอร์จากจำนวน commit |
| PLAN-02 | F1–F4 อยู่ใน working diff ของ 842c; hash ทั้ง 6 source/test/tool files ตรง `build/verification/r15-review/fixes-source.json` | รับเป็น repaired baseline candidate ใน P0.2 ตรวจ dependency/config/log pins ก่อน reuse; ไม่แก้ทั้งสี่ซ้ำและไม่อ้างว่ารัน tests เอง |
| PLAN-03 | Generated registrants 7 ไฟล์ค้างใน 842c แยกจาก F1–F4 | P0.2 บันทึก disposition ต่อไฟล์; regenerate ด้วย toolchain ที่ pin เมื่อจำเป็น ไม่คัดลอกตาม dirty status ทั้งหมด |
| PLAN-04 | R15 มี prior conversation context และ speech-attempt identity แล้ว แต่รายงานวิจัย/Source Register บางส่วนบรรยาย source ก่อน R15 ว่ายังไม่มี | P0.6 ทำ execution index และ supersession note; เก็บ observation เดิมเป็นประวัติ ไม่ใช้ stale source descriptions เป็น backlog ใหม่ |
| PLAN-05 | `LessonMode.defaultDelivery` ของ handwritingScratchpad เป็น implementedOff และ registry มี delivery parameters; `AppDependencies.focusTimerRollout` default implementedOff แต่ `app_bootstrap.dart` เปลี่ยนเป็น internal เมื่อ `learningPreviewEnabled` | ตรวจ actual composition ไม่สรุปจาก default เพียงจุดเดียว. P2.6/P4.3/P7.5 รับ timer preview ที่มีแล้วและปรับเฉพาะ delivery gap; ไม่สร้าง timer ใหม่ |
| PLAN-06 | f28 catalog route เป็น `research/assessment`; comparison ตรวจ protocol/assignment/consent/instrument/form/build/content metadata ร่วมกัน | P3.6/P7.5 ต้องแยกการทดสอบ synthetic ของ contract เดิมกับข้อเสนอ personal assessment. ห้ามถอด research gate หรือเพิ่ม enrollment เพื่อให้ catalog ดูครบ |
| PLAN-07 | WordScramble มี block slots, tap/drag, occurrence indexes, pending evidence/session close; tests มี correct/incorrect/durable retry และ semantics | P2.5 ตรวจ delta MG-01-A–F โดยเฉพาะ repeated-letter interaction, tap return, keyboard, resize และ owner change; การเห็น helper test สำหรับ repeated words ยังไม่พิสูจน์ทุก widget interaction |
| PLAN-08 | Save/report, offline manager, assessment, preferences, share card และ focus timer มี source/test อยู่แล้ว | P3/P4/P7 ตรวจ route + content + lifecycle + authority + result; ไม่สร้าง storage/controller อีกชุดเพียงเพราะหน้าจอไม่พร้อม |
| PLAN-09 | มี BinarySm2SrsPolicy v2, PairStarPolicy v1, AvatarProgressionPolicy v1, StreakPolicy v2 และ read models แยกกัน | P0.7 ทำ formula register; P1/P3/P4 ตรวจ boundary cases จาก policy เดิมก่อนตัดสินใจเปลี่ยนสูตร; preserve historical policy interpretation |
| PLAN-10 | Git ติดตามภาพใน `test/**/failures/*.png` จำนวน 76 ไฟล์ | เป็น cleanup candidates ที่ต้องตรวจ references และ defect status ใน P0.6; ไม่ใช่คำสั่งลบ 76 ไฟล์ทั้งหมด และไม่รวม `goldens` |
| PLAN-11 | มี `tool/final_test_plan/generate_final_test_plan.dart` และ final-test-plan contract tests อยู่แล้ว | P8.4 ใช้ระบบเดิมเพื่อออก Test Plan revision ใหม่หลัง code review. ตรวจ baseline/source pins และ gate compatibility ก่อน generate; ไม่เพิ่ม verifier ซ้ำ |
| PLAN-13 | `functions/` และ `tool/cli/tests/verify-scope.tests.ps1` อยู่ในสาย 7712/main แต่ไม่มีใน tracked inventory ของ R15; R15 มี `r15-scope.tests.ps1` | owner paths เหล่านี้เป็น source ของการ reconcile ไม่ใช่ paths ที่อ้างว่ามีใน 842c; P0.3 ตัดสิน integration ของ trusted backend และ CLI contract ก่อนใช้คำสั่งจาก main |
| PLAN-12 | การมี coverage row / test file / runtime enum ไม่เท่ากับ runtime acceptance | ทุก record มี source pin, status, requirement, routeหรือfoundation boundary, content state, test target, evidence และ external gate; G8 ห้ามใช้ Pair PASS แทน 14 modes |

### F1–F4 hash ที่ยืนยันรอบวางแผน

| Path ใน 842c | SHA256 ตรงกับ manifest |
| --- | --- |
| `lib/screens/ai_tutor_screen.dart` | `b7efd2a957fcb09604e54be89ac9be0bb0584d32072e99683f350341bc2ef171` |
| `test/screens/ai_tutor_screen_test.dart` | `8cfbff8be2aef6dd6b49623e04cad7db1bdc4f01c221043395bd9abb41bcf01f` |
| `tool/cli/verify-scope.ps1` | `c3c06c6c9c548c9fe990fc3ae883f3447d4b411dfebaf116a609048eedf39eae` |
| `tool/cli/tests/r15-scope.tests.ps1` | `27f28146b2c0202abdd54f35d26537536051a4df1bbd653cea4a817bdb42ac66` |
| `tools/camera_accuracy.py` | `fdc666c9cb238c7441784facba0cf98081acfdf146569df9cd29e1931d274476` |
| `tools/test_camera_accuracy.py` | `f2b854db94784a34957e766586ff077a6e7ecc34f76373819b5b6bf293587412` |

รายงานเดิมระบุ Flutter 155 cases / 11 targets, Python 20 cases, CLI และ analyzer ผ่าน; source fingerprint ที่รายงานคือ `abac5b94eee1ce55e460eb86ab7f1c8142cfb7d35206de1a98c3dceb20ec990b`. การเทียบ six-file hash รอบนี้ไม่ใช่การยืนยัน dependency closure หรือย้าย PASS มาที่ 7712

## 3. ใช้ข้อมูล Duolingo / ALLTCAS อย่างไร

ผู้ใช้ยืนยันว่า “AuthiCast” ในคำขอหมายถึง **ALLTCAS**. แหล่งหลักคือ [Source Register](../superpowers/specs/2026-09-12-r15-source-register.md) ซึ่งชี้รายงาน/ภาพ/วิดีโอต้นฉบับ และ [Minigame Contract](../superpowers/specs/2026-09-13-minigame-coverage-contract.md)

| สิ่งที่สังเกตได้จากหลักฐานเดิม | การตัดสินใจของ LexiQuest | ข้อจำกัด |
| --- | --- | --- |
| Duolingo correct/wrong/mistake retry; E-D04/D05/D08 | feedback อ่านได้, repair แยก first attempt, next action ชัด | ไม่ใช้ความยาว animation เป็นค่าที่วัดจริง |
| ALLTCAS Matching/flashcard/quiz/cloze; E-A05–A15 | mode-specific interaction + shell ร่วม, คำอธิบายอยู่ใน viewport, tap alternative | ไม่เหมารวมเกมที่เห็นเพียงเมนูว่าเล่นแล้ว |
| ALLTCAS TGAT short dialogue และผล first5/6, repair1/1; E-A18–A25 | content revision และ distractor-specific explanation, separate result/read models | ไม่คัดลอกข้อสอบ/asset และไม่สร้าง admission calculator |
| Duolingo onboarding/path และ ALLTCAS catalog | Today มีคำแนะนำพร้อมเลือกฝึกเอง | ข้อเสนอผลิตภัณฑ์ ไม่ใช่หลักฐาน causal efficacy |
| ALLTCAS AI follow-up/ข้อความบางช่วงหาย; E-AI152–161 | session-only bounded context, plain text ที่อ่านได้, stale cancellation | ไม่อนุมาน root cause renderer หรือรับ retention 90 วันเป็น contract |
| ALLTCAS timer/stat gate; E-SYS164/165 | timer แยก active effort; สถิติส่วนตัวไม่ผูกการปลดล็อกชั่วโมง | กราฟหลัง gate ยังไม่ใช่ observed layout |
| WordQuest adaptation | ใช้ wordScramble เดิมเป็น MG-01 | missing-letter mask proposal ถูกยกเลิกแล้ว |

แหล่งเดิมมีภาพ 49 ภาพและวิดีโอต้นฉบับ 4 ชิ้น ข้อจำกัดยังครอบคลุม paid AI/video call, หลายเมนู, audio/TalkBack, next-day behavior, physical camera และ live sync. รายการเหล่านี้มีสถานะ external/not verified ตามงานที่เกี่ยวข้อง ไม่ตั้งเป็น PASS เพื่อปิดแผน

## 4. ข้อเสนอออกแบบที่เลือกและทางเลือก

1. **แนะนำ: ปิด delta ตาม authority เดิมเป็นราย package.** ใช้ R15 เป็น baseline candidate, reconcile ความต่าง main, เติมเฉพาะ feature/lifecycle/evidence gaps. ลดการทำซ้ำแต่ต้องมี coverage ledger ที่ซื่อสัตย์
2. **Rewrite ทั้งระบบ.** เสี่ยงเสีย migration/history/reward semantics และทำฟีเจอร์ที่มีแล้วซ้ำ ไม่เลือกเพราะยังไม่มีหลักฐานว่า architecture เดิมใช้ต่อไม่ได้
3. **ทำ UI ก่อนแล้วค่อยแก้ข้อมูล.** เห็นภาพเร็ว แต่ตัวเลขและสถานะที่ UI แสดงอาจคลาดเคลื่อน ไม่เลือกเป็นลำดับหลัก; ใช้ visual work หลัง G1 พร้อมเท่านั้น

ดีไซน์ใช้ view → controller/use case → canonical repository/event/receipt → read model → view. AI, camera, voice และ sync เป็น adapters ที่ล้มเหลวได้โดย ordinary local learning ยังมีทางไปต่อ. เมื่อพบ authority สองสายจาก Git ให้ทำ versioned compatibility decision ใน P0/P1/P7 ไม่เชื่อม writer ซ้อนกัน

## 5. ขอบเขตการจัดข้อมูลเก่า

ได้รับอนุมัติแล้วและทำตามลำดับ G0.6/G7.4: จัด Active / Historical / Superseded / Generated-Reproducible / Unreferenced-Candidate พร้อม source hash, inbound references, replacement, rollback. Active index ชี้ Master Plan นี้เป็นลำดับแรก; R15 roadmap เป็น completed-milestone history และ spec/acceptance ที่ยังใช้คง active เป็นข้อกำหนดรอง

ข้อมูลเรียนจริง, owner history, reward receipts, migration, consent/protocol, dataset provenance, camera freeze และหลักฐานที่ยังอ้างอิงไม่ใช่ขยะ. Cache removal ต้องทดสอบว่าไม่ลบ canonical vocabulary/history. ใช้ dry-run list และ archive manifest ก่อนลบไฟล์ที่พิสูจน์แล้วว่า regenerate ได้หรือไม่ถูกใช้งาน. ไม่ลบทั้ง worktree/build/docs จากอายุไฟล์

## 6. ปัญหาระหว่างการวางแผน

- `PLAN-OPS-01`: การค้นด้วยโครงสร้างที่คาดเดาพบ `lib/app` และ `lib/runtime/production_bootstrap.dart` ไม่มีอยู่ใน R15. หยุดการอ่านแบบคาดเดาและใช้ `git ls-files` เป็น inventory ตาม AGENTS; ตำแหน่ง bootstrap ที่ยืนยันคือ `lib/runtime/app_bootstrap.dart`. ไม่มีไฟล์ application ถูกแก้และเหตุการณ์นี้ไม่ใช่ runtime defect
- Output บางคำสั่งยาวถูก truncate; ลดเป็น headings, exact sections, file inventory และ bounded results. ไม่ใช้ส่วน output ที่หายไปเป็นหลักฐาน

## 7. เงื่อนไขรับงานตามการอนุมัติปัจจุบัน

- Master Plan มี 9 phases / 64 packages, coverage 44 features + 14 modes + 2 journeys + 14 MG groups ไม่มีรายการไร้ปลายทาง
- Source reconciliation และ delivery decisions เป็นงานต้นแผนที่ต้องปิดก่อนกล่าวว่าระบบพร้อม; ไม่มี application PASS ใน ledger จากการตรวจเอกสารครั้งนี้
- Full code review อยู่หลัง G1–G7 และก่อนการออก System Test Plan ฉบับ executable. Plan revision, source freeze และ defect log ต้องสัมพันธ์กัน
- คำสั่งผู้ใช้ล่าสุดให้ **เริ่ม G0.1 แล้วส่งต่อทีละ task**. เริ่ม source/ownership/bootstrap ได้และให้ package ถัดไปทำงานตามขอบเขตที่ตรวจรับ; actual state อยู่ run-state ไม่ใช้จุดหยุด revision2 เป็นเหตุขออนุมัติซ้ำ

## 8. ผลตรวจเอกสาร revision2 ก่อนส่งผู้ใช้ — historical snapshot

ตรวจด้วย bounded PowerShell/JSON parsing และ Git inventory: Master มี 64 package headings ที่ไม่ซ้ำและตรง ledger, 9 phase counts รวม 64, coverage 74 rows แยก 44/14/2/14, formula 12 groups, review 12 zones และกรอบ System Test Plan 16 families. ทุก coverage row ชี้ package ที่มีจริง และไม่มี runtime record ถูกระบุเป็น verified-existing

ลิงก์ relative ใน Master Plan และรายงานนี้ resolve ได้ครบ; source/test paths ที่ใช้ในแผนตรวจจาก R15 inventory และ main-only inputs ตาม PLAN-13. Hash ของภาพทั้ง49ตรงกับ manifest. การตรวจเหล่านี้เป็น document/source-reference verification ไม่ใช่ application tests

ณ checkpoint revision2 ก่อนแก้ AGENTS/เอกสาร sequential-3: Git ของ 7712 อยู่ HEAD `7b8ac6cc029c0df43f9d4e7d161da3502e6f557b`; `git diff --quiet` คืน exit0 และ status มีเพียงเอกสาร untracked ที่รับมอบ/จัดทำ. ไม่มี tracked application/source changes, ไม่มีการลบข้อมูล, ไม่ commit/push. Ledger ระบุ executionAuthorized=false และ paused-awaiting-user-review
