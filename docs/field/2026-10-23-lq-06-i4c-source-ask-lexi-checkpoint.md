# LQ-06 I4c Source Ask Lexi — checkpoint

## สถานะและขอบเขต

- วันที่ 2026-10-23; bounded local I4c engineering-complete, awaiting root acceptance. ไม่ใช่ full I4 / whole-app / release-ready.
- Worktree: `C:\Users\Phet\Documents\LexiQuest`; branch `feature/associative-reading-loop`; HEAD `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1` (unchanged).
- Authority: `docs/field/2026-10-20-lq-00-wave-0-checkpoint.md`, section **S2 acceptance / I4c Source Ask Lexi exclusive transfer — 2026-10-23**.
- รักษา dirty/untracked predecessor work ทั้งหมด; Source screen/test มีอยู่ก่อน I4c แล้ว ไม่ใช่ไฟล์ที่สร้างใหม่ทั้งชุดในงานนี้. ไม่มี commit/merge/deploy/publish/cleanup.
- RETURN sole production writer + serialized Flutter/test/analyze/format slot. ไม่เริ่ม Source Voice, I5 หรือการ์ดอื่นเอง.
- Cap LQ-06=30 / program=250 unchanged; actual spend unavailable.

## Exact write set และผลที่ได้

1. `lib/screens/source_practice_screen.dart`: ปุ่ม `Ask Lexi: <first matched word>` หลังยืนยัน; reuse `_validatedPreviewForLaunch` และ launch serialization. ตรวจ owner/category/deletion/pending edit/controller identity/scope/epoch ซ้ำก่อนเปิด Tutor. คำที่เปลี่ยน spelling ต้องยืนยันใหม่; prompt เกิน500ถูกปฏิเสธ ไม่ตัดคำเงียบ ๆ.
2. `lib/screens/ai_tutor_screen.dart`: immutable view-only `TutorWordDraft` ในไฟล์เดิม; ติดตั้ง draft ครั้งเดียวหลัง `loadSettings()` สำเร็จ เฉพาะ controller/scope/epoch ที่ตรงกันและก่อนผู้ใช้แก้ข้อความ. Rebuild/theme/settings/new round/controller replacement/owner A→B→A ไม่ทำให้ seed กลับมา.
3. `test/screens/source_practice_screen_test.dart`: เพิ่ม confirmation/word-only/no-write/explicit Send/launch guard/layout regressions โดยใช้ real in-memory Drift + real Gemini use cases และ synthetic gateway/store/voice.
4. `test/screens/ai_tutor_screen_test.dart`: เพิ่ม seed admission/edit→clear/non-resurrection/controller replacement/owner ABA/error cases; รวม seed notice ใน light/dark/2x/IME layout tests เดิม.
5. เอกสาร checkpoint นี้เท่านั้น.

สิ่งที่ Source ส่งต่อมีเพียงคำถามที่มองเห็นและแก้ได้ เช่น `Help me understand the English word "station".` พร้อม owner/controller/epoch ภายใน view. ไม่ส่ง passage, file name/ID/revision, category, meanings, transcript หรือ history. ทั้ง Source และ Tutor แจ้งว่าไฟล์/ข้อความต้นฉบับไม่ได้แนบ. ต้องกด Send เองผ่าน admission/controller/gateway เดิม; การเตรียมหรือเปิด draft ไม่เรียก provider/TTS ไม่ใช้ attempt และไม่เขียน learning/reward/outbox/research.

ไม่มี trusted scope ให้ unavailable guidance และยังใช้ local practice ได้. ไม่แตะ bootstrap/main/domain/gateway/schema/dependencies/native/research/learning/reward authorities; ไม่มี persistence ใหม่.

รักษา T1 ตามคำตอบผู้ใช้: key เก็บแยก owner/auth scope ได้ แต่เป็น credential เท่านั้น; provider และ summary ต้อง explicit enable ใหม่ทุก app launch/owner epoch แม้ crash/uncertain canceled save. ไม่อ่านหรือ migrate legacy key. รักษา I5a สอง mode,500 input/120 output tokens/20s และ8 controller-call attempts ต่อ visible session (ไม่ใช่ HTTP/billing quota); reopen อาจ reset ได้ตามขอบเขตที่อนุมัติ.

