# LexiQuest R11 implementation map

วันที่: 2026-10-20
สถานะ: Card D1 — implementation handoff
Design baseline: R11 source hash `746354255a39619732391ad2f0f6a67377a7b2337231006331fef0e538091e10`

## 1. จุดประสงค์และขอบเขต

เอกสารนี้แปลง Figma R11 จำนวน **240 specimens** ให้เป็นโครงสร้าง Flutter ที่นำไปพัฒนาได้ โดยยึดหลักว่า specimen คือหลักฐานของหน้าจอ สถานะ หรือขนาดหน้าต่าง ไม่ใช่คำสั่งให้สร้าง widget ระดับหน้าจอ 240 ตัว

แหล่งอ้างอิงคือ:

- `tmp/figma/preview-v9/manifest.json` และ `routeManifest` 942 เส้นทาง
- `docs/design/figma-prototype-flow-map.md`
- `PRODUCT.md`, `DESIGN.md` และ feature catalog 8 หมวด/44 ความสามารถ
- route, screen, use case และ repository ที่มีอยู่ใน `lib/`

ผลลัพธ์เป้าหมายคือ **22 canonical UI families** ประกอบกันเป็น route surfaces และ state variants ทั้งหมด การเพิ่ม state ต้องขยาย family เดิมก่อนสร้าง screen ใหม่

ข้อจำกัดสำคัญ:

- R11 local preview/generator เป็น baseline ของเอกสารนี้; Figma Cloud ยังอาจแสดง R10
- Android-first, English-learning-only, local-first
- Main navigation ใช้ 4 จุดหมายแล้ว: เรียน, คลังคำ, ก้าวหน้า, โปรไฟล์
- Prototype แสดงความตั้งใจของ UX ไม่ได้ยืนยันว่า authority, entitlement หรือ persistence ของทุกฟีเจอร์พร้อม production
- AI, โน้ต, notification automation, curriculum graph และงานวิจัยจริงต้องคง hidden/limited จน contract และ acceptance ของแต่ละระบบพร้อม

## 2. Canonical families — ไม่ใช่ 240 widgets

| ID | Canonical family | หน้าที่ | Target composition | Route/state role |
|---|---|---|---|---|
| C01 | `AdaptiveAppScaffold` | shell, safe area, navigation, pane policy | app bar + NavigationBar/Rail + content slot | root shell และ responsive wrapper |
| C02 | `RootHubSurface` | งานถัดไปหนึ่งงานและบริบทประกอบ | next-action card + compact status + supporting content | root: เรียน/คลังคำ/ก้าวหน้า/โปรไฟล์ |
| C03 | `AuthFormSurface` | login/register/reset/verify | form fields + validation + provider action + IME-safe CTA | full route; idle/busy/error/success |
| C04 | `AccountLifecycleSurface` | link/merge/export/delete account | account summary + consequence + re-auth step | route + destructive confirmation chain |
| C05 | `CatalogListSurface` | catalog/category/history/search lists | filters + list/grid + empty/loading/error | root/nested list; optional selected item |
| C06 | `EntityDetailSurface` | word/pack/evidence/theme/session detail | title + provenance/status + actions | nested detail; right pane on wide windows |
| C07 | `SettingsListSurface` | grouped preferences/account/help | sectioned settings + control rows | root/nested settings; saved/error state |
| C08 | `StepWizardSurface` | onboarding, goal, consent choice, setup | progress + one decision + back/continue | sequential routes or local page state |
| C09 | `ActivityPickerSurface` | เลือกกิจกรรม หมวด และตั้งค่ารอบ | grouped choices + availability + primary CTA | route; selection/configuration states |
| C10 | `PracticeShell` | prompt เดียวและ action คงตำแหน่ง | progress + prompt slot + response slot + action area | active-session route; input variants |
| C11 | `SavedFeedbackSurface` | feedback หลัง persistence | status + explanation + repair/next actions | state of active session; retry on save failure |
| C12 | `SessionSummarySurface` | result, reward acknowledgement, next step | evidence summary + mistakes + one next action | terminal route; no back into finished session |
| C13 | `FlashcardReaderSurface` | flashcard, article, associative reading | content viewport + reveal/checkpoint + rating/stage | active learning route; resumable state |
| C14 | `TutorChatSurface` | Lexi chat/Socratic flow | message list + provenance + composer + attachment actions | nested route; sending/error/quota/offline |
| C15 | `ProgressEvidenceSurface` | mastery, weakness, plans, calendar, history | metric/evidence blocks + recommendation | root/detail; loading/N=0/error |
| C16 | `ChallengeSurface` | self-duel, games, timed challenge | challenge status + task slot + result transition | active route; reward posted once |
| C17 | `ImportEditorSurface` | add/batch/import/review before write | source chooser + editable rows + validation summary | route; parse/review/import/partial-failure |
| C18 | `MediaToolSurface` | speech, audio, camera, scanner | permission-aware tool viewport + fallback/result | full route; permission/model/provider states |
| C19 | `RewardMarketplaceSurface` | catalog, preview, purchase, owned items | balance + item catalog/detail + transaction state | nested routes/overlays; idempotent purchase |
| C20 | `ResearchDataSurface` | consent, assignment, export and internal evidence | authority summary + consent/status + data action | gated route/overlay; default-off |
| C21 | `AsyncStateSurface` | loading, empty, offline, denied, unavailable, error | preserved layout or compact state panel + recovery | inline/full replacement; never a new domain screen |
| C22 | `ModalActionSurface` | dialog/bottom sheet/context action | title + consequence/context + primary/secondary action | overlay; dismiss/destructive rules explicit |

