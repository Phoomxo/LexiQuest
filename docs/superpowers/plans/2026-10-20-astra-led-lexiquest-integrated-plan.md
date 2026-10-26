# LexiQuest Astra-led Integrated ADLC Plan

วันที่: 2026-10-20
ผู้ตัดสิน: Independent Chief SE / PM / SA / BA / UX / Dev / QA
สถานะเอกสาร: `DESIGNED`
ขอบเขต: Android-first, English-only, local-first, รักษา 8 หมวด/44 ความสามารถและ authority เดิม

## 1. Executive verdict

**คำตัดสิน: `ADOPT WITH MODIFICATION` และเริ่ม implementation จาก Card I1 (CSV/JSON Import) หลังทำ source snapshot สั้น ๆ ใน card เดียวกัน**

แผนรวมรับแก่นจากทั้งสองฝ่ายดังนี้:

- รับจาก Codex Red Team: authority boundary, four-destination shell, task cards ที่ระบุ file impact, idempotency, offline behavior, responsive/device verification และ release boundary
- รับจาก Claude Blue Team: source-first hierarchy, primary CTA เดียว, Thai readability, 8dp rhythm, 20dp compact gutter, 48dp target, state matrix, Messenger-style tutor และ marketplace state/back behavior
- แก้ลำดับงาน: ไม่เริ่มจากการรื้อ shell ทั้งหมด เพราะ `main_navigation_screen.dart` และ learning screens มีงานแก้ค้างอยู่ เริ่มจาก import ที่ให้คุณค่าครบวงจร ใช้ `file_selector` กับ `ImportVocabulary` เดิม และมี write set แคบกว่า
- แยก `designed`, `implemented`, `verified`, `release-ready` อย่างชัดเจน Prototype หรือแผนไม่ถือว่าโค้ดเสร็จ

Product thesis ที่ใช้ตัดสินทุก card คือ:

> ผู้เรียนเลือกหรือนำเข้าเนื้อหาภาษาอังกฤษ ตรวจแก้ก่อนบันทึก ฝึกต่อจากแหล่งเดียว รับ feedback ที่บันทึกแล้ว และซ่อมจุดอ่อนผ่าน authority เดิม แม้ AI หรือเครือข่ายไม่พร้อม

ข้อเท็จจริงด้าน Blue Team: เอกสาร Blue เป็น **evidence-derived** จากผล Claude ที่บันทึกไว้ก่อนหน้า การเรียก `claude-opus-5-5` ใหม่ในรอบนี้คืน HTTP `524` ทั้ง `messages` และ `chat/completions`; จึงห้ามอ้างว่าเป็น fresh Claude generation หรือว่ามี token usage รอบใหม่

## 2. Evidence and constraints

แผนนี้ยึดตามหลักฐานปัจจุบันต่อไปนี้:

- `DESIGN.md`: Calm Journey / Evidence Trail, compact 393×876dp, navigation 4 จุดหมาย, adaptive breakpoints และ primary action เดียว
- `PRODUCT.md`: ผู้เรียนภาษาไทยที่ฝึกคำศัพท์อังกฤษ, evidence-led, local-first และ offline learning ต้องทำงานต่อได้
- `docs/research/2026-10-20-astra-ai-social-feature-analysis.md`: source-first, transform once/reuse many, guided path, Socratic tutor และ chat workspace
- `docs/development/agentic-development-life-cycle.md`: Intent → Ground → Plan → Execute → Review → Attest → Integrate → Learn
- `lib/screens/add_multiple_words_screen.dart`: UI ปัจจุบัน parse ด้วย `line.split(',')`, import ทันที และยังไม่มี file preview
- `lib/features/vocabulary/application/import_vocabulary.dart`: เป็น write authority สำหรับ owner isolation, canonicalization, hash และ duplicate handling
- `lib/screens/main_navigation_screen.dart`: runtime ยังมีได้ถึง 6 destinations พร้อม drawer/FAB ขณะที่ design contract กำหนด 4
- `lib/features/learning/application/learning_use_cases.dart`: เป็น write boundary ของ answer evidence และรองรับ stable attempt identity/prompt mode
- `lib/screens/ai_tutor_screen.dart` และ `GeminiTutorUseCases`: มี bubble/input/voice, consent, key storage, cancellation และ serial execution อยู่แล้ว
- `lib/screens/shop_page.dart` และ `RewardUseCases`: มี purchase/equip/idempotency/owner-scoped durable state อยู่แล้ว แต่ preview, discovery และ applied theme ยังไม่ครบ
- `file_selector` ติดตั้งแล้ว; ไม่ต้องเพิ่ม file picker อีกตัว
- branch ปัจจุบันมีไฟล์แก้ค้าง โดยเฉพาะ navigation และ learning screens ต้อง reconcile ownership ก่อนให้ card เขียนทับ

ข้อบังคับร่วม:

