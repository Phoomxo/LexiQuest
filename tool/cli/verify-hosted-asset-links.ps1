#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ReleaseManifestPath =
        'build/field-release/release-manifest.json'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$manifestPath = if (
    [System.IO.Path]::IsPathRooted($ReleaseManifestPath)
) {
    [System.IO.Path]::GetFullPath($ReleaseManifestPath)
} else {
    [System.IO.Path]::GetFullPath(
        (Join-Path $repoRoot $ReleaseManifestPath)
    )
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Release manifest is missing: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 |
    ConvertFrom-Json
$certificate = ([string]$manifest.artifact.signingCertificateSha256).
    Replace(':', '').
    ToUpperInvariant()
if ($certificate -notmatch '^[A-F0-9]{64}$') {
    throw 'Release signing certificate SHA-256 is invalid.'
}

$urls = @(
    'https://vocab-learning-app-219ef.web.app/.well-known/assetlinks.json',
    'https://vocab-learning-app-219ef.firebaseapp.com/.well-known/assetlinks.json'
)
$results = @()
foreach ($url in $urls) {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
    if ([int]$response.StatusCode -ne 200) {
        throw "Asset Links returned HTTP $($response.StatusCode): $url"
    }
    $statement = @($response.Content | ConvertFrom-Json)
    $target = @(
        $statement |
            Where-Object {
                $_.target.namespace -eq 'android_app' -and
                $_.target.package_name -eq 'com.lexiquest.app'
            }
    ) | Select-Object -First 1
    if ($null -eq $target) {
        throw "Production package is absent from Asset Links: $url"
    }
    $fingerprints = @(
        $target.target.sha256_cert_fingerprints |
            ForEach-Object {
                ([string]$_).Replace(':', '').ToUpperInvariant()
            }
    )
    if ($certificate -notin $fingerprints) {
        throw "Release certificate is absent from Asset Links: $url"
    }
    $results += [ordered]@{
        url = $url
        status = [int]$response.StatusCode
        contentType = [string]$response.Headers['Content-Type']
        packageName = 'com.lexiquest.app'
        certificateSha256 = $certificate
    }
}

$evidenceDirectory = Join-Path $repoRoot 'field\evidence\cloud'
New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
$evidence = [ordered]@{
    schemaVersion = 1
    recordedAtUtc = [DateTime]::UtcNow.ToString('o')
    releaseApkSha256 = [string]$manifest.artifact.apkSha256
    results = $results
}
[System.IO.File]::WriteAllText(
    (Join-Path $evidenceDirectory 'firebase-asset-links.json'),
    (($evidence | ConvertTo-Json -Depth 8) + [Environment]::NewLine),
    [System.Text.UTF8Encoding]::new($false)
)
Write-Host 'Hosted Android Asset Links verified.' -ForegroundColor Green
