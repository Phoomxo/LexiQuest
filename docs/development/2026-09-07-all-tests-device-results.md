# ผลทดสอบเพิ่มเติมบน vivo และ local backends — 2026-09-07

## Remediation in progress — after the baseline below

ผู้ใช้อนุมัติให้ดำเนินการตามลำดับอย่างต่อเนื่อง ดู `2026-09-07-device-remediation-plan.md`.

- Media: reproduced on vivo in `focused-suite-20260907T144902809Z`. Feature and Shadowing mode were present; the forced 1280×900 / DPR1 view placed the drag outside the native phone view, and the scroll position never changed. Removed only the artificial viewport override, retaining every business assertion. The original fixture then passed on vivo in `build/verification/remediation-20260907/media-viewport-v1-run-20260907T145632349Z/response.json` (1 meaningful case, driver0, no reporter errors, original APK restored/hash verified). Fresh host revalidation also passed in `remediation-media-20260907T150556335Z`.
- Retry: the focused combined run reproduced the failure and attributed the asynchronous catalog error to the already-finished media test. The unchanged configured-disposition test file passed when launched in an independent app process: `retry-isolated-v1-run-20260907T145831847Z`, all 7 widget results successful, reporter `01:20 +28` including setUpAll/sentinel/tearDownAll, driver0, no late/reporter errors, original restored. Exact saved-session identity and no-extra-answer assertions passed. No Pair production logic changed; the combined live-binding result remains a failed harness run, not a passing unattended suite.
- Performance: split timing diagnosis `performance-suite-20260907T145317226Z` showed p95 32.086 ms, with expensive **build** frames. Moved Map/List state into the journey section so switching no longer rebuilds status/companion/mission. Keep-alive preserves the selection when the section leaves the viewport. The unchanged original profile fixture then **passed** in `performance-local-build-v1-run-20260907T150416234Z`: actual view 1080×2292/DPR2.75, 20 transitions/120 frames, p95 **14.265 ms** against unchanged **16.7 ms** budget; max24.267 ms, no >100 ms frames/tasks, all authority and idle checks true. Driver0, original restored.
- Regression: the initial focused Adventure selection passed 56 cases. Full regression on final production code, including keep-alive, then **passed all 4,852 named cases**, zero failures/skips/error events, reporter429.576s / gate434.107s. Evidence: `remediation-full-20260907T151425075Z`, `remediation-full-final.summary.json` and `.inventory.json`. The 86 inherited Drift warnings and 10 expected generator negative-fixture output lines were retained; no unexpected parse lines. The existing `release-excluded` tag remains explicitly excluded (three native-model cases already passed on vivo; one owner-excluded iOS case). Fresh analysis found no issues; the generated plan `--check` also passed after regression. Current-source serial regression was not repeated for this UI/fixture correction.
- Human phase: user confirmed readiness. Local QA APK `manual-uat-v2-debug.apk`, SHA256 `51274d60254f43ab778c06c87d77439c6bf2f2b9f2e90a49575d2bd86f5a09d9`, is now installed and visibly open on vivo; setup/launcher evidence is in `manual-uat-v2-manual-20260907T152251573Z`. Production media gateways and local-only native TTS use sample vocabulary; cloud sync/research are off, DB/support files are isolated, Pair data is in memory. User hearing confirmation has been requested but is not yet recorded. The original APK will be restored after this interactive phase. This launcher alone does not certify all original entry points, guardian policy, process-death restore or the full UAT-039–050 matrix.

The media edit changes the canonical source fingerprint. New builds use a before/after snapshot of 1,158 current source/config/fixture files under `build/verification/remediation-20260907`; they are not labelled as the frozen baseline below. The first snapshot is `e82af5320233d65a28120653144719e068ebc1d48c7332fb9098db220b353ab6`, base HEAD unchanged. Baseline failures and historical results are retained below.

Later snapshots include the manual fixture and generated plan (1,162 entries). The generated plan was regenerated through its normal generator against checkout HEAD plus the actual working-tree hashes: canonical fingerprint `abc1599cc5c99adc9578b4ec4196d8eec33c74d85f3d2c78d34b2e911e3f9713`. HEAD is the **base checkout**, and the remediation edits are still uncommitted; the old commit does not contain these edits. Each artifact retains its own full source manifest and fingerprint.

