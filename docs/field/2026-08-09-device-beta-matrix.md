# LexiQuest device and beta evidence matrix

**Recorded:** 2026-08-13

**Decision:** FAIL / BLOCKED-EXTERNAL — no field-distribution approval

This matrix is bound to the verified internal Task 10 artifact. It records
missing evidence as missing; host tests, emulators, and synthetic journeys are
not substituted for physical-device, provider-console, private-channel, or
owner evidence.

## Artifact boundary

- Artifact source:
  `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1`
- APK SHA-256:
  `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C`
- Signing-certificate SHA-256:
  `E1B00E17896BFB73FE0DC42429768B966465213D49A8A5165DE06688CC8FDC1F`
- Version/build: `1.0.0+14` / `c55f7bb13705`
- Model SHA-256:
  `D3949E8A3556C79739CB675E0BE7476503BCCE76938031C6A1048E13E0CB7D8B`
- Package: `build/field-release`
- Ignored evidence shell: `field/evidence/release-evidence.json`

The package and its release model runtime passed independent verification for
artifact source `c55f7bb`. Only declared final-metadata documentation follows
that frozen source.

## Physical-device matrix

| Tier | Required evidence | Status | Evidence |
|---|---|---|---|
| Low | Physical Android device; exact APK/certificate/model hashes; all mandatory journeys; CPU/XNNPACK benchmark; allowlisted GPU result or honest N/A; at least 30-minute endurance with crash, ANR, memory, battery, and temperature measurements | blocked-external | No low-tier device record; the connected device measured as mid tier and cannot be reused for this row |
| Mid | Same exact-artifact, journey, benchmark, and endurance contract | blocked-external | Signed physical draft exists for Android 13 / 7,631 MB RAM. Exact +14 installation, launch, installed-APK pull/hash verification, and upgrade-install outcome were collected; 13 journeys, CPU/XNNPACK, and endurance remain pending, so this is not certification |
| High | Same exact-artifact, journey, benchmark, and endurance contract | blocked-external | No high-tier device record; the connected device measured as mid tier and cannot be reused for this row |

Every device must complete consent/guest startup, offline vocabulary, learning
core, offline restart and sync, account lifecycle, model lifecycle, camera
scanner, speech/TTS/pronunciation, Gemini BYOK, clean install, upgrade install,
reboot/foreground/background, cloud kill switch, and data export. Each result
requires a private evidence reference. One signed mid-tier collector draft is
present, but none of its mandatory journey, CPU/XNNPACK, or endurance outcomes
is complete.

On 2026-08-13 the authorized collector preflight first saw zero entries from
`adb devices`. Starting the ADB server once produced the same zero-device
state, and an independent Windows present-device query found zero Android,
ADB, or MTP interfaces. A later bounded check found exactly one authorized
physical device. Its measured Android 13 / 7,631 MB configuration binds it only
to the mid tier. The signed collector installed and launched the exact +14 APK,
pulled the installed APK back, confirmed its hash, and recorded an
upgrade-install pass. Low and high still require two other devices, while the
mid-tier draft still requires genuine instrumented outcomes.

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
evidence shell remains `pending` for Cloud controls/cost, low/high physical
tiers, completion of the mid-tier outcomes, private references, beta/rollback,
and owner approval. The verifier
binds every accepted record to source `c55f7bb`, the +14 APK, a signed raw
source envelope, and (for device outcomes) the revalidated physical collector
receipt.

## Blocker report

- **Observed:** a genuine current signed package exists and verifies. One
  authorized mid-tier device produced a signed exact-artifact draft, but its
  journeys, CPU/XNNPACK benchmark, and endurance run remain pending. No
  low/high records or provider-console, private-channel, beta-operations,
  rollback, or owner-approval records are available for this candidate.
- **Expected:** three distinct physical device records plus all provider,
  operations, private-reference, and exact-hash owner-approval fields pass the
  closed field-evidence validator.
- **Evidence path:** `field/evidence/release-evidence.json` (ignored, pending
  shell) and this matrix.
- **Attempts:** initial ADB enumeration, one ADB server start, one independent
  PnP query, then one changed-state ADB check and one successful physical
  collector run; no pending journey was converted to PASS.
- **Smallest action sequence:** complete the genuine mid-tier instrumented
  journeys/benchmark/endurance, obtain distinct low- and high-tier devices,
  collect signed content-addressed provider/cost/beta/rollback records, and
  obtain owner approval for that exact APK hash.
- **Unaffected work:** local release-readiness reconciliation and a truthful
  `NOT READY` final acceptance record can proceed without fabricating evidence.
