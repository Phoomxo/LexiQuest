# Current source and retained artifacts

Updated 2026-10-29. This index identifies the audit fixes and continuing system integration. It does not declare a production rollout.

| Item | Location | Disposition |
| --- | --- | --- |
| Active development | `C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`, branch `codex/remaining-system-readiness` | Includes the 20 audit fixes, history, LM serving, research export, motion controls, owner coordination, signed measurement/linkage storage, v16 exact quiz recovery and the optional visible Study host. |
| Completed audit baseline | Branch `codex/cycle12-release`, commit `1aa189a3` | Historical audit/cleanup checkpoint retained before the continuing integration branch. |
| Remaining-system plan | [Complete the remaining LexiQuest systems](../superpowers/plans/2026-10-28-unfinished-system-integration.md) | Current execution board and acceptance checks. |
| Capability coverage | [44-capability runtime matrix](../field/2026-10-28-feature-readiness-matrix.md) | Source-backed connected/partial/missing states; not production or UAT certification. |
| Verified v11 integration | [Evidence metadata checkpoint](../field/2026-10-28-remaining-systems-wave2.md) | Source `efff26a6`, Flutter 2191, analysis 0, rules 45, CLI 23 and Android debug pass. |
| Verified motion/owner integration | [Wave 3 checkpoint](../field/2026-10-29-remaining-systems-wave3.md) | Application source `26952596`: Flutter 2308, analysis 0 and normal Android debug build passed. |
| Verified local assignments | [Wave 4 checkpoint](../field/2026-10-29-remaining-systems-wave4.md) | Application source `8504a202`: schema v12/30 tables, Flutter 2385, analysis 0, CLI 23 and normal Android debug build passed. |
| Verified signed participation | [Wave 5 checkpoint](../field/2026-10-29-remaining-systems-wave5.md) | Application source `6a49e8e7`, unchanged app inputs at `6f88bdc5`: schema v13/31 tables, Flutter 2445, analysis 0, CLI 23 and normal Android debug build passed. |
| Verified structured measurements | [Wave 6 checkpoint](../field/2026-10-29-remaining-systems-wave6.md) | Source `90a81306`: schema v14/33 tables, integration 794, full Flutter 2507, analysis 0, CLI 23 and normal Android debug build passed. Capture UI and canonical linkage are still separate work. |
| Verified first-session linkage | [Wave 7 checkpoint](../field/2026-10-29-remaining-systems-wave7.md) | Source `1128b9e6`: schema v15/34 tables, integration 1152, full Flutter 2594, analysis 0, CLI 23 and normal Android debug build passed. Visible UI and exact quiz resume remain separate work. |
| Motivation form component | [Form checkpoint](../field/2026-10-29-motivation-form.md) | Coded form, exact retries and visibility/withdrawal guards; 79 focused checks, five rendered fixtures and analysis pass. Shared dark contrast corrected; the later wave 9 host consumes this component. |
| Verified exact quiz recovery | [Wave 8 checkpoint](../field/2026-10-29-remaining-systems-wave8.md) | Source `4a4cbdd8`: schema v16/34 tables, exact owner/session resume and preserved canonical rewards; full Flutter 2728, analysis 0, CLI 23 and normal debug APK pass. Study host remains separate work. |
| Verified study consent component | [Study-bound consent](../field/2026-10-29-study-consent-version.md) | Source `2c94d4a3`: 133 focused and 700 integration cases, analysis 0 and independent review pass. Exact version withdrawal and legacy notice identity preserved; included in the wave 9 full suite/APK. |
| Verified Mission capture component | [Exposure and Mission facts](../field/2026-10-29-study-mission-capture.md) | Final visibility guard and exact canonical Started/Completed: 65 scoped and 1380 integration cases, analysis 0 and independent review pass. Wave 9 supplies its explicit Host caller and full-suite/APK evidence; default production factory remains absent. |
| Verified optional Study runtime/host | [Wave 9 checkpoint](../field/2026-10-29-remaining-systems-wave9.md) | Application source `e0771624`: schema v16/34, full Flutter 2869, analysis 0, CLI 23 and normal debug APK pass. Both real LocalStudyRuntime flows retain exact ordinary effects. Independent reviews accepted; production remains default-off and Research engineering continues. |
| Assessment domain component | [Assessment domain checkpoint](../field/2026-10-29-assessment-domain.md) | Later domain-only component: 79 scoped/125 frozen-contract checks, analysis 0 and independent review pass. Removes the unreachable sample-results screen/test after Git backup. No Assessment writer/UI/activation; full-suite/APK remain wave 9. Initial opening ordering correction is in progress. |
| Local Research authority adapters | [Authority adapter checkpoint](../field/2026-10-29-local-research-authority.md) | Five local ports with explicit refresh, real signature/revocation/freshness checks and a supported ambient-transaction probe; 115 focused integration cases, analysis0 and independent review pass. Production gateway/lifecycle composition and initial-opening correction remain separate. Latest full-suite/APK remain wave 9. |
| Study opening order correction | [Opening-order checkpoint](../field/2026-10-29-study-opening-order.md) | Durable preparation before either real renderer, same-process pre-frame retry and fail-closed uncertain exposure; inherited outer transactions denied. Four behavioral RED cases,117 focused/1147 expanded integration cases, analysis0 and independent review pass. Latest full-suite/APK remain wave9; switching and production authority composition remain separate. |
| Debug test artifact | `C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest\build\app\outputs\flutter-apk\app-debug.apk` | Normal app, build ID `e0771624`, debug `1.0.0+1`; not installed or published. Its hash and source trees are recorded in the wave 9 checkpoint. |
| Reduced Motion | Commit `0eedc90b` | Theme/motion persistence, OS accessibility settings, route/card/chat/sheet consumers; focused 153 tests and analysis pass. Android light 100% settings fixture is readable; dark/200% native checks remain unverified after emulator failure. |
| Remediation plan | [Audit remediation and storage cleanup](../superpowers/plans/2026-10-28-audit-remediation-and-storage-cleanup.md) | Acceptance checks and work board. |
| Completed audit result | [2026-10-28 remediation checkpoint](../field/2026-10-28-audit-remediation-checkpoint.md) | Fix commit `5cad746d`, verified tests/build, cleanup receipts and remaining release work. |
| Superseded-file cleanup | [2026-10-28 cleanup round 2](../field/2026-10-28-storage-cleanup-round2.md) | Another 51.572 GiB net reclaimed. GitHub snapshots cover 39 old worktrees; 9 local worktrees removed. |
| Old worktree recovery | GitHub branch `codex/archive/lexiquest-obsolete-20261028`, commit `48d34f7c9f7bf134417294acecd280673df2245c` | Manifest and parent snapshots preserve old source/WIP without keeping every checkout as active development source. |
| Signed baseline | Tag `adlc-cycle12-release-1.0.0+18` at `6500cbf399083b872f8c8337c560ffb177297485` | Retain. Existing signed APKs do not contain these fixes. |
| New execution evidence | `D:\LexiQuest-Storage\maintenance\2026-10-28` | Test logs, dependency findings, cleanup allowlist and receipts. |
| Original audit evidence | `C:\Users\Phet\.codex\visualizations\2026\10\28\01a181ed-87c6-7e71-ac08-e678cb4e4681\lexiquest-audit` | Retain as evidence of the pre-fix state. |
| Primary checkout | `C:\Users\Phet\Documents\LexiQuest`, branch `feature/associative-reading-loop` | Retain unique uncommitted work. Do not build it as the audit-fixed source. |
| Earlier UX checkout | `C:\Users\Phet\.codex\worktrees\lexiquest-current\LexiQuest` | Retain unique uncommitted work. The directory name does not imply newer source. |
| Prior storage archive | `D:\LexiQuest-Storage\archives\lexiquest-current\2026-10-26` | Retain hash-verified archives and migration manifests. |

The latest cleanup follows the user's explicit instruction to delete superseded versions after Git backup. Old generated evidence, packages and inactive Python environments may be removed; current source, +18 baseline, model sources and signing material remain. Link-related approval blocks leave 30 archived old checkouts in place. The 56 native build runs whose removal was previously denied remain outside the cleanup allowlist. See the round-2 report for exact retained and blocked paths.

Engineering tests, a signed field build, human UAT, production infrastructure and research authorization have separate completion states. Research enrollment/upload and production rollout remain disabled until their existing gates are satisfied.

The disposable `emulator-5568` session failed after its light settings capture.
Automatic tool approval rejected the combined command to stop its two owned
processes and remove its temporary VM and preview APK, stating `blocked by
policy`. No cleanup retry was made. Those artifacts remain under
`D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems\motion-native-a9595bdb`
and `visual-checks\reduced-motion-preview.apk`; the visual manifest records
the exact scope and retained evidence. No new reclaimed-space claim includes them.
