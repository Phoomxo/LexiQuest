# PM6 measured-admission adversarial tests

Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`. Test-only bounded task; source unchanged by this helper. Eight new test instances added and frozen; ownership released to main implementer for sole formatting and serialized validation. No helper-owned process remains

## Changes

`test/features/learning/pair_matching/pair_matching_atomic_start_test.dart`:

- `measured revision2 BEFORE insert failure rolls back both receipts`
- `measured revision2 AFTER insert failure rolls back both receipts`
- `measured committed write with lost caller acknowledgement retries exact bytes gate-off`
- `measured failure immediately before transaction commit rolls back durable admission`
- `generic append cannot forge measured admission at any revision or occurrence`
- `persisted measured admission with changed occurrence fails strict purpose reader`
- `measured coverage cannot be initialized a second time after durable null`

SQL triggers fail before/after real revision2 INSERT. A QueryInterceptor inspects both receipt rows immediately before real transaction commit and throws once, then proves rollback and successful fresh retry. The lost-ACK test deliberately loses acknowledgement at the caller boundary after the real adapter transaction completed; it does not claim process termination or storage-driver ACK simulation. Full event-row equality checks preserve IDs, payloads and occurrence bytes on exact retry/forged-write refusal. Existing old-initial→measured regression remains and generic-forgery regression also checks old-path retry cannot retrofit

`test/features/learning/pair_matching/pair_matching_checkpoint_codec_test.dart`:

- `measured admission exception accepts only virgin initial to codec4 zero`

Checks authorized zero control, default-denied admission, nonvirgin prior/next engine, nonzero initial total, wrong codec, historical existing timer, and sticky lost coverage

## Validation status

- Helper ran no Flutter/Dart/tests/analyzer/build/formatter. No invented RED claim
- Focused `git diff --check -- <two owned test paths>` returned exit0, with Git LF→CRLF advisory warnings only; no whitespace-error output
- Main requested sole serialized command: `flutter test test/features/learning/pair_matching/pair_matching_atomic_start_test.dart test/features/learning/pair_matching/pair_matching_checkpoint_codec_test.dart --reporter expanded`
- Actual result received from sole tool owner `/root/pm6_implementation`: **GREEN28 (8 new + 20 existing)** using `flutter test --no-pub test/features/learning/pair_matching/pair_matching_atomic_start_test.dart test/features/learning/pair_matching/pair_matching_checkpoint_codec_test.dart --reporter expanded`; evidence `.superpowers/sdd/pm6-admission-adversarial.log`. No corrections required. Final formatting deferred to main. This is not PM6 phase acceptance

No source/index/HEAD mutation or scanner. Read current tests, relevant admission implementation, prior integration brief admission sections, and installed Drift QueryInterceptor API for the precise commit interception signature

All test/report ownership released to root/main after this result update. No running processes or unresolved helper work
