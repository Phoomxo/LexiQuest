# R15.1 Engineering Specification — LexiQuest

วันที่ 2026-09-12 · source baseline `8c160f87d77d8beb8ace2d8f2b7b0e92acb297ac` · เอกสารออกแบบสำหรับพัฒนา ไม่ใช่ผลการทดสอบ runtime

เอกสารนี้เติมข้อกำหนดที่ roadmap R15 ยังไม่ได้กำหนด และมีลำดับเหนือถ้อยคำกว้าง ๆ ใน roadmap เฉพาะรายละเอียดการพัฒนารอบนี้ ผู้ใช้ยืนยันล่าสุดว่าข้อกำหนด UI/เกมเก่าจำนวนมากเป็นวิธีแก้ปัญหาเฉพาะจุดและปรับแทนได้ตามหลักฐานใหม่ จึงไม่ถือว่ารูปแบบหรือโค้ดเดิมเป็นข้อกำหนดถาวร ขอบเขต 8/44 และ frozen data contracts ยังเป็นฐานความเข้ากันได้ ไม่ใช่ข้อบังคับให้หน้าตาหรือวิธีฝึกเหมือนเดิม เลข R15.1 ในหัวเอกสารคือ revision ของชุดเอกสาร ไม่ใช่ package R15.1 หรือ APK version

อ่านประกอบ [source register](2026-09-12-r15-source-register.md), [acceptance/implementation contract](../plans/2026-09-12-r15-acceptance-contract.md) และ [roadmap](../plans/2026-09-12-r15-autonomous-development-roadmap.md) ครบทั้งสี่ไฟล์ก่อนเริ่มงาน

คำว่า MUST คือข้อกำหนดตรวจรับ; SHOULD คือค่าเริ่มต้นที่เปลี่ยนได้เมื่อบันทึกเหตุผลและหลักฐาน; ห้ามตีความ SHOULD เป็น permission gate ทุกครั้ง เลขค่าที่ระบุว่า project decision คือค่าที่เราเลือกสำหรับ LexiQuest ไม่ใช่มาตรฐานภายนอกหรือค่าที่วัดจาก competitor

## 1. ข้อสรุปการออกแบบและทางเลือก

**D-01 เลือกโครงแบบผสม:** Today มีคำแนะนำจากข้อมูลจริง และมีทางเข้าเลือกกิจกรรมเองตลอด ตาม E-D11/E-A01 และ C-TODAY ทางเลือก path บังคับทั้งหมดเพิ่มการสร้าง curriculum/locking ซึ่งยังไม่มีข้อกำหนด; ทางเลือกคลังเกมอย่างเดียวไม่ช่วยตอบว่าควรเรียนอะไรต่อ จึงไม่เลือกทั้งสองแบบเป็น navigation หลัก

**D-02 design system ที่ปรับแทนได้:** เริ่มจาก M3Theme, NotoSansThai และ semantic roles ตาม C-THEME/C-UI เพราะมีการรองรับภาษาไทยและ accessibility อยู่แล้ว แต่แก้ theme/component/shell หรือแทน layout ได้เมื่อรูปแบบใหม่เหมาะกว่า ไม่ต้องขออนุมัติซ้ำเพียงเพราะต่างจาก UI เก่า เลือก redesign เป็นชุดเส้นทางใช้งานที่ตรวจรับได้แทนการแก้ทั่วแอปพร้อมกัน ไม่คัดลอก assets/mascot ของ competitor

**D-03 local-first:** การเรียนหลัก/ประวัติ/dashboard ทำงานผ่าน read models และ authorities เดิม AI/cloud เป็น optional integrations ตาม C-PROGRESS/C-SYSTEM; ไม่ใช้ chatbot เป็นแหล่งเฉลยบังคับของบทเรียนที่ตรวจคำตอบได้อยู่แล้ว

**D-04 camera:** ทำ uncertainty UX และ validation pipeline ก่อนรับ model candidate; baseline คงเดิมในชุดงานนี้ ตาม C-CAMERA ไม่เปลี่ยนไป detector/RAG/โมเดลใหม่เพียงเพราะดูทันสมัย

## 2. Foundation และ visual tokens

