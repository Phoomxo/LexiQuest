#Requires -Version 5.1
<#
.SYNOPSIS
    Dependency-free contract test for the root OSV-Scanner exceptions.
#>
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0

function Assert-Count {
    param([string]$Text, [string]$Pattern, [int]$Expected, [string]$Message)
    $actual = ([regex]::Matches($Text, $Pattern)).Count
    if ($actual -eq $Expected) { $script:Passed++ } else {
        $script:Failed++
        Write-Host ("  [FAIL] {0}: expected {1}, got {2}" -f $Message, $Expected, $actual) -ForegroundColor Red
    }
}

$repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$configPath = Join-Path $repoRoot 'osv-scanner.toml'
if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Host "FAIL: missing $configPath" -ForegroundColor Red
    exit 1
}
$text = ([System.IO.File]::ReadAllText($configPath) -replace "`r`n", "`n") -replace "`r", "`n"

# brace-expansion@2.1.2 (GHSA-mh99 / GHSA-rgw5) was fixed via the scoped npm
# override in package.json (forces ^2.1.4). The contract below both pins the
# single remaining accepted ignore (uuid) and guards against brace-expansion
# regressing back into the ignore set.
Assert-Count $text '(?m)^\[\[IgnoredVulns\]\]\s*$' 1 'exactly one accepted ignore (uuid only)'
Assert-Count $text '(?m)^\s*id\s*=\s*"GHSA-w5hq-g745-h8pq"\s*$' 1 'uuid advisory id'
Assert-Count $text '(?m)^\s*reason\s*=\s*"\S[^"]*"\s*$' 1 'each advisory has a reason'
Assert-Count $text '(?m)^\s*ignoreUntil\s*=\s*2026-10-26\s*$' 1 'each exception expires on 2026-10-26'
Assert-Count $text '(?m)^\s*id\s*=\s*"GHSA-mh99-v99m-4gvg"\s*$' 0 'brace-expansion is fixed, not ignored'
Assert-Count $text '(?m)^\[\[PackageOverrides\]\]\s*$' 0 'package-wide overrides are forbidden'

Write-Host ("OSV config contract tests: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
