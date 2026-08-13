#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('low', 'mid', 'high')]
    [string]$Tier,

    [Parameter(Mandatory)]
    [ValidateSet('wifi', 'cellular', 'offline-mixed')]
    [string]$NetworkProfile,

    [string]$ReleaseManifestPath = 'build/field-release/release-manifest.json',
    [string]$OutputDirectory = 'field/evidence/devices',
    [string]$PrivateEvidenceDirectory = 'field/evidence/private-evidence',
    [string]$TrustedEvidencePublicKeyPath =
        'tool/cli/trusted-field-evidence-public-key.xml',
    [Parameter(Mandatory)]
    [string]$SigningCertificateThumbprint
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

function Invoke-AdbValue {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $value = (& adb @Arguments 2>$null | Select-Object -First 1)
    if ($null -eq $value) {
        return ''
    }
    return ([string]$value).Trim()
}

function ConvertTo-StrictUtcText {
    param([Parameter(Mandatory)][DateTimeOffset]$Value)

    return $Value.UtcDateTime.ToString(
        "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",
        [Globalization.CultureInfo]::InvariantCulture
    )
}

function New-PrivateEvidenceReceipt {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][object]$Payload,
        [Parameter(Mandatory)][object]$Manifest,
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)]
        [System.Security.Cryptography.RSA]$SigningRsa
    )

    $id = [Guid]::NewGuid().ToString('D')
    $observedAtUtc = ConvertTo-StrictUtcText ([DateTimeOffset]::UtcNow)
    $sourceEnvelope = [ordered]@{
        schemaVersion = 1
        kind = $Kind
        origin = 'physical-android-collector'
        captureMethod = 'physical-android-collector'
        hostFake = $false
        sourceCommit = [string]$Manifest.sourceCommit
        apkSha256 = [string]$Manifest.artifact.apkSha256
        observedAtUtc = $observedAtUtc
        payload = $Payload
    }
    $encoding = [Text.UTF8Encoding]::new($false)
    $sourceBytes = $encoding.GetBytes(
        ($sourceEnvelope | ConvertTo-Json -Depth 20 -Compress)
    )
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $sourceExportSha256 = (
            [BitConverter]::ToString($sha.ComputeHash($sourceBytes))
        ).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
    $sourceDirectory = Join-Path $Directory 'sources'
    New-Item -ItemType Directory -Path $sourceDirectory -Force | Out-Null
    $sourcePath = Join-Path $sourceDirectory "$sourceExportSha256.source"
    if (Test-Path -LiteralPath $sourcePath) {
        if (
            (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash `
                -cne $sourceExportSha256
        ) {
            throw 'Existing collector source has an unexpected digest.'
        }
    } else {
        [IO.File]::WriteAllBytes($sourcePath, $sourceBytes)
    }
    $receipt = [ordered]@{
        schemaVersion = 2
        kind = $Kind
        receiptId = $id
        observedAtUtc = $observedAtUtc
        sourceCommit = [string]$Manifest.sourceCommit
        apkSha256 = [string]$Manifest.artifact.apkSha256
        origin = 'physical-android-collector'
        sourceExportSha256 = $sourceExportSha256
        payload = $Payload
    }
    $receipt.signingKeyId = Get-LexiQuestEvidencePublicKeyId $SigningRsa
    $receipt.signatureAlgorithm = 'rsa-sha256-pkcs1'
    $receipt.signatureBase64 = [Convert]::ToBase64String(
        $SigningRsa.SignData(
            (ConvertTo-LexiQuestEvidenceSigningBytes `
                ([pscustomobject]$receipt)),
            [Security.Cryptography.HashAlgorithmName]::SHA256,
            [Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
    )
    $json = $receipt | ConvertTo-Json -Depth 20 -Compress
    $bytes = $encoding.GetBytes($json)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace(
            '-',
            ''
        )
    }
    finally {
        $sha.Dispose()
    }
    $blobDirectory = Join-Path $Directory 'blobs'
    New-Item -ItemType Directory -Path $blobDirectory -Force | Out-Null
    [IO.File]::WriteAllBytes(
        (Join-Path $blobDirectory "$digest.receipt"),
        $bytes
    )
    return "private-evidence:v1:$Kind`:$id`:sha256:$digest"
}

