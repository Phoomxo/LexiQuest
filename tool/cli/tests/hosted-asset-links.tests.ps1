$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$source=Join-Path $root 'tool/cli/verify-hosted-asset-links.ps1'
$certificate='A' * 64
function Statement($relation, $fingerprint=$certificate) {
    return @{relation=$relation; target=@{namespace='android_app';package_name='com.lexiquest.app';sha256_cert_fingerprints=@($fingerprint)}}
}
function Invoke-WebRequest {
    param($Uri, [switch]$UseBasicParsing, $TimeoutSec, $MaximumRedirection)
    if ($Uri -notmatch '^https://vocab-learning-app-219ef\.(web\.app|firebaseapp\.com)/.well-known/assetlinks.json$') {throw 'Unexpected fixture URI'}
    return @{StatusCode=200;Content=$global:assetLinksFixtureBody;Headers=@{'Content-Type'='application/json'}}
}
$failures=@();$passed=0
foreach($case in @(
    @{name='valid'; statements=@((Statement @('delegate_permission/common.handle_all_urls'))); pass=$true},
    @{name='missing'; statements=@((Statement @())); pass=$false},
    @{name='wrong'; statements=@((Statement @('delegate_permission/common.get_login_creds'))); pass=$false},
    @{name='certificate'; statements=@((Statement @('delegate_permission/common.handle_all_urls') ('B'*64))); pass=$false},
    @{name='split'; statements=@((Statement @()), (Statement @('delegate_permission/common.handle_all_urls') ('B'*64))); pass=$false},
    @{name='later-valid'; statements=@((Statement @() ('B'*64)), (Statement @('delegate_permission/common.handle_all_urls'))); pass=$true}
)) {
    $fixture=Join-Path $root ('build/assetlinks-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path "$fixture/tool/cli" -Force | Out-Null
    Copy-Item $source "$fixture/tool/cli/verify-hosted-asset-links.ps1"
    @{artifact=@{signingCertificateSha256=$certificate;apkSha256=('C'*64)}} | ConvertTo-Json | Set-Content "$fixture/manifest.json"
    $global:assetLinksFixtureBody=ConvertTo-Json -InputObject @($case.statements) -Depth 8
    $ok=$true
    try { & "$fixture/tool/cli/verify-hosted-asset-links.ps1" -ReleaseManifestPath "$fixture/manifest.json" | Out-Null } catch {$ok=$false; Write-Output ($case.name + ': ' + $_.Exception.Message)}
    $hasEvidence=Test-Path "$fixture/field/evidence/cloud/firebase-asset-links.json"
    if ($ok -ne $case.pass -or $hasEvidence -ne $case.pass) {$failures += $case.name} else {$passed++}
}
if($failures.Count){throw ('Asset-links cases: '+($failures -join ', '))}
Write-Output "PASS: $passed injected HTTP cases; no network"
