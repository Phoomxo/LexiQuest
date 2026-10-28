#Requires -Version 5.1
<#
.SYNOPSIS
    Builds and, when run directly, executes the LexiQuest Android run command.

.DESCRIPTION
    New-LexiQuestAndroidRunCommand is pure. It validates caller-supplied values
    and returns executable/argument tokens plus a safely quoted display string.
    Dot-sourcing this file only defines functions and never runs Flutter.
#>
param(
    [string]$DeviceId = 'emulator-5554',
    [string]$LanHost = '192.168.1.20',
    [int]$VoicePort = 8001,
    [int]$AiPort = 8000
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Test-LexiQuestLanHost {
    param([string]$LanHost)

    if ([string]::IsNullOrWhiteSpace($LanHost)) { return $false }
    $octets = $LanHost.Trim() -split '\.'
    if ($octets.Count -ne 4) { return $false }

    $values = @()
    foreach ($octet in $octets) {
        $parsed = 0
        if (-not [int]::TryParse($octet, [ref]$parsed)) { return $false }
        if ($parsed -lt 0 -or $parsed -gt 255) { return $false }
        if ($octet -ne ([string]$parsed)) { return $false }
        $values += $parsed
    }

    $first = $values[0]
    $second = $values[1]
    if ($first -eq 127 -or $first -eq 10) { return $true }
    if ($first -eq 172 -and $second -ge 16 -and $second -le 31) { return $true }
    if ($first -eq 192 -and $second -eq 168) { return $true }
    return $false
}

function Test-LexiQuestPort {
    param([int]$Port)
    return ($Port -ge 1 -and $Port -le 65535)
}

function ConvertTo-LexiQuestDisplayToken {
    param([string]$Token)

    if ($null -eq $Token) { return '""' }
    if ($Token -notmatch '[\s"]') { return $Token }
    return '"' + $Token.Replace('"', '\"') + '"'
}

function New-LexiQuestAndroidRunCommand {
    [CmdletBinding()]
    param(
        [string]$Version = '1.0.0+1',
        [string]$BuildId = 'development',
        [string]$DeviceId = 'emulator-5554',
        [string]$LanHost = '192.168.1.20',
        [int]$VoicePort = 8001,
        [int]$AiPort = 8000
    )

    if ([string]::IsNullOrWhiteSpace($Version)) {
        throw 'Refusing to build command: version is required.'
    }
    if ([string]::IsNullOrWhiteSpace($BuildId)) {
        throw 'Refusing to build command: build id is required.'
    }
    if ([string]::IsNullOrWhiteSpace($DeviceId)) {
        throw 'Refusing to build command: device id is required.'
    }
    if (-not (Test-LexiQuestLanHost -LanHost $LanHost)) {
        throw 'Refusing to build command: LAN host must be private or loopback IPv4.'
    }
    if (-not (Test-LexiQuestPort -Port $VoicePort)) {
        throw 'Refusing to build command: voice port must be between 1 and 65535.'
    }
    if (-not (Test-LexiQuestPort -Port $AiPort)) {
        throw 'Refusing to build command: AI port must be between 1 and 65535.'
    }

    $arguments = @(
        'run',
        '-d',
        $DeviceId,
        ('--dart-define=LEXIQUEST_VERSION=' + $Version),
        ('--dart-define=LEXIQUEST_BUILD_ID=' + $BuildId),
        ('--dart-define=LEXIQUEST_VOICE_API_URL=http://' + $LanHost + ':' + $VoicePort),
        ('--dart-define=LEXIQUEST_AI_API_URL=http://' + $LanHost + ':' + $AiPort)
    )
    $displayArguments = @($arguments | ForEach-Object {
        ConvertTo-LexiQuestDisplayToken -Token ([string]$_)
    })

    return [pscustomobject]@{
        Exe = 'flutter'
        Arguments = $arguments
        CommandString = 'flutter ' + ($displayArguments -join ' ')
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $scriptDir = $PSScriptRoot
    $repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
    $probeLib = Join-Path (Join-Path $scriptDir 'lib') 'runtime-probes.ps1'

    $guard = $null
    if (Test-Path -LiteralPath $probeLib) {
        try {
            . $probeLib
            $processes = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)
            $gpuCsv = (& nvidia-smi `
                    --query-gpu=index,name,memory.used,memory.total,utilization.gpu,temperature.gpu `
                    --format=csv,noheader,nounits 2>$null) -join "`n"
            $runner = { $gpuCsv }.GetNewClosure()
            $guard = Get-LexiQuestRuntimeGuard `
                -Processes $processes `
                -NvidiaSmiRunner $runner
        } catch {
            $guard = $null
        }
    }
    if ($null -eq $guard) {
        $guard = [pscustomobject]@{
            TrainingActive = $false
            GpuAvailable = $false
            MayStartGpuInference = $false
        }
    }

    $shortSha = 'unknown'
    try {
        $revision = & git -C $repoRoot rev-parse --short HEAD 2>$null
        if (-not [string]::IsNullOrWhiteSpace($revision)) {
            $shortSha = (($revision -split '\r?\n')[0]).Trim()
        }
    } catch { }
    $dirtySuffix = ''
    try {
        $statusOutput = & git -C $repoRoot status --porcelain 2>$null
        if (-not [string]::IsNullOrWhiteSpace($statusOutput)) {
            $dirtySuffix = '-dirty'
        }
    } catch { }

    $command = New-LexiQuestAndroidRunCommand `
        -Version '1.0.0+1' `
        -BuildId ($shortSha + $dirtySuffix) `
        -DeviceId $DeviceId `
        -LanHost $LanHost `
        -VoicePort $VoicePort `
        -AiPort $AiPort

    if ([bool]$guard.TrainingActive) {
        Write-Host 'AI/Voice GPU inference protected/offline while training is active; Flutter client may run.' -ForegroundColor Yellow
    } elseif (-not [bool]$guard.GpuAvailable) {
        Write-Host 'AI/Voice GPU inference offline (no GPU detected); Flutter client may run.' -ForegroundColor Yellow
    } else {
        Write-Host 'AI/Voice GPU inference available; this command does not start it.' -ForegroundColor Green
    }

    Write-Host $command.CommandString
    $exe = [string]$command.Exe
    $flutterArguments = @($command.Arguments)
    & $exe $flutterArguments
    exit $LASTEXITCODE
}
