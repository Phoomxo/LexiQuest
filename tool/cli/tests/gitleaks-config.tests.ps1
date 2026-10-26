#Requires -Version 5.1
<#
.SYNOPSIS
    Contract tests for narrow, path-and-pattern Gitleaks false-positive rules.
#>
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) { $script:Passed++ } else {
        $script:Failed++
        Write-Host ("  [FAIL] {0}" -f $Message) -ForegroundColor Red
    }
}

function Assert-NoMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { $script:Passed++ } else {
        $script:Failed++
        Write-Host ("  [FAIL] {0}" -f $Message) -ForegroundColor Red
    }
}

$repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$configPath = Join-Path $repoRoot '.gitleaks.toml'
if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Host "FAIL: missing $configPath" -ForegroundColor Red
    exit 1
}
$text = ([System.IO.File]::ReadAllText($configPath) -replace "`r`n", "`n") -replace "`r", "`n"

Assert-Match $text '(?m)^useDefault\s*=\s*true\s*$' 'default Gitleaks rules remain enabled'
Assert-NoMatch $text '(?m)^\s*condition\s*=\s*"OR"\s*$' 'allowlists never use broad OR matching'
Assert-Match $text 'Generated development evidence contains SHA-256 fingerprints' 'generated evidence allowlist is documented'
Assert-Match $text 'docs/development/\(\?:ari\|ux-delivery\|full-system\|post-g83-e' 'generated evidence paths are bounded'
Assert-Match $text '\[a-f0-9\]\{64\}' 'generated evidence allowlist requires a SHA-256-shaped value'
Assert-Match $text 'Retired Supabase anonymous client JWT was public configuration' 'historical public client JWT is documented'
Assert-Match $text 'ff2364209c53bf3b4ff5e3bff7630484d9c5fd05' 'historical JWT allowlist is commit bounded'
Assert-Match $text 'Synthetic AI provider keys are test fixtures' 'AI key fixtures are path bounded'
Assert-Match $text 'Sync and learning test identifiers are not credentials' 'domain identifiers are path bounded'
Assert-Match $text 'pm8-synthetic-owner-gate' 'domain allowlist names exact synthetic fixtures'
Assert-NoMatch $text '\(\?:ownerGateToken\|idempotencyKey\|leaseToken' 'domain allowlist does not accept arbitrary token assignments'
Assert-NoMatch $text "paths\s*=\s*\['''\(\?:\^\|/\)test/\.\*" 'no all-tests path allowlist exists'
Assert-NoMatch $text "paths\s*=\s*\['''\(\?:\^\|/\)docs/\.\*" 'no all-docs path allowlist exists'

Write-Host ("Gitleaks config contract tests: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
