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

## Verified locally

- Field release contract tests: 30 passed.
- Flutter static analysis: zero issues.
- P7 product completion tests: 331 passed.
- Firebase Auth emulator journey: 3 passed.
- Firestore rules emulator suite: 25 passed.
- Android debug APK and packaged LiteRT runtime integrity: passed.
- Expected-blocker probes confirmed that packaging fails without release
  signing, collection fails without one physical device, and the final gate
  fails without private evidence.

## External evidence still required

The development host currently has no connected Android device,
`android/key.properties` is absent, and no private release evidence exists.
Accordingly, no release-signed APK or real-device result is claimed.

P8 remains blocked until the owner supplies:

1. a dedicated release keystore through the gitignored signing configuration;
2. low-, mid-, and high-tier physical Android devices;
3. production App Check, budget alert 50/80/100, asset-link, and kill-switch
   records;
4. approved research protocol, retention/deletion procedure, and real
   feedback/support channel references;
5. completed device journeys and 30-minute endurance evidence for the exact
   release APK;
6. owner smoke-test approval referencing that APK SHA-256.

The final command remains:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/verify-field-release.ps1
```

It must remain failing until every external item above is genuine.
