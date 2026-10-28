#Requires -Version 5.1
<#
.SYNOPSIS
    Dependency-free contract test for the scheduled OSV-Scanner workflow.
#>
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) { $script:Passed++ } else {
        $script:Failed++
        Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
    }
}

$repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$workflowPath = Join-Path $repoRoot '.github/workflows/osv-scanner-scheduled.yml'
if (-not (Test-Path -LiteralPath $workflowPath)) {
    Write-Host "FAIL: missing $workflowPath" -ForegroundColor Red
    exit 1
}
$text = ([System.IO.File]::ReadAllText($workflowPath) -replace "`r`n", "`n") -replace "`r", "`n"
$sha = '9a498708959aeaef5ef730655706c5a1df1edbc2'

Assert-Match $text '(?m)^\s*push\s*:' 'push trigger exists'
Assert-Match $text '(?m)^\s*branches\s*:\s*\[main\]\s*$' 'push targets main'
Assert-Match $text '(?m)^\s*-\s*cron\s*:\s*[''"]0 21 \* \* 0[''"]\s*$' 'weekly schedule is Monday 04:00 Asia/Bangkok'
Assert-Match $text '(?m)^\s*actions\s*:\s*read\s*$' 'actions permission is read'
Assert-Match $text '(?m)^\s*contents\s*:\s*read\s*$' 'contents permission is read'
Assert-Match $text '(?m)^\s*security-events\s*:\s*write\s*$' 'security-events permission is write'
Assert-Match $text ([regex]::Escape("google/osv-scanner-action/.github/workflows/osv-scanner-reusable.yml@$sha")) 'official full workflow is SHA-pinned'
if ($text -notmatch 'osv-scanner-reusable\.yml@(main|master|latest|v\d)') { $script:Passed++ } else { $script:Failed++ }

Write-Host ("OSV scheduled contract tests: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
