# R15 Source Register and Decision Traceability

> **Evidence reference — sequential-3 authority:** observed/inferred/proposed และข้อจำกัดการเก็บข้อมูลในไฟล์นี้ยังต้องรายงานตรงหลักฐาน. Execution/scope decisions เดิมปรับได้ตาม [Rule Register](../../development/2026-09-13-rule-supersession-register.md) และ [Active Index](../../development/full-system-active-index.md); เอกสารนี้ไม่ใช่ roadmap หรือสิทธิ์หยุดการพัฒนาตาม Master

วันที่ตรวจ 2026-09-12 · source baseline `8c160f87d77d8beb8ace2d8f2b7b0e92acb297ac`

อ่านกับ [engineering spec](2026-09-12-r15-engineering-spec.md) และ [acceptance contract](../plans/2026-09-12-r15-acceptance-contract.md). ตารางนี้ระบุว่าแหล่งใดสนับสนุนเรื่องใด ไม่ใช้รายชื่อ URL รวมท้ายเล่มแทนการอ้างเหตุผลรายข้อ

## 1. ประเภทและน้ำหนักหลักฐาน

- **U:** คำสั่งผู้ใช้ รวมการอนุญาตล่าสุดให้แทนข้อกำหนด UI/เกมเก่าที่เป็น workaround ด้วยรูปแบบที่เหมาะสมกว่า มีลำดับเหนือ design choices ในเอกสารเก่า
- **E:** ภาพ/วิดีโอจากการทดลองจริง พิสูจน์เฉพาะสิ่งที่เห็นและการกระทำที่บันทึก ไม่พิสูจน์ backend implementation หรือประสิทธิผลการเรียน
- **C:** source code / repo documents ที่ pin กับ commit; checkpoint เป็นผลย้อนหลังตาม SHA ของ checkpoint ไม่ย้ายผลผ่านมาที่ HEAD ใหม่
- **S:** เอกสารทางการสาธารณะ ใช้สนับสนุนหลักการที่ระบุ ไม่ใช้แทน hands-on ของ app version ที่ติดตั้ง
- **D:** การตัดสินใจของ LexiQuest เช่น spacing/timing/AI caps/model gates ระบุชัดว่าเลือกเองและต้องตรวจรับ ไม่มีแหล่งภายนอกอ้างว่าเลขเหล่านี้เหมาะที่สุด

แอปที่ทดลอง: Duolingo 5.141.12(2348), ALLTCAS 1.0.4(9), LDPlayer/Android9; ภาษาอังกฤษและหน้าระบบที่เกี่ยวข้อง. ไม่อ้าง Duolingo build นี้เป็นรุ่นล่าสุดทุก platform. การอ้างอิงนี้ไม่ครอบคลุมทุกแบบฝึก/ทุกหน้าพรีเมียม/เสียงจริง

## 2. Local evidence locator

Root ของภาพ/วิดีโอ: `C:/Users/Phet/.codex/visualizations/2026/09/12/01a095a8-40ba-7031-817d-406822b5d3aa`

- [รายงานทดลองภาษาอังกฤษ](C:/Users/Phet/.codex/visualizations/2026/09/12/01a095a8-40ba-7031-817d-406822b5d3aa/duolingo-alltcas-english-study.md)
- [รายงาน AI และทิศทาง UI](C:/Users/Phet/.codex/visualizations/2026/09/12/01a095a8-40ba-7031-817d-406822b5d3aa/lexiquest-ui-ai-direction.md)
- [วิเคราะห์รวม](C:/Users/Phet/.codex/visualizations/2026/09/12/01a095a8-40ba-7031-817d-406822b5d3aa/lexiquest-consolidated-development-analysis.md)
- [ดัชนี39ภาพเดิม](C:/Users/Phet/.codex/visualizations/2026/09/12/01a095a8-40ba-7031-817d-406822b5d3aa/evidence-index.json)
- [manifest อ้างอิงพร้อม SHA-256](2026-09-12-r15-evidence-manifest.json) มี49ภาพที่อ้างถึงได้:39ภาพเดิม+10ภาพ AI/system; ไม่รวม auth/referral screenshot. SHA พิสูจน์ identity ของไฟล์ ไม่รับรองข้อสรุปในภาพ

