[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$manifestPath = Join-Path $repoRoot 'android\app\src\main\AndroidManifest.xml'
$gradlePath = Join-Path $repoRoot 'android\app\build.gradle.kts'
$servicesPath = Join-Path $repoRoot 'android\app\google-services.json'
$firebaseOptionsPath = Join-Path $repoRoot 'lib\firebase_options.dart'
$mainActivityPath = Join-Path $repoRoot 'android\app\src\main\kotlin\com\lexiquest\app\MainActivity.kt'
$legacyMainActivityPath = Join-Path $repoRoot 'android\app\src\main\kotlin\com\example\vocab_learning_app\MainActivity.kt'
$source = Get-Content -LiteralPath $manifestPath -Raw
$gradle = Get-Content -LiteralPath $gradlePath -Raw
$services = Get-Content -LiteralPath $servicesPath -Raw | ConvertFrom-Json
$firebaseOptions = Get-Content -LiteralPath $firebaseOptionsPath -Raw
$productionClient = @(
    $services.client |
        Where-Object {
            $_.client_info.android_client_info.package_name -eq 'com.lexiquest.app'
        }
) | Select-Object -First 1
$mainActivity = if (Test-Path -LiteralPath $mainActivityPath) {
    Get-Content -LiteralPath $mainActivityPath -Raw
} else {
    ''
}

$checks = [ordered]@{
    'Release manifest explicitly blocks cleartext traffic' =
        $source -match 'android:usesCleartextTraffic="false"'
    'Application backup is disabled' =
        $source -match 'android:allowBackup="false"'
    'Legacy broad external-storage permission is absent' =
        $source -notmatch 'android\.permission\.READ_EXTERNAL_STORAGE'
    'Camera hardware is optional' =
        $source -match 'android:name="android\.hardware\.camera"\s+android:required="false"'
    'Camera autofocus hardware is optional' =
        $source -match 'android:name="android\.hardware\.camera\.autofocus"\s+android:required="false"'
    'Microphone hardware is optional' =
        $source -match 'android:name="android\.hardware\.microphone"\s+android:required="false"'
    'Android namespace uses the production package' =
        $gradle -match 'namespace\s*=\s*"com\.lexiquest\.app"'
    'Android application id uses the production package' =
        $gradle -match 'applicationId\s*=\s*"com\.lexiquest\.app"'
    'Firebase config contains the production Android client' =
        $null -ne $productionClient
    'Firebase config uses the registered production app id' =
        $productionClient.client_info.mobilesdk_app_id -eq
            '1:145034183638:android:2c492244dd68e77dbe5a77'
    'Flutter Firebase options use the registered production app id' =
        $firebaseOptions -match
            "static const FirebaseOptions android[\s\S]*?appId:\s*'1:145034183638:android:2c492244dd68e77dbe5a77'"
    'MainActivity is stored under the production package path' =
        (Test-Path -LiteralPath $mainActivityPath)
    'MainActivity declares the production package' =
        $mainActivity -match '(?m)^package com\.lexiquest\.app\s*$'
    'Legacy MainActivity package path is absent' =
        -not (Test-Path -LiteralPath $legacyMainActivityPath)
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value })
foreach ($check in $checks.GetEnumerator()) {
    $state = if ($check.Value) { 'PASS' } else { 'FAIL' }
    Write-Host "$state - $($check.Key)"
}
Write-Host "Android manifest security tests: $($checks.Count - $failed.Count) passed, $($failed.Count) failed"
if ($failed.Count -gt 0) {
    exit 1
}
Write-Host 'PASS'
