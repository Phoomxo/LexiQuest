# Measurement Decision Spec — Adventure Motivation Mode

**Document ID:** LQ-AMM-MDS-001
**Version:** 1.0
**Status:** Planning Thresholds; Protocol Approval Required Before Research Pilot
**Date:** 2026-09-01
**Applies to:** Android-only Pilot v1 under ADR-005

## 1. Purpose

เอกสารนี้กำหนดว่า “Adventure กระตุ้นแรงจูงใจสำเร็จ” หมายถึงอะไร แยก Motivation, Engagement, Effort, Learning และ Outcome อย่างชัดเจน พร้อมสูตร เกณฑ์ตัดสิน sample rule และ guardrails ที่ใช้ได้จริง โดยไม่ตีความ app open, XP หรือ streak เป็นแรงจูงใจโดยอัตโนมัติ

## 2. Measurement Principles

1. **Motivation is primary:** วัดจาก bounded instrument score ที่ผู้เข้าร่วมตอบโดยสมัครใจ
2. **Engagement is secondary:** start/completion/return เป็นพฤติกรรม ไม่ใช่แรงจูงใจโดยตัวมันเอง
3. **Learning is a guardrail and outcome:** Adventure ต้องไม่เพิ่ม engagement แลกกับ learning ที่แย่ลง
4. **Effort is descriptive:** active duration, hints และ repair ไม่ถูกรวมเป็นคะแนนคุณค่าคน
5. **Intention-to-treat is primary:** วิเคราะห์ตาม stable assignment แม้ crossover
6. **Nonparticipant zero-row:** ผู้ใช้ทั่วไปไม่มี research exposure/response row
7. **No efficacy claim from UAT:** UAT พิสูจน์ usability/comprehension ไม่ใช่ผลเชิงสาเหตุ
8. **No post-hoc threshold relaxation:** การเปลี่ยน threshold หลังเห็นผลต้องเป็น exploratory analysis และห้ามใช้ตัดสิน primary success

## 3. Measurement Population

### 3.1 Research population

- owner มี stable experiment assignment;
- active measurement run pin protocol/treatment/instrument/form/app/build/content/policy versions;
- consent active at capture time;
- guardian permission/learner assent ครบเมื่อ applicable;
- Android device/build อยู่ใน Pilot matrix;
- owner หนึ่งคนอยู่ใน primary analysis หนึ่ง assignment เท่านั้น

### 3.2 Exclusions from primary efficacy analysis

- invalid or missing assignment metadata;
- consent absent before first research capture;
- instrument version not in approved catalog;
- app/build outside Pilot matrix;
- integrity failure that makes learning-session linkage unreconstructible

Exclusion ไม่ลบ canonical learning data และต้องรายงาน count/reason ทุกประเภท การถอน consent ปฏิบัติตาม approved protocol/retention policy ไม่ถูกตีความเป็น negative motivation

## 4. Measurement Axes and Exact Definitions

| Axis | Metric | Exact definition | Role |
|---|---|---|---|
| Motivation | `motivationNormalizedScore` | approved instrument scoring result mapped monotonically to 0–100; higher = more autonomous willingness to continue | Primary |
| Motivation | `motivationDelta` | post-session score − pre-session score when protocol uses paired form | Primary supportive |
| Engagement | `voluntaryMissionStartRate` | unique eligible presentations followed by `AdventureMissionStarted`/Standard equivalent within the same assigned opportunity ÷ unique eligible presentations | Secondary |
| Engagement | `missionCompletionRate` | completed accepted sessions ÷ accepted sessions, excluding typed technical invalidation | Secondary |
| Engagement | `return7dRate` | owners with one voluntary eligible learning start in days 1–7 after index session ÷ eligible owners with complete observation window | Secondary |
| Effort | `activeDurationBucket` | existing active-learning-time policy bucket; background/idle excluded | Descriptive |
| Effort | `guidedResponseRate` | guided eligible responses ÷ all eligible responses | Descriptive |
| Effort | `repairOpportunityRate` | items offered one in-session repair ÷ incorrect eligible items | Quality |
| Learning | `independentRecallAccuracy` | correct independent-recall evidence ÷ eligible independent-recall evidence | Guardrail |
| Learning | `reviewResolutionRate` | due review items resolved per existing SRS policy ÷ due review items admitted | Guardrail |
| Reliability | `duplicateEvidenceOrRewardCount` | confirmed duplicated canonical evidence or canonical side effect from one source identity | Stop guardrail |
| Safety | `criticalIntegrityPrivacyAccessibilityCount` | confirmed S0/S1 issue in evidence, owner isolation, consent, Standard escape or required accessibility path | Stop guardrail |

