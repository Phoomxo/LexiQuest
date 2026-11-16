# LexiQuest Figma clickable prototype flow map

วันที่จัดทำ: 2026-10-18

สถานะ: Blueprint สำหรับ wireframe/prototype บน Figma หน้าเดียว

แพลตฟอร์ม: Android-first; compact phone, large phone, foldable และ tablet

ขอบเขต: การนำทาง หน้าจอ สถานะระบบ เมนู การตั้งค่า และ interaction สำหรับทดสอบ prototype; ไม่ใช่หลักฐานว่า Flutter implementation หรือบริการภายนอกพร้อมใช้งานแล้ว

## 1. Intent และข้อสรุปสถาปัตยกรรมข้อมูล

Prototype ต้องทำให้ผู้ใช้ทำวงจรหลักได้จริงด้วยการกด:

`บริบท → งานถัดไป → ลงมือ → ผลตอบกลับที่บันทึกแล้ว → ขั้นถัดไป`

ใช้ข้อมูลจาก source จริงและหลักฐาน REA เป็นฐาน แต่ไม่คัดลอกแบรนด์ ภาพ หรือข้อความของ Duolingo, Astra AI และ AllTCAS:

- Duolingo: path/resume มาก่อนรายการกิจกรรม
- Astra AI: progressive disclosure, บริบทก่อนแผน และ onboarding ทีละคำถาม
- AllTCAS: catalog แยกจาก task; หน้าฝึกมีโจทย์เดียวและ action/feedback อยู่ตำแหน่งคงที่
- LexiQuest source: local-first, Guest ใช้งานต่อได้, learning/progress/reward แยก authority, AI/กล้อง/ไมค์/งานวิจัยมีทางเข้าและ consent/permission ชัดเจน

### ความต่างที่ต้องแก้ใน prototype ก่อนนำไป implement

`MainNavigationScreen` ปัจจุบันสร้าง NavigationBar ได้ 6 จุดหมาย: คลังคำศัพท์, เรียนรู้, สถิติ, จุดอ่อน, รางวัล, โปรไฟล์ ส่วน design contract กำหนด 4 จุดหมาย: **เรียน, คลังคำ, ก้าวหน้า, โปรไฟล์**. Prototype ใช้ 4 จุดหมายดังนี้:

| จุดหมายหลัก | เนื้อหาที่รวมไว้ | เหตุผล |
| --- | --- | --- |
| เรียน | แผนวันนี้, เลือกกิจกรรม, curriculum, reading, AI/voice/vision tools | ลดการตัดสินใจก่อนเริ่มงานและคง primary action หนึ่งจุด |
| คลังคำ | หมวด, รายการ, ค้นหา, รายละเอียด, เพิ่ม/แก้ไข/นำเข้า | เป็น workspace สำหรับข้อมูลคำศัพท์ทั้งหมด |
| ก้าวหน้า | Mastery, Weakness Clinic, Achievements, evidence details | รวมผลและ action ซ่อมจุดอ่อนโดยไม่เพิ่ม destination |
| โปรไฟล์ | โปรไฟล์, ร้านรางวัล/appearance, settings, account/data controls | รวมสิ่งที่เป็นเจ้าของบัญชีและการกำหนดค่า |

การรวมนี้เป็น **target IA ของ prototype**; ยังไม่ถือว่าโค้ด navigation ถูกแก้แล้ว

## 2. Frame naming และการจัดใน Figma หน้าเดียว

ใช้ Figma Page เดียว และใช้ Section node แทนการสร้าง Page เพิ่ม:

1. `01 Foundations`
2. `02 Components`
3. `03 Phone · Core Flows`
4. `04 Phone · Feature Inventory`
5. `05 Tablet & Foldable`
6. `06 States & Overlays`
7. `07 Prototype Flow Map`

ตั้งชื่อ frame เป็น `Pxx/ชื่อ/สถานะ` สำหรับ phone, `Txx/ชื่อ/สถานะ` สำหรับ tablet และ `Oxx/ชื่อ` สำหรับ overlay เช่น `P20/Quiz/Question`, `P21/Quiz/Correct saved`, `O01/Research consent` เพื่อให้ค้นหาและต่อ interaction ได้โดยไม่อาศัยตำแหน่งบน canvas

## 3. Responsive shell contract

