# LQ-06 AI Tutor, Voice & Camera — Ground/Plan checkpoint

Latest execution state: ดูหัวข้อ **T1 final handoff / slot return — 2026-10-21** ด้านล่าง; Ground/Plan, M1a และ T1 Running เป็น historical predecessor evidence ไม่ใช่ gate หรือสถานะล่าสุด

- วันที่: 2026-10-20 (Asia/Bangkok)
- Chat / card: `LQ-06 AI Tutor, Voice & Camera` / `I5` และ voice/camera journeys
- ADLC: Intent → Ground → Plan; implementation gate ยังปิด
- Branch: `feature/associative-reading-loop`
- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- HEAD: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`; dirty checkout ร่วมกับแชทอื่น
- Authority: active integrated plan §I5, §13 และ `2026-10-20-lq-00-wave-0-checkpoint.md`
- Data classification: local source review; runtime/provider/device verification not run
- Operating cap: 30 credits; ไม่อ้างว่าสามารถวัดเครดิตรวมของผู้ให้บริการจาก CLI ได้

## Outcome and user-visible behavior

ส่ง proposal จาก source จริงสำหรับผู้ช่วยฝึกภาษาอังกฤษแบบ Messenger/Socratic และ voice/camera permission/failure journeys ไม่มี runtime behavior เปลี่ยนในรอบนี้

สถานะ I5 ยังคง `DESIGNED / PARTIALLY IMPLEMENTED / NOT VERIFIED`. LQ-00 Wave 0 ระบุ `CLOSED` เนื่องจาก source freeze และ writer serialization ยังไม่ผ่าน จึงไม่มี production implementation หรือ Flutter command จาก LQ-06

Tutor UI รอ auth/session contract จาก LQ-02 และ I2; source-aware handoff รอ LQ-03/I4. Voice/camera เสนอแยกได้ แต่ Execute ต้องมี write ownership จาก LQ-00 ก่อน เอกสารนี้ไม่เปิด gate แทน LQ-00

## Changed files and shared-file touches

LQ-06 เพิ่มเฉพาะ `docs/field/2026-10-20-lq06-ground-plan-checkpoint.md` ตาม handoff §13.5; ไม่แก้ active plan หรือ checkpoint ของแชทอื่น

Direct tutor/Gemini/media-practice/voice paths ไม่มี tracked diff ณ focused observation. ไฟล์ shared ที่มี diff อยู่ก่อน ได้แก่ `app_bootstrap.dart`, `main_navigation_screen.dart`, learning use cases/repository/screens และ tests; ต้อง preserve และ re-ground ก่อน Execute. `ai_reading_content_adapter.dart` มี pre-existing diff และถูก LQ-00 ล็อกไว้ จึงไม่รวมใน write proposal นี้

ไม่มี stage, commit, deployment, cleanup, dependency resolution, schema write หรือ code generation จาก LQ-06. Claude CLI ทั้งสองคำขอจบแล้ว ไม่มี task-owned running process ค้าง

## Grounded impact map and review disposition

| Finding | Source evidence | Disposition / required boundary |
| --- | --- | --- |
| BYOK key และ provider/summary consent ใช้ชื่อคงที่ทั้งเครื่อง | `secure_gemini_settings_store.dart:58`; `account_use_cases.dart:87` เปลี่ยน owner/sign-out โดยไม่มี Gemini transition | **must-fix ก่อนเปิด tutor:** ให้ LQ-02/LQ-00 ตรึง owner scope, logout/account-change cancellation และ policy ของ global key เดิม ห้ามโอน consent/key ให้ owner ใหม่โดยปริยาย |
| Background cancel แค่ speech/TTS; generation ยังกลับมาเพิ่ม bubble/เริ่ม TTS ได้ตาม source path | `ai_tutor_screen.dart:118`, `:134`, `:209`; test background ที่ `ai_tutor_screen_test.dart:97` ตรวจ mic เท่านั้น | **must-fix:** invalidate generation/recognition epoch ก่อน await, cancel pending generation และพิสูจน์ว่า late completion ไม่เริ่ม TTS |
| Voice final ส่ง AI ทันที; ไม่มี review/edit draft ก่อนส่ง | `ai_tutor_screen.dart:165` | **proposal:** STT เติม composer ให้ผู้ใช้ตรวจและกดส่ง ภายใต้ provider consent และ payload contract; ห้ามเปิด attachment/raw-media upload |
| UI กัน double-send แล้ว แต่ use case serializes queued calls; ยังไม่มี explicit session budget/mode/context | `ai_tutor_screen.dart:99`; `gemini_tutor_use_cases.dart:112`; `gemini_contracts.dart:75` | **must-fix ตาม I5:** แยก one-active request จาก queue; ไม่สะสม queued user sends; typed mode/session bounds ต้องมี focused tests |
| Failed prompt ถูกล้างจาก composer และไม่มี edit/retry/local-practice action | `ai_tutor_screen.dart:110`, `:360`, `:385` | **must-fix ตาม I5:** รักษา failed turn identity + prompt/context, explicit retry/edit/cancel และ local learning CTA |
| Source-to-word handoff ยังไม่เป็น contract | `gemini_contracts.dart:106`; `main_navigation_screen.dart:244`; `vocabulary_import.dart:13` | **dependency:** LQ-03 ส่ง owner-validated source revision/reference และ matched word IDs; unknown words ไม่ auto-import |
| Reuse targeted practice ได้ แต่ปัจจุบันชื่อและ activity type เป็น weakness practice | `quiz_screen.dart:12`, `:48`, `:57`; `learning_use_cases.dart:147` | ใช้ authority เดิมได้; ห้ามส่งคำทั่วไปแล้วเรียกว่า “คำที่ผิด” หรือบันทึก weakness semantics โดยเงียบ ๆ เสนอ neutral label/activity intent ผ่าน LQ-04/LQ-00 หากจำเป็น |
| Speech start และ callbacks ไม่มี generation guard | `speech_practice_use_cases.dart:12`; `plugin_speech_recognition_gateway.dart:60`; `speak_to_text_screen.dart:122` | **must-fix:** double-tap/start-after-cancel/late final ต้องไม่ส่ง AI หรือสร้าง learning evidence; ตรวจทุก caller รวม shadowing |
| Empty transcript assessment คืน 0 | `speech_practice_use_cases.dart:52` | **must-fix ก่อนอ้าง speech readiness:** silence/cancel/unavailable ต้องไม่กลายเป็นคะแนนหรือ wrong evidence; เก็บเป็น unavailable และคง local practice |
| OS recognizer ไม่ได้บังคับ on-device | `plugin_speech_recognition_gateway.dart:75` ตั้ง `onDevice: false` | แจ้ง data path ตาม capability จริง; mic permission ไม่เท่ากับอนุญาตส่งเสียงไป provider ห้ามอ้างว่า offline/local-only จนพิสูจน์ |
| VoiceUseCases มีแล้ว แต่ bootstrap ไม่ wire shared voice | `voice_use_cases.dart:25`; `app_dependencies.dart:96`; `app_bootstrap.dart:341` | ส่ง composition proposal ให้ LQ-00; ไม่แก้ shared bootstrap เอง และไม่ตีความว่า P8-A orchestrator เสร็จแล้ว |
| Permanent denial มีข้อความ แต่ไม่มี settings action; scanner initialize ขอ permission เมื่อเปิด route | `object_scanner_screen.dart:354`; `speech_practice_use_cases.dart:18`; `object_scanner_use_cases.dart:111`; ค้น `openAppSettings` ไม่พบใน lib/test | **must-fix สำหรับ C18 acceptance:** rationale ก่อน prompt, explicit start, denied retry/settings action, resume recheck และ typed-input/local-learning fallback |
| Camera มี serialized initialization และลบ capture temp file | `plugin_camera_gateway.dart:51`, `:122`; focused test `plugin_camera_gateway_test.dart` | Reuse; เติมเฉพาะ regression ที่ขาด เช่น read/capture/cleanup failure, pause/dispose race; hardware ยัง not verified |
| Architecture consent check ตรวจแค่ substring และข้อความกำหนด research consent ผิด boundary | `test/architecture/fitness_test.dart:462`; gateway prompt `gemini_rest_gateway.dart:123` | Follow-up ที่เสนอให้เจ้าของ test: ตรวจ provider consent behavior ที่ use-case boundary; ordinary learning ไม่พึ่ง research consent |

Source evidence เป็น static review และ hypotheses สำหรับ RED tests ไม่ใช่ผล reproduce หรือ runtime pass. Reviewer ยืนยันพบ Gemini timeout/abort/typed quota/offline mapping อยู่แล้ว (`gemini_rest_gateway.dart:144`), input 500 chars/output 120 tokens และไม่มี auto-retry (`:89`, `:131`); reuse พฤติกรรมเหล่านี้

## Minimal execution cards proposed to LQ-00

| Card / predecessor | Proposed exclusive write set | Acceptance and first RED checks |
| --- | --- | --- |
| M1 Speech/camera recovery — หลังรับ media ownership | `features/media_practice/application/speech_practice_use_cases.dart`, `data/plugin_speech_recognition_gateway.dart`, media contracts เฉพาะ gap; `object_scanner_screen.dart`, `speak_to_text_screen.dart`, `shadowing_challenge_screen.dart`; related media/screen tests | permission rationale→explicit start; denied/permanent-denied→retry/settings→resume; rapid start ครั้งเดียว; late callback หลัง cancel/background/dispose ไม่เขียน evidence; silence ไม่มี score; camera temp cleanup และ local fallback. Contract signatures เปลี่ยนต้อง update fakes/callers ทุกตัว รวม tutor test โดย serialize writer |
| T1 Tutor contract/lifecycle — LQ-02 auth/session + I2 พร้อม และ LQ-00 เปิด gate | Gemini domain/use cases/gateway/secure-store files; `ai_tutor_screen.dart`; Gemini tests, `ai_tutor_screen_test.dart`, fake controller ใน `gemini_settings_screen_test.dart` | owner switch/logout/revoke cancel และ fail closed เฉพาะ AI; one active request; no user-send queue; modes ต่างกัน; typed input/turn/session bounds; background late reply ไม่เพิ่ม bubble/TTS; failure รักษา prompt; explicit edit/retry/cancel |
| T2 Source/practice/UX — T1 + LQ-03/I4 contract | Tutor screen/Gemini payload fieldsที่จำเป็น; tutor/use-case/gateway tests และ scoped IME/large-text/resize tests | source context bounded/consented; stale revision/foreign owner fail closed; matched word IDs เท่านั้น; handoff ผ่าน learning authority และกลับ chat คง draft; AI reply ไม่เขียน mastery/reward; local CTA ใช้ได้เมื่อ offline/quota/provider down |
| V1 Integration evidence — ทุก writer ส่งมอบและ LQ-00 freeze source | checkpoint ของ LQ-06; shared patches เฉพาะ LQ-00 จัดคิว | serialized focused suites, secret/log inspection และ review disposition บน snapshot เดียว; widget/layout evidence แยก emulator และ physical-device evidence |

ขอบเขตที่ต้องขอ writer window จาก LQ-00 ผ่าน proposal: `app_bootstrap.dart`, `app_dependencies.dart`, root/nested route contract, platform manifests และ dependency files. Learning/quiz label/activity semantics ให้ LQ-04 เป็น writer. ไม่มี schema/backend change จำเป็นที่พิสูจน์แล้ว; `/v1/content` ปัจจุบันเป็น sentence/story generation ไม่ใช่ tutor authority จึงยังไม่ขยาย

### Contract choices to freeze before T1/T2

- Auth/session: active owner identity/epoch, cancellation เมื่อ logout/switch/delete/revoke และการจัดการ global BYOK เดิม; preserve key at rest ได้แต่ห้าม owner ใหม่ใช้จน policy อนุญาต
- Tutor modes: `ช่วยฉันคิดทีละขั้น` ให้ hint หนึ่งระดับและถามกลับ; `อธิบายให้เลย` ให้คำอธิบายตรง ภายใต้ output budget เดิม ทดสอบ request contract ไม่อ้างว่าทุกคำตอบโมเดลถูกต้อง
- Budget proposal: คง 500 input chars, 120 output tokens, timeout 20s, concurrency 1 และ no auto-retry; เสนอเพดาน 8 dispatched requests ต่อ in-memory session ให้ LQ-00 ตัดสินก่อน implement. Count dispatched attempts รวม retry/cancel/timeout เพราะ provider อาจคิดค่าใช้จ่ายแล้ว; validation/offline ก่อน dispatch ไม่ใช้ budget. ไม่อ้าง daily quota/reset หรือ refund ของ BYOK provider
- Conversation: bounded in-memory history/context ส่งได้เฉพาะเมื่อ payload/consent contract ตรึงแล้ว; route exit/owner transition ต้องล้าง. ไม่มี transcript persistence/export/sync และไม่มี implicit queue ขณะ offline
- Source: reference/revision/owner + selected existing word IDs; metadata ที่แสดงกับข้อมูลที่ส่ง provider แยกกัน. Raw source ต้องไม่ถูกส่งโดยปริยาย; stale/unknown/foreign owner ไม่มี auto-import หรือ learning write
- Practice: screen รับ validated intent จากแอปเท่านั้น ไม่ใช้ model-supplied IDs/URLs/tools. ต้องกำหนด neutral semantics สำหรับ source practice ก่อน reuse weakness route

### UX state contract

`idle/draft → sending → answer` หรือ `failed/cancelled`; ตอน sending ปิด send/mic/mode/source change แต่มี cancel. Error เก็บ prompt/context ที่ใช้ส่งจริง; retry เป็น explicit action โดยไม่เพิ่ม bubble ซ้ำ, edit กลับ composer. Cancel invalidates epoch ทันทีและไม่ให้ late answer/TTS กลับมา

Missing key/consent เปิด settings; offline/provider down/timeout/quota แสดงเหตุผลและ local-practice CTA. Local guidance ต้องระบุว่าเป็นข้อมูลในเครื่อง. ไม่แสดง provider recovery/reset time ที่ไม่มีข้อมูล. Resize/rotation คง in-memory draft/messages; process restart ไม่อ้าง restoration ของ transcript

## Contracts/schema/route/feature IDs affected

ไม่มี contract mutation ในรอบนี้. Proposed boundaries: Gemini controller/gateway session/mode/context, media permission/recovery และ source practice intent. Routes ที่มีอยู่: `gemini/tutor`, `gemini/settings`, `practice/object-scanner`, `practice/shadowing`; route ใหม่/เปลี่ยน semantics รอ LQ-00

8/44 mapping ใช้ f13 native-mode integration, f19 hint/context, f38 accessibility, f40 local-first และ f41 controlled rollout; practice ปลายทางใช้ f05/f07/f17 ตามกิจกรรมจริง. Runtime flags `aiTutor`, `speechPractice`, `objectScanner` คง limited; ไม่เพิ่ม feature ID และไม่เปิด entitlement/billing path ล่วงหน้า

## Provider payload and privacy invariants

- Claude critique ใช้ source structure/proposal เท่านั้น ไม่มี key values, transcript, PII, audio/image หรือ voiceprint ใน prompt
- Gemini BYOK key ส่งได้เฉพาะ approved Gemini gateway header; ไม่อยู่ใน prompt/body/URL/log. Learner text/context ต้องมี provider consent และ bounds; optional learning summary คง opt-in เดิม
- Mic/STT เป็นอีก data boundary; recognized text เติม draft และส่งหลัง user action. Raw media/voiceprint ไม่อยู่ใน tutor payload. Provider-generated text ไป remote TTS ต้องผ่าน approved target-text/privacy contract ก่อน; ไม่ส่ง unfiltered PII ต่อโดยอัตโนมัติ
- Camera ใช้ verified local model และ explicit accept ผ่าน vocabulary authority. ไม่เปิด cloud image upload, OCR หรือ voice cloning จาก card นี้
- No raw prompt/transcript/source/response/media in telemetry, crash messages, exports or implicit outbox. AI ไม่เรียก learning/mastery/reward writers; unavailable AI ไม่ปิด local learning

## Focused checks with exact result

| Check performed | Result |
| --- | --- |
| `git branch --show-current`; `git rev-parse HEAD` | `feature/associative-reading-loop`; `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1` |
| Scoped `git status --short` over tutor/Gemini/media/voice paths and tests | ไม่มี tracked diff ใน direct scope ณ observation; shared dirty files preserve |
| `rg` callers/routes/contracts/tests และ reads ของ AGENTS/ADLC/I5/§13/P8 voice/P5/P6/latest checkpoints | Ground evidence ข้างต้น; ไม่พบ LQ-02/LQ-03 acceptance handoff เปิด gate ในเอกสารที่ตรวจ |
| SHA-256 source observations | Tutor screen `7DB1CCBBBADEDB6A72BDA4E3CCD2F044C9F24DE4381E70C6D9CD6F5C39D7D60D`; Gemini use cases `3188663972F90177FD4BFB2F7DAC4B871CEFFBEF573269AB9DBB37EDDD4ED976`; speech use cases `2BDA657DB939B2F2646F849939261814B3986DA43CC5EDCE7926C96F83C40FBE`; camera gateway `1AA1AAD4F4BE217D25C965A8BFFFD8E2D85015467C29FCB91BE759D9BBB097DB` |
| Claude attempt 1 | terminal `is_error=true`, `api_error_status=401`, `Invalid API key`, duration 180725ms, input/output tokens 0, reported cost USD 0; process exited 1 |
| Reconcile before one retry | request 1 confirmed terminal; auth-status check after removing inherited key only in child process still reported logged in/API-key auth. No secret value printed; persistent configuration untouched |
| Claude attempt 2 | terminal `is_error=true`, `api_error_status=401`, duration 191015ms, input/output tokens 0, reported cost USD 0. Shell exit 0 did not override structured failure. Retry budget exhausted |
| Checkpoint section/source-reference/scope/whitespace review | PASS: required handoff fields present, all 4 recorded SHA-256 observations match current scoped files, referenced source paths exist, no trailing whitespace; scoped Git status shows only this untracked checkpoint |
| Flutter unit/widget/golden/analyze/build; backend tests | **not run:** read-only Ground/Plan gate, no implementation diff, shared build/test queue unavailable |
| Emulator/physical device/live BYOK/provider acceptance | **not verified / not run** |

Source fingerprints above identify observations of affected files, not a repository integration freeze. Concurrent unrelated writes invalidate repository-wide evidence; recheck source before running tests

Commands proposed after Execute gate, run serially in the LQ-00 queue:

```powershell
flutter test --no-pub test/features/gemini test/screens/ai_tutor_screen_test.dart test/screens/gemini_settings_screen_test.dart
flutter test --no-pub test/features/media_practice test/screens/object_scanner_screen_test.dart test/screens/speak_to_text_screen_voice_test.dart test/screens/shadowing_challenge_screen_test.dart
flutter test --no-pub test/voice/hybrid_voice_service_test.dart test/voice/hybrid_voice_cancellation_test.dart
flutter test --no-pub test/features/learning/learning_use_cases_test.dart test/screens/quiz_screen_test.dart
```

เพิ่ม scoped format/analyze และ IME/130–200% text/resize tests ตาม touched files จริง. Full regression/build อยู่ที่ integration checkpoint; ไม่ใช้ historical P5/P6/R11 test counts รับรอง source ปัจจุบัน

## Claude review and final disposition

`Claude review: not available` — confirmed 401 ทั้ง initial request และหนึ่ง retry; ไม่มี fresh critique หรือ evidence-derived Claude authorship สำหรับข้อเสนอใน checkpoint นี้. Findings เป็น local Codex/source review

Review disposition: `must-fix` สำหรับ owner/session, lifecycle/callback/no-score และ I5 gaps; `not verified` สำหรับ runtime/device/provider journeys. Ground/Plan document ส่งมอบได้ แต่ engineering completion, release readiness และ implementation gate ยังไม่ผ่าน

## Device/external/release dependencies

ต้องมี LQ-00 writer/serialization window, LQ-02 auth/session contract และ LQ-03 source contractตาม card. Physical permission prompt, denied→settings→resume, no camera/mic, STT locale/offline behavior, rotation/audio interruption/low-memory และ latency ต้องตรวจจากอุปกรณ์จริงพร้อม APK/source identity. Emulator/widget tests ใช้แทน hardware certification ไม่ได้

Historical P8-A provider-neutral orchestration/audio packs/VoxCPM/mirror ยังไม่ใช่งานที่ implement แล้วใน checkout นี้. ไม่เพิ่ม provider, model weights, voiceprint enrollment, transcript DB, PDF/OCR dependency หรือ deployment ใน I5 proposal

## Next executable step

LQ-00 ตรวจ checkpoint นี้และจัด writer ownership/source freeze ก่อนเปิด M1; ส่งข้อสรุป auth owner/epoch/BYOK legacy policy ให้ LQ-02 และ source/ref/word-ID contract ให้ LQ-03 ผ่านช่องทางที่มนุษย์อนุญาต. เมื่อ gate เปิด ให้ re-read actual diff/callers, เขียน focused RED test ของ pending start→cancel→late final ก่อนแก้ shared speech use case แล้วรัน focused suite แบบ serialized

รอบนี้บันทึก handoff ไว้ใน repository เท่านั้น ไม่มีการส่งข้อความข้าม chat โดยอนุมานสิทธิ์จาก delegation message

## M1a execution / slot return — 2026-10-21

### Authority, outcome and scope

- Branch/worktree/HEAD เดิม: `feature/associative-reading-loop`, `C:\Users\Phet\Documents\LexiQuest`, `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`; preserve shared dirty baseline
- Authority: latest LQ-00 checkpoint หัวข้อ `Marketplace partial disposition and M1a transfer` / `LQ-06 M1a exclusive grant`; M1a เป็น sole production writer + serialized Flutter slot ระหว่าง Execute นี้
- ADLC: Intent/Ground/Plan → Execute → Review → Attest; ส่งคืน slot ให้ LQ-00 ตัดสิน Integrate ไม่เปิดการ์ดถัดไปเอง
- Outcome: local speech session lifecycle guards, no-result semantics และ UI/evidence regressions ผ่าน; independent review accepted **bounded M1a local engineering** ไม่ใช่ whole M1/I5, native/device หรือ release readiness
- Write set มีเพียง 6 source/test files ใน manifest ด้านล่าง + checkpoint นี้ ไม่แก้ gateway/contracts/bootstrap/main/theme/Gemini/account/schema/manifests/backend/learning authority
- No dependency install/resolution, generation, schema write, key reads, provider request, transcript/media persistence, research/reward mutation, deployment, commit หรือ cleanup

### Behavior and boundary changes

`SpeechPracticeUseCases` ใช้ generation และ synchronous start guard; cancel/dispose invalidate ก่อน await แม้ยังรอ permission/initialize. Replacement รอ previous startup และ **cleanup ล่าสุด**; platform start ที่กลับมาหลัง cancel ถูก cancel ซ้ำก่อน replacement เปิดรอบใหม่. Cleanup failure ส่ง error จริงและ block start จน explicit successful cancel ไม่กลืน failure เพื่อเปิด mic ต่อ

Final ถูกส่งไม่เกินครั้งเดียวพร้อม event/provenance เดิม. Empty partial ถูก ignore; empty final / done-without-final เป็น noMatch ไม่มี assessment/learning event. `assess` ปฏิเสธ blank target/transcript แทนคืนคะแนน0. Logical listening ไม่คืนเป็น true เมื่อ final มาระหว่าง pending start แม้ raw gateway ยัง true. `notListening`/explicit stop ยังรับ delayed legitimate final ได้จน replacement/cancel; done-without-final ปิดรอบและ restart ได้

Speak-to-text และ Shadowing ปิดปุ่มขณะ startup, ตรวจ epoch หลัง await/ใน callbacks และ invalidate ก่อน lifecycle cancel. Failure ล้าง partial assessment ไม่แสดงคะแนนจาก no-result. Screen exit ใช้ cancel ไม่ dispose shared service. Learning writer/provenance semantics เดิมไม่เปลี่ยน; widget tests ใช้ LearningUseCases จริงกับ recording repository/synthetic owner ยืนยัน silence/cancel ไม่ record และ explicit stop + duplicate final record ครั้งเดียว. Transcript-edit-distance ยังคงไม่ใช่ pitch/phoneme/acoustic pronunciation score

Constructor เปลี่ยนจาก const เป็น stateful constructor; scan ทุก caller ใน lib และ relevant tests ไม่พบ external const instantiation จึงไม่ต้องแก้ไฟล์นอก grant. Only assessment callers คือสอง screens และ unit test; ทั้งหมดรับ noMatch แล้ว

### TDD and review disposition

- Initial unit RED: 3pass/10fail สำหรับ pending cancel/dispose, duplicate start/final, stale callbacks และ no-result; แก้จน focused green. ก่อน behavioral RED มี compile error จาก misplaced `dart:async` import และแก้ตำแหน่งแล้ว ไม่ถือ compile failure เป็น behavioral evidence
- Widget RED: 9pass/3fail สำหรับ enabled startup buttons/blank assessment; unit cleanup RED: 14pass/2fail; delayed platform start RED: 0pass/1fail. แก้ด้วย hypothesis ใหม่ใน scope ไม่ลบหรือ skip tests
- Root integration review final-before-start-return RED: 0pass/3fail (logical getter + ทั้งสอง screens); หลัง independent review เพิ่ม terminal/restart, overlapping compensating-cancel failure และ partial→empty-final RED: 0pass/5fail ก่อนแก้
- Read-only reviewer `m1a_review` พบ Important 3 จุด: done-without-final restart, queued replacement ข้าม failed compensating cleanup, partial score ค้างเมื่อ noMatch. ปิดทั้งสามด้วย production fix + regression; final re-review: **accepted**, ไม่พบ Critical/Important/Minor ใหม่ใน 6-file diff
- Reviewer ไม่เขียนไฟล์/รัน Flutter/provider; test/analyze evidence ด้านล่างเป็น execution ของ LQ-06 ไม่ใช่คำอ้างจาก reviewer. Claude review ยัง **not available** ตาม 401 evidence เดิม ไม่ลองซ้ำ/ไม่แต่งค่าใช้จ่าย

### Exact final checks (same six-file source snapshot)

Focused command:

```powershell
flutter test --no-pub test/features/media_practice/speech_practice_use_cases_test.dart test/screens/speak_to_text_screen_voice_test.dart test/screens/shadowing_challenge_screen_test.dart --reporter expanded
```

Result: **exit0, +36 All tests passed (2s)**; source ไม่เปลี่ยนหลังผลนี้

Connected command รวม architecture policies:

```powershell
flutter test --no-pub test/features/media_practice test/features/gemini test/screens/ai_tutor_screen_test.dart test/screens/gemini_settings_screen_test.dart test/screens/speak_to_text_screen_voice_test.dart test/screens/shadowing_challenge_screen_test.dart test/voice test/features/learning/learning_use_cases_test.dart test/features/learning/drift_learning_repository_test.dart test/screens/quiz_screen_test.dart test/architecture/participant_screen_boundary_test.dart test/architecture/learning_screen_boundary_test.dart test/runtime/app_bootstrap_test.dart --reporter expanded
```

Result: **exit1, +309 -1 Some tests failed (16s)**. Sole failure: `participant_screen_boundary_test.dart` / `participant screens use application ports and typed navigation`: `lib/screens/add_multiple_words_screen.dart: imports infrastructure directly` จาก `package:file_selector`. Root ยืนยันเป็น accepted I1 follow-up นอก M1a write set และจัด LQ-03 read-only plan แล้ว. ไม่แก้ import/policy assertion, ไม่ skip test, ไม่อ้าง full connected command green. Intermediate303/1 ใน root ledger ไม่ใช้แทน final309/1 นี้

Connected subset ที่ระบุแยกอย่างชัดเจน ไม่รวม failing participant policy:

```powershell
flutter test --no-pub test/features/media_practice test/features/gemini test/screens/ai_tutor_screen_test.dart test/screens/gemini_settings_screen_test.dart test/screens/speak_to_text_screen_voice_test.dart test/screens/shadowing_challenge_screen_test.dart test/voice test/features/learning/learning_use_cases_test.dart test/features/learning/drift_learning_repository_test.dart test/screens/quiz_screen_test.dart test/architecture/learning_screen_boundary_test.dart test/runtime/app_bootstrap_test.dart --reporter expanded
```

Result: **exit0, +309 All tests passed (16s)**. นี่คือ narrower connected result ไม่ใช่ repository-wide/full-policy green

```powershell
flutter analyze --no-pub lib/features/media_practice/application/speech_practice_use_cases.dart lib/screens/speak_to_text_screen.dart lib/screens/shadowing_challenge_screen.dart test/features/media_practice/speech_practice_use_cases_test.dart test/screens/speak_to_text_screen_voice_test.dart test/screens/shadowing_challenge_screen_test.dart
dart format --output=none --set-exit-if-changed lib/features/media_practice/application/speech_practice_use_cases.dart lib/screens/speak_to_text_screen.dart lib/screens/shadowing_challenge_screen.dart test/features/media_practice/speech_practice_use_cases_test.dart test/screens/speak_to_text_screen_voice_test.dart test/screens/shadowing_challenge_screen_test.dart
git diff --check -- lib/features/media_practice/application/speech_practice_use_cases.dart lib/screens/speak_to_text_screen.dart lib/screens/shadowing_challenge_screen.dart test/features/media_practice/speech_practice_use_cases_test.dart test/screens/speak_to_text_screen_voice_test.dart test/screens/shadowing_challenge_screen_test.dart
```

Final analyze **exit0 / No issues found (3.6s)**; format **exit0 / 6 files, 0 changed**; scoped diff-check **exit0**, only normal Git LF→CRLF notices. Initial targeted analyze had one curly-braces info in test; fixed and reran. Final diff inspected completely across source/tests; no user work reset or weakened assertions

### SHA-256 handoff manifest

| Path | SHA-256 |
| --- | --- |
| `lib/features/media_practice/application/speech_practice_use_cases.dart` | `14BD2E7000EBBC1DDDF85B09FDEFDAA88EA48BB70E5A09CC6C088CC8E38D68FC` |
| `lib/screens/speak_to_text_screen.dart` | `12FF0685DD4C58A0DDAAF611C2FF33D2895FED9686AE061F827B26D75BC3F150` |
| `lib/screens/shadowing_challenge_screen.dart` | `2F236C35BE06452D4321B43096DA7E755E6D7F07BBE73E40E8BCC6B6DDDDBC4C` |
| `test/features/media_practice/speech_practice_use_cases_test.dart` | `86D8ACC353BB29E51C19102E2747577DA3EB62F537515C9CC1AA04596FA68B26` |
| `test/screens/speak_to_text_screen_voice_test.dart` | `E9834040D2FB6113E2F08F85B01E76ACAF10F2C9D5B118B7811BD3A85D63FF52` |
| `test/screens/shadowing_challenge_screen_test.dart` | `2FDEEA48B034D768681BCBAB4BB26749FFEB09F06F570B18B5E6ACBC452B5366` |

### Remaining limitations / next executable step

**Native callback attribution not verified:** unchanged `PluginSpeechRecognitionGateway` เก็บ status/error callback ล่าสุด และ installed speech plugin เก็บ result listener ล่าสุด. หาก native event ของรอบเก่าถูกส่งเข้าหลังติดตั้ง listener รอบใหม่ use-case generation ไม่สามารถบอกต้นทางของ event นั้นได้. Tests พิสูจน์ old callback reference invalidation, cancellation ordering และ simulated delayed activation เท่านั้น ไม่พิสูจน์ native cross-session ordering ทุกกรณี. Gateway/platform follow-up ต้องมี exact scoped grant และ adapter/device evidence; ไม่ขยายแก้ gateway โดยเงียบ ๆ

Physical mic/permission/settings/resume/OS recognition/network behavior, live BYOK/provider, acoustic measurement, full repository regression/build, secrets/dependency/policy scans และ deployment ไม่ได้รัน. `onDevice:false` ของ gateway เดิมยังคงอยู่ จึงไม่อ้าง offline/on-device-only. T1 owner-safe BYOK privacy fix ยังไม่ได้ implement ใน M1a

Human BYOK decision settled: new key/provider consent/summary consent ต้องแยก local-owner + Firebase binding + anonymous state; legacy global values preserved แต่ไม่อ่านเพื่อย้าย/ไม่ auto-use. T1 ต้อง invalidate pending config/generation/late UI/TTS เมื่อ scope/epoch เปลี่ยนรวม same-UID anonymous upgrade และ A→B→A. Decision ไม่ให้สิทธิ์เริ่ม T1 ระหว่าง M1a

Slot handoff: **LQ-06 คืน production writer/Flutter slot**, ไม่มี task-owned running Flutter/test/build process; final Win32 Dart/runtime/tester/gen_snapshot inventory = **0**. No process killed. Reviewer completed. LQ-00 reconcile six hashes/current checkpoint และรับ bounded disposition ก่อนเดิน queue **narrow LQ-05 closure → T1 explicit grant → LQ-07 S1**; LQ-06 ไม่เริ่ม card ถัดไปเอง. Cap30 / program250 คงเดิม ไม่ reset หรืออ้างยอดใช้จริงที่ไม่มีข้อมูล

## T1 owner-safe BYOK — Running 2026-10-21

Latest root `I6 closure acceptance / T1 explicit grant` เปิด sole writer/Flutter slot ให้ T1 แล้ว; M1a return ข้างต้นเป็น historical predecessor. ใช้ checkout/branch เดิมและ preserve latest picker DI/M1a/Marketplace. Write set ตรง root grant: Gemini contracts/use cases/secure store, tutor/settings screens, AppBootstrap เฉพาะ scope notification/composition/disposal, connected tests/controller fakes และ checkpoint นี้. ไม่มี account/identity/schema/dependency/backend/research/sync writes

Execution cards (ไม่เพิ่ม approval gate):

1. **Running — scoped configuration + command boundary:** immutable owner/Firebase binding/anonymous identity, coherent scoped secure record ไม่มี legacy access; admission epoch และ recheck after-await/pre-dispatch/return; no queued sends; revoke/remove/replace invalidate active operations. RED แล้ว: canceled validation และ canceled summary ยัง dispatch/write, second send ถูก queue (6pass/3fail)
2. **Ready — tutor/settings lifecycle:** subscribe invalidation; clear drafts/messages/consent, cancel mic/TTS, suppress late config/reply/status/UI; STT เติม draft รอ explicit send. รักษา UI/theme/provider limits เดิม ไม่สร้าง Messenger/history/raw-source flow
3. **Ready — bootstrap composition:** injected auth reader/events + owner watch, same-UID anonymous upgrade/ABA, actual owner/auth verification และ subscription disposal; preserve vocabulary picker wiring
4. **Ready — Review/Attest:** synthetic storage/gateway tests สำหรับ owner isolation, delayed writes/cancel/partial commit/restart, summary/generation/revoke/remove; connected account/identity/Gemini/media/voice/learning/bootstrap/architecture; scoped analyze/format/diff/independent review/hash/process0 แล้ว RETURN slot ไม่เริ่ม S1

Scope uncertainty/storage failure ปิดเฉพาะ AI; ordinary local learning คงเดิม. ไม่อ่าน secretจริง/legacy values ไม่เรียก live provider/device/deploy. Human credential policy settled; cap30/program250 ไม่ reset. Source/card acceptance ไม่ใช่ whole I5/hardware/native-callback/efficacy claim

## T1 final handoff / slot return — 2026-10-21

### Intent, authority and policy disposition

- Worktree `C:\Users\Phet\Documents\LexiQuest`, branch `feature/associative-reading-loop`, HEAD `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`; shared dirty source preserved, no stage/commit/merge/reset/cleanup
- Authority: latest LQ-00 `I6 closure acceptance / T1 explicit grant` และ `T1 crash/uncertain-write decision`; own T1 execution cards ข้างต้น → Execute/Review/Attest ครบใน bounded local scope; Integrate รอ LQ-00 รับ manifest
- Write set: 11 source/test paths ตาม final manifest + own checkpoint นี้เท่านั้น. `app_bootstrap.dart` แก้เฉพาะ Gemini scope/notifications/injection/disposal และ required import; latest picker DI + associative learning/account/Marketplace/M1a baseline คงไว้. Shared bootstrap/test diff เทียบ HEAD จึงมีงาน predecessor อยู่ด้วย ห้ามตีความทุกบรรทัดเป็น T1 ownership
- No account/identity/main/app_dependencies/schema/generated/backend/manifests/dependency/research/sync implementation writes, new provider, live requests, real key reads, publication/enrollment/upload/deployment

**Crash boundary resolved SAFE-FIRST:** เริ่มจาก delegated default ที่ coordinator/root เลือก (ไม่อ้างว่าเป็น direct human answer ในเวลานั้น) แล้วผู้ใช้ตอบคำถามในแชทนี้โดยตรงว่า **“ปลอดภัยก่อน: เก็บ key แยกบัญชีได้ แต่เปิด provider/summary ใหม่อย่างชัดแจ้งทุกครั้งที่เปิดแอป”**. Root ยังยืนยัน direct human choice เดียวกันใน root ledger. นี่เป็น latest authority แทนสมมติฐานเดิมที่คืน persisted consent ได้

Reason: async secure storage ไม่มี transaction/CAS จึงแยก successful final commit ออกจาก commit→cancel/crash-before-compensation ด้วย durable bytes อย่างเดียวไม่ได้. ไม่เพิ่ม pending-marker abstraction เพื่ออ้าง guarantee ที่ทำไม่ได้. Persist **credential only** ใน matching scope; provider activation/summary consent อยู่ RAM และเริ่ม false ทุก app/controller restart หรือ owner/auth epoch ใหม่. ไม่ต้องกรอก key เดิมทุก launch แต่ต้องเปิดใช้อย่างชัดแจ้ง. Uncertain key write อาจทิ้ง stored credential ไว้ได้ แต่ไม่คืน consent/chat/draft/pending request หรือ auto-call provider. Remove/write failure รายงานจริง ไม่อ้าง atomic rollback หรือ confirmed physical deletion เมื่อ acknowledgement ไม่แน่นอน

### Implemented behavior and data boundaries

- `GeminiScope` ประกอบด้วย local owner ID + Firebase UID binding + `isAnonymous`; secure record path encode identity tuple แบบไม่ชนกัน. ไม่มี read/write/delete/migrate/fallback ไป legacy global key/provider consent/summary consent. Malformed scoped record เป็น typed secureStorage; status ไม่เปิดเผย key
- Scoped key record หนึ่ง secure item, provider/summary flags persist false เสมอ และอ่านกลับเป็น credential only แม้พบ flags true ใน scoped record. Explicit configure validates ก่อน replace; explicit session enable ใช้ stored matching key ได้. Runtime activation ผูก valid cancellation token และถูกล้างทันทีเมื่อ scope/epoch invalidates
- Admission จับ scope+epoch ก่อนเข้า serial mutation gate; scope ที่เปลี่ยนโดยยังไม่มี notification ทำให้ invocation เดิม abort ไม่ adopt B. Verify หลัง relevant await และ synchronous check ก่อน action/storage/provider dispatch/return; verifier return microtask invalidation regression ผ่าน. One in-flight reply, second send ถูก reject ไม่ queue
- Revoke/remove cancel ก่อน await, pin captured scope **และ expected epoch** ของ self-revocation; reentrant A→B→A ไม่ re-admit คำสั่งเดิม. Mutation catch ครอบถึง final return check, clear runtime activation และพยายาม clear captured scoped credential เมื่อ late/uncertain write; compensation failure ไม่คืน activation หลัง restart. No success claim บน storage uncertainty
- Bootstrap อ่าน actual active-owner row ตรวจ auth binding หลัง await; auth reader/stream ใช้ immutable session snapshots และ `userChanges()` รวม same-UID anonymous→registered. Owner query subscription ใช้ refresh cache แต่ **ทุก owner-table update/commit** เป็น epoch fence เพิ่มต่างหากเพื่อกัน coalesced ABA; intentionally conservative แม้ final row เท่าเดิม. ไม่ reset จาก auth token/email metadata ที่ UID/anonymous ไม่เปลี่ยน. Subscription errors/factory/listen construction failures ปิด AI scope แต่ bootstrap/real local quiz ยังใช้ได้
- Tutor/settings subscribe invalidation, clear key draft/messages/checkbox/session state; guard controller replacement, captured scope, local epoch และ controller epoch. Settings self-revoke อนุญาตเพียง expected +1, genuine owner/ABA transition ไม่รับ result ข้าม scope. Real-controller removal widget ยืนยันสถานะ key refresh หลัง serial self-invalidation ไม่ใช่เฉพาะ fake ที่ไม่ emit
- STT final เติม reviewable composer เท่านั้น ต้อง explicit Send จึงเรียก Gemini. Scope/background/cancel/route exit invalidate pending reply/mic; late reply ไม่เพิ่ม bubble/TTS. Startup mic double tap ปิด; text similarity/native callback limitation ของ M1a ไม่ถูกอ้างว่าหายไป
- Audio cleanup failure ถูก contain พร้อม generic current-scope error ไม่หลุด stream/UI exception; failed pre-send mic cancel ไม่ dispatch Gemini. Dispose ไม่เขียน UI เมื่อ cleanup ล้มเหลว. ข้อผิดพลาด **ไม่ใช่หลักฐานว่า OS microphone/audio หยุดสำเร็จ**
- Gateway/transport ไม่เปลี่ยน: input500/output120/timeout20s, no new provider/history/raw-source/media/transcript persistence/export/outbox. Learning/mastery/reward authority ไม่เปลี่ยน; provider consent ไม่ใช่ research consent

### Review and development evidence

Read-only independent reviewer `t1_review` ตรวจ current 11-file scope และ connected code; พบ/แก้ restart activation, cancellation final-return cleanup, persistent verifier reload loop และ scope/epoch re-admission/UI issues. Final source disposition **accepted / no further must-fix**; reviewer ตรวจ last audio-error correction + session-only copy ซ้ำแล้ว ไม่รัน tests/analyze/provider และไม่เขียนไฟล์. LQ-00 read-only source review เสริม admission/microtask/reader/auth factory/Drift ABA findings; fixtures/fixes ด้านล่างปิดตาม scope เดิม. Claude review ยัง not available ตาม historical 401; ไม่ลองซ้ำหรือแต่งค่าใช้จ่าย

Recorded behavioral RED before corresponding corrections:

- Old use cases **6pass/3fail**: canceled validate ยัง configure, canceled summary ยัง dispatch, queued second send
- UI **9pass/5fail**: STT auto-send, late scope/background reply/TTS, stale key draft/configuration success, old delete confirmation. มี lifecycle fixture transition assertion ภายหลัง แก้ inactive/resumed ตาม Flutter state machine ไม่ลด business assertions
- Verifier return gap **0pass/2fail** (assert no gateway/storage invocation); typed verifier failure **18pass/1fail**; persistent unavailable reload **1pass/1fail**; mutation-return cancellation **0pass/1fail**
- Revoke scope re-admission + self-invalidating removal error **0pass/2fail**; unnotified scope configure/remove/consents **0pass/3fail**
- Bootstrap watcher factory construction **0pass/1fail**; unchanged-final-row real Drift owner update **1pass/1fail** before table-update fence. Two committed real Drift A→B→A validation fixture และ reentrant controller ABA ผ่านหลัง guard เดียวกัน
- Final audio error cases ต่างมี focused **0pass/1fail** ก่อนแก้ และคู่สุดท้าย **+2 All tests passed** หลังแก้. Original415 connected pass เป็น intermediate ก่อนสอง cases นี้ ไม่ใช้แทน final417

Scope/data tests ครอบคลุม two-owner/Guest/anonymous state, ABA, delayed validation/secure write/summary/generation, revoke/remove/replace, fresh controller restore, failed compensation/uncertain key outcome, malformed storage, legacy access-log untouched และ local learning ต่อได้เมื่อ AI auth unavailable. Fixtures ใช้ synthetic keys/owners/messages + fake gateway/storage เท่านั้น

Bounded recovery: API migration compile errors (รวม Firebase/Supabase `User` ambiguity) แก้จาก actual source; no behavioral evidence claimed from compile failure. Formatter เคย exit0 แต่แจ้ง Windows1224 cannot-overwrite หลัง test: ตรวจ actual files/read-only state และ runtime process=0 แล้ว retry หนึ่งครั้งสำเร็จ; final format0-change ด้านล่างรับรอง actual state. ไม่มี process kill/reset/denied-cleanup workaround. Corrected patch contexts หลัง formatter จาก actual source ไม่ overwrite shared changes

### Final exact verification commands and results

Focused T1:

```powershell
flutter test --no-pub test/features/gemini test/screens/ai_tutor_screen_test.dart test/screens/gemini_settings_screen_test.dart test/runtime/app_bootstrap_test.dart --reporter expanded
```

**exit0, +76 All tests passed (4s)** บน final manifest; ไม่มี source/test edits หลังผลนี้

Connected account/identity + Gemini/media/voice + local learning/bootstrap + **all architecture tests**:

```powershell
flutter test --no-pub test/features/account test/features/identity test/features/gemini test/features/media_practice test/voice test/screens/ai_tutor_screen_test.dart test/screens/gemini_settings_screen_test.dart test/screens/speak_to_text_screen_voice_test.dart test/screens/shadowing_challenge_screen_test.dart test/features/learning/learning_use_cases_test.dart test/features/learning/drift_learning_repository_test.dart test/screens/quiz_screen_test.dart test/runtime/app_bootstrap_test.dart test/architecture --reporter expanded
```

**exit0, +417 All tests passed (20s)**. Includes M1a regression, actual Drift account/identity/learning tests, fitness/Thai encoding/participant boundary/learning boundary; old M1a I1 import-boundary failure เป็น historical และแก้โดย predecessor แล้ว ไม่ถูก skip/filter/weaken ในรอบนี้. ไม่ใช่ whole repository suite

```powershell
flutter analyze --no-pub lib/features/gemini lib/screens/ai_tutor_screen.dart lib/screens/gemini_settings_screen.dart lib/runtime/app_bootstrap.dart test/features/gemini test/screens/ai_tutor_screen_test.dart test/screens/gemini_settings_screen_test.dart test/runtime/app_bootstrap_test.dart
dart format --output=none --set-exit-if-changed lib/features/gemini/domain/gemini_contracts.dart lib/features/gemini/application/gemini_tutor_use_cases.dart lib/features/gemini/data/secure_gemini_settings_store.dart lib/screens/ai_tutor_screen.dart lib/screens/gemini_settings_screen.dart lib/runtime/app_bootstrap.dart test/features/gemini/gemini_tutor_use_cases_test.dart test/features/gemini/secure_gemini_settings_store_test.dart test/screens/ai_tutor_screen_test.dart test/screens/gemini_settings_screen_test.dart test/runtime/app_bootstrap_test.dart
git diff --check -- lib/features/gemini lib/screens/ai_tutor_screen.dart lib/screens/gemini_settings_screen.dart lib/runtime/app_bootstrap.dart test/features/gemini test/screens/ai_tutor_screen_test.dart test/screens/gemini_settings_screen_test.dart test/runtime/app_bootstrap_test.dart
```

Final targeted analyze **exit0 / No issues found (6.2s)**; format **exit0 / 11 files, 0 changed**; scoped diff-check **exit0** (normal LF→CRLF notices only). Initial curly-braces infos/unused variable แก้ครบ ไม่กด severity/disable rule. Final source/connected diff + scope review performed, caller/fake scan มี concrete use case/store และ two controller fakes ทั้งหมด migrate ครบ

UI skills ใช้ incumbent Material/Thai design, semantic feedback และ session-consent disclosure ไม่ redesign. ตรวจพฤติกรรมด้วย widgets; ไม่อ้าง screenshot/contrast/TalkBack/physical-device/large-text matrix สำหรับ tutor/settings จาก tests เหล่านี้. No native/device operation ตาม grant

### Final 11-path SHA-256 manifest

| Path | SHA-256 |
| --- | --- |
| `lib/features/gemini/domain/gemini_contracts.dart` | `7D9D39CDF14E98EC4A002C15036C49E8943A05DE2B3BB560FAFD2451A24907DB` |
| `lib/features/gemini/application/gemini_tutor_use_cases.dart` | `5860C59481AA88DD8EA1DB98BAB0659A7E32C93F4258E3E1516D726F7E4464D0` |
| `lib/features/gemini/data/secure_gemini_settings_store.dart` | `DA818540DFFD5A29069C3D374C86A0791D1E0729329805F64D390917B045B29C` |
| `lib/screens/ai_tutor_screen.dart` | `19DF1168E338BAA1F900684AAEEE7C485A70936B79576A15102CB962EB28C7EB` |
| `lib/screens/gemini_settings_screen.dart` | `051149AC0E12B8BAD7B316E4AC8D5FA280928090EC0CBA5DE1AAEA942C040AE2` |
| `lib/runtime/app_bootstrap.dart` | `3CE78D3121BDC7471B9662D4EA838324550E6914A913B25ACF9F33E7861DBF64` |
| `test/features/gemini/gemini_tutor_use_cases_test.dart` | `0C9723CA2EEF44C80D688B2A8B25B52778E996EEBB0335BC190B39173D546185` |
| `test/features/gemini/secure_gemini_settings_store_test.dart` | `8D9CC0465FEF25E052662E26D7081B7868B9D5B9DC251B4724F1D19D1EF76D7F` |
| `test/screens/ai_tutor_screen_test.dart` | `0C9AFA36C670727EB9ED668E21367C6D586FA2CAB8A7F84FF62E9F04C867FA08` |
| `test/screens/gemini_settings_screen_test.dart` | `2EA6C83C9077CF780ACD1CAE7E5D124DED5F2A9C04CB3166B21B860A2EA49D39` |
| `test/runtime/app_bootstrap_test.dart` | `EE98E6EEAE18EEE5EC90FB36972DF7CC8DDC6D2FB40610CDBBF1EA42E6B65BB8` |

### Completion boundary and handoff

Disposition: **T1 bounded local engineering verified**, reviewer accepted, source manifest stable; no unresolved must-fix found in granted scope. Engineering evidence is not full I5/Messenger/source-aware learning, research efficacy/authority, release readiness or deployment permission

Not run: whole-repository regression/build, device/emulator/native recognition/Keystore crash or mic/audio interruption acceptance, live provider/BYOK, physical TalkBack/large-text/visual matrix, dependency/secret/policy scanners beyond listed architecture tests, backend/cloud/research rollout. M1a native untagged cross-session callback attribution gap remains separate. Async secure write/delete can have uncertain credential outcome; SAFE-FIRST prevents automatic activation, not a guarantee of crash-atomic credential erasure. Cleanup errors do not prove microphone stopped

**RETURN production-writer/Flutter slot to LQ-00 now**; no task-owned command running, final Win32 Dart/dartvm/dartaotruntime/flutter_tester/gen_snapshot inventory **0**. Reviewer complete. Keep branch/worktree/diff as-is (no merge/commit/cleanup authorized). LQ-00 can reconcile final11 hashes/checkpoint and then grant S1 to LQ-07; LQ-06 will not start S1 or broader I5 automatically. Cap30 / program250 unchanged, actual spend unavailable, no fabricated reset/use figures
