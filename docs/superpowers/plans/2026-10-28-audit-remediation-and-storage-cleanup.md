# แก้ audit และจัดรุ่นไฟล์เพื่อลดพื้นที่

วันที่ 2026-10-28. ผู้ใช้อนุมัติแก้ทั้ง 20 ประเด็น แล้วอัปเดตชุดงาน จัดระเบียบ และลบเวอร์ชันเก่าตามลำดับ.

## Outcome and authority

- แก้ตามรายงาน audit ที่ผูกกับ `6500cbf399083b872f8c8337c560ffb177297485` โดยใช้ worktree เดิม `C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest` เพื่อลดการทำสำเนาเพิ่ม.
- เก็บ tag/artifacts `1.0.0+18` เป็น baseline. ไม่ทับงานใน primary checkout หรือ `lexiquest-current` ซึ่งมีงานที่ยังไม่ commit.
- งานนี้ไม่อนุญาต deploy, enroll/upload ข้อมูลวิจัยจริง, แก้ guardrails, ลบ credentials/signing keys, หรือข้อมูลบริการ.
- ลบได้เฉพาะ exact allowlist ที่ตรวจผู้ใช้/process, tracked status, ความซ้ำ/การกู้คืน และ resolved absolute path แล้ว. ไม่ retry cleanup ที่เคยถูก policy ปฏิเสธผ่านกลไกอื่น.

## Throughput checkpoint

1. Blocking first steps. อ่าน source/checkpoint/audit, ยืนยัน working sets และบันทึกพื้นที่ C/D ก่อนเริ่ม.
2. Independent workstreams. Backend, app, tooling/LM แยก write sets; root รับผิดชอบ sync/identity/research และ integration/cleanup.
3. Shared mutable state. Root เป็นผู้เดียวรัน Flutter/build/codegen และ emulator tests. Python แยก per-service. หยุด writers ก่อน full regression.
4. Smallest safe decomposition. แก้ authority เดิมและเพิ่ม regression เฉพาะเคส ไม่เพิ่ม framework หรือย้าย schema โดยไม่มีเหตุจำเป็น.

## Work board

| Card | Audit IDs | Owner/write set | Acceptance | State |
| --- | --- | --- | --- | --- |
| BACKEND | 4,5,6,9,10,16 | fix_backend; backend/ai_api, backend/voice_api | chunked/malformed body, cache case, quota fallback, real retention, msgpack fixed lock, strict CI GREEN | Done; AI186/Voice64 |
| APP | 3,7,8,11 | fix_app; Shadowing/Reading, learning restore, progress counts, vocabulary lifecycle + tests | lost ack exactly once, resume honest/repeatable, deleted counts 0, safe revive logical row | Done; focused43 |
| TOOL-LM | 13,14,18,19,20 | fix_tooling_lm; CI, two CLI tests, Firestore rules/tests, LM generator/dry-run/tests | native JSON mutations, existing contracts in CI, closed legacy grants, correct grammar/features | Done; CLI23/LM83/rules39 |
| DATA | 1,2,12,15,17 | root; sync/identity/research + tests | owner isolation, deterministic natural-key reconciliation, bounded backlog drain, late-state merge, expiry recheck | Done; focused126 |
| VERIFY | all | root with independent read-only review | focused RED/GREEN then full Flutter/backend/policy/contracts/analysis + final diff | Flutter1851/analysis0 pass; Android build pending |
| ORGANIZE | current source/docs/artifacts | root | current version index and exact retained artifact manifest; no historical evidence rewritten as new PASS | Done; source index and retention manifest written |
| CLEANUP | superseded recoverable files only | root | exact approved candidates, no unique WIP/active or pinned work removed, actual free-space delta and receipts | Pending |

## Verification

- Promote the synthetic audit probes into scoped repository regressions. The existing baseline passed 1811 tests, but the new probes exposed missing behavior; those cases must go GREEN.
- Run Flutter serially. Backend CPU suites use existing service runtimes. Dependency lock changes use the normal resolver and are checked afterward.
- Run Firestore/Auth emulators only against demo projects, existing CLI contract suites, static analysis and a current-source review.
- Keep production release gates closed when contacts, human UAT, App Check/Play, infrastructure or research authority remain absent.
- Store new logs and inventory under `D:\LexiQuest-Storage\maintenance\2026-10-28` to limit C: growth.

## Organize before deletion

1. Record one current-source entrypoint and a retention index for source, baseline release, new test evidence, and historical archives.
2. Inventory worktrees and generated outputs by Git status, branch reachability, usage and measured size. Pinned primary checkout is retained.
3. Preserve all unique uncommitted/untracked source and meaningful evidence. Do not infer that older dates mean obsolete.
4. Remove only exact, validated superseded generated copies or recoverable clean inactive worktrees after the preceding cards complete.
5. Keep the previously denied source-removal paths from the 2026-10-26 migration out of the execution allowlist. Record that hold separately and pursue other eligible space savings.

## Completion evidence

Final checkpoint records changed files, tests with exact results, review disposition, retained/removed paths, released bytes and remaining dependencies. No full-completion claim until the source and storage predicates are verified.