| Window width | Shell | Content behavior | Prototype frame |
| --- | --- | --- | --- |
| Compact `< 600dp` | NavigationBar 4 จุดหมาย | single pane, margin 20dp, fixed bottom action เหนือ nav/safe area | 360×800 และ 412×915 |
| Medium `600–839dp` | NavigationRail แบบ compact | single pane กว้างไม่เกิน 720dp หรือ list + optional preview เมื่อเหมาะ; gutter 24–32dp | 700×1000 |
| Expanded `≥ 840dp` | NavigationRail แบบ extended เมื่อ label ไม่เบียด | list-detail/supporting pane, content max 1200dp, long text measure 560–680dp | 1024×1366 และ 1280×800 |
| Foldable/book posture | Rail ใน pane ซ้ายหรือริม window | ห้ามวาง control/ข้อความบน hinge; list และ detail อยู่คนละ pane เมื่อแต่ละ pane กว้างพอ | 884×1104 พร้อม 24dp hinge mask |

กฎร่วม:

- Phone แสดง NavigationBar เฉพาะ root ของ 4 จุดหมาย; nested task ใช้ top app bar + Back และซ่อน bottom nav หากจะรบกวน fixed action
- Tablet คง NavigationRail ระหว่าง root และ nested list-detail; task ที่ต้องโฟกัส เช่น Quiz/Reading/Camera เปิดใน content pane เต็มหรือ modal route โดยยังไม่วาง action บน hinge
- ใช้ 4/8dp grid, screen inset 20–24dp, section gap 24–32dp, component gap 8–16dp และ touch target อย่างน้อย 48×48dp
- ที่ text scale 200% ให้เพิ่มความสูงตามเนื้อหาและเลื่อน; ห้ามตัด label หรือใช้ fixed-height card
- เมื่อคีย์บอร์ดเปิด ให้ input, inline error และ CTA ที่เกี่ยวข้องเลื่อนมองเห็นได้; bottom nav อาจซ่อนชั่วคราว แต่ Back/ยกเลิกยังเข้าถึงได้
- Safe area ครอบ status bar, camera cutout, navigation gesture inset และ fold/hinge

## 4. Inventory หน้าจอและ entry point

### 4.1 Account และเริ่มใช้งาน

| ID | Frame/หน้าจอ | Entry → target หลัก | Back/exit | สถานะที่ต้องมี | Source grounding |
| --- | --- | --- | --- | --- | --- |
| P01 | Login | Launch → Login; เข้าสู่ระบบ → P04/P05; Guest → O01 แล้ว P06 | root Back ออกจากแอป | idle, busy, account unavailable, invalid credential, offline | `login_screen.dart`, `login_guest_mode_test.dart` |
| P02 | Register | P01 สร้างบัญชี → P02; สมัครสำเร็จ → P04 | Back → P01; retain form on error | validation, privacy checkbox, busy, provider unavailable | `register_screen.dart`, `registration_flow_test.dart` |
| O02 | Forgot password | P01 ลืมรหัสผ่าน → O02 | Cancel/Back ปิด overlay; ส่ง → P01 + snackbar | invalid email, network, sent-neutral message | `login_screen.dart` |
| P04 | Email verification | P02/บัญชียังไม่ยืนยัน → P04; ตรวจแล้ว → P06 | Back → P01; resend stays | checking, not verified, resend success/failure | `otp_screen.dart` |
| P05 | Email action result | deep link → P05; สำเร็จ → P01/P06 | ไม่มีการย้อนกลับไปลิงก์เก่า; CTA reset route | loading, success, invalid/expired action code | `app_route_factory.dart`, `email_action_screen.dart` |
| O01 | Research consent | sign-in/Guest ครั้งแรก → O01 | barrier ไม่ dismiss; เลือก “ยังไม่ยินยอม” หรือ “ยินยอม” เท่านั้น | optional, protocol version, learning continues when declined | `research_consent_dialog.dart` |

หมายเหตุ: OTP ใน source คือการตรวจสถานะ email verification ไม่ใช่การกรอกรหัส 6 หลัก จึงให้ prototype ใช้คำว่า “ตรวจสอบการยืนยันอีเมล” จนกว่าจะมี contract สำหรับ OTP จริง

### 4.2 Root shell 4 จุดหมาย