ใช้ UI/UX skills เพื่อคง Material/semantic theme และ controls เดิม เพิ่มเฉพาะ action/ข้อความขอบเขต; ไม่สร้าง design system, framework หรือ dependency เพิ่ม. ปุ่ม labelled, disabled ขณะทำงาน และตรวจขนาด Android ≥48dp กับจอขยาย/IME.

## TDD และ bounded recovery

- Baseline whole Source/Tutor files:38 passed,exit0 ก่อน implementation.
- Behavioral RED: Source ไม่มี action ที่ต้องการ; Tutor API scaffold ยังไม่ติดตั้ง seed (คาดข้อความแต่ได้ empty). จากนั้น core implementation40 passed,exit0.
- Expanded intermediate run58 passed/8 failed และรอบถัดมา64 passed/2 failed: layout/scroll/native-async harness ยังรอหรือเลื่อนไปไม่ถึง lazy children. แก้ bounded scroll, `tester.runAsync` สำหรับ fixture consent activation, native async pumps และ `ensureVisible`/hit-testing; เก็บ assertions ด้าน privacy/owner/no-write/Send ไว้ ไม่ skip หรือผ่อน guard.
- Pathological overlong-word fixture ใช้ bounded outer scroll jumps เพราะ editor ยาวรับ drag เอง; focused caseผ่าน1/1. จอ360x800และ800x360ที่2x+IMEผ่าน2/2หลังแก้ harness.
- เคยเริ่ม Tutor test ก่อน Source command เดิมจบ ทำให้ sqlite3 DLL lock ก่อนรัน tests. ไม่ลบ DLL; หยุดเฉพาะ task-owned synthetic tester หลังตรวจ parent/commandline แล้วจึงรัน serialized ใหม่. Buffered/hung Source commands/session53839และ52911ที่หยุดถือว่า incomplete/failed ไม่ใช่ passing evidence; ไม่มี process ค้างท้ายงาน.
- Whole focused filesผ่าน66/66ก่อน final lint-only braces; connected575/575ก่อน bracesเช่นกัน. Scoped analyzerพบ4 info เรื่อง curly braces; แก้4จุดโดยไม่เปลี่ยน logic แล้วรัน final connected suite ใหม่ทั้งหมดตามด้านล่าง.
- Apply-patch context mismatch ถูก reconcile ด้วย read-only source ก่อนแก้ context; failed patches ไม่ทิ้ง partial writes. ไม่มีการแก้ guardrails หรือขยาย write set เพื่อผ่าน checks.

## Final current-source verification

ทุก Flutter/Dart command ด้านล่างรัน serialized; final source/test hashes ด้านล่างไม่เปลี่ยนหลังตรวจ. Final connected command รวม whole unfiltered Source/Tutor files ทั้ง66เคส ไม่ใช่เลือกเฉพาะเคสที่เคยผ่าน.

```powershell
flutter test --no-pub test/screens/source_practice_screen_test.dart test/screens/ai_tutor_screen_test.dart --reporter expanded
```

66/66 passed,exit0,01:41 ก่อน braces-only lint correction; ไม่ใช้ผลนี้แทน final post-braces connected result.

```powershell
flutter test --no-pub test/features/gemini test/features/vocabulary test/features/learning test/features/identity test/features/account test/features/consent test/features/media_practice test/voice test/screens/source_practice_screen_test.dart test/screens/ai_tutor_screen_test.dart test/screens/srs_flashcards_screen_test.dart test/screens/quiz_screen_test.dart test/screens/choose_mode_screen_test.dart test/screens/gemini_settings_screen_test.dart test/runtime/app_bootstrap_test.dart test/runtime/account_startup_restore_test.dart test/architecture --reporter expanded
```

Final post-braces run: **575/575 passed,exit0,01:57**, session82439. Includes real-controller explicit edited Send, Source no-write assertions, T1 restart/uncertain-save/owner guards, existing local Reading/Quiz/Flashcards and Tutor lifecycle regression. Testsใช้ synthetic/local fixtures ไม่ใช่ live provider หรือ research participants.

