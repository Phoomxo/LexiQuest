# S01-BC — explicit logout recovery

## S01-BC — checkpoint ล่าสุด (หยุดตามคำสั่งผู้ใช้)

Existing explicit logout recovery **HOST_PASS570**: account/settings/owner 286 + runtime/navigation 284; 46 new offline cases. Callback เดิมหมดสิทธิ์เมื่อ account/session/dependency/route/tab/pop/lifecycle เปลี่ยน; ป้องกันคำสั่งซ้ำและผลล่าช้าพาออกจากหน้าใหม่. ตรวจ owner ที่คิวและ transaction เดิม; รักษา rollback/entry restoration โดยไม่ย้อนผล provider ที่ commit แล้วหรือแทนที่ owner ใหม่. Error แสดงภาษาไทยอย่างไม่อ้างผลสำเร็จหรือ rollback ที่พิสูจน์ไม่ได้; ต้องเลือกใหม่โดยผู้ใช้เอง.

Final source pins 1,563 ตรงกันและตรงไฟล์ปัจจุบัน; inherited ZIPs 233 ชุดไม่เปลี่ยน. Scoped analysis ไม่พบปัญหา; Drift warnings core11/runtime25 ไม่ถูก suppress. Prototype115+3 ใช้หลักฐานเดิมบน8 pins. Self-review only; ไม่ใช่ native/device/visual/keyboard/screen-reader/user/trial/release acceptance. UX-D01–25 OPEN และวันเริ่ม/กำหนด review S01 เดิมไม่เปลี่ยน.

คำสั่งล่าสุดให้จบ BC แล้ว release writer และส่ง controller เพื่อสำรอง/จัดระเบียบ: **ไม่มี successor, nested transfer ZIP, commit/push หรือ cleanup โดย writer นี้**. ดู [validation](evidence/S01-BC-validation.json), [รายงาน BC](S01-BC.md), [controller checkpoint](handoffs/S01-BC-controller-checkpoint.json) และ [backup inventory](handoffs/S01-BC-backup-inventory.json). S01 ยังไม่จบ.

### สิ่งที่ตรวจ

- Native/semantics callbacks, replacement/removal of direct and inherited accounts, same-UID events, route/tab/immediate pop/disposal/lifecycle, usable fresh controls and single-flight submission.
- Synchronous/untyped/recent-login errors, entry read/partial clear, owner/guest failure, failed rollback, lost acknowledgement, newer owner/session and explicit recovery.
- Real SQLite in-memory transaction and queued-owner tests; canonical account rows and committed outcomes preserved. No real Firebase/account actions, credentials, emulator or shared-user storage.
- Final bounded verify-scope Learning/Runtime gates and changed-file Dart analysis; raw command/result/stream hashes are in validation. Earlier red/candidate results are retained.

### ส่งคืน controller

Worktree: `C:\Users\Phet\.codex\worktrees\s01-bc-logout\LexiQuest`  
Branch: `feature/ux-s01-bc-logout-01a0de13`  
Exact base: `2ea4d407e7d5b1d41af65a533691b8aafe019ac5`  
Writer thread: `01a0de13-8083-7fd0-9fdc-ba59ebdb4944`

Application edits stop at this checkpoint. Dirty/untracked source and ignored evidence/media remain in place. Inventory records sizes and hashes for backup and restore verification; it is not authorization to delete excluded caches or user data. No processes from this package remain running after gates. Controller owns backup/commit/push and any separately authorized cleanup.
