### Task 5: Replace registration duplicates with one verified workflow

**Files:**
- Modify: `lib/screens/register_screen.dart`
- Modify: `lib/screens/otp_screen.dart`
- Delete: `lib/screens/register_form_screen.dart`
- Create: `lib/account/account_profile_provisioner.dart`
- Modify: `lib/navigation/app_router.dart`
- Modify: `test/screens/registration_flow_test.dart`
- Modify: `test/screens/otp_screen_test.dart`
- Create: `test/account/account_profile_provisioner_test.dart`

**Interfaces:**
- Consumes `AccountGateway`, `AccountProfileProvisioner`, validation, cooldown.
- Produces idempotent create-profile-send-verification workflow.

- [ ] **Step 1: Write failing registration tests**

Tests submit email, password, confirmation, first/last name, and age on one
screen and assert this exact sequence:

1. `createAccount`;
2. `ensureProfile(uid, profile)`;
3. `sendVerificationEmail`;
4. typed navigation to verification.

Profile retry with the same UID must use merge semantics and not duplicate
default categories. Resend uses a 60-second cooldown. Reload only enters home
after `isEmailVerified == true`.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/screens/registration_flow_test.dart test/screens/otp_screen_test.dart test/account/account_profile_provisioner_test.dart
```

Expected: old two-screen workflow fails the new contract.

- [ ] **Step 3: Implement the unified workflow**

`AccountProfileProvisioner.ensureProfile` writes:

```dart
{
  'first_name': firstName,
  'last_name': lastName,
  'email': normalizedEmail,
  'age': age,
  'createdAt': FieldValue.serverTimestamp(),
  'profileSchemaVersion': 1,
}
```

with `SetOptions(merge: true)` and invokes an idempotent default-category
provisioner. Registration never routes home before email verification.
`OTPScreen` contains natural Thai copy and stable keys
`verify-refresh` and `verify-resend`.

- [ ] **Step 4: Run GREEN**

```powershell
flutter test test/screens/registration_flow_test.dart test/screens/otp_screen_test.dart test/account/account_profile_provisioner_test.dart
```

Expected: PASS and no reference to `RegisterFormScreen`.

- [ ] **Step 5: Commit**

```powershell
git add lib/account lib/screens/register_screen.dart lib/screens/otp_screen.dart lib/screens/register_form_screen.dart lib/navigation/app_router.dart test
git commit -m "feat: unify registration and verification"
```

---

