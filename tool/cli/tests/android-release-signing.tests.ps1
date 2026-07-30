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
$proguardPath = Join-Path $repoRoot 'android\app\proguard-rules.pro'
$initializerPath = Join-Path $repoRoot `
    'tool\cli\initialize-release-signing.ps1'
$firebaseShaPath = Join-Path $repoRoot `
    'tool\cli\configure-firebase-release-sha.cjs'
$appCheckPath = Join-Path $repoRoot `
    'tool\cli\configure-firebase-app-check.cjs'

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
    Assert-Match $gitignore '\*+/\*\.p12|\*\.p12' `
        'PKCS12 release keys are gitignored'
}

Assert-True (Test-Path -LiteralPath $proguardPath) `
    'release ProGuard rules exist'
if (Test-Path -LiteralPath $proguardPath) {
    $proguard = [System.IO.File]::ReadAllText($proguardPath)
    Assert-Match $gradle 'proguardFiles' `
        'release build applies project ProGuard rules'
    Assert-Match $proguard `
        'androidx\.work\.impl\.WorkDatabase_Impl[\s\S]*<init>\(\)' `
        'R8 retains the WorkManager Room constructor used by reflection'
}

Assert-True (Test-Path -LiteralPath $initializerPath) `
    'release signing initializer exists'
if (Test-Path -LiteralPath $initializerPath) {
    $initializer = [System.IO.File]::ReadAllText($initializerPath)
    Assert-Match $initializer 'RandomNumberGenerator' `
        'initializer uses a cryptographic password generator'
    Assert-Match $initializer 'PKCS12' `
        'initializer creates a standard release keystore'
    Assert-Match $initializer '4096' `
        'initializer creates a 4096-bit RSA key'
    Assert-Match $initializer 'ConvertFrom-SecureString' `
        'initializer creates a current-user protected recovery secret'
    Assert-Match $initializer 'icacls' `
        'initializer restricts local signing material ACLs'
    Assert-Match $initializer 'Get-ChildItem -LiteralPath \$signingDirectory' `
        'initializer enumerates every signing child artifact'
    Assert-Match $initializer '\$artifact\.FullName[\s\S]*\(F\)' `
        'initializer preserves owner access to every signing child artifact'
    Assert-Match $initializer 'Refusing to overwrite' `
        'initializer never overwrites a permanent release key'
    Assert-NoMatch $initializer '(?i)storePassword\s*=\s*["'']?[A-Za-z0-9]{8,}' `
        'initializer contains no hard-coded release password'
}

Assert-True (Test-Path -LiteralPath $firebaseShaPath) `
    'Firebase release SHA configurator exists'
if (Test-Path -LiteralPath $firebaseShaPath) {
    $firebaseSha = [System.IO.File]::ReadAllText($firebaseShaPath)
    Assert-Match $firebaseSha 'listAppAndroidSha' `
        'Firebase SHA registration checks existing state first'
    Assert-Match $firebaseSha 'createAppAndroidSha' `
        'Firebase SHA registration uses the authenticated management API'
    Assert-Match $firebaseSha 'signingCertificateSha256' `
        'Firebase SHA registration reads the packaged certificate'
    Assert-NoMatch $firebaseSha '(?i)(access_token|refresh_token|authorization)' `
        'Firebase SHA evidence never handles or writes authentication tokens'
}

Assert-True (Test-Path -LiteralPath $appCheckPath) `
    'Firebase App Check configurator exists'
if (Test-Path -LiteralPath $appCheckPath) {
    $appCheck = [System.IO.File]::ReadAllText($appCheckPath)
    Assert-Match $appCheck 'allowUnrecognizedVersion:\s*true' `
        'direct APK distribution permits off-Play recognition state'
    Assert-Match $appCheck 'MEETS_DEVICE_INTEGRITY' `
        'App Check requires standard device integrity'
    Assert-Match $appCheck 'requireLicensed:\s*false' `
        'direct APK distribution does not require Play licensing'
    Assert-Match $appCheck 'NOT_ENABLED_UNTIL_PHYSICAL_DEVICE_ACCEPTANCE' `
        'App Check enforcement remains gated on physical acceptance'
    Assert-NoMatch $appCheck 'enforcement:\s*["'']ENFORCED' `
        'automation cannot prematurely claim App Check enforcement'
}

Write-Host ("Android release signing tests: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