จำนวน canonical families: **22**. `C01` เป็น wrapper และ family อื่นเป็น surface/slot; responsive specimens ใช้ composition เดิมและเปลี่ยน pane policy ไม่ fork business UI ตามยี่ห้ออุปกรณ์

## 3. Authority และ use-case map

| Concern | Authority/use case ที่ต้องเรียก | Current implementation/reuse | กฎส่งมอบ |
|---|---|---|---|
| Session/account | `AccountUseCases`, `FirebaseAccountGateway`, `GuestSessionService`, `UpgradeGuestOwner` | `login_screen.dart`, `register_screen.dart`, `otp_screen.dart`, `email_action_screen.dart` | UI ห้ามเขียน Firebase/owner mapping โดยตรง; merge/delete ต้อง re-auth และแสดงผลลัพธ์จริง |
| Active owner | `LocalOwnerRepository` | `DriftLocalOwnerRepository` | owner scope มาก่อน read/write ทุก domain |
| Vocabulary | `VocabularyUseCases`, `VocabularyRepository` | `VocabListScreen`, `CategoriesPage`, `AddWordScreen` | duplicate/limits/validation อยู่ที่ authority; UI รักษา draft เมื่อผิดพลาด |
| Import | `ImportVocabulary`, `VocabularyImportRepository` | `AddMultipleWordsScreen`; เส้นทาง `CustomWordbookImporter`/`WordbookImportScreen` เป็น legacy | preview/edit/cancel ก่อน commit; retry ต้องไม่ duplicate |
| Learning/SRS/reading | `LearningUseCases`, `LearningRepository`, `BinarySm2SrsPolicy` | `QuizScreen`, `SrsFlashcardsScreen`, `AssociativeReadingSessionScreen`, `DriftLearningRepository` | feedback แสดงหลัง `recordAnswer` สำเร็จ; save failure ห้ามเดินข้อถัดไป; reveal/hint ใช้ `promptMode` เดียวกันและไม่สร้าง authority ใหม่ |
| Progress/weakness | `ProgressUseCases` + progress queries/projections | `MasteryDashboardScreen`, `WeaknessClinicScreen`; legacy `ProgressRepository` ใช้ผ่าน adapter ระหว่างย้าย | mastery มาจาก evidence; XP/time/reward ห้ามแทน mastery |
| Quest/streak | `QuestUseCases`, `QuestRepository`, streak policy/use cases | answer event sink จาก `LearningUseCases` | learning success เป็นต้นทางเดียว; failure ของ motivation ไม่ทำให้ learning fail |
| Rewards/theme | `RewardUseCases`, `DriftRewardRepository`, `RewardCatalog` | `ShopPage`, `AvatarEquipmentScreen`, `SelectWallpaperScreen` | balance/purchase/idempotency มาจาก authority; transaction replay ไม่หักซ้ำ |
| AI tutor | `GeminiTutorUseCases`, `GeminiSettingsStore`, `GeminiGateway` | `AiTutorScreen`, `GeminiSettingsScreen`, secure store | one request in flight; offline/quota/provider failure กลับไป learning local ได้; key ไม่แสดงหลังบันทึก |
| Voice/camera/model | `VoiceUseCases`, `SpeechPracticeUseCases`, `ObjectScannerUseCases`, `DeviceModelUseCases` | plugin speech/camera gateways, `ObjectScannerScreen`, voice/audio screens | ขอ permission หลัง explicit action; permanent denial มี settings path; unverified scan ต้องยืนยันก่อนบันทึก |
| Research consent | `ResearchConsentUseCases`, `ResearchConsentRepository` | `research_consent_dialog.dart`, `DriftResearchConsentRepository` | default-off; decline/withdraw ไม่ปิด learning; real enrollment/upload ต้องผ่าน permit/assignment/protocol gates เพิ่มเติม |
| Export | `ExportUseCases`, `ExportArtifactStore` | `ExportCenterScreen` | format/selection/owner scope ชัด; cancel ไม่สร้าง artifact; research export gated แยก |
| Sync/offline | `SyncEngine`, `CloudSyncPolicy`, sync store/gateway | Drift/Firestore sync components | local learning ทำต่อได้; unavailable authority fail closed เฉพาะ cloud/research |
| Navigation | target route registry + `AppNavigator` | `AppRouteFactory`/`AppRoute` ปัจจุบันครอบคลุมเพียง login/register/verification/home | ขยาย route table ทีละ vertical slice; 942 prototype reactions ไม่แปลเป็น 942 named Flutter routes |
| Settings/help/appearance | app settings authority และ secure preference store ที่มีอยู่ | `SettingScreen`, `ProfileSettingsScreen`, M3 theme config | แยก device preference, account data และ provider secret; saved stateต้องมาจาก persistence acknowledgement |

