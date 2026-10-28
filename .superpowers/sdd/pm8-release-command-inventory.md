# PM8 release command inventory — inspection only

Prepared 2026-09-05 for root execution after PM5–PM8 implementation/review and writer handoff. This report is not a test result, G4P acceptance, release approval, or permission to enable production.

## Observed scope and source

- Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`.
- Branch observed: `codex/pair-matching-pm0-pm8`.
- HEAD observed: `c3b389e6d7473ba0e6eb7f080fd1315eb3b7367e`; accepted implementation baseline is PM4 `09ef33a1`, while PM5 source/test edits are in progress.
- Read `AGENTS.md`, `.superpowers/sdd/pm8-brief.md`, `pm8-compatibility-preflight.md`, and the current top of `progress.md`. PM5 remains sole source/Flutter/Dart tool owner. This worker only writes this report.
- No Flutter/Dart/pub/generator/test/build/scanner/network/install command was run. No Git/index/HEAD mutation, cleanup, process termination, credential read, or private field-evidence read was performed.
- Read-only document arithmetic found **258 RTM requirement rows / 258 unique IDs** and **44 TC-PMT rows / 44 unique IDs**. These are planned inventory counts, not executed requirements or UAT acceptance.

Sources: `docs/adventure-motivation-mode/08-requirements-traceability-matrix.md:13–35`, `06-test-plan-and-test-cases.md:404–448`, `.superpowers/sdd/progress.md:11–26`.

## Evidence directory and identity sequencing

The concrete repository convention is **`build/verification/<sha>/`**, documented with `targeted-*.json` outputs in `docs/superpowers/plans/2026-08-08-lexiquest-complete-field-trial-release-execution.md:28`. The active PM8 plan (`docs/superpowers/plans/2026-09-01-adventure-motivation-mode-implementation.md:855`) requires the approved build-evidence location but does not name a separate G4P path. `/build/` is ignored by `.gitignore:47`. This worktree currently has `build/`, but no `build/verification/` or Pair G4P artifact was found. Use the convention under **this worktree**, with the actual final source SHA. Names below are new PM8 execution labels, not existing evidence.

Root should first pause all implementation writers, inspect the final source and accepted reports, and finish any required source generation/formatting. A source-changing correction requires affected gates to run again. Preserve the pre-existing native registrant line-ending noise; do not use cleanup/reset to obtain a clean-looking tree. Record committed source identity separately from any later documentation-only HEAD.

Run the following setup only when root owns the serialized execution slot and the final implementation source identity is established:

```powershell
Set-Location -LiteralPath 'C:/Users/Phet/.codex/worktrees/02fa/LexiQuest'
$pm8SourceCommit = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $pm8SourceCommit -cnotmatch '^[0-9a-f]{40}$') {
    throw 'Cannot establish the actual PM8 checkout identity.'
}
& git branch --show-current
& git status --short
$pm8EvidenceDirectory = Join-Path (Get-Location).Path ('build/verification/' + $pm8SourceCommit)
New-Item -ItemType Directory -Path $pm8EvidenceDirectory -Force | Out-Null
$pm8Run = Get-Date -Format 'yyyyMMddTHHmmssfff'
$pm8Prefix = Join-Path $pm8EvidenceDirectory ('pm8-' + $pm8Run)
```

Use a new run prefix for a corrected rerun so an earlier failed log is retained. Every evidence record needs command, start/end UTC, exit code, tool versions, source commit/fingerprint, actual build/config identity, named exclusions, and defect disposition. The existing generated plan also requires schema/table inventory, product contract revision/hash, content/runtime/rules revisions, and rollback result. Neither a directory named after HEAD nor a clean diff proves the source was unchanged throughout a run.

## Existing generators: exact interfaces and ordering

1. `tool/feature_contract/generate_feature_map.dart:48–113` accepts exactly `--write` or `--check`. It writes only `docs/generated/alltcas-idea-integration-feature-map.md` and `.json`. It refuses an untrustworthy existing identity or unauthorized semantic identity drift; do not weaken that validation.
2. `tool/final_test_plan/generate_final_test_plan.dart:211–311` requires `<--write|--check> --source-commit <40-char-sha>`. **Write requires the supplied SHA to equal actual checkout HEAD.** Check compares generated content using the supplied source SHA, allowing the verified implementation identity to remain pinned after documentation-only commits.
3. The final generator reads feature-map outputs and canonical source references, including `lib`, `test`, and `tool` directories. `_readSources`, `_sourceFingerprint`, and `_hashSourcePath` (`:312–365`) hash raw file bytes, including recursively present untracked files within referenced directories; line-ending changes in these inputs matter. Output comparison normalizes line endings, but source hashing does not. Final generated-plan files themselves are outside the fingerprint to avoid a cycle.
4. Therefore complete code generation/format/source changes first; check/write/check the feature map before writing/checking the final plan. Capture the manifest fingerprint before the integration gates and check it again afterward. Do not regenerate merely to hide an unexplained mismatch.

Exact commands, with root checking `$LASTEXITCODE` after every native invocation:

```powershell
& dart run 'tool/feature_contract/generate_feature_map.dart' --check
if ($LASTEXITCODE -ne 0) { throw 'Inspect feature-map drift before any write.' }
```

If a reviewed source change legitimately requires the normal generator, the existing write/check commands are:

```powershell
& dart run 'tool/feature_contract/generate_feature_map.dart' --write
if ($LASTEXITCODE -ne 0) { throw 'Feature-map generation failed.' }
& dart run 'tool/feature_contract/generate_feature_map.dart' --check
if ($LASTEXITCODE -ne 0) { throw 'Feature-map verification failed.' }
```

After the final source snapshot is established, regenerate the final plan at its actual HEAD, then run both existing generator contract suites:

```powershell
& dart run 'tool/final_test_plan/generate_final_test_plan.dart' --write --source-commit $pm8SourceCommit
if ($LASTEXITCODE -ne 0) { throw 'Final-plan generation failed.' }
& dart run 'tool/final_test_plan/generate_final_test_plan.dart' --check --source-commit $pm8SourceCommit
if ($LASTEXITCODE -ne 0) { throw 'Final-plan verification failed.' }
$pm8Plan = Get-Content -LiteralPath 'docs/generated/alltcas-8-44-final-test-plan.json' -Raw | ConvertFrom-Json
$pm8Fingerprint = [string]$pm8Plan.sourceFingerprint
if ($pm8Plan.sourceCommit -cne $pm8SourceCommit) { throw 'Plan source identity mismatch.' }
& flutter test --no-pub --reporter failures-only `
    'test/architecture/final_8_44_test_plan_contract_test.dart' `
    'test/architecture/final_8_44_test_plan_review_contract_test.dart'
