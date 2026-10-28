# Architecture Decision Records — Adventure Motivation Mode

**Document ID:** LQ-AMM-ADR-001
**Version:** 1.2
**Status:** Accepted for planning
**Date:** 2026-09-04
**Baseline:** LexiQuest `99f7fb21`, Drift schema v22
**Authority:** TOR/SRS/SDS/WBS/UI/Test/UAT/RTM และ implementation plan ต้องสอดคล้องกับ ADR ชุดนี้

## 1. Purpose and precedence

เอกสารนี้ปิดประเด็นจาก Critic รอบที่ 2 และ multi-agent debate ของ Pair Matching Prototype แบบ contract-first โดยไม่แก้ย้อนหลัง Current System Audit v1.0 หากเอกสารระดับล่างขัดกับ ADR นี้ ให้ใช้ ADR นี้และ Measurement Decision Spec v1.2 เป็นข้อกำหนดอ้างอิง แล้วแก้เอกสารระดับล่างใน change set เดียวกัน

## ADR-001 — Production entry uses the existing Learn surface

### Decision

1. Adventure v1 ไม่เพิ่ม bottom-navigation destination และไม่เปลี่ยนลำดับ destination เดิม
2. Production entry เป็น additive card/action ใน Learn surface เดิม ใช้ navigation identity `home/learn/today-experience`
3. Card แสดงเมื่อ feature visible, invocation enabled, owner ตรงกัน, Today dependency พร้อม และ content revision ตรวจสอบผ่านเท่านั้น
4. การเปิด card ที่ผ่าน authorization จะสร้าง `entryAttemptId` แบบ UUID v4 หนึ่งครั้งต่อ Host opening แล้ว reuse ระหว่าง widget rebuild, loader retry และ presentation switch ของ opening เดิม
5. hidden, disabled, unknown หรือ stale direct route ต้องกลับ Learn พร้อม bounded reason โดยห้ามสร้าง `TodayExperienceHost`, Today snapshot, research opportunity หรือ Standard presentation
6. Standard fallback ใช้ได้เฉพาะภายใน `TodayExperienceHost` ที่ผ่าน entry authorization แล้ว เช่น Adventure content เสียหลัง Host เปิด หรือ active permit หมดอายุระหว่าง Host lifecycle
7. “มุมมองมาตรฐาน” เปลี่ยน presentation ใน Host เดิม ไม่ stack home route; system Back จาก Host กลับ Learn
8. emergency-off บล็อก Host ใหม่และ mission start ใหม่ทันที ส่วน accepted learning session ที่เริ่มแล้วต้องปิด/retire ตาม canonical lifecycle เดิมก่อนกลับ Learn/Standard
9. เมื่อ feature hidden Learn surface ต้องเทียบเท่า baseline: ไม่มี card, spacing ghost, dead route หรือ write side effect

### Consequences

- route ledger และ stable navigation test ต้องใช้ identity เต็ม `home/learn/today-experience`
- direct-route test ต้องแยก “ก่อน authorization” ซึ่งกลับ Learn ออกจาก “หลัง Host authorization” ซึ่งอนุญาต Standard fallback
- internal prototype route ต้องไม่ถูก expose ใน production navigation

## ADR-002 — Protocol treatment requires an active presentation permit

### Context

Product Entry ต้องไม่อ่าน raw consent/guardian/assent receipt แต่ treatment assignment ใน protocol จะมีผลต่อ presentation ได้ต่อเมื่อสิทธิ์วิจัยทั้งหมดตรวจสอบแล้ว การแยก raw receipts ออกจาก Product Entry ลด coupling และยังทำให้ withdrawal หยุด treatment presentation ได้จริง

### Decision

