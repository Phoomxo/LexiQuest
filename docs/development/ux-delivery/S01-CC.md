# S01-CC — native draft runner failure receipt

Canonical checkout `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest`, branch `codex/ux-current-after-s01-bc`, HEAD `c3a69c5fea4a5a9f08be06e2ea5717a937edc34d`. Controller `01a0ce9e-23a6-7931-88e6-6390da748f39`.

## ขอบเขตและผล

**HOST_STUB_PASS; NATIVE_NOT_RUN.** แก้เฉพาะ `tool/cli/run-native-draft-acceptance.ps1` และ stub test ของมัน. สาเหตุ CB คือ `finally` เรียก `Protected-Metadata` แล้ว throw ก่อนเขียน `result.json`; error หลังรันจึงบัง primary error. Runner ใหม่เก็บ primary failure กับ `postcheckFailure` แยกกัน เขียน `result.json` แม้ postcheck ใช้งานไม่ได้ และคงสถานะ FAIL เมื่อ transport ล้มเหลว. การตรวจ package collision/isolation และ protected metadata เจ็ดแพ็กเกจยังอยู่.

ก่อนเรียก ADB install จะเขียน `install-attempt.json` ใน output directory ใหม่ พร้อมสถานะ `ATTEMPTED_OUTCOME_UNKNOWN`; `result.json` จึงแยกผลตอบกลับ `SUCCESS_RETURNED` กับ `OUTCOME_UNKNOWN_OR_FAILED` และบันทึก exit code/error. Runner ปฏิเสธ install ครั้งที่สองใน run เดียว. การบันทึก attempt ไม่รับรองว่า device ได้รับคำสั่งหรือการติดตั้งสำเร็จ หาก process ถูกตัดหลังเขียน journal. ไม่มี retry อัตโนมัติ.

Stub `adb/aapt` ทดสอบ 9 กรณี: APK identity, permission/storage/provider rejection, package collision, normal success, และ `error: closed` ขณะ protected metadata ก่อน install, ระหว่าง install พร้อม postcheck failure, และใน postcheck หลัง main contract สำเร็จ. ตรวจ result persistence, primary/postcheck errors, journal ก่อน execution, install ไม่ซ้ำ, และคำสั่งต้องห้าม. ไม่มีการรัน native บนอุปกรณ์จริงใน CC; ไม่มี install/reinstall/clear/uninstall/reseed หรือ force-stop package จริง.

**หลักฐาน CB เดิมไม่เปลี่ยน:** สองรอบ full runner ของ CB ไม่มี result; จำนวน install command ยัง `UNVERIFIED_UP_TO_TWO_ATTEMPTS`. CC ไม่ลบความไม่แน่นอนนั้น และไม่อ้าง at-most-one-install ข้ามรอบย้อนหลัง. ก่อน native attempt ใหม่ต้องมีหลักฐาน ADB transport เปลี่ยนจาก `error: closed` และตัดสิน prerequisite ของ prior attempt อย่างตรงไปตรงมา พร้อม build/source manifest ใหม่ตาม runner source ที่เปลี่ยน. CB package ไม่พบว่าติดตั้งสำเร็จจาก postcheck เดิม; protected เจ็ดแพ็กเกจ/APK คงเดิมตาม CB receipt. Native draft/stale-route, N05 visual/IME/TalkBack, actual-user/UAT/trial และ frozen-source release ยัง NOT_RUN/DEFERRED.

S01/UX-D01–25 ยังเปิดอยู่. ไม่มี production `lib`/schema/owner/scoring/SRS/rewards/routes/gates/no-login/no-AI edit, deploy, research activation, external contact หรือ cleanup. Writer released without successor dispatch.
