# S01-BZ — native pending acknowledgement and next-question recovery

Canonical checkout: `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest`; branch `codex/ux-current-after-s01-bc`; base HEAD `c3a69c5fea4a5a9f08be06e2ea5717a937edc34d`.
Writer `01a0e679-4065-7040-8684-0621d889d7bb`; controller `01a0ce9e-23a6-7931-88e6-6390da748f39`.

## ผลที่พิสูจน์

**PASS_NATIVE_SYNTHETIC_PENDING_AND_NEXT_OS_RESTART** บน physical V2041 / API33 / serial `9582188822004C6`.
ติดตั้งแพ็กเกจใหม่ `com.lexiquest.app.nativeRecoveryBz` ครั้งเดียวด้วย `adb install -t` ไม่มี `-r` หลัง READINESS_PASS. หยุดเฉพาะ BZ สองครั้ง: PID **14187 → absent → 14483 → absent → 14834**. ใช้ in-app integration_test เท่านั้น; ไม่มี adb input/tap/screenshot/logcat, VM/browser/native-UI helper.

- **seed / N01–N03:** actual AppBootstrap แบบ synthetic offline สร้าง canonical ordinary session สองข้อและ frozen plan. ใช้ existing MeaningQuizModeAdapter injection รอ `operation()` จบ outer transaction ก่อนตรวจ committed result และอ่าน answer ผ่าน SQLite connection อีกตัวแบบ read-only. จากนั้นจึงโยน lost-acknowledgement error; durable progress ยังเป็น pending, มี answer จริงหนึ่งรายการ. Dispose controller, drain canonical reconciliation, ปิด DB และ flush immutable seal ก่อน process stop.
- **pending / N04,N06:** process ใหม่เปิด DB/guest เดิมแบบ verify-only; seal ทุกแถวทั้ง 58 ตารางตรงกับ seed ก่อน UI. actual MyApp → Today → ทำต่อ เปิด QuizScreen/session/owner/plan เดิม; navigation ไม่เปลี่ยน DB. กด retry ผ่าน widget instrumentation ได้ feedback คำตอบเดิม; frozen operation JSON และ answer row ทุก field ตรงกัน. Retry เพิ่มเฉพาะ checkpoint หนึ่ง event แล้วกด Next เพิ่ม checkpoint อีกหนึ่ง event; index 1 / awaitingAnswer, ไม่มี feedback เก่าค้าง. ปิด DB และสร้าง next seal แยกโดยไม่แก้ seed seal.
- **next / N07:** restart รอบสองกลับผ่าน actual AppBootstrap → Today → ทำต่อ. Index 1/prompt/options/frozen plan/session เดิมและทุกแถว 58 ตารางตรงกับ next seal ก่อนและหลัง navigation. ไม่มี seed/admission/reseal ในช่วงนี้.

ตลอดสามช่วง: learning_sessions=1, answer_attempts=1, points_ledger_entries=1, reward_transactions=1, achievement_unlocks=2, srs_states=0. `events_v2` เป็น **16 → 17 → 18 → 18** ตาม pending seed, answer acknowledgement, next checkpoint และ final restore; non-checkpoint events และอีก 57 ตารางมี digest เดิมทั้งหมด. ตรวจ checkpoint เดิมทุก field ยังอยู่และเพิ่มได้ครั้งละหนึ่งเท่านั้น จึงไม่ได้ใช้ whole-DB equality ข้ามการกระทำที่ตั้งใจเขียน journal.

local_owners=2 คือ active synthetic owner กับ inactive packaged starter; vocabulary_words=14 คือ synthetic 2 + packaged starter 12. Ordinary outbox 4 รายการเดิมมี identity/owner ตรง, pending/attempt_count=0, ไม่มี lease/ack/upload. `outboxRows=0` คือไม่มีแถวนอก allowlist หรือมีความพยายามส่ง. Research rows และ external HTTP operations=0. dailyContinuity เปิดเฉพาะ harness preview; fieldDefaults ยัง hidden ทุกช่วง.

Owner `local:synthetic-bz-synthetic-01-owner`; session `session:568de6da-0560-4225-92ca-9bd7b394290f`.

| Pin | SHA256 |
| --- | --- |
| Built APK / installed base.apk | `97ad0d35438a334541f9b90c18229b0acdddc8d1473d78106ecc0d9830858b18` |
| Pending whole-DB rows | `0f4f9611d457e3dc56ea31708ea535087c6a4fe267c6368bec2cd97dfa73bd8a` |
| Next whole-DB rows | `da8bb3d5ba9854e3faa1dcf28d3753e00850f72be19be77319c4e45048853a60` |
| Frozen plan | `a6c2a068ddb928ff44125617d15bfb56b478bd01694b9d01f6c99ad64affb646` |
| Pending progress | `96f78e9d1917f9b975141d92010abd076d1eeaa918739afde2dd205bbe9c29cf` |
| Next progress | `1e20319e58d776862aae748ec3005becb8692fad8624f251a52d56e3a19d5191` |
| Final on-device SQLite bytes | `ec7ae68f0cefa383e9f4700a55a6b79492fcd941fc7ef88f66765c9291a928e0` |

