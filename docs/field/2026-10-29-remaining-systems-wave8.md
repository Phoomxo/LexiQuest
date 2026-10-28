# Exact quiz recovery checkpoint

Application source `4a4cbdd88fe027427d00d4bb3be14b39d9b091ee`, pushed to
`codex/remaining-system-readiness`, in
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`.
Executable schema is v16/34 tables. The two pre-existing untracked critique
documents remain untouched; the primary checkout still has separate user work.

The three Meaning Quiz entries now persist the actual ordered questions,
content revisions/checksums, options and supported configuration before the
canonical accepted observer runs. The plan has its own content hash. A versioned
checkpoint retains sticky assistance, the exact pending answer and original
terminal time. Canonical answer/finish and checkpoint acknowledgement commit
together, using the existing SRS, reward and sync authorities. Revision CAS
rejects stale competing input. Restored unanswered items have unknown latency;
downtime is not counted as response time.

History opens the exact owner/session for an active stored quiz. Legacy,
synced, corrupt, changed-content and changed-owner inputs cannot generate a
replacement deck. Ordinary owner rehome preserves immutable bytes; resume still
checks original content and refuses old-owner pending commands. Personal export
retains the complete recovery fields and owner purge removes them. No plan text
or new operation type is added to sync.

Shadowing, source Flashcards and source pronunciation previously reused quiz
starters. They now use explicit canonical starters with their actual activity
types. Their historical rows remain unchanged. Quest/Streak tests use configured
answer transitions and retain their counter assertions.

Actual widget failures exposed optional haptics keeping Next disabled after
the answer committed, and an unhandled typed owner rejection. Optional caught
haptics no longer hold saving state; owner changes hide private content without
starting another round. A delayed-haptic behavioral test proves navigation can
finish before the device acknowledges feedback. Completion callback delivery
occurs after the canonical terminal checkpoint and before Score; an optional
study offer cannot undo learning or duplicate finish.

| Current-source check | Result |
| --- | --- |
| Database/historical migrations | 42 passed, including populated v15 snapshots of all 34 tables and deletion intent |
| Plan/repository/use cases | 86 passed |
| Storage/export/owner lifecycle | 47 passed, including four complete plan/checkpoint cases |
| Quiz/history/Quest/Streak UI integration | 65 passed |
| Other learning modes and bootstrap | 191 passed |
| Corrected account/owner fixtures | 23 passed |
| Full Flutter | 2728 passed |
| Analysis | No issues |
| CLI contract scripts | 23/23 passed |
| Normal Android debug APK | Passed, `lib/main.dart`, build ID `4a4cbdd8` |

The first full run passed 2709 and failed 19 because four old fixture INSERTs
supplied positional values for the original 11 session columns. They now name
those same columns, preserving every value and assertion; new recovery columns
retain null/null/0/null defaults. The focused owner checks and a complete second
full run passed. Independent readers accepted storage, domain, core and UI.
Final format/diff checks pass. No test was removed or skipped for this change.

The normal debug `1.0.0+1` APK at
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest\build\app\outputs\flutter-apk\app-debug.apk`
is 251564663 bytes, SHA-256
`6ead50655993a29cb3c339b964cfa5bf1256b265edb7bca2e766ff2897420bf6`.
It was not installed or published. The source/lib/test/Android trees and logs
are pinned in `configured-quiz-normal-debug-apk-manifest.json` under
`D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`.
Later builds replace this path; the hash identifies this artifact. Build output
reports future KGP migration and SDK XML 3/4 tool-version warnings. Backend and
cloud-policy sources are unchanged; their prior CPU/rules evidence was retained,
not rerun for this Flutter-only unit.

This completes the exact ordinary quiz recovery prerequisite. It also includes
the earlier guarded form/shared dark-contrast component in the full suite and
normal APK. The study host, both actual presentations, remaining neutral events,
assessment and upload are still engineering work. Research remains default-off;
missing authority cannot block ordinary learning. Coverage remains 10 connected,
19 partial and 15 missing capabilities, not a production score. Physical UAT,
authentic research authority and rollout remain separate.

Next executable cards are outside source: eight consent-version/caller files
with 22 unexecuted new cases, and five visibility/Mission-event files with 65
unexecuted cases. Their independent source reviews do not replace root testing.
Integrate the consent card first, then verify the Mission card before composing
the visible host. No v17 reservation or production enrollment is authorized.

Automatic approval previously rejected stopping/deleting the owned emulator VM
and preview APK with `blocked by policy`. No retry occurred. Their retained
scope and native-testing limitations remain recorded in wave 3.
