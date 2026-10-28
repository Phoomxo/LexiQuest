# รายงานส่งมอบ R3 P-256 signature verifier

สถานะ: DONE เฉพาะ bounded cryptographic verifier ตาม `research-crypto-resume-brief.md`.
คืน exclusive Flutter/Dart test/analyzer slot ให้ main แล้ว เวลา 2026-09-05 13:32 Asia/Bangkok.
ไม่มี test/analyzer process ของงานนี้ค้างอยู่; ทุกคำสั่งจบและคืน exit code แล้ว.

## แหล่งงานและขอบเขต

- Worktree: `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`.
- Branch: `feature/adventure-research`; HEAD: `6968ce97ff9b383e244b17b77cf0ed0f61eaaf3d`.
- อ่าน brief, AGENTS.md ฉบับ recovery rules, implementation plan และ checkpoint/progress ปัจจุบันก่อนแก้ไข.
- ใช้ TDD, systematic-debugging และ verification-before-completion: ยืนยัน RED เดิม, ตรวจ source ของ dependency, แก้สาเหตุ แล้วตรวจ GREEN/diff.
- แก้เฉพาะ `lib/features/research/data/research_p256_signature_verifier.dart` และสร้างรายงานนี้.
- `test/features/research/research_p256_signature_verifier_test.dart` ไม่ได้แก้ไข: คงทั้ง 76 tests และ assertions เดิม.
- ไม่แก้ dependency, interface, runtime gates หรือไฟล์อื่น; ไม่สร้าง task/commit, ไม่รัน pub-get/generator/full suite/repo-wide analyzer/security scanner.

## สาเหตุและการแก้ไข

- เดิมถอด base64 แล้วอ่านเพียง 64 bytes แรก ทำให้ยอมรับ signature ที่มี bytes ต่อท้าย; decoder ยังยอมรับ alternate alphabet/escaped padding บางรูปแบบ และโยน FormatException/RangeError สำหรับ input อื่น.
- จำกัด signature ที่ 88 ตัวอักษรก่อนถอดรหัส; ต้องได้ raw `r||s` 64 bytes และ `base64Encode(decoded) == original` เท่านั้น.
- คง immutable snapshot ของ issuer allowlist และ lookup แบบ exact; key ต้องยาว 130 hex characters เริ่มด้วย `04`, รองรับ hex ตัวเล็ก/ใหญ่.
- ตรวจ source ของ PointyCastle 4.0.0 ที่ติดตั้ง: `lib/ecc/ecc_base.dart` ยอมรับ uncompressed/hybrid โดยไม่ตรวจ curve membership; `lib/ecc/ecc_fp.dart` ปฏิเสธ coordinates >= field prime แต่ไม่ได้ตรวจสมการเส้นโค้งใน createPoint.
- ปฏิเสธ infinity และ off-curve ก่อนส่งให้ signer โดยตรวจ `y² = x(x²+a)+b` ด้วย field operations ของ PointyCastle; P-256 มี cofactor 1. ไม่สร้าง signing/verification algorithm หรือ curve constants ขึ้นเอง.
- ตรวจ `1 <= r,s < n` และใช้ `ECDSASigner(SHA256Digest())` ของ dependency เดิมกับ UTF-8 bytes ของ payload โดยสร้าง signer ใหม่ต่อการเรียก.
- Dart UTF-8 encoder แทน unpaired UTF-16 surrogate ด้วย U+FFFD; ตรวจ UTF-8 round-trip เพื่อปฏิเสธ payload aliases พร้อมคงการยอมรับ literal U+FFFD ที่มีลายเซ็นถูกต้อง.
- แปลง FormatException/ArgumentError จาก parsing และ coordinate validation เป็น `false`; key ที่เสียไม่ทำให้ issuer อื่นใช้ไม่ได้.

## หลักฐาน RED / GREEN และ analyzer

รันทุกคำสั่งจาก worktree ข้างต้น โดย serialize Flutter/Dart commands.

