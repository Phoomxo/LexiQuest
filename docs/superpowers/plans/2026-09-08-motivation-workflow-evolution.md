# Motivation Workflow Evolution — Decision and Phased Delivery Plan

> สำหรับผู้ดำเนินงานภายหลัง: ใช้ `subagent-driven-development` หรือ `executing-plans` เมื่อได้รับคำขอพัฒนาต่อ โดยคงหนึ่ง writer ต่อไฟล์และ serialize Flutter/test/build/codegen ตาม guardrails
> สถานะปรับปรุง 2026-09-08: **D0 และ A0–A4/C1 พัฒนาและตรวจภายในแล้ว; กำลังแก้ปัญหาที่พบจากการทดสอบต่อเนื่อง** ดูหลักฐานใน [implementation ledger](../../development/2026-09-08-motivation-ui-implementation.md) และ [ผลการแก้ไขรอบปัจจุบัน](../../development/2026-09-08-autonomous-remediation-results.md) รายการ checkbox ด้านล่างเป็นรายการตรวจรับต้นฉบับ ไม่ใช่สถานะงานล่าสุด; B/C ยังเป็นข้อเสนออนาคต และผลทดสอบภายในไม่เท่ากับ UAT หรืออนุมัติเปิดใช้งานจริง

**Goal:** ช่วยเด็กไทยเริ่ม/กลับมาเรียน เลือกงานอย่างมีเหตุผล และเข้าใจผลจริง ผ่าน UX/UI ที่เรียบร้อยคุ้นเคย โดยแยกแรงจูงใจ ผลเรียน การกลับมาใช้ และรางวัล
**Architecture:** เติม presentation/composition จาก Today, Goals, Progress, Reminder, Quest และ Rewards authority เดิมก่อน ไม่เพิ่ม planner/reward/evidence authority ใน Phase A; domain ใหม่แยก decisions/contracts ใน B/C
**Tech Stack:** Flutter/Dart, Material 3/NotoSansThai, Drift/SQLite schema v24, `package:timezone`, use cases/feature gates เดิม และ Flutter unit/widget/host integration tests; ไม่เพิ่ม dependency เพื่อจัดหน้า/ภาพเล็ก

## Global Constraints

- Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch `codex/pair-matching-pm0-pm8`; baseline HEAD `788e90e62b1694c20945734787723c168b6a6ab2` รวม tracked/untracked UI/contextual เดิม ไม่ reset หรือถือ HEAD เป็นงานทั้งหมด
- เอกสารอ้างอิงตัดสินใจ: [S11 synthesis](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/docs/development/2026-09-08-motivation-workflow-review/S11-synthesis.md), [DEV](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/docs/development/2026-09-08-motivation-workflow-review/DEV-integration.md), [QA](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/docs/development/2026-09-08-motivation-workflow-review/QA-acceptance.md)
- รักษา Standard, ห้าแท็บ, ทางโหมดเดิม, resume/repair/replay/pinned session, SRS/mastery/Quest/streak/XP/Coins authority เดิม; ไม่มี session เริ่มเพราะ load/preview/animation
- คง 8 domains/44 capabilities และ frozen EvidenceContext/EventEnvelopeV2; schemaจริง v24/48tables, Quest catalog v1, Reward catalog v2 เป็นคนละเลข; ledger RESERVED เก่าไม่ใช่ runtime blocker/เลขว่าง
- Phase A ไม่เพิ่ม schema, persistent week plan, recurrence, goal-content binding, score/trend policy, Quest objective/economy หรือ social; การอ่านข้อมูลยังต้องตรวจ semantic risk
- ไม่ใช้ goal title เดาเนื้อหา/หลักสูตร/ความพร้อมสอบ; quickstart ตาม availability ไม่ใช่ personalized plan และ Learn ไม่รอ Today เมื่อ hidden/unavailable
- optional supplemental speech หลังคำตอบหลักเป็น ephemeral unscored; ไม่เพิ่ม answer/SRS/mastery/Quest/reward/research และไม่เปลี่ยน independentRecall เป็น recognition เพื่อให้ใช้ง่าย
- Research default-off; nonparticipant ไม่มี research rows/events/outbox/uploads; collection/upload ที่มีสิทธิ์ต้องตรวจ owner/consent/assignment/permit authenticity+revision+expiry+revocation/protocol/instrument pins เดิม
- ไม่มี commit/deploy/publish/enrollment/real upload/destructive cleanup จากการทำแผนนี้; ไม่เรียก Codex Security workflow
- อายุหลักยังไม่ยืนยัน: ทดสอบสมมติฐาน ป.4–ป.6/มัธยมแยกกัน; การขาด interviews/UAT จำกัดคำอ้างและ rollout ไม่ห้าม local/synthetic design หรือ bounded implementation ที่อนุมัติแล้ว
- ทุก slice ต้องผ่าน D0 ก่อนเขียน implementation และผ่านภาพ/flow/data oracleหลังทำ; final whole-system เกิดหลัง UI ทั้งชุดเสร็จและหยุด writers เท่านั้น

