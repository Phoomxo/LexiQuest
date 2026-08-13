#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$DeviceEvidencePath,

    [Parameter(Mandatory)]
    [string]$InstrumentedResultPath,

    [Parameter(Mandatory)]
    [ValidateSet('Journey', 'CpuBenchmark', 'GpuBenchmark', 'Endurance')]
    [string]$ResultType,

    [string]$JourneyName = '',

    [Parameter(Mandatory)]
    [string]$SigningCertificateThumbprint,

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

$deviceFile = Resolve-RepositoryPath $DeviceEvidencePath
$instrumentedResultFile = Resolve-RepositoryPath $InstrumentedResultPath
$manifestFile = Resolve-RepositoryPath $ReleaseManifestPath
$privateEvidencePath = Resolve-RepositoryPath $PrivateEvidenceDirectory
$trustedPublicKeyFile = Resolve-RepositoryPath $TrustedEvidencePublicKeyPath
foreach ($requiredFile in @(
    $deviceFile,
    $instrumentedResultFile,
    $manifestFile,
    $trustedPublicKeyFile
)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required device-evidence input is missing: $requiredFile"
    }
}
$device = Get-Content -LiteralPath $deviceFile -Raw -Encoding utf8 |
    ConvertFrom-Json
$manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding utf8 |
    ConvertFrom-Json
$allowedEvidenceRoot = [IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'field/evidence')
).TrimEnd('\', '/')
if (-not $instrumentedResultFile.StartsWith(
    $allowedEvidenceRoot + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw 'InstrumentedResultPath must stay inside ignored field/evidence.'
}
$sourceEnvelope = Get-Content -LiteralPath $instrumentedResultFile -Raw `
    -Encoding utf8 | ConvertFrom-Json
if (
    $device.physical -ne $true -or
    [string]$device.collector.origin -cne 'physical-android-collector' -or
    [string]$device.release.sourceCommit -cne [string]$manifest.sourceCommit -or
    [string]$device.release.manifestGeneratedAtUtc -cne
        [string]$manifest.generatedAtUtc -or
    [string]$device.release.apkSha256 -cne
        [string]$manifest.artifact.apkSha256 -or
    [string]$device.release.signingCertificateSha256 -cne
        [string]$manifest.artifact.signingCertificateSha256 -or
    [string]$device.release.packageName -cne
        [string]$manifest.artifact.packageName -or
    [string]$device.release.versionName -cne
        [string]$manifest.artifact.versionName -or
    [string]$device.release.buildId -cne
        [string]$manifest.artifact.buildId -or
    [string]$device.release.versionCode -cne
        [string]$manifest.artifact.versionCode -or
    [string]$device.release.modelSha256 -cne
        [string]$manifest.artifact.modelSha256 -or
    [string]$device.collector.verifiedApkSha256 -cne
        [string]$manifest.artifact.apkSha256
) {
    throw 'The device record is not bound to the current release manifest.'
}

$collectorPayload = [pscustomobject][ordered]@{
    evidenceId = $device.evidenceId
    tier = $device.tier
    pseudonymousDeviceId = $device.pseudonymousDeviceId
    recordedAtUtc = $device.recordedAtUtc
    device = $device.device
    release = $device.release
    collector = [pscustomobject][ordered]@{
        schemaVersion = $device.collector.schemaVersion
        origin = $device.collector.origin
        collectorScriptSha256 = $device.collector.collectorScriptSha256
        connectedDeviceCount = $device.collector.connectedDeviceCount
        roKernelQemu = $device.collector.roKernelQemu
        roBootQemu = $device.collector.roBootQemu
        serialKind = $device.collector.serialKind
        buildType = $device.collector.buildType
        debuggable = $device.collector.debuggable
        secure = $device.collector.secure
        fingerprint = $device.collector.fingerprint
        brand = $device.collector.brand
        deviceName = $device.collector.deviceName
        hardware = $device.collector.hardware
        verifiedApkSha256 = $device.collector.verifiedApkSha256
    }
}
if (-not (Test-LexiQuestPrivateEvidenceReference `
    -Value $device.collector.evidenceRef `
    -ExpectedKind 'device-attestation' `
    -PrivateEvidenceDirectory $privateEvidencePath `
    -TrustedEvidencePublicKeyPath $trustedPublicKeyFile `
    -ExpectedSourceCommit ([string]$manifest.sourceCommit) `
    -ExpectedApkSha256 ([string]$manifest.artifact.apkSha256) `
    -RequireSourceExport `
    -AllowedOrigins @('physical-android-collector') `
    -MaximumAge ([TimeSpan]::FromDays(30)) `
    -ExpectedPayload $collectorPayload
)) {
    throw 'The collector receipt, device, or release binding is invalid.'
}

$kind = switch ($ResultType) {
    'Journey' { 'device-journey' }
    'CpuBenchmark' { 'device-benchmark' }
    'GpuBenchmark' { 'device-benchmark' }
    'Endurance' { 'device-endurance' }
}
if (
    [int]$sourceEnvelope.schemaVersion -ne 1 -or
    [string]$sourceEnvelope.kind -cne $kind -or
    [string]$sourceEnvelope.origin -cne
        'physical-android-instrumentation' -or
    [string]$sourceEnvelope.captureMethod -cne
        'physical-android-instrumentation' -or
    $sourceEnvelope.hostFake -isnot [bool] -or
    $sourceEnvelope.hostFake -ne $false -or
    [string]$sourceEnvelope.sourceCommit -cne [string]$manifest.sourceCommit -or
    [string]$sourceEnvelope.apkSha256 -cne
        [string]$manifest.artifact.apkSha256 -or
    [string]$sourceEnvelope.collectorEvidenceRef -cne
        [string]$device.collector.evidenceRef -or
    [string]$sourceEnvelope.evidenceId -cne [string]$device.evidenceId -or
    [string]$sourceEnvelope.tier -cne [string]$device.tier -or
    [string]$sourceEnvelope.pseudonymousDeviceId -cne
        [string]$device.pseudonymousDeviceId -or
    $null -eq $sourceEnvelope.PSObject.Properties['payload'] -or
    $null -eq (ConvertFrom-LexiQuestStrictUtcTimestamp `
        $sourceEnvelope.observedAtUtc)
) {
    throw 'The instrumented result is not bound to this device and release.'
}

