#Requires -Version 5.1
<#
.SYNOPSIS
    Dependency-free contract test for the OSV-Scanner pull-request workflow.
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
$workflowPath = Join-Path $repoRoot '.github/workflows/osv-scanner-pr.yml'
if (-not (Test-Path -LiteralPath $workflowPath)) {
    Write-Host "FAIL: missing $workflowPath" -ForegroundColor Red
    exit 1
}
$text = ([System.IO.File]::ReadAllText($workflowPath) -replace "`r`n", "`n") -replace "`r", "`n"
$sha = '9a498708959aeaef5ef730655706c5a1df1edbc2'

Assert-Match $text '(?m)^\s*pull_request\s*:' 'pull_request trigger exists'
Assert-Match $text '(?m)^\s*merge_group\s*:' 'merge_group trigger exists'
$mainBranches = ([regex]::Matches($text, '(?m)^\s*branches\s*:\s*\[main\]\s*$')).Count
if ($mainBranches -eq 2) { $script:Passed++ } else { $script:Failed++; Write-Host '  [FAIL] both triggers must target main' -ForegroundColor Red }
Assert-Match $text '(?m)^\s*actions\s*:\s*read\s*$' 'actions permission is read'
Assert-Match $text '(?m)^\s*contents\s*:\s*read\s*$' 'contents permission is read'
Assert-Match $text '(?m)^\s*security-events\s*:\s*write\s*$' 'security-events permission is write'
$permissionCount = ([regex]::Matches($text, '(?m)^\s{2}(actions|contents|security-events)\s*:')).Count
if ($permissionCount -eq 3) { $script:Passed++ } else { $script:Failed++; Write-Host '  [FAIL] permission scope changed' -ForegroundColor Red }
Assert-Match $text ([regex]::Escape("google/osv-scanner-action/.github/workflows/osv-scanner-reusable-pr.yml@$sha")) 'official PR workflow is SHA-pinned'
if ($text -notmatch 'osv-scanner-reusable-pr\.yml@(main|master|latest|v\d)') { $script:Passed++ } else { $script:Failed++ }

Write-Host ("OSV PR contract tests: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
