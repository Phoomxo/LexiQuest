# R15 Autonomous Development Roadmap

> **For agentic workers:** ใช้ executing-plans เมื่อได้รับคำสั่งลงมือ ดำเนินทีละงานใน worktree เดิมโดยผู้พัฒนาคนเดียว ไม่ dispatch subagent และไม่เปิดบริการจริงโดยปริยาย

**Goal:** จัดลำดับงานต่อจาก R14/Prototype 3 และผลศึกษา Duolingo–ALLTCAS ให้พัฒนาระบบภาษาอังกฤษต่อเนื่องได้โดยไม่ต้องรอผู้ใช้ในวงจรพัฒนาทั่วไป

**Architecture:** พัฒนาจากระบบ local-first และ canonical authorities เดิม เชื่อม UI–กิจกรรม–ผล–ทบทวน–ความก้าวหน้าเป็นวงจรเดียว แยก camera/AI experiments และ external acceptance ออกจากแกนเรียนฟรี

**Tech Stack:** Flutter/Dart, Drift/SQLite, existing LiteRT runtime, Python camera tools, local HTTP/Firebase emulators และ existing test/build tooling

**สถานะ:** แผนจัดลำดับเวอร์ชัน R15 วันที่ 2026-09-12 พร้อมชุด engineering specification revision R15.1 ไม่ใช่รายงานว่าลงโค้ดหรือผ่าน runtime acceptance แล้ว ชื่อ R15 เป็นรุ่นแผน ไม่ใช่ APK version code แผนครอบคลุมหลายระบบจึงแบ่งเป็น work packages ที่จบและตรวจรับแยกได้

**เอกสารบังคับอ่านสำหรับ implementation:** [engineering spec และ screen templates](../specs/2026-09-12-r15-engineering-spec.md), [source register และ decision traceability](../specs/2026-09-12-r15-source-register.md), [implementation/acceptance contract](2026-09-12-r15-acceptance-contract.md), [manifest ภาพอ้างอิงพร้อม SHA-256](../specs/2026-09-12-r15-evidence-manifest.json). รายละเอียดที่ชัดกว่าใน spec/acceptance มีลำดับเหนือข้อความกว้างใน roadmap นี้

**คำชี้แจงผู้ใช้ล่าสุด:** ข้อกำหนด UI/เกมเก่ามักเป็น workaround ของปัญหาเฉพาะจุด สามารถปรับแทนจากหลักฐานและรูปแบบที่เหมาะกว่าได้ ไม่ต้องรักษา layout/interaction/code เดิมเพียงเพราะเคยระบุไว้ ใช้ทะเบียน old rule → evidence → new rule → acceptance ใน engineering spec; รักษาความถูกต้องของข้อมูล/ผลการเรียนและสิทธิ์การเข้าถึง แทนการล็อกหน้าตาเก่า

## 1. ฐานข้อมูลที่ใช้ตัดสินใจ

- Active worktree: `C:/Users/Phet/.codex/worktrees/4366/LexiQuest` เป็น detached HEAD `8c160f87d77d8beb8ace2d8f2b7b0e92acb297ac`; ก่อนเขียนแผน Git status ว่าง
- Worktree `02fa/LexiQuest` สาขา `prototype-3-minimal-ui` อยู่ HEAD เดียวกันและ status ว่าง
- `ccf29d67` สำรองงาน R14 รวม 591 ไฟล์; `8c160f87` ปรับ Prototype 3 รวม 14 ไฟล์ ดังนั้นคำว่า “ไม่มี commit” ใน checkpoint R14 เป็นประวัติก่อน snapshot นี้ ไม่ใช่สถานะปัจจุบัน
- แผน minimal UI ยังมี checkbox commit/push ไม่ติ๊ก แต่ commit มีจริงแล้ว ต้องตรวจ remote โดยเฉพาะก่อนกล่าวว่า push ล่าสุดสำเร็จ รอบนี้ไม่ได้ fetch/push
- มี uncommitted changes ใน worktree อื่นจริง: checkout หลักมีเอกสาร/AGENTS/ภาพ, `e559` มี iOS/plugin generation, `f00a` มี Supabase config และ release-input tools, `complete-field-trial-release` มี navigation/feature registry, `adventure-motivation-plan` มี sync entity/generated DB ส่วนหลาย release worktrees มี generated registrants รายการนี้เป็น inventory ไม่ใช่ข้อสรุปว่าทุก delta ควร merge
- รายงาน R14 มี historical selected regression 826 ผ่าน และรายงาน unattended มี selected checks ของอีก source state ห้ามบวกเป็นผลทดสอบรอบใหม่หรืออ้างแทน HEAD ปัจจุบัน
- ผลศึกษา competitor อยู่ใน [รายงานวิเคราะห์รวม](C:/Users/Phet/.codex/visualizations/2026/09/12/01a095a8-40ba-7031-817d-406822b5d3aa/lexiquest-consolidated-development-analysis.md) พร้อมข้อจำกัด guest/Android 9/ตัวอย่างบางโหมด/AI สี่ข้อความ ไม่ใช่การศึกษาทุกฟีเจอร์ครบถ้วน

