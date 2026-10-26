# LexiQuest Android UI master

สถานะปัจจุบัน: Revision 11 เป็น Android-first design authority ที่ตรวจในเครื่องแล้ว โดยยึด Vivo V2041 ขนาด 393×876dp เป็น canonical mobile ใช้ AllTCAS เป็นโครงงานและลำดับข้อมูล, Astra เป็นบริบทของผู้ช่วย AI และ Duolingo เป็นวงจรฝึก feedback ความก้าวหน้า และแรงจูงใจ ส่วน iOS เป็น future scope

## Figma artifact

- ชื่อไฟล์ปลายทาง: `LexiQuest · Master UI Revision 3 · Clickable Prototype`
- ไฟล์: https://www.figma.com/design/o9e5GYmA1gdrLC9Csxil6w/LexiQuest-%C2%B7-Master-UI-Revision-3-%C2%B7-Clickable-Prototype
- Design authority ที่ตรวจรับในเครื่อง: `R11 · LexiQuest · 40-point Android UI · COMPLETE · 240 screens · 942 routes · 41 starts`
- Figma Cloud แสดง R11 ที่ node `81:2`; final8 ปรับข้อความ Google ใน Login และหน้าเลือกวิธีเริ่มให้ตรงกับ runtime แล้วผ่าน browser session ของบัญชีเจ้าของงาน
- เจ้าของและบัญชีหลักของงาน LexiQuest: `petch954100@gmail.com` สำหรับ Figma, Canva และบริการออกแบบที่เชื่อมกับโปรเจกต์นี้ ห้ามสลับบัญชีเอง; โปรเจกต์อื่นต้องถามก่อน
- Revision 11 มี 240 linked specimens ครอบคลุม mobile, authentication/onboarding, 8 domains/44 capabilities, secondary flows, responsive/fold/tablet specimens, system states, dialogs และ completion states
- Navigation หลัก: เรียน, คลังคำ, ก้าวหน้า, โปรไฟล์
- Prototype หลัก: Welcome → Home → Quiz idle → Selected → Submit → กำลังบันทึก → บันทึกแล้ว → Correct/Wrong feedback → Result → Repair/Home
- Motivation branch: Result → Unlock → แข่งกับตัวเอง → Win → Reward → Home updated
- บัตรคำ: Front → Reveal → Rating → Saved → Next/Verify
- ผู้ช่วยเรียนด้วย AI: บริบท → ข้อความผู้เรียน → คำตอบพร้อมที่มา → ถามต่อ → กลับเข้าการฝึก

Generator อยู่ที่ [`lexiquest_master_ui_v9.js`](../../tmp/figma/lexiquest_master_ui_v9.js) และไฟล์ plugin สำหรับ Figma Desktop อยู่ใน [`plugin-v9`](../../tmp/figma/plugin-v9/) โดยสร้าง staging root ใหม่และแทน revision ก่อนหน้าหลัง validation ผ่านเท่านั้น

Local preview อยู่ที่ `../../tmp/figma/preview-v9/` และ snapshot ปัจจุบันสร้างครบ 240 targets มี 942 valid cross-screen reactions, 41 flow starts, 0 dead interaction, 0 broken destination, 0 duplicate route source, 0 section overflow และ 0 content overflow ผล critique รายหน้าจอผ่าน 40/40 ตาม [`2026-10-20-figma-r11-screen-by-screen-critique.md`](2026-10-20-figma-r11-screen-by-screen-critique.md)

## Responsive phases

1. **Phase 1 — Vivo/compact:** Vivo 393×876dp เป็น baseline; ตรวจ 360×800 และ 412×915dp โดยคง single pane, NavigationBar และ hierarchy เดิม
2. **Phase 2 — foldable:** Samsung cover/book/tabletop ใช้ runtime window และ hinge bounds; หาก usable pane ไม่ผ่าน list 320dp + detail 480dp ให้ fallback เป็น primary pane เดียว
3. **Phase 3 — tri-fold/tablet:** Huawei single/dual/triple คำนวณ safe regions จาก display features จริง; tablet ตรวจ 600×960, 800×1280, 1024×1366 และ 1280×800dp

สัญญาหลักอยู่ที่ [`lexiquest-revision-5-responsive-contract.md`](lexiquest-revision-5-responsive-contract.md) และชุด emulator อยู่ที่ [`lexiquest-revision-5-ldplayer-matrix.md`](lexiquest-revision-5-ldplayer-matrix.md) โปรไฟล์ LDPlayer 9 ถูกสร้างแยก 9 instance โดยไม่แก้ instance เดิม จอพับ/จอสามพับยังต้องใช้ Android foldable emulator หรืออุปกรณ์จริงเพื่อรับ hinge/posture ที่แท้จริง

## Design evidence และ audit

- [`figma-responsive-layout-audit.md`](figma-responsive-layout-audit.md) กำหนด breakpoint, grid, max width, safe area, IME, foldable และ text scale
- [`figma-prototype-flow-map.md`](figma-prototype-flow-map.md) เป็น route/screen inventory และ interaction map
- [`ai-visual-quality-audit.md`](ai-visual-quality-audit.md) ตรวจ card/pill density, type scale, spacing, contrast และ touch target โดยไม่อ้างว่าเดาผู้สร้างงานได้
- [`2026-10-18-figma-community-revision-5.md`](../research/2026-10-18-figma-community-revision-5.md) บันทึก research จาก Figma Community และ public product references
- [`2026-10-18-duolingo-astra-alltcas-layout-synthesis.md`](../research/2026-10-18-duolingo-astra-alltcas-layout-synthesis.md) บันทึกหลักฐาน REA และข้อจำกัดการอนุมาน

## Legacy transfer artifacts

- `lexiquest-canva-master-ui.html` เป็น source ของ Canva/PDF staging รุ่นก่อน
- `../../output/pdf/LexiQuest-Master-UI-Revision-3.pdf` เป็นไฟล์ส่งต่อแบบคงรูป
- Canva Revision 2 และ Figma Revision 3–10 เก็บเป็นหลักฐานย้อนหลัง; Revision 11 local source/preview และ Cloud node `81:2` เป็น design authority ปัจจุบัน

## ขอบเขตการตรวจรับ

- ปุ่มและเมนูในเส้นทางหลักต้องมี declared reaction; ห้ามใช้ generic fallback ซ่อน dead route
- การเลือกคำตอบไม่บันทึกผลจนกด Submit; Back, overlay และ destructive confirmation ต้องคืนบริบทเดิมหรือมีทางออก
- ต้องตรวจ 100%, 130%, 200% text scale, TalkBack, IME, gesture/3-button navigation, landscape, split-screen และ posture transition
- Figma และ LDPlayer เป็นหลักฐานด้าน layout/prototype ไม่ใช่หลักฐานว่า hardware, usability หรือ production readiness ผ่านแล้ว
