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
$voiceConfigPath = Join-Path $repoRoot 'backend\voice_api\osv-scanner.toml'
$voiceProjectPath = Join-Path $repoRoot 'backend\voice_api\pyproject.toml'
$voiceReadmePath = Join-Path $repoRoot 'backend\voice_api\README.md'
$gatePath = Join-Path $repoRoot 'tool\cli\verify-osv-locks.ps1'
$evidencePath = Join-Path $repoRoot `
    'docs\field\2026-08-09-p8-hardening-evidence.md'
if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Host "FAIL: missing $configPath" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $voiceConfigPath)) {
    Write-Host "FAIL: missing $voiceConfigPath" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $gatePath)) {
    Write-Host "FAIL: missing $gatePath" -ForegroundColor Red
    exit 1
}
$text = ([System.IO.File]::ReadAllText($configPath) -replace "`r`n", "`n") -replace "`r", "`n"
$voiceText = ([System.IO.File]::ReadAllText($voiceConfigPath) -replace "`r`n", "`n") -replace "`r", "`n"
$voiceProject = ([System.IO.File]::ReadAllText($voiceProjectPath) -replace "`r`n", "`n") -replace "`r", "`n"
$voiceReadme = ([System.IO.File]::ReadAllText($voiceReadmePath) -replace "`r`n", "`n") -replace "`r", "`n"
$evidence = ([System.IO.File]::ReadAllText($evidencePath) -replace "`r`n", "`n") -replace "`r", "`n"
$gate = ([System.IO.File]::ReadAllText($gatePath) -replace "`r`n", "`n") -replace "`r", "`n"

# brace-expansion@2.1.2 (GHSA-mh99 / GHSA-rgw5) was fixed via the scoped npm
# override in package.json (forces ^2.1.4). The contract below both pins the
# Root policy is repository-wide and therefore permits only the existing npm
# exception. Optional voice-GPU exceptions live in a voice-lock-only config.
Assert-Count $text '(?m)^\[\[IgnoredVulns\]\]\s*$' 1 'root policy has exactly one npm exception'
Assert-Count $text '(?m)^\s*id\s*=\s*"GHSA-w5hq-g745-h8pq"\s*$' 1 'uuid advisory id'
Assert-Count $text '(?m)^\s*reason\s*=\s*"\S[^"]*"\s*$' 1 'root advisory has a reason'
Assert-Count $text '(?m)^\s*ignoreUntil\s*=\s*2026-10-26\s*$' 1 'uuid exception expiry'
Assert-Count $text '(?m)^\s*id\s*=\s*"GHSA-mh99-v99m-4gvg"\s*$' 0 'brace-expansion is fixed, not ignored'
Assert-Count $text '(?m)^\s*id\s*=\s*"PYSEC-2026-3552"\s*$' 0 'cryptography is fixed, not ignored'
Assert-Count $text '(?m)^\s*id\s*=\s*"PYSEC-2026-3628"\s*$' 0 'h2 is fixed, not ignored'
Assert-Count $text '(?m)^\s*id\s*=\s*"(?:PYSEC-2025-203|PYSEC-2025-204|PYSEC-2025-206|PYSEC-2026-139|PYSEC-2026-2286|GHSA-qfhq-4f3w-5fph|GHSA-rrmf-rvhw-rf47|GHSA-vgrw-7cvw-pwgx)"\s*$' 0 'root policy cannot suppress optional voice Torch advisories'
Assert-Count $text '(?m)^\[\[PackageOverrides\]\]\s*$' 0 'package-wide overrides are forbidden'

