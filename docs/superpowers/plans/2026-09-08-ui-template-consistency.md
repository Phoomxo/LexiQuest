# UI Template Consistency — Follow-up Implementation Plan

> Use subagent-driven-development with disjoint writers. This is the user's requested refinement of the approved motivation UI, before final regression/APK/device testing. No new approval gate, commit, dependency, domain, or schema change.

**Goal:** Make typography, card surfaces, spacing, and primary score alignment consistent across the learner application.

**Architecture:** Define the existing Material theme's text roles explicitly and reuse one presentation-only `LearningSummaryCard` for primary numeric summaries. Keep explanatory text and secondary metrics in readable left-aligned sections. Existing routes, controllers, values, rewards, evidence, and permissions stay authoritative.

**Tech Stack:** Flutter, Material 3, NotoSansThai, current theme, no new packages or network assets.

## Design decisions

- The user specifically requested centered primary scores and consistent templates. Compare captures at the same text scale; keep full system 200% scaling and reduced motion. Never shrink or clamp accessibility text to conceal overflow.
- App bar / dialog / section title: 20 sp, medium-weight. Subsection/card label: 16 sp. Body: 16 sp; supporting text: 14 sp. Main numeric result: 32 sp. Learning targets may use 24–28 sp where they are the actual exercise, not a menu heading.
- Common page gutter and card padding: 16 dp, related content spacing 8/12, section breaks 24, radius16 and minimum interactive target48. Use a quiet outlined surface with zero elevation consistently in light/dark mode. Card default margin has no horizontal inset and 12 dp bottom spacing; remove duplicate adjacent spacing on reviewed surfaces.
- Primary summary: centered icon/label/value/caption, no fixed-height or clipped numeric badge. The value is a short fact from existing data, not an invented mastery percentage. Empty/unavailable summaries show words without a false zero score. Longer explanations remain separate and left-aligned.
- Keep content responsive and scrollable. Large text is allowed to wrap naturally; a 240 dp viewport must keep dismiss/back/primary actions reachable.
- A4 preview remains local and temporary; no purchase/equip from rendering. Reminder denied-retry fix and all previously approved owner/evidence boundaries remain in force.

## C1.1 Theme and shared summary (root)

Files: `lib/config/m3_theme.dart`; create `lib/widgets/learning_summary_card.dart` after equivalent search found none.

Root also owns `lib/widgets/local_study_datetime_field.dart` (8 dp between date/time/zone controls) and `lib/screens/study_planning_hub_screen.dart` (SafeArea/SingleChildScrollView with16 dp gutter and full-width actions). Audit confirmed adjacent controls and a non-scroll hub; retain callbacks/gates and date resolution. These bounded refinements are in the user's requested layout scope.

Interface: `LearningSummaryCard({Key? key, required String title, String? value, String? caption, IconData? icon})`. No callbacks, read model, or persistence. Full-width Card/Padding16/Column(stretch) with centered title/value/caption, optional decorative icon; value uses headlineLarge32, title titleMedium16, caption bodyMedium16. Card owns only presentation.

- [ ] Preserve a C1 source baseline, record the two independent audits.
- [ ] Apply explicit matching light/dark text roles and card treatment while preserving Thai font, contrast-aware colors and motion/touch settings.
- [ ] Create the shared metric renderer, inspect normal and long values at 100/200%.

## C1.2 Summary surfaces (assigned writer)

Files: `lib/screens/mastery_dashboard_screen.dart`, `achievements_screen.dart`, `score_screen.dart`, `result_screen.dart`, `learning_calendar_screen.dart`; `lib/features/adventure/presentation/adventure_result_screen.dart`; `lib/features/learning/pair_matching/presentation/pair_matching_result_view.dart`.

