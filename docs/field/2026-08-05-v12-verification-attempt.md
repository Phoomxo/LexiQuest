# APK 1.0.0+12 Verification Attempt — 2026-08-05

Engineer-driven verification of the new signed release APK against the
post-hardening codebase. Records what was verified, what was inconclusive,
and the one regression caught and fixed during this session.

## Artifacts built this session

| APK | Commit | SHA-256 (prefix) | Status |
|-----|--------|------------------|--------|
| 1.0.0+11 | `2a4f394` | `645FBA4C…` | Superseded (H2 regression) |
| 1.0.0+12 | `f167f24` | (see `release-manifest.json`) | **Current** |

Both built from the current HEAD via `package-field-release.ps1`, signed with
cert `E1B00E…FDC1F` (unchanged release signing identity).

## Regression caught and fixed (H2 refinement)

The H2 retry-loop hardening (commit `826ce11`) was **too aggressive**: it
hard-stopped on `GuestSessionFailure.unknown`. That broke anonymous binding on
a cold start, because App Check / Play Integrity can need a few seconds to
mint a token — the first `signInAnonymously()` attempt surfaces as an unmapped
`FirebaseAuthException` (→ `unknown`) while the integrity service is still
binding, then succeeds on a retry. The prior working field session (W4,
APK 1.0.0+10) had succeeded precisely because `unknown` was retried.

**Fix (commit `f167f24`):** `_isTransient` now retries on `network` **and**
`unknown`, keeping the hard-stop only on the genuinely permanent failures
(`providerDisabled`, `firebaseUnavailable`). Tests updated: the `unknown`
case now asserts retry-to-cap (matching the field-proven behavior); the
`firebaseUnavailable` hard-stop test is unchanged. `guest_session_service_test`
16/16 pass.

## What was verified (high confidence)

- **APK builds clean** from HEAD (`package-field-release.ps1`); manifest
  `sourceCommit` matches HEAD; signing cert unchanged.
- **App installs and launches without crash/ANR** on the mid-tier device
  (vivo V2041, Android 13). `minSdk=26` (H3) confirmed on-device.
- **Play Integrity initializes and mints a token** — `requestIntegrityToken()
  finished for com.lexiquest.app` appears in the logs; the App Check /
  Play Integrity path is exercised.
- **Release SHA is registered against the CORRECT Firebase app**
  (`2c492244…`, LexiQuest Production). The `firebase-release-sha.json`
  evidence file was refreshed to reflect the correct appId (previously
  recorded the placeholder app `719eb3…`).
- **`verify.ps1` 11/11 PASS**; `flutter test` 1015/1015; `flutter analyze`
  clean (last full run; the H2 refinement adds +0 net tests).

## What is INCONCLUSIVE (needs owner manual confirmation)

**Anonymous Auth → Firestore sync was NOT observed end-to-end in this
session.** Across a clean-install + 75s full-retry-window + UI-driven
interactions, no documents appeared in `field_users`, `operations`,
`users` (recent), or `state` (recent). The last Firestore writes anywhere
in the project are dated 2026-07-29 (one week ago).

Two competing explanations, neither could be ruled out via the device
tooling:

1. **GMS instability on the test device.** After `pm clear
   com.google.android.gms` (attempted to bust a stale config cache),
   logcat showed `GoogleApiManager … SecurityException: Unknown calling
   package` and `ConnectionResult{statusCode=DEVELOPER_ERROR}` plus
   `Phenotype.API is not available on this device`. These are GMS-internal
   errors that can gate Firebase Auth indirectly. A device restart (not
   performed — disruptive to other device state) would likely clear this.
2. **A real auth regression.** Possible but considered less likely: the
   code path is identical to the W4 session that succeeded (same appId fix,
   same Firestore rules), and the H2 regression that *was* introduced has
   been fixed.

**Why automation could not resolve this:** (a) the vivo V2041's
`uiautomator dump` consistently returns a stale LINE-app hierarchy (a
known Funtouch OS bug), so UI state couldn't be read; (b) release builds
strip Flutter debug logs, and the debug build couldn't be cleanly compared
(version downgrade); (c) the Firebase CLI's apiv2 client lacks the scope
needed to query Identity Toolkit user records directly.

## Required owner actions before distribution

1. **Confirm Anonymous Auth works on a freshly-restarted device.** Reboot
   the test device, install APK 1.0.0+12 clean, and watch the Firebase
   Console → Authentication → Users tab for a new anonymous uid within
   ~75s of launch. If a uid appears, Blocker 1 is cleared for this APK.
   If not, capture `adb logcat` around `FirebaseAuth` and investigate
   before distributing.
2. **Blocker 2 (App Check enforcement)** — owner Console action per
   `docs/runbooks/release-blockers-resolution.md`.
3. **W4.3 AI Tutor** — owner Gemini API key.
4. **Owner smoke test + approval** of APK 1.0.0+12, recorded in
   `field/evidence/release-evidence.json`.
5. **Private channel refs** (`supportChannelRef`, `researchProtocolRef`)
   currently placeholders.

## Build/evidence hygiene note

`field/evidence/release-evidence.json` still references APK 1.0.0+1
(`versionCode: 1`, sha `18966EB…`) with `devices: []` and
`ownerApproval.approved: false`. It must be regenerated via
`tool/cli/new-field-release-evidence.ps1` against APK 1.0.0+12 once the
owner confirms auth works on the new build.
