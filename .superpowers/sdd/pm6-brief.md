### Task PM6 — Adaptive Standard UI, copy and accessibility (11 pd)

**Requirements:** UI-018–026, NFR-042/043, FR-106/112/116/119–127

**Files:**

- Create `lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart`
- Create `lib/features/learning/pair_matching/presentation/pair_board_view.dart`
- Update `lib/screens/matching_mode_screen.dart` as compatibility wrapper only
- Add `test/features/learning/pair_matching/pair_board_view_test.dart`
- Add `test/features/learning/pair_matching/pair_board_accessibility_test.dart`
- Add responsive/localization goldens under existing approved golden structure

**Steps:**

1. implement setup card with source reason, 4/6, direction, timer default off and one primary CTA;
2. regular effective width renders bounded balanced columns; narrow/200%/assistive policy renders focused prompt-to-target list;
3. preserve command/evidence semantics across layouts; tiles 56px/compact 64px and actions 48×48 minimum;
4. wrong/repair state uses text+icon+border and supportive copy; no shake/loss/shame;
5. timeout primary action Continue untimed with approved Thai copy; result/history axes remain separate;
6. add TalkBack/Switch/keyboard/focus restoration/status announcement/reduced-motion/no-audio coverage;
7. validate Thai wrapping/combining marks, English locale and language-aware pronunciation labels;
8. รัน `TC-PMT-043`, golden matrix และ UAT-039–049 dry run on prototype fixtures

**Exit:** all Pair paths operable without sight/audio/precision gesture/forced timer and no semantic divergence by layout
