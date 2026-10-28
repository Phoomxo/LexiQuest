# R1 implementation report

Status: DONE. No outstanding R1 implementation concerns. Verified on 2026-09-05 in `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`.

## Scope and changed files

Read the complete R1 brief first, then the required TDD skill and `pubspec.yaml` to confirm the package name, Dart constraint, and existing `crypto` dependency. Subsequent source inspection was limited to this slice. Authored only these three files:

- `lib/features/research/domain/motivation_instrument.dart`
- `test/features/research/motivation_instrument_test.dart`
- `.superpowers/sdd/research-r1-report.md`

No commits, staging, dependency changes, external research, security workers, repository-wide analysis, or additional agents. The controller's schema/migration files were neither inspected nor edited. Standard Flutter test/build artifacts were managed by the required Flutter commands; no generated artifacts were manually edited or deleted.

## Implemented contract

The public API in the brief is implemented using final domain classes and the existing `crypto` package. Constructors immediately detach and freeze locale maps, option lists, and item lists. Nested values are themselves final validated objects. Selection results are unmodifiable. JSON import detaches the complete incoming graph; JSON export returns fresh mutable maps/lists whose mutation cannot change the domain object or its checksum.

Validation throws `FormatException` for invalid domain values and malformed JSON:

- All IDs, response codes, and versions require 1–128 ASCII characters from letters, digits, underscore, dot, colon, and hyphen.
- Prompts and labels contain exactly `th` and `en`, with nonempty trim-stable text of at most 1000 Unicode runes. C0 and C1 control characters, including DEL, are rejected. Tests cover Thai text and supplementary-plane characters.
- Each timepoint has 1–32 items, with item IDs unique across the entire instrument.
- Each item has 2–10 options. Codes are unique within an item, and integer ordinals are unique, strictly increasing, and within 0–100.
- JSON parsing checks exact field sets, object/list shapes, scalar types, enum spellings, locale keys, and all constructor invariants. It rejects missing keys, unknown keys, free-text fields, malformed nested keys, duplicate IDs/codes, noninteger ordinals, and invalid item/option ordering.
- Unknown item IDs and response codes throw `FormatException` during lookup and scoring.

There is no production fixture wording, embedded instrument, or claim of psychometric validation. All synthetic item wording exists only in the test file.

## Serialization and integration details

Canonical serialization uses compact Dart `jsonEncode`, UTF-8 encoding, and SHA-256. `checksumSha256` is a cached 64-character lowercase hexadecimal digest of the immutable definition. Object keys are emitted in the following fixed order:

| Object | Keys in canonical order |
| --- | --- |
| Instrument | `instrumentId`, `instrumentVersion`, `formId`, `formVersion`, `itemCatalogVersion`, `items` |
| Item | `id`, `timepoint`, `prompts`, `options`, `reverseScored` |
| Response option | `code`, `ordinalValue`, `labels` |
| Localized text | `th`, `en` |

Item and option array order is preserved. Reordering input maps at every level produces identical canonical JSON and checksum. Item reordering changes the checksum. Reordering options into descending ordinals is rejected rather than silently sorted.

The checksum is transported separately from `toJson()` and verified through `fromJson(..., expectedChecksumSha256: expected)`. There is no embedded checksum field. Every emitted JSON field is required on import, including `reverseScored`; the typed item constructor defaults that field to `false`. A supplied expected checksum must match exactly. With no expected checksum, decoding still performs all structural/domain validation.

Tests pin an independent SHA-256 vector calculated with .NET SHA256 over the test's canonical UTF-8 JSON literal:

```text
b173460cb4300e2abee01bda39ce5cb8c8e911153e8f611b25517cafff0f72cb
```

Checksum tests cover all instrument identifiers/versions, item IDs, timepoints, reverse scoring, response codes/ordinals, and both languages of prompts and labels.

## Scoring behavior

Scoring resolves every supplied item/code pair before evaluating completeness. Unknown or malformed responses throw even when the selected form is incomplete or the invalid response belongs to the opposite timepoint. Valid opposite-timepoint responses are permitted and ignored for the requested score.

Any missing selected-timepoint item produces `null`, including an empty response map. For a complete form, each ordinal is normalized using that item's own minimum and maximum, reversed with `1 - normalized` when needed, and then the item scores are averaged and multiplied by 100. Tests verify exact 0/100 endpoints, a 50 midpoint, and unequal ranges yielding 37.5 and 62.5. The caller's response map is unchanged.

## TDD evidence

Tests use real value objects; there are no mocks. Compilable API scaffolding was used to expose the absent behaviors before implementation. Each cycle ran the exact focused Flutter command below.

| Cycle | Observed RED | Observed GREEN |
| --- | --- | --- |
| Defensive copying and immutable views | 0 passed / 3 failed; caller mutation changed labels/prompts and emptied items | 3 passed |
| Constructor validation | 6 passed / 50 failed; invalid values returned objects instead of throwing `FormatException` | 56 passed |
| Normalized scoring | 57 passed / 6 failed; complete forms returned `null`, invalid responses did not throw | 63 passed |
| Canonical serialization and strict JSON | 63 passed / 33 failed; missing decoder behavior and expected `FormatException` assertions failed | 96 passed |

An initial serialization-test import-placement compilation error was corrected before the runtime RED observation; it is not counted as behavioral RED evidence. During the next RED run, Flutter once reported that the generated `build/native_assets/windows/sqlite3.dll` could not be deleted. A brief wait allowed the lock to clear; one subsequent attempt ran successfully and produced the expected 33 test failures. No duplicate Flutter process was launched, no process was killed, and no file-error loop occurred. Progress was reported at approximately eight minutes, and measurable progress continued throughout.

## Final verification

From the research worktree:

```text
flutter test --no-pub test/features/research/motivation_instrument_test.dart
Exit 0: +96: All tests passed!

flutter analyze --no-pub lib/features/research/domain/motivation_instrument.dart test/features/research/motivation_instrument_test.dart
Exit 0: Analyzing 2 items... No issues found! (ran in 1.4s)

dart format lib/features/research/domain/motivation_instrument.dart test/features/research/motivation_instrument_test.dart
Exit 0: Formatted 2 files.
```

The 96-test suite passed both before and after formatting. Focused source review and path-limited Git status/whitespace checks were also performed. Verification intentionally did not expand to the controller's concurrent work or repository-wide checks.

## Integration recheck

After the controller reported the temporary line-444 test syntax error, the exact focused test command was rerun against the completed file: exit 0, all 96 tests passed. The two-file analyzer was rerun immediately afterward: exit 0, no issues found (1.3s). This recheck completed at 2026-09-05 05:13 UTC / 12:13 Asia/Bangkok. The earlier import-placement error is resolved. No source changes were needed for this recheck; only this report was updated, within the original three-path write scope.

## Handoff

The slice is ready for controller integration, without a commit. Persist or compare `checksumSha256` separately from the JSON definition, supply all canonical fields on import, and preserve `null` scores as incomplete forms. No outstanding blocker remains from the transient generated-DLL lock. Integration with schema/migration code remains outside this R1 slice and was not tested here.
