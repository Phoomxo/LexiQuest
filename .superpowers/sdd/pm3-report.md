# PM3 report — delayed repair, support and canonical Review

2026-09-05. Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch `codex/pair-matching-pm0-pm8`; base source PM2 `23c6b27e`, current HEAD `78848c8f` (root documentation commit). PM3 changes remain uncommitted and unstaged. No schema, frozen contract, catalog, navigation, activation, deployment or new authority change.

## ผลงานและขอบเขต

- เพิ่ม pure repair projection จาก authenticated committed attempt ledger: compact4 เว้น distinct correct other pairs 2, standard6 เว้น 3; pending/neutral/duplicate successes ไม่เพิ่ม spacing. One ticket ต่อ canonical word/session, stable due ordinal → original attempt ordinal → word ID; source operation และ original index ชี้กลับ evidence ID จริง.
- Ticket ไม่เพิ่ม persisted duplicate queue/lexical IDs: สร้างกลับจาก retained ledger จึงใช้ codecVersion2 compact shape เดิมและ PM1 initial bytes เดิม. รุ่น legacy 1–5 ไม่เปลี่ยน. Deferred flag ของ ticket ยังคงอยู่หลัง guided completion.
- Reducer ปฏิเสธการเลือก waiting/guided-required tiles. เมื่อ spacing ช่วงท้ายเป็นไปไม่ได้ หรือ scheduled repair ผิดซ้ำ เข้าสู่ revealed guided-required state. กรณีทุกคู่รอกัน เลือก guided tail ตาม stable order เพื่อไม่ deadlock. Wrong command ไม่ match/เพิ่ม progress.
- เพิ่ม `PairConfirmGuidedMapping`: learner confirmation แยกจาก wrong, bind canonical word, shown support revision, owner/session/round/op revision และ fingerprint. จึงสร้าง correct guidedPractice หนึ่งรายการ; duplicate acknowledged operation ไม่เพิ่มอีก. ไม่มี distractor guessing loop ใน guided-required state.
- ใช้ `PairSupportPolicy.classify` ผ่าน state `classificationFor` ทุก boundary: reducer support chronology, coordinator dispatch/frozen/recovery, codec hint level, repository pending occurrence และ committed checkpoint validation. `delayedRepair` ยังคง role แม้ support ทำให้ evidence เป็น guidedPractice; first wrong ไม่ถูกเขียนประวัติใหม่.
- เพิ่ม `PairReviewDeferral` read-only adapter และ coordinator `deferredReview`: ตรวจ actual committed owner/session/word/answer ID แล้ว expose item จาก `DriftReviewCenterReader` เดิมด้วย exact provenance. ไม่เขียน answer/Review queue/SRS. สอง wrong sources ที่ถูกต้องยังอยู่ใน item เดียว; source แรกหายต้อง reject handoff ของ source แรก แม้ item ยังมี wrong source อื่น.
- Audio เป็น **pure policy seam เท่านั้น**: local pronunciation หรือ text/IPA fallback enum; ไม่มี remote-text path และไม่สร้าง semantic support. ยังไม่ใช่หลักฐาน VoiceUseCases, native audio, offline/private route session, TalkBack หรือ UI fallback จริง. PM6 ต้องต่อและทดสอบทั้งหมดนั้น.

## Byte/revision admission

ขยาย shared budget ให้ reserve future wrong/scheduled-repair/guided opportunities, optional support writes และ terminal/Continue-untimed reserve เดิม. Byte projection ใช้ acknowledged interpretation ของ pending ก่อนนับ future rows และ full PM2 frozen-occurrence bound; ไม่ตัด attempts ไม่เพิ่ม 64-KiB/revision/attempt ceilings.

Raw bound 3 attempts ต่อ unresolved new word หัก distinct completions ที่จำเป็นก่อน scheduled failure แรก (forced guided confirmations ที่นับใน bound แล้วห้ามหักซ้ำ). Initial bound เป็น 10 สำหรับ compact4 และ 15 สำหรับ standard6; เป็น conservative bound ไม่ใช่คำอ้างว่าทุก combination สามารถมี 15 attempts จริง. มี 200 seeded valid schedules ตรวจ bound ลดอย่างน้อยหนึ่งต่อ acknowledged answer พร้อม round-trip strict state ทุก step; actual adversarial six-pair fixture ทำ 13 attempts (6 correct และ 7 wrong) แล้วจบได้โดยไม่ปฏิเสธ wrong ที่ยอมรับไปแล้ว.