| ID | Root | Primary action | Secondary entry | Tablet behavior |
| --- | --- | --- | --- | --- |
| P06/T01 | เรียน · Learning Home | Resume/เริ่มงานที่แนะนำ | เลือกกิจกรรม, เส้นทาง, AI/voice/camera tools | rail + supporting pane ที่อธิบายเหตุผลของคำแนะนำ |
| P07/T02 | คลังคำ · Vocabulary | เปิดหมวดล่าสุด/เพิ่มคำแรก | ค้นหา, เพิ่มคำ, batch, import | list-detail: หมวดซ้าย รายการ/รายละเอียดขวา |
| P08/T03 | ก้าวหน้า · Progress | ฝึกจุดอ่อนที่แนะนำ | Mastery, Weakness, Achievements, evidence | dashboard max 2–3 columns; detail pane เมื่อเลือก evidence |
| P09/T04 | โปรไฟล์ · Profile | ปรับเป้าหมายหรืออัปเกรดบัญชีตามสถานะ | rewards, appearance, settings, export | rail + settings list-detail; profile header ไม่กินเต็ม viewport |

Root ทุกหน้าแสดง offline/cloud status แบบ compact เมื่อเกี่ยวข้อง แต่ห้ามใช้ banner ถาวรหลายชั้นจนแย่งงานหลัก

### 4.3 Vocabulary workspace

| ID | หน้าจอ | Entry → target | Back | State/overlay |
| --- | --- | --- | --- | --- |
| P10 | หมวดคำศัพท์ | P07 → P10; แตะหมวด → P11; เพิ่มหมวด → O03 | root destination | loading, empty → P14/O03, local DB unavailable, retry |
| P11 | รายการคำในหมวด | P10 หมวด → P11; แตะคำ → P12; + → P14; import → P16 | Back → P10 | loading, empty, search no-result, delete O05 |
| P12 | รายละเอียดคำ | P11/search → P12; ฝึกคำนี้ → P20; แก้ไข → P14 | Back → source list/search | due, weakness, mastered, no example |
| P13 | Search & filter | P07 search → P13; result → P12 | Back → P07 | recent, results, no-result, clear filters |
| P14 | Add/Edit word | P11/P12/FAB → P14; save → P11/P12 | Back with dirty form → O06 discard confirm | idle, inline validation, duplicate, saving, save failure |
| P15 | Batch add | P11 → P15; validate → P17 | Back with rows → O06 | row error, duplicate, partial-valid, empty |
| P16 | Import source | P11/P07 → P16; file/text chosen → P17 | Back → P11/P07 | picker unavailable, unsupported file, parsing |
| P17 | Import review | P15/P16 → P17; confirm → P11; learn now → P22 | Back → edit source; cancel import clears temporary state | valid, duplicates, invalid rows, importing, partial failure |
| O03 | Add category | P10 + → O03; save → P10 | Back/Cancel closes with no write | empty name, duplicate, saving error |
| O05 | Delete category/word | long press/menu → O05 | Back/Cancel keeps data; confirm → source list | destructive copy names object and consequence |

Tablet: P10/P11/P12 รวมเป็น canonical list-detail ได้ แต่ทุก node ต้องมี destination แยกใน prototype เพื่อทดสอบ deep link และ compact fallback

### 4.4 Learning core

| ID | หน้าจอ | Entry → target | Back behavior | State/variant |
| --- | --- | --- | --- | --- |
| P18 | Activity selector | P06 “กิจกรรมอื่น” → P18 | Back → P06 | enabled/limited/hidden feature badge |
| P19 | Category selector | P18 Quiz ตามหมวด → P19; เลือก → P20 | Back → P18 | loading, empty → P14, load error/retry |
| P20 | Quiz question | P06 recommendation/P18/P19/P28 → P20; เลือกคำตอบ → P21 | Back during active session → O07 exit confirm | loading, empty, question, saving/disabled |
| P21 | Quiz feedback | P20 answer saved → P21; next → P20; last → P23 | Back → O07; feedback ไม่หายจากการ scroll | correct saved, wrong saved, save failed + retry |
| P22 | SRS flashcard | P06/P18/P28 → P22; reveal → rating; done → P23/P06 | Back → O07/checkpoint | loading, no due items, question, revealed, saving |
| P23 | Score & next step | P20/P22 done → P23; practice mistakes → P20; home → P06 | Back → P06 โดยไม่ย้อนเข้า finished session | score, mistakes, perfect, finish failure/retry |

Quiz interaction contract:

