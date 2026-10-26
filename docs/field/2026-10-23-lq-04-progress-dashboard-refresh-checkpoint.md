# LQ-04 — PROGRESS-DASHBOARD-REFRESH-LOCAL-1

## Section 13.5 / intent, authority and snapshot

- Outcome: เมื่อกลับจาก existing Weakness route ให้ Dashboard อ่าน snapshot ใหม่ผ่าน effective loader ปัจจุบัน; ระหว่างรอไม่แสดง score/error เก่าเป็นผลใหม่.
- Source root `01a14bdc-3561-7923-9517-1419a4420c64` ให้ ROOT GRANT ตาม exact coordinator proposal หลังรับ XP label แล้ว. Canonical proposal อยู่ท้าย `docs/field/2026-10-20-lq-00-wave-0-checkpoint.md`; grant ไม่ครอบคลุมใบงานอื่น.
- Worktree `C:\Users\Phet\Documents\LexiQuest`; branch `feature/associative-reading-loop`; HEAD `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1` unchanged. เก็บ unrelated dirty work; final manifestด้านล่างระบุ verified snapshot ไม่ใช้ HEAD อย่างเดียว.
- State: **bounded engineering-complete, submitted for root acceptance; RETURN sole production writer + serialized Flutter/test/analyze/format slot**. ไม่เริ่ม next card.
- Cap LQ-04 38 / program250 เดิม; actual spend telemetry ไม่พร้อม ไม่อ้าง actual spend/reset budget.

## Ground / exact changes and boundaries

อ่าน Dashboard/test/callers, AppNavigator, ChooseMode current-loader/Future.sync/mounted refresh pattern, Weakness, AppDependenciesScope, ProgressUseCases/query/model และ latest proposal/checkpoint. Pre-card hashesตรง accepted XP-label grant: Dashboard `B12CA5C7BC12726B6359DC60D1851867EBBB5B295EC1D8A309CE22BF09607D8B`; test `08749BAE78EB48C7937191A8A53A92F4D94B3FD77FAE96B35D18574DB48616AC`.

เขียนเฉพาะสาม path:

1. `lib/screens/mastery_dashboard_screen.dart`: await AppNavigator route future จริงเฉพาะ Weakness แล้ว callback ไป parent `_refresh`; ตรวจ mounted ก่อนอ่าน loader/setState. เลือก widget loader หรือ current dependency progress.load ที่ return time ไม่ใช้ loader เก่าที่จับตอนเปิด route. didUpdateWidget/didChangeDependencies เปลี่ยน selected futureเมื่อ effective loader เปลี่ยน; stable loader/theme/resize ไม่เพิ่มโหลด. ใช้ equality ของ function/instance-method tearoff ไม่สมมติว่าทุก rebuild คือ loader ใหม่.
2. `test/screens/mastery_dashboard_screen_test.dart`: คง previous label/metric/empty/navigation tests; เพิ่ม actual route-return/load counts/current-parent identity, delayed/error/empty/context replacement/late future/disposal/no-loop/gate และ real Drift read-only proof. ขยายสี่ actual viewport2× casesเดิมให้ผ่าน loading → safe error → refreshed data พร้อม labelled48dp action.
3. checkpoint ใหม่นี้; equivalent-file discovery ไม่พบและ Test-Path false ก่อนสร้าง.

`Future<ProgressSnapshot>.sync` รับ synchronous throw; missing dependency เป็น failed future. Fast failureระหว่าง route teardownอาจเกิดก่อน FutureBuilder subscribeใน frameถัดไป จึงติด `next.ignore()` observer ทันทีแล้ว **คืน original futureเดิม** ให้ FutureBuilder. ไม่เปลี่ยน errorเป็น success/zero ไม่ลบ errorจาก view. Builder ตรวจ `ConnectionState.done` ก่อน data/error เพื่อไม่ render retained old snapshot. FutureBuilder current-future callback identity เป็น generation fence ของ view สำหรับ superseded/disposed futures; ไม่สร้าง state framework/counter/cache/timer เพิ่ม.

