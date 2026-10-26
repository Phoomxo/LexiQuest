# แผน Codex Red Team — LexiQuest Source-to-Mastery Delivery Plan

**สถานะ:** ข้อเสนอจาก Red Team สำหรับนำไปเปรียบเทียบกับแผน Claude Blue Team
**มุมมอง:** PM, SA, BA, UX Designer, Dev และ QA
**ขอบเขต:** Android-first, English-only, local-first, รักษา feature catalog 8 หมวด/44 ความสามารถ และ authority ปัจจุบัน
**คำตัดสิน:** **REVISE AND INCREMENT** — ไม่รื้อระบบหรือไล่สร้างทุกหน้าพร้อมกัน ให้ปิดช่องว่างระหว่าง Design Revision 5 กับ Flutter implementation และส่งมอบวงจร `แหล่งเนื้อหา → ตรวจแก้ → ฝึก → feedback ที่บันทึกแล้ว → ซ่อมจุดอ่อน` ก่อน

---

## 1. Executive decision

ผลวิจัย Astra สนับสนุนแนวคิด source-first, guided path, Socratic tutor และ chat workspace แต่ LexiQuest มีระบบ authority ที่ Astra pattern ทดแทนไม่ได้ ได้แก่ owner isolation, `ImportVocabulary`, `LearningUseCases`, EvidenceContext/EventEnvelopeV2, reward ledger และ offline learning

Red Team เสนอให้ใช้สิ่งที่ศึกษาในระดับ **interaction pattern และลำดับงาน** ดังนี้:

```text
นำเข้าเนื้อหาภาษาอังกฤษ
→ พรีวิวและแก้คำ/วลี
→ ยืนยันเข้าคลังคำของผู้ใช้
→ เลือกงานถัดไปที่ชัดเจนหนึ่งงาน
→ ฝึกใน Reading / Flashcard / Quiz / เติมคำ / เสียง
→ บันทึกคำตอบผ่าน LearningUseCases
→ แสดง feedback หลังบันทึกสำเร็จ
→ ส่งคำผิดเข้าสู่ Weakness/SRS เดิม
```

ลำดับส่งมอบที่ควรใช้:

1. ปิด Design Foundation และ Navigation mismatch
2. ทำ File Import แบบพรีวิวด้วย authority เดิม
3. เชื่อม Source-to-Practice loop
4. ปรับ AI Tutor เป็น Messenger/Socratic shell
5. ทำ Shop/Theme ให้ครบจาก reward authority เดิม
6. จึงค่อยทดลอง PDF/OCR และ adaptive layouts ขั้นสูง

ไม่เพิ่ม `f45`, SRS ใหม่, mastery ใหม่, reward balance ใหม่, chat SDK, file picker ตัวที่สอง หรือ curriculum authority ที่ยังไม่มีข้อมูลจริง

---

## 2. Evidence ที่ตรวจพบจาก repository

