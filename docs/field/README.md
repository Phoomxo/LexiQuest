# LexiQuest field release runbook

This is a single fail-closed gate for one release candidate. A changed APK,
non-metadata source change, signing-key rotation, or stale evidence starts a new
candidate. Host tests, emulators, debug APKs, free-form references, and unsigned
JSON cannot replace physical or provider evidence.

## 1. Package one frozen source

Release signing uses the existing owner-controlled Android identity. Never
create an unsigned substitute or a second Android signing identity.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/package-field-release.ps1 -Version 1.0.0+14
```

The packager requires a clean worktree and writes the verified APK plus
`release-manifest.json` under `build/field-release/`.

## 2. Use the pinned evidence-signing identity

The tracked public key is
`tool/cli/trusted-field-evidence-public-key.xml`. Its matching non-exportable
private key remains in the current Windows user's certificate store. Initialize
it only when the tracked public key does not yet exist:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/initialize-field-evidence-signing.ps1 `
  -ConfirmOwnerControlledKeyCreation
```

Do not rotate or overwrite this identity during an evidence run. The full
receipt and payload contract is documented in
`docs/field/2026-08-13-field-evidence-signing.md`.

## 3. Collect low-, mid-, and high-tier Android drafts

Connect exactly one authorized physical device per run. Supply the thumbprint
of the matching current-user evidence certificate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/collect-android-field-evidence.ps1 `
  -Tier low `
  -NetworkProfile offline-mixed `
  -SigningCertificateThumbprint '<CURRENT_USER_CERT_THUMBPRINT>'
```

The collector rejects emulator/debug markers, installs and launches the exact
APK, pseudonymizes the device, signs its collector attestation, and records all
unobserved journeys/benchmarks/endurance as `pending`.

After a real instrumented result is exported under ignored `field/evidence/`,
attach its typed receipt with
`tool/cli/sign-android-field-evidence-result.ps1 -InstrumentedResultPath ...`.
The signer revalidates the collector attestation and derives the claim from the
raw source; editing the device JSON alone or using a host fake cannot pass.
Repeat for every mandatory journey, the CPU benchmark, the declared GPU
outcome, and endurance.

## 4. Collect provider and operations evidence

Store typed provider/operations/owner source envelopes under ignored
`field/evidence/` paths. Create their signed receipts with
`tool/cli/new-field-evidence-receipt.ps1`; the receipt payload is derived only
from the envelope, and source/capture/release binding is checked. Insert only
the returned content-addressed reference into the matching ignored Cloud,
cost, participant-package, beta, rollback, or owner record. Rollback and
kill-switch envelopes must share one UUID-v4 drill ID, candidate, target, and
ordered start/completion timestamps.

No receipt payload may contain a secret, keystore, participant identifier,
decrypted evidence, or raw provider credential.

## 5. Assemble and verify

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/new-field-release-evidence.ps1

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/verify-field-release.ps1 `
  -EvidencePath field/evidence/release-evidence.json `
  -ParticipantPackagePath build/field-release
```

The final verifier independently checks the immutable package, canonical
tracked public key, receipt signatures/digests/payloads, source and artifact
identity, strict freshness/order, physical-device matrix, central cost,
beta/rollback outcomes, and exact owner approval before rerunning the product
completion gate.
