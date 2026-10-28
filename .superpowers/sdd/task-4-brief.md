### Task 4: Complete sign-in, sign-out, and guest entry

**Files:**
- Modify: `lib/screens/login_screen.dart`
- Modify: `lib/screens/setting_screen.dart`
- Modify: `lib/services/guest_session_service.dart`
- Modify: `test/screens/login_guest_mode_test.dart`
- Create: `test/screens/login_screen_test.dart`
- Modify: `test/screens/setting_screen_test.dart`

**Interfaces:**
- Consumes injected `AccountGateway`, `GuestSessionService`, and `AppRoute`.
- Produces one guarded login flow without direct Firebase imports.

- [ ] **Step 1: Write failing login/session tests**

Tests assert:

- normalized email is submitted;
- invalid email/empty password do not call gateway;
- unverified session navigates to typed verification route;
- verified session navigates home;
- `invalid-credential`, `user-not-found`, and `wrong-password` display the
  same Thai text;
- double-tap while pending performs one request;
- forgot-password control routes correctly;
- sign-out calls the gateway and removes all routes back to session gate.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/screens/login_screen_test.dart test/screens/login_guest_mode_test.dart test/screens/setting_screen_test.dart
```

Expected: failures because screens still instantiate Firebase/AuthService and
use string routes.

- [ ] **Step 3: Implement injected flow**

`LoginScreen` constructor becomes:

```dart
const LoginScreen({
  super.key,
  required this.accountGateway,
  required this.guestSessionService,
});

final AccountGateway accountGateway;
final GuestSessionService guestSessionService;
```

Use `FilledButton`, `TextFormField`, stable keys
`login-email`, `login-password`, `login-submit`, `login-guest`, and
`login-forgot-password`. Never trim the password; only normalize the email.

Sign-out performs:

```dart
await accountGateway.signOut();
if (!context.mounted) return;
Navigator.of(context).pushNamedAndRemoveUntil(
  AppRoute.sessionGate.path,
  (route) => false,
);
```

- [ ] **Step 4: Run GREEN and full Flutter tests**

```powershell
flutter test test/screens/login_screen_test.dart test/screens/login_guest_mode_test.dart test/screens/setting_screen_test.dart
flutter test --reporter compact
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/screens/login_screen.dart lib/screens/setting_screen.dart lib/services/guest_session_service.dart test/screens
git commit -m "feat: complete typed sign-in and sign-out"
```

---

