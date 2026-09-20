# อารี — หนึ่งหัวข้อหลักต่อหนึ่ง task

อนุมัติจากผู้ใช้ 2026-09-20: เริ่มงานและแยก task ตามหัวข้อหลักเพื่อลด context ใช้ [แผนเดิม](ari-feasibility.md) และ [หลักฐานเดิม](ari-feasibility-evidence.json) ต่อ ไม่รีเซ็ตผลหรือขยาย scope เป็น production implementation

## ลำดับและขอบเขต

| Task | งานย่อยภายใน task | ผลส่งต่อ |
|---|---|---|
| LexiQuest · อารี V0 · ตรวจช่องทางบัญชีและมือถือ | V0.1 login; V0.2 inference rights; V0.3 Free/ไทย/mobile | route matrix แยก confirmed/unknown พร้อมเอกสารทางการ ส่ง V1 แม้ผลเป็นไม่รองรับ |
| LexiQuest · อารี V1 · ตรวจการเชื่อมต่อและค่าใช้จ่าย | V1.1 quota/billing; V1.2 native reply; V1.3 distribution/revoke | gate decision ที่อ้างหลักฐาน V0 และ V1 ครบทุกข้อ |
| LexiQuest · อารี V2 · ต้นแบบข้อความหนึ่งคำ | V2.1 บัญชี Free จริง; V2.2 bottle ในแอป; V2.3 failure/revoke/isolation | สร้างได้เฉพาะ gate ผ่าน; แยกผล live กับ simulated และบันทึก defect/retest |
| LexiQuest · อารี V3 · ตรวจรับแนวคิดและแผนต่อยอด | V3.1 requirement matrix; V3.2 pilot 5 คน; V3.3 ข้อสรุป | หาก gate ไม่ผ่าน ข้ามการสร้าง V2 task และบันทึก V2/pilot NOT_RUN; ทำข้อสรุปเอกสาร V3 ได้ |

สร้างทีละ task หลังงานก่อนหน้ามี handoff เท่านั้น ไม่เปิดสี่ task ทำงานพร้อมกัน V0/V1 เป็นการปิดช่องว่างหลักฐาน ไม่ใช่คำรับรองว่าเชื่อมต่อได้แล้ว V3 ที่ยังไม่มีผลผู้เรียนไม่ถือว่าผ่าน usability

## กติกาที่ต้องส่งต่อทุกครั้ง

- GPT-6 Astra (`gpt-6-astra`), reasoning `medium`, Standard/default; ห้าม Fast/1.5x หรือเลือก priority เอง ถ้าเครื่องมือไม่เปิดเผย tier ห้ามอ้างว่ายืนยันค่า runtime แล้ว
- สนทนาใน LexiQuest; browser เฉพาะ login; ChatGPT Free ในไทย; ไม่ให้จัดการ key/Developer mode; ไม่แทนด้วย paid API หรือ desktop companion; Gemini อยู่นอก scope
- ใช้ชื่ออารี คงตัวระบุ/ศัพท์/ประวัติเดิม ไม่แก้ E7 acceptance และไม่เริ่มงาน G/E เก่าจากคำสั่งอัตโนมัติในเอกสารประวัติ
- ห้าม subagents หรือ implementation พร้อมกัน มี writer เดียว คำสั่งหยุดใหม่ของผู้ใช้มีผลสูงสุด
- ข้อผิดพลาดที่แก้ได้: หยุดวิธีที่เสีย ค้น path จริง วินิจฉัย แก้และตรวจใหม่ แล้วทำต่อ ไม่ยก AGENTS เป็นเหตุหยุดเพราะคำสั่งล้มซ้ำ ไม่ข้าม defect/ลดเกณฑ์/อ้าง PASS ที่ไม่รัน
- อ่านผลเดิมก่อนค้นเพิ่ม ตรวจเฉพาะประเด็นที่ยังไม่ยืนยัน ถ้าไม่มีหลักฐานใหม่ให้สรุป UNCONFIRMED พร้อมช่องว่าง ไม่วนค้นเรื่องเดิมจน context เต็ม ไม่รัน tests ที่ผ่านและ inputs ไม่เปลี่ยน
- รายงานในแชทสั้นเฉพาะผล/ปัญหา/ขั้นต่อไป รายละเอียดอยู่ไฟล์หนึ่ง MD ต่อ task; แหล่งข้อมูล, pins และ test records อยู่ JSON ไม่มี raw log ก้อนใหญ่ในบทสนทนา

## ที่เก็บงานและส่งต่อ

Control root: `C:/Users/Phet/.codex/visualizations/2026/09/13/01a09888-61dd-7680-9b19-c33035043d59/ari-feasibility/tasks`

- `state.json`: ผู้รับงานปัจจุบัน, phase, task IDs และ gate; แยกจาก orchestration G/E เดิม
- `Vn.md`: ผลของ 3 งานย่อย สรุปสั้นและอ้างแหล่งข้อมูลที่รองรับแต่ละ claim
- `Vn-handoff.json`: input source SHA, ผลแต่ละงาน, route/unknowns, evidence paths, nextPhase, gate และงานที่ไม่รัน
- V0/V1/V3 ใช้ task ไม่มี repository สำหรับงานตรวจเอกสาร อ่านโค้ดจาก path ที่ระบุแบบ read-only เขียนเฉพาะ control root นี้ เพื่อไม่สร้าง worktree/build cache โดยไม่จำเป็น
- V2 ถ้าเข้าเกณฑ์จึงสร้าง project task ใน isolated worktree จาก accepted source ที่ระบุใน handoff ตรวจ SHA ก่อนเขียน ใช้ชื่อ branch `feature/` ตามคำสั่งผู้ใช้ล่าสุด ไม่ใช้ `codex/` หรือ `codeic/`

ผู้จบ phase ตรวจว่ามี successor task ID อยู่หรือไม่ ถ้ามีห้ามสร้างซ้ำ ถ้ายังไม่มี ให้บันทึก handoff และปล่อย writer ก่อนสร้าง **หนึ่ง** successor ด้วย model/thinking และข้อกำหนดข้างบน ส่งเฉพาะแผน, workflow, handoff ล่าสุด, พาธหลักฐาน และ SHA ไม่ fork ประวัติแชททั้งหมด บันทึก task ID ที่เครื่องมือส่งกลับ; clientThreadId ยังไม่ใช่ threadId

ถ้า V1 ไม่ผ่าน gate ให้สร้าง V3 เพื่อสรุปข้อจำกัด ไม่สร้าง V2 เพื่อเลี่ยง gate หากต้องใช้บัญชีหรือผู้เรียนจริงแต่ไม่มี ให้เตรียมแบบตรวจและงานที่ไม่พึ่งบุคคลให้ครบ แล้วระบุ prerequisite ที่ขาดตามจริง ห้ามสร้างผลจำลองแทนผลคนจริง ไม่ติดต่อผู้ให้บริการหรือผู้เรียนแทนผู้ใช้โดยไม่มีคำสั่งส่งข้อความ

## เกณฑ์ตรวจการส่งต่อ

ครบ 4 phases × 3 subitems = 12 IDs; scope ไม่เปลี่ยน; old evidence ใช้ซ้ำได้; ไม่มี source writer ซ้อน; handoff มี next action และสิ่งที่ยังพิสูจน์ไม่ได้; V2/pilot ไม่รับ PASS จากเอกสารหรือ tests ของการเปลี่ยนชื่อ การเริ่ม task ใหม่เป็นการแยก context ไม่ใช่รับประกันว่าจะประหยัด token เป็นเปอร์เซ็นต์คงที่
