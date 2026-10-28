# Task 8 second re-reviewer report

## Verdict

**APPROVED**

Re-reviewed the complete Task 8 range `bf2ec36..655b323`, all 949 lines of
`task-8-rereview-2-package.diff`, the Task 8 brief, the updated implementer
report, the prior findings, and the live committed source at full HEAD
`655b3235a73642800da22dd1a4e619b3e7765a2b`.

Both prior findings are resolved. The Digital Asset Links gate now has one
tracked, read-only validator that enforces the exact single-statement contract
and is exercised by eight behavioral fixtures. The account-recovery
integration test remains a meaningful provider-neutral `MyApp` UI/router
lifecycle, while local Windows and CI Linux execution now have real
whole-process deadlines distinct from Flutter's per-test timeout. No new
actionable Task 8 finding remains.

## Prior finding resolutions

### Exact Digital Asset Links document and fingerprint validation

The owner runbook retains the exact JSON template and states that only the
protected release-certificate fingerprint may be substituted
(`docs/runbooks/firebase-auth-actions.md:43-59`). It now delegates verification
to the tracked script and truthfully describes one statement, one relation,
one exact fingerprint, no value printing, and read-only behavior
(`docs/runbooks/firebase-auth-actions.md:61-76`).

`tool/cli/validate-firebase-assetlinks.ps1` enforces the complete contract:

- the expected fingerprint must be a non-empty, colon-separated 32-byte
  SHA-256 value (`tool/cli/validate-firebase-assetlinks.ps1:30-35`);
- without a supplied fixture, only HTTPS, the exact Hosting host, exact
  `/.well-known/assetlinks.json` path, and no query/fragment are accepted before
  the public GET (`tool/cli/validate-firebase-assetlinks.ps1:37-47`);
- the response must be a JSON array containing exactly one statement
  (`tool/cli/validate-firebase-assetlinks.ps1:49-55`);
- the statement must contain exactly one case-exact
  `delegate_permission/common.handle_all_urls` relation, namespace
  `android_app`, package `com.lexiquest.app`, and exactly one fingerprint equal
  to the protected expected value
  (`tool/cli/validate-firebase-assetlinks.ps1:57-67`);
- output is limited to fixed success/failure messages, and `-Quiet` emits
  neither (`tool/cli/validate-firebase-assetlinks.ps1:69-78`).

The behavioral fixture suite builds documents independently and invokes the
real validator with supplied JSON, so it performs no network request
(`tool/cli/tests/firebase-assetlinks-validator.tests.ps1:19-53`). Its eight
cases prove:

1. a valid single approved statement passes;
2. an extra relation fails;
3. a wrong relation fails;
4. a wrong namespace fails;
5. a wrong package fails;
6. an extra statement fails;
7. an extra fingerprint fails;
8. a wrong fingerprint fails.

The cases and environment restoration are at
`tool/cli/tests/firebase-assetlinks-validator.tests.ps1:55-71`.
The suite is wired into CI, production pre-build contracts, and the local full
verifier (`.github/workflows/ci.yml:40-56`;
`.github/workflows/production-release.yml:54-60`;
`tool/cli/verify.ps1:135-154`).

Fresh independent execution reported 8/8 PASS. A separate valid/extra-
fingerprint check used distinct 32-byte marker values and captured both
success and failure paths:

- valid document: exit `0`;
- document containing the approved plus an unapproved fingerprint: exit `1`;
- neither output contained either marker fingerprint;
- only the fixed `assetlinks.json contract verified.` /
  `assetlinks.json contract validation failed.` messages were emitted;
- tracked Git state remained clean.

A focused source scan found only the fixed-host `Invoke-WebRequest` GET at
`tool/cli/validate-firebase-assetlinks.ps1:46`; there is no deploy, write,
delete, POST, PUT, PATCH, credential, or remote-mutation operation.

The prior P1 false-acceptance and literal-only-contract defects are resolved.

### Unique recovery lifecycle and genuine whole-process limits

The provider-neutral integration test still launches production `MyApp` with
injected dependencies, traverses login and forgot-password UI, normalizes the
email, delivers a typed Hosting reset action through the coordinator/router,
verifies the code before enabling submission, rejects a second pending submit,
confirms exactly once, and returns to login
(`integration_test/account_lifecycle_test.dart:85-101,106-172`). This remains
meaningfully distinct from the lower-level action-link unit tests.

The local verifier now launches the entire Flutter command as a child process
using `ProcessStartInfo`, with the repository as its working directory
(`tool/cli/verify.ps1:72-92`). `WaitForExit(120000)` begins immediately after
process start, so the deadline includes desktop compilation, suite loading,
application startup, and execution. At deadline it invokes
`taskkill /PID ... /T /F` to terminate the `cmd`/Flutter descendant tree, uses
`Stop-Process` as a parent fallback, and fails the phase
(`tool/cli/verify.ps1:93-108`). A nonzero child exit also fails the phase at
lines 99-100. Phase `06.0` invokes this wrapper rather than a raw Flutter
command (`tool/cli/verify.ps1:202-208`).

Fresh independent execution extracted and invoked the tracked
`Invoke-AccountRecoveryIntegration` function. It built the Windows desktop
application, ran the lifecycle 1/1, and exited `0` in 40.51 seconds with clean
tracked state. This directly exercises the successful whole-process wrapper,
not merely the underlying Flutter test.

