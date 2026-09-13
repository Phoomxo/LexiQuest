# LexiQuest Minigame Coverage Contract

> **Current scope — sequential-3:** คงการแก้ความหมาย WordQuest เป็นเกม tile แตะ/ลาก/คืนตัวอักษรและ evidence distinctions. Scope อื่นปรับตาม [current Master](../plans/2026-09-13-lexiquest-full-system-master-plan.md) และ [Rule Register](../../development/2026-09-13-rule-supersession-register.md); ข้อกำหนดร่างที่ยกเลิกไม่กลับมาเป็น design lock

วันที่2026-09-13 · ภาคบังคับของ [Master Plan](../plans/2026-09-13-lexiquest-full-system-master-plan.md) และ [coverage audit](../../development/2026-09-13-master-plan-coverage-audit.md)

## คำชี้แจงที่มีลำดับเหนือร่างก่อนหน้า

ผู้ใช้หมายถึงเกม **นำตัวอักษรลงช่องบล็อกให้เป็นคำ** ที่เคยประยุกต์จาก [English-Game-For-Kids / WordQuest — Spelling Adventure](https://github.com/tarntanate/English-Game-For-Kids) ไม่ได้ขอเกมใหม่ที่เปิดบางตัวไว้แล้วเติมเฉพาะตัวที่หาย

ร่างก่อนหน้าตีความเป็นmissing-letterและกำหนดmask/keyboardใหม่ จึงยกเลิกข้อกำหนดmask1–2ตำแหน่ง/คำ4–10ตัว/visible-letterevidenceของร่างนั้นทั้งหมด ไม่มีการลงโค้ดตามร่าง และไม่เพิ่มขอบเขตเกมใหม่จากการตีความผิด

**หลักฐานมีอยู่ก่อนแล้ว:** [designเดิม](2026-09-08-contextual-word-sentence-speaking-proposal.md), [implementation reportเดิม](../../development/2026-09-08-contextual-practice-results.md), `lib/screens/word_scramble_screen.dart`. CodeมีDragTarget, word-slot keys, slotLetterIndexes/usedIndexesและcopy “แตะหรือลากตัวอักษรลงช่อง / แตะตัวอักษรในช่องเพื่อคืนกลับ”. ต้องรับงานเดิมเป็นbaselineแล้วตรวจdeltaตามMaster Plan ไม่สร้างเกมที่สองซ้ำ

READMEของต้นทางที่เปิด2026-09-13ระบุdrag-and-drop spellingและRPG progression; นี่คือpublicsourceinspection ไม่ใช่การเล่นเกมเว็บต้นทางครบในรอบนี้. แนวทางLexiQuestเพิ่มtapalternativeและใช้คำศัพท์/authorityของตน ไม่คัดลอกsource/assets/dataและไม่รับhearts/timers/จำนวนโลกของต้นฉบับเป็นข้อกำหนดทั้งหมด

## ทะเบียนรูปแบบเกม

ชื่อที่ผู้ใช้เรียกอาจต่างจากenumในcode ดังนั้นต้องใช้ตัวอย่างinteractionยืนยันก่อนกล่าวว่าฟีเจอร์ไม่มี. MGเป็นcoverage IDs ไม่เพิ่มจำนวนcatalog44หรือจำนวนLessonMode

| ID | รูปแบบ | ตัวอย่าง / interaction | Contract/phase | สถานะฐานและacceptance |
| --- | --- | --- | --- | --- |
| MG-01 | เติมตัวอักษรลงช่องบล็อก / เรียงตัวอักษรเป็นคำ | ช่องว่าง3ช่อง + tiles c,a,t; แตะ/ลากลงช่องให้เป็นcat และคืนtileได้ | f13/wordScramble, Phase2 | มีimplementationจากWordQuest; ตรวจMG-01-A–F ไม่สร้างใหม่ |
| MG-02 | พิมพ์คำศัพท์ทั้งคำ | “แมว”→พิมพ์cat | f11/typedRecall, Phase2/3 | มีmode; ตรวจkeyboard/normalization/independentrecall |
| MG-03 | เลือกเติมคำในประโยค | I drink ___. [tea/chair] | f09/cloze, Phase2/3 | A12และcontextual-practice implementation; select/changeก่อนsubmit |
| MG-04 | พิมพ์เติมคำในประโยค | I drink ___. →พิมพ์tea | f09/cloze variant, Phase2/3 | localselected/typedcontract; supportedanswers/evidenceต่างจากMG-03 |
| MG-05 | จับคู่คำกับความหมาย | cat↔แมว, dog↔สุนัข | f10/matching, Phase2 | A05–08และPair4/6; support/repair/final/replay |
| MG-06 | เลือกความหมายสองทิศทาง | cat→เลือกแมว; แมว→เลือกcat | f07/meaningQuiz, Phase2/3 | D03/A14และlocalcontract; direction/answers/feedback |
| MG-07 | เลือกคำจากคำจำกัดความอังกฤษ | definition→เลือกคำ | f08/definitionQuiz, Phase2/3 | A03menu-only; มีlocalmode ต้องตรวจactualprompt/content |
| MG-08 | เรียงคำเป็นประโยค | tea/I/drink→I drink tea | f13/sentenceScramble, Phase2/3 | Dwordbank+localmode; punctuation/duplicate tokens |
| MG-09 | ฟังแล้วพิมพ์ | ได้ยินcat→พิมพ์cat | f13/dictation, Phase6 | D07ตรวจskipเท่านั้น; localaudio/noaudio/retry/typing |
| MG-10 | อ่าน/บทสนทนาแล้วตอบ | shortdialogue→เลือกคำตอบที่เหมาะ | f13/f28, Phase3 | D06/A16–22จริง; groupedcounts/versions/เฉลย |
| MG-11 | พลิกบัตรแล้วทบทวน | cat→flipแมว→จำได้/ยังจำไม่ได้ | f06/flashcard, Phase2/3 | A09–11ตัวอย่างจริง; self-rating≠examcorrect |
| MG-12 | พูด/พูดตาม | ฟังประโยค→พูด→recognizedtext | f13/speaking/shadowing, Phase6 | existingmodes+contextual-practice supplementalpanel; แยกscoredactivityจากunscoredpanel |
| MG-13 | ฝึกผสมในเส้นทางAdventure | flashcard→recognition→typed→resultตามcatalog | f13/f15และAdventure, Phase2/4 | มีmixedreviewjourney; ไม่ใช่YenchaหรือDuolingoAdventuresทุกกติกา |
| MG-14 | ฝึกเทียบGhostเดิม | ตอบโจทย์เทียบghostrecordที่รองรับ | f13/nativeGhostentry, Phase2/4 | existingGhostShadowDuel; identity/time/rewardตามengine |

ภาพ/เสียงเป็นpromptmodalityที่ผูกcontentavailabilityและassetrights ไม่เพิ่มจำนวนเกมด้วยการนับทุกmodalityเป็นเกมใหม่. Scratchpadเป็นเครื่องมือlocalephemeral; cameraเป็นช่องทางเพิ่มคำ; AIเป็นผู้ช่วยตามสถานการณ์; assessmentมีcoverageต่างหากในaudit

## MG-01 — Block spelling acceptance

**Filesเริ่มตรวจ:** `lib/screens/word_scramble_screen.dart`, `test/screens/word_scramble_screen_test.dart`, `lib/features/learning/domain/lesson_mode.dart`, `lib/features/learning/application/current_activity_evidence.dart` และสองเอกสารเก่าที่ลิงก์ข้างต้น. Reuseexistingcontroller/evidencewriter/wordsource และตรวจsource842cก่อนแก้

- **MG-01-A:** canonicalword+meaning/POSที่มีจริง→แสดงhint, emptyanswerblocksตามจำนวนอักษรและletterbank; ไม่มีword/contentให้แสดงunavailable ไม่สุ่มคำภายนอกโดยไร้provenance
- **MG-01-B:** แตะหรือdragletterไปslot, แตะslotเพื่อคืนletter→ตำแหน่ง/occurrenceidentityถูกต้อง; คำเช่นletterที่มีตัวt/eซ้ำใช้tileindexไม่ใช้letterstringเป็นuniqueidentity
- **MG-01-C:** เปลี่ยน/คืนคำตอบก่อนsubmitตามinteractionlock; ตรวจคำเมื่อครบตามpolicy; correct/wrong/help/resultแสดงข้อมูลตรงengine ไม่ตัดสินจากanimation
- **MG-01-D:** duplicate/lateinput, transitionข้อใหม่, exit/dispose/ownerchange→ไม่มีoldanswerwrite, rewardไม่ซ้ำ; resumeทำเฉพาะlifecycleที่modeรองรับ ถ้าresetต้องแจ้งตรงจริง
- **MG-01-E:** narrow/text200/dark/reducedmotion/keyboard/focus→blocksไม่overflowและคืนtileได้; touchไม่บังคับdragอย่างเดียว; hidden/usedtilesไม่รับinputผิด
- **MG-01-F:** letterbankเป็นrecognition/construction support จึงไม่ยกระดับเป็นindependentfull-wordrecallโดยอัตโนมัติ; ใช้wordScrambleevidenceprofileจริง, ไม่เพิ่มpoints/SRSจากการวางtileทีละตัว

ผลtests/renderer/APKในรายงาน2026-09-08เป็นhistoricalevidence ไม่อ้างว่ารันผ่านsourceล่าสุด. ตรวจว่าR15deltaกระทบเกมนี้หรือไม่แล้วเลือกtestsเท่าที่จำเป็น ไม่ทำfullsuiteซ้ำโดยไม่มีdependencychange

## การปิดscopeมินิเกม

ก่อนG8ต้องมีMG-01–MG-14และ14LessonModes/2existingjourneysจากauditในledger พร้อมroute/config/requirements/sourcepin/result. MG-01ต้องใช้คำอธิบายไทย “เติมตัวอักษรลงช่องบล็อก” คู่กับinternalname wordScramble เพื่อไม่เกิดความสับสนอีก

Missing-letterแบบเปิดบางตัวล่วงหน้า **ไม่ใช่deliverygapที่ผู้ใช้ยืนยันในรอบนี้** จึงไม่รวมเป็นrequiredgameใหม่. Yenchaexactrules, unobservedminigames, realtimeAIvideoและonlinepartyยังอยู่OUT/EXPทะเบียนaudit ต้องมีevidence/designก่อนรับเข้ารุ่น. คำว่าแผนครบหมายถึงรายการที่รู้และตกลงถูกจัดปลายทางครบ ไม่ใช่จำลองทุกเกมทุกเวอร์ชันของสามแหล่งอ้างอิง
