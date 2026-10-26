# LexiQuest R11 Design-to-Code Implementation Plan

วันที่: 2026-10-20
สถานะ: Complete
Branch: `feature/associative-reading-loop`
Design authority: R11 source hash `746354255a39619732391ad2f0f6a67377a7b2337231006331fef0e538091e10`

## Outcome

ย้าย LexiQuest จากต้นแบบ R11 ไปสู่ Flutter implementation ที่ใช้ design tokens เดียวกัน มี adaptive shell สี่ปลายทาง และเดินวงจรเรียนหลัก `Home → Setup → Practice → Saved feedback → Result → Weakness` โดยไม่สร้าง authority หรือ state คู่ขนาน

## Constraints

- รักษา feature catalog 8/44 และ learning/reward/research authorities เดิม
- Android-first, Thai-first, English learning only
- Research และ real enrollment/upload ปิดเป็นค่าเริ่มต้นจน authority gates ผ่าน
- 240 Figma frames เป็น routes, states, overlays และ responsive specimens ไม่ใช่ 240 widgets
- ใช้ R11 local preview เป็น authority ระหว่างที่ Figma Cloud ยังเป็น R10
- Flutter dependency resolution, generation และ test/build รันตามลำดับใน worktree นี้

## Cards

### D0 — Close visual handoff defects · Done

- Write set: `tmp/figma/lexiquest_master_ui_v9.js`, generated preview/plugin, R11 checkpoint/critique metadata
- Work: แก้ Text scale 200% collision แล้ว render/validate 240 screens และ 942 routes ใหม่
- Acceptance: ภาพ `a11y-vivo-canonical-text-scale-200.png` ไม่มีข้อความซ้อน; validator ไม่มี dead/broken/duplicate/bounds errors

### D1 — Implementation mapping · Done

- Write set: `docs/design/2026-10-20-r11-implementation-map.md`
- Work: map frame families ไป canonical widget, UI state, route/overlay, authority และ acceptance test
- Acceptance: ครอบคลุม section A/B/C/D/E/F/G/K, ระบุ route/state/responsive/overlay ชัด และไม่เสนอ 240 widgets

### D2 — Foundations · Done

- Write set: `lib/config/m3_theme.dart`, `test/config/m3_theme_test.dart`
- Work: เปลี่ยน Material theme ให้ตรง R11 tokens, Noto Sans Thai, semantic colors, low-elevation cards และ touch target 48dp
- Acceptance: focused theme tests เขียนก่อน production change, เห็น RED ที่ถูกเหตุผล แล้ว GREEN

### D3 — Adaptive shell · Done

- Write set: `lib/screens/main_navigation_screen.dart`, `test/screens/main_navigation_screen_test.dart`, `test/screens/production_shell_navigation_test.dart`
- Work: ลด root navigation เป็น `เรียน · คลังคำ · ก้าวหน้า · โปรไฟล์`; compact ใช้ NavigationBar, width ≥600 ใช้ NavigationRail; เก็บ IndexedStack state และ drawer tools
- Acceptance: widget tests พิสูจน์ 4 destinations, compact/rail boundary 599/600dp, tab state preservation และ local learning ระหว่าง cloud outage

### D4 — Core learning vertical slice · Done

- Read/write set: existing Hub/Choose Mode/Quiz/Score/Weakness use cases and focused tests only; preserve current unrelated dirty edits
- Work: เชื่อม CTA และ navigation ให้เดินวงจรเรียนหลักด้วย persistence-before-feedback เดิม
- Acceptance: focused tests ครอบคลุม next action, setup, saved correct/wrong feedback, result recommendation และ weakness retry โดยไม่มี reward/mastery authority ใหม่

### D5 — Attestation · Done

- Work: focused tests → affected screen tests → `flutter analyze` → full Flutter suite at integration checkpoint; inspect final diff and save checkpoint
- Acceptance: แยกผลผ่าน, failure เดิม, device-only checks และ Figma Cloud dependency อย่างชัดเจน

ผลยืนยันล่าสุดบันทึกไว้ที่ `docs/field/2026-10-20-r11-design-to-code-checkpoint.md`

## Release-only dependencies

- Figma Cloud sync ของ R11
- LDPlayer/physical Android evidence สำหรับ IME, text 200%, insets และ fold posture
- Google sign-in contract, theme composition root และ research authority gates ก่อนเปิดฟีเจอร์เหล่านั้น