function Get-InstalledVersionCode {
    param(
        [Parameter(Mandatory)][string]$Serial,
        [Parameter(Mandatory)][string]$PackageName
    )

    $packageOutput = @(
        & adb -s $Serial shell dumpsys package $PackageName 2>$null
    )
    $versionMatch = [regex]::Match(
        ($packageOutput -join "`n"),
        '(?m)^\s*versionCode=(\d+)\b'
    )
    if (-not $versionMatch.Success) {
        return $null
    }
    return [int]$versionMatch.Groups[1].Value
}

if ($null -eq (Get-Command adb -ErrorAction SilentlyContinue)) {
    throw 'adb is required to collect physical Android evidence.'
}
$trustedEvidencePublicKeyFile = Resolve-RepositoryPath `
    $TrustedEvidencePublicKeyPath
$trustedEvidenceRsa = Get-LexiQuestTrustedEvidenceRsa `
    $trustedEvidencePublicKeyFile
if ($null -eq $trustedEvidenceRsa) {
    throw 'A tracked RSA-3072+ trusted field-evidence public key is required.'
}
$normalizedThumbprint = $SigningCertificateThumbprint.Replace(' ', '')
$certificatePath = 'Cert:\CurrentUser\My\' + $normalizedThumbprint
$signingCertificate = Get-Item -LiteralPath $certificatePath `
    -ErrorAction SilentlyContinue
if ($null -eq $signingCertificate -or -not $signingCertificate.HasPrivateKey) {
    $trustedEvidenceRsa.Dispose()
    throw 'The approved evidence-signing certificate is unavailable.'
}
$certificateNow = Get-Date
if (
    $signingCertificate.NotBefore -gt $certificateNow -or
    $signingCertificate.NotAfter -lt $certificateNow
) {
    $trustedEvidenceRsa.Dispose()
    throw 'The evidence-signing certificate is outside its validity window.'
}
$signingRsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey(
    $signingCertificate
)
if ($null -eq $signingRsa -or $signingRsa.KeySize -lt 3072) {
    $trustedEvidenceRsa.Dispose()
    if ($null -ne $signingRsa) {
        $signingRsa.Dispose()
    }
    throw 'The evidence-signing certificate must use RSA-3072 or stronger.'
}
if (
    (Get-LexiQuestEvidencePublicKeyId $signingRsa) -cne
        (Get-LexiQuestEvidencePublicKeyId $trustedEvidenceRsa)
) {
    $trustedEvidenceRsa.Dispose()
    $signingRsa.Dispose()
    throw 'The evidence signer does not match the tracked trusted public key.'
}
$trustedEvidenceRsa.Dispose()
$devices = @(
    & adb devices |
        Select-Object -Skip 1 |
        Where-Object { $_ -match "\tdevice$" } |
        ForEach-Object { ($_ -split "\t")[0] }
)
if ($devices.Count -ne 1) {
    throw 'Connect exactly one authorized physical Android device.'
}
$serial = $devices[0]
$roKernelQemu = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.kernel.qemu')
$roBootQemu = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.boot.qemu')
$buildType = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.build.type')
$debuggable = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.debuggable')
$secure = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.secure')
$model = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.product.model')
$fingerprint = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.build.fingerprint')
$brand = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.product.brand')
$deviceName = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.product.device')
$hardware = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.hardware')
$deviceMarkers = @(
    $model,
    $fingerprint,
    $brand,
    $deviceName,
    $hardware
) -join ' '
$roKernelQemuNormalized = if ([string]::IsNullOrWhiteSpace($roKernelQemu)) {
    'absent'
} else {
    $roKernelQemu
}
$roBootQemuNormalized = if ([string]::IsNullOrWhiteSpace($roBootQemu)) {
    'absent'
} else {
    $roBootQemu
}
if (
    $roKernelQemu -eq '1' -or
    $roBootQemu -eq '1' -or
    $serial -match '^emulator-' -or
    $buildType -cne 'user' -or
    $debuggable -cne '0' -or
    $secure -cne '1' -or
    $deviceMarkers -match (
        '(?i)goldfish|ranchu|cuttlefish|vbox|generic|' +
        'sdk_gphone|emulator'
    )
) {
    throw 'P8 evidence requires a physical Android device, not an emulator.'
}

$releaseManifestFile = Resolve-RepositoryPath $ReleaseManifestPath
if (-not (Test-Path -LiteralPath $releaseManifestFile -PathType Leaf)) {
    throw "Release manifest is missing: $releaseManifestFile"
}
$releaseManifest =
    Get-Content -LiteralPath $releaseManifestFile -Raw -Encoding utf8 |
        ConvertFrom-Json
$privateEvidencePath = Resolve-RepositoryPath $PrivateEvidenceDirectory
$apkPath = [System.IO.Path]::GetFullPath(
    (Join-Path (
        Split-Path -Parent $releaseManifestFile
    ) ([string]$releaseManifest.artifact.apkPath))
)
if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
    throw "Release APK is missing: $apkPath"
}
$localApkSha256 = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash
if (
    $localApkSha256 -cne
        (ConvertTo-NormalizedSha256 $releaseManifest.artifact.apkSha256)
) {
    throw 'Release APK bytes do not match release-manifest.json.'
}
$targetVersionCode = [int]$releaseManifest.artifact.versionCode
if ($targetVersionCode -lt 1) {
    throw 'Release manifest versionCode must be a positive integer.'
}
$priorVersionCode = Get-InstalledVersionCode `
    -Serial $serial `
    -PackageName 'com.lexiquest.app'

$installOutput = & adb -s $serial install -r $apkPath 2>&1
if ([int]$LASTEXITCODE -ne 0 -or ($installOutput -join "`n") -notmatch 'Success') {
    throw "APK installation failed: $installOutput"
}
& adb -s $serial shell monkey -p com.lexiquest.app 1 | Out-Null
if ([int]$LASTEXITCODE -ne 0) {
    throw 'The installed LexiQuest package could not be launched.'
}
$installedBaseApkPath = Invoke-AdbValue @(
    '-s',
    $serial,
    'shell',
    'pm',
    'path',
    'com.lexiquest.app'
)
$installedBaseApkPath = $installedBaseApkPath -replace '^package:', ''
if ([string]::IsNullOrWhiteSpace($installedBaseApkPath)) {
    throw 'Unable to resolve the installed base APK for verification.'
}
$installedApkTempRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'lexiquest-installed-apk-' + [Guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Path $installedApkTempRoot | Out-Null
try {
    $pulledApkPath = Join-Path $installedApkTempRoot 'base.apk'
    & adb -s $serial pull $installedBaseApkPath $pulledApkPath | Out-Null
    if (
        [int]$LASTEXITCODE -ne 0 -or
        -not (Test-Path -LiteralPath $pulledApkPath -PathType Leaf)
    ) {
        throw 'Unable to pull the installed base APK for verification.'
    }
    $installedApkSha256 = (
        Get-FileHash -LiteralPath $pulledApkPath -Algorithm SHA256
    ).Hash
}
finally {
    $systemTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $installedApkTempRoot.StartsWith(
        $systemTempRoot,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Unsafe installed-APK temporary cleanup target.'
    }
    if (Test-Path -LiteralPath $installedApkTempRoot) {
        Remove-Item -LiteralPath $installedApkTempRoot -Recurse -Force
    }
}
if ($installedApkSha256 -cne $localApkSha256) {
    throw 'The installed base APK bytes do not match the release candidate.'
}

$releaseId = '{0}:{1}' -f
    $releaseManifest.sourceCommit,
    $releaseManifest.artifact.apkSha256
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $identityBytes = [Text.Encoding]::UTF8.GetBytes("$releaseId`:$serial")
    $pseudonymousId =
        ([BitConverter]::ToString($sha.ComputeHash($identityBytes))).Replace(
            '-',
            ''
        )
}
finally {
    $sha.Dispose()
}

