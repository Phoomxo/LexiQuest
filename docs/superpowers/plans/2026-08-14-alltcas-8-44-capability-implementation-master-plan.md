# AllTCAS Idea Integration 8/44 Capability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** พัฒนา LexiQuest ให้ครบ 8 โดเมน 44 ความสามารถ โดยต่อยอดจากระบบเดิมผ่าน authority กลาง ไม่สร้างระบบคู่ขนาน และรักษาความถูกต้องของข้อมูลงานวิจัยทางการศึกษา

**Architecture:** ใช้ shared compatibility foundation เป็น Gate 0 ก่อนเปิดงานผู้เรียน แล้วส่งแต่ละความสามารถผ่าน typed product contract, runtime gate, Evidence Gateway, canonical domain authority และ owner lifecycle เดิม ฟีเจอร์ใหม่เริ่มที่ `implementedOff`; การเปิดใช้จริงและการจัดกลุ่มงานวิจัยเป็นคนละการตัดสินใจ

**Tech Stack:** Flutter/Dart, Drift/SQLite, Firebase Firestore Rules, local-first outbox sync, deterministic SHA-256 content manifests, Flutter unit/widget/integration tests และ Node rules tests

## Global Constraints

- ฐานอ้างอิงสำหรับแผนนี้คือ commit `50e61d1` บน branch `feature/alltcas-8-44-integration`
- ต้องทำ [Shared Compatibility Foundation](2026-08-14-alltcas-8-44-shared-compatibility-foundation.md) Tasks 0–13 ให้ผ่านก่อนเปิด surface ใหม่
- Layer 0 เป็น safety backbone ไม่ใช่โดเมนที่ 9 และไม่ใช่ฟีเจอร์ที่ 45
- ขอบเขตหลักต้องเป็น `f01`–`f44` เท่านั้น: C1=4, C2=9, C3=8, C4=7, C5=6, C6=5, C7=3, C8=2
- Coverage baseline ต้องคง exact set: Existing=8, Partial=23, New=13 จนกว่าจะ bump contract revision พร้อมหลักฐาน
- `EXP-P1` Local Same-Device Party Game และ `EXP-P2` Private Effort Comparison อยู่นอก 44 ข้อเสมอ และห้ามเปิดด้วย rollout state ของ catalog หลัก
- ห้ามเพิ่มระบบคำนวณคะแนนเข้ามหาวิทยาลัย/TCAS, generic calculator, online room/friend/chat, subscription/payment, OCR handwriting หรือ public leaderboard
- ห้ามสร้าง Vocabulary, Evidence, SRS/Mastery, Assessment, Quest, Streak, XP, Coins, Reward, History, Recommendation, Today Hub หรือ Download State authority ซ้ำ
- Product contract, runtime activation และ experiment assignment เป็นคนละ state; การ implement ไม่ได้แปลว่าเปิดใช้หรือย้าย cohort
- Schema v13–v15 เป็นของ foundation: v13 Evidence metadata, v14 Experiment Assignment, v15 Assessment Run
- จอง migration หลัง foundation ตามลำดับ: v16 Pack/Content Manifest + Download State, v17 Saved/Report, v18 Active-Time Segment, v19 Goal/Reminder, v20 Learner/Display Preference หากมี migration อื่น land ก่อน ต้อง rebase และ renumber ใน `docs/database/schema_ledger.md`; ห้าม reuse หมายเลข
- Migration test ต้องแยก targeted transition count (`33→37→39→40→42→43`) ออกจาก full-upgrade assertion ซึ่งใช้ `AppDatabase.currentSchemaVersion` และ named current table inventory เพื่อไม่ให้ test รุ่นเก่าค้างที่ count เดิม
- ตารางใหม่ทุกตารางต้องเข้า `ownerLifecycleManifest` หรือมี explicit non-owner/device-local classification และผ่าน migration, upgrade, sync, export, withdrawal, delete, retention และ cleanup ตามประเภทข้อมูล
- ทุก capability ใช้ TDD: RED ต้องล้มด้วยเหตุผลที่ตั้งใจ, GREEN เปลี่ยนเฉพาะ authority ที่กำหนด, VERIFY รัน focused tests, REVIEW ตรวจ diff, COMMIT เฉพาะไฟล์ใน work package
- Schema work package ทุกตัวต้องรัน `dart run build_runner build --delete-conflicting-outputs`, อัปเดต named current-schema inventory และรัน targeted migration พร้อม full-upgrade fixtures ก่อน commit
- Screen ใหม่ทุกหน้าต้องระบุ parent production entry/call site, dependency composition และ exact navigation test ใน work package เดียวกัน; หาก parent เป็น node ภายหลัง ต้องระบุ dependency edge/consumer ให้ชัดและคงสถานะ G1 `implementedOff` จน integration test ของ parent ผ่าน—ห้ามนับ unit/widget ที่ยังไม่มี production path ว่า G2
- ทุก surface ต้องผ่าน Accessibility gate, offline/restart gate, feature-off/emergency-off และ forward-only rollback ก่อน promotion
- การ run tests ในแผนนี้ใช้ `--no-pub` และแยก suite เพื่อให้ระบุ failure ได้; broad completion รันเมื่อจบทั้งโดเมนเท่านั้น

ทุก PowerShell 5.1 session ที่ execute plan ต้องประกาศ guard นี้ก่อน แล้วเรียก native command ทีละ suite; ห้ามใช้ operator chaining ที่ shell รุ่นนี้ไม่รองรับ:

```powershell
function Invoke-NativeStep {
  param([scriptblock]$Step)
  & $Step
  if ($LASTEXITCODE -ne 0) {
    throw "Native command failed with exit code $LASTEXITCODE"
  }
}
```

Typed dependency graph ด้านล่างเป็นแหล่งจริงหนึ่งเดียวของลำดับ implementation และต้องผ่าน resolution/acyclic test ก่อนเริ่มงาน: ready set แรกหลัง Foundation คือ `f40`, ต่อด้วย `f41`, จากนั้น `f04`/`f05`; schema spine คือ `f20 → f21 → f24 → f26 → f35`; `f43` เริ่มได้หลัง `f05`/`f40`; node อื่นเริ่มได้เมื่อ dependencies ครบ และ `f42` เป็น learner-facing composite ตัวสุดท้าย

| Gate | เงื่อนไขออกจาก Gate |
|---|---|
| G0 Foundation | Tasks 0–13 ผ่าน, schema v15, rollout Legacy, AnswerAttempt v1, research sync Off, Assessment unavailable |
| G1 Domain implementation | Focused tests, lifecycle delta และ exact authority test ผ่าน; state ยัง `implementedOff` |
| G2 Internal | runtime mapping/entry/dependency ครบ, accessibility/offline/restart ผ่าน, ไม่มี forbidden side effect |
| G3 Pilot | content/rules revision ตรง, consent/assignment จริง, data-quality monitor ผ่าน และ rollback ซ้อมแล้ว |
| G4 Broader release | ผล pilot ผ่านเกณฑ์ที่อนุมัติ, ไม่มี schema/rules drift และ owner lifecycle ครบ |

**Typed dependency graph ที่แผนนี้กำหนด**

ตารางนี้เป็น implementation-order contract ที่ต้องย้ายเข้า typed catalog และผ่าน dependency-resolution/acyclic tests; Layer 0 เป็น implicit prerequisite ของทุกแถว หัวข้อโดเมนจัดเพื่อความเข้าใจขอบเขต ไม่ใช่คำสั่งให้ทำ f01→f44 ตรง ๆ—ผู้ดำเนินงานต้องเลือกเฉพาะแถวที่ dependencies ผ่านแล้ว

| ID | Feature dependencies | Canonical authority dependencies |
|---|---|---|
| f01 | f04 | Vocabulary, Content Manifest |
| f02 | f01, f04 | Progress, Production Delivery |
| f03 | f02, f04 | Vocabulary, Media/Voice |
| f04 | f40, f41 | Product Contract, Vocabulary, Content QA |
| f05 | f40, f41 | LearningSessions, Evidence Gateway, Runtime Delivery |
| f06 | f05, f17, f19 | SRS, AnswerAttempts |
| f07 | f05, f17 | Vocabulary, AnswerAttempts |
| f08 | f03, f05, f17, f19 | Content Manifest, AnswerAttempts |
| f09 | f04, f05, f17, f19 | Content Manifest, AnswerAttempts |
| f10 | f05, f17 | Vocabulary, Evidence Policy |
| f11 | f05, f17, f19 | Vocabulary, Evidence Gateway |
| f12 | f05, f19 | Ephemeral Session State |
| f13 | f05, f17, f19 | Reading, SpeechEvidence, Evidence Gateway |
| f14 | f06 | SRS, Progress, Recommendation Policy |
| f15 | f06, f07, f08, f09, f10, f11, f13 | Mastery/SRS, Recommendation Policy |
| f16 | f05 | Protocol Limits, Pack Revision |
| f17 | f05 | AnswerRecordResult |
| f18 | f04, f17 | Reviewed Content Manifest |
| f19 | f05 | EvidenceContext, Hint Policy |
| f20 | f03, f17 | Learner Intent Repository |
| f21 | f04, f20 | Content Report Repository, Consent Policy |
| f22 | f06, f20, f21 | SRS, AnswerAttempts, Review Reader |
| f23 | f24 | Learning Time Repository, Monotonic Clock |
| f24 | f05, f17, f19, f20, f21 | LearningSessions, Time Authority |
| f25 | f24 | Progress, AnswerAttempts, Timezone Policy |
| f26 | f24 | Goal Repository, Timezone Policy |
| f27 | f22, f26 | Reminder Repository, OS Scheduler |
| f28 | f04, f24 | Assessment, Consent, Experiment Assignment |
| f29 | f05 | Quest, Evidence Projection Receipts |
| f30 | f05 | StreakStates, LearningDayLog, Timezone Policy |
| f31 | f05 | AchievementUnlocks, Evidence Policy |
| f32 | f31 | Lifetime XP, Coins, Reward Ownership |
| f33 | f05, f17 | Event Context, Script Catalog |
| f34 | f31, f32 | Achievement Evidence, File Export |
| f35 | f16, f26 | Learner Preferences, Owner Identity |
| f36 | f24, f25, f29, f30, f31 | Progress, SRS, Engagement Readers |
| f37 | f14, f15, f35, f36 | Recommendation Policy/Reader |
| f38 | f12, f15 | Accessibility Policy, M3 Theme |
| f39 | f35, f38 | Learner Preferences, M3 Theme |
| f40 | — | Drift Repositories, Outbox, Sync Engine |
| f41 | f40 | FeatureRegistry, ProductionFeatureContract |
| f42 | f22, f26, f27, f28, f29, f30, f37, f39, f43 | Today Hub Reader, Assignment Reader |
| f43 | f05, f40 | LearningSessions, AnswerAttempts, EventsV2 |
| f44 | f04, f40, f41 | Download State, Content Manifest, Artifact Store |

## Domain 1 — Learning Content & Packs / C1 (4 capabilities)

**Completion contract:** ทุก pack ต้องอ้างอิง canonical Vocabulary IDs และ pin revision, provenance, QA state, publication state และ checksum ได้ ห้ามสร้าง word/CEFR catalog ซ้ำ

**Domain-local topological order:** `f04 → f01 → f02 → f03`; cross-domain prerequisites ใช้ typed graph เท่านั้น

**Domain interfaces:**

```dart
abstract interface class LearningPackRepository {
  Future<List<LearningPackSummary>> list(LearningPackFilter filter);
  Future<LearningPackDetail> getVersion(String packId, int revision);
}

abstract interface class ContentManifestRepository {
  Future<VerifiedContentManifest> requireVerified(ContentIdentity identity);
}
```

The `LearningPackRepository` above is the final post-f02 interface. To keep each capability commit compiling, f01 initially creates that same interface and its `DriftLearningPackRepository` implementation with only `list(LearningPackFilter)`. After f02 creates `LearningPackDetail`, f02 extends the same interface and Drift implementation with `getVersion`; it must not create a second repository authority.

### f01 — Curriculum & Learning Pack Catalog

- **Source/Coverage:** `A / Partial`
- **ทำอะไร/หน้าที่:** ค้นหาและกรอง pack ตาม CEFR, topic, skill และ goal โดย pack item เก็บเฉพาะ canonical `VocabularyWord.id`
- **Authority/Dependencies:** `VocabularyRepository`, `ContentManifestRepository`, `f04`; ไม่มี pack-owned word row
- **Files:** Create `lib/features/learning_packs/domain/learning_pack.dart`, `lib/features/learning_packs/domain/learning_pack_repository.dart`, `lib/features/learning_packs/application/learning_pack_use_cases.dart`, `lib/features/learning_packs/data/drift_learning_pack_repository.dart`, `lib/screens/study_planning_hub_screen.dart`, `lib/screens/learning_pack_catalog_screen.dart`, `test/features/learning_packs/learning_pack_catalog_test.dart`, `test/screens/study_planning_hub_screen_test.dart`, `test/screens/learning_pack_catalog_screen_test.dart`; Modify `lib/runtime/app_dependencies.dart`, `lib/runtime/app_bootstrap.dart`, `lib/screens/main_navigation_screen.dart`, `test/runtime/app_bootstrap_test.dart`, `test/screens/main_navigation_screen_test.dart`, `test/scenarios/production_feature_navigation_test.dart`
- [ ] **RED:** ทดสอบ filter หลายค่า, deterministic order, unknown word ID fail closed, repository ไม่ insert `VocabularyWords` และ canonical `home/study-planning` entry มีเพียงหนึ่ง route ซึ่งหาย/fail closed เมื่อ `studyPlanning` ปิด
- [ ] **GREEN:** implement `list(LearningPackFilter)` จาก verified v16 pack tables และ Progress read model, wire repository ผ่าน production dependencies และให้ `StudyPlanningHubScreen` เป็น parent route เดียวที่เปิด catalog; capability ภายหลังเพิ่ม child action ใน Hub โดยไม่เพิ่ม production entry
- [ ] **VERIFY:** `flutter test --no-pub test/features/learning_packs/learning_pack_catalog_test.dart test/screens/study_planning_hub_screen_test.dart test/screens/learning_pack_catalog_screen_test.dart test/features/vocabulary/drift_vocabulary_repository_test.dart test/runtime/app_bootstrap_test.dart test/screens/main_navigation_screen_test.dart test/scenarios/production_feature_navigation_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/learning_packs/domain/learning_pack.dart lib/features/learning_packs/domain/learning_pack_repository.dart lib/features/learning_packs/application/learning_pack_use_cases.dart lib/features/learning_packs/data/drift_learning_pack_repository.dart lib/screens/study_planning_hub_screen.dart lib/screens/learning_pack_catalog_screen.dart test/features/learning_packs/learning_pack_catalog_test.dart test/screens/study_planning_hub_screen_test.dart test/screens/learning_pack_catalog_screen_test.dart lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart lib/screens/main_navigation_screen.dart test/runtime/app_bootstrap_test.dart test/screens/main_navigation_screen_test.dart test/scenarios/production_feature_navigation_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(content): add versioned learning pack catalog" }`
- **Exit/Rollback:** catalog อยู่ `implementedOff`; ปิด entry ได้โดยไม่ลบ pack manifest หรือ Vocabulary

### f02 — Learning Pack Detail

- **Source/Coverage:** `A / Partial`
- **ทำอะไร/หน้าที่:** แสดงระดับ เนื้อหา ตัวอย่าง progress และ activity ที่พร้อมใช้ก่อนเริ่ม session
- **Authority/Dependencies:** `f01`, `f04`, Progress queries และ `ProductionFeatureContract`; progress เป็น derived read model
- **Files:** Create `lib/features/learning_packs/domain/learning_pack_detail.dart`, `lib/features/learning_packs/application/learning_pack_detail_use_cases.dart`, `lib/screens/learning_pack_detail_screen.dart`, `test/features/learning_packs/learning_pack_detail_test.dart`, `test/screens/learning_pack_detail_screen_test.dart`; Modify `lib/features/learning_packs/domain/learning_pack_repository.dart`, `lib/features/learning_packs/data/drift_learning_pack_repository.dart`, `lib/screens/learning_pack_catalog_screen.dart`, `test/screens/learning_pack_catalog_screen_test.dart`
- [ ] **RED:** ทดสอบ pack revision mismatch, unavailable activity และ progress ที่คำนวณจาก canonical sessions
- [ ] **GREEN:** implement `getVersion(packId, revision)` และ typed activity availability โดยไม่สร้าง progress column ใน pack; catalog เปิด detail ด้วย pinned `(packId, revision)` เท่านั้น
- [ ] **VERIFY:** `flutter test --no-pub test/features/learning_packs/learning_pack_detail_test.dart test/screens/learning_pack_detail_screen_test.dart test/screens/learning_pack_catalog_screen_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/learning_packs/domain/learning_pack_detail.dart lib/features/learning_packs/application/learning_pack_detail_use_cases.dart lib/screens/learning_pack_detail_screen.dart test/features/learning_packs/learning_pack_detail_test.dart test/screens/learning_pack_detail_screen_test.dart lib/features/learning_packs/domain/learning_pack_repository.dart lib/features/learning_packs/data/drift_learning_pack_repository.dart lib/screens/learning_pack_catalog_screen.dart test/screens/learning_pack_catalog_screen_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(content): add learning pack detail" }`
- **Exit/Rollback:** pack ที่ manifest ไม่ผ่านต้องแสดง unavailable แบบ typed; rollback ปิด route โดยไม่แก้ evidence

