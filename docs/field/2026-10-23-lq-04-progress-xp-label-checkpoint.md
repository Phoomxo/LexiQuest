# LQ-04 — PROGRESS-XP-LABEL-LOCAL-1

## Section 13.5 / intent, authority and snapshot

- Outcome: เรียกค่า `progress.gameLevel` เดิมว่า **ระดับเกมจาก XP** แทน **ระดับการเรียน** เพื่อไม่สื่อว่า XP เป็นระดับความสามารถทางภาษา.
- Source root `01a14bdc-3561-7923-9517-1419a4420c64` ให้ ROOT GRANT แบบ exact scope หลัง bounded progress mapping รับแล้ว; latest coordinator proposal ใน `docs/field/2026-10-20-lq-00-wave-0-checkpoint.md` เป็นรายละเอียดที่ root อนุมัติ ไม่ใช่ grant ใบงานอื่น.
- Worktree `C:\Users\Phet\Documents\LexiQuest`; branch `feature/associative-reading-loop`; HEAD `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1` unchanged. Existing dirty work ของผู้ใช้/ใบงานก่อนหน้าถูกเก็บไว้; final manifest ระบุ tested snapshot.
- State: **bounded engineering-complete, submitted for root acceptance; RETURN sole production writer + serialized Flutter/test/analyze/format slot**. ไม่เริ่ม next card.
- Cap LQ-04 38 / program250 คงเดิม; actual spend telemetry ไม่พร้อม จึงไม่อ้างยอดใช้จริง.

## Ground and exact changes

อ่าน actual Dashboard/test/callers, query/model, latest root ledger/proposal, PRODUCT/DESIGN และ incumbent Material3 theme/font. Query ยังเป็น `(totalXp ~/ 20) + 1`; `_DashboardBody` แสดง `progress.gameLevel` โดยตรง. Pre-card hashes ตรง grant: Dashboard `F917F85153115DA55EA0B1129C720DB9B715459AD4A291383B49EE720978E735`, test `2D18F89B574B0F6FAC765463D57C7D34EC119FA30CA6FD090B69DEE49E8FA783`.

เขียนเฉพาะสาม path:

1. `lib/screens/mastery_dashboard_screen.dart`: เปลี่ยน string ของ metric จุดเดียวเป็น `ระดับเกมจาก XP`; formatter ห่อ call นี้หลายบรรทัด. Value ยังคง `${progress.gameLevel}` เดิม ไม่มี layout/calculation/state/refresh/navigation change.
2. `test/screens/mastery_dashboard_screen_test.dart`: คงสาม tests เดิม รวม empty และ Weakness/Achievements/Shop navigation; เปลี่ยน expected label และเพิ่ม old-label absence/metric-value assertions. เพิ่มสี่ matrix cases สำหรับ actual360×800/800×360 × light/dark ที่ text2× โดยใช้ M3Theme และ loaded NotoSansThai; ตรวจ scroll reachability, label bounds, full paragraph/max-lines, semantics, no framework exception และ injected loader เรียกครั้งเดียว. ใช้ published snapshots level1/XP8 และ level11/XP208 ไม่คำนวณ gameLevel ใหม่ใน screen.
3. checkpoint ใหม่นี้; equivalent-file discovery ไม่พบ และ Test-Path เป็น false ก่อนสร้าง.

Other translations/actions/feature-gate/navigation code ใน tracked diff เทียบ HEAD เป็น dirty baseline ก่อน card ไม่ใช่การแก้ครั้งนี้. ตรวจยืนยัน accepted query/projector hashes ยังเป็น `898177A131414199CC38D3D7EC496007C21D5C4A02B30D40D8740D2D07315B61` / `D6B5A1790A57FBAECAFDDC985271AA32566B2CC8B34225045B099C24489590A1` หลังทำ label. ไม่มี query/formula/value/XP/mastery/reward/skill-mapping/API/schema/model/authority หรือ source อื่นถูกเขียน. Catalog8/44/frozen research contracts ไม่เปลี่ยน.

## RED → GREEN

- Initial test-only compile พบว่า const fixture ใช้ property `_snapshot.skills` ใน constant expression ไม่ได้; เปลี่ยน fixture binding เป็น final ตาม diagnostic โดยไม่แก้ production.
- First runtime RED พบป้ายใหม่หาย และ matrix ไป scroll หา target ที่ไม่มี. เพิ่ม explicit existence assertion ก่อน scroll เพื่อรายงาน defect ตรงจุด ไม่ลด assertion.
- Behavioral whole-file RED ก่อน production edit: **exit1, 2 passed / 5 failed**, ทุก failed assertion พบ0 widgets สำหรับ `ระดับเกมจาก XP`; empty/navigation tests เดิมยังผ่าน.
- Production string-only correction ทำให้ whole file **exit0, 7 passed**; ไม่มี wrap/layout fix จำเป็นและไม่ skip/delete/weaken test. Formatting ตามด้วย whole-file rerun หลัง format **exit0, 7 passed** บน final hashesด้านล่าง.

## Final current-source evidence

Source/test คงที่หลัง formatting ก่อน review/connected checks. Flutter/Dart ทุกคำสั่งรัน serialized และ await actual completion; reviewer อ่านอย่างเดียวไม่ใช้ test slot.

```text
flutter test --no-pub test/screens/mastery_dashboard_screen_test.dart --reporter expanded
```

Final post-format focused run: **exit0, +7 All tests passed, 1s test elapsed**. Includes all original tests + four layout cases, ไม่ใช่ name-filtered run.