E-Dxx/E-Axx ตรงกับ D1–D14/A1–A25 ในดัชนีเดิมโดยเติมเลขศูนย์ เช่น E-D04=D4. ภาพ AI เป็น E-AI152…E-AI161 และหน้าระบบ E-SYS164/165 ตาม filename prefix. manifest บันทึก path จริงและ observation ไว้ ไม่ต้องเดาชื่อภาพ

| Evidence ID | Filename ที่ root | ข้อสังเกตและข้อจำกัด | ใช้กับ |
| --- | --- | --- | --- |
| E-D04 | 27-duolingo-correct.png | ข้อถูกมีข้อความ/สัญลักษณ์/สีพร้อมปุ่มไปต่อ | UI-03/UI-11 |
| E-D05 | 29-duolingo-wrong.png | จงใจเลือก coffee แทน tea เห็นเฉลยและปุ่มรับทราบ | UI-03/LEARN-02 |
| E-D08 | 52-duolingo-error-retry.png | นำข้อผิดกลับมาท้ายบท | LEARN-01 |
| E-D11 | 131-duolingo-resume.png | กลับจากสลับแอปเห็น progress ของบทเดิม | D-01/UI-09; ไม่ใช่ long-term retention |
| E-A01 | 73-alltcas-categories.png | คลังมีหมวดและระดับ | D-01/UI-07/UI-10 |
| E-A06/E-A07 | 78-alltcas-selected.png / 81-alltcas-after-correct.png | selected สีส้ม, คู่ถูกหายเหลือช่อง; ไม่เห็นช่วง green ไม่ได้พิสูจน์ว่าไม่มี | PAIR-01–03 |
| E-A09/E-A10 | 93-alltcas-flashcard.png / 94-alltcas-flashcard-back.png | POS/IPA/example, พลิกดูคำแปล/ภาพและ self-report | LEARN-01/02 |
| E-A12 | 91-alltcas-cloze-feedback.png | เฉลยในบริบทหลังตอบผิด | LEARN-02 |
| E-A14/E-A15 | 99-alltcas-quiz-correction.png / 100-alltcas-quiz-next.png | พบคำตอบ/คำถามนอก viewport หลังเลื่อนใน landscape หนึ่งครั้ง | UI-08/UI-11; ไม่อ้างเกิดทุกเครื่อง |
| E-A18/E-A19/E-A20 | 115-alltcas-english-feedback.png / 116-alltcas-word-help.png / 117-alltcas-sentence-help.png | เหตุผลตัวลวง/คำศัพท์ในบริบท/คำแปลเสริม | LEARN-02 |
| E-A22/E-A24/E-A25 | 124-alltcas-english-result.png / 129-alltcas-retry-result.png / 130-alltcas-english-stats.png | first5/6และretry1/1แยกกัน สถิติหลักยัง5/6 | DATA-01/LEARN-01 |
| E-AI152/E-AI153 | 152-ai-live-answer.png / 153-ai-live-complete.png | ตอบภาษาอังกฤษผ่านทางเข้า Math; partial→complete แต่ข้อความบางส่วนไม่ปรากฏ | AI-02; ยังไม่รู้ root cause |
| E-AI154/E-AI155 | 154-ai-followup.png / 155-ai-plain-question.png | follow-up เกี่ยว borrow/lend แต่โจทย์ไม่เห็น; ขอ plain text แล้วเห็นโจทย์ | AI-01/02/03; ไม่สรุป renderer implementation |
| E-AI156 | 156-ai-wrong-answer.png | ตอบ lend ผิด, AI ชี้ทิศทางการยืม แต่คำบางส่วนหาย | AI-02 และ rubric |
| E-AI157/E-AI160/E-AI161 | 157-ai-history.png / 160-ai-history-saved.png / 161-ai-history-open.png | new chat แล้ว archive/open readonly; UI กล่าว90วันแต่ไม่ได้รอพิสูจน์ deletion | AI-01 เลือกไม่คัดลอก retention |
| E-SYS164/E-SYS165 | 164-system-timer.png / 165-system-stats.png | timer+stats gate ต้องเรียนเพิ่ม9.8ชั่วโมง; ไม่ได้เปิดกราฟที่อยู่หลัง gate | T-05/MOT-01 ไม่ใช้ล็อก dashboard ตามคู่เทียบ |