## Task D0 — ออกแบบและตรึงเกณฑ์ของแต่ละ slice ก่อนลง code

- [ ] อ่าน current plan/checkpoint/code และเก็บ HEAD/dirty+untracked hashes/lockfiles/flags โดยไม่ทับ baseline เดิม; ยืนยันไม่มี writer อื่นครองไฟล์ที่จะใช้
- [ ] ทำ flow/prototype local ด้วยข้อมูลสังเคราะห์สำหรับ Learn/Today → goal/reminder → lesson/result/progress → shop; ครบ ready/empty/loading/pending/error/retry/disabled/owner transition ของ slice นั้น
- [ ] กำหนด anatomy ตาม S11: หนึ่ง action เด่น, secondary สม่ำเสมอ, review summary+ดูทั้งหมด, goal กางได้, เลือก→ตรวจ→commit→feedback, preview แยกซื้อ/สวม; ไม่มี curriculum path ที่ข้อมูลไม่รองรับ
- [ ] ใช้ M3Theme/NotoSansThai, spacing4/8/12/16/24/32, radius16, targets48×48; body16/title20–24 และ motion150–200msเป็นค่าต้นแบบ ไม่ใช่ผลพิสูจน์; เคารพ scaling/high contrast/reduced motion
- [ ] เปรียบเทียบ390×844/text100 กับ360×800/text200 และ240×640/keyboard; ทุก action/backเข้าถึงด้วย scroll/focus ไม่มีตัด label/ย่อฟอนต์/สีเป็นสัญญาณเดียว
- [ ] Review ภาพ+ข้อความ+interactionภายในต่อ slice ก่อน code: route ใช้ข้อมูลอะไร สิทธิ์ใดผลัก action และข้อความทุกคำอ้างย้อนถึง field ใด; บันทึก defect แล้วปรับจนผ่าน D0
- [ ] สำหรับ P5 ให้ D0 ระบุภาพ base+`headgear_ipa` หนึ่งชนิด, สิทธิ์ใช้ภาพ, bytes/ขนาด decode ที่ต้องวัด และชื่อไฟล์/rendererจริงหลังค้น equivalent ใน `lib/`/`assets/`; จึงกำหนด write set เพิ่มก่อนเริ่ม A4
- [ ] เก็บภาพต้นแบบ/state matrix/คำตัดสินไว้ใน verification directory ของงานพัฒนาจริงและผูก hashes; รอบทบทวนนี้ยังไม่มี artifacts เหล่านี้ ห้ามอ้าง D0 ผ่านจากภาพเดิม

## Task A0 — Integrator: โครงหน้าและทางกดที่ไม่เปลี่ยน authority

**Modify โดย integrator คนเดียว:** `lib/screens/main_navigation_screen.dart`, `lib/screens/choose_mode_screen.dart`, `lib/screens/today_hub_screen.dart`, `lib/features/adventure/presentation/today_experience_host.dart`, `lib/features/adventure/presentation/adventure_pair_experience.dart`
**Shared ownership:** `lib/screens/today_hub_view.dart` เฉพาะหลัง A1ส่งคืน; `lib/navigation/navigation_glossary.dart`, `lib/config/m3_theme.dart`, `lib/runtime/app_dependencies.dart`, `pubspec.yaml` เฉพาะสิ่งที่ D0พิสูจน์ว่าจำเป็น ไม่มี refactor/เปิดflagนอกขอบเขต
**Test:** `test/screens/main_navigation_screen_test.dart`, `test/screens/choose_mode_screen_test.dart`, `test/screens/production_shell_navigation_test.dart`, `test/scenarios/production_feature_navigation_test.dart`, `test/features/adventure/presentation/today_experience_host_test.dart`
**Interface เดิม:** `Future<TodayHubSnapshot> TodayHubSnapshotLoader.load()` และ delegate `resume(LearningSessionSummary)`, `startRecommendation(TodayHubRecommendation)`, `openReview(List<TodayHubReviewWorkItem>)`, `openHistory()`, `startAssessment(TodayHubAssignedAssessment)` คืน `Future<void>`
**Route decision ที่เสนอใหม่ ไม่ใช่ API ปัจจุบัน:** เพิ่มเพียง `Future<void> openPlanning({required String ownerId})` สำหรับปุ่ม “จัดการเป้าหมายและการเตือน”; เข้า hub เดิม→`study-planning/goals`→`goals/study-reminder-settings` ตาม source ของ goal ไม่เพิ่ม scheduler route แยก

