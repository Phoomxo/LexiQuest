# Task 5 implementer report

## Delivered

- Replaced the duplicate two-screen registration path with one validated form.
- Added the ordered workflow: create account, merge-provision profile, seed
  idempotent default categories, send verification email, and typed navigation
  to email verification.
- Replaced the legacy verification screen behavior with fail-closed reload,
  home navigation only for a verified session, and a 60-second resend cooldown.
- Removed `RegisterFormScreen` and all references to it.

## Files

- Added `lib/account/account_profile_provisioner.dart` and
  `test/account/account_profile_provisioner_test.dart`.
- Updated registration, verification, routing, session gate, default-category
  persistence, and the affected screen tests/audit.
- Deleted `lib/screens/register_form_screen.dart`.

## TDD evidence

- RED: `flutter test test/screens/registration_flow_test.dart test/screens/otp_screen_test.dart test/account/account_profile_provisioner_test.dart`
  failed before implementation because the profile provisioner and the injected
  unified-screen contracts did not exist.
- GREEN: the same focused command passed after implementation.
- Final verification: 21 tests passed across the focused suite plus
  `test/screens/full_system_audit_test.dart`; scoped `flutter analyze` reported
  no issues; `git diff --check` passed; a reference scan found no
  `RegisterFormScreen` references.

## Commit

`e7325a86c983190877c3713a0e24491a9d532141` — `feat: unify registration and verification`

## Risks

- Existing accounts created by the historical random-ID category writer are not
  migrated or deduplicated; the deterministic merge IDs prevent duplicates for
  this unified workflow going forward.
- Firestore integration is covered through injected writer/provisioner seams;
  emulator-backed persistence verification remains a follow-up integration test.

## Reviewer correction — resumable provisioning

### Delivered

- Retained the first successfully created `AccountSession` in the registration
  screen. Retries after a profile or email-delivery failure resume with that
  same UID and never call `createAccount` again.
- Added an explicit persisted `requiredProvisioningComplete` contract. It is
  written `false` with profile data and becomes `true` only after deterministic
  default-category provisioning completes.
- Routed incomplete registered sessions—verified or unverified—to a recovery
  form on session restoration. The recovery form reuses the authenticated UID,
  collects the required profile data, and resumes provisioning.
- Made OTP re-check provisioning before navigation home; incomplete verified
  sessions are routed to typed recovery instead.
- Injected `AccountProfileProvisioning` through `AppDependencies` and bootstrap
  composition. Router construction uses that seam and never constructs a
  Firestore-backed provisioner. Unavailable/test composition uses a
  non-Firebase implementation.
- Updated Firestore rules and emulator fixtures for the schema and completion
  fields.

### RED/GREEN evidence

- RED: failure-injection tests failed before implementation because profile
  completion, recovery route arguments, and dependency injection did not
  exist; retries also showed only one provision attempt under the old form.
- GREEN: focused registration, OTP, profile, session-gate, and router suite
  passed (19 tests), including failures at `ensureProfile` and
  `sendVerificationEmail`.
- Regression: 63 Flutter tests passed across account, navigation, bootstrap,
  registration/OTP/session-gate, and full-system audit targets.
- Policy: `npm run test:rules` passed all 46 Firestore emulator policy tests.
- Static/diff: scoped `flutter analyze` and `git diff --check` passed.

### Commit

`99e58bcf308c616fdd5553723666c0620a55536b` — `fix: make registration provisioning resumable`

### Residual risk

- The completion marker is an application-level workflow contract. The current
  client-owned Firestore model cannot prove every seeded word exists solely in
  a profile-rule expression; category writes are deterministic and create-only
  on retry, so interrupted provisioning converges without replacing records.

## Re-review correction — retry-safe default categories

### Delivered

- Replaced merge-based deterministic category and word writes with
  create-if-missing Firestore transactions. Retries leave existing category
  and word documents, including `created_at`, untouched.
- Added a `DefaultCategoryStore` seam so the complete seeded dataset can be
  failure-injected and retried in a Flutter unit test without Firebase.
- Added Firestore-emulator coverage for a partially seeded deterministic
  category, repeated production-style retries, preserved existing timestamp,
  no duplicate words, and retained cross-owner/non-idempotent mutation denial.
- Strengthened the verification-send-failure workflow test to assert category
  provisioning completed before the safe retry.

### RED/GREEN evidence

- RED: the new category-seeding test did not compile because the store seam and
  injectable `CategoryService` contract did not exist.
- GREEN: focused Flutter tests passed (20 tests), including partial category
  provisioning and all registration/session/router regressions.
- Policy: `npm run test:rules` passed all 47 emulator policy tests.
- Static/diff: focused `flutter analyze` and `git diff --check` passed.

### Commit

`b5af7dabf74e2404aba95c13f4376493ba20488e` — `fix: make default category seeding retry-safe`

## Re-review correction — deterministic category rules

### Delivered

- Allowed a registered owner to transaction-read only their own missing
  `${uid}_default_<index>` category document, enabling the create-if-missing
  default-category provisioner without exposing arbitrary missing IDs.
- Reserved deterministic default category IDs to the UID encoded in the ID, so
  another registered user cannot preclaim an absent owner default ID.
- Added emulator regression coverage for a fresh deterministic seed and for a
  cross-owner preclaim attempt, while retaining the prior partial retry,
  timestamp preservation, and mutation-denial coverage.

### RED/GREEN evidence

- RED: the new fresh-seed transaction test failed on the missing category read;
  the new cross-owner preclaim test failed because Bob could create Alice's
  reserved ID (47 passed, 2 failed).
- GREEN: `npm run test:rules` passed all 49 Firestore emulator policy tests.
- Regression: the focused Flutter suite passed all 20 tests.
- Static/diff: focused `flutter analyze` reported no issues and
  `git diff --check` passed.

### Commit

`958e410` — `fix: secure deterministic category provisioning`