CI wraps the complete Linux Flutter process in GNU
`timeout --kill-after=5s 120s`, retaining `--timeout 2m` only for the
individual test body (`.github/workflows/ci.yml:95-102`). The CI contract locks
the exact outer and inner timeout command and runs the validator fixtures
(`tool/cli/tests/ci-workflow.tests.ps1:125-146`). The Task 8 repository
contract also locks `ProcessStartInfo`, `WaitForExit(120000)`, forced
termination, Windows device/file arguments, the per-test flag, and the Linux
outer deadline
(`tool/cli/tests/firebase-auth-actions.tests.ps1:95-106`).

The runbook now explicitly says `--timeout 2m` is per test body and that the
full verifier supplies the additional Windows process limit covering build,
load, and execution, with the equivalent Linux outer bound in CI
(`docs/runbooks/firebase-auth-actions.md:101-119`). The updated implementer
report uses the same accurate distinction.

The prior P2 unbounded/mischaracterized-timeout defect is resolved. Linux
runtime success is correctly left to CI; this Windows-hosted re-review does not
claim a local Linux execution.

## Auth, manifest, CI, release, and owner-boundary audit

- Auth action parsing remains HTTPS-only and restricted to the exact Hosting
  host/path, supported modes, and non-empty action code
  (`lib/account/account_models.dart:3-29`).
- The coordinator deduplicates action `(mode, code)` values and uses typed
  reset/verification routes without logging the URI or code
  (`lib/navigation/account_link_coordinator.dart:25-58`).
- The source manifest retains `android:autoVerify="true"`, HTTPS, exact Hosting
  host, and `/auth/action`
  (`android/app/src/main/AndroidManifest.xml:37-45`). Fresh merged-APK
  inspection confirmed the same values.
- Application ID remains `com.lexiquest.app`
  (`android/app/build.gradle.kts:21-37`); `app_links` remains direct and no live
  `firebase_dynamic_links` dependency exists (`pubspec.yaml:11-32`).
- CI runs the repository and executable validator fixtures, focused action-link
  tests, bounded integration test, analysis, default Flutter suite, backend
  suites, and Android build in order
  (`.github/workflows/ci.yml:40-56,83-133`).
- Production release runs both Task 8 contract suites and focused action-link
  tests before validating the protected fingerprint format and before the
  signed AAB build
  (`.github/workflows/production-release.yml:51-69,107-117`).
- The protected fingerprint is never embedded or printed; production emits
  only a fixed format error.
- No `firebase deploy`, Hosting deployment action/credential, Firebase Console
  mutation, email send, or remote configuration write exists in Task 8
  workflows or validators.
- The runbook explicitly leaves authorized domain, custom handler, reset and
  verification templates, Hosting publication, exact release certificate,
  release-signed physical Android email consumption, and
  `pm get-app-links com.lexiquest.app` as unpassed owner gates
  (`docs/runbooks/firebase-auth-actions.md:19-31,33-42,78-100`).
- Local/debug success is explicitly not presented as Firebase, email, Hosting,
  Android-intent, or verified production App Link evidence
  (`docs/runbooks/firebase-auth-actions.md:3-8,111-119`).
- The implementer report likewise states that no Firebase Hosting deployment,
  Firebase Console mutation, remote email delivery, or verified Android App
  Link parity was attempted or claimed.

## Category lazy-construction scope

The earlier narrow category remediation remains unchanged. `CategoryService`
defers default Firestore store construction until default seeding requests it
(`lib/services/category_service.dart:78-84,331-348`), and the construction
regression remains focused at
`test/services/category_default_seeding_test.dart:35-38`. No unrelated
category behavior was added in the second remediation.

## Fresh verification and APK provenance

- Pre-check and post-check tracked state: clean.
- Full HEAD:
  `655b3235a73642800da22dd1a4e619b3e7765a2b`.
- `git diff --check d2ed02d..655b323` — PASS.
- `tool/cli/tests/firebase-assetlinks-validator.tests.ps1` — PASS, 8/8.
- `tool/cli/tests/firebase-auth-actions.tests.ps1` — PASS, 59/59.
- `tool/cli/tests/ci-workflow.tests.ps1` — PASS, 118/118.
- Independent valid/invalid validator leak and clean-state check — PASS.
- Tracked Windows `ProcessStartInfo` integration wrapper — PASS, 1/1 in
  40.51 seconds.
- The full verifier was not redundantly rerun after its unchanged constituent
  contracts/integration checks passed. The updated implementer report records
  the clean-HEAD full pass at `655b323`, including analysis, 781 Flutter tests,
  backend/emulator suites, CPU suites, bounded integration, and APK build.
- APK:
  `build/app/outputs/flutter-apk/app-debug.apk`;
  186,947,234 bytes; last write
  `2026-07-29T22:30:34.0548180Z`;
  SHA-256
  `25AA9BDB0A51D981FC0BCF7EEAD6EF3607A34EF813F2665A80782459B2F67A6D`.
- Fresh `aapt dump badging` reports package `com.lexiquest.app`, version
  `0.1.0`/code `1`; `aapt dump xmltree` confirms merged auto-verify,
  Hosting-host, and action-path values.
- Fresh `apksigner verify --verbose --print-certs` reports a valid v2 APK
  signature with one `CN=Android Debug` signer. This is correctly a debug
  artifact, not a production release-signed APK.
- Direct decompressed-kernel inspection found build ID `655b323` and no
  `655b323-dirty`.
- APK path, hash, and build ID exactly match the updated implementer report at
  the same clean committed HEAD.

No implementation file was edited, no commit was created, no Firebase/Hosting
mutation or remote email operation was performed, and no Codex Security
workflow was used.