## 2. กติกาที่ใช้ทุกระยะ

1. คง approved catalog 8/44 และ frozen EvidenceContext/EventEnvelopeV2; ไม่เพิ่ม learning/reward authority ซ้ำ
2. ไม่เปลี่ยน baseline camera model ด้วยคะแนน pilot สี่คลาส และไม่เปิด AI/Cloud เป็นข้อบังคับของการเรียน
3. ไม่มี paid service, purchase, deployment, enrollment, real research upload หรือ destructive cleanup จากแผนนี้ ใช้ synthetic fixtures/local emulator; ไม่มี Codex Security workflow
4. ถ้าพบความผิดพลาดที่ทำให้ข้อมูลผิด/รางวัลซ้ำ/owner รั่ว ให้ย้าย defect นั้นขึ้นก่อนงานภาพทันที แต่ไม่เขียนว่ามี defect เหล่านี้แล้วโดยไม่มี reproduction
5. ทุก owner-scoped storage ใหม่ต้องมี migration, export/delete และ applicable sync/policy; ตรวจ schema ปัจจุบันก่อนกำหนดเลข migration
6. หนึ่งผู้พัฒนา หนึ่ง worktree หนึ่ง Flutter test/build/codegen ต่อเวลา; ไม่แก้ไฟล์ข้าม worktree ระหว่าง inventory
7. ใช้สาขาเดิมของงานเมื่อเหมาะสม ไม่ใช้ prefix `codex/`; ถ้าต้องผูก detached HEAD ให้สร้างชื่อที่ไม่ชนโดยไม่สลับ branch ที่อีก worktree ใช้อยู่ ไม่ force-push
8. คำขอปัจจุบันอนุญาตสร้างแผน ไม่ใช่ merge งานค้างทั้งหมดหรือเริ่ม implementation; เมื่อผู้ใช้สั่งทำตามแผน ให้ตัดสินใจรายละเอียดปกติเองและไม่ถามซ้ำทุก package

## 3. ลำดับและ dependency

| ลำดับ | Package | ผลที่ต้องส่ง | เหตุผลที่อยู่ตรงนี้ | ขึ้นกับ |
| --- | --- | --- | --- | --- |
| 0 | R15.0 ฐานงาน/งานค้าง | disposition ของ delta + source pin + baseline checks | ป้องกันเริ่มจากงานเก่าหรือทำสิ่งที่เสร็จแล้วซ้ำ | ไม่มี |
| 1 | R15.1 ข้อมูล/เส้นทางหลัก | loop ใช้จริงได้ ข้อมูลและรางวัลเชื่อถือได้ | เป็นฐานของ UI และ dashboard | 0 |
| 2 | R15.2 Feedback/lesson UI | รับรู้ selected/correct/wrong/support และคู่สุดท้ายชัด | ช่องว่างจาก code และ competitor มีหลักฐานตรง | 1 |
| 3 | R15.3 Layout/Today/คลัง | เริ่มเรียนง่าย เลือกฝึกได้ หน้าภายในสม่ำเสมอ | ทำให้ระบบเดิมเข้าถึงได้ | 2 |
| 4 | R15.4 เนื้อหา/เฉลย/ทบทวน | เรียนแล้วเข้าใจและมีขั้นถัดไป | ลูกเล่นต้องมีเนื้อหาและการฝึกที่ถูกต้องรองรับ | 1, 3 |
| 5 | R15.5 Dashboard/เป้าหมาย | อ่านความก้าวหน้าได้ตรงความหมาย | ต้องอาศัยนิยามข้อมูลจาก 1 และ 4 | 4 |
| 6 | R15.6 Camera UX/runtime | รับมือไม่มั่นใจ/ไม่รู้จัก/โมเดลไม่พร้อมอย่างชัดเจน | ให้ฟีเจอร์ใช้งานได้ก่อนทดลองโมเดลใหม่ | 1, 3 |
| 7 | R15.7 Camera evaluation/model | ชุดข้อมูลและเกณฑ์รับ/ปฏิเสธ candidate ที่ทำซ้ำได้ | ความเสี่ยงสูงกว่างาน UI ต้องวัดก่อนแทน | 6 |
| 8 | R15.8 Motivation/motion | เป้าหมายและผลตอบรับมีความหมาย ไม่ขัดการเรียน | ต่อจาก loop และตัวเลขที่ถูกต้อง | 5 |
| 9 | R15.9 AI Tutor | บริบทหลายข้อความ/ระดับ/การแสดงผลที่ทดสอบได้ | optional และ live quality มี dependency ภายนอก | 4 |
| 10 | R15.10 Voice/sync/release | local integration regression และ preview artifact | ปิดช่องว่างระบบประกอบและตรวจ source รวม | 1–9 เฉพาะส่วนที่รับเข้า |