if ($LASTEXITCODE -ne 0) { throw 'Final-plan contract tests failed.' }
```

At the end repeat both `--check` commands with the retained `$pm8SourceCommit`, inspect `git diff --check`, and compare recorded `sourceFingerprint`. If root makes a later metadata-only commit, do not issue `--write --source-commit <old SHA>` against new HEAD: the generator intentionally rejects that. If regenerating for new HEAD, require the source fingerprint to stay equal before reusing implementation evidence and record the metadata distinction explicitly.

The currently committed generated JSON pins Research source `ed89efaf32a1090505a84d4b55b2cc60003068b3` and fingerprint `8e9ac9a8d74eba3cf2807ff6b02f6e57c4fa97ee6e3b49b8a8acb8f84a173988`. It is **not a current Pair verification artifact**. Generator table validation currently expects schema inventory **48 tables**; catalog **8/44** must not be confused with table count (`generate_final_test_plan.dart:381–403`).

## Full default/serial suites and the four exclusions

No `dart_test.yaml` exists in this checkout; do not assume a repository-wide exclusion is automatic. The tag is exactly **`release-excluded`**, at four individual tests:

| Test file | Exact test name | Tag location |
|---|---|---|
| `test/architecture/notification_platform_contract_test.dart` | `iOS notification integration is CocoaPods-backed at iOS 13` | line 101 |
| `test/features/device_model/litert_image_classifier_test.dart` | `opens the checksum-pinned model and runs real XNNPACK inference` | line 47 |
| `test/features/device_model/litert_image_classifier_test.dart` | `verifier rejects a manifest with the wrong output contract` | line 83 |
| `test/features/device_model/litert_benchmark_test.dart` | `runs bounded real CPU and XNNPACK benchmarks` | line 58 |

The three model cases default to `build/model-fixtures/mobilenet.tflite`; this inventory does not prepare/download it or reclassify those cases. Excluded means not run, never passed. Do not exclude an entire architecture or device-model directory.

Run these **sequentially on one unchanged source snapshot**, saving stdout JSON separately from stderr:

```powershell
$pm8DefaultStart = [DateTimeOffset]::UtcNow
& flutter test --no-pub --exclude-tags 'release-excluded' --reporter json `
    1> ($pm8Prefix + '-full-default.jsonl') 2> ($pm8Prefix + '-full-default.stderr.log')
$pm8DefaultExit = $LASTEXITCODE
$pm8DefaultEnd = [DateTimeOffset]::UtcNow
if ($pm8DefaultExit -ne 0) { throw 'Default suite failed; inspect its retained inventory.' }

$pm8SerialStart = [DateTimeOffset]::UtcNow
& flutter test --no-pub --exclude-tags 'release-excluded' --concurrency=1 --reporter json `
    1> ($pm8Prefix + '-full-serial.jsonl') 2> ($pm8Prefix + '-full-serial.stderr.log')
