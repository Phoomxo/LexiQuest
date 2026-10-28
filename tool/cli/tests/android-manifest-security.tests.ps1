[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$manifestPath = Join-Path $repoRoot 'android\app\src\main\AndroidManifest.xml'
$source = Get-Content -LiteralPath $manifestPath -Raw

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