ฟีเจอร์ที่ยังไม่มี authority ครบให้แสดง `limited/hidden` ตาม feature registry เท่านั้น ห้ามสร้าง local counter, mock readiness, parallel reward/progress store หรือเมนูที่กดแล้วไม่มีปลายทาง

## 4. Coverage map ครบ 240 specimens

ชื่อในแต่ละแถวเป็น exhaustive primary assignment: specimen แต่ละรายการถูกนับหนึ่งครั้ง แม้ implementation จริงจะ compose หลาย family

### Section A — Vivo Canonical (43)

| Count | Specimens | Canonical family | UI state / route role | Authority + acceptance focus |
|---:|---|---|---|---|
| 2 | `01 Welcome`, `28 เข้าสู่ระบบ` | C03 | entry/login route | account/guest; validation, offline, IME-safe CTA |
| 3 | `02 Daily Quest Home`, `10 Home · Updated`, `15 Profile` | C01+C02 | 4-destination roots | owner/quest/progress; one primary action, restore selected tab |
| 4 | `03 เลือกแบบฝึก`, `17 เลือกหมวดคำ`, `23 เมนูทั้งหมด`, `29 เลือกหมวดคำ · เลือกแล้ว` | C05+C09 | catalog/selection | availability and empty/error; no dead menu |
| 5 | `04 ตอบคำศัพท์ · เลือกแล้ว`, `30 ตอบคำศัพท์ · ยังไม่เลือก`, `31 ตอบคำศัพท์ · เลือกคำตอบอื่น`, `35 ตอบคำศัพท์ · เลือกข้อ 3`, `36 ตอบคำศัพท์ · เลือกข้อ 4` | C10 | question input variants | `LearningUseCases`; lock double submit, ≥48dp choices |
| 4 | `05 Saved Feedback`, `05B Wrong Feedback · Recovery`, `05C Answer Reveal · No Save`, `40 กำลังบันทึกคำตอบที่พลาด` | C11 | saved/wrong/reveal/saving | acknowledgement before next; reveal does not masquerade as saved mastery |
| 3 | `06 สรุปการฝึก`, `07 Path Unlock`, `09 Reward Reveal` | C12 | terminal/result | finish idempotently; reward failure independent from learning result |
| 2 | `08 แข่งกับตัวเอง`, `08B แข่งกับตัวเอง · ชนะ` | C16 | challenge active/won | baseline absence and post-once result |
| 2 | `11 Vocabulary Library`, `12 Word Detail` | C05+C06 | list/detail | owner isolation, loading/empty/detail/deleted state |
| 1 | `13 Progress` | C15 | progress root | evidence, N=0 and read failure |
| 5 | `14 ผู้ช่วย Lexi`, `33 ผู้ช่วย Lexi · ตอบต่อเนื่อง`, `37 ผู้ช่วย Lexi · กำลังส่ง`, `38 ผู้ช่วย Lexi · ส่งไม่สำเร็จ`, `39 ผู้ช่วย Lexi · ใช้ครบแล้ว` | C14 | chat/send/error/quota | one in-flight, retry keeps prompt, local fallback |
| 6 | `16 Settings`, `24 ตั้งค่าผู้ช่วย AI`, `25 การแสดงผล`, `26 สิทธิ์ของแอป`, `27 ข้อมูลและความเป็นส่วนตัว`, `34 การแสดงผล · ใช้ค่าใหม่` | C07 | setting roots/saved | persisted values, permission/provider states, text scale |
| 5 | `18 บัตรคำ · ด้านหน้า`, `19 บัตรคำ · เปิดคำตอบ`, `20 บัตรคำ · ระดับความจำ`, `21 อ่านเรื่องสั้น`, `32 บัตรคำ · บันทึกระดับแล้ว` | C13 | reveal/rating/reader/saved | SRS/reading checkpoint; save retry and resume |
| 1 | `22 ยืนยันออกจากรอบ` | C22 | exit overlay | cancel keeps session; confirm checkpoints or closes safely |

