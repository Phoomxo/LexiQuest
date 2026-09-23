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


### Study-plan native018 — 2026-09-21

Installed e00acb14 isolated preview. Native proposal10minutes, acceptance r1 and reopen passed without provider. Actual provider list_menu_actions read accepted r1/10minutes/0due/0new/0carry-over correctly. After explicit disconnect, native proposalr2/reject retainedr1. [Evidence](study-plan-native-018.json). Browser return required native reload and input-focus recovery re-entered route, so no-rebuild late-attach is not claimed. Empty-plan representative only; fullW08/all14 remains open. Bridge stopped, reverse removed, USB stay-awake2 retained.


### Weakness assistance019 — 2026-09-21

W07 clinic exposes owner-bound evidence summary and mounted word context, distinguishing incorrect history from due SRS. Progress query now carries owner metadata; ownerless legacy data is not shared. Native review/scoring unchanged. Screen and real-query projector suites passed, analysis clean. [Evidence](weakness-assistance-019.json). Native and completeW07 acceptance remain open.


### Export assistance020 — 2026-09-21

W13 optional guidance reports actual format/selection and operation status without sharing file paths or bytes. Native export remains authoritative. Selection changes clear previous saved status. Both export screen/flow suites passed with real local bytes and injected picker; analysis clean. [Evidence](export-assistance-020.json). Native and whole-workflow acceptance pending.


### Offline assistance021 — 2026-09-21

W14 mounted offline rows expose actual state, verification, byte counts, failure and native availability. Downloaded bytes are explicitly distinct from verified readiness or cloud sync. Existing native controls unchanged. Five status cases and full screen regression passed; analysis clean. [Evidence](offline-assistance-021.json). Fake-manager host evidence only; native, cloud-sync and fullW14 acceptance remain open.


### Quest assistance022 — 2026-09-21

Owner-bound quest context exposes persisted state/progress and conditional rewards, preserving native projection and score authorities. Missing definitions remain explicit; bounded title/objectives have truncation flags. Real Drift daily fixture plus complete screen suite passed; analysis clean. [Evidence](quest-assistance-022.json). Native and remaining W10/full14 remain open.


### Rewards assistance023 — 2026-09-21

Owner-bound shop account and catalog contexts separate coins/XP/level and unlocked/owned/equipped/preview states. Canonical avatar load supplies owner metadata; ownerless fixtures are not shared. No new purchase/equip tools. Real Drift context assertions and full equipment regression suite passed; analysis clean. [Evidence](rewards-assistance-023.json). Native and fullW10 acceptance pending.


### Camera assistance024 — 2026-09-21

Optional scan context distinguishes model confidence, mapped vocabulary and accepted persistence without images. New background test exposed stale context after internal invalidation; lifecycle now schedules rebuild and retest passed. Full scanner suite plus final2context cases passed. [Evidence](camera-assistance-024.json). Fake-sensor evidence only; native quality and connection-mode acceptance remain open.


### Shadowing assistance025 — 2026-09-21

Owner-bound final speech context distinguishes transcript similarity from acoustic pronunciation and records actual saved/retry state. Interim/empty input has no invented score; native learning authority unchanged. Full shadowing suite and analysis passed. [Evidence](shadowing-assistance-025.json). Fake speech gateway evidence only; microphone and fullW11 acceptance remain open.

## Native baseline026

Installed source d527c531 (APK hash in native-baseline-026.json). Disconnected native quest details, reward balances, Anki selection and offline download/delete exercised. Offline voice fixture restored to not-downloaded; existing ready content and original app preserved. Shop insufficient-funds feedback and expansion accessibility labels are review candidates, not resolved defects. Live-provider checks for019–025 and all14 acceptance remain open. Whole-project SDLC/Agile review remains queued after current acceptance under post-mcp-project-review-plan.json. USB stay-awake2 retained.

## Offline native027 and byte interpretation repair

Live provider context read and refresh on the mounted Vivo offline screen succeeded before/after a native download. Found misleading3066/708-byte ratio: manifest payload and installed total include different files. Added explicit byte meaning and non-comparability to optional AI context; five red assertions reproduced the missing contract and the full screen suite passed after repair. Native repair retest remains required; all14 acceptance remains open. Explicit disconnect preserved native removal; temporary voice fixture removed, original content/accounts and USB stay-awake retained. Details: offline-native-027.json.

## Native connected context028

Source64710021 installed and tested with live provider. Original offline prompt now reports verified5819/3066 bytes separately; misleading ratio not repeated. Quest5/5 and conditional50XP, shop15coins/75XP/level4/next5XP, and Anki vocabulary-only idle guidance matched native UI. Tool receipts observed. Explicit disconnect retained manual PDF selection. No reward mutation or file export acceptance claimed. Bridge/reverse stopped; original content/accounts retained and temporary voice fixture removed. Full scope remains open; see native-context-028.json.

## Review assistance029

