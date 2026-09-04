#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PassedCount = 0
$script:FailedCount = 0

function Write-Pass {
    param([Parameter(Mandatory = $true)][string]$Message)
    $script:PassedCount++
}

function Write-Fail {
    param([Parameter(Mandatory = $true)][string]$Message)
    $script:FailedCount++
    Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
}

function Assert-Equal {
    param(
        [AllowNull()]$Expected,
        [AllowNull()]$Actual,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Expected -eq $Actual) {
        Write-Pass $Message
    }
    else {
        Write-Fail "$Message Expected <$Expected>, actual <$Actual>."
    }
}

function Assert-True {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ([bool]$Value) {
        Write-Pass $Message
    }
    else {
        Write-Fail $Message
    }
}

function Restore-EnvironmentValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][string]$Value
    )

    if ($null -eq $Value) {
        Remove-Item -LiteralPath "Env:$Name" -ErrorAction SilentlyContinue
    }
    else {
        Set-Item -LiteralPath "Env:$Name" -Value $Value
    }
}

function Remove-VerifiedTestDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RequiredParent
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $resolvedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $resolvedParent = [System.IO.Path]::GetFullPath(
        $RequiredParent
    ).TrimEnd('\', '/')
    $requiredPrefix = $resolvedParent + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedPath.StartsWith(
        $requiredPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to remove test directory outside $resolvedParent."
    }
    Remove-Item -LiteralPath $resolvedPath -Recurse -Force
}