Section total: **43**

### Section B — Responsive Models (20)

| Count | Specimens | Canonical family | Responsive role | Acceptance focus |
|---:|---|---|---|---|
| 11 | `P1 Compact lower bound 360×800`, `P1 Vivo 393×876`, `P1 Compact upper 412×915`, `Samsung fold Cover`, `Mate XT Single`, `Text scale 200%`, `Compact height 800×479`, `Medium height 800×480`, `Text scale 130%`, `Dark theme core flow`, `Android split-screen 720×540` | C01 with existing surface | compact/single-pane and accessibility variants | no clipped CTA, scroll at 200%, semantics order, contrast, real insets/IME |
| 9 | `Samsung fold Book 840×900`, `Samsung fold Tabletop 840×900`, `Book two-pane 1024×900`, `Mate XT Dual 720×960`, `Mate XT Triple 1100×900`, `Small tablet 600×960`, `Small tablet 800×1280`, `Large tablet 1280×800`, `Medium tablet 1024×1366` | C01 | rail/list-detail/supporting-pane variants | `LayoutBuilder`/WindowManager posture; no content/control on hinge; same route/state as compact |

Section total: **20**. รุ่นอุปกรณ์เป็น test matrix ไม่ใช่ widget subclass

### Section C — Auth + Account Lifecycle (29)

| Count | Specimens | Canonical family | State / route role | Authority + acceptance focus |
|---:|---|---|---|---|
| 13 | `A00`, `A03`–`A13` (ตรวจสถานะ, Google success, register, terms, verify email, reset, existing account, link/merge, sign-in methods) | C03+C08 | auth routes and step states | `AccountUseCases`; neutral reset response, form retained, deep-link expiry, owner upgrade |
| 3 | `A14 ตรวจขอบเขตการลบ`, `A15 ยืนยันตัวตนก่อนลบ`, `A16 ผลการลบบัญชี` | C04 | destructive route chain | scope shown, re-auth required, partial/failure result explicit |
| 7 | `O01`, `O01B`, `O01C`, `O01D`, `O02`, `O03`, `O03B` | C22 | Credential Manager and confirmation overlays | dismiss rules, no write on cancel, exact account/action visible |
| 6 | `AS01`–`AS05` | C03+C21 | invalid/IME/password visible/reset sent/success/resend | 360×800 + IME + 200% matrix; errors announced and CTA visible |