| หลักฐาน | ข้อค้นพบ | ผลต่อแผน |
| --- | --- | --- |
| `DESIGN.md` | กำหนด Calm Journey / Evidence Trail, 4 destinations, Vivo 393×876dp และ adaptive contract แล้ว | ใช้เป็น design contract ไม่สร้างภาษาภาพใหม่ |
| `PRODUCT.md` | ผู้ใช้หลักเป็นคนไทยที่เรียนคำศัพท์อังกฤษ; offline learning และ evidence-led เป็นหลัก | ทุก copy เป็นภาษาไทยทั่วไป แต่เนื้อหาการเรียนต้องเป็นภาษาอังกฤษ |
| `docs/design/README.md` | Prototype Revision 5 มี 216 screens, 876 routes, 29 starts | เป็นหลักฐาน design/prototype เท่านั้น ไม่ใช่ implementation completion |
| `main_navigation_screen.dart` | Flutter ปัจจุบันยังมี 6 bottom destinations และ floating drawer | ขัดกับ design contract ที่กำหนด 4 destinations ต้องแก้ก่อนเพิ่ม surface ใหม่ |
| `AddMultipleWordsScreen` | รองรับการวางข้อความ CSV แบบแยกด้วย comma และ import ทันที | ยังไม่มี file picking, preview/edit per row หรือผล rejected ที่แก้ได้ |
| `ImportVocabulary` | มี owner isolation, canonicalization, hash, duplicate handling และ persistence แล้ว | เป็น authority เดียวสำหรับ import ใหม่ |
| `WordbookImportScreen` / `CustomWordbookImporter` | เป็นเส้นทางเก่าและไม่พบ caller ใน `lib` | ห้ามขยายเส้นทางนี้ ให้ migrate/remove ภายหลังเมื่อยืนยัน caller |
| `AiTutorScreen` | มี message list, bubble, input, voice และสถานะ provider แล้ว | ปรับโครงและ contract เดิม ไม่เพิ่ม chat framework |
| `GeminiTutorUseCases` | มี consent, key storage, cancellation, serialization และ progress summary | เพิ่ม Socratic mode ใน contract เดิมโดยรักษา consent/limits |
| `LearningUseCases` | มี quiz, SRS, weakness, durable answer และ event/reward hooks | ทุกกิจกรรมใหม่ต้องไหลผ่าน authority นี้ |
| `ShopPage` / `RewardUseCases` | มี purchase/equip/idempotency และรายการ theme/wallpaper แล้ว | ร้านค้าไม่ใช่ฟีเจอร์ใหม่ แต่ต้องปรับ discovery, preview และ applied state |
| `file_selector` | ติดตั้งอยู่แล้ว | ใช้ทันที; ไม่เพิ่ม dependency |
| Layout/accessibility tests | มี 360×800, large text, dark theme และ golden บางหน้า | ขยาย fixture เดิม ไม่สร้าง test harness ใหม่ |
| Astra social research | ยืนยัน source-first, transform once/reuse many, guided path, Socratic และ chat shell | รับเฉพาะ pattern; ไม่รับ claims, multi-subject หรือระบบ readiness ที่ไม่มีสูตร |

---

## 3. Assumptions

1. Revision 5 เป็น design baseline ที่ผู้ใช้ยอมรับว่า “ดีขึ้น” และต้องปรับต่อ ไม่เริ่ม Revision 6 จากศูนย์
2. Android เป็น platform ส่งมอบระยะแรก; iOS ยังไม่อยู่ใน acceptance
3. Canonical compact viewport คือ 393×876dp และต้องไม่พังที่ 360×800 กับ 412×915dp
4. feature catalog 8/44 เป็น frozen contract; import, tutor, theme และ source practice ต้องแมปเข้า capability เดิม
5. เนื้อหาและกิจกรรมทั้งหมดจำกัดเฉพาะภาษาอังกฤษ แม้ UI อธิบายเป็นภาษาไทย
6. AI/cloud unavailable ต้องไม่ปิดกั้นการนำเข้าคำ การทบทวน Quiz/SRS/Weakness และการดูคลังคำ
7. งานนี้ไม่อนุญาต deployment, production data migration หรือ research enrollment
8. current dirty files เป็นงานที่มีอยู่ก่อน ต้อง reconcile ก่อนให้ card ใดถือครองไฟล์เดียวกัน

---

## 4. Gaps และข้อขัดแย้งที่ต้องปิด

### P0 — Authority และข้อมูล

- Import UI ปัจจุบัน parse comma ด้วย `line.split(',')` จึงไม่รองรับ quoted CSV และไม่มี preview
- Source material ยังไม่มี persisted contract ที่เชื่อม provenance ไปยังคำ/กิจกรรม
- AI Tutor ยังไม่มี contract ของ `socratic` กับ `explain`, ไม่มี budget ต่อ turn/session และยังไม่เชื่อม action กลับไปฝึก
- ห้ามให้ AI, hint หรือ reveal เขียน mastery/reward โดยตรง
- PDF/OCR ยังไม่มี data lifecycle, size budget หรือ accuracy handling

### P1 — Navigation และ UX

