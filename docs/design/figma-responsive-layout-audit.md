# LexiQuest Figma Page 1: responsive layout audit

วันที่ตรวจ: 2026-10-18
ขอบเขต: Android-first สำหรับโทรศัพท์ Android, foldable และ tablet เท่านั้น ส่วน iOS เป็นงานอนาคต
สถานะ: ข้อกำหนดสำหรับออกแบบ Figma Page เดียวและสร้าง clickable wireframe prototype; ยังไม่ใช่หลักฐานว่า Flutter implementation รองรับทุกขนาดแล้ว

## ข้อสรุปที่ต้องใช้ตัดสินใจ

Figma Page 1 ต้องใช้ **available window size** เป็นตัวตัดสิน layout ไม่ใช้ชื่ออุปกรณ์หรือ orientation โดยตรง และต้องมีระบบเดียวที่เปลี่ยนจาก single pane ไปเป็น rail/two-pane ตามพื้นที่จริง การนำเสนอเดิมดีขึ้นจาก Revision 2 แล้ว แต่ยังเป็นชุด mockup โทรศัพท์ขนาดคงที่ จึงยังตรวจ adaptive behavior ไม่ได้

โครงหลักที่อนุมัติสำหรับงานออกแบบ:

- ปลายทางหลัก 4 รายการ: `เรียน`, `คลังคำ`, `ก้าวหน้า`, `โปรไฟล์`
- Compact ใช้ NavigationBar และ single pane
- Medium ใช้ NavigationRail แต่ยังคง single pane เป็นค่าเริ่มต้น
- Expanded ขึ้นไปใช้ NavigationRail และ list-detail/supporting pane เมื่อความสูงเพียงพอ
- ถ้าความสูงต่ำกว่า 480dp ให้กลับเป็น single pane และ navigation ด้านล่าง แม้ความกว้างจะถึง medium
- ความกว้างเนื้อหาหลักไม่ยืดตามจอแบบไร้ขอบเขต: practice/hub 720dp, form 560dp, prose 640dp และ shell รวม 1,200dp
- รองรับข้อความไทยที่ text scale 200%, safe area, IME/keyboard, split screen, การพับ/กาง และแนวตั้ง/แนวนอนโดยไม่เปลี่ยน route หรือทำ state หาย

## หลักฐานและข้อจำกัด

1. หลักฐาน REA ของ Duolingo และ AllTCAS ยืนยัน path-first, question/feedback, action ด้านล่าง และการทำงานทีละข้อ ส่วน Astra ยืนยัน document-to-plan และ progressive onboarding (`docs/research/2026-10-18-duolingo-astra-alltcas-layout-synthesis.md:8-22`, `:24-39`)
2. ลำดับผลิตภัณฑ์ที่ควรรักษาคือ `บริบท → งานถัดไป → ลงมือ → ผลตอบกลับ → ขั้นถัดไป` และหนึ่ง viewport มี headline/primary action เด่นอย่างละหนึ่ง (`docs/research/2026-10-18-duolingo-astra-alltcas-layout-synthesis.md:26-33`, `:59-65`; `DESIGN.md:5-15`)
3. Design contract ระบุ compact เป็น single pane พร้อม NavigationBar 4 จุดหมาย และ expanded เป็น NavigationRail พร้อม pane เสริม (`DESIGN.md:17-25`)
4. Design system กำหนด Noto Sans Thai, 4/8dp rhythm, touch target 48dp, system text scaling และ safe area (`design-system/lexiquest/MASTER.md:3-7`, `:57-84`, `:86-115`, `:146-158`)
5. หลักฐานคู่แข่งใช้เพื่ออนุมานลำดับและสัดส่วนเท่านั้น ห้ามคัดลอกภาพ โลโก้ ข้อความ หรือกลไกเฉพาะ (`DESIGN.md:60-64`)
6. Astra เป็นหลักฐานจาก public flow/onboarding ไม่ใช่ APK บนมือถือ และไม่ได้ยืนยันว่าทุกฟีเจอร์เปิดในทุกบัญชี (`docs/research/2026-10-18-duolingo-astra-alltcas-layout-synthesis.md:12-20`)

