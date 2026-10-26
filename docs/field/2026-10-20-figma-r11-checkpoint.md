# Figma R11 checkpoint

วันที่: 2026-10-20
Branch: `feature/associative-reading-loop`
Worktree: `C:\Users\Phet\Documents\LexiQuest`

## สถานะ

- Generator: `tmp/figma/lexiquest_master_ui_v9.js`
- Source hash: `746354255a39619732391ad2f0f6a67377a7b2337231006331fef0e538091e10`
- Preview: `tmp/figma/preview-v9`
- Plugin: `tmp/figma/plugin-v9`
- Critique: `docs/design/2026-10-20-figma-r11-screen-by-screen-critique.md`
- ผล critique: 40/40 ระดับ Figma prototype, P0=0, P1=0

## การเปลี่ยนสำคัญ

- F00 ลดเป็น 3 เป้าหมายหลักและรวมรายการรองไว้ใต้ “ดูเพิ่มเติม”
- F13 จัด 6 กิจกรรมเป็น 3 กลุ่มตามวิธีฝึก
- เพิ่ม supporting pane ให้ fold, Mate XT และ tablet ตามงานจริง
- T03/T04 ใช้ master-detail และพื้นที่ล่างสำหรับงานถัดไป/ค่าที่ใช้อยู่
- Text scale 200% เปลี่ยนจากหน้าสาธิตเป็น Home/Review flow จริง และแยกชื่อกิจกรรม จำนวนคำ และเวลาไม่ให้ข้อความซ้อนกัน
- ปรับ research, transaction และ responsive state ให้สแกนจบใน viewport
- เอา R11 decoration ที่ซ้อนกับปุ่มลบบัญชีออก

## หลักฐาน

- Render 240/240 screens
- 942 routes / 942 reaction sources
- 41 flow starts
- 8 domains / 44 capabilities
- dead interaction = 0
- broken route = 0
- duplicate route source = 0
- section bounds error = 0
- content bounds error = 0
- ตรวจภาพ core, responsive, interaction, auth, capability, menus, completion และ marketplace contact sheets
- ตรวจภาพเดี่ยว F00, F13, T03, T04, A14 และ A15
- ตรวจภาพต้นฉบับ `a11y-vivo-canonical-text-scale-200.png` หลังแก้แล้ว ไม่พบข้อความซ้อนหรือตัดขอบ

## Figma file

- File: `o9e5GYmA1gdrLC9Csxil6w`
- Web file ตรวจพบ R10 ที่ `240 screens · 942 routes · 41 starts`
- เว็บ Figma ไม่แสดง Development plugin; ภายหลังตรวจพบ Figma Desktop ในเครื่อง แต่ไม่ได้เปิดควบคุมหน้าจอผู้ใช้เพื่อทำงานเบื้องหลัง
- official Figma MCP ยืนยันบัญชี `petch954100@gmail.com` มี Full seat แต่การซิงก์วันที่ 2026-10-23 ถูกหยุดก่อนเขียนสำเร็จเมื่อ Starter MCP call limit เต็ม รายละเอียดอยู่ที่ `docs/field/2026-10-23-figma-r11-cloud-sync-attempt.md`
- Plugin R11 ถูกสร้างและตรวจแล้ว พร้อมรันจาก `tmp/figma/plugin-v9/manifest.json` เมื่อ Figma Desktop พร้อมใช้งาน

## ขั้นต่อไปที่ทำได้ทันที

เปิด Figma Desktop ที่ Page 1 แล้วรัน development plugin `LexiQuest Revision 11 Builder`; ตรวจ root ชื่อ `R11 · LexiQuest · 40-point Android UI · COMPLETE · 240 screens · 942 routes · 41 starts` และรอ cloud sync สำเร็จ