- Implementation ยังแสดง 6 bottom destinations ขณะที่ design contract กำหนด 4
- Drawer/FAB เพิ่ม cognitive load และซ่อน feature hierarchy
- คำว่า `AI Tutor` และศัพท์เชิงระบบบางส่วนยังไม่เป็นภาษาคน
- File import ยังเป็น editor เดียว ไม่มีขั้น `เลือกไฟล์ → ตรวจข้อมูล → ยืนยัน`
- Shop มี transaction flow แต่ยังไม่มี preview ที่ทำให้ผู้ใช้เห็นผล theme/wallpaper ก่อนซื้อหรือใช้งาน
- Figma prototype route completeness ไม่ได้ยืนยันว่า Flutter routes/state/back ตรงกัน

### P1 — Verification

- ยังไม่มี runtime evidence ของ Revision 5 บน 393×876dp
- ยังไม่มี TalkBack/focus/IME evidence
- ยังไม่มี end-to-end test สำหรับ file import → restart → practice → weakness
- Foldable และ tablet มี contract แต่ยังไม่มี Flutter implementation evidence

---

## 5. Responsibility map

| บทบาท | ความรับผิดชอบ |
| --- | --- |
| PM | ตรึง outcome, dependency order, release boundary และไม่เปิดงานที่ไม่มี authority |
| BA | เขียน journey, copy ไทยทั่วไป, acceptance และข้อยกเว้น offline/error |
| SA | คุม owner isolation, provenance, authority, 8/44 mapping และ contract ระหว่าง UI/use case/repository |
| UX Designer | ปรับ Revision 5 ให้ทุก flow มีงานหลักหนึ่งงาน, responsive states และ feedback หลัง persistence |
| Dev | reuse component/use case/dependency เดิมและทำ smallest complete diff |
| QA | สร้าง test matrix ตาม state, viewport, restart, failure, accessibility และ duplicate protection |

หนึ่ง card มีผู้เขียนไฟล์ร่วมได้เพียงคนเดียว งาน Flutter build/test/dependency resolution/codegen ต้อง serialize ใน worktree นี้

---

## 6. ADLC delivery graph

### Card R0 — Baseline reconciliation and traceability

**ADLC:** Intent → Ground → Plan
**Outcome:** สร้าง source snapshot และ traceability จาก Revision 5 ไปยัง Flutter screens จริงก่อนแก้ UI
**Owner:** PM + SA + QA
**Write set ที่คาด:** เอกสาร plan/traceability เท่านั้น
**Read set:** `DESIGN.md`, `PRODUCT.md`, `docs/design/**`, routes, screens, registries และ tests

**งาน**

- ทำ matrix `Prototype screen/action → Flutter route/screen → authority → feature registry → test`
- แยกสถานะ `designed`, `implemented`, `verified`, `release-ready`
- ตรึงรายการ main journeys:
  1. Login/Register
  2. Hub → recommended practice
  3. Vocabulary → add/import
  4. Quiz → feedback → Score → weakness repair
  5. SRS
  6. AI Tutor
  7. Progress
  8. Shop/theme
  9. Profile/settings/export
- ตรวจ write conflict กับ dirty files ปัจจุบันก่อนมอบ card

**Acceptance**

- ทุก action ใน main journey มีปลายทาง Flutter จริงหรือระบุ gap
- ไม่มีการอ้างว่า prototype frame เท่ากับฟีเจอร์เสร็จ
- 44 capabilities ถูกแมปโดยไม่เพิ่ม ID ใหม่
- ระบุ authority ของ persistence/reward/mastery ทุก flow

---

### Card R1 — Design foundation and four-destination shell

**ADLC:** Execute → Review → Attest
**Outcome:** Flutter shell ตรงกับ design contract: `เรียน / คลังคำ / ก้าวหน้า / โปรไฟล์`
**Owner:** UX Designer + Dev; QA ตรวจอิสระ
**Predecessor:** R0

**Design**

- `เรียน`: Today plan, next action, path preview เฉพาะข้อมูลจริง และกิจกรรมรอง
- `คลังคำ`: หมวด, ค้นหา, เพิ่ม, นำเข้า และรายละเอียด
- `ก้าวหน้า`: ภาพรวม, จุดที่ควรฝึก, achievements และทางเข้าร้านค้า
- `โปรไฟล์`: บัญชี, AI/voice settings, privacy และ export
- Weakness เป็น recommendation/drill-down
- Shop อยู่ใน Progress
- AI Tutor เป็น contextual entry จาก Learn และ secondary tool ที่มีสถานะ limited
- Compact ใช้ `NavigationBar`; medium ขึ้นไปใช้ `NavigationRail`
- ลด/เลิก floating drawer เมื่อปลายทางทั้งหมดมี owner ที่ชัด