1. RED ก่อนแก้ไข:
   `flutter test --no-pub test/features/research/research_p256_signature_verifier_test.dart --reporter expanded`
   Exit 1: **40 passed / 36 failed**. มีทั้ง unexpected true ของ noncanonical inputs/Unicode aliases และข้อผิดพลาด parsing ที่หลุดออกจาก verify; ตรงกับ checkpoint เดิม.
2. GREEN หลังแก้ implementation ด้วย apply_patch: คำสั่ง test เดิม, exit 0, **76 passed / 0 failed**.
3. `dart format --output=none --set-exit-if-changed lib/features/research/data/research_p256_signature_verifier.dart`
   Exit 1: พบเฉพาะ constructor formatting ที่ต้องจัดรูปแบบ; คำสั่งนี้ไม่เขียนไฟล์และ analyzer ที่ต่อเงื่อนไขไว้ยังไม่ได้รัน.
4. `dart format lib/features/research/data/research_p256_signature_verifier.dart`
   Exit 0: จัดรูปแบบ production file เพียงไฟล์เดียว.
5. `dart analyze lib/features/research/data/research_p256_signature_verifier.dart test/features/research/research_p256_signature_verifier_test.dart`
   Exit 0: **No issues found!** บน source หลังจัดรูปแบบ.
6. Final GREEN หลังจัดรูปแบบ: รันคำสั่ง test ในข้อ 1 ซ้ำ, exit 0, **76 passed / 0 failed**.
7. ตรวจ final production diff ทั้ง 85 บรรทัดด้วย `git diff --no-index -- NUL lib/features/research/data/research_p256_signature_verifier.dart` เพราะไฟล์นี้เป็น untracked อยู่ก่อนรับงาน. Exit 1 หมายถึงมี diff; Git แจ้งเรื่อง LF/CRLF ตาม configuration โดยไม่มีการเขียนไฟล์จากคำสั่งนี้.

## Source fingerprints (SHA-256)

- Production ก่อนแก้: `9C5CA56A5C0BD191B88A98CFAF0E2964D3077C32CEA70FDA3D86C565EC4206A4`.
- Production หลัง final verification: `0AAC54F46CB71EC62DC5226844D0653394C445CB1A374C7251C0DC6F282E7E23`.
- Test ก่อน/หลังตรงกัน: `83AD7273C117ADEBCF22D46298E91F6894D1A54A7B29F6E057BE2ABBB7FA5381`.

## Self-review และข้อจำกัด

- Interface/constructor contract เดิมยังอยู่; empty/unknown/wrong issuer, mutable caller map, payload/signature changes, scalar boundaries, SEC1 formats/coordinates และ malformed Unicode ครอบคลุมโดยชุดทดสอบเดิมที่ผ่านครบ.
- Known-answer RFC 6979 vectors และ signed UTF-8 fixtures เดิมผ่านจริง; ไม่ได้สร้าง private key หรือกล่าวอ้างว่า rerun การตรวจ .NET ของผู้สร้าง fixtures ในรอบนี้.
- Canonical base64 เป็นข้อกำหนดการขนส่ง; ยังรับ standard ECDSA high-S signatures ตาม vectors เดิม ไม่มี low-S policy เพิ่มเติม.
- Verifier ตรวจลายเซ็นของ canonical payload ที่ caller ส่งมา; consent/revision/expiry/revocation/protocol pins และ runtime/upload integration เป็นหน้าที่ส่วนอื่นตาม interface เดิม.
- ไม่พบปัญหาค้างในขอบเขตนี้. ผลนี้เป็น focused component verification บน Flutter VM; ไม่ใช่ full Research completion, web/device/build/emulator/UAT evidence หรือสิทธิ์เปิด enrollment/production rollout.
- ขั้นตอนถัดไปของ main: อ่านรายงานและทบทวน production diff/fingerprints แล้วใช้ test slot สำหรับ integration งาน Research ที่เหลือตามแผน.