1. P20 เปิดด้วย progress + prompt เดียว; CTA/choices กดได้พื้นที่ ≥48dp
2. เมื่อแตะคำตอบ ให้ปิดการกดซ้ำและไป P21 หลัง acknowledgement
3. P21 แสดงข้อความ `ถูก/ยังไม่ถูก · บันทึกแล้ว` และความหมาย; สีไม่ใช่สัญญาณเดียว
4. ถ้าบันทึกล้มเหลว อยู่ P21 แบบ error พร้อม `ลองบันทึกอีกครั้ง`; ห้ามข้ามไปข้อต่อไป
5. Last question ไป P23; action ซ่อมคำผิดใช้ session summary เดิม

### 4.5 Progress, curriculum และ reading

| ID | หน้าจอ | Entry → target | Back | States |
| --- | --- | --- | --- | --- |
| P24 | Mastery dashboard | P08 → P24; skill/evidence → P27 | root/Back → P08 ตาม entry | loading, N=0, error, evidence available |
| P25 | Weakness Clinic | P08/P18 → P25; practice → P20; due review → P22 | Back → P08/P18 | loading, no answers, no weakness, due=0, retry |
| P26 | Achievements | P08/P09 → P26 | Back → entry | loading, none unlocked, unlocked list; reward ≠ mastery |
| P27 | Evidence detail | P24 metric/skill → P27; recommended action → P20/P22 | Back → P24 with scroll position | insufficient sample, version/provenance, offline data |
| P28 | Curriculum path | P06 route card → P28; unlocked node → P29/P31 | Back → P06 | loading, current/unlocked/locked, unavailable hidden state |
| P29 | CEFR catalog | P28/P18 → P29; diagnostic → P30; word group → P22; article → P31 | Back → entry | search/filter, no result, content revision |
| P30 | CEFR diagnostic | P29 → P30; complete → P30R | active Back → O07 | question progress, answered, result, error; certification claim prohibited |
| P30R | CEFR result | P30 → P30R; recommended level → P29/P31 | Back → P29 | confidence/sample limitation copy |
| P31 | Article entry/reader | P29/P18 → P31; Practice → P32 | Back checkpoints position then → P29/P18 | loading, article, resumed position, revision changed |
| P32 | Associative reading | P31 → stages 1–6; Finish → P23/P31 | Back/checkpoint; failed checkpoint stays with retry | loading, stage 1–6, saving, save failure |
| O08 | Memory association | P32 stage 4 → O08 | Back/Skip closes; save → P32 | suggested/custom cue; private-data explanation |

Curriculum path ใน source ยังเป็น hardcoded และไม่พบ root entry ที่พร้อม production จึงแสดง `Limited · curriculum data required` ใน prototype หรือซ่อนไว้หลัง Learn tools จนมี curriculum graph จริง

### 4.6 Practice games และ challenges

| ID | หน้าจอ | Entry/next | Back | Required variants |
| --- | --- | --- | --- | --- |
| P33 | Word scramble | P18/voice success → P33; correct → P23/P34 | active Back → O07 | correct, retry, empty word |
| P34 | Sentence scramble | P18/P33 → P34 | active Back → O07 | arrange, check, correct/incorrect |
| P35 | Fill in blanks | P18 → P35 | active Back → O07 | prompt, selected, feedback |
| P36 | Dictation | P18 → P36 | active Back → O07 | play, input, check, feedback, audio unavailable |
| P37 | Boss battle | P18 → P37; complete → P39 | active Back → O07 | active, won/lost, support state; timer/HP ไม่อ้าง mastery |
| P38 | Ghost duel | P18/P25 → P38; complete → P39 | active Back → O07 | no baseline, active, saved result; benchmark ≠ opponent identity |
| P39 | Challenge result | P37/P38 → P39; home → P06; retry → source challenge | Back → P06 | result, reward posted once, reward failure |

### 4.7 Voice, audio, camera และ AI

| ID | หน้าจอ | Entry → target | Permission/fallback | Back |
| --- | --- | --- | --- | --- |
| P40 | Speak to text | P18/Learn tools → P40; exact match → P33 | O09 microphone rationale; denied/permanent denied; local TTS unavailable | cancel recording then pop |
| P41 | Shadowing | P18/Learn tools → P41 | O09; no words; speech engine unavailable | cancel listen then pop |
| P42 | Phonetic explorer | P18/Learn tools → P42 | audio unavailable copy + text fallback | stop audio then pop |
| P43 | Smart audio playlist | P18/P29 → P43 | empty playlist; TTS unavailable; play/pause | stop/persist position then pop |
| P44 | Object scanner | P18/Learn tools → P44; capture → P45 | O10 camera rationale; denied/permanent denied; model unavailable/download | stop camera then pop |
| P45 | Scanner result | P44 capture → P45; add → P12/P11; rescan → P44 | unverified label cannot be saved as verified word | Back → P44 |
| P46 | AI Tutor | P18/Learn tools → P46; missing key → P47 | offline/quota/timeout/provider/blocked + local-learning fallback | cancel request/listen then pop |
| P47 | Gemini BYOK | P46/Profile settings → P47 | key never shown after save; provider consent required; remove → O11 | Back → P46/settings with status refresh |
| O09 | Microphone rationale | first explicit voice action → O09 | Allow → Android permission; Not now → source; permanent denial → system settings link | Back = Not now |
| O10 | Camera rationale | first scanner action → O10 | same rule; explain on-device model/data path | Back = Not now |
| O11 | Remove Gemini key | P47 remove → O11 | confirm removes key + disables provider/summary consent | Back/Cancel no change |