Added optional owner-pinned queue summary and mounted-row explanation, separating due SRS from saved/reported/incorrect reasons. Empty queue is explicit; no learner answer or scoring tools added. New context tests failed before implementation; full screen and reader suites passed afterward, targeted analysis clean. Native029 not run; installed APK remains64710021. All14 acceptance remains open. Evidence: review-assistance-029.json.

## Settings assistance030

Bound display context and existing AI setting actions to canonical preference owner. Cloud context now distinguishes service availability from unobserved sync completion. Full settings suite passed; wrong-owner access rejected. Corrected historical test owner prefix mismatch without weakening assertions; final analysis clean. Native030 and real cloud sync remain pending. Evidence: settings-assistance-030.json.

## Lesson disconnect031

Added and passed a shared-controller regression across four registered adapters (associative reading, meaning quiz, flashcard, typed recall). During a blocked durable answer write, simulated provider-owner loss hides context; completion and replay retain exactly one answer record. Reattachment exposes only committed feedback. Real controller/Drift host execution, not native mode UI or live provider interruption. No production source changed. Full14 acceptance remains open. Evidence: lesson-disconnect-031.json.

## Native review/settings032 baseline

Installed6fc67593 isolated APK. With provider disconnected, completed book review1/1 and returned to canonical queue. Native light/reduced-motion settings retained across route reentry; restored original system/false values. Automated review fixture remains in test app only. Initial accessibility output problem recovered via file dump; app remained alive/awake. Connected AI029–030 and whole14scope remain open. Evidence: review-settings-native-032.json.

## Live settings/review/progress033

Same-owner Vivo live provider read settings and changed/restored theme with tool receipts and native chip verification. Review10/0due, progress28/42and1523seconds, weakness42sample/11words/spoon1wrong matched native values. Cloud readiness and historical errors correctly distinguished from sync completion/SRSdue. Explicit disconnect retained native list scrolling. No new practice answers; original accounts and restored display settings preserved. Remaining history/camera/speech/mode acceptance stays open. Evidence: settings-review-progress-native-033.json.

## Camera/speech native034

Disconnected camera capture returned unknown-object guidance; resume reset result. Speech recording start/stop produced unclear-speech guidance without a score. Android Back returned to dashboard28/42 unchanged, active time26m13s (previous25m23s),0due. External floating bubble intercepted a coordinate tap; app restored and Android Back used. USB stayawake2 verified. These observations do not establish recognition accuracy or connected assistance acceptance. Full scope stays OPEN. Evidence: camera-speech-native-034.json. Whole-project review remains queued after MCP acceptance; findings schema and sequential SDLC/Agile repair criteria recorded in the existing plan.

## Pairing recovery035

Native history baseline loaded abandoned shadowing with no first answers. Live history check exposed actual debug pairing loss after Android recreation and stale capability across bridge rotation. Retain private pairing with explicit15minuteUTC expiry; reload on explicit login and invalidate old transport binding. Red tests reproduced both defects;14Flutter and16Python tests passed, analysis clean,debugAPK built/installed. Native force-stop/relaunch retained pairing and requested a login challenge. Authenticated browser-return and native rotation retests remain pending; no provider reply this batch. Original accounts preserved; bridge/reverse/privateconfig cleaned; USBstayawake2 retained. Evidence: pairing-recovery-035.json. Full14scope OPEN.

## Camera result and live evidence036

Live history matched abandoned shadowing0/0and235seconds; no proficiency inference. Native newbridge pairing and browser return succeeded. Camera notConfident exposed misleading AI claim that scan result was ready: ready meant camera availability and omitted error/result state. Renamed cameraReady,added scanResultAvailable/visibleMessage and prompt interpretation. Regression red then40screen tests/16Python testsPASS,analysis/buildPASS. NewAPK live retest correctly reported no scan result and retake guidance. Shadowing guidance usedbag without invented score; explicitdisconnect retained native0percent exercise. Dashboard28/42unchanged,30m53s. Disconnected camera produced unmappedmatchstick16percent; no groundtruth/accuracy claim. One empty testshadowing session retained. All14acceptanceOPEN; full provider recovery after forced process death during authorized browser flow remains unproven. Evidence: camera-result-036.json.

## Process recovery037

After browser confirmed authorization, forced isolated app process death (PID11345to15762). Baseline reopened; pairing survived but startup cleared provider session. Explicit reauthentication succeeded through browser return and live menu-read reply. This verifies recovery with a fresh login, not seamless restoration. Dashboard28/42,30m53s,0due unchanged afterdisconnect. Added realDrift/mockprovider integration proving explicit connection, durable owner-generation invalidation, reauthentication and unchanged answerAttempts.11testsPASS,analysisclean. Fixture issues corrected with evidence: initial-bootstrap timing assumption,offscreen tap and unbuilt lazy status text; assertions now check real controller state and exact provider requests. No product behavior changes. Cleanup complete and USBstayawake2 retained. Full14scope remainsOPEN. Evidence: process-recovery-037.json.

## Transfer-probe assistance — checkpoint038

