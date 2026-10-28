# Firebase Auth email actions and Android App Links

## Scope and release boundary

This runbook qualifies the Firebase Auth verification and password-reset path
for LexiQuest v0.1. It does not authorize a deployment. Completing local tests
or an Android debug build does not prove Firebase Hosting, Firebase Auth email
delivery, or Android App Links parity in production.

The action host and handler are fixed for v0.1:

- Android package: `com.lexiquest.app`
- Hosting host: `vocab-learning-app-219ef.web.app`
- Action handler: `https://vocab-learning-app-219ef.web.app/auth/action`
- Supported modes: `verifyEmail` and `resetPassword`

Do not use the retired `.page.link` or Firebase Dynamic Links system.

## Owner-controlled prerequisites

| Owner | Gate | Evidence required before signed v0.1 distribution |
| --- | --- | --- |
| Firebase owner | Add `vocab-learning-app-219ef.web.app` in Firebase Authentication **Authorized domains**. | Console screenshot or change record. |
| Firebase owner | Configure the custom email action handler URL as `https://vocab-learning-app-219ef.web.app/auth/action`. | Console screenshot or change record. |
| Android release owner | Set GitHub production variable `ANDROID_RELEASE_CERT_SHA256` to the exact, colon-separated SHA-256 fingerprint of the protected release signing certificate. | Protected-environment run validates its format without printing it. |
| Hosting owner | Publish `/.well-known/assetlinks.json` at the Hosting host for `com.lexiquest.app`, containing only the approved release certificate fingerprint and the required Android App Links relation. | HTTPS retrieval and Android App Links output below. |
| Firebase owner | Review the password reset template and verification template so each uses the approved handler and does not leak account state. | Sent-email review on a physical test device. |

The GitHub workflow validates only the fingerprint format. It never prints the
value and never deploys Hosting. Hosting deployment requires the owning
operator's explicit credentials and change approval.

## Hosting and Firebase Console checklist

1. In Firebase Authentication, add `vocab-learning-app-219ef.web.app` to
   **Authorized domains**.
2. Configure the custom email action handler URL as
   `https://vocab-learning-app-219ef.web.app/auth/action`.
3. Configure and review the Firebase Auth password reset template. Its reset
   link must resolve through the handler above.
4. Configure and review the Firebase Auth verification template. Its
   verification link must resolve through the same handler.
5. Publish the Hosting asset-link file at
   `https://vocab-learning-app-219ef.web.app/.well-known/assetlinks.json`.
   Use this exact template, substituting only the protected release-certificate
   fingerprint. Do not commit a real fingerprint.

   ```json
   [
     {
       "relation": ["delegate_permission/common.handle_all_urls"],
       "target": {
         "namespace": "android_app",
         "package_name": "com.lexiquest.app",
         "sha256_cert_fingerprints": ["<ANDROID_RELEASE_CERT_SHA256>"]
       }
     }
   ]
   ```

6. Run the tracked, read-only validator with
   `ANDROID_RELEASE_CERT_SHA256` provided through the operator's protected
   shell environment. It fetches the public JSON and requires exactly one
   statement, one relation, and one fingerprint equal to the protected value;
   it never prints the value:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass `
     -File tool/cli/validate-firebase-assetlinks.ps1
   ```

7. Confirm the command passes over HTTPS. Do not paste the fingerprint into
   tickets, logs, or CI output.

## Physical-device qualification

Use a release-signed build installed on a physical Android device. Debug keys
do not qualify the production App Link certificate relationship.

1. Reset Android's verification state if needed, then open a valid action URL.
2. Verify Android reports the host as verified:

   ```powershell
   adb shell pm get-app-links com.lexiquest.app
   ```

3. Send a real verification email to a controlled test account, open it on the
   physical test device, and confirm the app consumes it once.
4. Send a real password-reset email to a controlled test account, open it on
   the physical test device, set a valid password, and confirm that the same
   link cannot be consumed again.
5. Confirm an unknown email receives the product's neutral acknowledgement;
   do not use email delivery behavior to reveal whether the account exists.
6. Record the device model, Android version, app version/build ID, timestamps,
   and pass/fail result in the release evidence. Never record passwords,
   action codes, ID tokens, email addresses, or provider diagnostics.

## Local and CI contracts

Run these checks before requesting the remote owner gates:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/firebase-auth-actions.tests.ps1
flutter test test/account/account_models_test.dart test/navigation/account_link_coordinator_test.dart
flutter test integration_test/account_lifecycle_test.dart -d windows --timeout 2m
flutter analyze
flutter test --reporter compact
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify.ps1
```

The final command builds a debug APK locally. It does not establish Firebase
Console, Hosting, email-template, email-delivery, or verified-App-Link parity.
The Windows integration test uses provider-neutral fakes and a typed test link
to cover the local account-recovery UI/router lifecycle; it does not prove real
Firebase, email delivery, or Android intent delivery.
`--timeout 2m` is a per-test-body timeout only. Run `tool/cli/verify.ps1` for
the additional 120-second Windows process limit, which includes desktop build,
loading, and execution; CI applies the equivalent GNU `timeout` outer bound on
Linux.
