# QA — เกณฑ์ตรวจรับแรงจูงใจที่รักษาวงจรการเรียน

วันที่ 8 กันยายน 2026; independent memo สำหรับผู้ตรวจ 10 บทบาท รวมข้อสรุป cross-review และการตรวจภาพเดิมจาก visual/design dossier แล้ว
ตรวจ working tree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`; ใช้ source ที่ยังไม่ commit ร่วมกับ brief/history/PM/BA/contextual checkpoint
รอบนี้วิเคราะห์และเขียนเอกสารเท่านั้น ไม่รัน tests/build ไม่แตะอุปกรณ์ ไม่เปิด rollout และไม่รับรองผลเรียนของเด็กจาก persona หรือ automated tests

## ข้อเสนอ QA

รับลำดับ PM: P1/P2/P4 เฉพาะวงจรเลือกงาน–เริ่ม/เรียนต่อ–เข้าใจผล; P5 ขนาดจำกัดทำคู่ได้เมื่อไม่แย่งการตรวจวงจรหลัก; P3 นิยาม objective ก่อน; P6 แยก capability
เงื่อนไขส่งมอบมีทั้งความถูกต้องข้อมูลและหน้าจอที่เรียบร้อย: เด็กต้องเริ่มได้ เห็นสิ่งที่กำลังทำ และเข้าใจผล โดยไม่ต้องจัดแผน ซื้อของ เปิดไมค์ หรือร่วมวิจัยก่อน
การรู้สึกสนุก ความเต็มใจกลับมา และการเรียนดีขึ้นเป็นคนละข้ออ้าง ต้องใช้วิธีตรวจตาม BA; จำนวน test ผ่านหรือ XP เพิ่มไม่พิสูจน์สามเรื่องนี้
ทุกกรณีด้านล่างเป็น acceptance ที่เสนอให้เพิ่ม/ยืนยันภายหลังใน suite เดิม ไม่อ้างว่า suite เดิมครอบคลุม UI ใหม่แล้ว

## หลักฐานเดิมและช่องว่างปัจจุบัน

- `docs/development/2026-09-08-contextual-practice-results.md`: 4,964 PASS, 0 FAIL, 0 SKIP ในผลที่รัน โดยใช้ `--exclude-tags release-excluded`; ไม่ใช่ผล QA รอบนี้
- 4 exclusions ที่พบจริง: `test/architecture/notification_platform_contract_test.dart` 1 กรณี, `test/features/device_model/litert_benchmark_test.dart` 1 และ `test/features/device_model/litert_image_classifier_test.dart` 2; ห้ามนับรวมว่า native ผ่าน
- APK เดิม SHA256 `5bfa355b3f8e2cfd843f5be76e664599d1f1117d1e54b50be1dcc23ddf16ed08` ผูก source fingerprint `eefb9a48384ad47230c66514e34ab7e0c590d8a8d219e81fe9b340de4783977e`; ใช้แทน APK หลังเปลี่ยน motivation UI ไม่ได้
- `lib/screens/today_hub_view.dart` มี resume/assigned/review แต่ `TodayHubSectionKind.planning` เป็น `break`; เติม planning ต้องไม่ดันทางเรียนต่อหรือทำ due queue หาย
- `lib/screens/learning_goals_screen.dart` ให้กรอก deadline UTC/IANA timezone; เปลี่ยน picker ต้องตรวจ conversion จริง ไม่ใช่เปลี่ยน label อย่างเดียว
- `lib/screens/avatar_equipment_screen.dart` อ่าน `equippedBySlot` แต่แสดง icon/ชื่อและแจ้งว่ายังไม่มีภาพอุปกรณ์; P5 ต้องตรวจภาพกับของจริงใน inventory
- `lib/features/quest/application/quest_use_cases.dart` ระบุ projection/reconciliation คงทำงานแม้ปิด learner-facing quest gate; rollback ห้ามตัด authority นี้
- test เดิมมีการกดจริงและ DB assertions เช่น `sentence_practice_panel_test.dart`, `pair_practice_replay_test.dart`; ต้องต่อขยาย integration ของหน้าที่เปลี่ยน ไม่แทนด้วย golden อย่างเดียว

## ความเสี่ยง → สถานการณ์ → oracle และ suite ที่ใช้

| ขอบเขต/ความเสี่ยง | สถานการณ์ตรวจรับที่ต้องเดินจริง | ผลที่ต้องยืนยันและไฟล์ทดสอบเดิม |
| --- | --- | --- |
| P1 แผนแย่งทางเรียน/เวลาเพี้ยน | มี/ไม่มี goal; ไม่มี deadline; goal หมดอายุ; กลับจาก picker; Bangkok ข้ามเที่ยงคืน; เปลี่ยน timezone; double tap save และ owner switch ระหว่างรอ | ไม่ปลอม deadline เพื่อผ่าน contract; resume/assigned ที่ได้รับสิทธิ์ไม่หาย; คำแนะนำอ้างข้อมูลเดิม; บันทึกครั้งเดียวและข้ามตั้งแผนได้; `test/features/goals/learning_goal_use_cases_test.dart`, `test/screens/learning_goals_screen_test.dart`, `test/screens/today_hub_screen_test.dart` |
| P2 progress เกินหลักฐาน | 0/ข้อมูลน้อย/ข้อมูลไม่พร้อม; ช่วงเวลาต่างกัน; recognition เทียบ typed recall; ใช้ hint/repair/replay; เปิด dashboard ใหม่หลังจบและ owner เปลี่ยน | ระบุชนิด/ช่วงเวลา/จำนวนหลักฐานที่รองรับ ไม่รวมเป็นคะแนนพร้อมสอบ; noEvidence ไม่เท่ากับผลศูนย์; ไม่กล่าวว่าดีขึ้นจาก XP หรือ speech เสริม; `test/screens/mastery_dashboard_screen_test.dart`, `test/features/progress/personal_learning_profile_test.dart`, `test/features/learning/evidence_eligibility_policy_test.dart` |
| P3 ทางเลือกกลายเป็นคะแนนสองชุด | เลือกกิจกรรมเงียบ; ปิด gate/ไม่มี pack; เปลี่ยนใจ/back; replay ภารกิจ; reward sink ล้มเหลวหลัง commit แล้ว retry; เปลี่ยนวัน/สัปดาห์ | เสนอเฉพาะงานพร้อมใช้งาน ไม่เปิด spelling→cloze อัตโนมัติ; objective ใหม่ต้อง pin catalog/eligibility; credit ตาม source identity ครั้งเดียวผ่าน Quest/Rewards เดิม; `test/features/quest/quest_use_cases_test.dart`, `test/features/quest/quest_learning_integration_test.dart`, `test/features/rewards/economy_transaction_policy_test.dart` |
| P4 การกลับมาลงโทษ/เตือนผิดคน | หยุด 7/30 วันและคิวมาก; offline; quiet hours; ปฏิเสธ notification; cancel ขณะ pending; owner เปลี่ยน; OS schedule ล้มเหลว | เริ่มรอบเล็ก/เรียนต่อได้โดยไม่ clear due หรือ mark done ปลอม; phase/streak ตรงข้อมูล; ปิดเตือนยังเรียนได้; ไม่เผยข้อมูลเจ้าของเก่า; `test/features/motivation/streak_use_cases_test.dart`, `test/features/reminders/study_reminder_use_cases_test.dart`, `test/screens/study_reminder_settings_screen_test.dart` |
| P5 ภาพบอก ownership ผิด/ซื้อซ้ำ | preview แล้ว back; equip ของไม่ owned; ซื้อสองครั้งระหว่าง pending; catalog/asset หาย; restart offline; owner switch ขณะภาพโหลด | preview ไม่หัก coin/ให้ reward; equip ตรงหนึ่ง item/slot และ fallback มีชื่อ; ไม่แสดงชุดคนก่อน; `test/features/rewards/reward_use_cases_test.dart`, `test/features/rewards/avatar_progression_policy_test.dart`, `test/screens/avatar_equipment_screen_test.dart` |
| P6 social แฝง scope/ข้อมูลเด็ก | ต้นแบบสมัครใจ/ปฏิเสธ/ออก; เพื่อนไม่มา; offline; ผู้ไม่ร่วมใช้ solo | รอบนี้ยังไม่มี acceptance coverage ของ social จริง; ต้องมี spec/owner lifecycle/การช่วยเหลือที่เหมาะกับรูปแบบจริงก่อนสร้างบัญชี/ห้อง; solo ได้สิทธิ์เรียนและรางวัลฐานเท่าเดิม ไม่เปิดด้วย flag เดิมหรือเรียก Pair Matching ว่า multiplayer |

## Invariants ที่ต้องรอดทุกระยะ

| สัญญาเดิม | Scenario และหลักฐานตรวจที่ต้องคง |
| --- | --- |
| Standard และ Adventure เป็นทางเลือก | Today → Standard/โหมดเดิม → จบ → Today; Adventure → กลับ Standard; back ทุกชั้นไม่สร้าง session ใหม่โดยไม่ตั้งใจ; `test/screens/production_shell_navigation_test.dart`, `test/scenarios/production_feature_navigation_test.dart`, `test/features/adventure/application/adventure_learning_bridge_test.dart` |
| Resume/recovery ไม่ทิ้งงานค้าง | ปิดหน้า/พักแอป/เริ่มใหม่ระหว่าง save และ pending result; checkpoint เดิมเปิดต่อด้วย identity เดิม; `test/scenarios/production_learning_restart_test.dart`, `test/scenarios/adventure_learning_restart_test.dart`, `test/features/learning/learning_recovery_foundation_test.dart` |
| Pair repair/replay/timeouts | wrong → repair ที่มีขอบเขต → resume → result; timeout แข่งกับ save; replay/back/keyboard; `test/features/learning/pair_matching/pair_repair_policy_test.dart`, `pair_timeout_race_test.dart`, `pair_matching_idempotency_test.dart`, `pair_practice_replay_test.dart` ในโฟลเดอร์เดียวกัน |
| Authority เดียวและไม่มีเครดิตซ้ำ | เปรียบเทียบ DB/projections ก่อน–หลัง retry/revisit/replay/double tap: answer/evidence, SRS, mastery, quest, streak, points/reward และ learning time ตาม eligibility เดิม; projection rebuild ต้องได้ค่าเดิม; `test/features/learning/learning_side_effect_reconciler_test.dart`, `test/features/rewards/projection_rebuild_v2_test.dart` |
| เสียงเสริม optional/ephemeral/unscored | หลังคำตอบหลัก commit เท่านั้น; ฟัง/พูด/หยุด/ลองใหม่/ข้าม/ออก/พักแอป/ปิด gate; session เดิมจบครั้งเดียว ไม่มี transcript/answer/SRS/points/reward/speech/research row เพิ่ม; `test/features/learning/sentence_practice_panel_test.dart`, `test/features/learning/cloze_mode_adapter_test.dart` |
| Owner/offline/feature gates | owner A เริ่ม async → B login/guest upgrade → A callback กลับ; sync retry/offline restart; ไม่แสดงหรือเขียนข้าม owner; `test/scenarios/guest_upgrade_restart_test.dart`, `test/scenarios/file_backed_sync_recovery_test.dart`, `test/scenarios/runtime_kill_switch_journey_test.dart` |
| Research ไม่รั่วจาก motivation | nonparticipant/default-off เดิน P1–P5 แล้วไม่มี research rows/events/outbox/uploads แต่เรียนปกติ; participant สังเคราะห์ตรวจ consent/assignment/permit signature/revision/expiry/revocation/protocol pins ที่ collect และ upload; `test/features/research/research_participation_lifecycle_test.dart`, `test/features/research/research_runtime_sync_integration_test.dart`, `test/features/sync/research_gateway_transaction_fence_test.dart` |
| Contract และวงจรข้อมูลเดิม | คง 8/44/EvidenceContext/EventEnvelopeV2; owner-scoped state ใหม่ต้อง migration/deletion/export/sync/policy หลังตรวจ ledger; `test/architecture/final_8_44_test_plan_contract_test.dart`, `test/features/learning/evidence_context_test.dart`, `test/scenarios/complete_owner_export_delete_test.dart` |

## UX/UI gate — ความเรียบร้อยที่กดใช้ได้

1. อ่าน visual/design dossier และตรวจต้นแบบทั้ง flow: Today, goal/time picker, เลือกงาน, lesson, result/progress, reminder, avatar; คงห้าปลายทางหลัก คำไทยและตำแหน่ง primary/secondary สม่ำเสมอ
2. ความคุ้นเคยจาก Duolingo/ALLTCAS ใช้เป็นเหตุผลเรื่องลำดับ/feedback/จังหวะ animation; ไม่คัดลอกแบรนด์ และต้องยืนยันกับเด็กที่เหมาะกับเนื้อหาจริงตาม BA ไม่ถือความนิยมเป็น UAT
3. ตรวจ 390×844 และ 360×800 ที่ text 100%/200%, light/dark/high contrast, reduced motion, ข้อความไทยยาว และ offline; ไม่มี overflow/การตัดความหมาย/ปุ่มซ้อน/เนื้อหาสำคัญถูก keyboard บัง
4. แตะทุก primary/secondary action และ Android back/gesture back, cancel dialog, scroll ถึงปุ่ม, keyboard Tab/Enter/Space ตาม control; ตรวจ destination/state/จำนวน command จริง ไม่จบที่ find text หรือ golden ผ่าน
5. Semantic label ไทยสื่อ action/state, focus order อ่านเหตุผลก่อนคำสั่ง, selected/disabled/pending/error ถูกประกาศ, touch target อย่างน้อย 48×48 logical pixels; สีไม่ใช่สัญญาณถูก/ผิดเพียงอย่างเดียว
6. ใช้ guideline checks `androidTapTargetGuideline`, `labeledTapTargetGuideline`, `textContrastGuideline` เมื่อ surface รองรับ พร้อม manual checks ที่ guideline ไม่ครอบคลุม; คงฐาน `test/screens/accessibility_smoke_test.dart` และ Pair accessibility suite
7. Empty/loading/pending/save failed/retry/offline/permission denied/asset missing ต้องมีทางออกที่ใช้ได้; pending กัน double tap แต่ไม่ขัง back; retry ไม่ปลอม success หรือสร้างธุรกรรมใหม่
8. Animation ต้องช่วยบอกการเลือก/การบันทึก/ผลสำเร็จ ไม่บดบังข้อความหรือทำให้รอจึงเรียนต่อได้; reduced motion มีผลเทียบเท่า; cosmetic ภาพเสียไม่กั้นการเรียน
9. หลักฐานส่งมอบเป็นภาพเทียบพร้อม state matrix และ log การเดินจริง; golden เป็นส่วนตรวจรูปลักษณ์ ไม่แทน TalkBack/keyboard/native picker หรือความเข้าใจของผู้ใช้

## คำสั่งที่ตรวจพบและลำดับ final-system gate หลัง UI เสร็จทั้งหมด

ทุกคำสั่งต่อไปนี้เป็นแผนรันภายหลังจาก root worktree ที่ระบุ ไม่ได้รันใน review นี้; serialize Flutter/test/build/codegen และไม่เปลี่ยน inputs ระหว่าง gate

| ลำดับ | คำสั่ง/งานตรวจและเกณฑ์ผ่าน |
| --- | --- |
| G0 ตรึงงาน | หยุด implementation writers ทุกคน; เก็บ HEAD/dirty diff/file hashes/lockfiles/build defines/fixture versions; diff scope และ `git diff --check`; มี relevant edit ภายหลังต้อง invalidate และรัน gate ที่ได้รับผลใหม่ |
| G1 Focused + UX | รัน `flutter test --no-pub --reporter expanded` ตาม exact suite ในตารางข้างต้น เริ่ม smallest changed journey; `flutter test --no-pub test/screens/accessibility_smoke_test.dart test/features/learning/pair_matching/pair_board_accessibility_test.dart`; ตรวจ UX gate ครบก่อนอ้างผล final-system |
| G2 Analysis | `flutter analyze --no-pub lib test integration_test test_driver assets tool tools`; format-check touched Dart ด้วย `dart format --output=none --set-exit-if-changed` และรายชื่อไฟล์จริง; ไม่ scan สำเนา build แทน source |
| G3 Full regression | `flutter test --no-pub --exclude-tags release-excluded --reporter json`; ตรวจ exit/status/error events/parse failures/doneSuccess/inventory และ 4 native exclusions แยก; จำนวนคาดหวังต้องมาจาก source ใหม่ ห้ามตั้ง 4,964 เป็นเป้าปลอม |
| G4 Host core | `flutter test -d flutter-tester --no-pub --timeout 90s --reporter expanded integration_test/field_trial_core_journey_test.dart` |
| G4 Host gates | `flutter test -d flutter-tester --no-pub --timeout 90s --reporter expanded integration_test/field_trial_feature_controls_test.dart` |
| G4 Host media | `flutter test -d flutter-tester --no-pub --timeout 90s --reporter expanded integration_test/field_trial_media_smoke_test.dart`; fake media ผ่านไม่เท่ากับ Android audio ผ่าน |
| G5 Backend/CLI | ที่ integration/release checkpoint ตาม plan และขอบเขตที่กระทบ ใช้ CPU suites ของ `tool/cli/verify.ps1` เป็นรายการตรวจ; คำสั่งตัวอย่าง `uv run --project backend/voice_api --frozen --no-sync --group dev pytest backend/voice_api/tests -q --ignore=backend/voice_api/tests/integration`; AI/LM ใช้ project/test path ของตนตาม script; ไม่เริ่ม GPU/model/server |
| G5 Policy | `npm run test:rules` และ `npm run test:auth` ใช้ demo emulator IDs จาก `package.json`; Supabase contract ใช้ `Get-Content -LiteralPath test/security/supabase_storage_contract.sql -Raw | docker exec -i supabase_db_lexiquest-local psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f -` หลังยืนยัน container local/synthetic; ไม่ชี้ production |
| G5 Coverage | mapping 8/44 และ runtime/gate ต้องตรง source ล่าสุด; backend/policy ที่ไม่รันใหม่ต้องระบุเหตุผลและหลักฐาน source-equivalence ตาม plan ไม่ยกผลเก่าว่าเป็นการรันใหม่; ห้ามเรียก Codex Security workflow |
| G6 APK | `flutter build apk --debug --no-pub`; เก็บ source before/after, version/build ID, defines, SHA256/bytes และ warnings; debug APK ผ่านยังไม่ใช่ release-signing หรือ device acceptance |
| G7 Native/device | เมื่ออุปกรณ์และการอนุญาตที่จำเป็นพร้อม ยืนยัน serial/package/signing/data ก่อนติดตั้งแบบรักษาข้อมูล; native exclusions 4 กรณีต้องมีผลจาก runtime ที่รองรับหรือระบุเหตุขาด; ตรวจ notification/timezone/permission, mic/TTS lifecycle, native picker และ offline/restart จริง |
| G8 TalkBack/UAT | เดินทุกหน้าที่เปลี่ยนกับ TalkBack จริงและผู้ใช้ตัวแทนตาม BA: เริ่ม/กลับมา/ทำผิด/ข้ามเสียง/อ่านผล/ปิดเตือน/ออก Standard; บันทึกสิ่งที่สังเกตกับความเห็นแยก ไม่สอนเพื่อให้ดูผ่าน; ทดสอบเด็กต้องใช้กระบวนการอนุญาตที่เหมาะกับกิจกรรม |
| G9 ใช้งาน 3 ชั่วโมง | แยกจาก smoke/UAT และนับเวลาจริง: lifecycle/พักแอป/เน็ตหาย/เสียง/เรียน–กลับ–เรียน, battery/thermal/memory/frame/log ตาม device plan; `integration_test/adventure_performance_profile_test.dart` และ `tool/cli/run-adventure-performance-profile.ps1` เป็นจุดต่อ profile จริง ไม่แทนสามชั่วโมงด้วย host debug |

G7–G9 ที่ยังไม่มีเครื่อง/ผู้ใช้ให้ระบุ pending เฉพาะส่วนนั้น; engineering completion ไม่ใช่การอนุมัติ enroll/upload และห้ามใช้ผล APK เก่ามาปิดช่องว่าง UI ใหม่
หาก UX gate พบว่าต้องปรับหน้าเพิ่มเติม ให้แก้แล้วตรึงใหม่ก่อน final-system tests; ผู้ใช้กำหนดให้ทดสอบระบบหลังแก้ UI ทั้งหมด ไม่ใช้การรันระหว่างที่ยังมี writer แทน

## เงื่อนไขหยุดเฉพาะส่วนและ rollback

- หยุดส่งมอบส่วนที่ทำให้ owner isolation/เครดิต/consent/permit ผิด หรือทำให้ Standard/resume ใช้ไม่ได้; เก็บ synthetic reproduction และแก้รากเหตุ ไม่ลบ test/ลด assertion/เพิ่ม exclusions ให้เขียว
- rollback เอาชั้นแนะนำ/ภาพ/entry ของชิ้นใหม่ออกผ่านขอบเขตที่ออกแบบ โดยรักษา evidence, SRS, reward ledger, inventory, pending recovery และ quest reconciliation; ปิด UI gate ไม่ใช่คำสั่งลบข้อมูลหรือย้อน schema
- state ใหม่ถ้ามีต้อง migration แบบไปข้างหน้าที่มีการทดสอบ และเส้นทาง export/delete; ไม่ downgrade DB, uninstall, clear app data หรือ reset worktree เพื่อแก้ failure โดยไม่ได้รับอนุญาต
- บันทึก checkpoint ของ gate ที่ขาด: source identity, files, exact command/result, native exclusions, process ที่ยังรัน, APK identity และ next executable step; ไม่มีข้อสรุป production/UAT/efficacy เกินหลักฐาน

## Cross-review และข้อสรุปหลังโต้แย้ง

อ่าน `03-cross-review-brief.md`, `02-design-evidence.md`, `U1-beginner.md`, `U4-access.md`, `SA-architecture.md` และ `DEV-integration.md`; ข้อสรุปต่อไปนี้แทนคำถามค้างของ initial memo
เปิดดูจริงด้วย `view_image` สามภาพเดิม: `build/verification/ui-implementation-20260908/visual/390x844-01-learning.png`, `390x844-06b-shop.png`, `360x800-text200-01-learning.png` ในโฟลเดอร์เดียวกัน; ไม่ได้เปิดภาพ cloze ในรอบนี้
Learn 390 มีปุ่มเริ่มสีน้ำเงินและห้าแท็บไทยชัด; shop 390 มีกล่องเงาหลายชุด ไอคอน/ชื่อ และคำว่า Material 3 แต่ไม่มี preview ตัวละคร; Learn 360/text200 ใช้พื้นที่แนวตั้งมากและชื่อบางแท็บขึ้นสองบรรทัด
ภาพเหล่านี้เป็น renderer fixtures ของรุ่นก่อนหน้า เห็นรูปลักษณ์ได้ แต่ไม่ยืนยันว่าทุก production gate เปิดอยู่ กดทุกปุ่มได้ หรือ UI ใหม่ผ่านบนโทรศัพท์
**ข้อเห็นต่างกับ U1/C1:** ความต้องการ “แผนเพื่อเป้าหมาย” มีคุณค่า แต่ QA รับข้อแก้ของ SA/DEV ว่า title/deadline ยังไม่ผูกเนื้อหา; ระยะแรกตรวจรับ goal/deadline และรายการฝึกเดิม โดยไม่ใช้คำว่า adaptive/แผนเฉพาะบุคคลหรือ % พร้อมสอบ
**ข้อเห็นต่างกับ U4/C4:** การทำให้เรียบหรือผ่านข้อจำกัดเครื่องอย่างเดียวไม่ปิดงาน polish; QA ยอมเพิ่มการเทียบทั้ง flow กับต้นแบบก่อน final-system และรับ P5 ภาพ local เล็กในร้านตาม DEV โดยไม่รอ weekly plan/ผลสอบ
ยอมปรับความหมาย “ปุ่มหลักหาได้ทันที” ให้คงลำดับ/น้ำหนักชัดและเข้าถึงด้วย scroll/focus ที่ 200%; ไม่บังคับทุกเนื้อหาพอดีจอ ไม่ย่อฟอนต์หรือซ่อนชื่อแท็บเพื่อให้ภาพผ่าน
**รับ U1/U4 ด้านการใช้งาน:** prototype ต้องมี ready/empty/pending/error/retry/disabled; การตรวจต้องแตะ next action/back/cancel และอ่านผลจริง ไม่ตัดสินจาก token/golden หรือ screenshot การ์ดเดี่ยว
เลือกแนว “เป็นมิตร มีโครงสร้างชัด” ใน dossier: คงห้าแท็บและ canonical next action ใช้ลำดับตัวอักษร/พื้นที่ว่าง/คำไทยสม่ำเสมอ ไม่เพิ่ม curriculum path หรือปลดล็อกที่ไม่มี authority รองรับ
รับ motion สั้น 150–200ms เป็นค่าทดลองตาม DEV/U4 เมื่อช่วยอธิบาย selected/committed/equipped; reduced motion ให้ final state ทันที ไม่มี idle loop/auto sound/รอภาพจึงกดต่อ และไม่มี transaction จาก animation
**C5/score truth ตาม SA/DEV:** ระยะแรกแสดงข้อเท็จจริงที่ field รองรับ เช่น ตอบถูก n จาก m ในชุดที่ระบุ; “ดีขึ้น/จำได้ระยะยาว/พร้อมสอบ” ต้องมี content/revision, evidence/assistance class, ช่วงเวลาและจำนวนตัวอย่างที่เทียบได้
recognition ที่ช่วยจำเมนูใน UX ไม่อนุญาตเพิ่มตัวเลือก/เฉลยใน independent recall แล้วคง evidence class เดิม; noEvidence/unavailable ไม่ใช่ความสามารถศูนย์ และ XP/อวาตาร์/เสียงเสริมไม่ชดเชยหลักฐาน
**P5 oracle ที่ยืนยันกับ DEV:** mapping ใช้ `(catalogVersion, itemId)` ของ owned/equipped เดิม; preview/back/restart ไม่หัก coin/สร้าง reward; unknown asset มีชื่อสำรอง และ owner A→B→callback A ต้องไม่คืนภาพหรือ preview ของ A
งบ P5 ต้องตรวจ bytes/decode memory/frame timing บน profile เครื่องเป้าหมายตาม U4; ความเล็กของไฟล์หรือ host debug ผ่านยังไม่ยืนยันประสิทธิภาพ และห้ามรอ asset/network ก่อนเข้าเรียน
**C6/C8 ตาม SA:** opening/layout/preview ไม่สร้าง session หรือ consent; ตรวจ opening snapshot/exposure/assigned presentation เดิมด้วย รวม owner switch ระหว่างโหลด และ cancel/reconcile notification ผ่าน authority เดิม ไม่ซ่อนเพียงการ์ด
Research คง default-off; nonparticipant ไม่มี research rows/events/outbox/uploads จาก UI ใหม่ แต่เรียนเดิมได้; participant สังเคราะห์ต้องผ่าน consent/assignment/permit/pins ที่ collect/upload ไม่ใช้ความพอใจต่อดีไซน์เป็นเหตุเปิดเก็บข้อมูล
อายุหลักยังไม่ยืนยันและยังไม่มี interviews/UAT: จำกัดการอ้างความเหมาะสมกับวัย/efficacy และการรับผู้ใช้จริง ไม่เป็นเหตุห้ามต้นแบบ local/synthetic หรือการแก้ UI ในขอบเขตที่ผู้ใช้อนุมัติภายหลัง
**ขอบเขตแรกที่รับ:** P1 goal/time UI, P2 ผลจริงพร้อมบริบท, P4 gentle return/เตือนครั้งเดียว และ P5 local preview หนึ่งพื้นที่; P3 ทางเลือกฝึกผ่าน gate เดิม ส่วน weekly persistence/recurrence/Quest objective ใหม่/P6 แยก contract และ lifecycle decision
**C10 final AFTER-UI:** focused ระหว่างพัฒนาใช้วินิจฉัยได้; หลังรวม UI ทุกส่วนและตรวจภาพ/flow แล้ว freeze writers+fingerprint → focused/accessibility → analysis 7 roots/full regression → host 3 ชุด/backend-policy/8–44 ตาม plan → APK/hash จาก source เดียวกัน; relevant edit ยกเลิกหลักฐานที่ได้รับผล
Native/device → TalkBack/UAT → สามชั่วโมงเป็นคนละ gate; 4,964 PASS, 4 native exclusions, APK และภาพเดิมใช้ได้ตามรุ่นเดิมเท่านั้น ไม่ปิด acceptance รุ่นใหม่หรืออนุมัติ enrollment/upload
**Rollback ที่รับจาก SA/DEV:** ถอดเฉพาะ incremental presentation/assets หรือปิด entry ใน binary ที่ยังรองรับ schema v24+; ไม่ใช้ binary เก่าเปิด DB ใหม่ ไม่ล้างข้อมูล/ยึดของ/ให้รางวัลย้อนหลัง และไม่ตัด Quest reconciliation; recurrence ถ้ามีต้อง cancel/reconcile ก่อนปิด
ข้อสรุปหลังโต้แย้ง: functional correctness, visual polish และการใช้งานจริงต้องผ่านเกณฑ์ของตนก่อนรวมคำรับรอง; รอบนี้ตรวจเอกสารกับภาพเดิมเท่านั้น ไม่มี app/test/build/device/UAT ใหม่ และไม่เพิ่ม approval gate นอกขอบเขตที่จำเป็นจริง
