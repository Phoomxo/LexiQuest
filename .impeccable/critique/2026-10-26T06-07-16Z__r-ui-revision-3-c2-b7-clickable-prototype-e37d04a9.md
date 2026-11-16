---
target: Figma Cloud รุ่นล่าสุดของ LexiQuest
total_score: 30
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 4
target_identity: "url:https://www.figma.com/design/o9e5GYmA1gdrLC9Csxil6w/LexiQuest-%C2%B7-Master-UI-Revision-3-%C2%B7-Clickable-Prototype"
timestamp: 2026-10-26T06-07-16Z
slug: r-ui-revision-3-c2-b7-clickable-prototype-e37d04a9
---
Method: design review only (detector not applicable, native Android)

# `/critique` — LexiQuest Figma Cloud as current design authority

## Design Health Score

Flutter final9 ที่มี source, golden และ regression evidence ยังรักษาผล 40/40
เฉพาะ flow ที่ตรวจแล้ว แต่ Figma Cloud ในฐานะ handoff authority ล่าสุดได้
**30/40 — Good** และยังเรียกว่า current whole-file ไม่ได้

| # | Heuristic | Score | Key issue |
| ---: | --- | ---: | --- |
| 1 | Visibility of System Status | 3/4 | Login มี error, loading และ Snackbar ชัด แต่สถานะรุ่นปัจจุบันกระจายระหว่าง R11, LQ15 และ draft |
| 2 | Match System / Real World | 4/4 | final9 ใช้ภาษาไทยทั่วไปและลำดับงานที่ผู้เรียนเข้าใจได้ |
| 3 | User Control and Freedom | 3/4 | Login มี Cancel/Back/recovery แต่ extracted states ยังไม่มี reaction-map ยืนยันทุกทางออก |
| 4 | Consistency and Standards | 2/4 | Runtime final9 กับ Figma R11 final8 ไม่ตรงกันหลาย flow |
| 5 | Error Prevention | 3/4 | Runtime form/dialog guards ดี แต่ Figma ยังไม่เก็บ state เหล่านั้นครบ |
| 6 | Recognition Rather Than Recall | 3/4 | ผู้เรียนเห็นงานชัด แต่ทีมต้องจำเองว่า source, R11 หรือ LQ15 ตัวใดล่าสุด |
| 7 | Flexibility and Efficiency | 2/4 | Native frames ใหม่มีเฉพาะ 412x917 และไม่มี adaptive handoff ที่พิสูจน์แล้ว |
| 8 | Aesthetic and Minimalist Design | 3/4 | Login v15 สงบและมี CTA หลักเดียว แต่ Page 1 มี revision และ draft ปะปน |
| 9 | Error Recovery | 4/4 | Login v15 และ final9 recovery รักษาบริบทและข้อมูลที่กรอก |
| 10 | Help and Documentation | 3/4 | Repository design docs ละเอียด แต่ contextual help ในทุก flow ยังไม่ถูกตรวจครบ |
| **Total** |  | **30/40** | **Good — ปิด P1 ก่อนเรียก Figma รุ่นล่าสุดทั้งไฟล์** |

## Design Specificity Verdict

LexiQuest มีภาษาภาพเฉพาะตัวแล้ว: LQ route mark, Calm Journey, งานถัดไปหนึ่งอย่าง,
ภาษาไทยแบบ evidence-led และการแยก mastery ออกจาก reward. งานไม่ใช่ Material
template ทั่วไป จุดอ่อนคือ authority ยังแตกเป็นสี่ชุด: R11 final8, Flutter final9,
Login v15 และ R12 draft ที่โควตาตัดกลางทาง

Deterministic scan: not applicable (native Android). ไม่มี browser overlay เพราะ
เป้าหมายเป็น native design/runtime; ใช้ Flutter goldens, signed Vivo captures และ
read-only Figma inspection แทน

## Overall Impression

หน้าที่ผ่าน final9 มี hierarchy, plain Thai, validation และ recovery ดีพอสำหรับ
engineering ต่อ แต่ design handoff ยังไม่ใช่ source of truth เดียว ความเสี่ยงใหญ่สุด
ไม่ใช่ความสวยของ Login แต่คือทีมอาจหยิบ R11 เก่าไปพัฒนาและย้อนการแก้ final9

## What's Working

- Login v15 มี CTA หลักเดียว, provider error อยู่ในบริบท, reset ไม่ปิดเมื่อ input
  ผิด และมี Guest/Google/Register ที่เข้าใจง่าย
- Golden ของ Learning Hub, Quiz feedback, Score และ Weakness ที่ 200% text
  รักษาลำดับข้อมูลและ recovery ต่อไปยังคำที่ควรฝึก
- Source final9 ปิดศัพท์เทคนิคสำหรับผู้เรียน, ใช้ live regions และ standard
  Material navigation/bar/rail ตามขนาดหน้าจอ

## Priority Issues

### [P1] ไม่มี canonical Figma รุ่นปัจจุบันทั้งระบบ

R11 node `81:2` ยังเป็น final8 ขณะที่ source final9 เปลี่ยน Vocabulary, CEFR,
Quiz, Score, Weakness, shell/copy, Registration, Email verification, Password,
Category, Add/Edit Word และ Import row แล้ว

Fix: สร้าง `CURRENT · R12` ที่ผูก source commit, ทำ source-to-Figma checklist
ครบทุก delta และห้ามติดป้าย COMPLETE จน checklist ผ่าน

