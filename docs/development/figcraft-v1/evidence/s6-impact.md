# S6 impact map

ตรวจแบบ read-only เมื่อ 2026-11-14 ใน `C:/Users/Phet/.codex/worktrees/figcraft-flutter-v1/LexiQuest`, branch `codex/figcraft-flutter-prototype`, HEAD `984e616438f264f4c54565ea0c7e0787272d7386` พร้อม S1–S4 ที่ยังไม่ commit. งานนี้เขียนเอกสารนี้เท่านั้น. ไม่แก้ production, ไม่ใช้โทรศัพท์, ไม่รัน Flutter หรือ Gradle และไม่เริ่มงาน Pair Matching.

นี่เป็นแผนผลกระทบสำหรับจัดลำดับ S6 หลัง milestone. Source และ test pointers ไม่ใช่ผลตรวจ runtime. กำหนด `not_checked` ให้ Android journey, 200%, TalkBack, background audio, notification delivery และการซื้อ/สวมจริงของ S6 ใน source รุ่นใหม่.

## ขอบเขตและทางเข้าที่มีอยู่

S6 ในทะเบียน `features.csv` มี f08, f10, f12, f23, f26, f27 และ f29–f34. Packages คือ P2.2, P2.3, P2.5–P2.8 และ P4.1–P4.5. ไม่เปลี่ยนทะเบียน 48/44/64 และไม่ปิดฟีเจอร์จากจำนวนหน้าหรือจำนวน tests.

| งานที่มีทางเข้าใน production source | Entry และ return | ขอบเขตที่พิสูจน์ได้จาก source |
| --- | --- | --- |
| ฝึกเพิ่มเติม | Home → ดูแบบฝึกทั้งหมด (`lib/screens/choose_mode_screen.dart:265`). `_activities:286` เปิด quiz/category quiz/SRS/reading/progress/weakness ตาม registry และ `_push` refresh หลังกลับ | มี basic modes จริง. รายการนี้ไม่ได้เปิด 14 หน้าที่หลุดจาก route graph ด้านล่าง และไม่ได้พิสูจน์ 14 interaction modes ของแผนเดิม |
| Ghost duel | Drawer → `GhostShadowDuelScreen` (`lib/screens/main_navigation_screen.dart:272`). Back ออกจากรอบได้ และหน้าผลมีทาง repair ตาม registry | `lib/screens/ghost_shadow_duel_screen.dart:97` pin owner/dependency. `_loadData:120` แยก no evidence จากรอบจริง. ใช้ `LearningUseCases.startGhostDuel` แทน boss HP/reward counters ของหน้าเก่า |
| ของตกแต่ง | Drawer → `ShopPage` (`lib/screens/main_navigation_screen.dart:230`), หรือ Progress → ร้าน (`lib/screens/mastery_dashboard_screen.dart:299`). Preview และ Back อยู่ในร้านเดิม | `lib/screens/shop_page.dart:162`, `:215` ซื้อและสวมผ่าน `RewardShopOperations` เดิม. Theme/wallpaper/avatar wrappers ที่ไม่มี caller ไม่ได้เพิ่มความสามารถอีกชุด |
| ความสำเร็จ | Progress → `AchievementsScreen` (`lib/screens/mastery_dashboard_screen.dart:283–293`) และ Back กลับ Progress | อ่าน stored achievement evidence จาก progress. ไม่มี share-card/Android Sharesheet ใน `lib/screens/achievements_screen.dart`. การเปิดหน้านี้ไม่ปิด f34 |
| ใช้เนื้อหาของผู้เรียน | Selected set → SourcePractice (`lib/screens/vocab_list_screen.dart:279`). หลังยืนยันข้อความมี reading, quiz, flashcards และคำแรกสำหรับ AI/voice (`lib/screens/source_practice_screen.dart:223`) | มีงาน text/file ที่ใช้ matched words จริง. ป้าย AI/voice ระบุขอบเขตคำแรกและไม่แนบไฟล์ (`:249`, `:263`). ไม่มี handwriting canvas ในหน้านี้ จึงไม่ปิด f12 |

## 14 หน้าที่ไม่มีเส้นทางจาก app root

ตรวจซ้ำจาก constructor calls ใน `lib` และ named routes (`lib/navigation/app_route_factory.dart:21`). ผลตรงกับ `evidence/screens.csv` เดิม คือ 13 หน้าไม่มี external constructor caller และ CefrSelection มี caller ใต้หน้า LearningWorldMap ที่ไม่มี root entry. ตารางนี้ไม่ได้บอกว่าอีก 34 หน้าใช้งานผ่าน runtime แล้ว. บาง constructor paths ยังติด gating/composition ตาม `s5-impact.md`.

