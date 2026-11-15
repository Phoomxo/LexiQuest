# S5 impact map

ตรวจแบบ read-only เมื่อ 2026-11-14 ใน `C:/Users/Phet/.codex/worktrees/figcraft-flutter-v1/LexiQuest` บน branch `codex/figcraft-flutter-prototype`, HEAD `984e616438f264f4c54565ea0c7e0787272d7386` พร้อมงาน S1–S4 ที่ยังไม่ commit. เอกสารนี้เป็นหลักฐานสำหรับจัดลำดับ S5 ไม่ใช่ผลตรวจรับ S5.

ผู้วิจารณ์ไม่ได้แก้ production, ใช้โทรศัพท์, รัน Flutter, Gradle, backend tests หรือเครื่องมือตรวจความปลอดภัยในงานนี้. Source ของ account, identity, export, account deletion, consent, research, sync และหน้าจอ S5 ที่อ้างด้านล่างไม่มี diff จาก HEAD ขณะตรวจ. `progress_use_cases.dart` มีงาน S3 ที่ยังไม่ commit จึงอ้างเป็น source ปัจจุบันเท่านั้น.

## ความหมายของสถานะ

| สถานะ | หลักฐานที่ใช้ |
| --- | --- |
| `static_reachable` | มี caller ใน normal composition และมีทางเข้าในแอปตาม source. ยังไม่ยืนยันว่ากดสำเร็จบนรุ่นใหม่ |
| `test_assertion_exists` | อ่าน assertion ใน test แล้ว. การมีไฟล์ไม่ใช่ผลว่ารันผ่าน |
| `runtime_passed_baseline` | สังเกตผลบน APK ของ source `984e6164` ตามหลักฐานที่ระบุเท่านั้น |
| `not_checked` | ยังไม่มีการรันหรือสังเกตในขอบเขตนี้ |
| `external` | ต้องมีบริการหรือ authority ภายนอกที่ยังไม่ได้ตรวจหรืออนุญาต |

ไฟล์ `build/milestone-full-test.txt` ลงท้าย `+1786: All tests passed!` เป็นหลักฐานชุดรวมของ milestone เดิม. Log นี้ไม่ยืนยัน working tree ปัจจุบันและไม่ยืนยัน backend, policy emulator หรือการใช้งาน S5 บน Android.

## ขอบเขตในทะเบียนเดิม

S5 ระบุ f28, f35, f36, f39 และ f40 ใน `features.csv`. Package ที่เกี่ยวข้องคือ P1.1, P1.4, P1.6, P1.7, P3.5, P3.6, P4.6 และ P7.1–P7.5. ตารางด้านล่างเจาะ owner, export, delete, offline และ research ตามคำขอ. งานตั้งวิธีเรียน f35/f36, appearance f39, deep link และ before/after f28 ยังต้องมี disposition ของตัวเองก่อนปิด S5. ไม่แก้ทะเบียน 48/44/64 ต้นฉบับ.

## ทางเข้าจริงและ authority

