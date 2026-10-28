Set-StrictMode -Version Latest

function Invoke-AiAnalysisProviderSmoke {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [ValidateRange(5, 600)][int]$TimeoutSeconds = 120,
        [switch]$CertifyEfforts,
        [scriptblock]$SecretReader,
        [scriptblock]$GptTransport,
        [scriptblock]$ClaudeTransport
    )

    $repository = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $config = Get-AiAnalysisConfig -ConfigPath ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\config.json')))
    if ($null -eq $SecretReader) { $SecretReader = { param($secretId) Read-AiAnalysisSecret -SecretId $secretId } }
    $prompt = 'Return only raw JSON: {"conclusion":"ok","findings":[]}. Do not use Markdown fences or add any other text.'
    $gptKey = $null
    $claudeKey = $null
    $sonnetProvider = New-AiAnalysisClaudeProvider -ClaudeConfig $config.providers.claudeReviewer -Model ([string]$config.providers.claudeReviewer.models.routine)
    $opusProvider = New-AiAnalysisClaudeProvider -ClaudeConfig $config.providers.claudeReviewer -Model ([string]$config.providers.claudeReviewer.models.deep)
    $requiredClaudeModels = @([string]$sonnetProvider.model, [string]$opusProvider.model)
    try {
        $gptKey = & $SecretReader 'gpt-stable'
        $claudeKey = & $SecretReader 'claude-reviewer'
        if ($gptKey -isnot [Security.SecureString] -or $claudeKey -isnot [Security.SecureString]) { throw 'secretDecryptFailed' }
        $null = Test-MaxPlusCredential -Provider $config.providers.gptStable -SecureKey $gptKey -TimeoutSeconds $TimeoutSeconds -Transport $GptTransport
        $null = Test-MaxPlusCredential -Provider $config.providers.claudeReviewer -RequiredModels $requiredClaudeModels -SecureKey $claudeKey -TimeoutSeconds $TimeoutSeconds -Transport $ClaudeTransport

        $gpt = Invoke-GptAnalysis -Provider $config.providers.gptStable -SecureKey $gptKey -Prompt $prompt -Effort low -MaxOutputTokens 2048 -TimeoutSeconds $TimeoutSeconds -Transport $GptTransport
        $sonnet = Invoke-ClaudeReview -Provider $sonnetProvider -SecureKey $claudeKey -Prompt $prompt -Effort low -MaxOutputTokens 4096 -TimeoutSeconds $TimeoutSeconds -Transport $ClaudeTransport
        $opus = Invoke-ClaudeReview -Provider $opusProvider -SecureKey $claudeKey -Prompt $prompt -Effort high -MaxOutputTokens 16384 -TimeoutSeconds $TimeoutSeconds -Transport $ClaudeTransport
        if ($gpt.Conclusion -cne 'ok' -or @($gpt.Findings).Count -ne 0 -or
            $sonnet.Conclusion -cne 'ok' -or @($sonnet.Findings).Count -ne 0 -or
            $opus.Conclusion -cne 'ok' -or @($opus.Findings).Count -ne 0) { throw 'smokeUnexpectedResult' }

        $effortSupport = New-Object System.Collections.ArrayList
        [void]$effortSupport.Add([pscustomobject]@{ provider=$config.providers.gptStable.pool; model=$config.providers.gptStable.model; effort='low'; status='supported' })
        [void]$effortSupport.Add([pscustomobject]@{ provider=$sonnetProvider.pool; model=$sonnetProvider.model; effort='low'; status='supported' })
        [void]$effortSupport.Add([pscustomobject]@{ provider=$opusProvider.pool; model=$opusProvider.model; effort='high'; status='supported' })
        if ($CertifyEfforts) {
            foreach ($effort in @('medium', 'high', 'xhigh', 'max', 'ultra')) {
                $status = 'supported'
                $unsupported = $false
                try {
                    $limit = [int]$config.providers.gptStable.outputTokens.PSObject.Properties[$effort].Value
                    $probe = Invoke-GptAnalysis -Provider $config.providers.gptStable -SecureKey $gptKey -Prompt $prompt -Effort $effort -MaxOutputTokens $limit -TimeoutSeconds $TimeoutSeconds -Transport $GptTransport
                    if ($probe.Conclusion -cne 'ok' -or @($probe.Findings).Count -ne 0) { throw 'smokeUnexpectedResult' }
                } catch {
                    if ($_.Exception.Message -ceq 'unsupportedEffort') {
                        $status = 'unsupportedEffort'
                        $unsupported = $true
                    } else { throw }
                } finally {
                    $probe = $null
                }
                [void]$effortSupport.Add([pscustomobject]@{ provider=$config.providers.gptStable.pool; model=$config.providers.gptStable.model; effort=$effort; status=$status })
                if ($unsupported) { break }
            }

            $claudeProbeGroups = @(
                [pscustomobject]@{ Provider=$sonnetProvider; Efforts=@('medium', 'high') },
                [pscustomobject]@{ Provider=$opusProvider; Efforts=@('xhigh', 'max') }
            )
            foreach ($group in $claudeProbeGroups) {
                foreach ($effort in @($group.Efforts)) {
                    $status = 'supported'
                    $unsupported = $false
                    try {
                        $limit = [int]$group.Provider.outputTokens.PSObject.Properties[$effort].Value
                        $probe = Invoke-ClaudeReview -Provider $group.Provider -SecureKey $claudeKey -Prompt $prompt -Effort $effort -MaxOutputTokens $limit -TimeoutSeconds $TimeoutSeconds -Transport $ClaudeTransport
                        if ($probe.Conclusion -cne 'ok' -or @($probe.Findings).Count -ne 0) { throw 'smokeUnexpectedResult' }
                    } catch {
                        if ($_.Exception.Message -ceq 'unsupportedEffort') {
                            $status = 'unsupportedEffort'
                            $unsupported = $true
                        } else { throw }
                    } finally {
                        $probe = $null
                    }
                    [void]$effortSupport.Add([pscustomobject]@{ provider=$group.Provider.pool; model=$group.Provider.model; effort=$effort; status=$status })
                    if ($unsupported) { break }
                }
            }
        }

        $recordedAt = [DateTime]::UtcNow
        $runName = $recordedAt.ToString('yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $smokeRoot = Resolve-AiAnalysisSafeOutputRoot -RepositoryRoot $repository -OutputRoot (Join-Path $repository 'build\ai-analysis\smoke')
        $runDirectory = Join-Path $smokeRoot $runName
        [System.IO.Directory]::CreateDirectory($runDirectory) | Out-Null
        try {
            $providers = @(@($gpt, $sonnet, $opus) | ForEach-Object { ConvertTo-AiAnalysisProviderMetadata $_ })
            $metadata = [ordered]@{
                schemaVersion = 1
                outcome = 'pass'
                providers = $providers
                effortCertificationPerformed = [bool]$CertifyEfforts
                effortSupport = @($effortSupport)
                recordedAtUtc = $recordedAt.ToString('o')
            }
            $temporary = Join-Path $runDirectory 'metadata.json.tmp'
            [System.IO.File]::WriteAllText($temporary, ($metadata | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
            [System.IO.File]::Move($temporary, (Join-Path $runDirectory 'metadata.json'))
            return [pscustomobject]@{ Outcome='pass'; Path=$runDirectory; Providers=@($providers | ForEach-Object { $_.model }) }
        } catch {
            if (Test-Path -LiteralPath $runDirectory) { Remove-Item -LiteralPath $runDirectory -Recurse -Force }
            throw
        }
    } finally {
        $prompt = $null
        $gpt = $null
        $sonnet = $null
        $opus = $null
        $effortSupport = $null
        $claudeProbeGroups = $null
        $requiredClaudeModels = $null
        $sonnetProvider = $null
        $opusProvider = $null
        $gptKey = $null
        $claudeKey = $null
    }
}
