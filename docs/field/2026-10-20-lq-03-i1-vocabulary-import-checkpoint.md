# LQ-03 Card I1 — Vocabulary CSV/JSON Import Checkpoint

## Identity and source state

- Date: 2026-10-20 (Asia/Bangkok)
- Architecture-boundary follow-up: 2026-10-21 (Asia/Bangkok)
- Chat/card: LQ-03 / I1 Vocabulary CSV/JSON import
- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- Source HEAD: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`
- Source state: dirty by design. Only the I1 files and picker-specific shared-file lines listed below plus this checkpoint are task-owned; shared runtime files also contain preserved work from other cards.
- Engineering disposition: locally complete for Card I1; not a release, deployment, or research-authority claim.

## Outcome and user-visible behavior

- Replaced manual multi-word comma splitting with a local CSV/JSON file picker and preview flow.
- CSV supports quoted commas, escaped quotes, CRLF, and quoted newlines. JSON accepts a top-level array whose vocabulary fields are strings.
- Import boundaries enforce a 1 MiB file limit, a 500-row limit, extension/MIME consistency when MIME is reliable, and row validation before confirmation.
- Native selection now sits behind a platform-neutral application port. The data adapter checks reported size before reading and uses bounded stream accumulation to reject an actual payload that grows beyond 1 MiB.
- Preview classifies rows as ready, needs edit, or duplicate; users can edit invalid rows, cancel without writing, and confirm only when the preview is valid.
- Selecting a replacement file clears the old preview before validation/read, and adapter/parser failures also clear it, preventing stale confirmation. Cancelling the native picker preserves the current preview.
- Only confirmation calls `ImportVocabulary`; no preview or cancellation path persists data.
- Duplicate detection is owner/category scoped. Reimport after soft deletion reports a duplicate instead of reaching the SQLite natural-key constraint.
- UI reports the repository result after confirmation and exposes preview status through text and semantics.

## Changed files and content hashes

SHA-256 values below identify the final tested source snapshot recorded by this checkpoint.

| File | SHA-256 |
| --- | --- |
| `lib/features/vocabulary/application/import_vocabulary.dart` | `7bcdc3ea0b64e5d24db6737a3bf768fa13b519ad50d2e94e3f398cccb4da39fb` |
| `lib/features/vocabulary/application/vocabulary_import_file_parser.dart` | `0f500522635c33188726bc0ae00307653da4642d3281813e2f7d7d2f3c8e1a38` |
| `lib/features/vocabulary/application/vocabulary_import_file_picker.dart` | `da6009c8e27d1a26934fbe1d70c640f8f518fb39d2d6d40e2cbc7a1c269724f9` |
| `lib/features/vocabulary/data/drift_vocabulary_import_repository.dart` | `a05de3cb2cc6a507241e299ede67a5375840dfb616fe8d986aaa0a1ef35ff81e` |
| `lib/features/vocabulary/data/file_selector_vocabulary_import_file_picker.dart` | `fb898ae4a0c6faec43aa449b05bb5e2c841b9bd54044e8e4d5098cdbf4eab380` |
| `lib/screens/add_multiple_words_screen.dart` | `8eea5388f0c2669286b1f4607634c5b3f0b2e9bae1991eae4813f15e003e075f` |
| `lib/screens/vocab_list_screen.dart` | `4975b6989953f0ef9c40ccf7d47def272dd0d6279839f96cb2a6ab5ca4da1bc3` |
| `lib/runtime/app_dependencies.dart` | `513f6b2c7e71f162aac538b5a94802d3a0ca2b7e6b016a2882af2725df043001` |
| `lib/runtime/app_bootstrap.dart` | `1f765d644be2f47a32271e4718089681fa95c3df099062ab8f464d27dce4625f` |
| `test/features/vocabulary/import_vocabulary_test.dart` | `027a5197a94deff914f0eeeb12a031440efcd434d370bcbedfdaf0a33e88d3c1` |
| `test/features/vocabulary/vocabulary_import_file_parser_test.dart` | `eb37f9d111ebcc3863eb2c219a47dba38ac22d70c7e5ebc24b9539293e97e26f` |
| `test/features/vocabulary/file_selector_vocabulary_import_file_picker_test.dart` | `2ef25daaafa01374fd5333d0701bc2c1b7d52a82e7c906f9ebc6a2d99ef4fb19` |
| `test/screens/add_multiple_words_screen_test.dart` | `16880c0a4fb4aab3034f7b83c54b9abf8872d2ec7ce6d9a644ba25961656e327` |
| `test/runtime/app_bootstrap_test.dart` | `1c5790959f39e8c196ee7bbcabd1382d9d8f1e12afdd9712c17470cc538c1aff` |

## Contracts and scope boundaries

- `ImportVocabulary` remains the sole vocabulary import write authority.
- `AppDependencies` and `AppBootstrap` were touched only to expose and compose the picker port; the screen does not instantiate infrastructure.
- No schema, migration, route, manifest, generated source, dependency, or other shared configuration was changed. `file_selector` was already an approved dependency.
- No feature IDs were added or changed; the approved 8/44 feature catalog and frozen evidence contracts were not touched.
- No TXT, Markdown, PDF, OCR, or I4 work was started.
- Source name retains only `file.name`; neither the full file path nor raw file bytes are logged.
- Test data and restart databases are local and synthetic. No participant answers, guardian PII, credentials, production keys, enrollment, or upload are involved.

## Verification evidence from the final source snapshot

1. Targeted static analysis:

   `flutter analyze --no-pub lib/features/vocabulary/application/vocabulary_import_file_picker.dart lib/features/vocabulary/data/file_selector_vocabulary_import_file_picker.dart lib/screens/add_multiple_words_screen.dart lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart test/features/vocabulary/file_selector_vocabulary_import_file_picker_test.dart test/screens/add_multiple_words_screen_test.dart test/runtime/app_bootstrap_test.dart`

   Result: exit 0, `No issues found! (ran in 3.1s)`.

2. Focused regression suite:

   `flutter test --no-pub test/architecture/participant_screen_boundary_test.dart test/features/vocabulary/vocabulary_import_file_parser_test.dart test/screens/add_multiple_words_screen_test.dart test/features/vocabulary/import_vocabulary_test.dart test/screens/offline_vocabulary_journey_test.dart test/features/vocabulary/file_selector_vocabulary_import_file_picker_test.dart test/runtime/app_bootstrap_test.dart --reporter expanded`

   Result: exit 0, `+40: All tests passed!` (policy 1, parser 10, widget 3, importer 8, offline journey 1, adapter 4, bootstrap 13).

3. Formatting:

   `dart format --output=none --set-exit-if-changed` over the eight boundary-follow-up Dart files.

   Result: exit 0, `Formatted 8 files (0 changed)`.

4. Scope and privacy checks:

   - `git diff --check` on tracked task targets: no whitespace errors; Git emitted only LF-to-CRLF warnings.
   - PCRE2 search for `print`, `debugPrint`, log/logger calls, and `.path`: `privacy/logging references: none`.
   - Added-line scope search found no TXT, Markdown, PDF, OCR, schema, migration, route, manifest, generated-source, or dependency expansion.
   - Final task-owned process check: `task-owned Flutter/Dart processes: none`.

## Review disposition

- Independent read-only code review: accepted with no remaining Critical, Important, or Minor findings.
- Boundary follow-up review first found that an adapter exception occurred before the screen cleared its old preview. A RED widget regression reproduced the confirmable stale state; typed and generic failures now clear preview/existing rows, while a `null` picker cancellation preserves the current preview. Follow-up review accepted the Android-first result with no remaining findings.
- The review also identified missing iOS uniform type identifiers. Product coordination explicitly deferred that compatibility work to a future iOS-only follow-up; this card remains Android-first and does not claim iOS picker readiness.
- LQ-00 final source review then found one additional EOF variant: a closed quoted-empty record without a trailing newline was discarded. A focused regression reproduced it and the parser now finalizes that record for the existing column-count validation.
- Review findings fixed with focused RED-to-GREEN tests:
  - failed replacement file could leave a confirmable stale preview;
  - generic CSV MIME `text/plain` was rejected despite a valid `.csv` extension;
  - CSV `,,` was silently dropped instead of surfacing as needs-edit;
  - a quoted-empty CSV record (`""`) was silently dropped;
  - the same quoted-empty record at EOF without a trailing newline was silently dropped;
  - soft-delete then reimport could reach a SQLite unique constraint instead of returning duplicate.
- Claude review: not available. The read-only CLI attempt returned `401 Invalid API key`; it was not retried without corrective evidence.

## Development failures and recovery evidence

- Parser tests first failed because the planned parser file did not yet exist; the minimal parser was added and the focused suite passed.
- Widget tests first failed because the screen lacked injectable use cases/file selection; the required seams and flow were added.
- One cancellation test exposed asynchronous widget timing and was corrected with bounded pumping.
- Targeted analysis found one unused Drift import; it was removed before the final clean analysis.
- The first restart test emitted a Drift multi-instance warning; fixture lifecycle was corrected, then the importer suite passed cleanly.
- Each reviewer finding above was reproduced by a failing focused test before the root cause was fixed.
- Architecture-boundary evidence: the unchanged participant-screen assertion failed with `add_multiple_words_screen.dart: imports infrastructure directly`, then passed after introducing the neutral port, data adapter, and composition-root wiring.
- Adapter RED first failed because the new implementation did not exist; GREEN covered CSV/JSON filters, native null cancellation, reported-size preflight, and an understated-length/oversized-payload fixture using bounded reads.
- Bootstrap DI RED failed because `AppDependencies.vocabularyImportFilePicker` did not exist; the focused bootstrap test passed after composition wiring.
- The stale adapter-failure regression failed because `confirm-import` remained visible, then passed after exception paths cleared the old preview. The companion valid-to-null case proves cancellation preserves preview without persistence.
- EOF regression evidence: the new focused test failed at `+9 -1` because parsing returned a preview instead of `malformedCsv`; after the one-condition parser fix, parser tests passed `+10` and the complete focused suite passed `+22`.
- A Windows `0x40010004` result was traced to control/termination residue from a prior stopped session; no task process remained, and a fresh session produced actionable test evidence.

## Not run and remaining release dependencies

- Not run: the full repository Flutter suite, native Android picker/device integration, TalkBack passes, physical-device testing, packaging, deployment, or production data flows.
- iOS selection is explicitly deferred: the current type group does not include iOS uniform type identifiers, so this feature must not be presented as iOS-ready until that follow-up is implemented and verified.
- External/release-only dependencies remain: platform-specific picker behavior, assistive-technology validation, device calibration, and the normal integration/release gate.
- These omissions do not change the local Card I1 engineering result, but they prevent a release-readiness claim.

## Handoff and next executable step

- No task-owned Flutter/Dart process is running; the serialized Flutter/build slot is released.
- LQ-00 should inspect the actual diff and hashes, reconcile this dirty snapshot with other authorized work, then freeze/integrate Card I1 using the normal review gate.
- Do not begin I4 or TXT/Markdown/PDF/OCR import work until its dependency and explicit sequencing conditions are satisfied.
