#Requires -Version 5.1
<#
.SYNOPSIS
    Dependency-free test runner for the LexiQuest protected GPU runtime probes.

.DESCRIPTION
    Custom PowerShell runner that works on Windows PowerShell 5.1 and PowerShell 7
    without Pester or any module dependency. Every process and nvidia-smi input is
    injected, so the tests never call Get-Process, Get-CimInstance, Start-Process,
    Stop-Process, or any cmdlet that queries, starts, stops, suspends, reprioritizes,
    or attaches to a real process.

    RED state: tool/cli/lib/runtime-probes.ps1 does not exist yet, so the runner
    fails fast with a non-zero exit code before any assertion runs.
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

function Assert-False {
    param([object]$Value, [string]$Message)
    if (-not $Value) { Write-Pass $Message } else { Write-Fail $Message }
}

function Assert-Equal {
    param([object]$Expected, [object]$Actual, [string]$Message)
    if ($Expected -eq $Actual) {
        Write-Pass $Message
    } else {
        Write-Fail ($Message + " (expected '$Expected', got '$Actual')")
    }
}

function Get-MemberValue {
    param([object]$InputObject, [string]$Name)
    if ($null -eq $InputObject) { return $null }
    $prop = $null
    try { $prop = $InputObject.PSObject.Properties[$Name] } catch { return $null }
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Assert-PropertyExists {
    param([object]$InputObject, [string]$Name, [string]$Message)
    if ($null -eq $InputObject) {
        Write-Fail ($Message + ' (object was null)')
        return
    }
    $prop = $null
    try { $prop = $InputObject.PSObject.Properties[$Name] } catch { }
    if ($null -eq $prop) {
        Write-Fail ($Message + " (missing property '$Name')")
    } else {
        Write-Pass $Message
    }
}

function New-ProcessSample {
    param([int]$Id, [string]$CommandLine)
    return [pscustomobject]@{ ProcessId = $Id; CommandLine = $CommandLine }
}

function Invoke-TrainingDetectionTests {
    $trueTraining = New-ProcessSample 42 'python lora_finetune.py --train'
    $quotedPath = New-ProcessSample 43 '"C:\Users\dev\lora_finetune.py" --train'
    $extraArgs = New-ProcessSample 44 'python /repo/backend/lexiquest_lm/train/lora_finetune.py --train --max-train-rows 1000'
    $caseVariant = New-ProcessSample 45 'PYTHON LORA_FINETUNE.PY --TRAIN'

    Assert-True (Test-LexiQuestTrainingProcess -Processes @($trueTraining)) 'basic training command line is detected'
    Assert-True (Test-LexiQuestTrainingProcess -Processes @($quotedPath)) 'quoted lora_finetune.py path is tolerated'
    Assert-True (Test-LexiQuestTrainingProcess -Processes @($extraArgs)) 'training still detected with additional arguments'
    Assert-True (Test-LexiQuestTrainingProcess -Processes @($caseVariant)) 'matching is case-insensitive'
    Assert-True (Test-LexiQuestTrainingProcess -Processes @(
        (New-ProcessSample 50 'python api.py'),
        $trueTraining,
        (New-ProcessSample 51 'python inference.py')
    )) 'a matching process among unrelated ones is detected'

    Assert-False (Test-LexiQuestTrainingProcess -Processes @()) 'empty process array returns false'
    Assert-False (Test-LexiQuestTrainingProcess -Processes $null) 'null process input returns false'
    Assert-False (Test-LexiQuestTrainingProcess -Processes @((New-ProcessSample 60 'python lora_finetune.py'))) 'command line without --train returns false'
    Assert-False (Test-LexiQuestTrainingProcess -Processes @((New-ProcessSample 61 'python lora_finetune.py --dry-run'))) 'dry-run command line returns false'
    Assert-False (Test-LexiQuestTrainingProcess -Processes @((New-ProcessSample 62 'python lora_finetune.py --max-train-rows 64'))) '--max-train-rows without standalone --train returns false'
    Assert-False (Test-LexiQuestTrainingProcess -Processes @((New-ProcessSample 63 'python lora_finetune.py --training-data a b'))) 'non-standalone --training token returns false'
    Assert-False (Test-LexiQuestTrainingProcess -Processes @((New-ProcessSample 64 'python api.py'))) 'unrelated api command line returns false'
    Assert-False (Test-LexiQuestTrainingProcess -Processes @((New-ProcessSample 65 'python inference.py'))) 'unrelated inference command line returns false'
    Assert-False (Test-LexiQuestTrainingProcess -Processes @((New-ProcessSample 66 'python not_lora_finetune.py --train'))) 'misleading not_lora_finetune.py returns false'
    Assert-False (Test-LexiQuestTrainingProcess -Processes @((New-ProcessSample 67 'python lora_finetune_v2.py --train'))) 'differently named script returns false'
    Assert-False (Test-LexiQuestTrainingProcess -Processes @((New-ProcessSample 68 'python --train'))) 'command line with only --train returns false'
}

function Invoke-GpuSnapshotTests {
    $goodCsv = { '0, NVIDIA GeForce RTX 4090, 1024, 24564, 5, 35' }

    $snapshot = Get-LexiQuestGpuSnapshot -NvidiaSmiRunner $goodCsv
    Assert-True (Get-MemberValue $snapshot 'GpuAvailable') 'well-formed nvidia-smi row yields GpuAvailable'
    Assert-Equal 1024 (Get-MemberValue $snapshot 'UsedMemoryMiB') 'parsed used memory MiB'
    Assert-Equal 5 (Get-MemberValue $snapshot 'UtilizationPercent') 'parsed utilization percent'

    $first = Get-LexiQuestGpuSnapshot -NvidiaSmiRunner $goodCsv
    $second = Get-LexiQuestGpuSnapshot -NvidiaSmiRunner $goodCsv
    Assert-True (-not [object]::ReferenceEquals($first, $second)) 'snapshot objects are independent (non-mutating)'

    $badCases = @(
        @{ Name = 'too few fields'; Runner = { '0, GPU' } },
        @{ Name = 'non-numeric memory'; Runner = { '0, GPU, oops, 24564, 5, 35' } },
        @{ Name = 'empty output'; Runner = { '' } },
        @{ Name = 'null output (absence)'; Runner = { $null } },
        @{ Name = 'no output (absence)'; Runner = {} },
        @{ Name = 'runner throws'; Runner = { throw 'nvidia-smi not found' } }
    )
    foreach ($case in $badCases) {
        $result = $null
        $threw = $false
        try {
            $result = Get-LexiQuestGpuSnapshot -NvidiaSmiRunner $case['Runner']
        } catch {
            $threw = $true
        }
        Assert-False $threw ('malformed/absent nvidia-smi must not throw: ' + $case['Name'])
        Assert-False (Get-MemberValue $result 'GpuAvailable') ('malformed/absent nvidia-smi yields GpuAvailable=false: ' + $case['Name'])
    }
}

function Invoke-RuntimeGuardTests {
    $goodCsv = { '0, NVIDIA GeForce RTX 4090, 1024, 24564, 5, 35' }
    $badCsv = { 'not-a-csv-row' }
    $training = @((New-ProcessSample 42 'python lora_finetune.py --train'))
    $idle = @((New-ProcessSample 50 'python api.py'))

    $guard = Get-LexiQuestRuntimeGuard -Processes $idle -NvidiaSmiRunner $goodCsv
    foreach ($member in 'TrainingActive', 'GpuAvailable', 'UsedMemoryMiB', 'UtilizationPercent', 'MayStartGpuInference') {
        Assert-PropertyExists $guard $member ("guard reports member '{0}'" -f $member)
    }

    $g = Get-LexiQuestRuntimeGuard -Processes $idle -NvidiaSmiRunner $goodCsv
    Assert-False (Get-MemberValue $g 'TrainingActive') 'idle processes => TrainingActive false'
    Assert-True (Get-MemberValue $g 'GpuAvailable') 'good GPU => GpuAvailable true'
    Assert-True (Get-MemberValue $g 'MayStartGpuInference') 'idle + good GPU => MayStartGpuInference true'
    Assert-Equal 1024 (Get-MemberValue $g 'UsedMemoryMiB') 'guard exposes used memory MiB'
    Assert-Equal 5 (Get-MemberValue $g 'UtilizationPercent') 'guard exposes utilization percent'

    $t = Get-LexiQuestRuntimeGuard -Processes $training -NvidiaSmiRunner $goodCsv
    Assert-True (Get-MemberValue $t 'TrainingActive') 'training => TrainingActive true'
    Assert-True (Get-MemberValue $t 'GpuAvailable') 'training guard still reports GPU availability'
    Assert-False (Get-MemberValue $t 'MayStartGpuInference') 'training blocks GPU inference'

    $b = Get-LexiQuestRuntimeGuard -Processes $idle -NvidiaSmiRunner $badCsv
    Assert-False (Get-MemberValue $b 'GpuAvailable') 'bad GPU => GpuAvailable false'
    Assert-False (Get-MemberValue $b 'MayStartGpuInference') 'bad GPU blocks GPU inference'

    $tb = $null
    $threw = $false
    try {
        $tb = Get-LexiQuestRuntimeGuard -Processes $training -NvidiaSmiRunner $badCsv
    } catch {
        $threw = $true
    }
    Assert-False $threw 'training + bad GPU does not throw'
    Assert-False (Get-MemberValue $tb 'MayStartGpuInference') 'training + bad GPU blocks GPU inference'
}

$repoToolCli = Split-Path $PSScriptRoot -Parent
$libPath = Join-Path (Join-Path $repoToolCli 'lib') 'runtime-probes.ps1'

if (-not (Test-Path $libPath)) {
    Write-Host ("FAIL: missing production dependency '{0}'." -f $libPath) -ForegroundColor Red
    Write-Host 'Runtime probe tests: 0 passed, 1 failed' -ForegroundColor Red
    Write-Host 'FAILED' -ForegroundColor Red
    exit 1
}

. $libPath

foreach ($fn in 'Test-LexiQuestTrainingProcess', 'Get-LexiQuestGpuSnapshot', 'Get-LexiQuestRuntimeGuard') {
    if ($null -eq (Get-Command $fn -ErrorAction SilentlyContinue)) {
        Write-Fail ("contract function not defined: {0}" -f $fn)
    }
}

Write-Host '-> Training detection' -ForegroundColor Cyan
try { Invoke-TrainingDetectionTests } catch { Write-Fail ('Training detection suite threw: ' + $_.Exception.Message) }

Write-Host '-> GPU snapshot' -ForegroundColor Cyan
try { Invoke-GpuSnapshotTests } catch { Write-Fail ('GPU snapshot suite threw: ' + $_.Exception.Message) }

Write-Host '-> Runtime guard' -ForegroundColor Cyan
try { Invoke-RuntimeGuardTests } catch { Write-Fail ('Runtime guard suite threw: ' + $_.Exception.Message) }

$total = $script:PassedCount + $script:FailedCount
Write-Host ''
Write-Host ("Runtime probe tests: {0} passed, {1} failed (of {2})" -f $script:PassedCount, $script:FailedCount, $total)

if ($script:FailedCount -gt 0) {
    Write-Host 'FAILED' -ForegroundColor Red
    exit 1
}

Write-Host 'PASS' -ForegroundColor Green
exit 0
