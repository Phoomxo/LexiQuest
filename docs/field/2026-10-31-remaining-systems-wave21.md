# Wave21: Review Center และการอ่านข้อมูลผูกเจ้าของ

Updated2026-10-31. Local Review Center engineering is attested on source
a54ac2e2e1b569a3656cc3300e094f1391c45203, branch
codex/remaining-system-readiness, worktree cycle12-release. Raw UTC timestamps
remain those of the executed checks, which began2026-10-30.
The763-Dart freeze SHA is b1b40ccd9d3e8c60c359a22407cea1405661930c9bfb7a5df41da9729037d636.
Lib tree2d20b0fbdb61d7804c5e5a55fc3d7e86dc55ef3f;
test tree6b92dd5fa4d86f27e81e95709a2583bfa913a77d.
Historical first source c650a4f197646cae852c9bdd313aa1f89baa07dc and its failed
full run remain retained. The current attestation has a separate a54 freeze and receipts.

Schema **v20/37 tables**, v21+ ยังไม่จอง; frozen8/44 และ
EvidenceContext/EventEnvelopeV2 คงเดิม. ไม่มี dependency, Research authority,
learning/reward writer, sync payload หรือ persistent queue ใหม่.

## Completed current-source gates

| Gate | สถานะ/หลักฐานจริง |
| --- | --- |
| Historical c650 source freeze | c650a4f197646cae852c9bdd313aa1f89baa07dc;763 Dart; manifest SHA7bd1f494fde7729949c0178262e848433281a1bcacefe6c1eac5806bea4fd0f2 |
| Analysis ของ c650 (historical) | 0 issues/17.2s; wave21-analyze-final.log SHA6609db46e5c30ac3ab1963259f48c9fac20b12ec71ed65309a78c747e6f789de |
| Current analysis ของ a54 | 0 issues/18.3s; wave21b-analyze-final.log SHAc83e9721b763713412bfcb055932771a0a9493c2d772a9f9e02e1a6d57f9331a |
| Current corrected source/freeze | a54ac2e2e1b569a3656cc3300e094f1391c45203;763 Dart; wave21b-frozen-dart-source-final.json SHAb1b40ccd9d3e8c60c359a22407cea1405661930c9bfb7a5df41da9729037d636 |
| Full Flutter terminal count/duration/exit | Actual4461PASS/0FAIL,11m32s,exit0; sourceAfterVerified=true. wave21b-full-flutter-final.log SHAd0649eb50820ce4311ca14d258bc79b2176fa6363a8f02ec8feab936e8c69a81; result SHA8c12458656655109c018fa282ffb771750c534ae868b14d4acb0440ae16f3984 |
| Fresh CLI result/source hashes | Actual23/23 exit0;54 input hashes unchanged, samea54/B1B before/after. wave21b-cli-manifest.json SHA41c9d976fe66903fa5219b4653d7aaa9320dfdad85a8fad72ec7c049fd095db4; wave21b-cli-results.json SHA0f2c10ad378f0aa5956a91aed64eef9d363d27d77955a44262c4103e010a15e3 |
| Fresh offline backend result/source hashes | Actual390PASS/1same optionalSKIP/0fail/error across391 cases;92 input hashes unchanged, samea54/B1B before/after. wave21b-backend-manifest.json SHA29436303935451fcdea2404dbe02f2bb6f10c8cd825d239bae2e853b6a3055b6 |
| Normal debug APK/native and wrapper exits/environment restoration | Normal lib/main.dart debug build129.2s; native and provider wrapper exit0; gradleEnvironmentRestored=true and source inputs unchanged. Build result SHA011b4a1e9387a5208419c652b275e14aba6629bd730a339a55f0b5520a8b419e |
| APK bytes/SHA/mtime/ZIP/kernel marker/source proof | Actual252354486 bytes; SHA479126e744752e5dff698ce3cef38011340a1ca2ff1adfeaa5facfec0635a263; mtime2026-10-30T17:28:38.570474Z within build window;752 unique ZIP entries all CRC-valid. Kernel103034456 bytes, SHAed9b192e7047b7ced6674dcf7f87a01ed002d0c1a295c60506f14e06dde811e0, marker a54ac2e2 at85819087. Source proof SHAfcc6faaab3626d4a97728fb3b50737f11579b827d7b7b0de250ba187d9110764 |
| Independent final validation/artifact acceptance | Root actual-log review SHA80184dc86a3de9628abcc4500e92307eb06f55db8faf50209d71f0c60097b58f; independent fixture bridge SHA00f0a82fdb9a77ea2ca404df73a7316b695a98733c366799dc9024c4e49b78a8; independent artifact/source ACCEPT SHAf9ac36a8ea836d60a9193804788d3fddf1dec75c8e121afa58ec58efdae5b15a. Exact tracked sets763Dart/54CLI/92backend have no mismatches. |

