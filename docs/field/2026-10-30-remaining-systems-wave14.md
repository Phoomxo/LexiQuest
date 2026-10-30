# Wave14: canonical Quest identity and atomic progress

2026-10-30. Application source `2702e0080937147e396b79cc290b0d1fb5deadf0`,
branch `codex/remaining-system-readiness`, existing cycle12-release worktree.
Full Flutter3700, analysis0, CLI23, offline backend390/one existing opt-in skip
and a normal debug APK pass on the unchanged source. This repairs the optional
Quest boundary; it does not activate the Quest product or certify production.

## Resulting behavior

The command adapter uses the actual persisted attempt ID as eventId and
`answer-attempt:<id>` as its stable key. Both real optional learning hooks pass
command.id. One answer keeps one identity across callbacks/processes, while two
answers in the same millisecond remain distinct. Legacy adapt(V1), envelope
fields/payload, inserted-only dispatch, projection eligibility and separate
optional error isolation remain. No nonparticipant events_v2 row is created.

Domain progress deduplicates each source per objective, rejects foreign owner/
actor, pre-assignment and terminal advancement, and cannot complete an empty or
incomplete quest. Completed replay retains its original time. Source/progress/
completion lists and authored filters/objectives/tags are copied and exposed
read-only. Actual const callers migrate; existing assertions remain.

One repository operation resolves the actual owned answer/session, checks stored
ordinary eligibility and canonical event claims, and validates every existing
objective source against its owned answer, objective and time window. Unknown
legacy counter IDs, malformed progress and missing rows fail closed without
reset/backfill. Supplied/stored/instance catalog pins must agree. Same-version
catalog writes are exact no-ops; changed content and downgrade are denied.

Progress and first completion share one top-level current-owner transaction.
The concrete owner coordinator must use the same database; inherited outer
transactions are rejected. Final source/session, definition and instance pins,
owner/deletion fence and fresh clock/window checks precede durable commit.
Expiry/abandonment uses active-only owner CAS and cannot overwrite completion.
Returned notifications follow commit. Public split saveProgress/markCompleted
ports and the unused command counter helper are removed after caller migration.

The first completion event, SQL row and subsequent read now use one persisted
millisecond timestamp; validation clocks retain full precision. Optional Quest
failure leaves the already-committed answer/SRS/XP/coins intact. Research,
Assessment and current declared assisted/recreational evidence gain no new
Quest eligibility. Existing Dictation/Cloze and remote SRS behavior remain.

## Evidence and review

Evidence root: `D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`.

| Evidence | Verified result |
| --- | --- |
| `quest-domain-red.log` |19 actual failures and2 controls before domain repair |
| `quest-catalog-aliasing-red.log` |4 caller-aliasing failures with21 existing controls; corrected by structural copies |
| `quest-canonical-adapter-behavior-red.log` |9 actual identity failures with3 unchanged payload controls |
| `quest-canonical-atomic-api-red.log` | Required constructor/atomic port absent before promotion |
| `quest-completion-precision-red.log` | Actual returned.123234 versus SQL.123 mismatch before correction |
| `quest-integration-first-run.log` |138 actual Quest/events/Assessment checks pass after corrections |
| `quest-learning-projection-regression.log` |1121 wider learning/Quest/events/reward/sync/progress/Assessment/native UI checks pass |
| `quest-integration-final-analysis.log` |0 issues; two initial style findings corrected before the full suite |
| `wave14-full-flutter-final.log` |3700 pass,11m12s, current frozen source |
| `wave14-cli-manifest.json` / `wave14-root-validation-review.json` |23/23 actual Windows PowerShell5.1 fixture/config suites; root read every CLI log and verified hashes |
| `wave14-backend-manifest.json` / `wave14-validation-review.json` | AI186 + Voice64 + LM140 =390 pass, one existing opt-in Firebase/OmniVoice skip; worker read all logs and391 JUnit cases, root independently parsed results |
| `wave14-source-verification-final.json` |0/683 Dart,0/54 CLI and0/92 backend input mismatches through checks/build; no untracked Dart |
| `wave14-normal-debug-build.log` | Normal debug build passes,118.4s, process-local heap3G/workers2/daemonfalse; previous environment restored |

Independent adapter and repository reviews are accepted. The catalog review
found a real aliasing gap across startQuest's owner await; four REDs preceded
the fix. The Assessment fixture previously assigned a quest after its ordinary
answers; its clock now assigns at-60s before the same-20s/-10s answers, preserving
the expected count1 and all isolation assertions. Two missed const variable
declarations caused initial test-load failures and were migrated without changing
values/assertions. No test was skipped or weakened to obtain green.

Backend verification uses existing Python3.11.15/pytest9.1.1 and actual current
C imports, with no new installs/downloads/GPU/live credentials. The113 audited
socket operations are internal standard-library Windows socketpairs, with0
denied external calls. The real Firebase/OmniVoice E2E remains explicitly opt-in.
Existing Google-Python and Starlette/httpx notices remain. CLI fixtures are not
live scanner/deployment runs. Unchanged policy sources retain earlier45/3/15
evidence; this is not a fresh live policy claim.

## Current debug artifact

`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest\build\app\outputs\flutter-apk\app-debug.apk`

- Normal `lib/main.dart`, debug `1.0.0+1`, build ID `2702e008`; not installed/published.
- Bytes251966049; SHA256 `d893b68bd77461958fe521f37f44cad5d6f0321f109c2429e642229722bcf284`.
- Actual compiled ZIP kernel identity verified at `assets/flutter_assets/kernel_blob.bin`.
- lib tree `9c2473ed7d20359c4a84ddc55bb8887645e7833a`;
  test tree `f496f648440873f80d5e8e881b52bfd51e8276ed`;
  Android tree `c9abd4fd1187a4af13b306f1f077127f96884bac`.
- APK manifest SHA256 `cd252f87f198e232c24cd2b788825e2ea4343e08480e7ce1d9cb28707c3f3657`;
  frozen Dart manifest `d3d3d4149b06d32a3b379d6029c786990091f0742251a8988effa39ab20542a0`.
- Final source proof SHA256 `7c0e1c871d26f180d9d1d65c1153448143372331c92764df51075a1f3d4a9cd4`.

The same output path replaces wave13's debug binary; no second full APK copy is
created. Existing future-KGP and SDK XML3/4 build warnings remain.

## Limits and next work

Schema stays v18/35, v19+ unreserved; the frozen8/44 catalog and EvidenceContext/
EventEnvelopeV2 fields remain unchanged. Coverage stays11 connected/18 partial/
15 missing. f29 stays partial: recurring periods, delivery recovery, grants/
freeze, catalog/bootstrap activation and real Quest/Today UI remain separate.
The existing optional shadow remains a dry run; this checkpoint does not certify
its payout or period metadata. No production reward authority is enabled.

Continue [owned Word Scramble](../superpowers/plans/2026-10-30-word-scramble-integration.md),
then Bookmark/saved review under the existing feature sequence. Their D drafts
are excluded from this source/APK. Research remains default-off; production
authority, real enrollment/upload, content efficacy and physical UAT are separate.
The primary checkout's unique WIP remains preserved.

Previously rejected emulator/preview and four feedback-PNG cleanup remain
rejected by automatic approval (`blocked by policy`), retained and not retried.
No new reclaimed-space claim includes them; no extra cleanup was performed.
