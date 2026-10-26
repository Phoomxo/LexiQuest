# APK 1.0.0+12 — GMS Recovery + Auth Re-verification — 2026-08-06

Follow-up to `2026-08-05-v12-verification-attempt.md`. That session left
**Anonymous Auth end-to-end INCONCLUSIVE** because the test device's GMS
state had been corrupted by `pm clear com.google.android.gms`. This record
confirms the recovery procedure and the cleared result.

## Root cause of the 08-05 inconclusive result

`pm clear com.google.android.gms` (run to bust a stale config cache) caused
two compounding failures on the vivo V2041 test device:

1. **`SecurityException: Unknown calling package name 'com.google.android.gms'`**
   — GMS's cross-process binder identity was reset; other apps (incl.
   LexiQuest) could not bind to the GMS broker. This gated Firebase Auth
   indirectly.
2. **`BAD_AUTHENTICATION` / "Long live credential not available"** — the
   `pm clear` wiped the stored OAuth refresh tokens for the on-device
   Google accounts. Accounts stayed *registered* but could not mint tokens.

Neither a single reboot nor re-launching the app resolved both at once.

## Recovery procedure that cleared it

| Step | Action | Result |
|------|--------|--------|
| 1 | `adb reboot` (first) | GMS processes restarted, but GMS was also auto-updated by Play Store (26.24.34 → 26.28.33) during this window, leaving the binder identity half-initialized |
| 2 | Re-authorize USB debugging on device | `unauthorized` → `device` |
| 3 | `adb reboot` (second, **after** the GMS update landed) | GMS 26.28.33 initialized cleanly from a fresh boot |
| 4 | Unlock screen PIN (vivo requires PIN after every cold boot) | `isKeyguardShowing=true` → `false` |
| 5 | `pm clear com.lexiquest.app` (app data only — **never** GMS again) + relaunch | Clean auth attempt |

**Key lesson:** `pm clear com.google.android.gms` is destructive on this
device class. Do not run it to bust caches. A plain reboot is the safe
cache-bust for GMS.

## Verified result — Play Integrity + token mint SUCCEED

Logcat timeline from the clean re-test (2026-08-06, PID 10515):

```
02:44:52.247  PlayCore: requestIntegrityToken(nonce=…, cloudProjectNumber=145034183638)
02:44:52.248  PlayCore: Initiate binding to the service.
02:44:52.306  PlayCore: onServiceConnected(com.android.vending/…IntegrityService)
02:44:52.307  PlayCore: linkToDeath
02:44:57.102  Finsky:  requestIntegrityToken() finished for com.lexiquest.app.
02:44:57.134  PlayCore: OnRequestIntegrityTokenCallback : onRequestIntegrityToken
02:44:57.136  PlayCore: Unbind from service.
```

- **cloudProjectNumber `145034183638`** matches the Firebase project in
  `android/app/google-services.json` (`vocab-learning-app-219ef`). Correct
  project binding.
- **End-to-end token mint = 4.9 s** (request → callback). Within normal
  range; well inside the retry window.
- The token was returned to the app via `OnRequestIntegrityTokenCallback`.
  Play Integrity / App Check path is exercised and **succeeds** on APK
  1.0.0+12.

### Errors that are NOT blockers

These GMS-internal warnings still appear in logcat but are **unrelated**
to the Play Integrity path (which binds to Finsky's `IntegrityService`,
not the GMS broker):

- `GoogleApiManager … SecurityException: Unknown calling package` — now
  only fires for the GMS *broker* path (providerinstaller), not Play
  Integrity. The earlier blocker form (firing for the integrity request)
  is gone after the second reboot.
- `ConnectionResult{statusCode=DEVELOPER_ERROR}` / `Phenotype.API is not
  available` — Phenotype flag-store for providerinstaller; cosmetic on
  this device.

## Blocker 1 status: CLEARED (for the Play Integrity / token-mint half)

The 08-05 inconclusive result is resolved for the integrity-token half of
the auth path. What remains owner-manual is the **Firestore write** half:
confirm a document lands in `field_users`/`operations` after the token
mint. That requires the owner's Firebase Console view (the CLI apiv2
client still lacks the scope to read Identity Toolkit user records), so
it is left to owner action per the 08-05 doc's "Required owner actions"
list — unchanged here.

## Device state after this session

- vivo V2041, Android 13, SDK 33
- GMS 26.28.33 (auto-updated during recovery)
- 10 Google accounts registered (tokens healthy after second reboot)
- APK 1.0.0+12 installed, versionCode 12, minSdk 26
- Screenshot: `lexiquest_auth.png` (app in foreground, post-mint)
