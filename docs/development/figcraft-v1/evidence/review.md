# Independent route audit and design evidence

Method: design review only (detector not applicable, native platform).

ตรวจจาก worktree `C:/Users/Phet/.codex/worktrees/figcraft-flutter-v1/LexiQuest` บน `codex/figcraft-flutter-prototype` ระหว่างผู้พัฒนาทำ S1/S4. รอบนี้ยังไม่ได้ freeze. แต่ละแถวระบุ HEAD ที่อ่านและหน้าจอมี SHA-256 ของ source ที่ตรวจ เพราะ line pointers เปลี่ยนได้เมื่อผู้พัฒนาแก้โค้ด. ไม่ได้แก้ทะเบียนต้นฉบับ.

## ความหมายของสถานะ

- `static_path_found` พบเส้นทาง constructor จาก AppRouteFactory ผ่าน source graph. ยังไม่ได้พิสูจน์ feature registry, prerequisites, การกดจริง หรือทางกลับ.
- `no_production_entry_found` ค้น constructor caller ทั้ง lib และตรวจ named-route factory แล้วไม่พบทางเข้าจากหน้าจออื่น.
- `caller_without_root_path` มี caller แต่ caller นั้นยังไม่มีเส้นทางจาก app root.
- `mapped_screen_paths_found` ในทะเบียนฟีเจอร์หมายถึงเฉพาะหน้าที่แมปมี static path. ไม่เท่ากับฟีเจอร์ทำงานครบ.
- `test_candidates` เป็นไฟล์ทดสอบที่ import source เป้าหมาย. ไม่ได้อ้างว่า assertions ครอบคลุม acceptance หรือทดสอบผ่าน.
- `runtime_status=not_checked`, `visual_status=not_checked`, `test_status=not_run_by_reviewer` แยกจากความพร้อมภายนอก. `external_status` ไม่ปิดงาน local implementation.
- ยังไม่มีรายการ `runtime_passed` ในการตรวจของผู้วิจารณ์รอบนี้. ต้องผูกผลรัน รูป และ SHA ของรุ่นใหม่ก่อนเปลี่ยนสถานะ.

## ตัวหารและหลักฐานปัจจุบัน

| ทะเบียน | ทั้งหมด | หลักฐานรันผ่านจากผู้วิจารณ์รอบนี้ |
|---|---:|---:|
| หน้าจอ | 48 | 0 |
| ฟีเจอร์ | 44 | 0 |
| ชุดงาน | 64 | 0 |

พบ static root path 34/48 หน้า. พบ 13 หน้าที่ไม่มี production caller และหนึ่งหน้าที่มีเพียง caller ซึ่งยังเข้าไม่ถึงจาก app root. ผลนี้ชี้จุดตรวจ ไม่ใช่ผลกดหน้าจอ.

ไม่มี caller ได้แก่ `avatar_equipment_screen`, `boss_battle_screen`, `cefr_article_reader_screen`, `cefr_diagnostic_test_screen`, `dictation_quiz_screen`, `learning_world_map_screen`, `phonetic_explorer_screen`, `result_screen`, `select_wallpaper_screen`, `sentence_scramble_screen`, `smart_audio_playlist_screen`, `thesis_chart_screen`, `wordbook_import_screen`.

`cefr_selection_screen` มี caller เฉพาะ LearningWorldMapScreen ซึ่งยังไม่มี root path. AppRouteFactory ที่อ่านมี `/login`, `/register`, `/home`, `/email-verification` และ email-action parsing. ไม่พบ named route ที่แก้ข้อสังเกต 13 หน้าข้างต้น. รายการ 14 หน้าจาก static graph รอบนี้กับกลุ่ม 14 หน้าที่เคยหาทางเข้าใน FigCraft ไม่ใช่รายการเดียวกัน.

ทะเบียน work-packages คง inherited COV-f IDs ในช่อง `linked_features` เพื่อเทียบต้นฉบับ. IDs เหล่านั้นยังไม่ยืนยันว่าใช้ความหมายเดียวกับ features.csv ปัจจุบัน เช่น P5.1–P5.3 งานกล้องอ้าง COV-f13 แต่ f13 ในทะเบียนฟีเจอร์ปัจจุบันคืองานรวมแบบฝึก. ผู้วิจารณ์เลือก source/test pointers ตามงานของแต่ละ package โดยตรง ไม่อนุมานความครบจาก inherited IDs. การแก้ semantic mapping ต้องมีการตัดสินและตรวจสัญญาแยกก่อนแก้ทะเบียนต้นฉบับ.

## จุดที่ต้องแก้หรือพิสูจน์ก่อนปิดงาน

