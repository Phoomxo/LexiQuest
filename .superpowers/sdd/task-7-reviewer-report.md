# Task 7 re-reviewer report

## Verdict

**APPROVED**

Re-reviewed the complete Task 7 range `e9e4d72..bf2ec36`, including all 1,648
lines of `task-7-rereview-package.diff`, the updated implementer report, the
prior reviewer report, and the live source at `bf2ec36`. All three prior P1
findings, the prior P2 dependency-injection finding, and the identified
coverage gaps are resolved. No new actionable Task 7 finding remains.

## Prior finding resolutions

### Password completion is lifecycle-safe and does not retain the current credential

After `AccountGateway.changePassword` completes, every success and handled
failure path now checks `mounted` before accessing any controller
(`lib/screens/change_password_screen.dart:28-44`). Success clears all three
password fields and pops a pushed route
(`lib/screens/change_password_screen.dart:32-36`). Both known account failures
and unknown failures clear the current-password controller before rendering a
generic mapped error (`lib/screens/change_password_screen.dart:37-44`).
Controllers are still disposed normally at lines 56-61.

The focused regressions prove:

- current, new, and confirmation fields are all required
  (`test/screens/change_password_screen_test.dart:106-124`);
- the current password reaches the gateway untrimmed while the validated new
  password is sent exactly once, and all fields clear on success
  (`test/screens/change_password_screen_test.dart:126-156`);
- `requires-recent-login` renders Thai reauthentication guidance and clears
  the current credential from controller state and rendered UI
  (`test/screens/change_password_screen_test.dart:158-184`);
- successful submission returns to the previous pushed route
  (`test/screens/change_password_screen_test.dart:186-201`);
- completing a pending gateway future after the password route is popped does
  not touch disposed controllers
  (`test/screens/change_password_screen_test.dart:203-223`).

The gateway still constructs an email credential from the exact supplied
current password, reauthenticates, and only then updates the password
(`lib/account/firebase_account_gateway.dart:81-96`). All three fields remain
obscured with autocorrect and suggestions disabled
(`lib/screens/change_password_screen.dart:75-116`).

### Guest post-link identity and handoff delivery are stable across failure/retry

`RegisterScreen` caches both the immutable `GuestUpgradeResult` and resulting
`AccountSession` immediately after one successful anonymous link
(`lib/screens/register_screen.dart:102-108`). Setting `_createdSession` before
awaiting the callback switches the form to recovery mode, making the linked
email read-only and removing password fields
(`lib/screens/register_screen.dart:41-42,152-191`). A retry therefore reuses
the same linked session through the `_createdSession` short circuit and cannot
call either `upgradeAnonymous` or `createAccount` again
(`lib/screens/register_screen.dart:68-76`).

Handoff delivery is explicitly at-most-once: `_handoffAttempted` is set before
the callback is awaited (`lib/screens/register_screen.dart:109-112`).
`GuestUpgradeHandoff` documents that Plan 3's durable migration must be
idempotent and recoverable because registration will not automatically
redeliver a pair after a callback throws
(`lib/account/account_models.dart:60-72`).

The failure/retry regression records the exact previous/resulting UID pair,
throws from the first callback, verifies the linked email is immutable, retries
registration, and proves one link, zero creates, one handoff delivery, and
successful continuation to verification
(`test/account/guest_upgrade_test.dart:183-239`). The ordinary success test
also proves one upgrade and one exact UID-pair handoff
(`test/account/guest_upgrade_test.dart:141-163`).

### The guest handoff is required throughout DI and production chooses the no-op explicitly

The callback has no default in `AppDependencies`
(`lib/runtime/app_dependencies.dart:16-38`), `RegisterScreen`
(`lib/screens/register_screen.dart:10-22`), or `SessionGateScreen`
(`lib/screens/session_gate_screen.dart:12-24`). `AppRouter` propagates the same
required dependency into both the session gate and direct registration route
(`lib/navigation/app_router.dart:22-33,106-125`). The session-gate recovery
path passes it onward to `RegisterScreen`
(`lib/screens/session_gate_screen.dart:47-63`).

