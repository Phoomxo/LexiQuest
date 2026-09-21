# App/device integration — live chat/MCP checkpoint, 2026-09-21

Accepted base: `7407111bbb3f85ae1bc519dfe8b10ed37e501c05`.
Task `01a0bfbd-9961-7da3-982b-77970bdc7027`; writer released at the bounded live chat/MCP checkpoint; broader system acceptance remains open.

**Vivo V2041 installation, launch, browser device authorization and native login status passed. The authorized chat/MCP prototype now has real Vivo evidence: Thai replies, contextual follow-up, selected-word lookup, unscored practice, cancel/reconnect and USB-offline recovery passed. Standalone production acceptance remains open.** OpenAI confirmed sign-in and Ari confirmed the account connection after the explicit status check. The bridge has no turn/thread/reply route. [Evidence](app-device-integration-evidence.json) and [handoff](app-device-integration-handoff.json) distinguish login from inference.

The user explicitly authorized agent taps using the sole cached account and inspection of consent/settings. The blocked Continue button was caused by the disabled Codex device-code authentication switch. Enabling that switch in web ChatGPT security settings and restarting device authorization resolved it. Developer mode, MFA and the existing native ChatGPT session were not changed. Rapid ADB input omitted a character; paced entry succeeded. No passwords, MFA codes, tokens or device challenge values are recorded in this report. The bridge remains ephemeral with a 15-minute lifetime.

## Execution plan

Latest user correction, 2026-09-21: prioritize a working in-app chatbot with real responses and observable tool outcomes. Quota/cost investigation is no longer the primary prerequisite for advancing this prototype; the earlier no-inference-until-quota-proof sequencing below is historical. This does not authorize purchasing credits or introducing an unapproved paid provider. Existing login and simulated component tests remain distinct from live response/tool acceptance. Acceptance now begins with Thai send/reply on Vivo, contextual follow-up, selected-word tool retrieval reflected in the answer, a verifiable app action, and cancellation/failure handling. Preserve all earlier open defects without diverting this priority back to broad unrelated testing.

Reference audit before this slice: `lib/screens/ai_tutor_screen.dart` already supplies a conversation UI on the existing BYOK path; `ManagedTutorPanel`/controller supplies managed-session UI and lifecycle but currently holds a reply rather than implementing a complete live conversation/tool loop. `docs/development/post-g83-e0-e1/reference-observations.json` contains Astra AI observations and intended adaptations, with implementation comparison pending. User clarified the names as AllTCAS and Astra AI. AllTCAS maps to `docs/generated/alltcas-idea-integration-feature-map.md` (44-feature contract); Astra observations are in `docs/development/post-g83-e0-e1/reference-observations.json`. MCP was not integrated throughout the menus and the central-chat loop had not yet been demonstrated. The bounded loop is now demonstrated below; all-menu integration remains open.

### Authorized chatbot implementation slice

User authorized adaptation of the named chatbot references to LexiQuest; user confirmed AllTCAS and Astra AI. Adapt canonical lexical context from the AllTCAS-derived feature map and explanation-then-practice from inspected Astra observations. This is a vocabulary-domain adaptation, not a claim to reproduce either complete product.

1. Add a bounded, private developer chat bridge beside the existing login-only diagnostic. Use the pinned App Server binary, isolated ChatGPT login and an ephemeral conversation; implement actual turn completion, contextual follow-up, cancellation and fixed failure responses. Keep the original login diagnostic's acceptance intact. No production deployment, account replacement or data migration.
2. Add a real stdio MCP server exposing selected-word lookup and a bounded practice draft from an explicit vocabulary snapshot. No arbitrary filesystem, shell, account or reward tools. Validate tool inputs and preserve word identity; distinguish returned tool receipts from generated prose. Test initialize/list/call using the real subprocess before model integration.
3. Extend the managed Flutter panel to a visible conversation, connect the authorized reply route, provide an explicit selected-word context, and display tool outcomes. Reuse canonical owner fencing; clear context/conversation on identity changes; prevent duplicate send and late replies. Use failing tests before implementation, bounded Python bridge/MCP tests and `verify-scope.ps1 -Level Targeted -Area AI` for affected Flutter targets.
4. Build only the isolated debug package, preserve the prior APK/account, then exercise Thai message, follow-up, actual MCP lookup/practice, cancellation and failure on Vivo. Record real-provider and simulated results separately with hashes. Provider/login failure is diagnosed while independent work continues; never fabricate live PASS. The USB developer bridge is a prototype dependency, not a claim of standalone mobile distribution.

