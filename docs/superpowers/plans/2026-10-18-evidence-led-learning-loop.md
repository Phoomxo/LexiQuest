# แผนพัฒนา LexiQuest จากหลักฐานแอปตัวอย่าง — ฉบับปรับ UI และเส้นทางเรียน

วันที่ 2026-10-18 · Revision 2

สถานะ: ระยะที่ 1 วงจรเรียนหลักทำเสร็จและตรวจแล้ว; เอกสารนี้ปรับแผนระยะถัดไป
Checkout `C:/Users/Phet/Documents/LexiQuest`
Branch `feature/associative-reading-loop`
ฐาน HEAD `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`

หลักฐานที่ใช้:

- `PRODUCT.md`
- `docs/research/2026-10-18-duolingo-alltcas-feature-study.md`
- `docs/field/2026-10-18-learning-loop-improvements.md`
- `docs/superpowers/specs/2026-08-03-lexiquest-v2-evolution-framework-design.md`
- `test/screens/goldens/learning_hub_large_text.png` และภาพ golden ที่เกี่ยวข้อง

## 1. เป้าหมายฉบับปรับปรุง

ทำให้ LexiQuest เป็นแอปที่เปิดแล้วรู้ทันทีว่า “วันนี้ควรเรียนอะไร” จากนั้นทำวงจร
เรียนสั้นให้จบ รับ feedback ที่เชื่อถือได้ และเห็นก้าวต่อไปบนเส้นทางคำศัพท์ของตน

UI ต้องเป็นระบบเดียวกันทั้ง Hub, Quiz, Weakness, Score และ Progress ใช้ Material 3
ตามความคุ้นเคยของ Android แต่มีบุคลิก LexiQuest ที่สงบ ชัด และให้ความรู้สึกว่า
กำลังเดินทางพัฒนาความสามารถ ไม่ใช่หน้าเมนูรวมฟีเจอร์หรือเกมสะสมแต้ม

## 2. สิ่งที่เปลี่ยนจากแผนเดิม

| เรื่อง | แผนเดิม | แผนฉบับปรับปรุง |
| --- | --- | --- |
| จุดเริ่มต้น | พัฒนาวงจร Hub → Quiz → Score → ฝึกคำผิด | ถือว่าวงจรนี้เสร็จแล้วและใช้เป็นฐาน ไม่ย้อนทำซ้ำ |
| Navigation | แต่ละฟีเจอร์เป็นปลายทางใน bottom bar/drawer | ลดเหลือ 4 ปลายทางหลัก: เรียน, คลังคำ, ความก้าวหน้า, โปรไฟล์ |
| Hub | แสดงคิวจริงและรายการกิจกรรม | เป็นหน้าหลักเชิงคำแนะนำ มี “ทำต่อ” เพียงหนึ่ง CTA และ path preview |
| Weakness | หน้าจัดอันดับข้อผิดพร้อมปุ่มฝึก | เป็นโหมดซ่อมจุดอ่อนที่อธิบายเหตุผลและเลือกชุดฝึกได้ชัดเจน |
| Quiz feedback | แสดงถูก/ผิดและคำแปลในหน้าเดิม | ใช้ feedback panel ที่คงบริบทคำถามและพาไปข้อต่อไปโดยไม่กระโดดหน้า |
| Score | เปอร์เซ็นต์และรายการคำผิด | เน้น “สิ่งที่ดีขึ้น/ควรทำต่อ” พร้อม CTA เดียวตามข้อมูลจริง |
| World Map | โหนด CEFR hardcoded และยังไม่อยู่ใน navigation | ห้ามเปิดจนใช้ Curriculum Graph และ progress จริง; ทำเป็น path preview ก่อน |
| Gamification | มีรางวัล/XP/quest หลายทางเข้า | รวมไว้ใต้ความก้าวหน้า; Flexible Momentum และ reward ledger เดิมเท่านั้น |
| AI/โน้ต/กลุ่ม | เป็นรายการฟีเจอร์ที่อาจขยายต่อ | เลื่อนไปหลัง core path, persistence และ data lifecycle ผ่าน gate |
| คุณภาพ UI | golden เฉพาะ 4 หน้าหลักและ text scale สูง | เพิ่ม light/dark, compact/expanded, offline/error/empty และมือถือจริง |