- [ ] หลัง D0 เขียน focused RED ที่แสดงว่าการ์ด planning กดจัดการไม่ได้และทางรองดัน quickstart; เพิ่ม hidden/unavailable/owner-changed cases ที่คงการเริ่มโหมดเดิม
- [ ] ใช้ `rg -n 'implements TodayHubActionDelegate|TodayHubActionDelegate' lib test` ตรวจทุก implementer ก่อนเปลี่ยน signature; เพิ่ม callback แบบผูก owner ตรวจ owner/gate/dependency อีกครั้งตอนกด แล้วเรียก `_openPlanning` เดิม
- [ ] ปรับ `_MainNavigationTodayHubActions` และ `_ContextualPairActions` พร้อม test doubles ใน `test/screens/today_hub_screen_test.dart`, `test/features/adventure/presentation/today_experience_host_test.dart`, `test/features/adventure/presentation/adventure_pair_experience_test.dart`, `test/features/learning/pair_matching/pair_measurement_boundary_test.dart` ใน integration เดียว
- [ ] จัด Learn ให้ action ตามข้อมูลที่พร้อมเด่น มีทางฝึกเองและ Standard; รักษา pending terminal recovery ก่อนเริ่มใหม่ ไม่บังคับ Today/preferences load และไม่เรียก starter quiz ว่าเฉพาะบุคคล
- [ ] รัน `flutter test --no-pub --reporter expanded test/screens/main_navigation_screen_test.dart test/screens/choose_mode_screen_test.dart test/screens/production_shell_navigation_test.dart test/scenarios/production_feature_navigation_test.dart test/features/adventure/presentation/today_experience_host_test.dart test/features/adventure/presentation/adventure_pair_experience_test.dart test/features/learning/pair_matching/pair_measurement_boundary_test.dart` แบบ serialหลังไม่มีwriterแก้inputs
- [ ] ตรวจผ่านเมื่อแต่ละปุ่มไป destinationถูก, callbackเก่าไม่เปิดให้ ownerใหม่, gateปิดยังเรียนเดิมได้ และ opening/snapshot/exposure/assigned presentation ไม่ถูกสร้างใหม่จากการจัดหน้า

## Task A1 — Today: คืนข้อมูล planning และทางกลับมาที่กดถึง

**Modify:** `lib/screens/today_hub_view.dart`; **Test:** `test/screens/today_hub_screen_test.dart`; A1เป็น sole writer จนส่งคืนให้ integrator
**Consumes:** `TodayHubSnapshot.sectionOrder/resumableSession/assignedAssessment/reviewWork/recommendation/goals/reminders/gentleStreak/dependencyStates`; `GentleStreakSnapshot.phase/currentStreakDays/longestStreakDays` ไม่มี preferences field
**Produces:** rendererจากsnapshotเดิม; expanded/collapsed stateอยู่ชั่วคราวในหน้า ไม่สร้าง Today store/เคลียร์คิวหรือเขียนstreak

- [ ] หลัง D0 เพิ่ม RED: มี goal/reminderแต่planningไม่แสดง, recovery14วันสื่อphaseไม่ครบ, resume+assigned+120dueกดงานหลักยาก; ใช้ snapshotจริงและ synthetic owner
- [ ] แสดง goals/reminders เมื่อgate+dependencyอนุญาต ชื่อ “เป้าหมายของฉัน” แยก “รายการวันนี้”; previewเริ่ม3รายการเป็นค่าตรวจ UX ปรับได้ในD0 พร้อมจำนวนทั้งหมดและ actionเปิดรายการใกล้summary
- [ ] รักษา canonical sectionOrder และงานที่มีสิทธิ์; recoveryใช้phaseเดิมและlongestตามจริง ไม่เปลี่ยน currentก่อนeligiblecommit ไม่ลบdue/เพิ่มหนี้/เลื่อนdeadlineเอง
- [ ] ส่ง `snapshot.reviewWork` **ทั้งชุด** ให้ `openReview` แม้แสดงpreview3รายการ; `_open` ใน `AdventurePairTodayActions` ใช้ `listEquals(work, action.today.reviewWork)` จึงห้ามส่งsubsetจนตกfallback
- [ ] ใช้ `flutter test --no-pub --reporter expanded test/screens/today_hub_screen_test.dart test/features/today_hub/today_hub_reader_test.dart test/features/adventure/presentation/adventure_pair_experience_test.dart test/features/adventure/presentation/today_experience_host_test.dart` หลัง A0หยุดเขียนไฟล์ร่วม
- [ ] GREEN/data oracle: exact work IDs/order/due dates/Pair destinationเท่าเดิม, เข้าถึงcanonicalactionในไม่เกิน2การกดหลังเข้าToday, ดูครบได้, hidden/empty/unavailableไม่แสดงข้อมูลปลอม, เปิด/ยุบไม่สร้างevidence/reward; ส่งdiffให้integratorแล้วหยุดเขียน

