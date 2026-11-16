#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'verify-device-model.ps1'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    Write-Error 'verify-device-model.ps1 is missing.'
}

$source = Get-Content -LiteralPath $scriptPath -Raw -Encoding utf8
$required = @(
    'prepare-field-model.ps1',
    'verify-apk-model-runtime.ps1',
    'dart format --output=none --set-exit-if-changed',
    'flutter analyze',
    'test/features/device_model',
    'test/data/local/app_database_migration_test.dart',
    'flutter build apk --debug',
    'git diff --check'
)
foreach ($needle in $required) {
    if (-not $source.Contains($needle)) {
        Write-Error ("Missing P4 gate command or path: {0}" -f $needle)
    }
}
if ($source -match 'flutter test\s+--reporter') {
    Write-Error 'P4 gate must not run a repository-wide Flutter test loop.'
}

Write-Host 'verify-device-model contract: PASS' -ForegroundColor Green
exit 0
