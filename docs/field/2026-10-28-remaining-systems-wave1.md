# Remaining systems: first verified integration

The branch `codex/remaining-system-readiness` continues the completed 20 audit fixes in `C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`. This checkpoint records the source through `53dad6a5`. It does not mark the full 44-capability catalog ready.

## Implemented units

| Commit | Result |
| --- | --- |
| `0704d632` | The HF Space implements authenticated `/v1/content`, keeps chat compatibility, limits actual request bytes and pins complete merged model snapshots. Content failure codes match the Flutter caller. Model loading is lazy and CPU HTTP tests need no live Firebase or model download. |
| `f8724a43` | Research JSON schema v2 preserves answer, vocabulary, session and document-revision relationships with artifact-local aliases. Its allowlist excludes raw content, identifiers and provider provenance. Existing consent, permit, owner and save-time checks remain. |
| `1397c826` | Frozen evidence and feature-contract definitions and caller-supplied instrument/protocol domains are restored from the approved archive. Catalog revision 1.3.0 retains hash `41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4`. Newly restored research capabilities remain hidden. |
| `53dad6a5` | Mastery opens a read-only learning history. It shows recorded session states, correct/total answers and seven local calendar dates. Stable cursor pages contain 50 entries. Queries preserve owner/session linkage and select the page before aggregating answers. |

Independent review accepted the export and history units. Review found a content error-code mismatch and an inefficient history join. Both were corrected and tested. The model-loading CLI contract now checks pinned local safetensors loading for serving while retaining the training base-model check.

## Verification on the combined source

Writers were paused during analysis and the full Flutter suite.

| Check | Result |
| --- | --- |
| Flutter unit and widget suite | 2,034 passed in 8 minutes 42 seconds |
| Flutter analysis | No issues |
| History and existing progress/Mastery checks | 54 passed, including three-page owner-isolation and 200% text cases |
| Research export checks | 52 passed |
| Frozen foundations and registry checks | 68 passed |
| Supplied instrument/protocol checks | 100 passed with synthetic forms |
| LM CPU suite | 140 passed; one TestClient deprecation warning |
| AI API CPU suite | 186 passed; two existing SDK Python support warnings |
| Voice API suite | 64 passed; live Firebase/OmniVoice E2E remained opt-in and skipped |
| Firestore, Auth and Hosting contracts | 39, 3 and 15 passed against synthetic/emulator configuration |
| CLI contract scripts | 22 passed initially; the stale serving-name assertion was corrected and its script passed all five checks |
| Diff whitespace check | Passed |

Logs are under `D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`. `wave1-source-manifest.json` records the frozen modified/new files before the final CLI correction and commits. The CLI correction has its own `model-loading-contract-green.log`. No Android build, device installation, signing, publishing or deployment was performed for this checkpoint.

## Next executable units

The current database is still v10 with 29 tables. Reserve v11 before adding only `answer_attempts.evidence_class` and `evidence_context_json`. Preserve the approved legacy sentinel and existing learning/reward behavior. New metadata must retain the content revision actually shown and survive replay, sync, owner merge and full-account export/deletion. Reject research-bearing metadata until collection and upload authority are composed.

Restore the P256 participation permit domain separately from the existing Ed25519 operation permit. The signed documents have different payloads and interfaces. Composition later needs versioned consent, assignments, participation receipts, trusted-time rechecks, storage lifecycle, collection, UI and upload rejection tests.

The active plan is [Complete the remaining LexiQuest systems](../superpowers/plans/2026-10-28-unfinished-system-integration.md). Research enrollment/upload remain default-off. Real instrument approval, issuer configuration, live-model behavior, physical-device UAT and rollout permission remain external requirements.