| งาน | UI และทางกลับ | Authority และ source | สถานะปัจจุบัน |
| --- | --- | --- | --- |
| ผู้เยี่ยมชมและบัญชี | Login ให้เริ่มแบบ guest หรือ sign in. `_completeSignIn` กลับ home หรือไปยืนยันอีเมล (`lib/screens/login_screen.dart:100`). Logout จาก Settings สร้าง guest แล้ว reset ไป login (`lib/screens/setting_screen.dart:337`). Named routes และ email action อยู่ที่ `lib/navigation/app_route_factory.dart:12` | `AccountUseCases.reconcileLocalOwner`, `_bind`, `signOutToLocalGuest` (`lib/features/account/application/account_use_cases.dart:25`, `:145`, `:173`). `DriftLocalOwnerRepository:25` และ `DriftOwnerUpgradeRepository:30` จัด owner เดิม | `static_reachable`. การ sign in, อีเมลจริง และ provider เป็น `external`; ไม่ได้เปลี่ยนบัญชีบน vivo |
| โปรไฟล์ | แท็บที่สี่เปิด `ProfileSettingsScreen` (`lib/screens/main_navigation_screen.dart:98`). แสดงข้อมูลบัญชีและแก้ display name (`lib/screens/profile_settings_screen.dart:72`). Source ปัจจุบันยังไม่มีเส้นทางตั้งเป้าหมาย/วิธีเรียนตาม f35/f36 | progress ผ่าน loader เดิม, ชื่อผ่าน `AccountUseCases.updateDisplayName` (`lib/features/account/application/account_use_cases.dart:95`) | `static_reachable`; f35/f36 ยังไม่ครบจากการมีหน้า profile |
| ส่งออกส่วนตัว | Drawer → ส่งออก (`lib/screens/main_navigation_screen.dart:301`), หรือ Settings → ส่งออกข้อมูลการเรียน (`lib/screens/setting_screen.dart:875`). Push ผ่าน `AppNavigator` และ Back กลับ caller (`lib/screens/setting_screen.dart:486`). `ExportCenterScreen:36` สร้างไฟล์จริงโดยเลือก format/scope. ไม่มีขั้น preview สำเนาตาม FigCraft | `AppBootstrap:326` ประกอบ `ExportUseCases`. `_prepare:49` pin owner, `_requireCurrentScope:144` ตรวจ owner/consent/permit ซ้ำ และ store เรียก revalidation หลัง native picker (`lib/features/export/data/file_selector_export_store.dart:92`). Reader filter owner เช่น vocabulary ที่ `lib/features/export/data/drift_export_reader.dart:113` | `static_reachable`. Android DocumentsUI save, cancel, low storage และกลับ caller ยัง `not_checked` ในงานนี้ |
| ลบบัญชี | Settings แสดง row เฉพาะ registered account และ `_accountDeletion != null` (`lib/screens/setting_screen.dart:834`, `:850`). `AccountDeletionScreen:39` ต้องพิมพ์คำยืนยันและกัน Back ระหว่างทำงาน. หลังสำเร็จแสดงข้อความ แต่ไม่มีปุ่มเริ่ม guest หรือ reset route (`:115`) | `AccountDeletionUseCases:36` ทำ full export → reauthenticate → cloud → journal → local. Retry ใช้ receipt เดิม (`:132`, `:180`). Local gateway ลบเฉพาะ owner ใน transaction (`lib/features/account_deletion/data/drift_local_account_deletion_gateway.dart:32`) | Normal bootstrap **ยังเข้าไม่ได้**. `AppDependencies.accountDeletion` optional (`lib/runtime/app_dependencies.dart:65`) และ `AppBootstrap:457–510` ไม่ส่งค่า. ไม่เปิด live deletion |
| Research choice และถอนตัว | Login/guest เสนอ dialog ก่อนเข้าบทเรียน (`lib/screens/login_screen.dart:134`). ปฏิเสธแล้วเดินต่อ. Register รับ decision แยกจากบัญชี (`lib/screens/register_screen.dart:77`). Settings แสดงสถานะและให้ยืนยันถอนเฉพาะ accepted (`lib/screens/setting_screen.dart:695`, `:358`). Dialog คืนผลให้ caller (`lib/widgets/research_consent_dialog.dart:5`) | `ResearchConsentUseCases:20` ตรวจ owner หลัง load, decision รับ expected owner (`:40`). Repository ตรวจ active owner ใน transaction และไม่สร้าง row เมื่อผู้ไม่เคยเข้าร่วมกดถอน (`lib/features/consent/data/drift_research_consent_repository.dart:41`). Research export ต้อง consent พร้อม authorizer (`lib/features/export/application/export_use_cases.dart:66`, `:177`) | `static_reachable`. Local consent decision ไม่ใช่หลักฐานรับผู้เข้าร่วมจริง. `AppBootstrap:160`, `:164` ใช้ deny-all โดยปริยาย. Real enrollment/upload คง `external` และไม่ได้อนุญาต |
| ออฟไลน์และคิว | Settings แสดง aggregate จาก current-owner stream (`lib/screens/setting_screen.dart:103`, `:449`), สั่ง sync ผ่าน `_runSync:415` และกลับด้วย Back. ผลแต่ละรอบแยก disabled/unauthenticated/partial จริง (`:433`) | `AppBootstrap:244` ประกอบ SyncEngine เมื่อ gateway พร้อม. `lib/features/sync/application/sync_engine.dart:78` ตรวจ kill switch และ owner แล้ว claim งานเดิม. local learning ไม่ต้องรอ sync | `static_reachable`. Offline quiz/result/restart บน vivo ของ `984e6164` เป็น `runtime_passed_baseline` ตาม `vivo-984e6164/README.md`. ไม่ได้ทดสอบ cloud sync, lost ack หรือ owner switch บนโทรศัพท์ |

