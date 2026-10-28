# Plan 2 bounded final re-review

## Verdict

**Ready for prototype baseline: Yes**

The consolidated `b45032f..f211366` package closes all three Important
findings and Minor findings 1 and 2 from the original bounded review. Minor 3
remains an accurate, explicitly bounded post-Prototype item and does not block
the provider-neutral Prototype baseline. No regression finding was identified
in the supplied fix package.

## Scope and method

- Re-review inputs were limited to the original reviewer report, the
  consolidated fix report, and
  `.superpowers/sdd/review-b45032f..f211366.diff`.
- Only tracked changes represented by the supplied package were evaluated.
- No build/cache path, wider repository crawl, Codex Security workflow, or
  large verification suite was run.
- The already reported focused 100-test gate, focused analysis, and
  `git diff --check` results were treated as existing evidence. Static review
  exposed no concrete risk requiring an additional test.
- This report update is the only review mutation; the worktree implementation,
  index, and `HEAD` were not changed.

## Original finding closure

### Important 1 — Closed: offline provisioning is now tri-state and durable

The account provisioning interface now returns `complete`, `incomplete`, or
`unavailable`, rather than collapsing every outcome into a `bool`
(`lib/account/account_profile_provisioner.dart:26-29`).

Successful provisioning records a per-UID completion marker after the remote
profile/default-category workflow completes
(`lib/account/account_profile_provisioner.dart:68-72`). A current remote
`incomplete` result remains authoritative, while a failed remote lookup can
admit only a UID with durable local completion evidence
(`lib/account/account_profile_provisioner.dart:76-94`). The local marker uses
`SharedPreferences`, stores only the UID-scoped completion boolean, and treats
failed persistence as a failed write
(`lib/account/account_profile_provisioner.dart:115-137`).

`SessionGateScreen` now keeps one state future per UID, renders registration
only for known-incomplete accounts, opens the correct verified/unverified
destination only for complete accounts, and renders an explicit retry boundary
for unavailable state
(`lib/screens/session_gate_screen.dart:60-152`). This avoids mislabeling a
no-cache lookup failure as incomplete while preserving offline shell access for
a previously completed UID.

Coverage directly exercises remote success followed by failure, no-marker
failure, stale-local/remote-incomplete precedence, fresh completion-store
restoration, unavailable UI, and restored-connectivity retry
(`test/account/account_profile_provisioner_test.dart:80-155`;
`test/screens/session_gate_screen_test.dart:262-325`).

Closure judgment: **Closed**.

### Important 2 — Closed: credential screens use the central validation policy

Login and recovery now delegate email validation and normalization to
`AccountValidation`
(`lib/screens/login_screen.dart:29-42`;
`lib/screens/forgot_password_screen.dart:29-44`). Reset-password delegates both
password and confirmation validation to the same central contract
(`lib/screens/reset_password_screen.dart:53-61`).

The new cross-screen contract covers the documented Thai password through
register/reset/change and one invalid email through
register/login/recovery
(`test/screens/account_validation_contract_test.dart:90-156`). Focused screen
tests also assert central messages and a Thai reset submission.

Closure judgment: **Closed**.

### Important 3 — Closed: warm App Links subscribe before cold lookup

The coordinator now creates the warm-link subscription before awaiting the
initial link, installs an error handler on the stream, contains cold-link
lookup failures, and wraps parse/navigation handling without logging link
contents or provider diagnostics
(`lib/navigation/account_link_coordinator.dart:31-54`).

Focused tests cover a delayed initial lookup with an intervening warm link, an
initial-link failure followed by a valid warm link, and a stream error followed
by a valid later link
(`test/navigation/account_link_coordinator_test.dart:134-203`).

Closure judgment: **Closed**.

### Minor 1 — Closed: settings sign-out is guarded and fail-safe

`SettingScreen` now blocks repeat submission, disables the action while
pending, maps typed failures through `AccountErrorMapper`, maps unexpected
failures to the safe generic message, and clears routes only after successful
sign-out
(`lib/screens/setting_screen.dart:32-61,168-173`).

Tests cover typed failure, unexpected failure, retained settings navigation,
safe user text, and repeated taps while pending
(`test/screens/setting_screen_test.dart:115-168`).

Closure judgment: **Closed**.

### Minor 2 — Closed: legacy AuthService is retired

The package deletes `lib/services/auth_service.dart` and both legacy service
test files. The full-system audit now uses `AccountErrorMapper` instead of
Firebase Auth/`AuthService`
(`test/screens/full_system_audit_test.dart:2-25,136-140`).

Closure judgment: **Closed**.

## Deferred finding judgment

### Minor 3 — Deferred, accurate, and non-blocking for Prototype

The production Firebase adapter contract still lacks behavioral coverage for
session mapping, sanitized provider exceptions, reauthentication, anonymous
linking, reload behavior, and missing-user cases. The fix report accurately
states that materially closing this requires either:

1. a complete injectable Firebase-auth facade spanning the gateway, or
2. bounded Firebase Auth emulator contract tests.

A partial wrapper would not resolve the finding, and either complete option is
a broader provider-adapter qualification task than the bounded navigation and
account-screen correction wave. The deferral is therefore acceptable for the
provider-neutral Prototype baseline because:

- the account UI and navigation are covered through the `AccountGateway`
  contract and fakes;
- the release runbook already forbids treating local fake-backed evidence as
  production Firebase/App Links qualification; and
- the fix report assigns the work to the immediate post-Prototype phase before
  any production Firebase qualification claim.

This remains a tracked Minor finding and becomes blocking before a production
Firebase lifecycle qualification claim, not before the Prototype baseline.

## Regression review

No regression finding was identified in the bounded package.

- Remote `incomplete` cannot be overridden by stale local completion.
- An unknown/no-marker account is not admitted to the shell.
- Verification refresh handles `unavailable` without routing home or profile
  recovery (`lib/screens/otp_screen.dart:37-59`).
- The completion marker stores no email, password, token, action code, or
  provider diagnostic.
- App Link error handling adds no sensitive logging and retains later stream
  delivery.
- Centralized validation preserves untrimmed passwords; only email
  normalization changed.
- Sign-out failure retains the settings route and successful sign-out still
  removes navigation history.
- Legacy provider-specific error translation and its diagnostic logging are
  removed rather than duplicated elsewhere.

## Evidence and production boundary

The consolidated fix report records:

- focused RED evidence for each Important finding;
- a final bounded account/navigation/settings gate of **100 tests**, exit 0;
- focused static analysis of the changed source/test set, exit 0; and
- `git diff --check`, exit 0.

These results support the Prototype baseline. They do not change the existing
production boundary: Firebase Hosting, real Auth email delivery/templates,
release-certificate `assetlinks.json`, physical-device App Links, and the
deferred Firebase adapter behavioral contract must be qualified before a
production distribution claim.

## Final finding count and decision

- Open Critical: **0**
- Open Important: **0**
- Open Minor: **1 deferred**
- Regression findings: **0**

**Blocking issue for Prototype baseline:** None.

**Ready for prototype baseline: Yes**