Initial loadยังครั้งเดียวเมื่อ loaderคงเดิม. Child Weakness/Achievements มี legitimate read ของตนเองนับแยกจาก parent; Weakness returnเพิ่ม parent readหนึ่งครั้ง. Loader replacementอาจมี readสำหรับ contextใหม่หนึ่งครั้งและ route-return readอีกหนึ่งครั้งตาม acceptance. Achievements/Shop routes/gatesยังเดิมและกลับแล้ว **ไม่**เพิ่ม parent refresh. ไม่มี optimistic attempt/counter/XP/reward incrementจาก navigation.

Owner/context claimจำกัดที่ current effective loader/dependency replacement และ selected-future fencing. ไม่มี continuous owner observer, atomic owner/read guarantee, owner metadata/model field หรือ shared API amendment. ไม่ retrofitทุก owner transaction. Read-only dependency testใช้ ownerA/ownerB ที่ seedไว้และ current ProgressUseCases/queryเดิม ไม่สร้าง authority ใหม่.

XP label `ระดับเกมจาก XP`, published metrics/formulas/query/skill mapping/mastery thresholds/routes/feature IDs คงเดิม. Accepted query/projector hashยังเป็น `898177A131414199CC38D3D7EC496007C21D5C4A02B30D40D8740D2D07315B61` / `D6B5A1790A57FBAECAFDDC985271AA32566B2CC8B34225045B099C24489590A1` หลัง final checks. Other Dashboard actions/translationsใน diffเทียบ HEADเป็น baselineก่อน cardนี้. ไม่เขียน query/model/learning/reward/identity/main/bootstrap/theme/catalog/schema/generated/dependency/native/backend/account/consent/research หรือ checkpointอื่น. Catalog8/44/frozen research contracts และ v11+ unreservedคงเดิม.

## Behavioral RED → GREEN / bounded recovery

- Test-only compileแรกขาด required `responseTimeMs` ใน synthetic RecordAnswerCommand; อ่าน actual constructorแล้วเติม500ตาม fixture intent. ไม่ถือ compile errorเป็น behavioral RED.
- First runtime REDพบ intended failuresพร้อม resize harnessที่ไม่ได้ตั้ง devicePixelRatio ทำให้800×600 physicalกลายเป็น266.7×200 logical. แก้เฉพาะ harnessเป็น DPR1 ไม่แก้ productionเพื่อหลบ overflow.
- หลัง harness correction ก่อน production: whole-file **exit1, 6 passed / 13 failed**. Missing parent third readหลัง Weakness, initial synchronous throwหลุดจาก view, replacementไม่ reload และ matrixไม่มี pending refresh เป็น source-backed runtime RED. Original label/empty/navigation, stable rebuild, hidden gate และ disposed-before-returnส่วนที่มีอยู่ยังผ่าน.
- First implementationใช้ expression-bodied setState assignmentซึ่งคืน Future; Flutter assertionชี้ root cause. เปลี่ยนเป็น synchronous block assignment ไม่เปลี่ยน authority/assertions.
- จากนั้น **17 passed / 2 failed** ชี้ fast sync/async refresh errorที่เกิดก่อน view subscribeระหว่าง route teardown. เพิ่ม early error observerตามด้านบน; whole19ผ่าน โดย safe-error assertionsยังอยู่และผ่าน ไม่กลบ errorใน UI.
- เพิ่ม pending-after-old-error และ removed-loader safety coverage, format แล้ว whole **21ผ่าน**. ไม่มี test skip/delete/assertion weakening หรือ policy bypass.

## Acceptance coverage