## สัญญาลบข้อมูลที่มีอยู่และ wiring ที่ยังขาด

- `ownerUpgradeInventory` ที่ `lib/features/identity/domain/owner_upgrade.dart:39` เป็นรายการ owner-scoped เดิม. `requiredFullAccountExportScopes` เพิ่ม child tables และ `local_owners` (`lib/features/account_deletion/domain/account_deletion_contracts.dart:3`). `DriftAccountSnapshotBuilder:29` สร้าง snapshot ทุก scope ใน transaction. Snapshot นี้ระบุชัดว่าไม่รวม cloud-only records และ credentials.
- `DriftLocalAccountDeletionGateway:143` ลบ inventory ย้อนลำดับ. Child import/quest rows ใช้ cascade. จากนั้นสร้าง guest ที่ derive จาก cloud receipt และ purge secret (`:164`). Partial failure เก็บ receipt ให้ลอง local ต่อได้.
- `FullAccountExporter` เป็น interface (`lib/features/account_deletion/domain/account_deletion_contracts.dart:127`). การค้น `FullAccountExporter` และ `AccountDeletionUseCases(` ใน `lib` ไม่พบ implementation หรือ composition ของ exporter/use case. Personal CSV/PDF/Anki จาก ExportCenter ไม่ครอบคลุม full account scopes จึงใช้แทน receipt นี้ไม่ได้.
- HTTP gateway มีอยู่ (`lib/features/account_deletion/data/http_privileged_account_deletion_gateway.dart:33`). Backend มี default-off `/v1/account-deletions` (`backend/ai_api/src/lexiquest_ai/app.py:156`, `config.py:110`). `AccountDeletionService:188` ใช้ server-verified identity, recent auth, tombstone และ receipt เดิม. Store และ deleter เป็น ports; `account_deletion.py:1` ระบุว่าไม่มี production datastore adapter.
- S5 ยังขาดการประกอบ full exporter, reauthentication, privileged gateway, journal และ local gateway ที่ทบทวนแล้ว. การตรวจยกเลิกและ retry ทำได้ด้วย synthetic ports. การเปิด endpoint หรือเชื่อมข้อมูลจริงต้องแยกจากงานต้นแบบนี้.

## กรณี dependency ค้างที่ต้อง reproduce ก่อนแก้

กรณีเหล่านี้เป็น source candidates ที่ยังไม่ได้รัน. Normal logout reset route จึงปิด State เก่าบนเส้นทางนั้น. `MyApp.didUpdateWidget` ยังรองรับการแทน dependencies โดยเก็บ navigator เดิมและ dispose ของเก่า (`lib/main.dart:50`, `:85`). จึงต้องแยก scope replacement ออกจากการเปลี่ยน active owner ภายใน repository เดิม.

| Candidate | ตัวกระตุ้นสังเคราะห์ขั้นต่ำ | ผลที่ต้อง assert |
| --- | --- | --- |
| ExportCenter เก็บ `_exports` จาก A ด้วย `??=` (`lib/screens/export_center_screen.dart:29`) | Pump State เดิมใต้ deps A แล้วแทนด้วย deps B ที่มี export B หรือไม่มี export. กดสร้าง CSV หลังเปลี่ยน | ไม่เรียก reader/store ของ A. กรณีไม่มี dependency ต้อง unavailable. Pending export A ต้องยกเลิกก่อน external write. การตรวจ current owner ภายใน use case A ไม่ตรวจ identity ของ scope ใหม่ |
| Settings เก็บ `_account`, `_accountDeletion`, `_syncTrigger` (`lib/screens/setting_screen.dart:81–91`) | Pump deps A แล้วแทน B โดยคง Settings State. ให้ B ไม่มี account/deletion/sync แล้วกด action เดิม | ไม่แสดงข้อมูลบัญชี A และไม่ dispatch password/logout/delete/sync ไป A. Consent และ sync-status source มี replacement logic อยู่แล้ว แต่ไม่ได้พิสูจน์สาม cached dependencies นี้ |
| Profile เก็บ `_account` (`lib/screens/profile_settings_screen.dart:39`) และ name dialog เก็บ account เดิม (`:190`) | เปิด Profile A, แทน scope เป็น B, เปิดหรือยืนยัน dialog ชื่อเดิม | ไม่แสดงหรือแก้ชื่อ A. Loader replacement ของ progress ไม่ได้แทน `_account` |
| Owner เปลี่ยนขณะ progress summary ค้าง | Delay `ProgressUseCases.load` หลังอ่าน owner A แล้วเปลี่ยน active owner เป็น B ภายใน dependencies เดิม ก่อนคืน query A (`lib/features/progress/application/progress_use_cases.dart:18`) | หน้า Home/Profile/Progress ไม่แสดง A ให้ B. ตรวจแยกจาก loader A→B เพราะ method identity เดิมไม่เปลี่ยน. `loadSession:27` มี owner recheck; summary `load:18` ยังไม่มี |