$pm8SerialExit = $LASTEXITCODE
$pm8SerialEnd = [DateTimeOffset]::UtcNow
if ($pm8SerialExit -ne 0) { throw 'Serial suite failed; inspect its retained inventory.' }
```

Reconcile actual named test inventories from both JSON streams and final `done.success`, not terminal dots or a historical expected total. Count visible `testDone` events (`hidden == false`); hidden loading/group events are not additional passed tests. Retain any unexpected skips/failures as separate outcomes. The current generated gate strings for architecture/unit suites omit this tag (`generate_final_test_plan.dart:515–591`), so the release-scope commands above must retain the explicit exclusion.

Historical Research closure (`docs/development/2026-09-05-research-engineering-status.md:189–237`) reported **4,328 default + 4,328 serial**, three host journeys, and one debug APK, at its own source/fingerprint. Earlier Adventure reported **3,542**. None is a target total or a substitute for current Pair output.

## Three existing host-fake integration commands

The exact three files and host selection are established in `tool/cli/verify-product-completion.ps1:106–109,148–156`; the Research closure used `failures-only`. Run one at a time:

```powershell
& flutter test -d flutter-tester --no-pub --timeout 90s --reporter failures-only `
    'integration_test/field_trial_core_journey_test.dart'
if ($LASTEXITCODE -ne 0) { throw 'Core host journey failed.' }
& flutter test -d flutter-tester --no-pub --timeout 90s --reporter failures-only `
    'integration_test/field_trial_feature_controls_test.dart'
if ($LASTEXITCODE -ne 0) { throw 'Feature-controls host journey failed.' }
& flutter test -d flutter-tester --no-pub --timeout 90s --reporter failures-only `
    'integration_test/field_trial_media_smoke_test.dart'
if ($LASTEXITCODE -ne 0) { throw 'Media host journey failed.' }
```

Capture each command's output/time/exit under the same PM8 prefix. These use `integration_test/support/field_trial_external_fakes.dart`; they prove host UI/composition only. They are neither physical camera/microphone/model checks nor external UAT. New PM6–PM8 host/rollback cases must also be recorded after those source files stabilize.

