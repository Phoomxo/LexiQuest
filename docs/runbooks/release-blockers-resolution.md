# Release blockers resolution

Operational checklist to clear the two blockers that prevent distributing a
release-signed APK. Every step below names an existing tool in this repository
— no manual Firebase Console copy-paste is required for the automated path.

This runbook is the executable companion to
[`firebase-field-operations.md`](./firebase-field-operations.md) (App Check
enforcement policy) and to
[`../development/p8-field-certification-gate-2026-07-30.md`](../development/p8-field-certification-gate-2026-07-30.md)
(certification status).

## Precondition

- `android/key.properties` exists and points at a real release keystore. If it
  does not, run step S0 below first.

## S0. Generate the release signing identity (once per signing identity)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tool/cli/initialize-release-signing.ps1
```

This generates a 4096-bit RSA keystore under
`%USERPROFILE%\.lexiquest\signing`, writes `android/key.properties` (DPAPI +
ACL locked to the current Windows user), and refuses to overwrite an existing
identity. Do not commit the keystore or `key.properties`.

## Section 1 — Register the release certificate with Firebase (Blocker 1)

> **Why this is a blocker:** `android/app/google-services.json` currently has
> no `sha1_cert_hashes` entry for the Android client. Without a registered
> fingerprint, Play Integrity rejects the app's token and every Firebase
> service that depends on it (Anonymous Auth, Firestore via Auth, App Check)
> returns `PERMISSION_DENIED`.

### S1.1. Build and package the signed release APK

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tool/cli/package-field-release.ps1 -Version 1.0.0+1
```

Outputs (under `build/field-release/`):

- `lexiquest-1.0.0+1.apk` — the signed APK
- `release-manifest.json` — contains `signingCertificateSha256` (64 hex chars),
  `apkSha256`, `buildId`, and `sourceCommit`

The script refuses to run if Android-relevant sources are dirty or if
`android/key.properties` is missing. It also verifies the signature with
`apksigner` and rejects debug/fake keys.

### S1.2. Register the certificate SHA-256 with Firebase

```bash
node tool/cli/configure-firebase-release-sha.cjs
```

This reads `signingCertificateSha256` from `release-manifest.json`, checks
Firebase for an existing match, and registers the SHA-256 fingerprint if it is
not already present. Requires a global `firebase-tools` login
(`firebase login`) with access to project `vocab-learning-app-219ef`.

Evidence is written to `field/evidence/cloud/firebase-release-sha.json`.

#### About the SHA-1 vs SHA-256 difference

The owner-supplied SHA-1 fingerprint
(`7A:B8:6E:48:96:1A:9F:B5:67:49:13:9D:4F:FE:97:8F:D3:B4:36:5B`, 20 bytes) and
the SHA-256 fingerprint (64 hex chars) both come from the **same release
keystore**. They are two views of the same certificate:

- Firebase App Check / Play Integrity configuration in the console accepts both
  SHA-1 and SHA-256.
- The automated registration script registers **SHA-256** because that is what
  `apksigner` reports in `release-manifest.json` and what Play Integrity
  requires going forward (SHA-1 is deprecated for new integrations).
- If a manual Firebase Console registration is needed instead, paste the
  SHA-1 fingerprint above under *Project Settings → Your apps → Android →
  Add fingerprint*, then re-download `google-services.json` and replace
  `android/app/google-services.json`.

### S1.3. Re-download and replace `google-services.json`

After registration, download the updated config from the Firebase Console
(*Project Settings → Your apps → Android → Download `google-services.json`*)
and replace `android/app/google-services.json`. The new file must contain a
`sha1_cert_hashes` and/or `sha256_cert_hashes` entry under
`client[].android_info`.

### S1.4. Verify the block clears

Build a release APK without the debug App Check override and run the owner
smoke test (see Section 4). Cloud sync and Anonymous Auth must succeed on a
physical device.

## Section 2 — App Check enforcement (Blocker 2)

