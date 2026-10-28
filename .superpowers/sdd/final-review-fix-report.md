# LexiQuest v0.1 Release Foundation Final-Review Fix Report

## Status and commit

Complete on `release/v0.1-complete-system`.

```text
30df9f0ed00109f7475ffc7b9ad4f2db38901a81
30df9f0 fix: address final release foundation review
```

The commit was created before the final APK build. The tracked worktree was
clean at the start of the canonical verifier, remained clean after it, and no
tracked commit was created after the APK build.

## Findings addressed

1. `.github/workflows/production-release.yml`
   - Requires both `LEXIQUEST_VOICE_API_URL` and
     `LEXIQUEST_AI_API_URL` before the build.
   - Parses each endpoint before building and accepts only a valid production
     origin: scheme `https`, non-empty authority and host, no username,
     password, or other userinfo, no query, no fragment, and path either empty
     or `/`.
   - Validates numeric/valid ports by evaluating the parsed port.
   - Emits only a fixed endpoint-label error and never reflects the supplied
     URL.
   - Quotes all four `--dart-define` arguments: version, build ID, Voice URL,
     and AI URL.
2. `lib/shop/product_artwork.dart`
   - Requires `uri.host.isNotEmpty` in addition to HTTPS, authority, and empty
     userinfo.
   - Retains trimmed valid HTTPS support and the legacy built-in fallback.
3. APK provenance
   - Rebuilt only after all tracked fixes were committed and the worktree was
     clean.
   - Embedded build ID is the exact clean short HEAD, `30df9f0`.
4. `pubspec.lock`
   - Targeted `flutter pub upgrade jni` changed only transitive `jni` from the
     retracted `1.0.1` release to resolvable `1.0.2`.
5. PowerShell contract reporting
   - `Assert-NotContainsString` now calls `Write-Pass` on success in both
     `ci-workflow.tests.ps1` and `verify-scope.tests.ps1`.
   - Totals are derived normally from the test counters; no expected total is
     hard-coded or suppressed.

## TDD evidence

### Product artwork RED

After adding the requested cases but before changing the resolver:

```powershell
flutter test test/shop/product_artwork_test.dart
```

Result: exit 1. The malformed and credential-bearing preservation cases
passed, while the new missing-host behavior failed for the intended reason:

```text
Expected: Instance of 'DefaultProductArtwork'
Actual:   Instance of 'NetworkProductArtwork'
resolveProductArtwork rejects HTTPS URLs with an empty host or missing authority
00:00 +4 -1: Some tests failed.
```

### Workflow contract RED

After adding the validation/quoting contracts but before changing the
workflow:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/ci-workflow.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/production-release-workflow.tests.ps1
```

Results:

```text
CI workflow contract tests: 88 passed, 16 failed (of 104)
Production release workflow tests: 27 passed, 15 failed
```

The failures were exactly the missing required-variable checks, URL parser
contract, HTTPS/authority/host/userinfo/query/fragment/path restrictions, and
quoted dart-defines.

### Focused GREEN

After the minimal resolver, workflow, and reporting changes:

```powershell
flutter test test/shop/product_artwork_test.dart
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/ci-workflow.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/verify-scope.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/production-release-workflow.tests.ps1
```

Final focused results:

```text
Product artwork: 5/5 passed
CI workflow contract tests: 108/108 passed
Scoped verification contract tests: 43/43 passed
Production release workflow tests: 42/42 passed
```

The actual validation block was also extracted from the YAML and executed with
Git Bash. A valid pair of HTTPS origins exited 0. Empty Voice URL, HTTP,
missing authority, userinfo, empty query, empty fragment, and non-root path
each exited 1. Python/PyYAML parsed the workflow successfully.

## Bounded dependency resolution

Dry run:

```powershell
flutter pub upgrade jni --dry-run
```

Result:

```text
> jni 1.0.2 (was 1.0.1)
Would change 1 dependency.
```

Applied command:

```powershell
flutter pub upgrade jni
```

Result:

```text
> jni 1.0.2 (was 1.0.1)
Changed 1 dependency!
```

Every lockfile delta was inspected. There are exactly two semantic deltas
under the `jni` entry:

```text
version: "1.0.1" -> "1.0.2"
sha256:
  ca1efa31ef27a0b8ecbb4f8dcf3785e5ad1b8a54c64af9b72d287ae81f93a4f4
  ->
  5bc9a9daac5ccfbd6a758377600b9f7fdce13d93f26e8012a8941014a5d978d1
