# SA — ขอบเขตสถาปัตยกรรมและผลกระทบ P1–P6

ตรวจ working tree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`, วันที่ 8 กันยายน 2026; เป็น independent source review ไม่ใช่ผลทดสอบ/UAT หรือการอนุมัติเปิดใช้ ผลทดสอบ 4,964 ข้อใน briefing เป็นหลักฐานรอบก่อนเท่านั้น

ข้อเสนอหลัก: เติมช่องว่างการอ่าน/นำทางก่อน แล้วแยกการผูกเป้าหมายกับเนื้อหา ตารางถาวร และ Quest objective ใหม่เป็นงาน domain ที่ต้องมีสัญญาเฉพาะ ส่วนเพื่อนออนไลน์เป็น capability ใหม่ เป้าคือช่วยเด็กไทยรู้ว่าจะเรียนอะไรและกลับมาได้ง่าย โดยไม่สร้างคะแนนหรือข้อมูลความชำนาญอีกชุด

## 1. เส้นทางและเจ้าของข้อเท็จจริงที่ตรวจพบ

| ช่วง | Interface/หลักฐาน source | ขอบเขตที่ต้องรักษา |
| --- | --- | --- |
| Standard → Today → เลือกกิจกรรม | `lib/features/today_hub/application/today_hub_use_cases.dart:10`; `lib/features/today_hub/data/drift_today_hub_reader.dart:32` | `compose` อ่านและตรวจ active owner ก่อน/หลัง; ลำดับปัจจุบัน resume → assigned → review → recommendation → planning → continuity ที่ `:86`; ไม่ใช่ session creator |
| Preference → recommendation | `lib/features/preferences/domain/learner_preferences.dart:152`; `lib/features/recommendation/application/recommendation_use_cases.dart:291` | goal enum/นาทีต่อวัน/activity เป็น preference คนละอย่างกับ deadline goal; activity จัดลำดับ safe modes ที่ `:303`, protocol ปฏิเสธ override ที่ `:309` |
| Adventure → mission → session plan | `lib/features/adventure/application/adventure_journey_reader.dart:261`; `lib/features/adventure/application/adventure_session_composer.dart:35` | mission resume และ review priority มาจาก Today; composer ตรวจ owner, เวลา snapshot, entry gate, mode และ content/checksum ก่อนสร้าง typed plan; ห้ามใช้ goal title เป็น content ID |
| Answer → canonical commit | `lib/features/learning/application/learning_use_cases.dart:1011`; `lib/features/learning/data/drift_learning_repository.dart:1551` | Frozen command/sourceEvidenceId + owner/session + EvidenceContext → immutable event/attempt ใน transaction; exact committed retry อ่านผลเดิมที่ use case `:1042` |
| Commit → SRS/mastery/Quest/reward | repository `:1711`–`:1749`; `lib/features/quest/application/quest_use_cases.dart:146`; `lib/features/adventure/application/adventure_motivation_projection_reader.dart:161` | durable eligibility decision กำกับ projections; Quest ตรวจ version/instance pins และ source-event receipts; UI แสดง pending/committed/notEligible จาก reader ไม่ให้รางวัลเอง |
| Pair resume/repair/replay | `lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart:528`; `lib/features/learning/pair_matching/domain/pair_matching_session_purpose.dart:393` | retry ใช้ frozen accepted evidence, replay purpose เป็น recreational; repair/งานค้างต้องเข้าทาง coordinator เดิม ไม่กดแนะนำแล้วเริ่มใหม่ทับ session |
| Cloze → ลองพูดเสริม | `lib/features/learning/presentation/sentence_practice_panel.dart:15`, `:123`, `:323` | ephemeral transcript และ optional skip; ไม่มี dependency learning/evidence/reward/persistence; อย่านับเป็น speaking mastery, Quest, streak, XP หรือ research response |

## 2. Impact matrix: ของที่มีแล้ว / policy / state ใหม่ / online

| P | Runtime ปัจจุบันและช่องว่าง | ขอบเขตที่เสนอและผลต่อข้อมูล |
| --- | --- | --- |
| P1 เป้าหมาย–สัปดาห์–วันนี้ | Today reader โหลด goals/reminders (`drift_today_hub_reader.dart:62`) แต่ renderer `lib/screens/today_hub_view.dart:204` ยัง `break`; `LearningGoal` มี kind/title/deadline/timezone/status (`lib/features/goals/domain/learning_goal.dart:33`) ไม่มี linked content/competency/target workload | ทำ deadline card และ “งานที่มีให้เลือกวันนี้” เป็น read projection ได้; “แผนเพื่อเป้านี้/เหลือกี่ %” ทำไม่ได้อย่างซื่อตรงจาก title เพียงอย่างเดียว ต้อง typed goal-content linkage + pin semantics; weekly plan ที่บันทึก/แก้ได้คือ persistent state ใหม่ |
| P2 อธิบายพัฒนาการ | มี `ProgressUseCases.loadPersonalLearningProfile` (`lib/features/progress/application/progress_use_cases.dart:40`), History และ projection receipts อยู่แล้ว | read projection พร้อมช่วงเวลา จำนวนตัวอย่าง ประเภทหลักฐาน และสถานะไม่พอข้อมูล; accuracy/recall/effort/reward แยกความหมาย ห้ามใช้ XP หรือ optional speech เป็นความชำนาญ; ถ้าต้องนิยาม score/trend ใหม่คือ domain policy ต้อง version แม้ไม่เพิ่มตาราง |
| P3 ภารกิจหลากหลาย/เลือกได้ | `lib/features/quest/application/quest_catalog_provider.dart:16` catalog v1 มี correct-answer daily/weekly จาก `QuizCompleted` (`:29`, `:53`); startup seed ทุก definition (`:96`) ไม่ใช่ระบบเลือก quest ตามใจ | ตัวเลือกเส้นทางฝึกที่มีอยู่ทำเป็น recommendation presentation; การเพิ่ม objective/การเลือกรับภารกิจจริงต้อง Quest authority และกติกาเลือก/เปลี่ยน/หมดอายุ ไม่ใช่ checkbox UI; ห้ามเริ่ม quest ทุกครั้งที่เปิด Today หรือให้ bonus จากการเลือก |
| P4 กลับมา–ตารางเตือน | `StudyReminderUseCases.optIn` รับหนึ่ง `scheduledAtUtc` และ source ที่ `lib/features/reminders/application/study_reminder_use_cases.dart:152`; `lib/data/local/tables/planning_tables.dart:31` ไม่มี weekday/recurrence rule | welcome-back จากประวัติ + resume เป็น read projection; เตือนครั้งเดียวใช้ authority เดิมและ permission/reconcile เดิม; recurring schedule เป็น domain policy + durable recurrence/version/cancellation semantics ใหม่ ไม่แอบ encode ใน title หรือ `sourceKind` |
| P5 ภาพอุปกรณ์ | `lib/screens/avatar_equipment_screen.dart:225` ระบุยังแสดงชื่อ; catalog item มี ID/version/kind แต่ไม่มีภาพ (`lib/features/rewards/domain/reward_models.dart:3`) | presentation asset mapping ตาม catalog ID/version และ owned/equipped snapshot; ไม่ต้องมี owner table ใหม่; purchase/equip ผ่าน `RewardUseCases.purchase/equip` (`lib/features/rewards/application/reward_use_cases.dart:53`, `:122`) พร้อม idempotency key เดิม |
| P6 เพื่อนสมัครใจ | Adventure contract ไม่รวม multiplayer/social (`docs/superpowers/specs/2026-09-01-adventure-motivation-mode-design.md:24`, `:90`); 8/44 เป็น catalog คงที่ ไม่ใช่ runtime flags (`docs/superpowers/specs/2026-08-14-lexiquest-alltcas-idea-integration-feature-contract-design.md:18`, `:98`) | peer identity/invite/accept/block/visibility/shared progress เป็น online capability และ data authority ใหม่ ต้องแยก design/version/scope decision; แนวทางชวนคนข้างตัวฝึกแบบไม่มี peer data อาจทดลองกับผู้ใช้ได้ แต่ห้ามเรียกว่า social system ที่เสร็จแล้ว |

## 3. ทางเลือกและจุดกึ่งกลางที่แนะนำ

| ทางเลือก | ผลดี | ต้นทุน/สิ่งที่ต้องยอมรับ | คำตัดสิน |
| --- | --- | --- | --- |
| A เติม UI ของเดิมเท่านั้น | เปลี่ยนน้อย ย้อนกลับง่าย ไม่มี schema ใหม่ | ยังไม่มี weekly plan ผูกเป้าจริง/quest diversity/social | ทำเป็นระยะแรก แต่เรียกสิ่งที่แสดงตรงกับข้อมูลจริง |
| B projection ก่อน แล้ว planning domain ที่ version แยก | ผู้ใช้ได้ประโยชน์เร็วและเพิ่ม personalization อย่างอธิบายได้ | ต้องกำหนด goal-content binding, mutable schedule และ lifecycle ก่อนระยะสอง | **แนะนำ**; P2/P5 และ P1/P4 ส่วนอ่านมาก่อน, P3 objective ตามหลัง |
| C ทำ P1–P6 พร้อมกัน | ได้ภาพประสบการณ์ครบเร็วในเชิง prototype | session selection/economy/schema/social/research เปลี่ยนพร้อมกัน แยกสาเหตุ regression ยาก | ไม่แนะนำสำหรับ source ที่กำลังรอ device/UAT รุ่นล่าสุด |
| D advisory planner ชั่วคราวไม่มีบันทึก | ลอง UX รายสัปดาห์ได้โดยไม่ migration | ต้องติดป้ายว่าแผนแนะนำชั่วคราว; ไม่มีคำสัญญาว่าคืนค่า/ข้ามเครื่อง/เรียนเพื่อ deadline นี้ครบ | ใช้เป็น prototype/UAT ของ B ได้ ห้ามกล่าวว่าเป็น persistent weekly plan |

สัญญาขอบเขตที่ควรตกลง: Today เป็น composition reader ต่อไป; planning ส่งเพียง typed suggested action ซึ่งมี ownerId, evaluatedAt, reason, content identity/revision และสถานะ availability; action ไม่มีสิทธิ์เขียน evidence/reward หรือสร้าง session จนผู้เรียนเลือกผ่าน entry/controller เดิม ตรวจ owner/gate/content freshness อีกครั้งขณะกด

การแนะนำตามเป้าหมายจริงต้องมี explicit binding ที่ผู้เรียนยืนยัน เช่น goalId → pack/content identity + revision/coverage semantics; อย่าทำ NLP จาก title, ห้าม infer “สอบนี้ = คำชุดนี้” หรือสร้าง unversioned JSON ใน preferences เป็นฐานข้อมูลแผนซ่อนอยู่ การเพิ่ม linkage ไม่อนุญาตแก้ frozen EvidenceContext/EventEnvelopeV2; ใช้ owner-scoped planning domain และอ้าง canonical identifiers

รักษางานค้าง/assigned/repair ก่อนคำแนะนำตามความชอบ โดยคงลำดับเดิมของแต่ละ surface ไม่บังคับ Today กับ Adventure ใช้ลำดับใหม่ที่คิดขึ้นเอง; goal/preference ทำหน้าที่จัดลำดับเฉพาะ safe candidates ที่เหลือ การเลือกคำแนะนำยังต้องแสดง config/ทางกลับเดิม ไม่เปิด follow-on session อัตโนมัติ

## 4. Lifecycle, failure และ recovery ที่ต้องออกแบบก่อนเพิ่ม state

| จุดเสี่ยง | พฤติกรรมปลอดภัยและ recovery | เกณฑ์ตรวจรับที่ยังต้องทำในงาน implementation |
| --- | --- | --- |
| Owner เปลี่ยนระหว่าง load/tap/write | ทิ้ง snapshot เก่า โหลดเจ้าของใหม่; mutation ผูก exact owner และ operation identity เดิม ไม่ rebind plan/quest ของคนก่อน | A→B/guest upgrade/delete ระหว่าง async; ไม่มีข้อมูล/notification/reward ข้าม owner; lifecycle manifest ต้องเพิ่ม binding/schedule ทุกตัว |
| Offline/missing content/authority | เรียน local เดิมได้; goal ที่ไม่มี content แสดงเพียง deadline; recommendation unavailable มีทางเลือก safe mode; ไม่แสดง progress=0 แทน unknown | ปิดเครือข่าย/corrupt reference/pack revised; no auto-download/start และ preserve resume |
| Commit สำเร็จแต่ UI/Quest receipt ยัง pending | โหลด canonical result/receipt เดิม; retry ด้วย evidence ID เดิม ห้าม increment card หรือ grant ก่อน committed | double tap/restart/revisit/replay ให้ attempts/SRS/Quest/XP/Coins delta ตรง eligibility และไม่มี duplicate |
| เตือนถูกปฏิเสธ/OS schedule ล้มเหลว/เขตเวลาเปลี่ยน | บันทึกสถานะจริงและ reconcile ผ่าน reminder authority; ปิด recurring ต้องยกเลิก future occurrences; DST ใช้ timezone ไม่ใช้ offset คงที่ตลอดปี | permission denied, quiet hours, date rollover, owner deletion และ reconnect ไม่คืน notification ที่ยกเลิก |
| ภาพอุปกรณ์หายหรือ version ไม่รู้จัก | fallback ชื่อ/placeholder; ยังคงอ่าน owned/equipped inventory ได้; preview ไม่มี write | ไม่มี purchase/grant ซ้ำ, reduced motion/จอเล็ก/ออฟไลน์แสดงสิ่งที่เป็นเจ้าของจริง |
| Feature ถูกซ่อน/emergency-off | ซ่อนเฉพาะความสามารถนั้นและคืน Standard; ไม่แก้ balance/history, ไม่ย้าย schema กลับ | `lib/runtime/registries/feature_registry.dart:59`–`:63` production ซ่อน planning/continuity/Adventure แม้ test เปิด `:83`; ต้องทดสอบ gate จริง ไม่เอามีโค้ด=เปิดใช้ |
| Research withdraw/permit หมดอายุ/ไม่มี authority | default-off; collection/upload ตรวจ owner/consent/assignment/permit authenticity+revision+expiry+revocation/protocol pins; ordinary learning เดินต่อได้ | `lib/features/research/application/research_participation_permit_validator.dart:38`; `lib/features/research/data/drift_research_sync_authorizer.dart:36`; nonparticipant ไม่มี research rows/events/outbox/uploads เพิ่ม |

ฐานปัจจุบันยืนยัน `AppDatabase.currentSchemaVersion = 24` ที่ `lib/data/local/app_database.dart:82`; ledger `docs/database/schema_ledger.md:454` ระบุสี่ตารางวิจัย รวม 48 ตารางที่ `:463` ไม่ใช่ 44 capabilities การจอง migration ครั้งใหม่ต้องตรวจ ledger ตอนเริ่ม implementation อีกครั้ง; memo นี้ไม่จองหมายเลข

ทุก owner-state ใหม่ต้องรวม owner migration/upgrade, tombstones, deletion order, export allowlist, outbox/sync conflict/policy validation และ cancellation side effects; จุดเชื่อมเดิมคือ `lib/features/identity/domain/owner_lifecycle_manifest.dart:484`, `:502`, `:518`, `lib/features/export/application/owner_lifecycle_archive.dart:661`, `lib/features/account/application/local_data_deletion.dart:118` และ owner operation gate ของ sync ไม่ใช้ SharedPreferences ปลีกย่อยเพื่อหลบ coverage

Rollback ระยะอ่านใช้ feature gate/ถอด view กลับของเดิมได้โดยคง canonical data; หลังเพิ่ม durable schema ต้อง forward-only compatibility/repair release และหยุด writer ใหม่ ไม่ใช้ binary เก่าเปิดฐานใหม่ ไม่ลบข้อมูลผู้เรียนเพื่อกลับ version (`schema_ledger.md:448`, `:466`) สำหรับ recurrence ต้อง reconcile cancellation ก่อนปิด entrypoint ไม่ปล่อย OS notifications ค้าง

## 5. ข้อขัดกันในประวัติและทางประนีประนอม

- V2 ต่อต้าน dual database/big-bang และกำหนดหนึ่ง authority (`2026-08-03-lexiquest-v2-evolution-framework-design.md:59`, `:68`, `:74`): เพิ่มคำอธิบาย/การเลือกของเดิมได้ แต่ persistent planning ต้องเป็น authority ของ “แผน” เท่านั้น ไม่เป็น mastery/reward authority
- Convergence กำหนด local authoritative/cloud additive (`2026-08-08-lexiquest-complete-field-trial-convergence-design.md:24`): P6 ใหม่ต้อง optional แยก availability; ไม่ยกระดับ server/social ให้เป็นเงื่อนไขเริ่มเรียนหรือ export local
- Adventure เดิมเป็น rebuildable map ไม่เพิ่ม progress table (`2026-09-01-adventure-motivation-mode-design.md:18`–`:24`): แผนรายสัปดาห์ที่ผู้ใช้แก้เป็นคนละข้อเท็จจริง อย่าอ้างว่าทุกอย่าง derive ได้; ถ้าบันทึกต้องอนุมัติขอบเขต domain ใหม่ตามข้อเสนอ B
- ledger v24 ยังเขียน RESERVED (`schema_ledger.md:457`) แต่ runtime เป็น v24 และรายงาน 5–7 ก.ย. ระบุ engineering complete: ใช้ code+latest evidence ระบุ implementation status โดยไม่แก้ ledger รอบนี้; คำว่า RESERVED ไม่อนุญาตใช้ v24 ซ้ำ และ complete ไม่ใช่สิทธิ์ enroll/upload
- P3 ใหม่ต้องเพิ่ม catalog version เมื่อ title/objective/reward เปลี่ยน (`quest_catalog_provider.dart:10`) และเก็บ active instance pins (`quest_use_cases.dart:166`, `:379`); จึงเลื่อน objective ใหม่จนกำหนด eligible event/filter และ rollover ของ instance เก่าได้ ห้าม retrofit อดีตหรือรวม optional voice
- P6 ขัด no-social เฟสแรกอย่างตรงไปตรงมา: คงนอกเฟสปัจจุบันและนอก 8/44 ที่ freeze; ถ้ามีเสียงผู้ใช้จริงสนับสนุนค่อยทำ extension proposal ที่แยก relationship/permission/abuse/data-retention และค่าใช้จ่ายดูแลอย่างยั่งยืน ไม่ให้รายได้เป็นเหตุบังคับเด็กใช้ social

## 6. UX/UI boundary ตามคำขอเพิ่มของผู้ใช้

ความเรียบร้อยและรูปแบบคุ้นเคยจาก Duolingo/ALLTCAS ควรอยู่ใน presentation composition: layout/tokens/typography/spacing, reusable action card, Thai copy และ avatar asset mapping; read model ส่งสถานะ+reason+actions ที่อนุญาต ไม่ส่งสิทธิ์ให้ widget สร้างคะแนนหรือสั่ง session จาก animation callback ไม่คัดลอกแบรนด์/leaderboard/social มาเพียงเพราะเป็นภาพต้นแบบ

Today ต้องคง primary action เด่นหนึ่งจุดตามงานที่มีจริง พร้อม disclosure ของเป้าหมาย/พัฒนาการ/ภารกิจที่รองลงมา; ไม่เพิ่มการ์ดทุก P จน resume/assigned/repair หลุดจอแรก การ์ดแชร์ design system เดียวกับห้าปลายทางเดิมและมี navigation outcome ชัดเจน

Animation เป็น transient presentation state ผูก receipt identity ที่ committed แล้ว; scene reload/back/owner switch ไม่ trigger domain mutation; reduced-motion ใช้ static outcome ที่ให้ความหมายเท่ากัน ไม่ block CTA เพื่อรอ animation และห้ามใช้แสง/เสียงเป็นสัญญาณสำเร็จเพียงอย่างเดียว

Whole-screen QA ในงาน implementation ต้องดูชุด Today → Standard/Adventure → config → lesson → result → History และ goals/reminder/avatar ไม่ใช่ snapshot การ์ดเดี่ยว; ตรวจ 320/360dp, large text/Thai wrapping, keyboard+safe areas, semantics/focus, loading/empty/stale/pending/error/disabled/owner-transition/reduced-motion/offline และงบ asset/layout performance บนอุปกรณ์เป้าหมายจริง ภาพที่สวยไม่ยืนยัน eligibility และ unit tests ไม่ยืนยัน layout/UAT รุ่นใหม่

## 7. คำท้าทายสำหรับ cross-review

BA/U1/U2: ก่อนใช้คำว่า “แผนเพื่อเป้าหมาย” ต้องมีคำตอบจากผู้เรียนว่าเนื้อหาใดสัมพันธ์กับเป้า; deadline/title ไม่ใช่หลักฐาน linkage และ population research ไม่ใช่ UAT ของเด็กผู้ใช้จริง

PM/DEV: ขอแยก deliverable “อ่านแผน/เตือนครั้งเดียว” ออกจาก “แผนรายสัปดาห์ที่บันทึก/เกิดซ้ำ”; อย่ารวมแค่เพราะหน้าตาคล้ายกัน หากเลือก schema ใหม่ต้องรับ lifecycle/rollback ครบ ส่วน QA ควรตรวจ delta จาก canonical sources และ source-bound device evidence ไม่ตรวจแค่ว่าการ์ดแสดง

## Cross-review และข้อสรุปหลังโต้แย้ง

อ่าน `03-cross-review-brief.md`, `02-design-evidence.md` และ U2/U5/DEV/QA; ปรับข้อสรุปตามคำขอ UX/UI ที่สวยเรียบร้อยและคุ้นเคยอย่างชัดเจน ภาพ fixture ที่ root ตรวจเป็นข้อมูลประกอบ ไม่ใช่ device/UAT ใหม่
**C1 — ต่อ U2:** ภาพปลายทาง “15 นาทีเพื่อสอบ/ปรับแผนเมื่อเหลือ 5 นาที” มีคุณค่า แต่ข้อมูล goal ปัจจุบันยังไม่ผูกชุดคำหรือ workload; รับข้อสรุปหลังโต้แย้งของ U2 ที่แยกภาพปลายทางออกจากระยะแรก และคงการคัดค้านคำว่า adaptive/พร้อมสอบใน deadline card
ยอมให้ deadline + คิวงานเดิมอยู่ร่วมกันและกางรายละเอียดได้; การปรับ “เวลาที่ชอบ” ไม่ใช่การทำนายเวลาจบ และไม่ลด due/reorder assigned/repair/resume เงียบ ๆ การผูก goal-content เป็น domain ระยะถัดไปตาม B
**C2 — ต่อ U5:** รับเหตุผลว่าซื้อ/สวมแล้วไม่เห็นภาพเป็นช่องว่างประสบการณ์เดิม จึงยืนยัน P5 static preview พื้นที่เดียวควบคู่ระยะแรก ไม่ต้องรอ weekly plan หรือพิสูจน์คะแนนสอบก่อน
ขอบเขต P5 ที่รับตรง DEV/U5 คือ bundled assets จำกัดสำหรับ ID/version ที่รองรับ, preview แยก equipped จริง, fallback ชื่อ และไม่มี catalog/economy ใหม่; หาก asset/renderer ไม่พร้อมให้เลื่อนเฉพาะ P5 ไม่ขวางการคืนทางเรียนหลัก
**C3 — ต่อ U5/U2:** รับทางเลือกฝึก 2–3 ทางจาก safe modes พร้อมเหตุผล และยังเลือกสำรวจได้; ไม่ใช้คำว่าเลือก Quest ใหม่ เพราะ catalog/instance lifecycle ปัจจุบันไม่ให้ opt-in/swap แบบนี้ และไม่ให้โบนัสจากเลือกกิจกรรม
สิ่งที่ไม่ยอมแลกคือ Quest version/eligibility/assignment-time/instance pins และ immutable source receipts; repair/replay/optional voice ได้ผลตาม purpose/eligibility เดิม ห้าม reinterpret เพื่อเพิ่ม quest variety
**C4 — รับข้อแก้จาก DEV:** สัญญา suggested action ในส่วน 3 เป็นข้อเสนอ ไม่ใช่ API ที่มีแล้ว; `TodayHubActionDelegate` ยังไม่มี openGoals/openReminders และ Today snapshot ไม่มี preferences การ์ดที่กดได้จึงต้อง integrator เพิ่ม delegate/wiring/implementers ในงานเดียว
ขอบเขตนี้เป็น application composition/route integration ไม่สร้าง authority ใหม่; compose preference แบบ owner-bound ผ่าน reader/use case เดิม ตรวจ snapshot/gate ตอนกด ห้าม query จาก widget build หรือสร้าง session ระหว่าง load/opening
**C5 — ต่อ U2/QA/DEV:** ยอมลด P2 รุ่นแรกให้บอกข้อเท็จจริงรอบนี้หรือ profile ที่มีช่วงเวลา/denominator จริง; derived progress เป็นการอ่านข้อเท็จจริง ไม่ใช่ใบอนุญาตเพิ่ม score/trend ใหม่ เพราะไม่มีตารางใหม่ก็ยังเปลี่ยนความหมายการวัดได้
คำว่า “ดีขึ้น/จำได้ระยะยาว/พร้อมสอบ” ต้องมีชุดคำ ชนิดหลักฐาน assistance ช่วงเวลา และจำนวนตัวอย่างที่เทียบกัน; noEvidence/unavailable ไม่ใช่ศูนย์ และ XP/อุปกรณ์/เสียงเสริมไม่ชดเชยหลักฐานที่ขาด
**C4/C10 — รูปแบบที่รับ:** ทางเลือก 2 ใน design dossier คงห้าแท็บและ canonical next action หนึ่งจุด ใช้ลำดับตัวอักษร/พื้นที่ว่าง/ไอคอน+คำไทยสม่ำเสมอและ feedback สั้น ไม่วาด curriculum path/ด่านปลดล็อกที่ไม่มีข้อมูลรองรับ
recognition ใน UX ลดการจำชื่อเมนู/ตำแหน่งปุ่มเท่านั้น; ห้ามเติมเฉลย/ตัวเลือกใน independent-recall task แล้วคง evidence class เดิม การ polish ต้องรักษาจังหวะเลือก→ตรวจ→บันทึก→feedback และทางข้ามเสียง
**C6/C8 — Owner และ opening:** เปิดหน้า/เปลี่ยน layout/ลองดูภาพไม่สร้าง learning/reward session ใหม่; ตรวจ opening snapshot/exposure เดิมกับ assigned presentation อีกครั้ง ไม่ให้ home preference หรือ visible card กลายเป็น consent/permit/assignment authority
Research ยัง default-off; participant สังเคราะห์ต้องผ่าน collection/upload guards และ protocol/instrument pins เดิม ส่วน nonparticipant ไม่มี research rows/events/outbox/uploads เพิ่ม; ไม่เปิดสัมภาษณ์/เก็บข้อมูลเด็กเพราะ prototype ได้รับการออกแบบแล้ว
Owner switch ต้อง invalidate snapshot/preview/async completion; reminder cancel/reconcile ผ่าน authority เดิมก่อนเลิกใช้ owner ห้ามซ่อนเฉพาะการ์ดแล้วปล่อย OS notification เก่า หรือเอา recurring rule ไปฝากใน preferences/title
**C10 — รับ QA:** ต้นแบบ Learn/Today→goal→lesson/result→avatar ต้องมี empty/pending/error/disabled ก่อน implementation แล้วตรวจทั้ง flow บน source เดียวหลัง UI ครบ; 390×844/text100, 360×800/text200+keyboard, TalkBack/reduced motion/offline ต้องรักษา CTA/back และความหมาย
Acceptance ชี้ขาดคือ action delegate เปิดงาน/content identity ที่สอดคล้องกับ authority, preview/เปิดซ้ำ/owner transition ไม่มี delta, การ retry หลัง commit ไม่เพิ่ม attempts/SRS/Quest/XP/Coins และภาพที่ใช้จริงตรง inventory; golden/fixture/4,964 tests เดิมไม่ปิด gate ใหม่
**C7/ประวัติ:** P6 ยังแยก capability/no-social/8–44 scope decision; v24 runtime กับ ledger RESERVED เป็นข้อมูลประวัติที่ยังไม่สอดคล้อง ไม่ใช่ runtime block ไม่จองเลขซ้ำ และ rollback ห้าม binary เก่าเปิด DB ใหม่
ข้อสรุปสุดท้าย: เลือก B ระยะแรกเป็น polished UI/composition + local deadline/reminder เดิม + ผลที่มีบริบท + P5 เล็กเมื่อแยกงานได้; linkage/weekly persistence/recurrence/Quest ใหม่ทำตาม contract ภายหลัง รอบนี้แก้เอกสารเท่านั้น ไม่มี implementation/tests/UAT/rollout ใหม่