Added optional owner-bound read-only method/committed-feedback context. Before a durable result, no answer or sentence is exposed; AI cannot submit answers, request hints or write scores. Native hint usage is identified separately from AI usage, and local timing is explicitly unverified. Three new real-Drift widget cases cover correct, assisted incorrect and failed-write/retry outcomes. Red missing-context failures preceded implementation;33tests passed across probe use-case/policy suites and analysis was clean.

APK038 built and installed on isolated Vivo. Provider-free Today/Review/dashboard navigation passed;28/42responses,30m53s,0due unchanged. USB stay-awake remains2. Probe live acceptance remains pending because existing rollout is off; no rollout/research activation or device-clock changes were made. All14 workflow/mode acceptance remains open. Whole-project SDLC/Agile review remains queued after current scope. [Evidence](transfer-probe-038.json).

## Scramble feedback and state preservation — checkpoint039

Fixed two defects: word/sentence native evidence bypassed the shared controller, leaving committed count0 after a real write; the production native loader recreated the game when its first feedback panel appeared. Both reproduced before fixes. Existing pending evidence now records through the lifecycle controller and loader structure remains stable. Six production-loader widget cases cover absent AI/registry present/registry disconnected during commit for both modes; exactly one durable answer and preserved State identity. Screen24 and loader77 regressions passed; analysis clean.

On final APK039, Vivo completed bag and I carry my clothes in a bag. with correct committed feedback and retained selections. Initial039APK exposed the remount defect; that build is not accepted. Provider remained disconnected. Three recreational test responses are retained in isolated history; dashboard mastery counts remain28/42 by existing evidence classification. USBstayawake2 retained. Live provider read-back of these results and full14scope remain open. [Evidence](scramble-feedback-039.json).

## Live scramble assistance and disconnect — checkpoint040

UnchangedAPK039 passed live-provider checks onVivo: sentence method guidance without target answer; exact committed sentence result read back without including the answer in the prompt; subsequent word mode result correctly read as bag rather than stale sentence context. Native controls submitted all responses. With I carry my already selected in a new sentence, explicit AI disconnect preserved the draft; remaining four words completed a correct result. Three additional recreational test submissions retained; mastery dashboard28/42,30m53s,0due unchanged.

Bridge22745 stopped, ownedreverse/privatepairing removed, no8765listener; USBstayawake2 retained. No new host tests because application source unchanged. Other modes/14workflow acceptance remain open. [Evidence](scramble-native-040.json).


### Speaking optional context — checkpoint041

Owner-bound read-only context separates final transcript similarity from acoustic pronunciation and storage acknowledgment. Four new screen cases use repository/recognizer doubles; final 50 targeted speech tests passed. A red/green regression preserves the saved receipt when raw speech is cleared for privacy. Source and receipt pins: [evidence](speaking-assistance-041.json).

Vivo intermediate build returned noMatch for PC synthetic speech and app TTS; successful native recognition remains pending. Final receipt-fix APK installed successfully and opens the baseline home; no live provider trial in041. USB stay-awake remains2. Whole14workflow/mode acceptance stays OPEN. Whole-project code review/data/root-cause analysis and sequential SDLC/Agile repairs remain queued after MCP acceptance per the user request.


### Shadowing save acknowledgment — checkpoint042

Confirmed premature saved-state defect by holding the repository acknowledgment: old context reported true while still pending. Moved saved=true after the successful await, retaining existing pending/epoch guards. New test verifies pending false, acknowledged true, single write despite duplicate final, one close and no AI actions. Full26 shadowing tests and targeted analysis passed. [Finding and evidence](shadowing-save-042.json).

Final042 debug APK built/installed and baseline home smoke passed. Successful physical recognition and live-provider validation remain pending; installation is not functional acceptance. Whole-project review remains queued after current MCP scope.


### CEFR optional article context — checkpoint043

Added bounded owner-bound excerpt/selected word and explicit reading-exposure interpretation. Screen-only completion remains distinct from acknowledged evidence and does not claim comprehension or CEFR certification. Seven production-loader/library tests use real Drift in-memory; six reader tests passed. Connection cases here are registry-state tests, not live-provider proof. Targeted analysis clean. [Evidence](cefr-assistance-043.json).

Final043 APK built/installed on Vivo. Without provider connection, A1 article opens, word book selects and native completion works. Audible playback and live CEFR assistance remain pending. Original app/accounts preserved; USB stay-awake2 retained. Whole14workflow/mode goal remains active and unaccepted.


### CEFR live context and picker separation — checkpoint044

Live provider exposed a prompt defect: article-selected book was explained but then rejected because the independent vocabulary picker was empty. Clarified bridge instructions to use reading/article-assistance directly. Existing7 bridge tests pass; semantic acceptance comes from the fresh live retest: same target-free question returned current selected bag, correct title and screen-only completion without an invalid-selection claim. [Evidence](cefr-native-044.json).

Native completion worked while connected; after explicit disconnect the article retained completion and selected word changed to blue. No scored answer submitted, acoustic playback not certified. Both bridge processes terminal; owned reverse/private pairing removed; USBstayawake2 preserved. Full scope remains OPEN.


