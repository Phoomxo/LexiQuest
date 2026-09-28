# S01-BW — isolated native ordinary meaning resume

Canonical checkout: `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest`; branch `codex/ux-current-after-s01-bc`; HEAD `4e70a26b0bf3c44c269bbcbaf9d6d37a273b4dd1`.
Writer `01a0e601-db27-7ea2-8d77-a84f4be685a4`; controller `01a0ce9e-23a6-7931-88e6-6390da748f39`.

## ผลที่พิสูจน์

**PASS_NATIVE_SYNTHETIC_FEEDBACK_RESUME** บน physical V2041 / Android API33 / serial `9582188822004C6`. ติดตั้ง debug package ใหม่ `com.lexiquest.app.nativeResumeBw` ครั้งเดียว ไม่มี `-r`, clear, uninstall หรือ reinstall. แพ็กเกจ production, ariTest และ nativeBaselineBm มี version/install/update metadata เดิมก่อน–หลัง และไม่มี mutation command ไปยังแพ็กเกจเหล่านั้น.

BW/N01 canonical ordinary `startQuiz` → BW/N02 ตอบผ่าน QuizScreen และบันทึก committed feedback → BW/N03 dispose widgets, ปิด SQLite และ flush seal → force-stop → BW/N04 เปิด SQLite เดิมแบบ verify-only และคืน QuizScreen/feedback เดิม. Verify ไม่เรียก seed, ไม่สร้าง owner/session ใหม่ และไม่เขียน seal ใหม่. PID `30948` → ว่าง → `31845`.

- owner/session เดิม, frozen plan/progress digest เดิม, index 0 / phase `answered`, selected correct option และ feedback ถูกคืนจริงด้วย canonical recovery/replay.
- Digest ครอบคลุมข้อมูลทุกแถวของทั้ง 58 ตารางก่อน–หลังเท่ากัน: learning_sessions=1, answer_attempts=1, events_v2=7, points_ledger_entries=1, achievement_unlocks=2; SRS/reward_transactions=0 เดิม. ไม่เพิ่ม evidence/score/SRS/reward ซ้ำในกรณีนี้.
- Research rows และ external-call counter=0. Ordinary local outbox 3 แถว (attempt 1, achievement 2) ถูกเก็บไว้และตรวจ exact identity/owner/pending/attempt_count=0; `outboxRows=0` ใน receipt หมายถึงแถวนอก allowlist หรือมีความพยายามส่ง ไม่ใช่ลบ ordinary outbox ให้เหลือศูนย์.

APK SHA256 ทั้งไฟล์ build และ installed base.apk จริง:
`e271910a2f24c63e127286af7375682411341d00f1b1df474868ae4588e205d4`

Sealed fixture digest:
`56ee5fdae39eaf555a90ae49eef017cec9f3e4dde1854fbd926a372c9407f767`

Plan digest: `fa6b2426b9b3b8d3bd7634ed9d73fecd141c85bdd6d940f6dd435953d57ef68c`.
Progress digest: `8a08585cc8290fba60316a496969d39b7e4328403a05e0724aa48208132fd1a2`.

## Isolation และ source

ใช้ BM เป็นแบบอย่าง แต่แยก fixture/cases/entrypoint/runner/contract/Android manifest/activity ของ BW. Gradle เพิ่ม `nativeResumeTest=true` แบบ debug-only และห้ามใช้ร่วมกับ BM/Ari identity. ไม่แก้ `lib/`, owner/scoring/SRS/reward authority, schema/routes/deep links หรือ production feature gates. dailyContinuity field ยังคง hidden. คง BD–BV และ generated/evidence เดิม.

Merged APK ตรวจจริง: debug ID ตรง, activity เดียว, provider/service/receiver=0, ไม่มี INTERNET/ACCESS_NETWORK_STATE/camera/audio/notification/boot permissions หรือ VIEW/BROWSABLE deep links. Activity ลงทะเบียนเฉพาะ SharedPreferences และ integration_test; ไม่เรียก generated plugin registration. READ_EXTERNAL_STORAGE ที่ merger เติมโดย implication ยังคง `granted=false`; harness ไม่ลงทะเบียน plugin หรืออ่าน external storage. Dart HTTP construction ถูกปฏิเสธและนับความพยายาม.

