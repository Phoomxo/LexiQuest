# งานต่อจาก Dictation และ Cloze

Grounded 2026-10-30 ที่ source `e6996b1a54b4619ecb5140ec1fda53409a333460`,
worktree `C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`, branch
`codex/remaining-system-readiness` ขณะ root รัน full regression บน source frozen
นั้น เอกสารนี้เขียนบน D เท่านั้น ไม่ได้รัน Flutter/network/scanner หรือจอง migration

Final read: root ขยับ HEAD เป็น `b86bbb6ca90c1a34e2d07354a91077958fd06e42`
ระหว่างจัดบอร์ด diff จาก e6996b1a ใน source ที่เกี่ยวข้องมีเพียง Thai learning hub
ของ ChooseMode (11 เพิ่ม/20 ลบ); Quest, vocabulary, native legacy screens,
schema ledger, matrix และ frozen catalog ที่ใช้วิเคราะห์ข้างล่างไม่เปลี่ยน
ไม่ถือว่าการเปลี่ยน HEAD นี้ทำให้ผล full suite เดิมรับรอง source ใหม่โดยอัตโนมัติ

## สถานะที่ใช้จัดคิว

Current attestation: Saved Words source `597187e5` ผ่าน Flutter3922, analysis0,
CLI23, backend390/หนึ่ง opt-in skip และ normal debug APK แล้ว (wave16)
รวม offline bookmark/list/targeted practice และ owner lifecycle; schema19/36 และ Quest runtime/grants ยังไม่เปิด

- `docs/field/2026-10-28-feature-readiness-matrix.md` เป็น snapshot ถึง
  `597187e5`: 12 connected / 18 partial / 14 missing ไม่ใช่ production/UAT
  certification แม้ Dictation/Cloze/Word Scramble verified แล้ว f13 ยังไม่ครบทุก native mode
- `docs/design/feature-catalog-1.3.0.json` คง 8 หมวด/44 รหัส revision 1.3.0,
  contract hash `41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4`
  ห้ามเพิ่มรหัสเพื่อให้งานใหม่ดูครบ
- `docs/database/schema_ledger.md` และ executable database อยู่ v19/36 tables;
  v20 จองสำหรับ local word reports หลัง genuine19 capture แล้ว; v21+ ยังไม่จอง จำนวน44 capabilities ไม่ใช่จำนวนตาราง
- แผนแม่ `docs/superpowers/plans/2026-10-28-unfinished-system-integration.md`
  ยัง queue Motivation integration และ remaining catalog integration ไว้
  งานที่ปิดได้ต้องมี caller จริง ไม่ใช่เพียง class หรือ catalog entry
- หลัง Cloze ให้ re-ground API จริงก่อนเริ่ม card ถัดไป:
  `cloze-architecture-refinement.md` เป็นแบบเสนอ sealed native lifecycle
  ไม่ใช่หลักฐานว่า API นั้นอยู่ใน C แล้ว และแม้ Dictation/Cloze ผ่านทั้งคู่
  f13/f05 ก็ยังไม่ครบทุก mode/shell

การ์ด [Saved Words](2026-10-30-saved-words-integration.md) ปิดด้วย wave16 แล้ว
ถัดไปคือ [รายงานคำศัพท์ของผู้ใช้](2026-10-30-local-word-reports.md): form→review/edit→immutable local queue→restart/list
แบบที่ผ่าน boundary review แล้ว เก็บ genuine v19/ข้อมูลครบ36ตารางก่อนจอง v20 แล้ว;
ยังไม่มี migration code และ executable ยัง19/36 (v21+ ยังไม่จอง)
ไม่อ้างว่าส่งรายงานออกหรือ moderation พร้อม และยังไม่รวม AI/chat/document targets

## สามหน่วยถัดไปที่เสนอ

เรียง Motivation integrity → native integration → content/review ตามแนวแผนแม่
แต่ละหน่วยจบด้วยหลักฐานของตนเอง ไม่ประกาศว่าปิดทั้ง capability ที่กว้างกว่าแล้ว

### 1. Quest รับหลักฐานเดิมได้ครั้งเดียวและอยู่ในเจ้าของ/ช่วงเวลาที่ถูกต้อง

**รหัส/ข้อกำหนด:** f29 และ prerequisite ของ f42; TOR ตารางข้อ 8 กำหนดภารกิจ
หลักฐานสำเร็จ และรางวัลที่ไม่แทน mastery ไม่ใช่คะแนนเพิ่มจากการเปิด Today

