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

## Budget alerts

The project owner must create a Google Cloud billing budget scoped to project
`vocab-learning-app-219ef` with actual-spend alerts at exactly:

- 50%
- 80%
- 100%

Route alerts to the owner-controlled billing notification channel. Do not put
email addresses, webhook secrets, or billing credentials in this repository.
Record screenshots or exported budget configuration in the private P8 owner
evidence package; do not commit participant identifiers.

## Android App Link

The manifest accepts:

`https://vocab-learning-app-219ef.firebaseapp.com/auth/action`

After release signing, publish `/.well-known/assetlinks.json` on that host with
the exact release certificate SHA-256 and package `com.lexiquest.app`. Confirm
with Android `pm verify-app-links` and a real Firebase verification/reset email.
The action screen accepts only `oobCode` plus the supported Firebase `mode`;
invalid or expired codes fail closed.

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
