# Content source inventory

Status: the bounded source inventory is complete for the recorded snapshot. The initial audit found defects in the starter, scanner, and reading paths; subsequent source edits addressed those findings. The companion reports preserve the original findings and do not describe the final state by themselves. Findings remain in legacy helpers with no production caller found, and external content remains variable. Baseline `a5e46226247ef09e7faa8cc12248fe483d7034db`, branch `codex/remaining-system-readiness`, worktree `C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest`. This inventory pass ran no runtime, Flutter, model, or device checks.

## Baseline bundled sources and paths

| Source | Count and status | Caller and impact |
| --- | --- | --- |
| `lib/features/learning_packs/data/bundled_starter_pack.dart` | 12 entries, each with one example and one definition question with three options. Version `1.0.0`. | `learning_pack_catalog_screen.dart` previews and explicitly installs it. `drift_learning_pack_repository.dart` materializes vocabulary and lexical snapshots. Lexical quiz and rich lexical card consume the installed snapshots. |
| `lib/services/object_vocabulary_database.dart` | 127 `ScannedVocabulary` entries, each with label, word, Thai meaning, level, IPA, example, and category. | `object_scanner_use_cases.dart` maps device model classifications through `lookupByMlLabel`; `object_scanner_screen.dart` shows the result and accepts it into the owner's vocabulary. Navigation and settings expose that screen. Existing accepted vocabulary is a stored copy, not automatically revised with this file. |
| `lib/services/ai_reading_content_adapter.dart` | Two level-specific passages, two generic default strings, and one dynamic target-word sentence template. | `choose_mode_screen.dart` calls `generatePassage` for associative reading. Despite its name and comment, the normal path uses local text and sets `isFallback` false with an `ai-gen-` ID. `_includeTargetWords` inserts missing words into a generic sentence, which can be ungrammatical and does not establish meaningful context. |

Counts were obtained with anchored `Select-String` expressions for `LearningPackEntry(` and `ScannedVocabulary(`. Starter option count follows the `_question` constructor. The reading count is a manual inspection of `_curatedBank`, the two defaults, and `_includeTargetWords`.

## Additional source classes

| Source | Count and observed boundary |
| --- | --- |
| `lib/services/cefr_service.dart` | 19 static `CefrWord` entries. `CefrSelectionScreen` consumes them, and `LearningWorldMapScreen` creates that screen. No production caller of `LearningWorldMapScreen` was found by symbol search. `ZpdRecommenderService` also calls `CefrService`, with no production caller found. Treat this as unreachable by the traced entry points, not proof that no reflective or future entry point exists. |
| `lib/services/phrasal_verb_service.dart` | Five static entries. No production caller found by symbol search. |
| `lib/services/dynamic_story_contextualizer_service.dart` | Two named templates and one interpolated default. No production caller found by symbol search. |
| `lib/screens/cefr_diagnostic_test_screen.dart` | Five static questions. No production constructor caller found by symbol search. |
| `lib/screens/boss_battle_screen.dart` | Three default word and translation pairs. No production constructor caller found by symbol search. |
| `backend/lexiquest_lm/dataset/` | Collection, synthetic generation, enrichment, and formatting scripts are training pipelines, not a bundled word list. No checked-in generated corpus was found in the file inventory. Training outputs are external or generated and cannot be counted from these scripts. |
| `test/`, `integration_test/`, and `test/fixtures/` | Synthetic fixtures and test support, including `test/support/authored_lexical_pack.dart`, are not production content sources. Their values can still constrain regression expectations. |
| User input and imported files | Variable cardinality. `add_multiple_words_screen.dart` calls `parseVocabularyImportFile`, which checks CSV or JSON, UTF-8, size up to 1 MiB, and at most 500 rows. `source_practice_screen.dart` uses `source_practice.dart` for user text and file input. `learning_pack_catalog_screen.dart` accepts external packs through the codec. These checks are structural and do not certify meaning. |
| Provider content | Variable cardinality. `app_bootstrap.dart` constructs the configured AI service. `learning_use_cases.dart` requests sentence content for native exercises; `sentence_scramble_content.dart` and `cloze_content.dart` validate it for their exercises. `backend/ai_api/src/lexiquest_ai/services/llm_content_service.py` defines sentence, story, and explanation prompts. Generation and outputs depend on configuration and are not a finite bundled corpus. |

