# LexiQuest R8 — Three-App Reference Synthesis

วันที่: 2026-10-18
สถานะ: ข้อกำหนดออกแบบและเกณฑ์ตรวจรับ R8 สำหรับ Android-first clickable prototype
ขอบเขต: นำรูปแบบงานที่สังเกตได้จาก AllTCAS, Duolingo และ Astra มาสังเคราะห์เป็น LexiQuest โดยคงชื่อภาษาไทย ระบบข้อมูล และกฎผลิตภัณฑ์ของ LexiQuest

## 1. ผลลัพธ์ที่ต้องส่งมอบ

R8 ต้องทำให้ที่มาของโครงหน้าจอมองเห็นได้จาก UI และเส้นทางใช้งานจริง ไม่ใช่เพียงกล่าวถึงแอปอ้างอิงในคำอธิบาย โดยกำหนดอำนาจตัดสินดังนี้:

1. **AllTCAS — โครงงานหลัก:** dashboard, catalog, setup, คำถามทีละข้อ, feedback ในบริบทเดิม, คลังคำ และเมนูรวม
2. **Duolingo — วงจรเรียนและแรงจูงใจ:** เรียนต่อ, เส้นทาง, practice hub, คิวคำที่ต้องทบทวน, ผลลัพธ์ และร้านธีม
3. **Astra — การตั้งบริบทและ AI:** onboarding ทีละคำถาม, progress, เลือกแหล่งข้อมูลก่อนถาม, คำตอบแบบมีโครงสร้าง, ตรวจที่มา และกลับไปฝึก
4. **LexiQuest — กฎผลิตภัณฑ์:** ภาษาไทยที่คนทั่วไปเข้าใจ, mastery อิงหลักฐาน, reward ไม่แทนผลการเรียน, AI แจ้งข้อจำกัด และงานวิจัยแยกจากการเรียนปกติ

เมื่อรูปแบบขัดกัน ให้ใช้ AllTCAS ตัดสินโครงหน้า, Astra ตัดสินลำดับงาน AI และ Duolingo ตัดสินจังหวะเรียนต่อ/ผลตอบกลับ/รางวัล โดยกฎข้อมูลและความถูกต้องของ LexiQuest มีลำดับสูงสุด

## 2. หลักฐานต้นทาง

### AllTCAS — Android runtime

รากหลักฐาน: `C:\Users\Phet\.codex\tools\rea\evidence\mobile-study-2026-10-18\screens\alltcas`

| หลักฐาน | รูปแบบที่นำมาใช้ |
| --- | --- |
| `06-home-after-consent/screen.png` | ลำดับ dashboard และงานหลักก่อนเครื่องมือรอง |
| `09-practice-setup/screen.png` | เลือกชุดก่อนกำหนดค่ารอบฝึก |
| `12-answer-explanation/screen.png` และ `13-feedback-settled/screen.png` | feedback อยู่กับคำถามและมีทางไปต่อชัดเจน |
| `17-vocab-home/screen.png`, `19-vocab-deck/screen.png`, `20-vocab-mode-selection/screen.png`, `21-flashcard-front/screen.png` | คลังคำ → ชุดคำ → วิธีฝึก → บัตรคำ |
| `36-ai-chat-composer/screen.png` | composer และสถานะบทสนทนา |
| `40-navigation-menu/screen.png` | เมนูรวมที่จัดกลุ่มตามงาน |

### Duolingo — Android runtime

รากหลักฐาน: `C:\Users\Phet\.codex\tools\rea\evidence\mobile-study-2026-10-18\screens\duolingo`

| หลักฐาน | รูปแบบที่นำมาใช้ |
| --- | --- |
| `05-resume/screen.png` | จุด “เรียนต่อ” เด่นหนึ่งจุดและใช้เวลาโดยประมาณ |
| `07-lesson-preview/screen.png` และ `20-section-overview/screen.png` | preview ก่อนเริ่มและความสัมพันธ์ของด่านปัจจุบัน/ด่านถัดไป |
| `15-practice-hub/screen.png` | เครื่องมือฝึกหลายแบบภายใต้ลำดับชั้นเดียว |
| `16-words/screen.png` และ `17-mistakes-entry/screen.png` | คิวคำและทางซ่อมคำที่พลาด |
| `21-shop/screen.png` | ร้านค้าเป็นปลายทางรองของแต้ม ไม่แทรกงานเรียนหลัก |

