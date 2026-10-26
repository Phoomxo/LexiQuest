# LQ-04 — G1 Ghost Duel retry identity and truthful completion

## Section 13.5 handoff / intent and authority

- Chat/card: LQ-04 / G1, bounded integrity repair หลัง source root รับ I4d และ coordinator RETURN; ไม่ใช่ full I4 หรือ release completion.
- Worktree: `C:\Users\Phet\Documents\LexiQuest`; branch `feature/associative-reading-loop`; HEAD `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`. Dirty work ของผู้ใช้/ใบงานก่อนหน้าถูกเก็บไว้; manifest ด้านล่างระบุ snapshot ที่ตรวจจริง ไม่ใช้ HEAD เพียงอย่างเดียว.
- Source coordinator `01a14bdc-3561-7923-9517-1419a4420c64` โอน sole production writer + serialized Flutter/test/analyze/format slot ตาม grant G1 หลัง coordinator checkpoint SHA256 `835F7A6B9C124696424030AE4ED83B89597FA2A63D563DC83D04867046A1A775`; integration coordinator `01a15925-357c-7a83-988a-17e3f562b6a7` เป็นผู้รับหลักฐานร่วม ไม่ใช่ slot ที่สอง.
- State: **bounded G1 engineering-complete, submitted for root acceptance; RETURN writer/test slot**. ไม่เริ่มใบงานถัดไปเอง.
- Budget: LQ-04 cap38 / program250 เดิม; actual spend telemetry ไม่พร้อม จึงไม่อ้างยอดใช้จริง.

## Ground / outcome / changed files

อ่าน active plan §13.5, latest root ledger/G1 grant, I4d checkpoint, current Ghost/callers/tests, LearningUseCases/DriftLearningRepository, combat service และ Weakness/feature gate ก่อนทำงาน. Pre-G1 hashes ตรงกับ grant: screen `36F165CDB501F5F481CD1A680AEF7FB717B0BDB8B63FA1E72C0A8CB8B9132507`, test `A01E8E19C126733D48CC8865C381C43275C966919129FE0BDDAFD518DFEAEEA2`.

เขียนเฉพาะสาม path ที่ได้รับอนุญาต:

1. `lib/screens/ghost_shadow_duel_screen.dart`: ตรึง normalized answer/correctness/duration/word/session/index และ stable attempt ID/UTC time ก่อน dispatch แรก; failed-write/lost-ack retry ใช้หลักฐานเดิมและไม่เปิดให้เปลี่ยนคำตอบ. ไม่มี auto retry. HP/log/index ใช้ค่าที่ตรึงและขยับครั้งเดียวหลัง acknowledged save. ใช้ `startGhostDuel`, `recordAnswer`, `finishSession` และสูตร combat เดิม ไม่สร้าง authority ใหม่.
2. `test/screens/ghost_shadow_duel_screen_test.dart`: เก็บ empty-account test เดิม; เพิ่ม real in-memory Drift + synthetic owner/failure/delayed-ack fixtures สำหรับ answer/Finish replay, contradictory input, double-tap, summary validation, Back/dispose, owner/dependency changes, historical Weakness gate/navigation และ 2×/IME layouts.
3. checkpoint ใหม่นี้: ค้น equivalent แล้วและ `Test-Path` เป็น false ก่อนสร้าง.

Combat-ended แยกจาก persisted completed: แสดง `บันทึกคำตอบแล้ว` และ explicit `จบรอบและบันทึกผล`; รับ success เฉพาะ returned summary ที่ session ID ตรงและ state completed. Finish failure/lost-ack แสดง `ลองบันทึกผลรอบอีกครั้ง` และ retry เฉพาะ Finish ไม่ส่งคำตอบหรือคิด combat ซ้ำ. Totals มาจาก returned summary ไม่ใช่ HP/log. Back/dispose ไม่เรียก Finish; dispatched answer อาจ commit ต่อได้โดยไม่อ้างว่า undo แล้ว. Legitimate first-answer/first-correct achievements ไม่ถูกลบหรือปิดกั้น.

Pin owner/learning ตอน admission และตรวจตาม action/await boundaries; authority ไม่พร้อมหรือ owner/context เปลี่ยนจะซ่อน old result และไม่ส่งหลักฐานไป owner B. หลัง completed เท่านั้นจึงเปิด `ฝึกคำที่ผิดจากประวัติ` เมื่อมี actual dependencies และ `FieldFeature.weakness` gate; ใช้ WeaknessClinicScreen/AppNavigator เดิม. เพิ่ม optional screen `featureRegistry` input และ local page name `learning/ghost-weakness`; ไม่เปลี่ยน global route/feature registry หรือ feature IDs. Historical weaknesses ไม่ถูกอ้างว่าเป็นเฉพาะรอบนี้.

