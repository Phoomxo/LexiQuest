# Remaining systems: structured motivation measurement storage

Date 2026-10-29. Source `90a81306` is pushed on
`codex/remaining-system-readiness` from
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`.
The two unrelated critique files remain untouched.

Schema v14 adds a 30-field measurement run and nine-field coded response table,
bringing the schema to 33 tables. One run spans baseline and post. Full supplied
instrument/checksum, consent, assignment, protocol, scoring and build/content
pins remain immutable. Ordinal, score and timestamps come from checked sources;
there is no free-text answer or caller-provided completion claim. Partial scores
remain null. Exact retries retain the original IDs, revisions and times. A new
permit cannot silently create another cycle for the same assignment/protocol.

Writes use the existing R2 actual receipt and concrete owner transaction. Final
checks include real signatures, current authority, consent, full-precision time
and timing facts after all waits. Unavailable timing differs from proven no
exposure. Baseline 24-hour eligibility and post 30-minute capture use distinct
rules. Active or abandoned index facts deny post capture. The required timing
port must supply the immutable first index; its durable implementation is next.

Canonical consent withdrawal commits independently using its ordinary consent
clock. Trusted research time still gates research bookkeeping; its unavailability
or a later SQL failure cannot restore consent. Independent review reproduced
three future-time read/replay defects. A shared last-clock predicate now keeps
historical rows but denies their eligibility or mutation when dates are future.
A fourth case verifies that this rejection cannot undo consent withdrawal.

| Current-source check | Result |
| --- | --- |
| Populated migration/database | 38 passed; all 31 old tables and deletion intent retained |
| Signed measurement repository | 46 passed |
| Populated owner/export/deletion lifecycle | 77 passed |
| Combined integration, including bootstrap and consent registry | 794 passed |
| Full Flutter | 2507 passed |
| Analysis | No issues |
| CLI contract scripts | 23/23 passed |
| Normal debug APK | Passed, target `lib/main.dart`, build ID `90a81306` |

Independent storage, lifecycle and repository reviews accepted the final source.
The initial integration command passed 735 cases but used an invalid bootstrap
path; the corrected expanded command passed 794. Initial failure evidence is
retained. A synchronous invalid-input test was corrected to observe the actual
throw without changing validation or its expected denial reason.

The normal Drift generator changed only the tracked database generated source:
histogram diff adds 4571 lines and removes 25 for the new tables/FK mappings.
Historical v10/v11/v12 fixtures remain unchanged. The v13 fixture is a normal
pre-change Drift export. The v14 DDL was exported before the next migration.

Logs and `measurement-normal-debug-apk-manifest.json` are under
`D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`.
The normal debug `1.0.0+1` APK at
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest\build\app\outputs\flutter-apk\app-debug.apk`
is 251408109 bytes, SHA-256
`07910ea06f731683b5b8719a06f53e551ca45cea7b7b51d1481927a707ee201e`.
It was not installed or published. The manifest pins source/lib/test/Android
trees; later builds replace this path. The existing future-KGP warning remains.

This completes the local storage unit, not Research engineering. The matrix
remains 10 connected, 19 partial and 15 missing runtime capabilities. Canonical
exposure/session linkage, visible capture UI, both presentations, learning-outcome
assessment, upload and production authority remain. No instrument validity,
ethics, physical UAT, model quality or rollout approval is inferred.

Next v15 reserves one local opportunity table. The optional canonical learning
observer must preserve ordinary learning on research failure and never backfill
a denied first start. Drafts were prepared outside the frozen source. Runtime
enrollment/upload stays default-off. The emulator/preview cleanup command remains
rejected by automatic approval with `blocked by policy`; no retry occurred.
Its retained paths and native accessibility limits remain recorded in wave 3.
