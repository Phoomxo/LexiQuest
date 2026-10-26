# LexiQuest AI-looking / visual-quality audit

วันที่ตรวจ: 2026-10-18
เป้าหมาย: `docs/design/lexiquest-canva-master-ui.html`
สถานะ: **ต้องแก้ P1 ก่อนใช้เป็นฐาน Figma prototype**

## คำตัดสิน

งานปัจจุบันมีทิศทางผลิตภัณฑ์ที่ถูกต้อง: ลำดับงานเรียนชัด สี mastery/momentum/error แยกบทบาท และหน้าสำคัญครอบคลุมตั้งแต่ onboarding ถึง error/offline state แต่ยังดูเหมือนชุด mockup ที่สร้างจาก template มากกว่าระบบผลิตภัณฑ์เดียวกัน เพราะใช้ card/chip/ปุ่มซ้ำเป็นคำตอบของหลายบริบท มีค่า spacing/type แบบปรับเฉพาะจุดจำนวนมาก และยังไม่มีหลักฐาน responsive สำหรับ tablet/foldable

สคริปต์ให้ **design-drift risk 84/100 (very-high)** จาก 10 findings: P1 จำนวน 3 ข้อ และ P2 จำนวน 7 ข้อ คะแนนนี้ไม่ใช่ความน่าจะเป็นว่า AI เป็นผู้สร้าง ไม่มีวิธีที่น่าเชื่อถือในการพิสูจน์ผู้สร้างจากหน้าตาเพียงอย่างเดียว ตัวเลขนี้วัดสัญญาณที่ตรวจซ้ำได้ซึ่งมักทำให้งานดู generic หรือไม่ผ่าน design system เท่านั้น

## ขอบเขตและหลักฐาน

ตรวจจาก:

- `DESIGN.md`: Calm Learning UI, 4 จุดหมายหลัก, 48dp touch target, type roles และจังหวะ `บริบท → งานถัดไป → ลงมือ → ผลตอบกลับ → ขั้นถัดไป`
- `design-system/lexiquest/MASTER.md`: semantic tokens, 4/8dp grid, card/chip constraints, Android-first และ checklist การส่งมอบ
- `docs/research/2026-10-18-duolingo-astra-alltcas-layout-synthesis.md`: REA runtime evidence ของ Duolingo/AllTCAS, Astra public/onboarding flow และ Android adaptive guidance
- `docs/design/lexiquest-canva-master-ui.html`: 22 boards, 66 mobile screens และ component/CSS implementation ของ Revision 3
- `tmp/pdfs/render-r3.mjs`: ตรวจจำนวน 22 หน้าและ page overflow ตอน render; สคริปต์นี้เก็บ `screenOverflow` แต่ยังไม่ได้ fail เมื่อพบ screen overflow

ไม่ใช้คะแนนทางการตลาดของแอปต้นแบบเป็นหลักฐานประสิทธิผล และไม่ได้อนุมานโค้ด backend, recommendation model หรือทรัพย์สินของคู่แข่ง

## ภาพรวมเชิงตัวเลข

| ตัวชี้วัด | ผล |
| --- | ---: |
| Design boards | 22 |
| Mobile screen mockups | 66 |
| `.card` | 109 |
| `.chip` | 58 |
| `.btn` | 80 |
| Inline `style` attributes | 120 |
| Responsive media queries | 0 (มีเพียง `print`) |
| Spacing declarations ที่หลุดกริด 4dp | 45 |
| DOM card ซ้อน card | 0 |

คู่สีข้อความหลักที่ตรวจได้ผ่าน WCAG AA 4.5:1 ทั้งหมด:

| คู่สี | Contrast |
| --- | ---: |
| Ink / background | 14.53:1 |
| Muted / background | 5.64:1 |
| Muted / surface | 6.09:1 |
| Surface / primary | 6.27:1 |
| Surface / mastery | 5.48:1 |
| Error / error-soft | 5.00:1 |

## Findings ตามลำดับความสำคัญ

### P1 — ต้องแก้ก่อนสร้าง prototype รอบตรวจรับ

#### 1. ไม่มี responsive contract ที่ตรวจได้ (`RSP-001`)

HTML มี mockup มือถือ 66 หน้าจอ แต่ CSS มีเพียง `@media print` ไม่มี compact/medium/expanded breakpoint และไม่มีกฎที่เปลี่ยน NavigationBar เป็น NavigationRail ตามความกว้าง จึงยังพิสูจน์ไม่ได้ว่า Android tablet, foldable หรือหน้าต่างแบบ resize ใช้งานได้จริง

