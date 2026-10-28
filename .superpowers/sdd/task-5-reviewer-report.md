# Task 5 third re-reviewer report

## Verdict

**APPROVED**

No actionable findings remain. Commit
`958e410fb00316f9f1d98bec77dffeb6532a3313` resolves both policy blockers from
the second re-review without weakening the existing ownership, retry, or
timestamp gates.

## Blocker disposition

### Missing own reserved category read

**Resolved.**

- `firestore.rules:53-57` recognizes only the authenticated user's exact
  `${uid}_default_<numeric-index>` category ID.
- `firestore.rules:218-221` allows a registered owner to read that reserved ID
  when the document is absent, which permits the production create-if-missing
  transaction's initial `get`.
- Existing category documents remain readable only when
  `resource.data.uid == request.auth.uid`.
- The fresh-seed emulator test begins without a category, executes the same
  read-before-create transaction shape, retries it, and verifies ownership,
  stable word timestamps, and exactly two deterministic words.

### Cross-owner reserved-ID preclaim

**Resolved.**

- `firestore.rules:59-61` identifies deterministic reserved category IDs.
- `firestore.rules:223-225` permits a reserved-ID create only when the ID
  encodes the authenticated UID.
- The emulator test attempts Bob's create of Alice's absent
  `alice_uid_default_0` before any owner document exists and confirms denial;
  Alice can then create the same owner-reserved ID.
- Ordinary non-reserved category creation and owner CRUD continue to pass.

## Prior fix reconfirmation

- Create-if-missing category and word transactions leave existing documents
  untouched. Partial retry creates only missing documents, preserves the
  original `created_at`, and creates no duplicate deterministic words.
- Category updates remain denied, word timestamp-replacing updates remain
  denied, and cross-owner category access remains denied.
- Registration retains the first created `AccountSession`; profile or
  verification-send retries reuse the same UID and do not create a second
  account.
- `AccountProfileProvisioning` remains injected through `AppDependencies` and
  bootstrap. Router construction does not instantiate a Firestore-backed
  provisioner.
- `SessionGateScreen` and `OTPScreen` still require persisted provisioning
  completion before entering home. Verified and unverified incomplete sessions
  use the typed registration-recovery path.
- `RegisterFormScreen` remains deleted with no references under `lib` or
  `test`.

The client-authored `requiredProvisioningComplete` field remains an
application workflow marker rather than a server attestation, as documented by
the implementer. That residual architecture limitation does not invalidate the
Task 5 recovery and routing contract.

## Verification evidence

Reviewed the complete updated implementer report and all 2,785 lines of
`task-5-rereview-3-package.diff`, then audited the live committed sources at
`958e410fb00316f9f1d98bec77dffeb6532a3313`.

- `npm run test:rules` - PASS, 49/49 Firestore emulator policy tests.
- Focused Flutter router/session/registration/OTP/account/bootstrap/default
  seeding suite - PASS, 48/48 tests.
- `flutter test test/screens/full_system_audit_test.dart --reporter compact` -
  PASS, 16/16 tests.
- Focused `flutter analyze` over 15 implementation/test targets - PASS, no
  issues.
- `git diff --check ac336bb..958e410` - PASS.
- Latest remediation scope (`b5af7da..958e410`) contains only
  `firestore.rules` and `test/security/firestore-rules.test.cjs`.
- Strict UTF-8 checks on the touched rules, service, registration, gate,
  router, bootstrap, dependency, and policy-test files - PASS.
- `RegisterFormScreen|register_form_screen` scan under `lib` and `test` - no
  references.

No implementation files were edited and no commit was created.
