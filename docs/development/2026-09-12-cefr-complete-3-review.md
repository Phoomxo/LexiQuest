# CEFR complete batch 3 — editorial review

วันที่ 2026-09-12; worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch `codex/pair-matching-pm0-pm8`.

## ขอบเขตและสถานะ

เขียน primary ใหม่ครบ 1,155 รายการใน `assets/content/cefr_editorial/complete-3.json` และตรวจ source senses ครบ 1,833 IDs ใน `assets/content/cefr_editorial/sense-review-3.json` จาก input-3.json ทั้งชุด ไม่มีการแก้ source catalog หรือ batches เดิม สถานะเป็น `ai-reviewed` ไม่ใช่การรับรองโดยมนุษย์หรือหลักฐานประสิทธิผลการเรียนรู้

เจ้าของอ่านทวนรอบสองครบทุกแถว 0–1832 รวม primary ใหม่ 1,155 และ existingEditorial เก่า 678 รายการ โดยอ่าน Thai meaning, English example, Thai translation, POS/override และ source mapping ประกอบ source meanings ทุกดัชนี เก็บการตัดสินใจและต้นฉบับประโยคที่แต่งรายคำเป็น 32 ชุด TSV ใน scratch `build/verification/cefr-complete-20260912/three/` การประกอบ JSON ใช้ข้อมูลที่แต่งไว้เท่านั้น ไม่ใช้แม่แบบสร้างตัวอย่างจำนวนมากหรือ paid API

สถานะปัจจุบัน: author + owner reread เสร็จ; root อ่าน cross-review primary ใหม่ครบ 1,155 และเจ้าของรับแก้ข้อเสนอครบแล้ว Final content frozen ตาม SHA ด้านล่าง รอ root ตรวจ final diff/บูรณาการ ไม่ได้รัน Flutter/build/runtime checks ซึ่งอยู่ในขอบเขตของ root

## Coverage และผลตรวจโครงสร้าง

| รายการ | จำนวน |
| --- | ---: |
| primary ใหม่ | 1155 |
| existingEditorial เก่าที่อ่านครบ | 678 |
| source IDs ที่ตรวจ | 1833 |
| source meanings ทั้งหมด | 3562 |
| accepted source meanings | 2943 |
| excluded source meanings พร้อมเหตุผลราย index | 619 |
| IDs ที่ไม่มี source sense ยอมรับได้ แต่มี curated primary | 116 |
| primary ใหม่ mapped / independent null | 1005 / 150 |
| POS override ใหม่ | 0 |

รัน `python -X utf8 build/verification/cefr-complete-20260912/three/validate_final.py` ได้ PASS: exact ID coverage ไม่มีซ้ำ; schema/status; accepted+excluded partition source indices; mapped indices อยู่ในขอบเขต source; exact headword token ครบทุก English example; Thai fields ไม่ว่าง; ไม่มี English example ใหม่ซ้ำ; final JSON ตรงกับร่าง TSV ที่ตรวจแล้ว การตรวจนี้เป็นหลักฐานโครงสร้าง ไม่ใช่หลักฐานคุณภาพภาษาแทนการอ่าน การยอมรับ raw source เพื่อแสดงผลแยกจาก identity ของ curated primary ที่แก้สะกดหรือเกลาความหมายแล้ว จึงไม่บังคับว่า mapped ต้องอยู่ใน accepted เสมอ

Owner reread เปลี่ยน mapping เป็น null เมื่อความหมายใหม่ไม่เทียบเท่า source อย่างแม่นยำ เช่น absolutely (degree), attraction (สิ่งดึงดูดใจ), inference (ข้อสรุป), judgment (วิจารณญาณ), notable (ลักษณะโดดเด่น), organizer (ผู้จัดงาน), plaque (วัสดุไม่ได้จำกัดเหล็ก/หิน), scholarly (งานเชิงวิชาการ), speculative (การคาดคะเน) และ nectar (ดอกไม้ ไม่ระบุเกสร) ปรับประโยค degrade/likelihood/misleading/versus และ Thai หลายจุดหลังอ่านรอบสอง

## ข้อผิดพลาดเดิมและการตัดสินใจที่สำคัญ

รอบ owner reread ไม่พบข้อผิดพลาดสำคัญเพิ่มใน primary เก่า 678; cross-review อิสระต่อมาพบรายละเอียดเครือญาติ/ถ้อยคำไทยและ official adjective gloss ซึ่ง root รับแก้ old batches แยกต่างหาก ข้อนี้แสดงขอบเขตการตรวจ ไม่รับประกันว่าปราศจากข้อผิดพลาดทั้งหมด และไม่ใช้การ exclude raw source เป็นเหตุเปลี่ยน curated mapping อัตโนมัติ

