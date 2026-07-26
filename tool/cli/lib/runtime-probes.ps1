#Requires -Version 5.1
<#
.SYNOPSIS
    Pure, dependency-injected probes for the LexiQuest protected GPU runtime.

.DESCRIPTION
    These probes never call Get-Process, Get-CimInstance, Start-Process,
    Stop-Process, nvidia-smi, or any other cmdlet that queries, starts, stops,
    reprioritizes, or attaches to a real process. Every process sample and every
    nvidia-smi output is supplied by the caller, so the probes are safe to run
    while an active LoRA training workload holds the GPU.
#>
Set-StrictMode -Version 3.0

function Get-LexiQuestProcessCommandLine {
    param([object]$Process)

    if ($null -eq $Process) { return $null }
    $property = $null
    try { $property = $Process.PSObject.Properties['CommandLine'] } catch { return $null }
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-LexiQuestTrainingCommandLine {
    param([string]$CommandLine)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }

    $tokens = @(
        $CommandLine.ToLowerInvariant().Trim() -split '\s+' |
            Where-Object { $_ -ne '' }
    )

    $hasScript = $false
    $hasTrain = $false
    foreach ($token in $tokens) {
        $stripped = $token.Trim('"').Trim("'")
        if ($stripped -eq '--train') { $hasTrain = $true }
        $segments = $stripped -split '[\\/]'
        if ($segments[-1] -eq 'lora_finetune.py') { $hasScript = $true }
    }

    return ($hasScript -and $hasTrain)
}

function Test-LexiQuestTrainingProcess {
    [CmdletBinding()]
    param([object[]]$Processes)

    if ($null -eq $Processes) { return $false }
    foreach ($process in $Processes) {
        $commandLine = Get-LexiQuestProcessCommandLine -Process $process
        if ([string]::IsNullOrWhiteSpace($commandLine)) { continue }
        if (Test-LexiQuestTrainingCommandLine -CommandLine $commandLine) {
            return $true
        }
    }
    return $false
}

function Get-LexiQuestGpuSnapshot {
    [CmdletBinding()]
    param([scriptblock]$NvidiaSmiRunner)

    $snapshot = [pscustomobject]@{
        GpuAvailable       = $false
        GpuIndex           = $null
        GpuName            = $null
        UsedMemoryMiB      = $null
        MemoryTotalMiB     = $null
        UtilizationPercent = $null
        TemperatureCelsius = $null
    }

    if ($null -eq $NvidiaSmiRunner) { return $snapshot }

    $rawOutput = $null
    try {
        $rawOutput = & $NvidiaSmiRunner
    } catch {
        return $snapshot
    }
    if ([string]::IsNullOrWhiteSpace($rawOutput)) { return $snapshot }

    $row = $null
    foreach ($line in [regex]::Split([string]$rawOutput, '\r?\n')) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $row = $line.Trim()
            break
        }
    }
    if ($null -eq $row) { return $snapshot }

    $fields = $row -split ','
    if ($fields.Count -lt 6) { return $snapshot }

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $style = [System.Globalization.NumberStyles]::Integer
    $index = 0
    $used = 0
    $total = 0
    $utilization = 0
    $temperature = 0

    if (-not [int]::TryParse($fields[0].Trim(), $style, $culture, [ref]$index)) {
        return $snapshot
    }
    if (-not [int]::TryParse($fields[2].Trim(), $style, $culture, [ref]$used)) {
        return $snapshot
    }
    if (-not [int]::TryParse($fields[3].Trim(), $style, $culture, [ref]$total)) {
        return $snapshot
    }
    if (-not [int]::TryParse($fields[4].Trim(), $style, $culture, [ref]$utilization)) {
        return $snapshot
    }
    if (-not [int]::TryParse($fields[5].Trim(), $style, $culture, [ref]$temperature)) {
        return $snapshot
    }

    $snapshot.GpuAvailable = $true
    $snapshot.GpuIndex = $index
    $snapshot.GpuName = $fields[1].Trim()
    $snapshot.UsedMemoryMiB = $used
    $snapshot.MemoryTotalMiB = $total
    $snapshot.UtilizationPercent = $utilization
    $snapshot.TemperatureCelsius = $temperature
    return $snapshot
}

function Get-LexiQuestRuntimeGuard {
    [CmdletBinding()]
    param(
        [object[]]$Processes,
        [scriptblock]$NvidiaSmiRunner
    )

    $trainingActive = $false
    try {
        $trainingActive = [bool](
            Test-LexiQuestTrainingProcess -Processes $Processes
        )
    } catch {
        $trainingActive = $false
    }

    $snapshot = $null
    try {
        $snapshot = Get-LexiQuestGpuSnapshot -NvidiaSmiRunner $NvidiaSmiRunner
    } catch {
        $snapshot = $null
    }
    if ($null -eq $snapshot) {
        $snapshot = [pscustomobject]@{
            GpuAvailable       = $false
            UsedMemoryMiB      = $null
            UtilizationPercent = $null
        }
    }

    $gpuAvailable = [bool]$snapshot.GpuAvailable

    return [pscustomobject]@{
        TrainingActive       = [bool]$trainingActive
        GpuAvailable         = $gpuAvailable
        UsedMemoryMiB        = $snapshot.UsedMemoryMiB
        UtilizationPercent   = $snapshot.UtilizationPercent
        MayStartGpuInference = (
            (-not [bool]$trainingActive) -and $gpuAvailable
        )
    }
}