The symbol searches above excluded generated Dart and tests. They establish direct references, not full runtime reachability. The later addendum records further route and source checks and their remaining limits.

## Pack identity, review, and preservation

At the baseline, the starter manifest identified `lexiquest.starter.en-th` version `1.0.0` and said editorial review was pending. The current version is `1.0.1`, as described below. `LearningPackMetadata.quality` returns `userProvidedUnreviewed`; it is not a record of an independent editorial review. The codec hashes canonical payload bytes and verifies length and SHA-256. These checks establish integrity, not linguistic correctness.

`DriftLearningPackRepository.importPack` looks up owner, pack ID, and version. A different package hash for the same identity raises a conflict. An installation creates an owner-scoped category, imported vocabulary, and `lexical_content_snapshots`, retaining package and source information. A corrected package therefore needs a new version rather than mutating bytes under `1.0.0`. Existing installations and user edits must not be silently overwritten. A version bump alone does not prove upgrade behavior or removal of duplicate categories.

`accepted_quiz_plan.dart` serializes accepted question data and checks the lexical pack version identity. Preserve old accepted plans and their referenced snapshots when publishing corrected content. Verify actual upgrade and resume behavior against an existing installed pack and accepted plan before claiming preservation. Review metadata must describe the review actually performed and must not claim certification or independent professional review without evidence.

## Evidence and limits

Inspected `AGENTS.md`, `docs/field/2026-11-04-content-quality.md`, the sources named above, `learning_pack_codec.dart`, `learning_pack.dart`, `learning_pack_use_cases.dart`, `drift_learning_pack_repository.dart`, `accepted_quiz_plan.dart`, `object_scanner_use_cases.dart`, `vocabulary_import_file_parser.dart`, and matching caller references. Discovery used `rg --files` and bounded `rg` searches across `lib`, `backend`, and test paths. `pubspec.yaml` declares the Noto Sans Thai font as an asset and does not declare a learning-content asset directory. This does not prove all content is represented by the searched patterns.

## Current-source route and coverage addendum

The hashes below identify the inspected source snapshot. `main.dart` uses `AppRouteFactory`; `/home` constructs `MainNavigationScreen`. Its learning tab constructs `ChooseModeScreen`, and its drawer constructs the scanner and tutor. `AppDependencies` supplies field defaults. Vocabulary, quiz, SRS, and reading are enabled; scanner, speech, and tutor are limited but visible. Their operation still depends on their model, owner, service, or consent prerequisites. The fallback registry without dependencies is all-enabled. The V2 registry separately defaults research assessment and offline content to hidden, and quest V2 to limited. Product catalog records describe feature contracts and are not a teaching corpus or evidence that all 44 features are reachable.

The pack tile in `ChooseModeScreen` checks for a `learningPacks` dependency, not `Feature.offlineContent`. The hidden V2 flag alone therefore does not establish that this catalog route is hidden. The scanner and tutor drawer entries use their respective field-feature visibility and explain their additional setup requirements.

