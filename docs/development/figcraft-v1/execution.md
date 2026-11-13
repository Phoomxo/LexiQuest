# FigCraft Flutter execution

Worktree `C:/Users/Phet/.codex/worktrees/figcraft-flutter-v1/LexiQuest`.
Branch `codex/figcraft-flutter-prototype`. Plan baseline `6a31964693f673b030a8c2a5d998a0a6da278e42`.
Flutter baseline `e05e8a6c`. Design baseline `21b34eaa` in the design-reset worktree.

## Outcome and authority

Implement S1 through S7 in dependency order. Preserve the denominators of 48 screens, 44 features, and 64 work packages. A screen opening does not prove its feature works. Engineering acceptance, release readiness, research authority, and publication remain separate. No merge, deployment, real enrollment, or real research upload is authorized.

The end-to-end predicate is app → library → camera → confirm → practice the selected set → result → return to that set → restart and read the saved data. Use synthetic records and existing owners, use cases, repositories, and reward authorities.

## Execution board

1. Read the poteto-mode Principles. Ground the plan against source and design evidence.
2. Frame. Capture the baseline and identify real device/service constraints.
3. Design the workflow. Use the approved S1–S7 cards rather than another product planning cycle.
4. Run the loop. For each card, write a focused failing behavior check, implement, verify, and obtain independent review.
5. Keep the audit trail in `decisions.tsv` and preserve per-card evidence.
6. Verify and hand back. Inspect the final diff, serialize full checks and APK build, verify CI against the PR head, and report every unverified item.

| Card | Write owner and boundary | Acceptance | Status |
| --- | --- | --- | --- |
| S1 | Root owns shell, practice home, and progress read projection. Test agent owns shell/home tests. Independent critic owns no production files. | Four Thai tabs, actual due preview/count, distinct new/empty/error states, library entry, contextual return, feature gating, large text. | Executing |
| S2 | Assign after S1 checks. Library and selected-set navigation. | Search, add/import, preserve selected set and filters, reopen persisted words. | Pending |
| S3 | Assign after S2 fixtures. Learning and progress. | Real answers, feedback, result context, durable and idempotent outcomes. | Pending |
| S4 | Assign after destination contract. Camera/audio/AI. | Explicit confirmation into selected set, failure recovery, known-object device evidence. | Pending |
| S5 | Account/device/data boundaries. | Owner isolation, export/deletion, offline learning, research default-off. | Pending |
| S6 | Existing motivation and advanced modes. | Single reward authority, honest availability, contextual return. | Pending |
| S7 | All writers paused for integration. | Current-SHA regression, 48/44/64 disposition, Android APK/hash/CI, independent runtime critique. | Pending |

## Grounded constraints

- A vivo V2041 is connected. Its existing `com.lexiquest.app` is versionCode 26. Inspect signing and data compatibility before any replacement. Do not clear or uninstall it.
- Flutter dependencies resolve using the existing lockfile. No dependency upgrade is part of this task.
- Existing progress has no vocabulary count or due-word preview. Extend its read projection without a schema migration rather than infer empty vocabulary from zero answers.
- Existing library lacks selected-set camera and quiz entry. Camera acceptance currently chooses a mapped category. These must share an explicit destination before the core journey can pass.
- Baseline screenshots and new Android screenshots are distinct from FigCraft design renders. TalkBack and known-object accuracy require their own observations.

## First S1 code slice

The focused shell/home/progress check passes 41 tests. This includes a real Drift-memory due review that writes one answer and completes one session, then returns to the same shell. The library shortcut retains the existing tab and scroll position. The independent source reviewer found no blocking issue in the five production files. The Windows large-text render was inspected before its golden was updated.

This is not whole-S1 acceptance. The separate practice menu, explicit library-mutation refresh case, Android runtime images, 200% device checks, and TalkBack observation remain open. Linux font rendering must be inspected from CI. The first baseline test run overlapped test-file edits and is not used as a clean baseline result.
