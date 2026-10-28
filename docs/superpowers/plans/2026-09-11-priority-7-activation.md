# Priority 7 local learning preview implementation plan

Execute inline in the existing worktree using the approved activation design. User's continuation accepts the recommended test-APK approach. Preserve inherited edits; do not commit unrelated work.

Goal: make Matching, ordinary Today and Focus Timer usable through real bootstrap in an opt-in APK.

Architecture: a build-time LEXIQUEST_LEARNING_PREVIEW boolean, false by default, configures the existing bootstrap. Matching uses its internal Pair adapter and enabled delivery. Ordinary Today is enabled through a wrapper around the existing base feature registry, before persisted runtime overrides. Focus Timer shares existing active-time capture; emergency-off stays authoritative. No research/Adventure activation, schema change or new reward authority.

- [ ] Add a real-bootstrap test in test/runtime/app_bootstrap_test.dart that checks Matching delivery, ordinary Today composition, supported quiz timer composition, unchanged research/Adventure states and runtime emergency-off. Run with --dart-define=LEXIQUEST_LEARNING_PREVIEW=true and observe the currently missing activation.
- [ ] Add lib/runtime/learning_preview_feature_registry.dart. Delegate all base states except dailyContinuity hidden, which becomes enabled for the opt-in profile; preserve disabled/emergencyOff. Wire lib/runtime/app_bootstrap.dart's constructor and buildLessonModeRegistry. Existing injected time rollouts retain their emergency-off flags.
- [ ] Run the bootstrap test with the flag and without it. Run touched bootstrap/navigation, Pair, Today and time-tracking suites; verify current changes with analysis and a scoped diff.
- [ ] Build and archive a preview APK with the flag, cloud/research off for local device work, distinct build metadata and SHA256. Use the existing owned synthetic manual fixture for actual vivo checks rather than clearing learner data. Verify Matching finish/reopen, Today navigation and timer controls.
- [ ] Record exact outcomes and unresolved device dependencies. Proceed to priority 8 only after this priority's verification is complete or an external acceptance dependency is explicitly recorded.

Baseline: 54 selected component tests passed on 2026-09-11. No claim of feature activation follows from that baseline alone.

Completion checkpoint: all five implementation steps above are satisfied for
the opt-in local preview. Exact current checks, corrected failures, R2 APK
hashes and actual vivo results are recorded in
`docs/development/2026-09-11-priority-7-preview-results.md`.
Priority 8 physical checks have started; human audibility/transcript acceptance
is pending in `docs/development/2026-09-11-priority-8-device-checkpoint.md`.
