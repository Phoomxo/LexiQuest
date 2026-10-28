Set-StrictMode -Version Latest

function Test-AiAnalysisConfigSequence {
    param($Actual, [string[]]$Expected)
    $actualValues = @($Actual | ForEach-Object { [string]$_ })
    if ($actualValues.Count -ne $Expected.Count) { return $false }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ($actualValues[$index] -cne $Expected[$index]) { return $false }
    }
    return $true
}

function Assert-AiAnalysisConfigInvariant {
    param([bool]$Condition)
    if (-not $Condition) { throw 'invalidConfig' }
}

function New-AiAnalysisClaudeProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ClaudeConfig,
        [Parameter(Mandatory)]
        [ValidateSet('claude-sonnet-5', 'claude-opus-5')]
        [string]$Model
    )

    $provider = $ClaudeConfig.PSObject.Copy()
    $provider | Add-Member -NotePropertyName model -NotePropertyValue $Model -Force
    return $provider
}

function Get-AiAnalysisConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw 'configNotFound'
    }

    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding utf8 | ConvertFrom-Json
    } catch {
        throw 'invalidConfig'
    }

    try {
        foreach ($provider in @($config.providers.gptStable, $config.providers.claudeReviewer)) {
            foreach ($endpoint in @([string]$provider.baseUrl, [string]$provider.accountBaseUrl)) {
                try { $uri = [Uri]$endpoint } catch { throw 'unsafeEndpoint' }
                if ($uri.Scheme -cne 'https' -or
                    $uri.Host -cne 'api.maxplus-ai.cc' -or
                    -not [string]::IsNullOrEmpty($uri.Query) -or
                    -not [string]::IsNullOrEmpty($uri.Fragment) -or
                    -not [string]::IsNullOrEmpty($uri.UserInfo)) {
                    throw 'unsafeEndpoint'
                }
            }
        }

        Assert-AiAnalysisConfigInvariant ([int]$config.schemaVersion -eq 1)
        $gpt = $config.providers.gptStable
        $claude = $config.providers.claudeReviewer

        Assert-AiAnalysisConfigInvariant ($gpt.id -ceq 'gpt-stable')
        Assert-AiAnalysisConfigInvariant ($gpt.pool -ceq 'GPT Pro 20x Stable')
        Assert-AiAnalysisConfigInvariant ($gpt.baseUrl -ceq 'https://api.maxplus-ai.cc/gpt-pro-20x-stable')
        Assert-AiAnalysisConfigInvariant ($gpt.accountBaseUrl -ceq 'https://api.maxplus-ai.cc')
        Assert-AiAnalysisConfigInvariant ($gpt.model -ceq 'gpt-5.6-sol')
        Assert-AiAnalysisConfigInvariant ($gpt.authStyle -ceq 'bearer')
        Assert-AiAnalysisConfigInvariant ($gpt.accountRoute -ceq '/v1/me')
        Assert-AiAnalysisConfigInvariant ($gpt.modelsRoute -ceq '/v1/models')
        Assert-AiAnalysisConfigInvariant ($gpt.generationRoute -ceq '/v1/responses')
        Assert-AiAnalysisConfigInvariant ($gpt.store -is [bool] -and -not $gpt.store)
        Assert-AiAnalysisConfigInvariant (Test-AiAnalysisConfigSequence $gpt.efforts @('low', 'medium', 'high', 'xhigh', 'max', 'ultra'))
        Assert-AiAnalysisConfigInvariant ([int]$gpt.outputTokens.low -eq 2048 -and [int]$gpt.outputTokens.medium -eq 4096 -and
            [int]$gpt.outputTokens.high -eq 8192 -and [int]$gpt.outputTokens.xhigh -eq 32768 -and
            [int]$gpt.outputTokens.max -eq 65536 -and [int]$gpt.outputTokens.ultra -eq 65536)

        Assert-AiAnalysisConfigInvariant ($claude.id -ceq 'claude-reviewer')
        Assert-AiAnalysisConfigInvariant ($claude.pool -ceq 'AWS Lite Ultimate')
        Assert-AiAnalysisConfigInvariant ($claude.baseUrl -ceq 'https://api.maxplus-ai.cc/aws-lite-ultimate')
        Assert-AiAnalysisConfigInvariant ($claude.accountBaseUrl -ceq 'https://api.maxplus-ai.cc')
        Assert-AiAnalysisConfigInvariant (Test-AiAnalysisConfigSequence @($claude.models.PSObject.Properties.Name) @('routine', 'deep'))
        Assert-AiAnalysisConfigInvariant ($claude.models.routine -ceq 'claude-sonnet-5')
        Assert-AiAnalysisConfigInvariant ($claude.models.deep -ceq 'claude-opus-5')
        Assert-AiAnalysisConfigInvariant ($claude.authStyle -ceq 'anthropic')
        Assert-AiAnalysisConfigInvariant ($claude.anthropicVersion -ceq '2023-06-01')
        Assert-AiAnalysisConfigInvariant ($claude.accountRoute -ceq '/v1/me')
        Assert-AiAnalysisConfigInvariant ($claude.modelsRoute -ceq '/v1/models')
        Assert-AiAnalysisConfigInvariant ($claude.generationRoute -ceq '/v1/messages')
        Assert-AiAnalysisConfigInvariant (Test-AiAnalysisConfigSequence $claude.efforts @('low', 'medium', 'high', 'xhigh', 'max'))
        Assert-AiAnalysisConfigInvariant ([int]$claude.outputTokens.low -eq 4096 -and [int]$claude.outputTokens.medium -eq 8192 -and
            [int]$claude.outputTokens.high -eq 16384 -and [int]$claude.outputTokens.xhigh -eq 65536 -and
            [int]$claude.outputTokens.max -eq 65536)

        Assert-AiAnalysisConfigInvariant ([int]$config.context.maxFiles -eq 20)
        Assert-AiAnalysisConfigInvariant ([int]$config.context.maxCharacters -eq 96000)
        Assert-AiAnalysisConfigInvariant ([int]$config.context.maxFileBytes -eq 262144)
        $expectedExtensions = @('.c', '.cc', '.cpp', '.css', '.dart', '.gradle', '.h', '.html', '.java', '.js', '.json', '.kt', '.m', '.md', '.mm', '.ps1', '.rules', '.sql', '.swift', '.toml', '.ts', '.tsx', '.txt', '.xml', '.yaml', '.yml')
        Assert-AiAnalysisConfigInvariant (Test-AiAnalysisConfigSequence $config.context.allowedExtensions $expectedExtensions)
        $expectedDenylist = @('.env*', '*.jks', '*.keystore', '*.p12', '*.pem', '*.key', 'key.properties', 'android/local.properties', 'field/evidence/**', 'build/**', '**/*.dpapi', '**/google-services.json', '**/GoogleService-Info.plist')
        Assert-AiAnalysisConfigInvariant (Test-AiAnalysisConfigSequence $config.context.denylist $expectedDenylist)

        $expectedPatterns = [ordered]@{
            maxplusInferenceKey = '(?<![A-Za-z0-9])ccsk-[a-f0-9]{64}'
            maxplusManagementToken = '(?<![A-Za-z0-9])ccmk-[A-Za-z0-9_-]{16,}'
            openAiKey = '(?<![A-Za-z0-9])sk-(?!ant-)[A-Za-z0-9_-]{20,}'
            anthropicKey = '(?<![A-Za-z0-9])sk-ant-[A-Za-z0-9_-]{20,}'
            geminiKey = '(?<![A-Za-z0-9])AIza[0-9A-Za-z_-]{20,}'
        }
        Assert-AiAnalysisConfigInvariant (@($config.secretPatterns).Count -eq $expectedPatterns.Count)
        $seenPatternIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        foreach ($rule in @($config.secretPatterns)) {
            Assert-AiAnalysisConfigInvariant ($expectedPatterns.Contains([string]$rule.id))
            Assert-AiAnalysisConfigInvariant ($seenPatternIds.Add([string]$rule.id))
            Assert-AiAnalysisConfigInvariant ([string]$rule.pattern -ceq [string]$expectedPatterns[[string]$rule.id])
            $null = [regex]::new([string]$rule.pattern)
        }
        Assert-AiAnalysisConfigInvariant ($seenPatternIds.Count -eq $expectedPatterns.Count)

        Assert-AiAnalysisConfigInvariant ([int]$config.retentionDays -eq 14)
        Assert-AiAnalysisConfigInvariant ([int]$config.timeouts.defaultSeconds -eq 120)
        Assert-AiAnalysisConfigInvariant ([int]$config.timeouts.minimumSeconds -eq 5)
        Assert-AiAnalysisConfigInvariant ([int]$config.timeouts.maximumSeconds -eq 600)
    } catch {
        if ($_.Exception.Message -ceq 'unsafeEndpoint') { throw }
        throw 'invalidConfig'
    }

    return $config
}
