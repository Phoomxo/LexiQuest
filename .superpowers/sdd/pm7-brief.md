### Task PM7 — Adventure renderer parity and bounded measurement (8 pd)

**Requirements:** FR-108/129/130, DATA-021, UI-027, NFR-044/045/046, BR-034

**Files:**

- Create `lib/features/adventure/presentation/adventure_pair_renderer.dart`
- Add `test/features/adventure/adventure_pair_renderer_parity_test.dart`
- Add/update research event projection tests only if Pair is inside an approved participant opportunity
- Add `test/features/learning/pair_matching/pair_measurement_boundary_test.dart`

**Steps:**

1. render the same immutable plan/ViewModel; permit only theme, companion, narrative and return-target differences;
2. normalize IDs/timestamps then compare commands, attempts, repair, timer, stars, evidence and terminal outcome against Standard;
3. participant uses neutral existing mission events/opportunity; restart/rebuild does not add denominator;
4. Practice Replay excluded from primary outcome and nonparticipant research row/outbox/upload stays zero;
5. bounded diagnostics omit raw word/meaning/DOB/guardian text and obey owner/retention policy;
6. simulate renderer failure/Adventure-off and continue through Standard with same checkpoint;
7. รัน `TC-PMT-038/042–044` และ UAT-050 rehearsal

**Exit:** normalized parity 100%, zero nonparticipant research rows, zero replay primary delta, safe Standard fallback
