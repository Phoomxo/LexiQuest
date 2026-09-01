# Architecture Decision Records — Adventure Motivation Mode

**Document ID:** LQ-AMM-ADR-001
**Version:** 1.0
**Status:** Proposed Decisions for Owner Approval
**Date:** 2026-09-01
**Baseline:** LexiQuest `99f7fb21`, Drift schema v22

## 1. Purpose

เอกสารนี้ปิดความกำกวมที่พบจากรอบ critic โดยกำหนด decision ที่เอกสาร TOR/SRS/SDS/WBS/UI/Test/UAT/RTM และ Implementation Plan ต้องยึดร่วมกัน หากมีเอกสารขัดกันให้ ADR นี้มีอำนาจเหนือ design ระดับล่าง แต่ไม่เหนือ TOR/SRS ที่แก้ให้สอดคล้องแล้ว

## ADR-001 — Production Entry Uses the Existing Learn Surface

**Status:** Accepted for planning

### Context

Today Hub มี implementation แต่ `dailyContinuity` ยัง hidden ใน production baseline ขณะที่ Adventure อาศัย Today snapshot เป็น canonical work source การเขียนเพียงว่า “Existing Today destination” จึงไม่พอสำหรับ implementation และเสี่ยงให้นักพัฒนาเพิ่ม navigation ใหม่ตามความเข้าใจตนเอง

### Decision

1. Adventure v1 **ไม่เพิ่ม bottom-navigation destination** และไม่เปลี่ยนลำดับ destination เดิม
2. Internal prototype เปิดผ่าน guarded internal route เท่านั้น ไม่มี learner-facing navigation entry
3. Production-eligible entry เป็น additive card/action หนึ่งรายการใน Learn surface เดิม ใช้ stable route identity `learn/today-experience`
4. Card แสดงต่อเมื่อ:
   - Adventure feature visibility ไม่ใช่ hidden;
   - invocation enabled;
   - Today snapshot dependency พร้อมและ owner identity ตรงกัน;
   - world/content revision ที่จำเป็น verify ผ่าน
5. การกด card เปิด `TodayExperienceHost` ภายใต้ Learn navigation family; host compose Today snapshot หนึ่งครั้งแล้วเลือก Standard หรือ Adventure presentation
6. หาก Adventure hidden/off แต่ Today host ยังถูกเปิดจาก stale route ให้ render Standard Today presentation เมื่อ dependency พร้อม; ถ้า Today dependency ไม่พร้อมให้กลับ Learn พร้อม bounded reason
7. “มุมมองมาตรฐาน” เปลี่ยน presentation ภายใน host เดิม ไม่ stack home route; system Back จาก host กลับ Learn
8. Feature-off ต้องทำให้ Learn surface เทียบเท่า baseline: ไม่มี card, spacing ghost หรือ dead route

### Consequences

- Flow เดิมไม่เปลี่ยนเมื่อ feature hidden
- ไม่จำเป็นต้องเปิด Today เป็น bottom tab
- ต้องเพิ่ม route-ledger entry และ navigation tests ก่อนสร้าง shell
- UI prototype กับ production entry มีคนละ gate; internal route ห้ามหลุด production

### Rejected alternatives

- **New Adventure bottom tab:** กระทบ information architecture และ flow เดิมมากเกินไป
- **Reuse `LearningWorldMapScreen`:** ไม่มี canonical caller/authority และมี static CEFR state
- **Replace Learn screen with Adventure:** ทำลาย feature-off equivalence และเข้าถึงฟังก์ชันเดิมยากขึ้น

## ADR-002 — Product Entry and Research Capture Are Separate Decisions

**Status:** Accepted for planning

### Context

Consent กำหนดสิทธิ์ประมวลผลข้อมูลวิจัย ไม่ใช่สิทธิ์ใช้ Adventure หาก consent อยู่ใน product entry resolver มีความเสี่ยงที่ผู้ใช้ไม่ยินยอมแล้วถูกปิดฟีเจอร์หรือถูกเลือก presentation ต่างจากที่ควร

### Decision

ใช้ decision สองชนิดที่ไม่เรียกกันเพื่อ mutation:

```text
AdventureProductEntryDecision
  inputs: owner, feature state, dependencies, catalog/content, stable assignment,
          session choice, learner preference
  output: effective Standard/Adventure presentation + bounded fallback reason
  forbidden input: research consent receipt or measurement response

AdventureResearchCaptureDecision
  inputs: owner, candidate event, stable assignment, consent snapshot,
          active measurement run, protocol/event versions
  output: eligible / ineligible(reason)
  effect: may authorize one idempotent research record; never changes presentation
```

Rules:

1. Product use continues when research decision is ineligible
2. No consent, no active run, assignment conflict or withdrawal → zero research row/outbox/upload
3. Feature, preference, consent and assignment never rewrite one another
4. Product UI may show consent details only inside an approved optional research prompt

### Consequences

- M01 does not depend on `ConsentRegistry`
- M10 owns consent lookup and must fail closed
- UAT can prove “Adventure works + zero research rows” for nonparticipants

## ADR-003 — Exposure Event Identity Depends on Lifecycle Stage

**Status:** Accepted for planning

### Context

`AdventurePresented` และบาง `AdventureSwitchedToStandard` events เกิดก่อนมี `AdventureSessionPlan` หรือ `learningSessionId` จึงไม่สามารถบังคับทุก exposure event ให้ใช้ learning-session aggregate ได้

### Decision