## 3. ทิศทางภาพรวม UI

### แนวคิด: “เส้นทางเรียนที่สงบและมีเป้าหมาย”

หน้าจอใช้พื้นที่หายใจมากพอ ลำดับตัวอักษรชัด การ์ดมีหน้าที่จริง และสีเน้นเฉพาะ
สิ่งที่ผู้เรียนควรทำต่อ รูปร่างโค้งมนสื่อความเป็นมิตร แต่ไม่ใช้การ์ดซ้อนทุกข้อความ
หรือสีลูกกวาดหลายชุดจนแย่งความสนใจจากคำศัพท์

บุคลิกที่ต้องได้:

- ฉลาดแต่ไม่เป็นห้องแล็บ
- เป็นมิตรแต่ไม่เด็กเกินไป
- มีความเป็นเกมจากเส้นทาง ความคืบหน้า และการตอบสนอง ไม่ใช่จากเสียงดังหรือแรงกดดัน
- แสดงข้อมูลการเรียนด้วยภาษาธรรมดา; algorithm version อยู่ในรายละเอียด ไม่อยู่บนหน้าหลัก

### ระบบภาพที่เสนอ

| บทบาท | แนวทาง |
| --- | --- |
| Primary | Indigo/Violet สำหรับ CTA และตำแหน่งปัจจุบันบนเส้นทาง |
| Secondary | Teal สำหรับ mastery, การทบทวนสำเร็จ และข้อมูลสนับสนุน |
| Tertiary | Amber ใช้เฉพาะ momentum, milestone และคำแนะนำที่ควรสังเกต |
| Surface | เทาอมครามอ่อนใน light theme; น้ำเงินดำใน dark theme |
| Error | ใช้ error role ของ Material พร้อมข้อความ/ไอคอน ห้ามใช้สีอย่างเดียว |
| Typography | Noto Sans Thai ผ่าน Material type scale; คำศัพท์อังกฤษใช้ weight มากขึ้น ไม่เพิ่มฟอนต์ใหม่ |
| Shape | การ์ดหลัก 24 dp, การ์ดทั่วไป 16 dp, chip/pill เต็มความสูง; 48 dp touch target |
| Elevation | ใช้ tonal surface เป็นหลัก เงาเฉพาะองค์ประกอบที่ลอยจริง เช่น bottom sheet |
| Icons | Material Symbols/Icons เส้นสม่ำเสมอ; ไม่ใช้ emoji เป็นไอคอน navigation |

สีต้องผูกกับ `ColorScheme` และรองรับ light/dark; ค่าเฉพาะที่ตัดสินตอน implement
บันทึกใน `lib/config/m3_theme.dart` แห่งเดียว ไม่กระจาย raw color ตามหน้าจอ

### Motion และ feedback

- เปลี่ยนปลายทางหลักด้วย fade-through; เดินหน้าใน Quiz ด้วย shared-axis แนวนอน
- CTA กดแล้วแสดง progress ในตำแหน่งเดิม ไม่เปิด overlay ที่ทำให้ผู้ใช้ไม่รู้สถานะ
- ตอบถูกใช้ haptic เบาและการเปลี่ยน tonal surface; ตอบผิดใช้ข้อความช่วยแก้ ไม่สั่นแรงซ้ำ
- milestone ใช้ motion 300–450 ms หนึ่งครั้ง; เคารพ Reduce Motion ด้วย crossfade/instant state

## 4. Information architecture ใหม่

### Compact width: โทรศัพท์

