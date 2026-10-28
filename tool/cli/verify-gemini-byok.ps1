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
    'lib/features/gemini',
    'lib/runtime/app_bootstrap.dart',
    'lib/runtime/app_dependencies.dart',
    'lib/screens/ai_tutor_screen.dart',
    'lib/screens/gemini_settings_screen.dart',
    'lib/screens/main_navigation_screen.dart',
    'test/features/gemini',
    'test/screens/ai_tutor_screen_test.dart',
    'test/screens/gemini_settings_screen_test.dart',
    'test/config/flutter_dependency_surface_test.dart'
)

Push-Location -LiteralPath $repoRoot
try {
    Invoke-Gate 'CLI contract' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File `
            'tool/cli/tests/verify-gemini-byok.tests.ps1'
    }
    Invoke-Gate 'Dart format' {
        # Contract marker: dart format --output=none --set-exit-if-changed
        & dart format --output=none --set-exit-if-changed $dartFiles
    }
    Invoke-Gate 'Static analysis' {
        & flutter analyze
    }
    Invoke-Gate 'Gemini BYOK tests' {
        & flutter test `
            test/features/gemini `
            test/screens/ai_tutor_screen_test.dart `
            test/screens/gemini_settings_screen_test.dart `
            test/config/flutter_dependency_surface_test.dart `
            test/runtime/app_bootstrap_test.dart `
            test/screens/main_navigation_screen_test.dart `
            --timeout 90s --reporter compact
    }
    Invoke-Gate 'Android debug APK' {
        # Contract marker: flutter build apk --debug
        $buildArguments = @(
            'build',
            'apk',
            '--debug',
            '--dart-define=LEXIQUEST_VERSION=1.0.0+1',
            '--dart-define=LEXIQUEST_BUILD_ID=p6-gemini-byok'
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

Write-Host 'LexiQuest P6 Gemini BYOK gate: PASS' -ForegroundColor Green
foreach ($result in $results) {
    Write-Host ('  {0}: PASS' -f $result.Name) -ForegroundColor Green
}
exit 0
