[CmdletBinding()]
param(
    [ValidateRange(5, 600)][int]$TimeoutSeconds = 120,
    [switch]$CertifyEfforts,
    [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\config.ps1')
. (Join-Path $PSScriptRoot 'lib\secret-store.ps1')
. (Join-Path $PSScriptRoot 'lib\maxplus-client.ps1')
. (Join-Path $PSScriptRoot 'lib\report-writer.ps1')
. (Join-Path $PSScriptRoot 'lib\smoke-command.ps1')
. (Join-Path $PSScriptRoot 'lib\repository-root.ps1')

$defaultRepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$repositoryRoot = Resolve-AiAnalysisRepositoryRoot -RepositoryRoot $RepositoryRoot -DefaultRoot $defaultRepositoryRoot
Invoke-AiAnalysisProviderSmoke -RepositoryRoot $repositoryRoot -TimeoutSeconds $TimeoutSeconds -CertifyEfforts:$CertifyEfforts
