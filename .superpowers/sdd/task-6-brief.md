### Task 6: Add neutral forgot-password and in-app reset action handling

**Files:**
- Modify: `pubspec.yaml`
- Generated: `pubspec.lock` and platform plugin registrants
- Create: `lib/screens/forgot_password_screen.dart`
- Create: `lib/screens/reset_password_screen.dart`
- Create: `lib/navigation/account_link_coordinator.dart`
- Modify: `lib/main.dart`
- Modify: `lib/navigation/app_router.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `test/screens/forgot_password_screen_test.dart`
- Create: `test/screens/reset_password_screen_test.dart`
- Create: `test/navigation/account_link_coordinator_test.dart`

**Interfaces:**
- Adds direct dependency `app_links: ^7.2.1`.
- Consumes `AccountActionLink` and `AccountGateway`.
- Produces cold/warm reset/verify navigation.

- [ ] **Step 1: Write failing recovery and link tests**

Tests assert:

- forgot screen always displays
  `หากอีเมลนี้มีบัญชี เราได้ส่งลิงก์ตั้งรหัสผ่านใหม่แล้ว` after accepted,
  `user-not-found`, or `email-not-found`;
- invalid local email is rejected before the gateway;
- network errors are not presented as accepted;
- reset screen calls `verifyPasswordResetCode(code)` before enabling submit;
- password and confirmation policy is enforced;
- `confirmPasswordReset` is called once and routes to login;
- expired/invalid code displays a request-new-link action;
- warm and cold action links navigate to the typed reset/verification route.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/screens/forgot_password_screen_test.dart test/screens/reset_password_screen_test.dart test/navigation/account_link_coordinator_test.dart
```

Expected: missing screens/coordinator.

- [ ] **Step 3: Implement recovery and App Links**

Add:

```yaml
app_links: ^7.2.1
```

Instantiate `AppLinks` before `runApp`, pass it to
`AccountLinkCoordinator`, and subscribe to `uriLinkStream`. Invalid/foreign
links are ignored without logging the URL or action code.

Android intent filter:

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data
        android:scheme="https"
        android:host="vocab-learning-app-219ef.web.app"
        android:pathPrefix="/auth/action" />
</intent-filter>
```

Recovery submit uses a 60-second cooldown and preserves the normalized email
for an explicit retry after network failure.

- [ ] **Step 4: Run GREEN and Android manifest contract**

```powershell
flutter test test/screens/forgot_password_screen_test.dart test/screens/reset_password_screen_test.dart test/navigation/account_link_coordinator_test.dart
flutter test test/config/android_network_security_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add pubspec.yaml pubspec.lock lib/screens lib/navigation lib/main.dart android/app/src/main/AndroidManifest.xml test linux/flutter macos/Flutter windows/flutter
git commit -m "feat: add password recovery action links"
```

---

