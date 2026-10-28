#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'verify-learning-core.ps1'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    Write-Error 'verify-learning-core.ps1 is missing.'
}

$source = Get-Content -LiteralPath $scriptPath -Raw -Encoding utf8
$required = @(
    'dart format --output=none --set-exit-if-changed',
    'flutter analyze',
    'test/data/local/app_database_migration_test.dart',
    'test/features/learning/drift_learning_repository_test.dart',
    'test/features/sync/learning_event_sync_test.dart',
    'test/screens/quiz_screen_test.dart',
    'npm run test:rules',
    'flutter build apk --debug',
    'git diff --check'
)
foreach ($needle in $required) {
    if (-not $source.Contains($needle)) {
        Write-Error ("Missing required gate command or path: {0}" -f $needle)
    }
}
if ($source -match 'flutter test\s+--reporter') {
    Write-Error 'Learning gate must not run a repository-wide Flutter test loop.'
}

Write-Host 'verify-learning-core contract: PASS' -ForegroundColor Green
exit 0
