# Field evidence signing contract

## Purpose

The final field gate accepts only content-addressed evidence receipts signed by
the repository-pinned operations key. The public key is tracked at
`tool/cli/trusted-field-evidence-public-key.xml`. Its matching non-exportable
private key remains in the current Windows user's certificate store; no private
key, password, participant record, or provider credential belongs in Git.

The key proves which approved local evidence issuer signed an artifact-bound
receipt and makes later edits detectable. It does not prove that a dishonest
authorized issuer performed a physical test. Device records therefore also
retain collector, anti-emulator, exact-APK, benchmark, and outcome checks.

## Identity lifecycle

The owner-controlled identity is initialized once:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/initialize-field-evidence-signing.ps1 `
  -ConfirmOwnerControlledKeyCreation
```

The initializer refuses to overwrite an existing public key. Any intentional
rotation must be a reviewed source change made before packaging; it invalidates
all receipts issued by the previous key for the new candidate.

## Physical Android evidence

Collect the first fail-closed device draft with exactly one authorized device:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/collect-android-field-evidence.ps1 `
  -Tier low `
  -NetworkProfile offline-mixed `
  -SigningCertificateThumbprint '<CURRENT_USER_CERT_THUMBPRINT>'
```

The collector rejects emulator/debug markers, installs and launches the exact
manifest APK, pseudonymizes the device, signs its collector attestation, and
leaves every unobserved result `pending`. It never converts camera, microphone,
provider, CPU, or endurance work into a pass.

After a real instrumented result has been exported under ignored
`field/evidence/`, attach a typed receipt. The signer revalidates the signed
collector attestation and the complete device/release identity, derives the
accepted payload from the instrumented source, and then updates the device
record:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/sign-android-field-evidence-result.ps1 `
  -DeviceEvidencePath 'field/evidence/devices/<DEVICE_RECORD>.json' `
  -InstrumentedResultPath `
    'field/evidence/device-results/<INSTRUMENTED_RESULT>.json' `
  -ResultType Journey `
  -JourneyName offlineVocabulary `
  -SigningCertificateThumbprint '<CURRENT_USER_CERT_THUMBPRINT>'
```

`ResultType` is one of `Journey`, `CpuBenchmark`, `GpuBenchmark`, or
`Endurance`. A host fake, manually edited device outcome, source from another
collector receipt, or result for another release is rejected. The signer writes
the content-addressed raw source and receipt under the ignored
private-evidence directory and attaches only its reference to the device
record.

The instrumented source envelope is schema 1 and contains exact `kind`,
`origin`/`captureMethod` = `physical-android-instrumentation`, `hostFake` =
`false`, source/APK identities, the collector evidence reference, evidence ID,
tier, pseudonymous device ID, strict UTC observation time, and the typed result
payload. Raw participant identifiers are forbidden.

## Provider, operations, and owner receipts

Use `tool/cli/new-field-evidence-receipt.ps1` only with one typed source
envelope exported by the provider console, release instrumentation, or owner
attestation workflow. There is no separate payload input: the signer derives
the claim from `sourceEnvelope.payload`, rejects host fakes, restricts every
kind to its declared origin/capture method, binds the manifest source and APK
hash, and rejects a signing certificate that does not match the tracked public
key.

Every provider/operations/owner envelope is schema 1 and contains `kind`, its
declared `origin` and `captureMethod`, `hostFake` = `false`, source commit, APK
SHA-256, strict UTC observation time, and `payload`. The receipt keeps the
content-addressed source bytes; a second hand-authored payload file is neither
accepted nor signed.

Accepted payload shapes are:

- `app-check`: `configured`, `validTrafficObserved`, `enforced`,
  `observedAtUtc`.
- budget-alert `billing`: `configured`, `notApplicable`, `billingMode`,
  `observedAtUtc`.
- central-cost `billing`: the complete central-cost object except
  `evidenceRef`.
- `asset-links`: `verified`, `observedAtUtc`.
- Cloud `kill-switch`: `verified`, `observedAtUtc`.
- rollback `kill-switch`: the same UUID-v4 drill ID, candidate, target, ordered
  start/completion timestamps, `status`, `cloudSyncDisabledObserved`,
  `localLearningUsable`, and `cloudSyncRestored`.
- feedback/support/research: `channel`, `verifiedAtUtc`, `consentVersion`.
- beta sessions: exact release, beta window, tester/consent counts, and session
  counters; the other beta receipts contain their exact sync, issue, provider,
  download, or decision counters.
- `rollback-drill`: UUID-v4 drill ID, candidate, target, ordered timestamps,
  outcome booleans, and data outcome. The kill-switch receipt must carry the
  identical drill identity and context.
- `owner-approval`: every artifact identity field, approval timestamp, and
  approver role.

Example:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/new-field-evidence-receipt.ps1 `
  -Kind app-check `
  -Origin provider-console-export `
  -SourceExportPath 'field/evidence/cloud/app-check-export.json' `
  -SigningCertificateThumbprint '<CURRENT_USER_CERT_THUMBPRINT>'
```

Copy only the returned `private-evidence:v1:...:sha256:...` reference into the
corresponding ignored aggregate record. Do not put participant identifiers,
raw console exports, secrets, or decrypted evidence in a receipt payload.
`SourceExportPath` must point to the ignored typed provider/operations envelope
that contains the accepted payload; its SHA-256 is included in the signed
receipt so the claim remains attributable without committing the export.

## Assemble and verify

Assemble the root record from explicit ignored inputs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/new-field-release-evidence.ps1
```

Then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/verify-field-release.ps1 `
  -EvidencePath field/evidence/release-evidence.json `
  -ParticipantPackagePath build/field-release
```

The verifier uses only the canonical tracked public key. Missing blobs,
unsigned or untrusted receipts, altered payloads, stale timestamps, dirty
source, non-metadata post-package changes, and artifact mismatches all fail.