$ramLine = Invoke-AdbValue @('-s', $serial, 'shell', 'cat', '/proc/meminfo')
$ramMatch = [regex]::Match($ramLine, 'MemTotal:\s+(\d+)')
$ramMb = if ($ramMatch.Success) {
    [Math]::Round([double]$ramMatch.Groups[1].Value / 1024)
} else {
    $null
}
$chipset = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.soc.model')
if ([string]::IsNullOrWhiteSpace($chipset)) {
    $chipset = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
        'ro.hardware')
}
$gpuLine = (
    & adb -s $serial shell dumpsys SurfaceFlinger 2>$null |
        Select-String -Pattern 'GLES:' |
        Select-Object -First 1
)
$gpu = if ($null -eq $gpuLine) { 'unavailable' } else {
    ([string]$gpuLine.Line).Trim()
}
$storageLine = (
    & adb -s $serial shell df -k /data 2>$null |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        Select-Object -Last 1
)
$storageColumns = @(([string]$storageLine).Trim() -split '\s+')
$storageFreeMb = if ($storageColumns.Count -ge 4) {
    [Math]::Round([double]$storageColumns[3] / 1024)
} else {
    $null
}

$recordedAt = [DateTimeOffset]::UtcNow
$evidenceId = "$Tier-$($recordedAt.ToString('yyyyMMddTHHmmssZ'))"
$cleanInstallPayload = $null
$upgradeInstallPayload = $null
$journeys = [ordered]@{}
foreach ($name in Get-LexiQuestRequiredFieldJourneys) {
    $journeys[$name] = [ordered]@{
        status = 'pending'
        evidenceRef = ''
        notes = ''
    }
}
if ($null -eq $priorVersionCode) {
    $cleanInstallPayload = [ordered]@{
        evidenceId = $evidenceId
        tier = $Tier
        pseudonymousDeviceId = $pseudonymousId
        journey = 'cleanInstall'
        status = 'pass'
    }
    $journeys.cleanInstall = [ordered]@{
        status = 'pass'
        evidenceRef = (New-PrivateEvidenceReceipt `
            -Kind 'device-journey' `
            -Payload $cleanInstallPayload `
            -Manifest $releaseManifest `
            -Directory $privateEvidencePath `
            -SigningRsa $signingRsa)
        notes = 'Package was absent before this exact APK was installed.'
    }
} elseif ($priorVersionCode -lt $targetVersionCode) {
    $upgradeInstallPayload = [ordered]@{
        evidenceId = $evidenceId
        tier = $Tier
        pseudonymousDeviceId = $pseudonymousId
        journey = 'upgradeInstall'
        status = 'pass'
    }
    $journeys.upgradeInstall = [ordered]@{
        status = 'pass'
        evidenceRef = (New-PrivateEvidenceReceipt `
            -Kind 'device-journey' `
            -Payload $upgradeInstallPayload `
            -Manifest $releaseManifest `
            -Directory $privateEvidencePath `
            -SigningRsa $signingRsa)
        notes = 'A lower installed version was upgraded in place.'
    }
}

