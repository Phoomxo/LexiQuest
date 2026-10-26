# LQ-04 — PROGRESS-SKILL-MAPPING-LOCAL-1

## Section 13.5 / intent, authority and snapshot

- Card: **current prompt modes in honest skill aggregates**. Bounded local read-only statistical grouping; ไม่ใช่ mastery/reward authority ใหม่หรือ whole-app readiness.
- Worktree `C:\Users\Phet\Documents\LexiQuest`; branch `feature/associative-reading-loop`; HEAD `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1` unchanged. เก็บ existing dirty work ทั้งหมด; final two-file manifest ด้านล่างเป็น source snapshot ที่ตรวจ ไม่ใช่ HEAD เพียงอย่างเดียว.
- Source coordinator `01a14bdc-3561-7923-9517-1419a4420c64` โอน sole production writer + serialized Flutter/test/analyze/format slot หลัง grid root acceptance/post-grid integration และ coordinator RETURN SHA256 `464ECA002C79AEF8BF1B0CF2CBA749EAF9955968A8E3B9C76207FCEA74146DE3`.
- State: **bounded engineering-complete, submitted for root acceptance; RETURN writer/test slot**. ไม่มี next card เริ่มเอง.
- LQ-04 cap38 / program250 เดิม; actual spend telemetry ไม่พร้อม จึงไม่อ้าง actual spend หรือ reset budget.

## Ground / impact and exact write set

อ่าน active plan §13.5, latest root ledger/exact grant, AGENTS/ADLC, actual progress query/model/use case, Ghost/Reading/Speak prompt writers, learning repository/projections, Mastery `_SkillRow`, callers และ existing projector/legacy XP tests. ก่อนเขียนยืนยัน hash ตรง grant:

- Query: `6360E10AD81164ACB70F09574990752DC3918FF8113D59437C3D9D534450F71E`.
- Existing projector test: `589A5E4DFB0D3344EFE0AA01040E6AC1DB3AEDA75DA9F18E2A598247369A3B18`.

พบว่า persisted attempts ใช้ `ghostSpelling`, `associativeRecall`, `pronunciationTranscript` จริง แต่ `_skills` ยังไม่รวมทั้งสาม ทั้งที่ overall totals รวมอยู่แล้ว. Mastery แสดง query label โดยตรง จึงไม่ต้องแก้ UI/model/caller. เปลี่ยนเฉพาะสาม path:

1. `lib/features/progress/data/drift_progress_queries.dart`: แก้เฉพาะ `_skills` definitions โดยคง key/order/memberships เดิมทั้งหมด เพิ่มสาม mode ตามตาราง และเปลี่ยนสี่ป้ายเป็นภาษาไทย.
2. `test/features/progress/progress_projector_test.dart`: ใช้ไฟล์จริงเดิมและ real in-memory DriftLearningRepository. เก็บ mixed-attempt test เดิม; เพิ่ม intended-only correct/incorrect, mixed legacy/denominator/dictation, unknown/similar names, stable replay, owner A/B/absent-owner และ all-application-table read-only snapshots. Empty test เดิมเพิ่ม four-key/Thai-label/zero-null assertions.
3. checkpoint ใหม่นี้; equivalent-file discovery ไม่พบและ Test-Path เป็น false ก่อนสร้าง.

| Stable key | Query label | Membership ที่เพิ่มเท่านั้น |
| --- | --- | --- |
| `listening` | การฟัง | ไม่มี |
| `pronunciation` | การพูด (ความตรงของข้อความ) | `pronunciationTranscript` |
| `spelling` | การสะกดคำ | `ghostSpelling` |
| `retention` | การจำและเรียกคืน | `associativeRecall` |

ชื่อเป็นคำอธิบาย recorded exercise evidence ไม่ใช่ validated proficiency/CEFR/mastery scale. Transcript matching ไม่วัด acoustic/phoneme/pitch quality; Reading recall ไม่ถูกนับเป็น listening/spoken competence และไม่มี inference จาก XP/coin/HP/TTS exposure.

คงคณิตศาสตร์เดิม: sampleSize = จำนวน persisted relevant attempts; accuracy = correct/relevant และ null เมื่อไม่มี relevant attempt. Exact mode matching; unknown/future modes ยังอยู่ใน overall แต่ไม่จัดกลุ่ม. Dictation อยู่ทั้ง listening/spelling ตามเดิม จึงห้ามรวม sample ของทุกกลุ่มเป็น unique attempts. Mixed test มี18 overall attempts/10 correct แต่ group sample sum20เพราะ dictation2รายการซ้อนสองกลุ่ม; pronunciation3/5, spelling3/6, retention3/6 แทนการเฉลี่ยเปอร์เซ็นต์ราย mode.

