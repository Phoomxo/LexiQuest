### Task PM3 — Delayed repair, semantic support and Review handoff (13 pd)

**Requirements:** FR-116–119, DATA-017/021, UI-022, NFR-038/041/043/044, BR-028–030

**Files:**

- Create `lib/features/learning/pair_matching/domain/pair_repair_policy.dart`
- Extend `pair_matching_engine.dart` and coordinator
- Add typed Review deferral adapter near existing Review/SRS application boundary
- Add `test/features/learning/pair_matching/pair_repair_policy_test.dart`
- Add `test/features/learning/pair_matching/pair_support_classification_test.dart`
- Add `test/features/learning/pair_matching/pair_review_deferral_test.dart`

**Steps:**

1. เขียน failing schedule fixtures: compact after 2 distinct correct other pairs, standard after 3, same-pair/non-answer not counted;
2. stable-order concurrent repair tickets by due ordinal/original ordinal/canonical ID;
3. wrong repair ซ้ำไม่สร้าง recursive queue; one unresolved canonical Review need ต่อ word/source evidence;
4. เมื่อ spacing ไม่พอ ให้ guided-complete อย่างโปร่งใสและ defer independent retry ไป Review โดยไม่ padding;
5. classify pronunciation/visible TalkBack as neutral; classify semantic reveal/corrective mapping as guided;
6. เมื่อ audio missing/offline/private remote disallowed ให้ text/IPA fallback และ board ทำงานต่อ;
7. รัน `TC-PMT-017–024`, SRS/Weakness/Review ownership regressions และ payload redaction tests

**Exit:** repair spacing exact, tail finite, no penalty/padding, Review receives one valid need, hint classification audit-ready