ลำดับข้างต้นคือ queue ของผู้พัฒนาคนเดียว ไม่ใช่สั่งทำทุกงานพร้อมกัน ถ้า R15.7 ไม่มี representative data ให้บันทึกผลไม่ผ่านการเปลี่ยนโมเดลและคง baseline แล้วเดิน R15.8–10 ต่อ การรอ physical scene/live service ไม่หยุด local packages

## 4. รายละเอียด package และเกณฑ์ปิดงาน

### R15.0 — เคลียร์ความหมายของงานค้าง

**ตรวจ:** Git worktree/status/log/diff, `docs/superpowers/plans/2026-09-12-minimal-ui-comparison.md`, `docs/development/2026-09-12-system-followup-r14-checkpoint.md`, `docs/development/2026-09-12-unattended-system-checkpoint.md` และ active guardrails

- [ ] บันทึก path/branch/SHA/changed paths ของทุก worktree ที่พบในรอบนี้ อ่าน diff เฉพาะ candidate ที่สัมพันธ์กับ scope ปัจจุบัน
- [ ] จัดแต่ละ candidate เป็น already incorporated / useful unique / obsolete generated / unrelated / overlapping unresolved พร้อมหลักฐานเปรียบเทียบ ห้ามตีความชื่อสาขาว่าใหม่กว่าหรือพร้อมกว่า
- [ ] ไม่ยกทั้ง old branch มารวม; ถ้าพบ useful unique ให้แยก integration task พร้อม reproduction/checks ส่วน overlapping writes หยุดเฉพาะไฟล์นั้น
- [ ] จัดเก็บสรุป competitor และ provenance ที่ใช้ตัดสินใจใน repo; คัดเฉพาะภาพที่จำเป็นและตรวจว่าไม่มี auth/PII ไม่ commit raw artifact directory ทั้งก้อน
- [ ] แก้ checkbox/history discrepancy ด้วยหมายเหตุปัจจุบัน ไม่แก้ผลย้อนหลังให้เหมือนทดสอบที่ HEAD ใหม่
- [ ] รัน baseline ตาม task scopes ถัดไป บันทึก pre-existing failures แยกจาก new failures

**ปิดงานเมื่อ:** รู้ฐานที่ใช้จริงและ disposition ของงานเกี่ยวข้อง ไม่จำเป็นต้อง merge ทุก worktree จึงจะเริ่ม UI ได้

### R15.1 — ความถูกต้องของ local system และเส้นทางเรียน

**Existing files:** `lib/screens/main_navigation_screen.dart`, `lib/screens/learning_history_screen.dart`, `lib/features/today_hub/application/today_hub_use_cases.dart`, `lib/features/progress/data/drift_personal_learning_profile_reader.dart`

**Checks:** `test/screens/main_navigation_screen_test.dart`, `test/screens/learning_history_screen_test.dart`, `test/features/progress/personal_learning_profile_test.dart`, `test/scenarios/file_backed_sync_recovery_test.dart`, `test/features/account/local_data_deletion_test.dart`

- [ ] ตรวจ Today → เรียนต่อ → จบ → History → replay → กลับ Today ที่ source ปัจจุบัน; R14 เคยเชื่อม replay แล้ว ไม่สร้าง callback/engine ซ้ำ
- [ ] ตรวจ duplicate submit, restart, owner switch, unavailable/stale content และ retry identity ด้วย synthetic file-backed fixtures
- [ ] ยืนยัน replay/repair/exposure ไม่แปรเป็น first-attempt accuracy หรือ duplicate XP/coins; ถ้าพบช่องว่างให้เขียน regression ก่อนแก้
- [ ] ตรวจการเปลี่ยน schema ถ้ามีจริงเท่านั้น; ใช้ migration/export/delete เดิม ไม่สร้างตารางสำหรับ presentation state