### 4.8 Rewards, profile, settings และ data controls

| ID | หน้าจอ/เมนู | Entry → target | Back/confirmation | States |
| --- | --- | --- | --- | --- |
| P48 | Reward shop | P09 → P48; buy → O12; equip stays | Back → P09 | loading, local read error, owned/equipped, insufficient balance, stale catalog |
| P49 | Appearance & equipment | P09/P48 → P49 | Back → entry; live preview revert on cancel | theme/wallpaper/avatar slots, large text/reduce motion preview |
| P50 | Profile summary | P09 → P50 | root/Back → P09 | Guest/verified/pending, loading/error, evidence-derived metrics |
| P51 | Settings root | P09 gear → P51 | Back → P09 | sections below; cloud local fallback status |
| P52 | Account settings | P51 → P52; change password → O13; sign out → O14 | Back → P51 | Guest upgrade, verified/pending, provider unavailable |
| P53 | Learning & accessibility | P51 → P53 | Back → P51; changes preview immediately and persist explicitly | theme, text size, reduce motion, audio/TTS/speed, haptic |
| P54 | Device permissions | P51 → P54; mic/camera row → O09/O10 or Android settings | Back → P51 | allowed/ask/denied/permanent denied/unavailable |
| P55 | AI settings | P51 → P55/P47 | Back → P51 | provider/key/consent/quota summary |
| P56 | Research consent | P51 → P56; accept/withdraw → O15 | Back → P51; ordinary learning unaffected | current revision, declined, accepted, withdrawn, authority unavailable |
| P57 | Export center | P51 → P57; create → P58 | Back → P51; active export asks cancel | no selection, N=0, consent required for research, permission/storage/write errors |
| P58 | Export progress/result | P57 → P58; cancel/success → P57 | cancel clears temporary file | progress, cancelled, saved path, failure with retry |
| P59 | Research dashboard | internal explicit route only | Back → internal tools; never public learner menu | synthetic-only label; real enrollment disabled |
| O12 | Purchase confirm | P48 buy → O12 | confirm once/idempotent; cancel no transaction | price changed, insufficient balance, owned |
| O13 | Change password | P52 → O13 | Back/Cancel retain account; success closes | inline fields, recent-login required, busy/error |
| O14 | Sign out | P52 → O14 | confirm resets navigation to P01 and creates local Guest context without deleting account data | clear consequence copy |
| O15 | Research accept/withdraw | P56 → O15 | explicit action only; barrier prevents accidental accept | version/purpose/data/retention/withdrawal visible |

### 4.9 System-state specimen frames

ระบบ state ไม่ใช่หน้าที่จบในตัวเอง แต่เป็น variant ที่ต้อง link กลับเส้นทางจริง:

| ID | State | Required anatomy | Primary recovery |
| --- | --- | --- | --- |
| S01 | Loading | skeleton คง layout + busy semantics; หลีกเลี่ยง spinner flash สำหรับงานสั้น | รอ; cancel เฉพาะงานที่ยกเลิกได้ |
| S02 | Empty | บอกว่าขาดอะไรและเหตุใด | Add word / Import / Start baseline ตามบริบท |
| S03 | Error | ชื่อการทำงานที่ล้มเหลว + ยืนยันว่ายังไม่แก้ข้อมูลเมื่อจริง | Retry; secondary Back/Home |
| S04 | Offline | local work ที่ยังใช้ได้ + services ที่พักไว้ | Continue offline |
| S05 | Permission denied | เหตุผลการใช้ permission + สิ่งที่ยังทำได้ | Try again หรือ Continue without feature |
| S06 | Permanently denied | ระบุว่าต้องเปิดจาก Android Settings | Open settings; Cancel |
| S07 | Save pending | control ต้นทาง disabled, progress ไม่ขยับ | Retry/cancel ตาม transaction boundary |
| S08 | Save acknowledged | ข้อความ `บันทึกแล้ว`, feedback คงอยู่ | Continue |
| S09 | Limited feature | badge + dependency ที่ขาด | Configure/download/learn offline |
| S10 | Destructive confirmation | object + consequence + verb เฉพาะ | destructive action; Cancel default |