1. UI อธิบายเป็นภาษาไทยทั่วไป แต่เนื้อหาและกิจกรรมเป็นภาษาอังกฤษเท่านั้น
2. ห้ามเพิ่ม `f45`; ทุกงานต้อง trace กลับไปยัง 8/44 Revision 1.3.0
3. ห้ามสร้าง learning, SRS, mastery, progress, reward หรือ AI-provider authority คู่ขนาน
4. local vocabulary/import/practice ต้องทำงานเมื่อ AI, quota, cloud หรือ network ไม่พร้อม
5. ห้ามคัดลอกแบรนด์ asset, illustration, copy หรือหน้าจอของ Astra/AllTCAS/Duolingo แบบ pixel-for-pixel
6. ห้ามเปลี่ยน research consent, production upload, deployment หรือ enrollment ในแผนนี้

## 3. Adjudication rubric

คะแนน 1–5 โดย 5 คือเหมาะสมที่สุดต่อ LexiQuest ปัจจุบัน

| เกณฑ์ | Red | Blue | คำตัดสินรวม |
| --- | ---: | ---: | --- |
| Product fit | 4.5 | 4.5 | ใช้ source-to-mastery loop ของทั้งคู่ แต่คง English-only และเลื่อน 3D/podcast/printed exam |
| Authority/data safety | 5.0 | 4.5 | ใช้ boundary จาก Red และ local-match/no-auto-import จาก Blue |
| UX clarity | 4.0 | 4.8 | ใช้ surface hierarchy, state matrix และ copy rules จาก Blue เสริม flow discipline ของ Red |
| Android responsiveness/accessibility | 4.6 | 4.8 | รวม canonical sizes, breakpoints, IME, Back, TalkBack, 48dp และ 200% text |
| Implementation feasibility | 4.7 | 4.2 | เริ่ม import ก่อน shell redesign; reuse dependency/use case/screen เดิม |
| Verification quality | 5.0 | 4.7 | ใช้ test matrix และ runtime evidence จากทั้งคู่ แยก emulator/device evidence |
| Scope/cost control | 4.8 | 4.4 | ไม่เพิ่ม dependency/schema/AI surface จน predecessor ผ่าน |

**สรุป:** Red แข็งแรงกว่าใน architecture, safety และ verification; Blue แข็งแรงกว่าใน information hierarchy, UI states และภาษาที่ผู้ใช้เข้าใจ แผนรวมจึงใช้ Red เป็น delivery spine และ Blue เป็น experience contract

## 4. Decision log: Adopt / Modify / Reject

| ข้อเสนอ | คำตัดสิน | เหตุผล/เงื่อนไข |
| --- | --- | --- |
| Source-first: เลือกแหล่ง → preview/edit → confirm → practice | Adopt | ตรง Astra evidence และแก้ปัญหา input กระจัดกระจาย |
| AllTCAS hierarchy + Astra context/AI + Duolingo feedback loop | Adopt | เป็น interaction pattern ไม่ใช่การคัดลอก asset |
| Four destinations: เรียน/คลังคำ/ก้าวหน้า/โปรไฟล์ | Adopt | ตรง `DESIGN.md`; Weakness/Shop/Tutor เป็น contextual entry |
| รื้อ navigation ก่อน import | Modify | เลื่อนหลัง Card I1 เพราะ navigation/learning files มีงานแก้ค้างและ import ให้ value โดย write set แคบกว่า |
| A→B→C→D→E ตาม Blue | Modify | แทรก shell/evidence-feedback/shop/adaptive cards เพื่อปิด implementation gaps จริง |
| 8dp rhythm, 20dp compact gutter, 48dp controls | Adopt | ใช้เป็น baseline; อนุญาต 24dp gutter ตามพื้นที่และ safe inset ของ `DESIGN.md` |
| Primary CTA เดียวต่อ viewport | Adopt | ลด cognitive load; action รองใช้ outlined/text/menu |
| Messenger-style Socratic tutor | Adopt | reuse UI/controller เดิม; ไม่เพิ่ม chat SDK และไม่ persist transcript จนมี lifecycle |
| Reveal = wrong หนึ่งครั้ง; hint = no-write | Adopt | ใช้ stable attempt ID และ `LearningUseCases`; ป้องกัน mastery/reward ซ้ำ |
| Source provenance เป็น schema ใหม่ทันที | Modify | เริ่มด้วย metadata ที่ contract เดิมรองรับ; migration เฉพาะเมื่อ restart/resume ต้องใช้ entity ใหม่จริง พร้อม export/delete/sync |
| PDF/OCR dependency ตอนนี้ | Reject for current release | ทำ spike หลัง TXT/MD และ tutor ผ่าน; APK/memory/privacy ยังไม่มีหลักฐาน |
| 3D, podcast generation, printed exam, device handoff | Reject for current release | ต้นทุนสูงและไม่จำเป็นต่อวงจรหลัก |
| Multi-subject/school/national exam catalog | Reject | ขัด English-only และ product evidence |
| readiness/predicted exam score | Reject | ไม่มี calibration/model authority |
| FSRS ใหม่หรือ reward/mastery authority ใหม่ | Reject | ซ้ำระบบเดิมและเสี่ยงข้อมูลขัดกัน |
| theme/wallpaper store | Adopt with gate | cosmetic only, ใช้ `RewardUseCases`, ไม่มีเงินจริง, preview/contrast/offline-owned ต้องผ่าน |
| fresh Claude authorship ของ Blue | Reject claim | provider รอบใหม่ HTTP 524; ใช้ได้เฉพาะ evidence-derived plan |