| Event | Aggregate type | Aggregate ID | Correlation ID | Deterministic occurrence key |
|---|---|---|---|---|
| `AdventurePresented` | `AdventurePresentation` | `entryDecisionId` | `adventurePlanId` เมื่อมี มิฉะนั้น null | `presented:<measurementRunId>:<entryDecisionId>` |
| `AdventureSwitchedToStandard` | `AdventurePresentation` | `entryDecisionId` | `adventurePlanId` เมื่อมี มิฉะนั้น null | `switch-standard:<measurementRunId>:<entryDecisionId>:<switchOrdinal>` |
| `AdventureMissionStarted` | `LearningSession` | `learningSessionId` | `adventurePlanId` required | `mission-start:<measurementRunId>:<learningSessionId>` |
| `AdventureMissionCompleted` | `LearningSession` | `learningSessionId` | `adventurePlanId` required | `mission-complete:<measurementRunId>:<learningSessionId>` |

Additional rules:

1. `entryDecisionId` เป็น transient product identity ที่สร้างแบบ deterministic ต่อ owner-operation scope; ไม่เข้า EvidenceContext
2. `switchOrdinal` เป็น bounded integer 1–10 ต่อ entry decision; event ที่เกินถูก aggregate เป็น diagnostic counter ไม่สร้าง research row เพิ่ม
3. Event ID derive จาก event type + occurrence key + eventVersion ผ่าน existing event identity policy
4. Nonparticipant หรือ ineligible research capture decision สร้าง event เหล่านี้เป็นศูนย์
5. `EventEnvelopeV2` keyset ไม่เปลี่ยน

### Consequences

- Pre-session และ session events ตรวจย้อนกลับได้โดยไม่ปลอม learning session
- RTM/Test ต้องแยกกรณี before-plan, after-plan และ replay

## ADR-004 — Product MVP Has an Independent Stop/Accept Point

**Status:** Accepted for planning

### Context

แผนเต็ม 294 person-days ครอบคลุม product shell, learning integration, preference, companion, research และ rollout การถือทั้งหมดเป็น deliverable เดียวเพิ่มความเสี่ยงต่อระบบเดิมและทำให้ไม่สามารถหยุดหลังพิสูจน์แนวคิดได้

### Decision

แบ่ง funding/acceptance เป็นสี่ independently closable increments:

| Increment | Included | Schema | Exit decision |
|---|---|---|---|
| A — Read-only Preview | baseline seams, hidden feature, catalog, deterministic journey, Map/List, internal route | v22 unchanged | Accept preview / revise / stop |
| B — Product Core MVP | canonical learning bridge, repair, result, restart, emergency-off | v22 unchanged | **MS-04 Product MVP Accept / Stop / Continue** |
| C — Product Extension | durable preference, read-only reward receipts, companion | preference migration only | Accept extension / keep session-local |
| D — Research Add-on | instrument, research tables/events/rules/lifecycle, consented Pilot | research migration | Pilot / revise / stop research |

Stopping after Increment A or B is a successful bounded outcome when its acceptance criteria pass; it is not a failed incomplete release. No schema migration is required to archive or remove A/B.

### Consequences

- Research cannot delay acceptance of a safe Product Core MVP
- Preference/companion can be deferred without reworking learning evidence
- WBS/contract must show separate budgets and change-control decisions

## ADR-005 — Pilot v1 Is Android-Only and Capability-Scoped

**Status:** Accepted for planning

### Context

Baseline has iOS Podfile/platform-contract, field-model and optional backend dependency findingsที่ไม่เกี่ยวกับทุก Adventure path การบังคับปิดทุก finding ก่อน Android-only Pilot อาจหยุดงานโดยไม่เพิ่มความปลอดภัย ขณะเดียวกันการละเว้นแบบไม่ประกาศจะลด release coverage

### Decision

1. First consented Pilot target คือ Android release/profile build เท่านั้น
2. Required Pilot capabilities: Learn/Today host, local learning, SRS/Review, canonical reward projection, packaged Adventure world, offline recovery, identity/sync/export/research pathsที่ Pilot เรียกใช้
3. iOS, desktop, AI Voice และ field-model capabilities เป็น `Excluded from Pilot v1`, ไม่ใช่ “ผ่าน”
4. Finding ของ capability ที่ excluded ยังคงเป็น release blocker ก่อนเปิด Adventure บน capability/platform นั้น
5. Android Pilot ยังต้องผ่าน full Flutter logical suite; platform/model/backend gates ใช้เฉพาะส่วนที่ reachable ตาม approved capability matrix
6. การเพิ่ม platform หรือ capability ต้องเป็น change request พร้อม rerun gate ที่เกี่ยวข้อง

### Consequences

- G0B เปลี่ยนจาก blanket closure เป็น zero unclassified failure ใน shared/touched foundation + green Android Pilot matrix
- เอกสารต้องรายงาน exclusions อย่างเปิดเผยและห้ามอ้าง cross-platform readiness

## 2. Decision Compliance Checklist

- [ ] Learn entry ไม่มีผลเมื่อ hidden และไม่มี bottom tab ใหม่
- [ ] `learn/today-experience` อยู่ใน route ledger และ stable navigation tests
- [ ] Product entry resolver ไม่มี consent dependency
- [ ] Research capture decision ไม่มีอำนาจเปลี่ยน presentation
- [ ] Pre-session/session event identities ตรงตาราง ADR-003
- [ ] MS-04 มี owner decision และ stopping path
- [ ] Preference/Research migrations ไม่ถูกทำก่อน increment gate
- [ ] Pilot evidence ระบุ Android-only และ exclusions
- [ ] Platform/capability expansion ผ่าน change control

## 3. Approval

| Role | Decision | Name | Date | Notes |
|---|---|---|---|---|
| Product Owner | Approve / Revise |  |  |  |
| Tech Lead | Approve / Revise |  |  |  |
| UX Owner | Approve / Revise |  |  |  |
| QA Lead | Approve / Revise |  |  |  |
| Research/Privacy Owner | Approve / Revise |  |  |  |
