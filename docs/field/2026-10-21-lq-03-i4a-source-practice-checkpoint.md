# LQ-03 — I4a local source practice checkpoint

## Intent, authority, and verified snapshot

- Card: LQ-03 / I4a, bounded local source practice from a user-selected TXT/Markdown file.
- Worktree: `C:\Users\Phet\Documents\LexiQuest`; branch `feature/associative-reading-loop`; base/current HEAD `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`.
- The source coordinator explicitly granted the exclusive production-writer and serialized Flutter/build slot for I4a. Existing dirty files and unrelated work were preserved; the SHA256 manifest below identifies the current verified source/test snapshot.
- State: **bounded I4a engineering-complete; independent review accepted; production-writer/Flutter slot returned**.
- No commit, merge, push, deploy, publication, provider call, device run, real participant enrollment, research upload, schema/migration, new authority, or new dependency was performed.
- Existing program/card caps remain unchanged. No spend or telemetry value was invented.

## Product result

I4a adds the smallest complete local workflow:

1. From Vocabulary, the user opens Source Practice and selects a `.txt` or `.md` file.
2. The picker preflights the reported file size, streams the actual bytes with a 1 MiB hard ceiling, accepts strict UTF-8 only, and rejects unsupported extensions/MIME types.
3. Markdown presentation syntax is removed while readable labels/text remain. The user can preview, edit, and recompute; edited text is rechecked by UTF-8 byte count.
4. A deterministic English-majority gate requires at least five English tokens and an ASCII-letter share of at least 0.70 among ASCII letters plus non-ASCII non-whitespace characters.
5. Matching is case-insensitive, whole-word/whole-phrase, limited to non-deleted words in the currently selected category. Duplicate spelling resolves deterministically. Unknown tokens are shown and can all be inspected, but are never imported or created.
6. Confirm is a local UI state transition and writes nothing. Before launch, the screen refreshes the active category and owner; changed matches invalidate confirmation instead of starting with stale data.
7. The user may start only Reading/Fill or Quiz, capped at 20 matched words with the cap disclosed. Reading uses the existing associative reading loop; Quiz uses its existing learning writer under an explicit source-practice activity/title.

SRS, Dictation, Voice, Ask Lexi, AI generation, network retrieval, automatic vocabulary import, and automatic file/provenance restoration are intentionally outside I4a.

## Privacy, identity, and write boundaries

- Raw selected/edited text, file path, filesystem handle, and unknown tokens are not persisted by this feature.
- `documentId` is an opaque SHA-256 value derived from the lower-cased logical filename. `documentRevision` is a positive deterministic 31-bit value derived from canonical content. Resume requires the user to reselect a file; there is no durable raw-source auto-rehydration.
- Launch is fenced synchronously against double taps. Owner and current-category state are checked before launch.
- Reading progress accepts an expected owner and fails closed if the active owner changed. The Drift progress repository repeats the active-owner check inside the same database transaction as projection/event/outbox writes.
- Associative-learning writes repeat the active-owner check inside their database transaction. Association identity includes owner, document ID, document revision, and stable target word ID, preventing cross-owner, cross-revision, and replaced-word collisions.
- No new table/entity/event-envelope/registry/export/sync contract was added. Existing export, deletion, sync, owner isolation, and architecture coverage therefore remains authoritative; raw source content adds nothing new to export, delete, or synchronize.

## Changed paths

Production:

1. `lib/features/vocabulary/application/source_practice.dart`
2. `lib/features/vocabulary/data/file_selector_source_practice_file_picker.dart`
3. `lib/features/learning/application/learning_use_cases.dart`
4. `lib/features/learning/data/drift_learning_repository.dart`
5. `lib/features/learning/data/drift_associative_learning_adapter.dart`
6. `lib/screens/source_practice_screen.dart`
7. `lib/screens/quiz_screen.dart`
8. `lib/screens/associative_reading_session_screen.dart`
9. `lib/runtime/app_dependencies.dart`
10. `lib/runtime/app_bootstrap.dart`
11. `lib/screens/vocab_list_screen.dart`

Tests:

1. `test/features/vocabulary/source_practice_test.dart`
2. `test/features/vocabulary/file_selector_source_practice_file_picker_test.dart`
3. `test/features/learning/learning_use_cases_test.dart`
4. `test/features/learning/drift_learning_repository_test.dart`
5. `test/features/learning/drift_associative_learning_adapter_test.dart`
6. `test/screens/source_practice_screen_test.dart`
7. `test/screens/quiz_screen_test.dart`
8. `test/screens/associative_reading_session_screen_test.dart`
9. `test/runtime/app_bootstrap_test.dart`
10. `test/screens/offline_vocabulary_journey_test.dart`