- Model snapshotA → actual Weakness push → update synthetic modelB → pop → parentเดิมแสดงB; load counts1 initial/1 child/1 returnแยกชัด ไม่ remount parentเพื่อ fake refresh.
- Delayed refreshซ่อน old data; pendingหลัง previous errorซ่อน old error. Current async failure/sync throw/unavailable loaderแสดง safe local error ไม่แสดง raw synthetic detail/fake zeros/stale scores; current emptyแสดง zero stateเดิม.
- Widget loaderเปลี่ยนขณะ routeเปิด: replacement futureเริ่มหนึ่งครั้ง, returnอ่าน current loaderอีกครั้ง, late obsolete errorไม่ทับB. Obsolete initial dataที่จบระหว่าง current refreshpendingไม่ทำให้Aปรากฏ. Parentdisposeก่อนreturnไม่ reload; disposeระหว่างpending ignores late result.
- Stable loader ordinary theme rebuild/resizeยัง initial1; Achievements childอ่านเองแต่ parentไม่ refreshเมื่อกลับ; Shopกลับไม่ refresh; hidden Weaknessไม่มี route/loadเพิ่ม.
- Real in-memory Drift fixture seed ownerB answerผ่าน existing learning repositoryก่อน baseline. สลับ AppDependencies progressจากA→Bระหว่าง Weaknessเปิดแล้วกลับ; A reads2/B reads2, DashboardแสดงB XP1. Snapshot sorted row JSONของ **29 application tables** ก่อน/หลัง reads/navigationเท่ากัน รวม answer/session/SRS/projections/ledgers/owners/outbox/events/research consent. ไม่มี learning/reward/research writeจาก refresh; seedsสังเคราะห์ ไม่ใช่ live participant data.
- Actual360×800/800×360 × light/dark, text2×, incumbent M3Theme + loaded NotoSansThai; assert real MediaQuery/theme/scaler. ตรวจ initial label/metrics/semantics, viewport bounds/max-lines, 48dp Weakness action, loadingมี `กำลังอ่านประวัติการเรียน` semantics, safe error hit-testable และ refreshed result scroll-reachableโดยไม่มี framework/layout exception. ไม่มี redesign/new retry button/polling.

## Final current-source verification

Code/testหยุดเขียนก่อน independent review และ final connected checks; หลังจากนั้นเขียนเฉพาะ checkpointนี้. Flutter/Dartทุกคำสั่งรัน serialized และ await completion ไม่มี cache/DLL concurrency.

```text
flutter test --no-pub test/features/progress test/features/learning test/features/rewards test/features/identity test/features/sync/reward_transaction_sync_test.dart test/screens/mastery_dashboard_screen_test.dart test/screens/weakness_clinic_screen_test.dart test/screens/choose_mode_screen_test.dart test/screens/achievements_screen_test.dart test/screens/shop_page_test.dart test/screens/main_navigation_screen_test.dart test/screens/production_shell_navigation_test.dart test/screens/learning_loop_layout_test.dart test/runtime/app_bootstrap_test.dart test/architecture --reporter expanded
```

**Exit0, +261 All tests passed, 17s.** Whole discovered Progress/projector/legacy-XP/learning/reward/identityและ named screens/Shop/layout/shell/bootstrap/all architecture. Expected synthetic shadow-provider exceptionถูก test catch/isolate ไม่ใช่ failure.

Final post-connected/review commandsรันแยกกัน:

```text
dart format --output=none --set-exit-if-changed lib/screens/mastery_dashboard_screen.dart test/screens/mastery_dashboard_screen_test.dart
flutter analyze --no-pub lib/screens/mastery_dashboard_screen.dart test/screens/mastery_dashboard_screen_test.dart
flutter test --no-pub test/screens/mastery_dashboard_screen_test.dart --reporter expanded
git -c core.safecrlf=false diff --check -- lib/screens/mastery_dashboard_screen.dart test/screens/mastery_dashboard_screen_test.dart
```

