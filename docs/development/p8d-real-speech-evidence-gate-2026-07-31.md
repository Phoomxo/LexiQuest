# P8-D Real Speech Evidence Gate — 2026-07-31

หลักฐานนี้รับรองเฉพาะขอบเขต P8-D ได้แก่การบันทึกหลักฐานการออกเสียงจริง
(recognized transcript, similarity score, STT engine, similarity algorithm
version) ผ่าน Drift local repository, provenance กลางที่สอดคล้องกัน,
typed unavailable state สำหรับ silence/failure (แทน zero score), การลบ
cosine-similarity evaluator ที่ไม่ได้ใช้ และการ wire Shadowing และ
Speak-to-Text ให้ persist evidence จริง

## ผลรับรอง

- Accepted command:
  `powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-real-speech-evidence.ps1`
- Result: **PASS**
- Implementation source commit:
  `68c81231ff2c7e8b0ccf12ea133f102548e5f205` (gate commit; full P8-D series
  `ec80359` plan → `cbf9dec` → `0961f9a` → `8975b24` → `94f8dfb` → `68c8123`)
- Gate contract: `PASS=14 FAIL=0`
- Dart format: scoped files, 0 changed after format
- Flutter analyzer: no issues
- Focused speech evidence tests: 48 passed
- Privacy boundary scan: passed (no raw audio persisted; centralized provenance
  uses `transcript-edit-distance-v1`; silence is a typed unavailable state)
- `git diff --check`: passed

ทุก phase ของ accepted invocation ทำงานหนึ่งครั้งตามลำดับและหยุดทันทีเมื่อ
ล้มเหลว โดยไม่มี automatic retry ภายใน gate

## Artifact

- Debug APK:
  `build/app/outputs/flutter-apk/app-debug.apk`
- Size: `249326247` bytes
- SHA-256:
  `bd89c2d289b51fd4d96463d84a2f65fe62f8d35f1e08c1b9580773b548ed45b1`
- Build defines:
  - `LEXIQUEST_VERSION=1.0.0+p8d`
  - `LEXIQUEST_BUILD_ID=p8d-real-speech-evidence`

## Deliverables

- `lib/features/media_practice/domain/speech_evidence_contract.dart` — versioned
  `SpeechEvidenceProvenance` builder + `SpeechAssessmentResult` (available /
  unavailable) so provenance and silence handling are centralized.
- `lib/features/media_practice/application/speech_practice_use_cases.dart` —
  `assessEvidence()` returns a typed `SpeechEvidenceUnavailable.silence` for
  empty transcripts instead of a zero score.
- `lib/data/local/tables/speech_evidence_tables.dart` + schema version 7 —
  `SpeechEvidence` table with transcript, score, engine, algorithm, sample
  size, unavailable reason, and duration; cascade-deleted with the session.
- `lib/features/media_practice/data/drift_speech_evidence_repository.dart` +
  `speech_evidence_use_cases.dart` — owner-resolved persistence.
- Shadowing Challenge and Speak-to-Text now persist a real `SpeechEvidence` row
  (transcript, score, engine, method) alongside the boolean answer that feeds
  SRS, and use the centralized provenance builder. Silence persists an
  unavailable reason without a score.
- Removed the unused `lib/services/cosine_similarity_evaluator_service.dart`
  (+ test) so the authoritative transcript-edit-distance algorithm is
  unambiguous.

## Runtime boundary

gate นี้ทดสอบด้วย injected fake `SpeechRecognitionGateway` และ in-memory Drift
เท่านั้น ไม่มีการอัดเสียงจากไมโครโฟนจริง และไม่มี cloud sync ของ speech evidence
(outbox path ยังเป็น P8-E onward) ไฟล์ enrollment audio และ raw microphone
stream ไม่ถูก persist — เก็บเฉพาะ recognized transcript text และ derived
metadata (score, engine, algorithm version, unavailable reason)

pitch/phoneme ยังเป็น unavailable ตาม spec §9 (แสดงเป็น honest unavailable
state ไม่ใช่ fabrication) — similarity score ปัจจุบันมาจาก
transcript-edit-distance เท่านั้น

## สิ่งที่ยังไม่ได้รับรองโดย P8-D

- คุณภาพเสียง/latency ของ acoustic pronunciation (pitch/phoneme) จริง
- การอัดเสียงจากไมโครโฟนจริงบนมือถือ (ทดสอบด้วย fake gateway)
- cloud sync ของ speech evidence (outbox path, `SyncCollection.speechEvidence`)
- weakness/SRS policy extension (ยังทำงานผ่าน boolean `isCorrect` เหมือนเดิม)
- การปิด journey บน vivo V2041 และทดสอบ 3 ระดับเครื่อง (P8-E/F)
- release signing และการแจกจ่าย (P8-G)

รายการเหล่านี้ยังเป็น P8-E ถึง P8-G และห้ามตีความจาก debug gate นี้ว่าเสร็จแล้ว

## Toolchain

- Flutter 3.44.7 stable
- Dart 3.12.x
- Drift 2.34.x (schema version bumped 6 → 7; idempotent migration)