### f03 — Rich Lexical Card

- **Source/Coverage:** `A / Partial`
- **ทำอะไร/หน้าที่:** แสดง meaning, part of speech, CEFR, IPA, audio, examples, synonyms และ antonyms แบบ progressive disclosure
- **Authority/Dependencies:** `VocabularyWord` เดิม + verified metadata จาก `f02`/`f04`; Media/Voice เป็น optional typed dependency
- **Files:** Modify `lib/features/vocabulary/domain/vocabulary_word.dart`, `lib/features/vocabulary/data/drift_vocabulary_repository.dart`, `lib/screens/learning_pack_detail_screen.dart`, `test/features/vocabulary/drift_vocabulary_repository_test.dart`, `test/screens/learning_pack_detail_screen_test.dart`; Create `lib/widgets/rich_lexical_card.dart`, `test/widgets/rich_lexical_card_test.dart`
- [ ] **RED:** ทดสอบ missing optional metadata, 200% text scale, screen-reader order, audio unavailable และ checksum mismatch
- [ ] **GREEN:** เพิ่ม versioned lexical metadata ใน Vocabulary authority เดิมและ render แบบไม่บังคับ media
- [ ] **VERIFY:** `flutter test --no-pub test/features/vocabulary/drift_vocabulary_repository_test.dart test/widgets/rich_lexical_card_test.dart test/screens/accessibility_smoke_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/vocabulary/domain/vocabulary_word.dart lib/features/vocabulary/data/drift_vocabulary_repository.dart lib/screens/learning_pack_detail_screen.dart test/features/vocabulary/drift_vocabulary_repository_test.dart test/screens/learning_pack_detail_screen_test.dart lib/widgets/rich_lexical_card.dart test/widgets/rich_lexical_card_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(vocabulary): add rich lexical card" }`
- **Exit/Rollback:** fallback เป็น canonical spelling/meaning เดิม; ห้าม duplicate lexical table

### f04 — Content Version & Quality Control

- **Source/Coverage:** `L / Partial`
- **ทำอะไร/หน้าที่:** เป็น content identity/QA authority สำหรับ pack, lexical metadata, assessment form และ offline artifact
- **Authority/Dependencies:** Layer 0 Content QA, contract revision/hash และ Vocabulary authority
- **Files:** Create `lib/data/local/tables/content_tables.dart`, `lib/data/local/tables/content_download_tables.dart`, `lib/features/learning_packs/domain/content_manifest.dart`, `lib/features/learning_packs/domain/content_quality_policy.dart`, `lib/features/learning_packs/data/drift_content_manifest_repository.dart`, `test/database/migration_v15_to_v16_test.dart`, `test/features/learning_packs/content_quality_policy_test.dart`, `test/support/current_database_contract.dart`; Modify `lib/data/local/tables/vocabulary_tables.dart`, `lib/data/local/app_database.dart`, `lib/data/local/app_database.g.dart`, `lib/features/vocabulary/data/drift_vocabulary_repository.dart`, `lib/features/identity/domain/owner_lifecycle_manifest.dart`, `lib/features/identity/data/drift_owner_upgrade_repository.dart`, `lib/features/sync/domain/sync_entity.dart`, `lib/features/sync/data/drift_sync_store.dart`, `lib/features/sync/data/firestore_sync_gateway.dart`, `lib/features/export/application/owner_lifecycle_archive.dart`, `lib/features/export/data/drift_export_reader.dart`, `lib/runtime/app_dependencies.dart`, `lib/runtime/app_bootstrap.dart`, `firestore.rules`, `test/data/local/app_database_migration_test.dart`, `test/data/local/app_database_test.dart`, `test/database/migration_v12_to_v13_test.dart`, `test/database/migration_v13_to_v14_test.dart`, `test/database/migration_v14_to_v15_test.dart`, `test/features/vocabulary/drift_vocabulary_repository_test.dart`, `test/features/identity/drift_owner_upgrade_repository_test.dart`, `test/features/sync/sync_contract_test.dart`, `test/features/sync/firestore_sync_gateway_test.dart`, `test/features/export/export_use_cases_test.dart`, `test/runtime/app_bootstrap_test.dart`, `test/security/firestore-rules.test.cjs`, `test/scenarios/complete_owner_export_delete_test.dart`, `docs/database/schema_ledger.md`
- [ ] **RED:** สร้าง v15 fixture แล้ว assert targeted v15→v16 เพิ่ม `learning_packs`, `learning_pack_items`, `content_manifests`, `content_download_states` (33→37) และ lexical version columns โดยรักษา 33 ตาราง/ข้อมูลเดิม; full-upgrade fixtures ใช้ `current_database_contract`; vocabulary payload เก่าอ่านได้แต่ payload ใหม่ถูก rules ปฏิเสธจน deploy ลำดับที่กำหนด
- [ ] **GREEN:** เพิ่ม SHA-256, provenance, review/publication state, immutable revision และ foreign-key/reference validation; classify pack/manifest เป็น packaged non-owner content, download state เป็น device-local, และ versioned learner vocabulary เป็น owner-synced payload แบบ dual-read/version-gated; user-authored vocabulary ใช้ explicit provenance ไม่ปลอมเป็น reviewed pack content
- [ ] **GENERATE:** `dart run build_runner build --delete-conflicting-outputs`
- [ ] **VERIFY:** `Invoke-NativeStep { flutter test --no-pub test/database/migration_v15_to_v16_test.dart test/data/local/app_database_migration_test.dart test/data/local/app_database_test.dart }`; `Invoke-NativeStep { flutter test --no-pub test/features/learning_packs/content_quality_policy_test.dart test/features/vocabulary/drift_vocabulary_repository_test.dart }`; `Invoke-NativeStep { flutter test --no-pub test/features/sync/sync_contract_test.dart test/features/sync/firestore_sync_gateway_test.dart test/runtime/app_bootstrap_test.dart test/scenarios/complete_owner_export_delete_test.dart }`; `Invoke-NativeStep { npm run test:rules }`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/data/local/tables/content_tables.dart lib/data/local/tables/content_download_tables.dart lib/features/learning_packs/domain/content_manifest.dart lib/features/learning_packs/domain/content_quality_policy.dart lib/features/learning_packs/data/drift_content_manifest_repository.dart test/database/migration_v15_to_v16_test.dart test/features/learning_packs/content_quality_policy_test.dart test/support/current_database_contract.dart lib/data/local/tables/vocabulary_tables.dart lib/data/local/app_database.dart lib/data/local/app_database.g.dart lib/features/vocabulary/data/drift_vocabulary_repository.dart lib/features/identity/domain/owner_lifecycle_manifest.dart lib/features/identity/data/drift_owner_upgrade_repository.dart lib/features/sync/domain/sync_entity.dart lib/features/sync/data/drift_sync_store.dart lib/features/sync/data/firestore_sync_gateway.dart lib/features/export/application/owner_lifecycle_archive.dart lib/features/export/data/drift_export_reader.dart lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart firestore.rules test/data/local/app_database_migration_test.dart test/data/local/app_database_test.dart test/database/migration_v12_to_v13_test.dart test/database/migration_v13_to_v14_test.dart test/database/migration_v14_to_v15_test.dart test/features/vocabulary/drift_vocabulary_repository_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart test/features/sync/sync_contract_test.dart test/features/sync/firestore_sync_gateway_test.dart test/features/export/export_use_cases_test.dart test/runtime/app_bootstrap_test.dart test/security/firestore-rules.test.cjs test/scenarios/complete_owner_export_delete_test.dart docs/database/schema_ledger.md }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(content): add versioned content quality authority" }`
- **Exit/Rollback:** corrupt/unreviewed content ถูก quarantine; rollback ปิด invocation และเก็บ v16 readable ห้าม downgrade

## Domain 2 — Unified Learning Experience & Activity Modes / C2 (9 capabilities)

**Completion contract:** ทุก mode ใช้ Unified Lesson Shell, typed adapter, state machine และ idempotent session/evidence identity ห้าม screen เขียน Drift หรือ projection โดยตรง

**Domain-local topological order:** `f05`; หลัง cross-domain `f17`/`f19` พร้อมจึง `f06 → f07 → f08 → f09 → f10 → f11 → f12 → f13`

**Domain interfaces:**

```dart
abstract interface class LessonModeAdapter {
  LessonMode get mode;
  EvidenceContext classify(LessonResponse response, LessonSupport support);
  Future<LessonItem> next(LessonCursor cursor);
}

final class UnifiedLessonController {
  Future<void> start(LessonStartCommand command);
  Future<void> pause(DateTime occurredAtUtc);
  Future<void> resume(DateTime occurredAtUtc);
  Future<AnswerRecordResult> submit(LessonSubmission submission);
  Future<void> complete(DateTime occurredAtUtc);
  Future<void> abandon(DateTime occurredAtUtc);
}
```

### f05 — Unified Lesson Shell

- **Source/Coverage:** `L / New`
- **ทำอะไร/หน้าที่:** เป็น presentation/application shell กลางสำหรับ planned/active/paused/completed/abandoned, progress, timer, audio, retry และ completion
- **Authority/Dependencies:** Foundation Evidence Gateway, `LearningSessions`, `FeatureRegistry`, `ProductionFeatureContract`; ไม่เป็น score authority
- **Files:** Create `lib/features/learning/domain/lesson_mode.dart`, `lib/features/learning/domain/lesson_session_state.dart`, `lib/features/learning/application/lesson_mode_registry.dart`, `lib/features/learning/application/legacy_lesson_mode_adapters.dart`, `lib/features/learning/application/unified_lesson_controller.dart`, `lib/features/learning/presentation/unified_lesson_shell.dart`, `test/features/learning/lesson_mode_registry_test.dart`, `test/features/learning/unified_lesson_controller_test.dart`, `test/architecture/lesson_mode_adapter_coverage_test.dart`, `test/screens/choose_mode_screen_test.dart`; Modify `lib/runtime/app_dependencies.dart`, `lib/runtime/app_bootstrap.dart`, `lib/screens/choose_mode_screen.dart`, `test/runtime/app_bootstrap_test.dart`
- [ ] **RED:** ทดสอบ state transition ทั้งหมด, duplicate submit/complete, retry identity, unavailable dependency, background pause, exact production-mode registry และ Choose Mode ห้ามเปิด route ที่ไม่มี adapter/gate
- [ ] **GREEN:** implement controller ที่เรียก `LearningUseCases.recordEvidence` เท่านั้น, wire registry/shell ผ่าน production dependencies และให้ Choose Mode resolve typed adapter; เริ่มด้วย bounded legacy adapters แล้ว f06–f13 replace ID เดิมทีละตัวโดยไม่มี route คู่
- [ ] **VERIFY:** `flutter test --no-pub test/features/learning/lesson_mode_registry_test.dart test/features/learning/unified_lesson_controller_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart test/screens/choose_mode_screen_test.dart test/runtime/app_bootstrap_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/learning/domain/lesson_mode.dart lib/features/learning/domain/lesson_session_state.dart lib/features/learning/application/lesson_mode_registry.dart lib/features/learning/application/legacy_lesson_mode_adapters.dart lib/features/learning/application/unified_lesson_controller.dart lib/features/learning/presentation/unified_lesson_shell.dart test/features/learning/lesson_mode_registry_test.dart test/features/learning/unified_lesson_controller_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart test/screens/choose_mode_screen_test.dart lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart lib/screens/choose_mode_screen.dart test/runtime/app_bootstrap_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(learning): add unified lesson shell" }`
- **Exit/Rollback:** parent runtime feature ปิดแล้ว Choose Mode ต้องหยุด invocation; rollback เลือก legacy adapter ของ ID เดิมโดยไม่ abandon evidence ที่ commit แล้วและห้ามสร้าง second route

### f06 — Flashcard Mode

- **Source/Coverage:** `A / Existing`
- **ทำอะไร/หน้าที่:** exposure และ self-rated recall ผ่าน SRS authority เดิม
- **Authority/Dependencies:** `f05`, `SrsPolicy`, `DriftLearningRepository`, `EvidenceClass.exposure/independentRecall`
- **Files:** Modify `lib/screens/srs_flashcards_screen.dart`, `lib/features/learning/application/lesson_mode_registry.dart`, `lib/screens/choose_mode_screen.dart`, `test/screens/srs_flashcards_screen_test.dart`, `test/features/learning/srs_policy_test.dart`, `test/features/learning/lesson_mode_registry_test.dart`, `test/architecture/lesson_mode_adapter_coverage_test.dart`, `test/screens/choose_mode_screen_test.dart`; Create `lib/features/learning/application/flashcard_mode_adapter.dart`
- [ ] **RED:** ทดสอบ exposure ไม่ update SRS, remembered/not-remembered ใช้ identity เดิม และ assisted flip ไม่กลายเป็น independent recall
- [ ] **GREEN:** ย้าย screen state/completion เข้าสู่ shell adapter และคง SRS writer เดิม
- [ ] **VERIFY:** `flutter test --no-pub test/screens/srs_flashcards_screen_test.dart test/features/learning/srs_policy_test.dart test/features/learning/lesson_mode_registry_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart test/screens/choose_mode_screen_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/screens/srs_flashcards_screen.dart lib/features/learning/application/lesson_mode_registry.dart lib/screens/choose_mode_screen.dart test/screens/srs_flashcards_screen_test.dart test/features/learning/srs_policy_test.dart test/features/learning/lesson_mode_registry_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart test/screens/choose_mode_screen_test.dart lib/features/learning/application/flashcard_mode_adapter.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "refactor(learning): route flashcards through lesson shell" }`
- **Exit/Rollback:** fallback ไป behavior เดิมผ่าน compatibility context ได้เฉพาะ Legacy rollout

### f07 — Meaning Quiz

- **Source/Coverage:** `A / Existing`
- **ทำอะไร/หน้าที่:** วัด bidirectional meaning recognition โดยไม่สร้าง quiz/answer authority ใหม่
- **Authority/Dependencies:** `f05`, `f17`, `AnswerAttempts`, Evidence Gateway, `Feature.quiz`
- **Files:** Modify `lib/screens/quiz_screen.dart`, `lib/features/learning/application/lesson_mode_registry.dart`, `lib/screens/choose_mode_screen.dart`, `test/screens/quiz_screen_test.dart`, `test/features/learning/learning_use_cases_test.dart`, `test/features/learning/lesson_mode_registry_test.dart`, `test/architecture/lesson_mode_adapter_coverage_test.dart`, `test/screens/choose_mode_screen_test.dart`; Create `lib/features/learning/application/meaning_quiz_mode_adapter.dart`
- [ ] **RED:** ทดสอบ word→meaning/meaning→word, deterministic distractors, retry identity และ recognition isolation จาก binary SRS v1
- [ ] **GREEN:** ส่ง `EvidenceClass.recognition` ผ่าน shell; feedback อ่านผลเดิมไม่สร้าง event ซ้ำ
- [ ] **VERIFY:** `flutter test --no-pub test/screens/quiz_screen_test.dart test/features/learning/learning_use_cases_test.dart test/features/learning/lesson_mode_registry_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart test/screens/choose_mode_screen_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/screens/quiz_screen.dart lib/features/learning/application/lesson_mode_registry.dart lib/screens/choose_mode_screen.dart test/screens/quiz_screen_test.dart test/features/learning/learning_use_cases_test.dart test/features/learning/lesson_mode_registry_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart test/screens/choose_mode_screen_test.dart lib/features/learning/application/meaning_quiz_mode_adapter.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "refactor(quiz): route meaning quiz through evidence gateway" }`
- **Exit/Rollback:** recognition policy fail closed; runtime `quiz` ปิดแล้ว route unavailable

### f08 — Definition Quiz

