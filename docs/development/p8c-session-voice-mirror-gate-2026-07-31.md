# P8-C Session Voice Mirror Gate — 2026-07-31

หลักฐานนี้รับรองเฉพาะขอบเขต P8-C ได้แก่ participant voice mirror ชั่วคราวต่อ
session: consent journey แยกต่างหาก, enrollment/recorder, Flutter gateway,
client-side session controller, lease/heartbeat/expiry, privacy boundary
(mirror output ไม่เข้า cache, raw audio/session ไม่เข้า Drift/Firebase/export),
uncached playback routing, และการล้างไฟล์ในทุก termination path

## ผลรับรอง

- Accepted command:
  `powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-session-voice-mirror.ps1`
- Result: **PASS**
- Implementation source commit:
  `8e9966a3a098c5450a295a4359ac204bd76fe558` (gate commit; full P8-C series
  `4bae4e4` → `3652758` → `baf9ca4` → `28241b5` → `8e9966a`)
- Gate contract: `PASS=18 FAIL=0`
- Dart format: scoped files, 0 changed
- Flutter analyzer: no issues
- Focused Flutter voice tests: 93 passed
- Shadowing challenge consent journey: 8 passed
- Runtime bootstrap tests: 37 passed
- Backend voice API: 104 passed, 1 opt-in E2E skipped
- Privacy boundary scan: passed (no mirror/private data in persistence, no
  cache, no raw logging in mirror boundary)
- `uv lock --check`: passed
- `git diff --check`: passed

ทุก phase ของ accepted invocation ทำงานหนึ่งครั้งตามลำดับและหยุดทันทีเมื่อ
ล้มเหลว โดยไม่มี automatic retry ภายใน gate

## Artifact

- Debug APK:
  `build/app/outputs/flutter-apk/app-debug.apk`
- Size: `249271587` bytes
- SHA-256:
  `91a3d2bbb644a6370f2a2d8db74670c8aaa8fafd2d7bd84185a5fe615630808a`
- Build defines:
  - `LEXIQUEST_VERSION=1.0.0+p8c`
  - `LEXIQUEST_BUILD_ID=p8c-session-voice-mirror`

## Deliverables

- Backend mirror session store, VoxCPM2 mirror engine, authenticated lease
  endpoints (`backend/voice_api`).
- `lib/voice/voice_mirror_gateway.dart` — authenticated HTTP boundary,
  refreshed-once bearer token, `Cache-Control: no-store`, typed failures.
- `lib/voice/voice_mirror_session_controller.dart` — separate consent,
  renewable lease, absolute 20-minute lifetime, request/character quota,
  idempotent end, cleanup-on-failure as `cleanupIncomplete`.
- `lib/voice/voice_mirror_recorder.dart` — bounded WAV enrollment in a
  dedicated cache directory, stop-then-delete, cancel/dispose cleanup, startup
  purge of stale files.
- `lib/voice/vox_cpm_mirror_provider.dart` — participant-transient provider,
  `allowsStandardCache: false`, forwards only the current learning target.
- Factory wiring with a `MirrorAwareVoicePolicySource` so consent/session
  state is read dynamically and mirror audio is never cached.
- Shadowing Challenge consent UI: optional AI target speech section, default
  off, retention summary, record/stop/cancel/withdraw, no free-text field.

## Runtime boundary

gate นี้ทดสอบด้วย injected fakes และ `MockClient`/`MockRecorder` เท่านั้น
ไม่มีการโทรไปยัง VoxCPM2 worker จริง, ไม่มีการอัดเสียงจากไมโครโฟนจริง และ
ไม่มี Firebase token จริง gate ยืนยัน privacy boundary, lifecycle cleanup,
lease/expiry logic, และ Android compile path ของทุกไฟล์ P8-C

ไฟล์ enrollment audio อยู่ใน dedicated cache subdirectory
(`voice_mirror_enrollment`) เท่านั้น และถูกลบในทุก path (stop/cancel/
dispose/startup purge) ข้อมูล mirror ไม่เข้า Drift, Firebase, research
export, media storage, หรือ backup ใด ๆ

## สิ่งที่ยังไม่ได้รับรองโดย P8-C

- คุณภาพเสียง/latency ของ model VoxCPM2 จริง (เป็น injected fake)
- GPU worker หรือ physical-device audio quality
- การอัดเสียงจากไมโครโฟนจริงบนมือถือ (recorder ทดสอบด้วย fake session)
- production deployment ของ voice API และเซสชันจริง
- STT และคะแนน pronunciation จากหลักฐานเสียงจริง (P8-D)
- การปิด journey บนเครื่อง vivo V2041 และทดสอบ 3 ระดับเครื่อง (P8-E/F)
- release signing และการแจกจ่ายให้ผู้เข้าร่วม (P8-G)

รายการเหล่านี้ยังเป็น P8-D ถึง P8-G และห้ามตีความจาก debug gate นี้ว่า
เสร็จแล้ว โดยเฉพาะอย่างยิ่งไม่อาจอ้างว่าระบบทำงานบนอุปกรณ์จริงหรือมี
คุณภาพเสียงเป้าหมายที่ได้รับการพิสูจน์

## Toolchain

- Flutter 3.44.7 stable
- Dart 3.12.x
- record `7.1.1` (pinned; switched from `^5.2.0` because the `record_linux`
  0.7.2 platform package was incompatible with `record_platform_interface`
  1.6.0 and failed the Android build — 7.x ships consistent platform packages)
- Python 3.11.x, uv (backend `uv lock --check` + pytest)
