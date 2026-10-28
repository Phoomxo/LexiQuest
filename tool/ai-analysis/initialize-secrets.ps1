[CmdletBinding()]
param(
    [ValidateSet('All', 'GptStable', 'ClaudeReviewer')]
    [string]$Provider = 'All',
    [ValidateRange(5, 600)][int]$TimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\config.ps1')
. (Join-Path $PSScriptRoot 'lib\secret-store.ps1')
. (Join-Path $PSScriptRoot 'lib\maxplus-client.ps1')

$config = Get-AiAnalysisConfig -ConfigPath (Join-Path $PSScriptRoot 'config.json')
$targets = switch ($Provider) {
    'GptStable' { @($config.providers.gptStable) }
    'ClaudeReviewer' { @($config.providers.claudeReviewer) }
    default { @($config.providers.gptStable, $config.providers.claudeReviewer) }
}

foreach ($target in $targets) {
    $secureKey = $null
    try {
        $secureKey = Read-Host -AsSecureString -Prompt "Enter inference key for $($target.pool)"
        if (-not (Test-AiAnalysisInferenceKey -SecureKey $secureKey)) { throw 'invalidInferenceKey' }
        $requiredModels = if ($target.id -ceq 'claude-reviewer') {
            @([string]$target.models.routine, [string]$target.models.deep)
        } else {
            @([string]$target.model)
        }
        $gate = Test-MaxPlusCredential -Provider $target -SecureKey $secureKey -TimeoutSeconds $TimeoutSeconds -RequiredModels $requiredModels
        if (-not $gate.ModelAvailable) { throw 'unsupportedModel' }
        Save-AiAnalysisSecret -SecretId $target.id -SecureKey $secureKey
        Write-Host "Validated and stored $($target.pool) / $($requiredModels -join ', ')."
    } finally {
        $gate = $null
        $requiredModels = $null
        $secureKey = $null
    }
}