| ID | ข้อกำหนด | ค่า/การผูกเข้าของเดิม | อ้างอิง |
| --- | --- | --- | --- |
| UI-01 | MUST ใช้ฟอนต์ไทยและ text scaling ของระบบ | NotoSansThai; titleLarge 20/w600/1.4, titleMedium 16/w600/1.5, body 16/1.5, supporting 14/1.5 ตาม M3Theme; ห้าม clamp text scale เพื่อทำให้พอดี | C-THEME, S-FLUTTER |
| UI-02 | MUST ใช้สีตาม semantic role | text/onSurface, secondary text/onSurfaceVariant, CTA/primary+onPrimary, surface/surfaceContainer ตาม theme; ห้ามใช้ primaryBlue ดิบเป็น foreground แล้วถือว่าผ่าน contrast | C-THEME, S-CONTRAST |
| UI-03 | MUST มีข้อความ/ไอคอนประกอบสีสถานะ | correct = check+“ถูกต้อง”, wrong = error+คำอธิบาย, support = help+“สำเร็จด้วยตัวช่วย”; selection ไม่ใช้สี success | E-D04/E-D05/E-A06, project decision |
| UI-04 | MUST รักษาพื้นที่กดและการอ่าน | tap target ≥48×48 logical pixels; ข้อความทั่วไป contrast ≥4.5:1 เป็น project target ทั้งขนาดเล็ก/ใหญ่; ตรวจ light/dark จริง ไม่อ้าง WCAG certification ทั้งแอป | S-FLUTTER, S-CONTRAST |
| UI-05 | SHOULD ใช้ spacing scale เดียว | 4,8,12,16,24,32 logical pixels; outer padding 16 เมื่อ width<600, 24 เมื่อ ≥600; content max width 960; section gap24; item gap12; card padding16/radius16 ตามฐาน theme | C-THEME, project decision |
| UI-06 | MUST responsive ตามพื้นที่และข้อความ | grid content/mode 1 column เมื่อ width<360 หรือ textScale≥1.5; มิฉะนั้น 2 columns เมื่อ width<840 และ 3 เมื่อ ≥840; ถ้าชื่อการ์ดล้นให้เพิ่มความสูง ไม่ตัดชื่อสำคัญ; ไม่บังคับ policy นี้กับ Pair board ซึ่งมี spatial contract ของตัวเอง | C-UI, project decision |
| UI-07 | SHOULD เลือก alignment ตามงาน ไม่ยึดข้อกำหนดเก่า | ค่าเริ่มต้นรอบนี้: การ์ดหมวด/วิธีฝึก icon+ชื่อสั้นกลาง; header/คำอธิบาย/ประโยค/เฉลยชิดซ้าย; หาก metadata ยาวหรือเปรียบเทียบหลายชุด ให้เปลี่ยนเป็น list row ชิดซ้ายพร้อมภาพ before/after และตรวจ A-UI; page title หนึ่งแห่ง | C-UI, E-A01, user clarification 2026-09-12 |
| UI-08 | MUST มี safe area/focus | CTA footer อยู่เหนือ keyboard/system inset; scrolling content มี bottom padding เท่าความสูง footer ที่วัดได้+16 ไม่ hardcode ทับแถวสุดท้าย; focus order = header→content→feedback→CTA | C-UI, S-FLUTTER |

เลข width/textScale ข้างต้นเป็น project decisions สำหรับหน้าที่เปลี่ยนรอบนี้ ไม่บังคับปรับหน้าที่ไม่เกี่ยวข้องและไม่เปลี่ยนเส้นทาง/เมนูที่มี contract โดยอัตโนมัติ ใช้ widget tests ตาม matrix A-UI ก่อนขยายไปหน้าถัดไป

Feedback palette ที่จะเพิ่มใน theme extension ต้องมีชื่อบทบาท success/onSuccess, support/onSupport ใช้สีเดิมที่ผ่าน contrast ถ้ามีอยู่แล้ว; หากต้องกำหนดใหม่ให้ใช้ light success background #E8F5E9/text #1B5E20 และ support background #E8EAF6/text #283593; dark success background #1B3B26/text #C8E6C9 และ support background #20284F/text #C5CAE9 เป็น starting palette ของ project ต้องตรวจ contrast จากคู่สีจริงก่อนรับ ไม่แก้ colorScheme.error ให้กลายเป็น support

## 3. Screen templates (ข้อกำหนดองค์ประกอบ ไม่ใช่ภาพประชาสัมพันธ์)