**ปิดงานเมื่อ:** restart แล้วยังได้ผลเดิม, retry ไม่ให้รางวัลซ้ำ, การเปิดหน้าว่างไม่สร้าง learning evidence และเส้นทางเรียนไม่ต้องเปิด cloud

### R15.2 — Feedback และรูปแบบระหว่างฝึก

**Modify:** `lib/features/learning/pair_matching/presentation/pair_board_view.dart`, `lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart`, `lib/features/learning/presentation/unified_lesson_shell.dart`

**Tests:** `test/features/learning/pair_matching/pair_board_view_test.dart`, `pair_matching_experience_host_test.dart`, `pair_board_accessibility_test.dart`, `pair_board_golden_test.dart` ใน directory เดียวกัน

- [ ] เพิ่ม presentation feedback หลัง accepted-correct ก่อนซ่อน pair โดยแยกจาก assisted/repair; สีต้องมีข้อความหรือสัญลักษณ์ประกอบ
- [ ] ผล durable ต้องบันทึกทันทีตาม authority เดิม ไม่รอ animation; input ซ้ำและ animation callback ไม่สร้าง attempt/reward เพิ่ม
- [ ] คู่สุดท้ายต้องแสดงผลตอบรับก่อน result route; interruption/restart/route disposal ต้องไม่ค้างและไม่ย้อน terminal state
- [ ] ใช้ state-driven motion และ reduced-motion; เริ่มด้วยค่าชั่วคราวใน theme/motion token แล้ววัดจาก preview ไม่อ้างว่า timing จากวิดีโอ competitor เป็น specification
- [ ] เก็บ golden/screenshots ของ correct/wrong/assisted/final pair, จอแคบและข้อความ 200%; ตรวจว่าข้อความ/ปุ่มไม่ถูกตัด

**ปิดงานเมื่อ:** ผู้เรียนแยกตอบถูกเองกับมีตัวช่วยได้ และจบเกมได้ครบทั้ง motion ปกติ/ลด motion โดย engine semantics เดิม

### R15.3 — Frontend layout และ navigation

**Modify:** `lib/config/m3_theme.dart`, `lib/screens/today_hub_view.dart`, `lib/screens/choose_mode_screen.dart`, `lib/screens/learning_pack_catalog_screen.dart`, `lib/screens/main_navigation_screen.dart`

**Tests:** `test/screens/today_hub_screen_test.dart`, `test/screens/learning_pack_catalog_screen_test.dart`, `test/screens/main_navigation_screen_test.dart`

- [ ] Today ชู action หลักจาก snapshot จริง: เรียนต่อ/ทบทวน/เริ่ม พร้อมเหตุผลสั้น และเปิดทางเลือกฝึกเอง
- [ ] ใช้ Prototype 3 เป็นจุดเทียบ before ไม่ใช่ข้อห้าม redesign; ปรับ grid/list/alignment/theme/shell ตาม UI-01–08 และหลักฐานใหม่ พร้อมตรวจหน้าภายในที่ override theme
- [ ] เพิ่มความสม่ำเสมอของหัวข้อ spacing สีตามบทบาท ปุ่มหลัก/รอง disabled/loading/empty/error และ bottom safe area
- [ ] ลดชื่อหัวข้อซ้ำ กรอบ/การ์ดที่ไม่มีหน้าที่ และหน้าคั่นรางวัลที่ไม่จำเป็น; ไม่ลบ capability จาก 8/44 เพียงเพราะลดเมนู
- [ ] แสดงระดับ/จำนวนเนื้อหา/ความพร้อมเฉพาะที่ยืนยันได้ ไม่ใส่ progress/path node สมมติ

**ปิดงานเมื่อ:** เข้าฝึกและกลับเส้นทางหลักได้ที่จอ 320/390 และหน้ากว้าง, light/dark/text 200%, focus/semantics ใช้ได้; visual QA ไม่เท่ากับ human usability/TalkBack acceptance

### R15.4 — คุณภาพการเรียนและ review

**Existing files:** `lib/features/learning/application/unified_lesson_controller.dart`, `lib/features/learning_packs/domain/content_quality_policy.dart`, `lib/screens/review_center_screen.dart`, `lib/features/review/application/review_center_use_cases.dart`, `lib/screens/learning_history_screen.dart`

**Tests:** `test/features/learning/unified_lesson_controller_test.dart`, `test/features/learning_packs/content_quality_policy_test.dart`, `test/screens/review_center_screen_test.dart`

