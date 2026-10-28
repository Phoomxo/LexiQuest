# Task 8 implementer report

## Commits

- `7384608 fix: defer category Firebase construction`
- `ac0f4aa test: qualify the complete account lifecycle`
- `d2ed02d fix: make account deployment gates reproducible`
- `7a258a0 fix: enforce exact account release gates`
- `655b323 fix: enforce exact account release gates`

## Scope delivered

- Added checked-in Firebase Auth/Android App Link contracts, a provider-neutral
  account-recovery UI/router integration test, CI coverage, and
  production-release pre-build gates.
- Added the operator runbook at
  `docs/runbooks/firebase-auth-actions.md`; the workflow validates the
  colon-separated `ANDROID_RELEASE_CERT_SHA256` format without printing it
  and does not deploy Hosting.
- The runbook now invokes the tracked, read-only
  `tool/cli/validate-firebase-assetlinks.ps1` validator. It accepts exactly one
  statement, relation, target namespace/package, and certificate fingerprint;
  each must equal the release contract. It never prints the protected
  fingerprint and performs no deploy or remote mutation.
- The account-recovery integration test launches `MyApp`, submits a forgot
  password request, sends a typed Hosting reset URI through the coordinator and
  router, verifies and confirms the reset exactly once, and returns to login.
  The verifier runs it on Windows through a real 120-second process deadline
  covering build, load, and execution; CI wraps the Linux command in GNU
  `timeout --kill-after=5s 120s`. Flutter's `--timeout 2m` remains a separate
  per-test-body limit. It is explicitly not evidence of Firebase, real email,
  or Android intent delivery.
- Repaired the pre-existing CategoriesPage test failure by making the default
  Firestore category store lazy. The regression test was first RED because
  `CategoryService()` accessed Firebase before initialization, then GREEN.

## TDD evidence

- Task 8 repository-contract RED:
  `firebase-auth-actions.tests.ps1` was absent, so the required command
  exited nonzero with a missing-file error.
- CategoriesPage regression RED:
  `constructs without resolving Firebase until default seeding runs` failed
  with `[core/no-app] No Firebase App '[DEFAULT]' has been created`.
- GREEN:
  - Firebase Auth action contracts: 41 passed, 0 failed.
  - CI workflow contracts: 116 passed, 0 failed.
  - Focused account/action-link and CategoriesPage regressions: 17 passed.
  - Windows account-recovery integration lifecycle: 1 passed.
- Exact-gate remediation RED/GREEN:
  - The initial asset-links fixture harness failed while the validator was
    absent; after implementation, 8/8 behavioral fixtures pass: valid input
    passes while extra/wrong relation, namespace, package, statement, and
    fingerprint forms fail.
  - The initial Windows wrapper exposed an empty `Start-Process` exit code for
    the Flutter child. Replacing it with `ProcessStartInfo` made the child exit
    code observable and preserves a `WaitForExit(120000)` whole-process bound;
    the focused Windows lifecycle run then passed 1/1 in about 39 seconds.

## Clean-HEAD verification

`powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify.ps1`
passed all 11 phases at clean committed HEAD `ac0f4aa`, including static
analysis, 781 Flutter tests, backend suites, contract suites, and the Android
debug APK build.

After the exact-gate remediation, the same command passed every listed phase
at clean committed HEAD `655b323`: 118 CI contracts, 59 Firebase Auth action
contracts, 8 asset-links validator fixtures, Flutter analysis, 781 Flutter
tests, the bounded Windows account-recovery integration lifecycle, backend and
emulator suites, CPU-only suites, and the Android debug APK build.

| Artifact | Value |
| --- | --- |
| APK | `C:\Users\Phet\Documents\LexiQuest\.worktrees\release-v0.1-complete-system\build\app\outputs\flutter-apk\app-debug.apk` |
| SHA-256 | `25AA9BDB0A51D981FC0BCF7EEAD6EF3607A34EF813F2665A80782459B2F67A6D` |
| Build ID | `655b323` |

## Remote production owner gates — not locally passed

1. Firebase owner: add `vocab-learning-app-219ef.web.app` to Firebase Auth
   authorized domains and configure
   `https://vocab-learning-app-219ef.web.app/auth/action` as the custom email
   action handler.
2. Android release owner: set the protected production variable
   `ANDROID_RELEASE_CERT_SHA256` to the exact release certificate fingerprint.
3. Hosting owner: publish and verify
   `https://vocab-learning-app-219ef.web.app/.well-known/assetlinks.json` for
   `com.lexiquest.app` and the protected release certificate.
4. Firebase owner: review the reset and verification templates, then send and
   consume real emails on a physical release-signed Android device; verify via
   `adb shell pm get-app-links com.lexiquest.app`.

No Firebase Hosting deployment, Firebase Console mutation, remote email
delivery, or verified Android App Link parity was attempted or claimed.
