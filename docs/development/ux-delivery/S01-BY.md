# S01-BY — native actual-bootstrap Today resume

Canonical checkout: `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest`; branch `codex/ux-current-after-s01-bc`; base HEAD `c3a69c5fea4a5a9f08be06e2ea5717a937edc34d`.
Writer `01a0e64a-8c87-7721-a044-cfec69e10d0d`; controller `01a0ce9e-23a6-7931-88e6-6390da748f39`.

## ผลที่พิสูจน์

**PASS_NATIVE_SYNTHETIC_ACTUAL_BOOTSTRAP_TODAY_RESUME** บน physical V2041 / API33 / serial `9582188822004C6`.
ติดตั้งแพ็กเกจใหม่ `com.lexiquest.app.nativeTodayBy` ครั้งเดียวด้วย `adb install -t` ไม่มี `-r`.
PID `11195` → ไม่พบ process → `11936`. force-stop เฉพาะ BY หนึ่งครั้ง; metadata version/install/update ของ production, ariTest, nativeBaselineBm และ nativeResumeBw ตรงกันก่อน–หลัง.

- N01: actual `AppBootstrap` + `MyApp` + Today → ทำต่อ → canonical `QuizScreen` ของ ordinary session ที่ admitted ไว้. NavigationBar ใต้ quiz เลือก Learning index 1.
- N02: ตอบผ่าน in-app integration_test บน QuizScreen; มี committed feedback ถูกต้องที่ index 0 / phase answered.
- N03: dispose UI/dependencies, ปิด SQLite และ flush seal ก่อนหยุด process.
- N04: process ใหม่เปิด sandbox/guest marker/SQLite เดิมแบบ verify-only, compose AppBootstrap ใหม่ แล้วผ่าน Today → ทำต่อจริงกลับมายัง session/plan/feedback เดิม. ไม่มีการ seed/admit/reseal ใน verify.
- Digest ครอบคลุมทุกแถวของทั้ง 58 ตารางตรงกันหลัง bootstrap และหลัง navigation/replay. learning_sessions=1, answer_attempts=1, events_v2=17, points_ledger_entries=1, reward_transactions=1, achievement_unlocks=2, srs_states=0. ไม่มี evidence/score/SRS/reward ซ้ำ.
- local_owners=2 คือ active synthetic owner กับ inactive `packaged:lexiquest-starter-v1` จาก bootstrap; ไม่ใช่ guest ใหม่หลัง restart. คำศัพท์ 14 คำคือ synthetic 2 + packaged starter 12; quiz ใช้ synthetic category เท่านั้น.
- Research rows/external HTTP operations=0. Ordinary outbox 4 แถวเป็น attempt, achievement 2 และ coin reward เดิมทั้งหมด; ตรวจ identity/owner/pending/attempt_count=0 ไม่มี lease/ack/upload. `outboxRows=0` หมายถึงแถวนอก allowlist หรือมีความพยายามส่ง.

Owner: `local:synthetic-by-synthetic-01-owner`.
Session: `session:7cdeb86d-9ec1-4a67-adee-042c0400b515`.

| Pin | SHA256 |
| --- | --- |
| Built APK และ installed base.apk | `1b24b3225fd19f3467b465c3f338d33381c63e9d95692b6d666cafa504355f18` |
| ทุกแถวของ 58 ตาราง / sealed-rows bytes | `5afbbb84b6e56dd9e4da20ee74723bbc3fa91b85c5481cab3c4b6ec3c958afb1` |
| Frozen plan | `5f0f67ba9f12370b77650c63044ecfd86b37bafc22e3230ebb94a39b1a26cd64` |
| Progress | `8ca9e41903263b7b1c86a06aef66608531850965fe1f424034dad456234f51e4` |

APK อยู่ที่ `build/native-today/S01-BY/gradle/app/outputs/apk/debug/app-debug.apk`. เก็บแพ็กเกจและ synthetic evidence บนเครื่องไว้ ห้าม reinstall/clear/uninstall/reseed.

## Source defect และการแก้

พบ S01-BY-01: ordinary recovery ครอบ canonical answer ด้วย outer transaction แต่ notification เรียก reconciliation ภายใน Drift transaction zone ก่อน commit. HOST RED หลัง drain พบ coin grant 0 แทน 1; coin ถูกสร้างเมื่อ bootstrap รอบถัดไป จึงไม่ผ่าน exact DB seal.

แก้เฉพาะ `LearningUseCases` และ `OrdinaryMeaningRecovery`: buffer answer/checkpoint mutation notifications และ side-effect scheduling จน outer ordinary transaction commit แล้วจึงส่งจาก caller zone. Rollback ทิ้งคิว; nested scope รวมคิวเมื่อสำเร็จเท่านั้น. เพิ่ม RED ของ caught nested rollback (expected 0 notifications / actual 4) ก่อนแก้. ไม่มี schema/migration หรือ scoring/SRS/reward authority ใหม่.