Bottom navigation มี 4 จุดหมาย:

1. **เรียน** — Hub, คิววันนี้, path preview และกิจกรรมทั้งหมด
2. **คลังคำ** — หมวด ค้นหา เพิ่ม/นำเข้า และรายละเอียดคำ
3. **ความก้าวหน้า** — mastery, weakness, momentum และ achievements
4. **โปรไฟล์** — บัญชี การตั้งค่า AI/voice, export และ privacy

Weakness Clinic ไม่เป็น bottom destination แยก เพราะเป็นทั้งคำแนะนำจาก Hub และ drill-down
จาก Progress ส่วนร้านค้า/รางวัลอยู่ใน Progress เมื่อ feature เปิด เครื่องมือทดลองที่ limited
อยู่ใน “เครื่องมือเพิ่มเติม” พร้อมป้ายสถานะ ไม่ใช้ floating menu ทับเนื้อหาหลัก

### Expanded width: tablet/desktop

ใช้ NavigationRail 4 จุดหมายและคงรายละเอียดทางขวา ห้ามยืด bottom navigation เต็มจอ
เนื้อหาหลักจำกัดความกว้างสำหรับการอ่านภาษาไทย ส่วนรายการคลังคำใช้ master-detail ได้

## 5. แบบหน้าจอหลัก

### 5.1 Learning Hub — หน้าหลักหลังเข้าสู่ระบบ

```text
┌─────────────────────────────────┐
│ สวัสดี วันนี้พร้อมไปต่อไหม     ○ │
│ Momentum 4 วัน   เป้าหมาย 2/3   │
├─────────────────────────────────┤
│ แผนวันนี้                        │
│ ทบทวน 3 คำ • ซ่อมจุดอ่อน 1 คำ │
│ [ เริ่มทบทวน 3 คำ           → ] │
├─────────────────────────────────┤
│ เส้นทางของคุณ         A2 · 38% │
│ ●━━━━●━━━━◉────○                 │
│ ถัดไป: คำศัพท์การเดินทาง        │
├─────────────────────────────────┤
│ ฝึกแบบอื่น                       │
│ [Quiz] [ตามหมวด] [Flashcards]   │
└─────────────────────────────────┘
```

ลำดับข้อมูล:

- top app bar ใช้ชื่อ/สถานะสั้น ไม่ซ้ำกับหัวเรื่องใหญ่
- แถว momentum เป็นข้อมูลรองและไม่ขวางการเรียนเมื่อยังไม่มีข้อมูล
- `Today's plan` เป็น hero card เดียว เลือก due ก่อน weakness แล้ว quiz ตาม policy เดิม
- path preview แสดงข้อมูล curriculum จริง; ก่อน backend พร้อมใช้ empty/coming state ไม่ใช้โหนดปลอม
- “ฝึกแบบอื่น” ใช้ compact cards/chips 2 คอลัมน์ ไม่แสดงรายการยาวห้าการ์ดเต็มหน้าจอ

### 5.2 Quiz — พื้นที่ทำงานหนึ่งอย่าง

```text
┌─────────────────────────────────┐
│ ‹ Quiz ตามหมวด       3 / 10     │
│ ━━━━━━━━━━━──────────            │
│                                 │
│              station            │
│                noun             │
│                                 │
│ [ สถานี ]                       │
│ [ ร้านค้า ]                     │
│ [ การเดินทาง ]                  │
│ [ อาคาร ]                       │
│                                 │
│ ┌ feedback หลัง save สำเร็จ ┐   │
│ │ ถูกต้อง · station = สถานี │   │
│ │ ตัวอย่าง/บริบท (ถ้ามีจริง) │   │
│ │               [ข้อต่อไป] │   │
│ └───────────────────────────┘   │
└─────────────────────────────────┘
```