**ช่องว่างจริง:** `EventV1ToV2Adapter.adaptFromCommand` สร้าง event ID จาก
timestamp+process counter และไม่มี canonical attempt ID เป็น input;
`QuestInstance.advanceIfMatches` append sourceEventIds แต่ไม่ตรวจว่ารับ ID เดิมแล้ว
`QuestUseCases.processEvent` อ่าน/บันทึก progress/markCompleted แยก await
ส่วน bootstrap ปัจจุบันยังไม่ได้ส่ง quest/streak hooks เข้า LearningUseCases
จึงต้องแก้ integrity ก่อนเปิด pipeline

**ขอบเขตเล็กสุด:** ให้ canonical persisted attempt เป็น source identity เดิม,
ตรวจ owner, eligibility, assignment/deadline ของ quest และทำ advance/complete
เป็น transaction เดียวด้วย owner coordinator เดิม ปรับเฉพาะ adapter/domain/repository/
use case ที่เกี่ยวข้องและ tests ห้ามเปลี่ยน EventEnvelopeV2 keyset หรือสร้าง learning writer
ใหม่ ไม่เพิ่มแถว `events_v2` สำหรับ nonparticipant เพียงเพื่อเดิน Quest
หลักฐาน replay ต้องอ้าง answer ที่มีอยู่จริง ไม่ใช้ nonce ใหม่เป็นเหตุการณ์ใหม่

**Reuse:** `learning_use_cases.dart` inserted-only hook และ shared projection gate,
`event_v1_to_v2_adapter.dart`, `quest_models.dart`, `drift_quest_repository.dart`,
`quest_use_cases.dart`, `DriftOwnerWriteCoordinator` และ reward ledger เดิม
ข้อควรระวัง: adapter ปัจจุบันใช้ชื่อ `QuizCompleted` สำหรับคำตอบถูกหนึ่งข้อ;
อย่าตีความเป็น session completion เพิ่มอีก authority

**ข้อมูล:** identity/replay repair ใช้ `quest_objective_progress.source_event_ids_json`
ที่มีอยู่ได้ ไม่ต้องตั้งตาราง processed-event ซ้ำโดยอัตโนมัติ
Daily/weekly recurrence เป็นหน่วยต่อจาก integrity นี้: unique `(owner_id,quest_id)`
ใน `QuestInstances` ยังขัดกับการเก็บ terminal history หลายช่วงเวลา จึงอาจต้องเพิ่ม
period identity/เปลี่ยน unique key เมื่อออกแบบ recurrence จริง ไม่ลบประวัติเพื่อเริ่มวันใหม่
ยังไม่จอง migration และยังไม่เปิด grants/freeze หรือ XP50/200 จาก built-in catalog
ผ่านเส้นทางใหม่ก่อนตรวจ payout ใน reward authority เดียว

**Acceptance:** actual persisted attempt เดิมหลัง restart/replay/concurrent callbacks
นับครั้งเดียว; คนละ attempt ใน millisecond เดียวไม่ชนกัน; owner A→B และ stale catalog/
deadline ไม่ advance; rollback ไม่ทิ้งครึ่ง progress/half completion; unknown/Assessment/
assisted native ไม่ได้รับ eligibility เพิ่ม; canonical SRS/XP/coins และ ordinary learning
ไม่เปลี่ยนเมื่อ optional Quest ล้มเหลว รัน domain+repository+learning hook tests ก่อน
recurrence/grant/UI composition แยกตาม prerequisite ไม่ตี f29 เป็น connected จาก repair นี้

### 2. Word Scramble หนึ่งคำจริงผ่าน canonical native lifecycle

**สถานะ:** verified source d995ffc2, Flutter3820/analysis0/CLI23/backend390/normal APK
ผ่าน independent review และ hash695Dart คงเดิม ดู [wave15](../../field/2026-10-30-remaining-systems-wave15.md)

**รหัส/ข้อกำหนด:** f13, f05, f11 และ f38; TOR P33 คือเรียงตัวอักษรเป็นคำ,
P23 คือผลสรุปจริง ต้องมี keyboard/tap alternative และ feedback หลัง ACK

**ช่องว่างก่อน wave15:** `WordScrambleScreen` รับ raw String, ตรวจถูกใน widget และ
เปลี่ยนไป FillInTheBlanks ด้วย delayed navigation ไม่มี canonical evidence
มี legacy reference จาก non-source branch ใน `SpeakToTextScreen` แต่ current
`SourcePracticeScreen` ส่ง sourceOwnerId จึงใช้ source finish/exit branch;
ไม่ใช่ ChooseMode entry ที่ owned/pinned สำหรับ Scramble

