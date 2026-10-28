# PM8 composition correction — independent bounded review

Reviewed 2026-09-07 in `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`.

Exact verified HEAD: `94c1e97fea5097af144b63adfdf9ab2e5f277bee`.

## Identity and scope

The raw correction packet SHA-256 is `08180daa4b610c733bae12a3a4f53267dde88afad2c81ebd22ceb085786cc9a0`; manifest SHA-256 is `c979c028c3fafcae4e70c4d85e2df98c2d6b97c9e5b818b7680d8473dbf4cb9d`. Both matched the dispatch. All 11 current-file hashes and 11 saved before-file hashes matched the manifest. Read the complete 11-file delta, active local verification record and review plan, plus named current evidence adapter, matching adapter, coordinator, bootstrap, legacy wrapper/renderer and disposition-test dependencies. Unrelated dirty docs and generated registrants were outside this correction review. No source/test/portable-doc/Git mutation, Flutter/Dart/pub/build/dependency/scanner command was performed by this reviewer.

## Findings

- **Resolved, P1 — caller-composed evidence authority was discarded.** The runtime and unavailable-session constructors now require `currentActivityEvidence` and reject a different `LearningUseCases` object before use. Ordinary host preparation forwards `runtime.currentActivityEvidence` through `MatchingModeAdapter.preparePairSession` into the coordinator without replacement; configured-unavailable recovery forwards the same object through `PairMatchingUnavailableSession` into coordinator restoration. Neither production path constructs an adapter or default Legacy provider. Owner checks, lifecycle admission/recovery callbacks, route lease reservation, configuration reset handling and canonical unavailable completion are unchanged by this delta.
- **Resolved, P2 — architecture test inspected the old renderer location.** The guard explicitly follows `MatchingModeScreen` to `LegacyMatchingModeScreen`, checks its import/dispatch/adapter forwarding, and adds the extracted renderer to the prohibited-constructor checks. The actual renderer resolves `widget.evidenceAdapter ?? dependencies?.currentActivityEvidence` and errors if absent. The production constructor allowlist remains exactly the adapter declaration and bootstrap composition; the two erroneous Pair locations were not allowlisted away.
- **No open actionable findings in the 11-file correction.** Caller changes use the same learning authority, and AppDependencies test compositions share the runtime adapter. The measurement fixture retains real persisted rollout and assigned research-state providers; its new adapter shares those providers with the existing real repository/configuration composition. The helper for fault-injected LearningUseCases builds against that exact learning object while preserving the fixture's persisted providers. No assertions or research authority checks were removed or relaxed.

## Test assessment and inspected evidence

The new host widget test actually selects and records a pair through the recovered UI. It asserts the custom generated attempt ID, actual rollout-owner call, and actual research-provider owner/input/exact UTC occurrence call. Thus it detects replacing the injected adapter with a new adapter even if that replacement points at the same learning object. The constructor test rejects mismatched authority in both runtime and unavailable disposition constructors. Existing disposition cases still assert enforced evidence, immutable committed receipts, no first-write retry after withdrawal, retained frozen pending identity, owner continuity and ordinary baseline continuation.

Unavailable recovery intentionally restores frozen contexts without reconsulting mutable rollout/research providers (`CurrentActivityEvidenceAdapter.restore` / `_resolveAndMemoize`); expecting new provider calls on that path would conflict with exact frozen recovery. The corrected object flow preserves both the composed instance and that existing recovery contract.

Inspected actual `.superpowers/sdd/pm8-composition-red-20260907T041931503.log` and metadata: architecture-only command exited 1 in 9.0142459 seconds, 6 passed / 2 failed, with the exact constructor-allowlist and old-wrapper-location failures described above. Inspected actual focused log `.superpowers/sdd/pm8-composition-focused-20260907T042357674.log` and metadata: architecture plus host tests exited 0 in 55.464505 seconds, 51 passed / 0 failed, including both added tests. Focused `git diff --check` for the 11 paths exited 0; Git emitted existing LF-to-CRLF notices, without whitespace errors.

## Verdict

**Spec: PASS for the bounded composition correction. Quality: PASS for the bounded composition correction.** The two failures are addressed at their actual causes, without widening the production constructor boundary or weakening measurement authority.

This is source review plus inspection of the recorded focused checks, not an independent full-suite execution. Broader affected tests, analyzer, repeated final default/serial suites, source fingerprint and final APK remain root-owned release evidence; this report does not claim those pending gates passed or authorize rollout.

## Follow-up exposed by covering run (outside frozen 11-file delta)

The covering log subsequently showed failures in `pair_measurement_boundary_test.dart`; no covering-suite pass is claimed. Independent inspection confirms that line 323 compares the points ledger immediately after **normal learning Pair** against the earlier prior-recall-only baseline, before the actual Practice Replay action. That equality is not a valid Replay isolation assertion. Existing `evidence_eligibility_policy.dart` gives recognition XP/coins `protocolControlled`; the real mapped assigned-state provider sets `engagementAllowed: true`, and the canonical repository rebuilds XP when its decision permits it. Recognition's SRS denial remains unconditional. The actual full `_primaryEffects` equality after Replay at line 355 uses the proper post-normal-Pair baseline and must remain intact.

This is an open **P2 test expectation correction outside the reviewed packet**, not a defect in forwarding the composed provider. Appropriate bounded correction: preserve exact SRS equality and all prior ledger rows, verify the exact additional ordinary-Pair ledger rows against eligible correct recognition and canonical decisions, then preserve the whole Replay before/after comparison. Do not suppress ordinary protocol-authorized rewards, alter production eligibility, or remove research isolation assertions to force green. Root will provide any twelfth-file correction separately; it is not covered by this 11-file PASS.