| ระดับ | ข้อสังเกตจาก source | ผลต่อผู้เรียนและวิธีตรวจรับ |
|---|---|---|
| P1 | หลายหน้ามี direct widget test แต่ไม่มี production entry. ดู screens.csv ราย ID และ `lib/navigation/app_route_factory.dart:21`. | เปิดจากสี่แท็บจริง ทำงานจนจบ และย้อนกลับบริบทเดิม. ห้ามนับเพียง pumpWidget ว่า reachable. |
| P1 | WordbookImportScreen แสดงนำเข้าสำเร็จหลัง parse. `_parsedWords` อยู่ใน State และส่งเป็น wordList โดยไม่มีการเขียนคลัง. ดู `lib/screens/wordbook_import_screen.dart:42` และ `lib/screens/wordbook_import_screen.dart:46`. Test `test/screens/wordbook_import_screen_test.dart:6` ตรวจ parse/display เท่านั้น. | แยกอ่านไฟล์จากยืนยันเก็บ ใช้ authority เดิม และตรวจอ่านคำหลังเปิดแอปใหม่ก่อนเรียกว่าเก็บสำเร็จ. ยังไม่ได้ reproduce runtime. |
| P1 | ThesisChartScreen มีค่าตั้งต้น 52/88.5 และ latency ตัวอย่างพร้อมหัวผลสัมฤทธิ์งานวิจัย. Labels ของแท่งคงที่แม้ ctor รับค่าอื่น. ดู `lib/screens/thesis_chart_screen.dart:11` และ `lib/screens/thesis_chart_screen.dart:74`. | ห้ามเชื่อมเป็นผลจริงของผู้เรียน. ต้องระบุข้อมูลสังเคราะห์และ authority/gate ก่อนเชื่อมงานวิจัย. ตรวจ labels จากข้อมูลที่ส่งจริง. |
| P1 | CefrDiagnosticTestScreen มีห้าข้อคงที่แล้วตีผล C1/C2 จากเปอร์เซ็นต์โดยไม่มี instrument metadata. ดู `lib/screens/cefr_diagnostic_test_screen.dart:15` และ `lib/screens/cefr_diagnostic_test_screen.dart:61`. | เรียกกิจกรรมตัวอย่างโดยไม่อ้างเครื่องมือวัดระดับที่ผ่าน validation. งานประเมินจริงรอเครื่องมือ/สิทธิ์ตาม AGENTS.md. |
| P1 | FillInTheBlanksScreen await แล้ว setState โดยไม่มี mounted check; service คืน null แล้วไม่แสดง retry. ดู `lib/screens/fill_in_the_blanks_screen.dart:25`. SentenceService คืน null เมื่อ provider ไม่พร้อม. | ออกก่อนคำตอบกลับต้องไม่ setState หลัง dispose; ไม่มีคีย์/ออฟไลน์ต้องมีข้อความและทางกลับ. ทำ reproduction แยกก่อนปิด finding. |
| P1 | WordScramble/FillInBlanks ใช้ Draggable/DragTarget โดยยังไม่เห็นทางเลือกแตะสำหรับจัดคำ. ดู `lib/screens/word_scramble_screen.dart:94` และ `lib/screens/fill_in_the_blanks_screen.dart:111`. | ตรวจ TalkBack บนเครื่องจริงและเพิ่มวิธีทำงานครบได้โดยไม่ลาก หากรุ่นนี้เปิดเส้นทางดังกล่าว. รูปอย่างเดียวพิสูจน์ไม่ได้. |
| P2 | ResultScreen reset ไป home แต่ ID ใน FigCraft คาดกลับเลือกเกม. ดู `lib/screens/result_screen.dart:35`. | เมื่อเชื่อมทางเข้าต้องตรวจทางกลับและบริบทชุด/เกม. |
| P2 | หลายฟีเจอร์ในทะเบียนต้นฉบับระบุช่องว่าง เช่น f08/f12/f20/f21/f23/f26/f33/f34. | คง `registry_declares_gap` จนอ่าน implementation เฉพาะงานและมี acceptance runtime. การเปิดหน้าข้อจำกัดไม่ปิดความสามารถเต็ม. |

Findings ข้างต้นเป็น pre-existing/static observations. ไม่ใช่ผลทดสอบล้มเหลวที่รันใหม่ และไม่อ้างว่า diff S1 สร้างปัญหาเหล่านี้. Pair Matching f10/P2.2 คงรอ Research engineering และคำขอแยกตาม AGENTS.md.

## Review disposition ของ S1 initial slice

ตรวจ diff ของ MainNavigationScreen, ChooseModeScreen, ProgressSnapshot, DriftProgressQueries และ DriftLearningRepository พร้อมเทสต์ที่เกี่ยวข้องแล้ว ไม่พบ blocking source finding ใน slice นี้. ข้อสรุปไม่รวม native visual acceptance หรือความครบของ S1.