- [ ] แยก flashcard self-report, recognition, contextual answer, exposure, delayed review ในคำอธิบายและการอ่านผล โดยไม่แก้ frozen envelope
- [ ] ให้เฉลยสั้นตอบว่าเหตุใดถูก/ผิดก่อน แล้วเปิดรายละเอียด/ตัวอย่างที่ตรงเวอร์ชันเนื้อหาได้
- [ ] ตรวจ distractor, cloze ambiguity, reading question/answer alignment และ CEFR label; ไม่เรียกเนื้อหาประมาณระดับว่า certified
- [ ] Result → ฝึกข้อผิด/Review Center ใช้ authority เดิม; การฝึกแก้ไม่ทับผลครั้งแรก
- [ ] ใช้ clock fixture ทดสอบ due review ข้ามวัน/timezone; ไม่เพิ่ม SRS rows ให้ผู้ใช้จริงเพื่อจัดฉากทดสอบ

**ปิดงานเมื่อ:** จบกิจกรรมแล้วเห็นสิ่งที่ได้ฝึก สิ่งที่ยังควรฝึก และไปต่อได้โดยไม่ต้องพึ่ง AI

### R15.5 — Dashboard และเป้าหมายที่ไม่ต้องมี server ใหม่

**Modify:** `lib/screens/mastery_dashboard_screen.dart`, `lib/features/progress/domain/personal_learning_profile.dart`, `lib/features/progress/data/drift_personal_learning_profile_reader.dart`, `lib/screens/learning_goals_screen.dart`, `lib/screens/study_reminder_settings_screen.dart`

**Tests:** `test/screens/mastery_dashboard_screen_test.dart`, `test/features/progress/personal_learning_profile_test.dart`, `test/features/reminders/study_reminder_use_cases_test.dart`

- [ ] จัดหน้าเป็นสัปดาห์นี้ → ควรทำต่อ → รายละเอียด ใช้ profile/read models เดิม ไม่สร้าง analytics service อีกชุด
- [ ] แยก accuracy พร้อมจำนวนตัวอย่าง, active practice time, mastery/SRS, streak/XP; ไม่มีข้อมูลใช้ noEvidence ไม่วาดศูนย์เป็นผลสอบ
- [ ] แสดงการเปลี่ยนแปลงจากช่วงข้อมูลที่เทียบกันได้ ไม่สร้าง learning improvement claim จาก streak
- [ ] Goals/reminders ใช้ timezone และ scheduler เดิม; permission denied ยังเรียนได้ และไม่สร้าง notification ซ้ำ

**ปิดงานเมื่อ:** ค่าบนกราฟเทียบ fixture ledger ได้ทุกตัว ทั้ง empty/small-sample/replay/exposure และข้ามเที่ยงคืน

### R15.6 — กล้องใช้งานได้อย่างชัดเจนก่อนเปลี่ยนโมเดล

**Modify:** `lib/screens/object_scanner_screen.dart`, `lib/features/media_practice/application/object_scanner_use_cases.dart`, `lib/features/media_practice/application/image_preprocessor.dart`, `lib/features/media_practice/data/plugin_camera_gateway.dart`

**Tests:** `test/screens/object_scanner_screen_test.dart`, `test/features/media_practice/object_scanner_use_cases_test.dart`, `test/features/media_practice/image_preprocessor_test.dart`, `test/features/media_practice/plugin_camera_gateway_test.dart`

- [ ] ตรวจเส้นทาง permission/model missing/download cancel/retry/camera resume/dispose และผลตอบกลับจาก route เก่า
- [ ] แยก “โมเดลไม่มั่นใจ” จาก “พบ label แต่ไม่มีคำศัพท์รองรับ”; แสดงถ่ายใหม่/เพิ่มคำด้วยตนเองตาม capability เดิม ไม่บันทึกคำอัตโนมัติเพียงเพราะมี top-1
- [ ] ปัจจุบัน use case กรอง confidence แล้ว lookup เฉพาะ primary label: ประเมินข้อจำกัดนี้ก่อนออกแบบ candidate chooser ไม่เลือก label อันดับต่ำเพราะแปลได้โดยปิดบังอันดับ/ความไม่แน่ใจ
- [ ] ตรวจ rotation/crop/resize/RGB normalization และ repeated open/close ด้วย fixture; accept ซ้ำไม่สร้างคำซ้ำและ source มี model identity เดิม

**ปิดงานเมื่อ:** offline/cache states และ errors มีทางออก; mocked camera ไม่ถูกอ้างเป็น physical scene accuracy

### R15.7 — โมเดลกล้องและชุดประเมิน