### CEFR session durability and history — checkpoint045

Native no-provider session was initially unavailable without leveled personal vocabulary. Created isolated AriCEFR045 category and added catalog a/A1 through native controls, then completed one CEFR reading session. Read-only SQLite/WAL copy after force-stop proves exposure attempt and completed session; history survives restart. Legacy wrong_count1 remains internal and is excluded from first-answer accuracy by existing history projection. [Evidence](cefr-session-045.json).

Added CEFR to shared visible/AI reading-exposure interpretation. Regression failed before fix;21history screen tests and two-file analysis pass. Final045 built/installed; native history explicitly says reading exposure is not correctness. Retain named test fixture for connected/disconnected session tests. All broader acceptance stays OPEN.


### Dictation registry parity on native screen — checkpoint046

Six new cases cross correct/incorrect answers with absent/connected/disconnected registry. Actual production screen/loader/controller and Drift in-memory preserve typed input, one durable write and committed feedback; target answer stays hidden until commit and owner changes hide old context. Voice is a test double and registry state is not live-provider evidence. Ten targeted dictation cases and analysis pass. [Evidence](dictation-disconnect-046.json). Production unchanged; APK045 remains installed, native audio/provider coverage pending.

### Handwriting optional assistance — checkpoint 054

Added owner-bound, read-only method guidance to the standalone scratchpad. Private strokes and typed text stay local; guidance cannot grade or award progress. Seven selected host tests pass, including absent/connected/disconnected variants with all-table storage invariance. APK054 built and installed on Vivo; baseline drawing, undo and both empty/populated self-check feedback observed. Native live-provider guidance/disconnect remains pending; this does not close the 14-mode goal. See [structured evidence](handwriting-assistance-054.json).

### Handwriting live guidance — checkpoint 055

APK054 live provider returned Thai method guidance and correctly denied private stroke/text access, grading and rewards. A connected stroke survived explicit disconnect; clear and subsequent drawing/self-check continued manually. Repeated self-check captured its transient feedback. Native DB was not re-snapshotted; host054 supplies storage invariance evidence. Bridge cleaned up. [Evidence](handwriting-native-055.json). Flashcard next; full goal open.

### Flashcard method/state context — checkpoint 056

Canonical SRS screen now publishes owner-bound read-only phase/reveal context, distinguishing exposure from independent recall. Full screen suite passed with three connection variants preserving state, exposure rows and unchanged SRS schedule. Owner fixture and asynchronous example-load synchronization corrected without removing assertions. Analysis clean; APK056 installed and home ready. Native mode/live/disconnect and independent-rating/retry context coverage remain open. [Evidence](flashcard-assistance-056.json).

### Flashcard native journey — checkpoint 057

Live AI correctly read revealed card1/10 and distinguished exposure from independent recall. After explicit disconnect, the ten-card session completed with exactly eight exposure and two self-rating records. Legacy numeric aggregate is not recall accuracy. Found OPEN FLASHCARD-PROGRESS-057: shared progress stayed0% while card index advanced; next work must diagnose/fix with regression coverage. [Evidence](flashcard-native-057.json). No full acceptance claim.

### Flashcard progress repair — checkpoint 058

FLASHCARD-PROGRESS-057 fixed: native evidence acknowledgements now update shared progress without another write. Three connection variants reproduced0 instead of1 before repair. Full26 screen tests pass, including failure/retry count invariants for both self-ratings. APK058 on Vivo shows0/50/100% for a two-card exposure review and returns home. Analysis clean. [Evidence](flashcard-progress-058.json). Remaining full-goal acceptance open.

### Typed recall native baseline — checkpoint 059

Two-item mixed route completed without provider. Blank typed submit disabled; actual result1 correct/1 wrong agrees with two durable rows classified recognition and independentRecall. Found OPEN TYPED-FEEDBACK-ACTION-059: final wrong feedback says try again but only results is available. Fix before acceptance; live/disconnect partial-input coverage remains pending. [Evidence](typed-recall-native-059.json).

### Quiz feedback continuation — checkpoint 060

TYPED-FEEDBACK-ACTION-059 host fix: feedback now names the actual host continuation (next question/results). Correctness, committed answer and persistence retries unchanged. New final-wrong regression cases and non-final assertions pass in the full quiz/panel suites; analysis clean. Native build/retest pending;installed APK remains058. [Evidence](feedback-action-060.json).


### Native typed recall 061

APK061 from845492e3: live provider identified typed recall and returned Thai method guidance. Explicit disconnect preserved partial `wro`; appending `ng` produced committed `wrong`. Final feedback correctly named results. Native SQLite confirmed completed session with exactly2 attempts (recognition correct, independentRecall incorrect), score50%. Current translation direction was not exposed by method context; response asked user. All14 workflow/mode acceptance remains open. See [evidence](typed-recall-native-061.json). Bridge stopped and private debug connection removed; original app/accounts preserved.


### Quiz current question context 062