**File impact**

- `lib/screens/main_navigation_screen.dart`
- `lib/screens/choose_mode_screen.dart`
- `lib/screens/mastery_dashboard_screen.dart`
- `lib/screens/profile_settings_screen.dart`
- `lib/config/m3_theme.dart`
- route/navigation tests และ golden tests
- อาจเพิ่ม shared adaptive shell เฉพาะเมื่อใช้จริงอย่างน้อยสองหน้าจอ

**Acceptance**

- แสดงไม่เกิน 4 destinations ในทุก feature-state combination
- hidden/limited/enabled ยังมีผลตาม registry
- system Back และ deep route เดิมที่มี caller ยังทำงาน
- 360×800, 393×876 และ 412×915 ไม่มี overflow
- touch target ≥48dp, text scale 130%/200%, light/dark ผ่าน
- runtime unavailable แสดง banner แต่ local learning ยังใช้ได้

**Red Team condition**

ห้ามแก้ feature registry เพื่อบังคับให้เมนูดูครบ และห้ามเปิด Learning World Map ด้วย hardcoded nodes

---

### Card R2 — File import with preview and durable authority

**Outcome:** ผู้ใช้เลือก `.csv`/`.json`, ตรวจแก้รายการ และยืนยันเข้าคลังคำผ่าน `ImportVocabulary`
**Owner:** BA + SA + Dev + QA
**Predecessor:** R1

**Flow**

```text
คลังคำ → เพิ่ม/นำเข้า → เลือกไฟล์
→ ตรวจชนิด/ขนาด
→ parse ในเครื่อง
→ ตารางพรีวิว: ผ่าน / ต้องแก้ / ซ้ำ
→ แก้หรือตัดรายการ
→ ยืนยัน
→ accepted/duplicate/rejected
→ ไปยังคลังคำหรือเริ่มฝึก
```

**Implementation direction**

- ใช้ `file_selector` ที่ติดตั้งแล้ว
- ย้าย parsing ออกจาก widget ไปเป็น pure parser ขนาดเล็ก
- CSV ต้องรองรับ quoted comma หรือใช้ parser ที่มีอยู่ใน dependency tree หากตรวจพบแล้ว; ห้ามใช้ `split(',')` สำหรับไฟล์
- จำกัด extension/MIME/bytes/row count ก่อนอ่านทั้งหมด
- `ImportVocabulary` ยังคงเป็น persistence authority
- `sourceName` เก็บชื่อที่ปลอดภัย ห้ามเก็บ path เต็มหรือ file bytes ใน event/log
- cancel ก่อน persist ไม่สร้าง record
- uncertain acknowledgement ใช้ idempotency/hash เดิม ไม่ submit ซ้ำ

**File impact**

- `lib/screens/add_multiple_words_screen.dart`
- parser/domain object ใหม่ใน `lib/features/vocabulary/application/` เฉพาะที่จำเป็น
- อาจเพิ่ม file selection adapter ใน vocabulary data/platform
- `lib/features/vocabulary/application/import_vocabulary.dart` เฉพาะเมื่อ contract ต้องคืน preview metadata
- `test/features/vocabulary/import_vocabulary_test.dart`
- test parser, widget import และ `offline_vocabulary_journey_test.dart`
- legacy `wordbook_import_screen.dart` ยังไม่ลบจน R0 ยืนยัน route/caller ทั้งหมด

**Acceptance**

- malformed/empty/oversize/unsupported file ไม่ persist
- ผู้ใช้แก้ rejected row ก่อนยืนยันได้
- duplicate import หลัง restart ไม่สร้างคำซ้ำ
- owner A ไม่เห็นข้อมูล owner B
- accepted/duplicate/rejected totals ตรง repository result
- offline import และเปิดคลังคำหลัง restart ผ่าน
- TalkBack อ่านสถานะ row โดยไม่พึ่งสี

---

### Card R3 — English source-to-practice loop

