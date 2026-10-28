# P8-F Owner Runbook — Device Matrix และ Cloud Readiness

สถานะ: รอ owner ดำเนินการด้วย signed release candidate (RC) และอุปกรณ์จริง

## เงื่อนไขก่อนเริ่ม

- P8-E ผ่าน 14/14 journeys บน vivo V2041 ด้วย RC เดียวกัน
- มีอุปกรณ์จริง low, mid (vivo V2041) และ high อย่างละหนึ่งเครื่อง
- มีสิทธิ์ Firebase/Play Console สำหรับตรวจ App Check
- มี private references สำหรับ support, feedback และ research
- มี real API key สำหรับ Gemini, OpenAI, OpenRouter, Claude และ MaxPlus

ห้ามรวมหลักฐานจากคนละ commit, dependency-lock hash หรือ APK SHA-256

## Device evidence ที่ต้องบันทึก

สร้างไฟล์ต่อเครื่องใน `field/evidence/devices/*.json` ตามรูปแบบนี้ โดย
`journeys` ต้องเป็น object ไม่ใช่ array:

```json
{
  "evidenceId": "<unique-id>",
  "tier": "low",
  "pseudonymousDeviceId": "<SHA-256>",
  "recordedAtUtc": "<ISO-8601 UTC>",
  "device": {
    "physical": true,
    "model": "<model>",
    "androidVersion": "<version>",
    "ramMb": 4096,
    "chipset": "<chipset>",
    "gpu": "<gpu>",
    "storageFreeMb": 10240,
    "networkProfile": "offline-slow-online"
  },
  "release": {
    "apkSha256": "<same RC SHA-256>",
    "signingCertificateSha256": "<same certificate SHA-256>",
    "modelSha256": "<same model SHA-256>",
    "versionName": "<version>",
    "versionCode": 1,
    "buildId": "<build-id>"
  },
  "journeys": {
    "consentGuestStartup": { "status": "pass", "evidenceRef": "private:<ref>" },
    "offlineVocabulary": { "status": "pass", "evidenceRef": "private:<ref>" },
    "learningCore": { "status": "pass", "evidenceRef": "private:<ref>" },
    "offlineRestartSync": { "status": "pass", "evidenceRef": "private:<ref>" },
    "accountLifecycle": { "status": "pass", "evidenceRef": "private:<ref>" },
    "modelLifecycle": { "status": "pass", "evidenceRef": "private:<ref>" },
    "cameraScanner": { "status": "pass", "evidenceRef": "private:<ref>" },
    "speechTtsPronunciation": { "status": "pass", "evidenceRef": "private:<ref>" },
    "geminiByok": { "status": "pass", "evidenceRef": "private:<ref>" },
    "cleanInstall": { "status": "pass", "evidenceRef": "private:<ref>" },
    "upgradeInstall": { "status": "pass", "evidenceRef": "private:<ref>" },
    "rebootForegroundBackground": { "status": "pass", "evidenceRef": "private:<ref>" },
    "cloudKillSwitch": { "status": "pass", "evidenceRef": "private:<ref>" },
    "dataExport": { "status": "pass", "evidenceRef": "private:<ref>" }
  },
  "benchmarks": {
    "cpuXnnpack": {
      "status": "pass", "delegate": "xnnpack", "iterations": 20,
      "medianLatencyMs": 20.0, "evidenceRef": "private:<ref>"
    },
    "gpuDelegate": {
      "status": "notApplicable", "allowlisted": false, "iterations": 0,
      "reason": "GPU not allowlisted", "evidenceRef": "private:<ref>"
    }
  },
  "endurance": {
    "status": "pass", "durationMinutes": 30, "crashCount": 0,
    "anrCount": 0, "peakRssMb": 300, "batteryStartPercent": 90,
    "batteryEndPercent": 80, "temperatureStartC": 31,
    "temperatureEndC": 38, "evidenceRef": "private:<ref>"
  }
}
```

ทั้งสามเครื่องต้องตรวจ cold start, resume/background, process recreation,
microphone, TTS, cancellation, offline/slow network/provider errors, guest
persistence, Guest→Authenticated, database migration, upgrade install และ API
key lifecycle ห้ามถอนแอปเพื่อทำ journey `upgradeInstall`

## Provider smoke evidence

รันคำขอจริงอย่างน้อยหนึ่งครั้งต่อ provider ด้วย RC เดียวกัน เก็บไฟล์ใน
`field/evidence/providers/*.json` โดยห้ามบันทึก key, prompt หรือ response:

```json
{
  "providerId": "openai",
  "status": "pass",
  "apkSha256": "<same RC SHA-256>",
  "recordedAtUtc": "<ISO-8601 UTC>",
  "evidenceRef": "private:<redacted-smoke-record>"
}
```

ต้องมี `gemini`, `openai`, `openrouter`, `claude`, `maxPlus` อย่างละหนึ่งรายการ
ส่วน Custom OpenAI-compatible/Cointh ให้ระบุ experimental จนกว่าจะมีหลักฐานจริง

## Cloud controls

1. สังเกต valid App Check traffic ขณะ enforcement ปิด
2. เปิด enforcement แล้วทดสอบ valid/invalid traffic
3. ทดสอบ Cloud kill switch โดย offline learning ต้องยังทำงาน
4. บันทึก billing mode และ budget alerts
5. ใส่ private references จริง ห้ามมี placeholder/pending

## ปิด gate

ประกอบ evidence:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/new-field-release-evidence.ps1 <owner parameters>
```

ตรวจ release gate หนึ่งครั้งต่อ APK hash:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-field-release.ps1 -EvidencePath field/evidence/release-evidence.json
```

หาก source, dependency lock หรือ APK เปลี่ยน ต้องสร้าง RC ใหม่ และรันเฉพาะ
focused gate ที่ได้รับผลกระทบก่อนทำ device smoke ซ้ำทุกเครื่อง