- ปุ่มคำตอบเป็น outlined/tonal choice cards ไม่เป็น CTA สี primary ทั้งหมด
- หลังตอบ ล็อกตัวเลือกและเปิด feedback panel ใต้คำตอบหรือ modal bottom sheet บนจอสั้น
- panel แสดงคำตอบผู้ใช้ คำตอบที่ถูก และบริบทจากข้อมูล LexiQuest เท่านั้น
- save failure คงตัวเลือกเดิมและแสดง “ลองบันทึกอีกครั้ง” ในตำแหน่ง action
- ปุ่มออกใช้ system back; ถ้ามีคำตอบที่ยังไม่จบ session จึงค่อยถามยืนยัน

### 5.3 Weakness Clinic — จากอันดับสู่แผนซ่อม

```text
┌─────────────────────────────────┐
│ ‹ จุดที่ควรฝึก                  │
│ 6 คำจากคำตอบล่าสุด 42 รายการ    │
│ [ผิดบ่อย] [ถึงกำหนด] [ล่าสุด]   │
├─────────────────────────────────┤
│ 1  station        ผิด 2/3       │
│    สถานีรถไฟ...   ●●○ 67%       │
│ 2  journey        ผิด 1/2       │
│ ...                             │
├─────────────────────────────────┤
│ [ ฝึกชุดที่แนะนำ 6 คำ        ] │
└─────────────────────────────────┘
```

- ข้อความสรุปใช้ภาษาผู้เรียน; sample size และรายละเอียด algorithm เปิดผ่าน info sheet
- filter เปิดเมื่อ query รองรับจริงเท่านั้น แผนระยะแรกมีเพียงอันดับผิดบ่อยตามข้อมูลปัจจุบัน
- sticky CTA เดียวเริ่ม targeted practice; due SRS เป็น action รองแบบ text/outlined

### 5.4 Score — ผลลัพธ์ที่พาไปต่อ

```text
┌─────────────────────────────────┐
│          ทำรอบนี้เสร็จแล้ว      │
│              8/10               │
│  ถูก 8  •  ควรฝึกต่อ 2 คำ      │
│                                 │
│ คำที่ควรฝึก                     │
│ station   journey               │
│                                 │
│ [ ฝึก 2 คำนี้ต่อ             ] │
│ [ กลับสู่แผนวันนี้            ] │
└─────────────────────────────────┘
```

- ใช้จำนวนถูก/ทั้งหมดเป็นข้อมูลหลัก; เปอร์เซ็นต์อยู่รองเพื่อลดความหมายแบบสอบตก/ผ่าน
- ถ้ามีคำผิด CTA หลักคือฝึกต่อ ถ้าไม่มีคำผิด CTA หลักคือกลับ Hub/เส้นทาง
- achievement หรือ reward ที่เกิดจริงแสดงเป็น inline celebration สั้นและ grant ครั้งเดียว

### 5.5 Progress — รวมภาพรวม จุดอ่อน และรางวัล

ส่วนบนตอบสามคำถาม: “ฉันอยู่ตรงไหน”, “อะไรดีขึ้น”, “ควรทำอะไรต่อ” จากนั้นใช้ tabs
หรือ segmented button สำหรับ ภาพรวม / จุดอ่อน / ความสำเร็จ โดย reuse progress projection เดิม
และไม่สร้าง score authority ใหม่

## 6. States ที่ต้องออกแบบพร้อมหน้าปกติ

ทุกหน้าหลักต้องมี:

- loading แบบ skeleton ที่รักษา layout โดยไม่กระพริบเปลี่ยนตำแหน่ง
- empty state พร้อม action จริง เช่น เพิ่มคำศัพท์หรือเริ่ม Quiz แรก
- inline error พร้อม retry และข้อความว่าข้อมูลในเครื่องเปลี่ยนหรือไม่
- offline/service unavailable banner ขนาดเล็ก โดยการเรียนในเครื่องยังทำต่อได้
- large text 1.3–1.8, TalkBack labels, contrast และ focus order
- dark theme ที่ใช้ role token เดียวกัน ไม่ invert สีแบบตรงตัว
- compact width 360 dp และ expanded width อย่างน้อยหนึ่งขนาด

