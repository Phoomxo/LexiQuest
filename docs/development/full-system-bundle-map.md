# LexiQuest — Bundle Map

Revision `2026-09-13-bundles-4` · 9phases/64requirements · **accepted5 + remaining59 in20bundles**

G0.1–G0.5เป็นacceptedhistory. G0.5base `9125ae7b9ccff15bb44ebbab455b8b0251c8fcfe`. ตารางเปลี่ยนหน่วยdispatchเท่านั้น; อ่านscope/acceptance/testsเดิมจากpackagebriefเมื่อถึงข้อ. [Index](full-system-task-index.json) เป็นregistry; [workflow](full-system-package-workflow.md) กำหนดwriter/commit/handoff

| Bundle | Packagesตามลำดับ | จำนวน | งาน | เหตุผลที่ใช้taskร่วมกัน |
| --- | --- | --- | --- | --- |
| B01 | G0.6–G0.8 | 3 | [ปิดฐานเอกสาร สูตร และ edition](../superpowers/bundle-briefs/B01.md) | เอกสาร authority, formula registry และ edition decision ใช้ coverage/source pins ของ G0.5 ร่วมกันก่อนปิด G0 |
| B02 | G1.1–G1.3 | 3 | [Owner คำตอบ และประวัติ](../superpowers/bundle-briefs/B02.md) | owner/session identity → answer acknowledgment → history/replay เป็นเส้นทางข้อมูลเดียวกัน |
| B03 | G1.4–G1.7 | 4 | [Recovery SRS และ local runtime](../superpowers/bundle-briefs/B03.md) | persistence/recovery, evidence readers, SRS และ runtime composition ใช้ฐานข้อมูลและ lifecycle acceptance ต่อเนื่องกัน |
| B04 | G2.1–G2.2 | 2 | [Shell และ Pair Matching](../superpowers/bundle-briefs/B04.md) | shared UI tokens/shell เป็นฐานของ Pair layout และ interaction states |
| B05 | G2.3–G2.5 | 3 | [Quiz Cloze และ block spelling](../superpowers/bundle-briefs/B05.md) | input/correctness/feedback adapters และ evidence ของโจทย์เลือก พิมพ์ และจัดตัวอักษรใช้ interaction contracts ร่วมกัน |
| B06 | G2.6–G2.8 | 3 | [Study modes และ journeys](../superpowers/bundle-briefs/B06.md) | study-mode configuration เชื่อม local tools, mode inventory และ Reading/Adventure/Ghost journeys |
| B07 | G3.1–G3.3 | 3 | [Content cards และ feedback](../superpowers/bundle-briefs/B07.md) | pack metadata/lexical presentation ใช้ content revision เดียวกับ hints/bookmarks/report |
| B08 | G3.4–G3.7 | 4 | [Review progress และ assessment](../superpowers/bundle-briefs/B08.md) | learning history/read models เชื่อม review, dashboard/formulas, assessment metadata และ content-version recovery |
| B09 | G4.1–G4.3 | 3 | [Navigation goals และ effort](../superpowers/bundle-briefs/B09.md) | Today/navigation, goals/reminders และ effort/timer ใช้ active learning/read models ร่วมกัน |
| B10 | G4.4–G4.6 | 3 | [Motivation และ preferences](../superpowers/bundle-briefs/B10.md) | reward/quest/streak readers ต่อกับ avatar/achievements และ lifecycle/preferences ของประสบการณ์เดียวกัน |
| B11 | G5.1–G5.3 | 3 | [Camera runtime](../superpowers/bundle-briefs/B11.md) | permission/model lifecycle → uncertainty/accept decision → saved vocabulary เป็น runtime transaction ต่อเนื่อง |
| B12 | G5.4–G5.6 | 3 | [Model evaluation และ evidence](../superpowers/bundle-briefs/B12.md) | dataset/model pins, metrics/resources และ device/rollback evidence ต้องอยู่บน evaluation freeze เดียวกัน |
| B13 | G6.1–G6.3 | 3 | [AI session และ provider](../superpowers/bundle-briefs/B13.md) | context/intent, request cancellation และ provider/usage finalization ใช้ attempt/session identity ร่วมกัน |
| B14 | G6.4–G6.6 | 3 | [Speech evidence และ quality](../superpowers/bundle-briefs/B14.md) | speech gateways เชื่อม speaking/shadowing/dictation และ quality/no-key journey โดยคงแยก scored/unscored evidence |
| B15 | G7.1–G7.2 | 2 | [Sync และ recovery](../superpowers/bundle-briefs/B15.md) | queue/lost ack/reopen และ owner/conflict/migration เป็น recovery protocol เดียวกัน |
| B16 | G7.3–G7.5 | 3 | [Policy data lifecycle และ activation](../superpowers/bundle-briefs/B16.md) | policy boundaries, export/delete และ runtime activation ต้องตรวจ ownership/edition ตาม data lifecycle เดียวกัน |
| B17 | G7.6–G7.7 | 2 | [Service contracts และ release tooling](../superpowers/bundle-briefs/B17.md) | cross-service contracts/resources ต่อกับ dependency/native/release tooling readiness ก่อน freeze |
| B18 | G8.1–G8.3 | 3 | [Freeze รีวิวทั้งแอป และแก้ผลรีวิว](../superpowers/bundle-briefs/B18.md) | source inventory/freeze, whole-app review และ remediation ต้องใช้ฐาน review เดียวกันก่อนอนุญาต System Test Plan |
| B19 | G8.4–G8.7 | 4 | [System Test Plan และ execution](../superpowers/bundle-briefs/B19.md) | สร้าง Test Plan หลัง B18 review accepted แล้วจึงรัน automated/build/device/fault/accessibility/resource cases บน pins ที่สัมพันธ์กัน |
| B20 | G8.8–G8.9 | 2 | [Defect closure และ final ledger](../superpowers/bundle-briefs/B20.md) | defect/retest/affected regression ปิดก่อนสรุป coverage/review/test/cleanup และ final release ledger |

ไม่มีการข้ามdependency/เปลี่ยนลำดับ: review/fixes B18 ก่อนTest Plan/execution B19 แล้วdefect closure/finalledger B20. Package/commitไม่สร้างtask. การจัดกลุ่มตรวจร่วมกับexistingownerpaths/testownershipใน [coupling evidence](full-system/evidence/bundles-4/coupling.json)
