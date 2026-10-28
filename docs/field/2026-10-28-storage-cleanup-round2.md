# Storage cleanup after the superseded-file clarification

Date 2026-10-28. The user explicitly requested deletion of superseded versions and old working copies, including source copies after Git/GitHub backup. Test discovery and similar filenames are not reasons to retain obsolete versions. No project files are relocated to D: in this run; that drive holds inventory, scripts and execution metadata only.

## Measured result

The round's initial C: snapshot has 106,808,209,408 free bytes. The final measurement has 162,183,495,680 free bytes. Net gain is 55,375,286,272 bytes, or **51.572 GiB**. C: has approximately **151.045 GiB** free. This includes the cost of local Git snapshots and is separate from the previous 40.579 GiB cleanup.

- Removed 1,310 exact file/directory targets, including obsolete compiler caches, APK/AAB versions 1–17, superseded branch builds and an older Figma installer. Installed Figma is newer than that installer.
- Removed 9 obsolete Git worktrees after source backup. Original branch references remain. Their removal returned another measured 7.529 GiB after the earlier file cleanup.
- Removed 44 inactive uv-managed Python environments. Their source projects and lockfiles are preserved either locally or in the snapshots. Restoring an old branch requires reinstalling its dependencies.
- Preserved the current source, its three backend environments, the signed +18 baseline, the current audit debug APK, model sources and signing material.

Per-target records and before/after measurements are under `D:\LexiQuest-Storage\maintenance\2026-10-28\cleanup-round2`.

## GitHub recovery

- Current audited source is available on [codex/cycle12-release](https://github.com/Phoomxo/LexiQuest/tree/codex/cycle12-release). The implementation remains `5cad746d`; later commits contain documentation.
- The [obsolete-worktree archive](https://github.com/Phoomxo/LexiQuest/tree/codex/archive/lexiquest-obsolete-20261028) is commit `48d34f7c9f7bf134417294acecd280673df2245c`. Its manifest maps 39 original paths/branches to orphan source snapshots. Each snapshot is a parent commit of the manifest commit.
- Snapshots preserve tracked/nonignored WIP and reviewed ignored handwritten source. Superseded generated test evidence is explicitly discarded. Private signing configuration is not uploaded. Original repository histories are not imported as snapshot parents.
- Redacted scanning reported 22 findings. Independent review classified 20 as synthetic fixtures/diff copies, one as ordinary prose and one as the already-public Supabase anon client configuration. The classification is pinned to this exact archive commit. No scanning policy was weakened.
- Both remote branch OIDs were checked after push. No main-branch merge, deployment or release publication occurred.

## Verification

- All 50 audited implementation/test file hashes remain unchanged.
- All 10 retained +18 artifact hashes and the current debug APK hash match their original measurements.
- Retained runtime checks pass after cleanup. AI has 186 passing tests, Voice CPU has 64 and LM CPU has 83, totalling 333.
- The full Flutter suite is not rerun because implementation source is unchanged; its earlier 1,851-test evidence remains associated with that source snapshot.
- A reviewer independently confirmed all declared source paths are present in the 39 Git snapshot trees. Deletion validates source status, file hashes, retained copies, registered roots and remote archive identity.

## Remaining protected or blocked files

There are 34 registered worktrees. Nine were removed from the original 43. Thirty archived old worktrees contain generated Flutter plugin links and remain because the link-removal path was stopped after an automatic approval rejection. The four explicitly retained roots are the pinned primary checkout, current `cycle12-release`, `lexiquest-current` containing the earlier denied native runs, and `p0-integration` containing unique signing configuration.

Automatic approval rejected the junction unlink self-check command and separately rejected the v15 transfer-chunk removal command. Both responses state only `blocked by policy`. Neither action was retried through another mechanism. The 27 v15 transfer parts, totalling 112,353,496 bytes, remain. Three old environment junction entries are also retained; current runtime environments are real independent directories and passed their tests.

The 56 native build runs excluded after the prior denial are still excluded. Shared package caches, Docker data and unrelated projects are outside this cleanup. The remaining blocked paths are listed in `junction-disposition.json`, `environment-link-disposition.json` and the artifact inventory.

Build the Lever produced the inventory, bounded deletion and Git snapshot tools. Prove It Works required measured free space, remote OID confirmation, source/artifact hashes and retained-runtime tests before reporting the result.
