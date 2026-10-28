[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Command,
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$Task,
    [string[]]$Path = @(),
    [ValidateSet('Auto','Low','Medium','High','XHigh','ExtraHigh','ExtendedHigh','Max','Ultra')][string]$Effort = 'Auto',
    [ValidateSet('All','GptStable','ClaudeReviewer')][string]$Provider = 'All',
    [switch]$ChangedFiles,
    [switch]$NoReviewer,
    [switch]$NoReport,
    [ValidateRange(5,600)][int]$TimeoutSeconds = 120,
    [Parameter(ValueFromRemainingArguments=$true)][object[]]$RemainingArguments = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$allowedCommands = @('Health','Analyze','Smoke','CertifyEfforts','Initialize','Remove')
if ($Command -cnotin $allowedCommands -or @($RemainingArguments).Count -gt 0) { throw 'invalidRuntimeCommand' }
$allowedParameters = @{
    Health = @('Command','ProjectRoot')
    Analyze = @('Command','ProjectRoot','Task','Path','Effort','ChangedFiles','NoReviewer','NoReport','TimeoutSeconds')
    Smoke = @('Command','ProjectRoot','TimeoutSeconds')
    CertifyEfforts = @('Command','ProjectRoot','TimeoutSeconds')
    Initialize = @('Command','ProjectRoot','Provider','TimeoutSeconds')
    Remove = @('Command','ProjectRoot','Provider')
}
$invalidBoundParameters = @($PSBoundParameters.Keys | Where-Object {
    $_ -cne 'RemainingArguments' -and $_ -cnotin @($allowedParameters[$Command])
})
if ($invalidBoundParameters.Count -gt 0) { throw 'invalidRuntimeCommand' }

$installRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$activePath = Join-Path $installRoot 'active-runtime.json'
if (-not [IO.File]::Exists($activePath)) { throw 'runtimeMissing' }
try {
    $active = Get-Content -LiteralPath $activePath -Raw -Encoding utf8 | ConvertFrom-Json
} catch {
    throw 'runtimeIntegrityFailure'
}
if ([int]$active.schemaVersion -ne 1 -or [string]$active.projectId -cne 'lexiquest' -or [string]$active.sourceCommit -cnotmatch '^[a-f0-9]{40}$') {
    throw 'runtimeIntegrityFailure'
}

$expectedRuntime = [IO.Path]::GetFullPath((Join-Path $installRoot "runtime\$([string]$active.sourceCommit)"))
try { $activeRuntime = [IO.Path]::GetFullPath([string]$active.runtimePath) } catch { throw 'runtimeIntegrityFailure' }
if (-not [string]::Equals($expectedRuntime.TrimEnd('\','/'), $activeRuntime.TrimEnd('\','/'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'runtimeIntegrityFailure'
}

$manifestPath = Join-Path $expectedRuntime 'runtime-manifest.json'
if (-not [IO.File]::Exists($manifestPath)) { throw 'runtimeIntegrityFailure' }
$launcherHash = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
$manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($launcherHash -cne [string]$active.launcherSha256 -or $manifestHash -cne [string]$active.runtimeManifestSha256) {
    throw 'runtimeIntegrityFailure'
}

try {
    $runtimeManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
} catch {
    throw 'runtimeIntegrityFailure'
}
$expectedManifestProperties = @('files','gitCommonDirectory','installedAtUtc','projectId','runtimePath','schemaVersion','sourceCommit')
$actualManifestProperties = @($runtimeManifest.PSObject.Properties.Name | Sort-Object)
if ((ConvertTo-Json $expectedManifestProperties -Compress) -cne (ConvertTo-Json $actualManifestProperties -Compress) -or
    [int]$runtimeManifest.schemaVersion -ne 1 -or [string]$runtimeManifest.projectId -cne 'lexiquest' -or
    [string]$runtimeManifest.sourceCommit -cne [string]$active.sourceCommit -or
    -not [string]::Equals(([IO.Path]::GetFullPath([string]$runtimeManifest.runtimePath)).TrimEnd('\','/'), $expectedRuntime.TrimEnd('\','/'), [StringComparison]::OrdinalIgnoreCase) -or
    -not [string]::Equals(([IO.Path]::GetFullPath([string]$runtimeManifest.gitCommonDirectory)).TrimEnd('\','/'), ([IO.Path]::GetFullPath([string]$active.gitCommonDirectory)).TrimEnd('\','/'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'runtimeIntegrityFailure'
}
$expectedRuntimeFiles = @(
    'config.json','initialize-secrets.ps1','invoke-analysis.ps1','remove-secrets.ps1','test-provider-smoke.ps1',
    'lib/analysis-command.ps1','lib/config.ps1','lib/context-builder.ps1','lib/effort-router.ps1','lib/maxplus-client.ps1',
    'lib/project-binding.ps1','lib/repository-root.ps1','lib/report-writer.ps1','lib/reviewer.ps1','lib/runtime-health.ps1',
    'lib/secret-store.ps1','lib/smoke-command.ps1'
) | Sort-Object
$actualRuntimeFiles = @($runtimeManifest.files | ForEach-Object { [string]$_.path } | Sort-Object)
if ((ConvertTo-Json $expectedRuntimeFiles -Compress) -cne (ConvertTo-Json $actualRuntimeFiles -Compress)) { throw 'runtimeIntegrityFailure' }
foreach ($record in @($runtimeManifest.files)) {
    $relativePath = [string]$record.path
    if ($relativePath -notmatch '^[a-zA-Z0-9._/-]+$' -or $relativePath -match '(^|/)\.\.(/|$)' -or [string]$record.sha256 -cnotmatch '^[a-f0-9]{64}$') {
        throw 'runtimeIntegrityFailure'
    }
    $runtimeFile = Join-Path $expectedRuntime $relativePath.Replace('/','\')
    if (-not [IO.File]::Exists($runtimeFile) -or (Get-FileHash -LiteralPath $runtimeFile -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$record.sha256) {
        throw 'runtimeIntegrityFailure'
    }
}
$installedRuntimeFiles = @(Get-ChildItem -LiteralPath $expectedRuntime -Recurse -File | ForEach-Object {
    $_.FullName.Substring($expectedRuntime.Length + 1).Replace('\','/')
} | Sort-Object)
$allowedInstalledFiles = @($expectedRuntimeFiles + 'runtime-manifest.json' | Sort-Object)
if ((ConvertTo-Json $installedRuntimeFiles -Compress) -cne (ConvertTo-Json $allowedInstalledFiles -Compress)) { throw 'runtimeIntegrityFailure' }

. (Join-Path $expectedRuntime 'lib\repository-root.ps1')
. (Join-Path $expectedRuntime 'lib\project-binding.ps1')
. (Join-Path $expectedRuntime 'lib\secret-store.ps1')
. (Join-Path $expectedRuntime 'lib\runtime-health.ps1')

$requiresSecrets = $Command -cin @('Health','Analyze','Smoke','CertifyEfforts')
$health = Test-AiAnalysisProjectRuntime -InstallRoot $installRoot -ProjectRoot $ProjectRoot -RequireSecrets:$requiresSecrets

switch ($Command) {
    'Health' {
        $health | ConvertTo-Json -Compress
        return
    }
    'Analyze' {
        if ([string]::IsNullOrWhiteSpace($Task)) { throw 'invalidRuntimeCommand' }
        $arguments = @{
            Task = $Task
            RepositoryRoot = $ProjectRoot
            Effort = $Effort
            TimeoutSeconds = $TimeoutSeconds
        }
        if (@($Path).Count -gt 0) { $arguments.Path = $Path }
        if ($ChangedFiles) { $arguments.ChangedFiles = $true }
        if ($NoReviewer) { $arguments.NoReviewer = $true }
        if ($NoReport) { $arguments.NoReport = $true }
        & (Join-Path $expectedRuntime 'invoke-analysis.ps1') @arguments
        return
    }
    'Smoke' {
        if (-not [string]::IsNullOrWhiteSpace($Task) -or @($Path).Count -gt 0 -or $ChangedFiles -or $NoReviewer -or $NoReport -or $Effort -cne 'Auto') {
            throw 'invalidRuntimeCommand'
        }
        & (Join-Path $expectedRuntime 'test-provider-smoke.ps1') -RepositoryRoot $ProjectRoot -TimeoutSeconds $TimeoutSeconds
        return
    }
    'CertifyEfforts' {
        if (-not [string]::IsNullOrWhiteSpace($Task) -or @($Path).Count -gt 0 -or $ChangedFiles -or $NoReviewer -or $NoReport -or $Effort -cne 'Auto') {
            throw 'invalidRuntimeCommand'
        }
        & (Join-Path $expectedRuntime 'test-provider-smoke.ps1') -RepositoryRoot $ProjectRoot -TimeoutSeconds $TimeoutSeconds -CertifyEfforts
        return
    }
    'Initialize' {
        & (Join-Path $expectedRuntime 'initialize-secrets.ps1') -Provider $Provider -TimeoutSeconds $TimeoutSeconds
        return
    }
    'Remove' {
        & (Join-Path $expectedRuntime 'remove-secrets.ps1') -Provider $Provider
        return
    }
    default { throw 'invalidRuntimeCommand' }
}