- **Source/Coverage:** `A / Partial`
- **ทำอะไร/หน้าที่:** ฝึกเลือกคำจาก English definition พร้อมแยก evidence calibration
- **Authority/Dependencies:** `f03`, `f05`, `f17`, `f19`, Content Manifest
- **Files:** Create `lib/features/learning/application/definition_quiz_mode_adapter.dart`, `lib/screens/definition_quiz_screen.dart`, `test/features/learning/definition_quiz_mode_adapter_test.dart`, `test/screens/definition_quiz_screen_test.dart`; Modify `lib/features/learning/application/lesson_mode_registry.dart`, `lib/screens/choose_mode_screen.dart`, `test/features/learning/lesson_mode_registry_test.dart`, `test/architecture/lesson_mode_adapter_coverage_test.dart`, `test/screens/choose_mode_screen_test.dart`
- [ ] **RED:** ทดสอบ definition revision pin, distractor reproducibility, missing reviewed definition และ hinted answer classification
- [ ] **GREEN:** implement adapter จาก verified lexical metadata; default evidence เป็น recognition ไม่แตะ SRS v1
- [ ] **VERIFY:** `flutter test --no-pub test/features/learning/definition_quiz_mode_adapter_test.dart test/screens/definition_quiz_screen_test.dart test/features/learning/lesson_mode_registry_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart test/screens/choose_mode_screen_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/learning/application/definition_quiz_mode_adapter.dart lib/screens/definition_quiz_screen.dart test/features/learning/definition_quiz_mode_adapter_test.dart test/screens/definition_quiz_screen_test.dart lib/features/learning/application/lesson_mode_registry.dart lib/screens/choose_mode_screen.dart test/features/learning/lesson_mode_registry_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart test/screens/choose_mode_screen_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(quiz): add definition recognition mode" }`
- **Exit/Rollback:** ไม่มี reviewed definition ให้ skip item แบบ auditable; ปิด entry ไม่แก้ session เดิม

### f09 — Cloze Test

- **Source/Coverage:** `A / Partial`
- **ทำอะไร/หน้าที่:** ฝึก contextual retrieval โดย selected cloze และ typed cloze ใช้ evidence class ต่างกัน
- **Authority/Dependencies:** `f04`, `f05`, `f17`, `f19`, AnswerAttempts
- **Files:** Modify `lib/screens/fill_in_the_blanks_screen.dart`, `lib/features/learning/application/lesson_mode_registry.dart`, `lib/screens/choose_mode_screen.dart`, `test/features/learning/lesson_mode_registry_test.dart`, `test/architecture/lesson_mode_adapter_coverage_test.dart`, `test/screens/choose_mode_screen_test.dart`; Create `lib/features/learning/application/cloze_mode_adapter.dart`, `test/screens/fill_in_the_blanks_screen_test.dart`, `test/features/learning/cloze_mode_adapter_test.dart`
- [ ] **RED:** ทดสอบ selected=`recognition`, typed without hint=`independentRecall`, hinted typed=`guidedPractice`, content revision mismatch และ retry
- [ ] **GREEN:** ย้าย scoring/classification เข้า typed adapter และให้ screen แสดง feedback เท่านั้น
- [ ] **VERIFY:** `flutter test --no-pub test/features/learning/cloze_mode_adapter_test.dart test/screens/fill_in_the_blanks_screen_test.dart test/features/learning/lesson_mode_registry_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart test/screens/choose_mode_screen_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/screens/fill_in_the_blanks_screen.dart lib/features/learning/application/lesson_mode_registry.dart lib/screens/choose_mode_screen.dart test/features/learning/lesson_mode_registry_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart test/screens/choose_mode_screen_test.dart lib/features/learning/application/cloze_mode_adapter.dart test/screens/fill_in_the_blanks_screen_test.dart test/features/learning/cloze_mode_adapter_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "refactor(quiz): classify cloze evidence by input mode" }`
- **Exit/Rollback:** unknown input/hint state fail closed ไม่เขียน mastery

### f10 — Matching Mode

- **Source/Coverage:** `A / New`
- **ทำอะไร/หน้าที่:** ฝึก fluent recognition ด้วยจับคู่คำ/ความหมายและไม่อ้างเป็น independent recall
- **Authority/Dependencies:** `f05`, `f17`, Vocabulary, Evidence policy
- **Files:** Create `lib/features/learning/application/matching_mode_adapter.dart`, `lib/screens/matching_mode_screen.dart`, `test/features/learning/matching_mode_adapter_test.dart`, `test/screens/matching_mode_screen_test.dart`; Modify `lib/features/learning/application/lesson_mode_registry.dart`, `lib/screens/choose_mode_screen.dart`, `test/features/learning/lesson_mode_registry_test.dart`, `test/architecture/lesson_mode_adapter_coverage_test.dart`, `test/screens/choose_mode_screen_test.dart`
- [ ] **RED:** ทดสอบ deterministic pair set, duplicate tap, timeout, restart และ SRS/assessment/motivation ไม่เปลี่ยนใน default policy
- [ ] **GREEN:** implement `EvidenceClass.recognition` หรือ `guidedPractice` ตาม hint/support; ไม่มี custom score store
- [ ] **VERIFY:** `flutter test --no-pub test/features/learning/matching_mode_adapter_test.dart test/screens/matching_mode_screen_test.dart test/features/learning/lesson_mode_registry_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart test/screens/choose_mode_screen_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/learning/application/matching_mode_adapter.dart lib/screens/matching_mode_screen.dart test/features/learning/matching_mode_adapter_test.dart test/screens/matching_mode_screen_test.dart lib/features/learning/application/lesson_mode_registry.dart lib/screens/choose_mode_screen.dart test/features/learning/lesson_mode_registry_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart test/screens/choose_mode_screen_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(learning): add matching recognition mode" }`
- **Exit/Rollback:** เริ่ม `implementedOff`; remove route ได้โดย canonical attempts ยังอ่านได้

### f11 — Typed Recall / Writing

- **Source/Coverage:** `A / Partial`
- **ทำอะไร/หน้าที่:** productive spelling recall จาก meaning, audio หรือ context
- **Authority/Dependencies:** `f05`, `f17`, `f19`, Vocabulary normalization, Evidence Gateway
- **Files:** Create `lib/features/learning/application/typed_recall_mode_adapter.dart`; Modify `lib/features/learning/application/lesson_mode_registry.dart`, `lib/screens/quiz_screen.dart`, `lib/screens/associative_reading_session_screen.dart`, `lib/screens/choose_mode_screen.dart`, `test/screens/quiz_screen_test.dart`, `test/screens/associative_reading_session_screen_test.dart`, `test/features/learning/lesson_mode_registry_test.dart`, `test/architecture/lesson_mode_adapter_coverage_test.dart`, `test/screens/choose_mode_screen_test.dart`
- [ ] **RED:** ทดสอบ normalization ที่อนุมัติ, exact/accepted variant, hint downgrade, duplicate submit และ response code bounded
- [ ] **GREEN:** ให้ adapter derive correctness/evidence; screen ห้ามส่ง correctness ที่เชื่อถือเอง
- [ ] **VERIFY:** `flutter test --no-pub test/screens/quiz_screen_test.dart test/screens/associative_reading_session_screen_test.dart test/features/learning/lesson_mode_registry_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart test/screens/choose_mode_screen_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/learning/application/typed_recall_mode_adapter.dart lib/features/learning/application/lesson_mode_registry.dart lib/screens/quiz_screen.dart lib/screens/associative_reading_session_screen.dart lib/screens/choose_mode_screen.dart test/screens/quiz_screen_test.dart test/screens/associative_reading_session_screen_test.dart test/features/learning/lesson_mode_registry_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart test/screens/choose_mode_screen_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(learning): unify typed recall evidence" }`
- **Exit/Rollback:** unknown normalization revision fail closed; preserve raw-free controlled response evidence

### f12 — Handwriting Scratchpad

- **Source/Coverage:** `A / New`
- **ทำอะไร/หน้าที่:** พื้นที่เขียนด้วยมือแบบ local/ephemeral ให้ผู้เรียน self-check โดยไม่มี OCR
- **Authority/Dependencies:** `f05`, `f19`; ไม่มี persistence, sync, assessment หรือ mastery writer
- **Files:** Create `lib/features/learning/presentation/handwriting_scratchpad.dart`, `lib/features/learning/application/handwriting_self_check_adapter.dart`, `test/features/learning/handwriting_scratchpad_test.dart`; Modify `lib/features/learning/application/lesson_mode_registry.dart`, `lib/features/learning/presentation/unified_lesson_shell.dart`, `test/features/learning/lesson_mode_registry_test.dart`, `test/architecture/lesson_mode_adapter_coverage_test.dart`
- [ ] **RED:** ทดสอบ clear on session end/background privacy, no image persistence/network, self-check=`guidedPractice` และ accessibility alternative เป็น typed input
- [ ] **GREEN:** implement in-memory strokes พร้อม explicit self-check; ห้าม import OCR/camera service
- [ ] **VERIFY:** `flutter test --no-pub test/features/learning/handwriting_scratchpad_test.dart test/features/learning/lesson_mode_registry_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart test/screens/accessibility_smoke_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/learning/presentation/handwriting_scratchpad.dart lib/features/learning/application/handwriting_self_check_adapter.dart test/features/learning/handwriting_scratchpad_test.dart lib/features/learning/application/lesson_mode_registry.dart lib/features/learning/presentation/unified_lesson_shell.dart test/features/learning/lesson_mode_registry_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(learning): add ephemeral handwriting scratchpad" }`
- **Exit/Rollback:** widget ถอดออกได้โดยไม่มี data cleanup เพราะไม่ persist

### f13 — LexiQuest Native Modes Integration

- **Source/Coverage:** `L / Partial`
- **ทำอะไร/หน้าที่:** รวม Dictation, Speaking, Shadowing, Reading, Scramble และ Associative Reading เข้ากับ shell/evidence contract เดียว
- **Authority/Dependencies:** `f05`, `f17`, `f19`, SpeechEvidence, Reading authority และ existing runtime mappings
- **Files:** Modify `lib/features/learning/application/lesson_mode_registry.dart`, `lib/screens/choose_mode_screen.dart`, `lib/screens/dictation_quiz_screen.dart`, `lib/screens/speak_to_text_screen.dart`, `lib/screens/shadowing_challenge_screen.dart`, `lib/screens/cefr_article_reader_screen.dart`, `lib/screens/sentence_scramble_screen.dart`, `lib/screens/word_scramble_screen.dart`, `lib/screens/associative_reading_session_screen.dart`, `test/screens/choose_mode_screen_test.dart`, `test/screens/dictation_quiz_screen_test.dart`, `test/screens/speak_to_text_screen_voice_test.dart`, `test/screens/shadowing_challenge_screen_test.dart`, `test/screens/cefr_article_reader_screen_test.dart`, `test/screens/sentence_scramble_screen_test.dart`, `test/screens/word_scramble_screen_test.dart`, `test/screens/associative_reading_session_screen_test.dart`, `test/features/learning/lesson_mode_registry_test.dart`, `test/architecture/lesson_mode_adapter_coverage_test.dart`; Create `lib/features/learning/application/native_mode_adapters.dart`
- [ ] **RED:** exact-set test ต้องพบ adapter ของทุก production mode; pronunciation/recreational/exposure ห้ามเข้า SRS/Quest/XP default
- [ ] **GREEN:** ย้าย completion/evidence call ผ่าน shell โดยคง media/reading domain repositories เดิม
- [ ] **VERIFY:** `flutter test --no-pub test/screens/choose_mode_screen_test.dart test/screens/dictation_quiz_screen_test.dart test/screens/speak_to_text_screen_voice_test.dart test/screens/shadowing_challenge_screen_test.dart test/screens/sentence_scramble_screen_test.dart test/screens/word_scramble_screen_test.dart test/screens/associative_reading_session_screen_test.dart test/features/learning/lesson_mode_registry_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/learning/application/lesson_mode_registry.dart lib/screens/choose_mode_screen.dart lib/screens/dictation_quiz_screen.dart lib/screens/speak_to_text_screen.dart lib/screens/shadowing_challenge_screen.dart lib/screens/cefr_article_reader_screen.dart lib/screens/sentence_scramble_screen.dart lib/screens/word_scramble_screen.dart lib/screens/associative_reading_session_screen.dart test/screens/choose_mode_screen_test.dart test/screens/dictation_quiz_screen_test.dart test/screens/speak_to_text_screen_voice_test.dart test/screens/shadowing_challenge_screen_test.dart test/screens/sentence_scramble_screen_test.dart test/screens/word_scramble_screen_test.dart test/screens/associative_reading_session_screen_test.dart test/features/learning/lesson_mode_registry_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart lib/features/learning/application/native_mode_adapters.dart test/screens/cefr_article_reader_screen_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "refactor(learning): integrate native modes with lesson shell" }`
- **Exit/Rollback:** แต่ละ parent runtime flag ปิด mode ของตนได้; no compatibility wrapper call เหลือใน production screens

## Domain 3 — Recall, Feedback & Learner Control / C3 (8 capabilities)

**Completion contract:** ทุก answer/support action ต้องมี evidence class, skill, hint level และ policy ก่อน side effect ห้าม assisted หรือ recreational work ถูกนับเป็น independent retention

**Domain-local topological order:** `f17 → f19 → f20 → f21 → f14 → f15 → f16 → f18`; `f14`/`f15` รอ activity dependencies ตาม typed graph

**Domain interfaces:**

```dart
abstract interface class LearningRecommendationPolicy {
  RecommendationDecision recommend(RecommendationEvidence evidence);
}

abstract interface class LearnerIntentRepository {
  Future<void> save(SavedLearningItem item);
  Future<void> unsave(ContentIdentity identity);
}

abstract interface class ContentQualityReportRepository {
  Future<void> submit(ContentQualityReport report);
}
```

### f14 — Flashcard-First Recommendation

- **Source/Coverage:** `A / Partial`
- **ทำอะไร/หน้าที่:** แนะนำ flashcard preparation ก่อน recall ที่ยากขึ้น แต่ผู้เรียนเลือกข้ามหรือ override ได้
- **Authority/Dependencies:** `f06`, Progress/SRS read models และ shared Recommendation authority; ไม่เปลี่ยน assignment
- **Files:** Create `lib/features/recommendation/domain/recommendation_models.dart`, `lib/features/recommendation/domain/recommendation_policy.dart`, `test/features/recommendation/recommendation_policy_test.dart`; Modify `lib/features/progress/data/drift_progress_queries.dart`
- [ ] **RED:** ทดสอบ unseen/low-confidence item แนะนำ flashcard, mastered item ไม่ถูกบังคับ และ override ไม่เปลี่ยน research cohort
- [ ] **GREEN:** extract recommendation logic จาก Progress query เป็น pure versioned policy พร้อม reason code
- [ ] **VERIFY:** `flutter test --no-pub test/features/recommendation/recommendation_policy_test.dart test/features/progress/progress_projector_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/recommendation/domain/recommendation_models.dart lib/features/recommendation/domain/recommendation_policy.dart test/features/recommendation/recommendation_policy_test.dart lib/features/progress/data/drift_progress_queries.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "refactor(recommendation): add flashcard first policy" }`
- **Exit/Rollback:** recommendation เป็นคำแนะนำเท่านั้น; ปิด panel แล้วไม่มี data mutation

### f15 — Active-Recall Ladder

- **Source/Coverage:** `L / Partial`
- **ทำอะไร/หน้าที่:** จัดลำดับ exposure → recognition → matching → cloze → typed recall → dictation → speaking จาก evidence ที่มี
- **Authority/Dependencies:** `f06–f13`, Recommendation policy, Mastery/SRS read models และ protocol limits
- **Files:** Create `lib/features/recommendation/domain/active_recall_ladder.dart`, `lib/features/recommendation/application/recall_ladder_use_cases.dart`, `test/features/recommendation/active_recall_ladder_test.dart`
- [ ] **RED:** ทดสอบ deterministic next step, missing mode, accessibility alternative, protocol-locked step และไม่มี circular recommendation
- [ ] **GREEN:** implement versioned ladder ที่คืน `RecommendationDecision` พร้อม evidence/reason refs; ไม่เขียน progress
- [ ] **VERIFY:** `flutter test --no-pub test/features/recommendation/active_recall_ladder_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/recommendation/domain/active_recall_ladder.dart lib/features/recommendation/application/recall_ladder_use_cases.dart test/features/recommendation/active_recall_ladder_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(recommendation): add active recall ladder" }`
- **Exit/Rollback:** fallback เป็น learner choice list; ห้าม fallback เป็น hard-coded screen routing

### f16 — Session Configuration

- **Source/Coverage:** `A / Partial`
- **ทำอะไร/หน้าที่:** กำหนด item count, direction, difficulty, hint budget, time limit และ pack ภายใน protocol bounds
- **Authority/Dependencies:** `f05`, pack revision, LessonModeAdapter capabilities; f35 ให้ defaults ภายหลังแต่ไม่เป็น dependency บังคับ
- **Files:** Create `lib/features/learning/domain/session_configuration.dart`, `lib/features/learning/application/session_configuration_policy.dart`, `lib/features/learning/presentation/session_configuration_sheet.dart`, `test/features/learning/session_configuration_policy_test.dart`, `test/features/learning/session_configuration_sheet_test.dart`; Modify `lib/screens/choose_mode_screen.dart`, `lib/features/learning/application/unified_lesson_controller.dart`, `test/screens/choose_mode_screen_test.dart`, `test/features/learning/unified_lesson_controller_test.dart`
- [ ] **RED:** ทดสอบ min/max, unsupported option, protocol clamp, accessibility untimed alternative, serialization stability และ Choose Mode ต้องเปิด validated sheet ก่อนสร้าง `LessonStartCommand`
- [ ] **GREEN:** implement typed immutable `SessionConfiguration`, wire sheet ที่ Choose Mode แล้วส่ง validated value เข้า shell controller; screen ห้าม bypass policy
- [ ] **VERIFY:** `flutter test --no-pub test/features/learning/session_configuration_policy_test.dart test/features/learning/session_configuration_sheet_test.dart test/screens/choose_mode_screen_test.dart test/features/learning/unified_lesson_controller_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/learning/domain/session_configuration.dart lib/features/learning/application/session_configuration_policy.dart lib/features/learning/presentation/session_configuration_sheet.dart test/features/learning/session_configuration_policy_test.dart test/features/learning/session_configuration_sheet_test.dart lib/screens/choose_mode_screen.dart lib/features/learning/application/unified_lesson_controller.dart test/screens/choose_mode_screen_test.dart test/features/learning/unified_lesson_controller_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(learning): add bounded session configuration" }`
- **Exit/Rollback:** invalid/stale configuration แสดง typed reset prompt; ไม่แก้ assignment หรือ evidence เก่า