ทุกแถวในตารางนี้มีสถานะ runtime `not_checked`. คอลัมน์ test ระบุ assertion ที่มีอยู่ ไม่ใช่หลักฐานว่าเข้าจากแอปได้.

| Screen ID และ source | Actual production entry | พฤติกรรมและทางกลับที่มีใน source | Exact test evidence และข้อจำกัด |
| --- | --- | --- | --- |
| `avatar_equipment_screen`, `lib/screens/avatar_equipment_screen.dart:7` | ไม่มี caller. งานร้านมี route ตามตารางข้างบน | Wrapper คืน `ShopPage` (`:13`). Back เป็นของ route ผู้เรียก | `test/screens/avatar_equipment_screen_test.dart:8` เป็น direct pump. ไม่พิสูจน์ app entry |
| `select_wallpaper_screen`, `lib/screens/select_wallpaper_screen.dart:7` | ไม่มี caller. งาน wallpaper ใช้ filter ของ ShopPage ได้ | Wrapper คืน `ShopPage` (`:13`) | ไม่มี direct import test ใน ledger เดิม. `test/screens/shop_page_test.dart:66` ตรวจ filter wallpaper ของ route ที่ใช้งานจริง |
| `boss_battle_screen`, `lib/screens/boss_battle_screen.dart:10` | ไม่มี caller | Default คำถามสามข้อ. `_attackBoss:44` เพิ่ม XP ใน State จาก latency คงที่ 1000ms และ coins ทีละ 30. AppBar Back ไม่มีผลที่ผูก session | `test/screens/boss_battle_screen_test.dart:6` ตรวจ HP/attack. ไม่ตรวจ learning persistence หรือ reward authority. ห้ามเปิดเป็นยอดรางวัลจริง |
| `cefr_article_reader_screen`, `lib/screens/cefr_article_reader_screen.dart:11` | ไม่มี caller | Caller ต้องส่ง title/content/level. แตะคำเรียก voice (`:37`). AppBar Back. ไม่มี session/progress write ในหน้า | `test/screens/cefr_article_reader_screen_test.dart:27` ตรวจ fake voice request. ไม่พิสูจน์เสียงจริง, content catalog หรือ persisted reading |
| `cefr_diagnostic_test_screen`, `lib/screens/cefr_diagnostic_test_screen.dart:4` | ไม่มี caller | ห้าข้อคงที่ (`:15`), แปลงเปอร์เซ็นต์เป็น A1–C1/C2 (`:61`). Dialog กดตกลง pop สองชั้น (`:82`) | `test/screens/cefr_diagnostic_test_screen_test.dart:6` ตรวจตอบและ dialog. ไม่ใช่ validated CEFR instrument. ต้องระบุ demonstration ก่อนเปิด route |
| `cefr_selection_screen`, `lib/screens/cefr_selection_screen.dart:12` | Caller เดียว `lib/screens/learning_world_map_screen.dart:96`, parent ไม่มี root entry | CEFR/category/search ผ่าน CefrService. เปิด `SrsFlashcardsScreen(wordList: wordMaps)` (`:205`), Back กลับ caller | `test/screens/cefr_selection_screen_test.dart:8`, `:34`, `:63` ตรวจ filters/200%/initial level. ต้องตรวจว่า raw word list มี learning authority รองรับก่อนนับรอบและผล |
| `dictation_quiz_screen`, `lib/screens/dictation_quiz_screen.dart:9` | ไม่มี caller | Caller ส่ง targetWord. เล่นเสียงหลัง first frame (`:27`), ตรวจ typed answer ใน State (`:50`). AppBar Back | `test/screens/dictation_quiz_screen_test.dart:30`, `:52`, `:77` ตรวจ fake speech/speed/feedback. ไม่มี durable session evidence |
| `learning_world_map_screen`, `lib/screens/learning_world_map_screen.dart:23` | ไม่มี caller | หกระดับเป็น navigation nodes. Node เปิด CefrSelection (`:91`). AppBar Back. ไม่ได้แสดง unlock จาก owner progress | `test/screens/learning_world_map_screen_test.dart:6`, `:16`, `:28` ตรวจ nodes, child route และไม่มี progress lock สมมติ. Direct pump ไม่ทำให้ parent reachable |
| `phonetic_explorer_screen`, `lib/screens/phonetic_explorer_screen.dart:20` | ไม่มี caller | IPA หกตัวอย่าง. `_speakWord:68` อ่าน example word ผ่าน VoiceUseCases. AppBar Back | `test/screens/phonetic_explorer_screen_test.dart:27` ตรวจว่าแตะ /æ/ ส่งคำ cat ไป fake voice. ไม่ใช่ผลตรวจ acoustic IPA |
| `result_screen`, `lib/screens/result_screen.dart:7` | ไม่มี caller | แสดง int score ที่ caller ส่งและ reset home (`:35`). ไม่มี session/result ID | ไม่พบ direct import test ใน ledger เดิม. Core journey ใช้ `ScoreScreen` พร้อม session จริงอยู่แล้ว. หน้าเก่านี้ไม่ใช่ทางกลับ selected set |
| `sentence_scramble_screen`, `lib/screens/sentence_scramble_screen.dart:10` | ไม่มี caller | สลับและเลือกคำใน State (`:35`, `:63`). ตรวจเทียบ string (`:79`), reset ในหน้า (`:87`), AppBar Back. ไม่มี learning write | `test/screens/sentence_scramble_screen_test.dart:27` ตรวจ widget/fake voice. ไม่พิสูจน์ session หรือผลหลัง restart |
| `smart_audio_playlist_screen`, `lib/screens/smart_audio_playlist_screen.dart:9` | ไม่มี caller | รับ raw wordList. Start/stop ผ่าน `BackgroundAudioPlayerService` (`:34`), stop เมื่อ dispose (`:56`), AppBar Back | `test/screens/smart_audio_playlist_screen_test.dart:24` ตรวจปุ่ม/fake voice. ไม่พิสูจน์ Android background service, playback notification หรือ lock-screen control |
| `thesis_chart_screen`, `lib/screens/thesis_chart_screen.dart:9` | ไม่มี caller | Default 52/88.5 (`:11`), labels ของ graph คงที่ (`:74`). AppBar Back | `test/screens/thesis_chart_screen_test.dart:3` ไม่ยืนยัน paired assessment จริง. งานนี้อยู่ S5/f28. ไม่เชื่อมค่าตัวอย่างเป็นผลผู้เรียน |
| `wordbook_import_screen`, `lib/screens/wordbook_import_screen.dart:9` | ไม่มี caller | `_processImport:27` parse ลง State แล้วขึ้นนำเข้าสำเร็จ (`:46`). เปิด raw flashcards (`:173`), AppBar Back. ไม่มี repository write | `test/screens/wordbook_import_screen_test.dart:6` ตรวจ parse/display เท่านั้น. S2 มี persistent import ของ selected set อยู่แล้ว. การนำหน้าเก่านี้เข้าเมนูโดยตรงจะอ้างเก็บสำเร็จเกินจริง |