Section total: **29**

### Section D — 8/44 Capability Screens (41)

| Count | Specimens | Canonical family | Role | Authority + acceptance focus |
|---:|---|---|---|---|
| 5 | `F00`–`F04` | C05+C06 | feature hub, pack catalog/detail, lexical detail, provenance | 44 IDs traceable; content revision/source visible; unavailable feature hidden/limited |
| 11 | `F05`, `F08`–`F16` including `F12B` | C09+C10+C13 | common practice, choice/cloze/match/type/write, mode groups, recall/session setup | one session authority; input semantics; clear/retry; no duplicate answer |
| 4 | `F19`, `F20`, `F21A`, `F21B` | C06+C22 | hint/save/report/review report | hint not mastery; saved/report acknowledgement and editable review |
| 6 | `F22`–`F26`, `F28` | C15 | review, timer/time, calendar, goal, assessment compare | evidence provenance; empty/offline; time and assessment do not inflate mastery |
| 4 | `F30`, `F31`, `F33`, `F34` | C12+C16 | streak, achievement, companion, share | no shame; reward/motivation separate; share redacts private data |
| 7 | `F35A`–`F35D`, `F36`–`F38` | C08+C07 | onboarding goal/time/method, profile, recommendation, accessibility | save/resume wizard; reason for recommendation; 200%/screen-reader/touch target |
| 4 | `F41`, `F44`, `F43A`, `F43B` | C05+C15+C21 | rollout, offline, history/detail | learner-facing copy; local availability; history owner scope and detail route |

Section total: **41**. Catalog มี 44 capabilities เพราะบาง screen รองรับ capability มากกว่าหนึ่งรายการและบางรายการใช้ screen family ที่อยู่ Section A/E/K

### Section E — Extended Tools + Theme Marketplace (50)

| Count | Specimens | Canonical family | Role | Authority + acceptance focus |
|---:|---|---|---|---|
| 5 | `M01`–`M05` | C05+C07+C09 | secondary menu hubs | every entry routes or is hidden; 4-root IA remains unchanged |
| 3 | `S01 เพิ่มคำศัพท์`, `S02 เพิ่มหลายคำ`, `S03 ตรวจไฟล์นำเข้า` | C17 | add/batch/import review | `VocabularyUseCases`/`ImportVocabulary`; cancel no write, retry idempotent |
| 13 | `S04`–`S15` | C10+C16+C18 | match/scramble/cloze/dictation/speech/camera/challenge/results | one answer pipeline; permission/model/audio fallbacks; reward once |
| 13 | `S16`–`S27B` | C07+C14+C20 | points, profile decoration, AI provider/key, notes, plan, research, export, help, notification | authority/entitlement gates; notes/automation hidden until lifecycle exists; secret redaction; decline research preserves learning |
| 16 | `M35`–`M50` | C19 | theme catalog/filter/detail/preview/purchase/apply/owned/balance/history/offline | `RewardUseCases`; stale price/balance, insufficient points, purchase replay, offline-owned assets |

Section total: **50**

### Section F — System States (10)

| Count | Specimens | Canonical family | State role | Acceptance focus |
|---:|---|---|---|---|
| 10 | `ST01`–`ST10` | C21; `ST10` composes C22 | loading, empty, save error, offline, denied/permanent denied, saving/saved, unavailable, delete | preserve context, announce status, show cause and recovery, never clear user input on retry |

Section total: **10**

### Section G — Contextual Bottom Sheets (15)

| Count | Specimens | Canonical family | Overlay role | Authority + acceptance focus |
|---:|---|---|---|---|
| 15 | `D01`–`D15` | C22 | exit, permission rationale, offline detail, import source, delete word, export file, research detail, reward, filter, AI provenance, search, delete account, licenses, help, full account document | barrier/back behavior explicit; scrollable at 200%; destructive action names object/consequence; cancel has zero mutation |

Section total: **15**

