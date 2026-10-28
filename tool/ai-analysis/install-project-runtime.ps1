[CmdletBinding()]
param(
    [string]$ProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\repository-root.ps1')
. (Join-Path $PSScriptRoot 'lib\project-binding.ps1')
. (Join-Path $PSScriptRoot 'lib\runtime-installer.ps1')

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'windowsRequired' }
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'localAppDataUnavailable' }
$requestedDirectory = Resolve-AiAnalysisRepositoryRoot -RepositoryRoot $ProjectRoot -DefaultRoot ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')))

$sourceTopOutput = & git -C $PSScriptRoot rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0) { throw 'gitStateFailed' }
$sourceWorktreeRoot = Resolve-AiAnalysisRepositoryRoot -RepositoryRoot ([string]($sourceTopOutput | Select-Object -First 1)) -DefaultRoot $PSScriptRoot
$sourceToolRoot = ConvertTo-AiAnalysisCanonicalDirectoryPath -Path (Join-Path $sourceWorktreeRoot 'tool\ai-analysis')
if (-not [string]::Equals($sourceToolRoot, (ConvertTo-AiAnalysisCanonicalDirectoryPath -Path $PSScriptRoot), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'runtimeSourceMismatch'
}

$requestedTopOutput = & git -C $requestedDirectory rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0) { throw 'gitStateFailed' }
$ProjectRoot = Resolve-AiAnalysisRepositoryRoot -RepositoryRoot ([string]($requestedTopOutput | Select-Object -First 1)) -DefaultRoot $requestedDirectory
$sourceCommon = Resolve-AiAnalysisGitCommonDirectory -WorkingDirectory $sourceWorktreeRoot
$null = Assert-AiAnalysisProjectBinding -WorkingDirectory $ProjectRoot -ExpectedGitCommonDirectory $sourceCommon

$sourceCommitOutput = & git -C $sourceWorktreeRoot rev-parse HEAD 2>$null
if ($LASTEXITCODE -ne 0) { throw 'gitStateFailed' }
$sourceCommit = ([string]($sourceCommitOutput | Select-Object -First 1)).Trim().ToLowerInvariant()
if ($sourceCommit -cnotmatch '^[a-f0-9]{40}$') { throw 'gitStateFailed' }

$dirtyOutput = @(& git -C $sourceWorktreeRoot status --porcelain --untracked-files=all -- ':(top)tool/ai-analysis' 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'gitStateFailed' }
if (@($dirtyOutput | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) { throw 'runtimeSourceDirty' }

$installRoot = Join-Path $env:LOCALAPPDATA 'LexiQuest\ai-analysis'
$null = Install-AiAnalysisProjectRuntime -SourceRoot $sourceToolRoot -ProjectRoot $ProjectRoot -InstallRoot $installRoot -SourceCommit $sourceCommit

[pscustomobject][ordered]@{
    ProjectId = 'lexiquest'
    SourceCommit = $sourceCommit
    Status = 'installed'
}