### f17 — Immediate Answer Feedback

- **Source/Coverage:** `A / Existing`
- **ทำอะไร/หน้าที่:** แสดง correct/incorrect, correct answer และ next action แบบเข้าถึงได้ โดยใช้ผลจาก submission เดิม
- **Authority/Dependencies:** Unified Shell submission result; ห้ามสร้าง score/event ใหม่
- **Files:** Create `lib/features/learning/presentation/answer_feedback_panel.dart`, `lib/features/learning/domain/answer_feedback.dart`, `test/features/learning/answer_feedback_panel_test.dart`; Modify `lib/features/learning/application/unified_lesson_controller.dart`, `lib/features/learning/presentation/unified_lesson_shell.dart`, `test/features/learning/unified_lesson_controller_test.dart`, `test/architecture/lesson_mode_adapter_coverage_test.dart`, `test/screens/accessibility_smoke_test.dart`
- [ ] **RED:** ทดสอบ semantic announcement, non-color cue, retry/next, no duplicate submit, reduced-motion rendering และ registered adapter ทุกตัวส่งผลจาก canonical `AnswerRecordResult` เข้า feedback panel เพียงครั้งเดียว
- [ ] **GREEN:** implement feedback view model จาก `AnswerRecordResult` แล้ว wire ผ่าน controller/shell production adapter boundary; UI ไม่มี repository dependency
- [ ] **VERIFY:** `flutter test --no-pub test/features/learning/answer_feedback_panel_test.dart test/features/learning/unified_lesson_controller_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart test/screens/accessibility_smoke_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/learning/presentation/answer_feedback_panel.dart lib/features/learning/domain/answer_feedback.dart test/features/learning/answer_feedback_panel_test.dart lib/features/learning/application/unified_lesson_controller.dart lib/features/learning/presentation/unified_lesson_shell.dart test/features/learning/unified_lesson_controller_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart test/screens/accessibility_smoke_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(learning): unify accessible answer feedback" }`
- **Exit/Rollback:** mode ใช้ minimal text feedback ได้ แต่ยังต้องไม่สร้าง scored event เพิ่ม

### f18 — Contrastive Distractor Explanation

- **Source/Coverage:** `A / New`
- **ทำอะไร/หน้าที่:** อธิบายว่าคำตอบถูกเพราะอะไรและ distractor ที่เลือกต่างอย่างไรในฐานะ guided feedback
- **Authority/Dependencies:** `f04`, `f17`; explanation มาจาก reviewed/versioned content ไม่ใช่ unpinned generation
- **Files:** Create `lib/features/learning/domain/contrastive_explanation.dart`, `lib/features/learning/application/contrastive_feedback_use_cases.dart`, `lib/features/learning/presentation/contrastive_feedback_panel.dart`, `test/features/learning/contrastive_feedback_test.dart`; Modify `lib/features/learning/presentation/answer_feedback_panel.dart`, `lib/features/learning/presentation/unified_lesson_shell.dart`, `test/features/learning/answer_feedback_panel_test.dart`
- [ ] **RED:** ทดสอบ revision pin, missing rationale, wrong distractor ID, no answer leakage before submit, evidence=`guidedPractice` และ feedback shell แสดง panel เฉพาะหลัง canonical attempt commit
- [ ] **GREEN:** resolve explanation จาก content manifest หลัง canonical attempt commit แล้ว compose ใต้ AnswerFeedbackPanel; missing/unreviewed rationale ไม่สร้าง fallback route
- [ ] **VERIFY:** `flutter test --no-pub test/features/learning/contrastive_feedback_test.dart test/features/learning/answer_feedback_panel_test.dart test/features/learning/learning_use_cases_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/learning/domain/contrastive_explanation.dart lib/features/learning/application/contrastive_feedback_use_cases.dart lib/features/learning/presentation/contrastive_feedback_panel.dart test/features/learning/contrastive_feedback_test.dart lib/features/learning/presentation/answer_feedback_panel.dart lib/features/learning/presentation/unified_lesson_shell.dart test/features/learning/answer_feedback_panel_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(learning): add contrastive answer explanation" }`
- **Exit/Rollback:** ไม่มี reviewed rationale ให้ซ่อน explanation; ห้ามเรียก AI เป็น fallback

### f19 — Hint, Strategy & Context

- **Source/Coverage:** `A / Partial`
- **ทำอะไร/หน้าที่:** ให้ staged support และบันทึก hint level ที่ใช้จริงก่อน classify evidence
- **Authority/Dependencies:** EvidenceContext, Unified Shell และ optional existing tutor entry; hint policy เป็น local deterministic authority
- **Files:** Create `lib/features/learning/domain/hint_policy.dart`, `lib/features/learning/application/hint_use_cases.dart`, `lib/features/learning/presentation/hint_panel.dart`, `test/features/learning/hint_policy_test.dart`; Modify `lib/features/learning/application/current_activity_evidence.dart`, `lib/features/learning/application/unified_lesson_controller.dart`, `lib/features/learning/presentation/unified_lesson_shell.dart`, `test/features/learning/unified_lesson_controller_test.dart`, `test/features/learning/evidence_context_test.dart`, `test/architecture/lesson_mode_adapter_coverage_test.dart`
- [ ] **RED:** ทดสอบ hint levels, context reveal, exhausted budget, retry equality, independentRecall downgrade เมื่อมี assistance และ adapter ที่ประกาศ hint support ต้องเรียก use case ผ่าน shell เท่านั้น
- [ ] **GREEN:** shell snapshot `hintLevel` ก่อน `recordEvidence`; wire `HintUseCases` เข้า controller/shell production boundary และห้าม activity screen เปลี่ยน evidence context เอง
- [ ] **VERIFY:** `flutter test --no-pub test/features/learning/hint_policy_test.dart test/features/learning/unified_lesson_controller_test.dart test/features/learning/evidence_context_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/learning/domain/hint_policy.dart lib/features/learning/application/hint_use_cases.dart lib/features/learning/presentation/hint_panel.dart test/features/learning/hint_policy_test.dart lib/features/learning/application/current_activity_evidence.dart lib/features/learning/application/unified_lesson_controller.dart lib/features/learning/presentation/unified_lesson_shell.dart test/features/learning/unified_lesson_controller_test.dart test/features/learning/evidence_context_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(learning): add evidence aware hints" }`
- **Exit/Rollback:** hint unavailable ต้องไม่ reset attempt; unknown hint state fail closedเป็น guided evidence

### f20 — Bookmark / Save

- **Source/Coverage:** `A / New`
- **ทำอะไร/หน้าที่:** เก็บ learner intent ว่าต้องการกลับมาดู item โดยไม่จัด item เป็น weakness หรือ incorrect
- **Authority/Dependencies:** canonical content identity from `f04`; Review Center consumes it
- **Files:** Create `lib/data/local/tables/review_tables.dart`, `lib/features/review/domain/learner_intent.dart`, `lib/features/review/domain/learner_intent_repository.dart`, `lib/features/review/data/drift_learner_intent_repository.dart`, `test/database/migration_v16_to_v17_test.dart`, `test/features/review/learner_intent_repository_test.dart`; Modify `lib/data/local/app_database.dart`, `lib/data/local/app_database.g.dart`, `lib/features/identity/domain/owner_lifecycle_manifest.dart`, `lib/features/identity/data/drift_owner_upgrade_repository.dart`, `lib/features/sync/domain/sync_entity.dart`, `lib/features/sync/data/drift_sync_store.dart`, `lib/features/sync/data/firestore_sync_gateway.dart`, `lib/features/export/application/owner_lifecycle_archive.dart`, `lib/features/export/data/drift_export_reader.dart`, `lib/runtime/app_dependencies.dart`, `lib/runtime/app_bootstrap.dart`, `lib/widgets/rich_lexical_card.dart`, `lib/features/learning/presentation/answer_feedback_panel.dart`, `firestore.rules`, `test/support/current_database_contract.dart`, `test/data/local/app_database_migration_test.dart`, `test/data/local/app_database_test.dart`, `test/database/migration_v15_to_v16_test.dart`, `test/features/sync/sync_contract_test.dart`, `test/features/sync/firestore_sync_gateway_test.dart`, `test/features/export/export_use_cases_test.dart`, `test/features/identity/drift_owner_upgrade_repository_test.dart`, `test/runtime/app_bootstrap_test.dart`, `test/widgets/rich_lexical_card_test.dart`, `test/features/learning/answer_feedback_panel_test.dart`, `test/security/firestore-rules.test.cjs`, `test/scenarios/complete_owner_export_delete_test.dart`, `docs/database/schema_ledger.md`
- [ ] **RED:** targeted v16→v17 fixture ต้องเพิ่ม `saved_learning_items`/`content_quality_reports` (37→39), full-upgrade inventory ต้องเป็น 39, save replay idempotent, unsave tombstone sync, rich-card/feedback bookmark action และ no weakness mutation
- [ ] **GREEN:** implement owner/content/revision unique key, wire `LearnerIntentRepository` ผ่าน production dependencies แล้ว inject bookmark action ที่ RichLexicalCard/AnswerFeedbackPanel; เปิดเฉพาะ saved-item sync v1 แบบ default Off จน rules deploy และ report table เข้า lifecycle โดยยังไม่มี writer จน f21
- [ ] **GENERATE:** `dart run build_runner build --delete-conflicting-outputs`
- [ ] **VERIFY:** `Invoke-NativeStep { flutter test --no-pub test/database/migration_v16_to_v17_test.dart test/data/local/app_database_migration_test.dart test/data/local/app_database_test.dart }`; `Invoke-NativeStep { flutter test --no-pub test/features/review/learner_intent_repository_test.dart test/widgets/rich_lexical_card_test.dart test/features/learning/answer_feedback_panel_test.dart }`; `Invoke-NativeStep { flutter test --no-pub test/features/sync/sync_contract_test.dart test/features/sync/firestore_sync_gateway_test.dart test/runtime/app_bootstrap_test.dart test/scenarios/complete_owner_export_delete_test.dart }`; `Invoke-NativeStep { npm run test:rules }`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/data/local/tables/review_tables.dart lib/features/review/domain/learner_intent.dart lib/features/review/domain/learner_intent_repository.dart lib/features/review/data/drift_learner_intent_repository.dart test/database/migration_v16_to_v17_test.dart test/features/review/learner_intent_repository_test.dart lib/data/local/app_database.dart lib/data/local/app_database.g.dart lib/features/identity/domain/owner_lifecycle_manifest.dart lib/features/identity/data/drift_owner_upgrade_repository.dart lib/features/sync/domain/sync_entity.dart lib/features/sync/data/drift_sync_store.dart lib/features/sync/data/firestore_sync_gateway.dart lib/features/export/application/owner_lifecycle_archive.dart lib/features/export/data/drift_export_reader.dart lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart lib/widgets/rich_lexical_card.dart lib/features/learning/presentation/answer_feedback_panel.dart firestore.rules test/support/current_database_contract.dart test/data/local/app_database_migration_test.dart test/data/local/app_database_test.dart test/database/migration_v15_to_v16_test.dart test/features/sync/sync_contract_test.dart test/features/sync/firestore_sync_gateway_test.dart test/features/export/export_use_cases_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart test/runtime/app_bootstrap_test.dart test/widgets/rich_lexical_card_test.dart test/features/learning/answer_feedback_panel_test.dart test/security/firestore-rules.test.cjs test/scenarios/complete_owner_export_delete_test.dart docs/database/schema_ledger.md }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(review): add durable saved learning items" }`
- **Exit/Rollback:** rollback ปิด save action; v17 rows คง export/delete ได้และไม่ downgrade

### f21 — Flag / Report Content

- **Source/Coverage:** `A / New`
- **ทำอะไร/หน้าที่:** รายงานปัญหา text/audio/answer/explanation โดยผูก content revision และ bounded reason code
- **Authority/Dependencies:** v17 `content_quality_reports`, `f04`, consent/privacy policy; ไม่แก้ content โดยตรง
- **Files:** Create `lib/features/review/domain/content_quality_report.dart`, `lib/features/review/domain/content_quality_report_repository.dart`, `lib/features/review/data/drift_content_quality_report_repository.dart`, `lib/features/review/application/content_report_use_cases.dart`, `lib/features/review/presentation/content_report_sheet.dart`, `test/features/review/content_quality_report_repository_test.dart`, `test/features/review/content_report_use_cases_test.dart`, `test/features/review/content_report_sheet_test.dart`; Modify `lib/features/sync/domain/sync_entity.dart`, `lib/features/sync/data/drift_sync_store.dart`, `lib/features/sync/data/firestore_sync_gateway.dart`, `lib/runtime/app_dependencies.dart`, `lib/runtime/app_bootstrap.dart`, `lib/widgets/rich_lexical_card.dart`, `lib/features/learning/presentation/answer_feedback_panel.dart`, `firestore.rules`, `test/features/sync/sync_contract_test.dart`, `test/features/sync/firestore_sync_gateway_test.dart`, `test/runtime/app_bootstrap_test.dart`, `test/widgets/rich_lexical_card_test.dart`, `test/features/learning/answer_feedback_panel_test.dart`, `test/security/firestore-rules.test.cjs`, `test/scenarios/complete_owner_export_delete_test.dart`
- [ ] **RED:** ทดสอบ exact reason enum, optional comment length, revision required, duplicate retry/restart, withdrawal/upload block, owner delete, report action จาก rich-card/feedback และ no content mutation
- [ ] **GREEN:** wire report repository แยกจาก learner intent, inject typed report action/sheet ที่ RichLexicalCard/AnswerFeedbackPanel, persist local report transaction ก่อน enqueue sync เฉพาะ policy อนุญาต และ redact provider/device secrets
- [ ] **VERIFY:** `Invoke-NativeStep { flutter test --no-pub test/features/review/content_quality_report_repository_test.dart test/features/review/content_report_use_cases_test.dart test/features/review/content_report_sheet_test.dart test/widgets/rich_lexical_card_test.dart test/features/learning/answer_feedback_panel_test.dart }`; `Invoke-NativeStep { flutter test --no-pub test/features/sync/sync_contract_test.dart test/features/sync/firestore_sync_gateway_test.dart test/runtime/app_bootstrap_test.dart test/scenarios/complete_owner_export_delete_test.dart }`; `Invoke-NativeStep { npm run test:rules }`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/review/domain/content_quality_report.dart lib/features/review/domain/content_quality_report_repository.dart lib/features/review/data/drift_content_quality_report_repository.dart lib/features/review/application/content_report_use_cases.dart lib/features/review/presentation/content_report_sheet.dart test/features/review/content_quality_report_repository_test.dart test/features/review/content_report_use_cases_test.dart test/features/review/content_report_sheet_test.dart lib/features/sync/domain/sync_entity.dart lib/features/sync/data/drift_sync_store.dart lib/features/sync/data/firestore_sync_gateway.dart lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart lib/widgets/rich_lexical_card.dart lib/features/learning/presentation/answer_feedback_panel.dart firestore.rules test/features/sync/sync_contract_test.dart test/features/sync/firestore_sync_gateway_test.dart test/runtime/app_bootstrap_test.dart test/widgets/rich_lexical_card_test.dart test/features/learning/answer_feedback_panel_test.dart test/security/firestore-rules.test.cjs test/scenarios/complete_owner_export_delete_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(review): add versioned content reporting" }`
- **Exit/Rollback:** ปิด upload ได้โดย local report ยัง export/delete ตาม lifecycle; ห้าม retry loop

## Domain 4 — Review, Time & Research Assessment / C4 (7 capabilities)

**Completion contract:** ต้องมี stable assignment, consent snapshot, versioned instrument/form, assessment isolation และ trustworthy active time ห้าม pre-test สอนเนื้อหา เปิดเฉลย หรือให้ reward

**Domain-local topological order:** `f24 → f23 → f25 → f28 → f26 → f22 → f27`; ทุก node รอ cross-domain prerequisites ตาม typed graph

**Domain interfaces:**

```dart
abstract interface class LearningTimeRepository {
  Future<void> append(LearningTimeSegment segment);
  Future<Duration> activeDuration(String sessionId);
}

abstract interface class ReviewCenterReader {
  Future<List<ReviewQueueItem>> compose(ReviewQueueFilter filter);
}

abstract interface class StudyReminderRepository {
  Future<void> save(StudyReminder reminder);
  Future<void> cancel(String reminderId);
}
```