**Existing files:** `tools/prepare_openimages_pilot.py`, `tools/train_camera_pilot.py`, `tools/export_camera_pilot.py`, `tools/camera_accuracy.py`, `tools/test_camera_accuracy.py`, `lib/features/device_model/domain/model_manifest.dart`, `lib/features/device_model/data/litert_image_classifier.dart`

**ฐานหลักฐาน:** baseline quantized MobileNet มี 1001 outputs ตาม manifest; pilot มี 4 คลาส การใช้ threshold 0.15 กับ softmax 4 คลาสปฏิเสธ unknown ไม่ได้ เพราะ maximum อย่างน้อย 0.25 ผล 40 ภาพและ timing บน vivo ในรายงานเดิมไม่ครอบคลุม natural unknown/physical scenes หลายแสง

- [ ] ทำ inventory รูป/labels/license/provenance/hash/splits และ audit source-group leakage; ภาพ test เดิมที่นำผลมาวิเคราะห์แล้วให้เป็น regression set สำหรับรอบใหม่ ไม่ปรับโมเดลตามชุดนั้นแล้วอ้างเป็น fresh held-out
- [ ] เตรียม validation และ fresh held-out ที่มี known/unknown natural scenes, หลายวัตถุ/ฉาก/แสงเท่าที่หาได้จากข้อมูลที่อนุญาต ไม่ใช้ UI golden เป็นตัวแทน unknown ธรรมชาติ
- [ ] ประกาศ coverage, per-class metrics, false acceptance ของ unknown, rejection ของ known, latency/memory/model size ก่อน training; เลือก threshold/calibration จาก validation เท่านั้น
- [ ] การขยายคลาสต้องอิงคำศัพท์ที่ผลิตภัณฑ์รองรับและตัวอย่างเพียงพอ; เริ่มทางเลือกปรับ calibration/preprocessing/baseline ก่อนเพิ่ม detector หรือ neural model อีกตัว
- [ ] เปรียบเทียบ pipeline เดียวกันแบบ paired; แยก decode/preprocess/invoke/mapping, cold/warm, CPU/delegate และ repeated lifecycle; เก็บ model/data/environment pins
- [ ] Candidate ไม่ผ่าน coverage/open-set/resource criteria ให้ปิด experiment ด้วย retain-baseline decision ได้ ไม่ฝึกวนจนชนะ test set
- [ ] ก่อนเสนอ ship ต้องมี manifest/hash/license/compatibility/download interruption/rollback checks และ physical acceptance ที่แยกไว้ ไม่สับเปลี่ยน shipped manifest ในงานทดลอง

**ปิดงานส่วนอัตโนมัติเมื่อ:** ได้รายงาน reproducible พร้อมข้อสรุปรับไปประเมินต่อหรือคง baseline; การไม่เปลี่ยนโมเดลเป็นผลลัพธ์ที่ยอมรับได้ ไม่อ้าง production accuracy โดยไม่มีหลักฐาน

### R15.8 — ลูกเล่นและแรงจูงใจ

**จุดต่อ:** theme/UnifiedLessonShell/Today/MasteryDashboard และ existing Goal/Quest/Streak/Reward authorities; ค้น writer จริงก่อนแตะ ห้ามทำ counter ใน widget

- [ ] เพิ่ม feedback ความคืบหน้า/เป้าหมายสำเร็จและ mascot reaction จาก state จริง ใช้ asset ที่มีสิทธิ์; reduced motion และปิดเสียงยังเข้าใจ
- [ ] รวมผลรางวัลบน result แทน modal หลายชั้น; ไม่ขัดออกจากบท/ทบทวนด้วยหน้าคั่นซ้ำ
- [ ] นิยามเป้าหมาย effort แยกจาก mastery; ไม่ล็อก dashboard หรือเฉลยด้วยชวนเพื่อน/ซื้อแพ็กเกจ
- [ ] ตรวจ reward replay/idempotency และตกแต่งไม่เปลี่ยน time accounting ของการเรียน

**ปิดงานเมื่อ:** เพิ่มความชัดและแรงจูงใจโดยไม่เพิ่มจำนวนขั้นตอนจำเป็น และไม่มี authority ซ้ำ

### R15.9 — AI Tutor ที่เป็นส่วนเสริม

**Modify:** `lib/screens/ai_tutor_screen.dart`, `lib/features/ai_tutor/domain/ai_tutor_contracts.dart`, `lib/features/ai_tutor/application/ai_tutor_use_cases.dart`, gateways ทั้งสามใน `lib/features/ai_tutor/data/`

