# R15 combined review — F1–F4 repair verification

วันที่ 13 กันยายน 2026 · แก้ตามคำสั่งผู้ใช้หลังตรวจ R15.1–R15.10

## Source และขอบเขต

- Worktree: `C:/Users/Phet/.codex/worktrees/842c/LexiQuest`
- Branch: `feature/r15-integration-continuation`
- Base HEAD: `f4eebb895836349fbf8e9960312a78bad524d462`; การแก้รอบนี้อยู่ใน working diff ยังไม่ commit/merge
- แผน: `docs/superpowers/plans/2026-09-13-r15-review-fixes.md`
- รายงานรีวิวก่อนแก้ยังเก็บเป็น historical evidence: `build/verification/r15-review/REVIEW.md`
- ไม่เปลี่ยน 8/44, EvidenceContext/EventEnvelopeV2, DB/schema, canonical learning/reward authority, research gates หรือ shipped model
- Generated platform registrants 7 ไฟล์มี diff ค้างก่อนเริ่มงานและยังคงอยู่

## ผลแก้ทั้งสี่ข้อ

**F1 — แยก speech attempt จากบทสนทนาใหม่:** reset ยกเลิก speech และ invalidate callback ทันที ตรวจ epoch/conversation/session ใน final/error/status และ async start completion จึงไม่เติมข้อความเก่าหรือเขียนทับ draft ใหม่ การเปิด settings รอ native cancellation เดิมแทนการสั่งซ้ำ; native cancellation ล้มเหลวไม่ทำให้ callback เก่ากลับมาใช้ได้ ไม่เปลี่ยน shared speech policy

Regression ครอบคลุม scenario/level/intent/new chat, cancellation failure และ pending permission พร้อมยืนยันว่าเริ่มไมโครโฟนใหม่ได้

**F2 — source fingerprint:** frontend areas ใช้ input coverage ร่วมสำหรับ lib/test/assets/tool/config; รวม feature authorities และ shared dependencies ที่ regex เดิมตกหล่น ไม่เพิ่มจำนวนเทสต์ที่ถูกเลือก แต่ cache อาจ invalidated บ่อยขึ้นเพื่อไม่ใช้ผลเก่า การตรวจ CLI ใช้ temporary Git fixture และเปลี่ยน dependency ภายใต้ source pins เดิม 7 areas × 8 dependency paths พร้อมตรวจ unchanged input stability

แก้ Runtime contract-test command ที่อ้างชื่อไฟล์ซึ่งไม่มีอยู่ ให้ชี้ `tool/cli/tests/r15-scope.tests.ps1` ที่มีจริง การรันในงานนี้ใช้ explicit targets และ source ปัจจุบัน

**F3 — validation freeze:** ใช้ `r15-camera-freeze-v2` เก็บสำเนา validation predictions และ hash; เมื่อ evaluate ต้องตรวจ schema/hash/coverage/config แล้วคำนวณ validation metrics ใหม่เทียบกับรายงานเดิมทั้ง counts, image IDs, rates และ intervals ก่อนคำนวณ test metrics ข้อมูลขาด/ผิดรูป/nonfinite หรือเปลี่ยนหลัง freeze ถูกปฏิเสธ

**F4 — baseline accounting:** config ต้องมี `baseline_label_map`; predictions ต้องมี `baseline_accepted` เป็น bool จริงเท่านั้น ชื่อ baseline ที่ไม่อยู่ใน mapping เป็น input error จำนวน known-correct ต้องทั้ง accepted และ mapped ถูก ส่วน unknown-false-accept อ่าน explicit acceptance ไม่อนุมานจากชื่อที่อยู่นอกชุดคำ

## รูปแบบ evaluator ใหม่และการใช้ข้อมูลเดิม

ตัวอย่างส่วน config/prediction สำหรับข้อมูล synthetic (ยังต้องมี fields อื่นตาม evaluator เดิม):

```json
{
  "baseline_label_map": {
    "book": "book", "bottle": "bottle", "chair": "chair",
    "cup": "cup", "coffee-mug": "cup", "car": "unknown"
  }
}
```

```json
{"baseline": "coffee-mug", "baseline_accepted": true}
```

`baseline` คือ raw label; mapping คืน canonical label ใน book/bottle/chair/cup/unknown โดย unknown หมายถึงอยู่นอก vocabulary สี่คลาส ไม่ใช่คำสั่งปฏิเสธ หาก baseline ยอมรับคำที่อยู่นอกสี่คลาสบน unknown sample จะนับ accepted ตาม decision จริง ไม่ถือว่า rejected อัตโนมัติ การเปรียบเทียบนี้ยังเป็น pilot สี่คลาส ไม่ใช่ข้อสรุปแทน broad vocabulary

