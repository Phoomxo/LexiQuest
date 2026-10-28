# LexiQuest P8-F Device Matrix and Cloud Readiness Implementation Plan

**Status:** READY FOR EXECUTION (owner-action checklist; blocked on hardware)

**Scope:** Run the same 14 mandatory journeys on one low-tier and one
high-tier physical Android device in addition to the accepted mid-tier vivo
V2041, verify CPU/XNNPACK and GPU allowlisting, achieve a valid App Check
production token and enforce Firestore only after acceptance, confirm the Cloud
kill switch and the zero-billing boundary, and record private support and
research-protocol references.

**Out of scope:** Participant rollout (P8-G). P8-F only proves the three-tier
matrix and Cloud readiness; it does not distribute the APK.

**Upstream:** P8-E mid-tier completion.

## Hard external dependencies

P8-F is predominantly an owner-action checklist because it requires physical
hardware and production Cloud configuration that cannot be simulated:

- one **low-tier** physical Android device (e.g. ≤4 GB RAM, Android 11–12);
- one **high-tier** physical Android device (e.g. ≥8 GB RAM, Android 14+);
- a **Play Console / Firebase linkage** that yields a valid production App
  Check token;
- **private** support, feedback, and research-protocol channels whose
  references cannot be committed as placeholders.

Until those exist, P8-F cannot close. No device evidence may be fabricated or
emulated (design §13, §15).

## Delivery rules

- Every journey is executed on a physical device with the exact release-signed
  APK produced in P8-E Task E1. The APK SHA-256 must match across all tiers.
- Each device produces one record per journey plus an endurance record
  (≥30 minutes, zero crash/ANR) tied to the APK hash.
- GPU is enabled only for an exact tested allowlist; otherwise CPU/XNNPACK is
  preferred. No assumed GPU acceleration.
- App Check is enforced on Firestore only after a valid production token is
  observed; the bounded acceptance pass is run a second time post-enforcement.
- The Cloud kill switch must leave offline learning uninterrupted on every
  tier.
- Billing remains a zero-paid-cost boundary (no billing account), or
  documented 50/80/100 alerts exist if billing is enabled.
- Private references must start with `private:` and must not match any
  placeholder pattern.

## Dependency order

1. Acquire low-tier and high-tier physical devices.
2. Run the 14 journeys + endurance on each new tier.
3. Verify CPU/XNNPACK and GPU allowlisting per tier.
4. Achieve valid App Check production acceptance.
5. Verify the Cloud kill switch and billing boundary.
6. Record private support and research references.
7. Bounded P8-F gate and evidence.

## Task F1: Low-tier physical device matrix

**Owner action:** provide one low-tier physical Android device. Install the
release-signed APK, run all 14 journeys, and run a ≥30-minute endurance
session. Record crash/ANR/RSS/battery/temperature. Expect tighter resource
limits; confirm the app degrades gracefully (CPU inference, smaller caches).

## Task F2: Mid-tier (vivo V2041) re-acceptance

Re-use the P8-E mid-tier evidence, confirming the APK SHA-256 is unchanged. If
P8-G produces a new final APK, re-run mid-tier journeys against that hash.

## Task F3: High-tier physical device matrix

**Owner action:** provide one high-tier physical Android device. Run all 14
journeys and endurance. Confirm GPU is used only where allowlisted and tested;
otherwise prefer CPU/XNNPACK.

## Task F4: CPU/XNNPACK and GPU allowlisting

Record CPU and XNNPACK median latency per tier. Enable GPU only for an exact
tested allowlist; record the rationale for any tier that keeps CPU preferred
(the mid-tier baseline prefers CPU at 33.7 ms median).

## Task F5: App Check production acceptance

1. With enforcement OFF, observe network traffic and confirm a valid
   production App Check token appears for the release-signed APK.
2. After a valid token is observed, set Firestore enforcement ON.
3. Run a second bounded acceptance pass: offline learning still works,
   synchronization carries a valid token, and no invalid/unknown token is
   accepted.

Currently App Check is UNENFORCED because the baseline produced an
invalid/unknown token. This task is a hard P8-G dependency.

**Owner action:** complete the Play Console / Firebase linkage that produces a
valid production token.

## Task F6: Cloud kill switch and billing boundary

Run the `cloudKillSwitch` journey on every tier and confirm offline learning
continues. Run `tool/cli/configure-firebase-budget.cjs` and record the
`billingMode`: either `noBillingAccount` (zero-paid-cost boundary) or
`budgeted` with 50/80/100 alerts.

## Task F7: Private support and research references

**Owner action:** create real private support, feedback, and research-protocol
channels and record their references (starting with `private:`) in the
release-evidence JSON. Replace the current placeholders in
`docs/field/release-evidence-template.json`. Note that
`research-protocol-v1.md` is a technical protocol, not an ethics-board
approval; institutional approval is a separate external dependency.

## Task F8: Close the bounded P8-F gate

- Create `tool/cli/tests/verify-device-matrix.tests.ps1`
- Create `tool/cli/verify-device-matrix.ps1`
- Create `docs/development/p8f-device-matrix-gate-2026-07-31.md`
- Mark P8-F complete in the authoritative design only after PASS

The gate runs each phase once and, critically, validates the final
field-release evidence schema: exactly three tiers (`low`, `mid`, `high`),
each with 14 journeys tied to the exact APK hash, App Check configured +
observed + enforced, kill switch verified, billing mode recorded, and private
references present.

**Commit:** `test(field): close P8-F device matrix gate`

## P8-F completion boundary

P8-F is complete only after the accepted gate proves the three-tier physical
matrix passes for the exact APK, App Check is enforced only after a valid
production token, GPU is enabled only where tested, and the Cloud kill switch
and billing boundary are verified. A passing gate does not distribute the APK
or approve the rollout.
