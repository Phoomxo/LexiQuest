# LexiQuest internal APK checkpoint

Status: packaged and independently verified for controlled internal evidence
collection. This checkpoint is not a publication, distribution, physical-device
certification, beta approval, or release-readiness decision.

## Frozen source and artifact

- Artifact source commit:
  `4e4b398e5dc19a29a4f81953e16b084bfe0400d3`
- Build ID: `4e4b398e5dc1`
- Package: `com.lexiquest.app`
- Version: `1.0.0+14`
- APK: `lexiquest-1.0.0+14.apk`
- APK size: `113567700` bytes
- APK SHA-256:
  `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A`
- Signing-certificate SHA-256:
  `E1B00E17896BFB73FE0DC42429768B966465213D49A8A5165DE06688CC8FDC1F`
- Device-model SHA-256:
  `D3949E8A3556C79739CB675E0BE7476503BCCE76938031C6A1048E13E0CB7D8B`
- Package manifest generated at: `2026-08-13T16:40:42.3018171Z`

The ignored package directory is `build/field-release`. Its
`release-manifest.json` contains the relative APK filename and the same values
above. This evidence document is a later metadata-only commit; it does not
change or relabel the artifact's frozen source commit.

## Verification performed

- Existing owner-controlled signing identity passed its pinned certificate
  fingerprint gate before its normalized X.500 OID/value comparison. Alias,
  PKCS12 store type/path, validity, exact OID set, and values matched.
- The source worktree was completely clean at the artifact source commit before
  packaging and immediately after packaging.
- Flutter passed all three non-secret provenance values explicitly as Android
  project properties. Release Gradle rejected missing/invalid values and the
  produced manifest carried the exact source commit, build ID, and model hash.
- The package script verified one signer, the pinned certificate fingerprint,
  package ID, version name/code, embedded provenance, APK hash, and native
  model runtime integrity before atomically publishing the package directory.
- A separate explicit-path invocation of `verify-field-package.ps1` repeated
  signature, fingerprint, package/version, manifest provenance, APK hash, and
  release model-runtime verification and returned PASS.
- A separate `Get-FileHash` calculation matched the manifest APK SHA-256
  byte-for-byte.
- `android/key.properties` remained ignored and untracked. Its ACL had one
  non-inherited allow entry for the current Windows user. No credential,
  password, recovery envelope, private-key material, or secret was printed,
  logged, added to Git, or placed in this evidence.

## Verification chronology

Two earlier attempts produced no APK or package:

1. `356c4f5` stopped at the release provenance gate because inherited Gradle
   environment properties did not cross the Flutter release boundary.
2. `ac8d035` crossed that gate with explicit project arguments, then stopped
   because `--no-pub` preserved a stale Android registrant referencing the
   development-only `integration_test` plugin outside the release classpath.

The earlier authorized attempt at `c199d50` retained explicit project arguments
and allowed Flutter's normal pub freshness step to regenerate release-mode
plugin registration. Task 12 then required a new candidate after verifier and
field-evidence hardening. At clean commit `4e4b398`, the stale ignored +13
package was archived without deletion; one actual +14 release build produced
and verified the single artifact recorded above. No release-build retry
followed that successful build.

## Tool boundary

- Git: `2.54.0.windows.1`
- Flutter: `3.44.7` stable, framework revision `84fc5cbb22`
- Dart: `3.12.2`
- Android SDK build-tools: `37.0.0`
- `apksigner`: `0.9`
- Product completion gate on the frozen source: PASS; one initial committed-head
  run had a field-journey harness failure, all three exact journeys then passed
  individually, and one bounded full-gate rerun passed.
- Focused release contracts: Android signing 54/54, provenance 28/28,
  packager 27/27, independent package verifier 5/5, field verifier 152/152,
  product-gate contract PASS
- Stable manual release-packaging diff review: CLEAN
- MaxPlus advisory review: unavailable after the prior `invalidKey`; it was not
  retried. The plan-authorized local read-only review was used instead.

## Distribution and next gate

The APK was not published, uploaded, pushed, released, or distributed. Task 11
must bind all physical-device and beta evidence to this exact APK and manifest.
Until that evidence passes, this checkpoint must not be described as
field-certified or release-ready.
