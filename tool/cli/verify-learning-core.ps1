#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the bounded P3 learning-core release gate.

.DESCRIPTION
    Verifies only the local database, learning evidence, projections, sync,
    participant learning screens, Firestore rules, and an Android debug build.
    It is fail-fast and never retries a failed command.
#>
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
    'lib/data/local/tables/learning_tables.dart',
    'lib/features/learning',
    'lib/features/progress',
    'lib/features/sync',
    'lib/screens/quiz_screen.dart',
    'lib/screens/srs_flashcards_screen.dart',
    'lib/screens/mastery_dashboard_screen.dart',
    'lib/screens/weakness_clinic_screen.dart',
    'test/data/local/app_database_migration_test.dart',
    'test/features/identity/drift_owner_upgrade_repository_test.dart',
    'test/features/learning/drift_learning_repository_test.dart',
    'test/features/learning/learning_use_cases_test.dart',
    'test/features/learning/srs_policy_test.dart',
    'test/features/progress/progress_projector_test.dart',
    'test/features/sync/background_sync_scheduler_test.dart',
    'test/features/sync/cloud_sync_policy_test.dart',
    'test/features/sync/drift_sync_store_test.dart',
    'test/features/sync/firestore_sync_gateway_test.dart',
    'test/features/sync/learning_event_sync_test.dart',
    'test/features/sync/sync_contract_test.dart',
    'test/features/sync/sync_engine_test.dart',
    'test/screens/quiz_screen_test.dart',
    'test/screens/srs_flashcards_screen_test.dart',
    'test/screens/mastery_dashboard_screen_test.dart',
    'test/screens/weakness_clinic_screen_test.dart'
)

$flutterTests = @(
    'test/data/local/app_database_migration_test.dart',
    'test/data/local/app_database_test.dart',
    'test/features/identity/drift_owner_upgrade_repository_test.dart',
    'test/features/learning/drift_learning_repository_test.dart',
    'test/features/learning/learning_use_cases_test.dart',
    'test/features/learning/srs_policy_test.dart',
    'test/features/progress/progress_projector_test.dart',
    'test/features/sync/background_sync_scheduler_test.dart',
    'test/features/sync/cloud_sync_policy_test.dart',
    'test/features/sync/drift_sync_store_test.dart',
    'test/features/sync/firestore_sync_gateway_test.dart',
    'test/features/sync/learning_event_sync_test.dart',
    'test/features/sync/sync_contract_test.dart',
    'test/features/sync/sync_engine_test.dart',
    'test/architecture/learning_screen_boundary_test.dart',
    'test/screens/quiz_screen_test.dart',
    'test/screens/srs_flashcards_screen_test.dart',
    'test/screens/mastery_dashboard_screen_test.dart',
    'test/screens/weakness_clinic_screen_test.dart'
)

Push-Location -LiteralPath $repoRoot
try {
    Invoke-Gate 'CLI contract' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File `
            'tool/cli/tests/verify-learning-core.tests.ps1'
    }
    Invoke-Gate 'Dart format' {
        # Contract marker: dart format --output=none --set-exit-if-changed
        & dart format --output=none --set-exit-if-changed $dartFiles
    }
    Invoke-Gate 'Static analysis' {
        & flutter analyze
    }
    Invoke-Gate 'Focused Flutter tests' {
        & flutter test $flutterTests --timeout 60s --reporter compact
    }
    Invoke-Gate 'Firestore emulator rules' {
        & npm run test:rules
    }
    Invoke-Gate 'Android debug APK' {
        $sha = (& git rev-parse --short HEAD).Trim()
        # Contract marker: flutter build apk --debug
        $buildArguments = @(
            'build',
            'apk',
            '--debug',
            '--dart-define=LEXIQUEST_VERSION=1.0.0+1',
            ("--dart-define=LEXIQUEST_BUILD_ID={0}-p3" -f $sha),
            '--dart-define=LEXIQUEST_VOICE_API_URL=http://10.0.2.2:8001',
            '--dart-define=LEXIQUEST_AI_API_URL=http://10.0.2.2:8000'
        )
        & flutter @buildArguments
    }
    Invoke-Gate 'Whitespace and conflict markers' {
        & git diff --check
    }
}
finally {
    Pop-Location
}

Write-Host 'LexiQuest P3 learning-core gate: PASS' -ForegroundColor Green
foreach ($result in $results) {
    Write-Host ('  {0}: PASS' -f $result.Name) -ForegroundColor Green
}
exit 0