- Six-pair fixture: initial full-worst-future reservation **59,357 bytes**, maximum written pending/clear snapshot **8,871 bytes**.
- Admitted compact4 มี Thai word IDs 256 ตัว, long spelling/meaning/owner/plan metadata, actual canonical evidence ID 197 ตัว: maximum written snapshot **24,022 bytes**; answer lost ACK + clear lost ACK restore/retry ผ่าน และทุก snapshot <=65,536.
- Max-everything Unicode six-pair PM2 fixture ไม่พอสำหรับ PM3 worst-future reserve: reject **ก่อน LearningSession INSERT** (SQLite BEFORE INSERT trigger proves ordering), ไม่มี session/event/ID allocation. ไม่เปลี่ยน plan density โดยเงียบ ๆ.
- Historical PM2 committed 29-attempt Unicode fixture ยังคง codec read-only regression และอ่านครบ29. ไม่ใช้ reducer ใหม่สร้าง unlimited immediate retries. Old codec1/2 generic append negative tests ยืนยันเลือก reader version เก่าเพื่อ admit immediate retry ไม่ได้; pending repair chronology rejects และจำนวน canonical answers คงเดิม.

## RED → GREEN และ recovery evidence

1. Pure repair/support fixtures เริ่ม RED เพราะยังไม่มี policy types/files; หลังเพิ่ม policy ผ่าน5. Integrated engine fixture เริ่ม RED เพราะยังไม่มี repair tickets/guided-confirm action; หลังเพิ่ม reducer ผ่าน รวม waiting-tile fence, separate confirmation, retained wrong และ strict round trip.
2. Real Review fixture เริ่ม RED เพราะไม่มี typed handoff/coordinator API; หลัง implementation ผ่านจริงกับ Drift source events, provenance และ guided evidence.
3. Initial Pair regression พบ9 failures จาก fixtures PM2 ที่สมมติ immediate/unlimited retry. เปลี่ยนเป็น exact spaced schedule โดยเก็บ wrong/source identity, historical codec bytes, checkpoint budget, Unicode, before/after lost ACK และ recovery assertions. ไม่ลบ/skip tests หรือทำให้ production constraints อ่อนลง.
4. Seeded reserve test จับ defect จริง: six-pair seed2 หลัง11 answers เหลือ guided-only2 คู่ แต่ bound เหลือ1. แก้ให้ไม่มี spacing deduction ถ้าไม่มี scheduled opportunity เหลือ; 200 seeded schedules GREEN. นี้เป็น meaningful failing assertion ก่อนแก้ arithmetic.
5. Test construction errors แก้ตาม evidence: generator 197 ตัวถูก canonical binder prefix `attempt:` เพิ่ม8จนเกิน bound จึงกลับเป็น generator189→actual197; ambiguous Drift matcher import เอาออก; EventsV2 ใช้ discovered `eventId` field. One read-only wildcard path error ถูกแทนด้วย `rg --files` discovery. ไม่มี uncertain writes หรือ destructive recovery.
6. Focused analysis พบ unused/duplicate imports และ brace lints แก้แล้ว; test byte logging เปลี่ยนเป็น `printOnFailure` หลัง avoid_print info. Final analysis no issues.

## Verification บน source ปัจจุบัน

**Impacted subsystem run: 495 passed, exit0** ก่อนเพิ่ม comparator/duplicate test และ numeric test diagnostics เท่านั้น; production source ไม่เปลี่ยนหลัง run นี้:

```text
flutter test --no-pub test/features/learning/pair_matching test/features/review/review_center_reader_test.dart test/features/learning/srs_policy_test.dart test/features/learning/hint_policy_test.dart test/features/learning/evidence_eligibility_policy_test.dart test/features/learning/matching_mode_adapter_test.dart test/features/learning/current_activity_evidence_test.dart test/features/learning/drift_learning_repository_test.dart test/features/learning/unified_lesson_controller_test.dart test/features/recommendation test/services/srs_service_test.dart test/services/weakness_clinic_service_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart test/features/identity/upgrade_guest_owner_test.dart test/features/sync/srs_state_sync_test.dart test/architecture/pair_matching_f10_boundary_test.dart --reporter expanded
```

Log: `.superpowers/sdd/pm3-impacted.log`.

**Final Pair selection: 89 passed, exit0** (`flutter test --no-pub test/features/learning/pair_matching --reporter expanded`), log `pm3-final-pair.log`. หลังเปลี่ยน test-only print→printOnFailure รัน affected evidence file อีกครั้ง **16 passed, exit0**, log `pm3-final-evidence.log`.

**Final focused analysis: No issues found, exit0**:

```text
dart analyze lib/features/learning/pair_matching lib/features/learning/data/drift_learning_repository.dart lib/features/review/application/pair_review_deferral.dart test/features/learning/pair_matching
```

Log `pm3-analysis.log`. Final production diff inspected; `git diff --check` exit0 ไม่มี whitespace errors. Existing generated registrant LF/CRLF status/warnings ยังคงเดิม ไม่ reset/cleanup. An accidental formatter-only idempotency-test diff was restored precisely; no unrelated test change remains.

