# LQ-01 Wave 1 checkpoint

วันที่: 2026-10-20
Chat / card: `LQ-01 Design, Responsive & Figma` / I2 + I7
Branch: `feature/associative-reading-loop`
HEAD snapshot: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1` + dirty working tree
Design authority: R11 hash `746354255a39619732391ad2f0f6a67377a7b2337231006331fef0e538091e10`

## Outcome and user-visible behavior

- จำกัด adaptive shell บนจอ large ให้กว้างไม่เกิน 1200dp และจัดกลาง แทนการยืดเต็ม 1280dp
- เพิ่ม widget evidence สำหรับ 360×800, 393×876, 412×915, 600×960, 840×900, 1280×800 และ height boundary 800×479/480
- ยืนยันว่า bar → rail และ height override ไม่สร้าง navigation event หรือทำ state ของ `ChooseModeScreen` หาย
- ไม่เปลี่ยน route, feature registry, schema, learning/reward/research authority หรือ contract สาธารณะ

## Changed files and shared-file touches

- `lib/screens/main_navigation_screen.dart` — shared adaptive shell; เพิ่ม max-width constraint เท่านั้น
- `test/screens/main_navigation_screen_test.dart` — responsive matrix, height-boundary continuity และ 1200dp shell bound
- `docs/field/2026-10-20-lq01-wave1-checkpoint.md` — checkpoint นี้

ไฟล์สองรายการแรกมี R11 dirty edits เดิมอยู่ก่อน LQ-01; งานนี้ไม่ reset หรือ overwrite ส่วนอื่น และ diff ของ LQ-01 จำกัดอยู่ที่ shell constraint กับ tests ข้างต้น

## Contracts / schema / route / feature IDs affected

- Responsive acceptance contract: large shell `≤1200dp`, width breakpoint 600dp และ compact-height boundary 480dp
- Schema: none
- Routes: none
- Feature IDs / catalog 8/44: none

## Focused checks

| Check | Result |
| --- | --- |
| Baseline focused suite ก่อนแก้: `flutter test --no-pub test/config/m3_theme_test.dart test/screens/main_navigation_screen_test.dart test/screens/production_shell_navigation_test.dart test/screens/learning_loop_layout_test.dart test/screens/accessibility_smoke_test.dart` | pass, 26 tests |
| TDD RED: `flutter test --no-pub test/screens/main_navigation_screen_test.dart --plain-name "large tablet keeps the adaptive shell within 1200dp"` | expected fail: actual shell width 1280dp > 1200dp |
| TDD GREEN คำสั่งเดิมหลังแก้ | pass, 1 test |
| `flutter test --no-pub test/screens/main_navigation_screen_test.dart` | pass, 10 tests |
| Focused affected suite คำสั่ง baseline เดิมหลังแก้ | pass, 29 tests |
| `flutter analyze lib/screens/main_navigation_screen.dart test/screens/main_navigation_screen_test.dart` | pass, no issues |
| `flutter build apk --debug --no-pub` | pass; `build/app/outputs/flutter-apk/app-debug.apk` |
| `git diff --check` | pass; มีเฉพาะคำเตือน CRLF ของ working copy |

## Claude review

`not available` — pre-edit read-only request จบด้วย `401 Invalid API key` หลังรอประมาณ 180 วินาที จึงไม่ retry โดยไม่มีหลักฐานว่า authentication ถูกแก้; post-check review ไม่ถูกอ้างว่าเกิดขึ้น

Local evidence-derived review: accepted สำหรับ max-width fix และ widget matrix; ไม่พบ route/authority/data side effect ในขอบเขต diff นี้

## Device / external / release dependencies

- LDPlayer 9 มี profile แยกครบ 9 ชุดตาม matrix และ `flutter build apk --debug --no-pub` ผ่าน
- Runtime LDPlayer ยัง `not verified`: instance `LQ-P1-Vivo-393x876` เปิด process ได้แต่ guest ADB ตอบ `device 'emulator-5556' not found`; หลัง reconcile ADB daemon และ quit/launch เฉพาะ task-owned instance แล้ว instance หยุดเอง จึงหยุดตาม recovery budget ไม่มี app install, screenshot, insets, IME หรือ text-scale runtime record
- Fold/hinge/tabletop, system bars/cutout และ physical-device behavior ยัง `not verified`; LDPlayer profile metadata ไม่แทนหลักฐานเหล่านี้
- Figma Cloud ยัง `not verified`: read-only metadata call ถูกปฏิเสธเพราะ Starter-plan MCP call limit; ไม่มี Figma mutation และไม่อ้างว่า R11 sync สำเร็จ
- ไม่ได้ deploy, publish, enroll participant หรือ upload research data

## Review disposition

- Code/layout card: `accepted` จาก focused automated evidence
- LDPlayer runtime matrix: `not verified`
- Figma Cloud sync: `not verified`
- Physical/foldable acceptance: `not verified`

## Next executable step

1. เมื่อ LDPlayer guest boot/ADB ใช้งานได้ ให้ติดตั้ง APK จาก snapshot เดียวกัน เปิดทีละ instance และเก็บ `wm size`, density, app window/insets, text scale, navigation mode และ screenshot ด้วยข้อมูลสังเคราะห์เท่านั้น
2. เมื่อ Figma MCP limit พร้อม ให้ inspect file `o9e5GYmA1gdrLC9Csxil6w` ก่อนเขียน แล้ว sync R11 และยืนยัน root ชื่อ `R11 · LexiQuest · 40-point Android UI · COMPLETE · 240 screens · 942 routes · 41 starts`
3. ใช้ Android foldable emulator ที่รายงาน display features หรืออุปกรณ์จริงสำหรับ hinge/posture; ห้ามใช้ LDPlayer model metadata แทน