## 5. Before → After: design, flow and system

### 5.1 Navigation and home

| ก่อน | หลัง |
| --- | --- |
| Bottom navigation อาจมี 6 จุดหมายและ drawer/FAB ซ่อนทางเข้าเพิ่ม | 4 จุดหมายคงที่: เรียน, คลังคำ, ก้าวหน้า, โปรไฟล์ |
| Home มีหลาย action แข่งกัน | แผนวันนี้ + งานถัดไปหนึ่งงาน + เหตุผลจาก evidence + action รอง |
| Weakness, rewards และ tutor มีโอกาสเป็น destination คู่ขนาน | Weakness อยู่ใน recommendation/result; Shop อยู่ใน Progress; Tutor เปิดจากบริบทคำ/แหล่งเรียน |

### 5.2 Import and content creation

| ก่อน | หลัง |
| --- | --- |
| วางข้อความ comma-separated และ import ทันที | เลือก CSV/JSON → validate → parse → preview/edit/reject → confirm |
| `split(',')` ทำให้ quoted comma ผิด | pure deterministic parser ที่มี fixture สำหรับ quoted fields/malformed rows |
| ไม่มีผลรวมที่อธิบายได้ | แสดง accepted/duplicate/rejected พร้อมทางแก้และ next action |
| AI อาจถูกมองเป็นข้อจำเป็น | local deterministic import และ match-first ทำงานได้เสมอ; AI เป็น optional enhancement |

### 5.3 Practice and feedback

| ก่อน | หลัง |
| --- | --- |
| กิจกรรมหลายหน้าใช้ feedback/state ต่างรูปแบบ | จังหวะเดียว: เลือก → ยืนยัน → บันทึก → feedback → ขั้นถัดไป |
| ผลลัพธ์อาจเน้นคะแนนหรือ XP | แสดง evidence รอบนี้, คำที่พลาด และ CTA ซ่อมจุดอ่อน |
| hint/reveal semantics ไม่ถูกตรึงทุก surface | hint ไม่เขียน; reveal บันทึก wrong หนึ่งครั้งผ่าน authority เดิม |

### 5.4 AI tutor

| ก่อน | หลัง |
| --- | --- |
| ชื่อ/provider และ response แบบทั่วไป | `ผู้ช่วยฝึกภาษาอังกฤษ`, source/context card และโหมด `ช่วยฉันคิดทีละขั้น` / `อธิบายให้เลย` |
| การสนทนาอาจจบใน chat | ทุกคำตอบมี action ที่เหมาะสม เช่น สร้างตัวอย่างหรือนำคำนี้ไปฝึก |
| online failure เป็น dead end | offline แสดง local guidance/match-only อย่างตรงไปตรงมาและไม่ปลอมว่าเป็น AI |

### 5.5 Theme marketplace

| ก่อน | หลัง |
| --- | --- |
| รายการซื้อ/ใช้แบบ list ไม่มี visual preview | balance → category → detail → preview → confirm → apply |
| state หลัง Back/rotate ยังไม่เป็น contract | คืน tab/scroll/preview context และ durable equipped state |
| cosmetic อาจแย่ง learning hierarchy | ร้านอยู่ใน Progress/Rewards และไม่ปลดล็อก mastery/learning capability |

### 5.6 Responsive model

- Compact `<600dp`: single pane, canonical 393×876dp; verify 360×800 และ 412×915
- Medium `600–839dp`: NavigationRail + focused/centered pane
- Expanded `840–1199dp`: list-detail เมื่อ usable list ≥320dp และ detail ≥480dp
- Large `1200–1599dp`: shell ≤1200dp, list-detail ใกล้ 42:58 และเพิ่ม outer space แทนยืด card
- Fold/tri-fold: ใช้ runtime display features/hinge; ยี่ห้อหรือรุ่นเป็น test matrix ไม่ใช่ breakpoint
- ทุกขนาดต้องรักษา selection, draft, scroll, import preview, quiz answer และ AI session ระหว่าง resize/rotate เท่าที่ state lifecycle อนุญาต

## 6. Role plan

| บทบาท | งานรับผิดชอบ | ผลส่งมอบ | Gate |
| --- | --- | --- | --- |
| PM | คุม outcome, dependency, card status, release boundary และ budget | roadmap, evidence links, risk/rollback, status board | ไม่เปิด card ที่ predecessor/authority ยังไม่พร้อม |
| SA | คุม write boundary, owner isolation, provenance, schema และ failure modes | context/data-flow, authority map, migration impact | ไม่มี authority คู่ขนาน; local path ไม่ขึ้นกับ AI |
| BA | แปลง evidence เป็น English-only journey และ copy ไทยทั่วไป | journey/state/copy matrix, 8/44 traceability | ผู้ใช้รู้ว่าทำอะไรต่อและไม่มี claim เกินหลักฐาน |
| UX | วาง hierarchy, responsive, accessibility และ component states | screen/state specs, route/back map, responsive specimens | 48dp, contrast, font scale, IME, TalkBack, one CTA ผ่าน |
| Dev | reuse ของเดิมและทำ smallest complete diff | code, focused tests, migration/dependency statement | cancel no-write, retry no-duplicate, restart durable |
| QA | ตรวจ behavior, authority, layout และ recovery | unit/widget/golden/integration/device evidence | แยก pass/fail/not-run/not-verified ตาม source snapshot |

