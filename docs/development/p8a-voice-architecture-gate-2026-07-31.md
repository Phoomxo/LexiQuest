# P8-A Voice Architecture Gate — 2026-07-31

หลักฐานเชิงข้อเท็จจริง (factual gate evidence) สำหรับเกต P8-A voice architecture ของ LexiQuest

## ขอบเขตและข้อจำกัด (สำคัญ)

เอกสารนี้เป็นหลักฐาน **เฉพาะสถาปัตยกรรมและ debug-build** เท่านั้น มิใช่การรับรองด้านอื่น ๆ โดยเจาะจงระบุว่าเอกสารนี้ **มิใช่** การรับรองประเภทใดประเภทหนึ่งต่อไปนี้:

- การทดสอบบนอุปกรณ์จริงใหม่ (new physical-device testing)
- การทดสอบ GPU
- การทดสอบกล้อง (camera)
- การทดสอบ STT (speech-to-text)
- การทดสอบความอดทน/อายุการใช้งาน (endurance)
- การเซ็นชุด release (release-signing)
- การรับรองแบบ 30 ผู้เข้าร่วม (30-participant certification)

นอกจากนี้ ระบุอย่างชัดแจ้งว่ารายการต่อไปนี้ยังคงอยู่ในขั้นตอน P8-B/P8-C **และยังมิได้ถูก implement หรือรับรองโดย P8-A:**

- การส่งมอบ VoxCPM runtime/model delivery
- การ mirror เสียงของผู้เข้าร่วมในเซสชัน (participant session voice mirroring)

## แหล่งที่มมของการ implement

- Source implementation commit: `60001c7e3b9a531df3d12d4963058c9593f639ec`

## เกตคำสั่งที่รับรอง (accepted command)

```
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-voice-architecture.ps1
```

การเรียกใช้ที่รับรอง (accepted invocation) ครั้งสุดท้ายผ่าน PASS โดยแต่ละ phase ทำงานครั้งละหนึ่งครั้ง และ **ไม่มีการ retry อัตโนมัติ** ของ phase ที่ล้มเหลว

## ความโปร่งใสเกี่ยวกับกระบวนการก่อนการรับรอง

การเรียกเกตก่อนการรับรอง (earlier pre-acceptance gate invocation) ครั้งก่อนหน้าได้เปิดเผยปัญหา **incorrect repository-root hop** หลังจากนั้น contract ได้รับการเสริมความแข็งแกร่ง (strengthened) script ได้รับการแก้ไข แล้วการเรียกใช้ที่รับรองจึงทำงานหนึ่งครั้ง ไม่มี phase ที่ล้มเหลวถูก retry อัตโนมัติ

## ผลลัพธ์ของแต่ละ phase

| Phase | ผลลัพธ์ |
| --- | --- |
| dart format | 46 files ตรวจสอบ, 0 changed |
| flutter analyze | ไม่มี issues |
| focused tests | 282 passed |
| contract tests | PASS=98 FAIL=0 |
| participant screen boundary | ผ่าน — `rg VoiceServiceFactory|ManagedVoiceService` ใน `lib/screens` ไม่พบ matches |

## Debug build artifact

- เส้นทาง: `C:\Users\Phet\Documents\LexiQuest\.worktrees\p8a-voice-architecture\build\app\outputs\flutter-apk\app-debug.apk`
- ขนาด: 217449805 bytes
- SHA-256: `4932FC1A5057357EC7CD1FCF20225B35CE9EF48C4455513712A4FCDCC140F12E`

## สภาพแวดล้อมการ build

- Flutter 3.44.7 stable, revision `84fc5cbb22`
- Dart 3.12.2
- Build defines:
  - `LEXIQUEST_VERSION=1.0.0+p8a`
  - `LEXIQUEST_BUILD_ID=p8a-voice-architecture`

## คำเตือน build แบบ non-blocking

- คำเตือนเกี่ยวกับ future Kotlin built-in migration ในอนาคต
- คำเตือนเกี่ยวกับ Android SDK XML tool-version mismatch

คำเตือนเหล่านี้เป็นแบบ non-blocking และมิได้ส่งผลให้เกตล้มเหลว