## Analyzer and focused local privacy/policy checks

Existing bounded invocation inventory; root chooses the touched selection after final integration and executes sequentially:

```powershell
& flutter analyze --no-pub lib test
if ($LASTEXITCODE -ne 0) { throw 'PM8 analyzer failed.' }
& flutter test --no-pub --reporter failures-only `
    'test/config/flutter_dependency_surface_test.dart' `
    'test/config/research_runtime_config_test.dart' `
    'test/config/adventure_research_runtime_config_test.dart' `
    'test/features/consent/research_consent_use_cases_test.dart' `
    'test/features/export/research_lifecycle_export_test.dart' `
    'test/features/research/research_sync_authorizer_test.dart' `
    'test/features/research/research_runtime_sync_integration_test.dart' `
    'test/scenarios/complete_owner_export_delete_test.dart'
if ($LASTEXITCODE -ne 0) { throw 'Privacy/authority selection failed.' }
& flutter test --no-pub --reporter failures-only `
    'test/runtime/production_feature_gate_test.dart' `
    'test/runtime/runtime_feature_controls_test.dart' `
    'test/architecture/alltcas_idea_feature_contract_test.dart' `
    'test/architecture/alltcas_idea_feature_contract_docs_test.dart' `
    'test/scenarios/production_feature_navigation_test.dart'
if ($LASTEXITCODE -ne 0) { throw 'Runtime/catalog selection failed.' }
& powershell -NoProfile -ExecutionPolicy Bypass -File 'tool/cli/tests/firestore-rules-security.tests.ps1'
if ($LASTEXITCODE -ne 0) { throw 'Static Firestore policy contract failed.' }
& powershell -NoProfile -ExecutionPolicy Bypass -File 'tool/cli/tests/osv-config.tests.ps1'
if ($LASTEXITCODE -ne 0) { throw 'Dependency exception policy contract failed.' }
```

The first PowerShell policy script is explicitly dependency-free/text-only and does not launch an emulator (`tool/cli/tests/firestore-rules-security.tests.ps1:5–27`). The Flutter privacy selection covers existing synthetic consent/export/upload/default-off boundaries; it is not the entire PM8 owner-rehome/compatibility matrix. Parent-gate disposal/reopen, legitimate guest rehome/collision, immutable v6 pins, before/after pending commits and unrelated Quiz/Adventure fallback remain required by the active PM8 brief.

The package scripts are exact synthetic/emulator policies (`package.json:7–8`, `firebase.json:27–40`):

```powershell
& npm.cmd run test:auth
if ($LASTEXITCODE -ne 0) { throw 'Demo Auth emulator policy failed.' }
& npm.cmd run test:rules
if ($LASTEXITCODE -ne 0) { throw 'Demo Firestore emulator policy failed.' }
```

They invoke demo projects `demo-lexiquest-auth-test` / `demo-lexiquest-rules-test`, loopback ports 9099 / 8080, and `test/security/firebase-auth-emulator.test.cjs` / `firestore-rules.test.cjs`. Auth deliberately deletes **demo emulator** accounts between synthetic tests. Root must establish the emulator/dependency prerequisites without substituting a live project. No emulator or network/dependency availability was tested here.

Supabase exists at `supabase/config.toml`, `supabase/migrations/20260727000000_image_bucket_public_readonly.sql`, and `test/security/supabase_storage_contract.sql`. The SQL uses `BEGIN`/`ROLLBACK` and tests existing policy; it does not create bucket/policy. CI also contains `db start`, **`db reset --local --no-seed`**, advisors and stop (`.github/workflows/ci.yml:69–90`). Do not run that broad CI chain for PM8. If a task-owned, already migrated synthetic local container is independently verified and this unchanged surface is applicable, the existing SQL invocation translated to PowerShell is:

```powershell
Get-Content -LiteralPath 'test/security/supabase_storage_contract.sql' -Raw |
    & docker exec -i supabase_db_lexiquest-local psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f -
