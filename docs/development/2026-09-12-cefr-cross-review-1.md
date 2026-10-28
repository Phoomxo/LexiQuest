# Cross-review CEFR complete batch 1 — 2026-09-12

Reviewer: AI agent editorial_three. Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`. ไม่ใช่การรับรองโดยมนุษย์

อ่าน source ทุกแถว 0–1833 รวม 1,834 IDs และทุก gloss 3,543 รายการ พร้อม accepted/excluded rationale, POS, primary mapping, English/Thai ทั้ง new primary 1,156 และ existingEditorial 678 รายการ การอ่านแบ่งช่วงประมาณ 70 แถว; output ที่ขาดช่วง 770 ถูกอ่านใหม่ครบก่อนดำเนินต่อ ไม่ใช่การสุ่มตัวอย่างหรือใช้ structural tests แทนการอ่านภาษา

ตรวจ actual old batches เทียบ snapshot หลังอ่านครบ พบเฉพาะ armchair, blame, cooker, december เปลี่ยนแล้ว อ่าน fields ใหม่ครบและยอมรับ จึงถือ old armchair/blame/december ในตารางเป็น **resolved by root** ไม่ต้องแก้ซ้ำ ข้อเสนอเก่าอื่นให้ root ดำเนินการ; ไม่แก้ asset ของผู้อื่น

## Findings ส่งเจ้าของเพื่อพิจารณาแก้

| row (0-based) | ID | ขอบเขต | ข้อสังเกต | ข้อเสนอ |
| --- | --- | --- | --- | --- |
| 19 | cefrj15:active | translation | grandfather ไม่ระบุฝ่าย แต่ไทยคุณปู่ | เพิ่ม paternal ใน English ให้ตรงคุณปู่ หรือแปลไม่ระบุฝ่าย |
| 95 | cefrj15:armchair | old-translation | Grandma ไม่ระบุฝ่าย แต่ Thai คุณยาย | เพิ่ม maternal grandmother หรือแก้ Thai ไม่ระบุฝ่าย |
| 115 | cefrj15:attentively | translation | grandmother ไม่ระบุฝ่าย แต่ Thai คุณยาย | เพิ่ม maternal ใน English |
| 134 | cefrj15:ballad | translation | sister ไม่ระบุอายุ แต่ Thai พี่สาว | เพิ่ม older ใน English |
| 172 | cefrj15:blame | old-translation | brother ไม่ระบุอายุ แต่ Thai น้องชาย | เพิ่ม younger ใน English |
| 205 | cefrj15:broccoli | source-review | ตัด source0 เพียงเพราะเป็นตัวพืชไม่เท่าอาหาร แต่ broccoli ใช้เรียกพืชได้ถูกต้องและ useful alternative ไม่จำเป็นตรง primary | รับ source0 สำหรับตัวพืช หรือให้เหตุผลเฉพาะว่าข้อความส่วนใดผิด/ไม่เป็นประโยชน์; primary null คงได้ |
| 331 | octanove10:confabulation | translation | Their ไม่กำหนดสองคน แต่ไทยทั้งคู่ | เพิ่ม the two friends หรือแก้ไทยการสนทนาของพวกเขา; gloss ควรติดป้ายทางการสำหรับconversation sense |
| 369 | octanove10:counsel | translation | grandfather ไม่ระบุฝ่าย แต่Thaiคุณปู่ | เพิ่ม paternal ในEnglish |
| 410 | cefrj15:december | old-translation | Grandma ไม่ระบุฝ่าย แต่Thaiคุณยาย | root เพิ่ม maternal grandmotherหรือปรับThaiไม่เดาฝ่าย |
| 480 | octanove10:divergent | translation | sisters ไม่ระบุจำนวน แต่Thaiพี่น้องหญิงคู่นั้นระบุสองคน | เพิ่ม two ในEnglish หรือเปลี่ยนThaiพี่น้องผู้หญิงเหล่านั้น |
| 709 | cefrj15:granny | old-translation | granny ไม่ระบุฝ่าย แต่Thaiยาย | root ระบุ maternal ใน English หรือเลือกบุคคลชื่อเฉพาะ |
| 722 | cefrj15:guitar | old-translation | brother ไม่ระบุอายุ แต่Thaiพี่ชาย | root เพิ่ม older ก่อน brother |
| 761 | cefrj15:hip-hop | old-translation | brother ไม่ระบุอายุ แต่Thaiพี่ชาย | root เพิ่ม older ก่อน brother |
| 757 | cefrj15:high | source-review | source1 (สระ)เสียงสูง อาจสื่อ pitch แทน tongue height ในhigh vowel | Exclude source index1: high vowel refers to tongue height, not pitch. Primary0 unchanged; Cambridge Phonetics Overview supports distinction. |
| 984 | cefrj15:memory | old-translation | grandmother ไม่ระบุฝ่าย แต่ไทยคุณยาย | เพิ่ม maternal ใน English |
| 1054 | cefrj15:nephew | translation | sister ไม่ระบุอายุ แต่ไทยพี่สาว | เพิ่ม older ใน English |
| 1095 | cefrj15:old | old-translation | Grandma ไม่ระบุฝ่าย แต่ไทยคุณยาย | เพิ่ม maternal grandmother ใน English |
| 1130 | cefrj15:owe | translation | brother ไม่ระบุอายุ แต่ไทยพี่ชาย | เพิ่ม older ใน English |
| 1312 | octanove10:recuperate | translation | sister ไม่ระบุอายุแต่ไทยพี่สาว | เพิ่ม older ใน English |
| 1387 | cefrj15:rugby | old-translation | brother ไม่ระบุอายุแต่ไทยพี่ชาย | เพิ่ม older ใน English |
| 1472 | cefrj15:sister-in-law | translation | brother ไม่ระบุอายุแต่ไทยพี่ชาย/พี่สะใภ้ | เพิ่ม older ก่อน brother ใน English |
| 1617 | cefrj15:tease | translation | brother ไม่ระบุอายุแต่ไทยพี่ชาย | เพิ่ม older ใน English |
| 1678 | cefrj15:transistor | translation | Grandfather ไม่ระบุฝ่ายแต่ไทยปู่ | เพิ่ม paternal grandfather ใน English |
| 1691 | cefrj15:trust | old-translation | sister ไม่ระบุอายุแต่ไทยพี่สาว | เพิ่ม older ใน English |
| 1808 | cefrj15:wisdom | old-translation | grandmother ไม่ระบุฝ่ายแต่ไทยยาย | เพิ่ม maternal ใน English |
| 1831 | cefrj15:youth | old-translation | grandfather ไม่ระบุฝ่ายแต่ไทยตา | เพิ่ม maternal ใน English |
| 1826 | cefrj15:yard | old-translation | yard ไม่ระบุด้านหน้าบ้านแต่ไทยสนามหน้าบ้าน | เพิ่ม front ก่อน yard หรือไทยลานบ้าน |
| 1195 | cefrj15:pleasure | source-review | source0 ความปิติยินดี สะกดปีติด้วยสระอิสั้น ไม่สม่ำเสมอกับsend/transportที่excluded | exclude0เหตุผลสะกดปีติผิด; primary1คงเดิม |
| 1292 | octanove10:rapture | source-review | source0 ความปิติยินดีอย่างยิ่ง สะกดปีติผิด แต่curatedแก้ถูกแล้ว | exclude0 typo; retain primarymapped0ตามsameidentity |

Aunt/uncle translation precision เป็นข้อพิจารณาเพิ่มเติม ไม่ได้เหมารวมเป็น semantic failure: new inherit834, knit893, worldly1818 ใช้ aunt→ป้า; old single1470 uncle→ลุง การแปลไทยเลือกช่วงอายุญาติที่ English ไม่ระบุ หากใช้เกณฑ์ตรงรายละเอียดเครือญาติเข้มงวดเช่น sibling ให้เปลี่ยนตัวอย่างเป็นบุคคลชื่อเฉพาะหรือระบุความสัมพันธ์เต็มอย่างเป็นธรรมชาติ โดยคง headword/POS/sense เดิม

## Semantic adjudication และหลักฐาน

- broccoli source0 เป็นตัวพืช จึงเป็น alternate sense ที่ใช้ได้ ไม่จำเป็นต้องเหมือน primary food sense; ownerone รับข้อเสนอแล้ว
- high source1 `(สระ) เสียงสูง` เสี่ยงตีความ pitch แทนระดับลิ้น ใช้ [Cambridge Phonetics Overview](https://www.cambridge.org/gb/files/1413/8018/5069/PhoneticsOverview.pdf) ซึ่งแยก high/mid/low จากตำแหน่งลิ้น จึงเสนอไม่แสดง raw gloss นี้ โดย primary สูง0ยังถูก
- ถอนข้อเสนอ exodus ตัดคำพร้อมกันหลังตรวจ [Merriam-Webster exodus](https://www.merriam-webster.com/word-of-the-day/exodus-2024-04-23) ซึ่งให้นิยามการออกจากสถานที่ของคนจำนวนมากในช่วงเดียวกัน จึงไม่ถือ gloss เดิมผิด
- ไม่ตีความ mapped primary→excluded raw เป็น error อัตโนมัติ อ่าน `2026-09-12-cefr-existing-primary-adjudication.md` แล้ว การเกลาคำสะกด/ความจำเพาะโดยคง identity มีเหตุผลรักษา indexได้ เช่น cinema, fail, satisfy, unknown, desk, grandchild, hamburger, hometown, trousers, manage, does, two, worst; ไม่สั่งremapทั้งชุด
- sourceทางเฉพาะที่ excludedด้วยเหตุผลว่าไม่จำเป็น ไม่ได้หมายความว่าไม่มีความหมายนั้นจริง เช่น prayerผู้สวด/shrinkการหด/ศัพท์กฎหมายเก่า รับการเลือก editorial นี้ได้
- micro/transistor/wizard มี dictionary adjudicationของownerอยู่ในรายงานชุด1แล้ว; wizard noun override/null เหมาะกว่าใช้ attributive nounเป็นหลักฐานadjective
- ไม่พบ severe slur primaryใหม่ที่ต้องเพิ่ม whole-entry restriction. yellow racial source1ถูกexcludeแล้ว; philistineใช้sentenceอธิบายคำพร้อมlabelดูถูก. peasant/poetess/handicappedต้องคงป้ายบริบท; stupid/dim/rat/nut/turkey/tease ไม่เหมารวมทุกbenignsenseเป็นslur

## Verification และ snapshot

`python -X utf8 build/verification/cefr-complete-20260912/three/verify_one.py` PASS บนsnapshotนี้: source1,834/new1,156/old678; partition all3,543 sourceglosses, accepted2,819/excluded724, unique/exactIDcoverage. Structural verificationยืนยันcoverage/partitionเท่านั้น ไม่พิสูจน์คุณภาพภาษา

- input-1 SHA256 `22ed209b0cde29104ec3b7ce41e3a5b58075e591494768b297a194b602f07f3c`
- complete-1 SHA256 `32c458008c58ba94a7fb36bd56065d9d07e058fc958a8f0ad5ade22703098b32`
- sense-review-1 SHA256 `25f2ca8fddfb8e3a861de8cf4eb4d4dc376e0dcffbef680509b121d311ecbd40`

## Final reconciliation

Ownerone แก้และ freeze แล้ว อ่านทุก field ของ records ที่แก้ครบ19รายการ: new15 active, attentively, ballad, confabulation, counsel, divergent, inherit, knit, nephew, owe, recuperate, sister-in-law, tease, transistor, worldly และ source4 broccoli, high, pleasure, rapture เทียบcandidate snapshotกับข้อเสนอแล้วรับได้ทั้งหมด รายละเอียดอายุ/ฝ่ายญาติตรงกัน; inherit/knit/worldlyใช้บุคคลชื่อเฉพาะอย่างเป็นธรรมชาติ; confabulationมีformal labelและพวกเขาไม่จำกัดสองคน; raptureprimarymapped0คงidentityแม้rawtypoถูกexcluded

อ่าน actual old batch corrections เทียบ input snapshotครบ15recordsที่เปลี่ยน: armchair, blame, cooker, december, granny, guitar, hip-hop, memory, old, rugby, single, trust, wisdom, yard, youth รับได้ทั้งหมด ข้อเสนอเก่าในตารางจึงresolvedโดยrootแล้ว รวมoptional singleด้วย

ตรวจcoverage/partitionใหม่ PASS:1,834IDs/1,156new/678old/3,543glosses; accepted2,817/excluded726. Final hashes:

- complete-1.json `c615817a58afb6ecb9b5c24d8c35b8b5d9f1af133a9ba659697858d8ff953551`
- sense-review-1.json `c3fcc05d70288e528517a6cbea1881cd285dbb7410fcd43243e80a4c8fa223eb`

ไม่มีactionable findingsค้างในขอบเขตcross-reviewนี้ ไม่รันFlutter/buildและไม่มีprocessค้าง งานนี้เขียนเฉพาะรายงานนี้กับscratchของeditorial_three