**ขอบเขตเล็กสุด:** เลือก category/word จริงหนึ่งคำ, freeze target revision/spelling
และ scramble order; reuse native transaction/one-answer/finish/retry proof ที่ผ่าน
จาก Dictation+Cloze เปลี่ยน sealed cases เท่าที่ใช้จริง ไม่สร้าง mode registry,
generic screen superclass หรืออีก writer แยกตัวอักษรด้วย grapheme ที่ dependency
เดิมรองรับ และตรวจคำที่สลับแล้วไม่ต่างจากต้นฉบับก่อนเสนอแบบฝึก
ถ้าไม่มี target ที่ใช้ได้ แสดง unavailable/empty โดยไม่สร้าง session

**Classification:** ตัวอักษรคำตอบถูกเปิดให้เห็นแล้ว จึงเป็น recreational ตาม
precedent ที่บันทึกใน `native-modes-grounding.md` ไม่ใช่ independent recall
เก็บ session/history ได้ แต่ไม่ให้ SRS, learning-effort, XP, coins, Quest,
Streak, achievement หรือ efficacy claim คง EvidenceContext/EventEnvelopeV2 เดิม
Sentence Scramble (P34) เป็น card ต่อไป ไม่แอบนับรวมจากการทำ P33

**ข้อมูล/ไฟล์:** ใช้ `learning_models.dart`, canonical repository/use cases,
activity capture+projection gate, `word_scramble_screen.dart`, ChooseMode และ
history label ที่จำเป็น ไม่มีเหตุให้เพิ่มตารางจากหนึ่งคำ/one-answer lifecycle
durable restart/resume ยังต้องเป็น versioned checkpoint แยก ห้ามใช้ raw ID รับช่วง

**Acceptance:** ChooseMode→category→real word→tap/keyboard→save retry→explicit finish
ได้หนึ่ง session/answer และ end เดิม; คำซ้ำ/อักษรซ้ำ/ไม่มีตัวสลับทำงานถูก;
owner/revision/fence/route/lifecycle และ generic API bypass ปิดเหมือน Native เดิม;
snapshot projections และ Research rows byte-identical; Thai/English 200%, IME,
Reduced Motion และไม่มี auto-chain ไป Cloze ก่อน save/finish ACK

### 3. Bookmark คำจริงและรายการ saved สำหรับกลับมาทบทวน

**รหัส/ข้อกำหนด:** f20 → saved ส่วนหนึ่งของ f22; TOR P12/P20/P31 ระบุ
saved/unsaved/offline โดยเฉพาะ การเพิ่มคำเข้าคลังไม่ใช่ bookmark
ไม่ประกาศ f03 rich lexical card หรือ f22 Review Center ครบทั้งหมดจาก bookmark

**ขอบเขตเล็กสุด:** action save/unsave ของ owned vocabulary word และรายการ saved
อ่านจาก local แล้วเปิดคำ/ส่ง word IDs เข้า targeted practice เดิม
สถานะเปลี่ยนหลัง ACK, กดซ้ำไม่สร้างรายการซ้ำ, offline ใช้ได้
bookmark อ้าง word ID; current card อ่าน revision ปัจจุบันจาก vocabulary authority
เมื่อคำถูกลบ/เข้าไม่ถึงต้อง unavailable/remove ได้ ไม่สร้าง fallback word
ไม่แก้ immutable learning evidence และไม่ให้ reward จากการ bookmark

**Reuse/ไฟล์:** `VocabularyUseCases`/repository, `VocabListScreen`,
`WeaknessClinicScreen`, targeted `LearningUseCases.startSourcePracticeForWords`,
owner coordinator, personal export/purge และ owner-upgrade inventory เดิม
เพิ่ม bounded bookmark domain/repository/query และ small saved view เท่าที่จำเป็น
ไม่สร้าง content pack/download manager หรือ generic content database ไปพร้อมกัน

**ข้อมูลที่น่าต้องเพิ่ม:** owner-scoped bookmark relation ที่ unique owner+word
พร้อม immutable creation time และ FK จริง เพราะ vocabulary tables ปัจจุบันไม่มี
bookmark flag/relation และ runtime_flags ไม่มี owner column
ชื่อ/คอลัมน์/migration เป็นเพียงข้อเสนอจน inspect ledger รอบ implementation
ต้องมี populated migration, export/delete/rehome/owner-fence และ policy coverage
ระบุให้ชัดถ้ารุ่นแรกเป็น local-only; ห้ามขึ้นคำว่า synced โดยไม่มี wire/policy จริง

**Acceptance:** actual add/remove/read/restart, rapid tap/lost ACK, owner isolation,
soft-delete target และ purge/rehome; saved→existing practice path ใช้ word/revision
จริงและสร้าง learning fact ผ่าน writer เดิมเท่านั้น; bookmark flow ไม่เพิ่ม SRS/
XP/coins/Research; cold offline, empty/error/retry และ 200% accessibility