if ($LASTEXITCODE -ne 0) { throw 'Synthetic local Supabase policy contract failed.' }
```

Container availability/ownership was not inspected; do not run against an assumed container. Otherwise mark this unchanged suite not run, as the Research closure did. No database start/reset/stop is authorized by this report.

## Bounded scanner/dependency inventory

Gitleaks and OSV executables were located with `Get-Command` only. Version execution and vulnerability queries were not performed. Preserve `.gitleaks.toml` exact path/value allowlists and `.gitleaksignore` historical fingerprint exceptions; inspect new findings individually without printing secret values.

Working-source Gitleaks scopes match the Research closure's bounded approach. The following command construction uses the installed Gitleaks directory mode, keeps redaction enabled, and does not traverse all Git history or ignored private/build directories:

```powershell
$pm8LeakScopes = @('lib', 'test', 'docs', 'tool/final_test_plan', 'tool/feature_contract', 'pubspec.yaml', 'pubspec.lock', 'firestore.rules', 'AGENTS.md')
foreach ($pm8LeakScope in $pm8LeakScopes) {
    $pm8LeakLabel = $pm8LeakScope -replace '[^A-Za-z0-9_-]', '_'
    & gitleaks dir $pm8LeakScope --redact --no-banner `
        --config '.gitleaks.toml' --gitleaks-ignore-path '.gitleaksignore' `
        --report-format json --report-path ($pm8Prefix + '-gitleaks-' + $pm8LeakLabel + '.json')
    if ($LASTEXITCODE -ne 0) { throw ('Inspect redacted Gitleaks result for ' + $pm8LeakScope) }
}
```

This is an execution inventory, not evidence that directory-mode flags or these inputs have been exercised in this worktree. The repository's historical full-history command is `gitleaks git . --redact --no-banner` (`docs/development/2026-09-04-adventure-motivation-checkpoint-6-local-verification.md:46`); a history scan does not replace checking current uncommitted/new source. Do not invoke any prohibited worker/plugin scanner.

Use the established Windows-safe literal-lock gate, not recursive OSV path scanning:

```powershell
& powershell -NoProfile -ExecutionPolicy Bypass -File 'tool/cli/verify-osv-locks.ps1' `
    -ScannerPath 'C:/Users/Phet/AppData/Local/Microsoft/WinGet/Links/osv-scanner.exe'
if ($LASTEXITCODE -ne 0) { throw 'Inspect the failed literal dependency inventory.' }
```

`tool/cli/verify-osv-locks.ps1:9–57` executes `scan source --config <policy> --lockfile <literal file>` for exactly:

| Dependency inventory | Policy |
|---|---|
| `pubspec.lock` | `osv-scanner.toml` |
| `package-lock.json` | `osv-scanner.toml` |
| `backend/ai_api/uv.lock` | `osv-scanner.toml` |
| `backend/voice_api/uv.lock` | `backend/voice_api/osv-scanner.toml` |
| `backend/lexiquest_lm/uv.lock` | `osv-scanner.toml` |
| `backend/lexiquest_lm/deploy/hf_space/requirements.txt` | `osv-scanner.toml` |

Root policy has one uuid exception ending **2026-10-26**; optional Voice/Torch policy has eight exceptions ending **2026-09-11**. These exceptions are not fixes or permission to enable GPU/remote voice. OSV may query external advisory services; this read-only preparation did not run it or establish cache/network readiness.

Existing CPU backend commands in `tool/cli/verify.ps1:170–195` use `uv run --project <backend> --frozen --no-sync --group dev pytest ...`. The three worktree-local `.venv/Scripts/python.exe` files were absent at inspection, so no ready backend environment is claimed. `backend/ai_api/tests/test_dependency_pins.py`, `backend/voice_api/tests/test_dependency_pins.py`, and `backend/lexiquest_lm/tests/test_dependency_pins.py` are present. Do not install/sync optional groups to turn this preflight into a backend/GPU task; report unchanged backend suites honestly if not applicable.