## 7. ลำดับพัฒนาใหม่

### ระยะ 1 — Core learning loop (เสร็จแล้ว)

ผลลัพธ์: Hub ใช้คิวจริง, targeted weakness, durable answer feedback, Score → ฝึกคำผิด

หลักฐาน: `docs/field/2026-10-18-learning-loop-improvements.md`; focused regression 150 tests
ผ่าน และ targeted analyze ไม่พบปัญหา ณ checkpoint นั้น

### ระยะ 2 — Design foundation และ navigation cleanup

ผลลัพธ์:

- ปรับ `lib/config/m3_theme.dart` ให้มี semantic color/type/shape roles ที่ครบ light/dark
- ปรับ `lib/screens/main_navigation_screen.dart` เป็น 4 destinations และ responsive rail
- ย้าย Weakness/Achievements/Settings ไปยังปลายทางใหม่โดยคง feature flags
- ปรับ Hub ตาม hierarchy ในข้อ 5.1 โดย reuse progress/learning use cases เดิม
- เพิ่ม component เฉพาะที่ใช้ซ้ำจริงอย่างน้อยสองหน้า; ไม่สร้าง design framework ใหม่

เกณฑ์รับ:

- route เดิมที่มี caller ยังไปถึงหน้าที่ถูกต้องและ system Back ทำงาน
- compact/expanded navigation ไม่เกิน 5 destinations และไม่มี FAB เมนูลอยทับ app bar
- light/dark, font scale 1.3 และ 360 dp ไม่มี overflow; touch target ≥ 48 dp
- field feature hidden/limited/enabled ยังควบคุมการมองเห็นได้

### ระยะ 3 — Practice surfaces และ feedback polish

ผลลัพธ์:

- ปรับ Quiz, Weakness และ Score ตามข้อ 5.2–5.4
- เพิ่ม feedback component ที่ใช้ข้อมูลจริงและสถานะ save/retry เดิม
- ปรับ SRS ให้ใช้ภาษาภาพเดียวกัน แต่ไม่เปลี่ยน scheduling semantics

ไฟล์หลัก:

- `lib/screens/quiz_screen.dart`
- `lib/screens/weakness_clinic_screen.dart`
- `lib/screens/score_screen.dart`
- `lib/screens/srs_flashcards_screen.dart`
- tests/goldens ของหน้าดังกล่าว

เกณฑ์รับ:

- answer → durable save → feedback → next เป็นลำดับเดียวกันทุกครั้ง
- failure-before-write และ lost acknowledgement ไม่สร้าง answer/reward ซ้ำ
- สีถูก/ผิดมีข้อความและ semantics; large text ยังเห็น CTA ผ่าน scroll
- เส้นทาง Hub → Quiz → Score → Mistake Quiz → Hub refresh เพียงเมื่อ flow จบ

### ระยะ 4 — Curriculum Graph และ Learning Path

ผลลัพธ์:

- กำหนด query/model สำหรับ node, prerequisite, revision, mastery confidence และ next action
- เปลี่ยน `lib/screens/learning_world_map_screen.dart` จาก `_nodes` hardcoded เป็นข้อมูลจริง
- แสดง path preview บน Hub และหน้ารายละเอียดเส้นทางเมื่อ contract พร้อม
- คงการเรียนแบบเลือกเองได้เมื่อ curriculum authority unavailable

เกณฑ์รับ:

- kill/restart แล้วยังคง node/progress ที่ถูกต้อง
- unlock ใช้ evidence threshold และ policy revision ไม่ใช้ XP/streak/purchase
- empty/offline/stale revision มี state ชัดเจน; ไม่มีโหนดตัวอย่างใน production
- หากต้องเพิ่ม schema ให้ตรวจ migration ledger, export, deletion, sync และ owner isolation ก่อน