หนึ่ง shared file มี writer เดียว และ Flutter test/build/dependency/codegen ใน worktree นี้ต้องรันแบบ serialized

## 7. Ordered ADLC cards

### I0 — Ground and ownership checkpoint

**สถานะ:** `READY`
**ADLC:** Intent → Ground → Plan
**Outcome:** ตรึง source snapshot, owner ของ dirty files และ traceability ของ journey หลักโดยไม่แก้โค้ด
**Dependencies:** ไม่มี

**File impact:** checkpoint/plan ที่ task owner ระบุ; ห้ามแก้ production codeใน card นี้

**Acceptance:**

- ระบุ branch/dirty files และ writer ownership โดยเฉพาะ navigation/quiz/score/weakness
- map `screen/action → route → authority → f01–f44 → test`
- ระบุแต่ละรายการเป็น designed/implemented/verified/release-ready
- ไม่มีการถือว่า Figma frame หรือเอกสารเท่ากับ runtime implementation

**Tests/evidence:** focused `git status`, `rg` callers/routes/registries/tests และ checkpoint ที่อ้าง source snapshot

### I1 — CSV/JSON file import with preview

**สถานะ:** `DESIGNED / NOT IMPLEMENTED / NOT VERIFIED`
**ADLC:** Execute → Review → Attest
**Outcome:** คลังคำรับไฟล์ CSV/JSON แบบ local, preview/edit/cancel และ persist ผ่าน `ImportVocabulary`
**Dependencies:** I0 ownership checkpoint

**File impact:**

- `lib/screens/vocab_list_screen.dart`
- `lib/screens/add_multiple_words_screen.dart`
- pure parser/model ใต้ `lib/features/vocabulary/application/` เฉพาะเมื่อไม่มี equivalent
- `lib/features/vocabulary/application/import_vocabulary.dart` เฉพาะ contract ปัจจุบันไม่พอ
- wiring ใน `lib/runtime/app_dependencies.dart` หรือ bootstrap เฉพาะที่จำเป็น
- `test/features/vocabulary/import_vocabulary_test.dart`
- parser/widget tests ใหม่ใกล้ implementation
- `test/screens/offline_vocabulary_journey_test.dart`

**Implementation rules:**

- ใช้ `file_selector` เดิม; ไม่เพิ่ม dependency
- validate extension, MIME เมื่อเชื่อถือได้, byte size และ row count ก่อน persist
- CSV รองรับ quoted comma; ห้ามใช้ `split(',')` สำหรับไฟล์
- preview แยก ผ่าน/ต้องแก้/ซ้ำ และ TalkBack ต้องอ่านสถานะได้โดยไม่พึ่งสี
- confirm เท่านั้นจึงเรียก `ImportVocabulary`; ไม่เก็บ full path/file bytes ใน event/log
- legacy `WordbookImportScreen`/`CustomWordbookImporter` ไม่ขยายและยังไม่ลบจนยืนยัน caller

**Acceptance:** malformed/empty/oversize/unsupported/cancel ไม่เขียนข้อมูล; แก้ rejected row ได้; retry/restart ไม่สร้าง duplicate; owner isolation ผ่าน; totals ตรง repository result; offline restart เห็นข้อมูล

**Focused tests:** parser fixtures, `flutter test --no-pub test/features/vocabulary/import_vocabulary_test.dart`, widget import test และ `test/screens/offline_vocabulary_journey_test.dart`

### I2 — Four-destination shell and design foundation

**สถานะ:** `DESIGNED / PARTIALLY IMPLEMENTED / NOT VERIFIED`
**Outcome:** Flutter shell ตรง `เรียน / คลังคำ / ก้าวหน้า / โปรไฟล์` โดยรักษา flags/deep routes/back
**Dependencies:** I0; เริ่มเมื่อ writer ของ dirty navigation files ส่งมอบหรือ reconcile แล้ว

**File impact:** `lib/screens/main_navigation_screen.dart`, `choose_mode_screen.dart`, progress/profile screens, `lib/config/m3_theme.dart`, navigation/layout/golden tests

**Acceptance:** ไม่เกิน 4 destinations; local learning ยังเข้าได้เมื่อ provider unavailable; 360/393/412 ไม่มี overflow; medium ใช้ rail; 48dp, light/dark, 130/200% text, system Back และ feature states ผ่าน

**Focused tests:** `test/screens/main_navigation_screen_test.dart`, `production_shell_navigation_test.dart`, `learning_loop_layout_test.dart`, `test/config/m3_theme_test.dart` และ touched goldens

### I3 — Evidence feedback consistency

**สถานะ:** `DESIGNED / PARTIALLY IMPLEMENTED / NOT VERIFIED`
**Outcome:** Quiz/SRS/Score/Weakness ใช้ save-feedback-next semantics เดียวกัน
**Dependencies:** I0 และ dirty-file reconciliation; ทำคู่กับ I2 ได้เฉพาะ write set ไม่ทับ

**File impact:** `quiz_screen.dart`, `srs_flashcards_screen.dart`, `score_screen.dart`, `weakness_clinic_screen.dart`, `LearningUseCases` เฉพาะ contract gap และ tests/goldens ที่เกี่ยวข้อง

