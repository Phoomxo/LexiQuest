[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$gradlePath = Join-Path $repositoryRoot 'android\app\build.gradle.kts'
$dartPath = Join-Path $repositoryRoot 'lib\device\device_capability_probe.dart'
$activityPath = Join-Path $repositoryRoot 'android\app\src\main\kotlin\com\lexiquest\app\MainActivity.kt'
$pluginPath = Join-Path $repositoryRoot 'android\app\src\main\kotlin\com\lexiquest\app\DeviceCapabilityPlugin.kt'

function Read-Source {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return [System.IO.File]::ReadAllText($Path)
    }
    return ''
}

function Get-DartSnapshotKeys {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    $setMatch = [regex]::Match(
        $Source,
        '(?ms)static\s+const\s+Set<String>\s+_snapshotKeys\s*=\s*<String>\s*\{(?<body>.*?)^\s*\};\r?$'
    )
    if (-not $setMatch.Success) {
        return @()
    }
    return @(
        [regex]::Matches(
            $setMatch.Groups['body'].Value,
            "'(?<key>[A-Za-z][A-Za-z0-9]*)'\s*,"
        ) |
            ForEach-Object { $_.Groups['key'].Value }
    )
}

function Get-KotlinResultMapKeys {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    $mapMatch = [regex]::Match(
        $Source,
        '(?ms)return\s+mapOf<String,\s*Any\?>\s*\((?<body>.*?)^ {8}\)\r?$',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    if (-not $mapMatch.Success) {
        return @()
    }
    return @(
        [regex]::Matches(
            $mapMatch.Groups['body'].Value,
            '"(?<key>[A-Za-z][A-Za-z0-9]*)"\s+to\s+'
        ) |
            ForEach-Object { $_.Groups['key'].Value }
    )
}

function Test-SnapshotKeyParity {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$DartKeys,
        [Parameter(Mandatory = $true)]
        [string[]]$KotlinKeys
    )

    if ($DartKeys.Count -eq 0 -or
        $DartKeys.Count -ne @($DartKeys | Sort-Object -Unique).Count -or
        $KotlinKeys.Count -ne @($KotlinKeys | Sort-Object -Unique).Count -or
        $DartKeys.Count -ne $KotlinKeys.Count) {
        return $false
    }
    return @(
        Compare-Object $DartKeys $KotlinKeys -CaseSensitive
    ).Count -eq 0
}

function Test-KotlinMemoryMappings {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    return (
        $Source -match 'ActivityManager\.MemoryInfo\s*\(\s*\)\.also\s*\(\s*activityManager::getMemoryInfo\s*\)' -and
        $Source -match '"memoryClassMb"\s+to\s+activityManager\.memoryClass(?:\s*,)?'
    )
}

$gradle = Read-Source $gradlePath
$dart = Read-Source $dartPath
$activity = Read-Source $activityPath
$plugin = Read-Source $pluginPath

$channelName = 'com.lexiquest.app/device_capabilities'
$methodName = 'snapshot'
$dartSnapshotKeys = @(Get-DartSnapshotKeys -Source $dart)
$pluginMapKeys = @(Get-KotlinResultMapKeys -Source $plugin)

$dartParserDefined =
    $null -ne (Get-Command Get-DartSnapshotKeys -ErrorAction SilentlyContinue)
$parityFunctionDefined =
    $null -ne (Get-Command Test-SnapshotKeyParity -ErrorAction SilentlyContinue)
$mismatchFixtureRejected = $false
if ($dartParserDefined -and $parityFunctionDefined) {
    $mismatchDart = @'
static const Set<String> _snapshotKeys = <String>{
  'alpha',
  'beta',
};
'@
$mismatchKotlin = @'
return mapOf<String, Any?>(
    "alpha" to 1,
    "gamma" to 2,
        )
'@
    $mismatchDartKeys = @(Get-DartSnapshotKeys -Source $mismatchDart)
    $mismatchKotlinKeys = @(Get-KotlinResultMapKeys -Source $mismatchKotlin)
    $mismatchFixtureRejected =
        $mismatchDartKeys.Count -eq 2 -and
        $mismatchKotlinKeys.Count -eq 2 -and
        -not (
        Test-SnapshotKeyParity `
            -DartKeys $mismatchDartKeys `
            -KotlinKeys $mismatchKotlinKeys
        )
}