$sourceResult = $sourceEnvelope.payload
if (
    [string]$sourceResult.evidenceId -cne [string]$device.evidenceId -or
    [string]$sourceResult.tier -cne [string]$device.tier -or
    [string]$sourceResult.pseudonymousDeviceId -cne
        [string]$device.pseudonymousDeviceId
) {
    throw 'The instrumented result payload has a different device identity.'
}
$target = $null
switch ($ResultType) {
    'Journey' {
        if ($JourneyName -cnotin (Get-LexiQuestRequiredFieldJourneys)) {
            throw 'JourneyName is not a declared mandatory field journey.'
        }
        $target = $device.journeys.$JourneyName
        if (
            [string]$sourceResult.journey -cne $JourneyName -or
            [string]$sourceResult.status -cne 'pass'
        ) {
            throw 'Only an instrumented passing journey may be signed.'
        }
        $payload = [pscustomobject][ordered]@{
            evidenceId = $device.evidenceId
            tier = $device.tier
            pseudonymousDeviceId = $device.pseudonymousDeviceId
            journey = $JourneyName
            status = $sourceResult.status
        }
        $target.status = $sourceResult.status
    }
    'CpuBenchmark' {
        $target = $device.benchmarks.cpuXnnpack
        if (
            [string]$sourceResult.benchmark -cne 'cpuXnnpack' -or
            [string]$sourceResult.status -cne 'pass' -or
            [string]$sourceResult.delegate -cne 'xnnpack' -or
            [int]$sourceResult.iterations -lt 10 -or
            -not (Test-LexiQuestFiniteNumber `
                $sourceResult.medianLatencyMs) -or
            [double]$sourceResult.medianLatencyMs -le 0
        ) {
            throw 'Only a complete passing CPU/XNNPACK benchmark may be signed.'
        }
        $payload = [pscustomobject][ordered]@{
            evidenceId = $device.evidenceId
            tier = $device.tier
            pseudonymousDeviceId = $device.pseudonymousDeviceId
            benchmark = 'cpuXnnpack'
            status = $sourceResult.status
            delegate = $sourceResult.delegate
            iterations = $sourceResult.iterations
            medianLatencyMs = $sourceResult.medianLatencyMs
        }
        $target.status = $sourceResult.status
        $target.delegate = $sourceResult.delegate
        $target.iterations = $sourceResult.iterations
        $target.medianLatencyMs = $sourceResult.medianLatencyMs
    }
    'GpuBenchmark' {
        $target = $device.benchmarks.gpuDelegate
        if (
            [string]$sourceResult.benchmark -cne 'gpuDelegate' -or
            [string]$sourceResult.status -cnotin @('pass', 'notApplicable')
        ) {
            throw 'GPU evidence must be pass or explicitly notApplicable.'
        }
        $payload = [pscustomobject][ordered]@{
            evidenceId = $device.evidenceId
            tier = $device.tier
            pseudonymousDeviceId = $device.pseudonymousDeviceId
            benchmark = 'gpuDelegate'
            status = $sourceResult.status
            allowlisted = $sourceResult.allowlisted
            iterations = $sourceResult.iterations
            reason = $sourceResult.reason
        }
        $target.status = $sourceResult.status
        $target.allowlisted = $sourceResult.allowlisted
        $target.iterations = $sourceResult.iterations
        $target.reason = $sourceResult.reason
    }
    'Endurance' {
        $target = $device.endurance
        if (
            [string]$sourceResult.status -cne 'pass' -or
            -not (Test-LexiQuestFiniteNumber `
                $sourceResult.durationMinutes) -or
            [double]$sourceResult.durationMinutes -lt 30 -or
            [int]$sourceResult.crashCount -ne 0 -or
            [int]$sourceResult.anrCount -ne 0 -or
            @(
                $sourceResult.peakRssMb,
                $sourceResult.batteryStartPercent,
                $sourceResult.batteryEndPercent,
                $sourceResult.temperatureStartC,
                $sourceResult.temperatureEndC
            ).Where({ -not (Test-LexiQuestFiniteNumber $_) }).Count -gt 0
        ) {
            throw 'Only a complete 30-minute zero-crash endurance run may sign.'
        }
        $payload = [pscustomobject][ordered]@{
            evidenceId = $device.evidenceId
            tier = $device.tier
            pseudonymousDeviceId = $device.pseudonymousDeviceId
            status = $sourceResult.status
            durationMinutes = $sourceResult.durationMinutes
            crashCount = $sourceResult.crashCount
            anrCount = $sourceResult.anrCount
            peakRssMb = $sourceResult.peakRssMb
            batteryStartPercent = $sourceResult.batteryStartPercent
            batteryEndPercent = $sourceResult.batteryEndPercent
            temperatureStartC = $sourceResult.temperatureStartC
            temperatureEndC = $sourceResult.temperatureEndC
        }
        foreach ($propertyName in @(
            'status',
            'durationMinutes',
            'crashCount',
            'anrCount',
            'peakRssMb',
            'batteryStartPercent',
            'batteryEndPercent',
            'temperatureStartC',
            'temperatureEndC'
        )) {
            $target.$propertyName = $sourceResult.$propertyName
        }
    }
}
$sourceResultJson = $sourceResult | ConvertTo-Json -Depth 20 -Compress
$payloadJson = $payload | ConvertTo-Json -Depth 20 -Compress
if ($sourceResultJson -cne $payloadJson) {
    throw 'The instrumented payload contains unexpected or reordered fields.'
}

