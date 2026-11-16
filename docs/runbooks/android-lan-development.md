# Android LAN Development Runbook

คู่มือนี้ใช้สำหรับรัน LexiQuest บน Android emulator หรือโทรศัพท์จริง โดยให้แอป
เชื่อมต่อ Voice API และ AI API ที่เครื่อง Windows ของผู้พัฒนาอย่างปลอดภัย

## การตั้งค่า Windows

เปิด **Developer Mode** อย่างเดียวก็เพียงพอสำหรับ Flutter, Android SDK และการติดตั้ง
แอปผ่าน USB แล้ว ส่วน **Device Portal** และ **Device discovery** ไม่ต้องเปิด เพราะ
ไม่ได้ใช้ในขั้นตอนนี้และเพิ่มพื้นผิวการโจมตีโดยไม่จำเป็น

เครื่องมือต้องมี `git`, `flutter`, `dart`, `uv`, Android SDK API 36 และ JDK 17

## ตรวจสถานะโดยไม่รบกวน GPU

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/doctor.ps1
```

คำสั่งนี้อ่านสถานะอย่างเดียวและคืน JSON:

| ฟิลด์ | ความหมาย |
| --- | --- |
| `RepositoryReady`, `RequiredToolsReady` | repository และเครื่องมือหลักพร้อม |
| `TrainingActive`, `TrainingProcessIds` | พบ `lora_finetune.py --train` และ PID |
| `GpuAvailable`, `GpuName`, `UsedMemoryMiB` | สถานะ GPU ปัจจุบัน |
| `MayStartGpuInference` | เริ่ม inference บน GPU ได้เมื่อไม่มี training เท่านั้น |

ระหว่าง LoRA training ระบบจะถือ AI/Voice GPU inference เป็น offline แต่ยัง build
หรือรัน Flutter client ได้ คำสั่ง doctor และ run-android จะไม่หยุด พัก ลด priority
หรือเริ่ม process ที่แข่งขันใช้ CUDA

## หา LAN IPv4 ของเครื่อง Windows

```powershell
Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -match '^(10|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.' } |
    Select-Object IPAddress, InterfaceAlias
```

เลือก private IPv4 ของ Wi-Fi/Ethernet ที่อยู่เครือข่ายเดียวกับโทรศัพท์ เช่น
`192.168.1.20`

- Android emulator ใช้ `10.0.2.2` เพื่อเข้าถึง loopback ของเครื่อง host
- โทรศัพท์จริงใช้ private LAN IPv4 ของเครื่อง Windows และ backend ต้อง bind กับ
  `0.0.0.0` หรือ LAN IP

## รันแอป

Android emulator:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/run-android.ps1 `
    -DeviceId emulator-5554 -LanHost 10.0.2.2 -VoicePort 8001 -AiPort 8000
```

โทรศัพท์จริง:

```powershell
flutter devices
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/run-android.ps1 `
    -DeviceId <adb-device-id> -LanHost 192.168.1.20 -VoicePort 8001 -AiPort 8000
```

สคริปต์ตรวจ host/port, สร้าง build ID จาก Git short SHA พร้อมเติม `-dirty` เมื่อมี
ไฟล์แก้ไข, แสดงคำสั่งจริง แล้วจึงเรียก Flutter โดยไม่ใช้ `Invoke-Expression`

หากต้องการสร้าง APK โดยไม่เปิดแอป:

```powershell
flutter build apk --debug `
    --dart-define=LEXIQUEST_VERSION=1.0.0+1 `
    --dart-define=LEXIQUEST_BUILD_ID=<git-short-sha> `
    --dart-define=LEXIQUEST_VOICE_API_URL=http://10.0.2.2:8001 `
    --dart-define=LEXIQUEST_AI_API_URL=http://10.0.2.2:8000
```

## ตรวจว่าแอปที่ติดตั้งเป็น build ใหม่

เปิด drawer ของแอปแล้วดูบรรทัด `<version> · <buildId>` เช่น
`1.0.0+1 · 4a4cf28-dirty` จากนั้นเทียบกับ:

```powershell
git rev-parse --short HEAD
git status --short
```

ถ้า SHA ไม่ตรง แสดงว่าแอปที่ติดตั้งไม่ได้สร้างจาก revision ปัจจุบัน ส่วน `-dirty`
หมายถึงสร้างตอน working tree มีการแก้ไขที่ยังไม่ commit

## ขอบเขต HTTP/HTTPS

Debug build ยอมรับ HTTP เฉพาะ loopback, `10.0.2.2` และ RFC 1918 private IPv4
โดย Android cleartext config อยู่เฉพาะ `android/app/src/debug` ส่วน release build
ปฏิเสธ HTTP ทั้งหมดผ่าน `AppConfig` และต้องใช้ HTTPS backend เท่านั้น

ห้ามใส่ API key, bearer token, Firebase service-account JSON หรือ server secret ใน
`--dart-define` ค่าเหล่านี้จะติดไปกับ binary ของแอป ใช้ได้เฉพาะ URL สาธารณะ,
version และ build ID

## ตรวจระบบฐานทั้งหมดแบบ CPU-safe

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify.ps1
```

สคริปต์ตรวจ Flutter, backend unit tests และ Android APK แบบ fail-fast โดยใช้ Python
environment ที่ติดตั้งไว้แล้ว (`--no-sync`) และไม่เริ่ม OmniVoice, Ollama, local LM
server หรือ model inference
