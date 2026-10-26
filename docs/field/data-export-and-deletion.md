# ข้อมูล การส่งออก และการลบ

ผู้ใช้เลือกส่งออกข้อมูลของตนเป็น CSV, PDF หรือ Anki ได้จาก Export Center
และเลือกสร้างชุดข้อมูลวิจัย JSON ได้เฉพาะเมื่อความยินยอมรุ่นปัจจุบันยังมีผล
หากการเขียนไฟล์ล้มเหลว ระบบจะแจ้งข้อผิดพลาดและไม่รายงานว่าสำเร็จ

## การรักษาข้อมูล

- การถอนการติดตั้งหรือกดล้างข้อมูล Android จะลบฐานข้อมูลในเครื่อง
  และ Gemini key ใน Android Keystore จากอุปกรณ์นั้น
- ข้อมูลที่ยังอยู่ใน outbox และไม่เคยซิงก์จะกู้คืนไม่ได้หลังล้างข้อมูล
- การออกจากระบบไม่ควรลบข้อมูลการเรียนของ Guest หรือบัญชีโดยอัตโนมัติ
- การอัปเกรด Guest เป็นบัญชีจะรวมข้อมูลเข้าบัญชีและสร้าง projection ใหม่

## การถอนความยินยอม

เปิด ตั้งค่า > ความยินยอมการทดลอง > ถอนความยินยอม หลังถอนแล้ว
การส่งออกชุดข้อมูลวิจัยจะถูกบล็อก แต่ CSV/PDF/Anki ส่วนตัวและการเรียน
ออฟไลน์ยังใช้งานได้

## การขอลบข้อมูล Cloud

การลบข้อมูลในเครื่องไม่เท่ากับการลบข้อมูลที่ซิงก์แล้ว หน้า
`https://vocab-learning-app-219ef.web.app/delete-account/` แสดงทั้งเส้นทางในแอป
และช่องทางภายนอกที่โหลดจาก owner-controlled release configuration
ช่องทางดังกล่าวต้องยืนยันเจ้าของบัญชีก่อนรับคำขอ บันทึกขอบเขต วันที่ ผลลัพธ์
และใบรับคำขอ โดยห้ามขอรหัสผ่าน โทเคน หรือ API key ผ่านช่องทางสนับสนุน
หาก configuration หรือ production deletion service ไม่พร้อม รุ่นนั้นต้อง fail closed
และห้ามเปิดเก็บข้อมูลจริง

## การส่งออกก่อนลบบัญชีจริง

ไฟล์ CSV/PDF/Anki ที่ผู้ใช้ดาวน์โหลดจากเครื่องเป็นสำเนาสำหรับผู้ใช้
ไม่ใช่หลักฐานว่าข้อมูลฝั่ง Cloud ถูกส่งออกครบ การลบบัญชี production
จึงต้องสร้าง server-complete export แยกต่างหากก่อนเริ่มลบข้อมูลหรือ Firebase
Auth identity หากขั้นตอนนี้สร้างหรือยืนยันหลักฐานไม่ได้ ระบบต้องหยุดโดยไม่ลบ

ระบบ production รองรับ authority ชนิด `gcp-kms-hmac-sha256-v1` เท่านั้น
และปิดไว้โดยค่าเริ่มต้น โดยบันทึก canonical JSON ลง GCS แบบ private และ
create-if-absent จาก operation ID แล้วใช้ Cloud KMS HMAC-SHA256 ลงนามใน
ใบรับรอง Server จะดาวน์โหลดและตรวจ digest กับ MAC ซ้ำเมื่อ retry หรือเมื่อ
ไม่แน่ใจว่าการอัปโหลดครั้งแรกสำเร็จหรือไม่ วัตถุเดิมที่ข้อมูลหรือผู้ใช้งาน
ไม่ตรงกันจะถูกปฏิเสธและไม่ถูกเขียนทับ

ระบบไม่เก็บ recovery key แบบ plaintext ใน Firestore แต่เก็บ keyed verifier
ที่ผูกกับ KMS key version แบบ exact allowlist เท่านั้น เมื่อหมุน key สามารถใส่
key version เก่าใน
`LEXIQUEST_AI_ACCOUNT_DELETION_EXPORT_TRUSTED_KMS_KEY_VERSIONS` ได้
เฉพาะช่วงที่ operation เก่ายังกู้คืนได้ เอกสารเก่าที่มี plaintext จะถูกย้าย
แบบ atomic ผ่าน KMS; ถ้า KMS ใช้ไม่ได้หรือเอกสารผิดรูป ระบบหยุดโดยไม่ลบข้อมูล

