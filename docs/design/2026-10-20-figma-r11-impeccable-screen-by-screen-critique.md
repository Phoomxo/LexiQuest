# Figma R11 — Impeccable Visual & UX Critique รายหน้าจอ

วันที่: 2026-10-20
Target: `tmp/figma/preview-v9`
Method: design review only (detector not applicable, native Android)
Source hash: `f669ca22a101f997a9c0d2274099b2948714ec9e7f8ec8fa212d3a84e6acb8c3`

## Design Health Score

| # | Heuristic | Score | Key issue |
|---:|---|---:|---|
| 1 | Visibility of System Status | 4/4 | loading, save, offline และ transaction state ครบ |
| 2 | Match System / Real World | 4/4 | ภาษาไทยส่วนใหญ่ตรงงานผู้เรียน; F41 ยังมีศัพท์ระบบ |
| 3 | User Control and Freedom | 3/4 | back/cancel ชัด แต่ undo และ bulk control ยังไม่ครอบคลุมทุกงาน |
| 4 | Consistency and Standards | 4/4 | Android navigation, component roles และ feedback สม่ำเสมอ |
| 5 | Error Prevention | 4/4 | destructive, auth, research และ purchase มี guardrail |
| 6 | Recognition Rather Than Recall | 4/4 | งานถัดไปและบริบทเดิมยังมองเห็น |
| 7 | Flexibility and Efficiency | 3/4 | ยังมี power-user/bulk path จำกัด |
| 8 | Aesthetic and Minimalist Design | 4/4 | hierarchy สงบและหนึ่ง primary action ต่อ viewport |
| 9 | Error Recovery | 4/4 | error ระบุสาเหตุ รักษางานเดิม และมี next step |
| 10 | Help and Documentation | 3/4 | มีศูนย์ช่วยเหลือ แต่ contextual help ยังไม่ทั่วทุก flow |
| **รวม** | | **37/40** | **Excellent · ไม่มี P0/P1** |

## ภาพรวม

R11 มีภาษาภาพที่เป็น LexiQuest ชัดขึ้น: AllTCAS ให้โครงงานและการสอบ, Astra ให้บริบท AI, Duolingo ให้ learning loop โดยรางวัลไม่แย่ง mastery จุดที่ยังต้องพิสูจน์คือ accessibility แบบผสมหลายเงื่อนไขและ adaptive layout บนอุปกรณ์จริง

## สรุประดับปัญหา

- P0: 0
- P1: 0
- P2: 7
- P3: 45

## ผลรายหน้าจอ

