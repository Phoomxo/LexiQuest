# DEV — จุดเชื่อมและการส่งมอบ P1–P6

วันที่ 8 กันยายน 2026; วิเคราะห์เท่านั้น ไม่มี app/test/config edits, tests/builds หรือการเปลี่ยน rollout
Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`, HEAD `788e90e62b1694c20945734787723c168b6a6ab2` พร้อม dirty UI/contextual เดิม
อ่าน brief/history, BA, PM, SA และ source ล่าสุด; เป้าคือช่วยเด็กไทยเริ่มฝึก เข้าใจผล และกลับมาได้ ไม่เพิ่มยอดใช้งานหรือรายได้เป็นเกณฑ์แทนผลการเรียน

## คำตัดสินด้านการพัฒนา

ทำระยะ A เป็นการเติมข้อมูลและทางเลือกจาก authority เดิมก่อน; P5 ชิ้นเล็กทำขนานได้หากจำกัดหน้าร้านและมีเจ้าของงานแยก
การ์ด goal/deadline ไม่ใช่ adaptive weekly plan: `LearningGoal` ไม่มี content/competency binding หรือ workload; ห้ามแปลง title เป็นหลักสูตรเอง [C1]
`LearnerPreferences.availableMinutesPerDay` มีแล้ว (1–240 นาที, default 20) เป็นความชอบที่แก้ได้ ไม่ใช่เวลาจบงานที่ระบบประเมินหรือเวลาที่เด็กยืนยันว่าเหมาะสม [C2]
ไม่ต้องเพิ่ม schema/dependency/remote service เพื่อแสดง snapshot, ใช้ local picker หรือวาดอุปกรณ์จากของเดิม; UI ที่เรียก write ยังต้องใช้ guard/idempotency เดิม

## Existing interfaces ที่ต้องใช้และขอบเขตของแต่ละข้อ

| P | จุดเชื่อมที่มีจริง | ระยะ A และสิ่งที่ต้องเลื่อน |
| --- | --- | --- |
| P1 | `TodayHubUseCases.load` → `DriftTodayHubReader.compose` → `TodayHubSnapshot.goals/reminders`; renderer `TodayHubView` ยัง `planning: break` [C3] | แสดงชื่อ/วันครบกำหนด/การเตือนที่มี; ไม่แสดง % ครบเป้า/แผนสัปดาห์/คำว่าเหมาะกับสอบนั้น; linkage และ durable week plan เป็นงาน domain ภายหลัง |
| P2 | `ProgressUseCases.loadPersonalLearningProfile`, `PersonalLearningProfile`, `MasteryDashboardScreen.loader`; reader รวม mastery/SRS/calendar/quest/streak/reward [C4] | อธิบายค่าปัจจุบันพร้อม sample size/noEvidence และทาง review/weakness เดิม; trend ที่ต้องเทียบช่วงไม่ใช่เพียงตกแต่งข้อความ |
| P3 | `QuestCatalogProvider.allQuests/seedOnStartup`, `QuestUseCases.loadStatusForCurrentOwner/projectEvent`, `QuestStatusScreen` [C5] | ชี้ทางกิจกรรมเดิมที่มีสิทธิ์ได้; การเลือกรับ/สลับ quest จริงยังไม่มี lifecycle นี้; objective/title/reward ใหม่ต้อง catalog version และ pin/eligibility tests |
| P4 | `GentleStreakSnapshot` จาก `StreakPolicy.snapshot`; `StudyReminderUseCases.optIn/cancel/reconcile/timezoneContext` [C6] | แสดง recovery/longest และ review summary จาก snapshot; เตือนครั้งเดียวผ่าน scheduler เดิม; weekday recurrence/exception/reschedule ทั้งชุดเป็น persistent policy ใหม่ |
| P5 | `RewardUseCases.loadAvatar/purchase/equip`, `AvatarRewardState.account`, `RewardAccount.ownedItemIds/equippedBySlot`, `RewardCatalog` v2 [C7] | renderer อ่าน item ID + catalog version; preview ชั่วคราวแยกจาก equipped จริง; ไม่เพิ่มราคา/เลเวล/สินค้าหรือแก้ frozen catalog เพื่อทำภาพ |
| P6 | Adventure/8–44 เดิมไม่ใช่ friend graph หรือ shared room; ไม่มี social authority ที่นำการ์ดเดิมมาเปิดใช้แทนได้ [H1,SA] | ทดลอง scenario/prototype สังเคราะห์ก่อนได้; peer identity/invite/accept/block/visibility และ shared state ต้อง capability/version/service decision ใหม่ หากเลือก online |

`TodayHubActionDelegate` ปัจจุบันมี `resume/startRecommendation/openReview/openHistory/startAssessment` เท่านั้น; ไม่มี `openGoals/openReminders` [C3]
ขั้นต่ำของ A คือ renderer อ่านข้อมูลและใช้เส้นทางจัดการเดิม; ถ้าจะให้กดการ์ดไปแก้ goal/reminder ให้ integrator ออกแบบ delegate addition และแก้ implementers/tests ในงานเดียว ไม่เรียก method ที่ยังไม่มี
`TodayHubSnapshot` ยังไม่มี learner preference; ถ้าจะแสดงเวลาที่มี ให้ compose จาก `LearnerPreferencesRepository.read(ownerId)` หรือ use case เดิมพร้อมตรวจ owner ตรงกันก่อนเผยผล ห้าม query DB จาก build
การแนะนำกิจกรรมยังใช้ recommendation/entry guards เดิม; ตรวจ owner, gate, content freshness อีกครั้งตอนกด ไม่เริ่ม session เพียงเพราะอ่านหน้า Today หรือเปิด goal

## ระยะ A: แบ่ง write set โดยผู้รับผิดชอบคนเดียวต่อไฟล์

รายการนี้เป็นขอบเขตงานอนาคต ยังไม่ได้อนุมัติหรือเริ่มแก้ไฟล์ และไม่สร้างไฟล์สมมติล่วงหน้า

| เจ้าของชิ้นงาน | Existing write set ขั้นต่ำ | เงื่อนไขส่งคืน |
| --- | --- | --- |
| A1 Today/return | `lib/screens/today_hub_view.dart`, `test/screens/today_hub_screen_test.dart` | เติม planning ที่ gate อนุญาต, recovery และ review preview; resume/assigned/review order เดิม, ดูทั้งหมดเข้าคิวเดิม ไม่เปลี่ยน due dates หรือ mark done |
| A2 เวลา | `lib/screens/learning_goals_screen.dart`, `lib/screens/study_reminder_settings_screen.dart` และ screen tests ชื่อเดียวกันใต้ `test/screens/` | picker/ข้อความท้องถิ่นผ่าน create/optIn เดิม; payload เวลา/เขตเวลาถูกต้อง, cancel และ retry truthfulness คงเดิม |
| A3 ผลจริง | `lib/screens/mastery_dashboard_screen.dart`, `test/screens/mastery_dashboard_screen_test.dart` | สรุปเฉพาะ profile ที่ส่งมา; ไม่เพิ่ม score/store; noEvidence/unavailable ไม่กลายเป็นศูนย์ความสามารถ |
| A4 ภาพร้าน | `lib/screens/avatar_equipment_screen.dart`, `test/screens/avatar_equipment_screen_test.dart` | ภาพ static local ของ base + อุปกรณ์เดิมจำนวนน้อยที่ตกลง; fallback และ ownership ถูกต้อง; ไม่แตะ shared lesson/Today widgets |
| Integrator | `lib/screens/today_hub_screen.dart`, `lib/screens/main_navigation_screen.dart`, `lib/features/adventure/presentation/today_experience_host.dart` เฉพาะเมื่อเพิ่ม wiring จริง | ตรวจ implementations ของ delegate ทุกตัวด้วย `rg`; A1 หยุดเขียนก่อนรวม; การเพิ่ม field/loader ขยาย write set อย่างชัดเจนและตรวจ owner |

`lib/navigation/navigation_glossary.dart`, `lib/config/m3_theme.dart`, `lib/runtime/app_dependencies.dart` และ `test/screens/accessibility_smoke_test.dart` เป็น shared ownership ของ integrator; ไม่ให้หลาย agent แก้พร้อมกัน
ถ้าต้องสร้าง asset manifest/renderer/helper ใหม่ ให้ค้น equivalent ภายใน `lib/` และ `assets/` ก่อนเลือกชื่อจริง; `pubspec.yaml` จัดให้ integrator คนเดียวเมื่อจำเป็น ไม่เพิ่ม package เพียงเพื่อรูป static
P5 ระยะถัดไปจึง reuse renderer ใน `lib/features/adventure/presentation/widgets/adventure_companion_panel.dart` และ `lib/features/companion/presentation/contextual_companion_widget.dart`; เจ้าของสอง widget ต้องรับต่อหลังร้านผ่านและตรวจ lesson lifecycle ใหม่

## วันเวลา: ลดภาระเด็กโดยรักษา instant เดิม

ใช้ Flutter date/time picker และ `package:timezone` ที่มีอยู่ แสดงวันเวลาใน IANA timezone ที่เลือก/ยืนยันแล้ว; ไม่ใช้ `DateTime.toLocal()` แทน timezone การเรียนหรือใช้ +7 ตลอดทุกเขตเวลา
สร้าง wall-clock ด้วย `TZDateTime(location, year, month, day, hour, minute)` แล้ว `.toUtc()`; คำนวณ offset ณ instant นั้นด้วย `LearningGoalUseCases.timezoneContext` หรือ `StudyReminderUseCases.timezoneContext` [C1,C6]
ตรวจ round-trip ว่าปี/เดือน/วัน/ชั่วโมง/นาทีตรงกับที่เลือก; DST gap ต้องให้เลือกใหม่ และ DST fold ต้องแสดง offset/ทางเลือกชัดก่อนยืนยัน ไม่ปล่อย library normalize แล้วบันทึกเงียบ
display-only ต้องไม่บันทึก goal/reminder ใหม่; แก้ฟอร์มโดยไม่แก้เวลาห้ามเปลี่ยน UTC instant; ห้ามตั้งเวลาเที่ยงคืน/สิ้นวันแทน deadline แบบเงียบ ๆ หากผู้ใช้ยังไม่เลือกเวลา
ใช้ `LearningGoalUseCases.prepareCreate/executeCreate` และ `_pendingCommand` เดิมเมื่อ acknowledgement ไม่แน่นอน; ห้ามสร้าง ID ใหม่จากการ retry และคง mutation guard เมื่อ gate/owner เปลี่ยน
quiet hours แสดงเป็นช่วงนาฬิกาแล้วแปลงเป็นนาทีภายใน; `effectiveScheduledAtUtc`, rebase และ platform reconciliation เป็นอำนาจของ reminder เดิม; goal deadline ห้ามเลื่อนตาม timezone ของเครื่องโดยอัตโนมัติ

## ผลจริงและภาพเคลื่อนไหวที่ตรวจรับได้

P2 ระยะแรกแสดง “ตอบถูก n จาก m ในหลักฐานชุดนี้” หรือ due count ตาม field จริง; one correct ไม่แปลว่า mastered/จำได้ระยะยาว/พร้อมสอบ และกิจกรรมแบบเลือกกับ recall ห้ามเทียบตรง ๆ
profile ปัจจุบันไม่ให้ matched before/after series; ถ้าต้องการ trend ให้ขยาย read model/policy พร้อม owner, content identity/revision, activity/evidence/hint/assistance, ช่วงเวลาที่เทียบได้ และ sample size ก่อน แม้ไม่เพิ่ม schema ก็ต้องตรวจนิยาม/version
ห้ามอนุมาน learning gain จาก XP, avatar, streak, เวลาที่อยู่ในแอป หรือการลองพูดเสริม; supplementary speech ยังคง ephemeral/unscored และข้ามได้ ไม่เข้ารางวัล/Quest/research [H2]
reuse `M3Theme`/NotoSansThai/ColorScheme/ปุ่มขั้นต่ำ 48×48 และ `M3Theme.motionDuration/applyReducedMotionPreference`; ค่า theme อย่างเดียวไม่ยืนยันความสวยหรือความเข้าใจ [C8]
เกณฑ์ภาพที่เสนอ: ปุ่มเริ่ม/เรียนต่อหลักมองหาได้ทันที, การ์ดสรุปหนึ่งหัวข้อก่อนรายละเอียด, spacing/แนวข้อความสม่ำเสมอ, อ่านไทยครบ, สถานะ wrong/pending/success ไม่ใช้สีอย่างเดียว; เรียนรู้ hierarchy ของ Duolingo/ALLTCAS โดยไม่คัดลอก assets
motion ต้องอธิบายผลจาก state จริง เช่น selected→saved หรือเปลี่ยนอุปกรณ์ครั้งเดียว; ไม่วน/ไม่ auto-scroll/ไม่บดบัง CTA/ไม่รอ animation เพื่อไปต่อ; reduced motion แสดง final state ทันทีและไม่เปลี่ยน semantics
P5 เริ่ม bundled static assets จำนวนน้อยที่สิทธิ์ใช้ชัด วัดขนาดเพิ่มและ decode memory; ไม่ให้ download/cache/network availability เป็น prerequisite; unknown ID/version/asset หายยังอ่านชื่อและเรียนได้
preview ต้องระบุว่าเป็นการลองดูโดยไม่ซื้อ และแสดง equipped จริงเมื่อยกเลิก; owner switch ทิ้ง preview เก่า; ไม่แสดงผลธีมทั้งแอปสำหรับ item ที่ renderer ยังไม่รองรับ

## RED/GREEN ที่มีความหมาย — เสนอคำสั่ง ยังไม่รันในรอบนี้

เริ่ม RED เฉพาะความต้องการที่ยังขาดด้วย synthetic owner/snapshot จริงของโดเมน; เก็บ failure ก่อนแก้แล้ว GREEN ชุดเดิม ไม่เขียน test ที่ตรวจเพียงชื่อ widget ตาม implementation
ใช้ `flutter test --no-pub --reporter expanded <path...>` ใน worktree นี้ และรัน Flutter/test/build/codegen แบบเรียงลำดับใน source snapshot คงที่

| ชิ้น | RED/negative case → GREEN acceptance | Existing test paths ที่ใช้เริ่ม |
| --- | --- | --- |
| A1 | ready planning ไม่แสดง → แสดงเมื่อ gate อนุญาต; 100 review items ไม่ฝัง CTA; owner เปลี่ยน/hidden gate ไม่เผยรายการเก่า; resume และ full review delegate ได้ input เดิม | `test/screens/today_hub_screen_test.dart`, `test/features/today_hub/today_hub_reader_test.dart`, `test/features/adventure/presentation/today_experience_host_test.dart` |
| A2 | ฟอร์มต้องพิมพ์ UTC → เลือก local แล้วได้ exact UTC/offset; near-midnight/DST/invalid time/cancel/denied/retry/owner switch ไม่สร้างรายการซ้ำ | `test/screens/learning_goals_screen_test.dart`, `test/features/goals/learning_goal_use_cases_test.dart`, `test/screens/study_reminder_settings_screen_test.dart`, `test/features/reminders/study_reminder_use_cases_test.dart` |
| A3 | noEvidence/หนึ่งคำตอบ/ข้อมูลต่างกิจกรรมถูกสื่อว่าเก่งขึ้น → ข้อความมีขอบเขตและฐานจำนวนจริง; review/weakness ยังเปิดได้ | `test/screens/mastery_dashboard_screen_test.dart`, `test/features/progress/personal_learning_profile_test.dart` |
| A4 | สวม item เดิมแล้วไม่มีภาพ → ภาพตรง owned/equipped/version, preview/cancel ไม่มี transaction delta, missing asset/offline/owner switch fallback ได้ | `test/screens/avatar_equipment_screen_test.dart`, `test/features/rewards/reward_use_cases_test.dart` |

ชุดกัน regression เมื่อรวม: `test/features/quest/quest_learning_integration_test.dart`, `test/features/quest/quest_use_cases_test.dart`, `test/features/learning/pair_matching/pair_practice_replay_test.dart`, `test/features/history/learning_history_replay_test.dart` และ `test/features/learning/sentence_practice_panel_test.dart`
ตรวจ canonical attempts/events/SRS/Quest/XP/Coins delta หลัง retry/revisit/replay และ optional voice ไม่สร้างเครดิตเพิ่ม; เปรียบเทียบ current owner ไม่ยอมให้ยอดรวมข้ามเจ้าของกลบข้อผิดพลาด
ตรวจภาพจริงใน light/dark, 390×844 และ 360×800/text 200%, จอแคบ 240×640, labels ยาว, keyboard/TalkBack/reduced motion; ใช้ `test/screens/accessibility_smoke_test.dart` และ `test/config/m3_theme_test.dart` ร่วมกับการอ่าน rendered images ไม่ถือ golden ผ่าน=สวย
integration checkpoint หยุด writers ก่อน analyze/full regression `flutter test --no-pub --exclude-tags release-excluded --reporter json` และ APK ตามแผนเดิม; 4 native/platform exclusions ต้องเปิดเผย และ physical-device/UAT รุ่นล่าสุดยังเป็นงานที่ขาด [H2]

## Schema, merge และ rollback

ฐานจริง `AppDatabase.currentSchemaVersion = 24`; ledger v24 ยังเขียน RESERVED แต่บันทึกสี่ตารางวิจัย/48 tables และห้าม binary ก่อนหน้าเปิด v24 จึงไม่ใช้เลขนี้ซ้ำ [C9]
durable goal-content binding/weekly choices/recurrence ต้อง migration กับ owner upgrade/deletion/export/sync-policy/offline conflict; P3 objective ที่แสดงจาก event เดิมอาจไม่เพิ่มตาราง แต่ต้อง catalog/version/domain/receipt pin; social online ต้อง service/auth/visibility/abuse lifecycle แยก ไม่จอง migration รอบนี้
dirty งานเดิมครอบคลุม Today/goals/reminders/mastery/avatar/navigation/quest และ generated registrants; เก็บไว้ครบ ห้าม reset/ล้าง churn หรือใช้ HEAD-only diff แล้วอ้างว่าเป็นงานใหม่ทั้งหมด
ก่อน implementation เก็บ tracked+untracked hashes และ incremental diff เทียบ baseline; รวมทีละชิ้นแบบ three-way บน working tree ปัจจุบัน ตรวจ source fingerprint ก่อน/หลังแต่ละ gate และผูก APK hash ไม่ยืมผล 4,964 tests ของซอร์สเดิม
rollback A คือ revert เฉพาะ incremental UI/assets หรือปิด capability ผ่านกลไกเดิมใน binary ที่ยัง compatible v24; ห้ามเปิดฐาน v24+ ด้วย binary เก่าที่ไม่รองรับ ห้ามลบฐาน ลบประวัติ ยึดของ หรือ reward backfill เพื่อย้อนหน้าจอ
หลัง schema ใหม่ใช้ forward-compatible/repair release และหยุด writer ใหม่; ถ้าเพิ่ม recurrence ต้อง cancel/reconcile OS entries ก่อนปิด entrypoint ไม่ทิ้ง notification หลังถอนสิทธิ์/ลบ owner
Research คง default-off/consent/permit/assignment/pins; review UI exposure แยกจากสิทธิ์ collect/upload; nonparticipant ต้องไม่เพิ่ม research rows/events/outbox/uploads และการเรียนเดิมยังเดินต่อ

## หลักฐานและสถานะแลกข้อโต้แย้ง

C1: `lib/features/goals/domain/learning_goal.dart:33`, `lib/features/goals/application/learning_goal_use_cases.dart:54`, `:119`; C2: `lib/features/preferences/domain/learner_preferences.dart:152`, `lib/features/preferences/application/learner_preferences_use_cases.dart:19`
C3: `lib/features/today_hub/data/drift_today_hub_reader.dart:32`, `:86`, `lib/features/today_hub/domain/today_hub_models.dart:109`, `lib/screens/today_hub_view.dart:13`, `:204`; C4: `lib/features/progress/application/progress_use_cases.dart:40`, `lib/features/progress/domain/personal_learning_profile.dart:13`
C5: `lib/features/quest/application/quest_catalog_provider.dart:10`, `lib/features/quest/application/quest_use_cases.dart:146`, `:367`; C6: `lib/features/motivation/domain/streak_policy.dart:110`, `lib/features/reminders/domain/study_reminder.dart:66`, `lib/features/reminders/application/study_reminder_use_cases.dart:152`
C7: `lib/features/rewards/domain/reward_models.dart:32`, `lib/features/rewards/application/reward_use_cases.dart:43`, `lib/screens/avatar_equipment_screen.dart:225`; C8: `lib/config/m3_theme.dart:16`; C9: `lib/data/local/app_database.dart:82`, `docs/database/schema_ledger.md:454`
H1: `01-history-baseline.md`, `SA-architecture.md`, `PM-delivery.md`, `BA-user-problems.md`; H2: `docs/development/2026-09-08-contextual-practice-results.md:13`, `:26`, `:55` — เป็นหลักฐานเดิม ไม่ได้รันใหม่ใน DEV
คงข้อเสนอ BA/PM เรื่องเริ่มวงจร P1/P2/P4 และ P5 เสริมแบบแยกงาน; รับ SA ว่า goal linkage/weekly state ไม่ derive จาก title และต้องรักษา frozen contracts; ข้อสรุปหลังแลกข้อโต้แย้งอยู่ด้านล่าง

## Cross-review และข้อสรุปหลังโต้แย้ง

อ่าน `03-cross-review-brief.md`, `02-design-evidence.md` และ SA/U4/QA แล้ว; ยืนยันแนว “เป็นมิตร มีโครงสร้างชัด” เพื่อแก้ปัญหาเด็กไทย โดยยังไม่สมมติอายุหลักหรือกล่าวว่าภาพเดิมเป็น UAT
**ข้อเห็นต่างกับ U4/P5:** “โหลดภาพภายหลัง” อาจถูกตีความเป็น download dependency; ปรับให้หมายถึง decode local asset เฉพาะที่แสดง เริ่ม base + preview `headgear_ipa` หนึ่งชนิดได้ ไม่ preload ทั้งร้าน และไม่โหลดเครือข่ายก่อนเรียน
รับข้อ U4 ว่าความเล็กของไฟล์ไม่พอรับรองเครื่องเบา: acceptance ต้องบันทึก bytes เพิ่ม, decoded memory และ frame timing ใน profile บนอุปกรณ์เป้าหมาย เทียบ source/build เดียวกันเปิด–ปิดภาพ; รอบนี้ยังไม่มีผลวัดหรืองบตัวเลขที่ยืนยัน
**ข้อเห็นต่างกับ SA/การปรับร้าน:** ยอมให้คำอธิบายเป็นภาษาเด็กเข้าใจ แต่ไม่แก้ frozen RewardCatalog snapshot เพื่อ localization; mapping presentation ต้องใช้ `(catalogVersion, itemId)` และรักษา ID/ราคา/level/owned/equipped เดิม
catalog v2 มี `theme_default`, `theme_ocean`, `wallpaper_focus`, `headgear_ipa`, `weapon_cefr`, `armor_srs`; แสดงชื่อไทยพร้อมคำอธิบายผลที่เห็นจริงสำหรับ IPA/CEFR/SRS และเอาศัพท์ framework เช่น Material 3 ออกจากคำอธิบายหน้าร้านผ่าน presentation เท่านั้น
รับข้อ QA ว่า preview กับ purchase ต้องมี oracle แยก: “ลองดู” เปลี่ยนเฉพาะภาพชั่วคราวและกลับ equipped จริงได้; แตะซ้ำ/back/restart ไม่มี coin/transaction delta และไม่ประกาศว่า theme ทั้งแอปเปลี่ยนจากภาพอวาตาร์
**ข้อเห็นต่างกับ SA/ทางเข้าแผน:** อ่านข้อมูลอย่างเดียวไม่พอให้เด็กไปจัดการได้สะดวก จึงยอมขยาย route/delegate แบบ bounded เมื่อ prototype ต้องการ แต่เป็น integration scope ใหม่ ไม่ใช่ planner authority และไม่ใช้ goal title เป็น content linkage
Integrator คนเดียวรับ `today_hub_view.dart` ส่วน delegate signature ร่วมกับ `today_hub_screen.dart`, `main_navigation_screen.dart`, `today_experience_host.dart` และ test implementers ที่ค้นพบจริง; A1 ส่ง renderer patch แล้วหยุดเขียนก่อนรวม ไม่มี writer ซ้อนแม้แก้คนละบรรทัด
A2 คุมสองฟอร์มเวลาและ screen tests; A3 คุม mastery screen/test; A4 คุม avatar screen/test; integrator คุม glossary/theme/app_dependencies/accessibility suite และ `pubspec.yaml` หาก asset registration จำเป็น; ชื่อ renderer/asset ใหม่เลือกหลังค้น equivalent ไม่ให้หลายคนสร้างสำเนา
**ปรับตาม QA/C10:** M3 tokens หรือ golden ผ่านไม่ใช่หลักฐาน polish; ก่อน implementation ให้มีต้นแบบ Learn/Today → lesson/result และ goal/reminder/shop ที่ใช้ข้อความ/สถานะจริง แล้วตรวจ primary action, type/spacing/icon และภาพ fallback ทั้ง flow
รับรูปแบบคุ้นเคยจาก Duolingo/ALLTCAS ใน hierarchy/feedback และ motion เล็ก; ไม่คัดลอก path หลักสูตรหรือ unlock ที่ไม่มี authority, ไม่บังคับ avatar/เสียง และยังมีห้าแท็บกับ Standard escape เดิม
เกณฑ์ชี้ขาดร่วม U4/QA คือ 390×844/text100 กับ 360×800/text200 พร้อมจอแคบ/keyboard/dark/high contrast: label ไม่หาย, resume เข้าถึงได้ด้วย scroll/focus, semantics ไม่ซ้ำ และ reduced motion มีผลลัพธ์ครบโดยไม่หน่วง CTA
owner A โหลดภาพ/บันทึกเตือน → เปลี่ยน B → callback A กลับ ต้องทิ้งภาพ/preview/pending ของ A; การซ่อน UI อย่างเดียวไม่พอสำหรับเตือน ต้อง cancel/reconcile ผ่าน owner/reminder authority และไม่ล้าง session/history ของเจ้าของเดิม
ระหว่างพัฒนาใช้ focused RED/GREEN รายชิ้น; เมื่อ UI ทุกชิ้นรวมและตรวจภาพ/flow เสร็จแล้วหยุด writers เก็บ fingerprint จาก dirty+untracked และรัน focused/accessibility บน final source อีกครั้ง ก่อน final-system gates
ลำดับสุดท้ายตาม QA: format/diff → `flutter analyze --no-pub lib test integration_test test_driver assets tool tools` → full regression → host core/feature-controls/media ทั้งสามคำสั่งที่ QA ระบุ → backend/policy/8–44 ตามขอบเขตแผน → APK/hash; serial ทั้งหมดและ relevant edit ทำให้หลักฐานที่กระทบใช้ต่อไม่ได้
จากนั้น native/device → TalkBack/UAT → การใช้งานสามชั่วโมงตามแผนแยกกัน; เปิดเผย 4 exclusions และส่วนที่ยังไม่ได้ทำ ไม่ใช้ debug host/ภาพ fixture/4,964 tests เดิมแทนการตรวจรุ่นใหม่ และไม่เปิด research collection เพราะต้องการวัดดีไซน์
ข้อสรุป DEV: รับ A1–A3 และ P5 local slice ตามเงื่อนไขนี้, เลื่อน durable weekly/recurrence/objective/social จนมี domain/lifecycle decision; rollback ถอด incremental presentation ใน binary ที่รองรับ v24+ โดยไม่ตัด Quest reconciliation ไม่ลบข้อมูลหรือให้รางวัลย้อนหลัง; รอบนี้แก้เฉพาะ memo ไม่มี tests/build หรือวิจัยใหม่
