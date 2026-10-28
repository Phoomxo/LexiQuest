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
    [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\config.ps1')
. (Join-Path $PSScriptRoot 'lib\effort-router.ps1')
. (Join-Path $PSScriptRoot 'lib\secret-store.ps1')
. (Join-Path $PSScriptRoot 'lib\context-builder.ps1')
. (Join-Path $PSScriptRoot 'lib\maxplus-client.ps1')
. (Join-Path $PSScriptRoot 'lib\reviewer.ps1')
. (Join-Path $PSScriptRoot 'lib\report-writer.ps1')
. (Join-Path $PSScriptRoot 'lib\analysis-command.ps1')
. (Join-Path $PSScriptRoot 'lib\repository-root.ps1')

$defaultRepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$repositoryRoot = Resolve-AiAnalysisRepositoryRoot -RepositoryRoot $RepositoryRoot -DefaultRoot $defaultRepositoryRoot
$outputRoot = Join-Path $repositoryRoot 'build\ai-analysis'
Invoke-AiAnalysisCommand -Task $Task -Path $Path -ChangedFiles:$ChangedFiles -Effort $Effort -NoReviewer:$NoReviewer -NoReport:$NoReport -TimeoutSeconds $TimeoutSeconds -RepositoryRoot $repositoryRoot -OutputRoot $outputRoot
