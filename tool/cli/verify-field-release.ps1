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

function Find-ApkSigner {
    $command = Get-Command apksigner -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }
    $sdkCandidates = @(
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($sdk in $sdkCandidates) {
        $buildTools = Join-Path $sdk 'build-tools'
        if (-not (Test-Path -LiteralPath $buildTools -PathType Container)) {
            continue
        }
        $candidate = Get-ChildItem -LiteralPath $buildTools -Directory |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -First 1
        if ($null -ne $candidate) {
            return $candidate
        }
    }
    throw 'apksigner is required to verify the release certificate.'
}

$resolvedEvidence = Resolve-RepositoryPath $EvidencePath
$resolvedPackage = Resolve-RepositoryPath $ParticipantPackagePath
if (-not (Test-Path -LiteralPath $resolvedEvidence -PathType Leaf)) {
    throw (
        'Field evidence is missing: {0}. Collect three real Android devices; ' +
        'do not replace missing evidence with simulated results.' -f
        $resolvedEvidence
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
$apkPath = Resolve-RepositoryPath ([string]$evidence.artifact.apkPath)
if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
    throw "Release APK is missing: $apkPath"
}

$actualApkSha256 = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash
$apkSigner = Find-ApkSigner
$signatureOutput = & $apkSigner verify --verbose --print-certs $apkPath 2>&1
if ([int]$LASTEXITCODE -ne 0) {
    throw "apksigner rejected the release APK: $signatureOutput"
}
$certificateMatch = [regex]::Match(
    ($signatureOutput -join "`n"),
    'Signer #1 certificate SHA-256 digest:\s*([A-Fa-f0-9:]{64,95})'
)
if (-not $certificateMatch.Success) {
    throw 'apksigner did not report a SHA-256 signing certificate digest.'
}
$actualCertificateSha256 = $certificateMatch.Groups[1].Value

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

& powershell -NoProfile -ExecutionPolicy Bypass -File `
    (Join-Path $PSScriptRoot 'verify-apk-model-runtime.ps1') `
    -ApkPath $apkPath
if ([int]$LASTEXITCODE -ne 0) {
    throw 'Release APK model runtime integrity failed.'
}

Write-Host 'LexiQuest P8 field release gate: PASS' -ForegroundColor Green
exit 0
