# LQ-03 — I4b Source Flashcards checkpoint

## Scope and disposition

- Branch: `feature/associative-reading-loop`
- Baseline HEAD: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`
- State: **bounded local engineering complete; root review accepted**.
- This card adds a `Flashcards` action to the already confirmed TXT/Markdown Source Practice preview and reuses the existing learning/reward authorities. It adds no schema, dependency, provider, raw-source persistence, or reward path.

## Accepted behavior

- The action targets at most 20 matched vocabulary IDs, including words with no existing SRS due row.
- Owner/category/text changes during launch invalidate the previous confirmation and create no practice session.
- Rapid taps admit one launch/session.
- Good/Again records one stable answer intent; failed writes and lost acknowledgements retry with the same identity and cannot mint duplicate evidence or coins.
- Save feedback is shown before Next/Finish. Next never writes an extra answer and Finish is retryable.
- Load failures remain in the error UI without an unhandled child future.
- The 360x800 viewport at 200% text keeps confirmation and practice actions reachable; SRS supports portrait and compact landscape scrolling.

## Fresh root verification — 2026-10-23

```text
flutter test test/screens/source_practice_screen_test.dart test/screens/srs_flashcards_screen_test.dart
```

Exit 0 — **26/26 passed**.

```text
flutter analyze lib/screens/source_practice_screen.dart lib/screens/srs_flashcards_screen.dart test/screens/source_practice_screen_test.dart test/screens/srs_flashcards_screen_test.dart
dart format --output=none --set-exit-if-changed <the same four paths>
git diff --check -- <the same four paths>
```

Exit 0 — analyzer found no issues, formatter changed 0 files, and the scoped diff check reported no whitespace error.

```text
flutter test --no-pub
```

Exit 0 — **1,308/1,308 passed** on the current workspace snapshot.

## Manifest

| Path | SHA-256 |
| --- | --- |
| `lib/screens/source_practice_screen.dart` | `4E616E2C3A0A69FE8321D7437384581C060F76C96CF28B2E49D0B2C5BE6C2254` |
| `lib/screens/srs_flashcards_screen.dart` | `76A83A497E5B02C575E3FA10981E30B3491E5278EA7678F318D09EA691883BA9` |
| `test/screens/source_practice_screen_test.dart` | `86DB7B0122EC88ED6B59AFFD5377B524DB23FEDA706D7959ACB25640DDB300B3` |
| `test/screens/srs_flashcards_screen_test.dart` | `356B6342F7711AD8F37766BDB8B0CB79758BD3CFF127C467D0855A7CDAF985D4` |

## Remaining I4 scope

Targeted Voice and Ask Lexi actions, the consolidated Result/Weakness handoff, durable source provenance/restart lifecycle, and physical-device/TalkBack evidence remain separate cards. Durable provenance requires an explicit schema reservation plus export/deletion/sync/policy coverage before implementation.
