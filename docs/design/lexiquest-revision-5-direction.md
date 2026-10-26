# LexiQuest Revision 5 — Product and UI direction

อัปเดต: 2026-10-18

ขอบเขต: Android-first; Figma Page เดียว; Vivo V2041 เป็น canonical mobile; responsive ตาม runtime window, insets และ display features

## 1. แนวทางหลัก

LexiQuest ใช้โครงที่ผู้ใช้ไทยอ่านแล้วรู้ว่าต้องทำอะไรต่อทันที:

- **AllTCAS:** ลำดับ catalog → เลือกชุด → ทำทีละข้อ → ยืนยัน → เฉลย → สรุป
- **Astra:** บอก context ที่ AI ใช้ก่อนตอบ, แสดง provenance และมีทางกลับเข้าการฝึก
- **Duolingo:** ใช้เฉพาะ learning loop, visible progress, recovery และ motivation ที่ไม่แย่ง authority จากผลการเรียน

ภาษาในหน้าจอใช้คำไทยทั่วไป เช่น “เลือกแบบฝึก”, “บัตรคำทบทวน”, “แข่งกับตัวเอง”, “คำที่ควรฝึกเพิ่ม” หลีกเลี่ยงชื่อระบบอย่าง SRS, Ghost Battle หรือศัพท์เทคนิคที่ผู้ใช้ไม่จำเป็นต้องรู้

## 2. ลำดับ responsive

### Phase 1 — โทรศัพท์มาตรฐาน

- Baseline: Vivo V2041 `393×876dp`
- Boundary checks: `360×800dp`, `412×915dp`
- Single pane, margin 20dp, content width 353dp ที่ baseline
- NavigationBar 4 จุดหมาย; focused task ใช้ AppBar + Back
- Home ต้องเห็นงานถัดไปในครึ่งบน; Quiz ต้องเห็น prompt/choices/Submit; AI ต้องเห็น context/reply/composer; Result ต้องแสดงผลก่อน reward

### Phase 2 — Samsung foldable

- Cover, book, tabletop และ split window อ่านค่าจาก runtime
- Book 840dp fixture ใช้ single primary pane เพราะ safe regions ไม่ผ่านขั้นต่ำ
- Two-pane specimen ใช้ 1024×900dp โดย list 320dp, hinge 24dp และ detail 480dp
- Tabletop แยก content/control ตาม horizontal hinge โดยไม่ให้ prompt หรือ CTA คร่อม seam

### Phase 3 — Huawei tri-fold และ tablet

- Mate XT single/dual/triple แสดง seam เป็น exclusion zone และไม่สร้างหลาย task pane เพียงเพื่อเติมพื้นที่
- Tablet small: 600×960 และ upper check 800×1280dp
- Tablet medium: 1024×1366dp; conditional list-detail
- Tablet large: 1280×800dp; list/detail ใกล้ 42:58, gap 24dp
- Height boundary: 800×479 และ 800×480dp เพื่อพิสูจน์ compact-height override

รายละเอียดตัวเลขและ acceptance gate อยู่ใน [`lexiquest-revision-5-responsive-contract.md`](lexiquest-revision-5-responsive-contract.md)

## 3. Information architecture

Top-level navigation มีสี่จุดหมายเท่านั้น:

1. **เรียน** — Daily Quest, Resume, เส้นทาง, เลือกแบบฝึก
2. **คลังคำ** — ค้นหา กรอง ดูรายละเอียด เพิ่ม/นำเข้า และกล้อง
3. **ก้าวหน้า** — ผลที่บันทึกจริง คำที่ควรฝึกเพิ่ม เส้นทาง และรางวัลรอง
4. **โปรไฟล์** — บัญชี ส่งออก ช่วยเหลือ และการตั้งค่า

เมนูรองจัดตามงานของผู้ใช้ ไม่ใช้ชื่อโมดูลภายใน:

- ตอบคำศัพท์
- บัตรคำทบทวน
- อ่านเรื่องสั้น
- แข่งกับตัวเอง
- ฟังแล้วพิมพ์ / ฟังแล้วพูดตาม
- ส่องวัตถุหาคำ
- ผู้ช่วยเรียนด้วย AI
- โน้ตและแผนอ่านหนังสือ

## 4. Interaction contract

- การแตะ choice เปลี่ยน selected state เท่านั้น การบันทึกคำตอบเกิดเมื่อกด “ตรวจคำตอบ”
- Wrong answer ใช้ recovery → reveal → retry โดยไม่สร้าง mastery evidence จากการเปิดเฉลย
- Flashcard แยก reveal, rating, saved consequence และ optional verification quiz
- Back/Cancel คืน parent context ตามหมวด ไม่ส่งทุกหน้าไปเมนูรวม
- Dialog เปิดแบบ overlay และมี Close/Cancel ทุกครั้ง
- App bar actions: Home/Profile → Settings, Library → Search, AI → AI settings
- ไม่มี heuristic fallback ใน prototype; interactive node ที่ไม่มี declared route ทำให้ generator ล้มเหลว

## 5. Visual system

- Calm canvas `#F5F6FA`, surface `#FFFFFF`, ink `#171A2B`
- Primary `#5A4CF2`, mastery `#0E8176`, momentum `#D98213`, error `#B3261E`
- Noto Sans Thai เป็นหลัก; headline ใหญ่หนึ่งจุดต่อหน้าจอ; body 15–17sp; meta 12–14sp
- Spacing base 4dp; component gap 8–16dp; section gap 24–32dp
- Touch target อย่างน้อย 48×48dp; primary button 52–54dp
- Card ใช้เพื่อจัดกลุ่มงานเท่านั้น; ไม่ใส่ pill, gradient หรือ badge โดยไม่มีความหมาย

## 6. Coverage ของ Revision 5

- 39 main screens
- 28 authentication/onboarding screens
- 41 capability screens
- 34 secondary screens
- 17 responsive/accessibility specimens
- 10 system states
- 15 dialogs/sheets
- 32 TOR completion screens สำหรับ Auth, คลังคำ, หลักฐาน, CEFR, เสียง, overlays และ tablet roots
- รวม 216 linked frames, 876 valid cross-screen prototype reactions และ 29 flow starts ใน generator snapshot ปัจจุบัน; แท็บล่างที่เลือกอยู่ 4 จุดเป็นสถานะแสดงผลและไม่สร้าง self-navigation
- Local preview สร้างครบ 216 targets เป็น HTML/PNG ที่ไม่ซ้ำ; ให้ยึดผลตรวจจาก `../../tmp/figma/preview-v5/manifest.json`

งานทั้งหมดที่ตรวจรับแล้วอยู่ใน root `R5 · LexiQuest · Build 2026-10-18 · COMPLETE · 216 screens · 876 routes · 29 starts` บน Figma Page 1 เดียว เพื่อให้ใช้ฟรีได้และเชื่อม prototype ข้ามทุกกลุ่มหน้าจอ

## 7. Verification sequence

1. Generator route assertion และ local render ต้องผ่าน
2. ตรวจ contact sheets รอบ desktop สำหรับ overflow, typography, density และ pane balance
3. Import plugin เข้า Figma Desktop แล้วตรวจ Present mode ทุก starting point
4. รัน APK บน LDPlayer matrix ตาม [`lexiquest-revision-5-ldplayer-matrix.md`](lexiquest-revision-5-ldplayer-matrix.md)
5. รัน foldable/tri-fold บน emulator ที่รายงาน display features และอุปกรณ์จริงเมื่อมี
6. ตรวจ text scale 100/130/200%, IME, TalkBack, gesture/3-button navigation, rotation และ state continuity

Figma และ emulator ยืนยัน structure/interaction ได้ แต่ไม่ใช้กล่าวอ้าง usability, hardware compatibility หรือผลการเรียนโดยไม่มีหลักฐานทดสอบจริง
