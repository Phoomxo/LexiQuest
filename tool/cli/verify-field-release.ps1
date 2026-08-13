#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$EvidencePath = 'field/evidence/release-evidence.json',
    [string]$ParticipantPackagePath = 'build/field-release'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'lib\field-release-evidence.ps1')

function Resolve-RepositoryPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

$resolvedEvidence = Resolve-RepositoryPath $EvidencePath
$resolvedPackage = Resolve-RepositoryPath $ParticipantPackagePath
if (-not (Test-Path -LiteralPath $resolvedEvidence -PathType Leaf)) {
    throw (
        "Field evidence is missing: $resolvedEvidence. " +
        'Collect mid-tier and high-tier real Android devices; do not replace ' +
        'missing evidence with simulated results.'
    )
}

$evidence = Get-Content -LiteralPath $resolvedEvidence -Raw -Encoding utf8 |
    ConvertFrom-Json
$releaseManifestPath = Join-Path $resolvedPackage 'release-manifest.json'
if (-not (Test-Path -LiteralPath $releaseManifestPath -PathType Leaf)) {
    throw "Packaged release manifest is missing: $releaseManifestPath"
}
$releaseManifest =
    Get-Content -LiteralPath $releaseManifestPath -Raw -Encoding utf8 |
        ConvertFrom-Json
foreach ($field in @(
    'apkPath',
    'apkSha256',
    'signingCertificateSha256',
    'packageName',
    'versionName',
    'versionCode',
    'buildId',
    'modelSha256'
)) {
    $evidenceValue = [string]$evidence.artifact.$field
    $manifestValue = [string]$releaseManifest.artifact.$field
    if ($evidenceValue -ne $manifestValue) {
        throw "Evidence artifact.$field does not match release-manifest.json."
    }
}
$apkPath = [System.IO.Path]::GetFullPath(
    (Join-Path $resolvedPackage ([string]$releaseManifest.artifact.apkPath))
)
if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
    throw "Release APK is missing: $apkPath"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File `
    (Join-Path $PSScriptRoot 'verify-field-package.ps1') `
    -PackagePath $resolvedPackage
if ([int]$LASTEXITCODE -ne 0) {
    throw 'The immutable field package failed independent verification.'
}
$actualApkSha256 = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash
$actualCertificateSha256 =
    [string]$releaseManifest.artifact.signingCertificateSha256

$evidenceErrors = Test-LexiQuestFieldReleaseEvidence `
    -Evidence $evidence `
    -ActualApkSha256 $actualApkSha256 `
    -ActualCertificateSha256 $actualCertificateSha256 `
    -ParticipantPackagePath $resolvedPackage
if ($evidenceErrors.Count -gt 0) {
    $message = "Field release evidence is incomplete:`n - " +
        ($evidenceErrors -join "`n - ")
    throw $message
}

& powershell -NoProfile -ExecutionPolicy Bypass -File `
    (Join-Path $PSScriptRoot 'verify-product-completion.ps1')
if ([int]$LASTEXITCODE -ne 0) {
    throw 'P7 product completion gate failed.'
}

Write-Host 'LexiQuest P8 field release gate: PASS' -ForegroundColor Green
exit 0
