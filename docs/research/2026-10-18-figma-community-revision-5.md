# Figma Community และแนวทางเลย์เอาต์สำหรับ LexiQuest Revision 5

วันที่สังเคราะห์: 2026-10-18
ขอบเขต: mobile learning, flashcards, quiz, AI tutor, results/progress และ Android adaptive layout

เอกสารนี้ใช้แหล่ง Figma Community เพื่อสำรวจรูปแบบหน้าจอและความครอบคลุมของ state และใช้ผลิตภัณฑ์จริงกับ Android guidance เพื่อกำหนดลำดับงาน ไม่ได้อนุญาตให้คัดลอกทรัพย์สินของแหล่งอ้างอิง

## แหล่งอ้างอิงที่คัดเลือก

| # | แหล่ง | รูปแบบที่นำมาปรับใช้ | สิ่งที่ต้องหลีกเลี่ยง |
| --- | --- | --- | --- |
| 1 | [Learn-Up V2: Free Language Learning Mobile App UI Kit](https://www.figma.com/community/file/1553387914458677624/e-learning-free-language-learning-mobile-app-ui-kit) | ลำดับ onboarding → home/recommendation → lesson → progress และ component ที่ปรับข้อความได้ | course marketplace, thumbnail และ paid CTA ที่แย่งภารกิจถัดไป |
| 2 | [Coursezy: Course, Quiz and Flashcard UI Kit](https://www.figma.com/community/file/1502006485635837743/coursezy-online-course-quiz-educational-mobile-app-ui-kit-elearning-course-quiz-game-app-ui) | ใช้เป็นรายการตรวจ state: quiz, flashcard, quiz end, badge, profile, notification และ settings | friends, scoreboard, badge และ conversion UI หลายชั้นในเส้นทางหลัก |
| 3 | [Aptis Practice UI](https://www.figma.com/community/file/1622808499508850540/aptis-e-learning-exam-practice-platform-ui-aptis-practice) | เลย์เอาต์ตามงานจริง เช่น timer+question, audio+transcript, matching และ reference pane | ย่อ desktop exam workspace ทั้งหมดลงมือถือ หรือใส่หลาย pane บนจอ compact |
| 4 | [Minimalist Daily Vocab UI](https://www.figma.com/community/file/1538065073596668567/minimalist-black-white-daily-vocab-memorization-mobile-ui-3p) | หนึ่งคำเป็นจุดเด่น มี progress และ metadata รองที่กระชับ | monochrome ล้วนและ tag จำนวนมาก เพราะสถานะ selected, mastery, momentum และ error ต้องแยกได้ |
| 5 | [AI Study Helper App UI Kit](https://www.figma.com/community/file/1589839137281023834/ai-study-helper-app-ui-kit) | subject/context → question → structured response → progress | หน้า generic chat ที่ไม่บอกแหล่งข้อมูล หรือยก scan/solve เป็นหน้าหลัก |
| 6 | [Skillforge: AI Online Course Mobile UI Kit](https://www.figma.com/community/file/1573012688699108154/skillforge-ai-online-course-mobile-app-ui-kit) | inventory สำหรับ AI recommendation, tutor, quiz, adaptive path, progress และ empty/error | feature sprawl, certificate, subscription และ catalog ที่ทำให้ AI กลายเป็นศูนย์กลางผลิตภัณฑ์ |
| 7 | [AllTCAS](https://alltcas.com/download/) · [Google Play](https://play.google.com/store/apps/details?id=com.alllearn.alltcas) | โครงที่ผู้ใช้ไทยคุ้น: เลือกวิชา/ชุด → ทำทีละข้อ → action ด้านล่าง → เฉลย → คะแนนและจุดที่พลาด | คัดลอกข้อสอบ แบรนด์ โปรโมชั่น หรือ social/PvP ที่ไม่เกี่ยวกับ learning authority |
| 8 | [Astra AI ภาษาไทย](https://astra-ai.co/th/) | เริ่มจากเอกสาร วันสอบ และเป้าหมาย แล้วสร้างแผนทีละขั้น; tutor แสดง context ก่อนตอบ | feature parade, hero แบบหน้าโฆษณา คำรับประกันผล และคำตอบ AI ที่ไม่มี provenance |
| 9 | [Duolingo: The Science Behind the Home Screen Redesign](https://blog.duolingo.com/new-duolingo-home-screen-design/) | current node + Resume และการแทรก review ในเส้นทางเพื่อให้การทบทวนยังรู้สึกว่าเดินหน้า | long-scroll path เป็น navigation ทั้งหมด หรือ reward/quest ที่บังคับก่อนกลับไปเรียน |
| 10 | [Quizlet Study Modes](https://quizlet.com/gb/features/study-modes) · [Quizlet Flashcards](https://quizlet.com/en/features/flashcards) | set → mode → card/question → Know/Still learning หรือ feedback → review missed | gesture-only, ซ่อน progress และเปลี่ยน mode ระหว่างทำโจทย์ |
| 11 | [Khan Academy: Mastery Progress Visualization](https://support.khanacademy.org/hc/en-us/articles/18735142028045-Update-New-mastery-progress-visualization-on-Course-and-Unit-pages) | ภาพรวมระดับทักษะที่กดดูรายละเอียดได้ และผลลัพธ์ที่ชี้ว่าควรทำอะไรต่อ | dashboard ที่มี KPI มากกว่าคำแนะนำ หรือรวมเวลาเรียน แต้ม streak และ mastery เป็นค่าเดียว |
| 12 | [Android Canonical Layouts](https://developer.android.com/develop/adaptive-apps/guides/canonical-layouts) | compact เป็น single pane; expanded ใช้ list-detail/supporting pane; เปลี่ยน NavigationBar เป็น NavigationRail ตามพื้นที่ | ยืด phone UI ให้กว้าง แสดงสอง pane บนจอแคบ หรือวางเนื้อหาทับ hinge |

## กฎเลย์เอาต์ Revision 5

1. **ใช้ AllTCAS เป็นโครงหน้าทำงาน** — หน้าฝึกเรียง progress → prompt → choice → fixed submit → saved feedback มีหนึ่งโจทย์และหนึ่ง primary action ต่อ viewport
2. **Home ตอบว่า “ทำอะไรต่อ” ก่อนแรงจูงใจ** — next action 32–36%, route/evidence 28–34%, optional modes 16–20% และ navigation 12–14%; streak, badge และ reward ใช้พื้นที่รวมไม่เกิน 10–15%
3. **AI เป็นชั้นเสริมที่ตรวจสอบที่มาได้** — เรียง context source → learner question → structured answer → provenance/verify action → composer และทุกคำตอบต้องมีทางกลับเข้าการฝึก
4. **Practice กับ Progress ใช้วงจรเดียวกัน** — ผลลัพธ์เรียงสถานะปัจจุบัน → หลักฐาน/คำที่พลาด → next action; แสดง KPI หลักไม่เกิน 3 และแยก mastery, speed, streak และ reward
5. **Thai-first และ adaptive** — มือถือใช้ margin 20dp, section gap 24–32dp, headline ใหญ่หนึ่งจุด และบรรทัดไทยประมาณ 32–38 ตัวอักษร; จอใหญ่เปลี่ยน composition เป็น list-detail/supporting pane แทนการขยายการ์ดเดิม

## Canonical Android frame

### Canonical device: Vivo V2041 — 393×876dp

ใช้เป็นเฟรมหลักของ Revision 5 จากอุปกรณ์จริง `1080×2408px @440dpi` (`density=2.75`) ซึ่งแปลงได้ประมาณ `393×876dp` พื้นที่แอปที่สังเกตได้ปัจจุบันอยู่ที่ประมาณ `393×809dp`; ค่า `WindowInsets` ขณะรันเป็นแหล่งอ้างอิงสุดท้าย:

- กริด 4dp, margin ซ้าย/ขวา 20dp และความกว้างเนื้อหา 353dp
- ไม่กำหนดตำแหน่ง `y` จากกรอบเครื่อง ให้ใช้ system bar/gesture insets จริง แล้วจัด app bar สูง 64dp ภายใน app area
- หน้า shell แบ่ง app area เป็น app bar 64dp, body ที่ยืดหยุ่น และ NavigationBar 80dp
- หน้าฝึกแบบ focused แบ่งเป็น app bar 64dp, body ที่ยืดหยุ่น และ fixed action สูงไม่เกิน 96dp เหนือ bottom inset
- ปุ่มหลักสูง 52dp, control และ touch target อย่างน้อย 48×48dp
- ใช้ single pane เท่านั้น; feedback ต้องไม่บัง prompt และ fixed action ต้องไม่ซ้อน navigation/system inset
- รองรับชื่อหน้า 2 บรรทัด ข้อความไทยยาว และ system text scaling โดยไม่กำหนดความสูงของ content card แบบตายตัว

### ขนาดตรวจรับ

| ขนาด | รูปแบบที่คาดหวัง | Checks ที่ต้องผ่าน |
| --- | --- | --- |
| **360×800dp** | compact lower-bound check; single pane และลด margin เป็น 16dp ได้เมื่อจำเป็น | ไม่มี horizontal scroll/ข้อความถูกตัด; title ไม่ชน action; touch target ≥48dp; fixed CTA อยู่เหนือ inset; navigation label อ่านครบ |
| **393×876dp** | canonical Vivo V2041; app area ปัจจุบันประมาณ 393×809dp | Home เห็น Resume ในครึ่งบน; Quiz เห็น prompt, choice และ CTA; AI เห็น context/provenance/composer; primary action หนึ่งจุด; ไม่มีองค์ประกอบชน runtime insets |
| **412×915dp** | compact upper-bound check เท่านั้น; ต้องขยายพื้นที่ว่างตาม constraint ไม่ใช่เปลี่ยน hierarchy | สัดส่วนและลำดับอ่านตรงกับ canonical; card ไม่ยืดโดยไม่มีเหตุผล; fixed action/nav ยังยึด safe area; ไม่มีพื้นที่ว่างก้อนใหญ่ |
| **600×960dp / 800×1280dp** | small-tablet checks ใน Medium width class: NavigationRail และ centered single/focused column; ยังไม่บังคับสอง pane | ไม่ยืด card เต็มพื้นที่; ลำดับอ่านเหมือนมือถือ; state คงอยู่เมื่อ rotate |
| **1024×1366dp** | medium-tablet fixture ใน Expanded width class: NavigationRail + conditional list-detail เมื่อ pane minima ผ่าน | list ≥320dp, detail ≥480dp; selection ตรงกับ detail; ไม่มี Back ซ้ำ |
| **1280×800dp** | Large landscape: NavigationRail + list-detail/supporting pane อัตราประมาณ 42:58, gutter 24dp และ content รวมไม่เกิน 1200dp | selection ใน list ตรงกับ detail; detail ไม่มี back arrow ซ้ำ; primary action อยู่กับ pane ที่เป็นเจ้าของ; pane ไม่ชน navigation หรือ system inset |

## ข้อจำกัดด้านลิขสิทธิ์และหลักฐาน

- ไฟล์ Figma Community แต่ละรายการมีเจ้าของและเงื่อนไขสิทธิ์ของตนเอง ต้องตรวจ license ในหน้าต้นทางก่อน duplicate, export หรือใช้ asset ใดในผลิตภัณฑ์
- อนุญาตให้ศึกษาเฉพาะ information hierarchy, สัดส่วน, state coverage และ interaction pattern ห้ามคัดลอกภาพประกอบ โลโก้ ไอคอนเฉพาะ ข้อความ แบรนด์ ชุดสี หรือหน้าจอทั้งชุด
- คำอธิบายจากผู้สร้าง UI kit เป็นข้อกล่าวอ้างของผู้สร้าง ไม่ใช่ผลทดสอบ usability, accessibility หรือ production readiness
- หน้าเว็บผลิตภัณฑ์และ store listing แสดง public/marketing surface อาจไม่ตรงกับทุกบัญชี entitlement, A/B test หรือ runtime ปัจจุบัน และไม่ใช่หลักฐานของ backend หรือสูตร AI
- Android canonical layouts เป็นแนวทางโครงสร้าง ไม่รับประกันว่าเลย์เอาต์ผ่านเมื่อใช้ข้อความไทยหรือ text scaling; ต้องตรวจด้วยภาพ render และ prototype จริงทุกขนาดด้านบน
- การนำ pattern มาใช้ต้องรักษา LexiQuest local-first, แยก mastery/momentum/reward/research และไม่อ้างประสิทธิผลทางการเรียนโดยไม่มีหลักฐาน
