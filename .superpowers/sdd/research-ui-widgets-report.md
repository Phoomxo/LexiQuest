# Research UI widgets — R5 bounded handoff

Worktree: `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`
Branch: `feature/adventure-research`; base HEAD `6968ce97ff9b383e244b17b77cf0ed0f61eaaf3d`.

Status: **Bounded widget implementation complete: 52/52 tests passed**, focused
analyzer **No issues found**, format check **0 changed** on final source.
Exclusive Flutter/Dart slot explicitly **RELEASED to MAIN** at approximately
2026-09-05 14:20 Asia/Bangkok. MAIN was notified through task messaging.
No UI-owned process remains. The four Dart files are frozen for integration.
This does not claim completion of all Research engineering or production rollout.

## Scope and design

Only this report and the following four NEW files are owned:

- `lib/features/research/presentation/motivation_measurement_form.dart`
- `lib/features/research/presentation/research_participation_panel.dart`
- `test/features/research/motivation_measurement_form_test.dart`
- `test/features/research/research_participation_panel_test.dart`

Read active AGENTS, approved implementation plan R5, current research domain
contracts, historical checkpoint, UI spec sections 8.10–8.13, 11 and 13.8–13.9,
and the normative research participation SVG companion. The supplied request
narrows guardian/assent interaction to importing opaque externally signed JSON;
no local consent/assent/age checkbox, receipt issuance or database behavior.

Form: one current unanswered item from the immutable run instrument, coded
radio selection saves immediately, await completion before advancing, recorded
items are immutable. Explicit Finish delegates to `onComplete`; baseline does
not close the paired study run. Skip and Withdraw remain reachable, with writes
serialized. Failure/retry messages contain no exception text or identifiers.

Panel: caller supplies already validated permit or null. Adult/minor enum only;
guardian permission and learner assent have independent external verification
statuses. Null never invents approval. Import passes the unchanged opaque JSON
object to the callback; UTF-8 size limit is 16,384 bytes. Explicit Paste reads
the clipboard only after the user's action. A read-only obscured field preserves
the signed document's newlines; oversized input is rejected before retaining it
in the controller. Import failure retains valid input for retry; success,
disposal and permit-context replacement clear it. This removes owned references,
not a claim of zeroizing immutable Dart strings or caller-owned callback data.
Continue learning/Skip remain independent of pending research writes. Successful
withdrawal stays latched until the caller supplies a new permit identity/revision.
No PII/signature/reference rendering or logging, and no local authority creation.

Both: Thai/English, single scrollable reflow, 48px targets, semantic headings,
radio group/labels, live failure status and keyboard focus. Host owns prompt
entry, parent focus restoration, validation and research lifecycle decisions.

## Test slot and verification

TDD evidence, with only the two owned widget suites executed:

| Stage | Observed result |
| --- | --- |
| Tests and API-only scaffolds | Written before production behavior, no Flutter/Dart before explicit grant |
| Initial test-helper correction | Removed `await` from void-returning `TestTextInput.hide()`; compiler failure was not treated as valid RED |
| RED against empty scaffolds | 0 passed / 49 failed, exit 1; missing widget behavior |
| First implementation | 41 passed / 8 failed, exit 1; slot returned to MAIN |
| Corrections during MAIN/schema slots | No Flutter/Dart invoked; preserved JSON newlines with explicit paste, corrected rendered-text/merged-semantics assertions and test helper lifetime |
| Second explicit slot, added race RED | 49 passed / 3 failed, exit 1; same-run rebuild retry, failed Skip answer lock, stale permit after withdrawal |
| Race fixes GREEN | 52 passed / 0 failed, exit 0 |
| Final source after lint cleanup | 52 passed / 0 failed, exit 0; 21 form cases + 31 panel cases |

Exact final commands (all in this worktree, executed serially):

```powershell
dart format --output=none --set-exit-if-changed lib/features/research/presentation/motivation_measurement_form.dart lib/features/research/presentation/research_participation_panel.dart test/features/research/motivation_measurement_form_test.dart test/features/research/research_participation_panel_test.dart
dart analyze lib/features/research/presentation/motivation_measurement_form.dart lib/features/research/presentation/research_participation_panel.dart test/features/research/motivation_measurement_form_test.dart test/features/research/research_participation_panel_test.dart
flutter test --no-pub test/features/research/motivation_measurement_form_test.dart test/features/research/research_participation_panel_test.dart --reporter expanded
```

Output: `Formatted 4 files (0 changed)`; `No issues found!`;
`00:05 +52: All tests passed!`, final process exit 0. Earlier analyzer info
messages were corrected (flow-control braces and modern `flagsCollection`).
New-file `git diff --no-index --check -- /dev/null <file>` was clean for each
of the four Dart files; only repository LF-to-CRLF informational warnings.
No tests were deleted, skipped or assertions weakened to obtain GREEN.

Verified behaviors include Thai/English copy; all 32 baseline items with long
choice labels at 320px/200% text; both panel locales at 320px/200%; 48px action
targets; semantic headings, radio checked/group state, keyboard escape actions
and live failure status; exact callback codes and serialized submission;
recorded answer immutability; incomplete score remaining absent; baseline
completion delegated without closing the run; explicit retry of the same answer;
late callback disposal/replacement; adult/minor independent receipt statuses;
empty/unconfigured continuation without writes; unchanged pasted JSON, exact
16 KiB acceptance, oversized multibyte rejection, masked rendered/semantic values
and disposal cleanup.

Focused analyzer/format covered only the four files above. No main opportunity,
motivation service, document codec, Host/runtime/bootstrap or sync tests were
run. No repository-wide analysis, build, dependency resolution or code generation.

No Flutter/Dart process was started before grant. No commits, tasks, Figma,
scans, deployment or edits to any other file by this UI worker.

## Frozen source fingerprints (SHA-256)

- Form: `3372F005D6499CD0D5D18C70A0FCB1B23664D6D90E33EB05E4289794183EB188`
- Panel: `C41148750444180BE7ED7F8F5E3C493599F8DF73DCBAEE26B3DECDFD3F01E239`
- Form tests: `CB2593B46E8B8FEE6BC96777172693B285B9E8F5EF5940307A944C6E10DF48B9`
- Panel tests: `9B0A4453564C1D99EBC8FAFC825D4A0A7F8E3C304706503FF826DAB2557A029C`

## MAIN integration handoff

Constructor field names and callback types match the supplied brief exactly;
only the optional normal Flutter `key` is additional. No application, Host,
runtime, fixture or existing file was edited by this UI worker. The report is
under the repository's ignored `.superpowers` directory as requested.

The importer must perform actual signature/receipt/owner/expiry/revision checks;
the panel's JSON check is only bounded syntax. Host must pass null for unavailable
authority, remove/replace the form when authority changes, decide baseline vs
post lifecycle completion, and restore focus to the invoking learning control.
Awaited writes are not timed out locally because a timeout cannot cancel a
potentially committed mutation. Callback implementation owns bounded operation
completion and idempotent persistence.

No unresolved failures remain in these two widget suites. Remaining validation
belongs to MAIN: real Host/runtime integration, end-to-end lifecycle and sync,
physical TalkBack/Switch Access/focus-return verification and release checks.
No device/UAT, enrollment approval or research efficacy is claimed.

Next executable step: MAIN uses the released slot for its next integration
batch (or assigns it to the queued sync worker). No further UI work is running.
