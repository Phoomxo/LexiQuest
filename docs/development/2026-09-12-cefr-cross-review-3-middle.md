# Cross-review source batch 3 middle — 2026-09-12

อ่านครบ input-3 indices 230–899 จำนวน 670 source rows ด้วย root-view-senses.py ครั้งละไม่เกิน 80 rows เทียบ actual sense-review-3.json, complete-3.json และ actual batch-1/2/3.json อ่านทุก source gloss/POS/accepted/excluded reason/primary mapping และภาษาอังกฤษ–ไทยของทุก old primary ในช่วงนี้ ไม่ได้อ้างว่าอ่าน new primary sentences ทั้งชุด (root ตรวจส่วนนั้น) ไม่ใช่การรับรองโดยมนุษย์หรือ CEFR

ไม่พบ source acceptance/exclusion หรือ new primary mapping ที่ต้องแก้อย่างชัดเจนในช่วงนี้ การตัดความหมายเฉพาะทางบางข้อเป็นดุลยพินิจด้านประโยชน์ต่อการฝึก ไม่ใช่อ้างว่าความหมายนั้นไม่มีอยู่จริง

## Findings ส่ง root สำหรับ old primary

| ID | ข้อเสนอแก้ | เหตุผล |
| --- | --- | --- |
| cefrj15:company | example: My older sister works for a small software company. | ไทยระบุพี่สาว |
| cefrj15:cooking | example: My older brother enjoys cooking for the whole family. | ไทยระบุพี่ชาย |
| cefrj15:couple | example: The married couple next door invited us to dinner. | ให้ตรง primary คู่สามีภรรยาและไทย |
| cefrj15:deep | translation: รากงอกลึกลงไปในดินนุ่ม | soft ไม่ระบุชนิดดินร่วน |
| cefrj15:fighter | translation: นักสู้อายุน้อยฝึกซ้อมอย่างระมัดระวังก่อนการแข่งขัน | young ไม่ระบุเพศชาย |
| cefrj15:from | example: This letter is from my maternal grandmother. | ไทยระบุคุณยาย |
| cefrj15:guy | example: The guy by the door is my older brother. | ไทยระบุพี่ชาย |
| cefrj15:hug | example: I always hug my maternal grandmother when I visit. | ไทยระบุยาย |
| cefrj15:joy | example: She cried with joy when her older brother returned. | ไทยระบุพี่ชาย |

ทั้งหมดเป็นข้อเสนอให้ root เจ้าของ old files ประเมินและแก้ ผู้ตรวจไม่ได้แก้ assets หรือ runtime ไม่ได้รัน Flutter/build

## Source snapshot hashes ที่สิ้นสุดการอ่าน

- complete-3.json: `3c0d6c460b99f99c99b51371f101dbd668de48c2dc93e8ebde1cd99e24647d3f`
- sense-review-3.json: `539c51ebc9868d9437da907f11e0db4c938123cd26d779d363012ec30631bc06`
- batch-1.json: `08a2c4eb8cd5beb585e5c91f1fce8fcc89d3e78701641ee23e811936c9901606`
- batch-2.json: `00820783a741f7d6cd5020ef28f4191e3c5bfdfbf16f1d60616a23d23bafb95e`
- batch-3.json: `d85708ae5ea49306fe31dc5e3e5c7ab3a4a9ffafcf5996f4e12415f80db41435`

คำอ่อนไหวในช่วงนี้ เช่น gook มีป้ายความรุนแรงชัด และ source ที่ไม่เตือนถูก exclude แล้ว; fairy/insect sense ดูหมิ่นถูก exclude การเห็น schema/coverage ถูกต้องไม่ใช่หลักฐานคุณภาพภาษา การประเมินข้างต้นเกิดจากการอ่านเนื้อหาครบตามขอบเขต