- [ ] Center primary numeric facts with the shared summary. Weekly Mastery may show `correct / sample`, keeping the full original Thai count sentence and all evidence limits. Achievements shows XP as XP, never mastery. Adventure learning count, reward receipt and effort remain distinct. Pair matched/independent/assisted/replay/star data unchanged.
- [ ] Score/result bodies use scrollable layouts and theme color/text roles, preserving callbacks. Do not silently turn an unavailable result into a score.
- [ ] Remove duplicate adjacent card spacing; use left-aligned secondary detail rows and consistent headings. Keep diagnostic detail disclosure and lifecycle unchanged.
- [ ] Run existing result/mastery/achievement/calendar/Pair regressions after all writers freeze; add only meaningful navigation/overflow regressions if existing coverage lacks them.

## C1.3 Core templates (assigned writer)

Files: `lib/screens/choose_mode_screen.dart`, `today_hub_view.dart`, `avatar_equipment_screen.dart`, `profile_settings_screen.dart`, `setting_screen.dart`, `learning_goals_screen.dart`, `study_reminder_settings_screen.dart`; `lib/features/learning/presentation/session_configuration_sheet.dart`.

- [ ] Normalize actual heading roles and inset rhythm; remove redundant card separators introduced by common margin; retain pending recovery/quickstart priorities and lazy-list accessibility.
- [ ] Match goal/reminder picker button spacing, small-screen dialog scrolling and card/list hierarchy. Preserve picker values and canonical owner guards.
- [ ] Keep shop hero preview centered and secondary level/coin information compact; route labels/body copy stay readable. Do not resize activity words merely to match menu labels.
- [ ] Use current screen tests plus actual same-scale captures to check all action/back/cancel/keyboard paths.

## C1.4 Integration and quality gate (root)

- [ ] Freeze all writers, format only C1 Dart files, inspect incremental diff against C1 baseline plus prior approved changes.
- [ ] Repair the focused visual harness to match real Scaffold/owner IDs and lazily built controls; fixture corrections do not count as app defects or successful captures.
- [ ] Capture base28 + focused30 + contextual14 in a new C1 output root, plus result states not covered by those fixtures. Keep historical captures and hashes. Inspect every image in separate100%/200% groups; no mixed-scale impression used as acceptance.
- [ ] Re-review C1 source, run touched regressions/accessibility then resume the original plan F0–F8 (analysis, full Flutter, integrations, backend/CLI/policy, contracts, APK) only after UI is finished.
- [ ] Then install the verified APK on the connected vivo with data-preserving identity checks, record actual native results and request human observations for UAT/TalkBack. Three-hour actual usage remains a separate unfinished gate until elapsed activity and observations exist.

Baseline worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`, HEAD `788e90e62b1694c20945734787723c168b6a6ab2`. Preserve all dirty/untracked prior work. Evidence in `build/verification/motivation-ui-20260908/`; no final/native success claimed by this plan.

## C1.5 Findings from actual pixel review

The first complete focused30 capture passed its renderer tests but independent pixel inspection found two defects. These are in-scope corrections before final gates, not additional product capabilities.

- Align nested secondary Mastery/SRS/engagement metric containers to stretch so their labels and values share the left edge with skill rows. Primary weekly summary stays centered; no formula or availability changes.
- Material input TimePicker clips the minute input and confirm action at240dp/text200. Behavioral RED also reproduced a61px bottom overflow with a280dp keyboard inset. Add a shared `showStudyTimePicker` presentation helper used by LocalStudyDateTimeField and quiet-hour pickers. Keep the native24-hour Material picker at ordinary widths/scales with Thai labels; use a scrollable vertically stacked hour/minute dialog for width<360 or text scale>1.3. The width cutoff accounts for the installed SDK's fixed content width plus dialog padding/insets;320 is insufficient. Preserve full system text scaling, initial values, validation(0–23/0–59), cancel-null and confirm-only result semantics. No schedule/owner/UTC authority changes.
- Write meaningful narrow/keyboard/invalid/cancel tests, observe RED, implement, rerun the existing date/time/reminder integration tests, then refresh and inspect actual pixels. The first RED is `motivation-c1-time-picker-red-20260908T074052979Z`; its failures are not final acceptance.

New files: `lib/widgets/study_time_picker.dart`, `test/widgets/study_time_picker_test.dart`; discovered no existing equivalent shared implementation. Root remains the only toolchain runner.
