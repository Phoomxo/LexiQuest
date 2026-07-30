# P8 field certification gate — 2026-07-30

## Implemented

- Research consent version 1 is stored in Drift per local owner. Acceptance and
  withdrawal are explicit; declining or withdrawing does not disable offline
  learning.
- Research JSON export requires active consent. Personal CSV, PDF, and Anki
  exports remain available after withdrawal.
- `package-field-release.ps1` requires a dedicated owner-controlled release
  keystore, a committed Android-relevant source state, and `apksigner`
  verification. It packages the APK, participant documents, SHA-256 values,
  certificate digest, version, build ID, source commit, and model checksum.
- `collect-android-field-evidence.ps1` accepts exactly one physical device,
  rejects emulators, hashes the serial with release identity, installs and
  launches the exact APK, captures device facts, and marks every unexecuted
  journey `pending`.
- `new-field-release-evidence.ps1` assembles private device, Cloud-control,
  support, research-protocol, and owner evidence without committing it.
- `verify-field-release.ps1` has no release bypass. It reconciles the packaged
  manifest, APK hash, signing certificate, three distinct device tiers,
  mandatory journeys, CPU/XNNPACK benchmarks, honest GPU policy, 30-minute
  endurance, participant documentation, Cloud controls, and owner approval,
  then runs the complete P7 regression gate once.
- `initialize-release-signing.ps1` creates a permanent 4096-bit release key
  outside the repository, protects its recovery secret with Windows DPAPI,
  restricts every signing artifact to the current user, and refuses overwrite.
- Firebase operations scripts register the release SHA-256, configure off-Play
  Play Integrity, verify the no-billing cost boundary, exercise and restore the
  cloud kill switch, and validate both hosted Android App Links.
- The release build applies a focused R8 rule retaining the WorkManager Room
  database constructor used by AndroidX Startup reflection.

## Verified locally

- Field release contract tests: 54 passed.
- Android release-signing contracts: 45 passed.
- Flutter static analysis: zero issues.
- P7 product completion tests: 331 passed.
- Firebase Auth emulator journey: 3 passed.
- Firestore rules emulator suite: 25 passed.
- Android debug APK and packaged LiteRT runtime integrity: passed.
- A dedicated release key and signed APK were created. The key remains outside
  Git and the recovery secret is not recorded in logs or evidence.
- Firebase release SHA registration, App Check provider configuration, hosted
  asset links, zero-billing verification, and production kill-switch
  disable/offline/restore checks completed.
- A signed release APK was installed on the Android 15 emulator. The first
  candidate reproduced a release-only `WorkDatabase_Impl` R8 crash; the
  corrected candidate starts `com.lexiquest.app/.MainActivity`, remains the
  resumed activity, and has no fatal exception or ANR in the launch log.
  This is a release preflight only and is not physical-device evidence.
- Expected-blocker probes confirmed that packaging fails without release
  signing, collection fails without one physical device, and the final gate
  fails without private evidence.

## External evidence still required

The development host has only an emulator and no connected physical Android
device. No physical-device result or owner approval is claimed.

P8 remains blocked until the owner supplies:

1. low-, mid-, and high-tier physical Android devices;
2. valid App Check traffic from the signed APK on physical hardware, followed
   by enforcement and a second acceptance pass;
3. approval of the research protocol/retention procedure and a real private
   support channel reference;
4. completed device journeys and 30-minute endurance evidence for the exact
   release APK;
5. owner smoke-test approval referencing that APK SHA-256.

Cloud Billing is disabled, so 50/80/100 alerts are not applicable. Enabling a
billing account only to create alerts would weaken the current zero-paid-cost
boundary and is not required by the final evidence schema.

The final command remains:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/verify-field-release.ps1
```

It must remain failing until every external item above is genuine.