061 revealed session mixed direction was insufficient for active-question guidance. Added owner-bound readonly metadata from actual quiz controller: prompt/answer languages, choice/typed response, index and phase; no draft or hidden answer. Red reproduced missing binding in2 connected variants, absent baseline passed. Full36 quiz screen tests pass, including3 new real-storage absence/connected/disconnected journeys, owner fencing and retained draft; analysis clean. APK062 built and installed. Live provider retest remains pending, all14 acceptance remains open. [Evidence](quiz-context-062.json).


### Quiz current question native 063

APK062 live provider correctly identified first question English-to-Thai choice, then second Thai-to-English typed in same conversation. Partial ba retained after explicit disconnect; appending g committed bag. Results100%;SQLite exactly2 correct attempts (recognition and independentRecall). First request occurred with an accidentally opened exit dialog; provider withheld underlying quiz context, then fresh request after dismissing dialog passed. [Evidence](quiz-context-native-063.json). Bridge cleaned; original app preserved; all14 acceptance remains open.


### Definition context 064

Added owner-bound readonly current-item metadata (choice/skip, reason, phase, English definition-to-English word) and corrected wrong-feedback continuation to actual next/results.10 full definition screen tests pass, including absence/connected/disconnected exact2 incorrect recognition attempts and no SRS, plus skip-to-question with no answer evidence. Initial new-test fixture hang resolved with runAsync owner read; acceptance unchanged. Analysis clean. [Evidence](definition-context-064.json). Build/native pending; installed device remains062. All14 acceptance open.


### Definition baseline native065

APK065 built/installed. Without AI, skip-only completed with0 attempts and0 wrong. Three-item route skipped unreviewed a then manually answered bag/book incorrectly; exact2 incorrect recognition attempts, final0correct/2wrong. Continuation labels now match next/results. New defect DEFINITION-PROGRESS-065: shared header stays0% after committed responses; item index advances. Fix before live acceptance. [Evidence](definition-native-065.json). No provider test this checkpoint.


### Definition progress066

Fixed DEFINITION-PROGRESS-065: native review now tracks acknowledged unique response indices and reflects count through existing session-fenced read-only lifecycle. Skips do not inflate answers. Red3 screen variants reproduced0 instead of1. Full17 definition screen/adapter tests pass, including skip/acknowledgment-failure/exact-retry invariants;4-file analysis clean. Native build/retest pending;device still065. [Evidence](definition-progress-066.json).


### Definition native live067

APK067 verifies DEFINITION-PROGRESS-065 repaired: after skip, committed answers update shared header33 then67percent (2/3 configured;skip not counted as answer). Attached provider during third item;live Thai response correctly names mode3/3,English definition/choice and not-skipped state. Explicit disconnect retained item;manual completion100%accuracy,exact2 correct recognition attempts2/3. [Evidence](definition-live-067.json). Native live skip guidance still pending. Bridge cleaned;all14 acceptance open. Cloze inspection shows similar missing lifecycle progress reflection;test next.


### Cloze context/progress068

Added readonly owner-bound active cloze input-mode/phase/index/skip metadata without draft or answer. Fixed acknowledged count reflection and feedback next/results label. Red: absent progress0 vs1,connected/disconnected no context. Full22 screen/adapter tests pass;3 real-storage variants preserve draft,owner fencing,typed correct plus selected wrong through completion with exactly2 evidence rows. Ack failure remains0 until exact retry1.4-file analysis clean. [Evidence](cloze-context-068.json). Native067 unchanged;cloze skip assertions and native acceptance pending.


### Cloze skip069

Focused real-storage regression verifies skip context reason/phase,transition to choose-input-mode,0committed until actual typed answer then1at index2. Initial test submit lookup required a pump for rebuild;enabled assertion preserved. Prior22tests reused unchanged production. APK069 built/installed;native skip-only without AI completes with no-answer UI and0database attempts/0wrong. [Evidence](cloze-skip-069.json). Native reviewed typed/selected/live journeys pending;set itemCount3 next.

## Cloze baseline native — checkpoint070

APK069 on Vivo, provider disconnected: typed bag correct and selected bag for book incorrect, both locked after submission. Empty typed/unchosen selection guarded. Shared progress 0→33→67 for two answers/three configured items; optional unscored speech does not block next/results. Results50%,1correct/1wrong; real SQLite confirms exactly clozeTyped/independentRecall true at2 and clozeSelected/recognition false at3, no skip attempt. Isolated app restarted; original accounts preserved. [Evidence](cloze-native-070.json). Native live context/disconnect remains next; physical speech and whole-goal acceptance remain open.

## Cloze live continuity and guidance defect — checkpoint071

APK069 provider recognized skipped1/3 and typed2/3 English context, but incorrectly described only Back/no next control while controls were below AI panel. CLOZE-MANUAL-GUIDANCE-071 remains open pending native retest. Partial ba survived chat/disconnect;appending g gave correct bag;selected book completed100% with exact2attempts/no skip row. Added read-only phase-specific manualNextStep with collapse/scroll and editorial skip meaning. Red missing-context assertion reproduced;full cloze screen+adapter tests PASS;2file analysis clean. APK071 built/installed;fresh live retest next. Bridge stopped/config removed;original app preserved. [Report](cloze-live-071.json).

