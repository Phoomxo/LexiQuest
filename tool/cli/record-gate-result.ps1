#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('microtask', 'package', 'integration', 'release')]
    [string]$Gate,
    [Parameter(Mandatory)][string]$Command,
    [Parameter(Mandatory)]
    [ValidateSet('pass', 'fail')]
    [string]$Result,
    [string]$ApkSha256 = '',
    [string]$LedgerPath = 'docs/field/gate-ledger.json'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'lib/gate-ledger.ps1')

$commitSha = (& git -C $repoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve the current Git commit.' }
$lockSha = Get-LexiQuestDependencyLockSha256 -RepositoryRoot $repoRoot
$resolvedLedger = if ([System.IO.Path]::IsPathRooted($LedgerPath)) {
    [System.IO.Path]::GetFullPath($LedgerPath)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $LedgerPath))
}
$ledger = if (Test-Path -LiteralPath $resolvedLedger -PathType Leaf) {
    Get-Content -LiteralPath $resolvedLedger -Raw -Encoding utf8 |
        ConvertFrom-Json
} else {
    New-LexiQuestGateLedger
}

$mayRun = Test-LexiQuestGateMayRun `
    -Ledger $ledger `
    -Gate $Gate `
    -CommitSha $commitSha `
    -DependencyLockSha256 $lockSha `
    -ApkSha256 $ApkSha256 `
    -Command $Command
if (-not $mayRun) {
    throw (
        'This exact gate identity is already recorded. Change source, lock ' +
        'files, APK hash, or the bounded command before running it again.'
    )
}

$record = [pscustomobject]@{
    gate = $Gate
    commitSha = $commitSha
    dependencyLockSha256 = $lockSha
    apkSha256 = $ApkSha256
    command = $Command
    result = $Result
    recordedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$errors = @(Test-LexiQuestGateRecord -Record $record)
if ($errors.Count -gt 0) {
    throw ('Invalid gate record: ' + ($errors -join '; '))
}
$ledger.records = @($ledger.records) + $record
$parent = Split-Path -Parent $resolvedLedger
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$ledger | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $resolvedLedger -Encoding utf8
Write-Host "Recorded $Gate gate result: $Result" -ForegroundColor Yellow
