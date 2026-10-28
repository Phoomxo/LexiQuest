# R15 Review Fixes Implementation Plan

> Execute inline, one fix at a time, using executing-plans. No subagents. User approved implementing the four findings from the combined review.

**Goal:** Close F1–F4 on `feature/r15-integration-continuation` starting at `f4eebb895836349fbf8e9960312a78bad524d462`.

**Architecture:** Reuse the current speech session cancellation API and add presentation attempt guards. Conservatively hash shared Flutter dependencies without widening executed suites. Make camera freeze evidence self-contained and reproducible; require a pinned baseline label mapping and an explicit acceptance decision.

**Tech stack:** Flutter/Dart, PowerShell, Python standard library; no new dependencies.

## Constraints and decisions

- Preserve 8/44, frozen evidence contracts, canonical stores/rewards and default-off research. No deployment, merge, enrollment, training or shipped model changes.
- Preserve seven pre-existing generated registrant changes. Existing worktree is already isolated.
- Review repair directions already approved; do not restart design/permission gates. Retain descriptive evaluator scope and external-evidence limitations.
- Choose shared frontend hashing over narrower hand-maintained regexes: more cache invalidations are preferable to stale passes. Test selection remains bounded.
- Choose recomputation from retained validation predictions over superficial schema-only checks: verify both hashes and metric/count consistency. Old incomplete freezes fail closed; never relabel an opened test as fresh.
- Camera baseline predictions carry `baseline` (raw label) and `baseline_accepted` (bool); config pins `baseline_label_map` into canonical book/bottle/chair/cup/unknown labels. Unknown labels absent from the map are errors, not rejection.

## Task 1 — F1: conversation/speech boundary

Files: `lib/screens/ai_tutor_screen.dart`, `test/screens/ai_tutor_screen_test.dart`.

- [x] Add regression using the existing fake gateway: start pending speech, change scenario/level/intent/new chat, deliver old final/error/status and verify the new draft/state survive; fresh microphone still works. Cover pending start and cancellation failure.
- [x] Run `verify-scope.ps1 -Level Targeted -Area AI -TestTargets test/screens/ai_tutor_screen_test.dart -TestName 'R15 review'`; require behavioral RED.
- [x] Invalidate/cancel speech synchronously during reset. Guard all asynchronous speech completions by attempt epoch, session identity and conversation id. Preserve shared speech policy.
- [x] Run the focused regressions and affected AI/speech suite.

## Task 2 — F2: reliable fingerprints

Files: `tool/cli/verify-scope.ps1`, `tool/cli/tests/r15-scope.tests.ps1`.

- [x] Add temporary Git-repository regression calling actual fingerprint functions: change feature/contract/config/asset under unchanged HEAD, assert fingerprint changes; unchanged input stays stable. Check explicit targets and all frontend areas.
- [x] Run `powershell -NoProfile -File tool/cli/tests/r15-scope.tests.ps1`; require RED before implementation.
- [x] Share lib/test/assets/tool/config input coverage across frontend areas; preserve backend and platform inputs and exact test selection. Fix the touched Runtime gate's nonexistent CLI-test reference to the existing r15-scope test.
- [x] Run CLI regression and inspect generated command targets without launching unrelated suites.

## Task 3 — F3/F4: camera evaluation evidence

Files: `tools/camera_accuracy.py`, `tools/test_camera_accuracy.py`.

- [x] Add malformed/missing freeze, validation hash/count/identity mismatch and nonfinite metric tests; assert ValueError instead of evaluated output. Add unmapped baseline and explicit acceptance tests in validation/test phases.
- [x] Run `python -B -m unittest discover -s tools -p test_camera_accuracy.py`; require behavioral RED.
- [x] Freeze versioned validation predictions with hashes; at evaluation recompute validation metrics from pinned rows/config, require exact equality and coverage before test metrics. Validate input types at boundaries.
- [x] Validate pinned baseline mapping and bool acceptance; calculate known correctness only for accepted mapped answers and unknown false acceptance from the explicit flag.
- [x] Verify CLI malformed freezes produce no report, single-open receipts remain conservative, old incomplete freeze rejected, retained-baseline and training preflight unchanged. Run full camera evaluator test module.

## Integration and handoff

- [x] Freeze current source after edits. Run affected AI/speech/provider regressions, CLI/Python gates and scoped analyzer. Reuse unaffected previous R15 evidence only as historical evidence.
- [x] Review semantic diff and guardrail compliance; fix any demonstrated issues. No source writers during integration tests.
- [x] Save verification report and replace active checkpoint with current source/diff, exact outcomes, process status and next step. Keep original review report historical.
- [x] Leave verified changes on the existing integration branch for review; no push/merge or unrelated cleanup.
