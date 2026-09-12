# R15.5 local dashboard acceptance

Source: feature/r15-dashboard-continuation, cad3 worktree, based on exact
4936b48b4ce307ecdeb8aa6f77282f5f202f3bd1 (R15.0–4). This file accompanies the
accepted R15.5 commit; resolve HEAD for exact handoff SHA.

## Acceptance coverage
- A-DATA-01: summary/detail share rounding formatter; correct/total and percent
  (5/6=83%). Reader fixture independently proves5 correct of6.
- A-DATA-02: accuracy getter respects availability; noEvidence/sampleSize0 render
  unavailable copy, never0%proficiency. Domain regression covers nonempty noEvidence.
- A-DATA-03: profile activeDuration displayed as1 minute19 seconds; ledger fixture
  has79 active seconds within ten-minute wall span. No wall-time calculation.
- A-DATA-04: XP increase leaves mastery unchanged; accumulated mastery/XP labelled
  separately from weekly accuracy/effort. Existing authorities retained.
- A-DATA-05: Bangkok Monday midnight (Sunday17:00UTC) starts Aug31; same instant
  in UTC stays Aug24 week. Weekly evidence empties, overall mastery/XP remain.
  Uses existing calendar snapshot; no new query or widget timezone policy.
- A-DATA-06: profile file reopen/read-only and history replay lost-ack/idempotency
  tests pass. No historical identity, migration, snapshot or reward-writer change.
- A-DATA-07: dashboard stale-loader/owner tests pass; fixed Goals retaining A's
  list after use-case replacement with B. Explicit and inherited dependency paths
  resolve current use case. Complete-owner export/delete scenario passes.
  No new owner storage.
- Existing reminder permission failure, duplicate scheduling, timezone/DST and
  owner-isolation coverage passes. New dashboard entry opens existing Goals route,
  retaining its guarded reminder entry; reminder implementation unchanged.
- Ordering: weekly summary → existing review/weakness actions → labelled detail
  → calendar and goals/reminder routes. No unsupported improvement claim.

## Commands, results and source accounting
All Flutter operations serialized; solo manual review, no background writer.
Checks use tool/cli/verify-scope.ps1 -Level Targeted -Area Learning -TestTargets
with explicit arrays and optional -TestName plain substring.
Log root: build/verification/4936b48b4ce307ecdeb8aa6f77282f5f202f3bd1/.

1. Broad8-target gate:137 passed,1 failed;exit1,24.40s including setup.
   Log:1e92a0a14152-5bd0061f472f/Explicit-Flutter-tests.stdout.log.
   Fingerprint:5bd0061f472fe6ae89cb7e6c7839237e86cbcc03f3ad7711904b313d4c0e5903.
   Targets (all under test/, .dart):
   screens/mastery_dashboard_screen_test, screens/learning_goals_screen_test,
   screens/study_reminder_settings_screen_test,
   features/progress/personal_learning_profile_test,
   features/progress/learning_calendar_reader_test,
   features/reminders/study_reminder_use_cases_test,
   features/history/learning_history_replay_test,
   scenarios/complete_owner_export_delete_test.
   Sole failure: activation test searched Listening before scrolling to its now
   lower card. Both count and Listening assertions retained; scroll first.
2. Corrected activation case (TestName 'reloads profile whenever'):1/1,exit0,9.18s.
   Log:ac35486fbd9a-2de9cc121ce2/Explicit-Flutter-tests.stdout.log.
3. Additional ledger case (TestName 'R15.5 ledger'):1/1,exit0,about10s.
   Final fingerprint:305b34114968c6b2bfb91540240257b8f3e677ed6189642320c111aafb015910.
   Result:targeted-learning-d1c77c2c2bad00eb8271ebe698daae0bb650fe62a614c098a0439e000ba205ad.json
   includes exact runtime/log location. Initial fixture UPDATE was correctly
   rejected by immutable-segment trigger; corrected by inserting ten-minute span
   initially. Existing fixtures retain default one-minute span.
4. flutter analyze on three modified runtime and three test files:exit0,
   no issues (analysis4.2s); build/verification/r15-dashboard-analysis.log.
   Runtime:mastery_dashboard_screen, learning_goals_screen, personal_learning_profile.
   Tests:matching three screen/profile suites. Manual diff reviewed for routing,
   availability and owner cache. Windows CRLF-aware diff check passes:
   git -c core.whitespace=cr-at-eol diff --check.

No runtime changes after broad gate. Subsequent test-only changes fix one stale
scroll assertion and add ledger fixture with unchanged default helper span.
Broad137 passes remain applicable; no unchanged broad rerun. Counts overlap with
earlier focused gates, so do not sum their totals.

Regression-first evidence:
- Four accuracy/summary failures:1a28c42099fd-04c34c89616a; then4/4 green:
  1a28c42099fd-b30e8f91d339.
- Goals source replacement retained Goal A:b682d91cdc03-c52696fcafe0; then1/1 green:
  29dd95f527c3-66322d855677.
- Goals entry absent:5e7efe95ab09-2a3217a52ec2; passed in broad gate.
- Ledger immutable fixture failure:599fa04a5e96-2de9cc121ce2; corrected as above.
Each directory contains Explicit-Flutter-tests.stdout.log and stderr.log.

## Visual evidence and limits
Actual Flutter390x844 PNGs reviewed: empty summary/details at100%, 5/6 summary
and details at200% text. Text wraps without overflow. Files:
build/verification/r15-visual/after/r15-dashboard-empty.png,
r15-dashboard-empty-details.png, r15-dashboard-large-text.png,
r15-dashboard-details.png.
No physical/TalkBack/human/live-service/release or research acceptance claimed.
No APK build/install; authorized Vivo check remains at combined UI source freeze.
No new research storage, schema, authority or service.

Generated platform registrants: EOL-only status, no content diff; excluded from
commit/handoff. All task-owned verification processes completed. Full logs/PNGs
untracked in cad3/build/verification. Token/credit usage unavailable; no savings
estimate.
