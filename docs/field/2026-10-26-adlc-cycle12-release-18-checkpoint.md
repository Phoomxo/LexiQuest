# ADLC Cycle 12 — release 1.0.0+18 checkpoint

วันที่: 2026-10-26
สาขา: `codex/cycle12-release`
ฐานก่อน checkpoint: `abdcea3903ea4af582b0ae94e6ef4084bb3dbc61`

## Intent / Ground

รอบนี้ปิดงานที่ยังข้ามหรือไม่มีหลักฐานหลัง release 17 โดยไม่เปิด production
rollout, ไม่ลงทะเบียนผู้เข้าร่วมจริง และไม่สร้างหลักฐานอุปกรณ์หรือสิทธิ์ที่ไม่มีอยู่จริง
ขอบเขตประกอบด้วย local-first App Check fallback, account export/deletion,
research fail-closed permit contracts, dependency remediation, UI critique fixes,
secret scanning และ signed Android release ใหม่

## Execute

- App Check ปฏิเสธ token ว่าง, junk และ Firebase placeholder ที่ทราบแน่ชัด;
  เมื่อ preflight ไม่ผ่านจะปิด cloud composition แต่การเรียนในเครื่องยังทำงาน
- committed account-deletion receipt ทำ local purge ต่อได้แม้ Firebase/Auth ไม่พร้อม;
  คำขอลบใหม่และ sync ยัง fail closed
- readiness probe ไม่เรียก `FirebaseAuth.deleteUser`; ใช้ read-only reserved UID probe
- account export/deletion เพิ่ม owner fence, update-time CAS, KMS HMAC recovery,
  GCS/KMS/Firestore/Auth readiness contracts และ production-default-off config
- research UI/runtime production-default-off พร้อม signed permit codec,
  Ed25519 verification และ trusted-time lease contracts
- Login ยก local learning เป็น primary action เมื่อ account provider ไม่พร้อม,
  Registration แจ้ง unavailable ตั้งแต่ต้น, consent แสดง 30/180 วันและความเสี่ยง,
  และ Export ไม่ประกาศ raw `content://` URI ให้ผู้ใช้หรือ TalkBack
- dependency graph ลด OSV จาก 133 รายการเหลือ 3 advisory ใน 2 package โดยไม่เพิ่ม ignore
- Gitleaks allowlist จำกัดด้วย path + exact fixture/commit และตรวจประวัติ Git ทั้งหมด

## Review / Attest

หลักฐานจาก source snapshot นี้ก่อน commit:

- `flutter analyze --no-pub`: PASS, 0 issues
- `flutter test --no-pub`: PASS, 1811/1811
- focused UI regression: PASS, 43 tests
- runtime bootstrap: PASS, 42 tests
- AI backend: PASS, 164 tests (2 upstream Python 3.11 FutureWarnings)
- Voice backend: PASS, 58 tests; real Firebase/OmniVoice E2E ถูก skip เพราะไม่มี test token
- Local LM: PASS, 78 tests
- Firestore emulator: PASS, 37 tests; Auth emulator: PASS, 3 tests
- static Firestore rule contracts: PASS, 25 tests
- Gitleaks: PASS, 1207 commits / 1.31 GB / 0 findings
- npm audit high gate: PASS, 0 vulnerabilities
- OSV Scanner: 0 Critical, 0 High, 2 Medium, 1 Low
- `uv lock --check`: PASS ทั้ง Voice, AI และ Local LM
- `git diff --check`: PASS

OSV ที่ยังเหลืออยู่ใน official Voice runtime:

- `setuptools 81.0.0`: fixed ที่ 83/84.1 แต่ PyTorch 2.11 กำหนด `<82`
- `torch 2.11.0+cu128`: fix ที่ 2.13 แต่ official Torchaudio ที่เข้าคู่มีถึง 2.11

Source ไม่เรียก `torch.jit.script` และไม่ใช้ setuptools build API ตอน runtime
จึงบันทึกเป็น upstream compatibility risk แทนการฝืน ABI หรือซ่อน advisory

## Integrate / release boundaries

- packager ต้องสร้างและผูก hash/signature ของ APK กับ AAB จาก commit ที่มี checkpoint นี้
- Vivo V2041 ที่ต่ออยู่ต้องรับ exact signed +18 แบบ in-place; ถ้า signature ไม่ตรงให้หยุด
  และห้าม uninstall อัตโนมัติ
- Firebase Test Lab ใช้แทนอุปกรณ์จริง low/high/Fold/tablet ได้เฉพาะ automated crash/layout
  evidence ไม่แทน human TalkBack/UAT
- Figma Cloud ยัง sync ไม่ได้: MCP ปัจจุบันเชื่อม `natthawut222005@gmail.com`
  แบบ View แทน owner/editor `petch954100@gmail.com`; R11 จึงยังเป็น final8-era และ
  R12 ยังเป็น draft ห้ามอ้างว่า current

## External gates ที่ห้ามสวมหลักฐาน

- Play Console app/upload/Play signing/compatibility acceptance
- valid App Check traffic, enforcement และ rollback evidence
- production GCS lifecycle/retention, KMS/IAM, Firestore TTL/rules deployment และ rollout approval
- owner-approved public support/deletion contacts
- human TalkBack และ end-to-end UAT บน exact signed artifact
- research ethics/protocol/instrument approval, trusted issuer/time และ explicit enrollment authority
- real Voice API token + OmniVoice GPU smoke

สถานะ: engineering source พร้อมเข้าสู่ signed packaging และ bounded device verification;
ยังไม่ใช่ production rollout authorization หรือหลักฐานประสิทธิผลการวิจัย
