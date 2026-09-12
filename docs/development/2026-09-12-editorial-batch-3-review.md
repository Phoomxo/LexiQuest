# CEFR editorial batch 3 — ตรวจบรรณาธิการโดย AI

วันที่ 2026-09-12; worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`.

ส่งมอบ `assets/content/cefr_editorial/batch-3.json` ครบ 678 รายการ A2 จาก `frighten` ถึง `zone` ตาม input-3.json ทุก ID เรียงตามต้นฉบับ ใช้ senseKey `primary-v1` และ status `ai-reviewed` ทั้งหมด ไม่ใช่การรับรองจากมนุษย์หรือการรับรองระดับ CEFR ของประโยค

## วิธีตรวจเนื้อหา

- อ่านคำ ชนิดคำ และความหมายเดิมครบทุกแถวก่อนแต่ง แบ่งงานเป็น 8 ชุด ชุดละ 80 แถว และชุดสุดท้าย 38 แถว บันทึก scratch ใน `build/verification/cefr-editorial-20260912/agent-3/part-1.tsv` ถึง `part-9.tsv`.
- แต่งประโยคอังกฤษและคำแปลไทยแต่ละรายการโดยตรง ไม่ใช้ตัวสร้างประโยคจากแม่แบบและไม่เรียก paid API.
- อ่านรอบสองครบ 678 รายการจาก scratch ตรวจความเป็นธรรมชาติ ไวยากรณ์ ชนิดคำ ความหมาย คำแปลไทย และตัวสะกดเป้าหมาย ก่อนแปลงเป็น JSON ด้วยข้อมูลที่ตรวจแล้ว
- รอบสองแก้คำแปล grandchild ให้เป็นไทยธรรมชาติ; แก้ pence เป็นห้าสิบเพนนี; แก้ collocation `tells a romance` เป็น `is a romance`; แก้คำแปล superstar; ปรับ tights; เปลี่ยน off ให้ชัดว่าเป็น adverbial particle และ sightseeing ให้เป็นคำนามประธาน; ปรับ unlike ให้เป็น predicative adjective ที่มีบริบทชัด
- ตรวจ sourceMeaningIndex เทียบรายการความหมายเดิม หลัง cross-review เลือก 634 รายการที่เทียบเคียงได้ และ 44 รายการใช้ null เพราะต้องนิยามใหม่ ไม่มี POS override

## การตัดสินใจสำคัญ

- `frightened` หมายถึงรู้สึกกลัว ไม่ใช่น่าตกใจ; `frighten` ต้องเป็นการทำให้กลัว
- `globe` ใช้ลูกโลก; `grace` ใช้ความสง่างาม; `greedy` ใช้โลภ; `however` ใช้อย่างไรก็ตาม; `instant` ใช้ผลที่เกิดขึ้นทันที ทั้งหมดแยก identity จาก gloss เดิมที่ไม่ตรง
- `mug` เป็นแก้วมีหู ไม่ใช่เหยือก; `pea` เป็นถั่วลันเตา; `pepper` ในประโยคเป็นเครื่องปรุง; `lemon`/`lemonade` ระบุเลมอนให้ต่างจากมะนาวไทย
- `pilgrim` มีวัตถุประสงค์แสวงบุญ; `planet` เป็นดาวเคราะห์; `symphony` เป็นบทประพันธ์ ไม่ใช่ตัววง; `thunderstorm` เป็นพายุฝนฟ้าคะนอง; `tights` เป็นถุงน่องยาวถึงเอว
- `vocabulary` ใช้คลังคำที่รู้หรือใช้; `wallet` เป็นกระเป๋าสตางค์; `website` เป็นเว็บไซต์ ไม่ใช่เพียงที่อยู่; `wedding` เป็นงานแต่งงาน
- noun ที่อาจสับสนกับ verb: `knock`, `mention`, `pass`, `release`, `return`, `search`, `shot`, `spread`, `writing`; adjective ที่อาจสับสนกับ noun/adverb: `kindly`, `lyric`, `net`, `principal`, `split`, `terrorist`, `uniform`; จัดประโยคตามชนิดคำจริงทั้งหมด
- `nation` เลือก index 1 เพราะประโยคกล่าวถึงคนทั้งประเทศ; `loose` index 13; `lost` index 6; `passage` index 5; `range` index 5; `shot` index 7; `unit` index 4; `writing` index 3
- รักษารูปสะกด catalog เช่น `gramme`, `metre`, `traveller`, `make-up`, `right-hand`, `well-known` และตัวใหญ่ `Olympic`.

## ข้อสังเกตด้านทะเบียนภาษา

`handicapped` เป็นคำเก่าที่อาจไม่สุภาพ จึงวางในบริบทป้ายเก่าและแจ้งใน gloss/reviewNote. `pacific` (รักสงบ) เป็น adjective ที่เป็นทางการและไม่ค่อยพบบ่อย ไม่ใช่ชื่อมหาสมุทร. `lyric` adjective, `weep` noun (`a quiet weep`), `unlike` adjective และ `such` pronoun (`and such`) เป็นการใช้จริงแต่มีข้อจำกัดด้านทะเบียนภาษา ระบุไว้ให้ผู้ตรวจข้ามชุดพิจารณา ไม่ได้อ้างการค้นแหล่งภายนอกหรือการยืนยันโดยผู้เชี่ยวชาญมนุษย์

ตัวอย่างเกี่ยวกับกฎหมาย การแพทย์ สงคราม อาชญากรรม และเหตุการณ์สาธารณะใช้บริบททั่วไปหรือเรื่องแต่ง ไม่มีคำแนะนำเฉพาะทางหรือข้ออ้างเหตุการณ์ปัจจุบัน

## หลักฐานตรวจเชิงโครงสร้าง

รัน Python โดย import `validate` จาก `tools/validate_cefr_editorial.py` เทียบ input-3 กับ batch-3 ใน worktree นี้:

```json
{"coverage":678,"levels":{"A2":678},"sourceLinked":634,"independentSenses":44,"posOverrides":[],"duplicateExampleTexts":[],"warnings":[],"languageQualityCertifiedByThisCheck":false}
```

ตรวจเพิ่มเติม: 678 unique IDs, 678 unique examples, exact headword token ครบ (ไม่แยกตัวใหญ่เล็ก), ไม่มี source index เกินขอบเขต, ไม่มีช่องข้อความว่าง, ทุกประโยคขึ้นต้นตัวใหญ่, ไม่มีอักษรละตินหลงในคำแปลไทย ประโยคยาว 7–11 คำตาม whitespace split. `git diff --check -- assets/content/cefr_editorial/batch-3.json` ไม่รายงาน whitespace error (asset ใหม่เป็น untracked จึงใช้ content validator เป็นหลัก).

SHA-256 asset หลัง cross-review: `d85708ae5ea49306fe31dc5e3e5c7ab3a4a9ffafcf5996f4e12415f80db41435`.

## แก้ไขหลัง cross-review และ freeze รอบสุดท้าย

อ่าน `docs/development/2026-09-12-editorial-cross-review-3.md` และตรวจแถวปัจจุบันทั้งหกกับข้อเสนอแล้ว รับการแก้ไขทั้งหมด: furniture แปลทิศทางว่าให้ห่างจากหน้าต่าง; mall เปลี่ยนเป็น null เพื่อแยกศูนย์การค้าจากห้างสรรพสินค้า; sunflower ใช้ดอกไม้ในแจกันให้ตรง source sense; hey/somebody/sunglasses แปล left ว่าวางทิ้งไว้โดยไม่อนุมานว่าลืม

อ่านแถวที่แก้ซ้ำและรัน validator เดิมผ่านครบ 678 รายการ ไม่มี warning หรือประโยคซ้ำ ไม่แก้ข้อมูลส่วนอื่นและไม่ใช้ POS override. Scratch TSV เป็นหลักฐานรอบแรกเท่านั้น ห้ามนำมาแปลงทับ asset หลัง cross-review. ฉบับ JSON ตาม hash ข้างบนคือฉบับ freeze ล่าสุดสำหรับ root นำไปตรวจ integration.

ไม่รัน Flutter/build หรือแก้ runtime/test/shared catalog. ไม่มี process ที่ยังทำงานจากงานย่อยนี้ ไม่มีปัญหาเชิงโครงสร้างค้าง ขั้นต่อไปคือ root จัด cross-review เนื้อหาและตรวจ integration บน source ปัจจุบัน; การผ่านตัวตรวจโครงสร้างไม่ใช่หลักฐานคุณภาพภาษาโดยตัวมันเอง