XP, Coins, streak length, app opens, animation views และ map taps ห้ามใช้เป็น Motivation metric

## 5. Primary Estimand and Success Threshold

Primary estimand:

```text
ITT motivation effect
= adjusted mean(motivationNormalizedScore | assigned Adventure)
 - adjusted mean(motivationNormalizedScore | assigned Standard)
```

Adjustment covariates ต้อง pre-register ก่อน enrollment และจำกัดเฉพาะ baseline score, declared age band when ethically approved, prior canonical learning activity bucket และ instrument form; ห้ามเลือก covariate หลังเห็นผล

### Controlled-expansion success

Adventure มีสิทธิ์เข้าสู่ controlled expansion เมื่อครบทุกข้อ:

1. estimated ITT motivation effect ≥ **+5.0 points** บนสเกล 0–100;
2. two-sided 95% confidence interval lower bound > **0.0**;
3. one-sided 95% confidence lower bound ของ independent-recall accuracy difference (Adventure − Standard) > **−3 percentage points**;
4. one-sided 95% confidence lower bound ของ review-resolution-rate difference > **−5 percentage points**;
5. duplicate evidence/reward count = **0**;
6. critical integrity/privacy/accessibility count = **0**;
7. required metadata completeness = **100%**;
8. UAT comprehension gates ผ่าน

หาก motivation ไม่ผ่านแต่ engagement สูงขึ้น ห้ามกล่าวว่า Adventure กระตุ้นแรงจูงใจสำเร็จ

### Pilot feasibility success

Pilot อาจถือว่า feasibility ผ่านโดยไม่ claim efficacy เมื่อ:

- eligible research capture completeness ≥99%;
- assignment/version metadata =100%;
- instrument completion ≥85% ของผู้ที่เปิด promptและไม่ Skip;
- crossover/replay reconstruct ได้ 100%;
- stop guardrails =0;
- protocol-approved efficacy sample ยังไม่ครบ

ผล feasibility ใช้ตัดสิน “ทำการศึกษาต่อหรือไม่” ไม่ใช้เปิด Enabled แบบอ้างผลแรงจูงใจ

## 6. Sample Size Rule

Research Lead ต้องคำนวณก่อน enrollment ด้วย primary effect 5 points, two-sided alpha 0.05 และ power 0.80:

```text
n_per_arm_raw = ceil(2 × (1.96 + 0.84)^2 × sigma^2 ÷ 5^2)
n_per_arm = ceil(n_per_arm_raw ÷ (1 - expectedAttritionRate))
```

Learning guardrails ต้องมี non-inferiority power calculation แยก โดยใช้ margin เป็นสัดส่วน (`0.03` หรือ `0.05`):

```text
n_per_arm_guardrail_raw
  = ceil(2 × (1.645 + 0.84)^2 × p0 × (1 - p0) ÷ margin^2)
n_per_arm_guardrail
  = ceil(n_per_arm_guardrail_raw ÷ (1 - expectedAttritionRate))

final_n_per_arm
  = max(n_per_arm_motivation,
        n_per_arm_independent_recall,
        n_per_arm_review_resolution)
```

- `sigma` มาจาก approved instrument validation evidence หรือ blinded internal variance estimate ที่กำหนดไว้ใน protocol;
- `p0` มาจาก frozen Standard historical estimate ก่อน enrollment; หากไม่มีใช้ `0.50` แบบ conservative;
- `expectedAttritionRate` ต้องอยู่ช่วง 0.00–0.30 และ pin ก่อน enrollment;
- cluster/repeated-measure design ต้องเพิ่ม design effect ที่ pre-register;
- สูตร guardrail เป็น planning normal approximation; Statistician/Research Lead ต้องยืนยัน exact analysis method และปรับ sample เมื่อ baseline rate, repeated observations หรือ clustering ต้องใช้วิธีอื่น;
- ห้ามเริ่ม efficacy enrollment หากไม่มี inputs/outputs ทั้ง primary และ guardrail พร้อมลายเซ็น Research/Privacy Owner;
- ห้ามหยุดเมื่อผลดูดี เว้นแต่ protocol มี pre-registered sequential boundary

## 7. UAT Sample and Acceptance Rule

### 7.1 General learner UAT

- ผู้ใช้ตัวแทนขั้นต่ำ 12 คน;
- ทุกคนทำ UAT-001/002/005/007/011/014 และ comprehension questions;
- เกณฑ์ 90% แปลเป็นอย่างน้อย **11/12** ผ่าน;
- เกณฑ์ 85% แปลเป็นอย่างน้อย **11/12** ผ่าน;
- shame/coercion/false mastery confirmed finding =0

