### Task PM5 — Stars, results, history and Practice Replay isolation (14 pd)

**Requirements:** FR-125–129, DATA-018/020/021, UI-024/025, NFR-038/041, BR-032/033

**Files:**

- Create `lib/features/learning/pair_matching/domain/pair_star_policy.dart`
- Create `lib/features/learning/pair_matching/presentation/pair_matching_result_view.dart`
- Extend existing history read model through a typed Pair projection
- Add `test/features/learning/pair_matching/pair_star_policy_test.dart`
- Add `test/features/learning/pair_matching/pair_practice_replay_test.dart`
- Extend `test/features/history/learning_history_replay_test.dart`

**Steps:**

1. เขียน table-driven boundary tests สำหรับ 3 ดาว, 3/4, 5/6, 4/6, guided tail และ incomplete;
2. derive จาก committed immutable ledger + `starPolicyVersion`; cached valueเป็น rebuildable read modelเท่านั้น;
3. แสดง matched/independent/assisted/stars/timer/elapsed/Review next แยกแกน ไม่มี combined score;
4. Practice Replay สร้าง session purpose ใหม่, exact valid content, shuffle ใหม่และ immutable source link;
5. เขียน before/after projection harness ครบ SRS/Mastery/Weakness/global accuracy/XP/reward/quest/streak/achievement/Today/research-primary และบังคับ delta=0;
6. History group/label replay; latest/best normal ไม่ถูก overwrite;
7. รัน `TC-PMT-032–041` และ reward/history/Today regressions

**Exit:** stars reproducible/non-economic, incomplete unscored, replay visible but zero-authority/reward effect