**Acceptance:** failure-before-write เก็บคำตอบให้ retry; lost acknowledgement ไม่สร้าง answer/reward ซ้ำ; reveal wrong ครั้งเดียว; hint no-write; feedback มีคำตอบผู้ใช้/คำตอบถูก/next action; สีไม่เป็นสัญญาณเดียว; large text เลื่อนถึง CTA

**Focused tests:** learning use-case/repository tests, quiz/SRS/weakness screen tests, layout/golden tests

### I4 — TXT/Markdown source-to-practice

**สถานะ:** `DESIGNED / NOT IMPLEMENTED / NOT VERIFIED`
**Outcome:** นำเข้าแหล่งภาษาอังกฤษหนึ่งชุดและเปิด Reading/Flashcard/Quiz/Fill/Voice/Ask Lexi ผ่าน authority เดิม
**Dependencies:** I1 และ I3

**File impact:** vocabulary import application, source/session model เฉพาะจำเป็น, related practice screens, repository/schema เฉพาะเมื่อ provenance ต้อง survive restart, export/delete/sync tests หากเพิ่ม entity

**Acceptance:** English-content gate; local match-first; unknown no-auto-import; preview/edit ก่อนเขียน; AI failure ไม่หยุด local practice; raw source ไม่เข้า telemetry/implicit queue; source revision stale มีทาง re-import; flow จบ Result/Weakness

**Focused tests:** deterministic extraction fixtures, offline/slow-network fixtures, restart/resume, reveal/hint idempotency, owner isolation; migration/export/delete/sync checksเฉพาะเมื่อมี schema

### I5 — Socratic Messenger-style tutor

**สถานะ:** `DESIGNED / PARTIALLY IMPLEMENTED / NOT VERIFIED`
**Outcome:** `ผู้ช่วยฝึกภาษาอังกฤษ` มีโหมดคิดทีละขั้น/อธิบายให้เลยและส่งผู้ใช้กลับไปฝึกได้
**Dependencies:** I2; source actions เต็มรูปแบบหลัง I4

**File impact:** `lib/screens/ai_tutor_screen.dart`, Gemini contracts/use cases/gateway tests; backend `/v1/content` เฉพาะ structured field ที่จำเป็น

**Acceptance:** one in-flight; input/turn/session budget; consent/key/quota/timeout/cancel/offline/edit/retry states; IME ไม่บัง composer; draft/session state ทน resize; provider provenance เป็นข้อมูลรอง; transcript ไม่ persist จนมี lifecycle; AI ไม่เขียน mastery/reward; practice action ใช้ use case เดิม

**Focused tests:** AI tutor widget/use-case/gateway/backend contract tests, IME/large-text golden, offline/slow/timeout fixtures และ secret/log inspection

### I6 — Theme and wallpaper marketplace

**สถานะ:** `DESIGNED / PARTIALLY IMPLEMENTED / NOT VERIFIED`
**Outcome:** ค้นพบ พรีวิว ซื้อ และใช้ cosmetic ผ่าน reward authority เดิม
**Dependencies:** I2

**File impact:** `lib/screens/shop_page.dart`, wallpaper/theme selection, reward catalog/use cases เฉพาะ gap, theme composition root หนึ่งจุด, reward/shop/theme tests

**Acceptance:** preview ก่อนซื้อ/equip; retry/double-tap ไม่หักซ้ำ; insufficient/stale/offline-owned/restart ถูกต้อง; applied theme อ่าน equipped state เดิม; contrast/font/touch targets ไม่ลด; Back คืน tab/scroll; ไม่มีเงินจริง

**Focused tests:** `test/features/rewards/reward_use_cases_test.dart`, reward repository/projection tests, shop/widget/theme tests และ dark/large-text golden

### I7 — Adaptive Android verification

**สถานะ:** `DESIGNED / NOT VERIFIED`
**Outcome:** ยืนยัน implementation จริงบน viewport และ posture ตาม contract
**Dependencies:** integration snapshot ของ I1–I6

**Matrix:** 360×800, 393×876, 412×915; 599/600, 839/840, 1199/1200; 600×960, 800×1280, 1024×1366, 1280×800; compact height 479/480; Android foldable emulator; physical device เมื่อพร้อม

**Acceptance:** ไม่มี overflow/clipping/inset/IME obstruction; selection/draft/scroll/preview/answer คงอยู่ตาม state contract; TalkBack order/focus restoration/48dp/contrast ผ่าน; fold/device ที่ยังไม่รันต้องระบุ `not verified`

### I8 — PDF/OCR go/no-go spike

**สถานะ:** `DEFERRED / NOT IMPLEMENTED / NOT VERIFIED`
**Outcome:** ตัดสิน dependency ด้วยหลักฐาน ไม่ใช่เพิ่ม feature ล่วงหน้า
**Dependencies:** I1–I5 ผ่าน focused acceptance

**Scope:** ทดลอง `pdfrx` กับ digital PDF และ ML Kit OCR กับภาพ/scan; วัด APK/startup/memory/latency, encrypted/malformed/oversize, rotation/low-light, offline/data locality และ temp-file deletion