### 7.2 Accessibility UAT

อย่างน้อย 4 moderated sessions ซึ่งอาจ overlap กับ 12 คนได้:

1. Android screen-reader user;
2. Android Switch Access หรือ external-keyboard accessibility user บน supported Android test host;
3. text 200% + narrow Android viewport user;
4. reduced-motion/high-contrast/no-audio user

Required primary mission, Standard escape, Start, answer, Result และ error recovery ต้องผ่านทุก session; aggregate percentage ใช้กลบ critical accessibility failure ไม่ได้

### 7.3 Research comprehension UAT

- research participants ขั้นต่ำ 10 คนก่อน Pilot enrollment เต็ม;
- **10/10** ต้องระบุได้ว่า Skip/withdraw ได้และไม่กระทบสิทธิ์เรียน;
- ผู้ที่ตอบไม่ได้ต้องไม่ enroll จน copy/consent process ถูกแก้และ retest

## 8. Android Pilot v1 Matrix

| Profile | Required state | Required UAT coverage | Evidence |
|---|---|---|---|
| Small Android phone | logical viewport ≤360×640, text 100%/200% | 001/002/004/005/011/014/016/030/032 | layout, target, performance |
| Mainstream Android phone | current supported Android range, release/profile build | 001–032 ตามรอบที่ applicable; ทุก case อย่างน้อยหนึ่ง pass | full core/UAT/performance |
| Android tablet | portrait + landscape | 002/005/011/014/015/030/032 | responsive/List parity |
| TalkBack profile | screen reader on certified phone | 002/004/005/007/011/015–017/019/032 | traversal/action/state |
| Switch/keyboard profile | Android Switch Access หรือ external keyboard | 002/004/005/007/011/015–017/032 | focus/action/state |
| Offline profile | verified local world/content | 004/005/010/018/022/032 | complete/restart/sync replay |
| Corrupt asset profile | checksum mismatch | 004/019/022/032 | quarantine/repair/Standard |

เลข UAT ในตารางย่อจาก `UAT-xxx` และไม่หมายความว่าทุก case ต้องทำซ้ำบนทุก profile; mapping นี้เป็นขั้นต่ำ ส่วน case ที่แตะ profile เพิ่มต้องถูกเพิ่มตาม risk-based change review

iOS/desktop evidence ไม่ถูกนับเป็น Pilot v1 pass และเอกสารผลต้องเขียนว่า excluded

## 9. Decision Matrix

| Evidence | Decision |
|---|---|
| Stop guardrail >0 | Emergency-off / stop Pilot / investigate |
| Learning guardrail ต่ำกว่า margin | Stop expansion; investigate learning flow |
| Motivation threshold ผ่าน + guardrails ผ่าน | Eligible for controlled Android expansion |
| Motivation ไม่ผ่าน แต่ feasibility ผ่าน | Keep Limited; revise treatment or end study |
| Engagement เพิ่ม แต่ Motivation/Learning ไม่ผ่าน | Do not claim success; revise/stop |
| Sample/power ไม่ครบ | No efficacy conclusion; continue only under approved protocol |
| Metadata <100% | Primary analysis invalid; hold |
| UAT comprehension ไม่ผ่าน | Revise UI/copy before Pilot |

## 10. Required Evidence Package

- protocol ID/version และ dated pre-registration;
- instrument/form/scoring catalog IDs and checksums;
- sample-size inputs/output and approval;
- assignment/consent/run reconstruction report;
- analysis code/version and immutable input fingerprint;
- ITT primary table, confidence interval and missingness;
- crossover/adherence secondary table;
- learning/safety/accessibility guardrail report;
- UAT denominator/numerator per threshold;
- Android device/build matrix;
- Continue/Hold/Stop decision with signatories

## 11. Change Control

ก่อน enrollment เปลี่ยน threshold/instrument/sample rule ได้ผ่าน Product + Research + Privacy approval และ protocol version bump หลัง enrollment การเปลี่ยน primary endpoint, threshold หรือ exclusions ต้องรายงานเป็น amendment; analysis เดิมยังคงอยู่และผลใหม่เป็น secondary/exploratory เว้นแต่ ethics/statistical governance อนุมัติเป็นอย่างอื่น

## 12. Approval

| Role | Decision | Name | Date | Evidence reference |
|---|---|---|---|---|
| Product Owner | Approve / Revise |  |  |  |
| Research Lead | Approve / Revise |  |  |  |
| Privacy/Ethics Owner | Approve / Revise |  |  |  |
| QA/Data Quality Lead | Approve / Revise |  |  |  |
| Accessibility Owner | Approve / Revise |  |  |  |