### 4.10 Cross-cutting overlays

| ID | Overlay | เปิดจาก | ผลลัพธ์ |
| --- | --- | --- | --- |
| O06 | Discard draft? | Back จาก Add/Edit/Batch import ที่มีข้อมูลเปลี่ยน | `แก้ไขต่อ` ปิด overlay; `ทิ้งการเปลี่ยนแปลง` กลับ source โดยไม่เขียนข้อมูล |
| O07 | Exit active session? | Back จาก Quiz/SRS/diagnostic/game/challenge ที่ยังไม่จบ | `อยู่ต่อ` ปิด overlay; `ออกจากรอบ` checkpoint เมื่อ contract รองรับแล้วกลับ entry โดยไม่สร้าง answer/reward ซ้ำ |

## 5. เมนูและ settings map ที่ต้องกดได้

### Learn tools

`P06 Learn` → `P18 เลือกกิจกรรม` → Quiz, SRS, Weakness, Curriculum/CEFR, Reading, games, challenges

`P06 Learn` → `Tools` → AI Tutor, Object scanner, Speak to text, Shadowing, Phonetic explorer, Audio playlist

ฟีเจอร์ `limited` ต้องยังมองเห็นพร้อมเหตุผลและ setup CTA; ฟีเจอร์ `hidden` ไม่สร้าง dead tile

### Profile/settings hierarchy

`P09 Profile`:

- `P50 Profile summary`
- `P48 Reward shop` → `P49 Appearance & equipment`
- `P51 Settings`
  - `P52 Account`: Guest upgrade, email status, password, sign out
  - `P53 Learning & accessibility`: theme, text scale, reduce motion, audio/TTS/speed, haptic
  - `P54 Device permissions`: microphone, camera, notification future placeholder only when authorized
  - `P55 AI`: Gemini key, provider consent, summary sharing, quota/fallback
  - `P56 Privacy & research`: optional consent/withdrawal, current revision
  - `P57 Export`: CSV/PDF/Anki/research JSON; research export obeys consent
  - `Sync status`: local-first status, retry when network returns
  - `Delete data`: prototype may show entry + O15-like destructive confirmation แต่ห้ามสื่อว่า implementation/export/deletion coverage เสร็จจน source รองรับครบ

ทุก row ต้องมี target หรือแสดง disabled/coming-later พร้อมเหตุผล; ห้ามทำ hotspot ที่กดแล้วไม่เกิดอะไร

## 6. Interaction map source → target

### Flow A: Guest เริ่มเรียนและจบรอบ

`P01 Guest` → `O01 consent (decline/accept)` → `P06 Learn` → `Resume` → `P20 Quiz` → `P21 saved feedback` → `Next` ↔ `P20` → `P23 score` → `Practice mistakes` → `P20` หรือ `Back to plan` → `P06`

### Flow B: เพิ่มคำแล้วฝึก

`P07 Library` → `P10 category` → `P11 word list` → `P14 add word` → `Save` → `P11` → `P12 word detail` → `Practice this word` → `P20` → `P21` → `P23`

### Flow C: Import คลังคำ

`P11/P07 Import` → `P16 source` → `P17 review` → `Import` → `P11` → `Learn imported set` → `P22 SRS` → `P23`

### Flow D: ซ่อมจุดอ่อนจากหลักฐาน

`P08 Progress` → `P25 Weakness` → `Practice wrong words` → `P20` → `P21` → `P23` → `P24/P27 updated evidence`

### Flow E: Curriculum และ associative reading

`P06 path` → `P28 curriculum` → `P29 CEFR` → `P31 article` → `P32 stages 1–3` → `O08 association at stage 4` → `P32 stages 5–6` → `Finish` → `P23/P31`

### Flow F: AI Tutor setup และ fallback

`P06 Tools` → `P46 AI Tutor` → missing key `P47 BYOK` → consent + validate → Back → `P46` → send → reply; quota/offline → `S03/S04` → `Continue local learning` → `P18`