$collectorScriptSha256 = (
    Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256
).Hash
$gpuPolicyPayload = [ordered]@{
    evidenceId = $evidenceId
    tier = $Tier
    pseudonymousDeviceId = $pseudonymousId
    benchmark = 'gpuDelegate'
    status = 'notApplicable'
    allowlisted = $false
    iterations = 0
    reason = 'GPU remains disabled until this device passes certification.'
}
$gpuPolicyRef = New-PrivateEvidenceReceipt `
    -Kind 'device-benchmark' `
    -Payload $gpuPolicyPayload `
    -Manifest $releaseManifest `
    -Directory $privateEvidencePath `
    -SigningRsa $signingRsa
$releaseRecord = [ordered]@{
    sourceCommit = [string]$releaseManifest.sourceCommit
    manifestGeneratedAtUtc = [string]$releaseManifest.generatedAtUtc
    apkPath = [string]$releaseManifest.artifact.apkPath
    apkSha256 = [string]$releaseManifest.artifact.apkSha256
    signingCertificateSha256 =
        [string]$releaseManifest.artifact.signingCertificateSha256
    packageName = [string]$releaseManifest.artifact.packageName
    versionName = [string]$releaseManifest.artifact.versionName
    versionCode = [int]$releaseManifest.artifact.versionCode
    buildId = [string]$releaseManifest.artifact.buildId
    modelSha256 = [string]$releaseManifest.artifact.modelSha256
}
$recordedAtText = ConvertTo-StrictUtcText $recordedAt
$deviceRecord = [ordered]@{
    physical = $true
    model = $model
    androidVersion = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
        'ro.build.version.release')
    sdk = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
        'ro.build.version.sdk')
    ramMb = $ramMb
    chipset = $chipset
    gpu = $gpu
    storageFreeMb = $storageFreeMb
    networkProfile = $NetworkProfile
}
$collectorRecord = [ordered]@{
    schemaVersion = 1
    origin = 'physical-android-collector'
    collectorScriptSha256 = $collectorScriptSha256
    connectedDeviceCount = $devices.Count
    roKernelQemu = $roKernelQemuNormalized
    roBootQemu = $roBootQemuNormalized
    serialKind = 'physical'
    buildType = $buildType
    debuggable = $debuggable
    secure = $secure
    fingerprint = $fingerprint
    brand = $brand
    deviceName = $deviceName
    hardware = $hardware
    verifiedApkSha256 = $installedApkSha256
}
$collectorAttestationPayload = [ordered]@{
    evidenceId = $evidenceId
    tier = $Tier
    pseudonymousDeviceId = $pseudonymousId
    recordedAtUtc = $recordedAtText
    device = $deviceRecord
    release = $releaseRecord
    collector = $collectorRecord
}
$collectorRecord['evidenceRef'] = New-PrivateEvidenceReceipt `
    -Kind 'device-attestation' `
    -Payload $collectorAttestationPayload `
    -Manifest $releaseManifest `
    -Directory $privateEvidencePath `
    -SigningRsa $signingRsa