$trustedRsa = Get-LexiQuestTrustedEvidenceRsa $trustedPublicKeyFile
if ($null -eq $trustedRsa) {
    throw 'The tracked trusted evidence public key is invalid or too weak.'
}
$thumbprint = $SigningCertificateThumbprint.Replace(' ', '')
$certificate = Get-Item -LiteralPath ('Cert:\CurrentUser\My\' + $thumbprint) `
    -ErrorAction SilentlyContinue
if ($null -eq $certificate -or -not $certificate.HasPrivateKey) {
    $trustedRsa.Dispose()
    throw 'The approved evidence-signing certificate is unavailable.'
}
$certificateNow = Get-Date
if (
    $certificate.NotBefore -gt $certificateNow -or
    $certificate.NotAfter -lt $certificateNow
) {
    $trustedRsa.Dispose()
    throw 'The evidence-signing certificate is outside its validity window.'
}
$signingRsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey(
    $certificate
)
if (
    $null -eq $signingRsa -or
    $signingRsa.KeySize -lt 3072 -or
    (Get-LexiQuestEvidencePublicKeyId $signingRsa) -cne
        (Get-LexiQuestEvidencePublicKeyId $trustedRsa)
) {
    $trustedRsa.Dispose()
    if ($null -ne $signingRsa) {
        $signingRsa.Dispose()
    }
    throw 'The evidence signer does not match the tracked trusted public key.'
}
$trustedRsa.Dispose()

$sourceExportSha256 = (
    Get-FileHash -LiteralPath $instrumentedResultFile -Algorithm SHA256
).Hash
$sourceDirectory = Join-Path $privateEvidencePath 'sources'
New-Item -ItemType Directory -Path $sourceDirectory -Force | Out-Null
$sourceBlobPath = Join-Path $sourceDirectory "$sourceExportSha256.source"
if (Test-Path -LiteralPath $sourceBlobPath) {
    if (
        (Get-FileHash -LiteralPath $sourceBlobPath -Algorithm SHA256).Hash `
            -cne $sourceExportSha256
    ) {
        $signingRsa.Dispose()
        throw 'Existing instrumented source has an unexpected digest.'
    }
} else {
    Copy-Item -LiteralPath $instrumentedResultFile -Destination $sourceBlobPath
}
$receiptId = [Guid]::NewGuid().ToString('D')
$receipt = [ordered]@{
    schemaVersion = 2
    kind = $kind
    receiptId = $receiptId
    origin = 'physical-android-instrumentation'
    observedAtUtc = [string]$sourceEnvelope.observedAtUtc
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
[IO.File]::WriteAllBytes($blobPath, $bytes)
$reference = "private-evidence:v1:$kind`:$receiptId`:sha256:$digest"
$target.evidenceRef = $reference
$device | ConvertTo-Json -Depth 20 |
    Set-Content -LiteralPath $deviceFile -Encoding utf8
Write-Output $reference