วิดีโอประกอบ: `duolingo-study-01.mp4`, `duolingo-study-results.mp4`, `alltcas-matching-study.mp4`, `alltcas-english-study.mp4` ที่ root เดียวกัน ผ่านการตรวจ decode ในรายงานเดิม ไม่มี audio และ frame rate แปรผัน; ใช้เห็นลำดับ state ไม่ใช้หา frame-perfect duration/60fps. ค่า450/150msใน spec เป็น D ไม่ใช่ค่าที่วัดจากวิดีโอ

## 3. Code/reference register

Path ในตารางอิง repository root; อ่าน source version ตาม baseline ก่อนเปรียบเทียบกับ working tree. ถ้า code เปลี่ยน ให้บันทึก SHA ใหม่ใน acceptance report

| ID | ต้นทางที่ตรวจ | สิ่งที่ใช้ตัดสิน / requirement |
| --- | --- | --- |
| C-THEME | `lib/config/m3_theme.dart` | มี NotoSansThai/text roles/card radius16/button min48/reduced-motion helpers; UI-01–08/UI-12 เริ่มจากฐานนี้แต่ปรับแทนได้ |
| C-UI | `docs/superpowers/specs/2026-09-12-unified-learner-ui-draft.md`, `docs/development/2026-09-12-prototype3-ui-comparison.md` | ประวัติการเลือก alignment/Prototype3; latest user clarification ทำให้ old style rules เป็น revisable decisions ไม่ใช่ hard constraints |
| C-PAIR | `lib/features/learning/pair_matching/presentation/pair_board_view.dart`, `pair_matching_experience_host.dart` ใน directory เดียวกัน; `lib/features/learning/pair_matching/domain/pair_matching_engine.dart` | matched/support/repair, immediate hidden และ host result; PAIR-01–03, learning decisions อยู่ engine ไม่อยู่ animation |
| C-TODAY | `lib/features/today_hub/domain/today_hub_models.dart`, `lib/features/today_hub/data/drift_today_hub_reader.dart` | canonical sectionOrder/owner/ready-empty-stale-unavailable-corrupt; UI-09 |
| C-PROGRESS | `lib/features/progress/domain/personal_learning_profile.dart`, `lib/features/progress/data/drift_personal_learning_profile_reader.dart` | availability/sampleSize/correctCount/activeDuration และ source authorities; DATA-01/02 |
| C-CAMERA | `lib/features/media_practice/application/object_scanner_use_cases.dart`, `lib/features/device_model/domain/model_manifest.dart`, `docs/development/2026-09-12-camera-followup.md`, `docs/superpowers/plans/2026-09-11-priority-12-camera-pilot.md` | baseline manifest, confidence0.15, primary-only lookup, pilot4-class/40images/known limits; CAM-01–03 |
| C-AI | `lib/features/ai_tutor/application/ai_tutor_use_cases.dart`, `lib/features/ai_tutor/domain/ai_tutor_contracts.dart`, `lib/features/ai_tutor/data/openai_responses_gateway.dart`, `openai_compatible_gateway.dart`, `anthropic_gateway.dart` ใน data directory เดียวกัน | latest message/optional summary ไม่มี prior turns, hardcoded level/output; AI-01–06 |
| C-AI-Q | `docs/development/2026-09-11-ai-tutor-quality-cases.md` | authored12case rubric 7/8+correctness2; engineering threshold ไม่ใช่ validated learning measure |
| C-SYSTEM | `docs/development/2026-09-12-system-followup-r14-checkpoint.md`, `docs/development/2026-09-12-unattended-system-checkpoint.md`, `docs/superpowers/plans/2026-08-14-alltcas-8-44-capability-implementation-master-plan.md`, `AGENTS.md` | existing local/research/owner/authority boundary และ historical verification ไม่ใช่การห้ามเปลี่ยน UX |

## 4. Public primary references