### f22 — Review Center

- **Source/Coverage:** `A→L / Partial`
- **ทำอะไร/หน้าที่:** รวม due-SRS, saved, incorrect และ reported items พร้อมคงเหตุผลของแต่ละ queue item
- **Authority/Dependencies:** SRS, AnswerAttempts, `f20`, `f21`; เป็น composer/read model ไม่มี review table ใหม่ และ parent production consumer คือ `f42`
- **Files:** Create `lib/features/review/domain/review_queue_item.dart`, `lib/features/review/data/drift_review_center_reader.dart`, `lib/features/review/application/review_center_use_cases.dart`, `lib/screens/review_center_screen.dart`, `test/features/review/review_center_reader_test.dart`, `test/screens/review_center_screen_test.dart`
- [ ] **RED:** ทดสอบ multi-reason merge, deterministic priority, deleted content, due clock และ query ไม่เขียน projection/table
- [ ] **GREEN:** compose typed reasons จาก authorities เดิม; launching review สร้าง session ใหม่ผ่าน shell
- [ ] **VERIFY:** `flutter test --no-pub test/features/review/review_center_reader_test.dart test/screens/review_center_screen_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/review/domain/review_queue_item.dart lib/features/review/data/drift_review_center_reader.dart lib/features/review/application/review_center_use_cases.dart lib/screens/review_center_screen.dart test/features/review/review_center_reader_test.dart test/screens/review_center_screen_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(review): add canonical review center" }`
- **Exit/Rollback:** คง G1 `implementedOff` จน f42 navigation test เปิด action ได้; ปิด screen แล้วไม่มี data migration/cleanup และห้ามสร้าง ReviewCenter table

### f23 — Focus Timer

- **Source/Coverage:** `A / New`
- **ทำอะไร/หน้าที่:** จัดการ explicit focus interval แบบ start/pause/resume/finish โดยแยก wall-clock กับ active duration
- **Authority/Dependencies:** f24 LearningTimeRepository และ monotonic clock; Timezone policy ใช้เฉพาะการแสดงผล
- **Files:** Create `lib/features/time_tracking/domain/focus_timer.dart`, `lib/features/time_tracking/application/focus_timer_controller.dart`, `lib/features/time_tracking/presentation/focus_timer_widget.dart`, `test/features/time_tracking/focus_timer_controller_test.dart`; Modify `lib/features/learning/application/unified_lesson_controller.dart`, `lib/features/learning/presentation/unified_lesson_shell.dart`, `test/features/learning/unified_lesson_controller_test.dart`
- [ ] **RED:** ทดสอบ transition, process background, clock rollback, duplicate finish, monotonic duration และ shell แสดง/ซ่อน timer ตาม adapter capability โดยไม่สร้าง time writer อีกตัว
- [ ] **GREEN:** controller append segment transitions ผ่าน time repository แล้ว inject widget ใน Unified Shell; timer UI ไม่เขียน LearningSessions เอง
- [ ] **VERIFY:** `flutter test --no-pub test/features/time_tracking/focus_timer_controller_test.dart test/features/learning/unified_lesson_controller_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/time_tracking/domain/focus_timer.dart lib/features/time_tracking/application/focus_timer_controller.dart lib/features/time_tracking/presentation/focus_timer_widget.dart test/features/time_tracking/focus_timer_controller_test.dart lib/features/learning/application/unified_lesson_controller.dart lib/features/learning/presentation/unified_lesson_shell.dart test/features/learning/unified_lesson_controller_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(time): add resilient focus timer" }`
- **Exit/Rollback:** pause/disable timer แล้ว segment ที่ปิดสมบูรณ์ยัง immutable; open segment ถูก recovery แบบ bounded

### f24 — Automatic Learning-Time Capture

- **Source/Coverage:** `A→L / Partial`
- **ทำอะไร/หน้าที่:** วัด active effort ของ session โดยตัด idle/background และเก็บ UTC occurrence, timezone context, monotonic duration แยกกัน
- **Authority/Dependencies:** Unified Shell lifecycle, Layer 0 Time Authority และ owner identity
- **Files:** Create `lib/data/local/tables/time_tracking_tables.dart`, `lib/features/time_tracking/domain/learning_time_segment.dart`, `lib/features/time_tracking/domain/learning_time_repository.dart`, `lib/features/time_tracking/data/drift_learning_time_repository.dart`, `lib/features/time_tracking/application/active_learning_time_controller.dart`, `test/database/migration_v17_to_v18_test.dart`, `test/features/time_tracking/learning_time_repository_test.dart`, `test/features/time_tracking/active_learning_time_controller_test.dart`; Modify `lib/data/local/app_database.dart`, `lib/data/local/app_database.g.dart`, `lib/features/learning/application/unified_lesson_controller.dart`, `lib/features/learning/presentation/unified_lesson_shell.dart`, `lib/features/identity/domain/owner_lifecycle_manifest.dart`, `lib/features/identity/data/drift_owner_upgrade_repository.dart`, `lib/features/sync/domain/sync_entity.dart`, `lib/features/sync/data/drift_sync_store.dart`, `lib/features/sync/data/firestore_sync_gateway.dart`, `lib/features/export/application/owner_lifecycle_archive.dart`, `lib/features/export/data/drift_export_reader.dart`, `lib/runtime/app_dependencies.dart`, `lib/runtime/app_bootstrap.dart`, `firestore.rules`, `test/support/current_database_contract.dart`, `test/data/local/app_database_migration_test.dart`, `test/data/local/app_database_test.dart`, `test/database/migration_v16_to_v17_test.dart`, `test/features/learning/unified_lesson_controller_test.dart`, `test/features/sync/sync_contract_test.dart`, `test/features/sync/firestore_sync_gateway_test.dart`, `test/features/export/export_use_cases_test.dart`, `test/features/identity/drift_owner_upgrade_repository_test.dart`, `test/runtime/app_bootstrap_test.dart`, `test/security/firestore-rules.test.cjs`, `test/scenarios/production_learning_restart_test.dart`, `test/scenarios/complete_owner_export_delete_test.dart`, `docs/database/schema_ledger.md`
- [ ] **RED:** targeted v17→v18 fixture เพิ่ม `learning_time_segments` (39→40), full-upgrade inventory เป็น 40; ทดสอบ shell active/pause/resume/background/idle transitions, negative/overlap rejection, retry equality และ restart recovery
- [ ] **GREEN:** wire active-time controller ผ่าน production dependencies และ Unified Shell lifecycle, append immutable active segments จาก monotonic clock แล้ว derive duration; ห้ามคำนวณ effort จาก `ended-started` อย่างเดียว
- [ ] **GENERATE:** `dart run build_runner build --delete-conflicting-outputs`
- [ ] **VERIFY:** `Invoke-NativeStep { flutter test --no-pub test/database/migration_v17_to_v18_test.dart test/data/local/app_database_migration_test.dart test/data/local/app_database_test.dart }`; `Invoke-NativeStep { flutter test --no-pub test/features/time_tracking/learning_time_repository_test.dart test/features/time_tracking/active_learning_time_controller_test.dart test/features/learning/unified_lesson_controller_test.dart }`; `Invoke-NativeStep { flutter test --no-pub test/runtime/app_bootstrap_test.dart test/scenarios/production_learning_restart_test.dart test/scenarios/complete_owner_export_delete_test.dart }`; `Invoke-NativeStep { npm run test:rules }`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/data/local/tables/time_tracking_tables.dart lib/features/time_tracking/domain/learning_time_segment.dart lib/features/time_tracking/domain/learning_time_repository.dart lib/features/time_tracking/data/drift_learning_time_repository.dart lib/features/time_tracking/application/active_learning_time_controller.dart test/database/migration_v17_to_v18_test.dart test/features/time_tracking/learning_time_repository_test.dart test/features/time_tracking/active_learning_time_controller_test.dart lib/data/local/app_database.dart lib/data/local/app_database.g.dart lib/features/learning/application/unified_lesson_controller.dart lib/features/learning/presentation/unified_lesson_shell.dart lib/features/identity/domain/owner_lifecycle_manifest.dart lib/features/identity/data/drift_owner_upgrade_repository.dart lib/features/sync/domain/sync_entity.dart lib/features/sync/data/drift_sync_store.dart lib/features/sync/data/firestore_sync_gateway.dart lib/features/export/application/owner_lifecycle_archive.dart lib/features/export/data/drift_export_reader.dart lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart firestore.rules test/support/current_database_contract.dart test/data/local/app_database_migration_test.dart test/data/local/app_database_test.dart test/database/migration_v16_to_v17_test.dart test/features/learning/unified_lesson_controller_test.dart test/features/sync/sync_contract_test.dart test/features/sync/firestore_sync_gateway_test.dart test/features/export/export_use_cases_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart test/runtime/app_bootstrap_test.dart test/security/firestore-rules.test.cjs test/scenarios/production_learning_restart_test.dart test/scenarios/complete_owner_export_delete_test.dart docs/database/schema_ledger.md }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(time): add trustworthy active learning time" }`
- **Exit/Rollback:** capture ปิดได้แต่ stored segments คง exportable; no schema downgrade

### f25 — Learning Calendar & Weekly Analytics

- **Source/Coverage:** `A / Partial`
- **ทำอะไร/หน้าที่:** แสดง effort, accuracy, skill distribution และ trend แยกแกน ไม่รวมเป็นคะแนนเดียว
- **Authority/Dependencies:** f24, Progress/SRS/AnswerAttempts, TimezonePolicy; เป็น read model และ f36 เป็น parent production consumer
- **Files:** Create `lib/features/progress/domain/learning_calendar.dart`, `lib/features/progress/data/drift_learning_calendar_reader.dart`, `lib/features/progress/application/learning_calendar_use_cases.dart`, `lib/screens/learning_calendar_screen.dart`, `test/features/progress/learning_calendar_reader_test.dart`, `test/screens/learning_calendar_screen_test.dart`
- [ ] **RED:** ทดสอบ timezone week boundary, empty week, assessment exclusion/inclusion by axis และ no combined score
- [ ] **GREEN:** derive immutable daily/weekly buckets จาก canonical rows; UI label axes แยก
- [ ] **VERIFY:** `flutter test --no-pub test/features/progress/learning_calendar_reader_test.dart test/screens/learning_calendar_screen_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/progress/domain/learning_calendar.dart lib/features/progress/data/drift_learning_calendar_reader.dart lib/features/progress/application/learning_calendar_use_cases.dart lib/screens/learning_calendar_screen.dart test/features/progress/learning_calendar_reader_test.dart test/screens/learning_calendar_screen_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(progress): add separated weekly learning analytics" }`
- **Exit/Rollback:** คง G1 จน f36 dashboard integration test ผ่าน; ปิด analytics screen ไม่มี writer/table ใหม่

### f26 — Goal / Test Countdown

- **Source/Coverage:** `A→L / New`
- **ทำอะไร/หน้าที่:** เก็บ deadline ของ language test, course หรือ personal goal โดยไม่มี admission-score logic
- **Authority/Dependencies:** owner identity, TimezonePolicy, optional f35 defaults; ไม่พึ่ง university database
- **Files:** Create `lib/data/local/tables/planning_tables.dart`, `lib/features/goals/domain/learning_goal.dart`, `lib/features/goals/domain/learning_goal_repository.dart`, `lib/features/goals/data/drift_learning_goal_repository.dart`, `lib/features/goals/application/learning_goal_use_cases.dart`, `lib/screens/learning_goals_screen.dart`, `test/database/migration_v18_to_v19_test.dart`, `test/features/goals/learning_goal_use_cases_test.dart`, `test/screens/learning_goals_screen_test.dart`; Modify `lib/data/local/app_database.dart`, `lib/data/local/app_database.g.dart`, `lib/features/identity/domain/owner_lifecycle_manifest.dart`, `lib/features/identity/data/drift_owner_upgrade_repository.dart`, `lib/features/sync/domain/sync_entity.dart`, `lib/features/sync/data/drift_sync_store.dart`, `lib/features/sync/data/firestore_sync_gateway.dart`, `lib/features/export/application/owner_lifecycle_archive.dart`, `lib/features/export/data/drift_export_reader.dart`, `lib/runtime/app_dependencies.dart`, `lib/runtime/app_bootstrap.dart`, `lib/screens/study_planning_hub_screen.dart`, `firestore.rules`, `test/support/current_database_contract.dart`, `test/data/local/app_database_migration_test.dart`, `test/data/local/app_database_test.dart`, `test/database/migration_v17_to_v18_test.dart`, `test/features/sync/sync_contract_test.dart`, `test/features/sync/firestore_sync_gateway_test.dart`, `test/features/export/export_use_cases_test.dart`, `test/features/identity/drift_owner_upgrade_repository_test.dart`, `test/runtime/app_bootstrap_test.dart`, `test/screens/study_planning_hub_screen_test.dart`, `test/security/firestore-rules.test.cjs`, `test/scenarios/complete_owner_export_delete_test.dart`, `docs/database/schema_ledger.md`
- [ ] **RED:** targeted v18→v19 fixture เพิ่ม `learning_goals`/`study_reminders` (40→42), full-upgrade inventory เป็น 42; ทดสอบ past/future deadline, timezone, idempotent update, reject admission fields และ Hub เพิ่ม goal child action โดย production entry ยังคง exact one `home/study-planning`
- [ ] **GREEN:** persist typed goal kind/title/deadline/status, wire repository/screen ผ่าน production dependencies แล้วเพิ่ม child action ใน `StudyPlanningHubScreen` โดยไม่เพิ่ม main-navigation/production entry; sync v1 remains Off until reviewed rules deploy
- [ ] **GENERATE:** `dart run build_runner build --delete-conflicting-outputs`
- [ ] **VERIFY:** `Invoke-NativeStep { flutter test --no-pub test/database/migration_v18_to_v19_test.dart test/data/local/app_database_migration_test.dart test/data/local/app_database_test.dart }`; `Invoke-NativeStep { flutter test --no-pub test/features/goals/learning_goal_use_cases_test.dart test/screens/learning_goals_screen_test.dart test/screens/study_planning_hub_screen_test.dart }`; `Invoke-NativeStep { flutter test --no-pub test/runtime/app_bootstrap_test.dart test/scenarios/complete_owner_export_delete_test.dart }`; `Invoke-NativeStep { npm run test:rules }`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/data/local/tables/planning_tables.dart lib/features/goals/domain/learning_goal.dart lib/features/goals/domain/learning_goal_repository.dart lib/features/goals/data/drift_learning_goal_repository.dart lib/features/goals/application/learning_goal_use_cases.dart lib/screens/learning_goals_screen.dart test/database/migration_v18_to_v19_test.dart test/features/goals/learning_goal_use_cases_test.dart test/screens/learning_goals_screen_test.dart lib/data/local/app_database.dart lib/data/local/app_database.g.dart lib/features/identity/domain/owner_lifecycle_manifest.dart lib/features/identity/data/drift_owner_upgrade_repository.dart lib/features/sync/domain/sync_entity.dart lib/features/sync/data/drift_sync_store.dart lib/features/sync/data/firestore_sync_gateway.dart lib/features/export/application/owner_lifecycle_archive.dart lib/features/export/data/drift_export_reader.dart lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart lib/screens/study_planning_hub_screen.dart firestore.rules test/support/current_database_contract.dart test/data/local/app_database_migration_test.dart test/data/local/app_database_test.dart test/database/migration_v17_to_v18_test.dart test/features/sync/sync_contract_test.dart test/features/sync/firestore_sync_gateway_test.dart test/features/export/export_use_cases_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart test/runtime/app_bootstrap_test.dart test/screens/study_planning_hub_screen_test.dart test/security/firestore-rules.test.cjs test/scenarios/complete_owner_export_delete_test.dart docs/database/schema_ledger.md }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(goals): add language learning countdowns" }`
- **Exit/Rollback:** ปิด entry/notification ได้โดย goals ยัง export/delete; ห้าม schema downgrade

### f27 — Opt-in Study Reminder