**Go gate:** ทุกผล OCR ผ่าน preview/edit/retake/delete/confirm; ไม่มี raw upload/log; device/APK budget ผ่านค่าที่ PM/SA ตรึงก่อน spike หากไม่ผ่านให้คง CSV/JSON/TXT/MD ซึ่งส่งมอบ core value ได้แล้ว

## 8. Status ledger

| พื้นที่ | Designed | Implemented | Verified | Release-ready |
| --- | --- | --- | --- | --- |
| Source-first flow | Yes | Partial | No | No |
| CSV/JSON picker + preview | Yes | No | No | No |
| TXT/MD local match-first | Yes | No | No | No |
| Four-destination shell | Yes | Partial; runtime ยังมี 6/drawer | No | No |
| Evidence feedback loop | Yes | Partial | Focused evidence มีบางส่วน | No |
| Socratic tutor modes | Yes | Partial shell only | No | No |
| Theme/wallpaper marketplace | Yes | Purchase/equip partial | Authority tests มีบางส่วน | No |
| Compact responsive | Yes | Partial | บาง widget/golden เท่านั้น | No |
| Tablet/foldable | Yes | Unknown/partial | No runtime evidence | No |
| PDF/OCR | Deferred design | No | No | No |

สถานะนี้ต้องอัปเดตจาก source snapshot เดียวกันหลังแต่ละ integration checkpoint; ห้ามยกผล test เก่ามารับรอง diff ใหม่

## 9. Verification and attestation

ทุก card ใช้ลำดับ: focused unit → widget/domain → touched subsystem → integration checkpoint เท่านั้น ไม่รัน full suite หลังทุก diff

ตัวอย่างคำสั่งตามไฟล์ที่แตะ:

```powershell
dart format --output=none --set-exit-if-changed <touched Dart files>
flutter analyze --no-pub <touched Dart files>
flutter test --no-pub test/features/vocabulary/import_vocabulary_test.dart
flutter test --no-pub test/screens/offline_vocabulary_journey_test.dart
flutter test --no-pub test/features/learning test/features/rewards
flutter test --no-pub test/screens/main_navigation_screen_test.dart test/screens/learning_loop_layout_test.dart
flutter test --no-pub test/screens/accessibility_smoke_test.dart
```

ก่อน integration/release checkpoint ให้รัน required repository suite บน source snapshot คงที่ พร้อม evidence manifest ที่ระบุ command/result/reason, review disposition และ release dependencies

## 10. Release boundaries and rollback

- Engineering-complete ไม่เท่ากับ release-ready และไม่อนุญาต deploy/publish
- Production research enrollment/upload ยังคงปิด; งานเรียนปกติห้ามขึ้นกับ research consent
- ไม่มี data migration ใน I1–I3 โดยปริยาย หาก I4 ต้องเพิ่ม provenance entity ต้องมี migration, owner isolation, export, deletion และ sync/policy coverage ก่อน merge
- AI เป็น optional path; ปิด feature/provider แล้ว deterministic local learning ยังทำงาน
- Shop ไม่มีเงินจริง; reward balance/mastery แยก authority กัน
- Navigation rollout ต้องรักษา deep routes และสามารถ rollback shell โดยไม่ rollback learning data
- PDF/OCR อยู่หลัง feature/dependency gate และไม่อยู่ใน release แรกของแผนนี้
- Device/foldable/physical evidence ที่ไม่รันต้องเขียน `not verified`; ห้ามอนุมานจาก Figma หรือ widget test

## 11. First executable step

เริ่มที่ **I0 + I1, test-first ใน write set ของ vocabulary import เท่านั้น**:

1. บันทึก source snapshot และยืนยันว่าไม่มี writer อื่นถือ `add_multiple_words_screen.dart` / vocabulary import files
2. อ่าน caller ทั้งหมดของ `AddMultipleWordsScreen` และ `ImportVocabulary`
3. เพิ่ม focused failing parser tests สำหรับ quoted comma, malformed row, empty, unsupported/oversize และ duplicate preview
4. ทำ pure parser/model ขั้นต่ำ และ file-picker entry ที่ใช้ `file_selector`
5. เพิ่ม preview/edit/cancel; confirm เท่านั้นเรียก `ImportVocabulary`
6. รัน import domain/widget/offline restart tests และตรวจ diff ว่าไม่มี full path/raw bytes/logging
7. ออก review disposition และ evidence manifest ก่อนเปลี่ยน I1 เป็น `Done` หรือเปิด I4

งานแรกนี้ไม่ต้องแก้ navigation, learning authority, schema, backend หรือ Figma จึงลด conflict และให้ user-visible value ที่พิสูจน์ได้เร็วที่สุด

## 12. Definition of done for this plan

แผนรวมถือว่าออกแบบเสร็จเมื่อทุก card มี outcome, dependency, write set, acceptance และ evidence ตามเอกสารนี้ ส่วนระบบถือว่าเสร็จเมื่อ:

