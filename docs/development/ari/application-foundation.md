# อารี — application foundation

ฐาน 80b227813483b630128c78edd4f8b31554f4f1c0; task 01a0bfa7-c450-7f10-8974-3dafeef31c43.

## Design ก่อน implementation

AiTutorGateway/AiTutorController/AiTutorUseCases เป็น BYOK (key, model, credential store และ usage journal) จึงไม่ใช้ key ว่างหรือเพิ่ม provider enum ปลอมเพื่อแทน managed session. เพิ่ม ManagedTutorTransport และ ManagedTutorController แยกขอบเขต โดยใช้ AiCancellation, AiTutorException และ OwnerOperationCoordinator เดิมซ้ำ ไม่เปลี่ยน production composition, API หรือ persisted schema.

Transport ที่ฉีดเข้ามาผูกกับ owner + opaque account reference + connection generation; ไม่มี token/key ใน contract หรือ UI. connect เป็นการเตรียม session ที่ชั้น host ยืนยันแล้ว ไม่ใช่ OAuth/login. ทุก connect/reply ผ่าน owner gate และตรวจ active owner ก่อน/หลัง await; controller ล้างข้อความและยกเลิกงานเมื่อเปลี่ยน owner/account, reconnect, offline, disconnect, dispose. หมายเลข operation ป้องกัน late result/error. ครอบ deadline และ cancellation แม้ transport ไม่ตอบ; transport ห้าม late side effects/persistence และต้องเคารพ cancellation ใน adapter จริง. Local disconnect ไม่อ้าง provider revoke.

State: disconnected, pending, ready, replying, cancelled, expired, offline, quotaExhausted, providerUnavailable. ไม่ retry/fallback/ซื้อเครดิตอัตโนมัติ. UI component แบบ reusable แสดงสถานะและคำตอบในแอป มี send/cancel/disconnect ตาม state แต่ไม่มีปุ่ม login จน route รองรับ. ไม่มี fake transport ใน lib และไม่มีการประกอบเข้าหน้าจอ production.

## ลำดับและเกณฑ์

1. Tests สำหรับ lifecycle, owner/account/generation fences, timeout/cancel/dispose, sanitized errors และ no fallback ก่อน implementation.
2. Controller + UI; tests เชื่อม widget/controller/injected test transport รวมอยู่ใน focused Flutter suite (ไม่ใช่ device E2E).
3. verify-scope Targeted/AI และ focused analyze; review diff; structured evidence/handoff; commit/push และปล่อย writer.

V2 gate NOT_MET: hosted distribution, entitlement, quota-only billing, provider revoke ยังไม่ยืนยัน; device-code มี security setting จริง ไม่แก้ข้อกำหนด Free ไทย/in-app/no key/no Developer mode/no desktop companion. Live login/inference/mobile/pilot NOT_RUN; E7 ไม่ปิด. Device acceptance deferred-until-implementation-complete.

## ผล implementation และตรวจสอบ

เพิ่ม transport seam, controller และ reusable panel แล้ว โดยไม่มี transport จริงหรือ mock ใน lib และไม่มี production entry point. Tests ใหม่ 26 + regression ของ owner gate/BYOK 37 = 63 PASS ผ่าน verify-scope; focused analyze: No issues found. ไม่รัน gate ที่ผ่านซ้ำเมื่อ inputs ไม่เปลี่ยน. Tests UI เป็น simulated component integration ไม่ใช่ device/E2E acceptance.

Self-review พบ deadline ที่ครอบ transport แต่ไม่ครอบ owner lookup ที่ค้าง: เพิ่ม test ให้เห็น pending ผิดเวลา แล้วแก้ cancellation race รอบ coordinator ด้วย ผลสุดท้ายผ่าน. UI จบการยกเลิกได้ทันที ส่วน coordinator เป็นเจ้าของ cleanup/release ต่อเมื่อ dependency ที่กำลัง await คืนค่า; lease เดิมยังป้องกันงานใหม่ ไม่อ้างว่า local cancel ถอนสิทธิ์ provider.

Host ในอนาคตต้องแจ้ง owner/account change แบบ synchronous เพื่อล้างข้อความและ draft ที่แสดงอยู่, ส่ง offline event และดูแลอายุ transport; controller ตรวจ active owner ซ้ำก่อน dispatch/หลังผลและหลัง gate cleanup. ไม่มีการเก็บประวัติหรือ credential เพิ่ม. ผลที่มาหลัง cancel/timeout/dispose/reconnect ถูกทิ้ง รวม late error โดยไม่ส่งรายละเอียด exception ไป UI/log.

หลักฐาน: [evidence](application-foundation-evidence.json) · [handoff](application-foundation-handoff.json). ยังไม่ประกาศระบบครบหรือ V2 ผ่าน. Successor ที่เป็นซอฟต์แวร์อิสระ: host lifecycle binding ของ owner/account, network และ route disposal ใน disabled composition harness พร้อม simulated navigation tests; จากนั้นจึงทำ provider adapter/OAuth/revoke ได้เมื่อ route gate ยืนยัน ไม่วนวิจัยเอกสารเดิมหรือรอมือถือก่อนทำส่วนอิสระ.
