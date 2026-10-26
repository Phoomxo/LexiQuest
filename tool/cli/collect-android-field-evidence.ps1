#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('low', 'mid', 'high')]
    [string]$Tier,

    [Parameter(Mandatory)]
    [ValidateSet('phone', 'foldable', 'tablet')]
    [string]$FormFactor,

    [Parameter(Mandatory)]
    [ValidateSet('wifi', 'cellular', 'offline-mixed')]
    [string]$NetworkProfile,

    [Parameter(Mandatory)]
    [string]$ReleaseManifestPath,
    [Parameter(Mandatory)]
    [string]$EvidenceRootPath,
    [string]$OutputDirectory = 'devices'
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

function Invoke-AdbText {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $lines = @(& adb @Arguments 2>$null)
    return (@($lines | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

function Get-TextSha256 {
    param([Parameter(Mandatory)][string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString(
            $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))
        )).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
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

function Get-InstalledLastUpdateTime {
    param(
        [Parameter(Mandatory)][string]$Serial,
        [Parameter(Mandatory)][string]$PackageName
    )

    $packageOutput = @(
        & adb -s $Serial shell dumpsys package $PackageName 2>$null
    )
    $lastUpdateMatch = [regex]::Match(
        ($packageOutput -join "`n"),
        '(?m)^\s*lastUpdateTime=(.+)$'
    )
    if (-not $lastUpdateMatch.Success) {
        return ''
    }
    return $lastUpdateMatch.Groups[1].Value.Trim()
}

function Get-InstalledVersionName {
    param(
        [Parameter(Mandatory)][string]$Serial,
        [Parameter(Mandatory)][string]$PackageName
    )

    $packageOutput = @(
        & adb -s $Serial shell dumpsys package $PackageName 2>$null
    )
    $match = [regex]::Match(
        ($packageOutput -join "`n"),
        '(?m)^\s*versionName=(\S+)\s*$'
    )
    if (-not $match.Success) {
        return ''
    }
    return $match.Groups[1].Value
}

function Get-InstalledBaseApkPath {
    param(
        [Parameter(Mandatory)][string]$Serial,
        [Parameter(Mandatory)][string]$PackageName
    )

    $pathLine = @(
        & adb -s $Serial shell pm path $PackageName 2>$null |
            Where-Object { [string]$_ -match '^package:.*base\.apk\s*$' }
    ) | Select-Object -First 1
    if ($null -eq $pathLine) {
        return ''
    }
    return ([string]$pathLine).Trim().Substring('package:'.Length)
}

function Get-InstalledApkPaths {
    param(
        [Parameter(Mandatory)][string]$Serial,
        [Parameter(Mandatory)][string]$PackageName
    )

    return @(
        & adb -s $Serial shell pm path $PackageName 2>$null |
            ForEach-Object {
                $line = ([string]$_).Trim()
                if ($line.StartsWith('package:')) {
                    $line.Substring('package:'.Length)
                }
            } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-InstalledSourceFacts {
    param(
        [Parameter(Mandatory)][string]$Serial,
        [Parameter(Mandatory)][string]$PackageName
    )

    $output = @(
        & adb -s $Serial shell cmd package get-install-source `
            $PackageName 2>$null
    ) -join ' '
    $readValue = {
        param([string]$Name)
        $match = [regex]::Match(
            $output,
            [regex]::Escape($Name) + '=([^\s]+)'
        )
        if (-not $match.Success -or $match.Groups[1].Value -eq 'null') {
            return ''
        }
        return $match.Groups[1].Value
    }
    return [pscustomobject]@{
        installerPackageName = & $readValue 'installerPackageName'
        initiatingPackageName = & $readValue 'initiatingPackageName'
    }
}

if ($null -eq (Get-Command adb -ErrorAction SilentlyContinue)) {
    throw 'adb is required to collect physical Android evidence.'
}
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
$isEmulator = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.kernel.qemu')
$bootQemu = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.boot.qemu')
$deviceHardware = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.hardware')
$deviceModel = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.product.model')
$deviceManufacturer = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.product.manufacturer')
$deviceFingerprint = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.build.fingerprint')
$emulatorDetected = (
    $isEmulator -eq '1' -or
    $bootQemu -eq '1' -or
    $serial -match '^(?:emulator-|127\.0\.0\.1:)' -or
    $deviceHardware -match '(?i)ranchu|goldfish|vbox|ldplayer' -or
    $deviceModel -match '(?i)sdk[_ -]?gphone|emulator|ldplayer|virtualbox' -or
    $deviceManufacturer -match '(?i)genymotion' -or
    $deviceFingerprint -match '(?i)^generic(?:_x86)?/'
)
if ($emulatorDetected) {
    throw 'P8 evidence requires a physical Android device, not an emulator.'
}

$sdkText = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
    'ro.build.version.sdk')
if ($sdkText -notmatch '^\d+$') {
    throw 'Unable to measure the Android API level.'
}
$sdk = [int]$sdkText
$ramLine = Invoke-AdbValue @('-s', $serial, 'shell', 'cat', '/proc/meminfo')
$ramMatch = [regex]::Match($ramLine, 'MemTotal:\s+(\d+)')
if (-not $ramMatch.Success) {
    throw 'Unable to measure physical device RAM.'
}
$ramMb = [Math]::Round([double]$ramMatch.Groups[1].Value / 1024)
$featureText = Invoke-AdbText @('-s', $serial, 'shell', 'pm', 'list', 'features')
$windowState = Invoke-AdbText @('-s', $serial, 'shell', 'dumpsys', 'window',
    'displays')
if ([string]::IsNullOrWhiteSpace($featureText) -or
    [string]::IsNullOrWhiteSpace($windowState)) {
    throw 'Unable to measure Android features and window properties.'
}
$displaySize = Invoke-AdbText @('-s', $serial, 'shell', 'wm', 'size')
$displayDensity = Invoke-AdbText @('-s', $serial, 'shell', 'wm', 'density')
$sizeMatch = [regex]::Match(
    $displaySize,
    '(?im)^Physical size:\s*(\d+)x(\d+)\s*$'
)
$densityMatch = [regex]::Match(
    $displayDensity,
    '(?im)^Physical density:\s*(\d+)\s*$'
)
if (-not $sizeMatch.Success -or -not $densityMatch.Success -or
    [int]$densityMatch.Groups[1].Value -le 0) {
    throw 'Unable to derive the physical smallest window width.'
}
$smallestWidthDp = [Math]::Round(
    [Math]::Min(
        [double]$sizeMatch.Groups[1].Value,
        [double]$sizeMatch.Groups[2].Value
    ) * 160 / [double]$densityMatch.Groups[1].Value,
    1
)
$hasHingeSensor = $featureText -match
    '(?im)^feature:android\.hardware\.sensor\.hinge_angle\s*$'
$foldFeatureObserved = (
    $windowState -match '(?i)\b(?:FoldingFeature|HingeFeature)\b' -or
    $windowState -match (
        '(?i)(?:m?FoldedArea|foldedArea)\s*=\s*' +
        'Rect\((?!0,\s*0\s*-\s*0,\s*0\))[^)]*\)'
    )
)
$unsupportedFormFactorFeature = $featureText -match
    '(?im)^feature:android\.hardware\.type\.(?:watch|television|automotive|embedded)\s*$'
$derivedTier = Get-LexiQuestDerivedDeviceTier -RamMb $ramMb -Sdk $sdk
$derivedFormFactor = Get-LexiQuestDerivedFormFactor `
    -SmallestWidthDp $smallestWidthDp `
    -HasHingeSensor $hasHingeSensor `
    -FoldFeatureObserved $foldFeatureObserved `
    -UnsupportedFormFactorFeature $unsupportedFormFactorFeature
if ($Tier -ne $derivedTier) {
    throw (
        "Requested tier '$Tier' does not match measured tier '$derivedTier'."
    )
}
if ($FormFactor -ne $derivedFormFactor) {
    throw (
        "Requested form factor '$FormFactor' does not match measured " +
        "form factor '$derivedFormFactor'."
    )
}
$featureSetSha256 = Get-TextSha256 -Text $featureText
$windowStateSha256 = Get-TextSha256 -Text $windowState

$releaseManifestFile = Resolve-RepositoryPath $ReleaseManifestPath
if (-not (Test-Path -LiteralPath $releaseManifestFile -PathType Leaf)) {
    throw "Release manifest is missing: $releaseManifestFile"
}
$releaseManifest =
    Get-Content -LiteralPath $releaseManifestFile -Raw -Encoding utf8 |
        ConvertFrom-Json
$apkPathValue = [string]$releaseManifest.artifact.apkPath
$apkPath = if ([System.IO.Path]::IsPathRooted($apkPathValue)) {
    [System.IO.Path]::GetFullPath($apkPathValue)
} else {
    [System.IO.Path]::GetFullPath(
        (Join-Path (Split-Path -Parent $releaseManifestFile) $apkPathValue)
    )
}
if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
    throw "Release APK is missing: $apkPath"
}
$trustPath = Join-Path $repoRoot `
    'tool/cli/config/release-signing-trust.json'
if (-not (Test-Path -LiteralPath $trustPath -PathType Leaf)) {
    throw 'The committed release signing trust record is missing.'
}
$trust = Get-Content -LiteralPath $trustPath -Raw -Encoding utf8 |
    ConvertFrom-Json
$trustedCertificate = ConvertTo-NormalizedSha256 `
    $trust.uploadCertificateSha256
$modelSha256 = Get-LexiQuestPinnedModelSha256 -RepoRoot $repoRoot
$expectedVersion = '{0}+{1}' -f
    $releaseManifest.artifact.versionName,
    $releaseManifest.artifact.versionCode
$measuredApk = Get-LexiQuestMeasuredApkMetadata `
    -ApkPath $apkPath `
    -ExpectedBuildId ([string]$releaseManifest.sourceCommit) `
    -ExpectedModelSha256 $modelSha256 `
    -ExpectedVersion $expectedVersion
$metadataErrors = @(Test-LexiQuestArtifactMetadata `
    -Measured $measuredApk `
    -Expected $releaseManifest.artifact `
    -ExpectedCertificateSha256 $trustedCertificate `
    -ExpectedModelSha256 $modelSha256)
if ($metadataErrors.Count -gt 0) {
    throw (
        "APK failed pre-install release verification:`n - " +
        ($metadataErrors -join "`n - ")
    )
}
$targetVersionCode = [int]$releaseManifest.artifact.versionCode
if ($targetVersionCode -lt 1) {
    throw 'Release manifest versionCode must be a positive integer.'
}
$priorVersionCode = Get-InstalledVersionCode `
    -Serial $serial `
    -PackageName 'com.lexiquest.app'
$priorLastUpdateTime = Get-InstalledLastUpdateTime `
    -Serial $serial `
    -PackageName 'com.lexiquest.app'

$installOutput = @()
$installExitCode = 0
$isDirectInstall = [string]$releaseManifest.releaseProfile -eq 'fieldTrial'
if ($isDirectInstall) {
    $installOutput = & adb -s $serial install --no-streaming -r `
        $apkPath 2>&1
    $installExitCode = [int]$LASTEXITCODE
} elseif ([string]$releaseManifest.releaseProfile -ne 'publicProduction') {
    throw 'Release manifest profile must be fieldTrial or publicProduction.'
}
$transportReady = $false
for ($attempt = 0; $attempt -lt 15; $attempt++) {
    $deviceState = (& adb -s $serial get-state 2>$null | Select-Object -First 1)
    if (([string]$deviceState).Trim() -eq 'device') {
        $transportReady = $true
        break
    }
    Start-Sleep -Seconds 1
}
$installedVersionCode = Get-InstalledVersionCode `
    -Serial $serial `
    -PackageName 'com.lexiquest.app'
$installedLastUpdateTime = Get-InstalledLastUpdateTime `
    -Serial $serial `
    -PackageName 'com.lexiquest.app'
$installationChanged = if ($isDirectInstall) {
    $null -eq $priorVersionCode -or
    $priorVersionCode -ne $installedVersionCode -or
    $priorLastUpdateTime -ne $installedLastUpdateTime
} else {
    $true
}
if (
    -not $transportReady -or
    $installedVersionCode -ne $targetVersionCode -or
    -not $installationChanged
) {
    throw (
        'APK installation failed or did not reconcile to versionCode {0}: ' +
        'adbExit={1}; {2}' -f
            $targetVersionCode,
            $installExitCode,
            ($installOutput -join "`n")
    )
}
$installedVersionName = Get-InstalledVersionName `
    -Serial $serial `
    -PackageName 'com.lexiquest.app'
$installSource = Get-InstalledSourceFacts `
    -Serial $serial `
    -PackageName 'com.lexiquest.app'
if (-not $isDirectInstall -and
    [string]$installSource.installerPackageName -ne
        'com.android.vending') {
    throw 'Public-production evidence requires a Play-installed package.'
}
$installedBasePath = Get-InstalledBaseApkPath `
    -Serial $serial `
    -PackageName 'com.lexiquest.app'
if ([string]::IsNullOrWhiteSpace($installedBasePath)) {
    throw 'Unable to resolve the installed base APK.'
}
$installedRemoteApks = @(Get-InstalledApkPaths `
    -Serial $serial `
    -PackageName 'com.lexiquest.app')
$temporaryInstalledApks = [System.Collections.Generic.List[string]]::new()
try {
    $temporaryBaseApk = ''
    $apkIndex = 0
    foreach ($remoteApk in $installedRemoteApks) {
        $temporaryApk = Join-Path ([System.IO.Path]::GetTempPath()) (
            'lexiquest-installed-' + [Guid]::NewGuid().ToString('N') +
            "-$apkIndex.apk"
        )
        & adb -s $serial pull $remoteApk $temporaryApk 2>&1 | Out-Null
        if ([int]$LASTEXITCODE -ne 0 -or
            -not (Test-Path -LiteralPath $temporaryApk -PathType Leaf)) {
            throw "Unable to pull installed APK: $remoteApk"
        }
        $temporaryInstalledApks.Add($temporaryApk)
        if ($remoteApk -eq $installedBasePath) {
            $temporaryBaseApk = $temporaryApk
        }
        $apkIndex++
    }
    if ([string]::IsNullOrWhiteSpace($temporaryBaseApk)) {
        throw 'Installed base APK was absent from the measured APK set.'
    }
    $installedApk = Get-LexiQuestMeasuredApkMetadata `
        -ApkPath $temporaryBaseApk `
        -ExpectedBuildId ([string]$releaseManifest.sourceCommit) `
        -ExpectedModelSha256 $modelSha256 `
        -ExpectedVersion $expectedVersion `
        -ProvenanceArchivePaths $temporaryInstalledApks.ToArray()
}
finally {
    foreach ($temporaryApk in $temporaryInstalledApks) {
        if (Test-Path -LiteralPath $temporaryApk -PathType Leaf) {
            [System.IO.File]::Delete($temporaryApk)
        }
    }
}
if ($installedApk.packageName -ne 'com.lexiquest.app' -or
    [int]$installedApk.versionCode -ne $targetVersionCode -or
    [string]$installedApk.versionName -ne
        [string]$releaseManifest.artifact.versionName) {
    throw 'Installed package identity does not match the release candidate.'
}
if ($isDirectInstall -and
    (ConvertTo-NormalizedSha256 `
        $installedApk.signingCertificateSha256) -ne $trustedCertificate) {
    throw 'Installed package signer does not match the verified field APK.'
}
& adb -s $serial shell monkey -p com.lexiquest.app 1 | Out-Null
if ([int]$LASTEXITCODE -ne 0) {
    throw 'The installed LexiQuest package could not be launched.'
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

$recordedAt = [DateTime]::UtcNow
$evidenceId = "$derivedTier-$($recordedAt.ToString(
    'yyyyMMddTHHmmssZ',
    [System.Globalization.CultureInfo]::InvariantCulture
))"
$evidenceRoot = Resolve-RepositoryPath $EvidenceRootPath
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$output = Get-LexiQuestContainedPath `
    -Path $OutputDirectory `
    -RootPath $evidenceRoot
New-Item -ItemType Directory -Path $output -Force | Out-Null
$recordDirectory = Join-Path $evidenceRoot 'records'
New-Item -ItemType Directory -Path $recordDirectory -Force | Out-Null
$installRecordPath = Join-Path $recordDirectory "$evidenceId-install.json"
$installRecord = [ordered]@{
    recordType = 'lexiquestMeasuredInstallation'
    recordedAtUtc = $recordedAt.ToString(
        'o',
        [System.Globalization.CultureInfo]::InvariantCulture
    )
    releaseProfile = [string]$releaseManifest.releaseProfile
    localApkSha256 = $measuredApk.archiveSha256
    localApkSigningCertificateSha256 =
        $measuredApk.signingCertificateSha256
    installedBaseApkSha256 = $installedApk.archiveSha256
    installedSigningCertificateSha256 =
        $installedApk.signingCertificateSha256
    installedPackageName = $installedApk.packageName
    installedVersionName = $installedVersionName
    installedVersionCode = $installedApk.versionCode
    installerPackageName = $installSource.installerPackageName
    initiatingPackageName = $installSource.initiatingPackageName
}
[System.IO.File]::WriteAllText(
    $installRecordPath,
    (($installRecord | ConvertTo-Json -Depth 6) + [Environment]::NewLine),
    [System.Text.UTF8Encoding]::new($false)
)
$installEvidenceRef = New-LexiQuestEvidenceReference `
    -Path $installRecordPath `
    -EvidenceRootPath $evidenceRoot

$journeys = [ordered]@{}
foreach ($name in Get-LexiQuestRequiredFieldJourneys) {
    $journeys[$name] = [ordered]@{
        status = 'pending'
        evidenceRef = ''
        notes = ''
    }
}
if ($null -eq $priorVersionCode) {
    $journeys.cleanInstall = [ordered]@{
        status = 'pass'
        evidenceRef = $installEvidenceRef
        notes = 'Package was absent before this exact APK was installed.'
    }
} elseif ($priorVersionCode -lt $targetVersionCode) {
    $journeys.upgradeInstall = [ordered]@{
        status = 'pass'
        evidenceRef = $installEvidenceRef
        notes = 'A lower installed version was upgraded in place.'
    }
}

$record = [ordered]@{
    recordType = 'lexiquestPhysicalDeviceEvidence'
    schemaVersion = 2
    evidenceId = $evidenceId
    tier = $derivedTier
    formFactor = $derivedFormFactor
    pseudonymousDeviceId = $pseudonymousId
    recordedAtUtc = $recordedAt.ToString(
        'o',
        [System.Globalization.CultureInfo]::InvariantCulture
    )
    device = [ordered]@{
        physical = $true
        emulatorDetected = $false
        model = $deviceModel
        androidVersion = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
            'ro.build.version.release')
        sdk = $sdk
        ramMb = $ramMb
        chipset = $chipset
        gpu = $gpu
        storageFreeMb = $storageFreeMb
        networkProfile = $NetworkProfile
        displaySize = $displaySize
        displayDensity = $displayDensity
        smallestWidthDp = $smallestWidthDp
        hasHingeSensor = $hasHingeSensor
        foldFeatureObserved = $foldFeatureObserved
        unsupportedFormFactorFeature = $unsupportedFormFactorFeature
        featureSetSha256 = $featureSetSha256
        windowStateSha256 = $windowStateSha256
    }
    release = [ordered]@{
        apkSha256 = $measuredApk.archiveSha256
        aabSha256 = [string]$releaseManifest.artifact.aabSha256
        signingCertificateSha256 =
            $measuredApk.signingCertificateSha256
        modelSha256 = $modelSha256
        packageName = $measuredApk.packageName
        versionName = $measuredApk.versionName
        versionCode = $measuredApk.versionCode
        buildId = $measuredApk.embeddedBuildId
    }
    installation = [ordered]@{
        source = if ($isDirectInstall) { 'directAdb' } else { 'play' }
        localApkSha256 = $measuredApk.archiveSha256
        localApkSigningCertificateSha256 =
            $measuredApk.signingCertificateSha256
        installedBaseApkSha256 = $installedApk.archiveSha256
        installedPackageName = $installedApk.packageName
        installedVersionName = $installedVersionName
        installedVersionCode = $installedApk.versionCode
        installedSigningCertificateSha256 =
            $installedApk.signingCertificateSha256
        installerPackageName = $installSource.installerPackageName
        initiatingPackageName = $installSource.initiatingPackageName
    }
    journeys = $journeys
    acceptance = [ordered]@{
        portrait = [ordered]@{ status = 'pending'; evidenceRef = '' }
        landscape = [ordered]@{ status = 'pending'; evidenceRef = '' }
        textScale100 = [ordered]@{ status = 'pending'; evidenceRef = '' }
        textScale200 = [ordered]@{ status = 'pending'; evidenceRef = '' }
        manualTalkBack = [ordered]@{ status = 'pending'; evidenceRef = '' }
        humanUat = [ordered]@{ status = 'pending'; evidenceRef = '' }
        foldPostures = if ($derivedFormFactor -eq 'foldable') {
            [ordered]@{
                cover = [ordered]@{ status = 'pending'; evidenceRef = '' }
                book = [ordered]@{ status = 'pending'; evidenceRef = '' }
                tabletop = [ordered]@{ status = 'pending'; evidenceRef = '' }
            }
        } else {
            $null
        }
    }
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
            evidenceRef = 'release-policy:gpu-not-allowlisted'
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

$outputFile = Join-Path $output "$($record.evidenceId).device.json"
$record | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath $outputFile -Encoding utf8
Write-Host (
    'Physical-device draft created with pending journeys: {0}' -f $outputFile
) -ForegroundColor Yellow
