# Measurement Decision Spec — Adventure Motivation Mode

**Document ID:** LQ-AMM-MDS-001
**Version:** 1.2
**Status:** Planning thresholds; protocol approval required before enrollment
**Date:** 2026-09-04
**Applies to:** Android-only Pilot v1, adult and minor strata, under ADR-002/003/005/007/008 และ Pair Matching Prototype measurement guardrails under ADR-009–013

## 1. Purpose

เอกสารนี้กำหนด measurement population, timepoint, estimand, missing-data policy, sample rule, feasibility gate และ efficacy gate ที่ใช้ตัดสิน Adventure Motivation Mode โดยแยก Motivation, Engagement, Effort, Learning และ Safety ออกจากกันอย่างชัดเจน App open, XP, Coin, streak, animation view หรือ map tap ไม่ใช่ motivation endpoint

## 2. Measurement principles

1. Motivation เป็น primary endpoint จาก bounded validated instrument ที่ตอบโดยสมัครใจ
2. Engagement เป็น secondary behavior ไม่ใช่ motivation proxy
3. Learning เป็น outcome/guardrail; ห้ามแลก learning quality กับ engagement
4. ITT เป็น primary analysis ตาม assigned treatment แม้ presentation switch/crossover
5. Standard และ Adventure ใช้ neutral events/opportunity contract เดียวกัน
6. participant denominator มาจาก `MeasurementOpportunity`; ห้ามอนุมานจาก event ที่ capture สำเร็จ
7. nonparticipant zero-row: ไม่มี permit/opportunity/response/research event/outbox/upload
8. adult และ minor เป็น pre-specified strata; powered sample และ release decision แยก class
9. UAT/MS-08A พิสูจน์ feasibility/usability/comprehension ไม่ใช่ efficacy
10. threshold, timepoint, imputation และ analysis code ต้อง pre-register ก่อน enrollment และห้ามผ่อนหลังเห็นผล

## 3. Population and participation contract

### 3.1 Eligibility

ผู้เข้าร่วมต้องมี `ResearchParticipationPermit` ที่:

- owner, stable assignment, protocol/version และ assigned treatment ตรงกัน
- active consent ครบ
- `participantClass` เป็น `adult` หรือ `minor` และมี approved `ageBandCode`
- minor มี guardian permission และ learner assent receipt references ทั้งคู่
- signature/payload SHA-256/revisions ตรวจสอบผ่าน ยังไม่หมดอายุ ไม่ถูก revoke/delete
- Android build/content/instrument/form อยู่ใน approved Pilot matrix

Product Entry รับเฉพาะ `ActivePresentationPermit` projection และไม่อ่าน raw receipts การไม่มี/ถอน permit ไม่ตัดสิทธิ์เรียน แต่ห้ามใช้ protocol treatment และห้ามสร้าง research data ใหม่

### 3.2 Analysis populations

- **ITT primary:** ทุก owner ที่ randomized และได้รับ valid permit ก่อน first authorized Host opening วิเคราะห์ตาม assigned treatment
- **Safety:** ทุก participant ที่เปิด authorized Host หรือเริ่ม accepted session
- **Per-protocol supportive:** ผู้ที่มี active permit ครบ window และไม่มี major protocol deviation; ไม่แทน ITT
- **Nonparticipant:** ไม่อยู่ใน research population และต้องมี research row เท่ากับศูนย์

การถอน consent/assent หลัง randomization ไม่ลบคนออกจาก ITT โดยอัตโนมัติ การใช้ข้อมูลที่มีอยู่และ deletion ใช้ approved protocol/retention policy และต้องรายงาน disposition โดยไม่ imputing เหตุผลว่าเป็น negative motivation

## 4. Opportunity and neutral event policy

หนึ่ง authorized Host opening สร้าง `entryAttemptId` UUID v4 หนึ่งครั้งและ participant-only opportunity หนึ่ง row:

```text
TodayExperiencePresented
TodayExperiencePresentationChanged
TodayExperienceMissionStarted
TodayExperienceMissionCompleted
```

- event ทุกชนิด pin `assignedTreatment` และ `effectivePresentation`
- `lastSwitchOrdinal` emit ได้ 1–10 แบบ transactional; ส่วนเกินเพิ่ม `suppressedSwitchCount`
- Presented/Changed ผูก opportunity; Started/Completed ผูก accepted `learningSessionId` และ opportunity เดิม
- capture completeness = opportunities ที่มี required event/linkage ครบ ÷ eligible opportunities
- replay ใช้ deterministic identity และห้ามเพิ่ม numerator/denominator ซ้ำ

