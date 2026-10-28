# Audit remediation and storage checkpoint

Updated 2026-10-28. Worktree `C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`, branch `codex/cycle12-release`. Baseline `6500cbf399083b872f8c8337c560ffb177297485`.

Remediation source commit `5cad746d1873ab7aae7726619dcc7219b0db1ef8` contains the 20 fixes and their regressions.

The user authorized all 20 audit fixes, current-file organization, and removal of recoverable obsolete copies. The original signed `1.0.0+18` artifacts remain historical baseline artifacts. They do not contain the fixes below.

## Audit disposition

| ID | Corrected behavior | Regression evidence |
| --- | --- | --- |
| 1 | Reject incoming category/word IDs owned by another retained account before upsert. | `data_owner_regression_test.dart`, `natural_key_sync_test.dart` |
| 2 | Keep a local natural-key target and persist owner-scoped aliases with raw remote evidence. Remap child words/attempts and rebuild merged SRS from all answer evidence. | `natural_key_sync_test.dart`, including restart/replay, raw alias, canonical target and ordinary SRS control |
| 3 | Shadowing retries the same answer ID/time and retries finish without awarding another answer/XP. | `shadowing_retry_test.dart` |
| 4 | Bound actual ASGI body bytes for AI/Voice, including chunked requests. Reject malformed length headers. | AI/Voice `test_app.py` |
| 5 | Resolve AI/Voice MessagePack to `1.2.4` with the normal lock resolver. | Dependency pin tests, malformed-input allocation probe, lock checks and OSV report |
| 6 | Keep warnings as errors in AI CI and exempt only the known Google Python-version warning. | Strict AI command and CI contract |
| 7 | Reopening post-recall Reading starts an explicitly labelled new round when no exact persisted session result can be restored. Preserve old answers. | `reading_resume_regression_test.dart`, owner-aware screen journey |
| 8 | Dashboard due/mastery counts join active vocabulary for the same owner. | `deleted_vocabulary_progress_test.dart` |
| 9 | Preserve case in AI cache keys. | `test_content_services.py` |
| 10 | Separate local credential quota identities without exposing credentials or promising multiplied project/provider quotas. | `test_content_services.py`, config/comment review |
| 11 | Re-adding a deleted natural key revives the same row/history and increments its revision/outbox. | `vocabulary_recreate_test.dart` |
| 12 | Follow push/pull backlog with bounded continuation. Preserve aggregate counts/failures, reject regressing cursors, renew the run lease and continue after quarantined batches. | `sync_engine_test.dart`, `sync_continuation_test.dart`, five lease-loss regressions and two invalid-backlog regressions |
| 13 | Mutate parsed MiroFish JSON fixtures and assert the current Gemini namespace/encryption contract. | Native CLI contracts |
| 14 | Run signing/release/static-policy/Gitleaks/evidence contracts in a Windows CI job. Preserve Linux checks. | `ci-workflow.tests.ps1` |
| 15 | Resolve late-domain guest/account unique-key collisions with target-wins policy, archive discarded rows/quest children and preserve alias identities. | `late_owner_merge_test.dart`, `data_owner_regression_test.dart` |
| 16 | Require a covering GCS Delete lifecycle rule and reject incompatible retention/hold/versioning before enabling exports. | `test_gcp_account_export.py` |
| 17 | Re-read trusted time and permit expiry after asynchronous authority state lookup. | `permit_expiry_regression_test.dart` |
| 18 | Disable obsolete `vocabulary`/`global_words` client writes while retaining signed reads. | Firestore emulator and static policy contracts |
| 19 | Generate verb examples with `He will <base verb>` instead of invalid inflections. | `test_generate_synthetic.py` |
| 20 | Pair token/label positions in dry-run features with strict length checking. | `test_lora_finetune.py` |

The rejected EOF-parser finding was not changed. Its runtime probe passed before remediation.

## Current evidence

Logs and manifests are under `D:\LexiQuest-Storage\maintenance\2026-10-28`.

