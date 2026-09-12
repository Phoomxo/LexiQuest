# Approved learner UI implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement task-by-task.

**Goal:** Implement the accepted six-agent UI verdict for ordinary Thai learners.
**Architecture:** Presentation and existing route wiring only; existing application authorities remain source of truth. No backend/schema/catalog changes. Existing task worktree preserves all uncommitted work.
**Tech stack:** Flutter/Dart and existing widget/scenario tests.

## Global constraints
Worktree: C:/Users/Phet/.codex/worktrees/02fa/LexiQuest on codex/pair-matching-pm0-pm8. Latest user explicitly authorizes implementing the completed six-agent verdict. Preserve ALL pre-existing changes. No commits/reset/cleanup/deploy/enrollment/real uploads/security workers. Keep 8/44, frozen contracts, gates, owner/consent/permit boundaries and existing learning/reward authorities. No fake data, no-data is not zero, pending is not success. Use apply_patch for text. Source is current working tree. Tests/build/codegen serialized: you own Flutter test lease while active; do not start servers/device controls. Read AGENTS and applicable TDD/debugging skills. Behavior fixes need meaningful regression RED then GREEN; simple copy/spacing need existing checks not tests mirroring text. Inspect existing equivalents before adding files. Report full file list, exact tests/results, unresolved items in assigned report. No other agents.

## Execution
- [x] Task1: AI/export action correctness and Thai setup — task-1-brief.md (independent review approved; 44 focused, final24 AI regression, analyzer clean)
- [x] Task2: session quickstart, semantic actions, settings/offline — task-2-brief.md (independent review approved; layered204coverage, final15settings, analyzer10files clean;390px real widget capture PASS)
- [x] Task3: five main destinations, grouped learning, secondary paths — task-3-brief.md (134PASS, analyzer8clean, independent reviewAPPROVED;390widgetcapturePASS)
- [x] Task4: progress/quests/rewards/Adventure hierarchy — task-4-brief.md (118PASS, analyzer21clean, independentAPPROVE; correctedrealprofilevisual390PASS)
- [x] Task5: final Thai system-action/headings sweep and deliberate integration traversal — independent review approved; 550 focused PASS, final21 semantic PASS, analyzer50 clean. Final full suite supersedes focused execution evidence.
- [x] Review each task against its current incremental diff and report; fix important findings before next task.
- [x] Integration: canonical generator/check PASS; final Flutter4931 PASS, all current Dart roots analyzer PASS, normal debug APK PASS with identical stable source fingerprint. Backend332 PASS/1existingremote SKIP, Supabase PASS, CLI25layered PASS; 44-feature exact-path join complete. See results report for exclusions and qualified host reuse.
- [x] Visual verification through local artifact:28 captures at390x844 and360x800/text200%, actual routes/actions and simulated IME checks; cramped shop metrics corrected and reviewed. ADB absent; human UX/TalkBack/device performance remain unvalidated.
- [x] Final whole-change review APPROVE (final-system-review.md); 92 current UI/test hashes and APK verified. All changes retained uncommitted; results/checkpoint saved. Native/device/UAT dependencies remain explicitly listed, no deployment or release approval inferred.

## User-required system verification after all UI changes

Latest user explicitly requires a thorough whole-system test AFTER UI implementation is finished. Task-level RED/GREEN checks continue during development; they do not fulfill this final requirement. Complete Task3/Task4 and important review fixes, freeze writers, then execute the current source through the existing complete automated test inventory. Include full Flutter regression, screen/navigation/feature journeys with real taps and back/return behavior, narrow/200% rendering and semantics, gate changes, pending/error/retry and data persistence. Do not only count passing tests: reconcile button/route/feature coverage against the 8/44 catalog and report gaps.

Run available local backend CPU pytest suites (AI, Voice, LM), demo Firebase Auth/Firestore policy tests, local Supabase policy checks, and applicable existing CLI tests after the UI freeze. Reuse known isolated/synthetic fixtures and pinned environments. No production services, real uploads, enrollment or prohibited security workers. Check current device availability then; actual Android/native/performance tests use safe existing owned-fixture install/restore workflow only when a device is available. Human hearing/camera/microphone/TalkBack and representative learner acceptance remain separate until actually observed.

Fix discovered UI/system regressions and rerun affected checks; a relevant source edit invalidates earlier final-source evidence and requires appropriate integration revalidation. Retain original failures and exact logs. Final report must distinguish PASS/FAIL/NOT RUN and explain actual missing device/service dependencies; never claim all 44 physical flows tested from host widget tests.

Decision source: build/verification/ui-design-debate-20260908/verdict.md (historical no-edit scope is superseded by latest user implementation authorization). Task briefs are in build/verification/ui-implementation-20260908. No need ask design approval again.
