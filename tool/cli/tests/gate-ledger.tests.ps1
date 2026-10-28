#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0

function Assert-True {
    param([object]$Value, [string]$Message)
    if ($Value) {
        $script:Passed++
    } else {
        $script:Failed++
        Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
    }
}

$repoRoot = Split-Path -Parent (
    Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
)
. (Join-Path $repoRoot 'tool/cli/lib/gate-ledger.ps1')

$ledger = New-LexiQuestGateLedger
$record = [pscustomobject]@{
    gate = 'integration'
    commitSha = 'a' * 40
    dependencyLockSha256 = 'B' * 64
    apkSha256 = ''
    command = 'flutter test'
    result = 'pass'
    recordedAtUtc = '2026-08-01T00:00:00Z'
}

$errors = @(Test-LexiQuestGateRecord -Record $record)
Assert-True ($errors.Count -eq 0) 'a complete integration record is valid'

$ledger.records += $record
$mayRun = Test-LexiQuestGateMayRun `
    -Ledger $ledger `
    -Gate 'integration' `
    -CommitSha ('a' * 40) `
    -DependencyLockSha256 ('B' * 64) `
    -ApkSha256 '' `
    -Command 'flutter test'
Assert-True (-not $mayRun) 'an unchanged gate identity cannot run twice'

$mayRunAfterChange = Test-LexiQuestGateMayRun `
    -Ledger $ledger `
    -Gate 'integration' `
    -CommitSha ('c' * 40) `
    -DependencyLockSha256 ('B' * 64) `
    -ApkSha256 '' `
    -Command 'flutter test'
Assert-True $mayRunAfterChange 'a source change creates a new gate identity'

$release = [pscustomobject]@{
    gate = 'release'
    commitSha = 'a' * 40
    dependencyLockSha256 = 'B' * 64
    apkSha256 = 'C' * 64
    command = 'verify-field-release.ps1'
    result = 'pass'
    recordedAtUtc = '2026-08-01T00:00:00Z'
}
$errors = @(Test-LexiQuestGateRecord -Record $release)
Assert-True ($errors.Count -eq 0) 'a release record requires an APK hash'

$release.apkSha256 = ''
$errors = @(Test-LexiQuestGateRecord -Record $release)
Assert-True (
    ($errors -join "`n") -match 'apkSha256'
) 'a release record without an APK hash is rejected'

$lockRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'lexiquest-lock-test-' + [Guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Path $lockRoot | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $lockRoot 'pubspec.lock') `
        -Value 'root-lock' -Encoding utf8
    $buildDirectory = Join-Path $lockRoot 'build/transient'
    New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $buildDirectory 'uv.lock') `
        -Value 'generated-lock-a' -Encoding utf8
    $before = Get-LexiQuestDependencyLockSha256 -RepositoryRoot $lockRoot
    Set-Content -LiteralPath (Join-Path $buildDirectory 'uv.lock') `
        -Value 'generated-lock-b' -Encoding utf8
    $after = Get-LexiQuestDependencyLockSha256 -RepositoryRoot $lockRoot
    Assert-True ($before -eq $after) `
        'dependency hash ignores transient build-directory lock files'
} finally {
    Remove-Item -LiteralPath $lockRoot -Recurse -Force
}

Write-Host ("Gate ledger tests: {0} passed, {1} failed" -f `
    $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