```text
ResearchParticipationPermit
  id, ownerId, participantClass, ageBandCode
  assignmentId, assignedTreatment
  consentReceiptId
  guardianPermissionReceiptRef?  // required for minor
  learnerAssentReceiptRef?       // required for minor
  protocolId/version
  issuedAtUtc, expiresAtUtc, revokedAtUtc?
  issuerKeyId, payloadSha256, signature
  localRevision, cloudRevision, isDeleted

ActivePresentationPermit
  permitId, ownerId, assignedPresentation
  protocolId/version, assignmentId, expiresAtUtc
```

1. Research enrollment authority ออก `ResearchParticipationPermit`; แอปไม่ออก permit เอง
2. `ActivePresentationPermit` เป็น read-only projection หลังตรวจ owner, assignment, active consent, guardian permission และ learner assent สำหรับ minor, protocol/version, expiry, revocation, signature และ revision conflict แล้ว
3. Product Entry อ่านได้เฉพาะ `ActivePresentationPermit` และห้ามเห็น consent, guardian หรือ assent fields/receipts
4. protocol treatment มี precedence เฉพาะเมื่อ projection active; permit หาย, invalid, expired หรือ revoked ให้ fallback ตามลำดับ `session choice → LearnerPreferences.homeExperience → Standard`
5. withdrawal ต้อง invalidate projection ก่อน operation ถัดไปและห้ามเริ่ม treatment Host/session ใหม่ ผู้ใช้ยังใช้การเรียนแบบ product ปกติได้
6. nonparticipant และผู้ที่ไม่มี active permit ใช้ session choice/preference ได้ แต่ไม่มี protocol treatment หรือ research rows
7. feature state, preference, assignment, consent และ permit ห้าม rewrite กัน

### Consequences

- Product Entry ไม่มี raw consent dependency แต่มี narrow dependency ต่อ active projection
- offline entry ใช้ได้เฉพาะ permit ที่ลายเซ็นถูกต้อง ยังไม่หมดอายุ ไม่ถูก revoke ตาม local/cloud revision ที่รู้ล่าสุด และผ่าน protocol policy
- withdrawal race, expired permit และ invalid signature เป็น blocking tests

## ADR-003 — Neutral event policy and independent opportunity ledger

### Decision

ทั้ง Standard และ Adventure ใช้ event policy v1 ชุดเดียวกัน:

```text
TodayExperiencePresented
TodayExperiencePresentationChanged
TodayExperienceMissionStarted
TodayExperienceMissionCompleted
```

```text
MeasurementOpportunity
  id, ownerId, measurementRunId, permitId
  entryAttemptId, assignedTreatment, effectivePresentation
  presentedEventId?
  learningSessionId?, startedEventId?, completedEventId?
  lastSwitchOrdinal, suppressedSwitchCount
  openedAtUtc, closedAtUtc?
```

Rules:

1. เมื่อ participant เปิด Host ที่ authorized ให้สร้าง/เปิด opportunity หนึ่ง row ด้วย deterministic ID จาก `measurementRunId + permitId + entryAttemptId`
2. `TodayExperiencePresented` ใช้ opportunity เป็น aggregate และ pin ทั้ง `assignedTreatment` กับ `effectivePresentation`
3. presentation change ใช้ transaction เพิ่ม `lastSwitchOrdinal` ช่วง 1–10 และ emit event ด้วย occurrence key ที่รวม ordinal; หลัง 10 เพิ่มเฉพาะ `suppressedSwitchCount`
4. mission started/completed ผูก `learningSessionId` และ update event IDs ใน opportunity เดิม โดยไม่เปลี่ยน canonical learning event
5. participant denominator มาจาก opportunity ledger ไม่อนุมานจากจำนวน exposure events
6. nonparticipant เก็บ `entryAttemptId` เป็น transient UI stateเท่านั้น และต้องสร้าง permit/opportunity/research event/outbox/upload เป็นศูนย์
7. `EventEnvelopeV2` keyset ไม่เปลี่ยน; event ID ใช้ existing deterministic event identity policy
8. replay/rebuild/retry ต้อง reuse opportunity/event identity และห้ามนับซ้ำ

### Consequences