ยังไม่จัด candidates เหล่านี้เป็น runtime failure หรือกล่าวว่าเกิดบนเส้นทาง logout ปกติ. Home loader-replacement fix และ tests รอบปัจจุบันไม่ปิดการตรวจ owner เปลี่ยนภายใน provider เดิมแทน S5.

## Test assertions ที่อ่านแล้ว

ทุกแถวเป็น `test_assertion_exists`; ยังไม่ได้รันใหม่โดยผู้วิจารณ์.

| Boundary | Exact tests และสิ่งที่ assert |
| --- | --- |
| Owner isolation และ migration inventory | `test/features/account/account_owner_isolation_test.dart:46` แยก registered A จาก B, `:108` binding failure เก็บ A. `test/features/identity/drift_owner_upgrade_repository_test.dart:80` เทียบ inventory กับ SQLite tables ที่มี owner_id, `:93` rehome ทุก table และ replay, `:197` rollback, `:227` logout ไม่ลบข้อมูลเดิม |
| Export | `test/features/export/export_use_cases_test.dart:119` consent อย่างเดียวส่ง research ไม่ได้, `:365` owner สลับระหว่าง prepare, `:466` ถอนตัวระหว่าง data read, `:825` authority recheck, `:862` permit revoke, `:910` owner สลับขณะ picker เปิดแล้วไม่ save, `:1102` personal PDF ยังใช้ได้หลังถอนวิจัย. `test/features/export/file_selector_export_store_test.dart:36`, `:150`, `:228` ตรวจ revalidation/cancel ก่อนส่ง bytes. Tests นี้ไม่ใช่ native DocumentsUI end-to-end |
| Full snapshot และ deletion | `test/features/account_deletion/drift_account_snapshot_test.dart:37` scope/hash/owner A ไม่มี B. `drift_local_account_deletion_gateway_test.dart:30` ลบ A เก็บ B, `:117` reopen หลัง ack loss, `:146` purge secret ต่อหลัง DB commit. `account_deletion_use_cases_test.dart:53` default-off, `:127` สลับ owner หลัง export, `:196` durable journal resume. `test/screens/account_deletion_screen_test.dart:15`, `:72`, `:105` exact confirmation/local retry/200% |
| Backend deletion contract | `backend/ai_api/tests/test_account_deletion.py:117` disabled, `:128` server identity และ tombstone first, `:149` key เดิมไม่ลบซ้ำ, `:169` key ต่าง conflict, `:189` stale auth, `:206` invalid scope, `:229` verified auth_time. ใช้ synthetic adapters ไม่ใช่ production deletion |
| Research/nonparticipant | `test/screens/login_guest_mode_test.dart:351` decline แล้วยังเข้าเรียนและไม่มี research rows. `:394` dialog A retarget ไป B ไม่ได้. `test/features/consent/research_consent_use_cases_test.dart:68` never-participant withdrawal ไม่มี consent/events/outbox. `test/screens/setting_screen_test.dart:183`, `:268`, `:274`, `:278` read-only nonparticipant และ delayed/cross-owner consent. `test/runtime/app_bootstrap_test.dart:329`, `:350` production deny-all แม้ consent accepted |
| Signed permit | `test/features/research/research_operation_authorizer_test.dart:10`, `:153`, `:185`, `:225`, `:244` exact operation/pins, revisions/revocation, signature และ fail-closed dependency errors. นี่ไม่ใช่การยืนยัน issuer หรือเครื่องมือวิจัยจริง |
| Offline/sync | `test/features/sync/sync_engine_test.dart:75`, `:88`, `:101`, `:274`, `:300` kill switch, guest, offline retry once, conflict และ isolate lease. `test/screens/setting_screen_test.dart:383`, `:464`, `:533` ซ่อนผลรอบเก่าระหว่างรอ, aggregates และทิ้ง delayed source A |

