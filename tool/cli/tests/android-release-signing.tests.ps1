#Requires -Version 5.1
<#
.SYNOPSIS
    Dependency-free security contract for LexiQuest Android release signing.
#>
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0

function Assert-True {
    param([object]$Value, [string]$Message)
    if ($Value) { $script:Passed++ } else {
        $script:Failed++
        Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
    }
}

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

$repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$gradlePath = Join-Path $repoRoot 'android\app\build.gradle.kts'
$examplePath = Join-Path $repoRoot 'android\key.properties.example'
$androidGitignorePath = Join-Path $repoRoot 'android\.gitignore'

if (-not (Test-Path -LiteralPath $gradlePath)) {
    Write-Host ("FAIL: missing {0}" -f $gradlePath) -ForegroundColor Red
    exit 1
}
$gradle = [System.IO.File]::ReadAllText($gradlePath)

# Release must never sign with the debug keystore; it must bind a dedicated config.
Assert-NoMatch $gradle 'signingConfigs\.getByName\("debug"\)' 'release build does not reuse the debug signing config'
Assert-Match $gradle 'signingConfigs\s*\{[\s\S]*create\("release"\)' 'dedicated release signing config is declared'
Assert-Match $gradle 'buildTypes\s*\{[\s\S]*?release\s*\{[\s\S]*?signingConfig\s*=\s*signingConfigs\.getByName\("release"\)' 'release build type binds to the release signing config'

# Fail closed only when a release artifact is requested without key.properties.
Assert-Match $gradle 'rootProject\.file\("key\.properties"\)' 'build reads the local key.properties file'
Assert-Match $gradle 'Properties\(\)' 'build loads keystore values through java.util.Properties'
Assert-Match $gradle 'gradle\.taskGraph\.whenReady' 'build registers a task-graph readiness gate'
Assert-Match $gradle '(packageRelease|bundleRelease)' 'fail-closed gate observes release artifact tasks'
Assert-Match $gradle 'GradleException' 'fail-closed gate throws a GradleException with an actionable message'

# Secret-safe: the example ships placeholders only, and signing material stays out of git.
Assert-True (Test-Path -LiteralPath $examplePath) 'key.properties.example template is present'
if (Test-Path -LiteralPath $examplePath) {
    $exampleRaw = [System.IO.File]::ReadAllText($examplePath)
    $example = ($exampleRaw -replace "`r`n", "`n") -replace "`r", "`n"
    foreach ($key in 'storeFile', 'storePassword', 'keyAlias', 'keyPassword') {
        Assert-Match $example ('(?m)^\s*' + [regex]::Escape($key) + '\s*=') ("example documents required key: {0}" -f $key)
    }
    Assert-Match $example '(?m)^storePassword=__REPLACE' 'example storePassword is a placeholder, not a secret'
    Assert-Match $example '(?m)^keyPassword=__REPLACE' 'example keyPassword is a placeholder, not a secret'
    Assert-NoMatch $example '(?i)BEGIN (RSA |EC |DSA |OPENSSH |)PRIVATE KEY' 'example contains no embedded private key material'
}

Assert-True (Test-Path -LiteralPath $androidGitignorePath) 'android/.gitignore exists'
if (Test-Path -LiteralPath $androidGitignorePath) {
    $gitignore = [System.IO.File]::ReadAllText($androidGitignorePath)
    Assert-Match $gitignore '(?m)^key\.properties\s*$' 'key.properties is gitignored'
    Assert-Match $gitignore '\*+/\*\.keystore|\*\.keystore' 'keystore files are gitignored'
    Assert-Match $gitignore '\*+/\*\.jks|\*\.jks' 'jks files are gitignored'
}

Write-Host ("Android release signing tests: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