- Preview อ่านจำนวนคำและคำถึงคิวจาก owner-scoped nondeleted join. ลำดับ dueAt/wordId ตรงกับ listDueWords. Home ไม่อ่านคำแปลมาเผยก่อนเฉลย.
- Shell rebuild entries เมื่อสลับแท็บ จึงส่ง isActive false/true ให้หน้าฝึก refresh. IndexedStack ยังรักษา State ตามชนิดและตำแหน่งเดิม.
- ปุ่มเปิดคลังยังตรวจ vocabulary registry. ไม่เพิ่มผู้เขียนข้อมูลหรือเปลี่ยน schema.
- Bounded no-comments pass พบ comment เพิ่มใน S1 diff เป็นศูนย์. ไม่เสนอ churn กับ comment นอก diff.
- เทสต์ใหม่มี due → saved → shell และ scroll retention แต่ผู้วิจารณ์ไม่ได้รันเทสต์. ยังควรตรวจเพิ่มคำจากคลังแล้วกลับ home เพื่อครอบคลุม isActive refresh โดยตรง.
- ยังรอหน้าเลือกวิธีฝึกแยกจาก shell, ภาพ Android 200%, TalkBack และการตรวจบน source ที่ freeze.

## ภาพอ้างอิง S1 ที่เปิดดู

ใช้แบบ LexiQuest รุ่น `21b34eaa` ใต้ `C:/Users/Phet/.codex/worktrees/figcraft-design-reset-20261113/LexiQuest/docs/design/2026-11-13-design-reset`.

- `screen-previews/choose_mode_screen.webp` เป็นหน้าฝึกภาษา.
- `screen-previews/main_navigation_screen.webp` เป็นหน้าเลือกวิธีฝึก. Flutter MainNavigationScreen ดูแล shell สี่แท็บ จึงต้องแยกหน้าที่ตาม README.
- `navigation-preview.png` ใช้เทียบหน้าฝึกกับคลัง.
- `navigation-design.md` และ `learn_home.py` อธิบายสถานะหลังทบทวน.

แบบ 390×844 ใช้แนวซ้าย 24, หัวเรื่อง 32, หัวข้อ 22 และเป้าแตะ 48. มีคำถึงคิวให้เห็นคำ/ประโยคจริงพร้อม “ทบทวนคำนี้” โดยไม่เห็นคำแปลก่อนนึก. คิวจบแสดง “ทบทวนครบแล้ว”. ผู้ใช้ใหม่มีทางเข้าคลัง. โหลดล้มเหลวแยกเป็น “ลองอีกครั้ง”. ตัวอย่าง platform/หนึ่งคำในแบบไม่ใช่ข้อมูล runtime.

### ต้นฉบับภาพคู่สำหรับตรวจ Flutter

แยก bytes ของ native FigCraft export ที่ฝังใน HTML มาเก็บโดยตรง ไม่ resize, crop, re-encode หรือสร้างพิกเซลใหม่. ยืนยัน source checkout อยู่ที่ `21b34eaa5cdb4a4ffd8b4d5dcbc51e5052b68aa8` และไฟล์ต้นทางสองไฟล์ไม่มีการแก้ใน working tree. ขนาดทั้งสองภาพ 390×844.

| ไฟล์หลักฐาน | HTML section / FigCraft frame | สถานะที่เทียบได้ | SHA-256 ของภาพ |
|---|---|---|---|
| [design-home.webp](design-home.webp) | choose_mode_screen / 2 | ชุดการเดินทางมี platform ถึงคิว 1 คำ | 5b61041d0c13c6a944dbd5d0614ee8f3bda59f30eafec3cee3544c7380a4057d |
| [design-library.webp](design-library.webp) | categories_page / 46 | การเดินทางมี station/platform/ticket และของใช้ในครัวยังว่าง | e8104d60a9962e54a8606e818a3bf78ea07993439353c7297feba08fd357430d |

HTML ต้นทาง `ลองใช้งาน.html` มี SHA-256 `400b0cc1be6aaa837d004fb60d58171ab6f89d19b00f7d24b899c097dc93da0e`. ไฟล์ `LexiQuest.figcraft` มี SHA-256 `b0920d7043a1981447a16a14a39939dcb96f63215817ba657f0bb87fb2f6f245`. ภาพคู่ Flutter ต้องมาจาก Android จริงหรือ emulator และระบุ SHA/device/data state แยก. ภาพ FigCraft สองภาพนี้ไม่ใช่หลักฐานว่า Flutter ทำงานผ่าน.

ไม่พบ home ผู้ใช้ใหม่หรือคลังทั้งระบบว่างในแบบที่ตรึง. `_kitchen_empty` frame 175 เป็นเพียงหน้าชุดว่าง จึงใช้แทน home หรือคลังรวมว่างไม่ได้. กรณี fresh/empty ต้องตรวจพฤติกรรมเพิ่มเติมโดยแจ้งว่าไม่มี visual reference สถานะเดียวกัน.