| Content | Current route and boundary |
| --- | --- |
| Starter pack, 12 entries, version `1.0.1` | `ChooseModeScreen` and settings open `LearningPackCatalogScreen`; preview and installation are explicit. Quiz, SRS, and lexical cards read installed content. See the starter item ledger for the baseline review. |
| Scanner, 127 entries | Main navigation and settings open the scanner when visible. Model availability and a recognized label determine whether an entry is shown. See the scanner item ledger for the baseline review. |
| Reading | `lib/services/offline_reading_material.dart` defines `ReadingMaterial`, which joins the first current lexical example containing the target as a whole word, or the word itself if no matching example exists. It also assembles a meaning and a missing-example notice for supported text. `ChooseModeScreen._openReading` uses this material and no longer calls the baseline generator. |
| Exercises | Quiz, matching, SRS, dictation, word scramble, sentence scramble, cloze, shadowing, ghost duel, and source practice use owner vocabulary, installed snapshots, supplied source text, or provider responses. They are transformations of those inputs, not an additional fixed vocabulary list. |
| Provider and user content | Imported packs, CSV or JSON, typed text, generated sentences, tutor replies, and stored owner vocabulary are variable. Structural admission does not certify their meanings, grammar, or CEFR level. |
| Research instruments | Assessment and motivation instruments are authority-controlled research material, not ordinary authored teaching content. Their access and enrollment depend on research authorization. They were not reviewed or modified here. |

Reading preparation stores ordered pairs of each selected word and its matching lexical snapshot. The screen receives the same ordered words as records containing spelling, word ID, and content revision, so duplicate spellings do not collapse into a spelling-keyed map. The material ID hashes the ordered word and snapshot identities and selected example. This is a source-level observation, not a runtime or migration-preservation claim.

Exact symbol searches found no production construction of `LearningWorldMapScreen`, `CefrDiagnosticTestScreen`, `BossBattleScreen`, `CefrArticleReaderScreen`, or `WordbookImportScreen`, and no production caller of `PhrasalVerbService`, `DynamicStoryContextualizerService`, `AssociativeMemoryService`, `CollocationService`, `LexiVisionAccessibilityService`, or `GlobalWordService`. `CefrSelectionScreen` is constructed by the unreferenced map. These are static route findings, not proof against every future or indirect entry point. The separate additional-content report inventories these legacy datasets, including the newly found collocation and accessibility dictionaries.

The current starter attribution identifies an AI-assisted language and exercise review, says independent human editorial review is pending, identifies a British pronunciation model, and calls A1 an author-declared target rather than certification. The pack detail warns that content is not expert-certified and that file verification checks integrity. The catalog filter still says CEFR and the scanner calls its level approximate. These labels do not establish independent level validation. Model verification messages in the scanner refer to the model, not linguistic certification.

The following relevant files did not match the broad pattern. At the final source check their SHA-256 hashes were `5ffc1d7a36d57e895ae08bdf5cee1aab44a2b6c46b99b149748a007b97018978` for `lib/features/learning_packs/data/bundled_starter_pack.dart`, `d65f9fdc43069d7346236ad1016f5b095e5d66b572505b336928a39fe4b52d5c` for `lib/features/learning_packs/presentation/learning_pack_catalog_screen.dart`, and `1afaf3972aa1d3af7600fb0fef0409334e0595729666addc61097e55ea5cb991` for `lib/services/offline_reading_material.dart`.

The broad pattern search matched 90 Dart files, including generated database code. The ledger below classifies all matching files and records their hashes. Generated schema mirrors, serialization, sync, exports, evidence and progress counters, voice fallback, consent, and billing are infrastructure rather than independent teaching corpora. Matched research prompts are authority-controlled. UI labels and test fixtures are not additional teaching entries. The discovery also inspected static lists in services, models, and screens and found the additional dictionaries recorded in the companion report. Remote provider outputs, generated training datasets, the voice research golden texts, and final runtime feature configuration remain outside this source-only review.

## Matched-file classification ledger

This ledger covers all 90 Dart files returned by the case-insensitive pattern `exampleSentence|example_sentence|correctAnswer|correct_answer|questionText|quizQuestions|sample (sentence|question)|dummy|mock|fallback|gemini|prompt` under `lib` in this source snapshot. Every matching line was inspected in bounded groups. Scanner examples are also itemized in the scanner review. The SHA-256 is over each complete file, and the count is the number of matching lines. The code letters classify the matched role, not every possible line in the file.