## 5. Exact endpoint definitions

| Axis | Metric | Exact definition | Role |
|---|---|---|---|
| Motivation | `postMotivationNormalizedScore` | approved post form score mapped monotonically 0–100 | Primary outcome |
| Motivation | `baselineMotivationNormalizedScore` | approved baseline form score mapped 0–100 | Required covariate |
| Motivation | `motivationChangeScore` | post − baseline | Supportive |
| Engagement | `voluntaryMissionStartRate` | opportunities with an accepted voluntary start ÷ eligible opportunities | Secondary |
| Engagement | `missionCompletionRate` | completed accepted sessions ÷ accepted sessions, excluding typed technical invalidation | Secondary |
| Engagement | `return7dRate` | eligible owners with voluntary canonical start during days 1–7 after index session ÷ owners with complete window | Secondary |
| Effort | `activeDurationBucket` | canonical active-learning-time bucket; idle/background excluded | Descriptive |
| Effort | `guidedResponseRate` | guided eligible responses ÷ all eligible responses | Descriptive |
| Learning | `independentRecallAccuracy` | correct independent-recall evidence ÷ eligible independent-recall evidence | Guardrail |
| Learning | `reviewResolutionRate` | due review items resolved under existing SRS policy ÷ due items admitted | Guardrail |
| Reliability | `duplicateEvidenceOrRewardCount` | confirmed duplicate canonical evidence/side effect from one source identity | Stop guardrail |
| Safety | `criticalIntegrityPrivacyAccessibilityCount` | confirmed S0/S1 issue in evidence, owner isolation, participation, Standard escape or required accessibility flow | Stop guardrail |

### 5.1 Primary timepoints

1. baseline ต้อง completed หลัง permit issuance และไม่เกิน 24 ชั่วโมงก่อนผู้เรียนเห็น treatment presentation ครั้งแรก
2. first treatment exposure คือ `TodayExperiencePresented` รายการแรกของ permit หลัง baseline
3. index session คือ accepted learning session แรกหลัง first treatment exposure
4. post ต้อง completed หลัง index session status `completed` และภายใน 30 นาทีของ canonical completion timestamp
5. response ก่อน completion, เกิน 30 นาที, ผิด form/version หรือไม่มี reconstructible index session เป็น protocol deviation และไม่ใช้เป็น observed primary post
6. ผู้ที่ไม่เริ่มหรือไม่ complete index sessionยังอยู่ใน ITT และใช้ missing-data policy ไม่ถูกตัดออก

## 6. Primary estimand and analysis

```text
ITT motivation effect by participant class
= adjusted mean(postMotivationNormalizedScore | assigned Adventure)
 - adjusted mean(postMotivationNormalizedScore | assigned Standard)
```

Primary model เป็น ANCOVA ของ post score โดยปรับ baseline score และ pre-registered covariates เท่านั้น: prior canonical learning activity bucket และ instrument form; age ใช้เพียง randomization stratum/class และ approved age-band term ห้ามเลือก covariate หลังเห็นผล

รายงาน adult และ minor แยกกันพร้อม treatment estimate, standard error, two-sided 95% CI, sample disposition และ missingness ห้าม pool เพื่อให้ class ที่ sample ไม่ครบผ่าน gate การวิเคราะห์ pooled interaction เป็น secondary เท่านั้น

## 7. Missing-data policy

1. primary ITT ใช้ pre-registered multiple imputation ภายใน participant class โดยรวม treatment, baseline, permitted pre-treatment covariates และ observed outcome predictors ที่ระบุล่วงหน้า
2. จำนวน imputations อย่างน้อย `max(20, ceil(percentMissingPost))` และใช้ Rubin's rules
3. complete-case result เป็น supportive
4. tipping-point sensitivity shift imputed Adventure outcomes ลงและ/หรือ Standard outcomes ขึ้นตาม grid ที่ pre-register จน conclusion เปลี่ยน พร้อมรายงาน tipping value
5. missing post รวมมากกว่า 15% ใน class ใด หรือ absolute arm difference มากกว่า 5 percentage points ให้ class นั้น **ห้ามผ่าน MS-08B** ไม่ว่าค่า estimate จะผ่าน
6. ห้ามเติมค่าศูนย์, last observation carried forward หรือ exclude non-completer แบบ post-randomization ใน primary analysis