First full บน c650 จบจริง **4460ผ่าน/1fail/11m22s**; all763 Dart hashes
คงเดิมก่อน/หลัง. เก็บ log SHA9556bc8473d9a4dbf3856a23c88eff6f8e8936b2a0d7c0eeda008c3c80faaae5
และ result SHA0a4633a5f95ca3429272470353c93060bf036dd58268f0b4c24c94298e173e0b
ไว้เป็น failed evidence. Ghost/Clinic fixture เดิมไม่มี runtime Progress และมี
สอง active owners; แก้เฉพาะ fixture ให้ same-DB runtime/owner เดียวแล้ว Ghost24ผ่าน/8s.
Production source ไม่เปลี่ยน. คง first freeze/run และ five unexecuted c650-bound drivers.
Source a54ac2e2: Flutter4461/11m32s, analysis0/18.3s, CLI23/23, offline backend390PASS/one existing opt-in skip and normal main/debug APK129.2s/exit0. All763 Dart,54CLI and92backend inputs match before/after. Independent source, fixture-bridge and artifact reviews accept the local unit.


## สิ่งที่เชื่อมแล้วและขอบเขต

- รวม due-SRS, ordinary incorrect history, Saved Words และ local reports.
  คำเดียวมีหลายเหตุผลได้; count ต่อคิวและ distinct-word union ระบุแยกกัน.
  Loading/unavailable/partial source error ไม่ถูกแสดงเป็น ready zero.
  Missing/deleted current words ยังรักษา reason แต่เปิดฝึกไม่ได้.
- รายงานแต่ละ receipt คง target/version/hash/comment เดิมและแยกจาก word rows.
  ใช้ WordReportDetails/ประวัติเดิม พร้อมข้อความ local/not sent.
  ห้ามนำ historical report snapshot ไปสร้าง practice target.
- Full lazy lists/filters/refresh ไม่ตัดข้อมูลเหลือ20แถว. เฉพาะ practice batch
  จำกัด20คำ: due ใช้ canonical due-SRS ปัจจุบัน, saved ใช้ sourcePractice,
  incorrect ใช้ weakness. Same real owner stream และ LearningUseCases ส่งต่อครบ.
- P06 ChooseMode และ P08 Mastery เปิด Hub จริง. ChooseMode/Clinic/Mastery
  อ่าน Progress/History ด้วย captured-owner SELECT guards โดยไม่สร้าง owner.
  Due/weakness eligibility ตรวจ owned active category ให้ตรง canonical activity.
- Shared transient binding ล้าง rows/counts/read callbacks ทันทีเมื่อ owner/cover/
  visibility/lifecycle/dependency เปลี่ยน. Read epoch แยกจาก owned launch generation;
  own child ทำงานต่อได้หลัง parent ล้าง read ส่วน foreign cover เผา return intent.
  Static entries รอ observed owner แต่ไม่ต้องอาศัย unrelated projection success.
- Captured actions หลัง null/A, A/B/A, stream error/done หรือ frame invalidation
  ใช้ต่อไม่ได้. Exact child/Score route identity แยก normal pop จาก foreign cover;
  ไม่มีการ whitelist route name หรือใช้ finished boolean เป็นสิทธิ์.