**Outcome:** นำเข้า `.txt/.md` ภาษาอังกฤษและใช้แหล่งเดียวสร้างกิจกรรมจาก authority เดิม
**Owner:** BA + SA + Dev
**Predecessor:** R2

**Scope**

- รองรับ plain text/Markdown ก่อน
- ตรวจ language gate และขนาด
- จับคู่คำ/วลีกับคลังคำที่มีอยู่แบบ deterministic
- คำไม่รู้จักต้องอยู่ใน preview และให้ผู้ใช้เติม/แก้ความหมาย; ห้าม AI auto-import
- เก็บ provenance ขั้นต่ำ: source ID/hash, display name, revision และ selected excerpts
- เปิดกิจกรรมเฉพาะที่มี implementation authority แล้ว: reading, flashcard, quiz, fill, voice
- หาก AI/network/quota ไม่พร้อม ใช้ local match-only fallback

**Authority rule**

- การตอบทุกแบบฝึกเรียก `LearningUseCases.recordAnswer`
- hint อย่างเดียวไม่เปลี่ยน mastery/reward
- reveal บันทึก incorrect เพียงครั้งเดียวด้วย stable attempt identity และ assisted/reveal `promptMode`
- source transform ห้ามสร้าง reward โดยตรง

**File impact**

- vocabulary/import application และ repository contract
- reading/session model เฉพาะเมื่อจำเป็นต่อ persistence
- `lib/screens/associative_reading_session_screen.dart`
- `lib/screens/srs_flashcards_screen.dart`
- `lib/screens/quiz_screen.dart`
- `lib/features/learning/application/learning_use_cases.dart` เฉพาะ contract ที่ขาด
- Drift schema/migration **เฉพาะเมื่อ provenance ต้อง persist** พร้อม export/delete/sync/owner coverage
- focused domain/widget/integration tests

**Acceptance**

- import → kill/restart → resume source/practice ได้
- AI failure ไม่ทำให้ local practice หยุด
- reveal/hint semantics ไม่เพิ่ม mastery หรือ reward ซ้ำ
- source revision stale มีข้อความและทางเลือก re-import
- ไม่มี raw source ใน telemetry
- flow จบด้วย Score/Weakness และกลับ Hub โดย refresh เมื่อ session จบเท่านั้น

---

### Card R4 — Socratic Messenger-style AI Tutor

**Outcome:** ผู้ช่วยภาษาอังกฤษที่คุ้นเคยแบบ LINE/Messenger มีสองโหมดชัดเจนและเชื่อมกลับสู่การฝึก
**Owner:** UX Designer + SA + Dev + QA
**Predecessor:** R1; source actions เพิ่มหลัง R3

**Design**

- ชื่อหน้าภาษาไทย: `ผู้ช่วยฝึกภาษาอังกฤษ`
- conversation header บอกโหมด/สถานะ service แบบไม่แสดงศัพท์ provider เป็นเนื้อหาหลัก
- bubble ซ้าย/ขวา, timestamps/metadata น้ำหนักรอง, composer ติดล่างเหนือ IME
- quick actions:
  - `ช่วยฉันคิดทีละขั้น`
  - `อธิบายให้เลย`
  - `สร้างตัวอย่าง`
  - `ฝึกคำนี้`
- คำตอบ Socratic ให้คำใบ้หนึ่งระดับและถามกลับก่อน reveal
- action จากข้อความไปสู่ practice ต้องส่งผ่าน use case เดิม
- provider/model provenance อยู่ใน info sheet หรือข้อความรอง

**Architecture**

- ขยาย `scenario` ใน `GeminiTutorController` อย่างมี type/validation หรือตรึงค่าที่ gateway รองรับ
- ใช้ consent, cancellation, serial gate และ secure storage เดิม
- one in-flight request ต่อ composer
- กำหนด input length, turn/session budget, timeout และ quota state
- local fallback เป็น guidance/template จากข้อมูลในเครื่อง ห้ามปลอมว่าเป็น AI response
- ไม่บันทึก transcript ถาวรจนกว่าจะมี data lifecycle/erase/export contract

**File impact**

