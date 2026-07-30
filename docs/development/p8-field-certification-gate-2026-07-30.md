# P8 field certification gate — 2026-07-30

**Last updated:** 2026-07-31
**Current design:** `docs/superpowers/specs/2026-07-31-p8-hybrid-voice-field-release-design.md`

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

## Verified baseline

- Field release contract tests: 59 passed in the latest recorded gate.
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

## Verified on the physical mid-tier device

The signed `1.0.0+9` APK was installed on a vivo V2041 running Android 13.
Evidence is tied to APK SHA-256
`FB9C39C5159566C8007878F0D2FAFDF415B2453B3AF235600F199DDEE1452C5E`
and source commit `6a42c9ade57243315607cd2492ed698f18824e1f`.

Passed:

- offline vocabulary persistence;
- offline force-stop, cold restart, reconnect, and synchronization;
- real LiteRT model lifecycle and camera inference;
- clean installation and upgrade from version code 8 to 9;
- CPU/XNNPACK benchmark;
- 30.44-minute endurance with zero crash and ANR, stable process ID,
  peak RSS 321.9 MB, and temperature from 33.7°C to 34.3°C with a 35.0°C peak.

The recorded comparison measured CPU median latency at 33.7 ms and XNNPACK at
43.2 ms. Production therefore prefers CPU on this exact device. GPU remains
disabled because the device is not allowlisted.

## App Check status

A bounded Play Integrity enforcement attempt returned an invalid/unknown App
Check token on the physical device. Enforcement was rolled back to
`UNENFORCED` so offline and synchronization behavior remained usable.

App Check is not accepted until Play Console/Firebase linkage produces valid
production traffic. Enforcement must then be enabled and verified with a
second bounded acceptance pass.

## Evidence still required

The following journeys remain pending on the mid-tier evidence record:

1. consent and Guest startup;
2. learning core;
3. account lifecycle;
4. real speech, TTS, and pronunciation;
5. Gemini BYOK;
6. reboot and foreground/background;
7. exact Cloud kill-switch journey;
8. data export.

The VoxCPM hybrid voice and session-only voice-mirror work defined by the
current design must also be implemented before a new final release candidate is
certified.

External requirements remain:

1. one low-tier and one high-tier physical Android device;
2. valid App Check traffic followed by enforcement;
3. approval of the research protocol/retention procedure and a real private
   support channel reference;
4. completed mandatory journeys for the exact final release APK;
5. owner smoke-test approval referencing the final APK SHA-256.

Cloud Billing is disabled, so 50/80/100 alerts are not applicable. Enabling a
billing account only to create alerts would weaken the current zero-paid-cost
boundary and is not required by the final evidence schema.

The final command remains:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/verify-field-release.ps1
```

It must remain failing until every required item above is genuine. Results from
version code 9 may be retained only for unchanged journeys; any journey affected
by a new APK must be rerun and tied to that APK hash.