- คง canonical answer/save/finish/SRS/reward semantics. การอ่าน Hub ไม่สร้าง
  session/attempt/Research/outbox หรือเปลี่ยนข้อมูลทั้ง37ตาราง.

## หลักฐาน focused และการแก้ที่เก็บไว้

Core/helper59ผ่าน; host ABA3ผ่าน; Hub23กรณีผ่านใน affected run.
Clean P06/P08 กับ Mastery รวม25ผ่าน/6s. Entry/SRS/layout18ผ่าน/12s.
Thai/English320px/200%, IME, keyboard และ Reduced Motion เป็น widget evidence;
ไม่อ้าง TalkBack หรือ physical-device UAT.

Affected รอบแรก **373ผ่าน/9fail** เก็บไว้. หลังแก้ fixture/Hub golden มี
**382ผ่าน/43s** ก่อนพบ connected asynchronous mistake-practice return อีกจุด.
ทั้ง outer Score return และ nested mistake-practice return มี actual foreign-pop
RED แล้วใช้ exact owned-route-current guard. Current entire Quiz module
**27ผ่าน/10s** รวม normal nested Score/practice และสอง negative return cases.
382เดิมไม่ใช่ผลผ่าน383หรือ full suite ของ source หลังแก้สุดท้าย.

เก็บ entry fixture incomplete3รอบ: original, phase-only และ appended-handoff.
Phase-only ผ่าน UI/DB assertions และ DB close แต่ Flutter completion ไม่จบ.
One-variable change ย้ายเฉพาะ observer cancellation เข้า captured I/O zone
ผ่าน tester.runAsync ทำให้ P06 เดิมผ่าน; clean two entries+Mastery ผ่าน25แล้ว.
Production default loader, same DB/stream/writers และทุก assertion คงอยู่.
ไม่มี arbitrary handoff delay ใน clean fixture.

Original/updated Hub golden ตรวจด้วยภาพจริง. Header/recommendation เดิมคงอยู่;
เพิ่ม Review Center tile จึงเลื่อนกิจกรรมลง. Current golden SHA
3f9db268f26035c14beb369955bb2af68d20b3199709ce1a3a406f85f22cba72.
W20 historical three-goldens-unchanged ยังเป็นข้อเท็จจริงของ W20 เท่านั้น.
ไม่ skip/delete assertion เพื่อให้ผ่าน ไม่ suppress missed tap และไม่ retry
cleanup ที่เคยถูกปฏิเสธ. เก็บ feedback images/critique/user WIP เดิม.

## หลักฐานที่มีแล้ว

ไฟล์อยู่ D:/LexiQuest-Storage/maintenance/2026-10-28/remaining-systems.
The earlier working-source acceptance is retained below. The current a54 full,
analysis, CLI, offline backend, normal APK and exact-source proof are now actual.
The immutable CLI manifest still says allLogsInspected=false. The separate root
receipt and independent peer read all23 actual logs and verify their hashes.

