# Review remediation design — 29 findings

User authorization: หลังรับรายงาน 29 ข้อ ผู้ใช้สั่งปรับแผน แก้ไข และทดสอบให้เรียบร้อย แนวทางแก้ในรายงานเป็นฐานของงานนี้ ดำเนินการต่อโดยไม่ขออนุมัติซ้ำสำหรับการแก้ภายในขอบเขต

## ผลลัพธ์ที่ต้องได้

1. ผู้เรียนเข้าทบทวน ตอบ และจบผ่าน canonical learning/evidence authority ได้จริง โดยประวัติและรางวัลไม่ซ้ำ
2. ภารกิจรายวันมีรอบเวลาชัดเจน เก็บประวัติได้ และไม่รับหลักฐานนอกช่วงเวลา
3. ผลเสียง คะแนน สถิติ และคำแนะนำสะท้อนข้อมูลที่ยอมรับแล้ว พร้อม recovery ที่ไม่สร้างความสำเร็จเทียม
4. แจ้งเตือนและ sync รักษา owner/consent isolation แม้เปลี่ยนสถานะกลางงานหรือกลับออนไลน์ภายหลัง
5. การดาวน์โหลด บริการ backend และ pipeline โมเดลรักษาขอบเขตข้อมูลและระบุผลตาม artifact ที่ใช้จริง
6. ทุก finding มี disposition และหลักฐานตรวจรับ; full regression/analysis/policy/build ใช้ source snapshot เดียวกันหลังรวมการแก้

## แนวทางที่เลือก

แก้ต้นเหตุเป็นชุดย่อยบนสถาปัตยกรรมเดิม ใช้ RED reproductions จาก review เป็นจุดเริ่ม แล้วเพิ่ม regression ใน suite ที่ดูแลระบบนั้น ไม่มีการสร้าง learning/reward authority คู่ขนาน ไม่ลดความเข้มของ signature, consent, content checksum หรือ owner checks เพื่อให้ข้อมูล sync ผ่าน

ทางเลือกที่ไม่ใช้: ปิดเมนูที่เสียโดยถาวรจะไม่ทำให้เส้นทางเรียนครบ; เขียนระบบใหม่หรือเปลี่ยน UI ทั้งชุดจะเพิ่มขอบเขตและทำให้หลักฐานบั๊กเดิมเทียบยาก การซ่อมตาม boundary เดิมเหมาะกับการตรวจรับทีละข้อและเก็บงานผู้ใช้ไว้

## การตัดสินใจสำคัญ

- R01 ต้องใช้ session ที่ ReviewCenter เปิดไว้ ห้ามสร้างอีก session แล้วทิ้ง session แรก การตอบและ complete ต้องผ่าน adapter/controller/use case เดิม และตรวจ actual durable attempts/result
- R02/R10 ใช้รอบวันของ learner timezone ที่ตรึงในข้อมูลรอบนั้น รางวัลยังใช้ durable completion identity เดิม ประวัติ terminal ห้ามถูกแทนที่เพื่อเริ่มวันใหม่ Migration ต้องจองใน schema ledger ก่อนแก้ schema และครอบ owner merge/export/deletion/replay
- R03–R05 แยก stop ที่รอ final จาก cancel; คะแนนยืนยันจาก final เท่านั้น; playbackCompleted ต้องมาจาก player จบจริง
- R06–R11 รักษาผลเดิมตาม checkpoint/session identity ไม่ย้าย evidence ข้าม session ตามอำเภอใจ; ทักษะ/คิว/actionable counts ใช้ canonical predicates และ availability จริง
- R12–R14 desired enabled ไม่เท่ากับ OS scheduled; สถานะ OS ปัจจุบันเหนือ cached grant; owner transition มี durable fencing และ compensation ที่ใช้ platform identity เดิม
- R15 คง wire identity แต่ local primary key ต้องแยก owner โดยไม่ทำลายรายการเดิม
- R16 withdrawal เป็น durable intent ที่การ reaccept ภายหลังไม่ลบล้าง; deny-only transport ยังต้องตรึง owner/permit identity
- R17 restore ต้องขนส่งหลักฐาน session ที่เพียงพอด้วย contract ที่ตรวจสอบได้ ห้าม fabricate canonical start/end หรือ bypass authorizer จาก placeholder
- R18 verify completed partial ก่อน network; R19 นับ body bytes จริงก่อน parse; R20 เก็บ response headers; R21 ไม่พิมพ์ input secrets ใน validation errors
- R22/R23 คู่มือและ artifact tools ต้องตรง producer/consumer contract จริง
- R24–R26 รักษา curated seed, แยก Pronoun ออกจาก Noun, adapter ที่ระบุแต่ไม่มีต้อง fail ก่อนประเมิน ไม่มีการฝึกหรือดาวน์โหลดโมเดลจริงเพื่อทดสอบข้อเหล่านี้
- R27–R29 retry ทำงานจริง และรักษา unknown/calendar semantics ถึง UI

## การตรวจรับและขอบเขตภายนอก

Root คุม Flutter/Dart/build/codegen ทีละคำสั่ง มี implementation writer ครั้งละหนึ่งราย และ independent reviewer ตรวจ spec+quality ของ diff เทียบ baseline รอบนี้ หลังชุดย่อยผ่านจึงตรวจรวม แผนเต็มอ้างอิงไฟล์ implementation plan วันที่เดียวกัน

ตรวจอุปกรณ์ด้วย read-only ADB ก่อน native workload ใช้การติดตั้งแบบรักษาข้อมูลและ runner ที่มี source/APK provenance เมื่ออุปกรณ์พร้อม งาน real-clock180นาทีต้องทำงานจริงครบ ไม่ใช้การรอเฉย ๆ แทน หากไม่มีอุปกรณ์ให้บันทึก NotRun พร้อมหลักฐาน และทำงาน local ที่เหลือต่อ

การได้ยิน/ออกเสียง/ถ่ายภาพจริง/TalkBack ที่ต้องอาศัยมนุษย์ยังรอผู้ใช้ตามข้อกำหนดเดิม ไม่อ้างผลแทนผู้ใช้ การฝึกเพื่อความแม่นยำ90%และการใช้ข้อมูลวิจัยจริงต้องมี dataset/authority ที่จำเป็น; ไม่ซื้อบริการ ไม่ deploy ไม่ enroll และไม่ upload จริงในงานซ่อมนี้
