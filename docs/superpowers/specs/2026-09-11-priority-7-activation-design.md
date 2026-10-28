# Priority 7 activation design and priorities 8–12 sequence

User closed priorities 1–6 and authorized priorities 7–12 in order. Worktree: C:/Users/Phet/.codex/worktrees/02fa/LexiQuest; branch codex/pair-matching-pm0-pm8. Preserve inherited changes. No separate task, deployment, real research enrollment or paid service purchase is authorized.

## Current findings

- Matching has existing PM0–PM8 implementation and compatibility tests. buildLessonModeRegistry defaults matchingDeliveryState to implementedOff and internalPairMatching to false. Delivery must use the existing Pair implementation and canonical learning authority.
- Today has existing home navigation and dependencies, but fieldDefaults hides dailyContinuity and adventureMotivation. Distinguish ordinary Today from the Adventure Today host; enabling ordinary Today must not implicitly enable research or unrelated Adventure functionality.
- Focus Timer has tested controller/UI, but bootstrap defaults both learning time capture and timer rollout to implementedOff. Timer composition requires trustworthy active effort, a supported adapter and a registered feature. Preserve those checks and the shared time authority.

## Recommended implementation

Provide an explicit local test-build activation configuration for these three capabilities, threaded through the production bootstrap and existing registries. Retain existing unavailable-dependency and emergency-off behavior. Enable ordinary Today; preserve Adventure's existing separate authorization. Use existing Pair routes, persistence and reward reconciliation. Enable Focus Timer only with the existing active-time capture implementation and supported modes. Do not introduce new database or reward authorities.

Alternative: change next-version defaults directly, which exposes the features to every installation of that build. Another alternative is test-only dependency injection, which is insufficient because the ordinary APK bootstrap remains untested. User preference between a test-build profile and next-version defaults was requested; do not silently treat local activation as external rollout approval.

## Acceptance

Verify actual bootstrap-to-route composition, feature-off and emergency-off behavior, owned persistence/reopen, Matching completion and reward idempotency, Today resume/review navigation, and Focus start/pause/resume/finish without double counting. Run focused tests before integration checks. Build a locally installable APK and verify the three flows on vivo with synthetic data. Retain the accepted prior endurance duration; no fresh three-hour requirement.

## Baseline evidence

2026-09-11: flutter test --no-pub on pair_matching_compatibility_rollout_test.dart, today_experience_host_test.dart, focus_timer_controller_test.dart and focus_timer_widget_test.dart: 54 passed, exit 0 (exec session 65745). No app source changes in this audit. This is component evidence, not activation acceptance.

## Subsequent sequence

8. Verify existing voice/microphone/Shadowing dependencies and real vivo flows; resolve bounded defects before advancing.
9. Audit lesson/CEFR content and prepare a validated starter set with provenance and explicit content-review limitations.
10. Connect the existing AI Tutor service and evaluate grounded answer quality; request any required service access/cost decision using a concrete configuration.
11. Complete owner-scoped cross-device sync including offline replay and conflict cases; use existing schema/export/deletion/policy contracts. A second physical device or supported independent client may be an external acceptance dependency.
12. Audit camera evaluation data first, establish a held-out baseline, then fine-tune only with authorized data and available compute. Do not claim improved accuracy without held-out comparison or obtain paid compute implicitly.

No work from 8–12 is declared complete by this design. Proceed sequentially and record external dependencies at their actual boundary.