```powershell
flutter analyze --no-pub lib/screens/source_practice_screen.dart lib/screens/ai_tutor_screen.dart test/screens/source_practice_screen_test.dart test/screens/ai_tutor_screen_test.dart
dart format --output=none --set-exit-if-changed lib/screens/source_practice_screen.dart lib/screens/ai_tutor_screen.dart test/screens/source_practice_screen_test.dart test/screens/ai_tutor_screen_test.dart
git diff --check -- lib/screens/ai_tutor_screen.dart test/screens/ai_tutor_screen_test.dart
```

- Final analyzer: No issues found,exit0,2.9s.
- Final formatter:4 files/0 changed,exit0.
- Tracked scoped diff check:exit0; Gitเตือน LF→CRLF ในอนาคตตาม existing configuration ไม่ได้ normalize/churn ไฟล์อื่น.
- ตรวจทั้ง4ไฟล์รวม untracked Source files ด้วย `Get-Content -LiteralPath` + regex `[ \t]+$`:0 trailing-whitespace lines.
- Independent read-only reviewer `/root/i5a_review` refresh final4ไฟล์: **accepted,Critical0/Important0/Minor0**, hashes4/4ตรง; ไม่พบ authority expansion หรือ assertions ถูกลดทอน. Reviewerไม่ได้รัน Flutter/analyzer/formatter; ผลข้างต้น primaryเป็นผู้รัน.

## SHA-256 manifest

| Path | ก่อน I4c | Final verified |
| --- | --- | --- |
| `lib/screens/source_practice_screen.dart` | `4E616E2C3A0A69FE8321D7437384581C060F76C96CF28B2E49D0B2C5BE6C2254` | `8D5391641EF4765B0EBEC45082835127F5B08BD2109C0C4674216F80D1C9FAA4` |
| `lib/screens/ai_tutor_screen.dart` | `C45222B99D79C19310307EDD6F639CC08C8A68875AD868470B02E57CB73D5CE9` | `E32805BDB0F724CC8EC4382F7BCF61E0F162116A995F49E7288076CE7A931EA7` |
| `test/screens/source_practice_screen_test.dart` | `86DB7B0122EC88ED6B59AFFD5377B524DB23FEDA706D7959ACB25640DDB300B3` | `0EA56F8B31A5D827BFAC2269179D1793C0EF93C82DDF0381FDD5441652B0F293` |
| `test/screens/ai_tutor_screen_test.dart` | `BCE3FBB3CD5314B9095ABF2EBCE6B5BBEB079D91D8E228EEDD59BBB13B568B4D` | `D1A40F379898E30427E995523D2AEE860F4DDBF187A967B84EB73E6C88221EBE` |

Checkpoint hashส่งแยกใน handoff เพื่อไม่อ้าง self-hash ภายในเอกสาร.

## Process inventory, ข้อจำกัด และ next step

```powershell
Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(dart|dartvm|dartaotruntime|flutter_tester|gen_snapshot)(\.exe)?$' } | Select-Object ProcessId,ParentProcessId,Name
```

Final runtime inventory0 รวม `dartvm.exe`; ไม่มี task-owned Flutter/Dart/test commands ค้าง. Source/test hashesตรง4/4หลัง final checks. ไม่มี implementation blocker ค้างใน bounded I4c.

ไม่ได้รัน full-repository regression/analyze/APK ในการ์ดนี้; เก็บไว้ integration checkpoint เมื่อ product cards stable ตาม transfer. ไม่ได้ตรวจอุปกรณ์จริง/IMEจริง/screen reader/reduced-motion ทุกอุปกรณ์, visual screenshot/golden ใหม่, contrast measurement ใหม่, live Gemini/TTS/Cloud หรือ efficacy. Widget layout tests ไม่แทน hardware/UAT/release acceptance.

Source Voice, full source-aware chat/provenance/history, full I4 และ whole-app release ยังคงเปิด; S3/v11ยังheld และไม่ได้จอง migration. ไม่มี deployment/publication/real enrollment/research upload/production authority/cleanup หรือ Codex Security workflow. Actual spend ไม่ทราบ.

Next executable step: rootตรวจ current4/4 hashes + checkpoint/review/evidenceนี้ แล้วรับหรือแจ้งข้อแก้ของ bounded I4c และโอน slot แบบ exact grant. LQ-06 RETURN/read-only หลังส่งมอบ; ไม่เริ่มการ์ดต่อเอง.