## Frozen baseline results

สถานะ ณ 14:19 UTC: รันชุดอัตโนมัติเพิ่มเติมที่พร้อมทดสอบจบแล้ว แต่ **ยังไม่ผ่านทั้งหมด** มี device findings และ performance gate ไม่ผ่าน; manual/external gates ยังระบุแยกไว้

Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch `codex/pair-matching-pm0-pm8`; HEAD `788e90e62b1694c20945734787723c168b6a6ab2`; implementation `1875a61854490e0493cc084bffb705f5d3bd4b0b`; canonical fingerprint `50ddab9318080e5dd7cd4b640cfb63dbbf52fb9613d7d61fa8064a59132d22fc`.

หลักฐานรอบนี้อยู่ใต้ `build/verification/788e90e62b1694c20945734787723c168b6a6ab2/device-20260907/` ทุกผลต้องอ่านร่วมกับข้อจำกัดของ fixture; ไม่รวมผล UAT หรือลายเซ็นที่ยังไม่มี

## ผลที่เสร็จแล้ว

| ชุด | ผล | หลักฐาน/ขอบเขต |
|---|---|---|
| Android core journey | ผ่าน 1 business journey / 23 phases | `device-core-smoke-final.json`, `private-discovery-20260907T131025620Z/`; vivo V2041 Android 13; synthetic DB, fake external services |
| AI API CPU | 76 ผ่าน | `ai_api-pytest.xml`; pinned uv lock, Python 3.11.15 |
| Voice API CPU | 55 ผ่าน / 1 skipped | `voice_api-pytest.xml`; remote Firebase/OmniVoice E2E ต้องมี explicit enable และ test token ที่ยังไม่มี |
| LexiQuest LM CPU | 75 ผ่าน | `lexiquest_lm-pytest.xml`; ไม่ติดตั้ง GPU/train extras |
| Supabase local | ผ่าน | `supabase-policy-result.md`; fresh task-owned database, schema lint, storage policy SQL, security advisors; SQL transaction rollback |
| Real LiteRT model | ผ่าน 3 ข้อบน vivo | `native-suite-20260907T140652976Z/core-fixture-test.log`; checksum-pinned inference, wrong tensor contract rejection, CPU/XNNPACK benchmark |
| Native local-only TTS | ผ่านไทยและอังกฤษ | โค้ด production provider + native plugin; installed offline voices en=9, th=3; playback completion callback ครบทั้งสองภาษา; ยังไม่ใช่คำยืนยันคุณภาพเสียงจากคนฟัง |
| Native camera inventory | ผ่าน | พบกล้อง back/front รวม 2 ตัว; ไม่ใช่การทดสอบ preview/capture หรือ microphone |
| Pair/shell บน vivo | รันครบ / FAIL | `pair-shell-continued-20260907T134434023Z/response.json`; 87 widget result records = 84 success / 3 failure; success 1 กรณีต้องแทรกแซง lifecycle จึงไม่ใช่ unattended pass |
| Media fixture แยกบน host | ผ่าน 1 ข้อ | `device-20260907T140442580Z-media-focused-host-diagnosis.*`; gate 46.318 วินาที |
| Temporary protocol retry แยกบน host | ผ่าน 1 ข้อ | `device-20260907T140528980Z-temporary-protocol-focused-host-diagnosis.*`; gate 11.293 วินาที |
| Adventure physical profile | FAIL: Map/List frame p95 | `performance-suite-20260907T141709578Z/response.json`; actual viewport พร้อม, profile mode, 20 transitions/120 frames; p95 31.946 ms เกิน 16.7 ms |

CPU backend รวม 206 ผ่าน / 1 skipped. ไม่รวมจำนวน host Flutter เดิมหรือ phone tests เข้ามานับซ้ำ

## ขอบเขตของผล device

