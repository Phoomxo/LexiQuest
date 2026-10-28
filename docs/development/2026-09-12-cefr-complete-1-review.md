# CEFR completion editorial review 1 — 2026-09-12

Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch: `codex/pair-matching-pm0-pm8`.

## ขอบเขตและการตรวจ

อ่าน input-1 ทั้ง 1,834 รายการ รวมความหมายต้นฉบับ 3,543 ความหมาย และตัดสินแต่ละดัชนีเป็นรับไว้ 2,817 หรือไม่เสนอ 726 พร้อมเหตุผลใน sense-review-1.json ไม่แก้ข้อความหรือ ID ต้นฉบับ ตัวอย่างใหม่ 1,156 รายการครอบคลุมเฉพาะรายการที่ไม่มี existingEditorial ส่วนรายการเดิม 678 รายการไม่ได้เขียนทับ

แต่งตัวอย่างอังกฤษและคำแปลไทยทีละรายการตามความหมาย/POS แล้วอ่านทวนตัวอย่างใหม่ครบ 1,156 รายการอีกครั้ง ผู้รวมงานอ่าน draft ครบ 1,156 รายการโดยอิสระและส่งข้อแก้ภาษา ซึ่งแก้แล้ว รวม bony, compound, fume, genome, hearing, maternal, wholly และ worldly การตรวจนี้เป็น AI editorial review ไม่ใช่การรับรองโดยมนุษย์หรือการรับรอง CEFR ของทุก sense คำเฉพาะและคำระดับสูงใช้บริบทที่ช่วยเข้าใจตามคำเป้าหมาย ไม่อ้างว่าทั้งชุดเป็น A1/A2

ตรวจไฟล์จริงด้วย Python: JSON ถูกต้อง; primary 1,156 ID ไม่ซ้ำและตรง missing IDs ทุกตัว; sense review 1,834 ID ไม่ซ้ำ; accepted/excluded partition ดัชนีต้นฉบับครบไม่ซ้ำ; sourceMeaningIndex อยู่ในขอบเขต; status/sense key ถูกต้อง; text fields ไม่ว่าง; ทุกประโยคมี exact headword token แบบไม่สนตัวพิมพ์; override ทุกตัวมี null index ไม่มี token error หลัง cross-review rapture คง mapping 0 แม้ raw gloss ถูก excluded เพราะสะกดผิด โดย curated แก้สะกดและคง sense เดิม การตรวจโครงสร้างเหล่านี้ไม่ใช่หลักฐานแทนคุณภาพภาษา ไม่รัน Flutter/build เพราะงานนี้เป็นเนื้อหาอย่างเดียว

## การแก้หลัง cross-review สุดท้าย

ปรับ 15 primary records: active/attentively/counsel/transistor ระบุฝ่ายปู่ยาย; ballad/nephew/owe/recuperate/sister-in-law/tease ระบุ older ให้ตรงไทย; divergent ระบุ two; confabulation เพิ่มป้ายคำเป็นทางการและไทยพวกเขาไม่กำหนดสองคน; inherit/knit/worldly ใช้บุคคลชื่อ Mary/Anna แทน aunt ทั้งอังกฤษและไทย อ่านทุกประโยคที่แก้ครบอีกครั้งแล้ว ไม่แก้ exodus เพราะหลักฐานรองรับความหมายเดิม

ปรับ source decisions 4 records: broccoli รับตัวพืชเป็น alternate sense โดย primary food sense ยัง null; high ตัด index1 เพราะ high vowel ระบุตำแหน่งลิ้น ไม่ใช่ pitch; pleasure/rapture ตัด raw index0 ที่สะกด ปิติ แทน ปีติ ให้สอดคล้องนโยบาย raw gloss อื่น โดย rapture primary ที่สะกดถูกคง mapping เดิม หลักฐาน high และ adjudication อยู่ในรายงาน cross-review-1

Final coverage/partition/exact-token check ผ่าน 1,156 primary / 1,834 source / 3,543 glosses ณ hashes ด้านล่าง ส่งผู้ตรวจ editorial_three อ่าน final diff ทั้ง 19 records อีกครั้งแล้ว

## การตัดสินที่ควรทราบ

