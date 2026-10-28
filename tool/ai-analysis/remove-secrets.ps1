[CmdletBinding()]
param(
    [ValidateSet('All', 'GptStable', 'ClaudeReviewer')]
    [string]$Provider = 'All'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\secret-store.ps1')

$secretIds = switch ($Provider) {
    'GptStable' { @('gpt-stable') }
    'ClaudeReviewer' { @('claude-reviewer') }
    default { @('gpt-stable', 'claude-reviewer') }
}

$removed = $false
foreach ($secretId in $secretIds) {
    if (Remove-AiAnalysisSecret -SecretId $secretId) { $removed = $true }
}

if ($removed) {
    Write-Host 'Local DPAPI blob removed; revoke or rotate the remote key in MaxPlus separately.'
} else {
    Write-Host 'No local DPAPI blob was present; revoke or rotate the remote key in MaxPlus separately.'
}