- **Source/Coverage:** `A→L / New`
- **ทำอะไร/หน้าที่:** ตั้ง reminder ที่ผู้ใช้ควบคุมเองจาก due review/goal พร้อม quiet hours และข้อความไม่ลงโทษ
- **Authority/Dependencies:** v19 StudyReminders, f22/f26, notification permission; OS schedule เป็น adapter ไม่ใช่ source of truth
- **Files:** Modify `pubspec.yaml`, `pubspec.lock`, `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `ios/Flutter/Debug.xcconfig`, `ios/Flutter/Release.xcconfig`, `ios/Runner/AppDelegate.swift`, `ios/Runner.xcworkspace/contents.xcworkspacedata`, `lib/runtime/app_dependencies.dart`, `lib/runtime/app_bootstrap.dart`, `lib/screens/learning_goals_screen.dart`, `test/screens/learning_goals_screen_test.dart`, `test/runtime/app_bootstrap_test.dart`, `test/scenarios/complete_owner_export_delete_test.dart`; Create `android/app/src/main/res/drawable/ic_stat_lexiquest.xml`, `android/app/src/main/res/raw/keep.xml`, `ios/Podfile`, `ios/Podfile.lock`, `lib/features/reminders/domain/study_reminder.dart`, `lib/features/reminders/domain/study_reminder_repository.dart`, `lib/features/reminders/domain/reminder_scheduler.dart`, `lib/features/reminders/data/drift_study_reminder_repository.dart`, `lib/features/reminders/data/platform_reminder_scheduler.dart`, `lib/features/reminders/application/study_reminder_use_cases.dart`, `lib/screens/study_reminder_settings_screen.dart`, `test/architecture/notification_platform_contract_test.dart`, `test/features/reminders/drift_study_reminder_repository_test.dart`, `test/features/reminders/study_reminder_use_cases_test.dart`, `test/features/reminders/platform_reminder_scheduler_test.dart`, `test/features/sync/study_reminder_sync_test.dart`, `test/screens/study_reminder_settings_screen_test.dart`; Reuse and contract-check `android/settings.gradle.kts`, `ios/Runner.xcodeproj/project.pbxproj`
- [ ] **RED:** ทดสอบ explicit opt-in, denied permission, DB restart, outbox retry, quiet hours, timezone/DST change, AGP ≥8.11.1 + compileSdk ≥35 + desugaring/multidex, Android reboot receiver + inexact scheduling without exact-alarm permission, iOS target ≥13 + pending cap 64, cancel/delete/owner withdrawal, goal-screen entry gating และ no punitive copy
- [ ] **GREEN:** wire repository/scheduler ผ่าน production dependencies; local DB transaction + outbox commit ก่อน schedule/cancel OS และ reconciliation ซ่อม desired-vs-platform state หลัง restart; pin `flutter_local_notifications: 22.3.0` และ `timezone: 0.11.1`, enable Java 17 core-library desugaring `2.1.4` + multidex, add Android permission/receivers/resources, bootstrap CocoaPods at iOS 13 และ register iOS notification delegate; ใช้ inexact reminder เป็นค่าเริ่มต้น
- [ ] **VERIFY:** `Invoke-NativeStep { flutter pub get }`; `Invoke-NativeStep { flutter test --no-pub test/architecture/notification_platform_contract_test.dart test/features/reminders/drift_study_reminder_repository_test.dart test/features/reminders/study_reminder_use_cases_test.dart test/features/reminders/platform_reminder_scheduler_test.dart test/features/sync/study_reminder_sync_test.dart }`; `Invoke-NativeStep { flutter test --no-pub test/features/motivation/timezone_policy_test.dart test/features/motivation/streak_use_cases_test.dart test/screens/study_reminder_settings_screen_test.dart test/screens/learning_goals_screen_test.dart test/runtime/app_bootstrap_test.dart test/scenarios/complete_owner_export_delete_test.dart }`; `Invoke-NativeStep { flutter build apk --debug --no-pub }`; บน macOS CI รัน `Push-Location ios; Invoke-NativeStep { pod install }; Pop-Location; Invoke-NativeStep { flutter build ios --debug --no-codesign --no-pub }`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- pubspec.yaml pubspec.lock android/app/build.gradle.kts android/app/src/main/AndroidManifest.xml ios/Flutter/Debug.xcconfig ios/Flutter/Release.xcconfig ios/Runner/AppDelegate.swift ios/Runner.xcworkspace/contents.xcworkspacedata lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart lib/screens/learning_goals_screen.dart test/screens/learning_goals_screen_test.dart test/runtime/app_bootstrap_test.dart test/scenarios/complete_owner_export_delete_test.dart android/app/src/main/res/drawable/ic_stat_lexiquest.xml android/app/src/main/res/raw/keep.xml ios/Podfile ios/Podfile.lock lib/features/reminders/domain/study_reminder.dart lib/features/reminders/domain/study_reminder_repository.dart lib/features/reminders/domain/reminder_scheduler.dart lib/features/reminders/data/drift_study_reminder_repository.dart lib/features/reminders/data/platform_reminder_scheduler.dart lib/features/reminders/application/study_reminder_use_cases.dart lib/screens/study_reminder_settings_screen.dart test/architecture/notification_platform_contract_test.dart test/features/reminders/drift_study_reminder_repository_test.dart test/features/reminders/study_reminder_use_cases_test.dart test/features/reminders/platform_reminder_scheduler_test.dart test/features/sync/study_reminder_sync_test.dart test/screens/study_reminder_settings_screen_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(reminders): add opt in study reminders" }`
- **Exit/Rollback:** kill switch ยกเลิก future schedules แต่ไม่ลบ goals; permission denied ต้องไม่ retry loop

### f28 — Learning Assessment & Progress Comparison

- **Source/Coverage:** `L / New`
- **ทำอะไร/หน้าที่:** รัน pre/post assessment ที่ version-pinned และเปรียบเทียบเฉพาะคู่ที่ metadata เข้ากัน โดยแยกจาก practice
- **Authority/Dependencies:** Foundation schema v15, Evidence Gateway, f04, f24, real consent และ stable assignment; f42 เป็น parent production consumer ที่แสดงเฉพาะ assigned run
- **Files:** Create `lib/screens/pre_post_assessment_screen.dart`, `test/screens/pre_post_assessment_screen_test.dart`; Modify `lib/features/assessment/domain/assessment_models.dart`, `lib/features/assessment/domain/assessment_repository.dart`, `lib/features/assessment/domain/assessment_instrument_catalog.dart`, `lib/features/assessment/data/drift_assessment_repository.dart`, `lib/features/assessment/application/assessment_use_cases.dart`, `lib/features/assessment/application/assessment_comparison.dart`, `test/features/assessment/assessment_use_cases_test.dart`, `test/features/assessment/assessment_isolation_test.dart`, `test/features/assessment/assessment_comparison_test.dart`
- [ ] **RED:** ทดสอบ unknown consent/unassigned/mismatched checksum/time invalid, no answer leakage และ SRS/Quest/Streak/XP/Coins unchanged byte-for-byte
- [ ] **GREEN:** UI เรียก `AssessmentUseCases`; scoring/correctness มาจาก instrument catalog ไม่รับจาก screen
- [ ] **VERIFY:** `flutter test --no-pub test/features/assessment test/screens/pre_post_assessment_screen_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/screens/pre_post_assessment_screen.dart test/screens/pre_post_assessment_screen_test.dart lib/features/assessment/domain/assessment_models.dart lib/features/assessment/domain/assessment_repository.dart lib/features/assessment/domain/assessment_instrument_catalog.dart lib/features/assessment/data/drift_assessment_repository.dart lib/features/assessment/application/assessment_use_cases.dart lib/features/assessment/application/assessment_comparison.dart test/features/assessment/assessment_use_cases_test.dart test/features/assessment/assessment_isolation_test.dart test/features/assessment/assessment_comparison_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(assessment): add isolated pre post assessment flow" }`
- **Exit/Rollback:** Assessment dependency nullable/off-only และ screen คง G1 จน f42 assigned-entry test ผ่าน; rollback ห้ามลบ runs/evidence

## Domain 5 — Motivation & Engagement / C5 (6 capabilities)

**Completion contract:** motivation เดินหน้าจาก eligible evidence เท่านั้น Quest/Streak มี authority เดียว Lifetime XP แยกจาก Coins และทุก grant/replay idempotent ห้าม purchase ลด level

**Domain-local topological order:** Foundation XP/Coins + Streak convergence → `f29 → f30 → f31 → f32 → f33 → f34`

**Domain interfaces:**

```dart
abstract interface class MotivationProjectionPort {
  Future<void> applyEligible(EvidenceProjectionDecision decision);
}

abstract interface class CompanionReactionCatalog {
  CompanionReaction resolve(CompanionSignal signal, String catalogVersion);
}
```

### f29 — Evidence-Based Quest

- **Source/Coverage:** `A→L / Existing`
- **ทำอะไร/หน้าที่:** advance Quest จาก evidence ที่ active policy อนุญาตและมี deterministic receipt เท่านั้น
- **Authority/Dependencies:** Existing `QuestUseCases`, `DriftQuestRepository`, Quest tables และ Foundation projection reconciler; ห้ามใช้ legacy quest services
- **Files:** Modify `lib/features/quest/application/quest_catalog_provider.dart`, `lib/features/quest/application/quest_use_cases.dart`, `lib/screens/quest_status_screen.dart`, `test/features/quest/quest_learning_integration_test.dart`, `test/features/quest/quest_use_cases_test.dart`, `test/screens/quest_status_screen_test.dart`
- [ ] **RED:** ทดสอบ assessment/guided/exposure denied, eligible replay once, prerequisite order และ Shadow divergence ไม่เปลี่ยน applied progress
- [ ] **GREEN:** ให้ Quest consume projection receipt v2 เท่านั้นและคง repository/table เดิม
- [ ] **VERIFY:** `flutter test --no-pub test/features/quest/quest_learning_integration_test.dart test/features/quest/quest_use_cases_test.dart test/screens/quest_status_screen_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/quest/application/quest_catalog_provider.dart lib/features/quest/application/quest_use_cases.dart lib/screens/quest_status_screen.dart test/features/quest/quest_learning_integration_test.dart test/features/quest/quest_use_cases_test.dart test/screens/quest_status_screen_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "refactor(quest): enforce evidence eligible progress" }`
- **Exit/Rollback:** emergency-off หยุด invocation ไม่ลบ quest instance/progress; assignment ไม่เปลี่ยน

### f30 — Gentle Streak

- **Source/Coverage:** `A→L / Existing`
- **ทำอะไร/หน้าที่:** ใช้ dedicated Streak authority พร้อม grace, freeze, recovery และข้อความไม่ลงโทษ
- **Authority/Dependencies:** `StreakUseCases`, `DriftStreakRepository`, `StreakStates`, `LearningDayLog`, TimezonePolicy และ eligible projection receipt; f42 เป็น parent consumer ของ card
- **Files:** Modify `lib/features/motivation/domain/streak_policy.dart`, `lib/features/motivation/application/streak_use_cases.dart`; Create `lib/widgets/gentle_streak_card.dart`, `test/widgets/gentle_streak_card_test.dart`; Modify `test/features/motivation/streak_use_cases_test.dart`, `test/features/motivation/streak_learning_integration_test.dart`
- [ ] **RED:** ทดสอบ timezone shift, grace/freeze/recovery, duplicate day, denied evidence และ Progress ไม่ recompute จาก attempts
- [ ] **GREEN:** ขยาย policy/reaction copy โดย writer เดียวยังคือ DriftStreakRepository
- [ ] **VERIFY:** `flutter test --no-pub test/features/motivation/streak_use_cases_test.dart test/features/motivation/streak_learning_integration_test.dart test/widgets/gentle_streak_card_test.dart test/architecture/streak_authority_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/motivation/domain/streak_policy.dart lib/features/motivation/application/streak_use_cases.dart lib/widgets/gentle_streak_card.dart test/widgets/gentle_streak_card_test.dart test/features/motivation/streak_use_cases_test.dart test/features/motivation/streak_learning_integration_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(motivation): add gentle streak recovery" }`
- **Exit/Rollback:** card คง G1 จน f42 integration test ผ่าน; ปิด card/recovery prompt ได้ แต่ห้ามสลับกลับไปคำนวณ streak จาก attempt dates

### f31 — Achievement & Milestone

- **Source/Coverage:** `A / Existing`
- **ทำอะไร/หน้าที่:** unlock durable milestone จาก eligible idempotent evidence ด้วย definition version ที่ตรวจสอบได้
- **Authority/Dependencies:** `AchievementUnlocks`, Evidence policy, existing projection rebuilder และ Progress reader
- **Files:** Create `lib/features/progress/domain/achievement_policy.dart`, `test/features/progress/achievement_policy_test.dart`; Modify `lib/features/learning/data/drift_learning_repository.dart`, `lib/features/learning/data/drift_learning_projection_rebuilder.dart`, `test/features/learning/data/drift_learning_projection_rebuilder_test.dart`, `test/screens/achievements_screen_test.dart`
- [ ] **RED:** ทดสอบ same evidence unlock once, definition version change, denied evidence และ rebuild/live equality
- [ ] **GREEN:** writer/rebuilder เรียก pure `AchievementPolicy` เดียวกันและเก็บ source event identity
- [ ] **VERIFY:** `flutter test --no-pub test/features/progress/achievement_policy_test.dart test/features/learning/data/drift_learning_projection_rebuilder_test.dart test/screens/achievements_screen_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/progress/domain/achievement_policy.dart test/features/progress/achievement_policy_test.dart lib/features/learning/data/drift_learning_repository.dart lib/features/learning/data/drift_learning_projection_rebuilder.dart test/features/learning/data/drift_learning_projection_rebuilder_test.dart test/screens/achievements_screen_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "refactor(progress): centralize achievement policy" }`
- **Exit/Rollback:** ปิด new definitions ได้โดย unlock เดิมไม่ถูกลบหรือ re-award

### f32 — Avatar Level-Up & Cosmetic Unlock

- **Source/Coverage:** `A / Partial`
- **ทำอะไร/หน้าที่:** เชื่อม lifetime XP กับ level และ cosmetic catalog โดย purchase/equip ใช้ Coins แยก authority
- **Authority/Dependencies:** Foundation Economy cutover, `RewardUseCases`, `DriftRewardRepository`, ProgressSnapshot, Owned/Equipped Reward tables
- **Files:** Create `lib/features/rewards/domain/avatar_progression_policy.dart`, `test/features/rewards/avatar_progression_policy_test.dart`; Modify `lib/features/rewards/domain/reward_models.dart`, `lib/features/rewards/application/reward_use_cases.dart`, `lib/screens/avatar_equipment_screen.dart`, `test/features/rewards/reward_use_cases_test.dart`, `test/features/progress/progress_projector_test.dart`, `test/screens/avatar_equipment_screen_test.dart`
- [ ] **RED:** ทดสอบ purchase ไม่ลด XP/level, insufficient Coins, unlock threshold, equip idempotency และ restart rebuild
- [ ] **GREEN:** level อ่าน lifetime XP; shop/purchase เขียน RewardTransactions/Coins เท่านั้น
- [ ] **VERIFY:** `flutter test --no-pub test/features/rewards/avatar_progression_policy_test.dart test/features/rewards/reward_use_cases_test.dart test/features/progress/progress_projector_test.dart test/screens/avatar_equipment_screen_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/rewards/domain/avatar_progression_policy.dart test/features/rewards/avatar_progression_policy_test.dart lib/features/rewards/domain/reward_models.dart lib/features/rewards/application/reward_use_cases.dart lib/screens/avatar_equipment_screen.dart test/features/rewards/reward_use_cases_test.dart test/features/progress/progress_projector_test.dart test/screens/avatar_equipment_screen_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(rewards): separate avatar progression from coins" }`
- **Exit/Rollback:** ปิด shop/cosmetic entry ได้; XP/ownership audit rows คงอยู่และห้ามย้อน purchase เข้า XP ledger

### f33 — Contextual Companion

- **Source/Coverage:** `A / Partial`
- **ทำอะไร/หน้าที่:** แสดง scripted/versioned reaction จาก session events เช่น เริ่มเรียน พยายามใหม่ จบ session โดยไม่เปลี่ยนคะแนน
- **Authority/Dependencies:** Unified Shell signals, immutable event context; version 1 ไม่เรียก generative AI
- **Files:** Create `lib/features/companion/domain/companion_reaction.dart`, `lib/features/companion/domain/companion_reaction_catalog.dart`, `lib/features/companion/application/companion_reaction_use_cases.dart`, `lib/features/companion/presentation/contextual_companion_widget.dart`, `test/features/companion/companion_reaction_catalog_test.dart`, `test/features/companion/contextual_companion_widget_test.dart`; Modify `lib/features/learning/application/unified_lesson_controller.dart`, `lib/features/learning/presentation/unified_lesson_shell.dart`, `test/features/learning/unified_lesson_controller_test.dart`
- [ ] **RED:** ทดสอบ deterministic reaction, unknown signal, reduced motion, no network call, no Evidence/Mastery mutation และ shell แสดง reaction หลัง canonical commit เท่านั้น
- [ ] **GREEN:** resolve local reviewed script by catalog version แล้ว inject use case/widget ที่ Unified Shell; widget เป็น consumer เท่านั้น
- [ ] **VERIFY:** `flutter test --no-pub test/features/companion/companion_reaction_catalog_test.dart test/features/companion/contextual_companion_widget_test.dart test/features/learning/unified_lesson_controller_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/companion/domain/companion_reaction.dart lib/features/companion/domain/companion_reaction_catalog.dart lib/features/companion/application/companion_reaction_use_cases.dart lib/features/companion/presentation/contextual_companion_widget.dart test/features/companion/companion_reaction_catalog_test.dart test/features/companion/contextual_companion_widget_test.dart lib/features/learning/application/unified_lesson_controller.dart lib/features/learning/presentation/unified_lesson_shell.dart test/features/learning/unified_lesson_controller_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(companion): add scripted contextual reactions" }`
- **Exit/Rollback:** ปิด widget ได้ทันที; ห้าม fallback ไป AI tutor หรือ persist persona transcript