### ระยะ 5 — Progress, Momentum และ adaptive quest

ผลลัพธ์:

- รวม Mastery, Weakness, Flexible Momentum และ Evidence-backed Achievements ใน Progress
- quest แนะนำงานจากคิวเรียนจริง และให้รางวัลผ่าน ledger authority เดิมครั้งเดียว
- league หากมีเป็น opt-in และไม่ใช้เวลาหรือ XP แทน mastery

เกณฑ์รับ:

- timezone, duplicate day, sync replay และ policy revision ไม่ให้ reward ซ้ำ
- ปิด streak/quest แล้วยังเรียนได้ครบ
- ข้อความไม่ใช้ guilt/shame และไม่ลดความสามารถเมื่อหยุดเรียนหนึ่งวัน

### ระยะ 6 — Optional tools gate

พิจารณา AI Tutor, โน้ต, scanner, voice และ co-op ทีละความต้องการ หลังระยะ 2–5 ผ่าน
โดยแต่ละรายการต้องมี owner authority, entitlement, offline behavior, cost ceiling,
privacy/data lifecycle, quality evaluation และทางปิด/ลบข้อมูลก่อนเปิด navigation

## 8. การตรวจสอบตาม checkpoint

แต่ละระยะใช้ลำดับ: focused widget/domain tests → touched-feature tests → targeted analyze
→ golden review → integration flow บน Drift memory จากนั้นเมื่อเตรียม release จึงทำ full regression
และ Android build/install

คำสั่งตรวจหลักในระยะ UI:

- `flutter test --no-pub test/screens/choose_mode_screen_test.dart test/screens/quiz_screen_test.dart test/screens/weakness_clinic_screen_test.dart test/screens/learning_loop_layout_test.dart`
- `flutter test --no-pub test/features/learning test/features/progress test/features/rewards`
- `flutter analyze --no-pub <touched Dart files>`
- `dart format --output=none --set-exit-if-changed <touched Dart files>`

ก่อนถือว่า UI พร้อม release ต้อง build/install บน Android และจับภาพจากมือถือหรือ emulator:

- โทรศัพท์ compact: light/dark, font scale 1.0 และ 1.3
- tablet/expanded หากประกาศรองรับ
- ตรวจ system/predictive Back, edge-to-edge, keyboard inset, TalkBack และ Reduce Motion

## 9. ข้อจำกัดและสิ่งที่ไม่เปลี่ยน

- รักษา 8/44, EvidenceContext/EventEnvelopeV2 และ learning/reward authority เดิม
- ไม่เปลี่ยน research collection, consent/upload, enrollment หรือ deployment ในแผน UI นี้
- ไม่คัดลอก asset, ข้อสอบ, copy หรือ source code จาก Duolingo/AllTCAS
- ไม่เพิ่ม dependency สำหรับสี animation หรือ navigation ที่ Flutter/Material 3 มีอยู่แล้ว
- ไม่เปิด AI/โน้ต/multiplayer เพียงเพื่อให้เมนูดูครบ
- pre-existing modified/untracked files นอกแผนยังคง untouched

## 10. Acceptance ของแผนฉบับนี้

ถือว่าแผนพร้อมนำไป implement เมื่อยืนยันสามข้อ:

1. Android-first และ 4 destinations เป็นโครงสร้างนำทางหลัก
2. ทิศทาง “เส้นทางเรียนที่สงบและมีเป้าหมาย” เป็นภาพลักษณ์ที่ต้องการ
3. ทำระยะ 2–3 ก่อน Curriculum Graph และ optional tools

จนกว่าจะยืนยัน แผนนี้เป็น design brief และ implementation sequence; ยังไม่ใช่การอนุมัติ
DESIGN.md หรือการรับรองว่า UI ใหม่ผ่านมือถือจริง
