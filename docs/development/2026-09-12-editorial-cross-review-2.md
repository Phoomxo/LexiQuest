# Cross-review batch 2 — 2026-09-12

ตรวจแบบ read-only ครบ **678/678** รายการจาก `assets/content/cefr_editorial/batch-2.json` เทียบ `build/verification/cefr-editorial-20260912/input-2.json` ใน worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest` ไม่ได้แก้ไฟล์เนื้อหาหรือ runtime

SHA-256 ก่อนและหลังตรวจตรงกัน: `B3F727DC279080BDCB92C18D9B6A6D71BB6A4C852F2558BD16D4C733FF678B43`

อ่านทุกประโยคอังกฤษ ความหมายไทย คำแปล ชนิดคำ และ gloss ที่ sourceMeaningIndex ชี้อยู่ ช่วงที่อ่านคือ 0–169, 170–339, 340–509, 510–594, 595–677; เปิดอ่านซ้ำแถว 422–429 และ 583–585 ที่ผลเครื่องมือตัดกลาง เพื่อให้ไม่มีแถวถูกข้าม ผลตรวจด้านภาษาแยกจากผลตรวจโครงสร้าง ไม่ใช่การรับรองโดยมนุษย์หรือการรับรอง CEFR ราย sense

## รายการแก้ไขที่แนะนำ: 7 IDs

ข้อ 1–5 เกี่ยวกับ identity/คำแปลที่มีความต่างชัดเจน ข้อ 6–7 เป็นการเลือกไม่เชื่อม identity อย่างระมัดระวังตามข้อกำหนดว่าต้องเทียบเท่าความหมายเดิม ไม่ใช่ข้อกล่าวหาว่าประโยคอังกฤษผิด

### 1. `cefrj15:student` — source identity กว้างกว่าต้นทาง

ต้นทางมีเพียง index 0 `นักศึกษา` แต่ผลลัพธ์ตั้งใจใช้ทั้งนักเรียนและนักศึกษา และแปลตัวอย่างเป็นนักเรียน ใช้ independent identity เพื่อไม่ยืนยันว่าขอบเขตเท่ากันทุกกรณี

```json
{
  "sourceMeaningIndex": null,
  "reviewNote": "Independent general-learner gloss includes school pupils as well as college students; source นักศึกษา is narrower."
}
```

### 2. `cefrj15:the` — คำแปลเพิ่มทิศทางเข้า

`Please close the door behind you.` ใช้ได้ทั้งตอนเข้าและออก แต่คำแปลเจาะจง `หลังจากเข้ามา` ปรับอังกฤษให้ชัดตรงคำแปลเดิม

```json
{
  "example": "Please close the door after you come in.",
  "reviewNote": "Definite article before door; incoming direction is explicit in both example and Thai translation."
}
```

### 3. `cefrj15:up` — เลือก source index สำหรับเส้นทาง

ต้นทาง index 0 คือ `ข้างบน`; index 1 คือ `ไปตาม` ประโยค `We walked up the hill.` กับ gloss `ขึ้นไปตาม` แสดงการเคลื่อนที่ไปตามทางลาด จึงเข้ากับ index 1 มากกว่า index 0

```json
{
  "sourceMeaningIndex": 1,
  "reviewNote": "Path preposition with hill as complement; maps to source index 1 ไปตาม, not positional ข้างบน."
}
```

### 4. `cefrj15:video` — อย่าสืบทอดข้อจำกัดเทป

ต้นทาง index 0 จำกัด `ภาพหรือหนังในเทปวิดีโอ`; index 1 คือ `ตลับเทปวิดีโอ` แต่ตัวอย่างและ gloss สมัยใหม่ไม่จำกัดสื่อ ควรใช้ identity อิสระ เช่นเดียวกับการปรับความหมาย e-mail ที่ล้าสมัยใน batch 1

```json
{
  "sourceMeaningIndex": null,
  "reviewNote": "Independent modern video-recording sense; source meanings restrict the content or object to videotape."
}
```

### 5. `cefrj15:chef` — พ่อครัวมืออาชีพไม่จำเป็นต้องเป็นหัวหน้า

ต้นทางมีเพียง `หัวหน้าพ่อครัว` แต่ gloss `พ่อครัวหรือแม่ครัวมืออาชีพ` ไม่กำหนดตำแหน่งหัวหน้า ตัวอย่างดีแล้ว เก็บ gloss ที่มีประโยชน์โดยไม่ผูก identity แคบกว่า

```json
{
  "sourceMeaningIndex": null,
  "reviewNote": "Independent professional-cook gloss does not require the head-cook position specified by the source."
}
```

### 6. `cefrj15:association` — สมาคมเป็นองค์กร ไม่ใช่ทุกกลุ่ม

ต้นทาง index 0 `กลุ่ม` กว้างมาก ส่วน `สมาคม` และ sports association ระบุองค์กรที่จัดตั้งขึ้น ไม่มี gloss องค์กร/สมาคมตรงในอีกสาม index แนะนำ independent identity เพื่อคงความแม่นยำของการนำเข้า

```json
{
  "sourceMeaningIndex": null,
  "reviewNote": "Independent organised-association sense; source กลุ่ม alone does not identify an association as an organisation."
}
```

### 7. `cefrj15:fancy` — ไม่ธรรมดาไม่เท่ากับหรูหรา

ต้นทางมีเพียง `ไม่ธรรมดา` ซึ่งไม่รับประกันนัยหรูหรา/ตกแต่งของ fancy clothes ตัวอย่างธรรมชาติและแปลตรงแล้ว แนะนำเก็บไว้เป็น gloss อิสระ

```json
{
  "sourceMeaningIndex": null,
  "reviewNote": "Independent elaborate-or-luxurious clothing sense; source ไม่ธรรมดา is too broad to assert exact equivalence."
}
```

## กรณีที่ตรวจแล้วไม่เสนอแก้

- `brainstorm`: เคยสงสัย noun ที่หมายถึง session เพราะ [Cambridge Dictionary](https://dictionary.cambridge.org/dictionary/english/brainstorm) เน้น noun ความคิดที่ผุดขึ้น แต่ [BBC Learning English: New words](https://downloads.bbc.co.uk/learningenglish/lowerintermediate/unit17/u17_6min_vocab_new_words.pdf), หน้า 3 และ 6 ยืนยันการใช้ brainstorm เป็นการรวมกลุ่มคิด จึงไม่ตีเป็นข้อผิดพลาด เนื้อหาได้ระบุ informal noun ใน reviewNote อยู่แล้ว
- noun `spell`, `stand`, `swim`, `throw`, `try`, `wash`, `being`, `bite`, `bloom`, `crisp`, `cross`, `dislike`, `express`, `fix`, `float` มีรูปประโยคและความหมายที่ใช้ได้ ไม่สลับ verb โดยเงียบ ๆ
- `some`, `which`, `whose`, `these`, `those` มีบริบทสรรพนามชัด; `across`, `ahead`, `apart`, `deep`, `downstairs`, `downtown`, `enough` แสดง adverb ได้
- ตัวอย่างจำนวนมากเป็นเหตุการณ์สมมุติทั่วไป ไม่ได้อ้างราคาจริง เหตุการณ์ประวัติศาสตร์จริง หรือผลวิจัยจริง จึงไม่ต้องเพิ่มการค้นเว็บโดยไม่มีเหตุจำเป็น
- ไม่พบการจำเป็นต้องเพิ่ม `partOfSpeechOverride` ใหม่ใน batch นี้ การติดป้าย yes เป็น adverb อยู่ในแนวพจนานุกรมดั้งเดิมและไม่ทำให้รูปประโยคตัวอย่างผิด

## หลักฐานและสถานะส่งต่อ

ตรวจ JSON ซ้ำ: 678 output / 678 input / 678 unique IDs, ID ตรงตามลำดับ, source indices ทุกตัวอยู่ในขอบเขต, SHA คงเดิม ผลเหล่านี้ยืนยันโครงสร้างเท่านั้น ไม่แทนผลตรวจภาษาและ semantic mapping ข้างต้น

ขั้นถัดไป: root ส่ง 7 IDs ให้ผู้เขียน batch 2 พิจารณาและแก้ตามขอบเขต จากนั้นตรวจ replacement fields บน SHA ใหม่ ไม่มีการแก้เนื้อหาจากผู้ตรวจ ไม่มี process ค้าง และไม่มี Flutter/build/test ระดับแอปถูกเรียกในงานตรวจนี้
