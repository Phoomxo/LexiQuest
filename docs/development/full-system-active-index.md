# LexiQuest — Active Full-System Index

Revision `2026-09-13-sequential-3` · ลำดับ task: G0.1 → … → G8.9 · model `gpt-6-astra` / reasoning `medium`

ผู้ใช้อนุมัติให้เริ่มและส่งต่อทีละ task แล้ว; previous pause-after-plan ถูกแทนที่. เอกสารเก่าที่อ้างว่า “รออนุมัติเริ่ม” ไม่เป็นสถานะปัจจุบัน เว้นแต่ผู้ใช้ส่ง pause/stop ใหม่

อ่านเอกสารตามลำดับและเฉพาะส่วนที่จำเป็น:

1. `AGENTS.md` และ [rule supersession](2026-09-13-rule-supersession-register.md)
2. [Package workflow](full-system-package-workflow.md) และ current run-state/handoff ที่ creation prompt ระบุ
3. [Task index](full-system-task-index.json) → brief ของ package ปัจจุบัน
4. [Master Plan](../superpowers/plans/2026-09-13-lexiquest-full-system-master-plan.md) เฉพาะ package, dependency และ gate ที่เกี่ยวข้อง
5. [Work/coverage ledger](2026-09-13-full-system-work-ledger.json) เฉพาะ rows ของ package; [coverage audit](2026-09-13-master-plan-coverage-audit.md), [minigame contract](../superpowers/specs/2026-09-13-minigame-coverage-contract.md), engineering/acceptance/source register เฉพาะ requirement IDs

หลักฐาน/คำอธิบาย source รุ่นเก่าใช้ตรวจย้อนหลังได้ แต่ไม่ใช้เป็น backlog ใหม่โดยไม่ตรวจ current source. ไม่อ่านรายงานวิจัยทั้งหมดหรือ media ทุกชิ้นในทุก task

`r15-package-workflow.md` เป็น compatibility pointer ไป workflow ปัจจุบัน. R15 roadmap เป็นประวัติ milestone; spec/acceptance ยังใช้ด้านเทคนิคตาม rule register. 44 features/14 modes/2 journeys/14 MG เป็น coverage baseline; package count ปัจจุบันยัง64

G0.1 ใช้ bootstrap document seed ที่ creation prompt ระบุพร้อม hash manifest. ตั้งแต่ G0.2 เป็นต้นไปใช้ documents จาก accepted predecessor source; ไม่ทับด้วย seed เก่า หากแผนมี revision ใหม่ให้รับตาม handoff พร้อม compatibility check

ทุก task จบด้วย accepted source commit + checkpoint + evidence pointers + external run-state handoff แล้วสร้าง next task เพียงหนึ่งตัว. G8.9 ไม่มี successor และส่ง final ledger กลับ master
