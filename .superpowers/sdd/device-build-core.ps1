$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'device-run-gate.ps1'
$taskPowerShell = 'C:/Users/Phet/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe'
$gateIdentity = @{
    SourceCommit = '1875a61854490e0493cc084bffb705f5d3bd4b0b'
    CheckoutCommit = '788e90e62b1694c20945734787723c168b6a6ab2'
    SourceFingerprint = '50ddab9318080e5dd7cd4b640cfb63dbbf52fb9613d7d61fa8064a59132d22fc'
}
function Invoke-DeviceGate([string]$Label, [string]$Executable, [string[]]$Tokens) {
    & $runner @gateIdentity -Label $Label -Executable $Executable -ArgumentList $Tokens
    if ($global:LASTEXITCODE -ne 0) { exit $global:LASTEXITCODE }
}
Invoke-DeviceGate 'feature-map-preflight' 'dart' @('run', 'tool/feature_contract/generate_feature_map.dart', '--check')
Invoke-DeviceGate 'final-plan-preflight' 'dart' @('run', 'tool/final_test_plan/generate_final_test_plan.dart', '--check', '--source-commit', '1875a61854490e0493cc084bffb705f5d3bd4b0b')
Invoke-DeviceGate 'core-fixture-apk-build' 'flutter' @('build', 'apk', '--debug', '--no-pub', '--target-platform', 'android-arm64', '--target', 'integration_test/field_trial_core_journey_test.dart', '--dart-define=LEXIQUEST_VERSION=1.0.0+14', '--dart-define=LEXIQUEST_BUILD_ID=device-core-788e90e62b1694c20945734787723c168b6a6ab2')
