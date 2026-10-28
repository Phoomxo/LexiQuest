# Remaining systems: canonical first-session linkage

Date 2026-10-29. Source `1128b9e6` is pushed on
`codex/remaining-system-readiness` from
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`.
The two unrelated critique files remain untouched.

Schema v15 adds one 15-field local opportunity table, bringing the schema to
34 tables. It links a stored Presented event to the first accepted canonical
session. UUID v7 occurrence milliseconds, the explicit stored millisecond and
the frozen EventsV2 epoch-seconds mapping agree. The event uses exactly the
approved four-field payload and 22-field envelope. It never enters learning,
reward or outbox projections. Other neutral events are not fabricated.

The optional learning observer from `af8d87fc` validates the persisted tuple and
database identity. It runs only for a genuinely new start, with required-new
research savepoints inside the canonical transaction. Research denial preserves
ordinary learning and rewards. Start retries cannot backfill an earlier denied
start; completion retries retain the original end. The first active or abandoned
index remains the index. Earlier/tied unlinked or ambiguous candidates deny
timing instead of selecting a later success.

Independent review reproduced two cases where a partial synced-evidence marker
was incorrectly ignored. Only the exact known marker pair is now excluded.
Five draft checks also incorrectly assumed all outbox rows should be absent
after ordinary completion. Their explicit exception now validates exactly one
canonical achievement/outbox row, including identity and time; default remains
zero and extra/research operations are still forbidden. Production reward code
was not changed.

| Current-source check | Result |
| --- | --- |
| Canonical learning hook | 21 focused; 351 learning/progress/reward/sync/bootstrap passed |
| Populated migration/database | 39 passed; every old v14 table snapshot retained |
| Opportunity repository | 43 passed, including both negative marker cases |
| Populated owner/export/deletion lifecycle | 99 passed |
| Combined integration | 1152 passed |
| Full Flutter | 2594 passed |
| Analysis | No issues |
| CLI contract scripts | 23/23 passed |
| Normal debug APK | Passed, `lib/main.dart`, build ID `1128b9e6` |

Independent repository and storage/lifecycle reviewers accepted the actual
source. Export/purge checks preserve all 15 opportunity, 22 event and four
payload fields for the retained owner. Owner-changing merge rejects research
facts and even known orphan neutral research events before business writes.
Opportunity deletion precedes every referenced owner table. Partial uniqueness
pins one index per owner/run on fresh creation and populated upgrade.

Normal Drift generation adds 2540 and removes 43 lines under histogram diff;
generated mappings were not hand edited. The v14 fixture is a normal pre-change
export. Normal v15 DDL was exported before further migration work.

Logs and `opportunity-normal-debug-apk-manifest.json` are under
`D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`.
The debug `1.0.0+1` APK at
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest\build\app\outputs\flutter-apk\app-debug.apk`
is 251468473 bytes, SHA-256
`4ffad72f18b9e64d57608844dbb523de8746fccc58757fc1d85a2579d7db8b9e`.
It was not installed or published. Source/lib/test/Android trees are pinned in
the manifest. Later builds replace that path; the hash identifies this artifact.
The existing future-KGP warning remains.

This completes the local observer/linkage unit. Actual visible presentation at
commit time, exact same-quiz resume, pending-answer recovery, study-bound consent
UI, both presentations, remaining neutral events, assessment and upload still
need implementation. There is no production Research composition. The matrix
remains 10 connected, 19 partial and 15 missing runtime capabilities, not a
production-readiness score. Instrument validity, ethics, authority, physical
UAT, model quality and rollout remain separate.

The next grounded card proposes four columns on existing learning sessions for
an immutable accepted quiz plan and versioned checkpoint; v16 is not reserved by
this checkpoint. A separate form draft remains outside the source. Enrollment
and upload stay default-off. Automatic approval previously rejected the owned
emulator/preview stop/delete command with `blocked by policy`; no retry occurred.
Retained paths and native limitations remain recorded in wave 3.
