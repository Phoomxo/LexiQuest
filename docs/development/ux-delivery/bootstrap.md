# S01 bootstrap — plan and source handoff

Date: 2026-09-24. This is coordination and document work preceding the S01 implementation chat. It does not close S01-A or any product acceptance criterion.

## Changes

- Plan v5 incorporates the six first-review fixes and the three second-review handoff/readiness fixes while retaining all v4 instructional criteria.
- The active AGENTS amendment and design index now point to the same sequential sprint/chat authority. Historical Ari/Jev/G/B dispatch files and the retired 215 register remain intact.
- The source origin is d38e, branch `feature/ari-app-device-integration`, base HEAD `2ea4d407e7d5b1d41af65a533691b8aafe019ac5`.
- A pre-edit archive preserves 263 paths (19,290,882 payload bytes); every archived file was read back and matched its recorded SHA256. It includes the old dirty/untracked files and the original AGENTS text.
- New state and handoff distinguish coordination, implementation, instructional review, usability and learning evidence.

## Verification

Executed document/source verification: 26 checks passed, including retained 18 sections, all nine critique resolutions, 12 backlog groups, four sprint subitems, state/handoff identity, gate paths and unchanged prototype/historical register hashes. All 260 original captured paths outside the three authorized documents are byte-identical. Authorized changes are limited to `AGENTS.md`, the blueprint and design README; their originals are in the pre-edit archive.

The second review identified a dependency-encoding ambiguity: S01-C navigation and learning-trial prerequisites could have been read as one AND gate. The state now records purpose-specific readiness, so unreviewed media still blocks learning trials while independent navigation can proceed. Targeted validation of these two readiness cases is recorded in the verification artifact.

Source transfer is verified separately by the manifest emitted after archive creation and hash/round-trip checks. Its recorded result, archive SHA256 and per-file hashes are the transfer authority; this document does not substitute for that check. No application source or prototype behavior has been changed by bootstrap.

## Outstanding work

S01-A/B/C remain unimplemented at bootstrap. Existing prototype defects UX-D01–04 remain open. Reviewed media, actual reviewers and trial participants are not confirmed. No live AI/provider or hosted-sync readiness is inferred. No Flutter/backend/Android/GPU/native/user/endurance checks were run for this document-only change.

## Next

Freeze the bootstrap source overlay, release the writer reservation, create exactly one fresh S01 project chat from the declared source, verify receipt/active progress, and stop application writes in the predecessor. The S01 chat verifies the received source before starting A and continues the authorized ready work.
