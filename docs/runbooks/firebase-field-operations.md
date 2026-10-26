# Firebase field operations

This runbook is an operational gate. It does not grant permission to enable
paid cloud usage. LexiQuest remains usable from Drift when every Firebase
control below is disabled.

## App Check rollout

1. Development and emulator builds may set
   `--dart-define=LEXIQUEST_APP_CHECK_DEBUG=true`. Register only the generated
   debug token used by the owner test device and revoke it after testing.
2. Release builds must omit that define. The app activates Play Integrity.
3. Register package `com.lexiquest.app`, the release SHA-256 certificate, and
   Play Integrity in Firebase before the owner smoke test.
4. Observe valid/invalid App Check traffic with enforcement off.
5. Enforce Firestore only after the release-signed APK completes the full
   offline/online journey. Auth is protected by its own provider controls.
6. If rejection or cost anomalies occur, set the server cloud policy to
   disabled and distribute a build with
   `LEXIQUEST_CLOUD_SYNC_ENABLED=false`. Local learning and pending outbox
   records remain available.

## Billing mode

Record exactly one mode in release evidence:

- `noBillingAccount`: remain on Spark/no billing, set alerts to false and
  not-applicable to true, and verify truthful quota-exhaustion behavior.
- `budgeted`: attach billing only with explicit cost authority, configure
  actual-spend alerts at 50%, 80% and 100%, and document quota/kill-switch
  ownership. A budget sends alerts; it is not a hard spending cap.

Route any alerts to an owner-controlled private channel. Do not put email,
webhook secrets or billing credentials in this repository. Gemini BYOK,
Supabase and Play costs are separate from the Firebase billing record.

## Android App Link

The manifest accepts Firebase Hosting email-action links at:

`https://vocab-learning-app-219ef.firebaseapp.com/__/auth/links`

Firebase may deliver this path as a wrapper whose `link` parameter contains
the percent-encoded Firebase action handler at
`https://vocab-learning-app-219ef.firebaseapp.com/__/auth/action`. The app
decodes that parameter once, then requires HTTPS, the exact project host, and
the exact handler path. A legacy flattened wrapper with `mode` and `oobCode`
on `/__/auth/links` remains supported.

`/auth/action` remains the state/continue URL supplied through
`ActionCodeSettings`. Only the app's relative internal route may use that
path directly. An absolute action or continue URL must use HTTPS and the exact
project host; untrusted hosts, user-info host confusion, alternate paths,
double encoding, duplicate action codes, and open redirects fail closed.

After release signing, publish `/.well-known/assetlinks.json` on that host with
the exact release certificate SHA-256 and package `com.lexiquest.app`. Confirm
with Android `pm verify-app-links` and a real Firebase verification/reset email.
The deterministic accepted/rejected contract lives in
`test/fixtures/email_action_links.json`. Invalid or expired codes fail closed.

## Cost boundary

- Emulator tests and local Drift are the default.
- Gemini remains participant BYOK and is unrelated to the Firebase budget.
- Do not enable Firebase paid products for the 30-person trial without an
  explicit owner acceptance record.

## Cloud kill switch

Set the server cloud policy to disabled first, then distribute a build with
`LEXIQUEST_CLOUD_SYNC_ENABLED=false` if provider access must stop completely.
Do not clear Drift or the outbox. Verify Quiz, SRS, reading, progress, rewards,
and export while cloud sync is disabled before declaring the kill switch ready.