$memoryContractDefined =
    $null -ne (
        Get-Command Test-KotlinMemoryMappings -ErrorAction SilentlyContinue
    )
$missingPopulationFixtureRejected = $false
$hardCodedMemoryClassFixtureRejected = $false
if ($memoryContractDefined) {
    $validMemoryMapping = @'
val memoryInfo =
    ActivityManager.MemoryInfo().also(activityManager::getMemoryInfo)
return mapOf<String, Any?>(
    "memoryClassMb" to activityManager.memoryClass,
        )
'@
    $missingPopulationCall = @'
val memoryInfo = ActivityManager.MemoryInfo()
return mapOf<String, Any?>(
    "memoryClassMb" to activityManager.memoryClass,
        )
'@
    $hardCodedMemoryClass = @'
val memoryInfo =
    ActivityManager.MemoryInfo().also(activityManager::getMemoryInfo)
return mapOf<String, Any?>(
    "memoryClassMb" to 512,
        )
'@
    $validMemoryMappingAccepted =
        Test-KotlinMemoryMappings -Source $validMemoryMapping
    $missingPopulationFixtureRejected =
        $validMemoryMappingAccepted -and
        -not (Test-KotlinMemoryMappings -Source $missingPopulationCall)
    $hardCodedMemoryClassFixtureRejected =
        $validMemoryMappingAccepted -and
        -not (Test-KotlinMemoryMappings -Source $hardCodedMemoryClass)
}