การปิดทะเบียนแต่ละหน้าต้องมี disposition ว่าจะใช้ route เดิมที่ทำงานเดียวกัน, ผูกหน้าที่จำเป็นกับ task จริง หรือคงยังไม่พร้อมพร้อมเหตุผล. ไม่มีการอนุมัติให้ลบ/ตัดรายการเหล่านี้ออกจากตัวหารในเอกสารนี้.

## Reward authority ที่ต้องใช้ต่อ

`AppBootstrap:320` ประกอบ `RewardUseCases` และ `DriftRewardRepository` เดิม. `RewardUseCases.loadSession:50` recheck owner. `purchase:64` รับ expected owner, catalog version และ idempotency key; `equip:103` ตรวจ owner และ ownership ผ่าน repository. Repository ทำ transaction และ replay (`lib/features/rewards/data/drift_reward_repository.dart:40`, `:110`).

Coin credits derive จาก immutable correct attempts ใน `DriftRewardProjectionRebuilder._materializeCredits` (`lib/features/rewards/data/drift_reward_projection_rebuilder.dart:61`). `foldRewardLedger` ตรวจ exact source evidence (`lib/features/rewards/domain/reward_ledger.dart:73`). `DriftLearningRepository:152`, `:396` rebuild projection จาก learning authority เดิม. ไม่เพิ่ม reward balance หรือ coin counter ในหน้าใหม่.

`ShadowRewardOrchestrator` เป็น dry-run eligibility pipeline (`lib/features/rewards/application/shadow_reward_orchestrator.dart:151`). ไม่ใช่แหล่ง mint เหรียญอีกชุด. BossBattle counters, quest reward specification และคะแนนจาก widget arguments ไม่ใช่สิทธิ์เพิ่มยอดของบัญชี.