## Local Android debug artifact and runtime integrity

Use the established `flutter build apk --debug --no-pub` workflow and explicit non-secret `LEXIQUEST_VERSION` / `LEXIQUEST_BUILD_ID` (`docs/development/2026-09-05-research-engineering-status.md:220–234`, `lib/runtime/app_build_info.dart:11–20`). Historical Research injected `1.0.0+1`; **current `pubspec.yaml:5` is `1.0.0+14`**, and Android Gradle uses Flutter's versionName/versionCode (`android/app/build.gradle.kts:65–66`). Therefore derive the current manifest version for the new Pair define, rather than silently copying the historical diagnostic version. This changes no source/version file.

```powershell
$pm8VersionLine = Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$'
if (@($pm8VersionLine).Count -ne 1) { throw 'Expected one explicit app version.' }
$pm8Version = $pm8VersionLine.Matches[0].Groups[1].Value
$pm8BuildId = 'pair-' + $pm8SourceCommit
& flutter build apk --debug --no-pub `
    ('--dart-define=LEXIQUEST_VERSION=' + $pm8Version) `
    ('--dart-define=LEXIQUEST_BUILD_ID=' + $pm8BuildId)
if ($LASTEXITCODE -ne 0) { throw 'Local Pair debug build failed.' }
$pm8Apk = 'build/app/outputs/flutter-apk/app-debug.apk'
if (-not (Test-Path -LiteralPath $pm8Apk -PathType Leaf)) { throw 'Debug APK missing.' }
Get-Item -LiteralPath $pm8Apk | Select-Object FullName,Length,LastWriteTimeUtc
Get-FileHash -LiteralPath $pm8Apk -Algorithm SHA256
& powershell -NoProfile -ExecutionPolicy Bypass -File 'tool/cli/verify-apk-model-runtime.ps1' `
    -ApkPath $pm8Apk -BuildMode Debug