## 8. Efficacy thresholds

participant class มีสิทธิ์ผ่าน MS-08B เมื่อครบทุกข้อ:

1. adjusted ITT motivation effect ≥ +5.0 points บนสเกล 0–100
2. two-sided 95% CI lower bound > 0.0
3. one-sided 95% lower bound ของ independent-recall difference > −3 percentage points
4. one-sided 95% lower bound ของ review-resolution difference > −5 percentage points
5. duplicate evidence/reward count = 0
6. critical integrity/privacy/accessibility count = 0
7. permit/opportunity/assignment/version metadata completeness = 100%
8. missing-data gate ใน §7 ผ่าน
9. powered sample ของ class นั้นครบ
10. class-specific UAT/comprehension gate ผ่าน

Engagement สูงขึ้นโดย motivation หรือ learning ไม่ผ่าน ห้าม claim ว่ากระตุ้นแรงจูงใจสำเร็จ

## 9. Sample-size rule

Research Lead คำนวณและ sign แยก `adult`/`minor` ก่อน enrollment ด้วย effect 5 points, two-sided alpha 0.05 และ power 0.80:

```text
n_per_arm_motivation_raw
  = ceil(2 × (1.96 + 0.84)^2 × sigma^2 ÷ 5^2)
n_per_arm_motivation
  = ceil(n_per_arm_motivation_raw ÷ (1 - expectedAttritionRate))

n_per_arm_guardrail_raw
  = ceil(2 × (1.645 + 0.84)^2 × p0 × (1 - p0) ÷ margin^2)
n_per_arm_guardrail
  = ceil(n_per_arm_guardrail_raw ÷ (1 - expectedAttritionRate))

final_n_per_arm_per_class
  = max(n_per_arm_motivation,
        n_per_arm_independent_recall,
        n_per_arm_review_resolution)
```

- `sigma` มาจาก validation evidence หรือ blinded estimate ที่ระบุไว้ล่วงหน้า
- `p0` มาจาก frozen Standard estimate; หากไม่มีใช้ 0.50
- attrition อยู่ช่วง 0.00–0.30 และ pin ก่อน enrollment
- repeated/cluster design ต้องเพิ่ม pre-registered design effect
- ห้าม optional stopping เว้นแต่มี sequential boundary ที่อนุมัติล่วงหน้า

## 10. MS-08A Feasibility gate

MS-08A ผ่านได้เมื่อ:

- eligible capture completeness ≥99%
- permit/assignment/version metadata =100%
- opportunity/event/session reconstruction =100%
- instrument completion ≥85% ของผู้ที่เปิด promptและไม่ Skip
- stop guardrails =0
- UAT และ comprehension minimums ผ่าน
- withdrawal/expiry/revocation cutoff และ nonparticipant zero-row ผ่าน 100%

ผลสูงสุดหลัง MS-08A คือ `Limited` เพื่อทำ approved study ต่อ ห้าม Controlled Expansion/Enabled และห้าม efficacy claim

## 11. MS-08B Efficacy gate and class isolation

- รันเมื่อ powered sample, analysis freeze และ evidence package ของ class นั้นครบ
- adult ผ่านไม่ได้ทำให้ minor ผ่าน และ minor ผ่านไม่ได้ทำให้ adult ผ่าน
- class ที่ไม่ครบ sample/guardrail/comprehension/missing-data gate ต้องคง Limited หรือหยุด
- Controlled Expansion/Enabled เฉพาะ class ที่ผ่าน §8 พร้อม Product, Research, Privacy, QA และ Accessibility sign-off
- critical guardrail สามารถ emergency-off ทั้งหมดหรือ class-specific ตาม blast radius

## 12. UAT sample and acceptance

### 12.1 General learners

- อย่างน้อย 12 คน และมี minors อย่างน้อย 4 คน
- required general flow ≥11/12; confirmed shame/coercion/false mastery =0

### 12.2 Accessibility

อย่างน้อย 4 moderated sessions ครอบคลุม TalkBack, Switch Access/keyboard, text 200% narrow viewport และ reduced-motion/high-contrast/no-audio อาจ overlap กับ general sample ได้ แต่ต้องบันทึก profile แยก

Research Prompt, guardian permission, learner assent, Standard escape, permit invalid/expired, withdrawal และ focus restoration ต้องผ่าน profile ที่เกี่ยวข้องทุก session; aggregate percentage ใช้กลบ critical failureไม่ได้

