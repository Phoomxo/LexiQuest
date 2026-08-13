# LexiQuest device and beta evidence matrix

**Recorded:** 2026-08-13

**Decision:** BLOCKED-EXTERNAL — no field-distribution approval

This matrix is bound to the verified internal Task 10 artifact. It records
missing evidence as missing; host tests, emulators, and synthetic journeys are
not substituted for physical-device, provider-console, private-channel, or
owner evidence.

## Artifact boundary

- Artifact source:
  `c199d501adb8b83d0a1b9e7bd529c9f123f168f9`
- APK SHA-256:
  `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158`
- Signing-certificate SHA-256:
  `E1B00E17896BFB73FE0DC42429768B966465213D49A8A5165DE06688CC8FDC1F`
- Version/build: `1.0.0+13` / `c199d501adb8`
- Model SHA-256:
  `D3949E8A3556C79739CB675E0BE7476503BCCE76938031C6A1048E13E0CB7D8B`
- Package: `build/field-release`
- Ignored evidence shell: `field/evidence/release-evidence.json`

The package and its release model runtime passed independent verification
before this matrix was created.

## Physical-device matrix

| Tier | Required evidence | Status | Evidence |
|---|---|---|---|
| Low | Physical Android device; exact APK/certificate/model hashes; all mandatory journeys; CPU/XNNPACK benchmark; allowlisted GPU result or honest N/A; at least 30-minute endurance with crash, ANR, memory, battery, and temperature measurements | blocked-external | No device record supplied |
| Mid | Same exact-artifact, journey, benchmark, and endurance contract | blocked-external | No device record supplied |
| High | Same exact-artifact, journey, benchmark, and endurance contract | blocked-external | No device record supplied |

Every device must complete consent/guest startup, offline vocabulary, learning
core, offline restart and sync, account lifecycle, model lifecycle, camera
scanner, speech/TTS/pronunciation, Gemini BYOK, clean install, upgrade install,
reboot/foreground/background, cloud kill switch, and data export. Each result
requires a private evidence reference. No such physical-device observation is
currently present.

## Provider and beta operations

| Gate | Status | Missing external evidence |
|---|---|---|
| App Check configuration | blocked-external | Configuration record |
| Valid signed-release App Check traffic | blocked-external | Observed traffic record |
| App Check enforcement | blocked-external | Controlled enforcement record |
| Hosted asset links | blocked-external | Verified hosted asset-link record |
| Cloud kill switch | blocked-external | Controlled production drill record |
| Shared-infrastructure cost guard | blocked-external | Verified 50/80/100 budget alerts or owner-controlled no-billing proof |
| Feedback channel | blocked-external | Real private channel reference |
| Support channel | blocked-external | Real private channel reference |
| Research protocol | blocked-external | Approved private protocol reference |
| Owner smoke test and approval | blocked-external | Approval record tied to the exact APK SHA-256 |
| Beta cohort/crash-free/sync/provider-cost observations | blocked-external | Genuine beta operations records |
| Rollback drill | blocked-external | Exact-artifact rollback observation |

## Field verifier observation

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/verify-field-release.ps1 `
  -EvidencePath field/evidence/release-evidence.json `
  -ParticipantPackagePath build/field-release
```

Result: `blocked-external` (exit 1). Package signature, fingerprint, artifact
metadata, APK hash, and release model runtime verified first. The evidence gate
then rejected every missing Cloud control/reference, all three missing physical
device tiers, the three pending private references, and missing owner approval.
The gate did not run the final product regression phase because external field
evidence failed first.

## Blocker report

- **Observed:** a genuine signed package exists and verifies, but no physical
  device, provider-console, private-channel, beta-operations, or owner-approval
  records are available for its exact hash.
- **Expected:** three distinct physical device records plus all provider,
  operations, private-reference, and exact-hash owner-approval fields pass the
  closed field-evidence validator.
- **Evidence path:** `field/evidence/release-evidence.json` (ignored, pending
  shell) and this matrix.
- **Attempts:** one evidence-shell generation and one field-gate observation;
  no missing field was converted to PASS and no historical artifact was reused.
- **Smallest external action:** conduct and record the low/mid/high exact-APK
  device matrix, configure and evidence the Cloud controls/cost guard, provide
  real private references, then obtain owner approval for this APK hash.
- **Unaffected work:** local release-readiness reconciliation and a truthful
  `NOT READY` final acceptance record can proceed without fabricating evidence.
