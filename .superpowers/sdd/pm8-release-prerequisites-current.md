# PM8 release prerequisites — current bounded recheck

Root execution addendum (2026-09-07): locked Node dependencies are now materialized. npm ci printed263 packages installed; helper-local LASTEXITCODE shadow prevented capturing native exit, so that run remains an uncertain-capture prerequisite attempt. Subsequent read-only npm ls --depth=0 --json returned actual exit0 and confirmed firebase-admin14.2.0, firebase12.16.0 and @firebase/rules-unit-testing5.0.1 with unchanged package files (pm8-node-dependency-reconciliation.json). No reinstall. Known node exit7 diagnostic proved local shadowing/global capture; ignored runner/helper now reset/read global:LASTEXITCODE and choose one resolved command. Corrected diagnostic captured7; parser passes. Earlier runner hashes below are historical after this root correction. No actual release gate/policy test/APK build yet. Main test/analyzer wrappers used top-level capture and are unaffected.

ตรวจครั้งแรกเมื่อ 2026-09-07 09:54 ICT และปรับ gate ตาม bounded follow-up ใน worktree
`C:/Users/Phet/.codex/worktrees/02fa/LexiQuest` ตามขอบเขต PM8 release preflight และ
runner hardening งานนี้ไม่ได้รัน Flutter, Dart, pub, npm install, tests, build,
generator, scanner, emulator/server, Supabase SQL หรือ Android device command และไม่ได้แก้
Git index/HEAD/process/configuration การแก้ไขถาวรถูกจำกัดไว้ที่ runner และรายงานนี้

## สรุปผล

- Branch คือ `codex/pair-matching-pm0-pm8` และ HEAD คือ
  `3bdb5f5605e670e8b30628f3f237cd9c0d660ad9` ตรงกับ identity ที่มอบหมาย
- ก่อนสร้างรายงานนี้ `git status --short` มี 27 entries: modified 23 และ untracked
  Pair tests 4 ไฟล์ จึงยังไม่มี frozen clean source snapshot สำหรับ release evidence
- `docs/generated/alltcas-8-44-final-test-plan.json` ยังอ้าง
  `sourceCommit=ed89efaf32a1090505a84d4b55b2cc60003068b3` และ
  `sourceFingerprint=8e9ac9a8d74eba3cf2807ff6b02f6e57c4fa97ee6e3b49b8a8acb8f84a173988`;
  ไม่ตรงกับ HEAD ปัจจุบัน สถานะนี้ **คาดไว้ก่อน source commit/plan generation** และไม่ใช่
  implementation blocker; ห้ามใช้ runner จนกว่า generator จะสร้าง plan จาก frozen source
- `.superpowers/sdd/pm8-run-gate.ps1` ผูก HEAD และ canonical raw source hashes กับ plan
  ก่อน/หลัง native command แล้ว รายละเอียด exit behavior และ verification อยู่ด้านล่าง
- Firebase demo policy scripts ชี้ไปยัง demo project และ loopback ที่ถูกต้อง แต่
  `node_modules` ไม่มีอยู่ใน worktree จึงยังรันไม่ได้จาก dependency snapshot ปัจจุบัน
- pinned LiteRT AAR และ debug APK ไม่มีอยู่ใน build tree จึงยังตรวจ APK runtime integrity
  ไม่ได้ สถานะนี้ **คาดไว้ก่อน serialized build** และไม่ใช่ implementation blocker
- Docker executable มีอยู่ แต่ Docker Desktop Linux engine pipe ไม่มี จึงตรวจ container
  ownership/migration state ไม่ได้ และ Supabase contract เป็น **NotRun**

## Executable locations และ versions ที่ตรวจสด

คำสั่ง version ด้านล่างเป็น metadata-only และ exit 0 ยกเว้น `apkanalyzer --version`
ซึ่งโปรแกรมแสดง usage แทน version จึงอ่าน revision จาก SDK `source.properties`

| Tool | Exact resolved path | Current version evidence |
|---|---|---|
| Git | `C:/Program Files/Git/cmd/git.exe` | `git version 2.54.0.windows.1` |
| Java | `C:/Program Files/Eclipse Adoptium/jdk-25.0.3.9-hotspot/bin/java.exe` | Temurin OpenJDK `25.0.3+9-LTS` |
| Node | `C:/Program Files/nodejs/node.exe` | `v24.16.0` |
| npm | `C:/Program Files/nodejs/npm.cmd` (`npm` also resolves `npm.ps1`) | `12.0.1` |
| Gitleaks | `C:/Users/Phet/AppData/Local/Microsoft/WinGet/Links/gitleaks.exe` | `8.30.1` |
| OSV Scanner | `C:/Users/Phet/AppData/Local/Microsoft/WinGet/Links/osv-scanner.exe` | scanner `2.4.0`, scalibr `0.4.5`, commit `b56b519...` |
| adb | `C:/Users/Phet/AppData/Local/Microsoft/WinGet/Packages/Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe/platform-tools/adb.exe` | ADB `1.0.41`, platform-tools `37.0.0-14910828` |
| apkanalyzer | `C:/Users/Phet/AppData/Local/Android/Sdk/cmdline-tools/latest/bin/apkanalyzer.bat` | command-line tools `Pkg.Revision=22.0`; CLI ไม่มี direct version verb |
| Firebase CLI | `C:/Users/Phet/AppData/Roaming/npm/firebase.cmd` | global `firebase-tools` package `15.24.0` (อ่าน package.json; ไม่ execute CLI) |
| Docker | `C:/Program Files/Docker/Docker/resources/bin/docker.exe` | file version `29.6.2`; daemon unavailable |

