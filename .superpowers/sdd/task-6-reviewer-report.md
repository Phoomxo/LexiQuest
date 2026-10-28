# Task 6 reviewer report

## Verdict

**APPROVED**

Re-reviewed the complete Task 6 range `958e410..e9e4d72`, including
`task-6-rereview-package.diff`, the updated implementer report, the prior
review report, and the live source at `e9e4d72`. Both prior P1 findings and all
three prior coverage gaps are resolved. No new blocking findings were found.

## Prior P1 resolutions

### Cold initial/stream duplication is handled once

`AccountLinkCoordinator` records a parsed `AccountActionLink` before
navigating and ignores the same mode/code pair thereafter
(`lib/navigation/account_link_coordinator.dart:28,37-52`).
`AccountActionLink` equality and hashing include both mode and code
(`lib/account/account_models.dart:31-36`), so this suppresses the initial-link
event repeated by `uriLinkStream` without suppressing a later action with a
different code.

Focused regressions now prove:

- repeated cold reset links navigate once
  (`test/navigation/account_link_coordinator_test.dart:35-53`);
- repeated cold verify-email links navigate once
  (`test/navigation/account_link_coordinator_test.dart:55-73`);
- a later distinct reset action remains routable after the duplicate is
  suppressed (`test/navigation/account_link_coordinator_test.dart:75-105`);
- warm verification links still route with typed arguments
  (`test/navigation/account_link_coordinator_test.dart:107-132`).

This resolves the original double reset-route/code-verification and double
verify-action application risk.

### Confirmation-time expired/invalid codes enter recovery

`ResetPasswordScreen` now classifies `expired-action-code` and
`invalid-action-code` through one helper
(`lib/screens/reset_password_screen.dart:101-102`). If either is returned by
`confirmPasswordReset`, it disables submission and switches to the explicit
request-new-link state (`lib/screens/reset_password_screen.dart:84-92`), whose
form replacement and recovery navigation are at
`lib/screens/reset_password_screen.dart:127-144`.

The fake gateway can inject confirmation failures
(`test/screens/reset_password_screen_test.dart:8-14,28-36`), and separate
parameterized tests prove both expired and invalid confirmation failures make
the submit form unavailable and expose the recovery action
(`test/screens/reset_password_screen_test.dart:182-209`).

## Prior coverage-gap resolutions

- Verify-email action handling remains provider-neutral through
  `AccountGateway.applyVerificationCode`
  (`lib/navigation/app_router.dart:127-168`). The new success test proves the
  code is applied once and navigation is cleared to login
  (`test/navigation/app_router_test.dart:150-180`). The failure test proves one
  application attempt, no login transition, and no action-code rendering
  (`test/navigation/app_router_test.dart:182-217`).
- The Android manifest retains one correct action filter with
  `autoVerify=true`, `VIEW`, `DEFAULT`, `BROWSABLE`, HTTPS, Hosting host
  `vocab-learning-app-219ef.web.app`, and `/auth/action`
  (`android/app/src/main/AndroidManifest.xml:37-45`). The persisted contract
  test locks every required value
  (`test/config/android_network_security_test.dart:59-81`); a separate
  read-only XML parse also confirmed those nodes are co-located in exactly one
  `autoVerify` filter.
- The parser still requires HTTPS, the exact Hosting host and path, a
  non-empty code, and one of the two accepted modes
  (`lib/account/account_models.dart:12-28`). An explicit `recoverEmail`
  negative case now proves unsupported modes are rejected
  (`test/account/account_models_test.dart:49-57`).

## Privacy, provider boundary, and unchanged Task 6 requirements

- Task 6 production UI/navigation imports no Firebase Auth implementation;
  forgot, reset, and verify-action behavior uses `AccountGateway`.
- No `print`, `debugPrint`, logger, URL/action-code logging, `page.link`,
  `firebase_dynamic_links`, or Dynamic Links reference exists in the Task 6
  production/remediation scope. Action codes are used only for parsing,
  in-memory deduplication, typed handoff, and gateway calls; failure UI remains
  generic.
- The exact neutral acknowledgement and non-enumerating success,
  `user-not-found`, and `email-not-found` behavior are unchanged
  (`lib/account/account_error_mapper.dart:4-5`;
  `lib/screens/forgot_password_screen.dart:51-74`).
- Network failures still report failure and retain only the normalized email
  for explicit retry (`lib/screens/forgot_password_screen.dart:54-63,128-135`).
- Reset submission still requires successful code verification, password
  policy and confirmation validation, and an in-flight single-submit guard
  (`lib/screens/reset_password_screen.dart:25-39,52-78,173-181`).
- `app_links: ^7.2.1` remains a direct dependency locked at 7.2.1
  (`pubspec.yaml:32`, `pubspec.lock:28-34`), and generated platform
  registrants remain included.
- The remediation commit changes only the coordinator, reset screen, and five
  focused test files. `git diff --check d68ba20..e9e4d72` passed.

## Fresh bounded verification

- `flutter test test/screens/forgot_password_screen_test.dart test/screens/reset_password_screen_test.dart test/navigation/account_link_coordinator_test.dart test/navigation/app_router_test.dart test/account/account_models_test.dart test/account/account_error_mapper_test.dart test/config/android_network_security_test.dart`
  — PASS, 43 tests.
- Targeted `flutter analyze` over the 17 Task 6 production/test files
  — PASS, no issues.
- Read-only semantic XML validation
  — PASS: exactly one `autoVerify=true` filter containing the required action,
  categories, scheme, host, and path prefix.
- Focused provider/privacy/Dynamic Links pattern audit
  — PASS, no prohibited references or logging calls.
- `git diff --check d68ba20..e9e4d72`
  — PASS.
- No Codex Security workflow was invoked.