### 12.3 Research comprehension

- adult research comprehension อย่างน้อย 10 คน; **10/10** เข้าใจ Skip, withdraw และ no-learning-impact
- guardian–learner dyads อย่างน้อย 5 คู่
- guardian **5/5** และ learner **5/5** ต้องตอบ Skip/withdraw/no-learning-impact ได้แยกกัน
- ผู้ที่ไม่ผ่านห้าม enroll จน copy/process ถูกแก้และ retest

## 13. Android Pilot matrix

| Profile | Minimum research/minor coverage | Evidence |
|---|---|---|
| Mainstream Android | UAT-001–038 ตาม applicability | full core, permit, opportunity, gate decision |
| Small phone + text 200% | Research Prompt, guardian, assent, invalid permit | layout, target, focus restoration |
| TalkBack | prompt, guardian, assent, withdrawal, Standard continuation | traversal, role, state, action |
| Switch Access/keyboard | prompt, guardian, assent, withdrawal | focus order, no trap, restored focus |
| Offline | signed permit validation, expiry/revocation-known state, learning continuation | fail-closed permit; product remains usable |
| Corrupt asset/config | authorized-Host Standard fallback; unauthorized route returns Learn | no loop, bounded reason |
| Pair Matching prototype | UAT-039–050 across regular/focused and timer choices | G4P learning/usability evidence only; not efficacy |

iOS, desktop, AI Voice และ field model เป็น excluded from Pilot v1 และห้ามนับเป็น pass

## 14. Decision matrix

| Evidence | Decision |
|---|---|
| stop guardrail >0 | emergency-off / stop / investigate |
| nonparticipant research row >0 | stop; privacy/integrity incident |
| MS-08A ผ่าน แต่ powered sample ไม่ครบ | remain Limited; no efficacy conclusion |
| efficacy threshold ผ่าน แต่ missing-data gate ไม่ผ่าน | remain Limited; no expansion |
| adult MS-08B ผ่าน; minor ไม่ผ่าน/ไม่ครบ | expand adult only; minor remains Limited |
| class ผ่าน MS-08B ทุก threshold | eligible for class-specific controlled expansion |
| UAT/comprehension ไม่ผ่าน | revise UI/copy/process and retest |

## 15. Required evidence package

- protocol/pre-registration ID, version and dated approvals
- permit issuer key/version, signature/revocation verification report
- assignment and participant-class reconstruction
- instrument/form/scoring checksums
- class-specific sample-size inputs/output and approval
- opportunity/event/session completeness report
- frozen analysis code/version and immutable input fingerprint
- ITT ANCOVA table, MI diagnostics, complete-case and tipping-point results
- learning/safety/accessibility guardrail report
- UAT numerator/denominator and comprehension records
- Android device/build matrix and explicit exclusions
- MS-08A and MS-08B signed decisions per participant class

## 16. Pair Matching Prototype measurement annex

### 16.1 Measurement position

Pair Matching เป็น learning activity ภายใต้ f10 ไม่ใช่แรงจูงใจโดยตัวมันเอง จึงห้ามใช้ดาว เวลา ความเร็ว จำนวน replay, tap, animation หรือ completion เพียงลำพังเป็นหลักฐานว่า Adventure “เพิ่มแรงจูงใจ” หรือ “เพิ่ม mastery” การประเมินแรงจูงใจระดับระบบยังใช้ primary endpoint และ gate ใน §5–§11 เท่านั้น

ต้นแบบต้องแยกสามชั้น:

| ชั้น | แหล่งข้อมูล | ใช้ตัดสิน | ห้ามตีความเป็น |
|---|---|---|---|
| Learning evidence | committed answer-role ledger และ canonical SRS/Review evidence | independent/guided/incorrect และ delayed recall | reward, motivation หรือความเร็ว |
| Session projection | matched count, stars, active elapsed, timely status, repair count | อธิบายรอบที่เพิ่งเล่นและ usability | mastery score, currency หรือ efficacy |
| Product/research measurement | neutral events + participant-only opportunity + approved instrument | feasibility/efficacy ตาม protocol | telemetry ของ nonparticipant หรือ replay reward |

### 16.2 Pair outcome and guardrail definitions