### f34 — Achievement Share Card

- **Source/Coverage:** `A / New`
- **ทำอะไร/หน้าที่:** สร้าง artifact ที่ผู้ใช้เลือก export/share เองจาก achievement ที่ unlock จริง โดยไม่สร้าง social graph
- **Authority/Dependencies:** f31, ProgressUseCases และ existing file export pattern; ไม่รับ arbitrary remote content
- **Files:** Create `lib/features/achievements/application/achievement_share_card_use_cases.dart`, `lib/features/achievements/data/file_selector_share_card_store.dart`, `lib/features/achievements/presentation/achievement_share_card.dart`, `test/features/achievements/achievement_share_card_use_cases_test.dart`, `test/features/achievements/achievement_share_card_test.dart`; Modify `lib/screens/achievements_screen.dart`
- [ ] **RED:** ทดสอบ locked achievement reject, explicit confirmation, deterministic safe metadata, no owner ID in artifact และ cancel leaves no file
- [ ] **GREEN:** render local card and write only after user-selected destination; no internal sharing/network/table
- [ ] **VERIFY:** `flutter test --no-pub test/features/achievements/achievement_share_card_use_cases_test.dart test/features/achievements/achievement_share_card_test.dart test/screens/achievements_screen_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/achievements/application/achievement_share_card_use_cases.dart lib/features/achievements/data/file_selector_share_card_store.dart lib/features/achievements/presentation/achievement_share_card.dart test/features/achievements/achievement_share_card_use_cases_test.dart test/features/achievements/achievement_share_card_test.dart lib/screens/achievements_screen.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(achievements): add opt in share card artifact" }`
- **Exit/Rollback:** remove action/widget; generated user filesอยู่นอก evidence authorityและลบได้โดยผู้ใช้

## Domain 6 — Personalization, Preferences & Accessibility / C6 (5 capabilities)

**Completion contract:** preference แก้ได้ recommendation อธิบายได้และ protocol-safe ทุก mode มี accessible alternative ห้าม preference เปลี่ยน experiment assignment หรือปิดกั้น input mode

**Domain-local topological order:** `f38 → f35 → f39 → f36 → f37`; cross-domain prerequisites ใช้ typed graph

**Domain interfaces:**

```dart
abstract interface class LearnerPreferencesRepository {
  Future<LearnerPreferences> read(String ownerId);
  Future<void> save(LearnerPreferences preferences);
}

abstract interface class RecommendationReader {
  Future<List<ExplainedRecommendation>> read(RecommendationRequest request);
}
```

### f35 — Learning Preference & Goal Quiz

- **Source/Coverage:** `A→L / New`
- **ทำอะไร/หน้าที่:** สร้าง editable defaults จาก goal, available time และ activity preference โดยไม่มี fixed learning-style label
- **Authority/Dependencies:** owner identity, f16, f26; preference authority แยกจาก ExperimentRegistry
- **Files:** Create `lib/data/local/tables/preference_tables.dart`, `lib/features/preferences/domain/learner_preferences.dart`, `lib/features/preferences/domain/learner_preferences_repository.dart`, `lib/features/preferences/data/drift_learner_preferences_repository.dart`, `lib/features/preferences/application/learner_preferences_use_cases.dart`, `lib/screens/learning_preference_quiz_screen.dart`, `test/database/migration_v19_to_v20_test.dart`, `test/features/preferences/learner_preferences_use_cases_test.dart`, `test/screens/learning_preference_quiz_screen_test.dart`; Modify `lib/data/local/app_database.dart`, `lib/data/local/app_database.g.dart`, `lib/features/identity/domain/owner_lifecycle_manifest.dart`, `lib/features/identity/data/drift_owner_upgrade_repository.dart`, `lib/features/sync/domain/sync_entity.dart`, `lib/features/sync/data/drift_sync_store.dart`, `lib/features/sync/data/firestore_sync_gateway.dart`, `lib/features/export/application/owner_lifecycle_archive.dart`, `lib/features/export/data/drift_export_reader.dart`, `lib/runtime/app_dependencies.dart`, `lib/runtime/app_bootstrap.dart`, `lib/screens/study_planning_hub_screen.dart`, `firestore.rules`, `test/support/current_database_contract.dart`, `test/data/local/app_database_migration_test.dart`, `test/data/local/app_database_test.dart`, `test/database/migration_v18_to_v19_test.dart`, `test/features/sync/sync_contract_test.dart`, `test/features/sync/firestore_sync_gateway_test.dart`, `test/features/export/export_use_cases_test.dart`, `test/features/identity/drift_owner_upgrade_repository_test.dart`, `test/runtime/app_bootstrap_test.dart`, `test/screens/study_planning_hub_screen_test.dart`, `test/security/firestore-rules.test.cjs`, `test/scenarios/complete_owner_export_delete_test.dart`, `docs/database/schema_ledger.md`
- [ ] **RED:** targeted v19→v20 fixture เพิ่ม `learner_preferences` (42→43), full-upgrade inventory เป็น 43; ทดสอบ editable/restart/sync, unknown value, no learning-style label, Hub child action โดยไม่มี production entry เพิ่ม และ assignment rows byte-equal
- [ ] **GREEN:** persist versioned defaults + explicit override, wire repository/quiz ผ่าน production dependencies และ child action ใน `StudyPlanningHubScreen`; general constructor defaults safe and research protocol may clamp without rewriting preference
- [ ] **GENERATE:** `dart run build_runner build --delete-conflicting-outputs`
- [ ] **VERIFY:** `Invoke-NativeStep { flutter test --no-pub test/database/migration_v19_to_v20_test.dart test/data/local/app_database_migration_test.dart test/data/local/app_database_test.dart }`; `Invoke-NativeStep { flutter test --no-pub test/features/preferences/learner_preferences_use_cases_test.dart test/screens/learning_preference_quiz_screen_test.dart test/screens/study_planning_hub_screen_test.dart }`; `Invoke-NativeStep { flutter test --no-pub test/runtime/app_bootstrap_test.dart test/runtime/persisted_registries_test.dart test/scenarios/complete_owner_export_delete_test.dart }`; `Invoke-NativeStep { npm run test:rules }`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/data/local/tables/preference_tables.dart lib/features/preferences/domain/learner_preferences.dart lib/features/preferences/domain/learner_preferences_repository.dart lib/features/preferences/data/drift_learner_preferences_repository.dart lib/features/preferences/application/learner_preferences_use_cases.dart lib/screens/learning_preference_quiz_screen.dart test/database/migration_v19_to_v20_test.dart test/features/preferences/learner_preferences_use_cases_test.dart test/screens/learning_preference_quiz_screen_test.dart lib/data/local/app_database.dart lib/data/local/app_database.g.dart lib/features/identity/domain/owner_lifecycle_manifest.dart lib/features/identity/data/drift_owner_upgrade_repository.dart lib/features/sync/domain/sync_entity.dart lib/features/sync/data/drift_sync_store.dart lib/features/sync/data/firestore_sync_gateway.dart lib/features/export/application/owner_lifecycle_archive.dart lib/features/export/data/drift_export_reader.dart lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart lib/screens/study_planning_hub_screen.dart firestore.rules test/support/current_database_contract.dart test/data/local/app_database_migration_test.dart test/data/local/app_database_test.dart test/database/migration_v18_to_v19_test.dart test/features/sync/sync_contract_test.dart test/features/sync/firestore_sync_gateway_test.dart test/features/export/export_use_cases_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart test/runtime/app_bootstrap_test.dart test/screens/study_planning_hub_screen_test.dart test/security/firestore-rules.test.cjs test/scenarios/complete_owner_export_delete_test.dart docs/database/schema_ledger.md }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(preferences): add editable learner defaults" }`
- **Exit/Rollback:** ปิด quiz ได้โดย preferences ยังอ่าน/export/delete; assignment ห้ามเปลี่ยน

### f36 — Personal Learning Profile

- **Source/Coverage:** `A / Partial`
- **ทำอะไร/หน้าที่:** แสดง Mastery, SRS, effort, accuracy, weakness และ engagement เป็น projections แยกกัน
- **Authority/Dependencies:** DriftProgressQueries, f24/f25, Quest/Streak/Reward readers; ไม่มี combined profile score
- **Files:** Create `lib/features/progress/domain/personal_learning_profile.dart`, `lib/features/progress/data/drift_personal_learning_profile_reader.dart`, `test/features/progress/personal_learning_profile_test.dart`; Modify `lib/features/progress/application/progress_use_cases.dart`, `lib/screens/profile_settings_screen.dart`, `lib/screens/mastery_dashboard_screen.dart`, `test/screens/profile_settings_screen_test.dart`, `test/screens/mastery_dashboard_screen_test.dart`
- [ ] **RED:** ทดสอบแต่ละ axis จาก authority ของตน, assessment isolation, empty state, ไม่มี weighted total และ dashboard เปิด f25 calendar ผ่าน typed action
- [ ] **GREEN:** compose read model โดยไม่ persist profile snapshot/table และให้ dashboard เป็น production parent ของ f25 โดยไม่คำนวณ metric ซ้ำ
- [ ] **VERIFY:** `flutter test --no-pub test/features/progress/personal_learning_profile_test.dart test/screens/profile_settings_screen_test.dart test/screens/mastery_dashboard_screen_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/progress/domain/personal_learning_profile.dart lib/features/progress/data/drift_personal_learning_profile_reader.dart test/features/progress/personal_learning_profile_test.dart test/screens/mastery_dashboard_screen_test.dart lib/features/progress/application/progress_use_cases.dart lib/screens/profile_settings_screen.dart lib/screens/mastery_dashboard_screen.dart test/screens/profile_settings_screen_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(progress): add separated personal learning profile" }`
- **Exit/Rollback:** ปิด profile panels ได้; ห้ามสร้าง PersonalProfile table

### f37 — Recommendation Panel

- **Source/Coverage:** `L / Partial`
- **ทำอะไร/หน้าที่:** แสดง next activity พร้อม reason, evidence freshness, protocol constraint และ learner override
- **Authority/Dependencies:** f14/f15/f35/f36, shared RecommendationPolicy; ไม่มี recommendation table และ f42 เป็น parent production consumer
- **Files:** Create `lib/features/recommendation/data/drift_recommendation_reader.dart`, `lib/features/recommendation/application/recommendation_use_cases.dart`, `lib/widgets/recommendation_panel.dart`, `test/features/recommendation/recommendation_use_cases_test.dart`, `test/widgets/recommendation_panel_test.dart`; Modify `lib/features/progress/data/drift_progress_queries.dart`
- [ ] **RED:** ทดสอบ explainability, stale evidence, unavailable mode, override, protocol lock และ query no-write
- [ ] **GREEN:** reader compose canonical projections แล้ว policy คืน typed reason/alternative
- [ ] **VERIFY:** `flutter test --no-pub test/features/recommendation/recommendation_use_cases_test.dart test/widgets/recommendation_panel_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/recommendation/data/drift_recommendation_reader.dart lib/features/recommendation/application/recommendation_use_cases.dart lib/widgets/recommendation_panel.dart test/features/recommendation/recommendation_use_cases_test.dart test/widgets/recommendation_panel_test.dart lib/features/progress/data/drift_progress_queries.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(recommendation): add explainable recommendation panel" }`
- **Exit/Rollback:** fallback แสดง neutral activity list; ห้าม hard-code recommendation ใน Today Hub/screen

### f38 — Accessibility

- **Source/Coverage:** `L / Partial`
- **ทำอะไร/หน้าที่:** บังคับ scaling, screen-reader semantics, non-color cues, untimed alternative และ input/media alternatives ทุก mode
- **Authority/Dependencies:** M3 theme, Unified Shell และ LessonModeAdapter capability metadata; เป็น release gate
- **Files:** Create `lib/features/accessibility/domain/accessibility_policy.dart`, `lib/features/accessibility/presentation/accessibility_scope.dart`, `test/features/accessibility/accessibility_policy_test.dart`; Modify `lib/features/learning/presentation/unified_lesson_shell.dart`, `lib/features/learning/presentation/handwriting_scratchpad.dart`, `lib/screens/quiz_screen.dart`, `lib/screens/srs_flashcards_screen.dart`, `lib/screens/definition_quiz_screen.dart`, `lib/screens/fill_in_the_blanks_screen.dart`, `lib/screens/matching_mode_screen.dart`, `lib/screens/dictation_quiz_screen.dart`, `lib/screens/speak_to_text_screen.dart`, `lib/screens/shadowing_challenge_screen.dart`, `lib/screens/sentence_scramble_screen.dart`, `lib/screens/word_scramble_screen.dart`, `lib/screens/associative_reading_session_screen.dart`, `test/screens/accessibility_smoke_test.dart`, `test/architecture/lesson_mode_adapter_coverage_test.dart`
- [ ] **RED:** exact-set test ทุก mode ต้องประกาศ alternatives; widget matrix ที่ 200% text, semantics order, high contrast, reduced motion และ keyboard/switch navigation
- [ ] **GREEN:** central policy/scope + adapter metadata; แก้เฉพาะ component ที่ fail โดยไม่สร้าง accessibility-specific score path
- [ ] **VERIFY:** `flutter test --no-pub test/features/accessibility/accessibility_policy_test.dart test/screens/accessibility_smoke_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/accessibility/domain/accessibility_policy.dart lib/features/accessibility/presentation/accessibility_scope.dart test/features/accessibility/accessibility_policy_test.dart lib/features/learning/presentation/unified_lesson_shell.dart lib/features/learning/presentation/handwriting_scratchpad.dart lib/screens/quiz_screen.dart lib/screens/srs_flashcards_screen.dart lib/screens/definition_quiz_screen.dart lib/screens/fill_in_the_blanks_screen.dart lib/screens/matching_mode_screen.dart lib/screens/dictation_quiz_screen.dart lib/screens/speak_to_text_screen.dart lib/screens/shadowing_challenge_screen.dart lib/screens/sentence_scramble_screen.dart lib/screens/word_scramble_screen.dart lib/screens/associative_reading_session_screen.dart test/screens/accessibility_smoke_test.dart test/architecture/lesson_mode_adapter_coverage_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(accessibility): enforce learning mode alternatives" }`
- **Exit/Rollback:** capability ใดไม่ผ่านต้องคง `implementedOff`; ห้ามปิด input mode ของ participant เพื่อให้ test ผ่าน

### f39 — Motion & Theme Controls

- **Source/Coverage:** `A→L / Partial`
- **ทำอะไร/หน้าที่:** รองรับ Light, Dark, System และ Reduced Motion อย่างสม่ำเสมอทั้งแอป
- **Authority/Dependencies:** f35 LearnerPreferencesRepository, f38, `M3Theme`; `main.dart` ไม่ hard-code ThemeMode
- **Files:** Create `lib/features/preferences/application/display_preferences_controller.dart`, `test/features/preferences/display_preferences_controller_test.dart`, `test/screens/setting_screen_test.dart`; Modify `lib/main.dart`, `lib/config/m3_theme.dart`, `lib/screens/setting_screen.dart`, `test/config/m3_theme_test.dart`
- [ ] **RED:** ทดสอบ persist/restart, system change, invalid value fallback, reduced animation duration และ no cohort mutation
- [ ] **GREEN:** drive `MaterialApp.themeMode`/motion scope จาก preference authority เดียว
- [ ] **VERIFY:** `flutter test --no-pub test/features/preferences/display_preferences_controller_test.dart test/config/m3_theme_test.dart test/screens/setting_screen_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/preferences/application/display_preferences_controller.dart test/features/preferences/display_preferences_controller_test.dart test/screens/setting_screen_test.dart lib/main.dart lib/config/m3_theme.dart lib/screens/setting_screen.dart test/config/m3_theme_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(settings): add theme and reduced motion controls" }`
- **Exit/Rollback:** invalid preference fallback System + platform reduced-motion; ห้ามใช้ separate SharedPreferences authority

## Domain 7 — Local Reliability, Offline & Rollout / C7 (3 capabilities)

**Completion contract:** ทุก feature commit local ก่อน sync, owner lifecycle ครบ, download ตรวจ checksum ได้, rollout fail closed และ rollback ผ่าน ห้าม corrupt content เปลี่ยน evidence หรือ cache removal ลบหลักฐาน

**Domain-local topological order:** `f40 → f41 → f44` โดย f44 รอ f04 ตาม typed graph

**Domain interfaces:**

```dart
abstract interface class OfflineContentRepository {
  Future<OfflineContentState> state(ContentIdentity identity);
  Future<void> persistVerified(VerifiedDownloadedArtifact artifact);
}

abstract interface class OfflineContentManager {
  Future<void> download(ContentIdentity identity);
  Future<void> verify(ContentIdentity identity);
  Future<void> repair(ContentIdentity identity);
  Future<void> removeBytes(ContentIdentity identity);
}
```