Suggested command: `$impeccable document` แล้ว `$impeccable polish`

### [P1] Adaptive native design matrix ยังไม่ครบ

Login Code Layer เคยตรวจเชิงเว็บหลายความกว้าง แต่ editable frames มีเพียง
412x917; ยังไม่มี native evidence สำหรับ tablet, expanded, landscape,
split-screen หรือ hinge exclusion

Fix: ตรวจ 320x720, 360x800, 412x915, 800x360, 600x960, 840x1200,
1280x800 และ 540x720 split-screen ทั้ง light/dark, 100/200% text และ IME-open

Suggested command: `$impeccable adapt`

### [P1] Prototype wiring ของ delta ใหม่ยังไม่ผ่าน end-to-end

R11 route count เป็น historical count; Login native frames เป็น captured states
แต่ยังไม่มี validator ยืนยัน reaction map, dead ends และ duplicate routes

Fix: วัดจริง Login/Google/Reset/Guest/Register, Learn-to-Weakness และ
Library-to-Import flows; reaction sources ต้องตรง route count และ dead/broken/
duplicate route ต้องเป็นศูนย์

Suggested command: `$impeccable harden`

### [P1] Accessibility ยังไม่มี human/native sign-off

ARIA, widget semantics และ TalkBack service/focus smoke ไม่เท่ากับการฟังเสียง
อ่านจริง โดยเฉพาะ modal focus, live-region timing, Snackbar, predictive Back,
IME และ 200% text ใน state เดียวกัน

Fix: manual TalkBack/UAT บน compact phone และ tablet/Fold พร้อม expected/
observed/pass-fail ที่ผูก build/device/timestamp

Suggested command: `$impeccable audit`

### [P2] Copy/state เก่ายังค้างใน R11

Terms/Privacy บน Login, controlled-rollout/provider metadata และจังหวะ Settings/
AI Tutor บางส่วนยังไม่ตรง final9 runtime

Fix: ทำ learner copy ให้ตรง source และย้าย system metadata ใต้รายละเอียดเพิ่มเติม

Suggested command: `$impeccable clarify`

### [P2] โครงสร้าง Figma ยังทำให้ handoff สับสน

แม้ draft ถูกติดป้าย INCOMPLETE แล้ว แต่ R5/R6/R11/LQ15/draft ยังอยู่ Page 1
ร่วมกันโดยไม่มี current root เดียว

Fix: เก็บ legacy ใต้ `Archive / Do not implement`; current root ต้องมี README
frame ระบุ commit, matrix, known gaps และ counts ที่ validator วัดจริง

Suggested command: `$impeccable distill`

## Cognitive Load

End-user Login/final9 flow มี cognitive-load ต่ำ: single focus, grouping,
hierarchy, one-thing-at-a-time และ progressive disclosure ผ่าน

Design handoff มี cognitive-load ปานกลาง โดยไม่ผ่าน 3 ข้อ:

- Chunking: revision หลายชุดอยู่ Page เดียว
- Minimal choices: ต้องเลือก R11, LQ15 หรือ draft
- Working memory: ต้องจำเองว่า state/copy ใดอยู่ใน source หรือ Figma

## Emotional Journey

Login ลดความกังวลได้ดีเพราะมี Guest, Google, reset และ error recovery โดยไม่
พาออกจากบริบท จุดตกต่ำเกิดหลัง Login เมื่อ Figma ไม่สามารถยืนยันอารมณ์ต่อเนื่อง
ของ Hub → Practice → Feedback → Repair จาก final9 ได้ทั้งเส้นทาง

## Persona Red Flags

- **Jordan — ผู้ใช้ครั้งแรก:** Login ชัด แต่ flow หลัง Login ใน Figma อาจยังใช้
  ชื่อและลำดับ final8 เมื่อทีมพัฒนาอ้างไฟล์ผิดชุด
- **Sam — ผู้ใช้ TalkBack/สายตาเลือนราง:** มี 200% portrait และ semantics smoke
  แต่ยังไม่มี spoken order, modal focus และ tablet/Fold native proof
- **Casey — ผู้ใช้มือถือมือเดียว:** Vivo portrait ใช้ได้ แต่ landscape,
  compact-height, IME และข้อความไทยยาวยังไม่มีหลักฐานจาก signed +15

## Minor Observations

- R12 atlas node `112:1819` ถูกติดป้าย draft ถูกต้องแล้ว แต่ partial changes ไม่ใช่
  evidence และไม่ควรนำไป extract
- Responsive matrix เดิมมีภาพ blank 4 ขนาดและใช้ artifact hash คนละชุดกับ +15
- Raw evidence บางส่วนอยู่นอก worktree และ CSV บางแถวมี mojibake
- final-gate message ยังมี placeholder `{0}` เป็น cosmetic defect

## Questions to Consider

- ควรให้ canonical authority เป็น Flutter source แล้ว generate Figma delta หรือให้
  Figma เป็น approval gate ที่ต้องซิงก์ก่อนทุก release?
- Tablet/Fold เป็น release target รอบนี้จริง หรือควรระบุเป็น preview support จนมี
  hardware evidence?
- Help ที่สำคัญกว่าคือ contextual help สำหรับผู้เรียน หรือ README/handoff สำหรับทีม?
