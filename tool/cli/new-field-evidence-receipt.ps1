#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet(
        'app-check',
        'billing',
        'asset-links',
        'kill-switch',
        'feedback-channel',
        'support-channel',
        'research-protocol',
        'beta-operations',
        'rollback-drill',
        'owner-approval'
    )]
    [string]$Kind,

    [Parameter(Mandatory)]
    [ValidateSet(
        'provider-console-export',
        'beta-ops-export',
        'owner-attestation'
    )]
    [string]$Origin,

    [Parameter(Mandatory)]
    [string]$SigningCertificateThumbprint,

    [Parameter(Mandatory)]
    [string]$SourceExportPath,

    [string]$ReleaseManifestPath = 'build/field-release/release-manifest.json',
    [string]$PrivateEvidenceDirectory = 'field/evidence/private-evidence',
    [string]$TrustedEvidencePublicKeyPath =
        'tool/cli/trusted-field-evidence-public-key.xml'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'lib\field-release-evidence.ps1')

function Resolve-RepositoryPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

function ConvertTo-StrictUtcText {
    param([Parameter(Mandatory)][DateTimeOffset]$Value)

    return $Value.UtcDateTime.ToString(
        "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",
        [Globalization.CultureInfo]::InvariantCulture
    )
}

$allowedOriginByKind = @{
    'app-check' = 'provider-console-export'
    'billing' = 'provider-console-export'
    'asset-links' = 'provider-console-export'
    'kill-switch' = 'beta-ops-export'
    'feedback-channel' = 'beta-ops-export'
    'support-channel' = 'beta-ops-export'
    'research-protocol' = 'beta-ops-export'
    'beta-operations' = 'beta-ops-export'
    'rollback-drill' = 'beta-ops-export'
    'owner-approval' = 'owner-attestation'
}
if ([string]$allowedOriginByKind[$Kind] -cne $Origin) {
    throw "Receipt kind $Kind requires origin $($allowedOriginByKind[$Kind])."
}

$manifestFile = Resolve-RepositoryPath $ReleaseManifestPath
$sourceExportFile = Resolve-RepositoryPath $SourceExportPath
$privateEvidencePath = Resolve-RepositoryPath $PrivateEvidenceDirectory
$trustedPublicKeyFile = Resolve-RepositoryPath $TrustedEvidencePublicKeyPath
foreach ($requiredFile in @(
    $manifestFile,
    $sourceExportFile,
    $trustedPublicKeyFile
)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required evidence-signing input is missing: $requiredFile"
    }
}
$manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding utf8 |
    ConvertFrom-Json