| Axis | Metric | Exact definition | Role |
|---|---|---|---|
| Learning | `pairFirstOpportunityAccuracy` | คู่ที่ตอบถูกแบบ independent ใน first answer opportunity ÷ คู่ที่มี first opportunity ใน normal learning sessions | Learning process |
| Learning | `pairIndependentCompletionRate` | คู่ที่ complete แบบ independent ก่อน answer reveal ÷ exact plan pair count | Learning process |
| Support | `pairGuidedCompletionRate` | คู่ที่ terminal role เป็น guided ÷ exact plan pair count | Support/usability |
| Repair | `pairRepairDueResolutionRate` | repair tickets ที่กลับมาตาม 2/3 distinct-success policy และ resolved ÷ tickets ที่มี spacing เพียงพอ | Contract guardrail |
| Review | `pairDeferredRecallResolutionRate` | tail-guided words ที่มี independent canonical Review result ใน approved follow-up window ÷ tail-guided words due in that window | Learning guardrail |
| Reliability | `pairDuplicateOrLostEvidenceCount` | logical attempt/repair/round/extension ที่สร้าง duplicate หรือหายจาก one-operation contract | Stop guardrail |
| Equity | `pairLayoutOutcomeGap` | independent-completion difference ระหว่าง regular กับ focused layout หลังแบ่งตาม density/direction และ accessibility profile | Diagnostic guardrail |
| Usability | `pairVoluntaryContinuationRate` | timeout decisions ที่เลือก Continue untimed ÷ timeout decisions ที่แสดง choice ครบ | Descriptive only |

ดาว 1–3 ดวงคำนวณตาม `starPolicyVersion` จาก terminal ledger เท่านั้นและรายงานเป็น distribution ห้ามเฉลี่ยรวมกับ mastery; session ไม่ complete ต้องเป็น `incomplete` ไม่ใช่ 0 ดาว

### 16.3 Timer interpretation

- timer default OFF และการเลือก 60/90/120 เป็น self-selection จึง **ห้าม** เปรียบเทียบ timer groups เป็น causal effect โดยตรง;
- `activeElapsedMs` ตัด background, modal, persistence wait และ required accessibility narration ตาม policy; wall-clock ไม่ใช้ตัดสินผู้เรียน;
- timely status, +30, Continue untimed และ Restart ห้ามเปลี่ยน stars, learning evidence, SRS, Mastery หรือ reward เมื่อ answer ledger เท่ากัน;
- เวลาแสดงเพื่อ feedback ส่วนบุคคลเท่านั้นใน prototype; ห้าม leaderboard, percentile หรือ pressure copy;
- หากต้องการทดลอง timer ในอนาคต ต้องมี protocol/randomization/consent/permit/analysis amendment แยกก่อน exposure

### 16.4 Practice Replay exclusion

Session `purpose=practiceReplay`:

1. ไม่อยู่ใน denominator/numerator ของ primary motivation, voluntary mission start, canonical completion, independent recall, review resolution หรือ Today due-resolution;
2. ไม่สร้าง reward/mastery/SRS/Weakness/global accuracy/quest/streak/achievement delta;
3. เก็บได้เฉพาะ bounded reliability/usability diagnostic และ history ที่ label ชัด ภายใต้ policy ที่อนุมัติ;
4. ต้อง link source session แบบ immutable เพื่อ audit แต่ห้าม overwrite latest/best normal outcome;
5. การเล่นซ้ำจำนวนมากห้ามถูกแปลว่า motivation สูงโดยไม่มี approved instrument

### 16.5 Required stratification and denominator rules

รายงาน Pair metrics ต้องแบ่งอย่างน้อยตาม:

- `pairCount`: compact4 / standard6;
- `direction`: enToTh / thToEn;
- `source`: Learn / Today / Review / Adventure พร้อม merged provenance category;
- `timerChoice`: off / 60 / 90 / 120 และ path: timely / extended / continuedUntimed / restarted;
- `presentation`: Standard / Adventure;
- `layout`: regular / focused;
- accessibility profile, offline state และ approved device class เมื่อ sample disclosure-safe

ห้ามรวมกลุ่มจนซ่อน critical failure, ห้ามรายงาน cell ที่ต่ำกว่า approved disclosure threshold และห้ามใช้ pair-size preference, assistive technology หรือ guardian setting เป็นตัวแทนอายุ/ความสามารถ

### 16.6 Event and privacy contract