## Cloze native guidance retest — checkpoint072

APK071 fresh live provider correctly described skip1/3→ดำเนินต่อ,typed2/3→ตรวจคำตอบ,and selected3/3→choose/check in one conversation,each with collapse-AI/scroll instruction. CLOZE-MANUAL-GUIDANCE-071 verified fixed for these reproduced cases. Explicit disconnect before last manual answer retained baseline;100%2correct0wrong with exact2durable attempts at2/3,no skip or AI answers. Source pins match071;23host tests reused. Updated cloze evidence index;whole scope remains OPEN. Bridge/config cleaned,USB stayawake2 preserved. [Evidence](cloze-guidance-072.json). Next:definition live skip and associative context.

## Definition live skip — checkpoint073

APK071 provider correctly describes skipped definition1/3 English→English,no answer to grade,and Continue. Reply uses English Continue rather than Thai button label;no exact-label claim. Explicit disconnect at skip retains manual advance;bag/book answers complete100%2correct0wrong. Exact2recognition attempts at2/3,no skipped or AI response row. [Evidence](definition-skip-live-073.json). Updated mode ledger;overall acceptance remains OPEN. Bridge/config removed,isolated home restored. Next:associative native context.

## Associative blank recall guard — checkpoint074

Native baseline exposed ASSOCiATIVE-BLANK-074:empty Stage3 submit persisted one wrong independentRecall and froze input. Corrected screen guard before capture for blank/whitespace and composing text,leaving frozen retry semantics intact. New regression red before fix;26full screen tests PASS after updating four later-stage fixtures to enter answers;2file analysis clean. APK074 built/installed;native blank stays editable atStage3 with validation message,real SQLite0attempts0wrong. Current bottle session remains active atStage3 after snapshot/restart. [Evidence](associative-blank-074.json). Six-stage valid continuation and owner-bound actual-stage AI context remain required;no whole-mode PASS.

## Associative baseline completion and progress — checkpoint075

APK074 resumes Stage3 after restart;valid bottle answer reaches stages4–6 and completes. SQLite confirms1correct independentRecall,water-container keyword,and reading progress completed at6. Stage5 sentence is ephemeral/ungraded,not persisted. Shared header remains0after answer:ASSOCIATIVE-PROGRESS-075 reproduced in host expected2actual0. Reflect acknowledged native count using union of restored/committed indices;26screen tests and2file analysis pass. APK075 built/installed;native progress retest pending. [Evidence](associative-baseline-075.json). Actual-stage AI binding and fullscope acceptance remain open.

## Associative actual-stage context — checkpoint076

APK075 fresh native recall updates shared0→100;SQLite confirms1correct independentRecall. Round left active atStage4. Added owner-bound readonly six-stage context with method/nextstep and honest Stage5 ephemeral/ungraded policy;no answer/draft/passages exposed. New absent/connected/disconnected flows cover6stages,retained draft/manual submit while disconnected,owner fence and disposal. Recording repository count1;existing realDrift tests retained. Red missing context;29fullscreen tests PASS and2file analysis clean. APK076 installed;live stage guidance and restored shared-progress check next. [Report](associative-context-076.json). Whole-goal acceptance open.


## Associative restoration — checkpoint077

Restored shared count now reflects acknowledged occurrences after owner revalidation. Broader tests exposed a second bug: blank validation included locked restored fields, blocking partial recovery; validation now covers only uncommitted occurrences. Updated later-stage fixtures to submit actual recall input, preserving exact durable-pair assertions. All61 tests across session/launcher/restart pass; three-file analysis clean. APK077 installed; Vivo restores Stage4 at100%, SQLite retains exactly1correct independentRecall and0wrong. Continuation is capped by durable600-second effort matching configuration; no timer reset or duplicate write. Live AI stage guidance still pending in a fresh round. [Evidence](associative-restoration-077.json). Whole-goal acceptance remains OPEN.


## Associative unavailable-state guidance — checkpoint078

Both emergency-off Stage3 and restored600-second effort cap incorrectly exposed ready/tap-next context. Red tests reproduced both. Readonly context now exposes feature-unavailable or operations-unavailable and respects actual disabled controls; no change to persistence or timer gates. All58 session/launcher tests pass, including real SQLite reopen with unchanged answer IDs/event/SRS/reward counts and stale-submit no-write. Three-file analysis clean. APK078 built and installed;USB stayawake2 retained. Live provider retest and fresh six-stage/disconnect journey remain pending. [Evidence](associative-availability-078.json). Full goal remains OPEN.


## Associative live guidance and compact viewport — checkpoint079

