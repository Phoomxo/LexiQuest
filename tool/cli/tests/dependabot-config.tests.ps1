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
Assert-Ecosystem $text 'pub' '/'
Assert-Ecosystem $text 'gradle' '/android'
Assert-Ecosystem $text 'uv' '/backend/ai_api'
Assert-Ecosystem $text 'uv' '/backend/voice_api'
Assert-Ecosystem $text 'uv' '/backend/lexiquest_lm'
Assert-Ecosystem $text 'pip' '/backend/lexiquest_lm/deploy/hf_space'
Assert-Ecosystem $text 'docker' '/backend/lexiquest_lm/deploy/hf_space'
Assert-Ecosystem $text 'github-actions' '/'
Assert-NoMatch $text '(?m)^\s*(target-branch|registries|reviewers|assignees)\s*:' 'config contains a forbidden ownership or registry key'

# GitHub's groups.update-types enum is major/minor/patch; ignore.update-types
# uses a different vocabulary. This checks the nine existing block-style groups.
# https://github.blog/changelog/2023-08-17-grouped-version-updates-by-semantic-version-level-for-dependabot/
function Test-GroupEnums([string]$Config) {
    $blocks = [regex]::Matches($Config, '(?m)^    groups:\n      minor-and-patch:\n        update-types:\n(?<values>(?:          - [^\n]+\n)+)')
    if ($blocks.Count -ne 9) { return $false }
    foreach ($block in $blocks) {
        $values = @([regex]::Matches($block.Groups['values'].Value, '(?m)^          - "?([^"\n]+)"?$') | ForEach-Object { $_.Groups[1].Value })
        if ($values.Count -ne 2 -or $values[0] -cne 'minor' -or $values[1] -cne 'patch') { return $false }
    }
    return $true
}
if (-not (Test-GroupEnums $text)) { $script:Failed++; Write-Host '[FAIL] nine groups must use minor/patch enums' } else { $script:Passed++ }
$validFixture = $text.Replace('version-update:semver-minor','minor').Replace('version-update:semver-patch','patch')
foreach ($invalid in @('version-update:semver-minor','unknown','MINOR')) {
    if (Test-GroupEnums $validFixture.Replace('"minor"', ('"'+$invalid+'"'))) { throw 'Group enum negative fixture was accepted' }
}

Write-Host ("Dependabot contract tests: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