Some tracked paths were already dirty before I4a. This checkpoint attests the bounded I4a behavior and the exact whole-file hashes below; it does not reassign ownership of unrelated predecessor hunks.

## TDD and review disposition

- Behavioral RED cases first exposed missing parser/gate/matching/confirm-and-launch behavior.
- Review-driven RED cases reproduced: edited text over 1 MiB, mixed-script English-gate bypass, stale category at launch, double launch, hidden unknown tokens beyond the initial summary, owner switch at the progress/association write boundary, and association-ID collision across revisions/stable word IDs.
- Each reproduction was corrected without weakening assertions. Focused affected tests then passed **70/70**.
- Integration review then found one launch-confirmation race: while owner/category validation awaited, the editable text could invalidate `_confirmed` and `_preview`, yet launch reparsed the new text and compared only matched IDs. The first harness run exposed an ambiguous `LocalOwner` import and lazy-ListView visibility issue; both test-only setup defects were corrected before judging behavior. The valid pre-fix run produced the expected **8 passed / 2 failed** result: both Reading and Quiz navigated after pending edits with the same matched word.
- The narrow fix snapshots the text/preview at launch admission and rejects the launch after the await if confirmation, preview identity, or text changed. Both regression cases assert no navigation/session/evidence, then fresh review+confirm launches exactly once. Focused screen tests passed **10/10** and the connected parser/picker/offline/bootstrap set passed **38/38**.
- Independent reviewer `/root/i4a_code_review` inspected the original I4a and the final narrow race follow-up. Both dispositions: **accepted — Critical 0, Important 0, Minor 0**. The reviewer did not run Flutter/analyzer/build; the commands below are the root-run evidence.

## Final current-source verification

All Flutter/Dart commands ran serially in this worktree. No production/test edit occurred after the final source verification.

```text
dart format --output=none --set-exit-if-changed lib/screens/source_practice_screen.dart test/screens/source_practice_screen_test.dart
```

**Exit 0 — Formatted 2 files (0 changed), 0.04s.** The preceding formatter pass changed only the new test's layout; no behavior changed.

```text
flutter test --no-pub test/screens/source_practice_screen_test.dart test/features/vocabulary/source_practice_test.dart test/features/vocabulary/file_selector_source_practice_file_picker_test.dart test/screens/offline_vocabulary_journey_test.dart test/runtime/app_bootstrap_test.dart --reporter expanded
```

**Exit 0 — 38 tests passed, 13s.**

```text
flutter analyze --no-pub lib/screens/source_practice_screen.dart test/screens/source_practice_screen_test.dart
```

**Exit 0 — No issues found, 4.6s.** Fresh independent review followed this check and accepted the snapshot.

An earlier unscoped `flutter analyze --no-pub` also traversed preserved generated/prototype delivery artifacts under `build/prototype-delivery/r8` and reported 34,469 artifact errors. The command was corrected to the repository source roots `lib test`; no artifact was deleted or rewritten.

```text
flutter test --no-pub --reporter compact
```

**Exit 0 — 1,303 tests passed, 1m17s.** This current-snapshot full suite subsumes the focused Source Practice, owner isolation, repository transaction, offline journey, export/deletion, sync, and architecture tests; no test was skipped or weakened for I4a.

```text
flutter analyze --no-pub lib test
```

**Exit 0 — No issues found, 5.4s.**

```text
flutter build apk --debug --no-pub
```

**Exit 0 — built `build/app/outputs/flutter-apk/app-debug.apk`, Gradle 21.5s.** Flutter emitted the existing future Built-in Kotlin migration warning for `firebase_app_check`, `flutter_tts`, `speech_to_text`, and `workmanager_android`; it was not a build failure.

- Scoped `git diff --check` over the two authorized follow-up source/test paths: **exit 0**.
- Source scan of the three new Source Practice production units for direct I/O/network/provider markers: **no matches** (`rg` exit 1 means no matches).
- `crypto: ^3.0.7` and `file_selector: 1.1.0` exist unchanged in both HEAD and the current `pubspec.yaml`; I4a added no dependency. The current `pubspec.yaml` has unrelated pre-existing dirty lines, which were preserved.
- Runtime inventory at `2026-10-21T04:51:51+07:00`: workspace-owned Flutter/Dart/Java/Gradle process count **0**. No process was killed.

## UI/accessibility evidence and limits

- Widget coverage exercises the 360×800 layout at 2× text scale, long content, edit/recompute, matched/unknown review, lazy “show all” unknown inspection, confirmation invalidation, delayed launch fencing, and error/live-region states.
- Controls use the existing Material app patterns and mobile gutters; the content is scrollable rather than relying on a fixed-height body.
- This is widget/accessibility-structure evidence, not physical-device pixel review, measured contrast certification, actual TalkBack/VoiceOver, process-kill restoration, or native file-provider validation.