- เปรียบเทียบ Standard/Adventure ได้แบบ symmetric
- ตรวจ capture completeness ได้แม้ Presented event บางรายการล้มเหลว
- ต้องเพิ่ม opportunity lifecycle, sync, rules, export, withdrawal, deletion และ retention coverage

## ADR-004 — Product MVP has an independent stop/accept point

แบ่งงานเป็นสี่ independently closable increments:

| Increment | Included | Base effort | Schema consequence | Exit decision |
|---|---|---:|---|---|
| A — Read-only Preview | baseline seams, hidden feature, catalog, deterministic journey, Host/View, Map/List | 90 pd | v22 unchanged | Accept preview / revise / stop |
| B — Product Core MVP | canonical learning bridge, repair, result, restart, emergency-off | 48 pd | v22 unchanged | **MS-04 Accept / Stop / Continue** |
| C — Product Extension | durable preference, canonical motivation receipts, companion | 48 pd | preference migration only | Accept extension / keep session-local |
| D — Research, Minor Participation and Rollout | permit, measurement, minor UX, lifecycle, UAT, efficacy gates | 168 pd | research migration only | Limited / revise / stop / class expansion |

การหยุดหลัง Increment A หรือ B เป็น bounded outcome ที่สมบูรณ์เมื่อ gate ผ่าน Product Core MVP/MS-04 ต้องปิดได้โดยไม่มี research migration

## ADR-005 — Pilot v1 is Android-only and capability-scoped

1. Pilot v1 ใช้ Android release/profile build เท่านั้น
2. required capabilities คือ Learn/authorized Today Host, local learning, SRS/Review, canonical reward projection, packaged world, offline recovery และ research lifecycle ที่ Pilot เรียกใช้
3. iOS, desktop, AI Voice และ field model เป็น explicit exclusions ไม่ใช่ pass
4. expansion platform/capability ต้องผ่าน change control และ rerun gate ที่เกี่ยวข้อง
5. Android Pilot ต้องมี zero unclassified failure ใน shared/touched foundation และ approved Android matrix

## ADR-006 — Today snapshot is loaded exactly once per Host opening

### Decision

```text
TodayExperienceHost
  authorize navigation and create/reuse entryAttemptId
  TodayHubSnapshotLoader.load() exactly once
  resolve ActivePresentationPermit/session choice/preference
  render TodayHubView(snapshot) or AdventureHubScreen(snapshot)

TodayHubScreen
  legacy destination loader wrapper
  load once, then render TodayHubView(snapshot)

TodayHubView(snapshot)
  pure Standard presentation; no loader/repository dependency
```

1. Standard และ Adventure ใน Host เดียวกันต้องใช้ snapshot object/fingerprint เดียวกัน
2. presentation switch, rebuild และ focus restoration ห้าม trigger load ใหม่
3. explicit refresh ปิด opportunity/Host lifecycle เดิม แล้วสร้าง Host opening และ `entryAttemptId` ใหม่
4. owner switch หรือ stale async result ต้อง discard ก่อน render/write

## ADR-007 — Minor participation is guardian-led and runtime-enforced

1. research รองรับ `participantClass = adult | minor` และ randomization แยก strata
2. guardian-led approved enrollment flow ออก signed permit โดยเก็บเพียง `ageBandCode`; ห้ามเก็บวันเกิดเต็มหรือ guardian PII ในแอป
3. minor permit ต้องมีทั้ง `guardianPermissionReceiptRef` และ `learnerAssentReceiptRef`; ขาดอย่างใดอย่างหนึ่ง projection ต้อง invalid
4. learner ปฏิเสธ/ถอน assent ได้โดยไม่เสียสิทธิ์เรียน และ invalidation ต้องใช้กติกาเดียวกับ consent withdrawal
5. guardian permission, learner assent และ research prompt ต้องผ่าน TalkBack, Switch Access, text 200%, offline permit validation และ focus restoration
6. governance checklist อย่างเดียวไม่ถือว่าเป็น runtime enforcement