APK: `build/native-recovery/S01-BZ/gradle/app/outputs/apk/debug/app-debug.apk`. Installed copy/hash, device seal hashes and metadata: `evidence/S01-BZ-runs/device-final.json`. เก็บทั้งหกแพ็กเกจไว้; ห้าม reinstall/clear/uninstall/reseed.

## Verification และ preservation

- Final `verify-scope -Level Targeted -Area Runtime`: **51 HOST tests PASS**, 5 files รวม BZ/BY/BW fixtures, actual Today recovery contract และ ordinary checkpoint/100-item capacity. Flutter runtime 4m33s. Gate pre/post `3aeddf3dc6dfdf21634eed31a9eb76d1da04a08763cce36ffe4c5019d6b07531` ตรงกัน.
- Final CLI gate: 23 BZ multi-phase contract cases, 6 executable stub runner cases, isolation suites BZ/BY/BW/BM PASS. Gate pre/post ทุก command `f0b9195b3faca3ed7a9f77ec3cd3905d5a95dbc8618413c4466376a3a954337d` ตรงกัน. Stub tests ไม่ถูกนับเป็น native acceptance.
- Analyzer ของ Dart ใหม่ 4 files: no issues. Final diff whitespace check ใช้ repository CRLF interpretation.
- Build debug exit 0 / 1m56s; มี Kotlin/plugin/deprecation warnings ตาม log. Source closure native 815, host 1,610 และ CLI 5,530 entries ตรวจหลัง native ก่อน publication: mismatch 0. CLI closure รวมเอกสาร; report/state/README publication ภายหลังแยกจาก executable source verification.
- Merged APK ไม่มี uses-permission, provider/service/receiver หรือ VIEW/BROWSABLE; มี activity เดียว. ลงทะเบียนเฉพาะ SharedPreferences/integration_test. Package identity/debug-only/source/APK collision checks ผ่านก่อนติดตั้ง; pulled installed base.apk hash ตรง build.
- APK เดิม 5 ไฟล์ยังอยู่ที่เดิมและ hash เดิม; metadata version/install/update ของ production, ariTest, BM, BW, BY ตรงก่อน–หลัง. Baseline 5,518 paths ตรวจ preservation; BZ เปลี่ยนไฟล์เดิมเฉพาะ Gradle สองไฟล์กับ README/state. Dirty BY production/source/evidence รักษาเดิมทั้งหมด; ไม่มี checkout อื่น/ZIP/cleanup.
- ไม่พบ production source defect ในขอบเขตนี้; ไม่มีการแก้ `lib`, schema, authority, scoring, SRS, rewards, routes หรือ gates. เพิ่มเฉพาะ BZ debug harness/runner/tests กับ Gradle isolation. No-login/no-AI/no-network baseline และ research default-off คงเดิม.

Development failures ไม่ใช่ PASS: missing harness contract/isolation RED; async test guard conflict; SQL `ORDER BY` ถูกแทนชื่อผิดตอนสร้าง fixture; Map identity matcher เปลี่ยนเป็น deep field equality; PowerShell stub string ติด provider metadata แก้เป็น trimmed raw string; analyzer 3 infos แก้ก่อน final. Verifier selector/path และ baseline script reserved variable errors วินิจฉัยและแก้ก่อน reuse. ไม่มี failing assertion ถูกลบ/skip หรือลด acceptance. รายละเอียด logs และ final command receipts เก็บไว้ใน runs และ `build/S01-BZ`; ไม่มี reinstall/reseed เพื่อแก้ native failure และ native run แรกผ่าน.

## Release boundary และ handoff

Native acceptance จำกัด **committed pending-answer lost acknowledgement + next-question restore** ใน synthetic preview หลัง real Android process restart. ไม่ใช่ crash ระหว่าง transaction หรือ power-loss test; seed ปิด DB/flush ก่อน force-stop ตาม harness. Terminal close/completion acknowledgement, draft, stale-route บนเครื่องจริง, N05 visual/IME/TalkBack **NOT_RUN**. Actual-user/UAT/learning trials **DEFERRED**; frozen-source full release **NOT_RUN**. S01/UX-D01–25 และ field acceptance ไม่ถูกปิด.

ไม่มี deploy/research activation/enrollment/upload ข้อมูลจริง/external contact. Current-model deterministic fallback; Standard/default requested, effective tier unverified; ไม่มี Jev/Fast/probe/login/paid/reset quota และ USD5 ledger ไม่เปลี่ยน.

Writer RELEASED ผ่าน [immutable receipt](evidence/S01-BZ-checkpoint.json) และ [validation](evidence/S01-BZ-validation.json). ไม่มี test/build/runner process ค้าง; native final process อาจคงอยู่แต่ UI disposed และ DB ปิดแล้ว. Source ยังไม่ commit; base HEAD + closures ระบุ bytes ที่ตรวจ. ส่งคืน controller `01a0ce9e-23a6-7931-88e6-6390da748f39` ทาง final เพื่อตรวจ receipt; ไม่ dispatch successor และหยุดเขียนหลัง release. Next executable step ของ controller คือ read-only ตรวจ receipt/hash/preservation และเลือกช่องว่างที่ยัง NOT_RUN โดยรักษาแพ็กเกจเดิมทั้งหมด.