**Tests:** `test/features/ai_tutor/ai_tutor_use_cases_test.dart`, `ai_gateway_adapters_test.dart`, `ai_gateway_loopback_test.dart` ใน directory เดียวกัน

- [ ] ปัจจุบัน reply ส่ง scenario/latest message/optional progress summary แต่ไม่มี prior turns; ออกแบบ bounded conversation context ที่ owner-scoped และล้างเมื่อ new chat/owner switch
- [ ] แทน hardcoded B1–B2/สองประโยค/120 tokens ด้วย policy ตาม learner level และ intent ภายใต้ cap ชัดเจน; ไม่เพิ่ม token โดยไม่มีเพดานและไม่รับรองความถูกต้องจาก prompt
- [ ] ตรวจ plain text/Markdown/Thai/streaming หรือ partial response ตาม transport ที่รองรับจริง; ข้อความสำคัญห้ามหายแบบที่พบใน competitor และ cancellation ไม่เหลือ stale bubble
- [ ] รักษา credential handling/cancellation/accounting เดิม ใช้ local loopback synthetic provider เพื่อพัฒนาเองได้
- [ ] เริ่ม session-only context ก่อนเพิ่ม persistent chat history; ถ้าจะเก็บถาวรต้องทำ lifecycle ครบและออกแบบ retention ไม่คัดลอก 90 วันจาก competitor โดยไม่มีเหตุผล
- [ ] ใช้ quality cases เดิมสำหรับ rubric; live model evaluation ต้องมี provider/model/credential/cost ceiling ที่อนุญาต ไม่เรียก API จริงเพียงเพื่อทำให้เช็กลิสต์ครบ

**ปิดงานส่วนอัตโนมัติเมื่อ:** payload/history/owner/error/rendering ผ่าน synthetic checks; live teaching quality ยังคงเป็นรายการต่างหาก และเรียนหลักได้แม้ไม่มี key

### R15.10 — ระบบประกอบและ integration checkpoint

- [ ] Voice/Shadowing: ตรวจ permission/no speech/cancel/timeout/unavailable/restart ด้วย fixtures; recognized-text similarity ต้องไม่แสดงเป็น acoustic pronunciation score
- [ ] Sync: ใช้ existing file-backed recovery และ local policy emulator ตรวจ offline queue/lost ack/conflict/owner/delete; ไม่มีความจำเป็นเพิ่ม backend hosting สำหรับ personal dashboard
- [ ] แยก human audio/TalkBack/physical camera/two-device live sync ไว้ใน external acceptance ledger ไม่ให้รายการเหล่านี้หยุด local defect fixing
- [ ] หยุดแก้โค้ดก่อน integration tests/analysis/build; ใช้ existing verification CLI หลังตรวจ help/config และ actual source scope ไม่สร้างคำสั่ง release ขึ้นจากความจำ
- [ ] สร้าง debug preview เฉพาะที่อนุญาต พร้อม SHA/source fingerprint/model/content pins; emulator install ต้องรักษาข้อมูลเดิมและ application identity
- [ ] เปิดเส้นทางหลักใหม่จาก artifact ที่สร้างจริง ตรวจ restart/persistence แล้วบันทึก checkpoint ไม่ใช้ภาพ/ผล build เก่าแทน

**ปิดงานเมื่อ:** accepted local scope มีหลักฐานที่ source เดียวกัน พร้อมรายการข้อจำกัดที่เจาะจง; ไม่ใช้คำว่า production-ready หรือผ่านงานวิจัยจากเพียง local tests

## 5. วิธีทำงานให้ต่อเนื่องโดยผู้พัฒนาคนเดียว

ทุก package ใช้วงจร: read current diff → bounded implementation checklist → failing regression สำหรับ behavior ที่เปลี่ยน → minimal fix → focused tests → visual QA เมื่อเปลี่ยน UI → diff review → checkpoint/commit ตามสิทธิ์ที่ได้รับ ไม่มีการขอให้ผู้ใช้กดแอปหรือเลือก spacing แทนผู้พัฒนาในระหว่างงานปกติ

ตัวอย่าง focused commands ที่มี path จริง (เรียกทีละคำสั่ง ไม่รัน Flutter ซ้อน):