1. I1–I7 ผ่าน acceptance บน source snapshot ปัจจุบัน
2. 8/44 mapping ไม่มี ID เพิ่มและ authority/data invariants ยังผ่าน
3. import → restart → practice → feedback → result → weakness ทำงาน offline
4. AI/tutor/shop failure ไม่ทำลายหรือปิดกั้น local learning
5. accessibility/responsive/device evidence ถูกบันทึกตามสิ่งที่รันจริง
6. review ไม่มี must-fix ค้าง และ evidence manifest แยก engineering/release/external dependencies

I8 เป็น go/no-go หลัง core loop เสถียร จึงไม่ขวาง engineering completion ของ release แรก

## 13. Chat workstreams and 250-credit operating budget

ส่วนนี้กำหนดวิธีแยกงานเป็นแชทย่อยโดยไม่แยก authority หรือสร้างแผนซ้ำ แชททุกตัวใช้ repository, plan, checkpoint และ source snapshot เดียวกัน แชทส่งมอบห้ามถือว่าข้อความในแชทอื่นเป็นหลักฐานจนกว่าจะถูกบันทึกใน checkpoint และตรวจจาก source ปัจจุบัน

### 13.1 รูปแบบการทำงานร่วมกับ Claude

- Codex เป็น operator และเจ้าของการแก้ไฟล์ ทดสอบ รวมงาน และ evidence ตาม ADLC
- Claude เป็น design/architecture critic ประจำทุกแชท: ช่วย Ground/Plan ก่อนแก้ และทำ adversarial review หลัง focused checks
- คำแนะนำจาก Claude เป็น proposal จนกว่า Codex จะตรวจเทียบ source, tests, schema ledger, 8/44 catalog และ guardrails
- ห้ามส่ง secret, API key, PII, participant data, raw research answers หรือ private channel refs ให้ Claude
- การเรียก Claude แต่ละครั้งรอผลได้สูงสุด 360 วินาที ซึ่งอยู่ในช่วงเผื่อ 300–400 วินาทีสำหรับงานวิเคราะห์หรือ critique ที่ใช้เวลานาน
- เมื่อครบ 360 วินาที ให้ตรวจสถานะคำขอเดิมก่อน retry; retry ได้อีกหนึ่งครั้งเฉพาะเมื่อยืนยันว่า request เดิมล้มเหลวและจะไม่คิดงานซ้ำ หากผลยังไม่แน่นอนให้หยุดเส้นทางนั้นและรักษางบเครดิต
- ถ้า Claude endpoint timeout/unavailable หลัง recovery budget แชทนั้นทำงาน local ต่อได้ และบันทึก `Claude review: not available`; ห้ามอ้างว่าได้ fresh Claude review
- เครดิตในตารางเป็น operating cap เพื่อควบคุมรอบวิเคราะห์/วิจารณ์ ไม่ใช่คำรับรองยอดเรียกเก็บของผู้ให้บริการภายนอก

ทุกแชทใช้ Claude อย่างมากสองจังหวะต่อการ์ด: (1) architecture/UX challenge ก่อนเขียน และ (2) review diff/evidence หลัง focused tests เว้นแต่แชทควบคุมอนุมัติใช้ reserve สำหรับ must-fix ที่มีหลักฐานใหม่

### 13.2 แชทและงบเครดิต

| Chat | ขอบเขตส่งมอบ | Card/ลำดับเดิม | เครดิตสูงสุด | Write-set owner หลัก |
| --- | --- | --- | ---: | --- |
| `LQ-00 Program Control & Integration` | checkpoint R11, task board, contract registry, merge/integration evidence, conflict resolution | 1 และ integration ทุก Wave | 30 | plan/checkpoint/status ledger; shared contracts เฉพาะช่วง integration |
| `LQ-01 Design, Responsive & Figma` | LDPlayer/device matrix, accessibility/layout fixes, R11 Cloud sync และ visual acceptance | 2–3, I2, I7 | 25 | design tokens, adaptive shell/layout tests, Figma artifacts |
| `LQ-02 Identity & Account` | Google/email auth, register/reset/session/sign-out, profile lifecycle, export/delete account และ owner isolation | 4 | 28 | auth/account/profile modules และ tests |
| `LQ-03 Vocabulary & Source Import` | CSV/JSON/TXT/MD picker, preview/edit/cancel, duplicate/owner/offline behavior | 5, I1, I4 | 30 | vocabulary/import modules และ tests |
| `LQ-04 Activities, Progress & Mastery` | activity catalog, exercise/result semantics, SRS/weakness, progress/mastery/streak/reward projection | 6–7, I3 | 38 | learning/activity/progress modules; reward contract ผ่าน LQ-00 |
| `LQ-05 Theme Marketplace` | theme/template/wallpaper catalog, preview, purchase/equip, owned/offline/restart states | 8, I6 | 24 | shop/theme UI และ reward use-case caller; ไม่สร้าง balance authority ใหม่ |
| `LQ-06 AI Tutor, Voice & Camera` | Messenger-style tutor, practice handoff, voice/camera permission/failure/hardware journeys | 9–10, I5 | 30 | tutor/media-practice UI, gateways และ focused tests |
| `LQ-07 Settings, Offline & Sync` | settings/account preferences, connectivity states, outbox/conflict/restart และ export/deletion integration | 11–12 | 25 | settings/sync/outbox modules; schema changesผ่าน LQ-00 |
| `LQ-08 Research & Release Gate` | research default-off gates, synthetic/emulator evidence, release candidate matrix และ final attestation | 13–14 | 10 | research/release evidence และ gate scripts; production rolloutยังไม่อนุญาต |
| `Cross-review reserve` | Claude/Codex review เพิ่มเติมเฉพาะ must-fix ข้ามโมดูลหรือ integration regression | ทุกแชทผ่าน LQ-00 | 10 | ไม่มี write set ถาวร |
| **รวม** |  |  | **250** |  |