| หลักฐาน | SHA-256 |
| --- | --- |
| wave21-frozen-dart-source-final.json | 7bd1f494fde7729949c0178262e848433281a1bcacefe6c1eac5806bea4fd0f2 |
| wave21-final-source-review.md | 53f597b855f3c71b5d2ca0f98c2cdaa3841a13e24ec0b6e512e57f663cf095dd |
| review-center-entry-fixture-root-cause.md | 60730bfa0605ebbd5feb1fde533a65152841d2a8f28598f3d1a7af4ae4098047 |
| wave21-analyze-final.log | 6609db46e5c30ac3ab1963259f48c9fac20b12ec71ed65309a78c747e6f789de |
| wave21-full-flutter-final.log (first failed full) | 9556bc8473d9a4dbf3856a23c88eff6f8e8936b2a0d7c0eeda008c3c80faaae5 |
| wave21-ghost-runtime-fixture-green.log | b4d604f22f2ccb13025b9181319ff2bb6d91a59e74ea5440d6acb055a3371913 |
| wave21b-frozen-dart-source-final.json | b1b40ccd9d3e8c60c359a22407cea1405661930c9bfb7a5df41da9729037d636 |
| wave21b-analyze-final.log | c83e9721b763713412bfcb055932771a0a9493c2d772a9f9e02e1a6d57f9331a |
| wave21b-backend-manifest.json | 29436303935451fcdea2404dbe02f2bb6f10c8cd825d239bae2e853b6a3055b6 |
| wave21b-cli-manifest.json | 41c9d976fe66903fa5219b4653d7aaa9320dfdad85a8fad72ec7c049fd095db4 |
| wave21b-cli-results.json | 0f2c10ad378f0aa5956a91aed64eef9d363d27d77955a44262c4103e010a15e3 |
| wave21b-full-flutter-final.log | d0649eb50820ce4311ca14d258bc79b2176fa6363a8f02ec8feab936e8c69a81 |
| wave21b-full-flutter-result.json | 8c12458656655109c018fa282ffb771750c534ae868b14d4acb0440ae16f3984 |
| wave21b-verification-driver-binding-receipt.json | 171ce77b313f2b8ce2e56ff74bb673379ab7c22e0dabbb851217e7801bad189b |
| wave21b-root-validation-review.json | 80184dc86a3de9628abcc4500e92307eb06f55db8faf50209d71f0c60097b58f |
| wave21b-ghost-fixture-review.md | 00f0a82fdb9a77ea2ca404df73a7316b695a98733c366799dc9024c4e49b78a8 |
| wave21b-normal-debug-build-result.json | 011b4a1e9387a5208419c652b275e14aba6629bd730a339a55f0b5520a8b419e |
| wave21b-normal-debug-apk-manifest.json | 5412941c4e3d210b1e51fdf096daba309ffbdfd98279b91540b56d38ecb51a0f |
| wave21b-artifact-source-verification-final.json | fcc6faaab3626d4a97728fb3b50737f11579b827d7b7b0de250ba187d9110764 |
| wave21b-artifact-proof-review.json | f9ac36a8ea836d60a9193804788d3fddf1dec75c8e121afa58ec58efdae5b15a |

The native build and corrected provider wrapper both exited0. Environment
restoration and current source identity passed. The Wave20 wrapper1/restorefalse
and its recovery remain historical Wave20 evidence. The normal output replaced
the previous debug APK through the normal build. Nothing was installed or published.

## Readiness and next executable unit

f22 is Connected for its local four-reason runtime. Counts are now
14Connected/18Partial/12Missing across44 unique capability IDs. This does not
certify production rollout or external services. f21 broader targets, transport
and moderation remain Partial. f03/f05/f11/f13, durable SRS/native resume,
Research authority/enrollment/upload, physical-device UAT and efficacy retain
their existing separate requirements.

A P3 Ghost fixture cleanup follow-up remains. CTA finally and package tearDown both close GeneratedDatabase, which undercounts Drift debug warnings. The executor prevents a second SQLite close; no assertion or production behavior was weakened. Root will promote the ready memoized-close draft as the immediate next source unit and verify it before Focus Timer checks.

Root approved D-only drafting of the corrected six-file f23 Focus Timer plan after independent shape review. D focus-timer-integration-plan-draft.md SHAe60c9811cd75c0886c949adde14905f95a3b70de1bb3b71389e06cef863001f1 and focus-timer-independent-plan-review.md SHA307bda16c4b5fb487c5a1765c0a4bc1c32130c9df069936a963738ef195da96b bind that proposal. No next C plan or timer implementation exists yet. f23 and f24 remain Missing; the typed f23-to-f24 dependency and single active-time authority remain unchanged.

Schema stays20/37 with v21+ unreserved. No new time/reward/Research authority,
Pair Matching task, deployment, real enrollment or upload is authorized by this card.
