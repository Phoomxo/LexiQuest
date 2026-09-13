# LexiQuest — Rule Supersession Register

Revision `2026-09-13-sequential-3` · ผู้ใช้อนุมัติให้เริ่ม G0.1 และส่งต่อทีละ task ถึง G8.9; ใช้ GPT-6 Astra / Medium

เอกสารนี้ระบุว่ากติกาใดหมดผล กติกาใดเป็นเพียงค่าตั้งต้น และเกณฑ์ใดยังคงใช้ตรวจความถูกต้อง อ่านผ่าน [Active Index](full-system-active-index.md) และ [Master Plan](../superpowers/plans/2026-09-13-lexiquest-full-system-master-plan.md). การหมดผลของข้อจำกัดไม่ใช่คำรับรองว่าได้แก้โค้ด ลบไฟล์เก่า หรือทดสอบ runtime แล้ว

## ลำดับการใช้เอกสาร

1. คำสั่งล่าสุดของผู้ใช้ รวมการหยุด/ปรับทิศทางที่เกิดภายหลัง
2. AGENTS.md และกติกาความถูกต้องของข้อมูล/หลักฐานที่ยังมีผล
3. Master Plan ปัจจุบัน + register นี้ + package workflow + current handoff
4. Engineering spec / acceptance / minigame contracts ที่ยังใช้ โดยอ่านเฉพาะ requirement ของ package
5. R15 roadmap, prototype choices, old checkpoints และ source descriptions เป็นประวัติ; ไม่ใช้ขอบเขตของ milestone เก่าตัดงาน Master

## กติกาที่เคลียร์สำหรับงานปัจจุบัน

| ID | ข้อความ/ตำแหน่งเดิมที่ตรวจพบ | สถานะใหม่และผลที่ต้องใช้ |
| --- | --- | --- |
| RULE-01 | Master revision2: “หยุดรอตรวจแผน”, “ไม่เริ่มexecutionจนได้รับคำสั่ง” | **Superseded:** ผู้ใช้ตอบให้เริ่ม G0.1 และส่งต่ออัตโนมัติแล้ว ไม่หยุดขออนุมัติทุก package ซ้ำ |
| RULE-02 | Master revision2: “ห้ามเริ่ม workers/tasks เบื้องหลัง”, “auto-created successor tasks” | **Replaced:** อนุญาตหนึ่ง successor task ตามลำดับหลังงานก่อนปิดแล้ว; ยังคงไม่ให้ parallel writers/background implementation workers |
| RULE-03 | `r15-package-workflow.md` ของ 842c: “through R15.10”, “No codex/ branch prefix” | **Retired for Master:** ใช้ G0.1–G8.9, prefix `codex/` ตามค่าเริ่มต้นปัจจุบัน; ไม่เริ่ม R15.11 และไม่สร้าง task ย้อนกลับไปทำ milestone เดิมซ้ำ |
| RULE-04 | R15 acceptance working protocol: R15.10 “expand only for reproduced voice/sync defect” | **Historical milestone limit:** ไม่จำกัด G0–G8; แก้ระบบอื่นที่อยู่ใน Master ได้ตาม owner package และ dependency reason |
| RULE-05 | R15 roadmap: “คง approved catalog 8/44”; Master revision2 wording แบบ fixed scope | **Reframed:** 44 เป็น coverage baseline ที่ต้องตรวจ ไม่ใช่เพดานถาวร. ถ้าการออกแบบต้องเพิ่ม/เปลี่ยน contract ให้ version และ update coverage/change record โดยรักษาประวัติเดิม |
| RULE-06 | R15 spec DATA-05: “R15 ไม่เพิ่ม owner-scoped table เป็นค่าเริ่มต้น”; old no-schema/no-dependency statements | **Baseline default, not ban:** เพิ่ม/เปลี่ยน storage/schema/dependency ได้เมื่อจำเป็นต่อ Master พร้อม owner key, migration, export/delete/sync/policy และ tests; ไม่ reserve migration number หรือสร้าง writer ซ้ำล่วงหน้า |
| RULE-07 | Prototype/Unified UI draft: fixed tabs/order/alignment; old workaround layouts | **Revisable design:** ปรับ navigation, UI, tokens, animations และเกมได้เมื่อ evidence/design/acceptance รองรับ. Route/history compatibility และ accessibility ต้องยังถูกต้อง |
| RULE-08 | R15 spec AI-01: “session-only history ใน revision นี้ ไม่มี chat-history table ใหม่”; AI-02 no-streaming-for-animation | **Revision-specific defaults:** ไม่เป็นข้อห้ามถาวรต่อ AI architecture. Current session-only path ยังเป็น baseline; persistent history/streaming ที่จำเป็นต้องมี purpose, privacy/lifecycle/usage/compatibility design ใน G6 ไม่เปิดเพราะชื่อเทคโนโลยีอย่างเดียว |
| RULE-09 | R15 CAM-03 จำกัด evaluation improvement/pilot; baseline manifest ไม่เปลี่ยนใน milestone | **Development limit retired:** ขยาย dataset/classes/evaluator/model candidate ใน G5 ได้. การส่ง candidate ต้องผ่าน dataset/model/resource/device/rollback acceptance; validation/test separation ไม่ถูกยกเลิก |
| RULE-10 | OUT/EXP lists ใน audit: online/friends/classroom/OCR/video/Yencha ฯลฯ | **Product backlog disposition, not permanent prohibition:** ยังไม่ใช่งานที่เลือกส่งใน edition ปัจจุบัน; หากจำเป็นต่อ Master ให้ออก design/change record และจัด owner package. ไม่เพิ่มทุกฟีเจอร์ของคู่เทียบโดยอนุมานจากการปลดข้อจำกัด |
| RULE-11 | Package owner/write-set lists ที่เคยใช้จำกัดงานให้เล็ก | **Starting scope:** ขยายไฟล์/consumer/contract ที่เกี่ยวข้องได้เองโดยบันทึกเหตุผลและเพิ่ม coverage ที่กระทบ. ไม่หยุดงานเพียงเพราะ dependency อยู่นอก list เก่า |
| RULE-12 | Old tests/goldens/source-string checks ที่ป้องกัน UI หรือกติกาเก่า | **Acceptance-led replacement:** เปลี่ยน assertions/goldens ที่ขัด design ใหม่ได้พร้อม rationale และ replacement tests. ห้ามลด assertion เพื่อซ่อน defect ของ behavior ที่ยังต้องการ |
| RULE-13 | “มี test/code แล้ว”, old PASS counts, menu-only observations | **Evidence classification retained:** รับ baseline credit เมื่อ source/dependencies/config ตรง. ไม่อ้างว่าเล่นทุกคู่เทียบหรือ runtime ผ่านทั้งหมด; ช่องว่าง observation ไม่ห้ามพัฒนาฟีเจอร์ที่มี local contract ชัด |
| RULE-14 | ข้อจำกัดให้ทำครบทั้งหมดใน task เดียว หรือวนอ่านประวัติทุกครั้ง | **Retired:** task ละหนึ่ง package; ใช้ brief + current checkpoint + exact source + เฉพาะ section/consumer ที่จำเป็น; 64 tasks สร้างทีละตัว |

