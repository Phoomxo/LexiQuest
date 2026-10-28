# Task 7 implementer report

## Commit

`1c6ac76 feat: add password change and guest upgrade`

`bf2ec36 fix: make account credential transitions lifecycle-safe`

## Review remediation

- Password completion now checks `mounted` before accessing controllers after
  an await and clears the current password after every completed gateway
  attempt while mounted. Coverage includes stale-auth clearing, pushed-route
  success pop, all three validation messages, and completion after route
  disposal with a pending completer.
- Guest linking now persists the resulting session before the handoff so the
  registration identity is locked after a successful Firebase link. The
  handoff has an explicit at-most-once delivery contract: a callback that
  records then throws is not reinvoked by a retry; the same stable linked
  session resumes profile provisioning without relinking or creating another
  account. Plan 3 must make its durable migration idempotent/recoverable.
- `GuestUpgradeHandoff` is required in `AppDependencies`, `RegisterScreen`,
  and the session-gate path. Production explicitly injects the Plan 2 no-op.
  Router/bootstrap propagation, anonymous profile navigation, and typed
  change-password construction/bad-argument coverage were added.

## Scope delivered

- Added the typed `/change-password` route and a password-change screen that
  validates current password, new password, and confirmation; it passes the
  current password unchanged to `AccountGateway.changePassword`, clears every
  password field on success, and returns to the previous route.
- Added a profile account section with Thai change-password, sign-out, and
  anonymous-account-upgrade actions.
- Registration now upgrades an existing anonymous Firebase session through
  `upgradeAnonymous` instead of creating a second account. The `GuestUpgradeHandoff`
  receives the exact previous UID and resulting session. The Plan 2 production
  bootstrap explicitly injects the no-op handoff; no data migration occurs
  until Plan 3.
- Added the safe `email-already-in-use` mapping. Failed upgrades do not sign
  out the guest or invoke a migration handoff.

## TDD evidence

The requested focused suite was run before implementation and was RED because
the change-password screen, guest-upgrade handoff type/parameter, and profile
account-gateway injection did not exist. The test runner reported those exact
missing symbols and exited 1.

After implementation, the same focused command passed all seven tests:

```powershell
flutter test test/screens/change_password_screen_test.dart test/account/guest_upgrade_test.dart test/screens/profile_settings_screen_test.dart
```

## Verification

- Focused Task 7 suite: PASS (7 tests).
- `flutter analyze`: PASS (`No issues found!`).
- `flutter test --reporter compact`: 770 tests passed, 1 failed outside Task 7.
  The reproducible failure is
  `test/screens/production_shell_navigation_test.dart` (`drawer category item
  reaches CategoriesPage`): `CategoriesPage` eagerly constructs
  `FirestoreDefaultCategoryStore`, which accesses `FirebaseFirestore.instance`
  before Firebase is initialized in that test. No Task 7 file is in the stack,
  and the unrelated defect was left unchanged.

## Safety notes

- Firebase performs current-password reauthentication before password update
  through the existing gateway implementation.
- Credentials are obscured, are never logged, and are cleared after successful
  password change.
- No Codex Security workflow was used, and the task ledger was not edited.