ไม่มีเปลี่ยน overall sample/accuracy/XP/streak/due/mastered/completed/achievement/weakness/recommendation/game-level formulas, owner filter หรือ historical/deletion treatment. Query read ไม่มี mutation/backfill/reclassification/reward recomputation. ส่วน `rewardPurchase` XP exclusion ใน tracked diff เป็น baseline dirty work ก่อน card นี้ ไม่ใช่การเปลี่ยนครั้งนี้.

ไม่มี domain/model/SkillEvidence API, Dashboard/UI/refresh/navigation, mastery thresholds/game-level labels, learning/reward/repository/identity authority, main/bootstrap/theme/catalog, schema/generated/dependency/native/backend/account/consent/research หรือ checkpoint อื่นถูกเขียน. อ่านยืนยัน current schema v10 และ v11+ unreserved; ไม่จอง migration. Catalog8/44 และ frozen EvidenceContext/EventEnvelopeV2 คงเดิม.

## RED → GREEN and recovery

- Test harness compile ครั้งแรกขาด required `partOfSpeech` ใน synthetic owner-B word. Diagnostic ชี้ constructor ชัดเจน; เทียบ fixture เดิมแล้วเติม field นี้ก่อนรันใหม่. ไม่ถือ compile error เป็น behavioral RED.
- Behavioral RED ก่อน production edit: whole existing projector file **exit1, 2 passed / 7 failed**. สาม new-mode tests ต้องการ sample2แต่ได้0; mixed/replay/owner testsแสดง missing groups และ empty-label assertionพบ English labelsเดิม. Existing mixed-attempt และ unknown-mode behaviorยังผ่าน.
- แก้เฉพาะ definitions/labels ใน production แล้ว whole projector **exit0, 9 passed**. ไม่แก้ assertion เพื่อลดความเข้ม/ไม่ skip/delete test.
- `dart format` จัด test formatting1ไฟล์; queryไม่เปลี่ยนจาก formatter. Scoped analyzerสะอาด. หยุด source/test edits ก่อน independent review/final connected checks.
- Seeds ผ่าน existing `startSession`/`recordAnswer` authority ไม่ insert AnswerAttempts โดยตรง. Replay ของ stable persisted command ได้ inserted=false และ progressนับ1/XP1 ไม่เพิ่มซ้ำ.
- ทุก new progress read และ empty/owner reads เปรียบเทียบ sorted row JSON ของ `database.allTables` ก่อน/หลัง รวม answer/session/SRS/projection/ledger/owner/outbox/events/research consent tables. ข้อมูลสังเคราะห์เท่านั้น; all-table snapshotsไม่เปลี่ยนจาก query. ไม่มี research enrollment/rows สร้างโดย progress read.

## Final current-source checks

Flutter/Dart ทุกคำสั่งรัน serialized และรอ completion ก่อนคำสั่งถัดไป. Reviewer read-only ไม่ใช้ test slot. หลัง final code/test freeze เขียนเฉพาะ checkpoint.

```text
flutter test --no-pub test/features/progress test/features/learning test/features/rewards test/features/identity test/features/account test/features/media_practice test/features/sync/reward_transaction_sync_test.dart test/screens/ghost_shadow_duel_screen_test.dart test/services/ghost_shadow_duel_service_test.dart test/screens/associative_reading_session_screen_test.dart test/screens/shadowing_challenge_screen_test.dart test/screens/speak_to_text_screen_voice_test.dart test/screens/mastery_dashboard_screen_test.dart test/screens/weakness_clinic_screen_test.dart test/screens/choose_mode_screen_test.dart test/screens/main_navigation_screen_test.dart test/screens/learning_world_map_screen_test.dart test/screens/learning_loop_layout_test.dart test/screens/offline_vocabulary_journey_test.dart test/screens/production_shell_navigation_test.dart test/runtime/app_bootstrap_test.dart test/architecture --reporter expanded
```

**Exit0, +335 All tests passed, 27s.** Whole discovered files/subsystems + all architecture; รวม legacy reward-XP compatibility. Expected synthetic shadow-provider exception ถูก test catch/isolateตามสัญญา ไม่ใช่ failed test. English labels ใน deliberately injected UI fixturesไม่ได้ถูกแก้เพื่อหลบ regression; testsตรวจ actual query labelsโดยตรง.

Final checksหลัง connected/review รันแยกกันตามลำดับ:

```text
dart format --output=none --set-exit-if-changed lib/features/progress/data/drift_progress_queries.dart test/features/progress/progress_projector_test.dart
flutter analyze --no-pub lib/features/progress/data/drift_progress_queries.dart test/features/progress/progress_projector_test.dart
flutter test --no-pub test/features/progress/progress_projector_test.dart --reporter expanded
git -c core.safecrlf=false diff --check -- lib/features/progress/data/drift_progress_queries.dart test/features/progress/progress_projector_test.dart
```

**Format exit0, 2 files / 0 changed, 0.02s; analyze exit0, No issues found, 1.7s; whole projector final rerun exit0, +9 All tests passed; scoped diff check exit0.** Earlier post-format whole9 alsoผ่านก่อน connected. Counts9/335 overlap ไม่ใช่344 unique tests. Final actual diff/scopeและ new checkpoint whitespace/manifestตรวจแยกจาก tracked diff; ไม่ normalize line endingsหรือแก้ unrelated changes.

Runtime inventory **2026-10-23T06:52:31.2165092+07:00**: `task_runtime_process_count=0`. Get-CimInstance Win32_Processตรวจ `dart.exe`, `dartvm.exe`, `flutter_tester.exe`, `dartaotruntime.exe` และ workspace/Firestore Java. ทุก exec sessionจบแล้ว ไม่มี process kill/cleanup.

## Review disposition and evidence limits

- Independent `/root/lq04_progress_review`: **accepted, C0/I0/M0, no must-fix** บน two-code-file hashesด้านล่าง. อ่าน full query/tests และ trace writers → LearningUseCases/Drift persisted attempts → ProgressUseCases/SkillEvidence → Mastery `_SkillRow`, legacy XP/owner/deletion boundaries. Reviewerไม่เขียนไฟล์ ไม่รัน Flutter/Dart/test/analyze/build; execution evidenceทั้งหมดข้างต้นเป็น root-run.
- Claude fresh review: **not available**; ไม่มี provider/Claude401 retry. Historical critiqueไม่ใช่ fresh code verdict.
- Ponytailทำให้ใช้ existing definitions/authorities ไม่เพิ่ม registry/abstraction/schema. TDDให้ behavioral missing-count REDก่อน production change; verification/reviewยืนยัน source snapshotเดียวกัน. ไม่มี UI redesignหรือ UI skill workflow เพราะ cardนี้เปลี่ยน query/testsไม่ใช่หน้าจอ.
- ยังไม่ตรวจ actual Thai-label renderingบนเครื่องจริง/TalkBack/native IME/contrast หรือ acoustic/efficacy/research validity. Connected widget testsไม่เท่ากับ physical-deviceหรือ release acceptance.

## Integration boundary / next executable step

Post-grid root **1489/1489**, scoped `flutter analyze --no-pub lib test tool` และ debug APKเป็น **pre-card predecessor evidence** ไม่รับรอง sourceหลัง mapping edit. ไม่ rerun full repository/build/APKใน cardนี้; source rootต้อง refresh final integration/build/artifactหลัง next freeze. Rootเคยรายงาน unscoped analyzer failureจาก historical `build/prototype-delivery/r8`; งานนี้ไม่ลบ directoryหรือแก้ exclusionsเพื่อซ่อน failureนั้น.

External Google/full deletion/S3a/v11 held/unreserved; physical low/mid/high0/3, TalkBack, research/efficacy/release gatesเดิมยังอยู่. ไม่ใช้ live provider/credentials/data, deploy/publish/enroll/upload real research, commit/merge/push/destructive cleanup/Codex Security. ไม่เริ่ม Dashboard refresh/game-level wording/Source Result linkage/history/provenanceหรือ cardอื่น.

**Next:** source/integration rootตรวจ actual diff + checkpoint + final two-file manifest แล้วรับ bounded cardหรือคืน finding. LQ-04 RETURN sole writer/Flutter slotพร้อม checkpoint SHAแยกให้ทั้งสอง coordinator; รอ grantใหม่ก่อนงานถัดไป. ไม่มี unresolved bounded must-fixหรือ running task process ณ handoff.

## Final SHA256 manifest

| Source/test path | SHA256 |
| --- | --- |
| `lib/features/progress/data/drift_progress_queries.dart` | `898177A131414199CC38D3D7EC496007C21D5C4A02B30D40D8740D2D07315B61` |
| `test/features/progress/progress_projector_test.dart` | `D6B5A1790A57FBAECAFDDC985271AA32566B2CC8B34225045B099C24489590A1` |

Checkpoint SHAส่งแยกเพื่อหลีกเลี่ยง self-reference. Final checks/reviewอ้าง sourceเดียวกัน; เก็บ unrelated dirty workไว้ทั้งหมด.
