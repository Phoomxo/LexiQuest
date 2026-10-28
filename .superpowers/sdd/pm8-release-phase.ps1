param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('contracts', 'full-default', 'full-serial', 'host', 'focused', 'policy-static', 'policy-emulator', 'gitleaks', 'osv', 'build', 'apk-integrity', 'final-checks')]
    [string]$Phase
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$pm8ExpectedRoot = 'C:\Users\Phet\.codex\worktrees\02fa\LexiQuest'
if ((Get-Location).Path -cne $pm8ExpectedRoot) { throw 'Wrong PM8 worktree.' }
$pm8Plan = Get-Content -LiteralPath 'docs/generated/alltcas-8-44-final-test-plan.json' -Raw | ConvertFrom-Json
$pm8SourceCommit = [string]$pm8Plan.sourceCommit
$pm8Fingerprint = [string]$pm8Plan.sourceFingerprint
$pm8Flutter = 'C:/Users/Phet/AppData/Local/Programs/flutter/bin/flutter.bat'
$pm8Dart = 'C:/Users/Phet/AppData/Local/Programs/flutter/bin/dart.bat'
$pm8WindowsPs = 'C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
$pm8Npm = 'C:/Program Files/nodejs/npm.cmd'
$pm8EvidenceRoot = Join-Path $pm8ExpectedRoot ('build/verification/' + $pm8SourceCommit)
function Invoke-Pm8Gate {
    param([string]$GateLabel, [string]$GateExecutable, [string[]]$GateArguments)
    Write-Output ('Starting ' + $GateLabel)
    & (Join-Path $PSScriptRoot 'pm8-run-gate.ps1') -SourceCommit $pm8SourceCommit -SourceFingerprint $pm8Fingerprint -Label $GateLabel -Executable $GateExecutable -ArgumentList $GateArguments
    $pm8ReturnedExit = $global:LASTEXITCODE
    if ($null -eq $pm8ReturnedExit -or $pm8ReturnedExit -ne 0) {
        throw ('Retained gate failure: ' + $GateLabel + '; exit ' + $pm8ReturnedExit)
    }
}
switch ($Phase) {
    'contracts' {
        Invoke-Pm8Gate 'generator-contracts' $pm8Flutter @('test', '--no-pub', '--reporter', 'failures-only', 'test/architecture/final_8_44_test_plan_contract_test.dart', 'test/architecture/final_8_44_test_plan_review_contract_test.dart')
    }
    'full-default' {
        Invoke-Pm8Gate 'full-default' $pm8Flutter @('test', '--no-pub', '--exclude-tags', 'release-excluded', '--reporter', 'json')
    }
    'full-serial' {
        Invoke-Pm8Gate 'full-serial' $pm8Flutter @('test', '--no-pub', '--exclude-tags', 'release-excluded', '--concurrency=1', '--reporter', 'json')
    }
    'host' {
        foreach ($pm8Journey in @('core_journey', 'feature_controls', 'media_smoke')) {
            Invoke-Pm8Gate ('host-' + $pm8Journey.Replace('_', '-')) $pm8Flutter @('test', '-d', 'flutter-tester', '--no-pub', '--timeout', '90s', '--reporter', 'failures-only', ('integration_test/field_trial_' + $pm8Journey + '_test.dart'))
        }
    }
    'focused' {
        Invoke-Pm8Gate 'analyze' $pm8Flutter @('analyze', '--no-pub', 'lib', 'test')
        Invoke-Pm8Gate 'privacy-authority' $pm8Flutter @('test', '--no-pub', '--reporter', 'failures-only', 'test/config/flutter_dependency_surface_test.dart', 'test/config/research_runtime_config_test.dart', 'test/config/adventure_research_runtime_config_test.dart', 'test/features/consent/research_consent_use_cases_test.dart', 'test/features/export/research_lifecycle_export_test.dart', 'test/features/research/research_sync_authorizer_test.dart', 'test/features/research/research_runtime_sync_integration_test.dart', 'test/scenarios/complete_owner_export_delete_test.dart')
        Invoke-Pm8Gate 'runtime-catalog-navigation' $pm8Flutter @('test', '--no-pub', '--reporter', 'failures-only', 'test/runtime/production_feature_gate_test.dart', 'test/runtime/runtime_feature_controls_test.dart', 'test/architecture/alltcas_idea_feature_contract_test.dart', 'test/architecture/alltcas_idea_feature_contract_docs_test.dart', 'test/scenarios/production_feature_navigation_test.dart')
    }
    'policy-static' {
        Invoke-Pm8Gate 'firestore-static-policy' $pm8WindowsPs @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tool/cli/tests/firestore-rules-security.tests.ps1')
        Invoke-Pm8Gate 'osv-config-policy' $pm8WindowsPs @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tool/cli/tests/osv-config.tests.ps1')
    }
    'policy-emulator' {
        $pm8Listeners = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in @(9099, 8080) })
        if ($pm8Listeners.Count -gt 0) { throw 'Inspect existing listener ownership before demo emulator gates.' }
        Invoke-Pm8Gate 'demo-auth-policy' $pm8Npm @('run', 'test:auth')
        Invoke-Pm8Gate 'demo-firestore-policy' $pm8Npm @('run', 'test:rules')
    }
    'gitleaks' {
        foreach ($pm8Scope in @('lib', 'test', 'docs', 'tool/final_test_plan', 'tool/feature_contract', 'pubspec.yaml', 'pubspec.lock', 'firestore.rules', 'AGENTS.md')) {
            $pm8ScopeLabel = ($pm8Scope -replace '[^A-Za-z0-9-]', '-').ToLowerInvariant()
            $pm8Stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ', [Globalization.CultureInfo]::InvariantCulture)
            $pm8ReportPath = Join-Path $pm8EvidenceRoot ('pm8-' + $pm8Stamp + '-gitleaks-' + $pm8ScopeLabel + '.report.json')
            Invoke-Pm8Gate ('gitleaks-' + $pm8ScopeLabel) 'C:/Users/Phet/AppData/Local/Microsoft/WinGet/Links/gitleaks.exe' @('dir', $pm8Scope, '--redact', '--no-banner', '--config', '.gitleaks.toml', '--gitleaks-ignore-path', '.gitleaksignore', '--report-format', 'json', '--report-path', $pm8ReportPath)
        }
    }
    'osv' {
        Invoke-Pm8Gate 'osv-literal-locks' $pm8WindowsPs @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tool/cli/verify-osv-locks.ps1', '-ScannerPath', 'C:/Users/Phet/AppData/Local/Microsoft/WinGet/Links/osv-scanner.exe')
    }
    'build' {
        $pm8VersionMatch = Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$'
        if (@($pm8VersionMatch).Count -ne 1) { throw 'Cannot establish app version.' }
        $pm8Version = $pm8VersionMatch.Matches[0].Groups[1].Value
        Invoke-Pm8Gate 'debug-apk-build' $pm8Flutter @('build', 'apk', '--debug', '--no-pub', ('--dart-define=LEXIQUEST_VERSION=' + $pm8Version), ('--dart-define=LEXIQUEST_BUILD_ID=pair-' + $pm8SourceCommit))
    }
    'apk-integrity' {
        $pm8Apk = 'build/app/outputs/flutter-apk/app-debug.apk'
        if (-not (Test-Path -LiteralPath $pm8Apk -PathType Leaf)) { throw 'Current APK missing.' }
        Invoke-Pm8Gate 'apk-native-integrity' $pm8WindowsPs @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tool/cli/verify-apk-model-runtime.ps1', '-ApkPath', $pm8Apk, '-BuildMode', 'Debug')
        foreach ($pm8Field in @('application-id', 'version-name', 'version-code')) {
            Invoke-Pm8Gate ('apk-' + $pm8Field) 'C:/Users/Phet/AppData/Local/Android/Sdk/cmdline-tools/latest/bin/apkanalyzer.bat' @('manifest', $pm8Field, $pm8Apk)
        }
    }
    'final-checks' {
        Invoke-Pm8Gate 'final-feature-map-check' $pm8Dart @('run', 'tool/feature_contract/generate_feature_map.dart', '--check')
        Invoke-Pm8Gate 'final-test-plan-check' $pm8Dart @('run', 'tool/final_test_plan/generate_final_test_plan.dart', '--check', '--source-commit', $pm8SourceCommit)
    }
}
exit 0
