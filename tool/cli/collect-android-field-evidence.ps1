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
    [string]$OutputDirectory = 'field/evidence/devices'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

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
if ($isEmulator -eq '1' -or $serial -match '^emulator-') {
    throw 'P8 evidence requires a physical Android device, not an emulator.'
}

$releaseManifestFile = Resolve-RepositoryPath $ReleaseManifestPath
if (-not (Test-Path -LiteralPath $releaseManifestFile -PathType Leaf)) {
    throw "Release manifest is missing: $releaseManifestFile"
}
$releaseManifest =
    Get-Content -LiteralPath $releaseManifestFile -Raw -Encoding utf8 |
        ConvertFrom-Json
$apkPath = [string]$releaseManifest.artifact.apkPath
if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
    throw "Release APK is missing: $apkPath"
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

$journeys = [ordered]@{}
. (Join-Path $PSScriptRoot 'lib\field-release-evidence.ps1')
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
        evidenceRef = "adb-clean-install:versionCode=$targetVersionCode"
        notes = 'Package was absent before this exact APK was installed.'
    }
} elseif ($priorVersionCode -lt $targetVersionCode) {
    $journeys.upgradeInstall = [ordered]@{
        status = 'pass'
        evidenceRef = (
            'adb-upgrade-install:versionCode={0}-to-{1}' -f
                $priorVersionCode,
                $targetVersionCode
        )
        notes = 'A lower installed version was upgraded in place.'
    }
}

$recordedAt = [DateTime]::UtcNow
$record = [ordered]@{
    evidenceId = "$Tier-$($recordedAt.ToString('yyyyMMddTHHmmssZ'))"
    tier = $Tier
    pseudonymousDeviceId = $pseudonymousId
    recordedAtUtc = $recordedAt.ToString('o')
    device = [ordered]@{
        physical = $true
        model = Invoke-AdbValue @('-s', $serial, 'shell', 'getprop',
            'ro.product.model')
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
    release = $releaseManifest.artifact
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

$output = Resolve-RepositoryPath $OutputDirectory
New-Item -ItemType Directory -Path $output -Force | Out-Null
$outputFile = Join-Path $output "$($record.evidenceId).json"
$record | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath $outputFile -Encoding utf8
Write-Host (
    'Physical-device draft created with pending journeys: {0}' -f $outputFile
) -ForegroundColor Yellow
