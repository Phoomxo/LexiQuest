### Task PM4 — Active timer, timeout recovery and restart (16 pd)

**Requirements:** FR-120–124/127, DATA-017/018, UI-023, NFR-038/041/043, BR-031/033

**Files:**

- Extend Pair domain with injected monotonic active clock interface
- Create/update checkpoint codec under `lib/features/learning/pair_matching/data/`
- Add timeout presentation state to shared experience host; no renderer-specific timer logic
- Add `test/features/learning/pair_matching/pair_active_timer_test.dart`
- Add `test/features/learning/pair_matching/pair_timeout_recovery_test.dart`
- Add `test/features/learning/pair_matching/pair_timeout_race_test.dart`

**Steps:**

1. เขียน fake-clock tests สำหรับ off/60/90/120 และยืนยัน timer ไม่ auto-enable จากรอบก่อน;
2. นับ active interaction เท่านั้น; pause/resume ด้วย reason set ที่อ้างอิงได้สำหรับ background/modal/persistence/accessibility narration;
3. timeout สร้าง durable decision state โดยไม่สร้าง incorrect/completion;
4. Continue untimed ใช้ state/evidence เดิม; +30 idempotent หนึ่งครั้งต่อ Learning Session; Restart สร้าง round/seed ใหม่แต่ exact content/revisions/direction เดิม;
5. serialize answer-timeout-extension-restart race และ persist entitlement/evidence ก่อน acknowledgement;
6. kill/relaunch/lost-ack tests ต้อง restore exact decision โดยไม่ reset clock/evidence;
7. รัน `TC-PMT-025–031` และ checkpoint write-budget proof

**Exit:** timer neutral and recoverable; no per-tick durable write; timeout never forces failure or reward/mastery change
