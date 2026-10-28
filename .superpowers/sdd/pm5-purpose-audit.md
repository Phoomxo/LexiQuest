# PM5 purpose/research advisory audit

2026-09-05. Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`. ตรวจแบบ read-only ตาม bounded assignment; เขียนเฉพาะรายงานนี้ ไม่มี source edits, Flutter/Dart/test/scan หรือ Git mutation และไม่มี task-owned running process. อ่าน active AGENTS.md, pm5-integration-brief.md และ pm5-preflight.md แล้ว รายงานนี้ไม่ใช่ final PM5 acceptance.

## ข้อค้นพบที่ยืนยันจากโค้ด

**[P2] Purpose decoder ยอมรับ terminal metadata ของ checkpoint envelope v2 ที่ canonical parser ปฏิเสธ** — `lib/features/learning/pair_matching/domain/pair_matching_session_purpose.dart:61` และ `:76`.

Decoder ตรวจชื่อ/จำนวน outer keys แต่ legacy branch (บรรทัด 61–64) ส่งเพียง `state` เข้า legacy validator แล้ว `continue` โดยไม่ตรวจ `terminalAtUtc` หรือ `terminalAcknowledged`. ดังนั้น checkpoint ที่ state schema 1–5 และ envelope/owner/key อื่นถูกต้อง ยังคืน ordinary learning authority แม้ envelope v2 มี `terminalAtUtc: 42`, `terminalAcknowledged: "bad"` หรือ `terminalAcknowledged: true` พร้อม `terminalAtUtc: null`. สำหรับ v6 initial checkpoint ที่ envelope v2 มี `terminalAcknowledged: null` ก็ผ่านบรรทัด 76 เพราะ `?? false` แปลง null เป็น false. ทั้งหมดเป็นการเปลี่ยน outer terminal fields ของ checkpoint เดิม ไม่ต้องแทนที่ plan/history ทั้งชุด.

Canonical parser ใน `lib/features/learning/data/drift_learning_repository.dart:1207`–`:1225` กำหนดว่า v2 acknowledgement ต้องเป็น bool, terminal timestamp ต้องเป็น null หรือ UTC string ที่ parse ได้และลงท้าย Z, และ acknowledgement=true ต้องมี timestamp. Shared purpose decoder จึงยอมรับ metadata เสียรูปซึ่ง canonical recovery ปฏิเสธ แล้ว `allowsLearningAuthority` ถูกใช้โดย reconcile (`motivation_measurement_use_cases.dart:175`), direct attach/complete (`drift_measurement_opportunity_repository.dart:223`, `:324`) และ mission upload (`drift_research_sync_authorizer.dart:691`).

ข้อแก้ที่แคบ: ตรวจ v2 terminal fields ก่อนแยก legacy/v6 ด้วย contract เดียวกับ canonical parser และคง v1 absence semantics. Acceptance ที่ผู้เขียนควรเพิ่ม: malformed legacy v2 terminal types/ack-without-time และ v6 initial v2 acknowledgement=null ต้องถูกปฏิเสธทั้ง pure decoder และอย่างน้อยหนึ่ง research boundary; valid legacy/v6 controls ต้องยังใช้ได้. ยังไม่ได้ execute mutation/test ตามข้อห้ามของ assignment.

## ขอบเขตและข้อจำกัด

ไม่พบข้อบกพร่องเพิ่มเติมที่ยืนยันได้จาก static inspection ใน all-missing/unknown matching admission, 6→5 state-shape downgrade, foreign envelope identity, missing/duplicate/gapped revision prefix, immutable start/plan/config/owner binding, legacy rehome actor/key with inactive `mergedInto:<currentOwner>`, purpose-before-idempotent-return สำหรับ attached/completed replay หรือ tracked checkpoint/historical-owner reads รอบ external permit await. `_Reads.all` บันทึกทั้ง ordered full-row query results รวม absence และ authorizer เปรียบเทียบก่อน/หลัง; ข้อความนี้เป็นการอ่านโค้ด ไม่ใช่ผล TOCTOU test.

อ่านเฉพาะ pure purpose decoder/Drift reader, research reconcile/watch/direct opportunity admission, mission authorizer/snapshot/_Reads, accepted legacy shape decoder, checkpoint codec decode/transition และ start-envelope binding. เพิ่ม bounded read ของ canonical `_latestActivityCheckpoint` terminal parser หลังแจ้ง root ถึงความเสี่ยง malformed envelope แล้ว. ไม่ตรวจ PM5 UI/zero-delta matrix, PM8 v6 owner rehome, deployment, physical device หรือ real research rollout. ไม่อ้างผล 96 regression/4 TOCTOU ที่ worker รายงานเป็น evidence ของ audit นี้.

## Snapshot evidence

แปด source files ด้านล่างมี SHA-256 เดิมที่อ่านเมื่อ `2026-09-05T14:38:52Z`, `14:41:31Z` และตรวจท้าย `14:43:15Z`; ไม่พบ source change ระหว่างช่วงตรวจ. ไฟล์ canonical repository ที่อ่านเพิ่มมี hash ก่อน/หลังตรงกันเมื่อ `14:41:48Z`. หาก source เปลี่ยนภายหลัง ต้องตรวจ/ทดสอบ snapshot ใหม่โดยเจ้าของ PM5 ก่อน final acceptance.

| File | SHA-256 |
| --- | --- |
| `lib/features/learning/pair_matching/domain/pair_matching_session_purpose.dart` | `2FFE56A3C7D2D8F2D6E333DFF19BCB9E46C524C3CE557BA82329F9D9FE8B1077` |
| `lib/features/learning/pair_matching/data/drift_pair_matching_session_purpose_reader.dart` | `EA4E6C083BCF674DEE1135850C51905763C59F1739ADD0619DA314910844B65E` |
| `lib/features/research/application/motivation_measurement_use_cases.dart` | `30D3149ACF718FFB77174472FB8D49F429A57A48224AA979462EA849DB28D39C` |
| `lib/features/research/data/drift_measurement_opportunity_repository.dart` | `3B1D2B9FC4CE6601D292079222CEB55A829B92CCE5F2489578C9AA15160D49D8` |
| `lib/features/research/data/drift_research_sync_authorizer.dart` | `525D7F68DE63A1AFE1D1729EA5E26DB2BDFDE755EC4F41174A07C75C23CF0B9A` |
| `lib/features/learning/application/matching_mode_adapter.dart` | `C19F391AD71AA2E6B4E67EDD162EF6EE12E04E7A2A5E072F088C16F01A8EB2C8` |
| `lib/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart` | `794B0990C5735BC81FE48CFE79DA75E3A8517ABCBB86A37E0C74ADF247CFE2D8` |
| `lib/features/learning/pair_matching/application/pair_matching_atomic_start.dart` | `1D55984EC9715BC9397811EF3D18CB694F11C1490469CDE2B981CF67E73A314D` |
| `lib/features/learning/data/drift_learning_repository.dart` (bounded parser comparison only) | `03CD92DA99C104713ACEBB466AB8B29D5F3C3C8292EFACD7B5577BA7E037D0F7` |

ขั้นถัดไป: PM5 owner เพิ่ม focused RED mutations ข้างต้น แก้ shared decoder และรัน focused purpose/research checks โดยไม่ให้ writer อื่นเปลี่ยน inputs ระหว่าง verification.

## Advisory closure หลังแก้เฉพาะข้อค้นพบ

`2026-09-05T14:45:40Z`: root มอบหมาย narrow recheck หลัง worker แก้ source. อ่านเฉพาะ `pair_matching_session_purpose.dart` ปัจจุบันและยืนยันว่าเงื่อนไขบรรทัด 60–64 ตรวจ envelope v2 ก่อนทั้ง legacy/v6 branch: acknowledgement ต้องเป็น bool, terminal ต้องเป็น null หรือ UTC string ที่ลงท้าย Z และ parse ได้, และ acknowledgement=true ต้องมี terminal. เส้นทาง malformed legacy timestamp/acknowledgement และ v6 null acknowledgement ในข้อค้นพบเดิมจึงถูกปฏิเสธจากโค้ดปัจจุบันแล้ว **ปิด P2 นี้ในระดับ advisory static review**; ไม่มีข้อค้นพบใหม่จากการตรวจซ้ำที่จำกัดนี้.

SHA-256 ใหม่ของ decoder: `E18992E4F905DC9E9610FA2B4C1781457B2769F46EDA4107574572CB0E64C34F`; ก่อน/หลัง read ตรงกัน, file last-write `2026-09-05T14:44:26.3811135Z`. Source change จาก snapshot แรกเป็นการแก้ที่คาดไว้และแจ้ง root แล้ว. ไม่รัน/อ่าน test logs ใน follow-up นี้; ผล RED2/GREEN10 เป็นข้อมูลที่ root ส่งมา ไม่ใช่ independent execution evidence ของ auditor. Root ยังต้องทำ independent final PM5 review และ verification บน source สุดท้ายตามเดิม.
