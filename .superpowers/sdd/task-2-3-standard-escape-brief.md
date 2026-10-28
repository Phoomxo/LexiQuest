# Task 2.3 corrective slice — unconditional Standard escape

## Context

This corrective slice closes the Task 2.3 shell contract and AMM-FR-007 / AMM-FR-010 / UX-AC-10. The approved design is already present; do not redesign the feature.

Root cause already established: `TodayExperienceHost.build` returns separate loading, error, and unavailable scaffolds before reaching either presentation shell, so those authorized Host states omit the Standard escape. In addition, a valid `ActivePresentationPermit` currently wins over every `sessionChoice`, which makes the visible escape ineffective for an assigned Adventure participant even though the design requires assignment to remain stable while the effective presentation may switch to Standard.

## Binding requirements

1. Within an already authorized `TodayExperienceHost`, a usable Standard escape must be visible without scrolling in every top-level state: loading, load failure, unavailable/post-authorization failure, Adventure, and Standard.
2. Hidden/disabled/unknown/stale unauthorized routes still return Learn before constructing the Host; do not add a Standard fallback outside an authorized Host.
3. The first resolution under a valid active permit uses the assigned presentation. An explicit in-Host switch to Standard changes only the effective presentation; it must retain the same permit ID, assignment ID, assigned treatment identity, entry-attempt UUID, and Today snapshot, and must not mutate or save the learner preference.
4. Presentation switch, rebuild, and focus restoration must not trigger a second Today load. Explicit refresh remains the only action that starts a new Host opening and UUID.
5. During unresolved permit state, using the Standard escape must never accidentally persist a preference for a protocol participant. Handle the unknown/async state deterministically and test it.
6. Preserve the current Standard/Adventure segmented control semantics, minimum target/accessibility behavior, existing Thai copy style, and no-scroll placement.
7. Do not add schema, research event capture, assignment mutation, navigation destinations, or learning/evidence fields.
8. Preserve the exact 8/44 feature catalog and Standard behavior outside the authorized Host.

## TDD and verification

Follow red-green-refactor. Add focused tests first and run them to capture expected failures before production edits. At minimum cover:

- Standard escape present and usable while loading;
- Standard escape present and usable on load failure and unavailable state;
- active Adventure permit initially shows Adventure, then explicit Standard escape changes effective presentation while retaining permit/assignment/treatment and avoiding preference writes;
- a switch during an unresolved permit read cannot write preference;
- switch/rebuild reuses the same Today snapshot and UUID and keeps Today loader call count at one;
- existing nonparticipant preference-save and explicit-refresh behaviors remain green.

Run the changed test files plus related entry/host/navigation regressions and focused analyzer. Do not run the repository-wide suite for this slice.

## Write scope

Primary files:

- `lib/features/adventure/presentation/today_experience_host.dart`
- `lib/features/adventure/application/adventure_entry_use_cases.dart`
- `lib/features/adventure/domain/adventure_entry.dart` only if an explicit switch signal is required
- `test/features/adventure/presentation/today_experience_host_test.dart`
- `test/features/adventure/application/adventure_entry_use_cases_test.dart`

Touch other files only if a directly related test contract requires it. Do not edit documentation in this slice.

## Commit and report

Commit the completed slice with a focused message. Write the full report, including RED and GREEN commands/output, files changed, and self-review, to:

`C:\Users\Phet\AppData\Local\Temp\lexiquest-task-2-3-standard-escape-report.md`