## Task A2 — วันเวลาท้องถิ่นและ reminder ครั้งเดียว

**Modify:** `lib/screens/learning_goals_screen.dart`, `lib/screens/study_reminder_settings_screen.dart`; **Test:** `test/screens/learning_goals_screen_test.dart`, `test/screens/study_reminder_settings_screen_test.dart`; writerเดียวครองทั้งสองฟอร์ม
**Consumes/produces:** `LearningGoalUseCases.prepareCreate({kind,title,deadlineAtUtc,timezone})`→`LearningGoalCreateCommand`; `executeCreate(command,{mutationAllowed})`→`Future<LearningGoal>`; ใช้ `_pendingCommand` เดิมเมื่อretry
**Reminder interface:** `StudyReminderUseCases.optIn({source,scheduledAtUtc,timezoneId,quietHours,mutationAllowed})`→`Future<StudyReminderOptInResult>`; `cancel(String reminderId, {required StudyReminderMutationGuard mutationAllowed})` และ `reconcile/timezoneContext` ใช้ signature เดิม ไม่เพิ่ม weekday rule ใน title/sourceKind

- [ ] หลัง D0 เพิ่ม RED ที่เลือกวัน/เวลาlocalแล้วตรวจexact UTC/offset ไม่ต้องพิมพ์Z/IANA; ครอบคลุม Bangkokข้ามเที่ยงคืน, cancel, no-goal, denied, pendingRetry, ownerเปลี่ยน และ quiet hours
- [ ] ใช้ picker+`timezone.TZDateTime` ในIANA timezoneที่แสดง/ยืนยัน แล้วแปลง UTC และใช้ `timezoneContext` ณinstantนั้น; display/reopenโดยไม่แก้ต้องคงinstantเดิม ไม่แทนเวลาที่ไม่เลือกด้วยเที่ยงคืน
- [ ] ตรวจ round-trip ปี/เดือน/วัน/ชั่วโมง/นาที; DST gapให้เลือกใหม่และfoldให้เลือกoffsetอย่างชัดก่อนsave; ไม่มีfixed+7สำหรับทุกtimezoneหรือ `toLocal()` แทนstudytimezone
- [ ] quiet hoursแสดงนาฬิกาและส่งนาทีภายในตามcontractเดิม; แสดง effective schedule/resultตามusecase; ปฏิเสธ/ปิดเตือนยังเรียนได้ ไม่scheduleเมื่อเพียงเปิดหน้า
- [ ] คง stable source/idempotencyเดิมเมื่อacknowledgementไม่แน่นอน; owner A→B→callback A ต้องinvalidatependingและ cancel/reconcile OS entriesผ่านauthorityเดิม ไม่เพียงซ่อนการ์ด
- [ ] รัน `flutter test --no-pub --reporter expanded test/screens/learning_goals_screen_test.dart test/features/goals/learning_goal_use_cases_test.dart test/screens/study_reminder_settings_screen_test.dart test/features/reminders/study_reminder_use_cases_test.dart`; GREENคือinstant/quiet-hoursถูก, ไม่สร้างgoal/reminderซ้ำและnotificationไม่ข้ามowner

## Task A3 — คำอธิบายผลที่ไม่เกินข้อมูลและตรวจ lesson/result เดิม

**Modify:** `lib/screens/mastery_dashboard_screen.dart`; **Test:** `test/screens/mastery_dashboard_screen_test.dart`; A3ไม่แก้Today/lesson/Questพร้อมintegrator
**Consumes:** `MasteryProfileLoader = Future<PersonalLearningProfile> Function()` ผ่าน `MasteryDashboardScreen.loader`/`ProgressUseCases.loadPersonalLearningProfile()`; accuracyมี `sampleSize/correctCount/value`, ช่วงสัปดาห์อ่าน `profile.calendar.weekStart/timezoneId`
**Produces:** คำอธิบายprofileเดิมพร้อมavailabilityและทาง review/weakness/calendar; ไม่ผลิต matched before/after series หรือรับรอง recallจากaccuracyรวม