PM3 actual Drift matrix 2 directions ×3 fault boundaries ×2 before/after states: supported delayed repair stays guided, guided confirmation uses one exact evidence ID, restore/retry succeeds, two real wrong provenance sources stay in one canonical Review item, source-event removal/mismatched owner/session/word/revision fail closed, and seeded due SRS row remains exactly equal. Canonical Review/recommendation/Weakness/SRS/owner regression suites above passed. This does not substitute for future PM8 Pair-specific authenticated owner rehome integration.

## Exact source/test write set

New:

- `lib/features/learning/pair_matching/domain/pair_repair_policy.dart`
- `lib/features/learning/pair_matching/domain/pair_support_policy.dart`
- `lib/features/review/application/pair_review_deferral.dart`
- `test/features/learning/pair_matching/pair_repair_policy_test.dart`
- `test/features/learning/pair_matching/pair_support_classification_test.dart`
- `test/features/learning/pair_matching/pair_review_deferral_test.dart`

Modified:

- `lib/features/learning/pair_matching/domain/pair_matching_engine.dart`
- `lib/features/learning/pair_matching/domain/pair_matching_checkpoint_budget.dart`
- `lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart`
- `lib/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart`
- `lib/features/learning/data/drift_learning_repository.dart` (Pair classification only)
- `test/features/learning/pair_matching/pair_matching_engine_test.dart`
- `test/features/learning/pair_matching/pair_matching_checkpoint_codec_test.dart`
- `test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart`

Local handoff artifacts: this report, updated preflight interpretation, `.superpowers/sdd/pm3-*.log`. Root retains status/RTM ownership.

## Remaining boundaries and handoff

PM3 implementation ready for independent root review, not production activation. PM4 owns timer, actual terminal schema/receipts, restart round semantics and combined reserve extension. Current reducer still round0 and PM4 must retain session-level repair/support/evidence lineage across rounds. PM5 owns actual stars/replay/history; self-correction recognition here does not establish star acceptance. PM6 owns routed host, explicit shown-mapping confirmation UI, real Voice fallback/privacy/TalkBack integration and device accessibility evidence. No new frozen contracts, DB tables, SRS/Review queue or reward authority. No full repository suite/build/pub/codegen/commit/security worker/deploy/real enrollment/upload performed.

Tooling released to root after final report; no task-owned running Flutter/Dart process. Next executable step: root independent diff/spec review of these14 source/test files, then in-scope fixes or PM3 acceptance before PM4 dispatch.

## Independent review followup — negative test specificity

อ่าน `pm3-review-report.md` แล้ว: Spec/Quality Approved, หนึ่ง Minor เรื่อง forged pending fixture มี frozenEvidence=null จึงอาจ reject จาก binding แม้ chronology fence ไม่ทำงาน. แก้เฉพาะ `test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart`; ไม่มี production change และไม่ stage/commit ทับ review index ของ root.

- Fixture ใช้ actual `CurrentActivityEvidenceAdapter.captureMatching(...).freezeForRecovery()` ด้วย canonical owner/session/word/pin/attempt number/classification ที่ตรงกับ pending.
- เพิ่ม direct `PairMatchingState.fromJson` assertion เจาะจง `FormatException.message == 'Pair repair chronology changed'` จึงไม่ผ่านด้วย frozen-binding failure อื่น.
- ทั้ง codec1/2 มี legal spaced control: commit correct other pairs2คู่จริง แล้ว decode same fixture construction ด้วย delayedRepair role และ valid frozen occurrence สำเร็จ. Negative append ไม่เพิ่ม canonical rows; positive decode ก็ไม่สร้าง pending answer โดยตัวมันเอง.
- ยืนยัน contract จาก `_expandEngine`: version1 และ2 ใช้ promptIndex/targetIndex ใน attempt เหมือนกัน; version2 เพิ่ม compact selected/matched/support IDs และ start envelope. ไม่เปลี่ยน version1 attempt เป็น lexical keys.
- Focused execution แรกพบ test-only Drift matcher ambiguity แล้วแก้; exact-path assertion จับ version1 fixture alias (`engine = public`) ซึ่ง compact mutation ทำ public assertion กลายเป็น shape error. แยก map copy แล้วทั้ง strict-path assertions และ positive controls GREEN.

Verification: `flutter test --no-pub test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart --plain-name 'historical codec' --reporter expanded` **2 passed, exit0**, log `pm3-review-followup-tests.log`. `dart analyze test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart` **No issues found, exit0**, log `pm3-review-followup-analysis.log`. Root original staged snapshot preserved; followup test/report unstaged. Tooling released again; no running process.