`EventEnvelopeV2` shape tests (`test/features/events/event_envelope_v2_test.dart:49`, `:105`) และ participant import/route boundary (`test/architecture/participant_screen_boundary_test.dart:6`) ไม่พิสูจน์ research collection/upload isolation ทั้งระบบ. Ordinary `DriftLearningRepository` เขียน learning attempts/SRS/reading/achievement outbox (`lib/features/learning/data/drift_learning_repository.dart:155`, `:331`, `:368`). Source ที่อ่านไม่เรียก research authorizer หรือเขียน research rows จากเส้นทางนั้น. ยังต้อง assert journey ของ nonparticipant ว่า research artifacts เป็นศูนย์ โดยแยกจาก ordinary learning outbox ที่ถูกต้อง.

`ThesisChartScreen` ยังไม่มี normal production caller ตาม route audit เดิมและมีค่า 52/88.5 พร้อม labels คงที่ (`lib/screens/thesis_chart_screen.dart:11`, `:74`). ไม่ผูกเป็น before/after ของผู้เรียน. f28 ยังต้องมี synthetic paired owner/instrument/revision/session evidence และคำอธิบายข้อมูลตัวอย่างก่อนทำ route ใหม่.

## คำสั่งตรวจรับสังเคราะห์ที่ยังไม่ได้รัน

คำสั่งต่อไปนี้เป็นข้อกำหนดของรอบ S5 หลัง source หยุดเปลี่ยน. Flutter ทำทีละชุดใน worktree นี้. ไม่มีคำสั่งเปิด live research หรือ live deletion. ใช้ dependencies ที่ติดตั้งตาม lockfile เดิม.

```powershell
	flutter test --no-pub --reporter expanded test/features/account/account_owner_isolation_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart test/screens/login_guest_mode_test.dart test/screens/registration_flow_test.dart test/screens/email_action_screen_test.dart
	flutter test --no-pub --reporter expanded test/features/export/export_use_cases_test.dart test/features/export/file_selector_export_store_test.dart test/screens/export_center_screen_test.dart
	flutter test --no-pub --reporter expanded test/features/account_deletion test/screens/account_deletion_screen_test.dart
	flutter test --no-pub --reporter expanded test/features/consent/research_consent_use_cases_test.dart test/features/research/research_operation_authorizer_test.dart test/screens/setting_screen_test.dart test/runtime/app_bootstrap_test.dart
	flutter test --no-pub --reporter expanded test/features/sync test/screens/profile_settings_screen_test.dart test/features/events/event_envelope_v2_test.dart test/architecture/participant_screen_boundary_test.dart
```

แต่ละ command ต้องจบก่อนเริ่ม command ถัดไป. Tests สำหรับ candidates ข้างต้นยังไม่มีและต้องเพิ่ม reproduction ก่อนแก้. การผ่าน tests เดิมอย่างเดียวไม่ปิด candidates.

Backend ใช้ Python 3.11 environment เดิมที่มี dev dependencies ของ `backend/ai_api/pyproject.toml`. Policy commands ใช้ demo emulator project จาก `package.json:8–9`.

```powershell
	python -m pytest -c backend/ai_api/pyproject.toml backend/ai_api/tests/test_account_deletion.py
	npm run test:rules
	npm run test:auth
```

ผลที่ต้องเก็บก่อนปิด S5 คือ synthetic A/B ก่อนและหลัง export/delete, retry receipt เดิมหลัง reopen, nonparticipant research counts เป็นศูนย์, offline learning ยังคงอ่านผลได้ และ entry/Back กลับ caller. Native export ต้องเปิดไฟล์ที่บันทึกจริงเพื่อตรวจ UTF-8/Thai และ scope. Native delete ตรวจ cancel และ unavailable ได้โดยเก็บข้อมูลเดิม. การลบสำเร็จใช้ synthetic local/backend fixtures; ไม่ใช้ข้อมูล vivo ที่มีอยู่.

สถานะปัจจุบันคงเป็น **S5 ยังไม่ตรวจรับ**. Historical full Flutter pass, contracts ที่มีอยู่ และ native offline milestone ไม่แทนหลักฐาน S5 ของ source รุ่นถัดไป.