Assert-Count $voiceText '(?m)^\[\[IgnoredVulns\]\]\s*$' 8 'voice policy has eight exact Torch advisory exceptions'
Assert-Count $voiceText '(?m)^\s*id\s*=\s*"PYSEC-2025-203"\s*$' 1 'Torch linalg advisory id'
Assert-Count $voiceText '(?m)^\s*id\s*=\s*"PYSEC-2025-204"\s*$' 1 'Torch rot90 advisory id'
Assert-Count $voiceText '(?m)^\s*id\s*=\s*"PYSEC-2025-206"\s*$' 1 'Torch integer-overflow advisory id'
Assert-Count $voiceText '(?m)^\s*id\s*=\s*"PYSEC-2026-139"\s*$' 1 'Torch loading-handler advisory id'
Assert-Count $voiceText '(?m)^\s*id\s*=\s*"PYSEC-2026-2286"\s*$' 1 'Torch weights-only advisory id'
Assert-Count $voiceText '(?m)^\s*id\s*=\s*"GHSA-qfhq-4f3w-5fph"\s*$' 1 'Torch lstm-cell advisory id'
Assert-Count $voiceText '(?m)^\s*id\s*=\s*"GHSA-rrmf-rvhw-rf47"\s*$' 1 'Torch jit-script advisory id'
Assert-Count $voiceText '(?m)^\s*id\s*=\s*"GHSA-vgrw-7cvw-pwgx"\s*$' 1 'Torch unpack-sequence advisory id'
Assert-Count $voiceText '(?m)^\s*reason\s*=\s*"\S[^"]*"\s*$' 8 'each Torch advisory has a reason'
Assert-Count $voiceText '(?m)^\s*ignoreUntil\s*=\s*2026-09-11\s*$' 8 'each Torch exception has the short review expiry'
Assert-Count $voiceText '(?m)^\s*id\s*=\s*"GHSA-w5hq-g745-h8pq"\s*$' 0 'voice policy cannot suppress the npm advisory'
Assert-Count $voiceText '(?m)^\[\[PackageOverrides\]\]\s*$' 0 'voice package-wide overrides are forbidden'

# The Torch exceptions remain valid only while the dependency is confined to
# the explicitly optional, unfielded OmniVoice GPU research stack.
Assert-Count $voiceProject '(?m)^gpu\s*=\s*\[$' 1 'voice GPU dependencies are a separate group'
Assert-Count $voiceProject '(?m)^\s*"omnivoice==0\.2\.1",\s*$' 1 'locked OmniVoice research version'
Assert-Count $voiceProject '(?m)^\s*"torch==2\.8\.0\+cu128",\s*$' 1 'locked Torch CUDA research version'
Assert-Count $voiceProject '(?m)^\s*"torchaudio==2\.8\.0\+cu128",\s*$' 1 'locked Torchaudio CUDA research version'
Assert-Count $voiceReadme '(?im)^.*research spike, not a completed backend\..*$' 1 'remote voice remains a research spike'
Assert-Count $voiceReadme '(?im)^.*opt-in end-to-end integration test.*$' 1 'real remote voice integration remains opt-in'
Assert-Count $evidence 'backend/voice_api/osv-scanner\.toml' 1 'evidence names the voice-lock-only exception policy'
Assert-Count $evidence 'repository-wide root OSV policy contains no Torch exception' 1 'evidence records that Torch is not globally suppressed'
Assert-Count $evidence 'tool/cli/verify-osv-locks\.ps1' 2 'evidence and ledger name the executable scope boundary'
Assert-Count $evidence 'pairs\s+the\s+voice\s+policy\s+exclusively\s+with\s+`backend/voice_api/uv\.lock`' 1 'evidence records the exact voice policy and lock pairing'

# The executable gate is the scope boundary: the voice policy may be passed
# only with the voice lock, while every other dependency file uses root policy.
Assert-Count $gate '(?m)^\s*Invoke-LockScan -ConfigPath ''backend/voice_api/osv-scanner\.toml'' -Lockfile ''backend/voice_api/uv\.lock''\s*$' 1 'voice policy is paired exactly with the voice lock'
Assert-Count $gate '(?m)^\s*Invoke-LockScan -ConfigPath ''osv-scanner\.toml'' -Lockfile ' 5 'five non-voice inventories use root policy'
Assert-Count $gate '(?m)^\s*Invoke-LockScan ' 6 'exactly six dependency inventories are scanned'
Assert-Count $gate '(?m)--recursive' 0 'recursive scanning is forbidden by the Windows path contract'
Assert-Count $gate '(?m)\*' 0 'wildcard paths are forbidden by the Windows path contract'
Assert-Count $gate '(?m)if \(\$LASTEXITCODE -ne 0\)' 1 'any lock scan failure stops the gate'

Write-Host ("OSV config contract tests: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