- [ ] หลัง D0 เพิ่ม RED: noEvidence/หนึ่งคำตอบ/unavailable/owner-change/กิจกรรมต่างกันถูกสื่อว่าเก่งขึ้น; ตรวจข้อความมีจำนวนและสัปดาห์ตรงcalendarโดยไม่ใช้ XP/streak/เวลาเป็นผลเรียน
- [ ] แสดงข้อเท็จจริงหนึ่งเรื่องก่อนรายละเอียด เช่นจำนวนคำตอบถูกในสัปดาห์ที่ระบุ; mixed evidenceต้องติดขอบเขตและไม่ใช้คำว่า “จำได้เอง/พร้อมสอบ/ดีขึ้น” เมื่อread modelไม่มีฐานเปรียบเทียบ
- [ ] ใช้ `flutter test --no-pub --reporter expanded test/screens/mastery_dashboard_screen_test.dart test/features/progress/personal_learning_profile_test.dart test/features/learning/evidence_eligibility_policy_test.dart`; GREENคือค่ากับavailabilityตรงauthorityและcallbacksเดิมยังทำงาน
- [ ] Integrator ตรวจ D0/D2 ทั้ง flow ของ `lib/features/learning/presentation/unified_lesson_shell.dart`, `lib/screens/fill_in_the_blanks_screen.dart`, `lib/screens/word_scramble_screen.dart`, `lib/features/adventure/presentation/adventure_result_screen.dart`; ถ้าต้อง polish ให้ลง incremental diff เฉพาะจุดและรับ write ownership ก่อนแก้
- [ ] ตรวจ `test/features/learning/unified_lesson_controller_test.dart`, `test/screens/fill_in_the_blanks_screen_test.dart`, `test/screens/word_scramble_screen_test.dart`, `test/features/adventure/presentation/adventure_result_screen_test.dart`, `test/features/learning/sentence_practice_panel_test.dart` ตามvisualdiff; noauto-next/noextra-speechcredit/เลือกก่อนตรวจคงเดิม
**Integrator — companion localization:** Modify `lib/features/companion/presentation/contextual_companion_widget.dart`; Test `test/features/companion/contextual_companion_widget_test.dart` และ `test/features/learning/unified_lesson_controller_test.dart` เฉพาะ expectation ภาษาเมื่อจำเป็น; อ่าน `lib/features/companion/domain/companion_reaction_catalog.dart`/`companion_reaction.dart` และ Adventure panel เดิมเพื่อรักษา interface ไม่แก้ catalog/reaction policy
- [ ] D0 ตรวจข้อความสาม signal ในภาษา UI ที่ใช้จริงพร้อมนโยบาย fallback สอดคล้อง Adventure; UI ไทยต้องไม่เหลือ semantic prefix อังกฤษ ตัวอย่างเริ่ม “ค่อย ๆ เรียนไปทีละขั้น”, หลัง commit ผิด “บันทึกคำตอบแล้ว พร้อมเมื่อไรลองอีกครั้งได้”, จบ “จบการฝึกรอบนี้แล้ว” เป็น copy ที่ต้องตรวจต้นแบบ ไม่อ้างว่าเด็กเข้าใจแล้ว
- [ ] เพิ่ม RED/GREEN ของข้อความไทย/อังกฤษและ semantic live-region พร้อม null/unknown ตาม contract, language change และ reduced motion; mapping อยู่ presentation ตาม catalog version/signal คง event identity/committedResponseCount และ reaction timing เดิม ใช้ branch/helper ลด motion เดิม ไม่ขวาง input/เพิ่มเสียง/เขียน evidence หรือ reward
- [ ] รัน `flutter test --no-pub --reporter expanded test/features/companion/contextual_companion_widget_test.dart test/features/companion/companion_reaction_catalog_test.dart test/features/learning/unified_lesson_controller_test.dart test/features/adventure/presentation/adventure_companion_panel_test.dart`; ผ่านเมื่อภาษา/semantics ตรง UI และ failed commit/lost-ack retry/replay/dispose ยังไม่สร้าง reaction หรือเครดิตซ้ำ ไม่ใช้การแปลเปลี่ยนกติกาเรียน

## Task A4 — P5 ภาพนิ่งของที่รองรับหนึ่งพื้นที่ในร้าน