ห้ามเติม acceptance/mapping โดยเดาจากผลเก่า ต้องมาจากนโยบาย/ผล inference ที่ระบุจริง Old incomplete freezes ถูกปฏิเสธและคงไว้เป็นประวัติ สร้าง v2 จาก validation ที่มีหลักฐานครบได้เฉพาะตาม protocol; test ที่เคยเปิดแล้วต้องคงสถานะ development evidence ไม่อ้างว่า fresh ใหม่ คำสั่ง audit และ historical compare ไม่ถูกเปลี่ยนเป็น certification

`decision` ยังคง retain-baseline ไม่มี training/export/inference ใหม่หรือ rollout และข้อมูล curator/predictions ยังเป็น supplied evidence ไม่ใช่หลักฐานความแท้จากผู้ให้บริการ

## ผลทดสอบจริง

Logs ใต้ `build/verification/r15-review/` และ wrapper reports ใต้ `build/verification/f4eebb895836349fbf8e9960312a78bad524d462/`

| Gate | ผล |
|---|---|
| F1 RED, TestName `R15 review` ก่อนแก้ | 1 pass / 4 fail: old transcript แทน draft และ old start หลัง reset; raw log `e57ac9c78d8d-6c829ed7efe6/Explicit-Flutter-tests.stdout.log` |
| F1 initial GREEN | 5 pass ก่อนเพิ่ม cancellation-failure case |
| F2 RED | fingerprint ไม่เปลี่ยนเมื่อ dependency เปลี่ยน และ Runtime test path ไม่มีจริง; `scope-red.log` |
| F2 GREEN | actual fingerprint mutation/stability, target selection และ test-path checks ผ่าน; `scope-green.log`, exit 0 |
| F3/F4 RED | 20 tests, 26 failing assertions/subtests; malformed freeze ไม่ถูกปฏิเสธและ baseline metrics ผิด; `camera-red.log` |
| F3/F4 GREEN | 20 tests passed; `camera-green.log`, exit 0 |
| Initial combined Flutter | 154 pass / 1 fail: settings cancelCalls=2 แทน 1; แก้ให้รอ cancellation เดิมโดยไม่ลด assertion |
| Final combined Flutter | **155 passed / 11 targets**, exit 0, 19.22 seconds wall time |
| Scoped analyzer | 2 touched Dart files, no issues, exit 0; `fixes-analyze.log` |
| Final diff | whitespace check ด้วย core.whitespace=cr-at-eol ผ่าน; semantic review ครบ 6 source/test/tool files |

Python command: `python -B -m unittest discover -s tools -p test_camera_accuracy.py`

CLI command: `powershell -NoProfile -File tool/cli/tests/r15-scope.tests.ps1`

Final Flutter command:

```powershell
& ./tool/cli/verify-scope.ps1 -Level Targeted -Area AI -TestTargets test/screens/ai_tutor_screen_test.dart,test/features/media_practice/speech_practice_use_cases_test.dart,test/features/ai_tutor/ai_tutor_use_cases_test.dart,test/features/ai_tutor/ai_gateway_adapters_test.dart,test/features/ai_tutor/ai_gateway_loopback_test.dart,test/features/gemini/ai_tutor_gateway_factory_test.dart,test/features/gemini/gemini_rest_gateway_test.dart,test/features/gemini/retry_gemini_gateway_test.dart,test/screens/shadowing_challenge_screen_test.dart,test/scenarios/ai_voice_fallback_journey_test.dart,test/scenarios/runtime_kill_switch_journey_test.dart
```

Final report: `targeted-ai-2b607a6d1fdc381d135027a5c797cfc19d42fe2920043f4600d4dbc95cd6d9cd.json`

Final source fingerprint: `abac5b94eee1ce55e460eb86ab7f1c8142cfb7d35206de1a98c3dceb20ec990b`

Final combined log: `d9c3ade053dc-abac5b94eee1/Explicit-Flutter-tests.stdout.log`; earlier failed combined log preserved in `d9c3ade053dc-8a463e2e4b79/`

Six-file source manifest: `build/verification/r15-review/fixes-source.json`, SHA256 `44bb03012124fc079a6b2cd6123fb6a0c1c6908e7c368aeccca59baea67e754f`. Files match after final tests/analyzer. Only plan/report/checkpoint documentation was changed afterward

## Completion boundary

F1–F4 fixed and locally verified. No task-owned test/build/analyzer process remains. No full Flutter/release suite, new APK build/install, live AI/voice, physical camera, two-device sync, research enrollment/upload or deployment was performed. Unaffected R15 tests and device checks in earlier reports remain historical evidence; their counts are not added to this run

Changes remain in this integration worktree for review. The next engineering action, if integrating, is to commit/review this exact diff and run the required release gates on the chosen frozen release source; no merge or rollout is implied by these repairs
