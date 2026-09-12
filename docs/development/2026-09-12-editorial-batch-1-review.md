# Editorial batch 1 — ตรวจทาน 2026-09-12

- Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`
- Branch: `codex/pair-matching-pm0-pm8`
- Input: `build/verification/cefr-editorial-20260912/input-1.json`
- Output: `assets/content/cefr_editorial/batch-1.json`
- ครบ 678 รายการ A1 จาก `a` ถึง `seventy`; เขียนความหมายหลัก ประโยคอังกฤษต้นฉบับ และคำแปลไทยทีละรายการ บันทึกเป็นชุด 100/100/100/100/100/100/78 รายการ
- สถานะ `ai-reviewed` หมายถึง AI เขียนและตรวจทาน ไม่ใช่การรับรองจากมนุษย์หรือการรับรองระดับ CEFR ของแต่ละความหมาย

## การอ่านตรวจรอบสอง

อ่านทุกแถวจากไฟล์ผลลัพธ์จริง โดยแบ่ง index 0–229, 230–459, 460–677 ตรวจความหมาย ชนิดคำ ความเป็นธรรมชาติของประโยค และคำแปล ไม่ใช้การผ่านโครงสร้างแทนการตรวจภาษา

แก้ไขหลังอ่านครบ:

- `aunt`: ระบุ younger sister เพื่อให้ตรงกับคำแปลน้า
- `believe`: ปรับเป็นประโยคเชื่อว่าพูดจริงที่มีบริบทชัดกว่า
- `bye`: อธิบายว่าเป็นสิทธิ์ผ่านรอบการแข่งขันกีฬา และเพิ่มบริบทการไม่ต้องเล่นรอบแรก
- `grandfather/grandma/grandmother/grandpa`: ความหมายต้นทางแต่ละรายการเป็น string เดียวที่มีเครื่องหมาย `/` ไม่ใช่หลาย index; แก้ `grandma/grandpa` เป็น index 0 และแสดงความหมายไทยทั้งสองสายญาติ ตัวอย่างระบุสายญาติอย่างชัดเจน
- `hat/mobile`: แปล left เป็นวางทิ้งไว้ ไม่เพิ่มข้อสรุปว่าลืมโดยไม่มีหลักฐาน
- `ideal`: เปลี่ยนเป็นความหมายแต่งอิสระ ไม่เชื่อม index ของคำว่า ดีเลิศ เข้ากับ sense ความเหมาะกับจุดประสงค์โดยตรง
- `later`: เก็บนัยว่าจะโทรอีกทีให้ครบ
- `seventy`: แก้ตัวอักษรผิดในคำแปลเป็น เจ็ดสิบ
- `its`: ตามข้อตกลง root เพิ่ม `partOfSpeechOverride: determiner` และ `sourceMeaningIndex: null`; ประโยคใช้ possessive determiner ตามไวยากรณ์สมัยใหม่ โดยไม่เปลี่ยน catalog เดิม

## การตัดสินใจที่ต้องรู้ในการรวมงาน

- 653 รายการเชื่อมความหมายต้นทาง; 25 รายการใช้ความหมายแต่งอิสระหรือ identity อิสระเพื่อแก้ POS (`its`) หลังแก้ cross-review
- POS override มีเพียง `its → determiner`
- เก็บ adverb จริงสำหรับ `about`, `above`, `before`, `behind`, `below`, `alone`, `along`, `each/all/any` แสดงสรรพนามตามบริบท; `no`, `much`, `lot` แสดงการขยายระดับ ไม่สลับเป็น determiner โดยเงียบ ๆ
- เก็บ noun จริงสำหรับ `call`, `catch`, `check`, `cook`, `cry`, `drive`, `feed`, `finish`, `hope`, `kick`, `kiss`, `look`, `move`, `paint`, `pay`, `play`, `purple`, `ride`, `run`, `saw`, `self` และ adjective สำหรับ `close`, `front`, `gold`, `key`, `only`, `orange`, `open`
- `mobile` เลือก noun โทรศัพท์มือถือแบบอังกฤษ โดยแต่ง gloss ใหม่; `e-mail` ไม่สืบทอดข้อจำกัด modem/สายโทรศัพท์เก่า; `gray`, `game`, `rice`, `never` เลือกความหมายใช้บ่อยที่ต้นทางไม่มีตรง ๆ
- ตัวอย่างสั้นไม่เกิน 12 คำทั้งหมด หลายคำหน้าที่ใช้ประโยคสองส่วนเพื่อให้ผู้เรียนเห็นตัวอ้างอิงชัดเจน ไม่ได้บังคับขั้นต่ำ 4 คำเมื่อประโยคสั้นเป็นธรรมชาติ

## แหล่งยืนยันกรณีเฉพาะ

- [American Heritage: bye](https://www.ahdictionary.com/word/search.html?q=bye), noun sense 2 ยืนยันการผ่านรอบโดยไม่มีคู่แข่ง; ประโยคแต่งใหม่ ไม่มีการคัดลอกตัวอย่าง
- [Merriam-Webster: dig](https://www.merriam-webster.com/dictionary/digging), noun sense 3 ยืนยันแหล่งขุดค้นโบราณคดี; ใช้การเยี่ยมชมสถานที่สมมุติ ไม่อ้างเหตุการณ์จริง
- Cambridge ปฏิเสธการเปิดด้วย 403 จึงเปลี่ยนไปแหล่งปฐมภูมิข้างต้น ไม่ retry ซ้ำโดยไม่มีการแก้ไข
- `bye` และ `dig` เป็นความหมายเฉพาะที่สอดคล้อง noun ใน inventory; ระดับ A1 มาจาก headword catalog ไม่ได้ยืนยันว่าความหมายกีฬาหรือโบราณคดีนั้นเป็น A1 โดยอิสระ ต้องสื่อข้อจำกัดนี้ในการรวมงาน

## หลักฐานตรวจโครงสร้าง

PowerShell อ่าน JSON input/output แล้วตรวจตามลำดับต้นทาง ผลหลังการแก้ไขสุดท้าย:

| ตรวจ | ผล |
| --- | --- |
| จำนวน input / output / unique IDs | 678 / 678 / 678 |
| ID ตรงทุกลำดับ | ผ่าน |
| sourceMeaningIndex ในขอบเขต | ผ่าน |
| headword token แบบ case-insensitive ในทุก example | ผ่าน |
| ตัวแรกอังกฤษเป็นตัวใหญ่และจบด้วย . ! ? | ผ่าน |
| meaning / translation / status / senseKey | ผ่าน |
| คำแปลไม่มีอักษรจีนหลงหรือ replacement character | ผ่าน |
| ประโยคซ้ำใน batch | 0 |
| ประโยคยาวเกิน 12 คำ | 0 |

SHA-256 ผลลัพธ์หลัง cross-review: `781581EAEE3DE66689359BA3768A1D42BBC1407539CA7D28313A075C836B2945`

SHA ก่อน cross-review (หลักฐานประวัติ): `60E0DC43D8BACEFC123B08C62E3DAD8A5494BC331A4D7FD59AA1B54BE11C6702`

## การแก้หลัง cross-review อิสระ

อ่าน `docs/development/2026-09-12-editorial-cross-review-1.md` ซึ่งตรวจครบ 678 รายการ แล้วเทียบ 4 ข้อเสนอกับ entry จริงและ source alternatives ของ peace ก่อนแก้:

- `set`: แปลว่า ทุกคืนฉันตั้งนาฬิกาปลุกให้ดังตอนหกโมง เพื่อแยกเวลาตั้งออกจากเวลาที่ปลุกดัง
- `grass`: ใช้ เช้านี้หญ้าเปียก ให้ตรงกับ present is wet
- `cool`: ใช้ อากาศยามเย็นเย็นสบาย ไม่ทำให้อากาศเป็นผู้รู้สึก
- `peace`: ใช้ ความสงบเงียบ และ null source identity ไม่ผูกกับความสงบเรียบร้อย/public order; ปรับคำแปลและ reviewNote ให้ตรงกัน

อ่านผลลัพธ์ JSON ของแต่ละ entry ทันทีหลังแก้ ตรวจซ้ำทั้งชุดว่าจำนวนและ unique IDs ยังเป็น 678, ID ตรง input ทุกลำดับ, index อยู่ในขอบเขต และทุกประโยคมี headword token: ผ่าน ไม่มีการเปลี่ยน ID/senseKey หรือประโยคอังกฤษทั้ง 678 ข้อ ผลเหล่านี้ยืนยันโครงสร้างบน SHA ใหม่ ส่วนคุณภาพภาษามาจากการอ่านของผู้เขียนและผู้ตรวจอิสระซึ่งยังเป็น AI ทั้งคู่

ไม่รัน Flutter, build, code generation หรือแก้ runtime/tests/shared catalog ตามขอบเขตงาน ไม่มี process ของงานนี้ค้างอยู่ ไฟล์เป็น untracked ใน worktree; ไม่ commit

## งานถัดไปและข้อจำกัด

Cross-review ภาษาและการจับคู่ source identity เสร็จและแก้ทั้ง 4 ข้อแล้ว หยุดเขียนเพื่อให้ root รวม parser/UI override และตรวจ integration บน snapshot ใหม่ งานชุดนี้ไม่ยืนยัน UAT, ประสิทธิผลการเรียน หรือการรับรองโดยผู้เชี่ยวชาญมนุษย์ ไม่พบประโยคที่ยังต้องรอเขียนในชุด 678 นี้