ตัด source ที่ทำให้เข้าใจผิด เช่น psychiatric=จิตวิทยา, respiratory=เหมาะสำหรับหายใจ, predecessor=บรรพบุรุษ, shocking=ผู้ตกใจ, stereotype=การทำแม่พิมพ์, profitability=ความได้เปรียบ, year=365.5 วัน และคงตัวตน/ข้อความ source เดิม ไม่เขียนทับแหล่งต้นฉบับ การ exclude หมายถึงไม่เสนอเป็น learning alternative ในชุดนี้ อาจเป็นเพราะผิด/กว้างเกิน/POS ผิด/เก่าหรือเฉพาะทางไม่เป็นประโยชน์ ไม่ได้หมายความว่าทุก excluded sense ไม่มีในพจนานุกรม

ศัพท์เฉพาะใช้ gloss Thai ระบุบริบทเมื่อจำเป็น เช่น proximal (กายวิภาค), parameter (คณิตศาสตร์), pathos/verisimilitude (วรรณกรรม), tinker (อาชีพในอดีต), queer (ความหมาย strange แบบเก่า) ไม่มีการเปลี่ยน CEFR level ของ catalog; คำยากที่ต้นฉบับจัดระดับมาไม่เท่ากับผ่านการสอบเทียบระดับใหม่

## คำดูหมิ่นและข้อจำกัดการฝึก

| ID | การตัดสินใจ |
| --- | --- |
| `cefrj15:gook` | Primary เป็นคำเหยียดเชื้อชาติรุนแรงต่อคนเอเชีย; ตัวอย่างอธิบายตัวคำเพื่อการรับรู้ ไม่เรียกบุคคลด้วยคำนี้; exclude source0 ที่นิยามเป็นกลางว่า คนผิวเหลือง Root รับผิดชอบ recognition-only และไม่เสนอฝึกพูด/ใช้กับคน |
| `cefrj15:queer` | Primary เป็น strange ในเรื่องเก่า มีป้ายการใช้แบบเก่า; exclude source2 นิยามอัตลักษณ์แคบและขาดบริบท คำนี้มีทั้งประวัติการเหยียดและการใช้ระบุตัวตนที่ยอมรับ ไม่ควรเหมารวมปิด sense ปลอดภัย และไม่ใช้ติดป้ายคนที่ไม่ได้ระบุตนเองเช่นนั้น |
| `octanove10:tinker` | Primary เฉพาะช่างเร่ซ่อมภาชนะโลหะในอดีต; ไม่ใช้เป็นคำเรียก Traveller/กลุ่มชาติพันธุ์ ซึ่งอาจเป็นคำดูหมิ่น ไม่ควรปิดความหมายอาชีพประวัติศาสตร์ทั้งหมด |
| `cefrj15:prick` | Primary รอยแทงจากหนามปลอดภัย; exclude source1 คำหยาบทางเพศ ไม่มีข้อเสนอปิดทั้ง entry |
| `cefrj15:fairy` | คง primary สิ่งมีชีวิตในเทพนิยาย; exclude source1 ที่ใช้เหยียดชายรักชาย ห้ามนำ sense เหยียดกลับมาฝึกใช้กับคน |
| `cefrj15:tramp` | Primary การเดินไกล; exclude source0 เรียกคนไร้บ้านอย่างดูแคลน ไม่ปิด benign walking sense |

อีกกลุ่มเป็นคำประเมิน/คำเก่าที่ต้องบริบท ไม่ใช่ severe slur ทั้ง entry: `cefrj15:dwarf` ใช้แฟนตาซี ไม่ติดป้ายสภาพร่างกายคน; `octanove10:deviant` มีป้ายเชิงดูหมิ่น; `cefrj15:lame` ใช้ข้ออ้างที่ฟังไม่ขึ้น ไม่ใช้เรียกความพิการ; source ของ insane/madness/hysteria ตัดคำวินิจฉัยเก่าที่ไม่แม่นยำ ไม่เสนอให้เหมารวมปิดทุก sense

## Primary dictionary checks

ตรวจเฉพาะคำกำกวมจริง ใช้คำอธิบายพจนานุกรมประกอบความหมาย แต่ประโยคตัวอย่างแต่งใหม่ ไม่คัดลอกตัวอย่าง:

- [Collins indiscrete](https://www.collinsdictionary.com/dictionary/english/indiscrete): ความเป็นก้อนเดียวไม่แยกส่วน ไม่ใช่ indiscreet
- [Merriam-Webster declination](https://www.merriam-webster.com/dictionary/declination): มี sense inclination/downward bending รองรับความลาดเอียง
- [Cambridge proximal](https://dictionary.cambridge.org/dictionary/english/proximal): ความใกล้จุดยึด/ศูนย์กลางกายวิภาค
- [Cambridge metalled](https://dictionary.cambridge.org/us/dictionary/english/metalled): ผิวถนนหินย่อยแบบอังกฤษ
- [Merriam-Webster cay](https://www.merriam-webster.com/dictionary/cay): เกาะเตี้ยหรือแนวทราย/ปะการัง
- [Merriam-Webster brimstone](https://www.merriam-webster.com/dictionary/brimstone): sulfur
- [Merriam-Webster cloister](https://www.merriam-webster.com/dictionary/cloister): ทางเดินมีหลังคาริมลาน
- [Merriam-Webster gook](https://www.merriam-webster.com/dictionary/gooks): ระบุ insulting/offensive โดยเฉพาะคนเอเชีย; dictionary มี homonym อื่น แต่ catalog นี้ให้ racial sense เท่านั้น
- [Cambridge queer](https://dictionary.cambridge.org/dictionary/english/queer): แยก old-fashioned strange และอัตลักษณ์ พร้อมข้อระวังการใช้กับผู้อื่น
- [Collins tinker](https://www.collinsdictionary.com/dictionary/english/tinker): แยกอาชีพซ่อมภาชนะในอดีตจากการเรียก Traveller ที่ offensive

## Cross-review reconciliation และ hash

รับและแก้ข้อเสนอ root จากการอ่าน new-primary index0–1154 ครบทั้งชุด รวม 33 คำ บันทึกทั้ง asset และ scratch เพื่อให้ validator ตรวจเทียบได้:

- translation: abhor, antique, arduous, creamy, exhibitionist, frequency, imagery, impede, initially, massacre, mortal, ox, presentation, squeeze, stabilize, suitably, treaty, total, uncontrollable, unless, unworldly
- example: athletic, grapefruit, grave, lifetime, neither, pathos
- meaning + translation: daydream
- example + translation: jealous, meaninglessly (แก้ reviewNote ให้ตรงการพูดซ้ำในบทสนทนาด้วย)
- meaning: hedgehog, menial
- meaning + sourceMeaningIndex + reviewNote: ungodly ใช้ความหมายไม่เคารพพระเจ้าเกี่ยวกับการกระทำ จึงเปลี่ยน mapping เป็น null ไม่เท่ากับ source ที่เน้นไม่ศรัทธา

ประเด็นสำคัญคือ unless ต้องแปลว่าเริ่มไม่ได้ถ้ายังมีคนไม่พร้อม ไม่ใช่ถ้าทุกคนไม่พร้อม; Thai ของเครือญาติสอดคล้อง English ที่เพิ่ม older/maternal/paternal; hedgehog ไม่เท่ากับ pygmy hedgehog ทุกชนิด; menial บอกสถานะที่สังคมมอง ไม่ตัดสินคุณค่าคน

Source cross-review ครบตามผู้ตรวจจริง: root แถว0–229, editorial_one แถว230–899, editorial_two แถว900–1832; root อ่าน new-primary prose ครบ1,155ต่างหาก เจ้าของรับข้อเสนอทั้งห้ารายการ:

- beyond source1 อยู่ทางนั้น ไม่ระบุเลยออกไป/อีกด้านหนึ่ง จึงexclude; primaryเดิมและmappingคงเดิม
- bronze source0 ทองสัมฤทธ์ สะกดผิด จึงexclude raw; primaryทองสัมฤทธิ์และmapped0คงsameidentity
- maggot source0 หนอนแมลง กว้างกว่า fly larva จึงexclude; primarynullเดิมคงเดิม ตาม [Oxford maggot](https://www.oxfordlearnersdictionaries.com/definition/english/maggot)
- mariner source0 กำกับล้าสมัยอย่างเด็ดขาด จึงexclude raw; curatedวรรณกรรม/nullคงเดิม ตาม [Cambridge mariner](https://dictionary.cambridge.org/us/dictionary/english/mariner) และ [Collins mariner](https://www.collinsdictionary.com/dictionary/english/mariner)
- overbook source0 จองตั๋วมากกว่าที่มี ไม่แสดงบทบาทผู้รับจองเกินความจุ จึงexclude; primaryรับจองเกิน/nullคงเดิม

แก้เฉพาะ acceptedSourceMeaningIndices/excludedSourceMeanings/reviewNote ของห้า entries ใน sense-review-3.json และร่าง TSV; complete-3.json ไม่เปลี่ยนจากprosefreeze รายงานcross-reviewชุด1อ่านครบแล้วส่งownerone/rootดำเนินการตามfinding ไม่แก้assetผู้อื่น

SHA256 final frozen หลัง source reconciliation และ validator PASS:

- complete-3.json: `3c0d6c460b99f99c99b51371f101dbd668de48c2dc93e8ebde1cd99e24647d3f`
- sense-review-3.json: `a2c9b8f1178fd0e6c5b4370fc46d7fd597cf477812dfbc5b326491ab5e3fd804`

ไม่มี process งานค้าง editorial_two อ่าน final diff ทั้งสาม records ในช่วง900–1832 เทียบ snapshotครบแล้ว ยืนยัน SHA และปิดรายงาน cross-review-3 ไม่มีข้อค้างในช่วงนั้น ขั้นต่อไป root บูรณาการ; cross-reviewชุด1อ่านครบแล้วและรออ่านdiffหลังowneroneแก้ โดยไม่แก้assetเจ้าของคนอื่น