### Section K — TOR Flow Completion (32)

| Count | Specimens | Canonical family | Role | Authority + acceptance focus |
|---:|---|---|---|---|
| 2 | `A02 เลือกวิธีเริ่ม`, `A08 ตรวจความปลอดภัยรหัสผ่าน` | C03+C08 | auth completion | guest/account routes; password checks without leaking secret |
| 4 | `P10`, `P11`, `P13`, `P16` | C05+C17 | vocabulary list/search/import source | owner scope, empty/error/filter retention, supported source validation |
| 8 | `P24`, `P25`, `P27`–`P30R`, `P32` | C13+C15 | mastery/weakness/evidence/path/CEFR/associative reading | evidence authority, no certification claim, curriculum limited until graph exists, resumable six stages |
| 3 | `P40`, `P42`, `P43` | C18 | speech/phonetic/audio | permission/audio unavailable, stop on route exit, resume position where applicable |
| 3 | `P50`, `P53`, `P58` | C07+C20 | profile/accessibility/export status | persisted settings, 200%, artifact progress/failure/cancel |
| 9 | `O03`, `O06`, `O08`–`O13`, `O15` | C22 | add category/discard/memory/permission/key/reward/password/research overlays | cancel no mutation; private data copy; explicit authority before write |
| 1 | `P59 แดชบอร์ดวิจัยภายใน` | C20 | internal gated route | synthetic data by default; owner/consent/assignment/permit/protocol checks |
| 2 | `T03`, `T04` | C01+C15/C07 | tablet progress and profile/settings roots | same state/authority as compact; rail and master-detail without duplicated business logic |

Section total: **32**

## 5. Coverage reconciliation

| Section | Manifest count | Mapped count | Result |
|---|---:|---:|---|
| A · Vivo Canonical | 43 | 43 | ครบ |
| B · Responsive Models | 20 | 20 | ครบ |
| C · Auth + Account Lifecycle | 29 | 29 | ครบ |
| D · 8/44 Capability Screens | 41 | 41 | ครบ |
| E · Extended Tools + Theme Marketplace | 50 | 50 | ครบ |
| F · System States | 10 | 10 | ครบ |
| G · Contextual Bottom Sheets | 15 | 15 | ครบ |
| K · TOR Flow Completion | 32 | 32 | ครบ |
| **รวม** | **240** | **240** | **ครบ** |

## 6. Route implementation rule

`routeManifest` มี 942 reactions ซึ่งรวมปุ่ม ตัวเลือก back, overlay และ state transition จึงต้องแปลงเป็น route/state contract ไม่ใช่สร้าง 942 routes

1. ใช้ named/page route เฉพาะ deep-linkable surface: auth, 4 roots, catalog/detail, active session entry, result, settings/account/data และ gated tools
2. selection, reveal, saving, feedback, filter และ chat send เป็น state ภายใน canonical surface
3. dialog/bottom sheet ใช้ C22 และคืน typed result ให้ caller; overlay ห้ามเป็น authority
4. adaptive route ใช้ route เดิม แล้ว C01 เลือก single pane หรือ list-detail ตาม window/posture
5. terminal session ใช้ replacement/reset semantics เพื่อไม่ย้อนกลับเข้า session ที่ finish แล้ว
6. ทุก prototype source ต้องลงท้ายที่ route, overlay, state mutation หรือ explicit disabled/limited state; ห้ามมี `onTap` ว่าง

ก่อนย้าย navigation ให้เขียน route registry จาก 4 roots และ vertical slice แรก แล้วทดสอบ parity กับ family map นี้ `AppRoute` ปัจจุบันมีเพียง login/register/emailVerification/home จึงยังไม่ใช่ R11 route source of truth

## 7. Acceptance tests ต่อ canonical family