**Format exit0, 2 files / 0 changed, 0.05s; analyze exit0, No issues found, 2.7s; final whole Dashboard exit0, +21 All tests passed, 4s; scoped diff exit0.** Counts21/261 overlap ไม่ใช่282 unique tests. Final actual diff/scopeและ new checkpoint whitespace/manifestตรวจแยกจาก tracked diff; ไม่มี unrelated normalization/cleanup.

Runtime inventory **2026-10-23T07:18:53.3544635+07:00**: `task_runtime_process_count=0`. Get-CimInstance Win32_Processตรวจ `dart.exe`, `dartvm.exe`, `flutter_tester.exe`, `dartaotruntime.exe` และ workspace/Firestore Java; exec sessionsจบแล้วทั้งหมด ไม่มี processถูก kill.

## Review disposition / limits / next executable step

- Independent reviewerเดิม `/root/lq04_progress_review`: **accepted, C0/I0/M0, no must-fix** บน final two-file hashesด้านล่าง. อ่าน full screen/tests, AppNavigator/ChooseMode/Weakness/AppDeps/query/model และยืนยัน early observerยังส่ง original failed futureให้ view. Reviewer read-only ไม่มี Flutter/Dart/test/analyze/build/write; execution evidenceทั้งหมดข้างต้นเป็น root-run.
- Fresh Claude review **not available**; ไม่มี provider/Claude401 retry/Codex Security. Historical critiqueไม่ใช่ fresh review.
- Ponytailใช้ existing route/FutureBuilder/loader pattern ไม่เพิ่มframework; TDDและ systematic debuggingแยก harness/implementation/fast-error causesก่อนแก้. Impeccable harden/craft-floor และ UI-UX Flutter async guidanceมีผลต่อ truthful waiting/error/empty และ scaled-state tests; ใช้ PRODUCT/DESIGN/Android contextเดิม ไม่ init/rewrite design artifacts. Local Flutter async searchตรง ConnectionState/FutureBuilder outcome.
- Widget evidenceไม่ใช่ physical-device/native screenshot/TalkBack/contrast/actual system Reduce Motion/efficacy/research/release proof. Synthetic disableAnimations/text2×ไม่ใช่ native system-setting validation. Future fencingไม่ใช่ continuous owner observation/atomic rollbackหรือ request cancellation.
- ไม่รัน full repository/build/APK/live provider/research flow. Post-grid1489/scoped-analysis/debug-APKเป็น predecessorก่อน mapping/label/refresh edits; rootต้อง refresh final whole-source integration/build/artifactหลัง next freeze. Known historical unscoped analyzer failureยัง disclosed; ไม่ลบ prototype/buildหรือแก้ analyzer exclusions.
- S3a/v11/Google/full deletion/Source Result history/provenanceและ device/research/release-only gatesยัง held; physical low/mid/high0/3/TalkBackไม่ถูกแทนด้วย widget tests. ไม่ deploy/publish/enroll/upload real data/commit/merge/push/destructive cleanup.

**Next:** source/integration rootตรวจ actual diff + manifest + checkpoint แล้วรับ bounded refreshหรือคืน finding. LQ-04 RETURN sole writer/Flutter slotพร้อม checkpoint SHAแยกให้ทั้งสอง coordinatorและรอ explicit grantใหม่. ไม่มี unresolved bounded must-fixหรือ task process ณ handoff; ไม่เริ่ม next cardเอง.

## Final SHA256 manifest

| Source/test path | SHA256 |
| --- | --- |
| `lib/screens/mastery_dashboard_screen.dart` | `823503CDC6D1D806DC2ED351DC5F73AFADE25AE23F068A205A8FCCE6C2566EF0` |
| `test/screens/mastery_dashboard_screen_test.dart` | `A189B031A5A7F6B249CBDC37AB64105FF5A678E5FF926201F783311032E97D88` |

Checkpoint SHAส่งแยกเพื่อหลีกเลี่ยง self-reference; final review/checksอ้าง source snapshotเดียวกัน.
