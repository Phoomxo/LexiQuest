### Task PM2 — Pure reducer, selection and evidence roles (10 pd)

**Requirements:** FR-107/113–115, DATA-016/017, NFR-038/039/041, BR-028

**Files:**

- Create `lib/features/learning/pair_matching/domain/pair_matching_engine.dart`
- Create `lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart`
- Extend the existing matching adapter only behind typed M12 interfaces
- Add `test/features/learning/pair_matching/pair_matching_engine_test.dart`
- Add `test/features/learning/pair_matching/pair_matching_idempotency_test.dart`
- Add `test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart`

**Steps:**

1. เขียน transition table tests สำหรับ select/deselect/reselect ทั้งสองฝั่งและ duplicate operation ID;
2. ทำ reducer ให้ pure: state + command → state + effects; UI ห้ามเขียน repository ตรง;
3. correct เพิ่ม matched pair ครั้งเดียว; mismatch ไม่เพิ่ม/ลด matched progress;
4. attach incorrect recognition ครั้งเดียวกับ prompt-side canonical word; distractor ไม่รับ incorrect evidence;
5. persist first-opportunity/attempt-role ledger ด้วย operation identity และ coalesced checkpoint boundary;
6. fence stale callback/owner change/rebuild และ reserve terminal revision;
7. รัน `TC-PMT-013–016` พร้อม Unified Lesson/Evidence Gateway regressions

**Exit:** deterministic reducer, monotonic matched progress, no duplicate/lost attempt and no presentation write path
