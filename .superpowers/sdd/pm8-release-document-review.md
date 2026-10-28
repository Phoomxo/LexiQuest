# PM8 release-document review

ผล: ไม่พบข้อบกพร่องสาระสำคัญในขอบเขตเอกสารร่างที่ตรวจ การรีวิวนี้ไม่ใช่ผล release gates, APK validation, external UAT หรือ G4P acceptance

ตรวจแบบ read-only ใน `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`, HEAD `94c1e97fea5097af144b63adfdf9ab2e5f277bee` เมื่อ 2026-09-07 ร่างหลักคือ `docs/development/2026-09-07-pair-matching-pm8-local-verification.md`, SHA256 `07b05506691f70593e5680e0fce05530ceb24420e83d3c5dc7557c9536cf75c4` ณ เวลาตรวจ ข้อมูล final identity/results/artifact ที่รอ root เติมถูกถือเป็น TODO ที่ตั้งใจไว้ ไม่ใช่ finding

## ขอบเขตและหลักฐาน

- อ่าน PM8 ใน active Adventure implementation plan, PM8 brief, historical engineering status และ PM8 finalizer report เพื่อแยกข้อกำหนดออกจาก historical/pending evidence
- อ่านร่างทั้งฉบับและ `.superpowers/sdd/pm8-reconcile-pmt-inventory.ps1`; อ่านตัวสร้าง named inventory `.superpowers/sdd/pm8-summarize-flutter.ps1` เพื่อเข้าใจ input contract โดยไม่ execute script เหล่านี้
- อ่าน actual compatibility fixtures, Matching reader/writer, Pair codec, native TTS adapter, Voice facade และ host narration/stop path ที่รองรับข้อความสำคัญ; อ่าน TC-PMT rows, UAT headings และ golden call sites เฉพาะที่เกี่ยวข้อง
- Read-only Git checks ยืนยัน cwd/branch/HEAD และ `git diff --numstat -- lib test` ไม่มี output ณ เวลาตรวจ ไม่มี source, tests, dependency, scanner หรือ build command ถูก execute โดย reviewer นี้

## ผลตรวจ

1. Version axes ตรงกับ actual implementation: legacy activity schemas 1–5/default writer 5, strict Pair activity 6, progressed codec readers 1–4, pinned start 1/2 และ ordinary attempt payload writer 1/explicit internal writer 2 ถูกแยกจาก database v24 และ feature catalog 8/44 ไม่มีการอ้างว่าทดสอบ historical APK
2. Compatibility fixtures ใช้ actual legacy reader และ Pair reader; schema6 old-reader rejection ตรวจไม่ให้ durable bytes ถูก rewrite ร่างจำกัด recovery artifact เป็น schema6-capable internal artifact และยังไม่ระบุ actual build/hash จนกว่าจะ build/verify เสร็จ ไม่อ้างว่า default APK เปิด public Pair entry point หรือเปิด Release B โดยอัตโนมัติ
3. Voice scope ตรงกับโค้ด: `VoiceSession.speak` คืน start acknowledgement; Pair ใช้ `speakUntilCompleted`, เก็บ narration pause เมื่อ cleanup incomplete และมี owned stop retry; adapter ระงับ natural-completion proof หลัง interruption จนเปลี่ยน instance ข้อจำกัด physical native playback และ screenshot ของ failed-stop affordance ถูกเปิดเผย
4. Read-only parsing ของตารางหลักได้ 14 groups, 44 case references, 44 unique IDs ครบ 001–044 ไม่มี missing/duplicate; 49 unique mapped Dart paths และทุก path มีจริง การเพิ่ม facade test อธิบายส่วนต่างจาก historical map 48 paths ได้
5. Golden call sites รวม 15 comparisons: board 8 (รวม narrow scrolled ภาพที่สอง), actual host 4 และ Adventure 3 ไม่มีการตีความว่า golden 15 ภาพเท่ากับ 15 independent test cases
6. Inventory reconciliation script ขยาย ranges/comma segments ตามรูปแบบตารางปัจจุบันได้, เทียบชื่อ/path/result/skipped ของ default/serial inventories แบบ ordinal และรักษา multiplicity, ตรวจครบ 44 IDs และทุก mapped path มีผล success/non-skipped ทั้งสองชุด ไม่พบ material parsing/counting defect สำหรับ input contract ที่ระบุ
7. 258 RTM/188 TC/44 PMT/50 UAT ถูกระบุเป็น planning inventories ไม่ใช่ executed acceptance; UAT-039–050, physical accessibility/audio/performance และ learner comprehension ยังคง Not Run ไม่มี measured numerator/denominator ของเป้า 11/12 ไม่มีลายเซ็นหรือ Accept/Revise/Reject ที่แต่งขึ้น; roles ทั้งห้ายัง Unrecorded และ research default-off/independent authority แยกชัดเจน

## Root-owned finalization ที่ยังต้องเติม

รายการนี้เป็นงานที่กำลังดำเนินอยู่ ไม่ใช่ correction finding: แทน pending source/gate/build fields ด้วย evidence ของ final source เดียวกัน, ระบุ APK/source/hash พร้อมข้อจำกัด reader-capable default-legacy artifact, บันทึก final disposition ของ retained failing correction run, แนบ actual named inventories และ reconciliation result หลัง full default/serial สำเร็จ นับ overlapping focused/affected runs แยกกัน ไม่รวมยอดเป็น unique coverage

Reviewer นี้ไม่ได้รับรองผล final gates ที่กำลังรัน ไม่มี process ค้าง และไม่มี write นอก ignored report นี้
