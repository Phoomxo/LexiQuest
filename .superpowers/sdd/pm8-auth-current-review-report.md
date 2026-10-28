# Spec Compliance — Issues Found

- ❌ **Issues Found:** I1 ยังปิดไม่ครบ: discriminator ของ legacy1–5 ยังข้าม validation ของ checkpoint ที่มีอยู่แต่เสียรูปแบบ (`lib/features/identity/data/drift_owner_upgrade_repository.dart:588`). I2 destination lifetime แก้ตรงข้อกำหนดแล้ว (`lib/features/learning/pair_matching/domain/pair_matching_session_purpose.dart:295`).
- ⚠️ Verdict นี้จำกัด four-file uncommitted authentication/capacity snapshot; repository/coordinator/host admission, stale leases, tracked research-await invalidation, durable reopen/retry, terminal/export/deletion และ alias projection ยังต้องผ่าน integration review ของ root/main. ไม่ใช่ whole-PM8/G4P/release หรือ production activation approval.

## Strengths

- `drift_owner_upgrade_repository.dart:144`, `:215`, `:500`, `:359`: preflight อยู่ก่อน category remap ใน transaction เดิม; terminal sessions อ่านเป็นหน้า; destination byte reserve ตรวจทั้งก่อน cutover และหลังย้าย rows. Pinned zero-answer words เข้าสู่ preservation และ collision fence เดิม (`:1043`, `:1096`) โดยไม่สร้าง authority/schema ใหม่.
- `pair_matching_session_purpose.dart:95`, `:197`, `:227`, `:254`: checkpoint key มาจาก stored actor, revision1 ยังคง P, prefix/transition และ durable reservations ถูกตรวจครบก่อนใช้ latest snapshot. Owner query รวม R, P และ frozen/checkpoint actors (`:430`).
- **I2 resolved:** `pair_matching_session_purpose.dart:295` เพิ่ม `currentCreated > upgraded` เป็น rejection โดยยังอนุญาต plan เกิดก่อน R ได้เมื่อ merge เกิดหลัง R ถูกสร้าง. Actual positive/negative fixture (`pair_matching_owner_upgrade_auth_test.dart:454`) และ direct-link rewrite control (`:748`) ตรวจ semantics นี้อย่างเหมาะสม.
- `pair_matching_session_purpose.dart:322`, `:362`: owner-only configuration projection ส่งครบทุก constructor field และเทียบทั้ง serialization/identity. Named cross-check `lib/features/learning/domain/session_configuration.dart:325` ตรงกัน.
- `pair_matching_checkpoint_codec.dart:344`, `:433`, `:440`, `:458`: reserve วัด encoded destination R จริง และเลือก max ระหว่าง historical pending bytes กับ future bound; historical frozen schema bound ใช้ frozen actor ของตัวเอง. Identifier scalar bound/event-second flooring ที่ `lib/features/learning/domain/learning_evidence_contract.dart:18`, `:30` รองรับเหตุผลด้าน Unicode และ precision. ไม่พบ defect ใหม่ใน fractional timestamp preservation หรือ same-owner reserve จากขอบเขตนี้.

## Issues

### Critical

- ไม่พบใน snapshot ที่ตรวจ.

### Important

1. **I1 continuation — schema marker alone still admits malformed present checkpoints.** `lib/features/identity/data/drift_owner_upgrade_repository.dart:568–588` ตรวจเพียงว่า `state` เป็น Map และ `schemaVersion` อยู่ใน1–6; ถ้าเป็น1–5และไม่มี `plan`/`startOperation` จะคืน `null` โดยไม่เรียก shared decoder. Concrete trigger: ใน existing actual accepted-Pair/category-only fixture แทน sole checkpoint `payload_json` ด้วย `{"state":{"schemaVersion":1}}` (หรือ2–5) โดยคง canonical session/config/event row เดิม. Payload นี้ไม่มี valid checkpoint envelope หรือ legacy state แต่ผ่าน discriminator. Session ไม่เข้า `pairPins`, ไม่มี word collision ให้ legacy fence ตรวจ และ postflight วนเฉพาะ `pairPins.sessionIds`; จึงมีเส้นทาง remap/rehome ที่ไม่ตรวจ payload เสีย. เป็น source-proven validation gap; reviewer ไม่ได้รัน reproduction และ GREEN169 ไม่มีกรณีนี้.

   แก้โดย validate nonempty legacy checkpoint chain/envelope/state ด้วย shared `PairMatchingSessionPurpose.decode` หรือ validation เดิมที่ครบก่อนจัดเป็น valid legacyและคืน `null`; รักษา empty-checkpoint policy และ valid legacy1–5 semantics. เพิ่ม focused RED/GREEN อย่างน้อย minimal malformed payload ข้างต้น และ valid outer envelope ที่ legacy state ไม่ครบ; เทียบ owner/category/word/session/attempt/event/outbox snapshot ว่า rollback. คง positive controls ของ valid legacy1–5/no-checkpoint และ I2/direct-multihop. Existing corruption matrix (`test/features/learning/pair_matching/pair_matching_owner_upgrade_auth_test.dart:426`) มี `{`, `[]`, `{}`, unsupported7 จึงยังไม่ครอบคลุม supported-version marker ที่รูปแบบเสีย.

