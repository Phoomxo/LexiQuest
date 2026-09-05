# Pair Matching engineering status

Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`.
Branch: `codex/pair-matching-pm0-pm8`.
Base: `ca123dddc1349acc4ed67bdd8f5476b02165307c`, directly after verified Research implementation `ed89efaf32a1090505a84d4b55b2cc60003068b3`.
Approved scope: Checkpoint 7 / PM0–PM8 in the Adventure implementation plan, design B — Playful Quest.

## Current acceptance

| Topic | Engineering status | Current evidence |
| --- | --- | --- |
| PM0 — f10 characterization | Complete | Local commit `a32e25d5`; 114/114 focused checks; independent spec and quality review approved |
| PM1 — immutable source plan / atomic start | Complete | Local commit `cf94aecf`; independent review approved; focused evidence below |
| PM2 — reducer / evidence roles | Complete | Local commit `23c6b27e`; independent final review approved; evidence below |
| PM3 — delayed repair / Review | Complete | Local commit `bccb7735`; final independent spec/quality approved; evidence below |
| PM4 — active timer / checkpoint / restart | In progress | Not yet accepted |
| PM5 — stars / History / Practice Replay | Pending | Not verified |
| PM6 — accessible Standard UI | Pending | Not verified |
| PM7 — Adventure parity / measurement | Pending | Not verified |
| PM8 — compatibility / G4P package | Pending | Not verified |

PM0 changed tests and documentation only. Its evidence covers TC-PMT-001, matching adapter 60 checks, screen 7, production navigation 25, architecture boundary 2, and exact 8/44 catalog 20. The navigation suite emitted a pre-existing Drift multiple-database debug warning; it is recorded, not described as pristine output. Details: [PM0 characterization](2026-09-05-pair-matching-pm0-characterization.md).

PM1 implements exact immutable source plans, a real atomic pinned Learning start, and optional density metadata in the existing matching configuration. It passed an impacted regression of 241 checks, then 58 Pair/repository checks after the final start retry correction. Review follow-up passed 49 Pair/policy/store checks and 2 owner-upgrade compatibility checks; the density file's 3 checks passed again after a test-only lint fix. Focused analysis and final staged whitespace checks passed. Tests include actual file-backed database reopen, lost acknowledgement, transactional rollback, active-owner changes, gate-off reconciliation, same-revision checksum rejection, Unicode label collisions and legacy preference compatibility. Independent spec/quality review accepted the final change with no remaining finding. TC-PMT-002–010 and source collision 012 have internal API evidence; gameplay evidence attachment and UI acceptance remain later phases.

PM2 delivers a pure reducer and real canonical evidence coordinator, strict v6 codec, owner/session/operation fences and exact pending/answer/clear recovery. Its review found a permitted Unicode plan could exceed 64 KiB later; the corrected compact codec and byte reservation reject unsafe admission before mutation while preserving required completion. Actual Drift tests cover Unicode/long IDs, optional capacity denial followed by completion, lost acknowledgements, file reopen, owner changes at SQL boundaries, generic API admission bypass and capture/freeze failures. Follow-up impacted checks passed 325; after the final strict-field correction, the affected Pair/legacy Matching/repository selection passed 155. Focused analysis and staged whitespace checks passed. Final independent review closed all PM2 findings. This provides internal evidence for TC-PMT-011/013–016; actual UI and the combined repair/timer budget remain later phases. Real guest/account rehome for v6 is explicitly still required in PM8.

PM3 adds exact delayed-repair spacing, a separate guided confirmation, shared support chronology and a read-only handoff to canonical Review. The production snapshot passed 495 impacted checks; subsequent test additions passed 89 Pair checks and the affected evidence file passed 16. Review follow-up strengthened two historical-codec negative fixtures with real frozen evidence, exact chronology rejection and valid spaced controls; both passed, and focused analysis/staged whitespace checks were clean. Independent final review approved spec and quality with no open findings. Tests include real two-direction pending/answer/clear fault recovery, preserved Review provenance/SRS rows and full-round capacity admission. Initial full-worst-future reservation for the tested six-pair plan was 59,357 bytes; the admitted long-Thai compact plan's maximum written snapshot was 24,022 bytes. Larger unsafe plans reject before session insertion. Audio remains a policy seam; actual Voice and accessible UI integration belong to PM6. Timer/restart, stars/replay and release compatibility remain pending.

## Fixed boundaries

- Pair remains f10, `LessonMode.matching`, activity `matching`, and route `learning/matching`. No f45, main destination, star currency, or new learning/reward authority.
- Database schema remains v24 with 48 tables; feature catalog remains 8/44. EvidenceContext and EventEnvelopeV2 contracts are frozen.
- Legacy matching remains the rollback target. New Pair UI and checkpoint writer require their compatibility checks and explicit internal configuration; production navigation activation is not implied.
- Research runtime/upload stay default-off. Pair is not evidence of motivation efficacy. No real participant data, deployment, push, merge, or other worktree changes are authorized by this implementation.

## Verification environment and remaining gates

Flutter 3.44.7 / Dart 3.12.2. `flutter pub get --offline` completed and package configuration resolves inside this worktree. Flutter/Dart test, format, analyze, dependency and build commands are serialized.

Integration full default/serial inventory, analyzer, generated-plan fingerprints, relevant policy/privacy checks and Android artifact verification have not yet been performed for Pair. The historical Research counts are baseline evidence only, not current Pair results. The existing four `release-excluded` platform/model checks remain explicit exclusions, not passes.

Physical-device accessibility/performance, learner UAT, external Product/Learning/UX/QA/Tech sign-off, production activation, real Research protocol/issuer/receipt provisioning, and efficacy remain separate gates. This document does not assert their completion or substitute synthetic results for them.