### Flow G: Camera → vocabulary

`P06 Tools` → `P44 Scanner` → `O10 rationale` → Android Allow → `P44 capture` → `P45 result` → `Add to library` → `P12/P11`; denied → `S05/S06` → `P06/P18`

### Flow H: Profile/data controls

`P09 Profile` → `P51 Settings` → `P56 consent` → accept/withdraw → `P51`

`P09 Profile` → `P51 Settings` → `P57 Export` → `P58 progress` → success/cancel → `P57`

### Flow I: Tablet list-detail

`T02 Library list` → select category in left pane → word list center → select word → detail right; system Back clears detail first, then returns to previous root. เมื่อ window แคบลง ให้ detail เป็น P12 full-screen โดยรักษา selected word และ scroll position

## 7. Android Back, overlays และ state restoration

ลำดับ Back ทุกขนาดจอ:

1. ถ้ามี keyboard เปิด: ซ่อน keyboard ก่อน โดยไม่ทิ้งค่า
2. ถ้ามี modal/dialog/bottom sheet/drawer: ปิดชั้นบนสุดและไม่ commit
3. ถ้ามี expanded tablet detail: clear detail selection ก่อน pop root
4. ถ้าอยู่ nested page: pop กลับ source พร้อม scroll/filter/selected tab เดิม
5. ถ้าอยู่ active learning session และยังมี unsaved work: เปิด O07 exit confirmation; `อยู่ต่อ` เป็น default
6. ถ้าอยู่ root ของ destination: system Back ออกจาก/ส่งแอปไป background ตาม Android; ห้ามวนสลับ 4 tabs แบบคาดเดาไม่ได้

Overlay rules:

- Research consent ใช้ non-dismissible dialog แต่มีสองทางเลือกที่ชัดและการปฏิเสธไม่ปิดการเรียน
- Permission rationale แสดงก่อน system prompt เฉพาะตอนผู้ใช้กดฟีเจอร์ที่ต้องใช้สิทธิ์
- destructive confirmation ระบุชื่อสิ่งที่จะลบ/ถอน/ซื้อและผลกระทบ; Cancel เป็น safe default
- loading overlay ห้ามบัง Back นานโดยไม่มี status; งาน network/model/export ต้องยกเลิกได้เมื่อ contract รองรับ
- Snackbar ใช้ผลชั่วคราวที่ไม่ต้องตัดสินใจ; error ที่ต้องแก้ต้องอยู่ใกล้ control และมี live announcement

State restoration:

- Root tabs รักษา scroll/filter/state แยกกัน
- หมุนจอ/พับ-กางรักษา active destination, selected item, input draft และ session progress
- process restart ต้องกลับได้ถึง checkpoint ที่ source รองรับ; prototype แสดง resume state โดยไม่อ้างว่า persistence ที่ยังไม่มีพร้อมแล้ว

## 8. Prototype wiring specification

| Trigger | Figma interaction | Transition |
| --- | --- | --- |
| NavigationBar/Rail destination | Navigate to matching P06–P09/T01–T04 | Instant หรือ 180ms dissolve; selected state เปลี่ยนโดยไม่ขยับ layout |
| List/card ที่เปิดรายละเอียด | Navigate to full screen (phone) / Change-to variant or detail frame (tablet) | Smart animate 180ms เฉพาะเมื่อ bounds สอดคล้อง |
| Dialog/permission/confirm | Open overlay, centered, background scrim | Dissolve 120–180ms; Back/Cancel close overlay |
| Bottom sheet ตัวเลือก | Open overlay จากล่าง | 180–240ms; รองรับ drag handle และปุ่ม Close |
| Answer/feedback | Change to component/frame variant | 120ms; progress/choice bounds คงที่ |
| Submit/loading | Change to disabled+busy variant | ไม่เปลี่ยนขนาดปุ่ม |
| Retry | Navigate/change to loading แล้ว success/error sample | เชื่อมครบ ไม่มี dead end |
| Tablet master-detail | Change selected row + detail content | 180ms; rail ไม่เคลื่อน |

ตั้ง Flow starting point อย่างน้อย 6 จุด: `Guest onboarding`, `Daily learning`, `Vocabulary`, `Progress repair`, `AI setup`, `Tablet library`

## 9. Acceptance checklist สำหรับ clickable wireframe

### Coverage และ navigation