Official protocol references checked for this slice: [App Server](https://learn.chatgpt.com/docs/app-server) and [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference). Pin actual request shapes against the installed binary schemas before dispatch.

1. Add an opt-in host around ManagedTutorController/Panel. Fence owner/account,
   network, route, background and disposal; test stale completions and cleanup.
   Keep BYOK, database schema and normal application entry unchanged by default.
2. Pin actual App Server login schema. Build an authenticated loopback-only
   developer bridge with isolated memory-only credentials, bounded cleanup and
   no API-key path. Native debug UI must distinguish login from tutor readiness.
   Historical sequencing: no inference before quota/no-tool investigation. Superseded for this bounded prototype by the latest functional-acceptance authorization above; no paid fallback or credit purchase is inferred.
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


## Chat/MCP live execution — 2026-09-21

User confirmed **AllTCAS + Astra AI**. Implemented a bounded vocabulary adaptation: choose canonical personal/shipped vocabulary, ask Ari in the app, keep follow-up context, and open a validated practice draft returned by MCP. The existing production BYOK screen is unchanged; this managed-account route is an explicitly enabled debug prototype that still depends on a USB-connected desktop bridge.

**Observed on Vivo V2041:** authenticated native chat returned a Thai explanation of `bottle` and an example sentence, alongside a successful selected-word MCP receipt. A follow-up asking for practice without repeating the word produced the corresponding MCP draft; the native button opened it. `wrong` produced retry feedback; `BOTTLE` produced correct/unscored feedback. A request cancelled while pending did not publish a late reply; explicit reconnect worked. Switching to `chair` started a new conversation and returned the correct Thai explanation with another lookup receipt. Removing only the test USB reverse mapping produced the offline state; restoring it and explicitly reconnecting recovered. Backgrounding cleared the conversation and the isolated login, confirmed by a fresh status check.

Inputs for these physical prompts were English; responses and practice feedback were Thai. Native Thai keyboard input is not claimed from this run. The safe HTTP/Flutter tests cover Thai payload transport separately. The UI shows Markdown markers as plain text; this and composer scrolling/login layout remain polish work before production integration. Cancelling currently clears the in-memory conversation. No persistent chat history, all-menu tool catalog, progress-awarding practice, standalone mobile backend, or production distribution is claimed.

### Defects found and repaired

- **CHAT-01:** Native login succeeded but opening chat immediately disconnected. Drift invalidated the owner-generation query whenever the lease wrote to the shared runtime-flags table. The watcher now uses `watchSingleOrNull().distinct()` so actual generation changes still invalidate the session, while unrelated lease writes do not. A real in-memory Drift test reproduced `ready` → `disconnected` before the fix and passed after it; physical reopening and three completed provider turns then passed.
- **CHAT-02:** The word selector omitted the shipped catalog by filtering personal owner rows only. It now reuses `PackagedStarterAccess.wordsFor`, including its exact catalog/manifest authorization rather than trusting a global flag. The catalog tests passed and the physical selector showed the authorized words; `bottle` and `chair` both reached MCP.
- **CHAT-03:** A completed MCP transport item could contain `isError`; that result must be labelled failed. The new failing test passed after correcting receipt status. This is simulated failure evidence, not a claim that a real tool error occurred during the successful live journey.
- Readiness is now required before the Flutter bridge can send a reply. Existing login-only mode remains non-inference-capable. Navigation/owner/cancellation fences and bounded HTTP allowlists remain covered.

Verification: **46 managed Flutter tests (8 files), 9 catalog/access tests, and 37 Python tests passed**; focused analysis found no issues; the isolated APK built and installed successfully. Python evidence includes actual stdio MCP subprocesses plus simulated provider protocol/HTTP tests. A separate real pinned App Server smoke discovered and called both MCP tools without model inference. These evidence levels are kept separate in [chat-mcp-001.json](chat-mcp-001.json).

The live APK SHA256 is `3de6bc67a14ca9161ad793a08d3e50f1c941dbd9a39a86cfc12fd8667231e740`, saved locally at `build/ari-chat-prototype.apk`. Native evidence images: [ready](evidence/chat-mcp-001/ari-chat-ready.png), [wrong answer](evidence/chat-mcp-001/ari-practice-wrong.png), [correct answer](evidence/chat-mcp-001/ari-practice-correct.png). No codes, bearer capabilities or account identifiers are in these artifacts.

Recovery notes: USB changed from offline to unauthorized and then authorized after the user reconnected. The browser's separate code fields dropped characters with rapid key injection; verified per-field entry succeeded. Early test-fixture compilation and a missing Drift extension import were corrected; no test was skipped or weakened. Build emitted existing future-Kotlin-plugin compatibility warnings, without failing.

After testing, the isolated session was cleared, the bridge process stopped, its USB reverse mapping removed, stay-awake restored to0, and the prior normal preview APK restored and launched successfully. The original `com.lexiquest.app` remains version23. No background tester, successor task or provider session is left running by this slice. Broader system coverage remains in the existing autonomous ledger; this closes only the bounded functional demonstration above, not V2's full original distribution/Free-plan requirements or whole-app acceptance.


## All-menu MCP integration — debug acceptance 2026-09-21

Latest authorization expands beyond the accepted selected-word prototype. One writer in the existing feature worktree; original accounts and app data remain intact. Standard/default requested; runtime tier cannot be verified with available controls.

Execution order and acceptance:
1. Build a bounded application action registry with explicit live callback bindings, owner/session/revision fences, disabled/unmounted checks and replay protection. RED/GREEN tests must prove real callback effects, not catalog presence.
2. Bind the actual main, drawer, learning, planning, today and settings actions; classify informational sections and sensitive confirmation flows separately. Discover extra actions beyond the 64-entry glossary. Never bypass feature gates or have the model approve its own destructive confirmation.
3. Extend the actual stdio MCP server and authenticated USB bridge with bounded app action requests/results; add global app chat composition so navigation does not destroy the initiating chat. Test protocol errors, cancellation, stale owners, duplicate delivery and unavailable actions.
4. Verify affected Flutter widgets and domain effects sequentially, build the isolated package, then run real Vivo journeys and record action/result receipts. Keep simulated, stdio, provider and native evidence separate.
5. Diagnose/fix/retest every observed defect; report exact untested interactions honestly. Listing all menu IDs alone never proves whole-app acceptance.

Accepted within the debug integration scope: [64-entry matrix and evidence](all-menu-mcp-001.json). The registry connects 48 executable controls, 15 read-only context entries and one explicitly manual-only logout entry. The user's instruction to preserve the account remains in effect. Seven additional navigation/planning/profile controls are registered. Menus invoke the application's real callbacks, including feature and owner checks; opening a configuration screen or confirmation dialog is not represented as saving data or completing a lesson.

The full application now shares a persistent chat pane outside its Navigator. Actual stdio MCP tools `list_menu_actions` and `execute_menu_action` exchange bounded requests/results with the authenticated USB bridge. Model input cannot supply arbitrary code, filesystem paths, route arguments or owner IDs. Revisions, request replay protection and cancellation/session fences reject stale work. Read-only profile context contains only the six explicit metrics; account email and arbitrary route arguments are excluded.

Repaired five integration defects: write-tool approval was denied before reaching the app; navigation Futures blocked until a page was closed; lazy offscreen finite menu groups were undiscoverable; an inactive duplicate drawer action could shadow the active tab; and receipts survived reconnects. Each has its cause, fix and evidence in the structured report. Finite menu groups now remain mounted, while vocabulary/history data lists retain virtualization. Corrected the chat disclosure to include currently open menu data.

Verification exercised all five main tabs, nine drawer destinations, three secondary destinations and 15 learning entries in the composed application, plus planning children, exact Today callback payloads, settings changes/confirmation boundaries and read-only context. The broader affected run had 285 passes and two fixture locator failures; the affected 44-test file passed after requiring a hit-testable profile button and scoping a duplicated label to the drawer. The final managed suite passed 63 tests, including exact extra-route widgets and cancellation/disconnect/disposal races. The 132-test UI group and 42 Python tests passed; these counts overlap and must not be summed. Analysis found no issues. No tests or acceptance assertions were skipped. Per-file source hashes and line-ending-only equivalence are recorded with the evidence.

On Vivo, a live prompt opened profile, expanded details and read all six metrics. Another opened learning and the offscreen dictation configuration. Cancelling a pending menu request left that configuration unchanged. Removing only the owned USB mapping produced the offline state; restoring it and explicitly reconnecting recovered. The final APK then opened Today and learning history through actual MCP, and after disconnect/reconnect correctly identified the current history page from tool context. [Native screenshot](evidence/all-menu-mcp-001/vivo-history-final.png). Native representatives complement the full callback matrix; they do not claim 64 separate live-model journeys.

Final debug APK: `build/ari-all-menu-release-check.apk`, SHA256 `eece7ee7187b28fa8c2eda57b9973cf34f054e017f518b43d877737e7207c782`. It remains installed as `com.lexiquest.app.ariTest`. The original app remains version23 and original browser/ChatGPT accounts were not logged out. The owned isolated provider session, local listener and USB reverse mapping were closed; stay-awake was restored to0. No background implementation worker or successor was created. Writer released for this accepted scope.

This remains a USB-connected debug implementation, not standalone mobile distribution or whole-app release acceptance. Individual lesson answers, arbitrary CRUD forms, sensors, research activation, native Thai keyboard entry and endurance/usability requirements are not closed by menu navigation. Their existing ledgers remain authoritative; no production deployment or credit purchase occurred.


## Vocabulary MCP continuation — 2026-09-21

Continued from accepted commit `2e1da202832c8d72054e190ecbdc881ff70434ee` in the same feature worktree. Connected category creation dialog, mounted category rows, word creation/edit routes, CEFR examples and import navigation to their existing UI callbacks. Data lists remain virtualized; read-only/feature/route gates are preserved. Opening a form does not imply that saving/importing is supported through MCP.

Two defects were reproduced and repaired: personal record labels/actions could remain discoverable after owner change before the UI rebuilt; bindings now check the record owner immediately. Live provider called the starter category personal because descriptors omitted category type; explicit personal/read-only labels corrected this, verified again with the live provider on Vivo. A category replacement test also verifies that an old index snapshot cannot open a different record.

Verification: 76 host tests across 13 files passed (13 vocabulary and 63 managed-chat tests); after the final descriptor change the affected 13 vocabulary tests passed again. Counts are not additive. Focused analysis found no issues. Test corrections retained actual assertions: use the real TextField controller, initialize the shared asset Future outside expired test clock zones, yield after mounting examples, and assert resolved CEFR content. No assertions or tests were skipped. Final Android debug build/install passed; existing Kotlin future compatibility warning remains.

Live provider on Vivo opened a category, add-category dialog, the exact isolated QA category and its empty add-word form, then the import page without saving words/importing. Final APK recheck correctly distinguished personal and read-only categories and reported addition unavailable in the starter catalog. Native edit/examples are not claimed from host evidence. Final APK `build/ari-vocabulary-menus-final.apk`, SHA256 `38d795e2c4258d791f4a31f6ad18e8a236b09fc7954b8690b317e8b502dfd7f9`.

Removed only this run's `ARI QA 002` fixture via its native delete confirmation. The original app remains version23 and original accounts remain signed in. Closed the bridge, removed its reverse mapping and private temporary homes, restored stay-awake to0; final isolated APK remains installed. [Structured evidence, source pins and remaining work](vocabulary-mcp-002.json). This is a navigation checkpoint, not full CRUD/whole-app acceptance. Next work remains offscreen list discovery, typed form actions with persistence validation, and the existing broader device/production acceptance gaps. No successor or background worker was started.


## Typed form execution plan — 2026-09-21

Continue authorized work from b0309e14 with one writer. First extend existing menu transport with bounded string fields declared by the mounted form, strict unknown-field/length rejection and payload-aware replay identity. Keep no-argument navigation compatible. Next wire word form fill and save to the same domain validation and database use cases as manual controls; only verified persisted data may produce saved status. Verify invalid/duplicate/owner-change/cancel/replay outcomes, real storage read-back, and native representative journeys. Never reinterpret invoked as persisted. Preserve original accounts and original application; use isolated QA data. No production deployment, remote backend rollout or schema migration is authorized by this step. Existing offscreen-list, standalone mobile and whole-app acceptance remain open.

Tests run through bounded verify-scope selections plus Python protocol tests, followed sequentially by analysis, isolated Android build and native execution. No parallel writers or build/test overlap. Recover failed methods without reducing acceptance.


Typed-word implementation checkpoint: bounded named string fields now reach the app through MCP; fill and save are separate. Save returns `saved` only after reading the persisted record back with matching owner, category, text and CEFR. Word creation/edit share manual validation. Same-session replay compares payloads, stale form snapshots reject, and cancelled turns retire their command revision. Owner/mutation guards apply before issuing domain writes; cancellation does not roll back an already committed write. This is not a durable exactly-once guarantee across sessions.

Verification: 99 combined Flutter tests passed, affected cancellation/bridge/form retest12 passed, Python44 passed including actual stdio MCP. Counts overlap. Real Drift assertions cover Thai persistence, no draft write, duplicate/replay rejection and edit revision. A reproduced manual typing focus loss was fixed by changing command revision without remounting the form. Analysis is clean and isolated Android build/install passed. [Evidence and source pins](typed-word-mcp-003.json).

Native acceptance is pending: Vivo remains connected but `mDreamingLockscreen=true`; an unlock-only request is pending. Final installed test APK `build/ari-typed-word-forms.apk`, SHA256 `b359e9377d99adf628c52f990bd323d9cb41f46ef55b1d18c0beff5d97ac9f10`. No live-provider/native form-save PASS is claimed. Single writer retained; no successor/background worker or bridge started. Next native checkpoint is disposable category -> live fill/save -> reopen/read-back -> duplicate/edit -> own fixture cleanup. Category/import/delete form wiring, offscreen discovery and standalone distribution remain open.


## Optional MCP compatibility contract - user clarification 2026-09-21

MCP is an opt-in enhancement to existing application features and workflows. No ChatGPT/GPT/provider connection may become a new prerequisite for baseline workflows. Preserve existing app identity, permission, network and feature requirements; this does not promise that network-dependent features work offline. Manual UI actions must use the original domain services independently of MCP. MCP disconnected, never configured, expired, unavailable or cancelled must leave baseline navigation, forms, learning, persistence and progress usable. Provider login and failures belong to the optional AI surface and must not force application logout or discard user work.

Acceptance must compare the same applicable core journeys with MCP never connected, connected, and disconnected/failed mid-session; verify equivalent domain validation and persisted outcomes for equivalent user actions. Confirm normal launch without the USB bridge/provider and no unsolicited provider calls in the unconnected path. Connected AI-only assistance is additional capability, not a replacement for controls or learner answers. This is a required compatibility gate; full no-MCP regression acceptance is pending and is not established by previous connected demonstrations.


Language scope clarification - user 2026-09-21: the application trains English to Thai and Thai to English only. The earlier Italian wording was not a request for Italian support. Keep MCP explanations, content selection and applicable direction handling within this bilingual scope; do not assume every mode supports both directions without checking its contract. MCP remains optional under the compatibility contract above.


## Separate optional AI workflow implementation - 2026-09-21

Authorized scope is tracked in optional-mcp-workflows.json: 14 workflow groups and 14 nested learning modes, English/Thai only. Keep one writer and original domain services. S1 first removes the debug entry dependency on USB pairing and gives AI its own opt-in section; launch/manual navigation must succeed when pairing is absent, invalid or failing. Relevant files: lib/main_ari_test.dart, lib/main.dart, managed_tutor_test_screen.dart and managed_tutor_panel.dart. S2 adds bounded per-mode assistance context through explicit adapters with owner/revision fences, without answering or scoring on behalf of learners. S3 completes workflow operations against existing use cases with actual persistence validation. S4 reconciles host and native evidence for never-connected, connected and connection-loss scenarios. No schema migration or production rollout assumed.

Verification uses tool/cli/verify-scope.ps1 -Level Targeted with exact affected Flutter targets, Python protocol tests when transport changes, and sequential Android build/native checks at stable checkpoints. Reuse unchanged accepted evidence. External live-provider/native checks remain distinct from host fixtures. Starting defect: main_ari_test.dart returns before app bootstrap when pairing file is absent; this is a debug-host coupling, not proof that production main.dart requires MCP. Repair with independent application startup and contained optional-AI failure.

S1 startup checkpoint: debug app now initializes original dependencies before and independently of AI pairing. AI preparation starts only when the learner opens its separate optional section. Missing/failing/pending pairing leaves manual navigation usable; successful optional runtime preparation preserves the selected tab. The existing production entry is unchanged. Regression reproduced 3 missing-NavigationBar failures before repair; combined 10 tests passed, then final strengthened 4-case retest passed with actual AI-screen mounting asserted. Analysis clean. Receipts/source hashes: evidence/optional-ai-004/. No Android build or native PASS for this change yet; no whole-workflow parity claim. Next: per-mode bounded assistance context and full manual baseline parity, then remaining workflow adapters and native acceptance.


## Lesson assistance checkpoint - 2026-09-21

Read-only mode guidance now covers all14 LessonMode enum values and shares actual owner-bound lesson status/direction/counts through the optional section. It exposes no learner-answer or scoring actions. Real-controller storage checks and draft retention pass. Native Vivo proved cold launch without MCP, a completed manual1-question quiz, later optional login preserving the route, live model reading0/1 then1/1, and manual completion after the owned reverse connection was removed. These are representative journeys, not all-mode acceptance.

Native defect ASSIST-01: Quiz displays feedback through its own panel while the shell controller only reflects committed count. Live AI honestly reported feedback unavailable. Added owner-scoped lesson/committed-feedback projection from the visible panel, with a failing reproduction followed by47 screen tests and162 lesson/feedback tests passing; Python44 and analysis clean. Counts overlap. The installed APK predates this fix, so next action is build/install and live feedback retest, followed by remaining mode-specific/current-question assistance and workflow adapters. See lesson-assistance-005.json for pins, recovery and cleanup. No bridge, reverse mapping, provider process or background worker remains; original app/account preserved. Goal remains active; no full14-workflow or14-mode acceptance claimed.


## Native feedback and word routing recovery — 2026-09-21

Fresh isolated APK from 734f6f0d passes ASSIST-01 on Vivo: AI reads meaning-quiz English-to-Thai, one committed correct response, and exact visible answer กระเป๋า. Manual lesson controls still own answering and completion. Evidence: lesson-assistance-006.json. This supersedes the previous native-pending checkpoint only.

Live word creation initially exposed incorrect provider routing: an ordinary add-word request called selected-word practice instead of the active new-word form. Explicit form guidance succeeded and reopened native editing confirmed pencil / ดินสอ / noun / A1. Updated provider instructions separate management from selected-word tutoring; Python44 passed. A fresh authenticated session then completed natural-language creation with list → filled → list → saved, without the prompt naming MCP tools. Duplicate and edit verification now pass: duplicate save is rejected with one native row retained, and edit A1 → A2 returns saved and reopens with A2. All14 workflow and mode coverage remains open. Own disposable fixtures006/007 removed; bridge, reverse mapping, provider process, private pairing capability and owned temporary home are gone; stay-awake restored to0. Original app version23/account preserved. Next: typed category form with owner/revision fences and persisted read-back, then remaining adapters and parity coverage. No successor or background implementation worker.


## Category forms and late AI attachment — 2026-09-21

Added vocabulary/category-fill and category-save to the existing dialog. Fill leaves storage unchanged; MCP save uses original category validation, guards owner/revision before mutation and reads back exact stored identity/name/revision before returning saved. Manual save retains its original completion path and does not wait for the optional receipt query. Duplicate, invalid and stale results are explicit. Category and word forms now bind to their local data owner independently of provider login and keep their widget tree stable; late AI attachment preserves text and word focus.

40 bounded Flutter tests passed across offline vocabulary, vocabulary screens/use cases and menu registry/bindings. Analysis clean. Red tests proved missing category actions and missing category/word actions after late AI attachment. Stream-based widget fixtures required frame/IO pumping and stream cancellation before database close; no assertions removed. Receipt and source pins: category-mcp-007.json. The final post-test edits only add braces and preserve historical line endings.

Android build succeeded; APK hash e6125854124d8bf91ab32c3ed1eefb042e12e9c49c9344c12e91d987f1666bec. Native acceptance is pending: ADB file-transfer EOF and a mismatched partial transfer were detected, then per-device reconnect returned unauthorized. USB trust authorization requested; no original account logout, bridge or provider process started. Delete owned /data/local/tmp/ari-category-008.apk after authorization and verify full APK hash before isolated installation. This checkpoint is host acceptance only, not closure of W03 or the14-workflow/mode goal. Continue useful source work while awaiting the indispensable physical authorization.


## Confirmed word deletion — 2026-09-21

Added optional per-word delete navigation, owner-bound exact target context, cancel and typed confirmation. Opening the original dialog makes no mutation. Confirm requires its exact word ID and uses the existing deleteWord use case with owner/revision admission; deleted is returned only after the owner-scoped active word list no longer contains that ID. Original manual deletion/cancellation remains available; dialog now includes meaning to distinguish homographs. Provider instructions require an explicit user deletion request and forbid guessing ambiguous targets. The actual stdio MCP transport recognizes verified deleted results.

42 bounded Flutter tests and45 Python bridge tests passed; analysis clean. Coverage includes exact persisted tombstone, invalid target, cancellation, immediate owner-context isolation, read-only words and unchanged native offline journey. Long Unicode menu/context/form labels reproduced Invalid action descriptor; binding now bounds descriptors without cutting surrogate pairs or changing native text. Widget delete test pumps frames and IO while awaiting SQLite completion; assertions are retained. Final post-test edits only remove a redundant assertion/add braces/restore line endings. Evidence: word-delete-008.json.

Vivo remains offline after per-device reconnect and ADB server restart. User asked why the screen was idle; clarified that phone testing is stopped by the USB connection while host implementation/testing continues. A USB reconnect/unlock/trust request is pending. No bridge or provider process started; native testing for category/delete is explicitly unverified. The category-only APK predates deletion; build the latest source for the next native run. Goal remains active; no whole14-workflow/mode acceptance or production readiness claimed.


### Optional import continuation — 2026-09-21

Typed bulk fill/preview/save now uses the existing manual importer. Real Drift mixed accepted/duplicate/rejected outcomes and replay passed; three targeted Flutter files and 9 Python menu transport tests passed. Preview explicitly does not check database capacity/duplicates or persist. Analysis clean after braces-only correction. [Evidence](import-mcp-009.json). USB now reports Vivo device, but this source is not yet installed or verified natively. Owner/cancellation/readback adversarial expansion remains pending; all-workflow completion remains open.

Import009 update: 9 import-domain tests passed including wrong-owner, post-owner-lookup cancellation and corrupted readback. APK built and installed successfully on isolated Vivo app; local startup, vocabulary tab and category open/cancel observed without a provider. Connected import/category/delete journeys remain pending. Earlier USB-offline and not-installed statements are historical.


### Vocabulary native010 — 2026-09-21

Live provider category create, mixed import preview/save and confirmed word deletion passed on Vivo at c2210ac4. Native category/word/empty state matched saved/deleted receipts. After disconnect manual invalid-row import returned 0/0/1 and native category cleanup worked. Own fixture, reverse and capability removed; original account retained. Own temporary directory retained after automatic policy rejection of combined cleanup. [Evidence](vocabulary-native-010.json). All14 workflow/mode acceptance remains OPEN.


### Late context011 — 2026-09-21

Reproduced and fixed mounted owner-bound context missing after late AI login. Explicit data-owner bindings survive disconnected/same-owner admission but retire on a different account; generic session context retains previous clearing. Registry/binding and four baseline startup scenarios passed; analysis clean. [Evidence](late-context-011.json). Native build/retest pending. Whole scope remains open.


### Study-plan assistance012 — 2026-09-21

W08 now exposes separate owner-bound summaries of actual proposed and accepted plans to optional AI. Counts, revision, budget, day/timezone and deadline flags come from displayed domain plans; busy/error/unowned states expose nothing. Native controls and persistence remain unchanged. Real-storage test verifies preview does not persist, native acceptance updates summary and owner switch hides context. Screen tests, 7 Python chat tests and analysis passed. [Evidence](study-plan-assistance-012.json). Native and remaining W08 acceptance are pending.


### History assistance013 — 2026-09-21

Owner-bound ordinary history cards expose session evidence separately to optional AI. First/repair answers, self-assessment and reading exposure retain distinct meanings; no overall proficiency inferred. All18 history screen tests, 7 Python chat tests and targeted analysis passed. New context tests use fixture readers. [Evidence](history-assistance-013.json). Pair history, assessment-specific acceptance and native verification remain open. Writer retained; full14 scope remains open.


### Pair history014 and USB display015 — 2026-09-21

Optional Pair history exposes canonical result counts, nullable stars/time and practice-only meaning. Failed purpose verification suppresses scores. Added available/unavailable and owner-fence tests; full history screen suite and analysis passed. [Evidence](pair-history-assistance-014.json). Native acceptance remains pending. User-requested USB stay-awake set to2 and verified awake/powered/stayOn with keyguard not showing; retain during testing. [Device setting](device-stay-awake-015.json).


### Progress assistance016 — 2026-09-21

Dashboard owner-bound summary distinguishes weekly, cumulative and current evidence; no-evidence fields remain absent and zero-sample accuracy nullable. Profile reload/error clears context. Full dashboard tests and analysis passed; fixture-based host evidence, native pending. [Evidence](progress-assistance-016.json). User authorized subsequent entire-project code review, evidence collection, root-cause analysis and sequential SDLC/Agile remediation: [queued plan](post-mcp-project-review-plan.json). Current14-workflow goal remains active.


### Native progress and preview admission017 — 2026-09-21

Built and installed136a11bf isolated APK. Without AI pairing, dashboard27/41, Today and ordinary history opened on Vivo. Planning was hidden by field defaults: introduced explicit Ari-only planning/offline admission while preserving production defaults and research gates. Preview registry and four baseline AI startup cases passed; analysis clean. [Evidence](preview-admission-017.json). Updated preview needs build/install; connected/disconnected acceptance remains pending. USB stay-awake2 retained.
