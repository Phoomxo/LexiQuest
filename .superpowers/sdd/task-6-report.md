# Task 6 Report: Remove Supabase from local and CI verification

## Commit

`b29c147 ci: retire Supabase build requirements`

## TDD evidence

### RED

Commands run before removing the retired inputs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/verify-scope.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/ci-workflow.tests.ps1
```

Observed output:

```text
release verification must not require a retired Supabase build input
```

```text
CI workflow contract tests: 67 passed, 1 failed (of 68)
[FAIL] Job coverage suite threw: CI must not provision Supabase
FAILED
```

### GREEN

Fresh complete contract-suite rerun before commit:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/verify-scope.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/ci-workflow.tests.ps1
```

Observed output:

```text
Scoped verification contract tests: 42 passed, 0 failed (of 42)
PASS

CI workflow contract tests: 75 passed, 0 failed (of 75)
PASS
```

## Changes

- `tool/cli/verify.ps1`
  - Removed `Get-RequiredSupabasePublishableKey` and its phase-10 call.
  - The debug APK build now uses only version `0.1.0+1`, build ID, Voice API URL, and AI API URL dart-defines.
- `tool/cli/tests/verify-scope.tests.ps1`
  - Replaced Supabase-presence assertions with absence and v0.1 identity assertions.
- `tool/cli/tests/ci-workflow.tests.ps1`
  - Added the requested absence helper and assertions.
  - Removed the retired `Invoke-SupabaseToolchainTests` function and invocation.
- `.github/workflows/ci.yml`
  - Removed Supabase CLI setup, local database start/reset/lint/advisor/storage-contract/stop steps, both publishable-key environment entries, both Supabase dart-defines, and the debug-key presence check.
  - Changed both Android build versions to `0.1.0+1`.

## Retained workflow coverage

- CLI contracts, Flutter dependency resolution/format/analyze/test, and all CPU-only backend tests.
- Firebase provisioning, Firestore emulator rules tests, trusted-writer tests, and trusted-writer emulator tests.
- Debug APK build, disposable release signing key creation, signed release AAB smoke build, signature verification, SBOM generation/upload, and signing-material cleanup.

## Self-review

- Reviewed the four-file diff and ran `git diff --check`; no whitespace errors.
- Confirmed the retired runtime/workflow inputs are absent from `verify.ps1` and `ci.yml`; expected references remain only in negative test assertions and historical Gitleaks documentation checks.
- No Flutter source files changed.

## Concerns

None. Git reported the repository's existing LF-to-CRLF checkout warning while staging; the committed diff contains only the intended logical changes.

## Follow-up: Production-release workflow

### Commit

`26cb9a3 ci: retire Supabase production release input`

### RED

After extending `tool/cli/tests/ci-workflow.tests.ps1` to load
`.github/workflows/production-release.yml` and validate the release contract,
the following command was run before changing the workflow:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/ci-workflow.tests.ps1
```

Observed output:

```text
-> Production release
  [FAIL] Production release suite threw: production release must not require Supabase

CI workflow contract tests: 75 passed, 1 failed (of 76)
FAILED
```

### GREEN

After removing the retired input, the complete scoped contract suites were run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/verify-scope.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/ci-workflow.tests.ps1
```

Observed output:

```text
Scoped verification contract tests: 42 passed, 0 failed (of 42)
PASS

CI workflow contract tests: 88 passed, 0 failed (of 88)
PASS
```

### Changes and self-review

- The production workflow no longer declares, checks, or injects
  `LEXIQUEST_SUPABASE_PUBLISHABLE_KEY`; its AAB build identity is now
  `0.1.0+1`.
- The CI contract suite now loads the production-release workflow and verifies
  the absence of Supabase while requiring the build ID, Voice/AI inputs,
  protected signing material, AAB signature verification, source/artifact SBOM,
  artifact upload, and `always()` signing-material cleanup.
- Reviewed the two-file diff and ran `git diff --check`; no whitespace errors.

### Follow-up concerns

None. The same existing LF-to-CRLF checkout warnings appeared while staging.