Test Today เดิม 4 กรณีอ่าน snapshot ระหว่าง reconciliation ที่เริ่มทำงานได้จริงหลังแก้ จึงเพิ่มการ drain คิวเดิมก่อน baseline snapshot โดยคง equality ของทุกแถวและ acceptance assertions เดิมทั้งหมด. ไม่สั่ง replay เพิ่มเพื่อทำให้ test ผ่าน.

Harness ใช้ existing dependency injection: local SQLite/guest, no-login/no-cloud/AI/voice และ HTTP client ที่ปฏิเสธทุก operation. Packaged-only offline verifier ใช้ implementation จริงกับ synthetic clock คงที่ เพื่อไม่ให้ timestamp การ reverify cache เปลี่ยน seal; ไม่แก้ production cache behavior. dailyContinuity เปิดเฉพาะ preview ที่ฉีดเข้า harness และตรวจ fieldDefaults ยัง hidden ทั้งสอง native phases.

## Verification / isolation

- Final HOST targeted: **320 PASS / 0 failed**, 13 test files รวม Today recovery, ordinary checkpoint, learning/reconciler, navigation, QuizScreen และ BW fixture เดิม; runtime ประมาณ 4 นาที 48 วินาที.
- CLI: 23 contract cases, 6 executable stub runner cases และ BY/BW/BM isolation suites ผ่าน. รวมกรณี package collision, APK/source identity, storage/network permission, receipt/digest drift และ process exit.
- Analyzer: 8 touched Dart files ไม่มีปัญหา. Focused diff check ผ่านเมื่อใช้ repository CRLF interpretation (`core.whitespace=cr-at-eol`).
- HOST gate pre/post: `241f05af55353c8bd5c0b7cd557ba3019a57858a1d855d8cf901dec94d06e627`.
- CLI gate pre/post: `4adb3626a3907fdb311f0d887c98c79781e56cb353b50905178aeb0ed0011068`.
- Build debug exit 0; 808 native source pins ไม่เปลี่ยนก่อน–หลัง build/ก่อน install. ตรวจ current source เทียบ HOST closure 1,601 entries และ native closure อีกครั้งแล้วไม่พบ drift. CLI fingerprint บันทึก snapshot ณ gate; เอกสาร publication ภายหลังแยกจาก executable source closure.
- Merged APK ไม่มี uses-permission, provider/service/receiver หรือ VIEW/BROWSABLE deep link; มี activity เดียวและลงทะเบียน plugin เฉพาะ SharedPreferences/integration_test. Optional camera hardware declaration จาก dependency ไม่ได้ให้สิทธิ์กล้อง; ไม่มี media plugin registration. READ_EXTERNAL_STORAGE ที่เคยถูก implied ใน BW ถูกลบที่ debug overlay ของ BY.
- READINESS_PASS มาก่อน install; installed APK hash ตรวจจาก base.apk บนเครื่องจริงตรงกับ build. Kotlin/Gradle/plugin warnings ไม่ได้ถูกอ้างเป็น clean build diagnostics; build สำเร็จ.
- แยก Gradle output ของ BY เพื่อรักษา APK เดิมทั้ง 4 ไฟล์ที่ตำแหน่งเดิมและ hash เดิม. เก็บ receipts/ignored artifacts เดิม ไม่ย้าย/ZIP/cleanup และไม่แตะ checkout อื่น. ตรวจ tracked baseline 5,483 paths และ local-only inventory 5,751 paths; final preservation อยู่ใน validation.

ข้อผิดพลาดระหว่างพัฒนา (identifier/regex ของ harness, async test guard, verifier selector และ lint) ได้วินิจฉัยและแก้ก่อน native install. Failed/InputDrift development runs ไม่ถูกนับเป็น PASS. Source RED receipts เก็บแยกไว้. ไม่รัน full dirty-source release verifier.

## Release boundary

ผล native จำกัดที่ **actual-bootstrap preview Today + committed-feedback resume** ของ ordinary quiz หลัง real process restart. Native draft/pending/close/next/stale-route variants, N05 visual/IME/TalkBack, actual-user/UAT/learning trials และ frozen-source release ยัง NOT_RUN/DEFERRED. ไม่ใช่ production field acceptance หรือหลักฐานผลการเรียน; S01/UX-D01–25 ยังไม่ accepted.

ไม่มี deploy/research activation/enrollment/upload ข้อมูลจริง/external contact. Current-model deterministic fallback; Standard/default requested แต่ effective tier unverified; ไม่มี Jev/billing/login/paid/quota probes หรือการเปลี่ยน USD5 ledger.

Writer RELEASED ผ่าน [immutable checkpoint](evidence/S01-BY-checkpoint.json) พร้อม SHA256; รายละเอียด [validation](evidence/S01-BY-validation.json) และ [native result](evidence/S01-BY-runs/native-1/result.json). Source edits ยังไม่ commit; base HEAD + current closure/hash pins ระบุ source ที่ตรวจแล้ว. ไม่มี host test/build ค้าง; native verify process อาจคงอยู่ แต่ UI ถูก dispose และ DB ปิดแล้ว.

ส่งคืน controller `01a0ce9e-23a6-7931-88e6-6390da748f39` เพื่อตรวจ receipt และเลือกงานต่อ ไม่ dispatch successor และหยุดเขียนหลัง publication.