**Modify:** `lib/screens/avatar_equipment_screen.dart`; **Test:** `test/screens/avatar_equipment_screen_test.dart`; renderer/asset write setใช้รายชื่อที่D0ตรึงหลังค้นจริง integratorคนเดียวรับregistrationเมื่อจำเป็น
**Consumes:** `RewardUseCases.loadAvatar()`→`Future<AvatarRewardState>`, `account.ownedItemIds/equippedBySlot`, `(catalogVersion,itemId)` จากRewardCatalogv2; previewชั่วคราวแยกequippedจริง
**Mutationเดิมเท่านั้น:** `purchase({itemId,catalogVersion,idempotencyKey})` และ `equip(itemId,{idempotencyKey})`; เปิด/ลองดู/animationห้ามเรียกสองmethodsนี้เอง

- [ ] หลังD0เพิ่มREDของbase+`headgear_ipa`, owned/unowned/equipped/preview/cancel/unknownversion/missingasset/ownerchange; ตรวจภาพพร้อมcoin/transactiondelta ไม่ตรวจเพียงชื่อwidget
- [ ] สร้างภาพlocalเฉพาะของที่รองรับและfallbackชื่อ; ไม่preloadทั้งร้าน/โหลดnetworkก่อนเรียน; คำอธิบายไทยเป็นpresentation mapping ไม่แก้ frozen item IDs/ราคา/level/catalog snapshots
- [ ] แยก “ลองดู/ซื้อ/ใช้งาน” และบอกขอบเขตภาพจริง ไม่ประกาศว่าธีมทั้งแอปเปลี่ยน; back/cancel/restartกลับequippedจากauthorityและไม่ให้เครดิตเพิ่ม
- [ ] รัน `flutter test --no-pub --reporter expanded test/screens/avatar_equipment_screen_test.dart test/features/rewards/reward_use_cases_test.dart test/features/rewards/avatar_progression_policy_test.dart test/features/rewards/economy_transaction_policy_test.dart`; GREENไม่มีธุรกรรมจากpreviewและภาพไม่ข้ามowner
- [ ] D2ตรวจstatic/reducedmotion/offline/fallback; เก็บbytes/decode memory/frameprofileบนเครื่องเป้าหมายภายหลังโดยเทียบเปิด–ปิดภาพในbuildเดียวกันก่อนอ้างperformance; หากภาพติดให้เลื่อนเฉพาะA4ไม่ขวางA1–A3

## Task D1/D2 — รับฟังและตรวจคุณภาพที่มองเห็นได้

- [ ] BAจัดรอบรับฟังเมื่อมีผู้ยินยอม/assentตามกิจกรรม: เด็ก8–12 ครู3–4 ผู้ดูแล3–4เป็นข้อเสนอเชิงคุณภาพ แยกวัย/ระดับ/เครื่อง/ผู้ไม่ชอบเกม; ไม่อ้างเป็นpopulation sample
- [ ] ถามประสบการณ์ติดขัดล่าสุดก่อนโชว์feature แล้วให้เริ่ม/เปลี่ยนคำตอบ/อ่านผล/กลับมา/ปิดเตือน/แยกpreview–ซื้อโดยไม่ชี้ปุ่ม; เก็บการช่วยเหลือ ความลังเล คำพูดจริงและการตีความแยกกัน
- [ ] เปรียบเทียบbaselineกับprototypeด้วยลำดับที่สลับกันและบันทึกกรณีค้าน; ตัวเลข2การกด/preview3รายการเป็นdesign acceptance candidate ไม่ใช่ผลเรียนหรือความเหมาะสมกับทุกวัย
- [ ] หลังแต่ละUIเสร็จ ตรวจภาพstateเดียวกับprototypeและกดทุกaction/back/cancel/keyboard; text200/light/dark/highcontrast/TalkBack/reducedmotion/offlineต้องครบ ไม่ใช้goldenหรือtheme tokenปิดD2
- [ ] ตรวจข้อมูลสังเคราะห์ก่อน–หลัง opening/preview/retry/replay/ownerchange: session/content pins, attempts/events/SRS/mastery/Quest/streak/XP/Coinsไม่เพิ่มผิดeligibility; optionalvoiceและnonparticipantไม่มีresearchdelta

## Task B/C — Decision packages ที่แยกจาก Phase A