$record = [ordered]@{
    evidenceId = $evidenceId
    tier = $Tier
    pseudonymousDeviceId = $pseudonymousId
    recordedAtUtc = $recordedAtText
    device = $deviceRecord
    release = $releaseRecord
    collector = $collectorRecord
    journeys = $journeys
    benchmarks = [ordered]@{
        cpuXnnpack = [ordered]@{
            status = 'pending'
            delegate = 'xnnpack'
            iterations = 0
            medianLatencyMs = 0
            evidenceRef = ''
        }
        gpuDelegate = [ordered]@{
            status = 'notApplicable'
            allowlisted = $false
            iterations = 0
            reason = 'GPU remains disabled until this device passes certification.'
            evidenceRef = $gpuPolicyRef
        }
    }
    endurance = [ordered]@{
        status = 'pending'
        durationMinutes = 0
        crashCount = $null
        anrCount = $null
        peakRssMb = $null
        batteryStartPercent = $null
        batteryEndPercent = $null
        temperatureStartC = $null
        temperatureEndC = $null
        evidenceRef = ''
    }
}

$output = Resolve-RepositoryPath $OutputDirectory
New-Item -ItemType Directory -Path $output -Force | Out-Null
$outputFile = Join-Path $output "$($record.evidenceId).json"
$record | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath $outputFile -Encoding utf8
$signingRsa.Dispose()
Write-Host (
    'Physical-device draft created with pending journeys: {0}' -f $outputFile
) -ForegroundColor Yellow