เครดิตที่เหลือจากแชทหนึ่งคืนเข้า `Cross-review reserve`; ห้ามแชทอื่นดึงไปใช้เอง การชนเพดานเครดิตไม่ลด acceptance checks และไม่อนุญาตให้ข้าม validation, accessibility, security หรือ hardware calibration

### 13.3 Dependency waves

```text
Wave 0: LQ-00  checkpoint + ownership + contract registry
Wave 1: LQ-01  ||  LQ-02  ||  LQ-03
Wave 2: LQ-04  ||  LQ-06 (ส่วน tutor หลัง auth/import) || LQ-07 (ส่วน settings)
Wave 3: LQ-05  ||  LQ-06 (voice/camera) || LQ-07 (offline/sync)
Wave 4: LQ-08  release integration and evidence
```

กฎเปิดงาน:

- LQ-01, LQ-02 และ LQ-03 เปิดพร้อมกันได้หลัง LQ-00 ตรึง source snapshot และ writer ownership
- LQ-04 เปิด activity implementation หลัง vocabulary contract จาก LQ-03 พร้อม; progress/reward projection ต้องให้ LQ-00 ตรึง result/reward contract ก่อน
- LQ-05 เปิด purchase/equip หลัง reward authority ของ LQ-04 ผ่าน domain tests
- LQ-06 เปิด tutor UI หลัง auth/session จาก LQ-02 พร้อม และเปิด source-aware handoff หลัง LQ-03 พร้อม; voice/camera ทำแยกได้เมื่อ permission write set ไม่ทับ
- LQ-07 ทำ settings UI ได้ใน Wave 2 แต่ offline/sync integration รอ schema และ owner-scoped entities ของ LQ-02/LQ-03/LQ-04 นิ่ง
- LQ-08 เริ่มเตรียม matrix แบบ read-only ได้ก่อน แต่ final release snapshot รอทุกแชทส่ง review disposition และ evidence manifest

### 13.4 Shared files and serialization

LQ-00 เป็นผู้จัดคิวสำหรับ `main_navigation_screen.dart`, theme tokens, route registry, dependency manifests, database schema/migrations, shared learning/reward contracts และ feature registry แชทส่งมอบต้องเสนอ patch/contract ผ่าน checkpoint ก่อนแตะ shared file; มี writer ได้ครั้งละหนึ่งราย

Flutter test/build, dependency resolution, database/code generation และ repository-wide analysis รันทีละงานใน worktree นี้ แชทที่กำลังรอคิวทำ read-only review, fixtures หรือ documentation ที่ไม่ชนกันได้ แต่ห้ามใช้ผลทดสอบที่รันระหว่าง source เปลี่ยนเป็น integration evidence

### 13.5 Handoff contract ของทุกแชท

ก่อนส่งกลับ LQ-00 ทุกแชทต้องบันทึก checkpoint ที่มีข้อมูลต่อไปนี้:

```text
Chat / card / source branch and snapshot
Outcome and user-visible behavior
Changed files and shared-file touches
Contracts/schema/route/feature IDs affected
Focused checks with exact result
Claude review: fresh | evidence-derived | not available
Review disposition: accepted | must-fix | follow-up | not verified
Device/external/release dependencies
Next executable step
```

คำว่า `Done` ใช้ได้เมื่อ diff, focused checks และ review disposition อ้าง source snapshot เดียวกันเท่านั้น ผล Figma, Claude critique หรือ unit test บางส่วนไม่เท่ากับ runtime integration

### 13.6 หน้าที่ของ LQ-00 ระหว่างทุก Wave

1. ตรวจ checkpoint และ actual diff ไม่รับสถานะจากคำบอกเล่า
2. ตรวจ route, authority, schema, export/delete, sync/policy และ 8/44 traceability ที่ได้รับผลกระทบ
3. คืน must-fix ให้แชทเจ้าของเดิม ไม่แก้ข้าม write set แบบเงียบ ๆ
4. freeze source แล้วรัน touched subsystem/integration checks แบบ serialized
5. อัปเดต status ledger และเปิดเฉพาะแชทที่ predecessor พร้อม
6. เก็บ Cross-review reserve สำหรับ defect ข้ามโมดูล ไม่ใช้สร้าง feature เพิ่ม

### 13.7 Exit criteria ของโครงสร้างแชท

- ไม่มี shared file ที่มี writer พร้อมกันมากกว่าหนึ่งแชท
- เครดิตจัดสรรรวมและ reserve ไม่เกิน 250
- ทุกแชทมี Claude review status ที่ตรวจสอบได้โดยไม่อ้างเกินหลักฐาน
- ทุก Wave มี source freeze, integration evidence และ must-fix disposition
- engineering-complete, release-ready, deployment permission และ research authority ยังคงเป็นคนละสถานะ