ทุก template มี content slot, state, action, owner และ test case ด้านล่าง จัด layout ตามลำดับนี้แล้วตรวจภาพจาก Flutter จริง ห้ามใช้รูป mockup เป็นหลักฐานว่าพฤติกรรมผ่าน

### T-01 Today / เริ่มเรียน

```text
Page title: วันนี้
Primary action card: ชื่อกิจกรรมจริง + เหตุผลหนึ่งบรรทัด + [เรียนต่อ/เริ่มฝึก]
Secondary action: [เลือกฝึกเอง]
Review section: จำนวนถึงกำหนดจริง + [ทบทวน]
Planning: เป้าหมายวันนี้ / reminder ที่ตั้งไว้
Continuity: สรุปกิจกรรมและทางเข้าประวัติ
Existing navigation
```

UI-09: ใช้ TodayHubSnapshot.sectionOrder และ dependencyStates เดิม ไม่ sort curriculum ใหม่ใน widget; เลือก primary จาก action แรกที่เปิดได้ตาม canonical order (รวม assigned หากมี authority จริง) ไม่ซ่อน assigned assessment ที่มีอยู่เพื่อให้ตรง wireframe ordinary learner ไม่มี research assignment ก็ไม่สร้างขึ้นมา CTA ที่ใช้ dependency stale/corrupt/unavailable ต้องไม่สร้าง learning session จากข้อมูลนั้น; section อื่นยังใช้ได้

Empty: “ยังไม่มีกิจกรรมล่าสุด” + เลือกฝึก; review empty: “ยังไม่มีคำถึงกำหนดทบทวน”; recommendation unavailable: “คำแนะนำยังไม่พร้อม” และคงเลือกฝึกเอง; loading แสดง progress indicator พร้อม semantic label ไม่มี fake progress percentage การ refresh ไม่เปลี่ยน sectionOrder ด้วยข้อมูลคนละ owner

### T-02 คลัง/ชุดคำ/เลือกวิธีฝึก

```text
Title + search
Filter chips (หมวด/ระดับที่มีจริง)
Content grid: icon, ชื่อ, จำนวนคำ, ความพร้อม
เมื่อเปิดชุด: ชื่อ+คำอธิบาย → [เริ่ม/ทบทวน] → mode grid
```

UI-10: search-no-result ต้องต่างจาก empty-category; ไม่มีเนื้อหาก็ไม่สร้างปุ่มเริ่มที่กดแล้วเงียบ disabled mode ต้องบอกเหตุผล เช่น “ชุดนี้ยังไม่มีเนื้อหาสำหรับกิจกรรมนี้” ไม่ใช้คำว่าล็อกพรีเมียม หากไม่ใช่ข้อเท็จจริง ตัวเลข “จำแล้ว” ต้องมาจาก authority ที่นิยามได้ มิฉะนั้นใช้ “คำในชุด” หรือไม่แสดงตัวเลขนั้น

### T-03 Lesson / ฝึก

```text
Back/exit + progress ตามจำนวนกิจกรรมจริง
Prompt / sentence / board
Answer controls
Feedback: สถานะ + คำอธิบายสั้น + [ดูรายละเอียด] เมื่อมี
Primary CTA: ตรวจคำตอบ หรือ ถัดไป ตาม mode contract
```

UI-11: เลือกจังหวะตรวจตามกิจกรรม Pair ค่าเริ่มต้นรับ selection event; quiz/cloze ค่าเริ่มต้นใช้ submit ที่มีอยู่ เปลี่ยน interaction ได้เมื่อหลักฐานชี้ประโยชน์และเขียน acceptance ของ accidental tap/แก้คำตอบ/submit ซ้ำ/ผลการเรียนครบ ไม่ถือว่าพฤติกรรมเดิมถูกต้องเพียงเพราะมี test. Feedback ที่ต้องอ่านไม่หายตาม timeout; คำถามใหม่เริ่มที่ prompt แต่การเปิดคำอธิบายไม่ reset scroll โดยไร้เหตุผล exit ใช้ lifecycle/copy ที่เกิดขึ้นจริง ไม่อ้าง “บันทึกแล้ว” ถ้าการเขียนยังไม่สำเร็จ

### T-04 Result / Review

```text
จบรอบแล้ว + ชื่อกิจกรรม
ผลที่ตรง evidence: จำนวนถูก/ตัวอย่าง หรือสรุป exposure/support
สิ่งที่ควรฝึกต่อ + [ทบทวนข้อที่ควรฝึก]
Reward summary ที่ได้รับจริง (ถ้ามี)
[กลับหน้าวันนี้] + [ดูประวัติ]
```

