# PM6 review-fix handoff

2026-09-06. Worktree C:/Users/Phet/.codex/worktrees/02fa/LexiQuest; branch codex/pair-matching-pm0-pm8; HEAD7919cb860bc37d6d2d2811e4f6633340eca94010.
Implementation submitted for re-review of I1/I2/I3 and M1/M2/M3. No self-acceptance. Original staged43 Dart+12 PNG snapshot was not staged/reset/committed or otherwise mutated by this implementer.

## Exact working-tree fix set

- lib/features/learning/pair_matching/presentation/pair_board_view.dart
- lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart
- lib/features/history/application/learning_history_use_cases.dart
- lib/screens/learning_history_screen.dart
- test/features/learning/pair_matching/pair_board_accessibility_test.dart
- test/features/learning/pair_matching/pair_board_view_test.dart
- test/features/learning/pair_matching/pair_matching_experience_host_test.dart
- test/screens/learning_history_screen_test.dart

No other source/test/golden/Voice files changed. Seven inherited native registrant line-ending entries remain untouched. Final git diff --name-only -- '*.dart' contains exactly these8; golden working-tree diff is empty.

## Fixes and focused evidence

I1: Guided card excludes descriptive children only. Its existing FilledButton is a real explicit semantic child. Same visual layout and public callback API; regular/focused SemanticsAction.tap dispatches exactly one correct word/support revision, with no select/reveal on build/focus. Busy/pending has no tap action.
M1: Board compares adjacent read-only timer samples and deduplicates downward30s/10s crossings by session+round+timer mode+threshold. Nonaligned30050→29800 and10050→9800, per-tick silence, phase/round rearm are tested. No clock/persistence authority added.
- RED: pm6-fix-board-red.log,15 pass/3 defect failures.
- GREEN: pm6-fix-board-green.log,18 pass.
- Command: flutter test --no-pub test/features/learning/pair_matching/pair_board_accessibility_test.dart test/features/learning/pair_matching/pair_board_view_test.dart --reporter expanded
- Disjoint pure_board helper wrote only the above board source+2tests; main ran all tools, then helper released all3 before formatting/final checks.

I2: Host Retry is selected from typed coordinator recovery, including finish and acknowledgePresentation. _run then finishes/reloads canonical result before the existing post-render presented receipt. Same controller/session/close identity retained; no new controller, no early presentation.
A narrow optional PairMatchingSessionPurposeReader resultReader lives only in the authorized runtime host file and only intercepts _finish projection read. Default remains actual Drift reader; canonical initialization/recovery/owner queries remain actual DB. Tests wrap the real reader and fail one acknowledged-result read.
- Actual RED3: pm6-fix-host-red.log, close before commit, close after lostACK, result read after close. Each had no Retry.
- GREEN3: pm6-fix-host-green.log, same controller,4 unique answers,3 terminal checkpoint receipts, same close timestamp, no presented result before retry.
- Command: flutter test --no-pub test/features/learning/pair_matching/pair_matching_experience_host_test.dart --plain-name 'same host retries exact canonical completion' --reporter expanded
- Initial pm6-fix-host-red-api.log was expected missing named resultReader seam; behavioral RED was rerun after adding that seam, before recovery fix.

I3: Strict owner/purpose/session authentication still applies to every displayed session. A valid snapshot without acknowledged terminal is omitted from successful-result hydration rather than failing the entire batch. Valid abandoned Pair gets stopped/incomplete/no-stars/no-replay copy; completed neighbors retain their results and typed Replay.
M2: Source session IDs stay in typed lineage only. Card shows name/date from the already-loaded page, or a generic selected-source explanation when absent. No extra query/hydration authority.
- Actual behavioral RED: pm6-fix-history-red4.log, completed replay button null in page containing actual normal+replay+configured-effort-cap abandoned canonical rows.
- Copy RED: pm6-fix-history-copy-red.log, old raw ID text lacks loaded source caption.
- GREEN12 full History screen: pm6-fix-history-green2.log. Mixed actual page at320px/200% retains enabled completed actions, disabled stopped action, no raw source ID, no framework exception. Typed callbacks carry original session identity.
- Commands: flutter test --no-pub test/screens/learning_history_screen_test.dart --plain-name 'canonical completed normal and replay survive abandoned Pair' --reporter expanded; flutter test --no-pub test/screens/learning_history_screen_test.dart --plain-name 'Pair overview separates' --reporter expanded; flutter test --no-pub test/screens/learning_history_screen_test.dart --reporter expanded.
- Fixture corrections preserved in logs: red.log initially used concrete _Reader instead of domain interface; red2 rejected same replay shuffle seed; red3 rejected a10-minute effort delta (corrected to two legal5-minute deltas). First green.log then exposed a test tap outside viewport; explicit ensureVisible and scroll reset fixed the harness, with assertions retained. No domain guards weakened.

M3: Post-frame resume handles only StateError accompanied by actual typed capacity pause and still-live resumable host status. Other domain/lifecycle failures are rethrown. Existing Continue UI remains available; no reserve bypass.
- RED1: pm6-fix-capacity-red.log, actual restored timed-capacity coordinator leaked StateError to framework.
- GREEN1: pm6-fix-capacity-green.log, no framework exception, Continue activates and board resumes.
- Command: flutter test --no-pub test/features/learning/pair_matching/pair_matching_experience_host_test.dart --plain-name 'restored timed capacity stays actionable' --reporter expanded.

## Frozen final verification

All8 files formatted serially in pm6-fix-format.log (8 files,6 formatted). No source edits after the following checks began.

1. flutter analyze --no-pub
   - No issues found. pm6-fix-analyze.log.
2. flutter test --no-pub test/features/learning/pair_matching test/features/learning/matching_mode_adapter_test.dart test/screens/matching_mode_screen_test.dart test/features/learning/unified_lesson_controller_test.dart test/features/learning/session_configuration_store_test.dart test/features/learning/session_configuration_sheet_test.dart test/features/learning/session_configuration_policy_test.dart test/screens/learning_history_screen_test.dart test/features/history/learning_history_replay_test.dart test/features/history/learning_history_reader_test.dart test/runtime/production_feature_gate_test.dart --reporter expanded
   - GREEN502 (original494 selection plus8 tests), pm6-fix-final-regression.log.
   - Includes unchanged12 golden comparison, full actual host, board accessibility, History and all prior Pair/core/legacy/lifecycle regressions. No --update-goldens or baseline writes.
3. git diff --check
   - Exit0; known LF/CRLF notices only.
4. Exact8 source diff and empty golden delta inspected; no task-owned Flutter/Dart processes remain.

Voice inputs are unchanged; prior GREEN163 pm6-final-voice-regression.log remains applicable and was not redundantly rerun.

M4 disclosure: final502 output still contains inherited duplicate AppDatabase Drift fixture warnings, starting line428 and subsequent blocks in pm6-fix-final-regression.log. This run is passing, not warning-free. Warnings were not suppressed and unrelated fixture cleanup was not attempted. The new History widget was checked at narrow200 without claiming a new History golden or physical-device validation.

## Release and limits

All helper/source/tool ownership is released to root for re-review; no running task-owned processes or pending writes. No source/index stage/reset/commit, dependency/schema/contracts/Voice changes, scanner, deployment/enrollment/upload.
PM7 configured-withdrawal/actual Adventure and PM8 owner-move/reader-first release work remain separately assigned. Physical TalkBack/Switch Access/native voice/UAT remain NotRun.