## ADR-008 — Feasibility and efficacy are separate release gates

| Gate | Purpose | Maximum resulting state |
|---|---|---|
| MS-08A Feasibility | data quality, usability, consent/assent comprehension, safety, reconstructibility | `Limited` |
| MS-08B Efficacy | powered class-specific sample, primary motivation endpoint, learning and safety guardrails | Controlled Expansion/Enabled เฉพาะ class ที่ผ่าน |

1. Small Pilot หรือ MS-08A ห้ามนำไป Enabled และห้าม claim motivation efficacy
2. adult/minor class ใด sample, comprehension หรือ guardrail ไม่ครบ class นั้นต้องคง Limited แม้อีก class ผ่าน
3. Controlled Expansion และ Enabled เริ่มได้เฉพาะ class ที่ MS-08B ผ่านและมี signed release decision
4. emergency/critical guardrail มีอำนาจย้อนกลับเป็น Limited/Hidden แยกตาม class หรือทั้งหมด

## ADR-009 — Pair Matching is a major revision of existing f10

### Decision

1. Pair Matching Experience ใช้ `FeatureContractId.f10`, `LessonMode.matching`, `activityType=matching`, route `learning/matching`, Unified Lesson Shell และ Evidence Gateway เดิม
2. M12 ในเอกสารชุดนี้เป็น logical planning module สำหรับ prototype integration เท่านั้น ไม่ใช่ capability `f45`
3. Learn tile เดิมคงเป็น secondary/free-practice entry เพื่อไม่ทำ regression ขณะ Today ยัง hidden; Today, Review และ Adventure เพิ่ม contextual launch โดยไม่เพิ่ม main/bottom navigation
4. Matching ยังคงเป็น `recognition` หรือ `guidedPractice`; source ที่มาจาก Due SRS/Weakness ไม่ยกระดับให้เป็น independent recall และไม่ปิด/เร่ง SRS interval
5. Pair-specific delivery state ต้อง map กลับ `f10`, default hidden และ compose กับ parent Quiz gate ที่ composition root; ห้ามใช้ broad Quiz flag เป็น emergency control เพียงตัวเดียว
6. Adventure presentation gate คงแยกจาก Pair delivery gate; Adventure unavailable ต้อง fallback Standard Pair เมื่อ `f10` ยัง authorized

### Consequences

- ไม่มี pair database, star wallet, reward authority หรือ engine แยกตาม Standard/Adventure
- change นี้ต้อง bump semantic contract, checkpoint codec และ test fixtures แต่ไม่เปลี่ยน serialized feature inventory 8/44

## ADR-010 — Pair plan is immutable, entry-aware and exact-sized

### Decision

1. ทุก launch resolve เป็น `PairMatchingPlanV1` ซึ่ง pin owner, exact `wordId/contentRevision/checksum`, merged source reasons, direction, pair count, source/target orders, shuffle seed, timer preset, policy versions และ session purpose
2. Today launch reuse Today snapshot เดิม; Review launch reuse exact selected Review items; Learn launch ใช้ composer กลาง; Adventure รับ exact plan จาก Standard path และห้าม recompose
3. Candidate ต้อง merge provenance และ deduplicate ตาม lexical identity ก่อน rank/filter; reported, deleted, stale revision, duplicate visible label และ ambiguous many-to-one pair ต้องถูก reject
4. Prototype รองรับหนึ่ง direction ต่อ session: `enToTh` หรือ `thToEn`; mixed direction ยัง out of scope
5. Board ต้องมี exact 4 หรือ 6 คู่ตาม resolved product preference เท่านั้น ผู้ขอ 6 แต่ safe content เหลือ 4 ต้องยืนยัน launch ใหม่เป็น 4; ต่ำกว่า 4 เป็น typed unavailable
6. Product preference precedence คือ guardian override → explicit learner/accessibility preference → one-time choice; หากไม่สามารถถามได้ให้ safe fallback 4 โดยห้ามอนุมานวัยจาก DOB, CEFR, XP, speed, error rate หรือ research permit
7. MVP ใช้ curated EN–TH allowlist และ locale-aware visible-collision validation; ไม่เพิ่ม `senseId` หรือ vocabulary authority ใหม่เพียงเพื่อ prototype