| # | หน้าจอ | ระดับ | ข้อสังเกตภาพ/UX | การแก้ที่แนะนำ |
|---:|---|---|---|---|
| 1 | 01 Welcome | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 2 | 02 Daily Quest Home | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 3 | 03 เลือกแบบฝึก | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 4 | 04 ตอบคำศัพท์ · เลือกแล้ว | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 5 | 05 Saved Feedback | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 6 | 06 สรุปการฝึก | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 7 | 07 Path Unlock | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 8 | 08 แข่งกับตัวเอง | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 9 | 09 Reward Reveal | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 10 | 10 Home · Updated | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 11 | 11 Vocabulary Library | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 12 | 12 Word Detail | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 13 | 13 Progress | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 14 | 14 ผู้ช่วย Lexi | P3 | โครงแชตคุ้นเคย แต่ mode chips และ trust note ยังใช้พื้นที่สนทนา | ย่อ metadata ใต้คำตอบและรักษาข้อความผู้ใช้/AI เป็นจุดนำสายตา |
| 15 | 15 Profile | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 16 | 16 Settings | P3 | รายการอ่านง่ายขึ้น แต่กลุ่มยาวยังมี visual rhythm ใกล้กัน | คงหัวข้อหมวดและเพิ่มระยะก่อนกลุ่มใหม่ใน implementation |
| 17 | 05B Wrong Feedback · Recovery | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 18 | 05C Answer Reveal · No Save | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 19 | 08B แข่งกับตัวเอง · ชนะ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 20 | 17 เลือกหมวดคำ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 21 | 18 บัตรคำ · ด้านหน้า | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 22 | 19 บัตรคำ · เปิดคำตอบ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 23 | 20 บัตรคำ · ระดับความจำ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 24 | 21 อ่านเรื่องสั้น | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 25 | 22 ยืนยันออกจากรอบ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 26 | 23 เมนูทั้งหมด | P3 | รายการอ่านง่ายขึ้น แต่กลุ่มยาวยังมี visual rhythm ใกล้กัน | คงหัวข้อหมวดและเพิ่มระยะก่อนกลุ่มใหม่ใน implementation |
| 27 | 24 ตั้งค่าผู้ช่วย AI | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 28 | 25 การแสดงผล | P3 | รายการอ่านง่ายขึ้น แต่กลุ่มยาวยังมี visual rhythm ใกล้กัน | คงหัวข้อหมวดและเพิ่มระยะก่อนกลุ่มใหม่ใน implementation |
| 29 | 26 สิทธิ์ของแอป | P3 | รายการอ่านง่ายขึ้น แต่กลุ่มยาวยังมี visual rhythm ใกล้กัน | คงหัวข้อหมวดและเพิ่มระยะก่อนกลุ่มใหม่ใน implementation |
| 30 | 27 ข้อมูลและความเป็นส่วนตัว | P3 | รายการอ่านง่ายขึ้น แต่กลุ่มยาวยังมี visual rhythm ใกล้กัน | คงหัวข้อหมวดและเพิ่มระยะก่อนกลุ่มใหม่ใน implementation |
| 31 | 28 เข้าสู่ระบบ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 32 | 29 เลือกหมวดคำ · เลือกแล้ว | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 33 | 30 ตอบคำศัพท์ · ยังไม่เลือก | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 34 | 31 ตอบคำศัพท์ · เลือกคำตอบอื่น | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 35 | 32 บัตรคำ · บันทึกระดับแล้ว | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 36 | 33 ผู้ช่วย Lexi · ตอบต่อเนื่อง | P3 | โครงแชตคุ้นเคย แต่ mode chips และ trust note ยังใช้พื้นที่สนทนา | ย่อ metadata ใต้คำตอบและรักษาข้อความผู้ใช้/AI เป็นจุดนำสายตา |
| 37 | 34 การแสดงผล · ใช้ค่าใหม่ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 38 | 35 ตอบคำศัพท์ · เลือกข้อ 3 | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 39 | 36 ตอบคำศัพท์ · เลือกข้อ 4 | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 40 | 37 ผู้ช่วย Lexi · กำลังส่ง | P3 | โครงแชตคุ้นเคย แต่ mode chips และ trust note ยังใช้พื้นที่สนทนา | ย่อ metadata ใต้คำตอบและรักษาข้อความผู้ใช้/AI เป็นจุดนำสายตา |
| 41 | 38 ผู้ช่วย Lexi · ส่งไม่สำเร็จ | P3 | โครงแชตคุ้นเคย แต่ mode chips และ trust note ยังใช้พื้นที่สนทนา | ย่อ metadata ใต้คำตอบและรักษาข้อความผู้ใช้/AI เป็นจุดนำสายตา |
| 42 | 39 ผู้ช่วย Lexi · ใช้ครบแล้ว | P3 | โครงแชตคุ้นเคย แต่ mode chips และ trust note ยังใช้พื้นที่สนทนา | ย่อ metadata ใต้คำตอบและรักษาข้อความผู้ใช้/AI เป็นจุดนำสายตา |
| 43 | 40 กำลังบันทึกคำตอบที่พลาด | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 44 | P1 · Compact lower bound · 360×800 dp | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 45 | P1 · Vivo V2041 canonical · 393×876 dp | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 46 | P1 · Compact upper check · 412×915 dp | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 47 | P2 · Samsung fold · Cover mode · Compact specimen | P3 | composition แยก pane และ rail ถูกทิศทาง แต่ hinge, inset และ posture ยังเป็น specimen | ยืนยันกับ WindowManager/LDPlayer และเครื่องจริงก่อน implementation sign-off |
| 48 | P2 · Samsung fold · Book posture · 840×900 fallback | P3 | composition แยก pane และ rail ถูกทิศทาง แต่ hinge, inset และ posture ยังเป็น specimen | ยืนยันกับ WindowManager/LDPlayer และเครื่องจริงก่อน implementation sign-off |
| 49 | P2 · Samsung fold · Tabletop posture · 840×900 specimen | P3 | composition แยก pane และ rail ถูกทิศทาง แต่ hinge, inset และ posture ยังเป็น specimen | ยืนยันกับ WindowManager/LDPlayer และเครื่องจริงก่อน implementation sign-off |
| 50 | P2 · Book posture · Two-pane minimum passed · 1024×900 | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 51 | P3 · Huawei Mate XT · Single panel · Compact class | P3 | composition แยก pane และ rail ถูกทิศทาง แต่ hinge, inset และ posture ยังเป็น specimen | ยืนยันกับ WindowManager/LDPlayer และเครื่องจริงก่อน implementation sign-off |
| 52 | P3 · Huawei Mate XT · Dual posture fallback · 720×960 illustrative | P3 | composition แยก pane และ rail ถูกทิศทาง แต่ hinge, inset และ posture ยังเป็น specimen | ยืนยันกับ WindowManager/LDPlayer และเครื่องจริงก่อน implementation sign-off |
| 53 | P3 · Huawei Mate XT · Triple posture fallback · 1100×900 illustrative | P3 | composition แยก pane และ rail ถูกทิศทาง แต่ hinge, inset และ posture ยังเป็น specimen | ยืนยันกับ WindowManager/LDPlayer และเครื่องจริงก่อน implementation sign-off |
| 54 | P3 · Small tablet · 600×960 dp | P3 | composition แยก pane และ rail ถูกทิศทาง แต่ hinge, inset และ posture ยังเป็น specimen | ยืนยันกับ WindowManager/LDPlayer และเครื่องจริงก่อน implementation sign-off |
| 55 | P3 · Small tablet upper check · 800×1280 dp | P3 | composition แยก pane และ rail ถูกทิศทาง แต่ hinge, inset และ posture ยังเป็น specimen | ยืนยันกับ WindowManager/LDPlayer และเครื่องจริงก่อน implementation sign-off |
| 56 | P3 · Large tablet landscape · 1280×800 dp | P3 | composition แยก pane และ rail ถูกทิศทาง แต่ hinge, inset และ posture ยังเป็น specimen | ยืนยันกับ WindowManager/LDPlayer และเครื่องจริงก่อน implementation sign-off |
| 57 | A11Y · Vivo canonical · Text scale 200% | P2 | reflow งาน Home/Review อ่านครบ แต่ยังไม่พิสูจน์ Login, Lexi chat และ Settings ที่ 200% | เพิ่ม specimen ของ 3 flow จริงที่ 200% พร้อมข้อความยาว |
| 58 | P3 · Medium tablet · 1024×1366 dp | P3 | composition แยก pane และ rail ถูกทิศทาง แต่ hinge, inset และ posture ยังเป็น specimen | ยืนยันกับ WindowManager/LDPlayer และเครื่องจริงก่อน implementation sign-off |
| 59 | Boundary · Compact height · 800×479 dp | P2 | จอสูง 479/480dp วาง CTA และ navigation ได้ แต่ยังไม่ได้รวม IME กับ font scale สูงใน state เดียว | เพิ่ม matrix 360×800, height 479dp, IME เปิด และ text 200% |
| 60 | Boundary · Medium height · 800×480 dp | P2 | จอสูง 479/480dp วาง CTA และ navigation ได้ แต่ยังไม่ได้รวม IME กับ font scale สูงใน state เดียว | เพิ่ม matrix 360×800, height 479dp, IME เปิด และ text 200% |
| 61 | A11Y · Vivo canonical · Text scale 130% | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 62 | A11Y · Vivo canonical · Dark theme core flow | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 63 | A11Y · Android split-screen · 720×540 dp | P3 | composition แยก pane และ rail ถูกทิศทาง แต่ hinge, inset และ posture ยังเป็น specimen | ยืนยันกับ WindowManager/LDPlayer และเครื่องจริงก่อน implementation sign-off |
| 64 | A00 ตรวจสถานะบัญชี | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 65 | A03 เชื่อมบัญชี Google สำเร็จ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 66 | A04 สร้างบัญชี | P3 | ลำดับฟอร์มชัด แต่ helper/legal text บางจุดยังเบากว่าฟิลด์มาก | เพิ่ม contrast และคง hit area ของ text action 48dp ใน implementation |
| 67 | A04B พร้อมสร้างบัญชี | P3 | ลำดับฟอร์มชัด แต่ helper/legal text บางจุดยังเบากว่าฟิลด์มาก | เพิ่ม contrast และคง hit area ของ text action 48dp ใน implementation |
| 68 | A05 ข้อกำหนดและความเป็นส่วนตัว | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 69 | A06 ตรวจอีเมลของคุณ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 70 | A07 ยืนยันอีเมลสำเร็จ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 71 | A08 ลืมรหัสผ่าน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 72 | A09 ตั้งรหัสผ่านใหม่ | P3 | ลำดับฟอร์มชัด แต่ helper/legal text บางจุดยังเบากว่าฟิลด์มาก | เพิ่ม contrast และคง hit area ของ text action 48dp ใน implementation |
| 73 | A10 พบบัญชีเดิม | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 74 | A11 ยืนยันก่อนเชื่อมบัญชี | P3 | ลำดับฟอร์มชัด แต่ helper/legal text บางจุดยังเบากว่าฟิลด์มาก | เพิ่ม contrast และคง hit area ของ text action 48dp ใน implementation |
| 75 | A12 ตรวจข้อมูลก่อนรวม | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 76 | A13 บัญชีและวิธีเข้าสู่ระบบ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 77 | A14 ตรวจขอบเขตการลบ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 78 | A15 ยืนยันตัวตนก่อนลบ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 79 | A16 ผลการลบบัญชี | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 80 | O01 Android Credential Manager | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 81 | O01B Google · สร้างบัญชี | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 82 | O01C Google · เชื่อมบัญชี | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 83 | O01D Google · ยืนยันก่อนลบ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 84 | O02 ยืนยันออกจากระบบ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 85 | O03 ยืนยันการลบครั้งสุดท้าย | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 86 | O03B พร้อมยืนยันการลบ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 87 | AS01 เข้าสู่ระบบไม่สำเร็จ | P3 | ลำดับฟอร์มชัด แต่ helper/legal text บางจุดยังเบากว่าฟิลด์มาก | เพิ่ม contrast และคง hit area ของ text action 48dp ใน implementation |
| 88 | AS02 เข้าสู่ระบบ · แป้นพิมพ์เปิด | P2 | CTA พ้น IME ใน canonical screen แต่ยังไม่มี error/ข้อความยาวและ compact width พร้อมกัน | ทดสอบ imePadding และ scroll-to-field ที่ 360×800 และ 200% |
| 89 | AS02B เข้าสู่ระบบ · แสดงรหัสผ่าน | P2 | CTA พ้น IME ใน canonical screen แต่ยังไม่มี error/ข้อความยาวและ compact width พร้อมกัน | ทดสอบ imePadding และ scroll-to-field ที่ 360×800 และ 200% |
| 90 | AS03 ส่งลิงก์รีเซ็ตแล้ว | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 91 | AS04 ตั้งรหัสผ่านสำเร็จ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 92 | AS05 ส่งอีเมลยืนยันอีกครั้ง | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 93 | F00 แผนที่ฟีเจอร์ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 94 | F01 คลังชุดเรียน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 95 | F02 รายละเอียดชุดเรียน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 96 | F03 การ์ดคำศัพท์แบบละเอียด | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 97 | F04 ที่มาและคุณภาพเนื้อหา | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 98 | F05 หน้าฝึกร่วม | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 99 | F08 เลือกคำจากคำอธิบาย | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 100 | F09 เติมคำในประโยค | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 101 | F10 จับคู่คำ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 102 | F11 พิมพ์คำตอบ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 103 | F12 กระดานฝึกเขียน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 104 | F12B กระดานเขียน · ล้างแล้ว | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 105 | F13 กิจกรรมฝึกครบรูปแบบ | P3 | การจัดกิจกรรมเป็น 3 กลุ่มช่วยลดภาระคิดแล้ว แต่คำอธิบายแต่ละกลุ่มยังเป็นข้อความสั้นมาก | ใส่ตัวอย่างงานหนึ่งบรรทัดเมื่อเปิดรายละเอียดกลุ่ม |
| 106 | F14 เริ่มด้วยบัตรคำ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 107 | F15 บันไดฝึกจำ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 108 | F16 ตั้งค่ารอบฝึก | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 109 | F19 คำใบ้และบริบท | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 110 | F20 บันทึกไว้ดูภายหลัง | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 111 | F21A รายงานเนื้อหา | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 112 | F21B ตรวจรายงานก่อนส่ง | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 113 | F22 ศูนย์ทบทวน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 114 | F23 จับเวลาเรียน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 115 | F24 บันทึกเวลาเรียน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 116 | F25 ปฏิทินการเรียน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 117 | F26 นับถอยหลังสู่เป้าหมาย | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 118 | F28 เปรียบเทียบผลประเมิน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 119 | F30 เรียนต่อเนื่องแบบไม่กดดัน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 120 | F31 ความสำเร็จและหมุดหมาย | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 121 | F33 เพื่อนร่วมทาง | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 122 | F34 การ์ดแบ่งปัน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 123 | F35A เลือกเป้าหมาย | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 124 | F35B เลือกเวลาที่มี | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 125 | F35C เลือกวิธีเรียน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 126 | F35D สรุปแผนเริ่มต้น | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 127 | F36 โปรไฟล์การเรียนรู้ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 128 | F37 คำแนะนำถัดไป | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 129 | F38 การช่วยการเข้าถึง | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 130 | F41 สถานะฟีเจอร์ทดลอง | P2 | หน้าสถานะยังใช้คำเชิงระบบ “controlled rollout” ซึ่งไม่ใช่ภาษาผู้เรียน | เปลี่ยนเป็นผลกระทบต่อผู้ใช้ และซ่อนรายละเอียดระบบใต้ “รายละเอียดเพิ่มเติม” |
| 131 | F44 เนื้อหาออฟไลน์ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 132 | F43A ประวัติการเรียน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 133 | F43B รายละเอียดรอบเรียน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 134 | M01 จัดการคลังคำ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 135 | M02 เลือกวิธีฝึก | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 136 | M03 เครื่องมือช่วยเรียน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 137 | M04 ดูความก้าวหน้า | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 138 | M05 บัญชีและข้อมูล | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 139 | S01 เพิ่มคำศัพท์ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 140 | S02 เพิ่มหลายคำ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 141 | S03 ตรวจไฟล์นำเข้า | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 142 | S04 จับคู่คำ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 143 | S05 เรียงตัวอักษร | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 144 | S06 เรียงประโยค | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 145 | S07 เติมคำ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 146 | S08 ฟังแล้วพิมพ์ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 147 | S09 ฟังแล้วพูดตาม | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 148 | S10 ผลการออกเสียง | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 149 | S10B ข้อความประกอบเสียง | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 150 | S11 ส่องวัตถุหาคำ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 151 | S12 ตรวจคำจากภาพ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 152 | S13 ด่านท้าทาย | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 153 | S14 เตรียมแข่งกับตัวเอง | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 154 | S15 ผลด่านท้าทาย | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 155 | S16 ศูนย์แต้มและร้านธีม | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 156 | S17 ของตกแต่งโปรไฟล์ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 157 | S18 บริการผู้ช่วย AI | P2 | ชื่อ provider และโควตายังเด่นใกล้เคียงงานของผู้ใช้ | แสดงสถานะพร้อมใช้/ใช้ไม่ได้ก่อน และย้ายชื่อบริการไปส่วนขั้นสูง |
| 158 | S19 คีย์สำหรับเชื่อมบริการ AI | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 159 | S20 โน้ตการเรียน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 160 | S21 เพิ่มโน้ต | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 161 | S22 แผนอ่านหนังสือ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 162 | S23 การเข้าร่วมงานวิจัย | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 163 | S24 งานวิจัยที่ได้รับ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 164 | S25 ดาวน์โหลดข้อมูล | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 165 | S26 ช่วยเหลือ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 166 | S27 การแจ้งเตือน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 167 | S27B บันทึกการแจ้งเตือนแล้ว | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 168 | M35 ร้านธีม | P3 | flow ร้านธีมครบและ recovery ชัด แต่ preview ยังพึ่ง palette มากกว่าบุคลิกภาพจริง | เพิ่ม thumbnail motif/texture ของธีมโดยคง contrast |
| 169 | M36 ร้านธีม · กรอง | P3 | flow ร้านธีมครบและ recovery ชัด แต่ preview ยังพึ่ง palette มากกว่าบุคลิกภาพจริง | เพิ่ม thumbnail motif/texture ของธีมโดยคง contrast |
| 170 | M37 รายละเอียดธีม | P3 | flow ร้านธีมครบและ recovery ชัด แต่ preview ยังพึ่ง palette มากกว่าบุคลิกภาพจริง | เพิ่ม thumbnail motif/texture ของธีมโดยคง contrast |
| 171 | M38 ดูตัวอย่างธีม | P3 | flow ร้านธีมครบและ recovery ชัด แต่ preview ยังพึ่ง palette มากกว่าบุคลิกภาพจริง | เพิ่ม thumbnail motif/texture ของธีมโดยคง contrast |
| 172 | M39 ยืนยันแลกธีม | P3 | flow ร้านธีมครบและ recovery ชัด แต่ preview ยังพึ่ง palette มากกว่าบุคลิกภาพจริง | เพิ่ม thumbnail motif/texture ของธีมโดยคง contrast |
| 173 | M40 กำลังแลกธีม | P3 | flow ร้านธีมครบและ recovery ชัด แต่ preview ยังพึ่ง palette มากกว่าบุคลิกภาพจริง | เพิ่ม thumbnail motif/texture ของธีมโดยคง contrast |
| 174 | M41 แลกธีมสำเร็จ | P3 | flow ร้านธีมครบและ recovery ชัด แต่ preview ยังพึ่ง palette มากกว่าบุคลิกภาพจริง | เพิ่ม thumbnail motif/texture ของธีมโดยคง contrast |
| 175 | M42 ทดลองใช้ธีม | P3 | flow ร้านธีมครบและ recovery ชัด แต่ preview ยังพึ่ง palette มากกว่าบุคลิกภาพจริง | เพิ่ม thumbnail motif/texture ของธีมโดยคง contrast |
| 176 | M43 ใช้ธีมแล้ว | P3 | flow ร้านธีมครบและ recovery ชัด แต่ preview ยังพึ่ง palette มากกว่าบุคลิกภาพจริง | เพิ่ม thumbnail motif/texture ของธีมโดยคง contrast |
| 177 | M44 ธีมของฉัน | P3 | flow ร้านธีมครบและ recovery ชัด แต่ preview ยังพึ่ง palette มากกว่าบุคลิกภาพจริง | เพิ่ม thumbnail motif/texture ของธีมโดยคง contrast |
| 178 | M45 รายละเอียดพื้นหลัง | P3 | flow ร้านธีมครบและ recovery ชัด แต่ preview ยังพึ่ง palette มากกว่าบุคลิกภาพจริง | เพิ่ม thumbnail motif/texture ของธีมโดยคง contrast |
| 179 | M46 ศูนย์แต้ม | P3 | flow ร้านธีมครบและ recovery ชัด แต่ preview ยังพึ่ง palette มากกว่าบุคลิกภาพจริง | เพิ่ม thumbnail motif/texture ของธีมโดยคง contrast |
| 180 | M47 ประวัติแต้ม | P3 | flow ร้านธีมครบและ recovery ชัด แต่ preview ยังพึ่ง palette มากกว่าบุคลิกภาพจริง | เพิ่ม thumbnail motif/texture ของธีมโดยคง contrast |
| 181 | M48 แต้มไม่พอ | P3 | flow ร้านธีมครบและ recovery ชัด แต่ preview ยังพึ่ง palette มากกว่าบุคลิกภาพจริง | เพิ่ม thumbnail motif/texture ของธีมโดยคง contrast |
| 182 | M49 รายการเปลี่ยนแปลง | P3 | flow ร้านธีมครบและ recovery ชัด แต่ preview ยังพึ่ง palette มากกว่าบุคลิกภาพจริง | เพิ่ม thumbnail motif/texture ของธีมโดยคง contrast |
| 183 | M50 ใช้งานออฟไลน์ | P3 | flow ร้านธีมครบและ recovery ชัด แต่ preview ยังพึ่ง palette มากกว่าบุคลิกภาพจริง | เพิ่ม thumbnail motif/texture ของธีมโดยคง contrast |
| 184 | ST01 กำลังโหลด | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 185 | ST02 ยังไม่มีคำ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 186 | ST03 บันทึกไม่สำเร็จ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 187 | ST04 ไม่ใช้อินเทอร์เน็ต | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 188 | ST05 ไม่อนุญาตสิทธิ์ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 189 | ST06 ปิดสิทธิ์ไว้ใน Android | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 190 | ST07 กำลังบันทึก | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 191 | ST08 บันทึกแล้ว | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 192 | ST09 ฟีเจอร์ยังไม่พร้อม | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 193 | ST10 ยืนยันการลบ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 194 | D01 ออกจากรอบฝึก | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 195 | D02 เหตุผลขอสิทธิ์ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 196 | D03 รายละเอียดออฟไลน์ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 197 | D04 แหล่งนำเข้า | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 198 | D05 ลบคำ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 199 | D06 สร้างไฟล์ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 200 | D07 รายละเอียดงานวิจัย | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 201 | D08 ได้รับรางวัล | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 202 | D09 ตัวกรอง | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 203 | D10 ข้อมูลที่ AI ใช้ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 204 | D11 ค้นหาคำ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 205 | D12 ลบบัญชี | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 206 | D13 เวอร์ชันและใบอนุญาต | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 207 | D14 ศูนย์ช่วยเหลือ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 208 | D15 เอกสารบัญชีฉบับเต็ม | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 209 | A02 เลือกวิธีเริ่ม | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 210 | A08 ตรวจความปลอดภัยรหัสผ่าน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 211 | P10 หมวดคำศัพท์ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 212 | P11 คำในหมวด | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 213 | P13 ค้นหาและกรอง | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 214 | P16 เลือกแหล่งนำเข้า | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 215 | P24 ภาพรวมความเข้าใจ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 216 | P25 คำที่ควรฝึกเพิ่ม | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 217 | P27 รายละเอียดหลักฐาน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 218 | P28 เส้นทางการเรียน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 219 | P29 คลังเนื้อหาตามระดับ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 220 | P30 แบบประเมินระดับ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 221 | P30R ผลประเมินระดับ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 222 | P32 อ่านเชื่อมโยง 6 ขั้น | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 223 | P40 พูดแล้วดูข้อความ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 224 | P42 สำรวจเสียงและสัทอักษร | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 225 | P43 เพลย์ลิสต์ทบทวน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 226 | P50 สรุปโปรไฟล์ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 227 | P53 การเรียนและการช่วยการเข้าถึง | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 228 | P58 ความคืบหน้าและผลส่งออก | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 229 | O03 เพิ่มหมวดคำศัพท์ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 230 | O06 ทิ้งแบบร่าง | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 231 | O08 ตัวช่วยสร้างภาพจำ | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 232 | O09 เหตุผลที่ขอใช้ไมโครโฟน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 233 | O10 เหตุผลที่ขอใช้กล้อง | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 234 | O11 ลบคีย์ผู้ให้บริการ AI | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 235 | O12 ยืนยันแลกของตกแต่ง | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 236 | O13 เปลี่ยนรหัสผ่าน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 237 | O15 เลือกเข้าร่วมหรือปฏิเสธงานวิจัย | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 238 | P59 แดชบอร์ดวิจัยภายใน | ผ่าน | ลำดับชั้น งานหลัก สถานะ และทางไปต่อชัดตาม Calm Journey / Evidence Trail | คง pattern และตรวจกับข้อมูลจริง |
| 239 | T03 แท็บเล็ต · ความก้าวหน้า | P3 | master-detail ใช้พื้นที่ดีขึ้น แต่ pane ซ้ายยังมีพื้นที่ว่างมากหลังรายการสั้น | ให้ความสูง pane ตาม content หรือเติมข้อมูลที่ช่วยตัดสินใจจริงเท่านั้น |
| 240 | T04 แท็บเล็ต · โปรไฟล์และการตั้งค่า | P3 | master-detail ใช้พื้นที่ดีขึ้น แต่ pane ซ้ายยังมีพื้นที่ว่างมากหลังรายการสั้น | ให้ความสูง pane ตาม content หรือเติมข้อมูลที่ช่วยตัดสินใจจริงเท่านั้น |