Global Java path ไม่ยืนยันว่า Flutter/Gradle จะเลือก JDK ตัวนี้ และงานนี้ไม่ได้รัน Flutter
หรือ Gradle เพื่ออนุมาน readiness

## Firebase Auth/Firestore emulator prerequisites

`package.json` กำหนด scripts ดังนี้จริง:

```text
test:auth  = firebase emulators:exec --project demo-lexiquest-auth-test --only auth
             "node --test test/security/firebase-auth-emulator.test.cjs"
test:rules = firebase emulators:exec --project demo-lexiquest-rules-test --only firestore
             "node --test test/security/firestore-rules.test.cjs"
```

`firebase.json` bind Auth ที่ `127.0.0.1:9099` และ Firestore ที่
`127.0.0.1:8080`; test sources pin project IDs เดียวกัน และ Firestore test เชื่อม
`127.0.0.1:8080` โดยตรง ณ เวลาตรวจทั้งสอง port ไม่มี listener และไม่มี owner process

สถานะ dependency/cache:

- `package-lock.json` มีอยู่ แต่ `node_modules`, `node_modules/.bin/firebase.cmd`,
  `node_modules/firebase`, `node_modules/@firebase/rules-unit-testing` และ
  `node_modules/firebase-tools` ไม่มีอยู่
- global `firebase-tools` มี Auth emulator implementation ใต้
  `.../firebase-tools/lib/emulator/auth/` และมี `firestoreEmulator.js`
- Firestore emulator JAR ถูก cache ที่
  `C:/Users/Phet/.cache/firebase/emulators/cloud-firestore-emulator-v1.21.0.jar`
  ขนาด 138,093,843 bytes; cache ยังมี storage/database/UI artifacts แต่ไม่มีหลักฐาน
  runtime readiness จากการ execute

ดังนั้น global CLI/emulator assets พร้อมบางส่วน แต่ npm policy tests ยังมี blocker ที่
local Node packages ไม่ถูก materialize งานนี้ไม่ได้ติดตั้งหรือรันคำสั่งดังกล่าว

## Supabase/Docker

พบไฟล์ที่ inventory ระบุครบ:

- `supabase/config.toml`
- `supabase/migrations/20260727000000_image_bucket_public_readonly.sql`
- `test/security/supabase_storage_contract.sql`

`docker ps --filter "name=supabase" ...` ติดต่อ
`npipe:////./pipe/dockerDesktopLinuxEngine` ไม่ได้เพราะ pipe ไม่มีอยู่ จึงไม่มี container
ให้ inspect และไม่มีหลักฐานอิสระว่าเป็น task-owned, synthetic และ migrated แล้ว
สถานะ Supabase policy contract สำหรับ release run นี้คือ **NotRun**; ห้ามอ้าง historical
container หรือเริ่ม/reset/stop container เพื่อเติมผลนี้โดยอัตโนมัติ

## APK verifier prerequisites

- `pubspec.yaml` ปัจจุบันคือ `version: 1.0.0+14`
- verifier pin AAR ที่
  `build/flutter_litert/tmp/downloadLitertJni/litert-2.1.5.aar`
  และ SHA-256 ที่คาดคือ
  `A162D1DDBDAD87C002B7EC7EB31A703F2761335E693F292F94091B3569D8AA37`
- AAR ไม่มีอยู่ จึงไม่มี actual hash ให้เปรียบเทียบ
- `build/app/outputs/flutter-apk/app-debug.apk` ไม่มีอยู่
- `apkanalyzer.bat` มีอยู่ตาม path ในตาราง; `apksigner` ไม่อยู่บน PATH

`tool/cli/verify-apk-model-runtime.ps1` จึงยังรันไม่ได้จนกว่า serialized build ที่ได้รับ
อนุญาตจะสร้างทั้ง AAR/APK จาก frozen source โดยไม่ลด checksum policy ไม่มี remote lookup
หรือ artifact download ในการตรวจครั้งนี้

## `pm8-run-gate.ps1` interface และ source-identity behavior

Static parser ยืนยัน interface ปัจจุบัน:

```text
-SourceCommit <40 lowercase hex>                 mandatory
-SourceFingerprint <64 lowercase hex>            mandatory
-Label <[a-z0-9][a-z0-9-]{0,80}>                 mandatory
-Executable <Application|ExternalScript>          mandatory
-ArgumentList <string[]>                          optional
```

Helper ยังคงบังคับ exact worktree/branch และตรวจ `SourceCommit`/`SourceFingerprint` กับ
generated plan ก่อนสร้าง evidence รอบแก้ไขเพิ่ม behavior ต่อไปนี้:

1. อ่าน property จริง `sources[].path` และ `sources[].sha256` จาก generated JSON เท่านั้น
   และคำนวณ raw SHA-256 ของทุก declared source ก่อน/หลัง command ไม่มี ignore rules
2. สำหรับ declared directory รวมทุก regular file แบบ recursive โดยไม่ follow reparse links,
   sort absolute path ด้วย ordinal comparison แล้ว hash UTF-8 ของ
   `child/path<NUL>raw-file-sha256` ที่เชื่อมด้วย LF ไม่มี trailing newline ตรงกับ
   `_hashSourcePath` ใน generator รวมถึง entries `lib`, `test`, `tool` และ nested directories
   ที่ plan ระบุ
3. บังคับ `checkout HEAD -ceq SourceCommit` ทั้งก่อนและหลัง native command และตรวจว่า
   generated plan bytes ไม่เปลี่ยนระหว่าง run
4. ใช้ชื่อรอบแบบ Gregorian UTC/invariant
   `pm8-yyyyMMddTHHmmssfffZ-<label>` แทน local-time filename
5. Metadata บันทึก `sourceCheckBefore`/`sourceCheckAfter` พร้อม expected/actual hash ทุก
   entry, `checkoutHeadBefore`/`After`, plan hashes, `commandStarted`,
   `nativeExitCode`, `gateExitCode`, `invocationFailure` และ `gateFailures`

Exit behavior เป็น fail closed:

- pre-check ผิด: ไม่เริ่ม native command, `nativeExitCode=null`, `gateExitCode=1`
- native command nonzero: เก็บ code เดิมใน `nativeExitCode` และใช้ code เดิมเป็น
  `gateExitCode` แม้ post-check จะพบ mismatch เพิ่ม
- native command exit 0 แต่ HEAD/source/plan post-check ผิด: เก็บ
  `nativeExitCode=0` และคืน `gateExitCode=1`
- ทุก check ตรงและ native command exit 0 เท่านั้นที่คืน `gateExitCode=0`
- field `exitCode` เดิมยังอยู่เพื่อ compatibility แต่มีความหมายเป็น gate exit;
  original native result อยู่ใน `nativeExitCode`

Runner นี้ต้องใช้หลัง source commit และ final-plan generation/check แต่ก่อน documentation-only
commit ตาม sequencing ที่ root ระบุ Stale plan ปัจจุบันจึงเป็น expected precondition failure
runner เสริม generator checks และไม่ทดแทน generator contract suites Metadata ยังไม่ execute
tool `--version`; release assembler ต้องแนบ version evidence กับ run เดียวกันตาม inventory

### Focused verification ของ runner

- RED ก่อนแก้ยืนยันว่าไม่มี canonical hash, pre/post snapshot, separate exit,
  invariant UTC filename และ HEAD/start binding
- PowerShell current parser และ Windows PowerShell parser: PASS หลังแก้
- synthetic raw-byte fixture ภายใต้ `.superpowers/sdd` ตรวจ uppercase/lowercase ordinal order
  `B.txt`, `a.txt`, `z/nested.txt`, forward-slash child path, NUL separator, LF join และ
  raw file SHA-256: PASS; directory SHA-256 คือ
  `0f510e187306220ca365e1fc7f9a39683649176ce8911d76d81a4e09246ef9a5`
- synthetic `sources[].path`/`sha256` snapshot ให้ `match` เมื่อ hash ตรง และ `mismatch`
  เมื่อ expected hash ผิด: PASS
- fixture files ถูกลบหลังตรวจ ไม่มี actual gate invocation, native release command หรือ
  `build/verification` evidence ถูกสร้างในการทดสอบนี้

## Reproducible read-only commands

```powershell
Set-Location -LiteralPath 'C:/Users/Phet/.codex/worktrees/02fa/LexiQuest'
git branch --show-current
git rev-parse HEAD
git status --short

git --version
java -version
node --version
npm.cmd --version
gitleaks version
osv-scanner --version
adb version
apkanalyzer.bat --version  # prints usage; read cmdline-tools/latest/source.properties

Get-NetTCPConnection -State Listen -LocalPort 9099,8080 -ErrorAction SilentlyContinue
docker ps --filter 'name=supabase' --format '{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}'

Test-Path -LiteralPath 'node_modules/.bin/firebase.cmd'
Get-ChildItem -LiteralPath 'C:/Users/Phet/.cache/firebase/emulators' -File
Test-Path -LiteralPath 'build/flutter_litert/tmp/downloadLitertJni/litert-2.1.5.aar'
Test-Path -LiteralPath 'build/app/outputs/flutter-apk/app-debug.apk'

$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path -LiteralPath '.superpowers/sdd/pm8-run-gate.ps1').Path,
  [ref]$tokens,
  [ref]$errors
) | Out-Null
$errors
```

ผลในรายงานนี้เป็น prerequisite snapshot เท่านั้น ไม่ใช่ผล test/build/scan, G4P/UAT,
physical-device acceptance, Supabase policy verification หรือ permission ให้ publish/deploy