## Known limits and next step

- Logical identity intentionally hashes the lower-cased filename, not a durable filesystem identity; two different files with the same logical filename and identical content are indistinguishable for local session identity.
- The 31-bit document revision has a theoretical hash-collision risk. It is sufficient for bounded local practice identity, not a cryptographic provenance or research-evidence contract.
- Resume does not happen automatically after restart. The user must reselect the source; raw content/provenance remains non-durable by design.
- No new deletion/export/sync entity exists. The feature relies on existing learning records and their current lifecycle coverage.
- No release-readiness, production permission, research efficacy, provider/device, or deployment claim is made.

**Next:** the coordinator may inspect this checkpoint and manifest, accept/reject bounded I4a, and assign the next card. I4a returns the exclusive production-writer/Flutter slot and starts no later card.

## Final SHA256 manifest

| Source/test path | SHA256 |
| --- | --- |
| `lib/features/vocabulary/application/source_practice.dart` | `F50596AAED391E56DA8F880A9151DF90254C1DF191E53D1FBEEB91E0468DA44D` |
| `lib/features/vocabulary/data/file_selector_source_practice_file_picker.dart` | `D239EDE16B639AAC00536D68D1DCC050D0D93B44FBA4D7CF8530173AC96F1DB7` |
| `lib/features/learning/application/learning_use_cases.dart` | `6563C3FFAEE65006AE05D783083224F47DA70F39E4B6D73265FE1377CF0C82EA` |
| `lib/features/learning/data/drift_learning_repository.dart` | `11545041125FAD45A75938CA86B22E41933754DCA60F3D5C9A028635470588DC` |
| `lib/features/learning/data/drift_associative_learning_adapter.dart` | `64D4621DAF98803248BD65ECDCF10BBB6184E623FEB1B614F9FCFD7207AFB5BB` |
| `lib/screens/source_practice_screen.dart` | `01D19185F5A5320B825CEA8F296FB55D33A1451C8D2A02763F4C0FBDF4A4F81E` |
| `lib/screens/quiz_screen.dart` | `72D09D7B5C0B8F6926E669D66E721A413BB6C37A158A187026072AB17292DE26` |
| `lib/screens/associative_reading_session_screen.dart` | `298343A0FA748B9C6A7ADCBE7F9C208953660C012DE3B1B681C28199EAA6C947` |
| `lib/runtime/app_dependencies.dart` | `4E64F04A93D7ADCE9868BAC9A363B2D1F621FB4BB067F79C461183AC1C2FB772` |
| `lib/runtime/app_bootstrap.dart` | `8D52606C2494335A0F988C04637280F9D39BECF8F745F62624C2701DEE187923` |
| `lib/screens/vocab_list_screen.dart` | `3AC5D2F8F9E135199452E50E30300E3B307EBCC4B404ED7733A061E4DB374775` |
| `test/features/vocabulary/source_practice_test.dart` | `4858F05DA9FCE90DC4E65F2E4743DF5BBE70B7D7EC4711859CA8674BE562C734` |
| `test/features/vocabulary/file_selector_source_practice_file_picker_test.dart` | `06E27F61F92742D74FFDC1E2BDF6843E64EFA447650EA215931320B72C9C998E` |
| `test/features/learning/learning_use_cases_test.dart` | `8192D9D56063A924AD6417F036D69D51E711CF953314799DE7C4F3C313803783` |
| `test/features/learning/drift_learning_repository_test.dart` | `67E8396DCC4F7F54496BE79AA0014ADD7B853733E6358396AE9526C819E44F25` |
| `test/features/learning/drift_associative_learning_adapter_test.dart` | `70A3C1C2E759E0D954FB4412853A9D619308CBC05BB0AFCD2C133103315D629B` |
| `test/screens/source_practice_screen_test.dart` | `78493A01243F88FD5AF9A0CF3D4A811457F477BFD69AED48CC8A45170AA40CCA` |
| `test/screens/quiz_screen_test.dart` | `7915597CAA6B59A521D6F4EF81A7E94FACA7613EB781A21CFD17F7F746F74F78` |
| `test/screens/associative_reading_session_screen_test.dart` | `95D7D62A0BC3A05D938C468FD804E2C67B8118845951486D1D154054AEA04548` |
| `test/runtime/app_bootstrap_test.dart` | `F79C68C865B7A4B476584F9E5A3154BF686FCC108637EA2D756A35ACF34E5906` |
| `test/screens/offline_vocabulary_journey_test.dart` | `60A3FA39C2041B7EF2AE3B6290FB4B6F066AA55E206B838A05023976E7BB8509` |

Checkpoint hash is omitted to avoid self-reference. No destructive cleanup was performed.