- `cefrj15:wizard` เป็น override ใหม่เพียงรายการเดียว: noun, null index, พ่อมด, “The wizard raised his staff in the story.” คำคุณศัพท์เกี่ยวกับเวทมนตร์เป็น archaic และ wizard hat ไม่พิสูจน์ adjective เพราะเป็น noun modifier จึงไม่สอน POS ที่ชวนผิด [Merriam-Webster wizard](https://www.merriam-webster.com/dictionary/wizard)
- `cefrj15:micro` ใช้ sense microprocessor ได้จริงตาม noun 2 ไม่จำเป็นเปลี่ยนเป็น microcomputer [Merriam-Webster micro](https://www.merriam-webster.com/dictionary/micro)
- `cefrj15:transistor` ใช้ความหมายวิทยุทรานซิสเตอร์และติดป้ายคำเรียกย่อ มี noun 2 รองรับ [Merriam-Webster transistor](https://www.merriam-webster.com/dictionary/transistor)
- buzzard ระบุการใช้แบบอเมริกันที่หมายถึงแร้ง เพื่อแยก British hawk [Merriam-Webster buzzard](https://www.merriam-webster.com/dictionary/buzzard)
- fume ใช้ noun modifier ใน fume hood เพื่อรักษารูปคำเดี่ยวอย่างเป็นธรรมชาติ ส่วน sense ไอสารเคมีมักพบ fumes ในการใช้ทั่วไป
- humble และ terminal เปลี่ยน mapping เป็น null เพราะ สมถะ และ สถานีปลายทาง ไม่เทียบเท่าความหมายหลักใหม่อย่างแม่นยำ; rotate เปลี่ยนเป็น index 0 ให้ตรง transitive ทำให้หมุน
- confabulation ใช้ sense การสนทนา ไม่ใช่ความจำที่แต่งขึ้น; ไม่คัดลอกตัวอย่างจากพจนานุกรม [Merriam-Webster confabulation](https://www.merriam-webster.com/dictionary/confabulation)
- shrink มี noun act of shrinking จริง แต่ไม่เสนอทางเลือกนี้เพราะไม่เป็นประโยชน์เท่า sense ที่ใช้ทั่วไป เหตุผล exclusion ไม่ได้อ้างว่าเป็นความหมายผิด [Merriam-Webster shrink](https://www.merriam-webster.com/dictionary/shrink)

## ข้อเสนอแก้ existingEditorial ให้ผู้รวมงานดำเนินการ

ไม่ได้แก้ batch เดิม รายการต่อไปนี้เป็น exact proposed corrections:

- `cefrj15:cooker`: sourceMeaningIndex: null; meaning: `เตาหุงต้ม (อังกฤษแบบบริติช)`; example: `Our new cooker has an oven and four rings.`; translation: `เตาหุงต้มใหม่ของเรามีเตาอบและหัวเตาสี่หัว`; reviewNote: `Bare cooker is the British cooking appliance; rice cooker is a compound and does not establish that cooker alone means หม้อหุงข้าว.` [Cambridge cooker](https://dictionary.cambridge.org/us/dictionary/english/cooker), [Oxford cooker](https://www.oxfordlearnersdictionaries.com/us/definition/english/cooker)
- `cefrj15:desk`, `cefrj15:grandchild`, `cefrj15:hamburger`, `cefrj15:hometown`, `cefrj15:trousers`: เสนอเปลี่ยนเฉพาะ sourceMeaningIndex เป็น null และคง primary fields อื่นทั้งหมด เพราะ gloss เดิมกว้าง/ไม่จำเพาะพอกับ curated sense (โต๊ะ, หลาน, ขนมปังยัดใส้เนื้อสัตว์, บ้านเดิม, กางเกง ตามลำดับ) ตัวอย่างเดิมไม่ได้ผิด
- `cefrj15:manage`: เสนอ sourceMeaningIndex: 0 แทน 1 โดยคง fields อื่น เพราะ index 1 มีข้อความทำสิ่งที่เป็นไปไม่ได้ซึ่งชวนเข้าใจผิด ส่วน index 0 สำเร็จตรง core sense
- `cefrj15:does`: gloss หลักอธิบาย third-person singular ถูกแล้ว แต่ source มีเพียง กริยาช่องที่ 1 ของคำกริยา do จึงเสนอ null index เพื่อให้ mapping เคร่งครัด ไม่ต้องเปลี่ยนประโยค
- cinema, fail, satisfy, unknown เป็นกรณี source สะกดผิด/ซ้ำ แต่ primary แก้ถูกแล้ว จึงไม่ถือว่า mapped core meaning ผิดเพียงเพราะ source นั้นถูก excluded; two มี source ซ้ำ และ worst มีคำอธิบาย POS ปะปน แต่ core gloss หลักยังตรง ไม่เสนอแก้ตัวอย่าง

## คำที่ควรอ่านเพื่อรู้และจำกัดการฝึกใช้กับคน

- `cefrj15:yellow` source index 1 ใช้จัดเชื้อชาติด้วยสีผิว ควรระงับ prompt ฝึกใช้เรียกคน; excluded แล้ว ไม่จำกัด sense สีเหลืองทั่วไป
- `octanove10:philistine` คำดูถูกความรู้/รสนิยมทางศิลปะ primary ระบุคำดูถูกและใช้บริบทอธิบายคำ ควรฝึกเชิงรับรู้
- `cefrj15:nut` index 1, `cefrj15:turkey` index 1, `cefrj15:rat` index 1 และ `cefrj15:tease` index 1 เป็นคำด่าหรือคำตัดสินคน (tease มีนัยกล่าวโทษทางเพศ) excluded แล้ว ไม่ใช้ฝึกเรียกบุคคล
- `cefrj15:stupid`, `cefrj15:dim` index 0 และ `octanove10:buffoon` อาจดูถูกคน ควรแยก context ที่กล่าวถึงความผิดพลาด/บทการแสดงจากการด่าคน ไม่ใช่ทุก sense เป็นคำเหยียดรุนแรง
- `cefrj15:handicapped` เป็นคำเรียกความพิการที่ล้าสมัยและอาจไม่สุภาพ existing primary มีคำกำกับแล้ว; `octanove10:peasant` ใช้ประวัติศาสตร์และไม่ควรเสนอให้เรียกคนร่วมสมัยอย่างดูแคลน; `octanove10:poetess` เป็นรูปแบ่งเพศที่เก่า ควรคงคำกำกับบริบท

## Frozen hashes

- complete-1.json SHA-256: `c615817a58afb6ecb9b5c24d8c35b8b5d9f1af133a9ba659697858d8ff953551`
- sense-review-1.json SHA-256: `c3fcc05d70288e528517a6cbea1881cd285dbb7410fcd43243e80a4c8fa223eb`

ไม่มี process ของงานนี้ค้างอยู่ ขั้นถัดไปคือผู้ตรวจอ่าน final diff และผู้รวมงานตรวจ integration ข้อเสนอ existingEditorial ด้านบนเป็นประวัติการเสนอ root adjudicate แล้วตาม 2026-09-12-cefr-existing-primary-adjudication.md ไม่ใช่คำสั่งให้แก้ซ้ำ
