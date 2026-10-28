Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$deviceId = $env:LEXIQUEST_ANDROID_DEVICE_ID
if ([string]::IsNullOrWhiteSpace($deviceId)) {
    exit 64
}

$devicesJson = & flutter devices --machine
if ($LASTEXITCODE -ne 0) {
    exit 65
}

try {
    $parsedDevices = ConvertFrom-Json -InputObject ($devicesJson -join [Environment]::NewLine)
    $devices = @($parsedDevices)
}
catch {
    exit 65
}

$selectedDevice = @(
    $devices | Where-Object {
        $idProperty = $_.PSObject.Properties['id']
        $null -ne $idProperty -and [string]$idProperty.Value -eq $deviceId
    }
) | Select-Object -First 1
if ($null -eq $selectedDevice) {
    exit 65
}

$targetProperty = $selectedDevice.PSObject.Properties['targetPlatform']
$targetPlatform = if ($null -eq $targetProperty) {
    ''
}
else {
    [string]$targetProperty.Value
}
if (
    [string]::IsNullOrWhiteSpace($targetPlatform) -or
    -not $targetPlatform.ToLowerInvariant().StartsWith('android')
) {
    exit 66
}

$platformProperty = $selectedDevice.PSObject.Properties['platformType']
$platformType = if ($null -eq $platformProperty) {
    ''
}
else {
    [string]$platformProperty.Value
}
if (
    -not [string]::IsNullOrWhiteSpace($platformType) -and
    $platformType.ToLowerInvariant() -ne 'android'
) {
    exit 66
}

& flutter test -d $deviceId --no-pub --reporter compact `
    integration_test/field_trial_core_journey_test.dart
exit $LASTEXITCODE