$allowedEvidenceRoot = [IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'field/evidence')
).TrimEnd('\', '/')
if (-not $sourceExportFile.StartsWith(
    $allowedEvidenceRoot + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw 'SourceExportPath must stay inside an ignored field/evidence input.'
}
$sourceEnvelope = Get-Content -LiteralPath $sourceExportFile -Raw `
    -Encoding utf8 | ConvertFrom-Json
$allowedCaptureMethodByOrigin = @{
    'provider-console-export' = 'provider-console-export'
    'beta-ops-export' = 'release-instrumentation-export'
    'owner-attestation' = 'owner-attestation'
}
if (
    $sourceEnvelope.schemaVersion -ne 1 -or
    [string]$sourceEnvelope.kind -cne $Kind -or
    [string]$sourceEnvelope.origin -cne $Origin -or
    [string]$sourceEnvelope.captureMethod -cne
        [string]$allowedCaptureMethodByOrigin[$Origin] -or
    $sourceEnvelope.hostFake -isnot [bool] -or
    $sourceEnvelope.hostFake -ne $false -or
    [string]$sourceEnvelope.sourceCommit -cne [string]$manifest.sourceCommit -or
    [string]$sourceEnvelope.apkSha256 -cne
        [string]$manifest.artifact.apkSha256 -or
    $null -eq $sourceEnvelope.PSObject.Properties['payload']
) {
    throw 'The source envelope is not an authentic current-release export.'
}
$observedText = [string]$sourceEnvelope.observedAtUtc
if ($null -eq (ConvertFrom-LexiQuestStrictUtcTimestamp $observedText)) {
    throw 'The source observedAtUtc must be a strict RFC3339 UTC timestamp.'
}
$payload = $sourceEnvelope.payload
$sourceExportSha256 = (
    Get-FileHash -LiteralPath $sourceExportFile -Algorithm SHA256
).Hash
$sourceBlobDirectory = Join-Path $privateEvidencePath 'sources'
New-Item -ItemType Directory -Path $sourceBlobDirectory -Force | Out-Null
$sourceBlobPath = Join-Path $sourceBlobDirectory `
    "$sourceExportSha256.source"
if (Test-Path -LiteralPath $sourceBlobPath) {
    if (
        (Get-FileHash -LiteralPath $sourceBlobPath -Algorithm SHA256).Hash `
            -cne $sourceExportSha256
    ) {
        throw 'Existing source-export blob has an unexpected digest.'
    }
} else {
    Copy-Item -LiteralPath $sourceExportFile -Destination $sourceBlobPath
}
$trustedRsa = Get-LexiQuestTrustedEvidenceRsa $trustedPublicKeyFile
if ($null -eq $trustedRsa) {
    throw 'The trusted evidence public key must contain an RSA-3072+ public key.'
}
$thumbprint = $SigningCertificateThumbprint.Replace(' ', '')
$certificate = Get-Item -LiteralPath ('Cert:\CurrentUser\My\' + $thumbprint) `
    -ErrorAction SilentlyContinue
if ($null -eq $certificate -or -not $certificate.HasPrivateKey) {
    $trustedRsa.Dispose()
    throw 'The approved evidence-signing certificate is unavailable.'
}
$nowUtc = [DateTime]::UtcNow
if (
    $certificate.NotBefore.ToUniversalTime() -gt $nowUtc -or
    $certificate.NotAfter.ToUniversalTime() -lt $nowUtc
) {
    $trustedRsa.Dispose()
    throw 'The evidence-signing certificate is outside its validity window.'
}
$signingRsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey(
    $certificate
)
if ($null -eq $signingRsa -or $signingRsa.KeySize -lt 3072) {
    $trustedRsa.Dispose()
    if ($null -ne $signingRsa) {
        $signingRsa.Dispose()
    }
    throw 'The evidence-signing certificate must use RSA-3072 or stronger.'
}
if (
    (Get-LexiQuestEvidencePublicKeyId $signingRsa) -cne
        (Get-LexiQuestEvidencePublicKeyId $trustedRsa)
) {
    $trustedRsa.Dispose()
    $signingRsa.Dispose()
    throw 'The evidence signer does not match the tracked trusted public key.'
}
$trustedRsa.Dispose()

$receiptId = [Guid]::NewGuid().ToString('D')
$receipt = [ordered]@{
    schemaVersion = 2
    kind = $Kind
    receiptId = $receiptId
    origin = $Origin
    observedAtUtc = $observedText
    sourceCommit = [string]$manifest.sourceCommit
    apkSha256 = [string]$manifest.artifact.apkSha256
    sourceExportSha256 = $sourceExportSha256
    payload = $payload
}
$receipt.signingKeyId = Get-LexiQuestEvidencePublicKeyId $signingRsa
$receipt.signatureAlgorithm = 'rsa-sha256-pkcs1'
$receipt.signatureBase64 = [Convert]::ToBase64String(
    $signingRsa.SignData(
        (ConvertTo-LexiQuestEvidenceSigningBytes ([pscustomobject]$receipt)),
        [Security.Cryptography.HashAlgorithmName]::SHA256,
        [Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
)
$signingRsa.Dispose()

$json = $receipt | ConvertTo-Json -Depth 20 -Compress
$bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $digest = (
        [BitConverter]::ToString($sha.ComputeHash($bytes))
    ).Replace('-', '')
}
finally {
    $sha.Dispose()
}
$blobDirectory = Join-Path $privateEvidencePath 'blobs'
New-Item -ItemType Directory -Path $blobDirectory -Force | Out-Null
$blobPath = Join-Path $blobDirectory "$digest.receipt"
if (Test-Path -LiteralPath $blobPath) {
    throw "Evidence receipt already exists: $blobPath"
}
[IO.File]::WriteAllBytes($blobPath, $bytes)
Write-Output "private-evidence:v1:$Kind`:$receiptId`:sha256:$digest"