- [ ] อยู่ใน Figma Page เดียว; ใช้ Section ไม่เพิ่ม Page
- [ ] 4 root destinations กดได้ทั้ง NavigationBar และ NavigationRail
- [ ] ทุกเมนู/row/button ที่ดู active มี target, overlay หรือ deterministic state change
- [ ] ทุก flow A–I เดินได้ถึงปลายทางและย้อนกลับได้โดยไม่ dead end
- [ ] เส้นทาง Login → Guest/Account → Home, Quiz → Feedback → Score และ Library → Add/Import → Practice กดได้ครบ
- [ ] limited/hidden/enabled ตรงกับ `FieldFeatureRegistry` และไม่มีฟีเจอร์เปิดก่อน dependency/authority พร้อม

### Android responsive

- [ ] ทดสอบ compact 360×800, large phone 412×915, medium 700×1000, expanded 1024×1366 และ landscape 1280×800
- [ ] Phone ใช้ bottom nav; medium/expanded ใช้ rail; ไม่มี destination label ล้น
- [ ] Tablet list-detail ไม่ขยายข้อความเต็มความกว้างเกินอ่าน และ foldable ไม่มี control ทับ hinge
- [ ] fixed action, NavigationBar และ keyboard ไม่บัง content/inline error
- [ ] text scale 200%, Thai wrapping และ font weight 400/500/700/800 ไม่ตัดข้อความ

### State และ accessibility

- [ ] มี loading, empty, error/retry, offline, save pending/saved, permission denied/permanent denied และ destructive confirmation
- [ ] ทุก touch target อย่างน้อย 48×48dp; pressed/selected/disabled/loading ชัดเจนโดยไม่ทำ layout shift
- [ ] color ไม่เป็นสัญญาณเดียวสำหรับ correct/wrong/limited/offline
- [ ] Back behavior เป็นไปตามลำดับในหัวข้อ 7 และ active session มี exit confirmation
- [ ] modal มี focus order, accessible name และ scrim contrast; error/live status ถูกประกาศ
- [ ] Reduce Motion ตัด nonessential animation และยังเข้าใจ state change ได้

### Product/data integrity

- [ ] Mastery อ้าง evidence/sample; XP/streak/reward ไม่แสดงเป็น mastery
- [ ] research เป็น optional; decline/withdraw แล้วยังเรียน offline ได้
- [ ] AI key/credentials ไม่ปรากฏใน mock data หลัง save และมี consent/fallback ชัดเจน
- [ ] camera/mic ขอ permission เมื่อเข้า feature โดยเจตนา ไม่ขอตั้งแต่ launch
- [ ] reward/purchase action ไม่อ้างว่าซื้อผลการเรียน และมี idempotent success state
- [ ] internal research dashboard ระบุ synthetic-only และไม่อยู่ในเมนูผู้เรียนทั่วไป

## 10. หลักฐาน source ที่อ่าน

- `AGENTS.md`
- `docs/development/agentic-development-life-cycle.md`
- `DESIGN.md`
- `design-system/lexiquest/MASTER.md`
- `docs/research/2026-10-18-duolingo-astra-alltcas-layout-synthesis.md`
- `docs/research/2026-10-18-duolingo-alltcas-feature-study.md`
- `docs/design/lexiquest-canva-master-ui.html`
- `lib/main.dart`
- `lib/navigation/app_routes.dart`
- `lib/navigation/app_route_factory.dart`
- `lib/runtime/field_feature.dart`
- `lib/runtime/field_feature_registry.dart`
- `lib/screens/*.dart` โดยเน้น `main_navigation_screen.dart`, account, vocabulary, learning, progress, reading, AI/media, rewards, settings และ export
- `lib/widgets/research_consent_dialog.dart`
- `lib/widgets/association_dialog_widget.dart`
- `test/screens/production_shell_navigation_test.dart`
- `test/screens/main_navigation_screen_test.dart`
- `test/screens/login_guest_mode_test.dart`
- `test/screens/registration_flow_test.dart`
- `test/screens/profile_settings_screen_test.dart`
- screen tests ที่ยืนยัน loading/empty/error/feedback/permission ของ Quiz, Choose Mode, Weakness, SRS, AI Tutor, Gemini settings, camera และ voice

แนวทาง UI/UX ที่นำมาทบทวนเพิ่มเติมมาจาก `ui-ux-pro-max`: predictable Back history, LayoutBuilder/adaptive constraints, stable loading layout, error ใกล้จุดเกิดพร้อม recovery, 48dp Android touch target, safe area, contrast และการทดสอบ TalkBack/large text
