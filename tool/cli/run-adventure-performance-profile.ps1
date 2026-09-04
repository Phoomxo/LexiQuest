#Requires -Version 5.1
[CmdletBinding()]
param(
    [AllowEmptyString()][string]$DeviceId = '',
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ObjectPropertyValue {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Get-NullableBoolean {
    param([AllowNull()]$Value)

    if ($Value -is [bool]) {
        return $Value
    }
    if ($Value -is [string]) {
        $parsed = $false
        if ([bool]::TryParse($Value, [ref]$parsed)) {
            return $parsed
        }
    }
    return $null
}

function Test-PathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if ($fullPath.Equals(
        $fullRoot,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        return $true
    }
    $rootPrefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith(
        $rootPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Write-RunnerError {
    param([Parameter(Mandatory = $true)][string]$Message)
    [Console]::Error.WriteLine($Message)
}

if ([string]::IsNullOrWhiteSpace($DeviceId)) {
    Write-RunnerError 'Select an Android device explicitly with -DeviceId.'
    exit 64
}

$repositoryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\..')
).TrimEnd('\', '/')
$requiredEvidenceRoot = Join-Path `
    $repositoryRoot `
    'build\adventure-performance'
$selectedOutputDirectory = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $requiredEvidenceRoot
}
else {
    [System.IO.Path]::GetFullPath($OutputDirectory)
}
if (-not (Test-PathWithinRoot `
    -Path $selectedOutputDirectory `
    -Root $requiredEvidenceRoot
)) {
    Write-RunnerError (
        'Evidence output must stay beneath build/adventure-performance.'
    )
    exit 67
}

Push-Location $repositoryRoot
try {
    $devicesOutput = @(& flutter devices --machine)
    if ($LASTEXITCODE -ne 0) {
        Write-RunnerError 'Unable to enumerate Flutter devices.'
        exit 65
    }
    try {
        $parsedDevices = ConvertFrom-Json -InputObject (
            $devicesOutput -join [Environment]::NewLine
        )
        $devices = @($parsedDevices)
    }
    catch {
        Write-RunnerError 'Flutter device output was not valid JSON.'
        exit 65
    }

    $selectedDevice = @(
        $devices | Where-Object {
            [string](Get-ObjectPropertyValue $_ 'id') -eq $DeviceId
        }
    ) | Select-Object -First 1
    if ($null -eq $selectedDevice) {
        Write-RunnerError "Selected device is not connected: $DeviceId"
        exit 65
    }

    $targetPlatform = [string](
        Get-ObjectPropertyValue $selectedDevice 'targetPlatform'
    )
    $platformType = [string](
        Get-ObjectPropertyValue $selectedDevice 'platformType'
    )
    if (
        [string]::IsNullOrWhiteSpace($targetPlatform) -or
        -not $targetPlatform.ToLowerInvariant().StartsWith('android') -or
        (
            -not [string]::IsNullOrWhiteSpace($platformType) -and
            $platformType.ToLowerInvariant() -ne 'android'
        )
    ) {
        Write-RunnerError 'The selected device is not consistently Android.'
        exit 66
    }

    $isEmulator = Get-NullableBoolean (
        Get-ObjectPropertyValue $selectedDevice 'emulator'
    )
    $evidenceClass = if ($isEmulator -eq $true) {
        'emulator_rehearsal'
    }
    elseif ($isEmulator -eq $false) {
        'physical_device_measurement'
    }
    else {
        'unclassified_android_rehearsal'
    }
    $eligibleForPhysicalCertification = $isEmulator -eq $false

    $commitOutput = @(& git rev-parse HEAD)
    if ($LASTEXITCODE -ne 0 -or $commitOutput.Count -ne 1) {
        Write-RunnerError 'Unable to resolve the build commit identity.'
        exit 68
    }
    $commitSha = ([string]$commitOutput[0]).Trim().ToLowerInvariant()
    if ($commitSha -notmatch '^[0-9a-f]{40}$') {
        Write-RunnerError 'Git returned a non-canonical commit identity.'
        exit 68
    }
    $shortCommit = $commitSha.Substring(0, 12)
    $trackedChanges = @(& git status --porcelain --untracked-files=no)
    if ($LASTEXITCODE -ne 0) {
        Write-RunnerError 'Unable to inspect tracked worktree state.'
        exit 68
    }

    $versionMatch = Select-String `
        -LiteralPath (Join-Path $repositoryRoot 'pubspec.yaml') `
        -Pattern '^version:\s*(?<value>\S+)\s*$' | Select-Object -First 1
    if ($null -eq $versionMatch) {
        Write-RunnerError 'Unable to resolve the application build version.'
        exit 68
    }
    $applicationVersion = $versionMatch.Matches[0].Groups['value'].Value

    $flutterVersionOutput = @(& flutter --version --machine)
    if ($LASTEXITCODE -ne 0) {
        Write-RunnerError 'Unable to resolve the Flutter toolchain identity.'
        exit 68
    }
    try {
        $flutterVersion = ConvertFrom-Json -InputObject (
            $flutterVersionOutput -join [Environment]::NewLine
        )
    }
    catch {
        Write-RunnerError 'Flutter version output was not valid JSON.'
        exit 68
    }

    New-Item `
        -ItemType Directory `
        -Path $selectedOutputDirectory `
        -Force | Out-Null
    $timestamp = [DateTime]::UtcNow.ToString(
        'yyyyMMddTHHmmssfffZ',
        [Globalization.CultureInfo]::InvariantCulture
    )
    $safeDeviceId = [regex]::Replace($DeviceId, '[^A-Za-z0-9._-]', '_')
    $artifactStem = "adventure-performance-$timestamp-$shortCommit-$safeDeviceId"
    $integrationOutputPath = Join-Path `
        $selectedOutputDirectory `
        "$artifactStem.integration.json"
    $driveLogPath = Join-Path `
        $selectedOutputDirectory `
        "$artifactStem.drive.log"
    $evidencePath = Join-Path `
        $selectedOutputDirectory `
        "$artifactStem.evidence.json"

    $driveArguments = @(
        'drive',
        '--profile',
        '--no-dds',
        '-d',
        $DeviceId,
        '--no-pub',
        '--driver=test_driver/adventure_performance_profile_driver.dart',
        '--target=integration_test/adventure_performance_profile_test.dart'
    )
    $priorDriverOutput = $env:LEXIQUEST_ADVENTURE_PERFORMANCE_DRIVER_OUTPUT
    $priorDriveErrorActionPreference = $ErrorActionPreference
    $driveOutput = @()
    $driveExitCode = 69
    try {
        $env:LEXIQUEST_ADVENTURE_PERFORMANCE_DRIVER_OUTPUT = `
            $integrationOutputPath
        $ErrorActionPreference = 'Continue'
        $driveOutput = @(& flutter @driveArguments 2>&1)
        $driveExitCode = $LASTEXITCODE
    }
    catch {
        $driveOutput = @($_.Exception.ToString())
        $driveExitCode = 69
    }
    finally {
        $ErrorActionPreference = $priorDriveErrorActionPreference
        if ($null -eq $priorDriverOutput) {
            Remove-Item `
                -LiteralPath 'Env:LEXIQUEST_ADVENTURE_PERFORMANCE_DRIVER_OUTPUT' `
                -ErrorAction SilentlyContinue
        }
        else {
            $env:LEXIQUEST_ADVENTURE_PERFORMANCE_DRIVER_OUTPUT = `
                $priorDriverOutput
        }
    }
    $driveOutputText = @($driveOutput | ForEach-Object { [string]$_ }) `
        -join [Environment]::NewLine
    Write-Utf8NoBom -Path $driveLogPath -Content $driveOutputText
    foreach ($line in $driveOutput) {
        Write-Output ([string]$line)
    }

    $integrationOutputExists = Test-Path -LiteralPath $integrationOutputPath
    $integrationOutputError = $null
    $integrationResponse = $null
    $profile = $null
    $allBudgetsPassed = $null
    if ($integrationOutputExists) {
        try {
            $integrationResponse = Get-Content `
                -Raw `
                -LiteralPath $integrationOutputPath | ConvertFrom-Json
            $profile = Get-ObjectPropertyValue `
                $integrationResponse `
                'adventurePerformance'
            $budgetValue = Get-ObjectPropertyValue $profile 'allBudgetsPassed'
            if ($budgetValue -is [bool]) {
                $allBudgetsPassed = $budgetValue
            }
            else {
                $integrationOutputError = `
                    'allBudgetsPassed is missing or is not boolean.'
            }
        }
        catch {
            $integrationOutputError = $_.Exception.Message
        }
    }
    else {
        $integrationOutputError = 'Integration response file was not written.'
    }

    $resultStatus = if ($driveExitCode -ne 0) {
        'test_failed'
    }
    elseif ($null -ne $integrationOutputError -or $null -eq $profile) {
        'invalid_output'
    }
    elseif ($allBudgetsPassed -ne $true) {
        'budget_failed'
    }
    else {
        'passed'
    }

    $integrationHash = $null
    $integrationBytes = 0
    if ($integrationOutputExists) {
        $integrationHash = (
            Get-FileHash -LiteralPath $integrationOutputPath -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        $integrationBytes = (
            Get-Item -LiteralPath $integrationOutputPath
        ).Length
    }
    $deviceName = [string](Get-ObjectPropertyValue $selectedDevice 'name')
    $deviceOs = [string](Get-ObjectPropertyValue $selectedDevice 'sdk')
    if ([string]::IsNullOrWhiteSpace($deviceOs)) {
        $deviceOs = [string](
            Get-ObjectPropertyValue $selectedDevice 'operatingSystem'
        )
    }
    if ([string]::IsNullOrWhiteSpace($deviceOs)) {
        $deviceOs = 'unknown'
    }

    $evidence = [ordered]@{
        schemaVersion = 1
        recordedAtUtc = [DateTime]::UtcNow.ToString('o')
        evidenceClass = $evidenceClass
        certificationStatus = 'not_certified'
        eligibleForPhysicalCertification = $eligibleForPhysicalCertification
        source = [ordered]@{
            commitSha = $commitSha
            applicationVersion = $applicationVersion
            trackedWorktreeChangeCount = $trackedChanges.Count
        }
        device = [ordered]@{
            id = $DeviceId
            name = $deviceName
            os = $deviceOs
            targetPlatform = $targetPlatform
            platformType = $platformType
            isEmulator = $isEmulator
        }
        build = [ordered]@{
            mode = 'profile'
            flutterVersion = Get-ObjectPropertyValue `
                $flutterVersion `
                'frameworkVersion'
            flutterChannel = Get-ObjectPropertyValue $flutterVersion 'channel'
            flutterRevision = Get-ObjectPropertyValue `
                $flutterVersion `
                'frameworkRevision'
            dartSdkVersion = Get-ObjectPropertyValue `
                $flutterVersion `
                'dartSdkVersion'
        }
        command = [ordered]@{
            executable = 'flutter'
            arguments = $driveArguments
        }
        integrationOutput = [ordered]@{
            fileName = [System.IO.Path]::GetFileName($integrationOutputPath)
            sha256 = $integrationHash
            byteLength = $integrationBytes
            error = $integrationOutputError
        }
        profile = $profile
        result = [ordered]@{
            status = $resultStatus
            flutterDriveExitCode = $driveExitCode
            allBudgetsPassed = $allBudgetsPassed
        }
    }
    $evidenceJson = ConvertTo-Json -InputObject $evidence -Depth 30
    Write-Utf8NoBom -Path $evidencePath -Content $evidenceJson

    if ($evidenceClass -eq 'emulator_rehearsal') {
        Write-Output 'EMULATOR REHEARSAL ONLY; not physical-device certification.'
    }
    elseif ($evidenceClass -eq 'unclassified_android_rehearsal') {
        Write-Output (
            'UNCLASSIFIED ANDROID REHEARSAL ONLY; not physical-device ' +
            'certification.'
        )
    }
    else {
        Write-Output 'Physical-device measurement captured; not certified.'
    }
    Write-Output "Adventure performance evidence: $evidencePath"

    if ($driveExitCode -ne 0) {
        exit $driveExitCode
    }
    if ($resultStatus -eq 'invalid_output') {
        exit 69
    }
    if ($resultStatus -eq 'budget_failed') {
        exit 70
    }
    exit 0
}
finally {
    Pop-Location
}