LEARN-01: repair/replay แสดงป้าย “ฝึกซ้ำ” และนโยบายรางวัลที่จริง; ไม่แทน first-attempt score ด้วย repair score Flashcard จำได้และอ่านจบไม่กลายเป็นผลสอบ 100% Missing title/level จากประวัติต้องแสดงไม่พร้อม ไม่เติมจากเนื้อหารุ่นปัจจุบัน

LEARN-02: explanation แบ่งสรุป≤2 ประโยคในส่วนแรก (project copy guideline ไม่ใช่ข้อจำกัด model) กับรายละเอียดที่ขยายได้; ถ้าเฉลยไม่มีหรือ content version ไม่ตรง ให้บอก “คำอธิบายยังไม่พร้อมสำหรับเนื้อหานี้” ไม่เรียก AI สร้างเฉลยแทนโดยอัตโนมัติ

### T-05 Dashboard / เป้าหมาย

```text
ความก้าวหน้า + ช่วงวันที่/timezone
สรุป: active time / accuracy+n / review due
ควรทำต่อ: action จาก recommendation/review เดิม
รายละเอียด: mastery, calendar, streak/XP (แยกบทบาท)
เป้าหมาย + reminder settings
```

DATA-01: ใช้ PersonalLearningProfile แบบ read-only; accuracy = correctCount/sampleSize×100 เฉพาะ availability available และ sampleSize>0 แสดงถูก/จำนวนร่วมกับเปอร์เซ็นต์; sampleSize=0 หรือ noEvidence แสดง “ยังไม่มีข้อมูลคำตอบที่ใช้คำนวณ” ไม่หารศูนย์ ไม่แสดงกราฟศูนย์เป็นความสามารถ

DATA-02: effort ใช้ activeDuration จาก profile ไม่ wall clock เปิดแอป; mastery ใช้ masteredWordCount/skills จาก authority ไม่ใช้ XP; week range ใช้ timezone policy เดิมของ LearningCalendarSnapshot ไม่กำหนดต้นสัปดาห์ใหม่ใน widget. DTO ไม่รองรับช่วงสัปดาห์ที่ต้องการต้องขยาย reader query อย่างมี test ไม่เอาค่าตลอดเวลามาติดป้าย “สัปดาห์นี้”

### T-06 Scanner

```text
กล้องคำศัพท์ + คำแนะนำจัดวัตถุในภาพ
Preview / permission หรือ model readiness panel
[ถ่ายภาพ] → processing → ผลที่เสนอพร้อมชื่อคำ
[บันทึกคำ] เมื่อ mapped result ใช้ได้ / [ถ่ายใหม่]
ผลไม่รองรับ: ข้อความ + ถ่ายใหม่ + ทางเข้าเพิ่มคำเองที่มีอยู่
```

CAM-01: UI state ต้องแยก permissionDenied, modelMissing/downloading, ready, processing, notConfident, unsupportedLabel, mappedResult, saving, saved, recoverableError; ชื่อเหล่านี้เป็น presentation states ที่ต้อง map จาก result/error ของเดิม ไม่ใช่ข้อเสนอเพิ่ม enums ลง frozen contracts

CAM-02: ใช้ ObjectScannerController.captureAndClassify → ObjectScanResult → accept เท่านั้น; ไม่ accept ระหว่าง processing; ผลเก่าหลัง owner/lease เปลี่ยนไม่เปิดบันทึก; accept twice ต้อง reuse existing duplicate vocabulary behavior ไม่สร้าง parallel store. ผล notConfident ไม่เขียนคำ, unsupported label ไม่เลือกคำอื่นเองโดยไม่ให้ผู้เรียนเห็น

### T-07 AI Tutor

```text
ติวเตอร์ภาษาอังกฤษ + สถานการณ์/ระดับ + [เริ่มบทสนทนาใหม่]
Conversation turns พร้อม user/assistant role
Busy/error เป็นสถานะในบทสนทนา
Composer + ส่ง (cancel ตาม transport เดิม)
Provider/settings entry; ไม่มี key → ตั้งค่า หรือ กลับไปฝึกปกติ
```

