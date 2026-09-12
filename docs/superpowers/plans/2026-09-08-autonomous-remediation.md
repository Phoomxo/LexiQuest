# Autonomous Learner Remediation Implementation Plan

> Continuation 2026-09-09: the user authorized repairing the subsequent 29-finding review. Current execution follows [the revised remediation plan](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/docs/superpowers/plans/2026-09-09-review-remediation.md). Checkboxes below are historical; use the new execution ledger for current closure status.

> For agentic workers: use subagent-driven-development, one writer per file and root-only serialized Flutter/Dart/build/ADB execution. This implements the user's explicit instruction following the 13-item current-state audit; no repeat permission gate for the same repairs.

**Goal:** repair reproducible learner defects and deliver/test missing local content without requiring user participation.

**Architecture:** preserve canonical learning/reward/content authorities. Package a bounded original starter corpus through the existing immutable reviewed-content contract and make it reachable using existing vocabulary/catalog flows. The scanner must present its highest-ranked eligible prediction honestly, never substitute a lower prediction merely because it has a translation. Unknown-object/low-confidence outcomes remain distinct from invalid images. Reading stage 2 shows the same passage without stage-1 cues. Profile changes must follow measured build/raster evidence and retain the 16.7ms p95 budget.

**Tech Stack:** existing Flutter/Dart/Drift and Android toolchain, no new dependency or schema migration by default.

## Global constraints

- Existing 02fa worktree, branch codex/pair-matching-pm0-pm8, HEAD788e90e62b1694c20945734787723c168b6a6ab2. Preserve inherited dirty work; baseline copies of1498 inputs at build/verification/autonomous-remediation-20260908/baseline.
- Preserve8/44, schema24/48tables, EvidenceContext/EventEnvelopeV2, owner/reward/consent rules. No live research, cloud upload, deployment or unsolicited feature activation.
- Human UAT/hearing/speaking/TalkBack, real notification permission, external credentials/approved research instruments remain deferred. No claim of measured>90% accuracy without an independent dataset and calibration evidence.
- Original educational content may be authored and internally reviewed by separate agents; record editorial review honestly, not expert/teacher/ethics certification. Never weaken requireVerified or mark unreviewed input approved on demand.
- Every behavioral fix begins with a failing regression through existing public interfaces. Root executes RED, signals writers to implement, freezes relevant writers, then GREEN. Review source deltas against this turn's captured baseline rather than HEAD alone.

## M1: Reading and learner-facing Thai copy

Owner: ui_reading_remediation. Files: lib/screens/associative_reading_session_screen.dart; lib/features/learning/application/cloze_mode_adapter.dart; lib/features/learning/application/definition_quiz_mode_adapter.dart; lib/features/rewards/domain/reward_models.dart; lib/screens/learning_calendar_screen.dart; existing corresponding tests discovered before edit.

- [ ] Add regression that enters reading stage2 and still finds the exact passage, without the stage1 target-word cue.
- [ ] Root run focused RED and retain output.
- [ ] In stage2 render instruction, spacing and Text(widget.passageText) with existing semantics/layout; do not change stage progression/evidence.
- [ ] Translate skipped-content/hint guidance and Material3/active descriptions to plain Thai. Preserve skip reasons/eligibility and English lesson content. Verify existing relevant tests without mirror-only tests for copy edits.
- [ ] Root format/focused GREEN, independently review diff and native screenshots.

## M2: Honest scanner outcomes

Owner: scanner_remediation. Files: lib/features/media_practice/application/object_scanner_use_cases.dart; lib/features/media_practice/domain/camera_gateway.dart (only if actual failure enum located there); lib/screens/object_scanner_screen.dart; existing scanner/domain/widget tests and reviewed object vocabulary catalog/tests only after path discovery.

