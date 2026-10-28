# Visible exposure and canonical Mission facts

Verified on 2026-10-29 in
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`, branch
`codex/remaining-system-readiness`, after `8e2ce80e`. Executable schema remains
v16/34 tables. This is a storage/observer component; no production screen calls
the exposure method yet.

`recordPresented` now requires a synchronous visibility predicate. The existing
active-run boundary evaluates it after fresh consent, signed participant
authorization and the final trusted clock read. There is no authority await
after that validation. Hidden, stale-generation or throwing predicates roll back
the new event and opportunity update; a hidden replay creates no new fact.

The accepted-session observer requires the actual saved configured quiz plan,
its independent content hash, supported meaning-quiz mode and initial checkpoint
before binding the first index. Started and Completed use exact five-field
payloads and the frozen 22-field envelope. Their occurrence times come from
canonical session start/original completion, while recorded time is the first
trusted capture time. UUIDv7 preserves occurrence milliseconds across the event
table's seconds mapping. Replay retains original identity and timestamps.

An orphan event, partial projection, legacy/non-quiz first session or denied
first acceptance cannot be adopted or replaced by a later session. Completion
requires the terminal checkpoint and valid Started fact. Required-new research
savepoints preserve ordinary learning, SRS, rewards, achievements and outbox
effects when optional capture fails. The test harness now uses real configured
quizzes for positive cases and retains explicit ordinary-effect assertions.

| Current-source check | Result |
| --- | --- |
| Opportunity/Mission repository | 65 passed, including 22 new cases |
| Configured writer deletion fence | 1 focused case passed |
| Research, learning, owners, deletion, export, consent, sync, progress, rewards, motivation, Quest, runtime and database integration | 1380 passed |
| Analysis | No issues |
| Format/diff | Passed |
| Independent current-source review | Accepted; no production exposure caller claimed |

The first executable run passed 64 and failed one new test because it expected
`StateError` for the real deletion coordinator's typed denial. The test now
requires `AccountDeletionException` with `unavailable`, retaining its zero-write
assertions. No production behavior or older assertion was weakened. Five style
diagnostics were corrected with braces. The final integration sees those edits.

Logs, the initial compile RED and five-file SHA-256 source manifest are under
`D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`, prefixed
`study-mission-`. The old yielded process handle expired; its complete 65-pass
log was reconciled, then the new 1380-pass run completed with exit 0.

Latest full-suite/APK evidence remains `4a4cbdd8` (2728 tests and the wave 8
artifact). No new full-suite, native UAT, enrollment or upload claim is made.
Next: compose the optional owner-bound StudyRuntime, explicit host route and
both supplied presentations; exercise real visibility and exact index recovery.
Assessment, PresentationChanged and upload remain separate engineering work.
Approved external artifacts, rollout authority and physical-device evidence
remain separate dependencies. The two existing critique files are untouched.

Automatic approval previously rejected stopping/removing the owned disposable
emulator and preview artifacts with `blocked by policy`; no retry was made.