No shared authority, combat service/model, main/bootstrap, schema/ledger/generated/dependency/native/backend/account/consent/research หรือ checkpoint อื่นถูกเขียนใน G1. Prompt mode `ghostSpelling`, provenance `local:ghost-duel:v1`, C-COIN และ existing reward/projection rules เดิม. Frozen EvidenceContext/EventEnvelopeV2 และ catalog8/44 ไม่เปลี่ยน. S3a/v11 ยัง held/unreserved. Tracked diff เทียบ HEAD รวม baseline dirty changes ที่มีมาก่อน (เช่น existing `startGhostDuel` call); ไม่อ้างว่าทุกบรรทัดใน diff เป็นงาน G1.

## RED → GREEN / bounded recovery

- ก่อนแก้ production: behavioral RED ทั้ง Ghost file **exit1, 1 passed / 5 failed**. Retry/Finish actions ยังไม่มี และ dispose เรียก Finish จริง1ครั้งเมื่อคาด0. เป็น runtime reproduction ไม่ใช่สมมติฐานจาก code อย่างเดียว.
- Test harness compile ชนชื่อ `LocalOwner` กับ generated DB model: แก้ import ด้วย hide. Production compile พบ `const Semantics` ที่ constructor ไม่ const: แก้เฉพาะ const. ไม่มีการเปลี่ยน guardrail/authority เพื่อผ่าน checks.
- First focused Ghost + unchanged combat service **exit0, 9 passed**; ขยาย tests ต่อแล้วพบ4fail จาก fixture assumptions2และ layout harness2.
- Fixture assumptions เดิมนับว่า Finish ต้องไม่มี outbox เพิ่มเลย และ pending committed correct answer ต้องไม่มี achievements ซึ่งผิดกับ existing authority. ตรวจ repository แล้วแก้ให้ assert preserved answer/SRS outboxes plus exactly2 legitimate completion-achievement outboxes และ exact first_answer/first_correct IDs ตามลำดับ. ไม่ลบ earned effects/ไม่ skip tests.
- Large-text harness ต้อง settle focus/scroll และ scroll กลับต้น ListView ก่อนค้น lazy-built Finish; แก้ harness ไม่เปลี่ยน difficulty/layout เพื่อหลบ assertion. Portrait/landscape ผ่าน2/2 แล้วขยาย owner/context/summary/Back casesจน focused ผ่าน27.
- Scoped analyze ครั้งแรกมี16infos (braces/function declaration/async context). แก้ style และ explicit mounted fences แล้วตรวจใหม่สะอาด. Final checks ด้านล่างรันบน source หลังแก้เหล่านี้ทั้งหมด.

## Final current-source verification

หยุด code/test edits ก่อน reviewer และ final checks; Flutter/Dart ทุกคำสั่งรัน serialized และ await completion จริง ไม่มี overlapping build/test/cache command. หลัง checks เขียนเฉพาะ checkpoint นี้.

```text
flutter test --no-pub test/features/learning test/features/progress test/features/rewards test/features/identity test/features/account test/features/consent test/features/gemini test/features/media_practice test/features/sync/reward_transaction_sync_test.dart test/screens/ghost_shadow_duel_screen_test.dart test/services/ghost_shadow_duel_service_test.dart test/screens/quiz_screen_test.dart test/screens/srs_flashcards_screen_test.dart test/screens/weakness_clinic_screen_test.dart test/screens/source_practice_screen_test.dart test/screens/speak_to_text_screen_voice_test.dart test/screens/ai_tutor_screen_test.dart test/screens/gemini_settings_screen_test.dart test/runtime/app_bootstrap_test.dart test/screens/production_shell_navigation_test.dart test/architecture --reporter expanded
```

**Exit0, +456 All tests passed, 3m40s.** Whole named files/subsystems + all architecture tests; ไม่มี name filter. SourcePractice มี measurable progress ต่อเนื่อง ไม่ใช่ stalled run.

```text
flutter test --no-pub test/voice test/services/ai_voice_reading_adapters_test.dart --reporter expanded
```

**Exit0, +201 All tests passed, 4s test elapsed.** Fake/local voice/provider adapters เท่านั้น ไม่ใช่ live provider/hardware evidence.

```text
flutter test --no-pub test/screens/ghost_shadow_duel_screen_test.dart test/services/ghost_shadow_duel_service_test.dart --reporter expanded
```

Final independent whole-file rerun: **exit0, +27 All tests passed, 7s** (24 Ghost widget + 3 unchanged combat-service tests). No code/test edit ระหว่างสาม runs; counts มี overlap ไม่ใช่684 unique tests.