## ADR-011 — Progress, evidence and delayed repair remain separate

### Decision

1. User-visible `matchedProgress` เพิ่มเฉพาะเมื่อ canonical pair สำเร็จและไม่ลด; wrong answer ไม่เพิ่มและไม่ลดค่า
2. first opportunity, attempt ordinal, support use และ repair state เป็นแกนแยก ห้ามนำ generic `session.score` มาแทน completion หรือ stars
3. mismatch สร้าง incorrect recognition หนึ่งรายการให้ prompt-side canonical word ตาม pinned direction; distractor ไม่ได้รับ incorrect evidence
4. Normal repair กลับหลัง distinct other correctly resolved pairs: 2 สำหรับ board 4 คู่ และ 3 สำหรับ board 6 คู่; tap, deselect, hint, audio, animation, technical retry และเวลาไม่นับ interval
5. หลัง corrective mapping หรือ answer-revealing semantic support การตอบซ่อมเป็น `guidedPractice`; pronunciation/screen-reader speech ของข้อความที่มองเห็นอยู่ไม่ใช่ semantic hint
6. หนึ่ง scheduled repair ต่อ content ต่อ Learning Session เพื่อ bound loop/checkpoint; หากผิดซ้ำให้ guided completion และ canonical Review owns future independent recall
7. หากผิดช่วงท้ายและ distinct pairs ไม่พอ ให้ guided completion และ defer independent retry ไป Review โดยไม่สร้าง filler, bridge, progress ปลอม หรือ recursive repair

## ADR-012 — Timer, stars, restart and Practice Replay are orthogonal

### Decision

1. Timer default OFF; user opt-in เลือกได้เฉพาะ 60/90/120 วินาที และ timer outcome ไม่เปลี่ยน evidence eligibility, stars, reward, mastery หรือ SRS
2. Timer นับ accumulated active interactive time; pause เมื่อ board ใช้งานไม่ได้, app background, modal/system interruption, persistence retry และ required accessibility narration
3. Timeout เข้าสู่ durable decision stateโดยไม่สร้าง answer/incorrect/completion ผู้ใช้เลือก Continue untimed, Add 30 seconds ครั้งเดียว หรือ Restart same set
4. Add 30 seconds ใช้ idempotent operation และให้ 30 active seconds หลัง decision persist สำเร็จ; entitlement ต้อง survive recovery
5. Timeout Restart เป็น round ใหม่ใน Learning Session เดิม ใช้ lexical identities/revisions/direction เดิม, deterministic reshuffle ใหม่ และไม่ลบ evidence, round lineage หรือ extension entitlement เดิม
6. Practice Replay เป็น Learning Session ใหม่ `purpose=practiceReplay` ที่ revalidate exact content และสร้าง evidence IDs ใหม่; ต่างจาก technical retry ซึ่ง reuse identity เดิม
7. Practice Replay บันทึกประวัติ/diagnostic ของรอบเองได้ แต่ SRS, Mastery, Weakness ranking, global proficiency/accuracy, XP, reward, quest, streak, achievement, Today due-resolution และ research primary outcome ต้อง no-op
8. Stars เป็น rebuildable read model จาก terminal session aggregate + committed attempt-role ledger: 3 ดาว = first-attempt correct ทุกคู่โดยไม่มี answer-revealing hint; 2 ดาว = independent completion อย่างน้อย 75% (`3/4`, `5/6`) โดย self-correction ก่อน reveal นับ; 1 ดาว = complete ที่เหลือ; incomplete ไม่มี 0 ดาว
9. Accessibility modality, timer, extension, continue untimed, layout และ presentation ไม่เป็น star input; History แสดง latest และ best แบบแยก normal learning จาก Practice Replay

