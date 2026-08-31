Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message Expected <$Expected>, actual <$Actual>."
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
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

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$smokeScript = Join-Path $repositoryRoot 'tool\cli\run-android-smoke.ps1'
$temporaryRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) ('lexiquest-android-smoke-contract-' + [guid]::NewGuid().ToString('N'))
$stubLog = Join-Path $temporaryRoot 'flutter-calls.log'
$originalPath = $env:PATH
$originalDeviceId = $env:LEXIQUEST_ANDROID_DEVICE_ID
$originalDevicesJson = $env:LEXIQUEST_STUB_DEVICES_JSON
$originalTestExitCode = $env:LEXIQUEST_STUB_TEST_EXIT_CODE
$originalStubLog = $env:LEXIQUEST_STUB_LOG
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
if /I "%~1"=="test" (
  >>"%LEXIQUEST_STUB_LOG%" echo %*
  exit /b %LEXIQUEST_STUB_TEST_EXIT_CODE%
)
exit /b 90
'@ | Set-Content -LiteralPath $flutterStub -Encoding Ascii

    $env:PATH = "$temporaryRoot;$originalPath"
    $env:LEXIQUEST_STUB_LOG = $stubLog

    function Invoke-SmokeCase {
        param(
            [AllowNull()][string]$DeviceId,
            [Parameter(Mandatory = $true)][object[]]$Devices,
            [int]$TestExitCode = 0
        )

        if ($null -eq $DeviceId) {
            Remove-Item Env:LEXIQUEST_ANDROID_DEVICE_ID -ErrorAction SilentlyContinue
        }
        else {
            $env:LEXIQUEST_ANDROID_DEVICE_ID = $DeviceId
        }
        $env:LEXIQUEST_STUB_DEVICES_JSON = ConvertTo-Json `
            -InputObject $Devices `
            -Compress
        $env:LEXIQUEST_STUB_TEST_EXIT_CODE = [string]$TestExitCode
        Remove-Item -LiteralPath $stubLog -ErrorAction SilentlyContinue

        & powershell -NoProfile -ExecutionPolicy Bypass -File $smokeScript
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
        }
    }

    $missingPlatformType = Invoke-SmokeCase `
        -DeviceId 'V2041' `
        -Devices @(
            @{
                id = 'V2041'
                targetPlatform = 'android-arm64'
            }
        )
    Assert-Equal 0 $missingPlatformType.ExitCode `
        'Android target without platformType must be admitted.'
    Assert-Equal 1 @($missingPlatformType.Calls).Count `
        'Accepted Android device must invoke exactly one test.'
    Assert-Equal `
        'test -d V2041 --no-pub --reporter compact integration_test/field_trial_core_journey_test.dart' `
        @($missingPlatformType.Calls)[0] `
        'Android smoke must invoke the exact bounded journey.'

    $explicitAndroid = Invoke-SmokeCase `
        -DeviceId 'emulator-5554' `
        -Devices @(
            @{
                id = 'emulator-5554'
                targetPlatform = 'android-x64'
                platformType = 'android'
            }
        )
    Assert-Equal 0 $explicitAndroid.ExitCode `
        'Consistent explicit Android metadata must be admitted.'
    Assert-Equal 1 @($explicitAndroid.Calls).Count `
        'Explicit Android metadata must invoke exactly one test.'

    foreach ($rejected in @(
        @{
            Name = 'Windows'
            DeviceId = 'windows'
            Devices = @(@{ id = 'windows'; targetPlatform = 'windows-x64' })
        },
        @{
            Name = 'Web'
            DeviceId = 'chrome'
            Devices = @(
                @{
                    id = 'chrome'
                    targetPlatform = 'web-javascript'
                    platformType = 'web'
                }
            )
        },
        @{
            Name = 'Contradictory platformType'
            DeviceId = 'contradictory'
            Devices = @(
                @{
                    id = 'contradictory'
                    targetPlatform = 'android-arm64'
                    platformType = 'windows'
                }
            )
        }
    )) {
        $result = Invoke-SmokeCase `
            -DeviceId $rejected.DeviceId `
            -Devices $rejected.Devices
        Assert-Equal 66 $result.ExitCode `
            "$($rejected.Name) metadata must fail closed."
        Assert-Equal 0 @($result.Calls).Count `
            "$($rejected.Name) metadata must fail before flutter test."
    }

    $missingEnvironmentId = Invoke-SmokeCase `
        -DeviceId $null `
        -Devices @(@{ id = 'V2041'; targetPlatform = 'android-arm64' })
    Assert-Equal 64 $missingEnvironmentId.ExitCode `
        'Missing selected device ID must fail closed.'
    Assert-Equal 0 @($missingEnvironmentId.Calls).Count `
        'Missing selected device ID must fail before flutter test.'

    $missingSelectedDevice = Invoke-SmokeCase `
        -DeviceId 'not-connected' `
        -Devices @(@{ id = 'V2041'; targetPlatform = 'android-arm64' })
    Assert-Equal 65 $missingSelectedDevice.ExitCode `
        'Unknown selected device ID must fail closed.'
    Assert-Equal 0 @($missingSelectedDevice.Calls).Count `
        'Unknown selected device ID must fail before flutter test.'

    $childFailure = Invoke-SmokeCase `
        -DeviceId 'V2041' `
        -Devices @(@{ id = 'V2041'; targetPlatform = 'android-arm64' }) `
        -TestExitCode 23
    Assert-Equal 23 $childFailure.ExitCode `
        'The bounded Flutter test exit code must propagate unchanged.'
    Assert-Equal 1 @($childFailure.Calls).Count `
        'A failing admitted child still runs exactly once.'
}
catch {
    $failure = $_
}
finally {
    Restore-EnvironmentValue -Name 'PATH' -Value $originalPath
    Restore-EnvironmentValue `
        -Name 'LEXIQUEST_ANDROID_DEVICE_ID' `
        -Value $originalDeviceId
    Restore-EnvironmentValue `
        -Name 'LEXIQUEST_STUB_DEVICES_JSON' `
        -Value $originalDevicesJson
    Restore-EnvironmentValue `
        -Name 'LEXIQUEST_STUB_TEST_EXIT_CODE' `
        -Value $originalTestExitCode
    Restore-EnvironmentValue -Name 'LEXIQUEST_STUB_LOG' -Value $originalStubLog
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force `
        -ErrorAction SilentlyContinue
}

Assert-Equal $originalPath $env:PATH 'PATH must be restored after the test.'
Assert-True `
    (-not (Test-Path -LiteralPath $temporaryRoot)) `
    'Temporary Android smoke test files must be removed.'
if ($null -ne $failure) {
    throw $failure
}

Write-Output 'Android smoke entrypoint contract passed.'