- Pair/shell device suite จบครบ: 29 Pair test files (ยกเว้น host golden 2 files) และ integration fixtures 2 files บน vivo จริง; reporter สุดท้าย `41:46 +417 -2` รวม hooks/sentinel จึงไม่ใช้เป็นจำนวน business tests ผ่านทั้งหมด ผล widget response มี failure 3 รายการตามด้านล่าง
- Lifecycle fixture ที่สั่ง synthetic paused แล้วรอเฟรม ต้องใช้ HOME/กลับแอปจริงเพื่อให้ live binding เดินต่อ; assertions ผ่านหลังแทรกแซง แต่ไม่นับเป็น unattended pass (`intervention.md`)
- Native suite จบครบ 6 meaningful cases (3 model, 1 camera inventory, 2 Voice) ในประมาณ 12 วินาที; reporter +8 รวม sentinel/tearDownAll; driver0, no reporter/unhandled errors, original APK restored/hash verified true
- Profile performance จบแล้วตามรายละเอียดด้านล่าง ไม่มี Flutter/test process ของงานนี้ค้าง

### ผล profile สุดท้าย

ใช้ unchanged original `adventure_performance_profile_test.dart` กับ bootstrap v2 ที่รอ Android view metrics จริงใน bounded setUpAll ก่อนเริ่ม body; `--no-dds` สำหรับเก็บ timeline โดยยังใช้ authenticated VM service ไม่เปลี่ยน thresholds/assertions หรือ production source

Actual view 1080×2292 px, DPR 2.75 (พื้นที่ view ต่างจาก panel 1080×2408 เพราะ system insets). ทุกชุดวัดมี 20 samples, Map/List มี 20 transitions/120 frames และ timeline markers ครบ 20. ผล:

| Metric | p95 / ผล | เกณฑ์ | สถานะ |
|---|---|---|---|
| Entry resolution | 0.011 ms | ≤50 ms | ผ่าน |
| Journey projection | 0.106 ms | ≤100 ms | ผ่าน |
| First meaningful render | 86.726 ms | ≤1500 ms | ผ่าน |
| Adventure start overhead | 0.087 ms | ≤150 ms | ผ่าน |
| Map/List frame | **31.946 ms** | **≤16.7 ms** | **ไม่ผ่าน** |
| Max frame / long frames | 33.295 ms / 0 | ≤100 ms / 0 | ผ่าน |
| Max synchronous timeline task | 22.845 ms | ≤100 ms | ผ่าน |
| Authority invariants, idle exclusion, actual viewport | true | true | ผ่าน |

`allBudgetsPassed=false`; driver exit1. เป็นผล profile บน vivo จริง ไม่ใช่ host estimate. Learner-pause check ใช้ injected clock 601 วินาทีตาม fixture ไม่ใช่การนั่งรอ idle จริง 5 นาที. ก่อนรอบสุดท้ายตรวจ thermal status0, battery93%, battery dumpsys temperature33.4°C; ไม่มีการเปลี่ยน performance mode เพื่อทำให้ผ่าน

เก็บประวัติสองรอบก่อนหน้าไว้: `performance-suite-20260907T141049461Z` timeline setup failed/DDS; `performance-suite-20260907T141202589Z` เก็บข้อมูลสำเร็จแต่ initial viewport0×0 และ frame p95 31.356ms ไม่ผ่าน. ไม่ลบ/เปลี่ยนผลเหล่านี้เป็น PASS; อ่าน disposition ของแต่ละรอบ

### Model benchmark บน vivo V2041

MobileNet 4,287,874 bytes; SHA256 `d3949e8a3556c79739cb675e0be7476503bcce76938031c6a1048e13e0cb7d8b`; input RGB zeros 224×224, 2 threads, 3 warmups + 10 samples/delegate. Debug harness, real native runtime; ไม่ใช่ accuracy, battery, thermal หรือ production performance certification

| Delegate | Median | p90 | Process peak RSS |
|---|---|---|---|
| CPU | 30.433 ms | 31.475 ms | 417,267,712 bytes |
| XNNPACK | 40.283 ms | 40.727 ms | 416,751,616 bytes |

Original benchmark fixture labels deviceTier as `host-gate`; execution identity for this run is the actual V2041 recorded with APK hash. Do not interpret that fixture label as host execution. Startup cases completed before the driver attached; their exact names, benchmark output and incrementing pass counters were independently verified in PID12662 `core-fixture-test.log`.

## Device findings