## Backlog ที่ยังต้องดำเนินต่อ ไม่ใช่ข้ออ้างหยุดหลัง Native

ตารางนี้รวมครบ 34 รหัสที่ matrix snapshot เดิมยัง partial/missing โดยไม่เปลี่ยน
counts หรือรวมค่าของแต่ละ capability เป็น claim เดียว

| กลุ่ม | รหัสที่ยังไม่ครบ | แยกงานที่ดำเนินต่อได้ |
| --- | --- | --- |
| แบบฝึก/การเรียนร่วม | f05,f08,f09,f11,f12,f13,f15,f16 | Cloze ที่กำลังจัดคิว; Word/Sentence Scramble แยก; Definition ต้องมี definition/content contract จริง ไม่เปลี่ยนชื่อ Meaning Quiz; shared feedback/summary/configuration/ladder หลัง concrete callers พร้อม; scratchpad undo/clear+text fallback ไม่อ้าง handwriting recognition |
| Content และ review | f01,f02,f03,f04,f18,f19,f20,f21,f22,f44 | Bookmark ก่อน; report queue ผูก exact revision แยกจาก bookmark; rich card ตัวอย่าง/สื่อที่มี source จริง; pack manifest/version/checksum/detail แล้ว download/pin/repair/remove โดยไม่ลบ evidence; Review Center รวม due/saved/reported/mistakes; distractor explanation ไม่ประดิษฐ์เหตุผลว่าถูกต้องทางวิชาการ |
| แผนและความต่อเนื่อง | f23,f24,f25,f26,f27,f35,f36,f42 | Foreground lesson-time segments ก่อน calendar/time analytics; focus timer pause/resume แยกจาก learning proof; local goal/date/preferences/profile แล้ว Today aggregation; opt-in reminders permission/schedule/cancel default-off เป็นอีก card ไม่ใช้ timestamp elapsed แทน active learning |
| Motivation/การแสดงผล | f29,f30,f32,f33,f34 | Quest integrity→period/history→payout เดียว;เลือก streak authority เดียวและพิสูจน์ freeze grant/consume replay ก่อน compose V2; avatar/unlock ใช้ RewardUseCases เดิม; companion deterministic controlled copy+Reduced Motion; private share preview/export/cancel ไม่เปิดเผย owner/research data |
| Accessibility | f38 | ทำผ่านทุก vertical slice และปิด remaining screen coverage แยก physical TalkBack/real keyboard/foldable ออกจาก widget fixtures |
| Research outcome | f28 | เก็บ partial: local signed Assessment/Study implementation ไม่ใช่ production gateway, collection/upload contract หรือ efficacy evidence |
| Matching | f10 | คงเป็น backlog; ไม่สร้าง separate Pair Matching task จากเอกสารนี้ ต้องเคารพ Research completion และคำสั่งผู้ใช้ที่เจาะจงก่อน |

Planning/time อาจต้อง owner-scoped learning-time segments และ preference/goal records;
report ต้อง revision-bound queue; packs ต้อง manifest/install state; freeze อาจต้อง
grant/consume receipt ถ้าข้อมูลเดิมพิสูจน์ idempotence ไม่พอ ทั้งหมดเป็น candidate
เท่านั้น ไม่จองเลข schema/ตารางใน workboard นี้

## สิ่งที่ต้องใช้ภายนอกและสิ่งที่ทำต่อได้

สามหน่วยแรกไม่มีคำถามที่ต้องให้ผู้ใช้ตอบก่อนเริ่ม grounding/RED ตาม scope ที่อนุมัติ
ส่วน production Research ต้องมี genuine gateway/current documents/revocations/
receipts/trusted lifecycle-time contract, approved keys/protocol/instrument/ethics และ
explicit rollout authority; การพัฒนาพอร์ต local, rejection tests และ upload contract
ที่กำหนดชัดยังทำต่อได้โดย default-off ห้ามแทน dependency ด้วย fake approval

Live Firebase/OmniVoice/model service, deployment/signing/App Check/support contacts,
content licensing/approved public packs และ physical-device UAT ต้องมีหลักฐานจริง
แยกจาก local engineering; ไม่มีข้อใดทำให้ต้องหยุดพัฒนา ordinary offline features
ไม่ขอ credential ผ่านข้อความ ไม่ deploy/enroll/upload หรือสร้าง separate task เอง

จบแต่ละ card ตาม ADLC: actual caller+focused RED/GREEN+peer review+owner/privacy/
projection checks แล้ว root ทำ integration/full analysis/build บน source frozen
อัปเดต matrix เฉพาะสิ่งที่พิสูจน์จริงและเก็บ backlog ส่วนที่ยังไม่ครบไว้
