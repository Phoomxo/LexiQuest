#Requires -Version 5.1
<#
.SYNOPSIS
    Read-only LexiQuest runtime doctor.

.DESCRIPTION
    Inspects repository, required CLI tools, protected training processes, and
    GPU status. It never starts, stops, suspends, reprioritizes, attaches to, or
    imports any training or inference backend.

    Emits exactly one compact JSON object and a deterministic exit code:
      0 - repository and required tools are inspectable.
      1 - repository or a required tool is missing/uninspectable.
#>
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $invokedPath = $null
    try { $invokedPath = $MyInvocation.MyCommand.Path } catch { }
    if (-not [string]::IsNullOrWhiteSpace($invokedPath)) {
        $scriptDir = Split-Path -Parent $invokedPath
    }
}
$toolDir = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent $toolDir
$probeLib = Join-Path (Join-Path $scriptDir 'lib') 'runtime-probes.ps1'

$probesLoaded = $false
if (Test-Path -LiteralPath $probeLib) {
    try {
        . $probeLib
        $probesLoaded = $true
    } catch {
        $probesLoaded = $false
    }
}

$requiredToolNames = @('git', 'flutter', 'uv')
$missingTools = @()
foreach ($toolName in $requiredToolNames) {
    $found = $null
    try {
        $found = Get-Command -Name $toolName -ErrorAction SilentlyContinue
    } catch { }
    if ($null -eq $found) { $missingTools += $toolName }
}
$requiredToolsReady = ($missingTools.Count -eq 0)
$gitPresent = ($missingTools -notcontains 'git')

$repositoryReady = $false
if ((Test-Path -LiteralPath $repoRoot) -and $gitPresent) {
    $revResult = $null
    try {
        $revResult = & git -C $repoRoot rev-parse --is-inside-work-tree 2>$null
    } catch { }
    $repositoryReady = ($revResult -eq 'true')
}
$repositoryReady = ($repositoryReady -and $probesLoaded)

$processes = $null
$processInspectionReady = $false
try {
    $processes = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)
    $processInspectionReady = $true
} catch {
    $processes = @()
}

$gpuCsv = $null
try {
    $gpuCsv = (
        & nvidia-smi `
            --query-gpu=index,name,memory.used,memory.total,utilization.gpu,temperature.gpu `
            --format=csv,noheader,nounits 2>$null
    ) -join "`n"
} catch { }
$nvidiaSmiRunner = { $gpuCsv }.GetNewClosure()

$guard = $null
$snapshot = $null
if ($probesLoaded) {
    try {
        $guard = Get-LexiQuestRuntimeGuard `
            -Processes $processes `
            -NvidiaSmiRunner $nvidiaSmiRunner
    } catch { }
    try {
        $snapshot = Get-LexiQuestGpuSnapshot `
            -NvidiaSmiRunner $nvidiaSmiRunner
    } catch { }
}
if ($null -eq $guard) {
    $guard = [pscustomobject]@{
        TrainingActive       = $false
        GpuAvailable         = $false
        UsedMemoryMiB        = $null
        UtilizationPercent   = $null
        MayStartGpuInference = $false
    }
}
if ($null -eq $snapshot) {
    $snapshot = [pscustomobject]@{
        GpuAvailable       = $false
        GpuName            = $null
        UsedMemoryMiB      = $null
        MemoryTotalMiB     = $null
        UtilizationPercent = $null
        TemperatureCelsius = $null
    }
}

$trainingProcessIds = @()
if ($probesLoaded -and $processInspectionReady) {
    foreach ($proc in $processes) {
        if ($null -eq $proc) { continue }
        $commandLine = $null
        try {
            $commandLine = Get-LexiQuestProcessCommandLine -Process $proc
        } catch { }
        $isTraining = $false
        try {
            $isTraining = Test-LexiQuestTrainingCommandLine `
                -CommandLine $commandLine
        } catch { }
        if (-not $isTraining) { continue }

        $pidValue = $null
        try {
            $pidProperty = $proc.PSObject.Properties['ProcessId']
            if ($null -ne $pidProperty) { $pidValue = $pidProperty.Value }
        } catch { }
        if ($null -ne $pidValue) {
            $trainingProcessIds += [int]$pidValue
        }
    }
}

$mayStartGpuInference = (
    $processInspectionReady -and
    [bool]$guard.MayStartGpuInference
)
$result = [pscustomobject]@{
    RepositoryReady      = [bool]$repositoryReady
    RequiredToolsReady   = [bool]$requiredToolsReady
    MissingRequiredTools = @($missingTools)
    TrainingActive       = [bool]$guard.TrainingActive
    TrainingProcessIds   = @($trainingProcessIds)
    GpuAvailable         = [bool]$snapshot.GpuAvailable
    GpuName              = $snapshot.GpuName
    UsedMemoryMiB        = $snapshot.UsedMemoryMiB
    MemoryTotalMiB       = $snapshot.MemoryTotalMiB
    UtilizationPercent   = $snapshot.UtilizationPercent
    TemperatureCelsius   = $snapshot.TemperatureCelsius
    MayStartGpuInference = [bool]$mayStartGpuInference
}
$result | ConvertTo-Json -Compress -Depth 5

if ($repositoryReady -and $requiredToolsReady) {
    exit 0
}
exit 1
