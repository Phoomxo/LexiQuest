# LexiQuest P8-G Field Release and Rollout Implementation Plan

**Status:** READY FOR EXECUTION (owner-action gated)

**Scope:** Produce the final release-signed APK with reconciled hashes and
participant documents, pass the final field-release gate, run an owner
smoke test, and roll out to 3 → 10 → 30 participants with bounded evidence
review at each stage.

**Out of scope:** Nothing — P8-G is the terminal package. Once it closes, the
APK is approved for the 30-participant field trial.

**Upstream:** P8-F three-tier matrix and Cloud readiness.

## Hard external dependencies

P8-G requires owner-only actions that cannot be automated:

- the **final** release-signed APK (which may differ from the P8-E APK if any
  correction was made during P8-F);
- **owner smoke-test** approval of that exact APK hash;
- real **private** support/feedback/research references;
- the staged **rollout** to real participants with evidence collection at each
  stage.

## Delivery rules

- The distributed APK is the exact artifact whose SHA-256 the owner approves.
  Any product-code change after approval requires a new APK, new hashes, and
  re-running the affected journeys.
- Participant documents (privacy, consent, install/update, export/deletion,
  known limitations, support) must reconcile with the final APK. If consent
  semantics changed, bump the consent version.
- The final field-release gate must pass before any participant receives the
  APK.
- Each rollout stage records evidence and a bounded crash/data review. A
  release blocker stops the rollout until resolved.
- No data loss, ownership crossover, consent regression, voice-retention
  violation, or secret leak is tolerated at any stage.

## Dependency order

1. Build the final release-signed APK and reconcile documents.
2. Pass the final field-release gate.
3. Owner smoke test.
4. Rollout 3 → 10 → 30.
5. Owner approval and lock.

## Task G1: Final release-signed APK and hashes

Run `tool/cli/package-field-release.ps1` to produce the final APK and
`release-manifest.json` carrying `apkSha256`, `signingCertificateSha256`,
`sourceCommit`/`buildId`, and `modelSha256`. If the APK differs from the
P8-E/P8-F artifact, re-run affected journeys on the mid-tier (and low/high if
P8-F is already complete) against the new hash.

## Task G2: Reconcile participant documents

Review and, if needed, update:

- `docs/field/privacy-and-consent-v1.md` (bump version if consent semantics
  changed — the voice mirror added a separate consent in P8-C);
- `docs/field/research-protocol-v1.md`;
- `docs/field/install-and-update.md`;
- `docs/field/data-export-and-deletion.md`;
- `docs/field/known-limitations.md`;
- `docs/field/feedback-and-support.md`.

Confirm every document references the final APK version and that the voice
mirror retention/consent summary is consistent with P8-C.

## Task G3: Final field-release gate

Run `tool/cli/lib/field-release-evidence.ps1` `Test-LexiQuestFieldReleaseEvidence`
against the assembled evidence. The gate requires, at minimum:

- three device tiers, each with all 14 journeys passing for the exact APK
  SHA-256;
- App Check configured + valid traffic observed + enforced;
- Cloud kill switch verified;
- billing mode recorded (no-billing or budgeted);
- private support and research references (no placeholders);
- endurance ≥30 minutes with zero crash/ANR per tier;
- matching APK, certificate, source, and model hashes.

A failure here blocks the rollout.

## Task G4: Owner smoke test

**Owner action:** install the final APK on a clean device, walk the critical
path (Guest startup, consent, vocabulary, Quiz, SRS, speech/pronunciation,
voice mirror consent + enrollment, Gemini BYOK, export, kill switch), and
record a smoke-test approval tied to the APK SHA-256. The owner must not
approve until the smoke test passes.

## Task G5: Rollout 3 → 10 → 30

1. **3-participant pilot:** distribute the APK, collect crash/analytics/data
   evidence for a bounded window, review. Stop on any release blocker.
2. **10-participant expansion:** after a clean 3-participant review, expand and
   repeat the bounded review.
3. **30-participant expansion:** after a clean 10-participant review, expand to
   the full trial.

Each stage records participant count, evidence window, crash/ANR/data review
outcome, and any blockers.

## Task G6: Owner approval and lock

**Owner action:** explicitly approve the exact APK SHA-256 for distribution,
record the approval in the release evidence, and mark P8-G complete in the
authoritative design. No unresolved release blocker may remain.

## Task G7: Close the bounded P8-G gate

- Create `tool/cli/tests/verify-field-release-rollout.tests.ps1`
- Create `tool/cli/verify-field-release-rollout.ps1`
- Create `docs/development/p8g-field-release-rollout-gate-2026-07-31.md`
- Mark P8-G complete in the authoritative design only after PASS

**Commit:** `test(field): close P8-G field release rollout gate`

## P8-G completion boundary

P8-G is complete only after the final gate passes for the distributed APK
hash, the owner explicitly approves distribution, and no unresolved release
blocker remains. Until then the project may be a valid pilot candidate but is
not field-test ready for the 30-participant trial.
