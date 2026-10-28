Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..\lib\config.ps1')
. (Join-Path $PSScriptRoot '..\lib\effort-router.ps1')

function Assert-ConfigMutationRejected {
    param([Parameter(Mandatory)][scriptblock]$Mutation)
    $sourcePath = Join-Path $PSScriptRoot '..\config.json'
    $candidate = Get-Content -LiteralPath $sourcePath -Raw -Encoding utf8 | ConvertFrom-Json
    & $Mutation $candidate
    $temporaryPath = Join-Path ([System.IO.Path]::GetTempPath()) ("lexiquest-ai-config-" + [guid]::NewGuid().ToString('N') + '.json')
    try {
        [System.IO.File]::WriteAllText($temporaryPath, ($candidate | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
        Assert-Throws { Get-AiAnalysisConfig -ConfigPath $temporaryPath } 'invalidConfig'
    } finally {
        if ([System.IO.File]::Exists($temporaryPath)) { [System.IO.File]::Delete($temporaryPath) }
    }
}

Invoke-AiAnalysisTest 'loads the approved exact-host provider configuration' {
    $config = Get-AiAnalysisConfig -ConfigPath (Join-Path $PSScriptRoot '..\config.json')
    Assert-Equal 'https://api.maxplus-ai.cc/gpt-pro-20x-stable' $config.providers.gptStable.baseUrl 'GPT base URL'
    Assert-Equal 'https://api.maxplus-ai.cc' $config.providers.gptStable.accountBaseUrl 'GPT account base URL'
    Assert-Equal 'gpt-5.6-sol' $config.providers.gptStable.model 'GPT model'
    Assert-Equal 'https://api.maxplus-ai.cc/aws-lite-ultimate' $config.providers.claudeReviewer.baseUrl 'Claude base URL'
    Assert-Equal 'https://api.maxplus-ai.cc' $config.providers.claudeReviewer.accountBaseUrl 'Claude account base URL'
    Assert-Equal 'claude-sonnet-5' $config.providers.claudeReviewer.models.routine 'routine Claude model'
    Assert-Equal 'claude-opus-5' $config.providers.claudeReviewer.models.deep 'deep Claude model'
    Assert-False ($config.providers.claudeReviewer.PSObject.Properties.Name -contains 'model') 'shared Claude config has no selected model'
    Assert-False $config.providers.gptStable.store 'Responses storage disabled'
}

Invoke-AiAnalysisTest 'creates a request-local Claude provider without mutating shared config' {
    $config = Get-AiAnalysisConfig -ConfigPath (Join-Path $PSScriptRoot '..\config.json')
    $provider = New-AiAnalysisClaudeProvider -ClaudeConfig $config.providers.claudeReviewer -Model 'claude-sonnet-5'
    Assert-Equal 'claude-sonnet-5' $provider.model 'request-local model'
    Assert-False ($config.providers.claudeReviewer.PSObject.Properties.Name -contains 'model') 'shared config remains unchanged'
    Assert-Throws { New-AiAnalysisClaudeProvider -ClaudeConfig $config.providers.claudeReviewer -Model 'claude-fable-5' } 'ValidateSet'
}

Invoke-AiAnalysisTest 'rejects modified provider and storage invariants' {
    Assert-ConfigMutationRejected { param($candidate) $candidate.providers.gptStable.store = $true }
    Assert-ConfigMutationRejected { param($candidate) $candidate.providers.gptStable.model = 'substitute-model' }
    Assert-ConfigMutationRejected { param($candidate) $candidate.providers.claudeReviewer.generationRoute = '/v1/other' }
    Assert-ConfigMutationRejected { param($candidate) $candidate.providers.claudeReviewer.authStyle = 'bearer' }
    Assert-ConfigMutationRejected { param($candidate) $candidate.providers.claudeReviewer.models.routine = 'substitute-model' }
    Assert-ConfigMutationRejected { param($candidate) $candidate.providers.claudeReviewer.models.PSObject.Properties.Remove('deep') }
    Assert-ConfigMutationRejected {
        param($candidate)
        $candidate.providers.claudeReviewer.models |
            Add-Member -NotePropertyName extra -NotePropertyValue 'claude-fable-5'
    }
}

Invoke-AiAnalysisTest 'rejects weakened limits and secret scanning' {
    Assert-ConfigMutationRejected { param($candidate) $candidate.context.maxFiles = 200 }
    Assert-ConfigMutationRejected { param($candidate) $candidate.context.denylist = @() }
    Assert-ConfigMutationRejected { param($candidate) $candidate.secretPatterns = @() }
    Assert-ConfigMutationRejected {
        param($candidate)
        $first = $candidate.secretPatterns[0]
        $candidate.secretPatterns = @($first, $first, $first, $first, $first)
    }
    Assert-ConfigMutationRejected { param($candidate) $candidate.retentionDays = 90 }
}

Invoke-AiAnalysisTest 'routes a release blocker to GPT max and Claude xhigh' {
    $policy = Resolve-AiAnalysisPolicy -Task 'Release blocker: migration data loss' -FileCount 3 -RequestedEffort Auto
    Assert-Equal 'releaseBlocker' $policy.Classification 'release classification'
    Assert-Equal 'max' $policy.GptEffort 'release GPT effort'
    Assert-Equal 'xhigh' $policy.ClaudeEffort 'release Claude effort'
    Assert-Equal 'claude-opus-5' $policy.ClaudeModel 'release reviewer model'
    Assert-True $policy.ReviewerRequired 'release reviewer required'
    Assert-Equal 65536 $policy.GptMaxOutputTokens 'release GPT output cap'
    Assert-Equal 65536 $policy.ClaudeMaxOutputTokens 'release Claude output cap'
}

Invoke-AiAnalysisTest 'routes architecture-sensitive work before file-count rules' {
    $policy = Resolve-AiAnalysisPolicy -Task 'Privacy architecture review' -FileCount 1 -RequestedEffort Auto
    Assert-Equal 'architectureSensitive' $policy.Classification 'architecture classification'
    Assert-Equal 'xhigh' $policy.GptEffort 'architecture GPT effort'
    Assert-Equal 'high' $policy.ClaudeEffort 'architecture Claude effort'
    Assert-Equal 'claude-opus-5' $policy.ClaudeModel 'architecture reviewer model'
    Assert-True $policy.ReviewerRequired 'architecture reviewer required'
}

Invoke-AiAnalysisTest 'routes failed or multi-file work to high and medium' {
    $policy = Resolve-AiAnalysisPolicy -Task 'Review this behavior' -FileCount 2 -RequestedEffort Auto
    Assert-Equal 'failedOrMultiFile' $policy.Classification 'multi-file classification'
    Assert-Equal 'high' $policy.GptEffort 'multi-file GPT effort'
    Assert-Equal 'medium' $policy.ClaudeEffort 'multi-file Claude effort'
    Assert-Equal 'claude-sonnet-5' $policy.ClaudeModel 'multi-file reviewer model'
    Assert-True $policy.ReviewerRequired 'multi-file reviewer required'
}

Invoke-AiAnalysisTest 'routes focused work to medium with a low reviewer' {
    $policy = Resolve-AiAnalysisPolicy -Task 'Fix provider cancellation behavior' -FileCount 1 -RequestedEffort Auto
    Assert-Equal 'focusedPackage' $policy.Classification 'focused classification'
    Assert-Equal 'medium' $policy.GptEffort 'focused GPT effort'
    Assert-Equal 'low' $policy.ClaudeEffort 'focused Claude effort'
    Assert-Equal 'claude-sonnet-5' $policy.ClaudeModel 'focused reviewer model'
    Assert-True $policy.ReviewerRequired 'focused reviewer required'
}

Invoke-AiAnalysisTest 'routes simple read-only work to GPT low without reviewer' {
    $policy = Resolve-AiAnalysisPolicy -Task 'Summarize these test names' -FileCount 1 -RequestedEffort Auto
    Assert-Equal 'simple' $policy.Classification 'simple classification'
    Assert-Equal 'low' $policy.GptEffort 'simple GPT effort'
    Assert-False $policy.ReviewerRequired 'simple skips reviewer'
    Assert-Equal $null $policy.ClaudeModel 'simple has no reviewer model'
    Assert-Equal 2048 $policy.GptMaxOutputTokens 'simple output cap'
}

Invoke-AiAnalysisTest 'forbids reviewer bypass for sensitive work' {
    Assert-Throws { Resolve-AiAnalysisPolicy -Task 'Privacy architecture review' -FileCount 2 -RequestedEffort Low -NoReviewer } 'reviewerRequired'
}

Invoke-AiAnalysisTest 'classifies database security and credential work as architecture sensitive' {
    foreach ($task in @('Database schema review', 'Security boundary review', 'Authentication state review', 'Credential storage review', 'Secret handling review')) {
        $policy = Resolve-AiAnalysisPolicy -Task $task -FileCount 1 -RequestedEffort Auto
        Assert-Equal 'architectureSensitive' $policy.Classification "$task classification"
        Assert-Equal 'claude-opus-5' $policy.ClaudeModel "$task model"
        Assert-Equal 'high' $policy.ClaudeEffort "$task reviewer floor"
    }
}

Invoke-AiAnalysisTest 'normalizes extended effort aliases and allows noncritical lowering' {
    foreach ($alias in @('XHigh', 'ExtraHigh', 'ExtendedHigh')) {
        $policy = Resolve-AiAnalysisPolicy -Task 'Review provider cancellation' -FileCount 1 -RequestedEffort $alias
        Assert-Equal 'xhigh' $policy.GptEffort "$alias GPT normalization"
        Assert-Equal 'xhigh' $policy.ClaudeEffort "$alias Claude normalization"
        Assert-Equal 'ExtraHigh' $policy.GptEffortDisplay "$alias GPT display"
        Assert-Equal 'ExtendedHigh' $policy.ClaudeEffortDisplay "$alias Claude display"
        Assert-Equal 'claude-opus-5' $policy.ClaudeModel "$alias upgrades reviewer model"
    }

    $lowered = Resolve-AiAnalysisPolicy -Task 'Review provider cancellation' -FileCount 1 -RequestedEffort Low
    Assert-Equal 'low' $lowered.GptEffort 'noncritical lowering allowed'
    Assert-Equal 'claude-sonnet-5' $lowered.ClaudeModel 'routine low remains Sonnet'

    $high = Resolve-AiAnalysisPolicy -Task 'Review provider cancellation' -FileCount 1 -RequestedEffort High
    Assert-Equal 'claude-sonnet-5' $high.ClaudeModel 'routine high remains Sonnet'

    $max = Resolve-AiAnalysisPolicy -Task 'Review provider cancellation' -FileCount 1 -RequestedEffort Max
    Assert-Equal 'claude-opus-5' $max.ClaudeModel 'routine max upgrades to Opus'
}

Invoke-AiAnalysisTest 'does not lower a release-critical effort floor' {
    $policy = Resolve-AiAnalysisPolicy -Task 'Release blocker in signing' -FileCount 1 -RequestedEffort Low
    Assert-Equal 'max' $policy.GptEffort 'release floor preserved'
    Assert-Equal 'xhigh' $policy.ClaudeEffort 'release reviewer floor preserved'
    Assert-Equal 'claude-opus-5' $policy.ClaudeModel 'release model preserved'
}

Invoke-AiAnalysisTest 'does not lower architecture or critical reviewer floors' {
    $architecture = Resolve-AiAnalysisPolicy -Task 'Security architecture review' -FileCount 1 -RequestedEffort Low
    Assert-Equal 'xhigh' $architecture.GptEffort 'architecture GPT floor preserved'
    Assert-Equal 'high' $architecture.ClaudeEffort 'architecture Claude floor preserved'
    Assert-Equal 'claude-opus-5' $architecture.ClaudeModel 'architecture Opus preserved'

    $critical = Resolve-AiAnalysisPolicy -Task 'Critical disagreement adjudication' -FileCount 1 -RequestedEffort Low
    Assert-Equal 'ultra' $critical.GptEffort 'critical GPT floor preserved'
    Assert-Equal 'max' $critical.ClaudeEffort 'critical Claude floor preserved'
    Assert-Equal 'claude-opus-5' $critical.ClaudeModel 'critical Opus preserved'
}

Invoke-AiAnalysisTest 'reserves ultra for critical adjudication' {
    Assert-Throws { Resolve-AiAnalysisPolicy -Task 'Review provider cancellation' -FileCount 1 -RequestedEffort Ultra } 'ultraRequiresCriticalAdjudication'
    $policy = Resolve-AiAnalysisPolicy -Task 'Critical disagreement adjudication' -FileCount 1 -RequestedEffort Ultra
    Assert-Equal 'criticalDisagreement' $policy.Classification 'adjudication classification'
    Assert-Equal 'ultra' $policy.GptEffort 'adjudication GPT effort'
    Assert-Equal 'max' $policy.ClaudeEffort 'adjudication Claude effort'
    Assert-Equal 'claude-opus-5' $policy.ClaudeModel 'adjudication reviewer model'
    Assert-True $policy.ReviewerRequired 'adjudication reviewer required'
}

Complete-AiAnalysisTests -Suite 'Effort router'