F means finite learning content. U means an unreferenced legacy teaching source or its UI. V means variable input, exercise, or provider boundary. I means generated code or infrastructure. C means UI copy. R means research authority or instrument handling. A file may have other roles. The file list does not include other relevant nonmatching sources such as the starter pack, reading material, collocation service, accessibility dictionary, or backend prompts; those are classified above and in the companion report.

| File | Class and reason | Matching lines | SHA-256 |
| --- | --- | ---: | --- |
| `lib/models/cefr_word.dart` | I: CEFR value model and JSON fields | 4 | `576002bb0ccf5863c1bea556526499cb4d6bbf3cea380744bec1d47e441b6672` |
| `lib/models/phrasal_verb.dart` | I: phrasal-verb value model and JSON fields | 4 | `1fc3fda5ca5b735da84cb089d036e4ef6ea3e8ee5d0a61b03623b7b1d476f244` |
| `lib/progress/local_progress_repository.dart` | I: progress answer counters | 17 | `800f0c49e846dc3458ff980d6a968dd8e0d1564ec0f92798176b18b245d120d6` |
| `lib/progress/progress_repository.dart` | I: progress answer counters | 8 | `01a95d91123964b8d948acc59a46dab478e4799cb0dc12770a13f2a5c562f63d` |
| `lib/runtime/app_bootstrap.dart` | V: tutor dependency composition and owner scope | 62 | `e37b0ac38fd64932c81de3bf13066ea900898cb093afbd261d4ded04ce7d2531` |
| `lib/runtime/app_dependencies.dart` | I: dependency declarations | 3 | `d1bcb90147fa56a1661e1c20b3300c4ad262b8dad8946848758fff79a2ee1473` |
| `lib/screens/ai_tutor_screen.dart` | V: tutor scenarios and provider output UI | 40 | `c78e1c5ecd9cbaf525c353d29ef4df8177daf04b17f90cfebdd064f2be17f401` |
| `lib/screens/associative_reading_session_screen.dart` | V: reading inputs and evidence mode | 2 | `0e2254047ceb1c2ea9598926e8775ee404c948c8012ef674143c6ff76cba042a` |
| `lib/screens/cefr_selection_screen.dart` | U: CEFR service examples on unreferenced map route | 2 | `743dbac388cc4da83bcc432c3ea63c16bc5b12200c908caf418121cb49af6b07` |
| `lib/screens/choose_mode_screen.dart` | I: activity navigation and answer count | 1 | `5170b5b0afc3ebd5671fd510c5e7253c8aa9ed4802b5c3e84b2474cbeeb44b35` |
| `lib/screens/gemini_settings_screen.dart` | V: provider settings, consent and errors | 50 | `d98344a66c495b4969609518d87dac8966e91d2a052939dbc1dc7e3887f9d3e9` |
| `lib/screens/ghost_shadow_duel_screen.dart` | V: owner-word prompt and evidence | 4 | `d32130010baf1b18a27863e85cca05faefdf7117fb4ff2d5440a6b15e794452c` |
| `lib/screens/login_screen.dart` | I: account email fallback | 3 | `eae1b274317f72fdee5738924dda2054c25c74eb16afb3064fa7ac2225a04296` |
| `lib/screens/main_navigation_screen.dart` | I: tutor navigation | 4 | `8427bf4d9363a9d554a7b0833398b85f726f7f67319b24b8a89cf54c3f8f09fd` |
| `lib/screens/matching_quiz_screen.dart` | V: owner-derived matching and score | 1 | `653f5ffc92689539d1c4604a6618ddaab00e1c439d3fb982f9bc96737369d2f7` |
| `lib/screens/pre_post_assessment_screen.dart` | R: assessment instrument prompt | 1 | `b23f1a9d11fb7d4a5878ca3f73b1fae357b5dbd8fa01304725ebc8333cfe00dd` |
| `lib/screens/quiz_screen.dart` | V: supplied quiz prompts and answers | 3 | `ac9df8cf5518ad4551f1a0f79720f582870e6fc24ba8511946d3d86942e72ab1` |
| `lib/screens/score_screen.dart` | I: session score counters | 5 | `349dec4300085bf712e5d6953602a9c3af771cc2b6d758a2c51d1a975ab7b8aa` |
| `lib/screens/setting_screen.dart` | I: tutor settings navigation | 3 | `67e2fed37d48f2f4e0c317985c2534254f22f2bc00f6e40b70a6aa8c9dae0334` |
| `lib/screens/shadowing_challenge_screen.dart` | V: owner-word voice prompt | 5 | `1583c449c9524572b9e94f2b42db422cfc860c42dd86201f766091b1d82ae60c` |
| `lib/screens/source_practice_screen.dart` | V: user source and tutor draft | 5 | `54867c3c7496d8e5686c0a29eadaae793ddc3d7ac5af98a155e09fef3611df57` |
| `lib/screens/speak_to_text_screen.dart` | V: owner-word speech exercise | 5 | `041d425545067638e68921eca1af5d63ed9c376eff83def51f5df66e5e9c2643` |
| `lib/services/associative_memory_service.dart` | U: three fixed associations, no production caller | 3 | `61e88e83ead3d8a42635eb495359c70a1a12ac47dca1a1bc41a7e00af8632a79` |
| `lib/services/cefr_service.dart` | U: 19 CEFR entries and enrichment fallback | 20 | `fd9356b5b89f039d004df5a98758b20a622cc9a28cb83b0ff1ae9456fa9397f0` |
| `lib/services/ghost_shadow_duel_service.dart` | I: duel scoring comment | 1 | `7b1f4c2cc4bc706a3dc426d850f3a7db7926e02643f04077f789b099f03aa719` |
| `lib/services/interleaved_srs_scheduler.dart` | I: category scheduling fallback | 1 | `1cb25d4c790353ec23c3d4e9da076cf02e89d8301f52c3f3f0689d5365497738` |
| `lib/services/object_vocabulary_database.dart` | F: 127 scanner vocabulary entries | 129 | `6b9f0f0aea20ce88b147774b8711f93803b14c6ab5c0b120d9cd5b6670a546b8` |
| `lib/services/phrasal_verb_service.dart` | U: five fixed phrasal verbs | 5 | `a479666627867e31c7012480bf4a9070e7f0adbd74c56a1281281e8182c3e01d` |
| `lib/services/research_experiment_service.dart` | R: research telemetry sanitization | 1 | `88f000b14fce93a23cbb88ade85195959639b3c04dc470c554b934e03323b506` |
| `lib/services/voice_reading_adapter.dart` | I: voice provider fallback | 2 | `0da464c09a226213f6d62716b03f1c1e70c2a53efa640e5ff843dcef22a552a7` |
| `lib/voice/hybrid_voice_service.dart` | I: voice playback fallback | 14 | `4f51b0babfb765429ccfcc81edd54059558c617505e4f028810d6341fbb70aba` |
| `lib/voice/native_tts_provider.dart` | I: native voice playback state | 1 | `b37f01176d341a946309851976250a950a6c07ddc0c6d35a43055c9d88a81858` |
| `lib/voice/voice_models.dart` | I: voice result data | 2 | `11c72782f8c0daf6fc0f71c2c7e1a698d443937ba28a3ec2e678f525884b3094` |
| `lib/voice/voice_telemetry.dart` | I: voice fallback telemetry | 18 | `1d3ddd496f76d2de54e2564701737b8ee7b16c615c55d2e5ac0623f0b5b0666c` |
| `lib/widgets/association_dialog_widget.dart` | U: association input widget, no service caller | 5 | `16916e694e1387f3da773bf18bc802cd91b5ff029910e0593bca2be5218454d8` |
| `lib/runtime/registries/consent_registry.dart` | I: consent declaration | 1 | `6a3836d33589979e6fe0b4a1193c361abf5bf7e9900191026da29d891f9e1926` |
| `lib/features/sync/data/drift_sync_store.dart` | I: sync evidence prompt mode | 6 | `5d8377b709e88651dab5f130b548cab39b3c5646754cd43e8d8989643951a8e0` |
| `lib/features/sync/domain/sync_entity.dart` | I: sync evidence validation | 5 | `df9b5a3f9dac03d6a03b13a4c2efe475d01e8e376c9e9fad419732789bca9ce5` |
| `lib/features/rewards/data/drift_achievement_share_reader.dart` | I: reward evidence read | 1 | `c3d024feecdb3a3d84d352d3f7b3327dcfce6aa08cd079140a20796d07cfe6e8` |
| `lib/features/rewards/data/drift_reward_projection_rebuilder.dart` | I: reward evidence projection | 3 | `725a3b868ab18db88ba854dac74becda3a50341269bd67358faaf016fbc484d8` |
| `lib/features/research/application/local_study_runtime.dart` | R: study prompt expiry | 5 | `06a817badef0e85e8b70cd0c801cc4ce311166b5bc9330a7236bb1c854cb7224` |
| `lib/features/research/application/study_runtime.dart` | R: study prompt expiry model | 2 | `9d03d0fcf0fbaea563143a5f1e8d9317758116b709b9b130dd9e7a91c6a22493` |
| `lib/features/research/data/drift_study_archive_repository.dart` | R: study archive evidence | 1 | `6a88fb84589a082ff714ca54dd17d9eecd26ce945487bbe516c62450701ae272` |
| `lib/features/research/domain/motivation_instrument.dart` | R: instrument prompt contract | 8 | `687a49be3bd1581cfcb524892d137cc7b569e64b5fb4711c6cded0d209e7733d` |
| `lib/features/research/presentation/motivation_measurement_form.dart` | R: instrument prompt rendering | 1 | `2066ac7a2ff3ccc8225bf3d11abcaf8bbcfb3f7e1b0d0e5bdc1d343000a7a6b7` |
| `lib/features/research/presentation/study_host.dart` | R: study prompt expiry checks | 4 | `540e31a7e29c5ce5ea75310051ca492b81a95397d67858ccada99537c787fd54` |
| `lib/features/quest/application/quest_catalog_provider.dart` | I: quest scoring definitions | 4 | `9607c962f52d131ac98f230e838b417eb17f1f87645acc5bdeae95e3aaf2d27f` |
| `lib/features/quest/data/drift_quest_repository.dart` | I: quest evidence persistence | 6 | `95e5cc85e1df0f223040fb11f63bf867b584a0543f136f010d78df176458f039` |
| `lib/features/progress/data/drift_progress_queries.dart` | I: progress evidence query | 4 | `38e835429ca0c85106278b3ef381dc8d4c6327bd1bd71b1a80c4a8b610d25f96` |
| `lib/features/motivation/data/drift_learning_day_recorder.dart` | I: learning-day evidence | 2 | `1fda36d07570dd48361fd9b7e0564cec315956612b7a05512a2781a51c5659a3` |
| `lib/features/motivation/data/drift_streak_repository.dart` | I: streak time fallback | 1 | `52b554ffc7aeee85b471dda353ca723d4f9f4772eee0981ff55bd7d84194fb7f` |
| `lib/features/motivation/domain/motivation_snapshot.dart` | I: streak fallback state | 2 | `3e31642163ad141b0a79cc50a19ac5856109084d94098e16098867a3c5d56701` |
| `lib/features/motivation/presentation/quest_screen.dart` | I: streak fallback UI | 1 | `0baff9ef7b03efb6e02f99d53bcc809c35fc21371aa1c1e39494f1d43898f5ec` |
| `lib/features/media_practice/data/plugin_camera_gateway.dart` | I: camera permission error | 1 | `b12e908b88175ef330cd3ee02e6d94c98782184d1bf22f4fb7d851118d5108b6` |
| `lib/features/learning_time/domain/learning_time_models.dart` | I: learning-time mode identifiers | 16 | `6db2f13ade389c5b31dd931c705f32f2255e630e6b89ead18fae17da8bfe0433` |
| `lib/features/learning/application/current_activity_evidence.dart` | I: activity evidence mode | 6 | `04590153e3bab322c1ff80852f619e2c28135190bec7bfa1606f4484c8a90a82` |
| `lib/features/learning/application/learning_use_cases.dart` | V: owner and provider exercise orchestration | 15 | `219f77aeff25afe0d561f0eebbe66d1d05d7d182932c70c1203cadea8bad2dce` |
| `lib/features/learning/data/drift_learning_projection_rebuilder.dart` | I: learning evidence projection | 1 | `f83ae880a65714054e7354f0f21c7900ed2cf0ae7b9431be31f4b8f8d2301f38` |
| `lib/features/learning/data/drift_learning_repository.dart` | I: learning evidence persistence | 30 | `0a779238afb8e4f86ed6a5e4f512d1329cdc03993ef49d58720de2e7a5645cf2` |
| `lib/features/learning/data/drift_matching_repository.dart` | I: matching evidence persistence | 2 | `a359ccb0311bd7b72d854da74f5e5af0843157201ef855cae1d71f28ab1b9ec6` |
| `lib/features/learning/data/drift_recall_ladder_reader.dart` | I: recall evidence reader | 8 | `807ac2b57fea7a3ff97bf0cf557cf02782f637accabdad2f2d136100b945acdc` |
| `lib/features/learning/domain/accepted_quiz_plan.dart` | I: accepted question serialization | 18 | `f01f7e690ee030ab75b1ac7efc5691d394bce40f4d0f11fd1cbe0ce2148ad76c` |
| `lib/features/learning/domain/learning_evidence_contract.dart` | I: evidence mode contract | 10 | `b9c8d60a5717d94ccab1fad14930b4abe71b506612bf97b6e36e4be5d973c505` |
| `lib/features/learning/domain/learning_models.dart` | V: prompt and answer derived from supplied word | 6 | `f6d555b80d00c685ae7ce3658c83e37d2fc77e110d424c89520cf5272d3f35f6` |
| `lib/features/learning/domain/learning_time_admission.dart` | I: voice prompt admission | 2 | `d5deec2e19e85c910af9da1f350745aa3845afda69c32d305b71a5defd7b6072` |
| `lib/features/learning/domain/matching_exercise.dart` | I: matching mode contract | 2 | `f2e4ac37b48f067849706810e9e989b41e9b38f7e81051f21d308cc812cc2212` |
| `lib/features/learning/domain/native_exercise_checkpoint.dart` | I: exercise checkpoint serialization | 2 | `f18e621f64dfe52275756de053f684dd0740c4f88ffe89c1aa78c8c040e1a4ba` |
| `lib/features/learning/domain/recall_ladder.dart` | I: recall evidence classification | 5 | `b24bdd9a6bffb025bfe9f7b3cce427d0b8e7a79aba55afc7c11fdb48bc0aa9d9` |
| `lib/features/learning/presentation/native_exercise_resume_screen.dart` | I: exercise score UI | 1 | `9c18dcc6645d75c1c50717a2da1cabdeb75387d0b98163fa2a34738ed015b5f6` |
| `lib/features/gemini/application/gemini_tutor_use_cases.dart` | V: tutor consent and provider request | 55 | `99621a4a03c1c14d510102525ce828ce41451c9610cd433ec42cc6fc43997593` |
| `lib/features/gemini/data/gemini_rest_gateway.dart` | V: tutor prompt and provider responses | 48 | `7de281d666d2d08cedbc5d4dc67c9d6d172e8f05c338efbb5823df6332f33a01` |
| `lib/features/gemini/data/secure_gemini_settings_store.dart` | I: scoped settings storage | 20 | `6603c5fbdac64e9e68153f8201fd43aed0ea1333e2d51f365f831b1f63ebd8a2` |
| `lib/features/gemini/domain/gemini_contracts.dart` | I: tutor interface and response types | 31 | `45eab8786abe20f95498f5eca2479857854a98edaa0871bbc97b3610cc1fc800` |
| `lib/features/export/application/export_use_cases.dart` | I: export record fields | 6 | `d17b36b76654cfabdf7706b79b0b442138b89079adcca557725af35d573b1780` |
| `lib/features/export/data/drift_export_reader.dart` | I: export evidence query | 4 | `d0cd39de30a69b625609f5cb78dfa5db80c3ac957720ac074daa8b3399bacd21` |
| `lib/features/events/application/event_v1_to_v2_adapter.dart` | I: event evidence adapter | 2 | `c093b430d91f8bdec627c8c83cd5452e878c33fcde2974b90859773619736e93` |
| `lib/features/events/domain/event_envelope_v2.dart` | I: event provider identifier | 1 | `47f13940b67dc3d40021c48a1b447f408f51b32282704d680d0dccd9c6bc0fb3` |
| `lib/features/device_model/domain/model_lifecycle.dart` | I: device model fallback comment | 1 | `d98094d98b39ce4beeeb1cabfaf8f51784b1aab2f565a19c6aa66509461f4c49` |
| `lib/features/content_reports/domain/content_report.dart` | I: report origin metadata | 2 | `1754c80fc115201ab02e6619a280dbdc0bac77e8e481cdd3aa816409f6ddf243` |
| `lib/features/content_reports/presentation/content_report_sheet.dart` | C: reporting instruction copy | 1 | `363b0d3cbdff670a124f39b7948f1c64aa9e0359c6e1cc6e6af7452af5622093` |
| `lib/features/billing/presentation/subscription_screen.dart` | C: subscription explanation copy | 1 | `6ca66f1cd5ba3668c78b3773aa13c1d4c67a51a3bafbc628afa7d2a805f8ebf7` |
| `lib/features/assessment/application/assessment_comparison.dart` | R: assessment comparison | 1 | `9992825b510546bdaa56875faa725ad3ff3a8266afdffe2813d66448c6a155bb` |
| `lib/features/assessment/application/assessment_use_cases.dart` | R: assessment item use cases | 1 | `02892cfba10ad94c8b36e27eaf146aa6ac5b459e2d6121c05d5066ef4d32f92b` |
| `lib/features/assessment/data/drift_assessment_repository.dart` | R: assessment evidence persistence | 4 | `f6d74473f526dc344f81d60e1d6f80e5286ba1b9c2c11efa8e1382a87db8caad` |
| `lib/features/assessment/domain/assessment_instrument_catalog.dart` | R: instrument catalog contract | 10 | `0d5c960260fd2e20c7b24cf1f678463a15e0efc7877aada1cf835b61bd6e5b77` |
| `lib/features/assessment/domain/assessment_models.dart` | R: assessment prompt model | 5 | `e2dfc1f9f1f7160b0df8e1b741b2d119f82ac9ae30db20b2b14633267b2532e4` |
| `lib/features/assessment/domain/assessment_repository.dart` | R: assessment evidence contract | 5 | `19e0afbc853a09715ab717adc07a75d6d66be0124b2612609ce7f771b2371f39` |
| `lib/features/adventure/domain/adventure_entry.dart` | I: adventure fallback status | 4 | `d3e890c56e167608fc84ea7055c0cce1715e7f2fc750f86f72407806c5702f67` |
| `lib/data/local/app_database.g.dart` | I: generated database prompt-mode column | 48 | `517d6ba9003aeea33c00a0e3ef8af5cdb336b6d7281b0ae8785f6324e70b32f8` |
| `lib/data/local/tables/learning_tables.dart` | I: source database prompt-mode column | 1 | `05a50b8fdaadd16ee1dcc6d4298709623df18ba37db2c9ec6f058565d616a869` |