- `lib/screens/ai_tutor_screen.dart`
- `lib/features/gemini/domain/gemini_contracts.dart`
- `lib/features/gemini/application/gemini_tutor_use_cases.dart`
- gateway/backend contract เฉพาะเมื่อ structured mode จำเป็น
- AI tutor widget/use-case/gateway tests
- accessibility/IME golden

**Acceptance**

- consent missing/offline/quota/timeout/cancel มี state และ retry ที่ไม่ส่งซ้ำ
- composer ไม่ถูก IME บังที่ compact widths
- rotate/resize รักษา draft และ messages ใน session
- Socratic และ Explain ให้พฤติกรรมต่างกันตาม contract
- AI reply ไม่เขียน SRS/mastery/reward
- `ฝึกคำนี้` เปิดกิจกรรมผ่าน authority เดิมและ Back กลับบริบทสนทนาได้
- provider key/message ไม่ปรากฏใน logs

---

### Card R5 — Evidence feedback surfaces

**Outcome:** Quiz, Flashcard, Score และ Weakness ใช้จังหวะเดียวกันและสื่อสถานะ persistence ชัด
**Owner:** UX Designer + Dev + QA
**Predecessor:** R1; ทำขนานกับ R2 ได้เมื่อ write sets ไม่ทับ

**Design rule**

`เลือก → ยืนยัน → กำลังบันทึก → บันทึกสำเร็จ → feedback → ขั้นถัดไป`

**File impact**

- `lib/screens/quiz_screen.dart`
- `lib/screens/srs_flashcards_screen.dart`
- `lib/screens/score_screen.dart`
- `lib/screens/weakness_clinic_screen.dart`
- learning screen tests/goldens

**Acceptance**

- failure-before-write คงคำตอบและให้ retry
- lost acknowledgement ไม่สร้าง answer/reward ซ้ำ
- feedback บอกคำตอบผู้ใช้, คำตอบถูก และ next action
- สีไม่ใช่สัญญาณเดียว
- large text ยัง scroll ถึง CTA
- Score มี CTA ฝึกคำผิดเมื่อมีคำผิด และกลับแผนวันนี้เมื่อไม่มี
- ห้ามแสดง readiness/mastery percentage ที่ไม่มีสูตรจาก authority

---

### Card R6 — Shop, themes and wallpaper completion

**Outcome:** ผู้ใช้ค้นพบ ซื้อ พรีวิว และใช้งาน theme/wallpaper ด้วย reward ledger เดิม
**Owner:** PM + BA + UX Designer + Dev + QA
**Predecessor:** R1

**Scope**

- ทางเข้าร้านค้าอยู่ใน Progress/Rewards
- filter `ธีม / วอลเปเปอร์ / ของตกแต่ง` เฉพาะชนิดที่ catalog มีจริง
- preview ก่อนซื้อและก่อน equip
- balance และราคาแสดงชัด
- purchased/equipped/idempotent states ใช้ `RewardUseCases`
- applied theme ต้องอ่าน equipped state จาก authority เดิม
- การเรียน/mastery ไม่ขึ้นกับการซื้อ
- ไม่มีเงินจริงหรือ in-app purchase ใน card นี้

**File impact**

- `lib/screens/shop_page.dart`
- `lib/screens/select_wallpaper_screen.dart`
- reward catalog/account/use cases เฉพาะ gap ที่ยืนยัน
- theme composition ใน `m3_theme.dart` หรือ composition root แห่งเดียว
- shop/reward/theme widget and persistence tests

**Acceptance**

- ซื้อซ้ำจาก retry ไม่หักคะแนนซ้ำ
- insufficient balance/stale catalog/restart แสดง state ถูก
- equip หลัง restart ยังอยู่
- theme ไม่ลด contrast, touch target หรือ text readability
- user ที่ไม่ใช้ร้านค้ายังเข้าถึง learning flow ครบ
- catalog item ทั้งหมดมาจาก authority เดียว ไม่มี `CardThemeItem` คู่ขนานที่สร้าง balance/ownership ใหม่

---

### Card R7 — PDF/OCR spike

**Outcome:** ตัดสินใจด้วยหลักฐานว่าจะเพิ่ม PDF/OCR dependency หรือไม่
**Owner:** SA + Dev + QA
**Predecessor:** R2–R4 ผ่าน