AI-01: session-only history ใน revision นี้ ไม่มี chat-history table ใหม่ ไม่มีการคัดลอก ALLTCAS retention 90 วัน; เปลี่ยน owner/new chat ล้าง context; provider/model/scenario เปลี่ยนเริ่ม session ใหม่เพื่อไม่ปะปน provenance

AI-02: ข้อความแสดงเป็น selectable plain text เป็น baseline เพื่อไม่ทำคำหาย หาก renderer Markdown เดิมยังใช้ ต้อง fallback plain text ได้โดยไม่ตัดเนื้อหาต้นฉบับ ไม่เพิ่ม streaming endpoint เพียงเพื่อ animation: Future response เดิมแสดง busy state อย่างซื่อสัตย์

## 4. Motion และ Pair state contract

UI-12: ใช้ M3Theme.motionDuration และ applyReducedMotionPreference ที่มีอยู่ ไม่สร้าง preference อีกชุด platform disableAnimations=true ต้องไม่ถูก override เป็น false

| Event | Presentation | Timing (project decision) | สิ่งที่ห้าม |
| --- | --- | --- | --- |
| Select | border/background เปลี่ยนพร้อม semantic selected | 100ms transition | ไม่ประกาศว่าถูกก่อน engine ยอมรับ |
| Accepted correct | check+“ถูกต้อง”, retain slots เดิม | hold 450ms แล้ว fade 150ms | ห้ามเขียน evidence/reward จาก callback |
| Incorrect | error+ข้อความที่สอดคล้อง repair policy | transition150ms; feedback อ่านได้จน action ถัดไปที่ policy อนุญาต | ห้าม auto-select คำเฉลย |
| Assisted completion | help+“สำเร็จด้วยตัวช่วย” | hold450ms/fade150ms | ไม่ใช้ label “ตอบถูกเอง” |
| Final pair | แสดง feedback เช่นเดียวกับคู่ทั่วไปแล้ว result | รวม600ms ปกติ | ห้ามรอ animation ก่อน durable completion |
| Reduced motion | ไม่มี fade/scale/hold ที่บังคับรอ | transition0ms; final result มีสถานะสรุปและ focus ที่อ่านได้ | ไม่ลบข้อมูล feedback ออกจาก semantics/result |
| Goal/reward | summary เปลี่ยน state หนึ่งครั้ง | transition150ms; optional flourish≤600ms | ห้าม replay reward animation ทุก rebuild |

PAIR-01: presentation episode identity ใช้ sessionId + roundOrdinal + accepted operation identity ที่ engine คืน/เก็บ (`lastOperationId`) ไม่ใช้เวลาสุ่ม แสดง episode เฉพาะ update ที่รับใหม่ในหน้าปัจจุบัน; initial load/rehydration ของ matched state ไม่เล่นย้อนหลังทุกคู่ แยก correctness/support จาก authoritative transition และ supportedWordIds ไม่อนุมานจาก matched count อย่างเดียว

PAIR-02: durable terminal state มีอำนาจเหนือ presentation state เสมอ Host อาจคง snapshot ของ board ไว้แสดง 600ms หลังยืนยัน terminal แต่ต้องปิดการส่ง input ทั้งหมดใน terminal overlay. สำหรับ nonterminal ล็อกเฉพาะ tiles ของ episode ที่กำลังจบตาม engine admissibility ไม่หยุด active clock เพิ่มเอง หากมีหลาย episode ให้ติดตามแยก word identity; final result รอเฉพาะ episode ที่ยังแสดงในหน้าปัจจุบันสูงสุด600ms นับจาก final acceptance ไม่ต่อคิวจนนานขึ้น

PAIR-03: dispose/owner change/session change ล้าง timers/episode; callbacks ตรวจ mounted+identity; reopen terminal เปิด result ทันที ไม่เริ่ม timer 600ms ใหม่ Focus ไม่ย้ายไป hidden tile; reduced motion ย้ายไป result heading ตาม frame ที่พร้อม โดยไม่รอเสียง/TTS จบ

Backend/engine ยังคำนวณ correctness, repair, rewards และ clock ตามเดิม View ส่ง tile identity ผ่าน onSelectTile ไม่ตรวจว่า prompt/target แปลตรงกันเอง Interface `PairBoardModel(state,timer,busy,...)` เดิมต้อง backward-compatible หากเพิ่ม presentation input ให้เป็น optional default ที่ไม่เปลี่ยน callers ที่ยังไม่ได้รับ episode

