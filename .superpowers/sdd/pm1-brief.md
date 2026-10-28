### Task PM1 — Entry-aware immutable plan and safe source composer (8 pd)

**Requirements:** FR-106–112, DATA-016/019, UI-018, NFR-038/039/044, BR-025–027

**Files:**

- Create `lib/features/learning/pair_matching/domain/pair_matching_launch.dart`
- Create `lib/features/learning/pair_matching/domain/pair_matching_plan.dart`
- Create `lib/features/learning/pair_matching/application/pair_matching_source_composer.dart`
- Modify only through typed adapters: Today/Review/Learn launch owners identified in PM0
- Add `test/features/learning/pair_matching/pair_matching_plan_test.dart`
- Add `test/features/learning/pair_matching/pair_matching_source_composer_test.dart`
- Add `test/features/learning/pair_matching/pair_matching_source_property_test.dart`

**Steps:**

1. เขียน failing fixtures สำหรับ Learn overlap, fixed Today snapshot, selected Review list และ Adventure pass-through;
2. นิยาม closed enums สำหรับ entry, direction, density, timer และ typed unavailable/confirm outcomes;
3. compose โดย merge provenance → deduplicate canonical identity → revalidate locale/revision/checksum/report/delete/collision → rank → exact select;
4. ใช้ curated EN–TH allowlist; ห้ามเพิ่ม sense table หรือ remote lookup เพื่อเติม plan;
5. resolve density จาก guardian product policy ก่อน learner preference; unknown prompt ครั้งเดียว/fallback 4; 6→4 ต้อง explicit accept; <4 ไม่ start;
6. สร้าง Learning Session + initial checkpoint แบบ atomic หลัง owner/source revalidation และ pin fingerprint/order/seed/version;
7. รัน `TC-PMT-002–012`, owner-switch/crash-injection และ Today single-load regressions

**Exit:** same pinned inputs ให้ plan/fingerprint เดิม; exact 4/6; zero session/evidence on unavailable/cancel; Adventure cannot recompose
