# Wave20: SRS ผูกเจ้าของและยืนยันการบันทึกเดิมได้อย่างปลอดภัย

วันที่2026-10-30; application source `dd45f8626add6d08c8e442fd3b54752023e30323`,
branch `codex/remaining-system-readiness`, worktree cycle12-release เดิม.
Production integration อยู่ที่ `2ecc0da3`; final source เปลี่ยนเฉพาะ3 integration fixtures
กับแผน. lib tree คงเดิม. Schema **v20/37 tables**, v21+ ยังไม่จอง;
frozen8/44 และ EvidenceContext/EventEnvelopeV2 คงอยู่.

Flutter **4372ผ่าน/11นาที6วินาที**, analysis0, CLI23/23,
offline backend390ผ่าน/หนึ่ง opt-in E2E skip เดิม. ตรวจ751 Dart/54 CLI/92 backend
ตรง source freeze หลัง checks/build. นี่เป็น local engineering checkpoint
ไม่ใช่ production rollout, physical-device UAT หรือการรับรอง efficacy.

## สิ่งที่เชื่อมและรักษาไว้

- ทั้ง6จุดเปิด SRS ใช้การจับ owner/context: recommendation/tile ใน ChooseMode,
  Clinic due queue, confirmed Source และ raw CEFR/Wordbook previews.
  Due actions รอเห็น owner จริงก่อนเปิด; retained callback หลัง owner ABA ใช้ต่อไม่ได้.
- เพิ่ม SrsReviewRepository capability ใน repository file เดิม ผ่าน Drift DAO
  และ private canonical start/answer/finish เดิม. ไม่มี writer/store ใหม่,
  schema, dependency หรือ EvidenceContext key/profile ใหม่.
- Prepare ไม่สร้าง learning fact และไม่สร้าง owner. Deck จริง1..20คำถูก copy/pin
  ตาม owned active category/content revision. Due มีลำดับ dueAt/ID คงที่;
  source รักษา requested IDs แม้ยังไม่มีคำถึงกำหนด.
- Original review/rating/finish handles ผูกกับ preparing usecase เดิม.
  Freeze ID, rating, ordinal, latency, UTC time, evidence และ end ก่อน await.
  Generic prefix/activity/prompt bypass ถูกปิด รวม legacy aliases.
  Historical read/pull/rebuild/rehome/export/purge ยังรองรับ.
- ทุกคำสั่งเป็น own commit; ambient/cross-database ถูกปฏิเสธ.
  Owner/fence/current/target และ canonical readback ถูกตรวจรอบ SQL.
  หลัง commit แล้ว ACK หาย ต้องลอง intent เดิม; ไม่เพิ่ม projections/outbox/hooks ซ้ำ.
  First confirmed receipt ส่ง notification หลัง top-level commit ได้ครั้งเดียว.
- Exact historical replay ไม่ rebuild projection และไม่ต้องมี live parent เดิม.
  หาก SRS projection ถูกล้างแล้ว คืน nullable saved state ตามจริง.
  srsRecall ยังใช้ independentRecall/srs-recall และผล learning/reward เดิม;
  ไม่มี Research event/row สำหรับ nonparticipant.
- Owned card และ autoplay เริ่มหลัง canonical start ACK; Next หลัง rating ACK;
  Source result หลัง finish ACK ที่ตรวจ summary จริง.
  Owner null/A, A/B/A, stream error/done, frame, cover/hidden/lifecycle/dependency
  ปิดข้อมูล/handlers เก่าทันที. Audio ใช้ borrowed voice และ join pending stop.
- Raw-map preview snapshot ทุกแถว รวม23แถวใน test ไม่ใช้ fake session/word IDs,
  ไม่สร้าง learning/SRS/reward/outbox/Research และระบุว่าไม่บันทึกผล.
  Retained per-card Flip/Rate/Next/Listen ใช้กับบัตรถัดไปไม่ได้.
  Thai/English320px/200%, IME, keyboard Enter/Space และ Reduced Motion ผ่าน;
  ไม่อ้าง Tab traversal, TalkBack หรืออุปกรณ์จริง.

## สิ่งที่พิสูจน์และ recovery

Core50ผ่าน รวม post-SQL rollback ทุก37ตาราง, generic bypass,20-card ordering,
lost-ACK และ actual inherited-transaction positive control.
Combined UI40ผ่าน:14 legacy executions,17 safety,9 callers.
Source SRS4ผ่าน รวม zero-due practice/reward/result และจริง A-to-B-to-A ใน commit เดียว.
Historical Progress11 และ model3 ผ่าน; focused counts ซ้อนกับ full suite.

Actual purged-projection replay เคย RED1 แล้วแก้โดยคืน srs=null ตาม receipt
แทนการบังคับ rebuild. ตัวทดสอบที่ย้ายมาคืนข้อความไทยตรง HEAD,
เลื่อนตาม outer scrollable จริงและรอ ACK/layout โดยไม่ suppress warning/assertion.
Real owner subscription ใช้ real IO scheduling; synthetic notification probe
คง caller/Drift transaction values และมี control ที่ต้องอ่าน executor เป็น transaction.

Full รอบแรกบน2eccจบ4366ผ่าน/6fail/13m10s:5 fixture preconditions/cleanup
และ1 binding cascade หลัง teardown ที่ล้ม. เก็บ log/freeze/result เดิมไว้.
ปรับเฉพาะ3 test modules ให้มี owner/lifecycle จริงและปิด widget/stream ก่อน DB.
Golden comparisons/ภาพเดิมทั้ง3ไม่เปลี่ยน; focused29ผ่าน.
รอบสุดท้าย4372ผ่านบน dd45 และไม่มี test ถูก skip/delete เพื่อให้ผ่าน.
สองบริการเก่า SrsService/WeaknessClinicService ที่ไม่มี production caller ถูกตัดออก
หลังยืนยัน blobs บน GitHub;3 SrsItem tests เดิมย้ายโดย assertion bodies เหมือนเดิม.
ไม่อ้างพื้นที่ดิสก์ที่ได้คืนจากการตัด source ขนาดเล็กนี้.

