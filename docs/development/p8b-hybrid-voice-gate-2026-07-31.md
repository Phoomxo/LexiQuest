# P8-B Hybrid Voice Gate — 2026-07-31

หลักฐานนี้รับรองเฉพาะขอบเขต P8-B ได้แก่ VoxCPM2 standard-speech adapter,
verified standard audio packs, การดาวน์โหลดแบบ resume/checksum/atomic
activation, offline-pack playback, dynamic quota, provider kill switch และ
Native TTS fallback

## ผลรับรอง

- Accepted command:
  `powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-hybrid-voice.ps1`
- Result: **PASS**
- Implementation source commit:
  `eb7e36fd7e44d4f4fa893f8882b95011f64f4930`
- Gate contract: `PASS=17 FAIL=0`
- Dart format: 61 files, 0 changed
- Flutter analyzer: no issues
- Focused Flutter tests: 305 passed
- Backend voice API: 70 passed, 1 opt-in E2E skipped
- Standard voice-pack contract: `PASS=10 FAIL=0`
- `uv lock --check`: passed
- `git diff --check`: passed

ทุก phase ของ accepted invocation ทำงานหนึ่งครั้งตามลำดับและหยุดทันทีเมื่อ
ล้มเหลว โดยไม่มี automatic retry ภายใน gate ก่อน accepted invocation มีการ
เรียกผ่าน CLI wrapper ที่ตั้ง timeout ผิดเป็น 1 วินาที ทำให้ pipe ถูกปิดก่อน
จบ Dart dependency resolution; เหตุการณ์นั้นไม่ใช่ผลทดสอบของแอปและไม่ถูกนับ
เป็น accepted invocation

## Artifact

- Debug APK:
  `build/app/outputs/flutter-apk/app-debug.apk`
- Size: `249176396` bytes
- SHA-256:
  `B79BEBD543175DEE083BD4D0C8FADB600A726A62B0CF39F5FC1274DDC9CF3E6E`
- Approved-content fixture SHA-256:
  `0C9C36D2167274D1CB0B168FF71566C248A768A32CFE287EE29B55018D9BED67`
- Build defines:
  - `LEXIQUEST_VERSION=1.0.0+p8b`
  - `LEXIQUEST_BUILD_ID=p8b-hybrid-voice`

## Toolchain

- Flutter 3.44.7 stable, revision `84fc5cbb22`
- Dart 3.12.2
- Python 3.11.15
- uv 0.11.8

## Runtime boundary

VoxCPM2 เป็น optional backend dependency และไม่ได้ถูกติดตั้งใน environment
ของ gate (`voxcpm-installed=False`) จึงไม่มีการดาวน์โหลด model weights และไม่
มีค่า GPU/cloud inference ระหว่าง unit gate นี้ ตัว adapter ถูกทดสอบด้วย
injected fake loader/writer และ production จะโหลด `openbmb/VoxCPM2` แบบ lazy
เมื่อเปิดใช้ worker ที่ติดตั้ง optional runtime แล้วเท่านั้น

APK ไม่ bundle model หลายกิกะไบต์ ระบบใช้ verified offline audio pack ก่อน,
ใช้ authenticated standard provider เมื่อออนไลน์ และ fallback ไป Native TTS
อย่างกำหนดได้เมื่อ pack/provider/network/quota/model ไม่พร้อม

## สิ่งที่ยังไม่ได้รับรองโดย P8-B

- การโหลด model VoxCPM2 จริงและคุณภาพ/latency ของ inference จริง
- GPU worker หรือ physical-device audio quality
- การดาวน์โหลด pack จาก production CDN จริง
- participant voice enrollment, cloning หรือ session voice mirror
- STT/pronunciation field validation
- release signing และการรับรองผู้เข้าร่วม 30 คน

รายการเหล่านี้ยังเป็น P8-C ถึง P8-G และห้ามตีความจาก debug gate นี้ว่าเสร็จแล้ว

## คำเตือนที่ไม่ block gate

- Flutter รายงานว่า plugin บางตัวต้องย้ายออกจาก Kotlin Gradle Plugin แบบเดิม
  ก่อน Flutter รุ่นอนาคตบังคับ Built-in Kotlin
- dependency 15 รายการมีรุ่นใหม่กว่าที่ไม่เข้ากับ constraint ปัจจุบัน จึงยัง
  ไม่อัปเกรดระหว่าง P8-B เพื่อหลีกเลี่ยงการขยายขอบเขต