### Minor

1. **Covering test output ยังมี Drift warnings 9 ครั้ง.** `.superpowers/sdd/pm8-finalize-auth-25690907T094538465.log:69` และอีก8ตำแหน่งแจ้ง multiple AppDatabase instances; first trace ชี้ unchanged `test/features/identity/drift_owner_upgrade_repository_test.dart:917`. Root ระบุเป็น inherited warnings; reviewer ยืนยัน warning count/trace แต่ไม่ได้ตรวจ baseline history หรือ executor ownership. ให้ root ติดตาม fixture lifecycle และแยกจาก auth regression; ไม่ควรอ้าง output pristine หรือเพิ่ม blanket warning suppression เพื่อให้เงียบ.

## Checked evidence

- Scope identity ตาม supplied brief/metadata: worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`, base `3bdb5f5605e670e8b30628f3f237cd9c0d660ad9`. Head เป็น uncommitted source snapshot; reviewer ไม่รัน Git commands และไม่สมมติ head commit.
- อ่าน full `pm8-auth-current-review.diff` ครบครั้งเดียว แบ่ง output ไม่ทับกัน; packet 76840 bytes, SHA256 `4b19247aa7ef4d8ef56efac031ef811aa482faac7ce87246a1525e5ad6abf24b`. ตรวจ actual four-file hashes ตรง manifest:

| File | SHA256 |
| --- | --- |
| `lib/features/identity/data/drift_owner_upgrade_repository.dart` | `c45122c0769b6a02aa922462a57310f374b26c5908786f7f04dfb03c2bd8bd44` |
| `lib/features/learning/pair_matching/domain/pair_matching_session_purpose.dart` | `9d723edefe165935edaa38ddf5b9f9a59d262e58d1e0d648ff6d02b04979fa96` |
| `lib/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart` | `9f0cef206f69b58f24e703d6e001be980d5bcfbdaa0a08f6f0371071e82feac5` |
| `test/features/learning/pair_matching/pair_matching_owner_upgrade_auth_test.dart` | `6dfb62651a81d60faf583e0960306fb9125bf9fdea711487a7c422c9291281b8` |

- Focused continuations เพราะ diff ตัดกลางฟังก์ชัน: purpose envelope/transition `:35–173`, `:214–250`; codec reserve/pending decode `:359–432`, `:583–660`; owner TX ordering `:90–214`, `:295–373`. ไม่ reread changed files ทั้งไฟล์.
- Named external boundaries: identifier/event precision และ configuration constructor ข้างต้น; unchanged `drift_pair_matching_session_purpose_reader.dart:13`, `:38`, `:50` ใช้ expanded owner query และ decode ใน transaction จริง. External-await tracked consumers อยู่นอก frozen packet จึงยังไม่อนุมานว่าผ่าน.
- ตรวจ fresh metadata `.superpowers/sdd/pm8-finalize-auth-25690907T094538465.metadata.json` และ paired log: executable `C:/Users/Phet/AppData/Local/Programs/flutter/bin/flutter.bat`; argv `test --no-pub --reporter expanded test/features/learning/pair_matching/pair_matching_owner_upgrade_auth_test.dart test/features/learning/matching_mode_adapter_test.dart test/features/learning/pair_matching/pair_matching_session_purpose_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart`; cwd ตรง worktree; start `2026-09-07T02:45:38.4673867+00:00`, end `2026-09-07T02:45:58.3088751+00:00`, duration19.8414884s, exit0, log`:337` แสดง `+169: All tests passed!`. ผลนี้มี nine Drift warnings ตาม Minor ข้างต้นและยังไม่ครอบคลุม I1 continuation.
- Reviewer ไม่รัน Flutter/Dart/tests/scanners; ไม่แก้ source/index/Git และไม่มี reviewer process ค้าง. เขียนเฉพาะรายงานนี้; prior `pm8-auth-review-report.md` คงเดิม. Analyzer/full branch/release checks ไม่ได้ตรวจในงานนี้.

## Assessment

**Task quality: Needs Fixes.** I2 และ auth/capacity ส่วนที่ตรวจสอดคล้อง contract แต่ I1 ยังมี malformed supported-version bypass ที่ควรแก้พร้อม focused rollback regression ก่อน auth subset นี้ผ่าน. ให้ re-review เฉพาะ corrective diff และผล RED/GREEN/current hashes ใหม่โดยคงขอบเขตนี้.
