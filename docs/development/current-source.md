# Current source and retained artifacts

Updated 2026-10-28. This index identifies the audit remediation work. It does not declare a production rollout.

| Item | Location | Disposition |
| --- | --- | --- |
| Current audit fixes | `C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`, branch `codex/cycle12-release` | Use this source for the 20 audit fixes. |
| Remediation plan | [Audit remediation and storage cleanup](../superpowers/plans/2026-10-28-audit-remediation-and-storage-cleanup.md) | Acceptance checks and work board. |
| Signed baseline | Tag `adlc-cycle12-release-1.0.0+18` at `6500cbf399083b872f8c8337c560ffb177297485` | Retain. Existing signed APKs do not contain these fixes. |
| New execution evidence | `D:\LexiQuest-Storage\maintenance\2026-10-28` | Test logs, dependency findings, cleanup allowlist and receipts. |
| Original audit evidence | `C:\Users\Phet\.codex\visualizations\2026\10\28\01a181ed-87c6-7e71-ac08-e678cb4e4681\lexiquest-audit` | Retain as evidence of the pre-fix state. |
| Primary checkout | `C:\Users\Phet\Documents\LexiQuest`, branch `feature/associative-reading-loop` | Retain unique uncommitted work. Do not build it as the audit-fixed source. |
| Earlier UX checkout | `C:\Users\Phet\.codex\worktrees\lexiquest-current\LexiQuest` | Retain unique uncommitted work. The directory name does not imply newer source. |
| Prior storage archive | `D:\LexiQuest-Storage\archives\lexiquest-current\2026-10-26` | Retain hash-verified archives and migration manifests. |

Cleanup is limited to exact ignored compiler caches and an APK duplicate with a matching SHA-256. Source checkouts, branches, release outputs, evidence, model assets, signing keys and unique work remain. The 56 native build runs whose removal was previously denied remain outside this cleanup allowlist.

Engineering tests, a signed field build, human UAT, production infrastructure and research authorization have separate completion states. Research enrollment/upload and production rollout remain disabled until their existing gates are satisfied.
