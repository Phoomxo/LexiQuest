---
target: LexiQuest version23 learning/results/report workflow
total_score: 24
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 1
target_identity: "file:C:\\Users\\Phet\\.codex\\worktrees\\cycle12-release\\LexiQuest\\lib\\screens\\score_screen.dart"
target_fingerprint: "sha256:1aef5def5141cfc71d3855cd3c9d77ed254deab16e2e03cda5b552e64bd78ac9"
target_path: "C:\\Users\\Phet\\.codex\\worktrees\\cycle12-release\\LexiQuest\\lib\\screens\\score_screen.dart"
timestamp: 2026-11-03T01-23-48Z
slug: lib-screens-score-screen-dart
---
# LexiQuest version23: learning, results and reporting

Native Android Assessment A; Operate mode. Source95c91d91, application be5e7668.
Target lib/screens/score_screen.dart; adjacent learning hub and report Inbox.
Evidence: version23 Vivo captures home-finished23, matching-finished23,
post-matching23, inbox-expanded23 and inbox-details23, plus current source.
This is a bounded UX critique, not a new all44-feature/device certification.
External PiP is excluded from app findings; obscured regions are not judged.

Design specificity: the evidence-led learning loop is distinctive, but explanatory
panels currently dominate the primary learner action. The biggest opportunity is
to make the next practice action immediate while preserving honest evidence.

Heuristic scores are expert judgments, not measured satisfaction:

| Heuristic | Score/4 |
|---|---|
| System status | 3 |
| Match to user language | 2 |
| Control and freedom | 3 |
| Consistency | 2 |
| Error prevention | 3 |
| Recognition | 2 |
| Efficiency | 2 |
| Minimalism | 2 |
| Recovery | 3 |
| Help | 2 |

Total24/40, provisional for the inspected flow. Recovery/prevention draw on the
previous bounded device receipts; no fresh destructive/error tests were run.

Strengths: update/resume preserves real progress; local report vs remote receipt
is explicitly distinguished; report date is readable and original evidence stays
available behind expansion. Four labelled navigation destinations are predictable.

Priority issues:

1. P1: Hub prioritizes companion, resume and evidence explanations over starting
practice. The inspected viewport offers more than four choices, with the
recommended action near the bottom. Put one recommended action first and collapse
supporting explanations. Preserve authority and evidence semantics. Commands:
impeccable layout, distill. Evidence choose_mode_screen.dart, home-finished23.
2. P2: Zero resumable rounds still occupy a large card with "open history and
resume". It invites an action with no candidate. Render a compact completion
state and a "view history" link when count is zero; retain the resume action for
positive counts. today_resume_panel.dart:230-247. Command: impeccable clarify.
3. P2: Thai results contain English recorded-time labels and a lengthy technical
explanation. The shared view resolves language separately from hardcoded Thai
ScoreScreen. Unify locale handling across callers and collapse the explanation;
do not infer that empty recorded time means failed answer persistence.
score_screen.dart:43-85, recorded_time_view.dart:254-330. Command: impeccable harden.
4. P2: "Return to activity selection" actually returns to History after a resumed
Matching round. ScoreScreen defaults to Navigator.pop, and Matching supplies no
destination-specific callback/label. Make wording reflect the real destination
or explicitly navigate to selection, preserving back-stack behavior. Evidence
matching-finished23 to post-matching23; score_screen.dart:111-113 and
matching_quiz_screen.dart:365. Command: impeccable clarify.
5. P2: Expanded report still puts a long technical report ID above the source
details and displays two unavailable action buttons in offlineTrial. Keep status
visible, place the ID in copyable details, and use one explicit offline message
instead of prominent unusable actions. Preserve report identity and transport
guards. content_report_sheet.dart:568, content_report_inbox.dart:235-279.
Command: impeccable distill.

Cognitive load: multiple next-step choices and caveats compete in the hub;
report/score expose implementation details before the learner needs them.
Emotional journey: preserved progress is reassuring, but the score's technical
empty-time explanation and destination mismatch weaken the successful ending.

Personas (analytical walkthrough, not recruited user testing): Jordan, a new
learner, must choose between companion/resume/ladder; Casey, returning after an
interruption, recovers progress successfully but gets a misleading final button;
Sam has bounded Tab/Enter evidence only, with full TalkBack and large-text flow
still unverified. Do not label these untested capabilities as failures.

Minor observations: starter content retains honest editorial-review disclosure;
matching separates recognition from recall mastery. Neither should be removed
merely to simplify copy. No P0 was observed in the bounded flow.

Questions: prioritize (A) hub hierarchy, (B) result language/navigation, or
(C) report readability? Scope (A) top3 issues, or (B) all5 while preserving design?