RULE-03 และ UI draft ต้นทางที่ยังไม่ได้ checkout อยู่ใน `C:/Users/Phet/.codex/worktrees/842c/LexiQuest`. รอบนี้เปลี่ยน authority/headers/compatibility entry ใน 7712; ไม่เขียนชน source 842c. G0.1 นำ document revision นี้เข้า isolated source, G0.2/G0.3/G0.6 จัด disposition ของไฟล์เก่าที่รับมาภายหลัง

## เกณฑ์ที่ยังต้องตรวจ แต่ไม่ใช้ล็อก implementation

- Owner isolation, transaction/idempotency, historical content/evidence/reward interpretation, versioned compatibility, privacy และผลทดสอบตามจริงยังเป็นเกณฑ์ตรวจรับ สามารถเปลี่ยน implementation เพื่อให้ได้คุณสมบัติเหล่านี้ดีขึ้น
- Free-first/local-first เป็นเป้าหมายผลิตภัณฑ์; ไม่อนุมานสิทธิ์จ่ายเงิน ส่งข้อมูลจริง deploy หรือเปิด research จากคำสั่งเคลียร์ข้อจำกัด
- บันทึกแยก local/emulator/physical/human/live acceptance. สิ่งที่ต้องใช้ข้อมูล/คน/อุปกรณ์จริงเป็น external gate ของคำกล่าวอ้าง ไม่เป็นข้ออ้างหยุดงาน local ที่ไม่พึ่ง gate นั้น
- รักษา AGENTS เรื่อง verifier ที่มีขอบเขต, ไม่รันงานหนักพร้อมกัน, ไม่ rerun passed inputs ที่ไม่เปลี่ยน และไม่ใช้ workflow/worker ที่ระบุห้าม
- เมื่อคำสั่งเดิมล้มซ้ำ/filesystem error ซ้ำ/no progress10นาที ให้หยุดคำสั่งหรือขั้นที่เสีย วินิจฉัยและบันทึกเหตุ ก่อนเลือกการแก้/ทางเลือกที่มีเหตุผล. ไม่วน retry โดยไม่เปลี่ยนสาเหตุ; แจ้งผู้ใช้เมื่อเป็นข้อขัดข้องที่แก้ต่อเองไม่ได้

## สถานะไฟล์เก่า

G0.6 มีงาน active-index / historical / superseded / archive / unreferenced-candidate พร้อม hash, references, replacement และ restore map. G7.4 ครอบคลุม unused code/data/cache/lifecycle หลังตรวจ consumers. ภาพ failure candidates76ไฟล์ยังไม่ได้ถูกลบ; goldens, migration, history, receipts และหลักฐานที่ยังอ้างอิงต้องมี disposition ก่อนเปลี่ยน

การแก้ครั้งนี้ทำให้ข้อจำกัดเก่าที่ขัดกัน **ไม่มีผลเป็นคำสั่งปัจจุบัน** และเตรียม task ที่รับผิดชอบ cleanup ไว้แล้ว. การลบ/ย้ายไฟล์ application และการอัปเดต GitHub เป็นงานคนละขั้น ไม่กล่าวว่าทำแล้วจากการแก้เอกสาร