Follows the 6-step rollout in [`firebase-field-operations.md`](./firebase-field-operations.md#app-check-rollout).
The tools below are the executable form of those steps.

### S2.1. Temporary: build with the debug provider

While the SHA is not yet registered (Section 1 incomplete), build with the
debug App Check provider so the rest of the release journey can be exercised:

```bash
flutter build apk --release \
  --dart-define=LEXIQUEST_APP_CHECK_DEBUG=true \
  --dart-define=LEXIQUEST_CLOUD_SYNC_ENABLED=true \
  --dart-define=LEXIQUEST_VERSION=1.0.0+1 \
  --dart-define=LEXIQUEST_BUILD_ID="$(git rev-parse --short HEAD)"
```

Register only the debug token printed in the console on the owner test device
and revoke it after testing (see `firebase-field-operations.md` step 1).

### S2.2. Inspect current enforcement state

```bash
node tool/cli/set-firebase-app-check-enforcement.cjs status
```

Prints the current Firestore App Check enforcement mode and writes evidence to
`field/evidence/cloud/`.

### S2.3. Observe valid/invalid traffic with enforcement OFF

This is the observation window described in
`firebase-field-operations.md` step 4. With enforcement `UNENFORCED`, run the
release-signed APK and confirm that the Firebase Console App Check logs show
both valid (after SHA registration) and (optionally) invalid traffic. Do not
proceed to S2.4 until valid traffic is observed.

### S2.4. Enforce

```bash
node tool/cli/set-firebase-app-check-enforcement.cjs enable
```

Switches Firestore enforcement to `ENFORCED`. Per
`firebase-field-operations.md` step 5, only enforce after the release-signed
APK completes the full offline/online journey. Auth is protected by its own
provider controls, not App Check.

### S2.5. Roll back if needed

```bash
node tool/cli/set-firebase-app-check-enforcement.cjs disable
```

If rejection or cost anomalies occur, return to `UNENFORCED` and, if cloud
access must stop completely, distribute a build with
`--dart-define=LEXIQUEST_CLOUD_SYNC_ENABLED=false` (see
`firebase-field-operations.md` step 6 / Cloud kill switch).

## Section 3 — Major issues that resolve once the blockers clear

| Issue | Status after blockers clear | Notes |
|---|---|---|
| Anonymous Auth fails in release | Auto-resolves | Play Integrity accepts the token once the SHA is registered. The retry budget was also reduced (8 → 5 attempts × 15 s = 75 s) so a transient failure wastes less resources. |
| SRS Flashcards flip / mark | Testable on a physical device | No code blocker; needs a device + a signed APK. |
| Speak-to-Text microphone | Testable on a physical device | Needs microphone permission + a signed APK on real hardware. |
| AI Tutor no response | Needs a Gemini API key | Follow `../development/p6-gemini-byok-gate-2026-07-30.md`. Missing keys are surfaced as a typed `GeminiException` and never crash the screen. |

## Section 4 — Owner-only actions (no automation)

These cannot be automated and require the project owner:

1. **Owner smoke test + approval.** Install the final signed APK on a physical
   device, run the mandatory journeys, and record approval against the exact
   APK SHA-256 from `release-manifest.json`. `verify-field-release.ps1` will
   refuse to pass until `ownerApproval.approved` is true and the hash matches.
2. **Gemini BYOK API key.** Create a Gemini API key and exercise the AI Tutor
   end-to-end (see the P6 gate).
3. **Private channel refs.** Supply `feedbackChannelRef`,
   `supportChannelRef`, and `researchProtocolRef` as `-FeedbackChannelRef`,
   `-SupportChannelRef`, `-ResearchProtocolRef` to
   `tool/cli/new-field-release-evidence.ps1` (see `docs/field/README.md`).
4. **Physical device tiers.** Procure and test on a low-tier device
   (≤ 4 GB RAM, Android 11–12) and a high-tier device (≥ 8 GB RAM,
   Android 14+). GPU allowlisting also needs a qualifying device.
5. **Manual SHA registration (fallback).** Only if S1.2 cannot run — paste the
   SHA-1 fingerprint into the Firebase Console as described in S1.2.

## Final gate

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tool/cli/verify-field-release.ps1
```

This must remain failing until every required item above is genuine. Any
journey affected by a new APK must be rerun and tied to the new APK SHA-256.
