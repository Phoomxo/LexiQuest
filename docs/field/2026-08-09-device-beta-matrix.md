# LexiQuest device and beta evidence matrix

**Recorded:** 2026-08-13

**Decision:** FAIL / BLOCKED-EXTERNAL — no field-distribution approval

This matrix is bound to the verified internal Task 10 artifact. It records
missing evidence as missing; host tests, emulators, and synthetic journeys are
not substituted for physical-device, provider-console, private-channel, or
owner evidence.

## Artifact boundary

- Artifact source:
  `4e4b398e5dc19a29a4f81953e16b084bfe0400d3`
- APK SHA-256:
  `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A`
- Signing-certificate SHA-256:
  `E1B00E17896BFB73FE0DC42429768B966465213D49A8A5165DE06688CC8FDC1F`
- Version/build: `1.0.0+14` / `4e4b398e5dc1`
- Model SHA-256:
  `D3949E8A3556C79739CB675E0BE7476503BCCE76938031C6A1048E13E0CB7D8B`
- Package: `build/field-release`
- Ignored evidence shell: `field/evidence/release-evidence.json`

The package and its release model runtime passed independent verification for
artifact source `4e4b398`. Only declared final-metadata documentation follows
that frozen source.

## Physical-device matrix

| Tier | Required evidence | Status | Evidence |
|---|---|---|---|
| Low | Physical Android device; exact APK/certificate/model hashes; all mandatory journeys; CPU/XNNPACK benchmark; allowlisted GPU result or honest N/A; at least 30-minute endurance with crash, ANR, memory, battery, and temperature measurements | blocked-external | No device record; no attached device was visible, so no tier could be measured |
| Mid | Same exact-artifact, journey, benchmark, and endurance contract | blocked-external | No device record; no attached device was visible, so no tier could be measured |
| High | Same exact-artifact, journey, benchmark, and endurance contract | blocked-external | No device record; no attached device was visible, so no tier could be measured |

Every device must complete consent/guest startup, offline vocabulary, learning
core, offline restart and sync, account lifecycle, model lifecycle, camera
scanner, speech/TTS/pronunciation, Gemini BYOK, clean install, upgrade install,
reboot/foreground/background, cloud kill switch, and data export. Each result
requires a private evidence reference. No such physical-device observation is
currently present.

On 2026-08-13 the authorized collector preflight saw zero entries from `adb
devices`. Starting the ADB server once produced the same zero-device state, and
an independent Windows present-device query found zero Android, ADB, or MTP
interfaces. No serial, model, tier, install, journey, or benchmark claim was
created. Exactly three distinct tier records are still missing; one physical
device may fill at most the one tier that its measured RAM/hardware actually
satisfies after the host sees it.

## Provider and beta operations

| Gate | Status | Missing external evidence |
|---|---|---|
| App Check configuration | blocked-external | Configuration record |
| Valid signed-release App Check traffic | blocked-external | Observed traffic record |
| App Check enforcement | blocked-external | Controlled enforcement record |
| Hosted asset links | blocked-external | Verified hosted asset-link record |
| Cloud kill switch | blocked-external | Controlled production drill record |
| Shared-infrastructure cost guard | blocked-external | Current measured project-total cost at 0-100 THB/month (or verified no-billing zero), exact 100 THB ceiling, and 50/80/100 alerts when billed |
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

Result: `blocked-external` is expected until genuine records exist. The v2
evidence shell remains `pending` for Cloud controls/cost, all three physical
tiers, private references, beta/rollback, and owner approval. The verifier
binds every accepted record to source `4e4b398`, the +14 APK, a signed raw
source envelope, and (for device outcomes) the revalidated physical collector
receipt.

## Blocker report

- **Observed:** a genuine current signed package exists and verifies. The host
  exposes no Android/ADB/MTP device interface, and no provider-console,
  private-channel, beta-operations, rollback, or owner-approval records are
  available for this candidate.
- **Expected:** three distinct physical device records plus all provider,
  operations, private-reference, and exact-hash owner-approval fields pass the
  closed field-evidence validator.
- **Evidence path:** `field/evidence/release-evidence.json` (ignored, pending
  shell) and this matrix.
- **Attempts:** ADB enumeration, one ADB server start, and one independent PnP
  interface check; no missing field was converted to PASS.
- **Smallest action sequence:** reconnect/authorize one Android device in data
  mode, collect only its measured tier, obtain two other distinct tiers, collect
  signed content-addressed provider/cost/beta/rollback records, and obtain owner
  approval for that exact APK hash.
- **Unaffected work:** local release-readiness reconciliation and a truthful
  `NOT READY` final acceptance record can proceed without fabricating evidence.