มีเฉพาะ local synthetic owner/category/words และ guest marker ใน private sandbox. เป็น isolated canonical Learning/QuizScreen composition ไม่ใช่ full production bootstrap หรือการตรวจ native Today navigation. ไม่มี account/login/provider/research/network/UI automation ภายนอก, adb input/tap/screenshot/logcat, VM/browser/helper หรือข้อมูลผู้ใช้จริง.

## Verification

- HOST: 11 targeted tests PASS (BW fixture 2 + actual-bootstrap Today resume contract 9). BW ทดสอบ disk close/reopen, exact feedback, ทุกตารางไม่เปลี่ยน และปฏิเสธ absent seed/path traversal/non-Android sandbox/reseed. ผล BV 283 เป็นหลักฐานเดิม ไม่ได้นับเป็นการรันทดสอบ BW ใหม่.
- CLI: 23 contract cases + 5 executable runner stub cases + 1 isolation source check PASS. Negative test พบ runner ยอมรับ changed plan digest ก่อนแก้; ปัจจุบันปฏิเสธ fixture/plan/progress/owner/session mismatch.
- Analyzer 4 ไฟล์ใหม่ clean. Targeted verify-scope HOST และ CLI มี pre/post fingerprints ตรงกัน. Build debug exit0; source manifest ก่อน–หลัง build ไม่มี drift; READINESS_PASS มาก่อน install.
- Native seed/verify receipts PASS, ปิด DB ก่อน receipt; installed APK hash เท่ากับ build hash. คง package/synthetic evidence ไว้; verify process อาจยังอยู่หลังจบ แต่ DB ปิดแล้ว.
- ตรวจ final scope/diff และ pins; ไม่มี full dirty-source release verifier หรือ full regression.

Recovery ที่ทำ: ค้น path README ที่ถูกต้อง; แก้ synthetic owner prefix ให้ตรง canonical `local:`; ตรวจและรักษา ordinary answer/achievement outbox; แก้ async test guard และ lint braces; แก้ verify-scope selector ให้ใช้ชื่อ CLI test ตาม schema; installed APK path มี `~~` จึงตรวจรูปแบบ path ที่สังเกตจริงก่อน hash. ไม่ retry installation. Build มี KGP/SDK XML warnings แต่สำเร็จ.

## ขอบเขตที่ยังไม่ผ่านและ handoff

Native PASS นี้ครอบคลุม admission + committed-feedback resume หลัง force-stop ของแพ็กเกจแยกเท่านั้น. Draft/pending/close/next/stale-route cases มี HOST scope ตาม BV; ไม่ยกระดับทั้งหมดเป็น native. Native Today full bootstrap, N05 visual/IME/TalkBack, UAT/actual-user/learning trials และ frozen-source release acceptance ยัง NOT_RUN/DEFERRED. S01 และ UX-D01–25 ยังไม่ accepted. ไม่มี deploy, research activation, enrollment หรือ external contact.

Writer RELEASED ผ่าน [immutable checkpoint](evidence/S01-BW-checkpoint.json); [validation](evidence/S01-BW-validation.json) และ [native result](evidence/S01-BW-runs/native-1/result.json) แยก HOST/native/user/release ชัดเจน. ไม่ dispatch successor และหยุดเขียนหลังเผยแพร่ receipt. Controller ตรวจหลักฐานแล้วเลือกงานถัดไป; ห้าม reinstall/clear/uninstall แพ็กเกจ BW หรือรัน seed ซ้ำ.

Jev ไม่มี fresh billing signal: current-model deterministic fallback, Standard/default requested แต่ runtime tier ไม่ได้รับการพิสูจน์; ไม่มี Fast/probe/login/paid fallback/quota reset และไม่แก้ ledger USD5.
