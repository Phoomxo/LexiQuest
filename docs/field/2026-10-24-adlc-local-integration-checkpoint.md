# ADLC local integration checkpoint — 2026-10-24

## คำตัดสิน

สถานะ: **LOCAL ENGINEERING ATTESTED; PRODUCTION ACTIVATION PENDING EXTERNAL AUTHORITY**

งานที่พัฒนาได้อย่างปลอดภัยใน checkout นี้ผ่านขั้น Ground, Plan, Execute,
Review, Attest และ local Integrate แล้ว โดยคง feature catalog 8 หมวด/44
ความสามารถและ authority เดิมไว้ครบ เอกสารนี้ไม่อนุญาตให้ deploy, เปิดรับผู้เข้าร่วม
งานวิจัย, ส่งข้อมูลจริง, ลบบัญชีจริง หรือ rollout ผ่าน Play Console

## Source snapshot

- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- HEAD baseline: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`
- Dirty worktree เดิมถูกรักษาไว้; ไม่มี reset/cleanup/overwrite งานผู้ใช้
- Deterministic manifest: 548 files จาก `lib/`, `test/`, `tool/`,
  `pubspec.yaml`, `pubspec.lock`
- Manifest: `output/integration-2026-10-24-adlc/source-manifest.json`
- Manifest SHA256:
  `C23B01D2462AF29F1CFF2DB3205DB7792A2899945A37BF31947C31ED9221F93E`

## ผลงานที่รวมใน snapshot นี้

| Card | ผลลัพธ์ |
| --- | --- |
| `DEVICE-DIALOG-1` | แก้ lifecycle race ของ dialog controller ที่พบจาก Test Lab และยืนยันซ้ำบน Vivo ด้วย IME จริง |
| `UI-PREF-1` | เพิ่ม System/Light/Dark ที่บันทึกค่าได้ โดยไม่ชน theme/wallpaper marketplace และไม่ทำ navigation state หาย |
| `FOLD-1` | เพิ่ม hinge-aware safe-area fallback ที่เลือก pane ปลอดภัย พร้อม synthetic vertical/horizontal hinge coverage |
| `ACCOUNT-A3` | หากสร้าง/เชื่อมบัญชีสำเร็จแต่ส่ง verification email ครั้งแรกล้มเหลว ระบบคง committed session และให้ resend ได้ |
| `ACCOUNT-G1` | เพิ่ม Google sign-in adapter, owner binding, anonymous-link/fallback และ UI busy guard; production default-off |
| `RESEARCH-R1` | เพิ่ม operation authorizer และ production deny-all; consent อย่างเดียวไม่สามารถส่งออกชุดวิจัย |

Review ของ agent ทั้งสามยืนยัน write set แบบจำกัด, owner isolation,
fail-closed research boundary และ conservative fold fallback ไม่มี must-fix
คงค้างในขอบเขต local engineering นี้

## Verification บน source snapshot เดียวกัน

| Gate | ผล |
| --- | --- |
| Connected focused Flutter matrix | 174/174 ผ่าน |
| Full Flutter regression | 1636/1636 ผ่าน, exit 0, 08:39 |
| Flutter analyze `lib test tool` | No issues found, exit 0 |
| Dart format check | 466 files, 0 changed, exit 0 |
| `git diff --check` | exit 0; มีเฉพาะ LF-to-CRLF warnings |
| Voice API | 55 tests ผ่าน |
| AI API | 76 tests ผ่าน |
| LexiQuest-LM | 75 tests ผ่าน |
| Backend รวม | 206 tests ผ่าน |
| Runtime/Android/CI/dependency/policy/Firestore/model/release CLI checks | 351 checks ผ่าน |
| Debug APK build | สำเร็จ |
| Release APK build | สำเร็จ |
| Release AAB build | สำเร็จ |
| `:app:validateSigningRelease` | BUILD SUCCESSFUL |
| APK `apksigner` | v2 verified, signer 1 ราย |
| APK/AAB ZIP integrity | ผ่านทุก entry |

ไม่ได้เรียก Codex Security ตาม project guardrail

## Build artifacts

| Artifact | Bytes | SHA256 |
| --- | ---: | --- |
| `build/app/outputs/flutter-apk/app-debug.apk` | 221,291,351 | `A3CDC608D75B7FB95F90A8BC55268B8AC9435430CDDF10D4899B3F74A672396C` |
| `build/app/outputs/flutter-apk/app-release.apk` | 112,139,940 | `7EFADB475F83F83E14E732DC86D337A292EC389A7886960B390AE131094D372C` |
| `build/app/outputs/bundle/release/app-release.aab` | 99,964,497 | `47CA2D090A68343CEA72DBBBA7A38ACE88305A0513ABB38EC29137C69DA8E3F0` |

Release certificate DN:
`CN=LexiQuest Release, OU=Field Trial, O=LexiQuest, L=Bangkok, ST=Bangkok, C=TH`

Certificate SHA256:
`E1B00E17896BFB73FE0DC42429768B966465213D49A8A5165DE06688CC8FDC1F`

`jarsigner -verify -strict` ของ AAB คืน exit 4 แม้รายงาน `jar verified`
เพราะ upload certificate เป็น self-signed และมี Android bundle
JarFile/JarInputStream warnings การรับ AAB hash นี้โดย Play Console จึงยังเป็น
release-only gate

## Vivo post-fix evidence

- Device: vivo V2041, Android 13, 1080x2408, density 440, font scale 1.0
- ติดตั้ง debug APK ปัจจุบันด้วย `adb install -r` สำเร็จและเปิดแอปสำเร็จ
- ตรวจ startup, Profile, Settings และ Appearance จริง
- Settings แสดง “การแสดงผล” และข้อมูล Guest/research/offline/export/AI
  โดยไม่พบ layout overlap จากภาพที่ตรวจ
- Appearance แสดงตัวเลือก “ใช้ตามอุปกรณ์”, “โหมดสว่าง”, “โหมดมืด”
  และปุ่มบันทึกครบ พร้อม semantic nodes กดได้
- App-PID log หลังเปิด Appearance ไม่มี fatal, AndroidRuntime, Flutter exception,
  disposed-controller หรือ assertion error
- `uiautomator` ของ Vivo แจ้ง `EACCES` เมื่ออ่าน OEM
  `/sys/board_info/user_cpu_freq` แต่ยัง dump/pull XML สำเร็จ; เป็นคำเตือนจาก
  tooling ของอุปกรณ์ ไม่ใช่ crash ของ LexiQuest
- Evidence manifest: 13 files ที่
  `output/integration-2026-10-24-adlc/vivo/evidence-manifest.json`
- Evidence manifest SHA256:
  `4230D702DA73AB47858713AE42C9B3A0D8AF4E43AE0BC391D3D6411BC69E2288`

ภาพหลัก:

- `startup.png` SHA256
  `01E29E04930A627E9F2D40BD9514298833E04D5529EE5DEB5519B91304253BF5`
- `profile.png` SHA256
  `A222185ADCD8CE55E60BACF2A6C005A2876B69777399AE6CEE34BFD47004D839`
- `settings.png` SHA256
  `7C501AD40DB306636F18976BFB068CC3B70847147BB7E152E006E0302F61F1C0`
- `appearance.png` SHA256
  `67814CA1AE0B850602A0632DE44EEFC1CE7DA3CD2E409DD7F9A7A38797804556`

## External/authority gates ที่ยังเปิดไม่ได้

1. **Google Sign-In production:** `android/app/google-services.json` ยังมี
   `oauth_client: []` สำหรับทั้ง `com.example.vocab_learning_app` และ
   `com.lexiquest.app`; `LEXIQUEST_GOOGLE_SIGN_IN_ENABLED` จึงต้องคง false
   จน Firebase/Google Console มี SHA fingerprints และ Web OAuth client จริง
2. **Research production:** production ใช้ deny-all ต่อไปจนมี canonical
   EvidenceContext, trusted permit/assignment issuer, signature algorithm,
   revision/expiry/revocation, protocol/instrument pins และ rollout authority
3. **Full account deletion:** ยังต้องมี privileged idempotent recursive-delete
   backend, full export, recent reauthentication และ deletion receipt ครอบคลุม
   owner-scoped tables ทั้งหมด จึงยังไม่เพิ่มปุ่มที่ลบเพียง Firebase user
4. **Firebase Test Lab post-fix:** quota physical device 5/5 ทำให้ artifact
   ปัจจุบันยังไม่ได้ rerun บน cloud low/high/fold/tablet หลักฐาน matrix เดิมเป็น
   predecessor evidence ส่วน current-source evidence มี Vivo และ synthetic fold tests
5. **Figma Cloud:** R11 local source/preview ยังเป็น design authority; cloud file
   ยังคง R10 เพราะ Starter write quota/payload path ยังไม่พร้อม
6. **Release/operations:** Play acceptance, App Check, production Firestore,
   stakeholder UAT และ rollout permission ยังต้องใช้สิทธิ์/หลักฐานภายนอก
7. **Hardware coverage:** FOLD-1 ยังไม่ได้ทดสอบบนอุปกรณ์พับจริงหลังแก้;
   ใช้ one-pane fallback โดยตั้งใจ ไม่ใช่ spanning UI

Build ยังเตือนว่า plugin บางตัวต้องย้ายไป Kotlin Built-in ในอนาคต และ retained
database write lock ที่เกิน 5 วินาทียังคงคืน timeout ตามสัญญาปัจจุบัน ทั้งสองข้อ
ไม่ทำให้ verification รอบนี้ล้มเหลว

## ADLC disposition

- **Intent/Ground/Plan:** ครบและอ้าง active source/guardrails
- **Execute:** การ์ด local ทั้งหมดบน board เสร็จ
- **Review:** agent reviews + root diff/repository review ไม่มี must-fix ในขอบเขต
- **Attest:** test/analyze/build/signature/device evidence ข้างต้นผูกกับ manifest
- **Integrate:** local engineering เสร็จ; ไม่มี deployment หรือ destructive write
- **Learn:** เก็บ dialog lifecycle regression, research fail-closed, OAuth
  default-off และ fold fallback เป็น regression contracts แล้ว

การเปลี่ยน production source หลัง checkpoint นี้จะทำให้หลักฐาน source snapshot
หมดอายุและต้องรัน integration gate ใหม่
