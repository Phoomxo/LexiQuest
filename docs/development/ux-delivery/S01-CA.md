# S01-CA — native terminal close acknowledgement recovery

Canonical checkout: `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest`; branch `codex/ux-current-after-s01-bc`; base HEAD `c3a69c5fea4a5a9f08be06e2ea5717a937edc34d`. Controller: `01a0ce9e-23a6-7931-88e6-6390da748f39`.

## ผลที่พิสูจน์

**PASS_NATIVE_SYNTHETIC_TERMINAL_CLOSE_OS_RESTART** บน physical V2041/API33 serial `9582188822004C6`. แพ็กเกจ debug ใหม่ `com.lexiquest.app.nativeTerminalCa` ติดตั้งครั้งเดียวหลัง readiness. หยุดเฉพาะ CA: PID **16682 → absent → 17285 → absent → 17536**. ใช้ in-app integration_test instrumentation; ไม่มี adb UI tap/input/screenshot/logcat, browser/VM/helper bypass.

- **seed:** actual AppBootstrap ใน synthetic offline preview สร้าง canonical ordinary meaning session หนึ่งข้อและ frozen plan. ตอบถูกหนึ่งครั้ง; `close.finish()` สำเร็จหลัง durable transaction แล้ว SQLite read-only connection อีกตัวเห็น `learning_sessions.state=completed`, `ended_at_utc_ms` และ answer row ก่อน harness โยน synthetic lost acknowledgement. Checkpoint อยู่ `closing`, `terminalAcknowledged=false`. ปิด controller/DB และ flush seal ก่อน force-stop.
- **resume:** process ใหม่เปิด owner/DB เดิมแบบ verify-only. ทั้ง 58 ตารางและ seal ตรงก่อน UI. actual MyApp → Today → ทำต่อ เปิด QuizScreen/session/owner/plan เดิม; navigation ไม่เขียน DB. Retry ปิด session ไป ScoreScreen; Today ไม่เสนอ resume อีก. เพิ่ม **หนึ่ง terminal-acknowledgement checkpoint** เท่านั้น.
- **closed:** หลัง force-stop/relaunch รอบสอง actual AppBootstrap/Today ไม่เสนอ session ที่ปิดแล้ว. 58 ตารางและ digest ตรงกับ post-retry seal ทั้งก่อนและหลัง navigation; ไม่มี seed/admission/reseal ในช่วง verify.

Owner `local:synthetic-ca-synthetic-01-owner`; session `session:de68e6ff-b243-4fc6-9656-abf65ff93326`. Whole-row digest **seed `0e6278fe051f8d238705392a6b8af104a22312f94e7bc42cee5e996cfc259706` → resume/closed `d26138e08fbc44f65b5bdf406a9d745ea341ba035d9262bf2de58b5508415888`**. Frozen plan `a8ffe594ca130a716f8d17ada342dfc8166fd5ec6be3b2af4c1c3262f778bd1b`; progress `ca29986a04bbe747055448ae304a6cfa1f3a0fc542c0c6fb795a721119aee7ff` unchanged. `events_v2` 18 → 19 → 19; checkpoint 5 → 6 → 6. Non-checkpoint events and other 57 table digests remain identical across retry. Answer attempts=1, points ledger=1, reward transactions=1, achievement unlocks=4, SRS=0 throughout. Six ordinary local outbox entries retain pending/attempt_count=0 with no lease/ack/upload. Research rows=0; external HTTP calls=0; field dailyContinuity hidden.

APK and installed base.apk SHA256 both `a78a0bb6ae4107bb241a58e1d75d5e47bfedea8677d8bccb2da1c075a824336f`; final on-device SQLite SHA256 `f198779964fd37730973e7d93deb037c4fe451df19c20e885f696458267f697d`. APK: `build/native-terminal/S01-CA/gradle/app/outputs/apk/debug/app-debug.apk`. Device/transition receipts: `evidence/S01-CA-runs/`. Preserve seven installed packages; never reinstall/clear/uninstall/reseed CA or predecessors.

## Verification และ preservation

- Final targeted `verify-scope -Level Targeted -Area Runtime`: **49 HOST tests PASS** across CA/BZ fixture, actual Today recovery and ordinary checkpoint contracts. Gate pre/post fingerprint `70667458625870f6c05d2d2e48aa922fcd942b00cf574fa0ee3a6cd7351ea762` identical. Focused CA host RED from Flutter guarded expectation and then outbox-count mismatch were diagnosed and corrected before final PASS; no assertion skipped or lowered.
- CLI: 23 CA three-phase contract cases, 6 executable stub runner cases, source isolation checks PASS. New Dart 4-file analyzer no issues. Isolated Gradle debug build exit 0. Source closure 827 pinned files unchanged through build, install and final validation. Build generated artifact and installed copy hash match.
- Readiness verified package ID, physical transport/model/API, source manifest and APK, merged manifest with one activity/no uses-permission/provider/service/receiver/VIEW/BROWSABLE, fresh CA package, and protected package metadata. Six prior APK files retain their prior hashes; metadata of production, ariTest, BM, BW, BY and BZ match pre/post. BZ/BY dirty source and evidence remain intact. No production `lib`, schema, scoring, SRS, reward, route, gate or research authority edit in CA; only additive debug harness/tests/Gradle isolation plus CA documentation/state.
- Final exact validation: [S01-CA-validation.json](evidence/S01-CA-validation.json); immutable handoff: [S01-CA-checkpoint.json](evidence/S01-CA-checkpoint.json). Build logs and installed APK copy remain local under `build/S01-CA`.

## Boundary และ handoff

Native acceptance covers **committed terminal close with lost acknowledgement and exact Today recovery** in synthetic preview after actual Android process restart. It does not prove a crash inside transaction or power loss. Native draft, stale-route, N05 visual/IME/TalkBack, actual-user/UAT/learning trial, and frozen-source full release **NOT_RUN/DEFERRED**. S01/UX-D01–25 and field acceptance remain open. No deploy, real research enrollment/upload, external contact, or destructive cleanup. Research remains default-off; no-login/no-AI/no-network harness preserved. Requested GPT-6 Sol medium and Standard/default; effective executor/tier not exposed in receipt, so no token-saving claim.

Writer released after final checkpoint; no successor dispatched. Controller's next executable step is read-only receipt/hash/preservation review, then selection of an outstanding authorized gap. Retain all installed packages and evidence.