APK078 live provider correctly described Stage1/6 A2,ungraded reading,manual next and collapse/scroll. Explicit disconnect atStage1 did not interrupt remaining stages;door round completed with exact1correct independentRecall,0wrong. Expired-provider prompt was not sent: initial field focus failed and Back left the capped round;no PASS claim or timer reset. Native AI expansion exposed105pixel overflow. Host short viewport reproduced20pixel overflow;responsive whole-content scroll fixes compact mode.29screen tests pass;strengthened focused test verifies next control reachable across all6stages;2file analysis clean. APK079 installed;native expanded Stage1 screenshot has no overflow stripe,collapse restores full content. New bottle round leftStage1,0answers. Bridge/config removed. [Report](associative-live-079.json). Remaining live stages2-6 and expired response explicitly pending;original goal remains OPEN.


## Associative remaining live stages and limit — checkpoint080

Unchanged APK079: one live conversation correctly described stages2–6,including no answer atrecall,saved non-graded associations,ephemeral non-graded sentence,and manual finish required. Connected round completed with exact1correct independentRecall,0wrong. Separate60second round configured through UI reached its real effort cap;AI correctly recognized unavailable operations and did not suggest submit/advance/reset/completion. Leaving via supported Back marked it abandoned with0attempts and durable60000000us.10minute configuration restored;bridge/config removed and isolated home. Reuse unchanged host079/078/077 evidence. [Report](associative-stages-080.json). Associative representative acceptance evidence now covers allsixstages and limit;final whole-scope audit and other workflows remain open. Next native export/readback.


## Native personal export/readback — checkpoint081

Unpaired APK079 saved4personal formats through real Android document picker. Anki237bytes matches exact owned-vocabulary projection (1row,4columns);CSV14579bytes reconciles113rows/IDs/fields (1vocabulary,108attempts,4reading),no duplicate/omitted evidence IDs. PDF19430bytes renders4readable Thai pages,matching counts. Owner JSON297463bytes validates content hash,58-table manifest envelope and3corecollectioncounts;not a full transformed-field audit. CSV cancellation leaves no new destination. Raw artifacts stay ignored/local,not committed or sent to AI;research export/activation not performed. [Evidence](export-native-081.json). Source unchanged;existing host020 reused as historical evidence,not a rerun. Native live format guidance/disconnect and failure-context audit remain.


## Export context continuity — checkpoint082

Five new failure/reconnect journeys exposed missing saved context after disconnect and manual retry. Export guidance now binds to the existing local owner, following article-reader isolation; no owner means no optional context, while native saving remains available. Eighteen host tests pass, including five safe failure codes, real temporary-file retry, first AI attachment after save, foreign-owner suppression, unavailable owner lookup, and pending/cancelled states. Three-file analysis clean. Initial fixture mismatch omitted the repository local: prefix; corrected without weakening assertions. APK082 built and installed in isolated package; existing Kotlin plugin migration warnings remain. Native live provider guidance is NOT_RUN on082, not inferred from host results. [Evidence](export-context-082.json). Full goal stays OPEN.


## Live export and reconnect recovery — checkpoint083

APK082 live provider accurately reported CSV/all three selections/idle and no file or path access. Native Anki cancellation produced no destination;picker lifecycle deliberately disconnected AI. Subsequent manual Anki save succeeded with237bytes exactly matching reconciled081. Browser re-login succeeded but room remained unavailable. Host regression reproduced stale MenuChannel.end against the deleted previous private home;ChatSession now retires mailbox before parent cleanup.26 bridge/channel/login tests PASS,including fresh room and repeated close after real directory cleanup. Native post-fix reconnect and saved-state guidance are NOT_RUN; no acceptance inferred. Bridge/reverse/config cleaned,isolated app restarted. [Evidence](export-live-083.json). Background/picker re-login and standalone delivery remain W01 limitations;whole goal OPEN.


## Native reconnect and export metadata — checkpoint084

Same corrected bridge process survives document-picker disconnect,explicit re-login,and new room creation. Actual provider reads CSV reading-only saved status without file/path access. Native CSV1214bytes contains4reading rows exactly matching reconciled081,zero vocabulary/answer rows. Format changes to owner archive and PDF yield correct new format/scope and unsaved status. Anki correctly excludes reading but says only word/meaning because formatPurpose omitted category/recordId. Added actual-byte/context regression (RED missing columns);purpose and ordered column descriptor corrected.18 export tests PASS,two-file analysis clean,APK084 built/installed. Live Anki wording after fix remains NOT_RUN. Other reconnect/format results are native PASS,not inferred. Bridge/reverse/configcleaned. [Evidence](export-reconnect-084.json). W06 ledger linked existing080 evidence to remove stale remaining-work wording;no retest or blanket acceptance. Whole goal remains OPEN.


## Nonempty native planning and Anki retest — checkpoint085