if ($LASTEXITCODE -ne 0) { throw 'Packaged native-runtime integrity failed.' }
```

`tool/cli/verify-apk-model-runtime.ps1` is local/read-only: it verifies the pinned AAR at `build/flutter_litert/tmp/downloadLitertJni/litert-2.1.5.aar`, SHA-256 `A162D1DDBDAD87C002B7EC7EB31A703F2761335E693F292F94091B3569D8AA37`, exact expected native-library set/raw hashes, mode-specific canonical custom-op hashes, and absence of `libLiteRt.*Accelerator.so`. `tool/cli/lib/elf-canonical-hash.ps1` only normalizes the documented 20-byte GNU build-id descriptor for custom ops. No APK or matching AAR was found in the current bounded build inventory; generation/download readiness was not tested. A missing artifact is a dependency to diagnose, not permission to loosen checksums.

The verified `apkanalyzer.bat` on PATH can separately confirm Android package/version identity after a successful build:

```powershell
& apkanalyzer.bat manifest application-id $pm8Apk
if ($LASTEXITCODE -ne 0) { throw 'APK application-id inspection failed.' }
& apkanalyzer.bat manifest version-name $pm8Apk
if ($LASTEXITCODE -ne 0) { throw 'APK version-name inspection failed.' }
& apkanalyzer.bat manifest version-code $pm8Apk
if ($LASTEXITCODE -ne 0) { throw 'APK version-code inspection failed.' }
```

Record actual output against `com.lexiquest.app` and the parsed version: with today's unchanged manifest, AppBuildInfo full version is `1.0.0+14`, Android versionName is `1.0.0`, and Android versionCode is `14`. These are intended local-build identities, not a published version. Hash/metadata/native-library inspection does not prove app navigation, Pair B-writer admission, or device acceptance. Verify final configuration via runtime/gate tests and bounded source review: `AdventureResearchRuntimeConfig.off()` is the bootstrap default (`lib/runtime/app_bootstrap.dart:420,475`); no instrument/issuer/receipt authority is bundled (`lib/config/adventure_research_runtime_config.dart:5–15`). Evidence rollout defaults to legacy/write-v1 (`lib/config/research_runtime_config.dart:22–35`); broad `researchAssessment` and `adventureMotivation` are hidden (`feature_registry.dart:60,63`). Future PM8 Pair-specific compatibility/off flags are not yet final, so no invented define/config is supplied here. Capture the implemented Release A reader/default-writer and authorized internal B configuration after PM8 handoff.

Do not run `verify.ps1` or `verify-product-completion.ps1` wholesale for this request: they bundle dependency resolution, broader backends, runtime probes, and/or a cloud-sync-enabled build. Reuse the bounded commands above. `package-field-release.ps1` creates a signed release package, validates exact `build/field-release`, and accesses signing metadata; it is not the local debug build path and was not executed.

## Template/sign-off inventory and real acceptance boundaries

No dedicated executable G4P JSON generator/template was found in the active PM8 files. The authoritative templates/fields are:

- `docs/adventure-motivation-mode/06-test-plan-and-test-cases.md:476–502`: command/tools/time/exit/counts/exclusions/sanitized logs/build-config-device/revisions/defects/screenshots/reviewer decision; Test Sign-off columns `Role | Decision | Name | Date | Evidence/conditions`.
- `docs/adventure-motivation-mode/07-uat-script.md:82–92`: commit, app/build, platform, SDK, schema/registry/catalog/policy/content/rules, applicable protocol/instrument, device/OS/locale/text/theme/motion/audio/network and pseudonymous owner fixture.
- UAT defect table (`:808–820`): `Defect ID | UAT/Step | Severity | Actual/Expected | Evidence | Owner | Target | Retest | Disposition`; S0/S1 must be resolved/retested; S2 needs owner/date/accepted risk.
- UAT sign-off table (`:867–882`): `Role | Decision | Name | Date | Build/evidence | Conditions`. Its entries are intentionally empty, and local automation is not a human UAT pass.
- **Specific G4P role rule** in `09-measurement-decision-spec.md:311–323` and `.superpowers/sdd/pm8-brief.md`: Product, **Learning/Data**, UX/Accessibility, QA and Tech must decide Accept/Revise/Reject. The general UAT table does not explicitly include Learning/Data; root must retain that specific G4P role in the eventual decision record, not infer approval from other rows.
- Required Pair package (`09-measurement-decision-spec.md:325–337`): normalized plan fixtures/fingerprints, curated eligibility/collision report without private vocabulary, reducer/idempotency/race/recovery, repair timeline, timer, star/no-authority writes, replay before/after projections, Standard/Adventure parity, reader-first compatibility/rollback, device/accessibility/localization, UAT comprehension numerator/denominator, signed G4P build/commit/config decision.

The existing field-release JSON at `docs/field/release-evidence-template.json` is a **separate real-field release schema**: source/releaseId/artifact hashes and signing certificate, cloud controls, participant package document hashes, devices, beta operations and owner decision. `tool/cli/new-field-release-evidence.ps1:4–18` consumes real manifest/device/cloud/private acceptance records and defaults to `field/evidence/release-evidence.json`; `verify-field-release.ps1:27–39` explicitly rejects missing genuine device evidence. Only public template/script definitions were read. No private records, signatures or participant data were opened, generated, or filled with synthetic acceptance.

At inspection all external Pair UAT/device/accessibility/comprehension/signatures remain **Not Run / required**. Engineering can be verified locally while G4P remains Revise/pending external evidence. Hidden/Internal does not authorize MS-08A/MS-08B, enrollment, upload, expansion, deployment, or feature enablement.

The eventual G4P decision record must explicitly carry every required role. This unexecuted row inventory deliberately supplies no person, date, signature, or decision:

| Required G4P role | Current status | Decision / name / date / build-config-evidence / conditions |
|---|---|---|
| Product | Not Run / required | Unrecorded |
| Learning/Data | Not Run / required | Unrecorded |
| UX/Accessibility | Not Run / required | Unrecorded |
| QA | Not Run / required | Unrecorded |
| Tech | Not Run / required | Unrecorded |

## Tool availability observed (Get-Command only)

| Command | Resolved path |
|---|---|
| Flutter / Dart | `C:/Users/Phet/AppData/Local/Programs/flutter/bin/flutter.bat`; `dart.bat` in the same directory |
| Windows PowerShell | `C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe` |
| PowerShell 7 | `C:/Users/Phet/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe` |
| Gitleaks | `C:/Users/Phet/AppData/Local/Microsoft/WinGet/Links/gitleaks.exe` |
| OSV Scanner | `C:/Users/Phet/AppData/Local/Microsoft/WinGet/Links/osv-scanner.exe` |
| Node / npm / npx | `C:/Program Files/nodejs/node.exe`; `npm.cmd`; `npx.cmd` |
| Firebase CLI | `C:/Users/Phet/AppData/Roaming/npm/firebase.cmd` |
| Java | `C:/Program Files/Eclipse Adoptium/jdk-25.0.3.9-hotspot/bin/java.exe` |
| uv | `C:/Users/Phet/.local/bin/uv.exe` |
| Python | `C:/Python314/python.exe` |
| adb | `C:/Users/Phet/AppData/Local/Microsoft/WinGet/Packages/Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe/platform-tools/adb.exe` |
| Supabase | `C:/Users/Phet/AppData/Local/Programs/Supabase/supabase.exe` |
| Docker | `C:/Program Files/Docker/Docker/resources/bin/docker.exe` |
| psql | `C:/Users/Phet/Tools/PostgreSQL18/bin/psql.exe` |
| APK analyzer | `C:/Users/Phet/AppData/Local/Android/Sdk/cmdline-tools/latest/bin/apkanalyzer.bat` |

`apksigner` was not on PATH. No running Docker/ADB/emulator/device status was queried; executable presence is not a live environment or physical-device result. A local `node_modules/.bin/firebase.cmd` was absent, but the global Firebase CLI above exists. Node package availability and emulator caches were not executed/validated. Flutter 3.44.7 / Dart 3.12.2 are the existing progress-note versions, **not freshly executed version results from this inventory**.

## Root next executable checklist

1. Await PM5–PM8 accepted source handoffs; pause writers and obtain the single tool slot. Inspect actual final code/diff and preserve unrelated changes.
2. Finish current source generation/formatting if required, establish exact implementation SHA, create its `build/verification/<sha>/` evidence prefix, and generate/check feature map then final plan.
3. Run current PMT/compatibility/owner-rehome/rollback and affected UI/evidence tests, analyzer and relevant privacy/policy selections; classify every external prerequisite and named exclusion.
4. Run default and serial JSON inventories, three host-fake journeys, applicable demo policy tests, bounded Gitleaks and literal OSV gate; no overlapping Flutter/build/scanner source writers.
5. Build one current-version/current-source debug APK, record size/hash/config, verify native integrity and package metadata. Keep default-off/Hidden/Internal.
6. Repeat generator checks and bounded final diff/source consistency; assemble RTM 258/258 / PMT 44 / UAT-039–050 mapping with actual evidence type and results. Keep unexecuted UAT/sign-off blank or explicitly Not Run, and record owners/dates only when actually assigned.

Inspection recovery note: one initial broad `rg` included absent `dart_test.yaml` and emitted a missing-path error; subsequent `Test-Path` established it is absent and searches used actual directories. A later optional inventory included absent `tool/cli/.runtime`; existence was then reconciled without a retry or write. Read-only no-match exits were not treated as test failures. No runtime process was started by this worker; only this report was added.
