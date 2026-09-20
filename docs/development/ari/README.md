# LexiQuest — ดัชนีงานอารี

จุดติดตามงานเดียวใน repository · 2026-09-20 · branch `feature/ari-feasibility`

**สถานะ: ตรวจเอกสารจบ แต่ยังไม่เริ่มต้นแบบเชื่อมบัญชีจริง** V2 gate = NOT_MET; pilot = NOT_RUN; E7 ไม่เปลี่ยนสถานะ ผล 77 tests เดิมครอบคลุมการเปลี่ยนชื่อ ไม่ใช่ ChatGPT Free integration

| หัวข้อ | งานย่อย | ผลล่าสุด | รายงาน / handoff |
|---|---|---|---|
| V0 ช่องทางบัญชีและมือถือ | V0.1–V0.3 | ตรวจเอกสารแล้ว ยังมี entitlement/mobile unknowns | [รายงาน](evidence/tasks/V0.md) · [handoff](evidence/tasks/V0-handoff.json) |
| V1 การเชื่อมต่อและค่าใช้จ่าย | V1.1–V1.3 | NOT_MET จากช่องว่างช่องทาง G1–G5; G6 พร้อมออกแบบและทดสอบภายหลัง | [รายงาน](evidence/tasks/V1.md) · [handoff](evidence/tasks/V1-handoff.json) |
| V2 ต้นแบบ | V2.1–V2.3 | NOT_RUN; ยังไม่ได้สร้าง task | รอช่องทางที่รองรับตามแผน |
| V3 ตรวจรับและต่อยอด | V3.1–V3.3 | ปิดงานเอกสาร มีแบบตรวจ T01–T08; ยังไม่ได้ทดลองผู้เรียน | [รายงาน](evidence/tasks/V3.md) · [handoff](evidence/tasks/V3-handoff.json) |

## ไฟล์หลัก

- [แผนและข้อกำหนด](../ari-feasibility.md) · [workflow และกติกาสร้าง task](../ari-task-workflow.md)
- [สถานะปัจจุบันและ task IDs](state.json) · [ผลทดสอบโค้ดเดิม](../ari-feasibility-evidence.json)
- [รายการนำเข้าพร้อม hash](import-manifest.json) · [หลักฐานทดสอบฉบับเต็ม](evidence/verification/targeted-ai.json)

## ตำแหน่ง task

Sidebar กลุ่ม **LexiQuest · อารี** รวมโปรเจกต์หลักกับ task เดิมสามอัน:

| Phase | Task ID |
|---|---|
| V0 | `01a0bf7a-8427-78e3-bc73-ae1d57050622` |
| V1 | `01a0bf7d-e868-7df2-a2cb-db71829cd8d5` |
| V3 | `01a0bf81-3881-7c10-bc29-783868bf6212` |

Task เดิมถูกสร้างแบบ projectless ผิดจากรูปแบบงานของโปรเจกต์ การจัด sidebar ช่วยให้ค้นเจอด้วยกัน แต่ไม่ได้เปลี่ยน project binding เครื่องมือปัจจุบันเปลี่ยน binding นี้ไม่ได้โดยตรง Task ถัดไปต้องสร้างใน LexiQuest project ตาม workflow

นำเข้าหลักฐานเดิม 16 ไฟล์รวม 478,049 bytes โดยคงเนื้อหาและตรวจ SHA-256 ทุกไฟล์ใน `evidence/` ไม่ใช่การรันหรือรับ PASS ใหม่ พาธภายนอกที่ฝังอยู่เป็นประวัติ ใช้ลิงก์ในดัชนีนี้เพื่ออ่านสำเนาใน Git ต้นฉบับภายนอกคงไว้สำหรับตรวจย้อนกลับ ไม่เป็นที่เขียนงานใหม่

การเปิดงานต่อ: ต้องแก้ช่องว่าง route/entitlement/billing/distribution/revoke ตาม V1 ก่อนเริ่ม V2 โดยไม่เอาผล live tests มาเป็น prerequisite ก่อนสร้างต้นแบบ ไม่มีคำสั่งรันงานเก่า G/E จากการจัดเอกสารครั้งนี้
