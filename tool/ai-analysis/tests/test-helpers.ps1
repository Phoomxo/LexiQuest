Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AiAnalysisPassed = 0
$script:AiAnalysisFailed = 0

function Invoke-AiAnalysisTest {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Test
    )

    try {
        & $Test
        $script:AiAnalysisPassed++
    } catch {
        $script:AiAnalysisFailed++
        Write-Error "$Name`: $($_.Exception.Message)" -ErrorAction Continue
    }
}

function Assert-True {
    param($Actual, [string]$Message = 'expected true')
    if (-not $Actual) { throw $Message }
}

function Assert-False {
    param($Actual, [string]$Message = 'expected false')
    if ($Actual) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message = 'values differ')
    $expectedJson = ConvertTo-Json @($Expected) -Compress -Depth 20
    $actualJson = ConvertTo-Json @($Actual) -Compress -Depth 20
    if ($expectedJson -cne $actualJson) {
        throw "$Message (expected $expectedJson, actual $actualJson)"
    }
}

function Assert-Match {
    param([string]$Pattern, [string]$Actual, [string]$Message = 'pattern did not match')
    if ($Actual -notmatch $Pattern) { throw "$Message (pattern $Pattern)" }
}

function Assert-NotMatch {
    param([string]$Pattern, [string]$Actual, [string]$Message = 'unexpected pattern matched')
    if ($Actual -match $Pattern) { throw "$Message (pattern $Pattern)" }
}

function Assert-Throws {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Category)
    try {
        $null = & $Action
    } catch {
        if ($_.Exception.Message -notmatch [regex]::Escape($Category)) {
            throw "expected error '$Category', actual '$($_.Exception.Message)'"
        }
        return
    }
    throw "expected error '$Category', but no error was thrown"
}

function Complete-AiAnalysisTests {
    param([Parameter(Mandatory)][string]$Suite)
    Write-Host "$Suite tests: $script:AiAnalysisPassed passed, $script:AiAnalysisFailed failed"
    if ($script:AiAnalysisFailed -gt 0) { exit 1 }
}
