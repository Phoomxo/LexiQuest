Set-StrictMode -Version Latest

function Invoke-AiAnalysisCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Task,
        [string[]]$Path = @(),
        [switch]$ChangedFiles,
        [ValidateSet('Auto', 'Low', 'Medium', 'High', 'XHigh', 'ExtraHigh', 'ExtendedHigh', 'Max', 'Ultra')]
        [string]$Effort = 'Auto',
        [switch]$NoReviewer,
        [switch]$NoReport,
        [ValidateRange(5, 600)][int]$TimeoutSeconds = 120,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$OutputRoot,
        [scriptblock]$SecretReader,
        [scriptblock]$GptTransport,
        [scriptblock]$ClaudeTransport
    )

    if ($ChangedFiles -and @($Path).Count -gt 0) { throw 'ambiguousScope' }
    $repository = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $repository 'build\ai-analysis' }
    $OutputRoot = Resolve-AiAnalysisSafeOutputRoot -RepositoryRoot $repository -OutputRoot $OutputRoot
    if ($null -eq $SecretReader) {
        $SecretReader = { param($secretId) Read-AiAnalysisSecret -SecretId $secretId }
    }

    $configPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\config.json'))
    $config = Get-AiAnalysisConfig -ConfigPath $configPath
    Remove-ExpiredAiAnalysisReports -OutputRoot $OutputRoot -RetentionDays $config.retentionDays

    if ($ChangedFiles -or @($Path).Count -eq 0) {
        $context = New-AiAnalysisContext -RepositoryRoot $repository -Config $config -ChangedFiles
    } else {
        $context = New-AiAnalysisContext -RepositoryRoot $repository -Config $config -Paths $Path
    }
    $policy = Resolve-AiAnalysisPolicy -Task $Task -FileCount @($context.Files).Count -RequestedEffort $Effort -NoReviewer:$NoReviewer
    $claudeProvider = $null
    if ($policy.ReviewerRequired) {
        $claudeProvider = New-AiAnalysisClaudeProvider -ClaudeConfig $config.providers.claudeReviewer -Model ([string]$policy.ClaudeModel)
    }

    $gptKey = $null
    $claudeKey = $null
    try {
        $gptKey = & $SecretReader 'gpt-stable'
        if ($gptKey -isnot [Security.SecureString]) { throw 'secretDecryptFailed' }
        $null = Test-MaxPlusCredential -Provider $config.providers.gptStable -SecureKey $gptKey -TimeoutSeconds $TimeoutSeconds -Transport $GptTransport

        if ($policy.ReviewerRequired) {
            $claudeKey = & $SecretReader 'claude-reviewer'
            if ($claudeKey -isnot [Security.SecureString]) { throw 'secretDecryptFailed' }
            $null = Test-MaxPlusCredential -Provider $claudeProvider -SecureKey $claudeKey -TimeoutSeconds $TimeoutSeconds -Transport $ClaudeTransport
        }

        $primaryInvoker = {
            param($prompt, $providerEffort, $maxTokens)
            Invoke-GptAnalysis -Provider $config.providers.gptStable -SecureKey $gptKey -Prompt $prompt -Effort $providerEffort -MaxOutputTokens $maxTokens -TimeoutSeconds $TimeoutSeconds -Transport $GptTransport
        }.GetNewClosure()
        $reviewerInvoker = {
            param($prompt, $providerEffort, $maxTokens)
            Invoke-ClaudeReview -Provider $claudeProvider -SecureKey $claudeKey -Prompt $prompt -Effort $providerEffort -MaxOutputTokens $maxTokens -TimeoutSeconds $TimeoutSeconds -Transport $ClaudeTransport
        }.GetNewClosure()
        $adjudicatorInvoker = {
            param($prompt, $providerEffort, $maxTokens)
            Invoke-GptAnalysis -Provider $config.providers.gptStable -SecureKey $gptKey -Prompt $prompt -Effort $providerEffort -MaxOutputTokens $maxTokens -TimeoutSeconds $TimeoutSeconds -Transport $GptTransport
        }.GetNewClosure()

        $result = Invoke-AiAnalysisReview -Task $Task -Context $context -Policy $policy -PrimaryInvoker $primaryInvoker -ReviewerInvoker $reviewerInvoker -AdjudicatorInvoker $adjudicatorInvoker
        $result | Add-Member -NotePropertyName Task -NotePropertyValue $Task

        $commitSha = [string](& git -C $repository rev-parse HEAD 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'gitStateFailed' }
        $dirtyOutput = @(& git -C $repository status --porcelain --untracked-files=no 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'gitStateFailed' }
        $scope = [pscustomobject]@{
            Files = @($context.Files)
            CommitSha = $commitSha.Trim()
            Dirty = @($dirtyOutput | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0
        }
        $report = Write-AiAnalysisReport -Result $result -Scope $scope -RepositoryRoot $repository -OutputRoot $OutputRoot -RetentionDays $config.retentionDays -NoReport:$NoReport
        Remove-ExpiredAiAnalysisReports -OutputRoot $OutputRoot -RetentionDays $config.retentionDays
        return [pscustomobject]@{
            Result = $result
            Report = $report
            Context = $context
            Policy = $policy
        }
    } finally {
        $primaryInvoker = $null
        $reviewerInvoker = $null
        $adjudicatorInvoker = $null
        $claudeProvider = $null
        $gptKey = $null
        $claudeKey = $null
    }
}