**งานทดลองเท่านั้น**

- `pdfrx`: extraction quality, encrypted/malformed PDF, APK/native size, latency/memory
- ML Kit OCR: Latin/Thai, orientation, low light, crop, device compatibility และ data locality
- ทุก OCR result ต้อง preview/edit/retake/delete/confirm
- ไม่ใช้ generic confidence score เป็นตัวอนุมัติอัตโนมัติ

**Go criteria**

- APK/startup/memory budget ผ่านค่าที่ทีมกำหนด
- offline behavior ชัด
- input ไม่ถูก upload โดยปริยาย
- OCR error fixture และ device matrix ผ่าน
- ลบ raw capture/temp file ตาม lifecycle

หากไม่ผ่าน ให้คง TXT/Markdown/CSV/JSON และ manual correction ซึ่งยังส่งมอบ source-to-practice value ได้ครบ

---

### Card R8 — Adaptive runtime verification

**Outcome:** ยืนยัน Flutter implementation ตาม responsive contract
**Owner:** QA + UX Designer + Dev
**Predecessor:** R1–R6 integration snapshot

**ลำดับ**

1. LDPlayer: 360×800, 393×876, 412×915
2. Tablet: 600×960, 800×1280, 1024×1366, 1280×800
3. Boundary: 599/600, 839/840, 1199/1200 และ height 479/480
4. Android foldable emulator ที่มี `displayFeatures`
5. อุปกรณ์จริงเมื่อพร้อม

**Acceptance**

- ไม่มี overflow/clipping/CTA ถูก inset หรือ IME บัง
- selected destination, scroll, draft, import preview, quiz answer และ AI conversation ไม่หายหลัง rotate/resize
- compact-height fallback เป็น single pane
- two-pane เปิดเมื่อ list ≥320dp และ detail ≥480dp หลังหัก rail/gutter/hinge
- TalkBack order/focus restoration/touch target ผ่าน
- fold/posture evidence ระบุ `not verified` จนมี runtime record จริง

---

## 7. Test matrix

| พื้นที่ | Happy path | Failure/edge | Persistence/security | UI/accessibility |
| --- | --- | --- | --- | --- |
| Navigation | 4 destinations และ deep route | hidden/limited feature | selected tab หลัง rebuild | 360/393/412, rail, Back, TalkBack |
| Import | CSV/JSON preview → confirm | malformed, quoted comma, empty, oversize, cancel | owner isolation, duplicate, restart | row status, 200% text, no color-only |
| Source practice | source → activity → result | offline, stale revision, unknown terms | provenance, no raw telemetry | one primary action, loading/empty/error |
| Quiz/SRS | save → feedback → next | retry/lost ack/back | stable attempt/reward once | CTA scroll, semantics |
| AI Tutor | Socratic/Explain/voice | consent, key, quota, timeout, cancel | no secret logs, no transcript persistence without contract | IME, rotation, bubbles, TalkBack |
| Shop | purchase/equip/preview | insufficient, stale, double tap | idempotency, restart, owner | contrast/theme/font scale |
| Responsive | compact/medium/expanded | boundary/compact height | state continuity | insets, focus, hinge |
| Offline | vocab/import/practice available | AI/cloud unavailable | no queued raw source upload | service banner ไม่ขวางงาน |

**Focused commands ต่อ integration checkpoint**

```powershell
dart format --output=none --set-exit-if-changed <touched files>
flutter analyze --no-pub <touched Dart files>
flutter test --no-pub test/features/vocabulary
flutter test --no-pub test/features/learning test/features/progress test/features/rewards
flutter test --no-pub test/screens/choose_mode_screen_test.dart test/screens/quiz_screen_test.dart test/screens/weakness_clinic_screen_test.dart test/screens/learning_loop_layout_test.dart
flutter test --no-pub test/screens/accessibility_smoke_test.dart test/screens/offline_vocabulary_journey_test.dart
```

ก่อน release checkpoint จึงรัน full Flutter regression, Android build/install, LDPlayer matrix และ device/foldable checks โดยใช้ source snapshot เดียวกัน

---

## 8. Primary risks and mitigations