| Existing assertion | สิ่งที่ครอบคลุม |
| --- | --- |
| `test/features/rewards/coin_authority_test.dart:23`, `:60`, `:237` | หนึ่ง attempt ได้หนึ่ง provenance-bound coin, legacy carry ไม่ทำลายประวัติ, incorrect/cross-owner source mint ไม่ได้ |
| `test/features/rewards/reward_use_cases_test.dart:44`, `:121`, `:144`, `:184`, `:314`, `:357` | Atomic/replay purchase, concurrent balance, owned equipment, catalog/unknown item, owner transition ไม่ debit/equip B |
| `test/screens/shop_page_test.dart:240`, `:815`, `:834`, `:893`, `:1000` | Preview/cancel ไม่เขียน, double tap debit ครั้งเดียว, owner เปลี่ยนขณะ confirm, filter/scroll/data คงอยู่ |
| `test/runtime/reward_appearance_restore_test.dart:26` | File-backed DB reopen และ owner switch คืน appearance โดยไม่ reset navigation |

ทั้งหมดเป็น `test_assertion_exists` ในงานนี้. ไม่มีการซื้อหรือสร้าง rewards บนโทรศัพท์จริง.

## แยก unavailable ที่ซื่อสัตย์จาก local flows ที่ยังไม่ครบ

| Boundary | Source evidence | Disposition ก่อนนับว่าผ่าน |
| --- | --- | --- |
| Field feature gates | `lib/runtime/field_feature_registry.dart:13` แยก enabled/limited/hidden. Scanner/speech/AI limited และ UI แสดง reason/setup ใน `lib/screens/main_navigation_screen.dart:239`, `:256`, `:282` | External provider/model/permission ที่ยังใช้ไม่ได้ต้องมีเหตุผลและ Back. การแสดงข้อความ limited ไม่ปิดความสามารถเต็ม. Native recognition/voice quality ยังแยกตรวจ |
| Quest f29 | `QuestUseCases` มี owner/catalog/event processing (`lib/features/quest/application/quest_use_cases.dart:20`, `:47`, `:79`). `LearningUseCases:38–39` มี optional sinks. แต่ bootstrap `:302` ไม่ส่ง eventAdapter/questEventSink และไม่ส่ง `AppDependencies.quest` | Local composition gap. `Feature.questV2=limited` (`lib/runtime/registries/feature_registry.dart:89`) ไม่สร้าง pipeline เอง. ต้อง reuse hooks/catalog/owner เดิมและทดสอบ event replay ก่อนเปิด UI. ไม่เพิ่ม reward authority |
| Streak f30 | `StreakUseCases.recordLearningDay:49` และ timezone policies มีอยู่. Bootstrap ไม่ส่ง streakEventSink. Progress แสดง `_streakDays` จาก UTC answer dates (`lib/features/progress/data/drift_progress_queries.dart:403`) | Local wiring/formula gap ต่อ requirement Gentle Streak/learner timezone. ต้องเลือกระบบเดิมตาม domain และเทียบข้ามวัน/เขตเวลา. ไม่แสดง freeze state จากค่าตัวอย่าง |
| Reminder f27 | `SpacedReviewReminderService:7` คำนวณ due/low box เท่านั้น; constructor search ไม่พบ production caller | Local scheduling/opt-in/cancel path ยังขาด. ไม่ใช่แค่รอ notification permission. OS delivery เมื่อปิดแอปยัง `not_checked` |
| Timer f23, goals/countdown f26, companion f33, share f34 | ทะเบียนระบุช่องว่าง. Home/Settings/Achievements ปัจจุบันไม่มีครบวงจรเหล่านี้ | Local product gaps ที่ยังไม่นับผ่าน. Timer ต้อง monotonic/lifecycle, goal ต้อง owner persistence, share ต้อง preview/cancel/native destination. ไม่มี external authority ที่ใช้เป็นเหตุปิดช่องว่างเหล่านี้แทน implementation |
| Definition f08 และ handwriting f12 | Basic quiz และ text SourcePractice มีอยู่ แต่ไม่ใช่ definition-bank contract หรือ handwriting canvas | Local content/interaction gap. ต้องระบุ task และ evidence จริงก่อนเปิด. ไม่แปลง typed text เป็นข้ออ้างว่าลายมือผ่าน |
| Pair Matching f10/P2.2 | ทะเบียนยังระบุรอ และ AGENTS กำหนด Research engineering เสร็จพร้อมคำขอแยก | คงรอ. งานนี้ไม่เริ่ม task, ไม่สร้าง implementation และไม่เพิ่ม reward/interaction contract |
| CEFR/research assessment | หน้า diagnostic/chart มีค่าหรือ scoring ตัวอย่างตามตาราง 14 หน้า | การวัดจริงต้อง instrument/authority ภายนอก. ความถูกต้องของ labels, provenance และการระบุข้อมูลสังเคราะห์เป็น local work ที่ต้องเสร็จก่อน expose |
| Legacy import/mini-games | Wordbook แสดงนำเข้าสำเร็จโดยไม่ persist; Boss แสดง coins ใน State; dictation/scramble มี feedback ที่ไม่บันทึก | ถ้าจะนำเข้า production route ต้องผูก task กับ authority เดิมหรือบอกว่าเป็นกิจกรรมไม่เก็บผล. ห้ามเรียก session/reward ที่บันทึกแล้วโดยไม่มีหลักฐาน |