```text
dart format --output=none --set-exit-if-changed lib/screens/ghost_shadow_duel_screen.dart test/screens/ghost_shadow_duel_screen_test.dart
flutter analyze --no-pub lib/screens/ghost_shadow_duel_screen.dart test/screens/ghost_shadow_duel_screen_test.dart
git -c core.safecrlf=false diff --check -- lib/screens/ghost_shadow_duel_screen.dart test/screens/ghost_shadow_duel_screen_test.dart
```

รันแยกกันตามลำดับ: **format exit0, 2 files / 0 changed, 0.05s; analyze exit0, No issues found, 2.2s; diff check exit0**. ตรวจ final actual screen/test diff และ checkpoint scope/whitespace/manifest. ไม่ normalize line endings หรือแก้ unrelated files.

Runtime inventory **2026-10-23T05:39:12.7515759+07:00**: `task_runtime_process_count=0`; Get-CimInstance Win32_Process ตรวจ `dart.exe`, `dartvm.exe`, `flutter_tester.exe`, `dartaotruntime.exe` และ Firestore/workspace Java. Exec test sessions จบแล้วทั้งหมด; ไม่มี process ถูก kill.

## Review disposition / UI evidence limits

- Independent read-only reviewer `/root/lq04_g1_review`: **accepted with limits; no must-fix** หลังอ่าน full screen/tests และ connected LearningUseCases/Drift/combat/Weakness/gate/callers. Reviewer ตรวจ final two-file hashesตรง manifestด้านล่าง; ไม่มี write และไม่ได้รัน Flutter/Dart/analyze/build. Test evidence เป็น root-run ไม่ใช่ reviewer-run.
- Claude review: **not available** สำหรับ G1 code snapshot; ไม่ยิง provider/request ใหม่และไม่ retry401. Historical critiques ไม่ใช่ fresh code verdict.
- Ponytail รักษา incumbent authorities/patterns; Impeccable/UI-UX guidance มีผลให้คง Material3/ListView, visible textual/live status และ growing controls ขั้นต่ำ48dp แทน fixed-height button ที่บีบ text2×. ไม่ redesign combat.
- Widget checks ใช้ actual360×800/light และ800×360/dark, text2× และ synthetic IME180; input/answer retry/Finish retry/result reachable โดยไม่มี layout exception. Back test ใช้ Navigator route จริงใน widget harness; historical Weakness route/gate ตรวจหลัง completed. ไม่อ้าง physical-device/native pixel/TalkBack/contrast/Reduce Motion หรือ process-kill coverage.

## Limits / release dependencies / next executable step

Retry intent อยู่ใน memory ของหน้าจอเท่านั้น ไม่มี durable crash-resume. Owner fences อยู่ที่ admission/actions/await ไม่ใช่ continuous owner observer หรือ atomic rollback ของ dispatched write; repo owner/session guardsยังเป็น trust boundary เดิม. Explicitly started unfinished sessionsอาจคง activeหลัง Back/invalidation; ไม่ cleanupหรือ fabricate completion. Pending committed answerอาจให้ legitimate answer achievements/XP/coinตามauthorityเดิม แต่ไม่มี false completed-session evidenceจาก dispose.

ไม่ได้รัน full-repository suite/analyze/build/APK/device/live Cloud/provider/security scan หรือ production research flow. ไม่ deploy/publish/enroll/upload real data/commit/merge/push/destructive cleanup. ไม่มี credentials/participant answers/PII ใน fixtures. Engineering-complete ของ G1 ไม่เท่ากับ release-ready/research authority; full current-source integration/build และ actual low/mid/high/TalkBack acceptanceยังเป็น gateแยกของroot.

**Next:** source/integration rootตรวจ checkpoint + actual diff + manifest, รับหรือคืน bounded G1 แล้วจึงมอบใบงานถัดไป. LQ-04 RETURN sole writer/Flutter slot พร้อมส่ง checkpoint SHAแยกให้ทั้งสอง coordinatorและไม่เริ่ม cardอื่นเอง. ไม่มี running task processหรือ unresolved bounded must-fix ณ handoff.

## Final SHA256 manifest

| Source/test path | SHA256 |
| --- | --- |
| `lib/screens/ghost_shadow_duel_screen.dart` | `ABC7F9E0CAB634FE10073F812C0AB224171450804AA6B44D95A7633A40517C8C` |
| `test/screens/ghost_shadow_duel_screen_test.dart` | `8A80F24117022BF0D18D57A5D6537AC1E51B9C5FF6DC5558E97052D9BF3927A9` |

Checkpoint SHAส่งแยกเพื่อหลีกเลี่ยง self-reference. Manifest/review/testsอ้าง current sourceเดียวกัน; existing dirty worktreeถูกเก็บไว้ทั้งหมด.
