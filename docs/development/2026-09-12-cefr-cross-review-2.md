# Cross-review completion batch 2 — 2026-09-12

สถานะ: ตรวจครบ source 0–1832 จำนวน 1,833 รายการและ new primary 1,155 รายการ อ่านทุกความหมายเดิมและเหตุผล accepted/excluded พร้อมตรวจภาษาอังกฤษ/ไทยของทุก primary ใหม่ จากนั้นอ่าน diff ทั้ง 52 records หลังผู้เขียน freeze แล้ว ข้อเสนอที่ต้องแก้ได้รับการแก้ครบ ไม่เหลือ actionable finding ในชุดใหม่ที่ตรวจ

ผู้ตรวจอ่าน input-2 เทียบ primary/review TSV snapshot ใน `build/verification/cefr-complete-20260912/one/cross-two-snapshot/` ครบทุก source gloss, accepted/excluded reason และทุก new primary จากนั้นเทียบ frozen JSON ด้วย `one/reconcile_two.py` และอ่านทั้ง 52 records ที่เปลี่ยน รวมข้อแก้ของผู้เขียนเอง ไม่ใช่สุ่มตรวจหรือถือ structural check เป็นคุณภาพภาษา

Input SHA-256: `641aa860100d5815af3c5f360fe788dafcfddbe82f46bd128a98b20d2820d895` Snapshot สร้างด้วย cross_snapshot.py และเก็บไฟล์จริงเพื่อเทียบ diff

Frozen `complete-2.json`: 1,155 entries, SHA-256 `f173b57c3540c4e44b39fe8ade0be7c6b1c75961ff39d74fbc90a930c3cab0c9`.

Frozen `sense-review-2.json`: 1,833 entries, SHA-256 `ebb94097be4a1d6a47f24849b0a76f2967af70c3f6c662e9d9e321f4d498278a`.

ตรวจ coverage IDs, primary-v1, status, source index bounds และการแบ่ง accepted/excluded ครบทุก index แล้วผ่าน ณ hash นี้ การตรวจเชิงโครงสร้างเป็นหลักฐานประกอบเท่านั้น การประเมินภาษาเป็น AI editorial review ไม่ใช่การรับรองโดยมนุษย์หรือ CEFR certification

## Findings ที่ส่งผู้เขียน — ตรวจการแก้ครบแล้ว