## 5. Backend/data contract

DATA-03: UI เป็น consumer ของ read models และ existing use cases; ห้าม widget เขียน Drift, research rows หรือ reward counters โดยตรง. หลัง session commit การ compose Today/Profile ใหม่ต้องใช้ owner และ evaluatedAtUtc ที่ถูกต้อง ไม่แชร์ cache คนละ owner

DATA-04: replay/repair/exposure มี semantic identity เดิม การเพิ่ม explanation metadata ผูก content ID+version ที่ reader ตรวจได้ ไม่เขียนทับ historical snapshot; หากไม่มี original metadata ให้ UI unavailable ตาม T-04 แทน migration เติมข้อมูลที่เดา

DATA-05: R15 ไม่เพิ่ม owner-scoped table เป็นค่าเริ่มต้น ถ้าพบจำเป็นต้องเพิ่มจริง ให้สร้าง change record ระบุ schemaVersion ปัจจุบัน/table owner key/export/delete/sync/policy และเพิ่ม tests ก่อนรับ diff ไม่ reserve migration number ใน roadmap

SYS-01: offline ordinary learning ไม่ต้องมี credential/network/research consent; research authority unavailable ต้อง fail closed เฉพาะ research. ตรวจ withdrawal/owner isolation/signature/permit ตาม existing policies ไม่แก้ gate เพื่อให้ demo ผ่าน

SYS-02: animation และ mock provider response ไม่ใช่ authoritative event. operation retry ใช้ identity เดิมถ้า acknowledgement หาย; ไม่สร้าง write ใหม่เพื่อชดเชย UI timeout

## 6. Camera experiment protocol ที่ตัดสินใจได้

CAM-03: รอบนี้จำกัดเป็น evaluation improvement และ candidate artifact เท่านั้น baseline manifest ไม่เปลี่ยน การยอมรับ candidate เข้า engineering evaluation ไม่เท่ากับอนุมัติ rollout

Dataset protocol (project decisions):

1. ประกาศ supported vocabulary classes และ label mapping ก่อนเลือกภาพ; revision นี้ pilot ยัง book/bottle/chair/cup ไม่ใช้ข้อสรุปแทน broad baseline coverage
2. ใช้ source-image/capture-group เป็น split unit; checksum/content duplicate ข้าม split เป็น hard failure; ทุกภาพมี license/source URL/label/split/hash. ข้อมูลเดิม40ภาพเป็น regression set เท่านั้น
3. Fresh validation อย่างน้อย30ภาพต่อ known class +200 unknown natural images, fresh test อย่างน้อย30ภาพต่อ known class +200 unknown จากกลุ่มต้นทางแยกกัน; จำนวนเป็น minimum engineering gate ไม่ใช่หลักประกัน statistical power. ถ้า source ที่อนุญาตไม่พอ รายงาน insufficient coverage และคง baseline ไม่ลด minimum หลังเห็นคะแนน
4. Unknown ต้องมีหลายวัตถุที่ไม่ใช่ known classes และฉากว่าง/รกจริง ไม่ใช้เพียง UI screenshots. เก็บ camera-like full frames แยกจาก crops; ไม่รายงานทั้งสองเป็น independent image count
5. เลือก model/threshold จาก validation เท่านั้น แล้ว freeze hashes/config ก่อน test. หลังเปิด test แล้วการปรับอีกครั้งต้องถือว่า test เดิมกลายเป็น development evidence

Engineering acceptance สำหรับพิจารณา candidate (ไม่ใช่ physical release): unknown false acceptance≤5%, known correct-and-accepted≥85% overall และ≥75% ทุก known class บน fresh test, รายงาน numerator/denominator และ Wilson95% intervals; baseline comparison ต้องใช้ภาพเดียวกัน. ค่า thresholds นี้เป็น project choices ไม่อ้างเป็น literature benchmark

Resource gate: ไม่มี invalid tensor/nonfinite/crash; repeated load/invoke/close30 cycles ไม่เหลือ active runtime handle; เปรียบเทียบ fresh processes ≥3/model/delegate, warmup5/measured50 ตาม protocol เดิม เก็บ cold/warm p50/p90 และ sampled RSS. Latency p90 pipeline ของ candidate≤1.2×baseline และ sampled RSS delta≤1.5×baseline บนอุปกรณ์เดียวกันเป็น comparative gate; host-only result ไม่ผ่าน physical gate และ RSS trend ไม่พิสูจน์ absence of native memory leak

