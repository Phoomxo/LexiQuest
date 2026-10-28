Set-StrictMode -Version Latest

function ConvertTo-AiAnalysisEffort {
    param([Parameter(Mandatory)][string]$Value)

    switch ($Value.ToLowerInvariant()) {
        'auto' { return 'auto' }
        'low' { return 'low' }
        'medium' { return 'medium' }
        'high' { return 'high' }
        'xhigh' { return 'xhigh' }
        'extrahigh' { return 'xhigh' }
        'extendedhigh' { return 'xhigh' }
        'max' { return 'max' }
        'ultra' { return 'ultra' }
        default { throw 'invalidEffort' }
    }
}

function Get-AiAnalysisEffortDisplay {
    param([Parameter(Mandatory)][string]$Effort, [Parameter(Mandatory)][ValidateSet('gpt', 'claude')][string]$Provider)

    if ($Effort -eq 'xhigh') {
        if ($Provider -eq 'gpt') { return 'ExtraHigh' }
        return 'ExtendedHigh'
    }
    return (Get-Culture).TextInfo.ToTitleCase($Effort)
}

function Get-AiAnalysisOutputLimit {
    param([Parameter(Mandatory)][string]$Effort, [Parameter(Mandatory)][ValidateSet('gpt', 'claude')][string]$Provider)

    $gpt = @{ low = 2048; medium = 4096; high = 8192; xhigh = 32768; max = 65536; ultra = 65536 }
    $claude = @{ low = 4096; medium = 8192; high = 16384; xhigh = 65536; max = 65536 }
    if ($Provider -eq 'gpt') { return $gpt[$Effort] }
    return $claude[$Effort]
}

function Resolve-AiAnalysisPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Task,
        [Parameter(Mandatory)][ValidateRange(0, 20)][int]$FileCount,
        [ValidateSet('Auto', 'Low', 'Medium', 'High', 'XHigh', 'ExtraHigh', 'ExtendedHigh', 'Max', 'Ultra')]
        [string]$RequestedEffort = 'Auto',
        [switch]$NoReviewer
    )

    $taskLower = $Task.ToLowerInvariant()
    if ($taskLower -match '\bcritical\b.*\b(disagreement|adjudicat)') {
        $classification = 'criticalDisagreement'
        $gptEffort = 'ultra'
        $claudeEffort = 'max'
        $reviewerRequired = $true
    } elseif ($taskLower -match '\b(release blocker|rollout blocker|release readiness|signing|signed apk|upgrade install)\b') {
        $classification = 'releaseBlocker'
        $gptEffort = 'max'
        $claudeEffort = 'xhigh'
        $reviewerRequired = $true
    } elseif ($taskLower -match '\b(architect|architecture|race|concurren|migration|database|schema|privacy|security|auth|credential|secret)\w*\b') {
        $classification = 'architectureSensitive'
        $gptEffort = 'xhigh'
        $claudeEffort = 'high'
        $reviewerRequired = $true
    } elseif ($FileCount -ge 2 -or $taskLower -match '\b(fail|failed|failing|failure|regression)\w*\b') {
        $classification = 'failedOrMultiFile'
        $gptEffort = 'high'
        $claudeEffort = 'medium'
        $reviewerRequired = $true
    } elseif ($taskLower -match '\b(summarize|summary|inventory|format|list|read-only|test output)\w*\b') {
        $classification = 'simple'
        $gptEffort = 'low'
        $claudeEffort = $null
        $reviewerRequired = $false
    } else {
        $classification = 'focusedPackage'
        $gptEffort = 'medium'
        $claudeEffort = 'low'
        $reviewerRequired = $true
    }

    $requested = ConvertTo-AiAnalysisEffort -Value $RequestedEffort
    if ($requested -eq 'ultra' -and $classification -ne 'criticalDisagreement') {
        throw 'ultraRequiresCriticalAdjudication'
    }

    if ($requested -ne 'auto') {
        if ($classification -in @('architectureSensitive', 'releaseBlocker', 'criticalDisagreement')) {
            $rank = @{ low = 0; medium = 1; high = 2; xhigh = 3; max = 4; ultra = 5 }
            if ($rank[$requested] -gt $rank[$gptEffort]) {
                $gptEffort = $requested
            }
            $requestedClaude = if ($requested -eq 'ultra') { 'max' } else { $requested }
            if ($rank[$requestedClaude] -gt $rank[$claudeEffort]) {
                $claudeEffort = $requestedClaude
            }
        } else {
            $gptEffort = $requested
            if ($reviewerRequired) {
                $claudeEffort = $requested
            }
        }
    }

    if ($NoReviewer) {
        if ($classification -in @('criticalDisagreement', 'releaseBlocker', 'architectureSensitive')) {
            throw 'reviewerRequired'
        }
        $reviewerRequired = $false
        $claudeEffort = $null
    }

    $claudeModel = if (-not $reviewerRequired) {
        $null
    } elseif ($classification -in @('architectureSensitive', 'releaseBlocker', 'criticalDisagreement') -or
              $claudeEffort -in @('xhigh', 'max')) {
        'claude-opus-5'
    } else {
        'claude-sonnet-5'
    }

    [pscustomobject]@{
        Classification = $classification
        GptEffort = $gptEffort
        ClaudeEffort = $claudeEffort
        ClaudeModel = $claudeModel
        ReviewerRequired = $reviewerRequired
        GptMaxOutputTokens = Get-AiAnalysisOutputLimit -Effort $gptEffort -Provider gpt
        ClaudeMaxOutputTokens = if ($reviewerRequired) { Get-AiAnalysisOutputLimit -Effort $claudeEffort -Provider claude } else { $null }
        GptEffortDisplay = Get-AiAnalysisEffortDisplay -Effort $gptEffort -Provider gpt
        ClaudeEffortDisplay = if ($reviewerRequired) { Get-AiAnalysisEffortDisplay -Effort $claudeEffort -Provider claude } else { $null }
    }
}