1. Media fallback fixture หา Shadowing destination ไม่พบที่ `integration_test/field_trial_media_smoke_test.dart:150` (`Bad state: No element`)
2. Temporary protocol retry ไม่พบ `PairBoardView` หลัง retry ที่ `test/features/learning/pair_matching/pair_configured_disposition_test.dart:325`
3. Async `synthetic temporarily unavailable catalog` จากกรณีที่ 2 ถูกบันทึกย้อนหลังให้ feature-controls test ที่จบแล้ว ไม่สรุปว่าเป็น product defect อิสระข้อที่สาม

ทั้ง media และ temporary protocol case ผ่านบน host เมื่อรันแยกใหม่ แต่ไม่ผ่านในชุดรวมบน vivo จึงยังไม่อาจสรุปว่าปัญหาอยู่ที่ production code หรือ cross-test/live-binding behavior และไม่เปลี่ยนผล device เป็น PASS

ชุดเดิมใช้ observer 25 นาที ซึ่งสั้นกว่าผลรวมของ real 60/120-second cases และ real 10-minute configured-cap case จึงส่งต่อ observer ไปเป็น 60 นาทีโดยคง Android PID9342 เดิม (`observer-handoff.md`) เทสต์ไม่เริ่มใหม่ ผลสุดท้าย sentinel ครบ, driver exit1, คืน original APK/hash verified true และ cleanup แล้ว

## หลักฐานเดิมและข้อจำกัด

ผล host Flutter เดิม 4,852 named tests ผ่านทั้ง default และ serial บน implementation เดิม ตาม `2026-09-07-pair-matching-pm8-local-verification.md`; source ไม่เปลี่ยนในรอบทดสอบนี้ การใช้ผลเดิมระบุว่าเป็นผลเดิม ไม่กล่าวว่าเพิ่งรันใหม่

UAT-039–050, physical TalkBack/Switch Access, การฟังคุณภาพเสียง, สิทธิ์กล้อง/ไมค์และ moderated learner comprehension ยังต้องมีการทดสอบกับคนจริง ไม่แทนด้วย automated semantics หรือข้อมูลสังเคราะห์ กล้อง/ไมค์ของแอปยังไม่ได้รับสิทธิ์บน vivo จากการตรวจครั้งนี้

iOS case ยัง excluded ตาม platform scope; remote Voice E2E ยัง skipped; Research authority/protocol/instruments/consent/rollout และ G4P role sign-offs ยังไม่มี ผล local ไม่ใช่ UAT, production approval หรือ efficacy evidence

ติดตั้ง fixture ด้วย `adb install -r -t` เท่านั้น และคืน original APK หลังแต่ละ run โดยตรวจ SHA256 `632edb07f6882890c98e467871f98da02502c792df9dadbb854b9f40f17872a1` ไม่ uninstall/clear app data ไม่ deploy หรือเปิด Research. Local Supabase ของงานนี้หยุดด้วย `supabase stop --project-id lexiquest-local` แบบเก็บ backup volume แล้ว; ไม่ใช้ --all/--no-backup และไม่หยุด containers โครงการอื่น

## งานคงเหลือ

- ตรวจ/แก้ device media navigation และ temporary protocol retry รวมถึง late async error; ผล isolated host ผ่านไม่หักล้าง device failure
- แก้ Map/List frame p95 ให้ผ่านเกณฑ์เดิม และวัดบนอุปกรณ์อีกครั้งหลังมีการเปลี่ยนแปลงที่เกี่ยวข้อง
- กล้อง preview/capture, microphone/recognition, physical TalkBack/Switch Access, การฟังคุณภาพเสียงและ learner UAT ยังไม่มีผล; คำถาม readiness ของผู้ใช้ยังไม่ได้รับคำตอบ และยังไม่มี camera/mic permissions
- Remote Firebase/OmniVoice E2E ยัง skipped เพราะขาด explicit enable/test token; iOS excluded ตาม scope; external UAT/G4P/research approvals ไม่สร้างแทน

ไม่มีการแก้ production behavior ในงานทดสอบนี้ ไม่อ้างว่าเสร็จพร้อม release. Source identity ตรวจครบ 104 canonical inputs ก่อน/หลังแต่ละ build/gated host check; tracked content diff ยังว่างนอกจากรายงานใหม่ที่ untracked และ inherited generated status เดิม 7 รายการ
