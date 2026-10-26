# R11 design-to-code checkpoint

วันที่: 2026-10-20
Branch: `feature/associative-reading-loop`
Worktree: `C:\Users\Phet\Documents\LexiQuest`
Design authority: R11 hash `746354255a39619732391ad2f0f6a67377a7b2337231006331fef0e538091e10`

## ขอบเขตที่เสร็จ

- Foundations: R11 semantic colors, Noto Sans Thai, low-elevation cards และ touch target 48dp
- Adaptive shell: 4 destinations, NavigationBar สำหรับ compact และ NavigationRail เมื่อกว้างอย่างน้อย 600dp และสูงอย่างน้อย 480dp
- Core learning: Hub → Quiz/SRS/Associative Reading → saved feedback → result → weakness practice
- Progress IA: คำที่ควรฝึกเพิ่ม, ความสำเร็จ และร้านธีมอยู่ในหน้าก้าวหน้าและเคารพ feature registry
- Associative Reading ใช้คำศัพท์และ owner จริง สร้าง session เมื่อเริ่ม Active Recall บันทึก SRS/association ลง Drift และปิด session ทันทีหลังหลักฐานการตอบถูกบันทึก
- Feature registry ถูกส่งต่อถึง nested Mastery/Weakness paths จึงไม่มีทางลัดเปิด Quiz หรือ SRS ที่ถูกซ่อน

## หลักฐาน

- R11 prototype: 240/240 screens, 942 routes, 41 starts, 8 domains/44 capabilities; dead/broken/duplicate/bounds errors = 0
- Screen/design review รอบสุดท้าย: P0 = 0, P1 = 0 ใน Foundations, Adaptive shell และ Core learning scope
- `flutter analyze lib test`: ผ่าน ไม่มี issue
- `flutter test --no-pub`: ผ่าน 1,054 tests บน source snapshot ล่าสุด
- Focused lifecycle tests ยืนยันว่าไม่มี learning session ก่อน Active Recall, retry แบบ partial multi-word ไม่สร้างหลักฐานซ้ำ, write failure ค้างอยู่ขั้นเดิม, rapid double callback ไม่ข้ามขั้น และ session เป็น `completed` หลังหลักฐานครบ
- `flutter build bundle --debug`: ผ่านและ FontManifest มี `NotoSansThai`
- `git diff --check`: ผ่าน; มีเฉพาะคำเตือน CRLF ของ working copy

## ไฟล์หลัก

- `lib/config/m3_theme.dart`
- `lib/screens/main_navigation_screen.dart`
- `lib/screens/choose_mode_screen.dart`
- `lib/screens/quiz_screen.dart`
- `lib/screens/score_screen.dart`
- `lib/screens/weakness_clinic_screen.dart`
- `lib/screens/associative_reading_session_screen.dart`
- `lib/features/learning/application/learning_use_cases.dart`
- `lib/runtime/app_bootstrap.dart`

## ยังเป็น release-only

- Figma Cloud ยังเป็น R10; R11 local preview/plugin เป็น design authority ที่ตรวจแล้ว
- ยังไม่ทดสอบ LDPlayer/เครื่อง Android จริงสำหรับ IME, insets, 200% text และ fold posture
- ไม่ได้ deploy, publish, enroll participant หรือเปิด research upload
- Working tree มีการแก้ไขและไฟล์ untracked เดิมหลายรายการ; ไม่ได้ reset หรือลบงานของผู้ใช้