- participant ใช้ neutral events เดิม `TodayExperienceMissionStarted` และ `TodayExperienceMissionCompleted` พร้อม pinned `assignedTreatment`, `effectivePresentation`, plan/policy fingerprints และ bounded Pair summary; Standard/Adventure ห้ามใช้ชื่อ event คนละชุด;
- `MeasurementOpportunity` ยังคงเป็น denominator ของ research exposure; Pair activity/restart/rebuild ห้ามสร้าง opportunity ใหม่;
- Timeout Restart เป็น round ใหม่ใน Learning Session เดิม โดยคงชุดคำศัพท์ หลักฐานที่บันทึกแล้ว และสิทธิ์ต่อเวลาที่ใช้ไป; Practice Replay เป็น session ใหม่แต่ excluded ตาม §16.4;
- nonparticipant สร้าง research row/event/outbox/upload เท่ากับศูนย์; operational diagnostics ต้อง bounded/local-or-approved และไม่มี raw word/meaning;
- ห้ามส่ง private vocabulary ไป remote TTS/analytics โดยไม่มี policy และ consent ที่อนุมัติ;
- payload ต้องมี schema/policy version และผ่าน export/withdrawal/deletion/retention lifecycle เมื่ออยู่ใน research scope

### 16.7 Pair prototype decision gate

Pair Matching Prototype ผ่าน `G4P` ได้เมื่อ:

1. PMT-001–044 และ UAT-039–050 ผ่านตาม applicability;
2. duplicate/lost evidence, replay authority delta, star currency/ledger และ silent filler/downgrade = 0;
3. repair spacing, timeout restore, one-extension entitlement, checkpoint compatibility และ Standard/Adventure parity ผ่าน 100% ของ deterministic fixtures;
4. accessibility required path ผ่านทุก moderated session และไม่มี critical clipping/trap/focus loss;
5. ผู้แทนอย่างน้อย 11/12 อธิบายได้ว่าดาว/เวลาไม่ใช่ mastery/reward และ Practice Replay ไม่เร่ง SRS;
6. outcome report แยก density/direction/source/timer/layout และไม่ทำ causal claim จาก self-selected timer;
7. Product, Learning/Data, UX/Accessibility, QA และ Tech ลงนาม Accept

การผ่าน `G4P` อนุญาตให้ใช้ต้นแบบเพื่อ internal validation เท่านั้น ไม่ทำให้ Adventure ผ่าน MS-08A/MS-08B และไม่อนุญาต Controlled Expansion/Enabled โดยอัตโนมัติ

## 17. Pair Matching required evidence package

- normalized `PairMatchingPlanV1` fixtures และ fingerprints สำหรับทุก entry/density/direction;
- curated EN–TH eligibility/collision validation report โดยไม่เผย private vocabulary;
- reducer/property/idempotency/race/recovery test report;
- repair timeline และ tail-deferral audit;
- timer active-time/pause/restore/extension/restart evidence;
- star rebuild fixtures และ proof ว่าไม่มี currency/reward/mastery write;
- Practice Replay cross-projection before/after diff;
- Standard/Adventure normalized parity diff;
- reader-first checkpoint compatibility/rollback matrix;
- accessibility/device/localization evidence และ UAT comprehension numerator/denominator;
- signed `G4P` decision พร้อม build/commit/config fingerprints

## 18. Change control

ก่อน enrollment การเปลี่ยน endpoint/timepoint/threshold/instrument/sample/imputation/strata ต้องผ่าน Product + Research + Privacy approval และ protocol version bump หลัง enrollmentต้องเก็บ analysis เดิม รายงาน amendment และถือผลใหม่เป็น secondary/exploratory เว้นแต่ ethics/statistical governance อนุมัติเป็นอย่างอื่น

Pair Matching หลัง prototype หากเปลี่ยน star threshold, repair spacing, timer choice, density inference, replay eligibility, telemetry field หรือ causal claim ต้องแก้ ADR/SRS/SDS/MDS/RTM และ test fixtures ใน revision เดียวกัน การเปลี่ยนที่กระทบ research endpoint/denominator ต้องผ่าน protocol amendment ก่อน exposure

## 19. Approval

| Role | Decision | Name | Date | Evidence reference |
|---|---|---|---|---|
| Product Owner | Approve / Revise |  |  |  |
| Research Lead/Statistician | Approve / Revise |  |  |  |
| Privacy/Ethics Owner | Approve / Revise |  |  |  |
| QA/Data Quality Lead | Approve / Revise |  |  |  |
| Accessibility Owner | Approve / Revise |  |  |  |
