# SOURCE-READING-FLASHCARDS-RESULT-LOCAL-1 checkpoint

## Disposition

- Date: 2026-10-23, Asia/Bangkok
- Branch: `feature/associative-reading-loop`
- HEAD baseline: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1` (unchanged; no commit)
- Status: accepted local engineering on the current dirty worktree; not a release or production approval

## Implemented behavior

- Added immutable `LearningSessionResult(summary, mistakeWordIds)` as the child-to-parent boundary.
- Reading returns the result only after the Stage 6 checkpoint. Stage 3 records answers and finishes once; Stage 6 does not duplicate attempts, Finish, progress or rewards.
- Source Flashcards returns the authoritative result only after every saved rating and acknowledged Finish. Lost acknowledgement retries retain the same attempt identity.
- Source validates completed state, non-negative counts, exact target total, rounded score, unique mistake IDs and target membership before opening Result.
- Result reuses `ScoreScreen`; correct rounds have no repair CTA, while mixed rounds open one explicit `QuizScreen` using only unique wrong IDs.
- Owner, category, source text, preview document/revision, word metadata or dependency invalidation closes/rejects Result and repair without fabricating a session.
- Result remains in-memory for the uninterrupted flow. No schema, generated source, dependency, reward or progress authority changed.

## Verification

```powershell
flutter test --no-pub test/screens/associative_reading_session_screen_test.dart test/screens/srs_flashcards_screen_test.dart test/screens/source_practice_screen_test.dart --reporter compact
```

- Exit 0, **98/98 passed**, 06:56.
- Covers Reading Stage 6 result, Flashcards Finish result, multi-wrong mapping, explicit repair, malformed counts, owner/context invalidation, retry identity and 200%/landscape regressions already in the three focused files.

```powershell
flutter analyze --no-pub lib/features/learning/domain/learning_models.dart lib/screens/associative_reading_session_screen.dart lib/screens/srs_flashcards_screen.dart lib/screens/source_practice_screen.dart test/screens/associative_reading_session_screen_test.dart test/screens/srs_flashcards_screen_test.dart test/screens/source_practice_screen_test.dart
```

- Exit 0, no issues.
- `dart format` reported 7 files / 0 changed; scoped `git diff --check` passed with only existing LF-to-CRLF notices.

## Source hashes

| Path | SHA-256 |
| --- | --- |
| `lib/features/learning/domain/learning_models.dart` | `FD88E06C0382C74ACC6AACC605D432F7A6F21883FC674FD80A835B5E879B097E` |
| `lib/screens/associative_reading_session_screen.dart` | `0E23377B2CC48B6EB0EDB565AA33282E70D8329A2D89FEA60B7EA2B5398CE71C` |
| `lib/screens/srs_flashcards_screen.dart` | `ACB11EEF45C6CBF7841283036332FB8A91600A24B950AB8E258D3A8BAFA3E32E` |
| `lib/screens/source_practice_screen.dart` | `B86DC8AE8C7AA37993A40E9701E5EF5E6D82A9007F3BDCC765BEEF88B5F75740` |
| `test/screens/associative_reading_session_screen_test.dart` | `7D988A29B3EE1CEFDC73F8F158CA35D4EBF72E5A7F639301EFD4D75E8614B526` |
| `test/screens/srs_flashcards_screen_test.dart` | `02B01E7BD696B859A423EB294C124EC027D5CE51E7992813F2EFD41C09389636` |
| `test/screens/source_practice_screen_test.dart` | `3C05A464122D609B0B9B03F8BC1EA9959FD33E7990A9A50E297840D93C65C3D0` |

## Remaining boundary

- Aggregate summary does not persist wrong-word identity. Result recovery after process death is therefore unsupported and belongs to the separate provenance/history contract.
- Physical-device and repository-wide regression run at the next integration checkpoint after remaining UI cards settle.
