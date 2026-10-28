# LexiQuest E2E Field Test Report — 2026-08-04

**Device:** vivo V2041, Android 13 (SDK 33), 7.5 GB RAM
**APK:** signed release `1.0.1+2`
**SHA-256:** `FB41242529C69B33898CB4109E88969ADF82E733FB824007CFFC7B5FD43A06F1` (after Firebase appId fix)
**Tester:** automated via adb + ZCode agent

---

## Summary

| Severity | Count | Status |
|---|---|---|
| 🔴 Blocker | 2 | แก้ appId แล้ว 1, ยังไม่แก้ 1 |
| 🟡 Major | 1 | พึ่ง Firebase ใน Guest mode |
| 🟢 Working | 3 | Register, Login, OTP UI |

**ผลรวม:** แอปไม่สามารถเข้าสู่หน้า Home ได้ด้วย Guest mode เนื่องจากปัญหา Firebase Auth + Play Integrity

---

## ปัญหาที่พบ

### 🔴 Blocker #1: Firebase appId ผิด — แก้แล้ว ✅

**Root cause:** `lib/firebase_options.dart` และ `android/app/google-services.json` ใช้ appId ของ Firebase app `vocab_learning_app` (package `com.example.vocab_learning_app`) แทนที่จะเป็น `LexiQuest Production` (package `com.lexiquest.app`)

| ค่า | เดิม (ผิด) | แก้แล้ว (ถูก) |
|---|---|---|
| appId | `719eb38067864496be5a77` | `2c492244dd68e77dbe5a77` |
| package | `com.example.vocab_learning_app` | `com.lexiquest.app` |

**แก้ไข:** อัปเดต `firebase_options.dart` + `google-services.json` → rebuild APK
**ไฟล์ที่แก้:** `lib/firebase_options.dart`, `android/app/google-services.json`
**สถานะ:** แก้ในโค้ดแล้ว แต่ยังไม่รู้ว่าแก้ปัญหาครบ (ดู Blocker #2)

---

### 🔴 Blocker #2: Play Integrity / App Check ไม่ผ่าน — ยังไม่แก้

**Symptom:** `SecurityException: Unknown calling package name 'com.google.android.gms'` + Play Integrity token request ล้มเหลว

**Root cause:** Firebase Auth (Anonymous sign-in) ถูกบล็อกโดย Play Integrity / App Check เพราะ:
1. Package `com.lexiquest.app` อาจไม่ได้ลงทะเบียน SHA cert กับ Firebase app ที่ถูกต้อง
2. Play Console ไม่ได้เชื่อมกับ Firebase app `2c492244dd68e77dbe5a77`
3. App Check enforcement อาจบังคับใช้ Play Integrity โดยไม่มี debug fallback

**ผลกระทบ:**
- Guest mode ใช้งานไม่ได้ (Anonymous Auth ล้มเหลว)
- Login ทำงานได้บางส่วน (Auth สำเร็จแต่ Firestore permission ถูกปฏิเสธ)
- ไม่สามารถเข้าสู่ Home ได้ด้วย Guest

**Action ที่ต้องทำ (Owner):**
1. ไป Firebase Console → Project Settings → App `2c492244dd68e77dbe5a77` → เพิ่ม SHA-1 `7A:B8:6E:48:96:1A:9F:B5:67:49:13:9D:4F:FE:97:8F:D3:B4:36:5B`
2. ไป Play Console → เชื่อมแอปกับ Firebase project
3. ลงทะเบียน App Check ด้วย Play Integrity
4. ปิด App Check enforcement ชั่วคราวจนกว่าจะมี valid token

---

### 🟡 Major #1: Guest mode พึ่งพา Firebase Auth — ปัญหาการออกแบบ

**Root cause:** `GuestSessionService.start()` เรียก `FirebaseAuth.instance.signInAnonymously()` — ถ้า Firebase ไม่ทำงาน Guest ก็ใช้ไม่ได้เลย

**ผลกระทบ:** แอปที่ควรเป็น offline-first ใช้งานไม่ได้เลยถ้าไม่มี Firebase/Auth

**Action ที่แนะนำ:** แยก Guest mode ออกจาก Firebase Auth — สร้าง local-only Guest ที่ไม่ต้องเรียก Anonymous Auth จนกว่าจะ sync

---

## ฟีเจอร์ที่ทดสอบได้และผล

| # | ฟีเจอร์ | ผล | หมายเหตุ |
|---|---|---|---|
| 1 | **Register (สมัครบัญชี)** | ✅ ทำงาน | สร้างบัญชีสำเร็จ → ส่งไปหน้า OTP |
| 2 | **OTP/ยืนยันอีเมล UI** | ✅ ทำงาน | หน้ายืนยันแสดงถูกต้อง ตรวจรหัสผิดได้ |
| 3 | **Login (อีเมล+รหัสผ่าน)** | ⚠️ บางส่วน | Auth สำเร็จ แต่ Firestore ถูกปฏิเสธ |
| 4 | **Guest mode** | ❌ ล้มเหลว | Anonymous Auth ล้มเหลว (Play Integrity) |
| 5 | **Home navigation** | ❌ ไม่ทดสอบได้ | ไม่สามารถเข้า Home ได้ |
| 6-14 | ฟีเจอร์อื่นๆ ทั้งหมด | ❌ ไม่ทดสอบได้ | ติดอยู่ที่ Home |

---

## สิ่งที่แก้ในรอบนี้

| ไฟล์ | การเปลี่ยนแปลง |
|---|---|
| `lib/firebase_options.dart` | appId `719eb...` → `2c492244...` |
| `android/app/google-services.json` | appId `719eb...` → `2c492244...` |
| `pubspec.yaml` | ลบ `integration_test` dev dependency (ทำให้ build fail) |

---

## Next steps (ลำดับความสำคัญ)

1. **ลงทะเบียน SHA-1 cert** กับ Firebase app `2c492244dd68e77dbe5a77` (Firebase Console)
2. **ปิด App Check enforcement** ชั่วคราวเพื่อให้ Guest/Login ทำงานได้
3. **ทดสอบ Guest mode ใหม่** หลังจากลงทะเบียน SHA
4. ถ้ายังไม่ได้ → แยก Guest mode ออกจาก Firebase Auth (code change)
5. เมื่อเข้า Home ได้ → ไล่ทดสอบฟีเจอร์ที่เหลือทั้งหมด
