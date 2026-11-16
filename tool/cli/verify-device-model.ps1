#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$results = @()

function Invoke-Gate {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    & $Action
    $code = [int]$LASTEXITCODE
    $script:results += [pscustomobject]@{ Name = $Name; ExitCode = $code }
    if ($code -ne 0) {
        throw ("Gate failed: {0} (exit {1})" -f $Name, $code)
    }
}

$dartFiles = @(
    'lib/data/local/app_database.dart',
    'lib/data/local/tables/model_tables.dart',
    'lib/features/device_model',
    'lib/runtime/app_bootstrap.dart',
    'lib/runtime/app_dependencies.dart',
    'test/data/local/app_database_migration_test.dart',
    'test/data/local/app_database_test.dart',
    'test/features/device_model',
    'test/runtime/app_bootstrap_test.dart'
)

Push-Location -LiteralPath $repoRoot
try {
    Invoke-Gate 'CLI contract' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File `
            'tool/cli/tests/verify-device-model.tests.ps1'
    }
    Invoke-Gate 'Model source contract' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File `
            'tool/cli/tests/prepare-field-model.tests.ps1'
    }
    Invoke-Gate 'APK runtime integrity contract' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File `
            'tool/cli/tests/verify-apk-model-runtime.tests.ps1'
    }
    Invoke-Gate 'Pinned model fixture' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File `
            'tool/cli/prepare-field-model.ps1'
    }
    Invoke-Gate 'Dart format' {
        # Contract marker: dart format --output=none --set-exit-if-changed
        & dart format --output=none --set-exit-if-changed $dartFiles
    }
    Invoke-Gate 'Static analysis' {
        & flutter analyze
    }
    Invoke-Gate 'Device model tests' {
        & flutter test `
            test/features/device_model `
            test/data/local/app_database_migration_test.dart `
            test/data/local/app_database_test.dart `
            test/runtime/app_bootstrap_test.dart `
            --timeout 90s --reporter compact
    }
    Invoke-Gate 'Android debug APK' {
        # Contract marker: flutter build apk --debug
        $buildArguments = @(
            'build',
            'apk',
            '--debug',
            '--dart-define=LEXIQUEST_VERSION=1.0.0+1',
            '--dart-define=LEXIQUEST_BUILD_ID=p4-device-model'
        )
        & flutter @buildArguments
    }
    Invoke-Gate 'APK model runtime integrity' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File `
            'tool/cli/verify-apk-model-runtime.ps1'
    }
    Invoke-Gate 'Whitespace and conflict markers' {
        & git diff --check
    }
}
finally {
    Pop-Location
}

Write-Host 'LexiQuest P4 device-model gate: PASS' -ForegroundColor Green
foreach ($result in $results) {
    Write-Host ('  {0}: PASS' -f $result.Name) -ForegroundColor Green
}
exit 0
