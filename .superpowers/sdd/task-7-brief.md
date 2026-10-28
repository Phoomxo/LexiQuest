### Task 7: Add change-password and anonymous-account upgrade

**Files:**
- Create: `lib/screens/change_password_screen.dart`
- Modify: `lib/screens/profile_settings_screen.dart`
- Modify: `lib/screens/register_screen.dart`
- Modify: `lib/navigation/app_router.dart`
- Create: `test/screens/change_password_screen_test.dart`
- Create: `test/account/guest_upgrade_test.dart`
- Modify: `test/screens/profile_settings_screen_test.dart`

**Interfaces:**
- Consumes `AccountGateway.changePassword` and `upgradeAnonymous`.
- Produces recent-login reauthentication and a stable old/new UID migration
  handoff for Plan 3.

- [ ] **Step 1: Write failing tests**

Tests assert:

- current password, new password, and confirmation are required;
- current password is never displayed or retained after completion;
- gateway receives the untrimmed current password and validated new password;
- `requires-recent-login` maps to a reauthentication prompt;
- success clears fields and routes back;
- anonymous registration calls `upgradeAnonymous` rather than
  `createAccount`;
- upgrade result exposes both previous UID and resulting session for Plan 3;
- `email-already-in-use` does not discard or sign out the guest session.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/screens/change_password_screen_test.dart test/account/guest_upgrade_test.dart test/screens/profile_settings_screen_test.dart
```

Expected: missing change-password UI and upgrade branch.

- [ ] **Step 3: Implement the tested workflows**

Add an account section to profile with natural Thai labels:

- `เปลี่ยนรหัสผ่าน`
- `ออกจากระบบ`
- for anonymous users: `สร้างบัญชีเพื่อสำรองข้อมูล`

After upgrade, call a required callback:

```dart
typedef GuestUpgradeHandoff = Future<void> Function(
  String previousUid,
  AccountSession session,
);
```

The default Plan 2 handoff records no data movement; production bootstrap must
inject a handoff implementation. Plan 3 replaces it with the Drift ownership
migration before remote sync is enabled.

- [ ] **Step 4: Run GREEN and full Flutter tests**

```powershell
flutter test test/screens/change_password_screen_test.dart test/account/guest_upgrade_test.dart test/screens/profile_settings_screen_test.dart
flutter analyze
flutter test --reporter compact
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/account lib/screens lib/navigation test
git commit -m "feat: add password change and guest upgrade"
```

---