| ID | Fields ที่เสนอแก้ | เหตุผล |
|---|---|---|
| cefrj15:adoption | translation: คู่รักคู่นี้ฉลองการรับบุตรบุญธรรมด้วยการพบปะครอบครัวกลุ่มเล็กๆ | The couple ไม่ระบุสถานะสมรสหรือเพศ |
| cefrj15:artistic | translation: โรงเรียนมีกิจกรรมเกี่ยวกับศิลปะหลายอย่าง รวมถึงการวาดภาพและการทำเครื่องปั้นดินเผา | pottery ในรายการกิจกรรมต้องสื่อการทำ |
| cefrj15:backyard | translation: เราปลูกต้นเลมอนเล็กๆ ในสวนหลังบ้านเมื่อฤดูใบไม้ผลิที่แล้ว | แยก lemon จาก lime |
| cefrj15:bless | translation: ชาวบ้านมารวมตัวกันเพื่ออวยพรคู่รักก่อนออกเดินทาง | couple ไม่ระบุคู่สามีภรรยา |
| octanove10:blister | meaning: แผลพุพอง; คง mapping 0 ได้ | แก้สะกดไทย primary จาก source ที่พิมพ์ ผุพอง |
| cefrj15:cattle | translation: วัวควายมารวมกันใกล้ประตูเมื่อเกษตรกรมาถึง | farmer ไม่จำกัดชาวนา |
| octanove10:convict | ถอนข้อเสนอ exclude index 1 แล้ว ไม่เป็น required fix | MW Kids ยอมรับ find or prove guilty จึง source พิสูจน์ว่ามีความผิดใช้ได้ |
| octanove10:debut | meaning: การปรากฏตัวเป็นครั้งแรกต่อสาธารณชนหรือวงสังคม | สะกดสาธารณชน |
| cefrj15:devil | translation: ในนิทานพื้นบ้าน เกษตรกรผู้ฉลาดหลอกปีศาจร้ายให้จากหมู่บ้านไป | farmer ไม่จำกัดชาวนา |
| cefrj15:flavour | translation: น้ำเลมอนทำให้ซุปมีรสชาติสดชื่น | แยก lemon จาก lime |
| cefrj15:fox | translation: สุนัขจิ้งจอกข้ามทุ่งแล้วหายเข้าไปในหมู่ต้นไม้ | crossed ไม่ระบุวิ่ง |
| octanove10:frosty | meaning: หนาวจนมีน้ำค้างแข็ง; null index; exclude 0 เพราะกลับเหตุ/ผล | ไม่ใช่หนาวเพราะน้ำแข็งตัว |
| cefrj15:fur | translation: เมื่อฉันสัมผัส ขนหนาของแมวให้ความรู้สึกนุ่ม | ไทยเดิมให้ขนเป็นผู้รู้สึก |
| cefrj15:handkerchief | translation: เธอพับผ้าเช็ดหน้าสะอาดแล้วใส่กระเป๋า | ไม่ระบุกระเป๋าเสื้อ |
| octanove10:hitch | translation: เกษตรกรหยุดเพื่อเทียมม้าเข้ากับเกวียนเล็ก | farmer ไม่จำกัดชาวนา |
| cefrj15:holocaust | candidate เพิ่ม by fire ในอังกฤษให้ตรงไทยและระบุ destruction sense | อังกฤษเดิมไม่ระบุไฟชัด แต่ไทยระบุไฟ |
| cefrj15:inhabitant | translation: ผู้อาศัยที่อายุมากที่สุดจำช่วงที่หมู่บ้านมีร้านค้าเพียงแห่งเดียวได้ | แก้โครงสร้างจำได้เมื่อที่ไม่เป็นธรรมชาติ |
| cefrj15:motor | candidate meaning: มอเตอร์; null index; source เครื่องยนต์ยังเป็นทางเลือกได้ | ประโยคนี้ระบุสายไฟจึงเครื่องยนต์ไม่เหมาะกับ electric motor |
| octanove10:neutralize | meaning: ทำให้หมดผล; null; example: The extra training helped neutralize the other team's advantage.; translation: การฝึกเพิ่มเติมช่วยลบข้อได้เปรียบของอีกทีม | neutralize dispute และไทยทำข้อพิพาทเป็นกลางไม่เป็นธรรมชาติ |
| octanove10:orchard | translation: เราเก็บแอปเปิลที่ร่วงอยู่บนหญ้าในสวนผลไม้ | ไม่ใช่ร่วงจากหญ้า |
| octanove10:palate | เปลี่ยนพ่อครัวเป็นเชฟใน translation | chef ไม่ระบุเพศ |
| cefrj15:pessimistic | translation: เขาพูดราวกับไม่ค่อยมีหวังว่าจะทำงานเสร็จก่อนวันศุกร์ | แก้ขอบเขตการมองแง่ร้ายให้อ่านตรง |
| cefrj15:picky | translation: เธอเลือกมากเรื่องสมุดและตรวจกระดาษอย่างละเอียดก่อนซื้อ | เลือกสมุดมากอาจหมายเลือกหลายเล่ม |
| cefrj15:plague | เปลี่ยนชาวนาเป็นเกษตรกรใน translation | farmer ไม่ระบุปลูกข้าว |
| cefrj15:radical | translation: ผู้สนับสนุนการเปลี่ยนแปลงครั้งใหญ่รุ่นใหม่เสนอว่าต้องเปลี่ยนทั้งระบบ | หนุ่มสาวในวลียาวนี้ไม่เป็นธรรมชาติ |
| octanove10:sauna | example: The guests enjoyed a sauna before resting in a quiet room.; translation: แขกอบซาวน่าอย่างเพลิดเพลินก่อนพักในห้องเงียบๆ | เดิมให้กิจกรรม followed by สถานที่ |
| cefrj15:sector | example: The report examines wages in the private sector.; translation: รายงานศึกษาค่าจ้างในภาคเอกชน | เดิม public and private sector ควร sectors เลือกเอกพจน์บริบทเดียวรักษา headword |
| cefrj15:sniff | translation: สุนัขหยุดเดินเพื่อสูดดมถุงข้างประตูรั้ว | หยุดสูดดมกลับเป็น stopped sniffing |
| cefrj15:somewhat | translation: ในห้องรู้สึกเย็นลงบ้างหลังพระอาทิตย์ตก | เดิมให้ห้องเป็นผู้รู้สึก |
| octanove10:speculate | example: We can only speculate about why the shop closed so suddenly.; translation: เราได้แต่คาดเดาว่าทำไมร้านจึงปิดอย่างกะทันหันเช่นนั้น | เดิมเกือบซ้ำ conjecture ทั้งประโยคและคำแปล เสนอเพิ่มความหลากหลาย |
| cefrj15:unfortunate | translation: น่าเสียดายที่ความล่าช้าทำให้เราพลาดคำกล่าวเปิดงาน | ความล่าช้าที่โชคร้ายไม่เป็นธรรมชาติในภาษาไทย |
| cefrj15:waste | candidate เปลี่ยน workshop จากโรงงานเป็นโรงทำงาน หรือระบุ factory ในอังกฤษ | ขนาด/ลักษณะสถานที่งานทำมือควรสอดคล้องกัน เป็นข้อเสนอความแม่นยำของบริบท |

การตรวจข้อสงสัยเพิ่มเติม: [Merriam-Webster convict](https://www.merriam-webster.com/dictionary/convicts) รองรับการพิสูจน์ว่าผิด จึงถอนข้อกังวล source index 1 ไม่เปลี่ยนความไม่แน่ใจของผู้ตรวจเป็นข้อผิดโดยไม่มีหลักฐาน

Source decisions ในช่วงที่อ่านยังไม่พบข้อผิดความหมายที่ต้องเปลี่ยนอย่างชัดเจน การ excluded ความหมายเฉพาะ/เก่าบางรายการเป็นดุลยพินิจทางการเรียน ไม่ใช่อ้างว่าความหมายเหล่านั้นไม่มีอยู่จริง