ข้อมูลที่ส่งออกและลบใช้รายการเดียวกัน ได้แก่ `field_users/{uid}` พร้อมข้อมูลลูก,
`users/{uid}`, `state/{uid}`, หมวดคำศัพท์ที่ `uid` ตรงกันพร้อมคำศัพท์ลูก,
รายการซื้อที่ `user_id` ตรงกัน และ `vocabulary` ที่ `uid` ตรงกัน โดยไม่รวม
ข้อมูลส่วนกลาง เช่น `products`, `global_words`, `quiz` และ
`voice_telemetry_events` ข้อมูล Firebase Auth ส่งออกเฉพาะรายละเอียดบัญชีที่
จำเป็น ห้ามรวม password hash, token, custom claims หรือ recovery secret

ระยะกู้คืนและเก็บ server export ใช้ 7 วันเป็นค่าปฏิบัติการ และต้องเป็นค่าบวก
ไม่เกิน 30 วัน Bucket ต้องมี lifecycle ลบไฟล์เมื่อครบกำหนด และ Firestore
ต้องเปิด TTL เฉพาะ native timestamp `purgeAtUtc` ซึ่งจะถูกสร้างหลัง
`identityDeleted == true` เท่านั้น ห้ามเปิด TTL ที่ `recoveryExpiresAtUtc`
เพราะอาจลบ tombstone และเปิดให้เขียนใหม่ระหว่างที่การลบ Auth ยังไม่จบ

ทันทีที่สร้าง `account_deletion_operations/{uid}` rules จะหยุด owner write
ทุกเส้นทางที่อยู่ใน inventory แต่ยังอนุญาต read, ผู้ใช้อื่น และคำศัพท์ shared
ที่ไม่มี `uid` ตามปกติ เอกสารที่ค้นจาก owner field จะถูกลบด้วย update-time
precondition; หมวดที่มีข้อมูลลูกต้องตรวจ owner และ claim root แบบ transaction
ก่อนลบ หากเกิด race จะไม่สร้าง receipt และไม่ลบ Firebase Auth

เมื่อปิด kill switch ระบบต้องไม่รับคำขอลบใหม่ แต่ยังต้องกู้คืน operation
ที่ commit แล้วให้จบได้ หากเปิดรับคำขอใหม่แต่ authority, bucket, KMS,
สิทธิ์เข้าถึง หรือ retention configuration ไม่ครบ readiness ต้องเป็น 503
และ endpoint ต้องรายงานว่าไม่พร้อม โดยไม่เปลี่ยนข้อมูลผู้ใช้

readiness runtime ตรวจ public-access prevention และ uniform bucket-level access,
สิทธิ์ GCS create/get, สถานะและอัลกอริทึม HMAC-SHA256 ของ KMS ทุก key version
ใน allowlist พร้อม sign/verify และสิทธิ์อ่าน Firestore/Firebase Auth ผลถูก cache
รวม query กับ safe delete ที่มี precondition ว่า target ต้องไม่มีอยู่ ผลถูก cache
ช่วงสั้นเพื่อลดภาระ คำขอลบใหม่ต้องผ่าน probe เดียวกันก่อนสร้าง tombstone
ดังนั้น direct traffic ก็ข้ามไม่ได้ ส่วน recovery ของ operation ที่ commit แล้ว
ยังพยายามทำต่อได้ Failure ทุกชนิดเป็น 503 โดยไม่เปิดทางข้ามสำหรับคำขอใหม่

การทดสอบ local/emulator ไม่ใช่สิทธิ์ deploy หรือสิทธิ์ลบบัญชีจริง ก่อนเปิดใช้งาน
ต้องมีหลักฐาน IAM แบบ least privilege, GCS lifecycle/retention, Firestore TTL,
KMS key version, การทดสอบ create/replay/tamper/expiry ด้วยข้อมูลสังเคราะห์
และบันทึกอนุมัติ rollout จากเจ้าของระบบ
