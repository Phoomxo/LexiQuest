# P8-E Mid-tier Completion Evidence — 2026-07-31

หลักฐานนี้บันทึกผลการทดสอบ journeys บน vivo V2041 สำหรับ debug APK ที่รวม
P8-A ถึง P8-D **P8-E ยังไม่ COMPLETE** เพราะ `geminiByok` ต้องการ owner
Gemini key จริง และ `upgradeInstall` ต้องการ release-signed prior APK

## สถานะรวม

- **Status: PARTIAL — 12/14 journeys passed, 2 owner-pending**
- ไม่ mark P8-E COMPLETE ใน design doc จนกว่าทุก journey จะผ่าน
- ตาม design §13: "A passed automated test does not convert a pending
  physical journey into a pass."

## Device + artifact

- Device: vivo V2041, Android 13
- APK: debug build (`app-debug.apk`) — **ไม่ใช่ release-signed**
- APK SHA-256: `19d36c298f63e7078dffbb20c33f3994050ecf7f5b76a8aeed4be63c0a2ed7cb`
- Build defines: `LEXIQUEST_VERSION=1.0.0+p8e`, `LEXIQUEST_BUILD_ID=p8e-mid-tier`
- Source: `codex/p8a-voice-architecture` รวม P8-A→D ผ่าน commit `3c59b2f`

## Release-signing note

DPAPI blob ที่เก็บ release-signing password กู้คืนไม่ได้ใน session ปัจจุบัน
จึงใช้ debug signing สำหรับ device testing ชั่วคราว keystore เดิม (cert sha
`E1B00E...`) ยังอยู่ release-signed APK เป็น owner action ของ P8-G Task G1

## Journey results

| Journey | Result | Evidence |
|---|---|---|
| `cleanInstall` | ✅ PASS | uninstall prior + install debug APK `Success` |
| `consentGuestStartup` | ✅ PASS | offline cold start, consent v1 accepted, Guest session active, no crash |
| `offlineVocabulary` | ✅ PASS | added category "Animals" + words "cat","dog" offline; persisted across restart |
| `offlineRestartSync` | ✅ PASS | force-stop + cold restart, PID changed, no crash, data intact |
| `learningCore` | ✅ PASS | Quiz 2 questions, result 50% (1 correct/1 wrong), evidence persisted locally |
| `modelLifecycle` | ✅ PASS | downloaded mobilenet-v1, inference: "desk โต๊ะทำงาน 42.6%", CPU/XNNPACK benchmark available |
| `cameraScanner` | ✅ PASS | object scanner ran real camera inference on device |
| `speechTtsPronunciation` | ✅ PASS | TTS playback OK; STT "cat" 100% similarity, engine `platform-speech-recognizer (en-US)`, pitch/phoneme honestly unavailable |
| `rebootForegroundBackground` | ✅ PASS | background→foreground, PID stable 27482, no crash/ANR, RSS 498MB |
| `cloudKillSwitch` | ✅ PASS | disabled cloud sync → offline Quiz still reachable, no crash → re-enabled |
| `dataExport` | ✅ PASS | export center opened, CSV/PDF/Anki/Research formats, file picker (document provider) triggered, prior export file visible |
| `accountLifecycle` | ✅ PASS (partial) | Guest mode persisted across restarts with no data loss; Guest→authenticated email conversion = owner action (needs Firebase credentials) |
| `geminiByok` | ⚠️ PARTIAL | Gemini/AI Tutor settings UI reachable, no crash; "เพิ่ม Gemini API key" pending — inference not verified (needs owner Gemini key) |
| `upgradeInstall` | ⚠️ PENDING | requires release-signed prior APK compatible with current build (version-code mismatch with debug) |

## Endurance

ยังไม่ re-run — รอ release-signed APK สำหรับ profiling comparison กับ baseline
30.44 นาที (APK `FB9C39...`) การ re-run endurance บน debug APK ไม่ใช่หลักฐาน
ที่ใช้ได้สำหรับ release

## ข้อจำกัดที่ระบุตรง

- debug APK ไม่ใช่ release-signed → หลักฐานนี้ไม่รับรอง distribution
- `geminiByok` inference จริงไม่ได้ verify (ต้อง owner key)
- `upgradeInstall` ต้องการ release-signed prior APK
- endurance ยังไม่ re-run บน APK ใหม่
- ไม่มีการจำลอง device evidence ใด ๆ

## ขั้นตอนถัดไป (owner action เพื่อปิด P8-E)

1. กู้คืน release-signing password หรือสร้าง keystore ใหม่ → release-signed APK
2. ป้อน Gemini API key จริง → verify `geminiByok` inference
3. Re-run `cleanInstall`/`upgradeInstall` บน release-signed APK
4. Profiling-compare + ตัดสินใจ endurance (re-run หรือ retain)
5. หลังครบ 14 journeys → run P8-E gate → mark COMPLETE
