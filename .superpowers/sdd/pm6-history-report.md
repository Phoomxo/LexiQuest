# PM6 Pair History handoff

วันที่ 2026-09-06 บน worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest` branch `codex/pair-matching-pm0-pm8`

## ผลลัพธ์

- เพิ่ม optional `PairMatchingSessionPurposeReader` ให้ `LearningHistoryUseCases` และ `loadPairResults` สำหรับ session IDs ที่หน้าจอแสดงอยู่
- Pair read deduplicate/canonicalize IDs, ยืนยัน active owner ก่อนและหลังอ่าน, รับเฉพาะ snapshot ที่ owner/session ตรงและ terminal acknowledged แล้ว, ข้าม legacy matching ที่ไม่มี Pair snapshot และ fail closed สำหรับ unknown/malformed Pair
- เพิ่ม Pair-specific History card ที่ใช้ `PairMatchingHistoryOverview` แยก latest/best ของรอบปกติจาก latest/best ของ Practice Replay ตาม direct source
- แสดง full interactive elapsed แบบตรงไปตรงมา: `null` เป็น unavailable และ `0` แสดง 0 วินาทีจริง
- Pair replay ใช้ typed `onPairReplay(PairMatchingHistoryProjection, replayOperationId)` เท่านั้น เก็บ operation ID เดิมเมื่อ acknowledgement ไม่แน่นอน และไม่เรียก generic `replayAsNewSession`
- เมื่อไม่มี callback หรือ Pair projection ยืนยันไม่ได้ จะแสดง replay unavailable และปิด action; ปุ่มสูงอย่างน้อย 48 px พร้อม copy ไทย/อังกฤษที่ไม่ตัด ellipsis
- generic non-Pair History cards และ generic replay flow เดิมยังคงทำงาน

## Exact write set

- `lib/screens/learning_history_screen.dart`
- `lib/features/history/application/learning_history_use_cases.dart`
- `test/screens/learning_history_screen_test.dart`
- `.superpowers/sdd/pm6-history-report.md`

## TDD evidence

- RED: `.superpowers/sdd/pm6-history-red.log` — test โหลดไม่ผ่านตามคาดเพราะยังไม่มี `pairReader`, `loadPairResults` และ `onPairReplay`; พบ test fixture ขาด import `PairCuratedAllowlist` เพิ่มเติม
- GREEN รอบแรก: `.superpowers/sdd/pm6-history-green.log` — 6 ผ่าน / 5 ล้มก่อนเข้า History behavior เพราะ fixture ใช้ checksum ปลอม
- Fixture correction: เปลี่ยนเป็น canonical lexical fixture ที่คำนวณ content checksum จริง และปิด in-memory DB ด้วย `try/finally`
- GREEN รอบสอง: `.superpowers/sdd/pm6-history-green2.log` — 9 ผ่าน / 2 ล้มเพราะ test MaterialApp resolve locale ไทยกลับเป็นอังกฤษ
- Locale correction: เพิ่ม test-only Material/Widgets/Cupertino delegates สำหรับ `th/en`; repo ไม่มี `flutter_localizations` dependency จึงไม่แก้ `pubspec.yaml` นอก scope
- GREEN รอบสาม: `.superpowers/sdd/pm6-history-green3.log` เป็นหลักฐาน regression ก่อนเพิ่ม delegates; รอบสี่ `.superpowers/sdd/pm6-history-green4.log` เหลือ 1 assertion ที่พึ่ง eager build ของ ListView
- Lazy-list correction: scroll ไปยังแต่ละ Pair card ก่อนตรวจ badge, lineage, disclaimer และ elapsed โดยคง behavioral assertions เดิม
- GREEN สุดท้าย: `.superpowers/sdd/pm6-history-green5.log` — focused screen suite **11 tests ผ่านทั้งหมด** (`All tests passed!`)
- `git diff --check` ของ source/test write set ผ่าน; มีเฉพาะคำเตือน working-copy LF/CRLF จาก Git

## ข้อจำกัดและงานส่งต่อ

- Parent เป็นเจ้าของการประกอบ real Pair Practice Replay callback เข้ากับ host/runtime; task นี้ทดสอบ typed boundary และ canonical reader fixtures แต่ยังไม่อ้างว่า route composition แบบ end-to-end ผ่าน
- ไม่ได้รัน repository-wide regression, analyzer หรือ formatter ใน task นี้ตามข้อกำหนดให้ serialize tooling; final formatting ถูกเลื่อนไปให้ parent

หลังรายงานนี้คืน ownership ของ source, tests และ tooling ทั้งหมดให้ `/root/pm6_implementation`; ไม่มี process ที่ค้างจาก task นี้