- [ ] Add RED for highest prediction lacking a vocabulary match while a lower result has one, and for no confident prediction vs invalid encoded image.
- [ ] Root execute RED; then implement top prediction presentation with optional exact reviewed mapping, separate actionable low-confidence outcome and truthful model-score label. Preserve cancellation/model/capture/accept idempotency.
- [ ] Expand reviewed vocabulary/aliases only for correct unambiguous English–Thai names in the agreed limited groups, keeping unknown labels unknown and preserving substring-rejection tests.
- [ ] Root focused GREEN; separate review for display mapping and error branches. Do not alter the model's probabilities to manufacture90%.

## M3: Real packaged starter content

Owner: recognition_readiness_audit. Files: lib/runtime/app_bootstrap.dart; pubspec.yaml; existing learning-pack/content/vocabulary repository and bootstrap tests; new corpus/catalog files only after checking for equivalents. No edits to M1 adapters or M2 scanner files.

- [ ] Trace existing provisioning/catalog/owner/deletion rules; report exact new-file interfaces before creating them.
- [ ] Write RED exercising ordinary production bootstrap/content loader without injected lexical bytes: usable reviewed Cloze and Definition items must exist, be visible via normal vocabulary selection, and remain unchanged after reopening bootstrap.
- [ ] Root execute RED. Implement a small original internally reviewed beginner corpus (bounded starter set, not a claim of full curriculum), canonical identity/revision/hash/manifests and package assets. Integrate through existing canonical authorities without new schema or bypassing reviewers/checksums.
- [ ] Test missing/corrupted/revision-conflict rejection, bootstrap replay, owner isolation and deletion semantics relevant to new provisioning. Independent agent checks sentence grammar, unique blank, definitions, translations and metadata integrity.
- [ ] Root GREEN plus actual APK archive asset inspection and a native route using production content loading rather than synthetic lexical overrides.

## M4: Adventure performance

Owner: root. Files: integration_test/adventure_performance_profile_test.dart (oracle retained), existing ignored diagnostic probe/runner, lib/features/adventure/presentation/adventure_hub_screen.dart and implicated widgets only after measurement.

- [ ] Preserve current failure22.574ms p95/16.7budget and actual profile APK evidence.
- [ ] Use existing build/raster split probe with current source/build/driver identity and synthetic lifecycle; diagnose one concrete bottleneck before changing production.
- [ ] Make a targeted rendering correction preserving semantics, motion preference and map/list parity; validate focused host tests.
- [ ] Rerun original AOT physical-device profile with unchanged budgets, exact frame coverage and authority invariants; compare measured result, not debug host timing.

## M5: Integration and remaining independent acceptance

- [ ] Freeze all writers; format/analyze actual source roots, full regression, contract/generated-plan checks, relevant host journeys and ordinary APK on a recorded current snapshot. Refresh generated artifacts through their generators only.
- [ ] Re-pin reviewed native wrappers to current fixture/source/build records; execute selected native routes, content, persistence and export checks serially, preserving failures and restoring exact predecessor APK without data clear/uninstall.
- [ ] Improve independently executable coverage for activity completion, export save/readback, network/lifecycle and display variants where controllable without user permission. Keep new fixture scope explicit and cleanup owned.
- [ ] Implement/run real-clock180-minute endurance when its workload and durable recovery harness are verified; elapsed idle waiting alone is not acceptance. Retain meaningful checkpoints and stop only affected work if a real external dependency blocks execution.
- [ ] Reconcile stale plan/schema status documentation against actual delivered code and verified results; keep intentional B/C future decisions and release/research approval separate from defects.
- [ ] Save final checkpoint: source identity, changed files, precise pass/fail/not-run evidence, installed APK, active processes and remaining executable work.

## Design choices and review

Selected: bounded packaged content using existing contracts, explicit scanner uncertainty, targeted measured UI fixes. Rejected for this repair: unrestricted generated lessons or broad new cloud/social architecture (larger authority/cost/quality scope); cosmetic confidence inflation or lower benchmark thresholds (would conceal failures). Current instruction authorizes this local implementation and testing. No missing user decision prevents M1–M4 investigation/repair; paid training, real-photo collection, release and research activation remain separate.