ให้สร้าง frame ตรวจรับอย่างน้อย:

- Compact: 360×800 และ 412×915, single pane + NavigationBar
- Medium: 600–839dp, single pane ที่ขยายระยะและจำกัด content width; ใช้ rail เมื่อพื้นที่และบริบทเหมาะ
- Expanded: ตั้งแต่ 840dp, NavigationRail + list-detail/supporting pane โดยจำกัดเนื้อหาหลักไม่เกิน 1,200dp
- Landscape และ IME/keyboard state สำหรับ Practice, Search, Add word และ AI prompt

ไม่ควรยืด phone canvas ให้กว้างขึ้นทั้งหน้า แต่ต้องเลือก canonical layout ตามงาน: Focus สำหรับ Practice, Browse/List-detail สำหรับ Library และ Evidence/Supporting pane สำหรับ Progress

#### 2. Touch target ต่ำกว่า 48dp (`A11Y-001`, `A11Y-002`)

จุดที่ตรวจพบ:

- `.back` และ `.round-icon` = 44×44px
- `.switch` visual bounds = 42×24px โดยไม่มี wrapper hit area ให้ตรวจ
- ปุ่มซื้อสองจุดที่บรรทัด 396 override เป็น `min-height:40px`
- `.navitem` ไม่มี `min-height/min-width` ให้ยืนยันพื้นที่กด

แก้ทุก interactive component ให้ hit area อย่างน้อย 48×48dp และห่างกันอย่างน้อย 8dp ตัว switch และ icon อาจคงรูปทรงเดิมได้ แต่ต้องอยู่ใน wrapper 48dp ที่เห็น focus/pressed state ชัด

#### 3. Navigation label ต่ำกว่า type floor (`TYPE-001`)

`.navitem` ใช้ 11.5px ต่ำกว่าขั้นต่ำ 12sp ใน design contract และต่ำเกินไปสำหรับภาษาไทยเมื่ออยู่ใต้ไอคอน ยกเป็น 12–14sp และทดสอบ system font scale 200% โดยห้ามซ่อน label หรือตัดข้อความ

### P2 — แก้เพื่อให้ระบบดูตั้งใจและลดความเป็น template

#### 4. Semantic token ใช้ชื่อไม่ตรงกัน (`TOK-001`)

HTML ใช้ `--teal`, `--amber`, `--bg`, `--line` แทน `--mastery`, `--momentum`, `--background`, `--border` แม้ค่าสีถูกต้อง การใช้ชื่อจากหน้าตาสีทำให้ความหมายหลุดเมื่อย้ายไป Figma variables และ Flutter `ColorScheme`

ให้มี canonical token ชุดเดียว แล้วค่อย map platform alias ภายใน adapter:

```text
mastery / mastery-soft
momentum / momentum-soft
background / surface / border
primary / error / ink / muted
```

#### 5. Type scale แตกเป็นค่าครึ่งพิกเซล (`TYPE-002`)

พบ 11.5, 13.5 และ 14.5px ใน `.navitem`, `.sub`, `.section-label`, `.label` และ `.btn` ลักษณะนี้ทำให้แต่ละหน้าดู “ปรับด้วยตา” แทนการใช้ role ที่ชัด

ยุบเป็นสี่ role ของหน้าจอ:

- Task/Prompt 24–32sp, 700–800
- Screen title 20–24sp, 700
- Body 15–17sp, 400–600
- Meta/Label 12–14sp, 500–700

#### 6. Spacing หลุดกริด 4dp (`SPACE-001`)

พบ 45 declarations เช่น screen bottom padding 82px, status margin 18px, card padding 14px/margin 10px, row gap 10px, button horizontal padding 18px และ input padding 13/14px ความต่างเล็ก ๆ จำนวนมากทำให้ baseline และแนวขอบไม่ตรงกัน

ให้แทนด้วย `space-1…space-6` (4, 8, 12, 16, 24, 32) และอนุญาต 20dp เฉพาะ screen margin ตาม contract ระยะระหว่างหัวข้อกับกลุ่มถัดไปต้องมากกว่าระยะภายในกลุ่มเสมอ

#### 7. Container/chip/action density สูงในบางหน้าจอ (`DENS-001`)

ตัวอย่างที่ควรลดก่อน:

- Learning hub บรรทัด 300–301 มี card 5 ใบต่อหน้าจอ
- Curriculum บรรทัด 329 มี surface 7 ชิ้น
- Vocabulary library บรรทัด 279 มี surface 5 ชิ้น
- Quiz, Progress, Reading และ Word games บาง state มี chip ตั้งแต่ 4 ชิ้น
- Word/sentence game บาง state มี action ตั้งแต่ 4 ปุ่ม

หลักแก้คือ “หนึ่งงานเด่น + บริบทรอง” ไม่ใช่ลดข้อมูลทั้งหมด:

- ใช้ whitespace/divider/list row แทน card ที่มีพื้นขาวเหมือนกัน
- ใช้ chip เฉพาะ filter, metadata และ status สั้น ๆ
- Choice ในเกม/Quiz ใช้รูปแบบ answer row ไม่ใช้ chip เพื่อประหยัดพื้นที่
- หน้าหลักคง primary action หนึ่งจุด และลด secondary action เป็น text/outlined action ตามลำดับ

#### 8. Copy density สูงสามหน้าจอ (`COPY-001`)

- Learning hub บรรทัด 299: 227 ตัวอักษร
- AI Tutor บรรทัด 386: 222 ตัวอักษร
- Research consent บรรทัด 416: 251 ตัวอักษร

ตัวเลขนี้เป็น review threshold ไม่ใช่เกณฑ์ตัดสินคุณภาพภาษา ให้ย้ายคำอธิบายยาวไป progressive disclosure, helper sheet หรือ detail screen แล้วตรวจอีกครั้งที่ 320dp และ text scale 200%

#### 9. Inline overrides ทำให้ component drift (`DRIFT-001`)

พบ inline style 120 จุด โดยใช้ `height` 37, `background` 27, `margin-top` 24, `color` 22, `width` 21 และ `margin` 19 ครั้ง ค่าเหล่านี้ทำให้ component เดียวกันเปลี่ยนรูปแบบตามหน้าและทำให้การแก้ใน Figma/Flutter ไม่ครบทุก state

ให้ย้ายค่าซ้ำไปเป็น component variants เช่น `Card/status`, `Button/size`, `Icon/emphasis`, `Progress/state` เหลือ inline value เฉพาะข้อมูลจริง เช่นเปอร์เซ็นต์ progress/bar height

## เหตุผลที่ภาพรวมยังดู generic

ปัญหาไม่ได้มาจากความเรียบหรือการใช้ Material 3 แต่เกิดจาก “ภาษาภาพหนึ่งคำตอบสำหรับทุกงาน”:

1. card สีขาว radius ใกล้กันถูกใช้กับทั้งข้อมูล, navigation, status, action และคำอธิบาย
2. chip ถูกใช้ทั้ง metadata และสิ่งที่ควรกดเป็นคำตอบ จึงไม่ชัดว่าอะไรเป็น status หรือ action
3. หลายหน้ามี container ที่มีน้ำหนักใกล้กัน ทำให้สายตาไม่รู้ว่าจะเริ่มตรงไหน
4. ค่า 10/13/14/18px และ inline overrides ทำให้แนวขอบ/จังหวะคล้ายกันแต่ไม่ตรงกัน
5. มีหน้าจอมือถือจำนวนมาก แต่ยังไม่มีหลักฐานว่าระบบเลย์เอาต์ปรับตัวเมื่อความกว้างเปลี่ยน

ทิศทางที่ควรรักษาคือ Calm Learning UI, สีเชิงความหมาย, evidence-led learning และ CTA หนึ่งจุด ทิศทางที่ควรตัดคือ card-everywhere, pill-everywhere และ one-off styling

## ข้อกำหนดสำหรับ Figma Revision 4

### Layout archetypes

| Archetype | ใช้กับ | Compact | Expanded |
| --- | --- | --- | --- |
| Focus | Quiz, SRS, Reading, Duel | prompt หนึ่งจุด + fixed action | prompt width จำกัด 560–680dp + supporting evidence pane |
| Browse | Library, Category, Import | list/filter แบบ single pane | list-detail; selection คงอยู่เมื่อ back/resize |
| Evidence | Home, Progress, Weakness | next action ก่อน summary | NavigationRail + main evidence + recommendation pane |
| Setup | Onboarding, Settings, Consent | one question/group per screen | content column 560–720dp; ไม่กระจาย form เต็มจอ |

