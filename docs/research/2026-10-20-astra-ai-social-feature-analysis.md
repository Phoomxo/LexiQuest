# Astra AI social feature analysis for LexiQuest

วันที่ตรวจ: 2026-10-20
สถานะ: งานวิจัยผลิตภัณฑ์และข้อเสนอเชิงสถาปัตยกรรม ยังไม่ใช่หลักฐานว่า LexiQuest implementation พร้อมใช้งาน
ขอบเขต LexiQuest: ฝึกภาษาอังกฤษเท่านั้น, Android-first, รักษาแค็ตตาล็อก 8 หมวด/44 ความสามารถเดิม

## 1. วิธีเก็บหลักฐานและข้อจำกัด

- ติดตั้ง `agent-reach v1.5.0` และ OpenCLI `v2.0.1` แล้ว; YouTube ใช้ `yt-dlp` ได้จริง
- หน้า Astra ไทยที่ใช้เป็นฐานหลัก: <https://astra-ai.co/th/>
- ช่อง YouTube ที่เชื่อมโดเมน Astra ในคำอธิบายวิดีโอ: <https://www.youtube.com/channel/UCLeHHS3yKRxBGieWxysicRg/videos>
- Instagram ไทยที่ลิงก์กลับ `astra-ai.co/th`: <https://www.instagram.com/astra_ai_th/>
- Facebook ที่ผลค้นหาสาธารณะระบุเป็น Astra AI: <https://www.facebook.com/astra.si/>
- Instagram/Facebook อ่านจากหน้าสาธารณะและดัชนีค้นหา เพราะ OpenCLI Browser Bridge ยังไม่ได้เชื่อม extension จึงไม่อ้างว่าเก็บทุกโพสต์หรือทุก Reel ได้ครบ
- ภาพจากคลิปใช้เป็นหลักฐานเฉพาะสิ่งที่เห็นใน UI; ข้อความโฆษณา เช่น “เรียนเร็วขึ้น 2x”, “แม่นยำ 91%” หรือ “เกรดดีขึ้น” ไม่ถือเป็นหลักฐานประสิทธิผล
- ไม่ได้เข้าถึง source code, prompt, model, backend, ranking, recommendation หรือข้อมูล A/B test ของ Astra

## 2. YouTube — คลังวิดีโอผลิตภัณฑ์ที่ตรวจ

ตรวจวิดีโอผลิตภัณฑ์ 11 รายการแรกในช่อง และสร้าง contact sheet 8 ช่วงเวลาต่อคลิปจากไฟล์วิดีโอสาธารณะ