| ความเสี่ยง | ผลกระทบ | วิธีควบคุม |
| --- | --- | --- |
| Prototype ถูกตีความว่า implementation เสร็จ | ส่งมอบไม่ตรงจริง | traceability R0 และแยก designed/implemented/verified |
| เพิ่ม source model กลายเป็น authority ใหม่ | progress/mastery แตกเป็นสองชุด | ทุก answer ผ่าน `LearningUseCases`; source เป็น provenance |
| AI สร้างคำหรือคะแนนเอง | ข้อมูลเรียนไม่น่าเชื่อถือ | preview/confirm และห้าม AI เขียน mastery/reward |
| Import parser ทำข้อมูลเสีย | คำ/ความหมายเลื่อนคอลัมน์ | parser test, preview, bounds และ cancel-before-write |
| Drawer/nav migration ทำ route หาย | ฟีเจอร์เข้าถึงไม่ได้ | route matrix และ legacy caller/back tests |
| Theme shop ทำ accessibility เสีย | อ่านยาก/contrast ต่ำ | semantic tokens และ golden/contrast checks |
| OCR เพิ่ม APK/memory สูง | Android ต่ำสเปกใช้งานไม่ได้ | spike หลัง core loop และมี no-go threshold |
| Tablet/fold design เกินหลักฐาน | state หายหรือ CTA คร่อม hinge | runtime display features และ single-pane fallback |
| Dirty worktree edits ทับกัน | สูญงานหรือ test evidence ไม่ตรง snapshot | one writer/file, reconcile ก่อนเริ่ม card, serialize build |

---

## 9. Definition of Done

แผนนี้ถือว่าปิดเมื่อ:

1. Flutter shell และ main journeys ตรงกับ Revision 5 และ 4-destination contract
2. ผู้ใช้ทำ `import → preview → persist → restart → practice → feedback → weakness` ได้โดย offline
3. AI Tutor มี Socratic/Explain, consent/quota/offline handling และไม่สร้าง learning authority ใหม่
4. Shop/theme ใช้ reward ledger เดิมและ idempotent
5. 8/44, EvidenceContext/EventEnvelopeV2, owner isolation และ export/delete/sync contracts ยังผ่าน
6. focused tests, full regression ที่ integration checkpoint และ Android runtime matrix มีหลักฐานจาก source snapshot เดียวกัน
7. สิ่งที่ยังไม่มี hardware/research/release evidence ระบุชัดว่า `not verified`
8. มี review disposition จาก Red Team, Blue Team และ adjudicator ก่อนรวมเป็น final execution plan

---

## 10. Red Team recommendation to adjudicator

เลือกแกนของแผนนี้เป็นฐานหาก Blue Team เสนอ redesign หรือ feature expansion ขนาดใหญ่ เพราะ code ปัจจุบันมี authority สำคัญครบหลายส่วนแล้ว ช่องว่างจริงคือการเชื่อม UI/flow เข้ากับ authority และการพิสูจน์ runtime

จุดที่เปิดให้รับจาก Blue Team:

- visual composition, typography, illustration และ microinteraction ที่ดีกว่า
- การรวม screens ใน Figma ให้ flow อ่านง่ายขึ้น
- copy ภาษาไทยและ Socratic conversation examples
- theme preview และ marketplace presentation
- alternative layout ที่ผ่าน responsive/accessibility constraints

จุดที่ไม่ควรต่อรอง:

- 8/44 frozen catalog
- English-only
- Android-first
- local learning ทำงานเมื่อ AI/cloud ล่ม
- `ImportVocabulary`, `LearningUseCases`, reward ledger และ owner isolation เป็น authority
- feedback หลัง durable save
- ไม่มี efficacy/readiness claim ที่ไม่มี evidence
- ไม่มี production/research rollout จาก design approval

ข้าม: ไม่ได้แก้ implementation และไม่ได้รัน Flutter tests เพราะเอกสารนี้เป็นแผนจากการตรวจแบบ read-only
ความเสี่ยง: dirty worktree มีไฟล์ implementation และ tests ที่แก้ค้างอยู่ จึงต้อง reconcile source snapshot ก่อนเริ่ม R1 มิฉะนั้น file impact และ test evidence อาจคลาดเคลื่อน
