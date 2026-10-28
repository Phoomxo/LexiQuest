# R1 task brief — immutable motivation instrument

Work only in `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`.
Write only `lib/features/research/domain/motivation_instrument.dart`, `test/features/research/motivation_instrument_test.dart` and `.superpowers/sdd/research-r1-report.md`. Do not commit or touch other files; controller integrates this slice.

Implement an immutable production instrument contract and tests with TDD. Use existing crypto package, no new dependency. Public API:

```dart
enum MotivationTimepoint { baseline, post }
final class MotivationResponseOption {
  // factory/constructor accepting these named fields
  final String code;
  final int ordinalValue;
  final Map<String,String> labels; // exactly th,en
}
final class MotivationItem {
  final String id;
  final MotivationTimepoint timepoint;
  final Map<String,String> prompts; // exactly th,en
  final List<MotivationResponseOption> options;
  final bool reverseScored; // default false
}
final class MotivationInstrument {
  // constructor validates and freezes full caller graph
  final String instrumentId, instrumentVersion, formId, formVersion, itemCatalogVersion;
  final List<MotivationItem> items;
  String get checksumSha256; // canonical order independent for maps, preserves item/option order
  MotivationItem item(String itemId); // throws FormatException for unknown
  MotivationResponseOption response(String itemId, String responseCode);
  List<MotivationItem> itemsAt(MotivationTimepoint timepoint);
  double? normalizedScore(MotivationTimepoint timepoint, Map<String,String> responseCodes);
  Map<String,Object?> toJson();
  factory MotivationInstrument.fromJson(Map<String,Object?> json, {String? expectedChecksumSha256});
}
```

Bounds: canonical IDs 1–128 ASCII alphanumeric plus `_ . : -`; versions same rule. Labels/prompts trim-stable, nonempty ≤1000 runes, no control characters. Both th/en required, no other locale keys. Between 1 and 32 items for EACH timepoint. Globally unique item IDs. Each item has 2–10 options with unique codes and unique strictly increasing integer ordinal values in 0..100. Constructor must freeze nested inputs immediately. FormatException on all invalid inputs. Unknown/malformed JSON keys, enum values, wrong types, duplicate IDs/codes rejected. No free-text response field. Fixture item wording exists only in tests, never claim validated instrument.

Scoring: validate ALL response keys/codes, unknowns throw; known opposite-timepoint responses are allowed and ignored for selected timepoint. If any selected-timepoint item missing return null (never 0). For complete form normalize EACH selected option to (ordinal-min)/(max-min), reverse if reverseScored, average items and multiply by 100. Exact 0/100 extremes and midpoint/unequal ranges tested. Deterministic checksum over fixed-key canonical JSON including all versions and content; fromJson rejects checksum mismatch.

Read only necessary project files and required TDD skill. No Codex Security, no repo-wide analysis. `flutter test --no-pub test/features/research/motivation_instrument_test.dart` and analyzer only the two files. If Flutter startup lock waits, wait for controller dependency resolution rather than launch copies. Report RED/GREEN evidence and changed files. Send concise progress if approaching 8 minutes; stop/report at 10 minutes with no measurable progress.