| วันที่ | คลิป | สิ่งที่ยืนยันได้ | ประโยชน์ต่อ LexiQuest |
| --- | --- | --- | --- |
| 2025-09-22 | [Največja posodobitev Astra AI](https://www.youtube.com/watch?v=b8PMxJvORJk) | อัปโหลดสื่อ, ระบุวันสอบ/เป้าหมาย, ลำดับแบบฝึก → quiz → flashcard → podcast | ใช้โครง `แหล่งข้อมูล → แผน → ฝึก → ทบทวน`; จำกัดเป็นภาษาอังกฤษ |
| 2025-02-18 | [Inštruktor matematike, ki je vedno na voljo](https://www.youtube.com/watch?v=nGjl3wFIdyY) | เลือกหัวข้อ, วิธีแก้ทีละขั้น, ภาพ/กราฟ, การตั้งค่าบทเรียน | ใช้ pattern อธิบายทีละขั้นและ feedback อยู่ในบริบทเดิม |
| 2025-02-05 | [Kaj je NPZ AI?](https://www.youtube.com/watch?v=kWlP61gfz6o) | โปรแกรมเตรียมสอบแบบมีลำดับและหัวข้อชัด | ใช้ guided path; ไม่ใช้คำกล่าวว่าโมเดล “ทำนายข้อสอบ” |
| 2024-09-18 | [Astra AI ima nov predmet — ANGLEŠČINA](https://www.youtube.com/watch?v=yKq5jxMjDWE) | โหมดภาษาอังกฤษใน chat workspace และแบบฝึกตอบโต้ | เหมาะโดยตรงกับ LexiQuest; ใช้แชตเป็นทางเข้าสู่การฝึก ไม่ใช่ปลายทางอย่างเดียว |
| 2024-05-05 | [GARANTIRAM ti boljše ocene](https://www.youtube.com/watch?v=M4krZidPQ4k) | มีแต่ข้อความการตลาดที่ตรวจประสิทธิผลไม่ได้ | ไม่ใช้เป็น requirement |
| 2024-04-23 | [Astra AI 2.0 UPDATE](https://www.youtube.com/watch?v=D8txlrIOtL8) | สื่อสารการอัปเดตและตัวเลขความแม่นยำเชิงการตลาด | ไม่ใช้ตัวเลขเป็นเกณฑ์ LexiQuest; ต้องมี evaluation ของตนเอง |
| 2024-03-14 | [How to start? Quick Tutorial](https://www.youtube.com/watch?v=-aic3QGXJXU) | onboarding → chat, คำตอบแบบลำดับขั้น, math keyboard, กราฟ และ follow-up | ยืนยันโครง chat-first และ progressive disclosure |
| 2024-02-26 | [Astra AI na iOS-u](https://www.youtube.com/watch?v=uAbBNHErY_o) | ถ่ายรูปโจทย์จากมือถือแล้วส่งเข้าแชต | ใช้แนวคิด “ถ่ายข้อความอังกฤษ → ตรวจแก้ → ฝึก”; iOS ยังอยู่นอกระยะแรก |
| 2024-02-26 | [Astra AI na Androidu](https://www.youtube.com/watch?v=QDqwT2y8M2A) | กล้อง Android, preview ภาพ, ส่งคำถาม และกลับสู่บทสนทนา | reuse camera gateway เดิมและเพิ่ม OCR ภายหลัง |
| 2023-09-14 | [Kako začeti z uporabo](https://www.youtube.com/watch?v=dqH-__zkXuc) | เลือกหัวข้อ, composer, keyboard เฉพาะงาน, คำตอบ card และถามต่อ | composer ต้องเปลี่ยนเครื่องมือตามงาน เช่น ข้อความ/เสียง/ภาพ |
| 2023-09-06 | [25 MILIJONOV v 10ih LETIH](https://www.youtube.com/watch?v=sY1FJfTm_w8) | ถ่ายโจทย์และขอวิธีคิดทีละขั้น | รับเฉพาะ interaction pattern; ไม่รับ claim จำนวนผู้ใช้/ประสิทธิผล |

แหล่งเสริมที่ใหม่กว่าและเห็น UI จริงคือ [Web Summit 2025 interview](https://www.youtube.com/watch?v=8do6lZEqR6E): เลือกวิชา/วันสอบ/เป้าหมาย, อัปโหลดโน้ตหรือข้อสอบเก่า, ปรับระดับตามข้อมูลผู้เรียน, มี Solver mode กับ Socratic mode, math keyboard, วาด, เครื่องคิดเลข, กล้อง และ chat workspace. ข้อมูลนี้ยืนยันรูปแบบผลิตภัณฑ์ ไม่ยืนยันสถาปัตยกรรมภายใน

## 3. Instagram — ฟีเจอร์ต่อคลิป/โพสต์ที่เข้าถึงได้

### ช่องไทยทางการ

| ลิงก์ | สิ่งที่ระบุ | สิ่งที่นำมาใช้ |
| --- | --- | --- |
| [โพสต์ 2026-10-13](https://www.instagram.com/astra_ai_th/p/Debq6s5FA8l/) | เลือกโรงเรียน, อัปโหลด PDF/สไลด์/หน้าหนังสือ, สร้างแผนเตรียมสอบและแนวข้อสอบ | เปลี่ยน “เลือกโรงเรียน” เป็นเลือกระดับ CEFR/เป้าหมายอังกฤษ; มี preview แหล่งข้อมูลก่อนสร้างกิจกรรม |
| [โพสต์ 2026-10-02](https://www.instagram.com/astra_ai_th/p/DeARXO7FATe/) | AI tutor, คำอธิบายทีละขั้น, interactive learning, exam prep | ใช้คำไทยง่ายและมีทาง `อธิบายต่อ` / `ลองทำเอง` |

### Reel สาธารณะ/UGC ที่ลิงก์กลับ Astra

| คลิป | ฟีเจอร์ที่แสดงหรือระบุ | ความเชื่อมั่น |
| --- | --- | --- |
| [Reel ที่ผู้ใช้ส่ง](https://www.instagram.com/reel/DerPBorSrSd/) | สร้างชุดสอบ, อัปโหลดไฟล์/รูป/กล้อง, learning path, บทเรียน/ฝึก/สอบ, readiness, จุดอ่อน, MCQ | สูง — ตรวจเฟรมวิดีโอแล้ว |
| [3D + PDF + quiz](https://www.instagram.com/reel/DeGZDpivUHW/) | โมเดล 3D, PDF, quiz, ถาม AI | สูง — caption และหน้าวิดีโอเข้าถึงได้ |
| [Astra can print you an exam](https://www.instagram.com/reel/DeW0DMzvYc8/) | สร้าง/พิมพ์ข้อสอบฝึก | กลาง — ยืนยันจากดัชนีสาธารณะ |
| [Better than ChatGPT?](https://www.instagram.com/reel/DbS8SetvqB4/) | สร้างเพื่อ workflow การเรียน, เริ่มจาก exam prep และวันสอบ | กลาง — ยืนยันจากดัชนีสาธารณะ |
| [Personalized study paths](https://www.instagram.com/reel/DbH7ivyTefM/) | เลือกวิชา, คะแนนเป้าหมาย, เส้นทางฝึกเฉพาะบุคคล | กลาง — ยืนยันจากดัชนีสาธารณะ |
| [Active recall + Socratic](https://www.instagram.com/reel/DeXBz4nvKvR/) | active recall และ Socratic method | กลาง — ยืนยันจากดัชนีสาธารณะ |
| [Practice exam](https://www.instagram.com/reel/DeOpW66PW9I/) | สร้างข้อสอบฝึกจากบริบท | กลาง — ยืนยันจากดัชนีสาธารณะ |
| [Materials to study guides](https://www.instagram.com/reel/DdZfuNbNLRf/) | เปลี่ยนเนื้อหาเรียนเป็น study guide | กลาง — ยืนยันจากดัชนีสาธารณะ |
| [Materials to study guides — short](https://www.instagram.com/reel/DdWi_1sTfdb/) | workflow เดียวกันในคลิปสั้น | กลาง — ยืนยันจากดัชนีสาธารณะ |

สิ่งที่ซ้ำกันหลายคลิปจึงน่าเชื่อถือในฐานะ **product workflow** คือ `เนื้อหาของผู้เรียน → ชุดเรียน/เส้นทาง → active recall/quiz → จุดอ่อน → รอบฝึกถัดไป`. สิ่งที่ยังเป็น marketing claim คือการทำนายข้อสอบ, เวลาที่ลดลง, คะแนนที่เพิ่ม และเปอร์เซ็นต์ readiness ที่ไม่มีสูตรเปิดเผย

## 4. Facebook — หลักฐานสาธารณะที่ค้นพบ

| คลิป/โพสต์ | สิ่งที่ระบุ | การใช้กับ LexiQuest |
| --- | --- | --- |
| [ติวเตอร์ AI สำหรับทุกวิชา](https://www.facebook.com/astra.si/videos/1522906496687209/) | อธิบายเรื่องยาก, ทำการบ้านทีละขั้น, เตรียมสอบหลายวิชา | รับเฉพาะ step-by-step และ guided practice; LexiQuest คงภาษาอังกฤษวิชาเดียว |
| [เชื่อมโทรศัพท์กับคอมพิวเตอร์](https://www.facebook.com/astra.si/videos/1385320999775537/) | ส่ง/เชื่อมบริบทระหว่างมือถือกับเว็บ | เลื่อนไปหลัง cloud sync และ owner isolation พร้อม |
| [Math tests — step by step](https://www.facebook.com/61572387211214/videos/1256807812682592/) | ถ่ายโจทย์และอธิบายทีละขั้น | ใช้ camera-to-guidance pattern กับข้อความอังกฤษ |
| [Matura AI](https://www.facebook.com/astra.si/videos/1079293527565506/) | โปรแกรมสอบที่อิงข้อสอบและวิธีทำย้อนหลัง | ใช้แนวคิด corpus-grounded; ห้ามอ้างว่าทำนายข้อสอบ |

Facebook บังคับ login เมื่อเปิดวิดีโอโดยตรง จึงใช้ title/snippet ที่ index สาธารณะและไม่อ้างรายละเอียดภาพในคลิปที่ตรวจไม่ได้

## 5. แก่นของ Astra ที่ควรปรับเข้า LexiQuest

1. **Source-first learning** — ผู้ใช้เลือกข้อความ/ไฟล์/รูปก่อน แล้วเห็นว่า AI ใช้ข้อมูลใด
2. **Goal and constraint setup** — เป้าหมายอังกฤษ, CEFR, เวลาที่มี และชนิดกิจกรรม แทนวิชา/โรงเรียน
3. **One visible next action** — ทุกหน้าบอกชัดว่า “ทำอะไรต่อ” และใช้ progress แบบขั้นตอน
4. **Transform once, reuse many ways** — แหล่งเดียวสร้างอ่านในบริบท, บัตรคำ, quiz, เติมคำ, ฟัง/พูด และทบทวน
5. **Socratic before reveal** — ให้คำใบ้ทีละระดับและถามกลับก่อนเปิดคำตอบ
6. **Evidence loop** — คำตอบจริงไหลเข้าสู่ SRS/Weakness/Mastery เดิม; AI ห้ามเขียน mastery หรือ reward โดยตรง
7. **Chat as a familiar shell** — bubble แบบ Messenger/LINE, composer ติดล่าง, เครื่องมือแนบไฟล์/กล้อง/เสียง และ action จากคำตอบกลับไปฝึก

## 6. การแมปกับโค้ด LexiQuest ปัจจุบัน

| ความต้องการ | ของที่มีแล้ว | การเปลี่ยนที่เล็กที่สุดและครบ |
| --- | --- | --- |
| เลือกไฟล์ | `file_selector 1.1.0` | ใช้ dependency เดิม; ไม่เพิ่ม file picker ตัวที่สอง |
| กล้อง | `camera`, `PluginCameraGateway`, image preprocessing | reuse gateway/permission/error เดิม; OCR เป็น adapter ใหม่ภายหลัง |
| นำเข้าคำ | `ImportVocabulary` + Drift + owner isolation + duplicate hashing | ให้หน้าพรีวิวเรียก authority นี้; ไม่ใช้ `CustomWordbookImporter` เป็น persistence ใหม่ |
| Quiz/SRS/จุดอ่อน | `LearningUseCases`, `BinarySm2SrsPolicy`, `WeaknessClinicScreen`, `SrsFlashcardsScreen` | routing กิจกรรมที่สร้างแล้วเข้าของเดิม; ไม่สร้าง scheduler/mastery คู่ขนาน |
| AI content | FastAPI `/v1/content`, Pydantic request, provider chain/cache/rate limit | เพิ่ม contract ที่มีโครงสร้างเฉพาะเมื่อเริ่ม implementation; คง auth/limits/provenance เดิม |
| สนทนา/เสียง | `AiTutorScreen`, `speech_to_text`, `flutter_tts`, voice API | ปรับโครงเป็น LINE/Messenger และเพิ่ม mode “ช่วยคิดทีละขั้น/อธิบายให้เลย”; ไม่เพิ่ม chat SDK |
| อ่านในบริบท | associative reading loop และ reading progress | ต่อจาก import หลัง persistence/restart path ถูกยืนยัน; ไม่เปิดด้วย adapter in-memory |

ข้อค้นพบสำคัญ: `WordbookImportScreen` และ `CustomWordbookImporter` เป็นเส้นทางเก่าที่ parse CSV/JSON แล้วพาไป flashcard โดยตรง และไม่พบ caller ใน `lib`. เส้นทาง UI ที่ใช้งานจริงคือ `VocabListScreen → AddMultipleWordsScreen → ImportVocabulary`. งานใหม่ควรรวมเข้าทางนี้เพื่อลด authority ซ้ำ

## 7. ของสำเร็จรูปที่ควรใช้หรือศึกษาต่อ

| แหล่ง | สถานะ | คำตัดสิน |
| --- | --- | --- |
| [Flutter `file_selector`](https://github.com/flutter/packages/tree/main/packages/file_selector/file_selector) | ติดตั้งแล้ว, Flutter-maintained, BSD | ใช้ทันทีสำหรับไฟล์ `.csv/.json/.txt/.md`; ระวังไฟล์ใหญ่บน Android และจำกัดขนาดก่อนอ่าน bytes |
| [pdfrx](https://pub.dev/packages/pdfrx) | MIT, มี PDFium และ text extraction API | ใช้เฉพาะระยะ PDF หากขนาดแอปและ native packaging ผ่าน spike; dependency `pdf` ปัจจุบันใช้สร้าง PDF ไม่ใช่อ่าน text |
| [google_mlkit_text_recognition](https://github.com/flutter-ml/google_ml_kit_flutter/tree/develop/packages/google_mlkit_text_recognition) | Android/iOS, ใช้ native ML Kit, ไม่ได้ดูแลโดย Google | ตัวเลือก OCR ระยะถัดไป; ต้องวัด APK size, script Latin/Thai, rotation, low-light และข้อมูลที่คงไว้ในเครื่อง |
| [dart-fsrs](https://github.com/open-spaced-repetition/dart-fsrs) | MIT, FSRS Dart | ศึกษาได้ แต่ยังไม่เพิ่ม: evidence ปัจจุบันเป็นถูก/ผิด ขณะที่ FSRS ต้อง rating ที่ละเอียดกว่า; ห้ามสร้าง SRS authority คู่ขนาน |
| FastAPI/Pydantic/Flutter Material ใน repo | ติดตั้งและใช้อยู่ | ใช้ต่อสำหรับ structured output, validation และ chat UI; ไม่ต้องดึง boilerplate AI tutor repo อื่น |

ไม่มี open-source “AI tutor app” ใดที่ควรยกทั้งโปรเจกต์มาใส่ LexiQuest เพราะ auth, owner isolation, EvidenceContext, EventEnvelopeV2, SRS และ reward authority ไม่ตรงกัน สิ่งที่ควร reuse คือ library ขอบเขตเล็กและ interaction pattern ที่ตรวจได้

## 8. แผนพัฒนาที่เสนอใน ADLC

### Card A — file import ที่เชื่อม authority เดิม

- รับ `.csv/.json` ผ่าน `file_selector`
- จำกัดขนาด/MIME/extension, parse แบบ deterministic, preview/edit/ยกเลิก
- ยืนยันแล้วเรียก `ImportVocabulary`; แสดง accepted/duplicate/rejected
- เกณฑ์ผ่าน: owner isolation, retry ไม่ duplicate, cancel ไม่เขียนข้อมูล, restart เห็นคำที่นำเข้า

### Card B — English source material

- รับ `.txt/.md`; ตรวจว่าเนื้อหาเป็นภาษาอังกฤษในสัดส่วนที่กำหนด
- แยกคำ/วลี candidate แล้วจับคู่คลังคำที่มีอยู่ก่อนเรียก AI
- แสดง source name, excerpt, candidate, meaning/POS และให้แก้ก่อน import
- เกณฑ์ผ่าน: ไม่มีเนื้อหาอื่นหลุดเข้า, raw source ไม่ถูก log, ผู้ใช้ยืนยันก่อนเขียนคำ, provenance ติดกับ import

### Card C — guided practice จาก source

- สร้าง action `อ่านในบริบท`, `บัตรคำ`, `แบบทดสอบ`, `เติมคำ`, `ถาม Lexi`
- ทุกคำตอบเรียก `LearningUseCases`; hint/reveal ไม่เพิ่ม mastery
- เกณฑ์ผ่าน: feedback, weakness, SRS, result และ next action ใช้ authority เดิมและไม่บันทึกซ้ำ

### Card D — Socratic AI tutor

- เพิ่มตัวเลือก `ช่วยฉันคิดทีละขั้น` และ `อธิบายให้เลย`
- bubble แบบ LINE/Messenger; คำตอบมี `คำใบ้`, `ตัวอย่าง`, `ลองตอบ`, `ตรวจข้อมูลที่ใช้`, `ไปฝึกคำนี้`
- เกณฑ์ผ่าน: fallback/offline/retry/edit, provenance, quota และข้อความภาษาไทยทั่วไป

### Card E — PDF/OCR หลัง Card A–D ผ่าน

- spike `pdfrx` สำหรับ digital PDF และ ML Kit สำหรับภาพ/scan
- preview หน้า/ข้อความที่อ่านได้และให้แก้ OCR ก่อนสร้างกิจกรรม
- เกณฑ์ผ่าน: file-size limit, timeout/cancel, malformed/encrypted PDF, rotation, low-light, no raw-content logging และ APK size budget

### ข้อกำหนดเพิ่มจากรอบ critique ด้วย Claude Opus 5.5

Claude Opus 5.5 ให้คำตัดสิน `REVISE` และยืนยันว่าลำดับ `A → B → C → D → E` เหมาะสม โดยต้องปิดช่องว่างต่อไปนี้ก่อนเปลี่ยน Card เป็น `Ready`:

1. Card B ต้องทำงานแบบ local match-only ได้เมื่อ AI ปิด, quota หมด หรือ network ล้มเหลว; คำที่จับคู่คลังเดิมไม่ได้คงอยู่ใน preview โดยไม่ถูก import อัตโนมัติ
2. Card C กำหนดว่า `reveal` จบรอบนั้นเป็นคำตอบผิดหนึ่งครั้งผ่าน `LearningUseCases` และใช้ `promptMode` ที่ระบุ assisted/reveal; hint อย่างเดียวไม่เขียน mastery/reward และห้ามบันทึกซ้ำ
3. Card D ใช้ request length, timeout, rate limit และ entitlement เดิม; client ยอมให้มีคำขอ in-flight ครั้งเดียวและต้องแสดง quota/fallback ก่อนเริ่มรอบ Socratic ยาว
4. Card E ไม่เชื่อค่า confidence ที่ plugin อาจไม่มีหรือเทียบข้ามอุปกรณ์ไม่ได้: OCR ทุกครั้งต้องผ่าน preview/edit และผู้ใช้เลือกถ่ายใหม่ ลบ หรือยืนยันก่อนสร้างกิจกรรม
5. ทุก Card ต้องมี fixture offline/slow-network; deterministic import ยังใช้ได้ในเครื่อง, AI แสดง match-only/offline fallback และไม่สร้าง content-request queue ใหม่ที่เก็บ raw source โดยปริยาย

หลังเพิ่มเกณฑ์เหล่านี้ disposition เป็น `GO for Card A planning`; Card B–E ยังต้องผ่าน predecessor และ focused acceptance checks ของตนเอง

## 9. สิ่งที่เลื่อนหรือปฏิเสธ

- เลื่อน 3D simulation, podcast generation, printed exam และ phone-to-desktop handoff จนวงจร import-to-practice หลักเสถียร
- ไม่เพิ่มหลายวิชา, catalog วิชา, โรงเรียน หรือข้อสอบระดับชาติ
- ไม่ใช้ readiness/predicted exam score ที่ไม่มีโมเดล calibration เปิดเผย
- ไม่คัดลอก brand assets, สี, illustration, copy หรือหน้าจอ Astra แบบ pixel-for-pixel
- ไม่เพิ่ม `f45`; งานทั้งหมดต้องแมปเข้า 8/44 เดิมและผ่าน feature registry/entitlement ที่เกี่ยวข้อง

## 10. ข้อสรุปสำหรับการตัดสินใจ

งานที่ให้ผลต่อผู้ใช้สูงสุดและใช้โค้ดเดิมมากที่สุดคือ **นำเข้าเนื้อหาภาษาอังกฤษ → ตรวจแก้คำ/วลี → ยืนยัน → ฝึกหลายรูปแบบ → ซ่อมจุดอ่อน**. เริ่มจาก Card A ด้วย dependency ที่ติดตั้งแล้ว จากนั้นเพิ่ม `.txt/.md` และ Socratic mode ก่อน PDF/OCR. แนวทางนี้นำแก่นของ Astra มาใช้จริงโดยไม่สร้าง learning, SRS, mastery, reward หรือ AI provider authority ชุดใหม่