- Focused data/sync/identity/permit tests pass 126 cases on the frozen source.
- AI strict CI command passes 186 tests. Voice CPU tests pass 64. LM CPU tests pass 83. Both changed dependency locks pass `uv lock --check`.
- CLI contracts pass 23/23 scripts under PowerShell 7. MiroFish's synthetic validator retains its Windows PowerShell 5.1 child process requirement.
- Firestore emulator passes 39 tests. Auth emulator passes 3. Hosting headers pass 15.
- Gitleaks history passes 1212 commits. The staged source diff passes separately. A broad local-directory scan also sees ignored signing configuration, external runtime packages and generated artifacts; that scan is not a clean-source result and its redacted report stays local.
- Full Flutter suite passes 1851 tests in 8m53s. Final analysis reports no issues. All 50 modified/new implementation and test files match `verified-source-snapshot.json` after the build and cleanup. No completion claim uses an interrupted earlier full-suite run.
- Android debug build passes in 160.3s using a 1536 MiB Gradle heap and one worker. The build retains existing Kotlin-plugin/SDK-tool compatibility warnings. It does not install or distribute the app.
- The debug-validation artifact is `D:\LexiQuest-Storage\maintenance\2026-10-28\artifacts\LexiQuest-audit-5cad746d-debug.apk`, 251,093,001 bytes, SHA-256 `8FB8C09084141CCC630A8CED270A92694C014693BD90375A8D12D7A9293D24F2`. It uses debug version `1.0.0+1` and the exact remediation build ID. It is separate from the signed field-release baseline.

Reviewers accepted the frozen backend/app/LM/tooling/rules and data/identity/research slices. Root reviewed the final ready-queue predicate and trigger aggregation. Focused RED evidence preceded fixes for alias SRS, cursor regression, lease expiry, aggregate totals and quarantined backlog.

## Storage disposition

The [source index](../development/current-source.md) identifies the current source and retained work. `cleanup-candidates.json` and `cleanup-verified-candidates.ps1` restrict cleanup to 11 ignored compiler-output directories in clean older worktrees and one SHA-256-identical APK copy. A reviewed preflight validates exact paths, clean retained source, ignored/untracked targets, no reparse points, inactive build processes and the duplicate APK hash. The final app usage check retains the pinned primary checkout and active chat.

Cleanup removed all 12 allowlisted targets. `cleanup-receipts.json` records each removal. The measured logical size was 43,577,031,812 bytes. Actual C: free space increased by 43,571,634,176 bytes, or 40.579 GiB, during cleanup, from 65,793,228,800 to 109,364,862,976 bytes. C: has about 101.85 GiB free at that measurement. The task's initial free-space snapshot was 67,201,261,568 bytes; build/test artifacts account for the difference between net task gain and cleanup gain.

All 43 Git worktrees remain registered. Primary checkout status remains 276 entries with the same paths/statuses as the before snapshot. Its README pointer is the sole intentional primary edit. Earlier UX WIP remains 938 entries. The 50-file verified source snapshot remains unchanged. Retained source lockfiles exist for all affected worktrees. All 19 retained APK/AAB inventory entries match their original SHA-256 hashes after cleanup. Rebuilding old checkouts will regenerate the removed compiler caches.

Retain all source checkouts/branches, unique tracked/untracked work, release outputs, evidence, models and signing keys. Retain all 56 native build source runs excluded after the prior cleanup denial. Existing `+18` APKs with different hashes are not duplicates.

## Remaining release work

- Validate the new source on physical Android hardware, including human UAT, TalkBack and audio behavior. Historical `+18` evidence does not validate the changed source.
- Rebuild and attest a new signed field release through the existing release gates before distributing it. No deployment, install, publication or production policy update is part of this task.
- Complete live App Check/Play acceptance, trusted support/deletion contacts and required GCS/KMS/IAM/Cloud Run configuration before opening the relevant production gates.
- OSV still reports three deduplicated issues in the Voice GPU dependency closure. Setuptools fixes require versions incompatible with the current Torch `<82` constraint. A paired Torch/Torchaudio upgrade needs runtime-guard changes and real GPU synthesis validation. The MessagePack issue is fixed.
- Research remains default-off. Production permit/state/trusted-time adapters and real collection/upload integration still need engineering and end-to-end rejection/withdrawal/export/deletion evidence. Protocol/instrument/issuer/ethics and rollout authority are separate dependencies.
- This round does not re-run unchanged Supabase Docker policies, live providers, GPU inference or non-Android builds.
