[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$manifestPath = Join-Path $repoRoot 'android\app\src\main\AndroidManifest.xml'
$source = Get-Content -LiteralPath $manifestPath -Raw
$assetLinksPath = Join-Path $repoRoot `
    'hosting\public\.well-known\assetlinks.json'
$firebasePath = Join-Path $repoRoot 'firebase.json'
$hostedVerifierPath = Join-Path $repoRoot `
    'tool\cli\verify-hosted-asset-links.ps1'

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
    'Android App Links statement is present' =
        (Test-Path -LiteralPath $assetLinksPath)
    'Firebase Hosting configuration is present' =
        (Test-Path -LiteralPath $firebasePath)
    'Hosted Asset Links verifier is present' =
        (Test-Path -LiteralPath $hostedVerifierPath)
}
if (Test-Path -LiteralPath $hostedVerifierPath) {
    $hostedVerifier = Get-Content -LiteralPath $hostedVerifierPath -Raw
    $checks['Hosted verifier checks both Firebase domains'] =
        (
            $hostedVerifier -match 'web\.app/\.well-known/assetlinks\.json' -and
            $hostedVerifier -match (
                'firebaseapp\.com/\.well-known/assetlinks\.json'
            )
        )
    $checks['Hosted verifier reconciles the release certificate'] =
        $hostedVerifier -match 'signingCertificateSha256'
}

if (Test-Path -LiteralPath $assetLinksPath) {
    $assetLinks = Get-Content -LiteralPath $assetLinksPath -Raw
    $checks['Asset links target the production package'] =
        $assetLinks -match '"package_name":\s*"com\.lexiquest\.app"'
    $checks['Asset links pin the release signing certificate'] =
        $assetLinks -match (
            'E1:B0:0E:17:89:6B:FB:73:FE:0D:C4:24:29:76:8B:96:' +
            '64:65:21:3D:49:A8:A5:16:5D:E0:66:88:CC:8F:DC:1F'
        )
}
if (Test-Path -LiteralPath $firebasePath) {
    $firebase = Get-Content -LiteralPath $firebasePath -Raw
    $checks['Hosting targets the production App Link site'] =
        $firebase -match '"site":\s*"vocab-learning-app-219ef"'
    $checks['Hosting applies explicit asset links headers'] =
        $firebase -match '/\.well-known/assetlinks\.json'
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