## Native Assessment A ที่ยังรอ

ยังไม่ให้คะแนน Nielsen หรือ verdict ผ่าน เพราะไม่มีภาพ Android ของ source ที่ freeze ในรอบนี้. รอ 360×800/390×844 ที่ 100%/200%, สว่าง/มืด, กลับจากรอบฝึก และคิวมีคำ/ว่าง/ผู้ใช้ใหม่/โหลดล้มเหลว. ตรวจสระ/วรรณยุกต์ เป้าแตะ ทางกลับ และ TalkBack ตาม verification.md. ต้องแยก device/emulator/widget-render evidence และไม่ใช้ภาพออกแบบแทนภาพแอป.

แอปต้นแบบคือ AllTCAS, Astra AI, Duolingo. ชุดศึกษา Lingo Trail เป็นงานสร้างกลับ. รอบนี้ไม่ได้ใช้ภาพ Lingo Trail ตัดสินพฤติกรรมของ Duolingo และไม่มีข้อกล่าวอ้างใหม่เกี่ยวกับ Duolingo.

## Run notes

อ่าน source, route factory, CSV ทั้งสาม และ tests ที่ใช้เป็น candidates. ตรวจ assert จำนวนแถว/ID ไม่ซ้ำ 48/44/64 และไม่มี runtime pass. รัน Impeccable context แล้วไม่พบ PRODUCT.md/DESIGN.md; scoped native review ใช้ blueprint/design evidence ที่ผู้ใช้ตรึงไว้. Native detector/overlay ไม่เกี่ยวข้อง. ไม่เปิด server ไม่เปลี่ยน device setting ไม่รัน Flutter/Gradle ไม่อ้างผล CI. ผู้พัฒนาต้องตรวจ hash/line pointers ใหม่บน SHA ส่งมอบ.

Questions skipped: งานและเกณฑ์ได้รับอนุมัติแล้ว.

## Current P2/S3/S5 source integration

The verified slice passes all1,903 local Flutter tests and clean full analysis with517 unchanged inputs before/after. See [the attestation](p2-s3-local.txt) and [input manifest](p2-s3-inputs.tsv). Independent reviews accepted the library/P2/Score, Weakness/Profile, actual logout and final Source/history return-label changes. The refined profile-clamp candidate passed unchanged production and was rejected as a defect; no clamp patch was added.

Windows Home and Quiz feedback renders were inspected before updating their goldens. This is local source/render evidence. New-source Android images, Linux CI rendering, complete TalkBack and the remaining48/44/64 catalogue criteria are still separate checks. The latest installed/native milestone remains08ce39bc/v28.

## Milestone source review corrections

The independent reviewer found a live-result repair route that ignored the quiz/weakness registry and a standalone-camera lookup race that could create a category/outbox for a new owner before detecting a switch. Both were reproduced with focused RED tests. The corrected source propagates the registry and pins expected owner IDs through vocabulary writer boundaries. The reviewer accepted the corrected source, including parent-to-WeaknessBody registry propagation. Root verified 101 boundary tests and clean full static analysis. This is source acceptance only; Android visual, camera, and TalkBack observations remain separate.

## Review of native-observation corrections

The source following the `984e6164` native observations now offers root Add Word with an explicit destination, literal cross-set word search, actual set counts/previews, and the latest persisted result for the selected set. Home uses the actual due-set name, offers set practice, hides weakness actions without error evidence, and replaces stale progress when dependencies change. Dark actions use a readable Material primary/onPrimary pair. Independent source reviews accepted these changes after reproducing and correcting held stream/future data, stale result/destination callbacks, same-frame duplicate destination requests, and nested category creation adopting a different owner. The latter RED observed one writer call where zero were expected.

Camera results now offer an editable manual draft for an unmapped proposal, a mapped wrong guess, or a no-confident-match result. English is editable; translation and part of speech require user entry. The ordinary vocabulary writer remains the authority and records a distinct manual-correction source only after Save. The reviewer reproduced an old injected vocabulary writing after scope replacement, then accepted the original-scope pin that rejects before the writer. Its RED preserved the stale synthetic row evidence; the corrected test asserts no word or outbox change. Cancel, pending Save/Back, owner switching, and retry remain covered.

The final focused correction run passes 50 tests, including both accepted-model and manually corrected camera journeys through practice and file-SQLite reopen with the same session ID and unchanged set B. The camera/model boundary in those tests is synthetic. The 140-test subsystem run and 26-test home/theme run are separate focused evidence, not a summed coverage claim. The Windows large-text render was opened before updating its golden; the visible change was the weakness action wording. Current-source full regression, latest-head Linux rendering, APK/device retest, known-object recognition, and complete TalkBack observations retain their separate dispositions. S5/S6 impact maps are plans grounded in source, not acceptance results.