### Component rules

- สร้าง Figma variables จาก canonical semantic tokens ไม่สร้างสีเฉพาะหน้าซ้ำ
- สร้าง Text Styles สี่ role และห้ามใช้ 11.5/13.5/14.5sp
- สร้าง Auto Layout spacing ด้วย 4/8/12/16/24/32dp
- Card มีเฉพาะ `group`, `selected`, `feedback/floating`; list row ใช้ divider/space
- Button มี `primary`, `tonal`, `outlined`, `text` และ `48/52dp`; ทุก variant มี pressed/focus/disabled/loading
- NavigationBar/NavigationRail ใช้ destination เดียวกันสี่รายการ: เรียน, คลังคำ, ก้าวหน้า, โปรไฟล์

### Prototype acceptance

- ทุก destination หลักเปิดได้จาก NavigationBar/NavigationRail และ active state ถูกต้อง
- ทุก deep screen ใช้ Back แล้วกลับ state/scroll/filter เดิม
- Primary action ทุกหน้าพาไป state ถัดไปจริง; ไม่มีปุ่มตกแต่งที่กดแล้วไม่เกิดอะไร
- Overlay/sheet/dialog มี close, dismiss และ destructive confirmation ที่ชัด
- Phone และ tablet flow ใช้ node เป้าหมายเดียวกัน แต่เปลี่ยนโครงหน้า ไม่ทำ duplicate logic ที่เชื่อมไม่ครบ
- Present mode เดินเส้นทาง Home → Practice → Feedback → Score → Weakness และ Profile → Settings → Appearance/AI/Research/Export ได้ครบ

## สคริปต์ตรวจ

ไฟล์: `tools/design_audit.py`

รันแบบ report-only:

```powershell
py -3 tools\design_audit.py docs\design\lexiquest-canva-master-ui.html
```

ผลปัจจุบัน:

```text
boards/screens: 22/66
cards/chips/buttons: 109/58/80
design-drift risk: 84/100 (very-high)
findings: 10
exit code: 0
```

รัน JSON สำหรับ CI หรือ dashboard:

```powershell
py -3 tools\design_audit.py docs\design\lexiquest-canva-master-ui.html --json
```

หลังแก้ fixture และยืนยันว่า rules ไม่สร้าง false positive แล้ว จึงเปิด strict mode:

```powershell
py -3 tools\design_audit.py docs\design\lexiquest-canva-master-ui.html --strict
```

Strict mode คืน exit code 1 เมื่อมี P0/P1 ปัจจุบันคืน 1 ตามคาด Default ยังเป็น report-only ตาม ADLC เพื่อไม่เปลี่ยน policy ใหม่เป็น blocking gate ก่อนมี fixture ที่เสถียร

## สิ่งที่สคริปต์ยืนยันไม่ได้

ต้องตรวจด้วย Figma Present mode หรือ Android emulator/device เพิ่มเติม:

- ปุ่มทุกปุ่มมี prototype reaction และ target ถูกต้อง
- Auto Layout ไม่ clip เมื่อภาษาไทยยาวหรือ text scale 200%
- safe area, display cutout, system bars และ IME ไม่บัง content/CTA
- system Back/predictive Back และ state restoration ทำงานจริง
- TalkBack order, accessible label, focus/pressed/disabled semantics <!-- gitleaks:allow -->
- dark theme, Dynamic Color และ Reduce Motion บนอุปกรณ์ Android
- ความรู้สึกของ motion, visual balance และความโดดเด่นของ primary action จากภาพ render จริง

## Review disposition

| สถานะ | รายการ |
| --- | --- |
| `must-fix` | RSP-001, A11Y-001, TYPE-001 ก่อน prototype รอบตรวจรับ |
| `follow-up` | TOK-001, A11Y-002, TYPE-002, SPACE-001, DENS-001, COPY-001, DRIFT-001 |
| `accepted` | โครง 22 boards/66 screens, semantic contrast 6 คู่, ไม่มี DOM card ซ้อน card, REA provenance ระบุชัด |
| `not verified` | Figma prototype links, phone/tablet resize, TalkBack, text scale 200%, physical-device behavior |

ลำดับทำงานที่แนะนำ: responsive archetypes → touch/type floor → spacing/tokens → ลด card/chip → เชื่อม prototype → ตรวจ Present mode โทรศัพท์และแท็บเล็ต → รัน detector ซ้ำและค่อยพิจารณา strict gate