- [ ] B1พิจารณาgoal-content+weeklyplanเฉพาะเมื่อปัญหาจริงต้องใช้: ระบุbindingที่ผู้เรียนยืนยัน, contentID/revision/coverage, budgetเป็นประมาณ, planrevision/edit/skip/replan/conflict/freshness และresume/reviewpriority; ไม่inferจากtitleหรือซ่อนJSONในpreferences
- [ ] B2พิจารณาrecurrenceแยกdeadline: ระบุtimezone/DST/weekday/exceptions/cancelall/occurrenceidentity/ownerchange/offline/OSreconcile; แยกฉบับversionก่อนเขียนscheduler ไม่สัญญาว่าA2ส่งตารางวนซ้ำแล้ว
- [ ] B3ก่อนQuestใหม่ ระบุเหตุผลผู้ใช้และcatalogversion/instancepins/assignmenttime/objectiveeligibility/opt-in/swap/expiry/receipt/rebuild; ไม่retrofitinstanceเก่า ไม่ใช้optionalvoice/replayเป็นเครดิตใหม่
- [ ] ทุก B ที่เพิ่ม owner state ต้องตรวจ schema/ledger ตอนเริ่มจริง แล้วกำหนด migration/guest upgrade/deletion/export/sync conflict/policy/tombstone และ rollback แบบไปข้างหน้า; ไม่จอง migration ในแผนนี้ ไม่แก้ frozen envelope
- [ ] Cเริ่มscenarioสังเคราะห์ของเพื่อนสมัครใจ/ไม่มา/ปฏิเสธ/ออก/solo; รับฟังคุณค่าการช่วยกันก่อนเลือกว่าonlineจำเป็นหรือไม่ ผลตัดสินอาจไม่ทำโดยไม่มีผลเสียต่อสิทธิ์เรียน
- [ ] ก่อนConlineต้องมีcapability/version/no-social/8–44extensiondecisionและidentity/invite/accept/block/visibility/leave/retention/owner/offline/abuse-support/cost; ไม่เพิ่มcontacts/chat/ranking/shared-streakเป็นdefault
- [ ] แต่ละ decision ที่เลือกทำต้องออก spec, versioned contracts และ implementation plan เฉพาะ พร้อม D0/negative acceptance ก่อน code; นี่คือขอบเขตการตัดสินที่ตรวจรับได้ ไม่ใช่การอ้างว่ามี API หรือโค้ดของ capability ที่ยังไม่กำหนด

## Task F — Final whole-system หลัง UI ทั้งหมดเสร็จเท่านั้น

คำสั่งต่อไปนี้ **NOT RUN ในรอบreviewนี้**; ทุกแถวรันจากworktreeข้างต้นแบบserialและเก็บcommand/exit/log/sourcefingerprintก่อน–หลัง ห้ามถือ4,964เป็นยอดเป้าของsourceใหม่

| ลำดับ | งาน/คำสั่งและผลที่ต้องได้ภายหลัง |
| --- | --- |
| F0 | หยุดwritersทั้งหมดหลังแก้D2; เก็บHEAD/dirty+untrackedhashes/flags/fixtures/lockfiles; `git diff --check`; format-checkเฉพาะDartที่เปลี่ยนด้วย `dart format --output=none --set-exit-if-changed` ตามmanifestไฟล์จริง ไม่มีautoformatงานเดิมนอกscope |
| F1 | รันfocusedA0–A4อีกครั้งบนfinalsource; `flutter test --no-pub test/screens/accessibility_smoke_test.dart test/features/learning/pair_matching/pair_board_accessibility_test.dart test/config/m3_theme_test.dart`; ตรวจภาพ/flowครบก่อนรับรองfinalระบบ |
| F2 | `flutter analyze --no-pub lib test integration_test test_driver assets tool tools`; ผลต้องไม่มีanalysiserrorบน7รากsourceจริง ไม่วิเคราะห์สำเนาbuildแทน |
| F3 | `flutter test --no-pub --exclude-tags release-excluded --reporter json`; ตรวจexit/error-events/parse-failures/doneSuccess/inventoryและfail/skipตามจริง |
| F4a | `flutter test -d flutter-tester --no-pub --timeout 90s --reporter expanded integration_test/field_trial_core_journey_test.dart` |
| F4b | `flutter test -d flutter-tester --no-pub --timeout 90s --reporter expanded integration_test/field_trial_feature_controls_test.dart` |
| F4c | `flutter test -d flutter-tester --no-pub --timeout 90s --reporter expanded integration_test/field_trial_media_smoke_test.dart`; fake mediaไม่ใช่Androidaudio |
| F5a | `uv run --project backend/voice_api --frozen --no-sync --group dev pytest backend/voice_api/tests -q --ignore=backend/voice_api/tests/integration` |
| F5b | `uv run --project backend/ai_api --frozen --no-sync --group dev pytest backend/ai_api/tests -q` |
| F5c | `uv run --project backend/lexiquest_lm --frozen --no-sync --group dev pytest backend/lexiquest_lm/tests -q`; CPU/pinnedenvironments ไม่มีGPU/model/serverใหม่; CLI inventoryอ้าง `tool/cli/verify.ps1` ไม่เรียกทั้งscriptโดยไม่ตรวจsideeffects |
| F6a | `npm run test:rules` แล้ว `npm run test:auth`; package.jsonระบุdemoemulatorIDsเท่านั้น |
| F6b | หลังยืนยันcontainerlocal/synthetic: `Get-Content -LiteralPath test/security/supabase_storage_contract.sql -Raw | docker exec -i supabase_db_lexiquest-local psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f -` |
| F7 | `dart run tool/feature_contract/generate_feature_map.dart --check`; กำหนด `$motivationVerifiedHead = git rev-parse HEAD` แล้ว `dart run tool/final_test_plan/generate_final_test_plan.dart --check --source-commit $motivationVerifiedHead`; ตรวจ8/44/runtimegateตรงsource |
| F8 | `flutter build apk --debug --no-pub`; `Get-FileHash -LiteralPath build/app/outputs/flutter-apk/app-debug.apk -Algorithm SHA256`; บันทึกbytes/buildID/defines/warnings/fingerprintคงที่ |

