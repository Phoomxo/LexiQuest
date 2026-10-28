#Requires -Version 5.1
<#
.SYNOPSIS
    Dependency-free contract tests for backend environments in verify.ps1.

.DESCRIPTION
    Ensures clean worktrees provision frozen CPU/dev dependencies for every
    backend suite while excluding optional GPU, LLM, and training groups.
#>
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:PassedCount = 0
$script:FailedCount = 0

function Write-Pass {
    param([string]$Message)
    $script:PassedCount++
}

function Write-Fail {
    param([string]$Message)
    $script:FailedCount++
    Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
}

function Assert-RegexMatches {
    param([string]$Haystack, [string]$Pattern, [string]$Message)
    if (-not [string]::IsNullOrEmpty($Haystack) -and ($Haystack -match $Pattern)) {
        Write-Pass $Message
    } else {
        Write-Fail ($Message + ' (regex did not match: ' + $Pattern + ')')
    }
}

function Assert-RegexNotMatches {
    param([string]$Haystack, [string]$Pattern, [string]$Message)
    if (-not [string]::IsNullOrEmpty($Haystack) -and ($Haystack -match $Pattern)) {
        Write-Fail ($Message + ' (forbidden match: ' + $Pattern + ')')
    } else {
        Write-Pass $Message
    }
}

function Get-NormalizedText {
    param([string]$Path)
    $raw = [System.IO.File]::ReadAllText($Path)
    return (($raw -replace "`r`n", "`n") -replace "`r", "`n")
}

function Get-VerifyPhaseBody {
    param([string]$Text, [string]$Number)
    $phasePattern = (
        '(?ms)^[ \t]*Invoke-VerifyPhase[ \t]+''' +
        [regex]::Escape($Number) +
        '''[ \t]+''[^'']+''[ \t]*\{(?<Body>.*?)(?=^[ \t]*Invoke-VerifyPhase[ \t]+''|\z)'
    )
    $match = [regex]::Match($Text, $phasePattern)
    if (-not $match.Success) {
        Write-Fail ('verify.ps1 declares phase ' + $Number)
        return ''
    }
    Write-Pass ('verify.ps1 declares phase ' + $Number)
    return $match.Groups['Body'].Value
}

function Test-BackendPhase {
    param(
        [string]$Body,
        [string]$Name,
        [string]$ProjectPath,
        [string]$ExcludedGroup
    )
    Assert-RegexMatches $Body '(?m)&[ \t]+uv[ \t]+run\b' ($Name + ' runs tests through uv')
    Assert-RegexMatches $Body (
        '--project[ \t]+\([^\n]*''' + [regex]::Escape($ProjectPath) + '''\)'
    ) ($Name + ' selects its project')
    Assert-RegexMatches $Body '(?m)^[ \t]*--frozen[ \t]*`?[ \t]*$' ($Name + ' uses the frozen lockfile')
    Assert-RegexMatches $Body '(?m)^[ \t]*--group[ \t]+dev[ \t]*`?[ \t]*$' ($Name + ' provisions dev dependencies')
    Assert-RegexMatches $Body (
        '(?m)^[ \t]*--no-group[ \t]+' + [regex]::Escape($ExcludedGroup) + '[ \t]*`?[ \t]*$'
    ) ($Name + ' excludes the ' + $ExcludedGroup + ' group')
    Assert-RegexNotMatches $Body '(?m)^[ \t]*--no-sync\b' ($Name + ' does not suppress environment provisioning')
    Assert-RegexNotMatches $Body '(?m)^[ \t]*--all-groups\b' ($Name + ' does not install every optional group')
}

$repoToolCli = Split-Path $PSScriptRoot -Parent
$verifyPath = Join-Path $repoToolCli 'verify.ps1'
if (-not (Test-Path -LiteralPath $verifyPath)) {
    Write-Host ("FAIL: missing verification script '{0}'." -f $verifyPath) -ForegroundColor Red
    exit 1
}

$verifyText = Get-NormalizedText -Path $verifyPath
$contractPhase = Get-VerifyPhaseBody -Text $verifyText -Number '02.1'
Assert-RegexMatches $contractPhase (
    '(?m)^[ \t]*''verify-backend-environments\.tests\.ps1'',[ \t]*$'
) 'phase 02.1 runs the backend environment contract'

$voicePhase = Get-VerifyPhaseBody -Text $verifyText -Number '07'
Test-BackendPhase `
    -Body $voicePhase `
    -Name 'Voice API' `
    -ProjectPath 'backend\voice_api' `
    -ExcludedGroup 'gpu'

$aiPhase = Get-VerifyPhaseBody -Text $verifyText -Number '08'
Test-BackendPhase `
    -Body $aiPhase `
    -Name 'AI API' `
    -ProjectPath 'backend\ai_api' `
    -ExcludedGroup 'llm'

$lmPhase = Get-VerifyPhaseBody -Text $verifyText -Number '09'
Test-BackendPhase `
    -Body $lmPhase `
    -Name 'Local LM' `
    -ProjectPath 'backend\lexiquest_lm' `
    -ExcludedGroup 'train'

$total = $script:PassedCount + $script:FailedCount
Write-Host ''
Write-Host (
    'Backend environment contract tests: {0} passed, {1} failed (of {2})' -f
    $script:PassedCount,
    $script:FailedCount,
    $total
)
if ($script:FailedCount -gt 0) {
    Write-Host 'FAILED' -ForegroundColor Red
    exit 1
}

Write-Host 'PASS' -ForegroundColor Green
exit 0