แหล่งอ้างอิงแพลตฟอร์มที่ใช้กำหนดตัวเลข:

- [Android window size classes](https://developer.android.com/develop/adaptive-apps/guides/use-window-size-classes): compact `<600dp`, medium `600–839dp`, expanded `840–1199dp`, large `1200–1599dp`; height compact `<480dp`, medium `480–899dp`, expanded `≥900dp`
- [Android adaptive navigation](https://developer.android.com/develop/adaptive-apps/guides/build-adaptive-navigation): navigation bar เมื่อ width หรือ height เป็น compact และ navigation rail ในพื้นที่อื่นโดยค่าเริ่มต้น
- [Android responsive navigation](https://developer.android.com/develop/ui/views/layout/build-responsive-navigation): bottom bar สำหรับ compact, rail สำหรับ medium และ rail/drawer สำหรับ expanded ตามจำนวนปลายทาง
- [Flutter adaptive best practices](https://docs.flutter.dev/ui/adaptive-responsive/best-practices): อย่าล็อก orientation และอย่าใช้ orientation/device type แทน available constraints
- [Flutter SafeArea & MediaQuery](https://docs.flutter.dev/ui/adaptive-responsive/safearea-mediaquery): SafeArea ป้องกัน cutout/system UI และ MediaQuery ให้ข้อมูล text scaling, padding, hinge/fold
- [Flutter large screens](https://docs.flutter.dev/ui/adaptive-responsive/large-screens): จำกัดความกว้างข้อความ/กล่อง และกำหนดจำนวนคอลัมน์จาก window width

## Audit ของสัดส่วนเดิม

### สิ่งที่ควรรักษา

- Revision 3 แก้ปัญหา Revision 2 ที่ใช้คอลัมน์คำอธิบายคงที่ 400px จนพื้นที่ตรวจมือถือเล็กและเกิดจุดศูนย์ถ่วงสองจุดแล้ว (`docs/research/2026-10-18-duolingo-astra-alltcas-layout-synthesis.md:78-89`)
- ลำดับ task-first, feedback ในบริบทเดิม, primary action เดียว และ evidence strip ทำให้เหตุผลของแต่ละหน้าตรวจสอบได้
- Mockup โทรศัพท์ 328×728 มีอัตราส่วนใกล้ 360×800 จึงใช้เป็น baseline เชิงภาพได้ (`docs/design/lexiquest-canva-master-ui.html:65-76`)

### จุดที่ยังไม่ผ่านสำหรับ adaptive UI

1. **ขนาด mockup ยังตายตัว** — บอร์ดใช้โทรศัพท์ 328×728 หรือ 292×662 และมี expanded ตัวอย่างเดียวขนาด 650×520 (`docs/design/lexiquest-canva-master-ui.html:65-76`, `:259-261`) จึงยังพิสูจน์ไม่ได้ว่า layout ทำงานที่ 320, 412, 600, 840 และ 1,280dp
2. **เปอร์เซ็นต์แนวตั้งไม่ควรเป็น fixed height** — สัดส่วน hub `10/34/42/14` และ practice `10/64/16/10` ใช้เป็น visual target ที่ 360×800 ได้ แต่ต้องยอมให้เนื้อหาโต/เลื่อนเมื่อภาษาไทยยาว, จอแนวนอน หรือ text scale 200% (`DESIGN.md:23-24`) มิฉะนั้น CTA/feedback จะทับเนื้อหา
3. **fixed bottom elements เสี่ยงบังเนื้อหา** — static board ใช้ `.screen { overflow: hidden }` และ `.bottomnav { position:absolute; height:70px }` (`docs/design/lexiquest-canva-master-ui.html:76`, `:139-140`) Figma prototype ต้องมี scroll content inset เท่ากับ nav/CTA + safe area และมี IME state แยก
4. **navigation ปัจจุบันขัดกับ contract** — Flutter สามารถสร้าง top-level destinations ได้ถึง 6 รายการ (`lib/screens/main_navigation_screen.dart:61-106`) แต่แสดง NavigationBar เดียวทุกขนาด (`lib/screens/main_navigation_screen.dart:140-156`, `:270-285`) ขณะที่ contract ระบุ 4 รายการ Weakness ต้องอยู่ใต้ Learn และ Achievements/Rewards อยู่ใต้ Progress/Profile
5. **ยังไม่มี adaptive switch ในโค้ดหลัก** — การค้นใน `lib/` ไม่พบ `LayoutBuilder`, `NavigationRail`, `MediaQuery.sizeOf` หรือ `OrientationBuilder`; ดังนั้น rail/two-pane ในบอร์ดยังเป็น design intent ไม่ใช่ behavior ที่ยืนยันจาก implementation
6. **spacing ปัจจุบันเอนเอียงไปที่ 16dp ทุกขนาด** — ตัวอย่าง Learning hub, Quiz และ dashboard ใช้ `EdgeInsets.all(16)` (`lib/screens/choose_mode_screen.dart:52-63`, `lib/screens/quiz_screen.dart:87-106`, `lib/screens/mastery_dashboard_screen.dart:66-70`) แต่ contract ใหม่ต้องเพิ่ม gutter ตาม window width
7. **grid ยังไม่ adaptive** — Phonetic Explorer ล็อก `crossAxisCount: 2` และ `childAspectRatio: 1.1` (`lib/screens/phonetic_explorer_screen.dart:133-141`); dashboard card ล็อกกว้าง 150dp (`lib/screens/mastery_dashboard_screen.dart:111-134`) จึงอาจแคบ/โล่งเกินไปเมื่อ split screen หรือ tablet
8. **หลักฐานทดสอบยังแคบ** — learning flow/golden ตรวจเพียง 360×800 ที่ text scale 1.8 (`test/screens/learning_loop_layout_test.dart:20-39`) และ Quiz ใช้เงื่อนไขเดียวกัน (`test/screens/quiz_screen_test.dart:172-201`) ส่วน auth ตรวจ 360×800 ที่ 200% (`test/screens/accessibility_smoke_test.dart:8-43`) ยังไม่มี breakpoint-edge, landscape, hinge หรือ IME assertion

## Responsive contract สำหรับ Figma Page 1

### 1. Breakpoint และพฤติกรรม

| Window class | ช่วงความกว้าง | โครงเนื้อหา | Navigation | Gutter | คอลัมน์ |
| --- | ---: | --- | --- | ---: | ---: |
| Compact | `<600dp` | single pane; secondary content ต่อท้ายใน scroll | NavigationBar 4 รายการ | 16dp ที่ 320–359; 20dp ที่ 360–599 | 4 |
| Medium | `600–839dp` | single pane ที่จัดกลาง; card/grid ขยายได้ 2 คอลัมน์ | NavigationRail แบบ icon+label | 24dp | 8 |
| Expanded | `840–1199dp` | list-detail/supporting pane เมื่อ height ≥480dp | NavigationRail | 32dp | 12 |
| Large | `1200–1599dp` | two-pane ภายใน shell สูงสุด 1,200dp; เพิ่ม whitespace แทนยืดข้อความ | NavigationRail หรือ persistent drawerเมื่อรายการรองจำเป็น | 48dp | 12 |

`480dp` ภายในกลุ่ม compact เป็นเพียงจุดปรับ gutter/density สำหรับ large phone ไม่ใช่ window class ใหม่และห้ามใช้ตรวจว่าเป็น “tablet”

### 2. Height class และ orientation

| Height | กฎ |
| --- | --- |
| `<480dp` compact height | single pane เสมอ, ลด app bar/section gaps หนึ่งระดับ, NavigationBar ด้านล่าง, content เลื่อนแนวตั้ง และ CTA ไม่ตรึงทับโจทย์ |
| `480–899dp` medium height | ใช้กฎตาม width; two-pane ได้ตั้งแต่ expanded width เมื่อแต่ละ pane ผ่าน minimum width |
| `≥900dp` expanded height | แสดง supporting pane และ context ต่อเนื่องได้ แต่ primary task ยังเด่นเพียงหนึ่งงาน |

- ห้ามล็อกแนวตั้งและห้าม branch ด้วย `OrientationBuilder` ที่ root
- หมุนจอ, split screen หรือพับ/กางแล้วอยู่ route เดิม รักษา selected tab, scroll, input และ progress
- phone landscape เช่น 800×360 ใช้ compact-height single pane แม้ width เป็น medium
- foldable/tablet landscape ใช้ two-pane เมื่อ usable width หลังหัก hinge/gap ยังเหลือ list ≥320dp และ detail ≥480dp

### 3. Grid และความกว้างเนื้อหา

- ใช้ baseline 4dp และ rhythm หลัก 8dp; component gap `8/12/16`, section gap `24/32`, page gap `32/48`
- Compact: 4 columns, gap 12–16dp; card และ CTA กว้างเต็ม content column
- Medium: 8 columns, gap 16–24dp; single task column กว้างไม่เกิน 720dp และจัดกลาง
- Expanded/Large: 12 columns, gap 24dp; list 320–360dp, pane gap 24–32dp, detail 480–720dp
- Max widths:
  - form/onboarding/settings editor: `560dp`
  - paragraph/reading copy: `640dp` หรือประมาณ 60–75 ตัวอักษรต่อบรรทัด
  - practice/hub/detail: `720dp`
  - chat/tutor transcript: `760dp`
  - app shell รวม: `1,200dp`
- Grid cards ใช้ max cross-axis extent แทนจำนวนคอลัมน์ที่ผูกกับชื่ออุปกรณ์: learning tiles 280–360dp, metric cards 160–220dp

### 4. Navigation และ information architecture

- Primary destinations 4 รายการคงที่ทุก breakpoint: Learn, Library, Progress, Profile; มี icon+label และ selected state
- AI Tutor, Quiz, SRS, Weakness Clinic, Scan, Speech และ Ghost Duel เป็น child route ใต้ Learn
- Achievement/Reward เป็นส่วนรองใต้ Progress หรือ Profile; Settings, BYOK, Export และ permission controls อยู่ใต้ Profile/secondary drawer
- เปลี่ยน NavigationBar ↔ NavigationRail โดยเปลี่ยน shell layout ไม่ navigate ไป route ใหม่
- Back ต้องคืนหน้าก่อนหน้าและรักษา state; prototype ทุก flow มีทางออกจาก dialog/sheet
- ปุ่ม/พื้นที่กดทุกชนิดขั้นต่ำ 48×48dp และห่างกันอย่างน้อย 8dp

### 5. Pattern ต่อหน้าหลัก

| Pattern | Compact/large phone | Medium | Expanded/foldable/tablet |
| --- | --- | --- | --- |
| Learning hub | next action → context → secondary activities | rail + centered single column; activity grid 2 columnsได้ | rail + route/list ซ้าย, next action/detail ขวา |
| Quiz/SRS | progress → prompt → choices → inline feedback → CTA; ทั้งหมด scroll ได้ | centered practice column max 720 | prompt/detail pane + contextual explanation pane; ไม่แยก answer stateคนละ route |
| Vocabulary | search/filter → list → detailเป็น route | rail + centered list/grid | list-detail; selected word คงอยู่เมื่อ resize |
| Progress | evidence summary → skill rows → recommendation | metric grid 2–3 columns | summary/supporting pane; chart มี text/table equivalent |
| AI Tutor | context source → question → messages → composer | centered transcript | source/outline ซ้าย + transcript ขวา; quota/consent stateยังเห็นได้ |
| Settings | section list → detail route | section list single pane | list-detail; destructive/data actionsแยกจาก settings ปกติ |

### 6. Typography และ text scaling

- Noto Sans Thai Variable, weights 400/500/700/800; ไม่ใช้ negative letter spacing กับภาษาไทย
- Screen task 24–32sp, title 20–24sp, body 15–17sp, meta 12–14sp ตาม `DESIGN.md:27-39`
- ทุก text container ใช้ Auto Layout + Hug contents; ความสูงปุ่ม 48–52dp เป็น **minimum** ไม่ใช่ fixed
- สร้าง Figma variants ที่ 100%, 130% และ 200%; ที่ 200% label/prompt ต้อง wrap, card ต้องสูงขึ้น, CTA ต้องยังเข้าถึงได้ และไม่มี ellipsis กับข้อความสำคัญ
- Phone line measure 35–60 ตัวอักษร; tablet/prose 60–75 ตัวอักษร ห้ามปล่อย paragraph เต็ม 1,200dp
- สีไม่ใช่สัญญาณเดียว; success/error/selected ต้องมี icon/shape/text และ contrast body text อย่างน้อย 4.5:1

### 7. Safe area, system UI และ keyboard

- background สามารถ edge-to-edge ได้ แต่ app bar, controls, labels และ CTA ต้องอยู่หลัง top/bottom/left/right insets
- scroll content bottom padding = ความสูง NavigationBar/CTA + system bottom inset + 16dp; ห้ามให้รายการสุดท้ายซ่อนหลัง fixed UI
- fold/hinge/cutout เป็น `display feature exclusion zone`: ไม่วาง text, CTA, dialog center หรือ selection control คร่อมรอยพับ
- เมื่อ IME เปิด ให้ viewport resize, focused field เลื่อนมองเห็น, label/error/helper text ไม่ถูกบัง และ primary submit อยู่เหนือ IMEหรือเลื่อนถึงได้
- composer ของ AI Tutor เป็น bottom region ที่ยกตาม `viewInsets.bottom`; transcript รักษาตำแหน่งการอ่านและไม่ถูก keyboard ทับ
- Figma ต้องมี state `IME open` อย่างน้อย Login/Register, Add word, AI Tutor และ Search; ใช้ keyboard mock สูง 300–340dp เพื่อ stress test แต่ acceptance อิง “ไม่บัง” ไม่อิงความสูงตายตัว

### 8. Foldable-specific

- ใช้ available pane bounds หลังหัก hinge ไม่ใช้ความกว้างจอรวม
- vertical hinge: list อยู่ pane ฝั่งหนึ่ง, detail อีกฝั่ง; rail อยู่ขอบนอกและไม่มี control คร่อม hinge
- tabletop/horizontal hinge หรือ height compact: กลับ single pane + bottom navigation; ห้ามบังคับ two-pane
- เมื่อ fold/unfold ต้องไม่สร้าง destination ใหม่ ไม่ reset session และไม่ส่งคำตอบซ้ำ

## โครงสร้าง Figma Page เดียว

ชื่อ Page: `01 · LexiQuest Android · Responsive Prototype`

จัดเป็น Sections ในหน้าเดียวตามลำดับซ้ายไปขวา:

1. `00 Evidence & Rules` — rhythm, breakpoint table, REA provenance และข้อจำกัด
2. `01 Foundations` — color/type/spacing/elevation/motion/safe-area variables
3. `02 Components` — app bar, NavigationBar/Rail, CTA, list tile, card, input, chip, feedback, dialog/sheet พร้อม states และ 100/200% text variants
4. `03 Responsive Shells` — 320, 360, 412, 600, 840, 1,280, compact-height landscape และ fold/hinge frames
5. `04 Main Flows` — onboarding/auth, home/learn, library, quiz/feedback/score, progress, AI tutor และ settings
6. `05 System States` — loading, empty, error, offline, permission denied, quota, IME open, dark mode และ reduced motion
7. `06 Prototype Map` — starting points และลูกศร flow; ใช้ component instances เดียวกับ frames จริง

ทุก frame ใช้ Auto Layout, variables และ component instances; ห้ามใช้ screenshot flatten เป็นหน้าจอหลักของ prototype

## Acceptance checks สำหรับ Figma Page 1

### Frame matrix

- [ ] 320×720 compact small phone portrait
- [ ] 360×800 compact baseline portrait
- [ ] 412×915 large phone portrait
- [ ] 800×360 compact-height phone landscape
- [ ] 600×960 medium portrait
- [ ] 840×1,200 expanded portrait
- [ ] 1,280×800 Android tablet landscape
- [ ] foldable spanned frame ที่มี vertical hinge exclusion zone
- [ ] 540×720 split-screen frame ซึ่ง reflow กลับเป็น compact

### Layout behavior

- [ ] ที่ 599/600dp navigation เปลี่ยน bar→rail โดย route/selection ไม่เปลี่ยน
- [ ] ที่ 839/840dp content เปลี่ยน single→two-pane เฉพาะเมื่อ height ≥480dp
- [ ] ที่ height 479/480dp ไม่มี CTA, prompt หรือ feedback ถูกตัด
- [ ] ทุกหน้าจัดอยู่บน 4/8dp grid และ gutter ตรงตาม class
- [ ] content widths ไม่เกิน form 560, prose 640, task 720, tutor 760 และ shell 1,200dp
- [ ] ไม่มี horizontal scroll ที่ 320dp หรือ split-screen 540dp
- [ ] scrollable content มี inset พ้น bottom navigation/fixed CTA/system bar
- [ ] ไม่มี element สำคัญคร่อม hinge/cutout

### Typography/accessibility

- [ ] Noto Sans Thai โหลดครบ; ไม่มี negative letter spacing
- [ ] ทดสอบทุก main flow ที่ text scale 100% และ 200%; ไม่มี clipped text, overflow, ellipsis ของข้อความสำคัญ หรือ fixed-height collision
- [ ] touch targets ≥48×48dp และห่าง ≥8dp
- [ ] body text contrast ≥4.5:1; control/icon boundary ≥3:1; สถานะไม่พึ่งสีอย่างเดียว
- [ ] screen-reader order ตาม visual order และ icon-only controls มีชื่อ
- [ ] dark mode และ reduced-motion variants ใช้ token เดียวกับ light/default

### Keyboard/system state

- [ ] Login/Register/Add word/Search/AI Tutor มี IME-open frame
- [ ] focused field, label, error/helper และ submit/composer มองเห็นหรือ scroll ถึงได้
- [ ] keyboard ไม่ทับ bottom sheet, feedback หรือ navigation action
- [ ] rotate/split/fold แล้วรักษา selected tab, scroll, typed text และ quiz progress

### Prototype wiring

- [ ] Start point: Login/Guest → Learn/Home
- [ ] Bottom bar/rail ทั้ง 4 จุดหมายเชื่อมถึงกันและ active stateถูกต้อง
- [ ] Learn → recommended activity → Quiz → answer → saved feedback → next/score → weakness practice
- [ ] Library → category → word detail → practice
- [ ] Progress → evidence detail → recommended action
- [ ] Profile → Settings → Appearance/Permission/AI BYOK/Export
- [ ] Back, close, cancel, retry, permission denied และ offline recovery มีปลายทางครบ ไม่มี dead end

### Visual-quality lint เพื่อลดลักษณะ “AI template”

ไม่ควรใช้ตัวตรวจที่อ้างว่าบอกได้แน่นอนว่า UI “สร้างด้วย AI” เพราะไม่มี metric ที่เชื่อถือได้ ให้ใช้กฎที่วัดได้แทน:

- [ ] หนึ่ง viewport มี primary CTA เดียว
- [ ] ไม่มี emoji เป็น structural icon และใช้ icon family/stroke เดียว
- [ ] ไม่มี gradient/เงา/แก้วที่ไม่มีหน้าที่สื่อ hierarchy
- [ ] card ใช้เฉพาะการจัดกลุ่มเชิงความหมาย ไม่ห่อทุกข้อความ
- [ ] pill/chip ใช้เฉพาะ metadata/filter/status ไม่ใช้กับทุก control
- [ ] ไม่มี spacing นอก token 4/8dp โดยไม่มีเหตุผล
- [ ] ไม่มีข้อความในกล่อง fixed-height และไม่มี layout-shifting pressed state
- [ ] แต่ละหน้ามี hierarchy ต่างตามงานจริง ไม่ใช้ hero + 3 equal cards ซ้ำทุกหน้า

## Disposition ต่อ implementation ปัจจุบัน

- `accepted`: task-first learning loop, one-question flow, inline saved feedback, SafeArea ใน Quiz, 52dp answer buttons (`lib/screens/quiz_screen.dart:87-178`)
- `accepted with evidence gap`: compact large-text tests; ผ่านเฉพาะ 360×800 ที่ 1.8 และ auth 2.0
- `must-fix before Android adaptive claim`: adaptive app shell, 4-primary-destination IA, NavigationRail, max-width containers, adaptive grids, breakpoint/landscape/fold/IME tests
- `not verified`: อุปกรณ์ foldable จริง, hardware keyboard, gesture navigation insets และ physical-device rendering; Figma/Flutter emulator evidence ไม่แทนผลทดสอบอุปกรณ์จริง
