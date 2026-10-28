#Requires -Version 5.1
<#
.SYNOPSIS
    Dependency-free tests for the pure LexiQuest Android command builder.

.DESCRIPTION
    Tests never launch Flutter, an emulator, the network, a GPU, Git, nvidia-smi,
    or query live processes. All command inputs are supplied by the caller.
#>
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:PassedCount = 0
$script:FailedCount = 0

function Write-Pass {
    param([string]$Message)
    $script:PassedCount++
}

function Write-Fail {
    param([string]$Message)
    $script:FailedCount++
    Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
}

function Assert-True {
    param([object]$Value, [string]$Message)
    if ($Value) { Write-Pass $Message } else { Write-Fail $Message }
}

function Assert-ContainsString {
    param([string]$Haystack, [string]$Needle, [string]$Message)
    if (-not [string]::IsNullOrEmpty($Haystack) -and $Haystack.Contains($Needle)) {
        Write-Pass $Message
    } else {
        Write-Fail ($Message + " (missing '" + $Needle + "')")
    }
}

function Get-MemberValue {
    param([object]$InputObject, [string]$Name)
    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Assert-PropertyExists {
    param([object]$InputObject, [string]$Name, [string]$Message)
    if ($null -eq $InputObject -or $null -eq $InputObject.PSObject.Properties[$Name]) {
        Write-Fail ($Message + " (missing property '$Name')")
    } else {
        Write-Pass $Message
    }
}

function Invoke-ExpectThrow {
    param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if ($threw) { Write-Pass $Message } else { Write-Fail ($Message + ' (expected throw)') }
}

function Invoke-ExpectNoThrow {
    param([scriptblock]$Action, [string]$Message)
    try { & $Action | Out-Null } catch {
        Write-Fail ($Message + ' (threw unexpectedly)')
        return
    }
    Write-Pass $Message
}

function New-ValidCommand {
    param(
        [string]$Version = '1.0.0+1',
        [string]$BuildId = '22944f2',
        [string]$DeviceId = 'emulator-5554',
        [string]$LanHost = '192.168.1.20',
        [int]$VoicePort = 8001,
        [int]$AiPort = 8000
    )
    return (New-LexiQuestAndroidRunCommand `
        -Version $Version `
        -BuildId $BuildId `
        -DeviceId $DeviceId `
        -LanHost $LanHost `
        -VoicePort $VoicePort `
        -AiPort $AiPort)
}

function Invoke-CommandConstructionTests {
    $result = New-ValidCommand
    Assert-PropertyExists $result 'Exe' 'command exposes Exe'
    Assert-PropertyExists $result 'Arguments' 'command exposes Arguments'
    Assert-PropertyExists $result 'CommandString' 'command exposes CommandString'

    Assert-ContainsString ([string](Get-MemberValue $result 'Exe')) 'flutter' 'Exe targets Flutter'
    $arguments = Get-MemberValue $result 'Arguments'
    Assert-True ($arguments -is [System.Array]) 'Arguments is an array'
    Assert-True ($arguments -contains 'run') 'targets flutter run'
    Assert-True ($arguments -contains '-d') 'uses an explicit device'
    Assert-True ($arguments -contains 'emulator-5554') 'carries device id'
    Assert-True ($arguments -contains '--dart-define=LEXIQUEST_BUILD_ID=22944f2') 'emits build id'
    Assert-True ($arguments -contains '--dart-define=LEXIQUEST_VERSION=1.0.0+1') 'emits version'
    Assert-True ($arguments -contains '--dart-define=LEXIQUEST_VOICE_API_URL=http://192.168.1.20:8001') 'emits voice URL'
    Assert-True ($arguments -contains '--dart-define=LEXIQUEST_AI_API_URL=http://192.168.1.20:8000') 'emits AI URL'
}

function Invoke-HostValidationTests {
    foreach ($candidate in '192.168.1.20', '10.0.2.2', '127.0.0.1') {
        $lanHost = $candidate
        Invoke-ExpectNoThrow { New-ValidCommand -LanHost $lanHost } ("accepts private host: " + $candidate)
    }
    foreach ($candidate in '', '   ', '8.8.8.8', 'example.com', '256.1.1.1', '192.168.1.300', '192.168.1') {
        $lanHost = $candidate
        Invoke-ExpectThrow { New-ValidCommand -LanHost $lanHost } ("rejects invalid host: " + $candidate)
    }
}

function Invoke-PortValidationTests {
    foreach ($candidate in 1, 8000, 65535) {
        $port = $candidate
        Invoke-ExpectNoThrow { New-ValidCommand -VoicePort $port -AiPort $port } ("accepts port: " + $candidate)
    }
    foreach ($candidate in 0, -1, 65536) {
        $port = $candidate
        Invoke-ExpectThrow { New-ValidCommand -VoicePort $port } ("rejects voice port: " + $candidate)
        Invoke-ExpectThrow { New-ValidCommand -AiPort $port } ("rejects AI port: " + $candidate)
    }
}

function Invoke-QuotingTests {
    $result = New-ValidCommand -BuildId 'abc def' -DeviceId 'my device'
    $arguments = Get-MemberValue $result 'Arguments'
    Assert-True ($arguments -contains '--dart-define=LEXIQUEST_BUILD_ID=abc def') 'raw define preserves spaces'
    Assert-True ($arguments -contains 'my device') 'raw device preserves spaces'

    $command = [string](Get-MemberValue $result 'CommandString')
    Assert-ContainsString $command '"--dart-define=LEXIQUEST_BUILD_ID=abc def"' 'define is safely quoted'
    Assert-ContainsString $command '"my device"' 'device id is safely quoted'
}

$repoToolCli = Split-Path $PSScriptRoot -Parent
$targetPath = Join-Path $repoToolCli 'run-android.ps1'
if (-not (Test-Path -LiteralPath $targetPath)) {
    Write-Host ("FAIL: missing production dependency '{0}'." -f $targetPath) -ForegroundColor Red
    exit 1
}

. $targetPath

foreach ($suite in @(
    @{ Name = 'Command construction'; Action = { Invoke-CommandConstructionTests } },
    @{ Name = 'Host validation'; Action = { Invoke-HostValidationTests } },
    @{ Name = 'Port validation'; Action = { Invoke-PortValidationTests } },
    @{ Name = 'Safe quoting'; Action = { Invoke-QuotingTests } }
)) {
    try { & $suite.Action } catch { Write-Fail ($suite.Name + ' suite threw: ' + $_.Exception.Message) }
}

$total = $script:PassedCount + $script:FailedCount
Write-Host ("Android run command tests: {0} passed, {1} failed (of {2})" -f $script:PassedCount, $script:FailedCount, $total)
if ($script:FailedCount -gt 0) { exit 1 }
exit 0
