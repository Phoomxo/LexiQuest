# Remaining systems: motion and owner coordination

Date 2026-10-29. Active worktree is
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`, branch
`codex/remaining-system-readiness`. Application source `26952596` is pushed to
GitHub. The two pre-existing untracked critique documents remain unrelated WIP.

## Implemented and reviewed

`436c17aa` returns the exact checked operation permit and final UTC verification
time. It preserves existing boolean callers and does not turn a completed
check into continuing authority. Focused operation/export checks pass 101 tests.

`0eedc90b` connects saved theme/Reduced Motion preferences, live OS accessibility
changes and significant route, card, chat and sheet motion. Focused checks pass
151 plus two sheet tests. The controls remain usable at 200% text scale in
widget tests. Independent source review accepted the change.

`26952596` persists deletion intent in the existing SQLite runtime flags and
checks it in owner upgrade, logout and rollback transactions. Nonce-based CAS
keeps stale actors from advancing or clearing another attempt. Preparing intent
precedes export; pending intent commits before the recovery-journal attempt.
Cloud/local proofs survive acknowledgement loss. Legacy journal adoption checks
owner binding and actual local purge proof before completing recovery.

Independent review found two foreground/background races after the first green
run. Operation-scoped journal keys now prevent a late actor from deleting a new
operation's recovery payload. Background recovery retains a live preparation;
only an explicit new deletion request can replace it through CAS. Regression
tests cover separate preference caches and commit-before-acknowledgement order.
The final focused integration passes 186 tests; independent re-review accepted
both fixes. Ordinary learning remains available and new deletion stays default-off.

## Frozen application evidence

| Check | Result |
| --- | --- |
| Full Flutter suite, concurrency 2 | 2308 passed on `26952596` |
| Flutter analysis | No issues |
| Android normal debug build | Passed, target `lib/main.dart`, build ID `26952596` |
| CLI contracts | 23/23 scripts pass after correcting and rerunning the MiroFish false positive |

The MiroFish gate misread this commit's 13-digit hash prefix as a national ID.
Its text scan now projects only known, correctly shaped fingerprint properties;
original schema, pin and provenance validators still receive unchanged objects.
Free-text identifiers, including escaped property-looking text, remain rejected.
The focused contract passes 45 assertions in both PowerShell 7 and Windows
PowerShell 5.1. This tooling change does not alter the application snapshot above.

Backend, rules and workflow inputs are unchanged from `efff26a6`. Their earlier
AI 186, Voice 64, LM 140, Firestore 45, Auth 3 and Hosting 15 results are retained
as earlier evidence, not relabelled as new runs.

The normal debug APK is
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest\build\app\outputs\flutter-apk\app-debug.apk`.
It is version `1.0.0+1`, 251229699 bytes, SHA-256
`1c969e30d07439c65887530d51b7e4d214c358fb7192c640f2f92424f72c5534`.
It was not installed or published. The manifest records the lib/test/Android
Git trees in `wave3-normal-debug-apk-manifest.json` under the maintenance log root.

## Native limits and retained temporary files

A network-free fixture rendered the actual settings screen on Android at
360x800 and 100% text scale. Independent visual review found readable Thai,
no clipping/overlap and a 48dp Save button. White status-bar icons had poor
contrast on the light fixture; the theme already requests dark icons, so the
cause is unresolved. This fixture is not full MyApp verification.

The disposable emulator then reported System UI ANR and went offline. Dark/200%
native layout and hardware gestures remain unverified. Automatic approval
rejected the combined stop/delete command with `blocked by policy`; no retry
or cleanup was performed. Its VM directory and preview APK remain at
`D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems\motion-native-a9595bdb`
and `visual-checks\reduced-motion-preview.apk`. The visual manifest records the
scope; the session used launcher PID 62568 and QEMU PID 60240. Their state after
the denied command is unconfirmed. No physical phone or real research data was used.

## Continuing work

The [runtime matrix](2026-10-28-feature-readiness-matrix.md) now records 10
connected, 19 partial and 15 missing capabilities. These are source coverage
states, not production certification. Research remains default-off.

The [ledger](../database/schema_ledger.md) reserves v12 for one immutable local
assignment table. The verified application above is still v11/29 tables.
The v11 DDL was exported with the normal Drift tool before migration changes.
Next implement strict assignment admission, populated-v11 migration and complete
merge/export/deletion coverage. Draft workers write outside the repository until
the root releases the frozen snapshot. Production authority adapters, enrollment,
physical UAT, model quality and rollout permission remain separate dependencies.