```powershell
git status --short
git diff --check
flutter test test/screens/main_navigation_screen_test.dart test/screens/learning_history_screen_test.dart
flutter test test/features/learning/pair_matching/pair_board_view_test.dart test/features/learning/pair_matching/pair_matching_experience_host_test.dart test/features/learning/pair_matching/pair_board_accessibility_test.dart
flutter test test/screens/object_scanner_screen_test.dart test/features/media_practice/object_scanner_use_cases_test.dart test/features/media_practice/image_preprocessor_test.dart
flutter test test/features/ai_tutor/ai_tutor_use_cases_test.dart test/features/ai_tutor/ai_gateway_adapters_test.dart test/features/ai_tutor/ai_gateway_loopback_test.dart
```

Expected หลังแต่ละ package: selected tests ผ่าน exit 0; ก่อนแก้ regression ต้อง fail ด้วยเหตุที่ต้องการแก้ ไม่ใช่ environment error รายการข้างต้นเป็นคำสั่งสำหรับการทำงานถัดไป **ยังไม่ได้รันในรอบวางแผนนี้** ขยาย test scope เมื่อมี dependency/ความเสี่ยงเพิ่ม และใช้ full integration checkpoint ตาม approved verification plan

Commit เป็นหน่วยที่ย้อนตรวจและทดสอบได้ เช่น data correctness, Pair feedback, layout, review, dashboard, scanner, camera evaluation, motivation, AI, integration แยก generated outputs ที่จำเป็นออกจาก unrelated churn ห้าม `git add .` เพื่อเก็บงานจากทุกที่โดยไม่ตรวจ

## 6. งานเพิ่ม / แก้ / ลด / เลื่อน

| ประเภท | รายการ |
| --- | --- |
| เพิ่ม | feedback state ที่ขาด, explanation/next action ที่ผูกข้อมูลเดิม, camera evaluation coverage, bounded AI context และ regression ของช่องว่างที่พบจริง |
| แก้ | layout ข้ามหน้าภายใน, content/answer consistency, dashboard semantics, scanner uncertainty, AI level/rendering, defects ที่ reproduce ได้ |
| ลด/นำออกเมื่อยืนยันว่าไม่ใช้ | หัวข้อ/กรอบ/หน้าคั่นซ้ำ, misleading copy, dead presentation code ที่ค้น references แล้ว; ไม่ลบฟีเจอร์ 8/44 หรือตารางเพื่อความสวยงาม |
| เก็บไว้ | baseline camera, local authorities, offline learning, existing permissions/owner boundaries, prototype backups |
| เลื่อน | public rankings, friends/online rooms, teacher multi-user dashboard, subscription/payment, cloud-dependent AI core, OCR/handwriting และ TCAS calculators ที่อยู่นอก catalog |

Personal dashboard ใช้ฐานข้อมูลและ chart library ที่มีอยู่ได้ จึงไม่มีข้อกำหนดต้องซื้อ server เพิ่มในแผนนี้ ต้นทุนที่ต้องแยกคือ live AI, online storage/sync, production distribution และ compute ที่อาจใช้ในการฝึกโมเดล; งาน local ไม่ได้รับรองว่า deployment ทุกแบบฟรีตลอดไป

## 7. จุดที่เดินเองได้และจุดที่แยกไว้รอภายนอก

**เดินเองได้:** source review, การจัด task, UI prototype ใน repo, local implementations/tests, synthetic fixtures, content consistency audit, public-data evaluation ที่สิทธิ์ชัดและอยู่ในขอบเขตเดิม, local model experiment, emulator QA, documentation และการแก้ recoverable errors

**ต้องมีข้อมูล/สิทธิ์เพิ่มเติมเฉพาะงานนั้น:** paid provider/model/budget, real cloud credentials/access, การเผยแพร่หรือเปลี่ยนโมเดล shipped, human pronunciation/TalkBack/physical scene acceptance และ research enrollment authority ไม่มีการจำลองผลเหล่านี้เป็นผ่าน และไม่ใช้เป็นเหตุหยุด package อื่น

**ขั้นแรกเมื่อเริ่มพัฒนา:** ทำ R15.0 แล้ว R15.1 เฉพาะข้อที่พบว่ายังขาดจริง จากนั้น R15.2 Pair feedback เป็นชุด UI แรกที่เห็นผลชัด ต่อด้วย Today/layout → เนื้อหา/review → dashboard → camera → motivation → AI → integration ตาม dependency ข้างต้น

## 8. Verification ของเอกสารรอบนี้

ตรวจ Git/worktree inventory, commit stats, แผนและ checkpoint ล่าสุดเทียบ source ของ scanner/model manifest/AI/Pair; ตรวจ path อ้างอิงและ whitespace ของไฟล์แผน ไม่มี application source edit, test execution, model training, commit, merge, push, deployment หรือการควบคุมเครื่องจริงในรอบวางแผนนี้