```

No direct dependency, `jni_flutter`, `jni_util`, SDK constraint, or unrelated
package changed. Pub continued to report 15 constrained packages with newer
versions; they were intentionally not upgraded.

## Pre-commit verification

```powershell
dart format lib/shop/product_artwork.dart test/shop/product_artwork_test.dart
flutter analyze
flutter test --reporter compact
git diff --check
```

Results:

```text
Formatted 2 files (0 changed)
No issues found!
703 Flutter tests passed
git diff --check: clean
```

## Complete clean-HEAD verification

The exact approved command was run once from clean committed HEAD:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify.ps1
```

Result: exit 0 in 182.5 seconds.

```text
LexiQuest verification: PASS
```

| Phase | Result |
|---|---|
| 01 Protected runtime probe tests | PASS, 49/49 |
| 02 Android command construction tests | PASS, 35/35 |
| 02.1 CI/CD contract tests | PASS, including CI 108/108, scoped verification 43/43, and production release 42/42 |
| 03 Flutter dependency resolution | PASS |
| 04 Dart format check | PASS, all tracked Dart files unchanged |
| 05 Flutter static analysis | PASS, no issues |
| 06 Flutter unit and widget tests | PASS, 703 tests |
| 06.1 Trusted writer tests | PASS, 6 tests |
| 06.2 Trusted writer emulator tests | PASS, 5 tests |
| 07 Voice API CPU-only tests | PASS, 55 tests |
| 08 AI API CPU-only tests | PASS, 76 tests |
| 09 Local LM CPU-only tests | PASS, 75 tests |
| 10 Android debug APK build | PASS |
| 11 Read-only live GPU doctor | PASS |

The verifier used Firebase-only runtime/build inputs and did not require a
Supabase runtime or build input.

## APK provenance

```text
Path:
  C:\Users\Phet\Documents\LexiQuest\.worktrees\release-v0.1-complete-system\build\app\outputs\flutter-apk\app-debug.apk
Exact size:
  186,836,601 bytes
SHA-256:
  1952632BE14FC61DE2CAEA11864780E8F654448E5CBFF973D3B72905DDCEFF6C
Last-write timestamp:
  2026-07-30T01:06:12.4426496+07:00
Full HEAD:
  30df9f0ed00109f7475ffc7b9ad4f2db38901a81
Embedded build ID:
  30df9f0
```

Embedded provenance was inspected from the debug kernel inside the APK:

```powershell
& 'C:\Program Files\Git\usr\bin\unzip.exe' -p `
  build\app\outputs\flutter-apk\app-debug.apk `
  assets/flutter_assets/kernel_blob.bin |
  rg -a -o --no-filename '30df9f0(?:-dirty)?|26cb9a3-dirty'
```

Output:

```text
30df9f0
```

There was no `-dirty` suffix and no old `26cb9a3-dirty` match. `git status
--porcelain` returned zero entries immediately before and after verification.

## Files in the tracked commit

- `.github/workflows/production-release.yml`
- `lib/shop/product_artwork.dart`
- `pubspec.lock`
- `test/shop/product_artwork_test.dart`
- `tool/cli/tests/ci-workflow.tests.ps1`
- `tool/cli/tests/production-release-workflow.tests.ps1`
- `tool/cli/tests/verify-scope.tests.ps1`

Commit scope: 7 files, 106 insertions, 11 deletions.

## Self-review

- Re-read all seven tracked diffs against the five final-review findings.
- Confirmed production validation matches `AppConfig` release-origin
  restrictions and runs before `flutter build appbundle`.
- Confirmed URL values are passed as quoted, single shell arguments.
- Confirmed validation errors do not echo endpoint contents.
- Confirmed the artwork change is the single missing host guard and does not
  narrow valid HTTPS image paths or query-based CDN URLs.
- Confirmed the dedicated production-release suite was updated because its old
  optional-endpoint assertions directly contradicted the corrected release
  contract and would otherwise regress the approved verifier.
- Confirmed no active Supabase runtime/build input was introduced.
- Confirmed the lockfile has no unrelated dependency movement.
- Confirmed `git diff --check` passed and the tracked worktree is clean.
- No fabricated production data or external production mutation was used.

## Concerns

No blocking concern remains.

Non-blocking existing toolchain notices from the successful verifier:

- Flutter warns that future releases will require Android Gradle Plugin
  8.11.1+; the project currently uses 8.9.1.
- Flutter warns that future releases will require Kotlin 2.2.20+; the project
  currently uses 2.1.0.
- npm warns that `global-ignore-file` will stop working in its next major
  version.
- The Firebase emulator emitted a transient `MetadataLookupWarning`, but all
  five emulator contracts passed and shutdown completed normally.
- Pub reports 15 constrained packages with newer versions. Per the bounded
  request, only retracted `jni 1.0.1` was upgraded.
