# Plan 2 final-review consolidated fix report

## Status

All three Important findings and bounded Minor findings 1 and 2 are fixed on
`release/v0.1-complete-system` from base `b45032f`. Minor 3 is deferred for the
reason recorded below. No Codex Security, Security Scan, or Deep Scan workflow
was used.

## Root-cause confirmation

### Important 1 — provisioning availability was collapsed into `bool`

- `SessionGateScreen` treated every result other than literal `true`, including
  a failed `Future`, as incomplete and opened `RegisterScreen`.
- `FirestoreAccountProfileWriter` performed only a remote document read, so no
  durable completion evidence existed for offline startup.
- The working local-first pattern already used by the repository is
  `SharedPreferences`-backed state with a fresh-instance restoration test.
- Fix: `AccountProvisioningState` now distinguishes `complete`, `incomplete`,
  and `unavailable`. Successful provisioning is recorded per UID in
  `SharedPreferences`. A remote `incomplete` result remains authoritative and
  overrides stale local completion; only a failed remote lookup may fall back
  to a durable completed UID. A no-cache failure shows a retry boundary and is
  neither admitted to the shell nor mislabeled as incomplete.

### Important 2 — screens owned duplicate validation rules

- Reset password used an ASCII-only password regular expression even though
  register/change-password and `AccountValidation` accept documented Thai
  letters and digits.
- Login and recovery each owned a stricter, duplicate email expression and
  manual normalization.
- Fix: reset password delegates password and confirmation checks to
  `AccountValidation`; login and recovery delegate email validation and
  normalization to the same policy. A cross-screen contract test covers
  register/reset/change and register/login/recovery with the same cases.

### Important 3 — App Links subscribed after the initial await

- `AccountLinkCoordinator.start()` awaited `getInitialLink()` before listening
  to `uriLinkStream`, creating a warm-link loss window.
- An initial-link exception skipped subscription, and the stream had no error
  handler.
- Fix: subscription is established first; initial lookup and stream errors are
  contained; parsing/navigation remains deduplicated and guarded. No URL,
  email, action code, token, or provider diagnostic is logged.

### Minor 1 — settings sign-out lacked the guarded UI pattern

- `SettingScreen._logout` awaited `signOut()` without a pending guard or error
  boundary, unlike the existing guarded profile-settings path.
- Fix: repeated taps are blocked, typed failures use `AccountErrorMapper`,
  unexpected failures use the safe unknown message, and navigation remains on
  settings when sign-out fails.

### Minor 2 — legacy provider-specific error translation remained live

- Repository search found `AuthService` consumers only in its own tests and the
  full-system audit assertion.
- Fix: the audit now asserts `AccountErrorMapper`; the legacy service and its
  two test files are deleted.

## TDD RED evidence

### Important 1

Command:

```text
flutter test test/screens/session_gate_screen_test.dart
```

Result: exit 1, `+8 -2`. The no-cache lookup failure incorrectly rendered
`RegisterScreen`, and no `provisioning-retry` control existed for restored
connectivity.

### Important 2

Command:

```text
flutter test test/screens/reset_password_screen_test.dart test/screens/login_screen_test.dart test/screens/forgot_password_screen_test.dart
```

Result: exit 1, `+21 -3`. Thai password reset produced no gateway call, and
login/recovery rendered their duplicate email error instead of the centralized
policy message.

### Important 3

Command:

```text
flutter test test/navigation/account_link_coordinator_test.dart
```

Result: exit 1, `+6 -3`. A warm link emitted during delayed initial lookup was
lost, the initial-link failure escaped, and the stream error reached the
uncaught zone.

## GREEN and focused gate evidence

The first consolidated run reached 99/100 and exposed one implementation issue:
the retry callback used an expression-bodied `setState` whose assignment
returned the new `Future`. The callback was changed to a synchronous block and
the complete bounded gate was rerun.

Command:

```text
flutter test test/account/account_profile_provisioner_test.dart test/account/account_validation_test.dart test/account/guest_upgrade_test.dart test/navigation/account_link_coordinator_test.dart test/navigation/app_router_test.dart test/screens/account_validation_contract_test.dart test/screens/session_gate_screen_test.dart test/screens/otp_screen_test.dart test/screens/registration_flow_test.dart test/screens/reset_password_screen_test.dart test/screens/login_screen_test.dart test/screens/forgot_password_screen_test.dart test/screens/change_password_screen_test.dart test/screens/setting_screen_test.dart test/screens/full_system_audit_test.dart
```

Result: exit 0, `+100`, `All tests passed!`

Focused static gate:

```text
flutter analyze <21 changed account/navigation/settings source and test files>
```

Result: exit 0, `No issues found!`

`git diff --check` also exited 0.

## Files changed

Production:

- `lib/account/account_profile_provisioner.dart`
- `lib/navigation/account_link_coordinator.dart`
- `lib/screens/forgot_password_screen.dart`
- `lib/screens/login_screen.dart`
- `lib/screens/otp_screen.dart`
- `lib/screens/reset_password_screen.dart`
- `lib/screens/session_gate_screen.dart`
- `lib/screens/setting_screen.dart`
- deleted `lib/services/auth_service.dart`

Tests:

- `test/account/account_profile_provisioner_test.dart`
- `test/account/guest_upgrade_test.dart`
- `test/navigation/account_link_coordinator_test.dart`
- `test/navigation/app_router_test.dart`
- added `test/screens/account_validation_contract_test.dart`
- `test/screens/forgot_password_screen_test.dart`
- `test/screens/full_system_audit_test.dart`
- `test/screens/login_screen_test.dart`
- `test/screens/otp_screen_test.dart`
- `test/screens/registration_flow_test.dart`
- `test/screens/reset_password_screen_test.dart`
- `test/screens/session_gate_screen_test.dart`
- `test/screens/setting_screen_test.dart`
- deleted `test/services/auth_service_error_handling_test.dart`
- deleted `test/services/auth_service_test.dart`

## Self-review

- Confirmed remote `incomplete` cannot be overridden by stale local state.
- Confirmed verified users with durable completion can enter the local shell
  when the remote lookup fails.
- Confirmed unknown/no-cache failures enter neither shell nor registration
  recovery and can retry after connectivity returns.
- Confirmed App Links subscribes before the initial lookup and all tested error
  boundaries stay active without sensitive logging.
- Confirmed all credential-screen validators now use the central policy at the
  required lifecycle points.
- Confirmed settings failure paths do not clear the route stack.
- Confirmed no tracked `AuthService` or `services/auth_service` reference
  remains under `lib/` or `test/`.
- Focused search found no new `print`, `debugPrint`, logger, or developer-log
  call in the changed production files.
- Diff review found no build/cache enumeration, unrelated refactor, generated
  file, or dependency change.

## Deferred finding

### Minor 3 — production Firebase adapter contract depth

Deferred to the post-Prototype provider-adapter hardening phase. A useful seam
cannot be introduced narrowly: Firebase `User`, `UserCredential`,
reauthentication credentials, anonymous linking, reload state, and every
gateway operation would all need a provider-neutral facade or an Auth emulator.
Wrapping only one or two methods would leave the review finding materially
unresolved, while wrapping all methods is a broad adapter refactor outside this
bounded account/navigation/settings wave.

Target phase: immediately after the Prototype baseline, before any production
Firebase qualification claim. Scope should be either:

1. a complete injectable Firebase-auth facade covering every gateway method,
   session mapping, missing-user behavior, and sanitized exception translation;
   or
2. bounded Firebase Auth emulator contract tests covering the same behavior.
