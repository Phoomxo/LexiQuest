# R15.4 local learning verification

Source: feature/r15-learning-continuation, starting at
b17bf81b365c6d5b37d67c84d4b3c36df13234ff. This document accompanies the accepted
R15.4 commit; resolve its exact SHA before handing off. No schema, envelope,
learning/reward authority, feature count or research gate changed.

## Acceptance coverage
- A-LEARN-01: canonical six-word Pair fixture first5/6 then repair1/1 displays
  separate counts. First answers remain5/6 after rendering; existing stars stay2.
  Projection is rebuilt from chronological attempts, never written as a score.
  History shows first-answer counts independently for normal and replay sessions.
  Existing typed review/replay authorities and no-extra-reward behavior retained.
- A-LEARN-02: history identifies flashcard self-report, reading exposure,
  recognition choices and contextual cloze. No accuracy is invented for
  self-report/exposure. Existing SRS reveal/restart classification tests pass.
- A-LEARN-03: existing exact-revision history reader and unavailable metadata/
  replay guards pass. No fallback to current catalog title/version was added.
- A-LEARN-04/05: committed reviewed explanations use existing exact identity,
  revision, checksum and distractor validation. Two short sentence excerpts
  (each capped at180 runes) expand to full original text. Missing, disabled or
  unresolved explanations explicitly say unavailable; no automatic AI call.
  Attempt-keyed feedback resets details across submissions. Outer scroll stays
  stable on expansion; quiz progression test includes forced nonzero scroll.
- A-LEARN-06: injected UTC clock crosses Bangkok midnight; a fresh reader/use
  case in another timezone retains due eligibility and the stored due instant.
  Synthetic in-memory DB only; no user SRS records were created or altered.
- Content checks: reviewed lexical revision/distractor distinctness, cloze
  ambiguity, editorial source/status validation and local reading catalog tests
  pass. Local CEFR labels remain approximate, not certified human evaluation.

## Commands and evidence
All JSON/log paths below are relative to
`build/verification/b17bf81b365c6d5b37d67c84d4b3c36df13234ff/` in this worktree.

1. `verify-scope.ps1 -Level Targeted -Area Learning -TestTargets` with these15
   files: answer_feedback_panel_test, contrastive_feedback_test,
   r15_learning_feedback_visual_test, pair_matching_result_view_test,
   learning_history_screen_test, quiz_screen_test, srs_flashcards_screen_test,
   unified_lesson_controller_test, content_quality_policy_test,
   review_center_screen_test, learning_history_reader_test, cloze_mode_adapter_test,
   definition_quiz_mode_adapter_test, cefr_editorial_catalog_test,
   local_reading_catalog_test (under their existing test directories).
   Result:298 passed,1 stale source-string assertion failed; exit1,33.04s including
   wrapper. Fingerprint47618e6000bb062e7ef968161d08dccb24d9367cc45317e6c42b3cddafb64568.
   JSON: targeted-learning-c706adb112bb93d4a1f2ff63948fbb794af437894cc7118d983fc77613969889.json.
   Log:4925d99a646e-47618e6000bb/Explicit-Flutter-tests.stdout.log.
2. Corrected the stale Today source assertion to require the current canonical
   dependency guard, preserving all other navigation assertions. Targeted
   review_center_screen_test with plain TestName `f22 is not exposed`:1 passed,
   exit0,7.65s. No runtime inputs changed after the298 passed checks.
   JSON: targeted-learning-225c5c2bbd7e50f23e2de541de04afe15fadcc26c59ed8df3b00163a24ec9d53.json.
3. Final Pair host result/replay golden case:1 passed, exit0,12.56s including
   wrapper. JSON:targeted-learning-4b46dbb930bfea5fc8691275aa00083dddf88f3e91caddec40d746780313716d.json.
   Final fingerprint for2/3:
   f2f17bfcde58d9317a7714d85525b47a6773a03cd7f15737fd13d6957388587d.
4. Due-clock/history regression group:3 passed,exit0,8.42s. Due runtime/test inputs
   unchanged afterward (formatter only). JSON:
   targeted-learning-ac89467d3601c2f89394aa9f08423b6136ee1c427ab72a357542eee773b738ca.json.
5. `dart analyze` the13 changed/new Dart files:exit0,no issues,6.65s.
   Log:`build/verification/r15-4-analysis.log`.
   Diff check passed with Windows CR-at-EOL handling; no semantic EOL cleanup.

Counts overlap across focused and broader checks; do not sum them indiscriminately.
No unchanged passed R15.2/3 gate was rerun merely for a task/commit change.

## Recovery and visual review
- Regression-first unavailable copy, excerpt/detail and history cases failed
  before fixes. A200% loading-fallback overflow was reproduced and bounded.
- Pair golden initially captured the final accepted-pair board. Read-only
  diagnostics established acknowledged terminal/completed session and a valid
  reader. Root cause was Flutter fake time not advancing the feedback hold/fade
  Timer. Fixture now pumps the production hold+fade duration before capture.
  No production completion logic was changed and no arbitrary real-time wait kept.
- Two updated Pair result goldens were generated in11.97s and reviewed, then
  passed the normal comparison in3. Generation log:
  `build/verification/r15-4-update-goldens.log`.
- Actual Flutter summary/details/unavailable200% PNGs reviewed under
  `build/verification/r15-visual/after/r15-4-feedback-*.png`. Details expose a
  persistent scrollbar; full text and next action remain reachable.
- Generated failure PNGs and registrant EOL-only changes remain excluded from
  the package commit. Never import those pending outputs into a successor.

Local implementation boundary accepted. Physical Vivo/TalkBack/human/release
acceptance is not established; build/device verification belongs at the combined
UI source freeze. No task-owned test/build process remains. Token/credit usage
was unavailable; no savings are claimed from context/file size.