Unchanged APK084:baseline native accepts/reopensr2(10min,7due);connected AI distinguishes savedr2 from proposedr3(5min,5due,2carry),then reads manually acceptedr3 and no pending proposal. After explicit disconnect,native proposes/rejectsr4 and reopen retainsr3. SQLite confirms exactly revisions1–3,active3,no rejected4;seven due identities partition5+2. All108answer rows,12SRS,46points-ledger,4reading-progress and39reading-event rows exactly unchanged since081. Browser handoff requires existing explicit reload;no pure late-attach claim. Anki actual-provider retest now lists all4columns correctly and excludes histories. [Evidence](study-plan-native-085.json). No host rerun/source changes;bridge/reverse/configcleaned,isolatedhome. W08 new-item planning/goals/preferences and W10 remain next;whole goal OPEN.


## Learner preferences optional context — checkpoint086

Added owner-bound read-only assistance separating draft from last-confirmed values and ready/editing/saving/saved/invalidDraft/saveFailed. Native controls and existing use-case validation remain authoritative; no AI save action. Two new tests reproduced missing context before implementation. Final11 screen tests pass, including disconnect during pending manual save, same-owner reconnect, foreign-owner hiding and invalid/failed-save disclosure checks; Dart analysis clean. Repository fixtures are host evidence only. APK086 built and installed on isolated Vivo; native no-AI35-minute save, leave and reopen verified. Actual provider connected/disconnected acceptance is pending. [Evidence](preferences-context-086.json). All14 workflows/modes remain open; no Jev integration or original account changes.


## Preferences live provider and keyboard recovery — checkpoint087

On APK086, actual provider correctly separated draft55minutes from lastConfirmed35 and unsaved status, then reported saved55 after native manual save. Explicitdisconnect followed by native40minute save and leave/reopen readback passed. This complements086 baseline. Found CHAT-FOCUS-087: removing chat input restored prior numeric form focus and obscured reply. Both send/disconnect regressions reproduced it; clearing focus before these transitions fixes both in6passing panel tests with clean Dart analysis. APK087 built/installed; physical focus retest remains required before next workflow work. Bridge stopped and reverse/configremoved;originalaccounts preserved. [Evidence](preferences-native-087.json).


## Native chat focus retest — checkpoint088

APK087 actual-provider retest closes CHAT-FOCUS-087. After focusing the underlying40-minute preference field then sending chat, the field remained unfocused and Android inputShown=false; screenshot confirmed no keyboard. Actual AI replied with correct preferences. Explicitly tapping the form still focused it and opened the keyboard. Repeated the prior-form → chat → disconnect sequence: field stayed unfocused/inputShown=false. Reused unchanged six-test087host evidence. No source changes. Bridge stopped, reverse/configremoved, original accounts untouched. [Evidence](focus-native-088.json). Next: W08 goals optional context and nonemptynew-itemplan; full14workflow14modeacceptance remainsopen.


## Optional learning-goal list context — checkpoint089

Added owner-bound read-only goal summary and loaded-row details; owner checked before/after list reads. Identity lookup failure suppresses optional personal context while baseline remains usable. Loading/read-error states omit entries and private exceptions. Context hides across foreign owners and beneath the edit dialog; late prior reads cannot rebind replacement context. Two regressions reproduced missing context; final19tests across new assistance and existing goal screen pass, Dart analysis clean. APK089 built/installed. Native no-AI emptylist → create Practice English089, languageTest, deadline25September2026 17:45Bangkok → leave/reopen retained active/due2days. Actualprovider/nativeedit/status/disconnecteddelete and dialogassistanceaudit remain. [Evidence](goals-context-089.json). No originalaccount changes;all14workflow14modeacceptance remainsopen.


## Native goal update and disconnected lifecycle — checkpoint090

On unchanged APK089, actual AI reported the created goal title/active status/deadline25September2026 17:45Bangkok correctly. Native edit appended revised and manual status changed to completed; a fresh provider reply reflected both and explicitly did not infer language proficiency. After explicit AI disconnect, native cancellation persisted across reopening; deletion then reopening showed emptylist. SQLite confirms cancelled/deleted tombstone. Exact108answer,12SRS,46points,4readingprogress and39readingevent rows match085; no fabricated learning evidence. Reuse089hosttests;no sourcechange or rerun. Bridge stopped/reverse/configremoved;isolatedhome restarted;originalaccountsuntouched. [Evidence](goals-native-090.json). Goal-dialog assistance audit/new-itemplan and whole-goalacceptance remainopen.


## Goal editor optional assistance — checkpoint091

Added owner-bound read-only editor context separating current draft from initial last-confirmed goal. Native controls remain authoritative; no AI save action. Tracks draft/submitting/invalidDraft/preparationFailed/confirmationUnknown and pending-command retry semantics. Tests reproduced missing dialog context, then a preparation lookup failure incorrectly classified invalidDraft; corrected status and native error text without exposing exceptions. Final23tests across assistance/baselinegoalsscreen PASS; Dart analysis clean. Tests include owner fencing, disconnect during manual pending save, reconnect after success/failure, unchanged confirmed data during uncertainty, invalid missing deadline and cancel. APK091 built/installed. Actual provider/dialog native acceptance is pending;no reused list evidence claimed for editor. [Evidence](goal-editor-091.json). Originalaccountsuntouched;full14workflow14modegoalremainsopen.