$checks = [ordered]@{
    'Contract derives its schema authority from Dart source' =
        $dartParserDefined
    'Contract self-test rejects a Dart and Kotlin key mismatch' =
        $mismatchFixtureRejected
    'Android minimum SDK is explicitly API 29' =
        $gradle -match '(?m)^\s*minSdk\s*=\s*29\s*$'
    'Dart declares the exact capability channel' =
        ([regex]::Matches($dart, [regex]::Escape("'$channelName'"))).Count -eq 1
    'Kotlin declares the exact capability channel' =
        ([regex]::Matches($plugin, [regex]::Escape("""$channelName"""))).Count -eq 1
    'Dart invokes only the exact snapshot method' =
        $dart -match "_snapshotMethod\s*=\s*'$methodName'"
    'Kotlin handles only the exact snapshot method' =
        $plugin -match "METHOD_SNAPSHOT\s*=\s*""$methodName"""
    'MainActivity overrides configureFlutterEngine' =
        $activity -match 'override\s+fun\s+configureFlutterEngine\s*\(\s*flutterEngine:\s*FlutterEngine\s*\)'
    'MainActivity calls the superclass engine configuration' =
        ([regex]::Matches(
            $activity,
            'super\.configureFlutterEngine\s*\(\s*flutterEngine\s*\)'
        )).Count -eq 1
    'MainActivity registers exactly one capability plugin' =
        ([regex]::Matches(
            $activity,
            'flutterEngine\.plugins\.add\s*\(\s*DeviceCapabilityPlugin\s*\(\s*\)\s*\)'
        )).Count -eq 1
    'Plugin reads ActivityManager MemoryInfo' =
        $plugin -match 'ActivityManager\.MemoryInfo\s*\('
    'Plugin populates MemoryInfo through the exact ActivityManager call' =
        $plugin -match 'ActivityManager\.MemoryInfo\s*\(\s*\)\.also\s*\(\s*activityManager::getMemoryInfo\s*\)'
    'Plugin maps memoryClassMb directly from ActivityManager' =
        $plugin -match '"memoryClassMb"\s+to\s+activityManager\.memoryClass(?:\s*,)?'
    'Contract self-test rejects unpopulated MemoryInfo construction' =
        $missingPopulationFixtureRejected
    'Contract self-test rejects a hard-coded memoryClassMb value' =
        $hardCodedMemoryClassFixtureRejected
    'Plugin fails redacted when ActivityManager is unavailable' =
        $plugin -match '(?ms)as\?\s*ActivityManager\s*\r?\n\s*\?:\s*throw\s+DeviceCapabilityUnavailableException\s*\(' -and
        $plugin -notmatch 'activityManager\?\.memoryClass\s*\?:\s*0'
    'Plugin reports native failures with only a stable error code' =
        $plugin -match 'result\.error\s*\(\s*"capability-unavailable"\s*,\s*null\s*,\s*null\s*\)'
    'Plugin reads available memory and converts it to whole MiB' =
        $plugin -match '"availableMemoryMb"\s+to\s+memoryInfo\.availMem\.let\(::bytesToWholeMiB\)' -and
        $plugin -match 'bytesToWholeMiB\s*\(\s*bytes:\s*Long\s*\):\s*Long\s*=\s*bytes\s*/\s*BYTES_PER_MIB' -and
        $plugin -match 'BYTES_PER_MIB\s*=\s*1024L\s*\*\s*1024L'
    'Plugin retains free storage in bytes' =
        $plugin -match '"freeStorageBytes"\s+to\s+StatFs\s*\(\s*context\.filesDir\.absolutePath\s*\)\.availableBytes' -and
        $plugin -notmatch '"freeStorageBytes"\s+to[^\r\n]*bytesToWholeMiB'
    'Plugin reads power-save mode' =
        $plugin -match '\.isPowerSaveMode\b'
    'Plugin reads current thermal status' =
        $plugin -match '\.currentThermalStatus\b'
    'Plugin reads supported ABI data' =
        $plugin -match 'Build\.SUPPORTED_ABIS\b'
    'Plugin reads device configuration GPU API data' =
        $plugin -match '\.deviceConfigurationInfo\b' -and
        $plugin -match '\.reqGlEsVersion\b'
    'Plugin maps every thermal constant to the exact stable name' =
        $plugin -match 'THERMAL_STATUS_NONE\s*->\s*"nominal"' -and
        $plugin -match '(?ms)THERMAL_STATUS_LIGHT\s*,\s*\r?\n\s*PowerManager\.THERMAL_STATUS_MODERATE\s*,?\s*\r?\n\s*->\s*"fair"' -and
        $plugin -match 'THERMAL_STATUS_SEVERE\s*->\s*"serious"' -and
        $plugin -match '(?ms)THERMAL_STATUS_CRITICAL\s*,\s*\r?\n\s*PowerManager\.THERMAL_STATUS_EMERGENCY\s*,\s*\r?\n\s*PowerManager\.THERMAL_STATUS_SHUTDOWN\s*,?\s*\r?\n\s*->\s*"critical"' -and
        $plugin -match 'else\s*->\s*"unknown"'
    'Plugin returns exactly the Dart snapshot keys' =
        (Test-SnapshotKeyParity `
            -DartKeys $dartSnapshotKeys `
            -KotlinKeys $pluginMapKeys)
    'Plugin does not read device model or manufacturer' =
        $plugin -notmatch 'Build\.(?:MODEL|MANUFACTURER)\b'
    'Plugin does not read Android ID or serial identifiers' =
        $plugin -notmatch '(?:Settings\.Secure\.ANDROID_ID|Build\.(?:SERIAL|getSerial)\b)'
    'Plugin contains no logging call' =
        $plugin -notmatch '(?m)\b(?:Log\.[vdiewtf]|println|printStackTrace)\s*\('
    'Plugin contains no network API' =
        $plugin -notmatch '\b(?:HttpURLConnection|URLConnection|OkHttpClient|Socket|URL)\b'
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value })
foreach ($check in $checks.GetEnumerator()) {
    $state = if ($check.Value) { 'PASS' } else { 'FAIL' }
    Write-Host "$state - $($check.Key)"
}
Write-Host (
    'Android device capability contract: {0} passed, {1} failed' -f
    ($checks.Count - $failed.Count),
    $failed.Count
)
if ($failed.Count -gt 0) {
    exit 1
}
Write-Host 'PASS'
exit 0