### Astra — public web และ onboarding

แหล่งที่ตรวจ: `https://astra-ai.co/th/` และ `https://app.astra-ai.co/th-TH/onboarding`
บันทึกการสังเคราะห์: `docs/research/2026-10-18-duolingo-astra-alltcas-layout-synthesis.md`

สิ่งที่ยืนยันได้คือการเริ่มจากเอกสาร/เป้าหมาย/วันสอบ, role selection, progress indicator, one-question-per-screen และ progressive disclosure เท่านั้น ไม่มี Astra APK บนมือถือที่เชื่อมต่อ และไม่มีภาพ runtime ของหน้าคำตอบ AI ภายในบัญชี ดังนั้น R8 ใช้ **ลำดับงานเชิงแนวคิด** `เลือกแหล่งข้อมูล → ยืนยันบริบท → ถาม → คำตอบมีโครงสร้าง → ตรวจข้อมูลที่ใช้ → ฝึกต่อ` โดยไม่อ้างว่าหน้าผู้ช่วย Lexi มีหน้าตาเหมือน Astra

## 3. การแมปหน้าต่อหน้าใน R8

| หน้าหรือสถานะ R8 | โครงที่ใช้จริง | แหล่งหลัก | ทางเข้าหรือทางต่อที่ต้องกดได้ |
| --- | --- | --- | --- |
| `home` — เรียนวันนี้ | เป้าหมาย/กำหนดเวลา → การ์ดเรียนต่อ → เส้นทาง → เครื่องมือด่วน | AllTCAS home + Duolingo resume/path | เรียนต่อ, เส้นทาง, ทบทวน, คลังคำ, ผู้ช่วย Lexi, ร้านธีม |
| `catalog` — เลือกชุดฝึก | stepper `เลือกชุด → ตั้งค่ารอบ`, ชุดแนะนำ, บัตรคำ, อ่าน และท้าทายตนเอง | AllTCAS setup/catalog + Duolingo practice hub | ชุดเรียน, บัตรคำ, อ่านเรื่องสั้น, เมนูทั้งหมด |
| `library` — คลังคำ | คำถึงกำหนด → filter → ชุดเดิม → หมวด → บัตรคำ | AllTCAS vocabulary + Duolingo words/mistakes | คำ, ชุดคำ, หมวด, filter และ flashcards |
| `quiz_idle`, `quiz`, `quiz_wrong_selected*` | progress, เวลา/ระดับ, prompt, ตัวเลือก, fixed action, รายงานและบันทึกข้อ | AllTCAS question flow | เลือกคำตอบ → ตรวจคำตอบ; รายงาน/บันทึกมีปลายทาง |
| `feedback`, `feedback_wrong`, `feedback_reveal` | คำถามและตัวเลือกเดิมพร้อมเหตุผล; แยกถูก/ผิด/เปิดเฉลย | AllTCAS explanation/feedback | ดูคำ, ดูผล, ดูเหตุผล, ลองใหม่ |
| `result` — สรุปการฝึก | หลักฐานรอบนี้ → คำที่พลาด → ด่านที่พร้อมเปิด → action ซ่อม | AllTCAS result hierarchy + Duolingo payoff/unlock | ฝึกคำที่พลาด และดูด่านถัดไป |
| `ai`, `ai_followup` | context card → bubble แบบแชตคุ้นเคย → คำอธิบาย/ตัวอย่าง → แหล่งข้อมูล → verify/practice → composer | Astra workflow + AllTCAS composer + LexiQuest provenance | เปลี่ยนข้อมูล, ตรวจคำสำคัญ, ฝึกคำ, ส่งคำถาม |
| `ai_sending`, `ai_error` | รักษาคำถามและบริบท; แสดงสถานะส่ง, retry, edit และฝึก offline | LexiQuest reliability policy | รับคำตอบ, ลองใหม่, แก้ข้อความ, ฝึกต่อ, ดูโควตา |
| `onboarding_goal` | หนึ่งคำถามต่อหน้า, progress 1/4, ตัวเลือกที่อธิบายผล | Astra onboarding | เป้าหมาย → เวลา → วิธีเรียน → ยืนยันแผน |
| `feature_hub` — เมนูทั้งหมด | จัดกลุ่ม `เรียนและฝึก / ติดตามและตกแต่ง / บัญชีและระบบ` | AllTCAS navigation | catalog, คลังคำ, AI, progress, ร้านธีม, บัญชี/ตั้งค่า |
| `theme_store` และสถานะซื้อ/ใช้ธีม | แต้ม → template/ธีม → preview → แลก/ใช้งาน พร้อม offline/stale/แต้มไม่พอ | Duolingo shop rhythm + LexiQuest reward rules | ดูตัวอย่าง, แลก, ใช้, กลับสู่การเรียน |