`ProductionFeatureContract` คง cardinality หนึ่ง delivery entry ต่อหนึ่ง broad runtime feature; child screen ใช้ typed action ภายใน parent และห้ามลงทะเบียน entry เพิ่ม:

| Runtime feature | Canonical delivery entry | Owning capability |
|---|---|---|
| `studyPlanning` | `home/study-planning` → `StudyPlanningHubScreen` | f01; f26/f27 เป็น child actions |
| `researchAssessment` | `research/assessment` → `PrePostAssessmentScreen` | f28; f42 แสดง action เมื่อ assigned |
| `dailyContinuity` | `home/today` → `TodayHubScreen` | f42; f22/f30/f37/f43 เป็น child content/actions |
| `offlineContent` | `settings/offline-content` → `OfflineContentManagerScreen` | f44 |

### f40 — Local-First Operation

- **Source/Coverage:** `L / Existing`
- **ทำอะไร/หน้าที่:** รับประกันว่า mutation ทุกโดเมน commit Drift แบบ transaction ก่อน enqueue/claim cloud sync และ recovery หลัง outage/restart ได้
- **Authority/Dependencies:** Existing domain repositories, `DriftSyncStore`, `SyncEngine`, `FirestoreSyncGateway`, outbox tables และ AppBootstrap
- **Files:** Create `test/architecture/local_first_authority_test.dart`; Modify `lib/features/sync/application/sync_engine.dart`, `lib/features/sync/data/drift_sync_store.dart`, `test/scenarios/file_backed_sync_recovery_test.dart`, `test/scenarios/production_learning_restart_test.dart`, `test/scenarios/complete_owner_export_delete_test.dart`
- [ ] **RED:** architecture test ตรวจ screen ไม่มี Drift/Firestore import, repository transaction precedes outbox, offline retry same ID และ crash between local/remote safe
- [ ] **GREEN:** ทุก work package ใช้ domain repository + existing outbox contract; ห้ามสร้าง LocalFirstService กลางซ้ำ
- [ ] **VERIFY:** `flutter test --no-pub test/architecture/local_first_authority_test.dart test/scenarios/file_backed_sync_recovery_test.dart test/scenarios/production_learning_restart_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- test/architecture/local_first_authority_test.dart lib/features/sync/application/sync_engine.dart lib/features/sync/data/drift_sync_store.dart test/scenarios/file_backed_sync_recovery_test.dart test/scenarios/production_learning_restart_test.dart test/scenarios/complete_owner_export_delete_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "test(sync): enforce local first domain writes" }`
- **Exit/Rollback:** cloud unavailable เป็น degraded state ไม่ทำให้ local learning fail; bounded backoff ห้าม retry loop

### f41 — Feature Flag & Controlled Rollout

- **Source/Coverage:** `L / Existing`
- **ทำอะไร/หน้าที่:** ใช้ registry เดิมสำหรับ Internal → Pilot → Enabled, emergency-off และ fail-closed dependency delivery โดยไม่สร้าง flag 44 ตัว
- **Authority/Dependencies:** `FeatureRegistry`, `RuntimeFeatureOverrideStore`, `ProductionFeatureGate`, `ProductionFeatureContract`, ExperimentRegistry independent
- **Files:** Create `test/architecture/production_feature_delivery_cardinality_test.dart`; Modify `lib/runtime/registries/feature.dart`, `lib/runtime/registries/feature_registry.dart`, `lib/runtime/production_feature_contract.dart`, `lib/runtime/production_feature_gate.dart`, `lib/runtime/app_dependencies.dart`, `lib/runtime/app_bootstrap.dart`, `lib/product/feature_contract/feature_contract_models.dart`, `lib/product/feature_contract/alltcas_idea_integration_catalog.dart`, `test/runtime/registries_test.dart`, `test/runtime/runtime_feature_controls_test.dart`, `test/scenarios/runtime_kill_switch_journey_test.dart`, `test/runtime/app_bootstrap_test.dart`, `test/architecture/production_feature_contract_test.dart`, `test/architecture/alltcas_idea_feature_contract_test.dart`, `test/architecture/alltcas_idea_feature_contract_docs_test.dart`, `docs/generated/alltcas-idea-integration-feature-map.md`, `docs/generated/alltcas-idea-integration-feature-map.json`
- [ ] **RED:** ทดสอบ append-only enum identity, exact four-entry map ด้านบน, one-to-one feature/entry cardinality, duplicate parent/child route rejection, missing dependency fail closed, emergency-off ไม่เปลี่ยน assignment และ product record ไม่ auto-enable
- [ ] **GREEN:** bump product-contract revision แล้ว append `studyPlanning`, `researchAssessment`, `dailyContinuity`, `offlineContent` ใน enum owner/registry เดิมด้วย default hidden/disabled และ exact canonical entry อย่างละหนึ่ง; child screen อยู่ใต้ parent typed action และห้ามเพิ่ม flag/`ProductionFeatureDelivery` ต่อหนึ่ง fXX
- [ ] **GENERATE:** `Invoke-NativeStep { dart run tool/feature_contract/generate_feature_map.dart --write }`; `Invoke-NativeStep { dart run tool/feature_contract/generate_feature_map.dart --check }`
- [ ] **VERIFY:** `flutter test --no-pub test/runtime/registries_test.dart test/runtime/runtime_feature_controls_test.dart test/scenarios/runtime_kill_switch_journey_test.dart test/runtime/app_bootstrap_test.dart test/architecture/production_feature_contract_test.dart test/architecture/production_feature_delivery_cardinality_test.dart test/architecture/alltcas_idea_feature_contract_test.dart test/architecture/alltcas_idea_feature_contract_docs_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- test/architecture/production_feature_delivery_cardinality_test.dart lib/runtime/registries/feature.dart lib/runtime/registries/feature_registry.dart lib/runtime/production_feature_contract.dart lib/runtime/production_feature_gate.dart lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart lib/product/feature_contract/feature_contract_models.dart lib/product/feature_contract/alltcas_idea_integration_catalog.dart test/runtime/registries_test.dart test/runtime/runtime_feature_controls_test.dart test/scenarios/runtime_kill_switch_journey_test.dart test/runtime/app_bootstrap_test.dart test/architecture/production_feature_contract_test.dart test/architecture/alltcas_idea_feature_contract_test.dart test/architecture/alltcas_idea_feature_contract_docs_test.dart docs/generated/alltcas-idea-integration-feature-map.md docs/generated/alltcas-idea-integration-feature-map.json }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(runtime): add controlled 8-44 rollout surfaces" }`
- **Exit/Rollback:** production defaults hidden/limited ตาม gate; kill switch ปิด invocation ไม่ลบ data และไม่ reassign cohort

### f44 — Offline Content Manager

- **Source/Coverage:** `L / Partial`
- **ทำอะไร/หน้าที่:** download, verify, pin, repair และ remove bytes ของ pack/media/model/voice โดยเก็บ manifest identity ที่ evidence อ้างถึง
- **Authority/Dependencies:** f04, f40, f41; existing Model/Voice download managers เป็น adapters; Download State authority เดียวอยู่ใน v16 content schema
- **Files:** Create `lib/features/offline_content/domain/offline_content_state.dart`, `lib/features/offline_content/domain/offline_content_repository.dart`, `lib/features/offline_content/application/offline_content_manager.dart`, `lib/features/offline_content/data/drift_offline_content_repository.dart`, `lib/features/offline_content/data/learning_pack_download_adapter.dart`, `lib/features/offline_content/data/model_download_adapter.dart`, `lib/features/offline_content/data/voice_pack_download_adapter.dart`, `lib/screens/offline_content_manager_screen.dart`, `test/features/offline_content/offline_content_manager_test.dart`, `test/screens/offline_content_manager_screen_test.dart`, `test/screens/offline_content_settings_entry_test.dart`; Modify `lib/runtime/app_dependencies.dart`, `lib/runtime/app_bootstrap.dart`, `lib/screens/setting_screen.dart`, `test/runtime/app_bootstrap_test.dart`, `test/screens/offline_vocabulary_journey_test.dart`; Reuse without schema edit `lib/data/local/tables/content_download_tables.dart`, `test/database/migration_v15_to_v16_test.dart`
- [ ] **RED:** ทดสอบ checksum mismatch quarantine, interrupted download, repair, pinned study revision, remove bytes preserving evidence/manifest และ disk-pressure cleanup
- [ ] **GREEN:** stage temp artifact, verify SHA-256/size/revision แล้ว atomic move + state transaction, wire ผ่าน production dependencies และ gated Settings entry; adapters ห้าม own catalog/table และ work package นี้ห้ามแก้ v16 schema
- [ ] **VERIFY:** `flutter test --no-pub test/database/migration_v15_to_v16_test.dart test/features/offline_content/offline_content_manager_test.dart test/screens/offline_content_manager_screen_test.dart test/screens/offline_content_settings_entry_test.dart test/runtime/app_bootstrap_test.dart test/screens/offline_vocabulary_journey_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/offline_content/domain/offline_content_state.dart lib/features/offline_content/domain/offline_content_repository.dart lib/features/offline_content/application/offline_content_manager.dart lib/features/offline_content/data/drift_offline_content_repository.dart lib/features/offline_content/data/learning_pack_download_adapter.dart lib/features/offline_content/data/model_download_adapter.dart lib/features/offline_content/data/voice_pack_download_adapter.dart lib/screens/offline_content_manager_screen.dart test/features/offline_content/offline_content_manager_test.dart test/screens/offline_content_manager_screen_test.dart test/screens/offline_content_settings_entry_test.dart lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart lib/screens/setting_screen.dart test/runtime/app_bootstrap_test.dart test/screens/offline_vocabulary_journey_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(offline): add verified content manager" }`
- **Exit/Rollback:** corrupt bytes quarantine/redownload; removing cache never deletes AnswerAttempts, Sessions, AssessmentRuns หรือ manifest identity

## Domain 8 — Daily Continuity & History / C8 (2 capabilities)

**Completion contract:** Today Hub และ History เป็น read models เหนือ canonical authorities; replay สร้าง immutable session/evidence ใหม่ ห้ามมี Hub/History progress writer หรือตาราง aggregate authority

**Domain-local topological order:** `f43 → f42`; f42 เริ่มเมื่อ dependencies ทุกตัวใน typed graph พร้อม

**Domain interfaces:**

```dart
abstract interface class LearningHistoryReader {
  Future<List<LearningHistoryEntry>> list(HistoryFilter filter);
  Future<LessonStartCommand> replayAsNewSession(String sourceSessionId);
}

abstract interface class TodayHubReader {
  Future<TodayHubSnapshot> compose(TodayHubRequest request);
}
```

### f42 — Today Hub

- **Source/Coverage:** `L / New`
- **ทำอะไร/หน้าที่:** compose assigned, due, resumable และ recommended work ในหน้าวันนี้ โดยไม่ own progress metric
- **Authority/Dependencies:** Active session, SRS due, f22, f26/f27, f28 assignment, f29 Quest, f30 Streak card, f37, f43; read-only join
- **Files:** Create `lib/features/today_hub/domain/today_hub_models.dart`, `lib/features/today_hub/data/drift_today_hub_reader.dart`, `lib/features/today_hub/application/today_hub_use_cases.dart`, `lib/screens/today_hub_screen.dart`, `test/features/today_hub/today_hub_reader_test.dart`, `test/screens/today_hub_screen_test.dart`; Modify `lib/runtime/app_dependencies.dart`, `lib/runtime/app_bootstrap.dart`, `lib/screens/main_navigation_screen.dart`, `test/runtime/app_bootstrap_test.dart`, `test/screens/main_navigation_screen_test.dart`, `test/scenarios/production_feature_navigation_test.dart`, `test/architecture/production_feature_delivery_cardinality_test.dart` only after f41 mapping
- [ ] **RED:** ทดสอบ deterministic sections, duplicate item reason merge, unavailable dependency, stale recommendation, assigned `research/assessment` action, review/history child routing, gentle-streak rendering, exact one `home/today` delivery, live emergency-off, no assignment mutation และ database snapshot byte-equal after compose
- [ ] **GREEN:** compose references/actions จาก authorities; register `home/today` เป็น delivery เดียวของ `dailyContinuity`, gate assessment child ด้วย `researchAssessment`, ให้ child screen รับ typed use case และ Hub ไม่เขียน metric/assignment
- [ ] **VERIFY:** `flutter test --no-pub test/features/today_hub/today_hub_reader_test.dart test/screens/today_hub_screen_test.dart test/runtime/app_bootstrap_test.dart test/screens/main_navigation_screen_test.dart test/scenarios/production_feature_navigation_test.dart test/architecture/production_feature_delivery_cardinality_test.dart test/architecture/fitness_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/today_hub/domain/today_hub_models.dart lib/features/today_hub/data/drift_today_hub_reader.dart lib/features/today_hub/application/today_hub_use_cases.dart lib/screens/today_hub_screen.dart test/features/today_hub/today_hub_reader_test.dart test/screens/today_hub_screen_test.dart lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart lib/screens/main_navigation_screen.dart test/runtime/app_bootstrap_test.dart test/screens/main_navigation_screen_test.dart test/scenarios/production_feature_navigation_test.dart test/architecture/production_feature_delivery_cardinality_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(today): add canonical today hub" }`
- **Exit/Rollback:** ปิด `dailyContinuity` entry แล้วไม่มี data loss; ห้ามสร้าง TodayHub table

### f43 — Learning History

- **Source/Coverage:** `L / Partial`
- **ทำอะไร/หน้าที่:** แสดง immutable session/evidence timeline และให้ replay เป็น session ใหม่โดยไม่แก้ original
- **Authority/Dependencies:** LearningSessions, AnswerAttempts, EventsV2, AssessmentRuns หลัง v15 และ f40; f42 เป็น production parent ภายใต้ canonical `home/today`
- **Files:** Create `lib/features/history/domain/learning_history_models.dart`, `lib/features/history/data/drift_learning_history_reader.dart`, `lib/features/history/application/learning_history_use_cases.dart`, `lib/screens/learning_history_screen.dart`, `test/features/history/learning_history_reader_test.dart`, `test/features/history/learning_history_replay_test.dart`, `test/screens/learning_history_screen_test.dart`
- [ ] **RED:** ทดสอบ chronological immutable view, evidence/context versions, deleted content fallback, replay new IDs และ original rows byte-equal; ไม่มี standalone production entry
- [ ] **GREEN:** reader join canonical rows; replay สร้าง `LessonStartCommand` ใหม่ผ่าน shell และไม่ clone outcomes/rewards; f42 เป็นผู้ inject use case และเปิด child action ภายหลัง
- [ ] **VERIFY:** `flutter test --no-pub test/features/history/learning_history_reader_test.dart test/features/history/learning_history_replay_test.dart test/screens/learning_history_screen_test.dart`
- [ ] **COMMIT:** `Invoke-NativeStep { git diff --cached --quiet }`; `Invoke-NativeStep { git add -- lib/features/history/domain/learning_history_models.dart lib/features/history/data/drift_learning_history_reader.dart lib/features/history/application/learning_history_use_cases.dart lib/screens/learning_history_screen.dart test/features/history/learning_history_reader_test.dart test/features/history/learning_history_replay_test.dart test/screens/learning_history_screen_test.dart }`; `Invoke-NativeStep { git diff --cached --check }`; `Invoke-NativeStep { git diff --cached --name-only }`; `Invoke-NativeStep { git commit -m "feat(history): add immutable learning history" }`
- **Exit/Rollback:** คง G1 `implementedOff` จน f42 integration test ผ่าน; ปิด screen ได้โดยไม่มี table/drop และห้ามสร้าง LearningHistory table

**Program verification and handoff**

หลัง capability สุดท้ายของแต่ละโดเมน ให้ทำตามลำดับนี้โดยไม่รวม command ที่ timeout ยากเกินไป:

```powershell
dart run tool/feature_contract/generate_feature_map.dart --check
flutter test --no-pub test/architecture
flutter test --no-pub test/features/learning
flutter test --no-pub test/features/progress
flutter test --no-pub test/features/review
flutter test --no-pub test/features/time_tracking
flutter test --no-pub test/features/research
flutter test --no-pub test/features/assessment
flutter test --no-pub test/features/quest
flutter test --no-pub test/features/motivation
flutter test --no-pub test/features/rewards
flutter test --no-pub test/features/preferences
flutter test --no-pub test/features/accessibility
flutter test --no-pub test/features/sync
flutter test --no-pub test/features/export
flutter test --no-pub test/features/identity
flutter test --no-pub test/features/offline_content
flutter test --no-pub test/features/history
flutter test --no-pub test/features/today_hub
flutter test --no-pub test/database
flutter test --no-pub test/scenarios/complete_owner_export_delete_test.dart
npm run test:rules
flutter analyze
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-product-completion.ps1
```

Final gate ต้องบันทึก exact commit, schema/table inventory, contract revision/hash, content revisions, runtime states, rules revisions, test exit codes และ rollback drill ผลลัพธ์ ห้ามเปิด learner-facing capability จากการมี code อยู่เพียงอย่างเดียว