Candidate ที่ลด vocabulary coverage ของ baseline ห้ามแทน baseline ทั้งแอปแม้ผ่าน4-class gate. ทางเลือก classifier routing/unknown head ต้องเป็น spec revision เพิ่มพร้อม failover tests ไม่ซ่อนเป็น implementation detail. ถ้าไม่ผ่าน ให้จบงานด้วย retained baseline + failure report แล้วทำ package อื่นต่อ

## 7. AI request contract สำหรับ implementation

AI-03: เพิ่ม immutable context value ใน `lib/features/ai_tutor/domain/ai_tutor_contracts.dart` (ไม่เพิ่ม storage) โดยกำหนด shape สำหรับ implementer:

```dart
enum TutorTurnRole { learner, tutor }
enum TutorIntent { conversation, explanation, practice }
class TutorContextTurn { // proposed type, not yet in source
  final TutorTurnRole role;
  final String text;
  const TutorContextTurn({required this.role, required this.text});
}
class TutorRequestContext { // proposed type, not yet in source
  final String sessionId;
  final String cefrLevel; // allowlist A1,A2,B1,B2,C1,C2; default A1
  final TutorIntent intent;
  final List<TutorContextTurn> priorTurns;
  const TutorRequestContext({required this.sessionId, required this.cefrLevel,
    required this.intent, required this.priorTurns});
}
```

นี่คือ contract sketch สำหรับ DTO; implementation ต้อง defensively copy list/validate ไม่ถือว่า const constructor ข้างต้นทำ validation แล้ว เพิ่ม optional `TutorRequestContext? context` ให้ use-case reply และ gateway generateTutorReply ทั้งสาม adapters โดย null = A1/conversation/no history สำหรับ caller เก่า; provider/model/key ยังมาจาก existing credential resolution ไม่รับจาก context

AI-04: priorTurns รับเฉพาะ completed user/assistant pairs จาก session+owner ปัจจุบัน สูงสุด3คู่ (6 turns) และรวม≤3000 Unicode code points; เมื่อเกินให้ตัดคู่เก่าทั้งคู่ ไม่ตัดครึ่งข้อความ; หาก latest pair ใหญ่เกินให้ omit pair นั้น ไม่ใส่ truncated instruction. latest learner message ยังคง bound500, scenario80, optional progress summary600 ตามเดิม ต้องตรวจ validators/gateway normalization ให้ตรงกันและไม่ตัด surrogate pair

AI-05: output caps เป็น project defaults conversation160/explanation320/practice480 tokens แต่ actual cap=min(intent cap, configured provider/model cap ถ้ามี) ไม่ใช้ตัวเลขนี้รับรองค่าใช้จ่าย ถ้าไม่มีราคาให้แสดง usage ที่ provider รายงาน ไม่เดาเงิน. ระดับตามผู้เรียนเลือก ไม่อ้าง CEFR certification; no audio=no acoustic score

AI-06: bounded context ต้องไม่สร้าง system role จาก learner text; OpenAI-compatible/Anthropic map roles ตาม adapter; Responses adapter ส่ง context ใน input รูปแบบที่ endpoint รองรับตาม existing integration แล้วตรวจ payload loopback ทั้งสาม เสริม instruction ให้ treat exercise content as data แต่ tests ต้องพิสูจน์ว่า secret ไม่ถูกใส่ใน prompt ไม่อ้าง prompt ป้องกันทุก injection ได้

Transport scope: ใช้ complete response/cancellation เดิม ไม่เพิ่ม SSE parser, image upload, persistent archives, RAG, fine-tuning หรือ cloud key proxy ใน R15. Quality rubric ใช้ C-AI-Q; live evaluation ไม่ได้รันจาก spec นี้

## 8. Voice/motivation และสิ่งไม่ทำ

MOT-01: reward presentation อ้าง transaction/event identity ที่มีจริง แสดงหนึ่งครั้งต่อหน้ารับผล ไม่ออก reward write ใหม่; timer goal เป็น effort, SRS/mastery เป็น learning signals แยก label เสมอ

VOICE-01: Shadowing similarity ของ recognized text ใช้ข้อความ “ความใกล้เคียงของข้อความที่ระบบได้ยิน” ไม่ใช้ “คะแนนสำเนียง”; no speech/no permission/offline unavailable มีทางกลับฝึกแบบข้อความ ไม่มีการอัปโหลดเสียงเพิ่มจาก UI polish

