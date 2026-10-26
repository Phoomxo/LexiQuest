# LexiQuest SE Council — Design System Decision

วันที่: 2026-10-20
สถานะ: `APPROVED FOR FIGMA DESIGN`
ผู้ร่วมตัดสิน: PM, SA, BA, UX/UI, Dev, QA และ CTO integrator

## Product thesis

ผู้เรียนภาษาไทยเลือกหรือนำเข้าคำศัพท์อังกฤษ เห็นงานที่ควรทำ ฝึก รับผลตอบกลับหลังบันทึกสำเร็จ และซ่อมคำที่พลาดต่อได้ทันที แม้ AI หรืออินเทอร์เน็ตไม่พร้อม

## ข้อตกลงที่ทุกบทบาทใช้ร่วมกัน

| เรื่อง | มติ |
| --- | --- |
| ขอบเขต | ภาษาอังกฤษเท่านั้น, Android-first, local-first |
| Navigation | เรียน / คลังคำ / ก้าวหน้า / โปรไฟล์ |
| Product loop | เลือกหรือนำเข้า → ตรวจแก้ → ยืนยัน → ฝึก → ผลตอบกลับที่บันทึกแล้ว → ซ่อมจุดอ่อน |
| Layout authority | AllTCAS ใช้กับ dashboard, catalog, setup, question และ feedback |
| AI authority | Astra ใช้กับ source/context, progressive disclosure และ structured answer |
| Learning rhythm | Duolingo ใช้กับ resume, path, repair loop และ cosmetic reward |
| Data authority | `ImportVocabulary`, `LearningUseCases`, reward ledger และ owner isolation เดิม |
| Catalog | รักษา 8 หมวด/44 ความสามารถ ห้ามเพิ่ม `f45` |
| AI | เป็นผู้ช่วยเสริม ห้ามเขียน mastery หรือ reward โดยตรง |
| Reward | ธีมและพื้นหลังเป็น cosmetic ไม่เปลี่ยนผลการเรียน |

## Information architecture

1. **เรียน** — งานวันนี้, เรียนต่อ, เลือกชุดฝึก และเครื่องมือช่วยเรียน
2. **คลังคำ** — หมวด, ค้นหา, เพิ่ม, นำเข้า, รายละเอียด และบัตรคำ
3. **ก้าวหน้า** — หลักฐาน, คำที่ควรฝึกเพิ่ม, ความสำเร็จ และร้านธีม
4. **โปรไฟล์** — บัญชี, การแสดงผล, สิทธิอุปกรณ์, AI, งานวิจัย และส่งออก

Weakness, achievements และร้านธีมเป็น drill-down จากก้าวหน้า ไม่เป็น bottom destination แยก เมนูทั้งหมดใช้กับงานรองที่มี route จริงเท่านั้น

## Layout archetypes

| Archetype | เป้าหมาย | ตัวอย่าง |
| --- | --- | --- |
| Focus | หนึ่งโจทย์ หนึ่งคำตอบ หนึ่งขั้นถัดไป | Quiz, SRS, Reading |
| Browse | ค้นหา เลือก และเปิดรายละเอียด | Library, Import, Theme Store |
| Evidence | แสดงผลที่ตรวจสอบได้และคำแนะนำ | Home, Progress, Result, Weakness |
| Setup | กรอกหรือตัดสินใจทีละกลุ่ม | Login, Onboarding, Settings, Consent |

## Design foundations

- แนวทาง: **Calm Journey / Evidence Trail**
- ฟอนต์: Noto Sans Thai; น้ำหนัก 400, 500, 700, 800
- สีหลัก: Primary `#5A4CF2`, Mastery `#0E8176`, Momentum accent `#D98213`, Error `#B3261E`
- สีข้อความบนพื้นอ่อนของ Momentum ใช้ `#6B3E00` เพื่อรักษา contrast
- Canvas `#F5F6FA`, Surface `#FFFFFF`, Ink `#171A2B`, Supporting `#626A80`, Border `#DDE1EC`
- spacing: 4, 8, 12, 16, 20, 24, 32dp
- compact gutter: 16dp ที่ 320dp; 20dp ตั้งแต่ 360–599dp
- radius: field 12dp, button 14dp, grouped surface 16dp; 24dp ใช้เฉพาะ hero/floating surface
- motion: 120/180/240ms และมี Reduce Motion
- touch target Android อย่างน้อย 48×48dp; ระหว่าง target อย่างน้อย 8dp

## Component inventory

Base components: Button, Icon button, Top app bar, NavigationBar/Rail, Text/Password/Search field, Composer, Choice/Answer row, List/Setting row, Chip, Switch, Progress/Stepper, Snackbar, Banner, Dialog, Bottom sheet และ Loading/Empty/Error/Offline panel

