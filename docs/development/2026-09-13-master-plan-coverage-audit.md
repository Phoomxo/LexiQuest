# Master Plan Coverage Audit — 2026-09-13

> **Authority update — sequential-3:** ตาราง coverage และ observation/evidence ในไฟล์นี้ยังเป็น baseline. ข้อจำกัด scope, exclusions และ delivery defaults ของร่างเก่าไม่ใช่เพดานถาวร; ใช้ [Active Index](full-system-active-index.md) และ [Rule Register](2026-09-13-rule-supersession-register.md) ก่อน. การขยายระบบที่จำเป็นทำได้พร้อม design/version/acceptance record; ไม่เปลี่ยนผล NOT RUN เป็น PASS

## 1. ข้อสรุปที่ตรวจพบ

**Master Plan ฉบับก่อนตรวจยังไม่ละเอียดพอที่จะรับรองว่าไม่มีรายการตกหล่น** แม้ครอบคลุมชื่อระบบหลัก แต่ไม่ได้ทำ traceability ครบ44capabilities, ไม่แจกแจง14LessonModes และไม่แยกส่วนที่ทดลองจริงจากส่วนที่เห็นทางเข้า/อ่านข้อมูลสาธารณะ เอกสารนี้เป็นภาคบังคับของ Master Plan ฉบับปรับปรุง ไม่ใช่ roadmap โครงการใหม่

**สิ่งที่ตรวจครบรอบนี้:** รายชื่อ44capabilitiesจากgenerated catalog, 14enum LessonModesในcodeรวม, 49รายการภาพในR15manifest, รายงานhands-onภาษาอังกฤษ/AI/ข้อจำกัด, Master Plan, R15spec/acceptance, สถานะreviewล่าสุด. ตรวจความครอบคลุมแผน ไม่ได้ทดสอบทุกfeatureบนruntimeใหม่

**สิ่งที่ยังรับรองไม่ได้:** เก็บทุกหน้าทุกโหมดของDuolingo/ALLTCASครบ, ทุกfeatureของLexiQuestเปิดใช้และผ่านacceptanceแล้ว, ไม่มีdefectที่ยังไม่ค้นพบ ไม่มีหลักฐานรองรับคำรับรองสามข้อนี้

เอกสารอ้างอิง:

- [Master Plan](../superpowers/plans/2026-09-13-lexiquest-full-system-master-plan.md)
- [44-feature catalog](../generated/alltcas-idea-integration-feature-map.json) revision1.3.0, semantic hash `41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4`
- [R15 spec](../superpowers/specs/2026-09-12-r15-engineering-spec.md), [source register](../superpowers/specs/2026-09-12-r15-source-register.md), [49-image manifest](../superpowers/specs/2026-09-12-r15-evidence-manifest.json)
- [รายงานทดลองภาษาอังกฤษ](C:/Users/Phet/.codex/visualizations/2026/09/12/01a095a8-40ba-7031-817d-406822b5d3aa/duolingo-alltcas-english-study.md)
- [รายงานAIและระบบภาพรวม](C:/Users/Phet/.codex/visualizations/2026/09/12/01a095a8-40ba-7031-817d-406822b5d3aa/lexiquest-ui-ai-direction.md)
- [วิเคราะห์รวม](C:/Users/Phet/.codex/visualizations/2026/09/12/01a095a8-40ba-7031-817d-406822b5d3aa/lexiquest-consolidated-development-analysis.md)
- [มินิเกมแต่ละinteractionและblockspellingที่ผู้ใช้ชี้แจง](../superpowers/specs/2026-09-13-minigame-coverage-contract.md)
- [GitHub WordQuest](https://github.com/tarntanate/English-Game-For-Kids), [implementationที่ประยุกต์ไว้แล้ว](2026-09-08-contextual-practice-results.md): แหล่งที่Master Planก่อนauditตกหล่น. “เติมตัวอักษรลงบล็อก”คือwordScrambleที่แตะ/ลากtileลงslot ไม่ใช่ข้อสั่งสร้างmissing-letterแบบเปิดตัวอักษรบางส่วนไว้ก่อน

## 2. Source และสถานะที่ต้องไม่ทำซ้ำ

งานเอกสารอยู่4366ที่HEAD `8c160f87`; sourceรวมอยู่842cที่HEAD `f4eebb895836349fbf8e9960312a78bad524d462` และมีworkingdiffของreviewfixes. generated catalogทั้งสองตรงกัน44recordsและsemantic hashเดียวกัน. ค่าexisting/partial/newCapabilityในcatalogเป็นhistorical classification ไม่ใช่runtime completion ณวันนี้

อ่าน [review-fixes verification](C:/Users/Phet/.codex/worktrees/842c/LexiQuest/docs/development/2026-09-13-r15-review-fixes-verification.md) และcheckpointล่าสุด พบว่า F1–F4 แก้แล้วในworkingdiff รายงาน155Flutter/11targets,20PythonและCLIchecksผ่าน แต่ยังไม่commit/merge. นี่คือรายงานของผู้ดำเนินงานที่ตรวจอ่าน ไม่ใช่การ rerunในauditนี้ จึงปรับPhase0เป็นreconcile/รับหลักฐานที่แก้แล้ว ไม่สั่งแก้F1–F4ใหม่จากสถานะเก่า

## 3. ทะเบียน44capabilities → phase → acceptanceที่ขาด/ต้องยืนยัน

ทุกแถวหมายถึง **อยู่ในขอบเขตที่ต้องตรวจรับ** ไม่ใช่ต้องสร้างใหม่ทั้งหมด: ตรวจsourceและหลักฐานเดิมก่อน; ขาดเฉพาะtestให้เติมtest; พบdefectให้แก้เฉพาะdelta; ไม่มีruntimepathให้บันทึกdeliverygapและปิดในphaseนั้น อย่าใช้การมีclass/testfileเป็นผลผ่าน

รหัส `COV-fNN` คือ acceptanceเพิ่มเติมจากR15 A-* ที่กล่าวกว้าง ต้องมีresultหรือexplicit external limitationในcoverage ledgerก่อนปิดG8

| ID | Capability (ชื่อจากcatalog) | Phase | COV acceptance ขั้นต่ำ |
| --- | --- | --- | --- |
| f01 | Curriculum & Learning Pack Catalog | 3/4 | filterระดับ/หัวข้อ/skill/goalจากmetadataจริง; unknown/emptyไม่สร้างpack |
| f02 | Learning Pack Detail | 3/4 | detailแสดงrevision/กิจกรรมที่ใช้ได้ตรงlaunch; เปลี่ยนpackไม่ค้างprogressชุดเก่า |
| f03 | Rich Lexical Card | 3 | meaning/POS/CEFR/IPA/audio/example/synonym/antonymแสดงเมื่อมี; missingfieldไม่แต่งข้อมูล; flipไม่เพิ่มmasteryเอง |
| f04 | Content Version & Quality Control | 3/7 | checksum/revision/publication/reviewstateผิดต้องไม่ใช้เป็นapprovedcontent; historypinไม่เปลี่ยนตามcatalogใหม่ |
| f05 | Unified Lesson Shell | 1/2 | launch/pause/resume/exit/resultครบทุก14modesที่section4; progressตรงacknowledgedactivity |
| f06 | Flashcard Mode | 2/3 | flip+self-rating+dueSRS+restart; exposureกับindependentrecallแยก |
| f07 | Meaning Quiz | 2/3 | Thai→EnglishและEnglish→Thai, correct/wrong/skip/duplicateackตรงpolicy |
| f08 | Definition Quiz | 2/3 | Englishdefinitionไม่เผลอใช้translationprompt; ambiguous/missingdefinitionมีreadinessstate |
| f09 | Cloze Test | 2/3 | selectedและtypedvariantให้evidenceprofileต่างกัน; blank/alternativeanswer/เฉลยตรงcontext |
| f10 | Matching Mode | 2 | Pair4/6, independent/support/repair/finalpair/replayผ่านA-PAIR; spatial/focus/timingครบ |
| f11 | Typed Recall / Writing | 2/3 | answer normalization/alternative/spelling/helpตามpolicy; ไม่เปลี่ยนทุกคำตอบให้lowercaseโดยไม่ตรวจความหมาย |
| f12 | Handwriting Scratchpad | 2/7 | เขียน/undo/clear/rotate/exitตามephemeralcontract; ไม่OCR/ไม่autograde; ตรวจdeliverygateก่อนเปิด |
| f13 | LexiQuest Native Modes Integration | 1/2/5/6 | ครบnative submodesในsection4และruntimeentry; camera/voicefallbackไม่ปลอมlearningevidence |
| f14 | Flashcard-First Recommendation | 3/4 | recommendedเมื่อpolicyเลือก; manualpracticeยังได้; ห้ามบังคับเริ่มflashcardทุกครั้งโดยไม่มีreason |
| f15 | Active-Recall Ladder | 3 | progression/recommendationใช้eligibilityจริง; support/recognitionไม่ถูกยกเป็นindependentproduction |
| f16 | Session Configuration | 2 | จำนวนข้อ/เวลา/direction/mode/availablecontentสัมพันธ์กัน; invalid/unsupportedconfigปฏิเสธก่อนstart |
| f17 | Immediate Answer Feedback | 2 | correct/wrong/support/skipต่างกัน; persistentexplanationและreducedmotionครบ |
| f18 | Contrastive Distractor Explanation | 3 | ตัวลวงที่เลือกได้explanationของตัวนั้นและcontentrevisionนั้น; missingไม่fabricate |
| f19 | Hint, Strategy & Context | 2/3 | wordhelp/translation/contextเปิดปิดได้; answer-revealinghintบันทึกsupportตามpolicy; TTSไม่ถูกนับhintผิดประเภท |
| f20 | Bookmark / Save | 3/7 | save/unsave/restart/ownerchange/export/delete; idempotentและไม่สร้างคะแนน |
| f21 | Flag / Report Content | 3/7 | reportผูกcontentid+revision; localpending/error/successตรงความจริง; ไม่ส่งsocialmessageอัตโนมัติ |
| f22 | Review Center | 3 | due/mistake/savedentryตามsourcesจริง; repairไม่ทับfirstresult; empty/restartพร้อม |
| f23 | Focus Timer | 4 | start/pause/resume/finish/background/restart; 60sพักไม่เพิ่มactiveeffort; ไม่อ้างเวลาจากเปิดแอป |
| f24 | Automatic Learning-Time Capture | 1/3 | activeinterval/duplicate/clockrollback/sessionoverlapตามauthority; no doublecountจากmanualtimerกับlesson |
| f25 | Learning Calendar & Weekly Analytics | 3 | midnight/timezone/ช่วงสัปดาห์และnoEvidence; ตัวเลขcalendarตรงdashboard |
| f26 | Goal / Test Countdown | 4 | targetdateในอดีต/วันนี้/อนาคต+timezone+edit/delete; countdownไม่กลายเป็นคะแนนTCAS |
| f27 | Opt-in Study Reminder | 4/7 | permissiondeclined/revoke/reschedule/cancelไม่ซ้ำ; opt-inจริงและเรียนต่อได้ |
| f28 | Learning Assessment & Progress Comparison | 3/7 | setup→items→submit→result→before/aftercomparisonมีinstrument/version/eligibility; missingbaselineไม่fabricate; realresearchgateแยก |
| f29 | Evidence-Based Quest | 4 | questconsumeeligibleeventsครั้งเดียว; replay/unsupportedไม่เพิ่มcompletion |
| f30 | Gentle Streak | 4 | timezone/dayboundary/eligibleactivity; ขาดวันไม่ล้างknowledge; ไม่ใช้counterคู่ขนาน |
| f31 | Achievement & Milestone | 4 | unlockreceiptครั้งเดียว, reopen/resultไม่ปลดซ้ำ; inaccessiblefutureachievementมีคำอธิบาย |
| f32 | Avatar Level-Up & Cosmetic Unlock | 4 | level/cosmeticจากledgerจริง; spendcoinsไม่ลดlifetimeXP; offline/restartไม่หาย |
| f33 | Contextual Companion | 4 | idle/correct/support/finish/errorตามstate; reduce-motion/noaudio; ไม่บังpromptหรือบังคับรอ |
| f34 | Achievement Share Card | 4/7 | preview/exportlocalimageใช้receiptจริง; owner/PII/filename/cancelถูกต้อง; publishต้องuseraction |
| f35 | Learning Preference & Goal Quiz | 4/7 | skip/edit/restart/ownerchange; preferenceไม่ถูกแสดงเป็นvalidatedplacement/CEFRscore |
| f36 | Personal Learning Profile | 3 | accuracy+n/effort/mastery/engagementแยกreadmodels; missing≠zero |
| f37 | Recommendation Panel | 3/4 | reason/currentowner/currentevidence; stalefailclosedเฉพาะrecommendation; manualentryยังใช้ได้ |
| f38 | Accessibility | 2/8 | semantics/focus/target48/text200/contrast/keyboard; humanTalkBackต่างจากautomatedPASS |
| f39 | Motion & Theme Controls | 2/4 | light/dark/system/reducedmotion persist; platformdisableAnimationsไม่ถูกoverride |
| f40 | Local-First Operation | 1/7/8 | coldstartoffline/contentinstalled/newinstallmissingcontentแยก; ordinarylearningไม่ต้องAI/cloud |
| f41 | Feature Flag & Controlled Rollout | 7/8 | off/unavailable/kill-switch/assignmentแยก; productcatalogentryไม่เปิดresearchอัตโนมัติ |
| f42 | Today Hub | 4 | canonicalorder/resume/assigned/review/recommendation/fallbackไม่แย่งauthority |
| f43 | Learning History | 1/3 | source/replay/support/exposure/timeถูก; missingmetadata/restart/owner/deleteครบ |
| f44 | Offline Content Manager | 3/7 | download/pause-or-cancel/resume/hashfail/cachemissing/storagepressure/versionreplace/remove→reopen; ไม่ลบvocabulary/historyเพราะลบcache |

## 4. มินิเกม/รูปแบบบทเรียนและชั้นการเรียน

`lib/features/learning/domain/lesson_mode.dart` ใน842cมี **14 modes**. Default enabled ไม่ได้พิสูจน์registry/launch readiness; handwritingScratchpad default implementedOff เป็นข้อเท็จจริงที่ต้องพิจารณาdeliveryexplicitly ไม่ควรรวมเป็นเปิดครบ14โหมด

ทุกโหมดต้องมี `MODE-<enum>` record ที่ระบุlaunchroute/contentfixture/actualmode/ตอบถูก/ผิด/skipหรือunsupported/exit/restart/result/evidence/reward. ใช้existingcontracts; ถ้าโหมดไม่ให้คะแนนต้องทดสอบว่าไม่มีคะแนนแทนการสร้างcorrect/wrongปลอม

| LessonMode | ตัวตรวจเฉพาะที่Master Planเดิมไม่ได้แจกแจง |
| --- | --- |
| associativeReading | word-in-context→relatedreading, selectedword/contextversionตรงกัน; readingexposureไม่ใช่recallscore |
| meaningQuiz | ทิศทางสองภาษาและanswercontrols/headerprogressตรงnativeack |
| typedRecall | input/keyboard/normalization/alternatives/help-provenance |
| definitionQuiz | definitionภาษาอังกฤษ, fallbackเมื่อcontentไม่พร้อม |
| cloze | selectionกับtyped,หลายblank/groupcountและambiguousanswers |
| matching | Pair4/6,episode/final/replay/helpและspatiallayout |
| flashcard | front/back/self-rating/dueSRS; เปิดเฉลยไม่เท่ากับตอบถูกเอง |
| handwritingScratchpad | localephemeraldrawingและdeliverygate; ไม่อนุมานว่าเป็นOCR |
| dictation | audioavailability/replay/skip/typedanswer; noaudioมีทางออก |
| speaking | recordingpermission/start/cancel/latecallback/no-speech; noacousticclaim |
| shadowing | audio→record/recognizedtextcomparison, missingaudio/no-speech/error |
| cefrReading | A1–C2navigation/อ่านจบ/missingtitle/version; estimatedCEFRnotice |
| sentenceScramble | tokenorder/duplicatewords/punctuation/reset/submitและselectedvsproductiveevidence |
| wordScramble | เติมtileลงemptyblocksด้วยtap/drag,คืนtile/repeatedletters/reset/answer/assistตามWordQuest adaptation; ไม่ใช่missing-lettervariantใหม่ |

**เส้นทางเพิ่มเติมที่ไม่ได้เป็นenumใหม่:** Adventure hub→mixed review→result→next/replay และ Ghost Shadow Duel. ตรวจในPhase2/4เป็น `MODE-adventure-journey` และ `MODE-ghost-duel`; ไม่เพิ่มเป็นฟีเจอร์45/46 และไม่เทียบDuolingoชื่อAdventuresว่าเป็นengineเดียวกัน. กล้องและAIเป็นintegrationเสริมในPhase5/6ตามspecเดิม

**ชั้น/หลักสูตร:** แยก (1) content taxonomy CEFR/topic/skill/goal (2) lesson sequence/readiness/review progression (3) assessmentcomparison (4) multiplayer/teacherclassroom. สามอย่างแรกอยู่ในf01/f04/f15/f16/f28/f37และต้องมีjourneyใหม่/returninglearner A1และระดับสูง, empty/purchased-freeไม่เกี่ยว, missingpackversion. อย่างที่4เป็นcloud/multi-user productคนละscope ยังไม่เพิ่มเองเพียงเพราะผู้ใช้กล่าวคำว่าชั้นเรียน

## 5. Coverage ของสิ่งที่ศึกษาจากคู่เทียบ

รหัสภาพใช้E-Dxx/E-Axx/E-AIxxx/E-SYSxxxตามmanifest; dispositionคือปลายทางในแผน ไม่ใช่คำยืนยันว่าฟีเจอร์นั้นเสร็จแล้ว

| หลักฐาน/รูปแบบที่พบ | ระดับการศึกษา | การนำไปใช้หรือเหตุผลไม่ทำ |
| --- | --- | --- |
| D01/D02 onboarding/เวลาเป้าหมาย | เปิดเลือกจริง | f35/f26; แยกpreferencesจากplacementtest |
| D03–D06 pictureMCQ/wordbank/dialogue+feedback | จบบทbeginnerจริง | f07/f13/f17/f19; image-basedpromptต้องใช้assetมีสิทธิ์ ไม่copyรูปคู่เทียบ |
| D07 listening skip | กดข้ามจริง ไม่ตรวจaudioจริง | MODE-dictation/speaking fallback; ไม่ถือว่าผ่านpronunciation |
| D08/D09 mistake retry/result | จบบทและแก้ข้อผิดจริง | f22/f43/first-vs-repair/resultsummary |
| D10 streak/reward | เห็นจริง | f29–34; ไม่มีevidenceว่าเพิ่มlearningefficacy |
| D11/D12 path/resume/guidebook | เปิดจริงบางnode | f01/02/15/19/42; guidance+เลือกฝึกเอง, ไม่สร้างcourseทั้งโลกเหมือนDuolingo |
| D13/D14 heart practice/exit/Super offer | ทดลอง1ข้อและออก ไม่ซื้อ | sessionexit+optionalpractice; hearts/gems/paywall **ไม่รับเข้าขอบเขต** เพราะขัดfree-firstและไม่มีneedพิสูจน์ |
| A01–A04 categories/deck/mode menu | เปิดจริง; modesบางตัวไม่ได้เล่น | f01/02/06–13/16; ห้ามรายงานYencha/Writing/Mixedว่าได้ทดสอบครบ |
| A05–A08 Matching25pairs | จบจริง มีintentionalwrong | f10/PAIR/UIfeedback; timingในspecเป็นprojectchoice |
| A09–A11 Flashcardflip/exit | ตัวอย่างหนึ่งใบ | f03/06/19; localpersistenceต้องตรวจแอปเราเอง |
| A12/A13 Cloze/exit | ตัวอย่างตั้งใจผิด | f09/17/18; exitmessageต้องตรงpersistenceจริง |
| A14/A15 vocabularyquiz/scroll | ตัวอย่างหนึ่งข้อและnext | f07/08/UI-08/11; viewportdefectต้องตรวจsmall/largefonts |
| A16–A22 TGATQ&A/shortdialogue/groups/result | จบ6ข้อจริง | f13/16/18/19/28; dialogue/readinggroupcount/เฉลยรายตัวลวงต้องมีcontentmodelตรวจได้ |
| A23–A25 review/repair/statistics | ตรวจจริง5/6→repair1/1 | f22/25/28/36/43; ไม่copyกราฟlockedจนมี100ข้อโดยไม่มีเหตุผล |
| AI152–AI157/AI160/AI161 | 4ข้อความจริง+archive/reopen; missingtext | AIcontext/plaintext/cancel/qualityrubric; archiveถาวรยังเลื่อน session-only ตามspec; camera/gallery/stop iconยังไม่ได้ทดสอบ |
| SYS164/SYS165 timer/stat gate | เปิดจริง ไม่ปล่อยtimerปลดล็อก | f23/25; กราฟหลังgateยังไม่ได้เก็บ จึงใช้readmodel+UIspecของเรา ไม่อ้างcopylayoutจากกราฟนั้น |
| DuolingoPractice/Roleplay/VideoCall | แหล่งทางการเดิม; ไม่ได้roleplay/callจริง | Practice→f22; situationaltext→AIoptional; realtimevideo/SSE/imageuploadยังไม่รับเข้ารุ่นนี้ |
| ALLTCASYencha/speed-round/randommixed/writing | menu-onlyบางส่วน | mixedใช้Adventure/MODEvariantsที่มีและตรวจacceptance; **Yenchaexactrulesยังไม่มีหลักฐานพอ** เก็บเป็นresearchcandidate ไม่สร้างเกมเลียนแบบจากชื่อ |
| ALLTCASlongdialogue/reading/AllExamPreview/solo-friends/drawing | setup/entryหรือtoolbarบางส่วน | knownQ&A/readingprinciples→f13/f28; scrapeทุกexam/สร้างTCASDB/onlinefriendsไม่รับ; scratchpad→f12ที่มีcontractแล้ว |

**ไม่ใช้คำว่าเก็บหมดแล้ว:** จุดที่ยังไม่ได้ใช้จริงมีDefinitionQuizบางแบบ, Writing/Yencha/mixedของALLTCAS, longdialogue/readingครบกลุ่ม, audio/TalkBack, next-dayreview, AIimages/stop, statisticsภายในgate, DuolingoRoleplay/VideoCallและpaidareas. ช่องว่างนี้ไม่ขวางfeaturesที่มีlocalcontractชัด แต่ขวางคำกล่าวว่าได้จำลองUXของต้นฉบับครบ

## 6. รายการเลื่อน/นอกขอบเขตต้องปรากฏเสมอ

| ID | รายการ | เหตุผล/เงื่อนไขพิจารณา |
| --- | --- | --- |
| OUT-01 | Online rooms/friends/chat/publicleaderboard/teacherclassroom | อยู่นอก44, multi-user/cloud/cost/identityเพิ่ม; ไม่ใช่personalDashboard |
| OUT-02 | Subscription/payment/hearts/gems/referralunlock | ไม่จำเป็นต่อlearninggoalและfree-first; ไม่copyเพราะคู่เทียบมี |
| OUT-03 | TCASadmissioncalculator/universityDB/non-Englishsubjects | นอกEnglish/currentproductscope |
| OUT-04 | OCRhandwriting | แยกจากf12scratchpad; ไม่มีOCRacceptance/dataในรุ่นนี้ |
| OUT-05 | RealtimeAIvideo/imageupload/persistentarchives/localLLMreplacement | optionalexpansion; session-onlyAIและbaselinecameraมีscopeชัดแล้ว |
| OUT-06 | ExactYenchaclone/newunobservedminigames | ยังไม่มีrules/gameplayevidenceเพียงพอ; ไม่อ้างว่าเก็บครบ |
| EXP-P1 | Local Same-Device Party Game | experimentalcandidateเดิม นอก44; เก็บไว้ไม่เปิดเอง |
| EXP-P2 | Private Effort Comparison | experimentalcandidateเดิม นอก44; ต้องแยกeffortจากmasteryและกำหนดprivacyก่อน |

## 7. ข้อแก้ Master Plan ที่มีผลตั้งแต่auditนี้

1. เพิ่ม44-feature+14-mode+2-existing-journeycoverage ledgerเป็นเงื่อนไขG0/G8; ต้องบันทึก `featureId,modeId,phase,route,contentRevision,sourcePin,status,acceptanceIds,evidencePaths,externalDependency` สถานะใช้ `verified-existing / needs-verification / defect / delivery-gap / external-pending / deliberately-excluded` ห้ามใช้blankแปลว่าdone
2. f12implementedOffต้องมีdeliverydecisionชัด ไม่เปิดเพราะชื่ออยู่ในcatalog; ถ้ารุ่นที่ส่งไม่รวม ต้องเปิดเผยว่าเป็นeditionที่ยังไม่ครบ44runtime ไม่รับรอง“ระบบครบทุกfeature”
3. G0รับงานR15ที่มีแล้วเป็นbaseline credit. Phase1–7ปิดเฉพาะgapตามledger ไม่สั่งทำทั้งหมดใหม่เพื่อให้ชื่อphaseครบ; reuse testresultได้เมื่อsource/dependency/configpinsยังตรง ไม่ต้องreviewทั้งprojectซ้ำ
4. เพิ่ม native modes/f12/f16 ในPhase2, f03/f04/f18–21/f28 ในPhase3, f23/f26/f31–35 ในPhase4, f20/21/f34/35/f44 lifecycleและf41 ในPhase7
5. G8ประกอบสองสถานะที่ห้ามปน: **engineering completion** (in-scopecode/localcontractsผ่าน, externalworkเปิดเผย) และ **release acceptance** (requiredtargetdevice/service/humanacceptanceที่editionสัญญามีหลักฐานครบ). Pendingexternalไม่ถือเป็นfullreleasePASS
6. “ไม่มีอะไรต้องทำเพิ่ม” หมายได้เพียงknown-scopetraceabilityไม่มีunassignedrow ณrevisionนี้ ไม่รับรองzero-unknown-defectหรือfutureplatformchange. ถ้าพบรายการใหม่ให้เพิ่มledgerและประเมินchange ไม่เปลี่ยนคำว่าเสร็จย้อนหลังโดยไม่บอกscope

## 8. Verification ของaudit

อ่านsourcecatalogและLessonModeจาก842cเทียบเอกสาร4366, ตรวจmanifestภาพ49entriesและsource-reportlimitations, ค้นexistingpathsของscratchpad/assessment/preferences/share/offline/nativegamesและtests. ไม่รันFlutter/Pythonmodel/test/buildในauditนี้และไม่แก้worktree842cที่กำลังมีreviewchanges. การพบไฟล์มีอยู่ช่วยป้องกันสร้างซ้ำ ไม่เท่ากับruntimeverification