## หลักฐานและ APK

Independent integrated/source, current validation และ actual APK review **ACCEPT**.
อ่าน raw CLI23 logs, backend3 logs/391 XML cases/29 current package origins
และตรวจ751/54/92 pathsets+hashes. Backendใช้113 stdlib socket pairs;
ไม่มี external connection attempt. คำเตือน Drift cross-database control
และ backend deprecation ที่บันทึกไว้ไม่ใช่ failure; ไม่อ้าง warning-free ทุก suite.

หลักฐานอยู่ `D:\\LexiQuest-Storage\\maintenance\\2026-10-28\\remaining-systems`:

| หลักฐาน | SHA-256 |
| --- | --- |
| wave20b-frozen-dart-source-final.json | `33f43de12488b6a4543faa4ac23faf76d212da90e588a2545afe7aae6e839e2a` |
| wave20b-full-flutter-final.log | `c219128ea4e9f81f1c7ab1ff04c97e6b9adf898ac50851a00aacab25a39645bd` |
| wave20b-root-validation-review.json | `4e53fa99188aef52cf68a042a87e774303ee685c139596f001b92d3ebb0b2d98` |
| wave20b-independent-validation-review.json | `8eb89b497dc2c08e090acf1c241dadd4415a677aafdf53e41e0a275afd8f3943` |
| wave20b-normal-debug-apk-manifest.json | `18803e219035f7f8fe4285f451ccf9768426925adc3afd225a80acc7bcc84a13` |
| wave20b-artifact-source-verification-final.json | `4537c8faf50feb66b061057512248f17c591773db839be441f9ec1836446d841` |
| wave20b-artifact-proof-review.json | `c397be68636b541ae9b25a0639062ca3fbc9e99d78f7ac7bd34a5b99c1140165` |
| wave20b-gradle-env-recovery.json | `555cee8b6edfa232ee13d1c84e7406edbcf4aa6ac0bc1e52c0113aee0fc74662` |

Normal `lib/main.dart`, debug1.0.0+1, buildID `dd45f862`;
native build **122.8s/exit0**, `252273727`bytes,
SHA `420ff7e1f4705b7da07d6ec0f9c586ae344e259552df545d17cfe514ad388e43`.
Actual ZIP752 entries CRC ผ่าน; kernel `102838872`bytes
มี marker ที่ offset85624212. Kernel SHA
`8208a6f0a7b655022caaa649012a92894fc02ea2c7814b7871c10c3959427db7`.
Start `2026-10-30T14:45:37.7182558Z`;
modified `2026-10-30T14:47:40.532946+00:00` ใหม่กว่า start.
lib tree `104f3364f2afb287aaefc5c64221996e3366ad99`;
test tree `76dd064231c1552ab26cd8e4b08d7d9aad4bf5f5`;
android tree `c9abd4fd1187a4af13b306f1f077127f96884bac`.
ใช้ normal output เดิมแทนรุ่นก่อน ไม่ copy APK เพิ่มเอง ไม่ install/publish.

Wrapper รายงาน exit1 หลัง native build สำเร็จ เพราะ .NET setter ใน PowerShell
ทำ absent GRADLE_OPTS เป็น empty แล้ว strict restoration check เป็น false.
เก็บ false/original result และ executed script ไว้ครบ ไม่แก้เป็น true.
Fresh child ยืนยัน parent inherited state ยัง absent; provider restoration
ผ่าน controls absent/empty/nonempty แบบ exact. Recovery receipt แยกและ
reconciled artifact proof รักษา source/full/hash/mtime/kernel guards เดิม.
ไม่ rebuild APK เพื่อปิดบัง postcheck; process-local3G/workers2/daemonfalse
ไม่แก้ global/project Gradle configuration. KGP/SDK XML warnings เดิมยังอยู่.

## งานต่อและข้อจำกัด

Coverage คง **13Connected/19Partial/12Missing**; f06 เดิม Connected ถูก harden,
f22 คง Partial เพราะส่วนประกอบมีแล้วแต่ combined Review Center ยังไม่มี.
Known source-level gap: ChooseMode, Mastery และ Clinic cache ownerless Progress futures
จึงอาจค้างข้อมูล owner เก่า; Clinic Quiz handoff ต้องจับ scope เพิ่ม.
นี่แยกจาก SRS writer ที่ตรวจแล้ว และต้องแก้ในหน่วย Review Center ถัดไป.
Due ยังเป็น self-rated SRS; historical report snapshot ห้ามกลายเป็น practice target.

ไม่เปิด Research enrollment/upload, production authority, Quest recurrence/grants,
Pair Matching task หรือ rollout. Durable SRS/native resume และ common shell ยังไม่ครบ.
ยังไม่รับรอง real Firebase/OmniVoice, physical audio/stylus/TalkBack, dark200/gesture
หรือ system-UI ANR acceptance. คง user WIP/primary checkout และไฟล์ critique เดิม.
รายการ cleanup ที่ automatic review ปฏิเสธก่อนหน้ายังเก็บไว้และไม่ retry;
feedback8ภาพใหม่จาก full รอบแรก copy ไป D พร้อม hashes โดยไม่ลบต้นฉบับ.