| Family | Minimum focused tests |
|---|---|
| C01–C02 | widget test ที่ 360×800, 393×876, 412×915, 600, 840 และ 1280dp; navigation 4 จุดหมาย; selected tab/restoration; no overflow |
| C03–C04 | validation, busy lock, offline, provider unavailable, IME, 200% text, reset deep link, re-auth, cancel/no mutation และ destructive result |
| C05–C07 | loading/empty/error/data, filter/search retention, owner isolation, saved acknowledgement, semantics order และ tablet list-detail |
| C08–C09 | back retains prior answers, unavailable option, resume wizard, single primary action และ configuration passed to use case |
| C10–C11 | double-tap records once, retry uses same attempt identity, feedback only after acknowledgement, save failure blocks next และ reveal/hint semantics |
| C12–C13 | finish idempotent, back cannot reopen finished session, rating/checkpoint retry, restart resumes reading position/revision correctly |
| C14 | single in-flight request, offline/quota/timeout, retry keeps draft, provenance visible, dispose cancels listening/request และ local learning remains accessible |
| C15–C16 | N=0/error/evidence provenance, mastery vs reward separation, no baseline challenge, result/reward replay idempotent |
| C17 | unsupported/oversize/malformed input, duplicates, partial valid rows, edit preview, cancel no write, retry no duplicate และ restart sees committed words |
| C18 | rationale before OS prompt, denied/permanent-denied, lifecycle dispose, audio/model unavailable, unverified scan confirmation และ no raw-content logging |
| C19 | stale balance/price, insufficient points, purchased/already-owned/replayed, apply/rollback, offline-owned theme และ contrast at 130/200% text |
| C20 | decline/withdraw, nonparticipant creates no research row/event/upload, owner isolation, export cancel/failure, permit unavailable fails research closed while learning continues |
| C21–C22 | status semantics/live region, retry preserves context, back/barrier matrix, scroll at 200%, cancel zero mutation และ destructive copy names exact object |

ใช้ test ที่มีอยู่เป็นฐาน ได้แก่ `quiz_screen_test.dart`, `srs_flashcards_screen_test.dart`, `weakness_clinic_screen_test.dart`, `main_navigation_screen_test.dart`, `production_shell_navigation_test.dart`, `ai_tutor_screen_test.dart`, `object_scanner_screen_test.dart`, `profile_settings_screen_test.dart`, `research_consent_use_cases_test.dart` และ repository tests ของ learning/vocabulary/reward/identity ห้ามสร้าง golden 240 ภาพ; golden ควรครอบ canonical family และ breakpoint/state ที่เสี่ยงเท่านั้น

## 8. ลำดับ implementation ที่ไม่แตกเป็น 240 งาน

1. **Foundation:** tokens, C01, route registry 4 roots, C21/C22 และ accessibility harness
2. **Learning vertical slice:** C02, C05/C06 vocabulary, C09/C10/C11/C12 และ authority `LearningUseCases`
3. **Review and reading:** C13/C15 พร้อม SRS, weakness, evidence และ restart checkpoints
4. **Account/data:** C03/C04/C07/C17/C20 พร้อม owner upgrade, import, export และ research default-off
5. **Tools:** C14/C18 เฉพาะ provider/model/permission ที่ contract พร้อม
6. **Motivation/marketplace:** C16/C19 หลัง reward/quest idempotency tests ผ่าน
7. **Adaptive closure:** fold/tablet/IME/text-scale matrix บน runtime จริง โดย reuse surface เดิม

Definition of Done ของแต่ละ slice คือ route ไป-กลับครบ, authority เดียว, state/error/offline/accessibility ครบ, focused widget/use-case/repository tests ผ่าน และไม่มีเมนูเปิดก่อน capability พร้อม

## 9. Handoff decision

R11 พร้อมใช้เป็น implementation baseline แบบ **canonical-family architecture**: 240 specimens ถูก reconcile ครบเป็น 22 families, 8/44 catalog คงเดิม และ route reactions ถูกลดเป็น route/state responsibilities ที่ตรวจได้

สิ่งที่ยังไม่ถือว่าปิดจากเอกสารนี้คือการ sync R11 เข้า Figma Cloud, physical-device/foldable validation, combined IME + 200% text matrix และ production authority ของฟีเจอร์ gated เอกสารนี้ไม่อนุญาตให้ข้ามข้อเหล่านั้น แต่ช่วยให้พัฒนา family และ vertical slice ที่พร้อมได้ทันทีโดยไม่สร้าง 240 widgets