Product components: TodayNextAction, RecommendationReason, LearningPathNode, DueVocabularyQueue, VocabularyRow, ImportPreviewRow, PracticeProgress, SavedFeedbackPanel, ResultEvidenceSummary, WeaknessRecommendation, SourceContextCard, TutorBubble, TutorComposer, FeatureAvailability, ThemeTile, ThemePreview, PurchaseState และ Sync/OfflineStatus

ทุก control มี state ที่เกี่ยวข้องจาก `default / pressed / focused / selected / disabled / loading / success / error / offline / limited` โดยไม่เปลี่ยนขนาด layout ระหว่าง state

## ภาษาในผลิตภัณฑ์

| ใช้ | ไม่ใช้กับผู้ใช้ทั่วไป |
| --- | --- |
| เลือกวิธีฝึก | Activity Catalog |
| คำที่ควรฝึกเพิ่ม | Weakness Clinic |
| แข่งกับผลงานครั้งก่อน | Ghost Duel |
| ฟังแล้วพูดตาม | Shadowing |
| ผู้ช่วยฝึกภาษาอังกฤษ | AI Tutor / Gemini Tutor |
| ช่วยฉันคิดทีละขั้น | Socratic Mode |
| อธิบายให้เลย | Solver Mode |
| ความก้าวหน้าจากการฝึก | Mastery Dashboard |
| แลกด้วยคะแนน | Purchase |

## Authority per interaction

```text
Import preview --Confirm--> ImportVocabulary --> Drift/owner-scoped persistence
Practice answer --Save--> LearningUseCases.recordAnswer --> Feedback --> Result/Weakness
AI question --> GeminiTutorUseCases --> Reply/provenance --> Optional practice action
Theme redeem/equip --> RewardUseCases --> Durable cosmetic state
```

Preview, hint, selection และ navigation ไม่เขียน mastery/reward การเปิดเฉลยบันทึกผิดได้หนึ่งครั้งด้วย attempt identity เดิม

## Responsive contract

- Compact `<600dp`: single pane + NavigationBar
- Medium `600–839dp`: NavigationRail + focused pane
- Expanded `840–1199dp`: list-detail เมื่อ list ≥320dp และ detail ≥480dp
- Large `1200–1599dp`: shell ≤1200dp
- Height `<480dp`: single/focused pane
- ตรวจ 320×720, 360×800, 393×876, 412×915, 800×360, 600×960, 700×1000, 840×1200, 1024×1366, 1280×800 และ 540×720
- Resize/rotate/fold รักษา route, tab, selection, scroll, draft และ session ตาม lifecycle contract

## Prototype journeys

1. Login/Guest → เรียน → Quiz → Saved feedback → Result → ฝึกคำที่พลาด
2. คลังคำ → หมวด → เพิ่มหรือนำเข้า → Preview/Edit → Confirm → เริ่มฝึก
3. เลือกชุดฝึก → ตั้งค่ารอบ → Preview → ฝึก → Feedback
4. ผู้ช่วยฝึกภาษาอังกฤษ → เลือกข้อมูล → เลือกวิธีช่วย → ถาม → ตรวจข้อมูล → ฝึกต่อ
5. ก้าวหน้า → คำที่ควรฝึกเพิ่ม → ฝึกซ่อม → Evidence updated
6. ก้าวหน้า → ร้านธีม → Preview → แลก → ใช้งาน → กลับบริบทเดิม
7. โปรไฟล์ → ตั้งค่า/สิทธิ/ส่งออก/งานวิจัย → กลับ
8. Responsive/Back/IME/state restoration

## Figma acceptance

- Page เดียว แบ่ง Foundations, Components, Archetypes, Flows, Responsive, States และ QA Evidence
- ทุก control ที่ดู active มี destination/state หรือ disabled reason
- ไม่มี dead interaction, broken destination, accidental self-loop หรือ overflow
- primary action เดียวต่อ viewport
- text scale 100/130/200%, light/dark, keyboard, safe area และ reduced motion มี specimen
- ทุก frame/action map กลับ `route → authority → f01–f44 → acceptance`
- แยกสถานะ `DESIGNED / IMPLEMENTED / VERIFIED / RELEASE-READY`

## สิ่งที่ตัดออกจากรอบนี้

Bottom navigation 6 จุดหมาย, duplicate drawer/FAB, multi-subject, school/national-exam flow, readiness claim ที่ไม่มีสูตร, PDF/OCR, 3D, podcast, cross-device handoff, learning-world hardcode, provider name ใน copy หลัก และ authority ชุดใหม่

## ลำดับหลัง Figma

I0 source snapshot → I1 CSV/JSON Import → I2 four-destination shell → I3 durable feedback → I4 TXT/Markdown source-to-practice → I5 Socratic Messenger tutor → I6 theme marketplace → I7 responsive/device verification → I8 PDF/OCR go/no-go spike