เส้นทางแกนกลางที่ใช้ตรวจรับคือ:

1. `Home → เรียนต่อ → Preview/บทเรียน → คำถาม → Feedback → Result → ซ่อมคำ/ด่านถัดไป`
2. `Home → เลือกชุดฝึก → รายละเอียดชุด → ตั้งค่ารอบ → คำถาม`
3. `Home → คลังคำ → คำ/ชุด/หมวด → บัตรคำหรือแบบฝึก`
4. `Home → ผู้ช่วย Lexi → เลือกข้อมูล → ถาม → ตรวจที่มา → ฝึกคำ`
5. `Home/Profile → ร้านธีม → Preview → แลก/ใช้ธีม → กลับหน้าหลัก`
6. `เมนูทั้งหมด → ทุกกลุ่มงาน → Back/Navigation → จุดเดิม`

## 4. เป้าหมาย Mobile และ Responsive

R8 เป็น **Android-first** และใช้ `393×876dp` เป็น compact canonical ของ Vivo V2041 โดยขนาดนี้คือ app window ในหน่วย dp; implementation ต้องอ่าน insets และพื้นที่ใช้งานจริง ห้ามอนุมานจาก physical pixels หรือชื่อรุ่น

| Window class | ช่วงกว้าง | โครง |
| --- | ---: | --- |
| Compact | `<600dp` | single pane, NavigationBar 4 จุดหมาย, gutter 16–20dp |
| Medium | `600–839dp` | centered single pane/2-column ตามเนื้อหา, NavigationRail |
| Expanded | `840–1199dp` | list-detail/supporting pane เมื่อแต่ละ pane ผ่านขั้นต่ำ |
| Large | `1200–1599dp` | two-pane ภายใน shell สูงสุด 1200dp |

กฎความสูง: `<480dp` บังคับ single pane และ CTA ต้องไม่ชน prompt; `480–899dp` ใช้กฎตามความกว้าง; `≥900dp` เพิ่ม supporting context ได้โดยคงงานหลักหนึ่งงาน
ชุดตรวจขั้นต่ำ: `360×800`, `393×876`, `412×915`, `600×960`, `800×1280`, `1024×1366`, `1280×800`, boundary `800×479/480`, text scale `100/130/200%` และ dark mode
Samsung fold/dual และ Huawei single/dual/triple ต้องใช้ window, insets, hinge/occlusion และ posture ที่ runtime รายงานจริง; LDPlayer ใช้ทดสอบ resolution/DPI/orientation ได้ แต่ใช้รับรอง hinge หรืออุปกรณ์จริงไม่ได้

กฎร่วม: touch target อย่างน้อย `48×48dp`, ระยะระหว่าง target อย่างน้อย `8dp`, form ≤560dp, prose ≤640dp, primary task ≤720dp, AI ≤760dp และ shell ≤1200dp; การ resize/fold/rotate ต้องรักษา route, selection, scroll, quiz progress และข้อความร่าง

## 5. เกณฑ์ตรวจรับ

R8 ผ่านด้านการออกแบบเมื่อมีหลักฐานครบทุกข้อดังนี้:

- มี 240 หน้าจอ/สถานะ, 8 domains/44 capabilities และ responsive specimens 20 แบบตามทะเบียนเดิม โดยไม่เพิ่มระบบ mastery/reward authority ซ้ำซ้อน
- หน้าแกนกลางในตารางข้อ 3 แสดงโครงของแหล่งอ้างอิงอย่างเห็นได้ชัด และบอร์ด `Three-App Reference Trace` เชื่อม pattern กับหน้าปลายทาง
- ทุก control ที่มีลักษณะกดได้มี route, overlay, back หรือ close จริง; ไม่มี dead interaction, duplicate source, accidental self-loop หรือปลายทางที่หาไม่พบ
- เส้นทางแกนกลางทั้งหกเดินได้ครบจาก entry ถึงผลลัพธ์และย้อนกลับได้ โดย state สำคัญไม่หาย
- ภาษาไทยเป็นศัพท์ทั่วไป; ไม่ใช้ชื่อชั่วคราวหรือศัพท์อังกฤษที่ผู้ใช้ต้องเดาความหมาย
- ไม่มีข้อความล้น/ถูกตัด, CTA ชน navigation/inset/IME, target ต่ำกว่า 48dp หรือ contrast ต่ำกว่าเกณฑ์ WCAG ที่ใช้ในโครงการ
- feedback ถูก/ผิด/เปิดเฉลยแยกกันชัด; การเปิดเฉลยไม่ถูกนับว่าเรียนรู้แล้ว; reward ไม่แสดงเป็น mastery
- AI แสดงข้อมูลที่ใช้ตอบ คำเตือนความคลาดเคลื่อน ทางตรวจข้อมูล และ fallback เมื่อส่งไม่สำเร็จ; retry ที่ล้มเหลวไม่หักโควตา
- ร้านธีมมี preview, แต้ม, เงื่อนไขแลก/ใช้ และสถานะแต้มไม่พอ, ข้อมูลเก่า, offline-owned โดยไม่ขวางการเรียน
- responsive ผ่าน visual/layout validation ทุก fixture และต้องมี runtime evidence แยกก่อนกล่าวว่า foldable หรืออุปกรณ์จริงผ่าน

หลักฐานตรวจส่งมอบต้องประกอบด้วย source generator `tmp/figma/lexiquest_master_ui_v8.js`, manifest จาก renderer, core/reference contact sheets, ผล `tmp/figma/validate_master_ui_v8.mjs`, plugin build และการ smoke-test ใน Figma prototype บน source snapshot เดียวกัน

## 6. ขอบเขตคำกล่าว

R8 เป็นการสังเคราะห์ interaction model, information hierarchy และ layout grammar จากพฤติกรรมที่สังเกตได้ ไม่ใช่การคัดลอกแบรนด์ ภาพประกอบ ข้อความ ชุดสี หรือสินทรัพย์เฉพาะของผลิตภัณฑ์อ้างอิง เอกสารนี้ไม่อ้างว่าออกแบบแบบ pixel-perfect เทียบต้นฉบับ ไม่อ้างว่าเข้าถึง source code, backend, ranking/recommendation logic, A/B test หรือโมเดล AI ภายในของ AllTCAS, Duolingo หรือ Astra และไม่ใช้ข้อความการตลาดของแหล่งอ้างอิงเป็นหลักฐานประสิทธิผลทางการเรียนรู้ของ LexiQuest

สถานะ “ผ่าน” ต้องมาจาก renderer, validator และ prototype smoke-test ที่รันกับ R8 ปัจจุบันเท่านั้น; Figma mockup หรือ emulator เพียงอย่างเดียวไม่ใช่หลักฐานว่า implementation บน hardware ผ่าน

## 7. หลักฐานส่งมอบ R8 วันที่ 2026-10-18

- Figma root: `38:21868` — `R8 · LexiQuest · Build 2026-10-18 · COMPLETE · 240 screens · 939 routes · 41 starts`
- Source hash: `3cf25eaa27fd444567a0b6e0bcc138ba1d3380da2cb9ece7ad190a037b62d681`
- Validator: ผ่าน 240 หน้าจอ, 939 routes, 41 starts; ไม่พบ dead interaction, broken destination, duplicate route source, section overflow หรือ content overflow
- Live prototype smoke-test: ผ่านเส้นทาง Google sign-in mock → Home → Resume/หน้าฝึก, Home → เลือกชุดฝึก → รายละเอียดชุดเรียน, Home → คลังคำ → บัตรคำ, Home → ผู้ช่วย Lexi → ข้อมูลที่ AI ใช้ และร้านธีม → รายละเอียด → preview → ยืนยันแลก → สำเร็จ → ทดลองใช้ → ใช้งานแล้ว
- บัญชีหลักของไฟล์ยังเป็น `petch954100@gmail.com`; ลิงก์ออกแบบและลิงก์ prototype ใช้ไฟล์เดิมเพื่อไม่แยก workspace

Claude Lite provider ตอบกลับด้วย gateway timeout ในสามรูปแบบคำขอที่ลดขนาดตามลำดับ จึงไม่มีผลวิจารณ์จาก Claude ที่ยืนยันได้ในรอบนี้ การตัดสินใจ R8 ใช้หลักฐาน REA, critique จาก sub-agent, renderer, validator และ live prototype smoke-test ข้างต้น