## Owner/dependency candidates สำหรับ S6

ยังไม่ได้ reproduce candidates ต่อไปนี้. `ShopPage.didChangeDependencies:33` เก็บ `_rewards`, `_session` และ appearance subscription ด้วย `??=`. Stream handler `:56` ตรวจ owner เปลี่ยนภายใน source เดิม แต่ยังไม่พิสูจน์ replacement ของ AppDependencies ทั้งก้อน. `AchievementsScreen.didChangeDependencies:43` ไม่ reload หาก `_load` มีอยู่ แม้ loader/scope เปลี่ยน.

Minimal synthetic check คือเปิดหน้าด้วย A แล้ว repump scope B โดยคง State/Navigator. B ต้องไม่เห็น achievement/balance A และไม่ dispatch purchase/equip ไป source A. กรณี B ไม่มี port ต้อง unavailable. แยกจาก existing owner-transition tests ที่ใช้ repository เดิม. ไม่แก้ source ในงาน map นี้.

## คำสั่งตรวจรับสังเคราะห์ที่ยังไม่ได้รัน

คำสั่งต่อไปนี้ใช้ source ที่หยุดเปลี่ยนและทำทีละชุดใน worktree เดิม. Historical log `build/milestone-full-test.txt` ที่จบ 1786 ผ่านไม่แทนผลของ source รุ่นใหม่หรือ Android acceptance.

```powershell
	flutter test --no-pub --reporter expanded test/features/rewards test/screens/shop_page_test.dart test/screens/achievements_screen_test.dart test/runtime/reward_appearance_restore_test.dart
	flutter test --no-pub --reporter expanded test/features/quest test/features/motivation test/runtime/field_feature_registry_test.dart test/runtime/registries_test.dart
	flutter test --no-pub --reporter expanded test/screens/ghost_shadow_duel_screen_test.dart test/screens/choose_mode_screen_test.dart test/screens/source_practice_screen_test.dart
	flutter test --no-pub --reporter expanded test/screens/avatar_equipment_screen_test.dart test/screens/boss_battle_screen_test.dart test/screens/cefr_article_reader_screen_test.dart test/screens/cefr_diagnostic_test_screen_test.dart test/screens/cefr_selection_screen_test.dart test/screens/dictation_quiz_screen_test.dart test/screens/learning_world_map_screen_test.dart test/screens/phonetic_explorer_screen_test.dart test/screens/sentence_scramble_screen_test.dart test/screens/smart_audio_playlist_screen_test.dart test/screens/thesis_chart_screen_test.dart test/screens/wordbook_import_screen_test.dart
```

ชุดสุดท้ายใช้ตรวจ behavior ของ legacy widgets เท่านั้น. ยังต้องมี root-entry/Back assertions เมื่อมีการตัดสิน route แต่ละหน้า. `test/features/quest/quest_learning_integration_test.dart:119`, `:183` และ `test/features/motivation/streak_learning_integration_test.dart:74`, `:95` ตรวจ pipeline ที่ fixtures ประกอบให้และ null hooks. ไม่ใช่หลักฐานว่า AppBootstrap ประกอบ pipeline แล้ว.

สถานะ S6 คง **ยังไม่ตรวจรับ**. สิ่งที่ตรวจครั้งนี้คือ actual callers, authority ที่ใช้ต่อได้, local gaps และ existing assertions. การเปิด source file, widget test หรือ limited notice ไม่ปิดฟีเจอร์เต็ม.