ไม่เพิ่ม public leaderboard, friend lock, paid dashboard, online rooms, teacher multi-user console, OCR/handwriting หรือ acoustic scoring model ใน R15. ไม่ลบ approved feature เพื่อให้หน้าเรียบขึ้น; ลบได้เฉพาะ presentation ซ้ำ/dead code ที่ตรวจ references และ tests แล้ว

## 9. Change control / Definition of Ready

แต่ละ package ต้องเปิด requirement IDs และ acceptance IDs ของตนจาก contract; อ่าน actual code at HEAD ใหม่; เปลี่ยน spec เมื่อ semantics/cost/data handling เปลี่ยน แต่ developer เลือกชื่อ private helper/การแบ่ง widget/spacing adjustment ที่ผ่าน acceptance ได้เองโดยบันทึกเหตุผล ไม่ถามผู้ใช้ทุกจุด

Requirement ที่ตัดสินแล้วในเอกสารนี้ไม่ให้ implementerเดาจากภาพ competitor. หากหลักฐานต้นทางหายให้ใช้ source register/hash ระบุ unavailable; ไม่กล่าวว่าเปิดดูหลักฐานแล้ว. ความขัดแย้งกับ frozen contract ต้องออกแบบ compatibility adapter/versioned transition โดยไม่ทำข้อมูลเก่าผิดความหมาย ไม่แก้ authority เพียงเพื่อให้ภาพดูตรง

### การแทนข้อกำหนดเก่า (ใช้ได้โดยผู้พัฒนาตามคำสั่งล่าสุด)

| ประเภท | วิธีดำเนินการ |
| --- | --- |
| Layout, alignment, menu grouping, copy, animation, component implementation | เปลี่ยนได้จากหลักฐานใหม่; บันทึก old rule → observation → new rule → acceptance IDs ไม่ต้องถามผู้ใช้ซ้ำ |
| Game interaction, retry/help flow, question pacing, board arrangement | เปลี่ยนได้เป็นชุดที่สมบูรณ์; ระบุผลต่อ attempt classification/timing/keyboard และอัปเดต behavioral tests ให้ตรง spec ใหม่พร้อมเหตุผล ไม่ลบ test เพียงเพราะ fail |
| Internal architecture, helper APIs, persistence implementation | refactor/แทนได้เมื่อรับผิดชอบ migration/compatibility/export/delete และ canonical authority ไม่แตกเป็นสองชุด |
| ข้อมูลในอดีต, correctness ของผล, owner isolation, consent และสิทธิ์เข้าถึง | ไม่เขียนย้อนหลังให้ดูดีขึ้น; การเปลี่ยนนิยามต้อง version และแยกผลเก่า/ใหม่อย่างตรงไปตรงมา |
| ค่าใช้จ่ายใหม่/production rollout/real research data | คำอนุญาตปรับ design ไม่ได้แทนสิทธิ์สำหรับงานเหล่านี้; เดิน local work ต่อได้ |

ทะเบียนแทนข้อกำหนดเริ่มต้น: OLD-ALIGN “รูป/ชื่อกลางทุกการ์ด” → UI-07 ใช้กลางเฉพาะเนื้อหาสั้นและ list เมื่อ metadata ยาว; OLD-PAIR-HIDE “ซ่อนคู่ทันที” → PAIR-01–03 feedback ก่อนซ่อน; OLD-THEME “ปรับเฉพาะผิวโดยห้ามเปลี่ยนพฤติกรรม” จากรอบ minimal UI → สิ้นสุดขอบเขตเดิมสำหรับงาน R15 ที่อนุมัติแล้ว โดยยังต้องทำ behavioral acceptance; OLD-AI-PROMPT “B1–B2/สองประโยค/120 tokens ทุกคำขอ” → AI-03–06 ตามระดับและ intent. แต่ละรายการเป็นข้อเสนอเปลี่ยนใน spec นี้ ยังไม่อ้างว่าลงโค้ดแล้ว

Definition of Done อยู่ใน acceptance contract: source diff + targeted tests + visual captures เมื่อเกี่ยวข้อง + exact-source integration + unresolved external gates ไม่มีการติ๊กผ่านจากการมีไฟล์หรือ golden baseline เพียงอย่างเดียว
