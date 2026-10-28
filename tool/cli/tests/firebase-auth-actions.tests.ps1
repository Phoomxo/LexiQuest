#Requires -Version 5.1
<#
.SYNOPSIS
    Repository contract tests for Firebase Auth email actions and Android App Links.

.DESCRIPTION
    Verifies only checked-in deployment contracts. This script never contacts
    Firebase, deploys Hosting, prints certificate fingerprints, or sends email.
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
    Assert-True ($Text -match $Pattern) $Message
}

function Assert-NoMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    Assert-True ($Text -notmatch $Pattern) $Message
}

function Get-RequiredText {
    param([string]$Path)
    Assert-True (Test-Path -LiteralPath $Path) ('required file exists: ' + $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    return ([System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n") -replace "`r", "`n"
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$manifest = Get-RequiredText (Join-Path $repoRoot 'android\app\src\main\AndroidManifest.xml')
$gradle = Get-RequiredText (Join-Path $repoRoot 'android\app\build.gradle.kts')
$runbook = Get-RequiredText (Join-Path $repoRoot 'docs\runbooks\firebase-auth-actions.md')
$ci = Get-RequiredText (Join-Path $repoRoot '.github\workflows\ci.yml')
$productionRelease = Get-RequiredText (Join-Path $repoRoot '.github\workflows\production-release.yml')
$pubspec = Get-RequiredText (Join-Path $repoRoot 'pubspec.yaml')
$assetLinksValidator = Get-RequiredText (Join-Path $repoRoot 'tool\cli\validate-firebase-assetlinks.ps1')
$assetLinksValidatorTests = Get-RequiredText (Join-Path $repoRoot 'tool\cli\tests\firebase-assetlinks-validator.tests.ps1')

Assert-Match $gradle 'applicationId\s*=\s*"com\.lexiquest\.app"' 'Android application ID is com.lexiquest.app'
Assert-Match $manifest '<intent-filter\s+android:autoVerify="true">' 'Android action-link intent filter enables auto verification'
Assert-Match $manifest 'android:scheme="https"' 'Android action-link intent filter is HTTPS only'
Assert-Match $manifest 'android:host="vocab-learning-app-219ef\.web\.app"' 'Android action-link host is Firebase Hosting'
Assert-Match $manifest 'android:pathPrefix="/auth/action"' 'Android action-link path is /auth/action'

Assert-NoMatch $manifest '\.page\.link' 'Android manifest does not reference retired Dynamic Links'
Assert-NoMatch $pubspec '(?im)^\s*firebase_dynamic_links\s*:' 'Flutter dependencies exclude Firebase Dynamic Links'
Assert-Match $runbook 'Do not use the retired `\.page\.link`' 'runbook prohibits retired Dynamic Links'
Assert-Match $runbook 'ANDROID_RELEASE_CERT_SHA256' 'runbook requires the release certificate fingerprint variable'
Assert-Match $runbook '/\.well-known/assetlinks\.json' 'runbook verifies the published asset links document'
Assert-Match $runbook 'delegate_permission/common\.handle_all_urls' 'runbook specifies the Android App Links relation'
Assert-Match $runbook '"namespace"\s*:\s*"android_app"' 'runbook specifies the Android App Links namespace'
Assert-Match $runbook '"package_name"\s*:\s*"com\.lexiquest\.app"' 'runbook specifies the Android App Links package'
Assert-Match $runbook '"sha256_cert_fingerprints"' 'runbook specifies the Android App Links fingerprint array'
Assert-Match $runbook 'validate-firebase-assetlinks\.ps1' 'runbook uses the tracked asset links validator'
Assert-Match $assetLinksValidator 'Invoke-WebRequest' 'asset links validator fetches the published document read-only'
Assert-Match $assetLinksValidator 'ConvertFrom-Json' 'asset links validator parses the published JSON'
Assert-Match $assetLinksValidator '\$env:ANDROID_RELEASE_CERT_SHA256' 'asset links validator uses the protected expected fingerprint'
Assert-Match $assetLinksValidator 'sha256_cert_fingerprints' 'asset links validator checks certificate fingerprints'
Assert-Match $assetLinksValidator 'statements\.Count -ne 1' 'asset links validator rejects extra statements'
Assert-Match $assetLinksValidator 'relations\.Count -ne 1' 'asset links validator rejects extra relations'
Assert-Match $assetLinksValidator 'fingerprints\.Count -ne 1' 'asset links validator rejects extra fingerprints'
Assert-Match $assetLinksValidatorTests 'extra statement fails' 'asset links validator tests cover extra statements'
Assert-Match $assetLinksValidatorTests 'extra fingerprint fails' 'asset links validator tests cover extra fingerprints'
Assert-Match $runbook 'Authorized domains' 'runbook includes the Firebase Auth authorized-domain gate'
Assert-Match $runbook 'https://vocab-learning-app-219ef\.web\.app/auth/action' 'runbook records the custom action handler URL'
Assert-Match $runbook 'password reset template' 'runbook includes the password-reset email-template gate'
Assert-Match $runbook 'verification template' 'runbook includes the verification email-template gate'
Assert-Match $runbook 'pm get-app-links com\.lexiquest\.app' 'runbook includes Android App Links verification'
Assert-Match $runbook 'physical test device' 'runbook requires physical-device email-action testing'

Assert-Match $ci 'firebase-auth-actions\.tests\.ps1' 'CI runs Firebase Auth action-link repository contracts'
Assert-Match $ci 'flutter test test/account/account_models_test\.dart test/navigation/account_link_coordinator_test\.dart' 'CI runs focused account action-link tests'
Assert-Match $ci 'flutter test integration_test/account_lifecycle_test\.dart -d linux --timeout 2m' 'CI runs the bounded Linux account recovery integration test'
Assert-Match $productionRelease 'firebase-auth-actions\.tests\.ps1' 'production release runs Firebase Auth action-link contracts'
Assert-Match $productionRelease 'firebase-assetlinks-validator\.tests\.ps1' 'production release runs asset links validator fixtures'
Assert-Match $productionRelease 'flutter test test/account/account_models_test\.dart test/navigation/account_link_coordinator_test\.dart' 'production release runs focused account action-link tests'
Assert-Match $productionRelease 'vars\.ANDROID_RELEASE_CERT_SHA256' 'production release reads the release certificate fingerprint from a protected variable'
Assert-Match $productionRelease 'test -n "\$\{ANDROID_RELEASE_CERT_SHA256\}"' 'production release requires a release certificate fingerprint'
Assert-Match $productionRelease '\^\[A-Fa-f0-9\]\{2\}\(:\[A-Fa-f0-9\]\{2\}\)\{31\}\$' 'production release validates the SHA-256 fingerprint format'
Assert-NoMatch $productionRelease 'firebase\s+deploy' 'production release does not deploy Hosting'

$verifyScript = Get-RequiredText (Join-Path $repoRoot 'tool\cli\verify.ps1')
Assert-Match $verifyScript 'firebase-assetlinks-validator\.tests\.ps1' 'local verifier runs asset links validator fixtures'
Assert-Match $verifyScript 'ProcessStartInfo' 'local verifier starts the Windows integration test as a child process'
Assert-Match $verifyScript 'WaitForExit\(120000\)' 'local verifier applies a 120-second wall-clock process limit'
Assert-Match $verifyScript 'Stop-Process -Id \$process\.Id -Force' 'local verifier terminates the Windows integration child at deadline'
Assert-Match $verifyScript "'integration_test/account_lifecycle_test\.dart'" 'local verifier runs the account recovery integration file'
Assert-Match $verifyScript "'windows'" 'local verifier selects the Windows desktop device'
Assert-Match $verifyScript "'--timeout'" 'local verifier retains the per-test timeout flag'
Assert-Match $verifyScript "'2m'" 'local verifier retains the per-test timeout value'
Assert-Match $ci 'timeout --kill-after=5s 120s flutter test integration_test/account_lifecycle_test\.dart -d linux --timeout 2m' 'CI applies a Linux wall-clock bound around the account recovery integration test'

$contractsIndex = $productionRelease.IndexOf('firebase-auth-actions.tests.ps1')
$buildIndex = $productionRelease.IndexOf('flutter build appbundle --release')
Assert-True (
    $contractsIndex -ge 0 -and $buildIndex -ge 0 -and $contractsIndex -lt $buildIndex
) 'production release runs action-link contracts before building'

Write-Host ("Firebase Auth action contracts: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
