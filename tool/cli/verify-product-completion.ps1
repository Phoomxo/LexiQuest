#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$results = @()

function Invoke-Gate {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
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
    'lib/config',
    'lib/data/local',
    'lib/features/account',
    'lib/features/export',
    'lib/features/identity',
    'lib/features/learning',
    'lib/features/progress',
    'lib/features/rewards',
    'lib/features/sync',
    'lib/navigation',
    'lib/runtime',
    'lib/screens',
    'test/architecture',
    'test/config',
    'test/data/local',
    'test/features/account',
    'test/features/export',
    'test/features/identity',
    'test/features/learning',
    'test/features/progress',
    'test/features/rewards',
    'test/features/sync',
    'test/runtime',
    'test/screens'
)

$flutterTests = @(
    'test/architecture',
    'test/config',
    'test/data/local',
    'test/features/account',
    'test/features/export',
    'test/features/identity',
    'test/features/learning',
    'test/features/progress',
    'test/features/rewards',
    'test/features/sync',
    'test/runtime',
    'test/screens/accessibility_smoke_test.dart',
    'test/screens/achievements_screen_test.dart',
    'test/screens/avatar_equipment_screen_test.dart',
    'test/screens/ghost_shadow_duel_screen_test.dart',
    'test/screens/login_guest_mode_test.dart',
    'test/screens/main_navigation_screen_test.dart',
    'test/screens/mastery_dashboard_screen_test.dart',
    'test/screens/offline_vocabulary_journey_test.dart',
    'test/screens/otp_screen_test.dart',
    'test/screens/production_shell_navigation_test.dart',
    'test/screens/profile_settings_screen_test.dart',
    'test/screens/registration_flow_test.dart',
    'test/screens/shadowing_challenge_screen_test.dart',
    'test/screens/weakness_clinic_screen_test.dart',
    'test/screens/word_scramble_screen_test.dart'
)

Push-Location -LiteralPath $repoRoot
try {
    Invoke-Gate 'CLI contract' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File `
            'tool/cli/tests/verify-product-completion.tests.ps1'
    }
    Invoke-Gate 'Dart format' {
        # Contract marker: dart format --output=none --set-exit-if-changed
        & dart format --output=none --set-exit-if-changed $dartFiles
    }
    Invoke-Gate 'Static analysis' {
        & flutter analyze
    }
    Invoke-Gate 'Product completion tests' {
        & flutter test --no-pub --timeout 90s --reporter compact $flutterTests
    }
    Invoke-Gate 'Firebase Auth emulator journey' {
        & npm run test:auth
    }
    Invoke-Gate 'Firestore emulator rules' {
        & npm run test:rules
    }
    Invoke-Gate 'Android debug APK' {
        # Contract marker: flutter build apk --debug
        & flutter build apk --debug --no-pub `
            --dart-define=LEXIQUEST_CLOUD_SYNC_ENABLED=true `
            --dart-define=LEXIQUEST_VERSION=1.0.0+1 `
            --dart-define=LEXIQUEST_BUILD_ID=p7-product-completion
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

Write-Host 'LexiQuest P7 product completion gate: PASS' -ForegroundColor Green
foreach ($result in $results) {
    Write-Host ('  {0}: PASS' -f $result.Name) -ForegroundColor Green
}
exit 0