function Get-OnlyFile {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Filter
    )

    $files = @(Get-ChildItem -LiteralPath $Directory -Filter $Filter -File)
    Assert-Equal 1 $files.Count "Exactly one $Filter file must be written."
    if ($files.Count -ne 1) {
        throw "Expected exactly one $Filter file in $Directory."
    }
    return $files[0]
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$runner = Join-Path $repositoryRoot `
    'tool\cli\run-adventure-performance-profile.ps1'
if (-not (Test-Path -LiteralPath $runner)) {
    throw "Missing runner under test: $runner"
}

$evidenceRoot = Join-Path $repositoryRoot 'build\adventure-performance'
$temporaryRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) ('lexiquest-adventure-performance-contract-' + [guid]::NewGuid().ToString('N'))
$stubLog = Join-Path $temporaryRoot 'flutter-calls.log'
$originalPath = $env:PATH
$originalDevicesJson = $env:LEXIQUEST_STUB_DEVICES_JSON
$originalDriverResponse = $env:LEXIQUEST_STUB_DRIVER_RESPONSE
$originalDriveExitCode = $env:LEXIQUEST_STUB_DRIVE_EXIT_CODE
$originalStandardError = $env:LEXIQUEST_STUB_STDERR
$originalStubLog = $env:LEXIQUEST_STUB_LOG
$originalDriverOutput = $env:LEXIQUEST_ADVENTURE_PERFORMANCE_DRIVER_OUTPUT
$createdEvidenceDirectories = [System.Collections.Generic.List[string]]::new()
$failure = $null

try {
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    $flutterStub = Join-Path $temporaryRoot 'flutter.bat'
    @'
@echo off
if /I "%~1"=="devices" (
  powershell -NoProfile -Command "[Console]::Out.Write($env:LEXIQUEST_STUB_DEVICES_JSON)"
  exit /b 0
)
if /I "%~1"=="--version" (
  echo {"frameworkVersion":"3.44.7","channel":"stable","frameworkRevision":"stub-framework","dartSdkVersion":"3.12.2"}
  exit /b 0
)
if /I "%~1"=="drive" (
  >>"%LEXIQUEST_STUB_LOG%" echo %*
  powershell -NoProfile -Command "if (-not [string]::IsNullOrWhiteSpace($env:LEXIQUEST_ADVENTURE_PERFORMANCE_DRIVER_OUTPUT)) { [IO.File]::WriteAllText($env:LEXIQUEST_ADVENTURE_PERFORMANCE_DRIVER_OUTPUT, $env:LEXIQUEST_STUB_DRIVER_RESPONSE) }"
  powershell -NoProfile -Command "if (-not [string]::IsNullOrWhiteSpace($env:LEXIQUEST_STUB_STDERR)) { [Console]::Error.WriteLine($env:LEXIQUEST_STUB_STDERR) }"
  echo Stub Flutter Drive output.
  exit /b %LEXIQUEST_STUB_DRIVE_EXIT_CODE%
)
exit /b 90
'@ | Set-Content -LiteralPath $flutterStub -Encoding Ascii

    $env:PATH = "$temporaryRoot;$originalPath"
    $env:LEXIQUEST_STUB_LOG = $stubLog

    $passingProfile = [ordered]@{
        schemaVersion = 1
        profileId = 'adventure-performance-v1'
        sampleCount = 20
        allBudgetsPassed = $true
        metrics = [ordered]@{
            localEntryResolutionP95Ms = 1.25
            journeyProjectionP95Ms = 2.5
            firstMeaningfulRenderP95Ms = 140.0
            adventureSessionStartOverheadP95Ms = 0.75
            mapListFrameP95Ms = 8.2
            mapListLongFrameCount = 0
            mapListLongTaskCount = 0
        }
        learnerPause = [ordered]@{
            timeoutPolicy = 'none'
            observedPauseMs = 3000
            missionAvailableAfterPause = $true
        }
    }
    $passingResponse = ConvertTo-Json -InputObject ([ordered]@{
        adventurePerformance = $passingProfile
    }) -Depth 20 -Compress

    function Invoke-RunnerCase {
        param(
            [AllowEmptyString()][string]$DeviceId,
            [Parameter(Mandatory = $true)][object[]]$Devices,
            [Parameter(Mandatory = $true)][string]$CaseName,
            [string]$DriverResponse = $passingResponse,
            [int]$DriveExitCode = 0,
            [string]$StandardError = '',
            [string]$OutputDirectory
        )

        if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
            $OutputDirectory = Join-Path $evidenceRoot (
                'contract-' + $CaseName + '-' + [guid]::NewGuid().ToString('N')
            )
        }
        if ($OutputDirectory.StartsWith(
            [System.IO.Path]::GetFullPath($evidenceRoot),
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            $createdEvidenceDirectories.Add($OutputDirectory)
        }
        $env:LEXIQUEST_STUB_DEVICES_JSON = ConvertTo-Json `
            -InputObject $Devices `
            -Depth 10 `
            -Compress
        $env:LEXIQUEST_STUB_DRIVER_RESPONSE = $DriverResponse
        $env:LEXIQUEST_STUB_DRIVE_EXIT_CODE = [string]$DriveExitCode
        $env:LEXIQUEST_STUB_STDERR = $StandardError
        Remove-Item -LiteralPath $stubLog -ErrorAction SilentlyContinue

        if ([string]::IsNullOrEmpty($DeviceId)) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $runner `
                -OutputDirectory $OutputDirectory | Out-Null
        }
        else {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $runner `
                -DeviceId $DeviceId `
                -OutputDirectory $OutputDirectory | Out-Null
        }
        $exitCode = $LASTEXITCODE
        $calls = if (Test-Path -LiteralPath $stubLog) {
            @(Get-Content -LiteralPath $stubLog)
        }
        else {
            @()
        }
        return [pscustomobject]@{
            ExitCode = $exitCode
            Calls = $calls
            OutputDirectory = $OutputDirectory
        }
    }

    $emulator = Invoke-RunnerCase `
        -CaseName 'emulator' `
        -DeviceId 'emulator-5554' `
        -Devices @(
            @{
                id = 'emulator-5554'
                name = 'Pixel_7_API_35'
                targetPlatform = 'android-x64'
                platformType = 'android'
                sdk = 'Android 15 (API 35)'
                emulator = $true
            }
        )
    Assert-Equal 0 $emulator.ExitCode `
        'Passing emulator rehearsal must succeed.'
    Assert-Equal 1 @($emulator.Calls).Count `
        'Passing emulator rehearsal must invoke Flutter Drive once.'
    Assert-Equal `
        'drive --profile --no-dds -d emulator-5554 --no-pub --driver=test_driver/adventure_performance_profile_driver.dart --target=integration_test/adventure_performance_profile_test.dart' `
        @($emulator.Calls)[0] `
        'Runner must use the exact profile-mode, no-timeout integration command.'
    $emulatorEvidenceFile = Get-OnlyFile `
        -Directory $emulator.OutputDirectory `
        -Filter '*.evidence.json'
    $emulatorOutputFile = Get-OnlyFile `
        -Directory $emulator.OutputDirectory `
        -Filter '*.integration.json'
    $emulatorEvidence = Get-Content -Raw -LiteralPath (
        $emulatorEvidenceFile.FullName
    ) | ConvertFrom-Json
    Assert-Equal 'emulator_rehearsal' $emulatorEvidence.evidenceClass `
        'Emulator evidence must be labeled rehearsal-only.'
    Assert-Equal 'not_certified' $emulatorEvidence.certificationStatus `
        'Runner must never certify an emulator.'
    Assert-Equal $false $emulatorEvidence.eligibleForPhysicalCertification `
        'Emulator evidence must not be eligible for physical certification.'
    Assert-Equal 'profile' $emulatorEvidence.build.mode `
        'Evidence must record the profile build mode.'
    Assert-Equal 'Android 15 (API 35)' $emulatorEvidence.device.os `
        'Evidence must record selected-device OS identity.'
    Assert-Equal 'adventure-performance-v1' $emulatorEvidence.profile.profileId `
        'Evidence must preserve the integration profile identity.'
    Assert-Equal 'passed' $emulatorEvidence.result.status `
        'Passing metrics and test process must produce passed evidence.'
    Assert-True ($emulatorEvidence.source.commitSha -match '^[0-9a-f]{40}$') `
        'Evidence must record a full commit SHA.'
    Assert-True ($emulatorEvidence.integrationOutput.sha256 -match '^[0-9a-f]{64}$') `
        'Evidence must bind the captured integration JSON by SHA-256.'
    Assert-True ($emulatorOutputFile.Length -gt 0) `
        'Captured integration output must be non-empty.'

    $stderrWarning = Invoke-RunnerCase `
        -CaseName 'stderr-warning' `
        -DeviceId 'emulator-5554' `
        -StandardError 'harmless Flutter build warning' `
        -Devices @(
            @{
                id = 'emulator-5554'
                targetPlatform = 'android-x64'
                platformType = 'android'
                emulator = $true
            }
        )
    Assert-Equal 0 $stderrWarning.ExitCode `
        'Native stderr must not override a successful Flutter exit code.'
    $stderrEvidenceFile = Get-OnlyFile `
        -Directory $stderrWarning.OutputDirectory `
        -Filter '*.evidence.json'
    $stderrEvidence = Get-Content -Raw -LiteralPath (
        $stderrEvidenceFile.FullName
    ) | ConvertFrom-Json
    Assert-Equal 'passed' $stderrEvidence.result.status `
        'Successful Flutter output with warnings must remain passed evidence.'

    $physical = Invoke-RunnerCase `
        -CaseName 'physical' `
        -DeviceId 'R58M12345AB' `
        -Devices @(
            @{
                id = 'R58M12345AB'
                name = 'Galaxy S23'
                targetPlatform = 'android-arm64'
                platformType = 'android'
                sdk = 'Android 14 (API 34)'
                emulator = $false
            }
        )
    Assert-Equal 0 $physical.ExitCode `
        'Passing physical-device measurement must succeed.'
    $physicalEvidenceFile = Get-OnlyFile `
        -Directory $physical.OutputDirectory `
        -Filter '*.evidence.json'
    $physicalEvidence = Get-Content -Raw -LiteralPath (
        $physicalEvidenceFile.FullName
    ) | ConvertFrom-Json
    Assert-Equal 'physical_device_measurement' $physicalEvidence.evidenceClass `
        'Explicit physical metadata must remain distinct from emulator evidence.'
    Assert-Equal $true $physicalEvidence.eligibleForPhysicalCertification `
        'Explicit physical metadata may be considered for certification.'
    Assert-Equal 'not_certified' $physicalEvidence.certificationStatus `
        'A successful runner invocation alone must not claim certification.'

    $unclassified = Invoke-RunnerCase `
        -CaseName 'unclassified' `
        -DeviceId 'android-unknown' `
        -Devices @(
            @{
                id = 'android-unknown'
                name = 'Android Device'
                targetPlatform = 'android-arm64'
                platformType = 'android'
                sdk = 'Android (unknown API)'
            }
        )
    Assert-Equal 0 $unclassified.ExitCode `
        'Unclassified Android hardware may run as rehearsal evidence.'
    $unclassifiedEvidenceFile = Get-OnlyFile `
        -Directory $unclassified.OutputDirectory `
        -Filter '*.evidence.json'
    $unclassifiedEvidence = Get-Content -Raw -LiteralPath (
        $unclassifiedEvidenceFile.FullName
    ) | ConvertFrom-Json
    Assert-Equal `
        'unclassified_android_rehearsal' `
        $unclassifiedEvidence.evidenceClass `
        'Missing emulator metadata must fail closed to rehearsal classification.'
    Assert-Equal $false $unclassifiedEvidence.eligibleForPhysicalCertification `
        'Unclassified Android hardware must not be certification eligible.'

    $failingProfile = [ordered]@{}
    foreach ($entry in $passingProfile.GetEnumerator()) {
        $failingProfile[$entry.Key] = $entry.Value
    }
    $failingProfile['allBudgetsPassed'] = $false
    $budgetFailureResponse = ConvertTo-Json -InputObject ([ordered]@{
        adventurePerformance = $failingProfile
    }) -Depth 20 -Compress
    $budgetFailure = Invoke-RunnerCase `
        -CaseName 'budget-failure' `
        -DeviceId 'emulator-5554' `
        -DriverResponse $budgetFailureResponse `
        -Devices @(
            @{
                id = 'emulator-5554'
                targetPlatform = 'android-x64'
                platformType = 'android'
                emulator = $true
            }
        )
    Assert-Equal 70 $budgetFailure.ExitCode `
        'Runner must fail when a reported budget fails despite process success.'
    $budgetEvidenceFile = Get-OnlyFile `
        -Directory $budgetFailure.OutputDirectory `
        -Filter '*.evidence.json'
    $budgetEvidence = Get-Content -Raw -LiteralPath (
        $budgetEvidenceFile.FullName
    ) | ConvertFrom-Json
    Assert-Equal 'budget_failed' $budgetEvidence.result.status `
        'Budget failure must be explicit in evidence.'

    $childFailure = Invoke-RunnerCase `
        -CaseName 'child-failure' `
        -DeviceId 'emulator-5554' `
        -DriveExitCode 23 `
        -Devices @(
            @{
                id = 'emulator-5554'
                targetPlatform = 'android-x64'
                platformType = 'android'
                emulator = $true
            }
        )
    Assert-Equal 23 $childFailure.ExitCode `
        'Flutter Drive failure must propagate unchanged.'
    $childEvidenceFile = Get-OnlyFile `
        -Directory $childFailure.OutputDirectory `
        -Filter '*.evidence.json'
    $childEvidence = Get-Content -Raw -LiteralPath (
        $childEvidenceFile.FullName
    ) | ConvertFrom-Json
    Assert-Equal 'test_failed' $childEvidence.result.status `
        'Child failure must be explicit in bounded evidence.'

    foreach ($rejected in @(
        @{
            Name = 'missing-device'
            DeviceId = 'not-connected'
            Devices = @(@{ id = 'emulator-5554'; targetPlatform = 'android-x64' })
            ExitCode = 65
        },
        @{
            Name = 'windows'
            DeviceId = 'windows'
            Devices = @(@{ id = 'windows'; targetPlatform = 'windows-x64' })
            ExitCode = 66
        },
        @{
            Name = 'contradictory-platform'
            DeviceId = 'device-one'
            Devices = @(
                @{
                    id = 'device-one'
                    targetPlatform = 'android-arm64'
                    platformType = 'windows'
                }
            )
            ExitCode = 66
        }
    )) {
        $result = Invoke-RunnerCase `
            -CaseName $rejected.Name `
            -DeviceId $rejected.DeviceId `
            -Devices $rejected.Devices
        Assert-Equal $rejected.ExitCode $result.ExitCode `
            "$($rejected.Name) must fail closed."
        Assert-Equal 0 @($result.Calls).Count `
            "$($rejected.Name) must fail before Flutter Drive."
    }

    $missingId = Invoke-RunnerCase `
        -CaseName 'missing-id' `
        -DeviceId '' `
        -Devices @(@{ id = 'emulator-5554'; targetPlatform = 'android-x64' })
    Assert-Equal 64 $missingId.ExitCode `
        'Missing explicit device ID must fail closed.'
    Assert-Equal 0 @($missingId.Calls).Count `
        'Missing explicit device ID must fail before Flutter Drive.'

    $outsideOutput = Join-Path $temporaryRoot 'outside-evidence'
    $outside = Invoke-RunnerCase `
        -CaseName 'outside-output' `
        -DeviceId 'emulator-5554' `
        -OutputDirectory $outsideOutput `
        -Devices @(
            @{
                id = 'emulator-5554'
                targetPlatform = 'android-x64'
                platformType = 'android'
                emulator = $true
            }
        )
    Assert-Equal 67 $outside.ExitCode `
        'Evidence output outside build/adventure-performance must be rejected.'
    Assert-Equal 0 @($outside.Calls).Count `
        'Unsafe evidence path must fail before Flutter Drive.'
}
catch {
    $failure = $_
}
finally {
    Restore-EnvironmentValue -Name 'PATH' -Value $originalPath
    Restore-EnvironmentValue `
        -Name 'LEXIQUEST_STUB_DEVICES_JSON' `
        -Value $originalDevicesJson
    Restore-EnvironmentValue `
        -Name 'LEXIQUEST_STUB_DRIVER_RESPONSE' `
        -Value $originalDriverResponse
    Restore-EnvironmentValue `
        -Name 'LEXIQUEST_STUB_DRIVE_EXIT_CODE' `
        -Value $originalDriveExitCode
    Restore-EnvironmentValue `
        -Name 'LEXIQUEST_STUB_STDERR' `
        -Value $originalStandardError
    Restore-EnvironmentValue -Name 'LEXIQUEST_STUB_LOG' -Value $originalStubLog
    Restore-EnvironmentValue `
        -Name 'LEXIQUEST_ADVENTURE_PERFORMANCE_DRIVER_OUTPUT' `
        -Value $originalDriverOutput
    foreach ($directory in $createdEvidenceDirectories) {
        Remove-VerifiedTestDirectory `
            -Path $directory `
            -RequiredParent $evidenceRoot
    }
    Remove-VerifiedTestDirectory `
        -Path $temporaryRoot `
        -RequiredParent ([System.IO.Path]::GetTempPath())
}

if ($null -ne $failure) {
    throw $failure
}

$total = $script:PassedCount + $script:FailedCount
Write-Output (
    'Adventure performance runner tests: {0} passed, {1} failed (of {2})' -f `
        $script:PassedCount,
        $script:FailedCount,
        $total
)
if ($script:FailedCount -gt 0) {
    exit 1
}
exit 0
