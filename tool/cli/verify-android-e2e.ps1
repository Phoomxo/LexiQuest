#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$DeviceId = $env:LEXIQUEST_ANDROID_DEVICE_ID
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($DeviceId)) {
    $devices = @(
        & adb devices |
            Select-Object -Skip 1 |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^(?<Id>\S+)\s+device$' } |
            ForEach-Object { $Matches['Id'] }
    )
    if ($devices.Count -ne 1) {
        throw (
            'Android E2E requires exactly one ready device or ' +
            'LEXIQUEST_ANDROID_DEVICE_ID.'
        )
    }
    $DeviceId = $devices[0]
}

$readyState = (& adb -s $DeviceId get-state 2>$null | Select-Object -First 1)
$bootCompleted = (& adb -s $DeviceId shell getprop sys.boot_completed 2>$null | Select-Object -First 1)
if ($readyState -ne 'device' -or $bootCompleted.Trim() -ne '1') {
    throw ('Android device is not ready: ' + $DeviceId)
}

& flutter test `
    integration_test/production_learning_flow_test.dart `
    -d $DeviceId `
    --reporter expanded
exit [int]$LASTEXITCODE