- [ ] F0–F8 ต้องมีหลักฐานจริงก่อนทำเครื่องหมายผ่าน; artifacts ที่ต้องอัปเดตใช้ generator เดิมโดย integrator ก่อนตรึง source ใหม่ ไม่แก้ generated ด้วยมือ; relevant edit ทำให้ gate ที่กระทบต้องรันใหม่
- [ ] Backend/CLI/policy ที่ยังรันไม่ได้ให้ระบุ command/dependency/source equivalence และ pending เฉพาะส่วน ห้ามเอาผลเก่ามาอ้างว่าเพิ่งรัน; ใช้ bounded local recovery ตาม AGENTS ไม่ reset/delete เพื่อให้เขียว
- [ ] เปิดเผย4native/platformexclusionsเดิม: `test/architecture/notification_platform_contract_test.dart`1, `test/features/device_model/litert_benchmark_test.dart`1, `test/features/device_model/litert_image_classifier_test.dart`2; ไม่รวมว่าnativeผ่าน
- [ ] F9เมื่อเครื่องพร้อม ตรวจserial/package/signing/dataก่อนติดตั้งแบบรักษาข้อมูล; notification/timezone/nativepicker/mic/TTS/offline/restartและ4exclusionsต้องมีruntimeที่รองรับหรือรายงานpending
- [ ] F10ตรวจTalkBackจริงและlearnerUATตามD1บนAPKที่ระบุhash; F11ใช้งาน3ชั่วโมงนับเวลาจริงพร้อมlifecycle/memory/frame/thermal/batteryตามdeviceplan เป็นคนละgateไม่แทนด้วยhostdebug
- [ ] การprofileใช้ `integration_test/adventure_performance_profile_test.dart` และ `tool/cli/run-adventure-performance-profile.ps1` ตามอุปกรณ์/ขอบเขตจริง; engineeringผ่านไม่ใช่release-signing/device/UAT/efficacyหรือสิทธิ์enroll/upload

## Task R — Rollback และส่งมอบตามหลักฐาน

- [ ] ถ้า Standard/resume/owner/evidence/consent/permit ผิด หยุด writer เฉพาะส่วน เก็บ synthetic reproduction และแก้ ไม่ลบ tests/ลด assertions/เพิ่ม skip เพื่อให้ผ่าน
- [ ] A ถอดเฉพาะ incremental presentation/assets หรือปิด entry ผ่านกลไกเดิมใน binary ที่รองรับ v24+; เก็บ history/pending recovery/SRS/inventory/Quest reconciliation ไม่ reset worktree/ลบ DB/uninstall/ยึดของ/backfill reward
- [ ] B/C ที่มี schema ใหม่ใช้ forward-compatible/repair release และหยุด writer ใหม่; ไม่ใช้ binary เก่าเปิดฐานใหม่; recurrence ต้อง cancel/reconcile OS entries ก่อนปิด entrypoint หรือ owner
- [ ] ส่ง checkpoint พร้อม branch/worktree/changed files/exact commands/results/exclusions/processes/APK identity/remaining gates/next step; แยก functional/visual/usability/learning claims และไม่ตั้งเป้ารายได้หรือ efficacy จาก automated tests
