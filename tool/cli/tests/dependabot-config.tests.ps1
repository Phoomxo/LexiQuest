#Requires -Version 5.1
<#
.SYNOPSIS
    Dependency-free contract test for the LexiQuest Dependabot configuration.
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

function Assert-NoMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) {
        $script:Failed++
        Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
    } else { $script:Passed++ }
}

function Assert-Ecosystem {
    param([string]$Text, [string]$Ecosystem, [string]$Directory)
    $ecosystemPattern = [regex]::Escape($Ecosystem)
    $directoryPattern = [regex]::Escape($Directory)
    $pattern = '(?si)package-ecosystem\s*:\s*"?{0}"?(?:(?!package-ecosystem\s*:).)*?directory\s*:\s*"?{1}"?' -f $ecosystemPattern, $directoryPattern
    Assert-Match $Text $pattern ("{0} monitors {1}" -f $Ecosystem, $Directory)
}

$repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$configPath = Join-Path $repoRoot '.github/dependabot.yml'
if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Host "FAIL: missing $configPath" -ForegroundColor Red
    exit 1
}
$text = ([System.IO.File]::ReadAllText($configPath) -replace "`r`n", "`n") -replace "`r", "`n"

Assert-Match $text '(?m)^version\s*:\s*2\s*$' 'config uses schema version 2'
Assert-Ecosystem $text 'npm' '/'
Assert-Ecosystem $text 'npm' '/functions'
Assert-Ecosystem $text 'pub' '/'
Assert-Ecosystem $text 'gradle' '/android'
Assert-Ecosystem $text 'uv' '/backend/ai_api'
Assert-Ecosystem $text 'uv' '/backend/voice_api'
Assert-Ecosystem $text 'uv' '/backend/lexiquest_lm'
Assert-Ecosystem $text 'pip' '/backend/lexiquest_lm/deploy/hf_space'
Assert-Ecosystem $text 'docker' '/backend/lexiquest_lm/deploy/hf_space'
Assert-Ecosystem $text 'github-actions' '/'
Assert-NoMatch $text '(?m)^\s*(target-branch|registries|reviewers|assignees)\s*:' 'config contains a forbidden ownership or registry key'

Write-Host ("Dependabot contract tests: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
