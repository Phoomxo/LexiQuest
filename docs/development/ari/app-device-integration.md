# App/device integration — prelogin checkpoint, 2026-09-21

Accepted base: `7407111bbb3f85ae1bc519dfe8b10ed37e501c05`.
Task `01a0bfbd-9961-7da3-982b-77970bdc7027`; writer retained for the user-authorized device testing continuation.

**Vivo V2041 installation, launch, browser device authorization and native login status passed. Inference remains disabled.** OpenAI confirmed sign-in and Ari confirmed the account connection after the explicit status check. The bridge has no turn/thread/reply route. [Evidence](app-device-integration-evidence.json) and [handoff](app-device-integration-handoff.json) distinguish login from inference.

The user explicitly authorized agent taps using the sole cached account and inspection of consent/settings. The blocked Continue button was caused by the disabled Codex device-code authentication switch. Enabling that switch in web ChatGPT security settings and restarting device authorization resolved it. Developer mode, MFA and the existing native ChatGPT session were not changed. Rapid ADB input omitted a character; paced entry succeeded. No passwords, MFA codes, tokens or device challenge values are recorded in this report. The bridge remains ephemeral with a 15-minute lifetime.

## Execution plan

1. Add an opt-in host around ManagedTutorController/Panel. Fence owner/account,
   network, route, background and disposal; test stale completions and cleanup.
   Keep BYOK, database schema and normal application entry unchanged by default.
2. Pin actual App Server login schema. Build an authenticated loopback-only
   developer bridge with isolated memory-only credentials, bounded cleanup and
   no API-key path. Native debug UI must distinguish login from tutor readiness.
   Do not implement inference unless supported no-tool/quota behavior is established.
3. Run bounded verify-scope tests, focused analysis and local binary prelogin
   smoke. Build and inspect debug APK. Check ADB and install only on identifiable
   user Vivo, preserving installed data. Device absence does not block software.
4. Record evidence by simulated/local binary/physical/prelogin/authenticated;
   commit and push tested software, release writer. Live acceptance remains open
   when device/account or provider prerequisite is missing.