Production explicitly selects `noOpGuestUpgradeHandoff`, so Plan 2 performs no
ownership migration (`lib/runtime/app_bootstrap.dart:222-239`). The bootstrap
identity test locks that composition
(`test/runtime/app_bootstrap_test.dart:278-289`), and the router test proves
that the exact injected callback reaches `RegisterScreen`
(`test/navigation/app_router_test.dart:165-186`).

## Route, profile, guest-preservation, and privacy checks

- `AppRoute.changePassword` remains the stable typed
  `/change-password` route. Router coverage now includes construction, rejects
  unexpected arguments, and constructs the screen through the injected account
  gateway (`lib/navigation/app_router.dart:59-65`;
  `test/navigation/app_router_test.dart:118-163`).
- The profile resolves its account gateway from direct injection or
  `AppDependenciesScope` and shows natural Thai actions appropriate to the
  session type (`lib/screens/profile_settings_screen.dart:59-64,146-173`).
  Signed-in action labels and anonymous upgrade navigation are covered
  (`test/screens/profile_settings_screen_test.dart:83-120`).
- The production gateway independently requires the current Firebase user to
  be anonymous before `linkWithCredential`, captures the pre-link UID, and
  returns the resulting session (`lib/account/firebase_account_gateway.dart:99-117`).
- `email-already-in-use` and `credential-already-in-use` map to the same
  non-enumerating Thai conflict message
  (`lib/account/account_error_mapper.dart:22-23`). A failed link never reaches
  the handoff and neither the screen nor gateway signs the guest out. The
  regression proves one failed upgrade, zero account creations, and zero
  sign-outs (`test/account/guest_upgrade_test.dart:165-181`).
- No password, UID pair, account exception, action code, or migration input is
  logged. A focused scan found no `print`, `debugPrint`, developer logger, or
  logger call in the Task 7 production surface. Error UI uses only fixed
  mapped Thai messages.
- The remediation changes only the account handoff contract, router/DI
  propagation, password/register lifecycle state, and focused call-site/tests.
  `git diff --check e9e4d72..bf2ec36` passed.

## Full-suite failure disposition

The previously reported category-navigation failure still reproduces in
isolation:

```powershell
flutter test test/screens/production_shell_navigation_test.dart `
  --plain-name "drawer category item reaches CategoriesPage" `
  --reporter expanded
```

It continues to fail when `CategoriesPage` eagerly constructs
`FirestoreDefaultCategoryStore` and accesses `FirebaseFirestore.instance`
without a default Firebase app
(`lib/screens/main_navigation_screen.dart:93-96`;
`lib/services/category_service.dart:23-25`;
`test/screens/production_shell_navigation_test.dart:198-206`).

Task 7 remediation changed that test only to provide the newly required
no-op handoff to `AppDependencies`
(`test/screens/production_shell_navigation_test.dart:73-83`). The production
category stack and Firebase gateway are unchanged in `1c6ac76..bf2ec36`, and
the isolated stack remains identical. This pre-existing failure is therefore
not introduced or exposed by Task 7 and does not block this task's approval,
although the branch cannot claim a fully green Flutter suite until the
category testability defect is fixed in its own scope.

## Fresh bounded verification

- `flutter test test/screens/change_password_screen_test.dart test/account/guest_upgrade_test.dart test/screens/profile_settings_screen_test.dart test/navigation/app_router_test.dart test/runtime/app_bootstrap_test.dart test/screens/session_gate_screen_test.dart test/screens/registration_flow_test.dart --reporter compact`
  — PASS, 43/43.
- `flutter analyze` — PASS, `No issues found!`.
- Isolated production-shell category navigation test — FAIL only with the
  documented pre-existing `[core/no-app]` category construction defect.
- `git diff --check e9e4d72..bf2ec36` — PASS.
- Focused Task 7 logging scan — no matches.
- No implementation file was edited, no commit was created, and no Codex
  Security workflow was used.