## ADR-013 — Pair UI is adaptive, Thai-first and rollback-safe

### Decision

1. Effective width ที่รองรับใช้ two-column English↔Thai; narrow/text 200%/assistive mode ใช้ focused source-to-target list โดย engine/evidence เดียวกัน
2. Pair tile ขั้นต่ำ 56 logical px และ compact/young profile 64; action อื่นขั้นต่ำ 48×48; state ใช้ข้อความ+ไอคอน+เส้นขอบ ไม่พึ่งสี เสียง หรือ motion เพียงอย่างเดียว
3. Matched visual position คง placeholder เมื่อจำเป็นเพื่อลด layout jump แต่ semantic node ออกจาก traversal หลัง announce/focus restoration
4. Timeout sheet primary action คือ Continue untimed; Add 30 เป็น secondary; Restart เป็น tertiary และอธิบายว่าคำชุดเดิมจะถูกสลับใหม่
5. Result แยก matched/independent/assisted, stars, timer status, active elapsed time และ next Review; “ทันเป้าหมาย” เป็น praise เท่านั้น
6. Checkpoint รุ่นถัดไป deploy reader-first/writer-later; legacy v1–v5 resume ด้วย legacy behavior และห้าม infer stars/repair/replay readiness ย้อนหลัง
7. New starts ถูกบล็อกเมื่อ Pair gate/emergency-off ปิด แต่ accepted session ต้อง resume/retire ตาม canonical lifecycle; rollback ห้าม destructive down migration

## 2. Decision compliance checklist

- [ ] route ledger ใช้ `home/learn/today-experience`; hidden/disabled/unknown direct route กลับ Learn
- [ ] Standard fallback เกิดเฉพาะ authorized Host
- [ ] Product Entry เห็นเฉพาะ `ActivePresentationPermit` projection
- [ ] withdrawal/expiry/revocation หยุด treatment start แต่ไม่ปิดสิทธิ์เรียน
- [ ] Standard และ Adventure ใช้ neutral events/opportunity ledger เดียวกัน
- [ ] Host load Today snapshot ครั้งเดียวและ pure `TodayHubView(snapshot)`
- [ ] minor permit ตรวจ guardian permission + learner assent ใน runtime
- [ ] MS-08A จำกัดสถานะสูงสุดที่ Limited; MS-08B ตัดสินแยก adult/minor
- [ ] Product Core MVP ปิดได้โดยไม่มี research migration
- [ ] Android-only exclusions ถูกระบุโดยไม่อ้างว่า pass
- [ ] Pair Matching map กลับ `f10`; ไม่มี `f45`, main navigation, pair authority หรือ star currency
- [ ] `PairMatchingPlanV1` exact 4/6, entry-aware, ambiguity-safe และ Standard/Adventure ใช้ plan เดียวกัน
- [ ] Wrong ไม่เพิ่ม/ลด matched progress; repair interval 2/3 และ tail guided completion/no-padding ถูกใช้ตรงกัน
- [ ] Timer OFF/60/90/120, active-time, +30 once และ same-session restart recover ได้
- [ ] Stars 1–3 derive จาก committed ledger; 2 ดาวใช้ `3/4` และ `5/6`; timer/accessibility ไม่เป็น input
- [ ] Practice Replay ถูกตัดออกจากทุก canonical learning/motivation/research primary projection ตาม ADR-012
- [ ] Pair UI ผ่าน two-column/focused parity, TalkBack, Switch Access, 200% text และ focus restoration

## 3. Approval

| Role | Decision | Name | Date | Notes |
|---|---|---|---|---|
| Product Owner | Approve / Revise |  |  |  |
| Tech Lead | Approve / Revise |  |  |  |
| UX Owner | Approve / Revise |  |  |  |
| QA Lead | Approve / Revise |  |  |  |
| Research/Privacy Owner | Approve / Revise |  |  |  |
| Accessibility Owner | Approve / Revise |  |  |  |