Official sources inspected: [App Server](https://learn.chatgpt.com/docs/app-server)
and [authentication](https://learn.chatgpt.com/docs/auth). Device-code is beta,
requires ChatGPT security setting, and has no browser callback dependency.
`ephemeral` credential storage is process-memory-only. Neither local logout nor
a successful local test proves provider revoke, Free Thailand, hosted distribution,
quota-only billing, V2, E7 or pilot acceptance.

## Delivered and checked

- Host watches canonical local owner/account and durable epoch; late replies
  cannot survive identity changes. Offline recovery does not resend. Route cover,
  background and disposal cancel tutor work; unsent draft survives offline and
  clears on disconnect/owner change. Default app entry and BYOK are unchanged.
- Native device-code UI opens only the fixed OpenAI URL. No auth polling while
  credentials are entered; user explicitly taps the return/status button. Account
  status is boolean-only. Cancel/navigation tombstones late login responses.
- Local bridge: pinned 0.146.0 binary, separate environment/home, `ephemeral`
  credentials, loopback listener, fresh private bearer capability, no CORS,
  no provider payload logging, no API-key fallback. Maximum lifetime 15 minutes;
  disconnect kills its private child. Abrupt device loss can retain the isolated
  session until that deadline; this is not provider revocation.
- Flutter targeted verification: **17 PASS** (14 new + 3 affected panel tests).
  Python bridge: **9 PASS**, including actual loopback HTTP with simulated provider.
  Focused analysis: **no issues**. Real binary: **unauthenticated prelogin PASS**.
  Existing 77 rename, 17 protocol, and unaffected foundation gates reused.
- APK: **debug build / package / signature / entrypoint PASS**. Package
  `com.lexiquest.app.ariTest`, SDK 26–36, v2 Android debug signature; no auth/pairing
  files bundled. SHA-256 `21d82cb6be433bdce41fe78506372be009472cb7928147c98d258077817478db`.
  First build ignored the environment-only Gradle flag; package inspection caught
  it before installation. Explicit project argument fixed the artifact. No APK
  was installed. Inherited Kotlin/deprecation warnings remain build warnings.

Review was performed in this task without subagents. Fixed: draft loss on offline,
cancelled-login child cleanup, native JSON charset handling, and isolated package
build argument. Remaining runtime boundary: owner/account tests use canonical
database changes, not a live Firebase sign-in. The test app uses a separate local
database and does not bootstrap cloud/research services.

## Continue on Vivo

Build (already passed; do not repeat without changed inputs):

```powershell
flutter build apk --debug --target lib/main_ari_test.dart --dart-define=ARI_LOCAL_TEST=true --android-project-arg=ariLocalTest=true --target-platform android-arm64
```

Artifact: `build/app/outputs/flutter-apk/app-debug.apk`. Connect the designated
Vivo using a data-capable USB cable. If ADB says unauthorized, accept its RSA
prompt on the phone. Do not uninstall, clear app data, restart global ADB, or
change device security on the user's behalf. Inspect serial/manufacturer, install
the verified APK with `adb -s <serial> install -r <apk>`, then run:

```powershell
python tool/experiments/ari_app_server/login_bridge.py --binary C:/Users/Phet/AppData/Local/Programs/OpenAI/Codex/bin/codex.exe --adb C:/Users/Phet/AppData/Local/Android/Sdk/platform-tools/adb.exe --serial <verified-vivo-serial>
```

The bridge provisions only the isolated debug app's private files via stdin, sets
one `adb reverse` mapping, refuses an occupied port, and expires after 15 minutes.
Open/reopen that app after provisioning. User selects Connect → OpenAI, enters
credentials privately and returns to press the explicit status button. Stop all
browser/screen/DOM/log inspection throughout credential entry. Never request a
code/password/token in chat. Device-code support is beta and requires the ChatGPT
security setting; its browser opening and explicit native return check passed in this session.

## Unresolved acceptance

The [pricing documentation](https://learn.chatgpt.com/docs/pricing) describes
continuation using available credits. This review has not established a
provider-enforced per-request quota-only switch, so a usage precheck cannot be
treated as proof of no paid continuation. [Configuration](https://learn.chatgpt.com/docs/config-file/config-sample)
documents individual tool switches, but a minimal tool-free inference setup has
not been validated against the pinned binary. Those are prerequisites for the
remaining inference adapter, not evidence that such support is impossible.

Login-only physical acceptance passed. Free-Thailand, provider-revoke, hosted-distribution, V2, E7, inference and pilot acceptance remain unclaimed. No successor task was dispatched. Existing source gates were reused because implementation files were unchanged.

## Autonomous physical testing — 2026-09-21

USB restored after user reconnection; physical testing is IN PROGRESS. The isolated local-learning-preview package `com.lexiquest.app.ariTest` is installed, cloud sync disabled. Main app/account remains preserved. Current APK SHA-256 `2f32fd76ab32c47438023096108830dc36c81e61ccff7f05c39ca66a4ced33f0` contains dictation/history repairs and self-check feedback. [Coverage matrix](device-test-matrix.json) separates full rounds, partial paths and external acceptance; [observations](device-observations.jsonl) contain sanitized UI evidence.

Completed physical rounds include 10-question meaning quiz, pair matching with repair, word/sentence scramble, review-center quiz and ghost duel. Vocabulary test-category create/import/edit/delete, research-export denial, local shop insufficient-funds/purchase/equip, microphone silence recovery and personal JSON/CSV/SVG file creation were exercised. Camera live capture returned unidentified on a cluttered table scene; CPU/XNNPACK benchmark completed, but this is not recognition-accuracy acceptance. More details and exact quantities remain in the matrix.

Two defects found: quiz shortage message fixed in `fe30b8c7` and physically retested; dictation accepted blank input as an incorrect answer. The latter now rejects blank/whitespace by button and keyboard; RED reproduced, all11screen tests PASS, focused analyze clean. Updated APK installed; disabled empty-submit observed. User confirmed concurrent phone touches; after coordination a controlled blank-tap and correct-answer completion regression passed. Existing success test now pumps the input-driven button update before tapping; no assertion was weakened.

A third defect, history failing to load after associative reading, was reproduced on the device and copied database. The established camel-case storage alias now maps only to its matching canonical mode. All37reader tests plus the16-session device diagnostic passed;Vivo history and replay now work. Replay points remained67. PDF2pages rendered cleanly;shop ownership/equip and display preferences survived restart. Active owner is firebaseBound,so email-status text does not establish a guest defect.

Still pending: remaining menu paths and full-round variants, actual Anki import, full export reconciliation, due-SRS/human audio and held-out camera evaluation, live online/account sync and provider inference. No native ChatGPT sign-out, data clearing, real-money purchase or research activation. Virtual reward purchase used only isolated test data. Work remains active; no whole-app PASS or successor dispatch.


Controlled continuation completed mixed typed recall2/2, six-stage associative reading1/1, and cloze/definition one-item rounds1/1. One-item choice rounds have only one option; completion is not distractor-quality acceptance. Focus timer starts, pauses and resumes. Planning, assessment and offline-content routes remain hidden by this preview registry.

Fourth reproduced defect: handwriting self-check buttons returned no visible feedback. Transient Thai feedback now explains empty input and each choice without changing scoring or persistence. RED reproduced, all11scratchpad tests and focused analyze pass; rebuilt isolated APK installed and all three messages physically verified. Small test viewport required waiting for transient feedback before next bottom-control tap; assertions preserved.

Populated Anki TSV144bytes exactly matches created test word, meaning, category and source ID plus4directives; test category removed. Actual Anki import remains untested. Personal JSON content hash matches; all39answer tuples(mode/correctness/latency/time) equal CSV, plus1reading count. Full58-table semantic reconciliation remains outside this bounded check. Matrix top-level cases and Thai inventory labels now reflect current evidence.

A1–C2 reading entries all open and return on Vivo; A1 mark-read was verified earlier. Certification, audio quality and full accessibility remain unclaimed. Open quality findings: single-option short cloze/definition rounds, list-like associative content, and absent active-pair UIAutomator semantics. The physical pass is a bounded checkpoint, not whole-system release acceptance.


## Autonomous test plan 2026-09-21

User request: design exhaustive, independently executable testing with no present user participation. Machine-readable plan: [autonomous-test-plan.json](autonomous-test-plan.json). This section is the execution design, not a claim that these tests have run. Continue in the existing task/worktree with one writer; do not create a parallel implementation or dispatch B19. Existing authorization permits scoped fixtures, testing and reproduced-defect repairs. This plan does not authorize paid calls, deployment, research activation or changes to the original account.

### Outcome and coverage boundary

Every current requirement, navigation entry, mode, storage side effect and applicable failure transition must map to a stable case ID and evidence level. Inventory is drawn from the current registry/glossary, actual UI, runtime flags, owner/export manifests and accepted requirement ledger. The historical generated full-system plans are reference material; their old PASS counts are not current-device acceptance. Final counts are derived after mapping; no guessed “hundreds of tests” or blanket 100% claim.

There are two separate totals: autonomous technical acceptance and externally dependent acceptance. Within the autonomous total report native-device, device-with-fixture, local-service and host-only results separately. Opening a screen does not satisfy domain/persistence acceptance. A test unavailable on-device can still yield a host result but the device obligation remains unpassed. Hidden features stay in the inventory; test-only exposure does not prove production availability.

### P0: repair the ledger before adding more results

Use device-test-matrix.json as the current summary and device-observations.jsonl as append-only historical actions. Mark superseded partial observations with the newer case ID; preserve original results. Cases receive requirements/routes, test level, source/input fingerprint, fixture identity, expected UI/data/economy changes, actual result, defect and cleanup evidence. Reuse passed checks only when their complete relevant dependency/configuration/artifact fingerprint is unchanged. Ambiguous provenance becomes STALE, not PASS. Existing four fixes retain their accepted bounded evidence.

Inventory the exact accepted source and active single-writer state before product changes. Do not conflate these physical tests with the full-system B18/B19 acceptance gates. Validate proposed script parameters locally before invoking a verifier; paths are references, not proof that a ready-made harness exists.

### P1: establish a recoverable test environment

Preserve the original com.lexiquest.app and native ChatGPT sessions. The current ariTest owner is firebaseBound, not a disposable guest: destructive cases must never target it. Use a new named disposable owner/database, and if the current debug package cannot isolate that safely, a separately identified test package with explicit denylisted original package IDs. Capture package/version/signature/APK hash, source revision, device serial/SDK and fixture version. Backup only the required test state, with restricted temporary files and deterministic cleanup.

Prefer existing integration_test/field_trial_core_journey_test.dart and repository interfaces after inspecting their reset/install behavior. Add missing test seams only to the fixture/composition; do not bypass production validation or force result rows into the database. Seed via normal use cases wherever possible. Migration/corruption tests use disposable copies and explicitly declared malformed fixtures. Give fixtures at least two owners, correct/wrong/guided/replay evidence, empty and due SRS sets, known economy transactions and Unicode/invalid content.

Clock injection advances synthetic study days without changing the phone clock. Local gateways/emulators inject timeout, denial, malformed data, duplicate/out-of-order delivery and conflicts without turning off the user's global network. Test-only flags can expose planning/preferences/assessment/offline UI using isolated dependencies, but production defaults and real research consent remain unchanged. Permission/settings tests affect only test-package resources and restore any state they change.

The UI driver verifies foreground package, expected screen and enabled controls before each action, then waits for a bounded observable state transition. It records intention/result and stops issuing taps on unexpected user input or a wrong screen, while host verification can continue. Use semantic finders and actual screenshots; use a production-widget integration driver when UIAutomator cannot expose a pair board. Do not equate missing automation semantics with an app crash or automatically claim TalkBack failure. Add stable accessibility identifiers where appropriate and verify they represent real controls.

### P2–P4: test, diagnose and repair sequentially

Execute domains A01–A16 in the structured plan. Apply relevant transitions rather than a blind full Cartesian product: normal path, invalid/empty/boundary input, cancellation, retry, duplicate action, background/resume, process death, persistence and owner isolation. Unsupported combinations need a documented NOT_APPLICABLE reason. Derive expected values from published product/domain contracts and hand-calculated fixtures, not by calling the same implementation to compute its expected output.

Example complete scenario: create a synthetic vocabulary item -> answer correctly -> inspect feedback -> verify one durable answer -> verify history/progress/SRS -> verify the expected reward ledger delta -> restart -> replay -> prove replay grants no duplicate reward -> export -> reconcile that row. A second scenario terminates the test app around a save/acknowledgement checkpoint, restarts it and checks that the result is either absent or committed once according to its transactional contract, never duplicated or cross-owner.

For every defect: preserve the minimal failing reproduction and source/artifact identity; distinguish FAIL_PRODUCT from FAIL_RUNNER; create a meaningful failing assertion; fix the cause; run the affected bounded tests; rebuild only when necessary; retest the changed device path and directly affected neighbors. Do not skip a failure, loosen a threshold, edit output data to pass or hand it to another task to bypass acceptance. If a test method fails, discover the actual path/state and change method. Keep working on independent cases when a true external prerequisite is unavailable.

Bounded entry points already present:

```powershell
& ./tool/cli/verify-scope.ps1 -Level Targeted -Area Learning -TestTargets test/features/learning/srs_policy_test.dart
& ./tool/cli/verify-scope.ps1 -Level Targeted -Area Learning -TestTargets test/features/history/learning_history_reader_test.dart
```

These are examples, not instructions to rerun unchanged PASS gates. Select the appropriate supported area/target for each change, and inspect the existing Android runner/profile before a device invocation. No full Flutter/backend/Android/GPU work runs concurrently. Full release verification is reserved for an authorized frozen SHA after the repository's prior gates, not triggered by this planning request.

### Media, AI and integration honesty

A known waveform can test parsing, scoring and error handling when the relevant interface accepts it; it does not prove that the physical microphone captures a person's speech correctly. Real TTS callbacks and native resource release can be tested autonomously; perceived sound quality remains separate. Live camera capture and an offline evaluation using the actual pinned model are distinct results. Freeze labeled known/unknown image sets and existing acceptance thresholds before testing. Images already inspected or used in repair become development data; use a new held-out set for acceptance. Do not pretend software can reposition physical objects around the phone.

Test AI orchestration autonomously with a local provider stub: timeout, cancellation, expired session, quota denial and late replies must produce correct user state and no unintended tool/network action. This does not supply the missing live inference adapter or prove provider billing behavior. Similarly, local sync faults do not prove production service configuration. Record each actual external prerequisite without classifying all AI/sync testing as blocked.

Anki file parsing is separate from importing into Anki. Use a compatible isolated runtime/profile if available; do not import into a user's existing deck. Reconcile exports against the full owner-lifecycle manifest, including intentionally count-only/redacted groups, not by demanding forbidden raw data be exported. Render PDF/SVG for visual review; validate escaping and formulas/markup as required by export contracts.

### P5: real endurance and resource budgets

First complete short smoke/fault cycles, then run a real 180-minute sequential journey on a stable source: study, switch modes, pause/resume, history, export, restart and local-sync recovery with periodic invariants. Simulated time does not satisfy elapsed-time endurance. Pin accepted frame-time/memory/latency/resource budgets before running; if no authoritative budget exists, define a provisional engineering target transparently before collecting results, without claiming formal release acceptance. Old performance failures must be reconciled against current source, not ignored or copied as present failures.

Measure crash/ANR, frame latency, memory trend/resource release and data/transaction counts at checkpoints. Disclose USB charging and debug/profile build effects on performance and battery observations; plugged-in measurements do not certify unplugged battery life. This is autonomous work, not human-dependent. Keep bounded tool waits and meaningful progress updates; do not claim any unattended execution is scheduled or continuing after a response unless actually configured and authorized.

### P6: stop conditions and delivery

Autonomous acceptance closes only when the inventory has no unmapped entries, every applicable required case has qualifying evidence, required product defects are fixed/retested, all synthetic state is reconciled/cleaned, no test process remains unexplained, and a final artifact/source identity is recorded. An outstanding runner failure is not a product PASS. No unresolved quality issue can disappear into a summary.

Deliver: current coverage matrix; detailed cases with evidence levels; defect/fix/retest ledger; exact artifact/source/fixture hashes; performance/endurance results; and a concise Thai report separating autonomous completion from genuinely external acceptance. External gaps remain visible: live provider rights/billing/revoke, hosted service credentials/configuration, human hearing/pronunciation/usability, fresh independent physical camera scenes, and Anki runtime availability if absent. Retain original app/account data throughout. No routine approval question is needed to continue already authorized independent work.

## Autonomous execution 2026-09-21

**ผลรอบนี้: ผ่าน 696 host tests จาก 53 ไฟล์ที่ไม่ซ้ำกัน และ native fixture บน Vivo อีก 3 test cases ที่มีขอบเขตชัดเจน; ยังไม่ผ่านการตรวจรับทั้งระบบ.** [หลักฐานและ hash](autonomous-run-001.json) · [ทะเบียนเมนูและโหมด](autonomous-inventory.json) · [ช่องว่างเดิม](device-test-matrix.json). Source base `72eca4585df9eaea05700e89c23d383770ad8a66`; application source ไม่เปลี่ยนในรอบนี้ มีการเพิ่ม/ปรับ integration fixtures เท่านั้น แต่ละ verifier เก็บ input closure และก่อน/หลัง fingerprint ของตัวเองใน `evidence/autonomous-run-001/*.gz` จึงไม่อ้างว่า harness ทุกรุ่นเป็น source เดียวกัน

| ชุด | สิ่งที่ตรวจจริง | ผล |
|---|---|---:|
| H01 | ข้อมูลถาวร/เจ้าของข้อมูล, offline sync recovery, quiz/scramble, SRS และเวลา | 44 PASS |
| H02 | ค่าเริ่มรอบและขอบเขต, จับคู่หมดเวลา/กดใกล้จบรอบ/เล่นซ้ำ, cloze/definition, การถอนสิทธิ์หน้าคำศัพท์ | 151 PASS |
| H03 | export/delete ของเจ้าของทดสอบ, แผนเรียน, assessment isolation, ยกเลิก/เขียนไฟล์ล้มเหลว/ลองใหม่, offline artifacts | 108 PASS |
| H04 | ทะเบียน 14 โหมด, glossary/navigation guards, SRS, อ่านแล้วเปิดฐานข้อมูลใหม่, วงจรพูดและ shadowing | 156 PASS |
| H05 | รางวัล/ซื้อ/สวมใส่/เจ้าของเปลี่ยนระหว่างคำสั่ง, quest ตามปฏิทิน, sync timeout/conflict/ซ้ำ | 153 PASS |
| H06 | กล้องและ speech gateway, cancellation, transcript evidence, voice lifecycle/fallback | 84 PASS |

ไม่มี target file ซ้ำระหว่างหกชุด จำนวนนี้ไม่นับ H02 รอบที่ verifier ปฏิเสธเพราะ input drift และไม่นับผลเก่าที่ผ่านก่อนหน้าเพิ่มเข้าไปเพื่อขยายยอด ทะเบียนพบ 64 navigation/action IDs และ 14 canonical lesson modes; 64 เป็นรายการ metadata ไม่ใช่ 64 requirement packages ของ full-system และไม่ได้หมายความว่าทดสอบทุกการกดครบแล้ว

Native core ใช้ viewport จริงของ Vivo V2041 และฐานข้อมูลชั่วคราวที่แยกจากบัญชีเดิม ทำ 23 ช่วง: guest → สร้างคำศัพท์ → quiz → associative ทั้งหกขั้น → SRS → progress/rewards → หน้าหลัก/ร้านค้า/quest → ปิดและเปิด dependency/database → ตรวจค่าคงเดิม → export → sign out ของ fake account. เพิ่ม assertion อิสระจากแถว SQL ห้าข้อ: หมวดว่างไม่เพิ่มแถว, double-save หมวดเพิ่มหนึ่งแถว, คำศัพท์ว่างไม่เพิ่มแถว, double-save คำเพิ่มหนึ่งแถว, double-answer เพิ่ม answer_attempts หนึ่งแถว ผ่านทั้งหมดใน journey เดียว ไม่ได้นับ 23 ช่วงเป็น 23 test cases และไม่นับ rerun baseline ซ้ำเป็นอีกหนึ่ง coverage case

Native fault suite อีกสอง cases ผ่าน: กล้องถูกปฏิเสธ/โมเดลไม่มี/ไมโครโฟนถูกปฏิเสธ และ emergency-off ของเมนู AI คงอยู่หลังเปิด dependency/database ใหม่ ผลสองชื่อถูกบันทึกเป็น `success` ใน [native-fault-results.json](evidence/autonomous-run-001/native-fault-results.json) พร้อม driver exit0. การรันบนมือถือใช้ production widgets แต่ account/camera/speech/AI/export gateways บางส่วนเป็น fake; ไม่มีการกล่าวอ้างว่าเป็นการวัดความแม่นยำ sensor หรือ live provider. การ restart ของ fixtures เป็นภายใน Android process เดียว และ SRS due row ถูก seed อย่างเปิดเผย จึงไม่แทน native process-death หรือการพิสูจน์ scheduler algorithm

### สิ่งที่ยังเป็นปัญหา

1. **CONTENT_SINGLE_CHOICE — ยังเปิด:** cloze/definition ที่กำหนดหนึ่งข้อแสดงคำตอบเดียว ตรวจ source ยืนยันว่า distractors มาจาก `session.questions` เท่านั้น (`definition_quiz_mode_adapter.dart:210`, `cloze_mode_adapter.dart:193`). การผ่าน tests ของความไม่ซ้ำและความคงที่ของ options ไม่ได้พิสูจน์ว่าโจทย์มีตัวลวงขั้นต่ำ คะแนนสำเร็จจึงไม่ใช่หลักฐานคุณภาพการเรียน
2. **ASSOCIATIVE_CONTENT — ยังเปิด:** local passage ที่เห็นมีลักษณะรายการคำศัพท์มากกว่าเรื่องต่อเนื่อง ผลทดสอบ flow/persistence ไม่ได้ปิดคุณภาพภาษาและการสอน
3. **PAIR_ACCESSIBILITY — ยังเปิด:** host semantics tests ผ่าน แต่ active native board ก่อนหน้าไม่ปรากฏใน UIAutomator tree; ยังไม่พิสูจน์ TalkBack usability และยังไม่สรุปว่าเป็น TalkBack defect จาก automation tree เพียงอย่างเดียว

บั๊กการใช้งานสี่ข้อที่แก้และ retest ก่อนหน้ายังคงอยู่ใน ledger เดิม: quiz shortage, blank dictation, history alias และ feedback ของ handwriting รอบนี้ไม่ได้อ้างว่าแก้ production defect ใหม่จากจำนวน tests ที่ผ่าน

### ปัญหาตัวทดสอบและการกู้คืน

Vivo ปิดบัง VM endpoint ใน logcat จึงใช้ endpoint ที่ยังมี authentication ใน private `code_cache` และ forward USB ที่เป็นของรอบทดสอบเท่านั้น; ไม่ปิด VM auth. แก้ async registration ที่เคยสร้างผลศูนย์ cases, แก้สมมติฐาน path และจำนวน starter rows ด้วย exact before/after deltas. H02 ต้องรันซ้ำเพราะแก้ fixture ระหว่าง gate; รอบที่ยอมรับมี fingerprint คงเดิมและ assertion เดิมทุกข้อ

Fault run แรกเจอหน้าจอดับและ active SemanticsHandle ระหว่างที่มี UIAutomator แทรกอ่านหน้าจอ การอ่านแทรกเป็นสาเหตุที่สงสัย; same APK ผ่านหลังแยกช่องทางควบคุม จากนั้น fixture ที่เพิ่ม receipt ของชื่อ cases ผ่านอีกครั้ง ไม่ปิดการตรวจ semantics. Streamed install ล้มเหลวหนึ่งครั้งโดยไม่มีรายละเอียด; ตรวจพบ device authorized/พื้นที่ว่างแล้วเปลี่ยนเป็น non-streamed installation สำเร็จ. รายละเอียด R01–R07 และ raw logs ที่บีบอัดอยู่ใน structured evidence

### สภาพเครื่องและการทำซ้ำ

คืน APK preview ปกติ SHA256 `2f32fd76ab32c47438023096108830dc36c81e61ccff7f05c39ca66a4ced33f0` ด้วย package/hash guard และ replace install สำเร็จ ตรวจพบหน้าเรียนภาษาไทยพร้อมห้าแท็บและสถานะข้อมูลในเครื่องพร้อมใช้ ไม่มี temporary fixture directory, private VM receipt หรือ ADB forward ของรอบนี้เหลืออยู่ ค่า USB stay-awake คืนเป็น0. ไม่ลบ/ลงทับ/ออกจาก `com.lexiquest.app` หรือบัญชี ChatGPT เดิม

Fixture entry points: `integration_test/field_trial_core_journey_test.dart` และ `integration_test/autonomous_device_faults_test.dart`. Build ใช้ `--dart-define=AUTONOMOUS_DEVICE_VIEWPORT=true --android-project-arg=ariLocalTest=true --target-platform android-arm64`; ตรวจ package ก่อน install ทุกครั้ง. Helper `integration_test/support/attach_autonomous_fixture.py` เก็บวิธี attach แบบปิดบัง URL ให้ทำซ้ำได้ โดยรับ `--serial --log --adb --flutter`; helper ฉบับ parameterized ตรวจ syntax/CLI แล้ว แต่ actual native runs ใช้ scratch predecessor ที่บันทึก logs ไว้ ต้องไม่อ่าน UIAutomator หรือส่ง taps อีกช่องทางขณะ driver ทำงาน

**Remaining acceptance:** ทุก interaction variant ของ 64 entries, single-choice/story quality, native save/ack process-death, TalkBack, resource budgets และ endurance180นาทีจริงยังไม่ปิด; endurance ไม่ใช่ external blocker และไม่ได้อ้างว่ารันแล้ว. Live inference/quota/billing/revoke, hosted sync, human speech/learning quality, fresh held-out camera และ actual Anki import ยังแยกเป็นช่องว่างเฉพาะด้าน ห้ามนำ host/native-fixture PASS ไปแทนผลเหล่านี้ แผนยังเป็น `EXECUTING_PARTIAL_ACCEPTANCE_OPEN`; ไม่มี background tester หรือ successor task ที่ทำงานต่อโดยไม่ได้ระบุ