```text
flutter test --no-pub test/features/progress test/features/learning test/features/rewards test/features/sync/reward_transaction_sync_test.dart test/screens/mastery_dashboard_screen_test.dart test/screens/weakness_clinic_screen_test.dart test/screens/choose_mode_screen_test.dart test/screens/achievements_screen_test.dart test/screens/main_navigation_screen_test.dart test/screens/production_shell_navigation_test.dart test/screens/learning_loop_layout_test.dart test/runtime/app_bootstrap_test.dart test/architecture --reporter expanded
```

**Exit0, +188 All tests passed, 13s.** Whole Progress/legacy-XP/learning/reward and named screens/shell/runtime/all architecture. Expected synthetic shadow-provider exception ถูก catch/isolate โดย test ไม่ใช่ failure. Counts7/188 overlap ไม่ใช่195 unique tests.

```text
dart format --output=none --set-exit-if-changed lib/screens/mastery_dashboard_screen.dart test/screens/mastery_dashboard_screen_test.dart
flutter analyze --no-pub lib/screens/mastery_dashboard_screen.dart test/screens/mastery_dashboard_screen_test.dart
git -c core.safecrlf=false diff --check -- lib/screens/mastery_dashboard_screen.dart test/screens/mastery_dashboard_screen_test.dart
```

รันแยกกัน: **format exit0, 2 files / 0 changed, 0.02s; analyze exit0, No issues found, 2.0s; scoped diff exit0**. Final actual diff/scope และ new checkpoint whitespace/manifest ตรวจแยกจาก tracked diff. ไม่มี unrelated normalization/cleanup.

Runtime inventory **2026-10-23T07:03:18.0940090+07:00**: `task_runtime_process_count=0`; Get-CimInstance Win32_Process ตรวจ `dart.exe`, `dartvm.exe`, `flutter_tester.exe`, `dartaotruntime.exe` และ workspace/Firestore Java. ทุก exec sessionจบแล้ว ไม่มี process ถูก kill.

## Review and UI evidence limits

- Independent reviewer เดิม `/root/lq04_progress_review`: **accepted, C0/I0/M0, no must-fix** สำหรับ XP label card บน final two-file hashes. อ่าน full screen/test และ connected query/model/theme/callers; ระบุ baseline dirty changes และ deferred refresh ถูกต้อง. ไม่เขียนไฟล์หรือรัน Flutter/Dart/test/analyze/build. Execution evidenceข้างต้นเป็น root-run.
- Claude fresh review: **not available**; ไม่ใช้ provider/Claude401 retry. Historical critiqueไม่ใช่ fresh review ของ cardนี้.
- Ponytailคงการแก้ production จุดเดียว. Impeccable clarify/Android/craft-floor และ UI-UX guidance ทำให้รักษา factual copy/Material3/content-sized wrapping/visible semantic label และทดสอบ actual TextScaler2× ด้วย fontจริง แทนการตัดข้อความหรือ redesign. Impeccable context เคยรันแล้วครั้งเดียวใน session ไม่ init/rewrite PRODUCT/DESIGN. Local UX searchแรกเป็น web reflow จึงไม่อ้างว่าเป็น Flutter match; narrower Flutter searchพบ large-font/TextScaler guidance ที่ตรงเรื่องและใช้เฉพาะประเด็นนี้.
- Widget harness ยืนยันขนาด viewport/theme/text scale จริง, labelทั้งหมดอยู่ใน ListView viewport หลัง scroll, hit-testable, paragraphไม่เกิน max lines, accessible labelตรงข้อความ และ old wordingหายจาก semantics. Synthetic disableAnimations=true ครบสี่ cases. ไม่ใช่ native screenshot/device/TalkBack/contrast/actual system Reduce Motion หรือ release acceptance; ไม่มีการอ้าง visual-device evidence ที่ไม่ได้เก็บ.

## Deferred scope / next executable step

Async Dashboard refresh หลังกลับจาก Weakness ยังคง **deferred separate card**; ไม่แก้ `_load`/`_ProgressActions._push` หรือเพิ่ม query/reward side effect. Formula/query/mastery thresholds/skill memberships/learning/reward/identity authority/routes/main/bootstrap/theme/schema/generated/dependencies/native/backend/account/consent/research และ checkpoint อื่นนอก grantไม่เปลี่ยน.

ไม่ได้รัน full repository/build/APK/device/live provider/research flow. Post-grid1489/scoped-analysis/debug-APK เป็น predecessorก่อน mapping และ label edits ไม่ใช่ current-source release proof; source root refresh final integration/build/artifact หลัง next freeze. ไม่ลบ historical build/prototype หรือเปลี่ยน analyzer exclusionsเพื่อซ่อน known unscoped failure. External Google/full deletion/S3a/v11 held/unreserved; physical low/mid/high0/3, TalkBack, efficacy/research/release-only gatesเดิมยังอยู่. ไม่ deploy/publish/enroll/upload real data/commit/merge/push/destructive cleanup/Codex Security.

**Next:** rootตรวจ actual diff/manifest/checkpoint แล้วรับ bounded XP label หรือคืน finding. LQ-04 RETURN sole writer/Flutter slotพร้อม checkpoint SHAแยกให้ source/integration coordinator และรอ grantใหม่. ไม่มี unresolved bounded must-fixหรือ task process ณ handoff.

## Final SHA256 manifest

| Source/test path | SHA256 |
| --- | --- |
| `lib/screens/mastery_dashboard_screen.dart` | `B12CA5C7BC12726B6359DC60D1851867EBBB5B295EC1D8A309CE22BF09607D8B` |
| `test/screens/mastery_dashboard_screen_test.dart` | `08749BAE78EB48C7937191A8A53A92F4D94B3FD77FAE96B35D18574DB48616AC` |

Checkpoint SHAส่งแยกเพื่อหลีกเลี่ยง self-reference; review/focused/connected/analyze/format อ้าง source snapshotเดียวกัน.