| ID | แหล่งอ้างอิง | สิ่งที่ใช้จริง | ข้อจำกัด |
| --- | --- | --- | --- |
| S-FLUTTER | [Flutter accessibility](https://docs.flutter.dev/ui/accessibility) ตรวจเปิด2026-09-12 | touch targets, text scaling, screen-reader labels, contrast และ release checklist รองรับ UI-01/04/08 | เป็น framework guidance ไม่พิสูจน์แอปเราผ่าน accessibility แล้ว |
| S-CONTRAST | [W3C Understanding Contrast Minimum](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html) ตรวจเปิด2026-09-12 | text contrast4.5:1ทั่วไป และ3:1สำหรับ large text ตามนิยาม; specเลือก4.5:1ทั่วไปเป็น project target | ไม่แปลง48logical-pixel targetเป็นข้อกำหนดของ WCAG และไม่อ้าง compliance ทั้งมาตรฐาน |
| S-DUO-PRACTICE | [Duolingo Practice Tab](https://blog.duolingo.com/guide-to-duolingo-practice-hub/) ตรวจเปิด2026-09-12 | บทความทางการกล่าว practice tab ใช้ได้ฟรี สนับสนุนความเป็นไปได้ของ review ที่ไม่ล็อกด้วยจ่ายเงิน | ไม่ยืนยัน UI/สิทธิ์เหมือนกันใน guest Android9 build ที่ทดลอง |

แหล่งทางการที่ใช้ในรายงานเดิม เช่น Duolingo Max/Video Call, ALLTCAS landing และ pub.dev อยู่ในรายงานวิเคราะห์รวม ใช้เป็น background เท่านั้น ไม่กำหนด R15 ให้สร้าง video call หรืออ้างราคา ณปัจจุบัน ส่วน ALLTCAS privacy เคยพบเนื้อหาต่างรุ่น จึงไม่ใช้เป็นข้อกำหนด retention/provider ของ LexiQuest. หน้า LiteRT model analyzer ที่เปิดในรอบนี้คืน internal error จึงไม่ถูกอ้างเป็นแหล่งที่ตรวจแล้ว

## 5. Requirement → evidence → design → verification

| Requirements | Sources | การประยุกต์ที่ตัดสิน | Acceptance |
| --- | --- | --- | --- |
| UI-01–08 | C-THEME/C-UI/E-A01/S-FLUTTER/S-CONTRAST | T-01–07, responsive roles, revised alignment | A-UI |
| UI-09/10 | C-TODAY/E-D11/E-A01 | suggested entry + choose practice, truthful empty states | A-NAV |
| UI-11/12, PAIR-01–03 | E-D04/05/E-A06/07/C-PAIR | state feedback, final-pair presentation, reduced motion | A-PAIR/A-UI |
| LEARN-01/02 | E-D08/E-A09/10/12/18/19/20/24/25 | explanation/provenance, repair separate | A-LEARN |
| DATA-01–05 | C-PROGRESS/E-A22/24/25/C-SYSTEM | read-only dashboard, noEvidence, historical truth | A-DATA |
| CAM-01/02 | C-CAMERA | uncertainty/unsupported/save lifecycle | A-CAM |
| CAM-03 | C-CAMERA + authored experiment protocol | fresh splits/calibration/comparative gates; retain baseline allowed | A-MODEL |
| AI-01–06 | E-AI152–161/C-AI/C-AI-Q | bounded session context, plain-text baseline, intent caps | A-AI |
| MOT-01 | E-D09/10/E-SYS164/165/C-SYSTEM | reward summary from real transaction, no invitation locks | A-MOT |
| SYS-01/02/VOICE-01 | C-SYSTEM/C-AI-Q | local learning independence, identity/cancel, no false acoustic score | A-SYS |

## 6. Portability / provenance policy

Spec และ source register เก็บข้อสังเกต/เหตุผล/เกณฑ์ครบใน repo เพื่อให้เข้าใจงานได้เมื่อไม่มีเครื่องต้นทาง ภาพต้นฉบับยังเป็น local artifacts ไม่ได้แนบทุกภาพใน Git. Manifest มี original path/hash/observation ช่วยส่งต่อชุดที่เลือกโดยไม่รวม auth/PII; หากเครื่องอื่นไม่มีไฟล์ต้องระบุ missing evidence ไม่สร้างลิงก์สมมติหรือกล่าวว่าดูภาพแล้ว ห้ามนำ screenshot competitor ไปเป็น shipped UI asset

เอกสารนี้ไม่อ้างว่า citation ทำให้ proposed design ดีที่สุด แต่ทำให้ตรวจย้อนกลับได้ว่าข้อเท็จจริงอยู่ตรงไหนและส่วนใดเป็น engineering judgment; ทุกการแทนข้อกำหนดเก่าต้องเพิ่ม source/decision/acceptance mapping ในตารางนี้
