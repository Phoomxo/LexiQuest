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

Assert-Count $text '(?m)^\[\[IgnoredVulns\]\]\s*$' 2 'exactly two ignored advisories'
Assert-Count $text '(?m)^\s*id\s*=\s*"GHSA-mh99-v99m-4gvg"\s*$' 1 'brace-expansion advisory id'
Assert-Count $text '(?m)^\s*id\s*=\s*"GHSA-w5hq-g745-h8pq"\s*$' 1 'uuid advisory id'
Assert-Count $text '(?m)^\s*reason\s*=\s*"\S[^"]*"\s*$' 2 'each advisory has a reason'
Assert-Count $text '(?m)^\s*ignoreUntil\s*=\s*2026-10-26\s*$' 2 'each exception expires on 2026-10-26'
Assert-Count $text '(?m)^\[\[PackageOverrides\]\]\s*$' 0 'package-wide overrides are forbidden'

Write-Host ("OSV config contract tests: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
