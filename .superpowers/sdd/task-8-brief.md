### Task 8: Add account deployment contracts and verify Plan 2

**Files:**
- Create: `docs/runbooks/firebase-auth-actions.md`
- Create: `tool/cli/tests/firebase-auth-actions.tests.ps1`
- Modify: `tool/cli/verify.ps1`
- Modify: `tool/cli/tests/ci-workflow.tests.ps1`
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/production-release.yml`
- Create: `integration_test/account_lifecycle_test.dart`

**Interfaces:**
- Produces reproducible Firebase Hosting/App Links operator gates.
- Does not deploy or mutate the production Firebase project.

- [ ] **Step 1: Write failing repository contracts**

PowerShell assertions require:

- package `com.lexiquest.app`;
- Hosting/action host `vocab-learning-app-219ef.web.app`;
- path `/auth/action`;
- `android:autoVerify="true"`;
- no `.page.link` or Firebase Dynamic Links dependency/reference;
- release certificate SHA-256 fingerprint variable
  `ANDROID_RELEASE_CERT_SHA256` is required before Hosting deployment;
- runbook commands verify `/.well-known/assetlinks.json`, authorized domain,
  custom email action handler, reset template, and verification template;
- CI runs focused account tests;
- production release runs account action-link contracts before building.

- [ ] **Step 2: Run RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/firebase-auth-actions.tests.ps1
```

Expected: failures for missing runbook/workflow contracts.

- [ ] **Step 3: Implement exact runbook and workflow gates**

The runbook records these owner-controlled prerequisites:

1. add `vocab-learning-app-219ef.web.app` to Firebase Auth authorized domains;
2. configure email action handler URL
   `https://vocab-learning-app-219ef.web.app/auth/action`;
3. host `.well-known/assetlinks.json` for `com.lexiquest.app` with the exact
   release signing certificate SHA-256 fingerprint;
4. verify the link using Android `pm get-app-links com.lexiquest.app`;
5. send and consume real verification/reset emails on a physical test device;
6. never use the retired `.page.link` system.

The workflow validates the fingerprint format but does not print it or deploy
Hosting without explicit owner credentials.

- [ ] **Step 4: Run complete Plan 2 verification**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/firebase-auth-actions.tests.ps1
flutter analyze
flutter test --reporter compact
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify.ps1
```

Expected: every suite PASS and debug APK builds from a clean committed HEAD.
Remote email delivery and verified App Link remain an explicit production
owner gate until Firebase Console/Hosting configuration is applied.

- [ ] **Step 5: Commit**

```powershell
git add docs/runbooks/firebase-auth-actions.md tool/cli .github integration_test/account_lifecycle_test.dart
git commit -m "test: qualify the complete account lifecycle"
```

---

## Plan 2 completion gate

Plan 2 is complete only when:

- all account screens use `AccountGateway` and typed routes;
- production account UI has no direct Firebase Auth call;
- registration creates one account/profile and blocks home until verified;
- verification resend is throttled;
- forgot-password responses do not enumerate accounts;
- valid reset action codes can be verified and consumed exactly once in-app;
- invalid/expired codes have a safe recovery path;
- changing a password reauthenticates with the current password;
- guest upgrade links credentials and emits an explicit UID migration handoff;
- sign-out clears navigation history;
- account copy is natural UTF-8 Thai;
- no password, email, action code, token, or provider message is logged;
- Android App Links use Firebase Hosting, not retired Dynamic Links;
- focused, full Flutter, CLI, and Android debug APK gates pass;
- remote Firebase email-template/Hosting parity is recorded as an owner gate
  and must pass before the signed v0.1 APK is distributed.
