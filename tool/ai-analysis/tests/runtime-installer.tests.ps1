Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..\lib\project-binding.ps1')
. (Join-Path $PSScriptRoot '..\lib\runtime-installer.ps1')

function New-InstallerFixture {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('lexiquest-installer-' + [guid]::NewGuid().ToString('N'))
    $source = Join-Path $root 'source'
    $project = Join-Path $root 'project'
    $projectB = Join-Path $root 'project-b'
    $common = Join-Path $root 'common\.git'
    $install = Join-Path $root 'install'
    foreach ($directory in @($source, $project, $projectB, $common, $install)) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }
    foreach ($relativePath in @(Get-AiAnalysisRuntimeRelativePaths)) {
        $path = Join-Path $source $relativePath
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
        [IO.File]::WriteAllText($path, "fixture:$($relativePath -replace '\\','/')", (New-Object Text.UTF8Encoding($false)))
    }
    $launcher = Join-Path $source 'runtime\lexiquest-ai-analysis.ps1'
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($launcher)) | Out-Null
    [IO.File]::WriteAllText($launcher, 'fixture launcher', (New-Object Text.UTF8Encoding($false)))
    return [pscustomobject]@{ Root=$root; Source=$source; Project=$project; ProjectB=$projectB; Common=$common; Install=$install }
}

function Get-FixtureGitInvoker {
    param([Parameter(Mandatory)][string]$CommonDirectory)
    return { param($workingDirectory) [pscustomobject]@{ ExitCode=0; Output=$CommonDirectory } }.GetNewClosure()
}

function Remove-InstallerFixture {
    param([Parameter(Mandatory)]$Fixture)
    if ([IO.Directory]::Exists($Fixture.Root)) {
        [IO.Directory]::Delete($Fixture.Root, $true)
    }
}

$commitA = 'a' * 40
$commitB = 'b' * 40
$installedAt = [datetime]'2026-08-01T01:02:03Z'

Invoke-AiAnalysisTest 'uses the exact runtime allowlist' {
    $expectedPaths = @(
        'config.json','initialize-secrets.ps1','invoke-analysis.ps1','remove-secrets.ps1','test-provider-smoke.ps1',
        'lib\analysis-command.ps1','lib\config.ps1','lib\context-builder.ps1','lib\effort-router.ps1','lib\maxplus-client.ps1',
        'lib\project-binding.ps1','lib\repository-root.ps1','lib\report-writer.ps1','lib\reviewer.ps1','lib\runtime-health.ps1',
        'lib\secret-store.ps1','lib\smoke-command.ps1'
    )
    Assert-Equal $expectedPaths @(Get-AiAnalysisRuntimeRelativePaths) 'exact allowlist'
}

Invoke-AiAnalysisTest 'copies only allowlisted files with matching hashes' {
    $fixture = New-InstallerFixture
    try {
        [IO.File]::WriteAllText((Join-Path $fixture.Source 'not-allowed.txt'), 'exclude')
        $result = Install-AiAnalysisProjectRuntime -SourceRoot $fixture.Source -ProjectRoot $fixture.Project -InstallRoot $fixture.Install -SourceCommit $commitA -GitInvoker (Get-FixtureGitInvoker $fixture.Common) -UtcNow { $installedAt }
        $manifestPath = Join-Path $result.RuntimePath 'runtime-manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
        $installedRelative = @(Get-ChildItem -LiteralPath $result.RuntimePath -Recurse -File | ForEach-Object {
            $_.FullName.Substring($result.RuntimePath.Length + 1).Replace('\','/')
        } | Where-Object { $_ -cne 'runtime-manifest.json' } | Sort-Object)
        Assert-Equal @((Get-AiAnalysisRuntimeRelativePaths) | ForEach-Object { $_.Replace('\','/') } | Sort-Object) $installedRelative 'installed files'
        foreach ($record in @($manifest.files)) {
            $path = Join-Path $result.RuntimePath ([string]$record.path).Replace('/','\')
            Assert-Equal ([string]$record.sha256) ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()) "hash $($record.path)"
        }
        Assert-False (Test-Path (Join-Path $result.RuntimePath 'not-allowed.txt')) 'extra file excluded'
    } finally { Remove-InstallerFixture $fixture }
}

Invoke-AiAnalysisTest 'pins the active runtime and runtime manifest hash' {
    $fixture = New-InstallerFixture
    try {
        $result = Install-AiAnalysisProjectRuntime -SourceRoot $fixture.Source -ProjectRoot $fixture.Project -InstallRoot $fixture.Install -SourceCommit $commitA -GitInvoker (Get-FixtureGitInvoker $fixture.Common) -UtcNow { $installedAt }
        $active = Get-Content -LiteralPath (Join-Path $fixture.Install 'active-runtime.json') -Raw -Encoding utf8 | ConvertFrom-Json
        Assert-Equal 1 ([int]$active.schemaVersion) 'active schema'
        Assert-Equal 'lexiquest' ([string]$active.projectId) 'active project'
        Assert-Equal $commitA ([string]$active.sourceCommit) 'active commit'
        Assert-Equal $result.RuntimePath ([string]$active.runtimePath) 'active runtime path'
        $manifestHash = (Get-FileHash -LiteralPath (Join-Path $result.RuntimePath 'runtime-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-Equal $manifestHash ([string]$active.runtimeManifestSha256) 'manifest hash pinned'
    } finally { Remove-InstallerFixture $fixture }
}

Invoke-AiAnalysisTest 'preserves the active manifest when a source file is missing' {
    $fixture = New-InstallerFixture
    try {
        $null = Install-AiAnalysisProjectRuntime -SourceRoot $fixture.Source -ProjectRoot $fixture.Project -InstallRoot $fixture.Install -SourceCommit $commitA -GitInvoker (Get-FixtureGitInvoker $fixture.Common) -UtcNow { $installedAt }
        $activePath = Join-Path $fixture.Install 'active-runtime.json'
        $before = [IO.File]::ReadAllBytes($activePath)
        [IO.File]::Delete((Join-Path $fixture.Source 'lib\reviewer.ps1'))
        Assert-Throws { Install-AiAnalysisProjectRuntime -SourceRoot $fixture.Source -ProjectRoot $fixture.Project -InstallRoot $fixture.Install -SourceCommit $commitB -GitInvoker (Get-FixtureGitInvoker $fixture.Common) -UtcNow { $installedAt } } 'runtimeSourceIncomplete'
        Assert-Equal $before ([IO.File]::ReadAllBytes($activePath)) 'active bytes preserved'
    } finally { Remove-InstallerFixture $fixture }
}

Invoke-AiAnalysisTest 'reuses a verified immutable runtime for the same commit' {
    $fixture = New-InstallerFixture
    try {
        $first = Install-AiAnalysisProjectRuntime -SourceRoot $fixture.Source -ProjectRoot $fixture.Project -InstallRoot $fixture.Install -SourceCommit $commitA -GitInvoker (Get-FixtureGitInvoker $fixture.Common) -UtcNow { $installedAt }
        $second = Install-AiAnalysisProjectRuntime -SourceRoot $fixture.Source -ProjectRoot $fixture.Project -InstallRoot $fixture.Install -SourceCommit $commitA -GitInvoker (Get-FixtureGitInvoker $fixture.Common) -UtcNow { [datetime]'2026-08-02T01:02:03Z' }
        Assert-Equal $first.RuntimePath $second.RuntimePath 'same runtime path'
        Assert-Equal 1 @(Get-ChildItem -LiteralPath (Join-Path $fixture.Install 'runtime') -Directory | Where-Object { $_.Name -notlike '.*.staging-*' }).Count 'one immutable runtime'
    } finally { Remove-InstallerFixture $fixture }
}

Invoke-AiAnalysisTest 'keeps same-commit runtime metadata neutral across worktrees' {
    $fixture = New-InstallerFixture
    try {
        $null = Install-AiAnalysisProjectRuntime -SourceRoot $fixture.Source -ProjectRoot $fixture.Project -InstallRoot $fixture.Install -SourceCommit $commitA -GitInvoker (Get-FixtureGitInvoker $fixture.Common) -UtcNow { $installedAt }
        $result = Install-AiAnalysisProjectRuntime -SourceRoot $fixture.Source -ProjectRoot $fixture.ProjectB -InstallRoot $fixture.Install -SourceCommit $commitA -GitInvoker (Get-FixtureGitInvoker $fixture.Common) -UtcNow { [datetime]'2026-08-02T01:02:03Z' }
        $active = Get-Content -LiteralPath (Join-Path $fixture.Install 'active-runtime.json') -Raw -Encoding utf8 | ConvertFrom-Json
        $runtime = Get-Content -LiteralPath (Join-Path $result.RuntimePath 'runtime-manifest.json') -Raw -Encoding utf8 | ConvertFrom-Json
        Assert-False ($active.PSObject.Properties.Name -contains 'projectRoot') 'active manifest worktree neutral'
        Assert-False ($runtime.PSObject.Properties.Name -contains 'projectRoot') 'runtime manifest worktree neutral'
        Assert-Equal $fixture.Common ([string]$active.gitCommonDirectory) 'active common directory'
        Assert-Equal $fixture.Common ([string]$runtime.gitCommonDirectory) 'runtime common directory'
    } finally { Remove-InstallerFixture $fixture }
}

Invoke-AiAnalysisTest 'rejects a conflicting existing same-commit runtime' {
    $fixture = New-InstallerFixture
    try {
        $result = Install-AiAnalysisProjectRuntime -SourceRoot $fixture.Source -ProjectRoot $fixture.Project -InstallRoot $fixture.Install -SourceCommit $commitA -GitInvoker (Get-FixtureGitInvoker $fixture.Common) -UtcNow { $installedAt }
        [IO.File]::AppendAllText((Join-Path $result.RuntimePath 'config.json'), 'tampered')
        Assert-Throws { Install-AiAnalysisProjectRuntime -SourceRoot $fixture.Source -ProjectRoot $fixture.Project -InstallRoot $fixture.Install -SourceCommit $commitA -GitInvoker (Get-FixtureGitInvoker $fixture.Common) -UtcNow { $installedAt } } 'runtimeIntegrityFailure'
    } finally { Remove-InstallerFixture $fixture }
}

Invoke-AiAnalysisTest 'rejects a self-consistent tampered runtime and manifest' {
    $fixture = New-InstallerFixture
    try {
        $result = Install-AiAnalysisProjectRuntime -SourceRoot $fixture.Source -ProjectRoot $fixture.Project -InstallRoot $fixture.Install -SourceCommit $commitA -GitInvoker (Get-FixtureGitInvoker $fixture.Common) -UtcNow { $installedAt }
        $configPath = Join-Path $result.RuntimePath 'config.json'
        [IO.File]::WriteAllText($configPath, 'tampered', (New-Object Text.UTF8Encoding($false)))
        $manifestPath = Join-Path $result.RuntimePath 'runtime-manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
        $configRecord = @($manifest.files | Where-Object { [string]$_.path -ceq 'config.json' })[0]
        $configRecord.sha256 = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash.ToLowerInvariant()
        [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
        Assert-Throws { Install-AiAnalysisProjectRuntime -SourceRoot $fixture.Source -ProjectRoot $fixture.Project -InstallRoot $fixture.Install -SourceCommit $commitA -GitInvoker (Get-FixtureGitInvoker $fixture.Common) -UtcNow { $installedAt } } 'runtimeIntegrityFailure'
    } finally { Remove-InstallerFixture $fixture }
}

Invoke-AiAnalysisTest 'cleans task-owned staging directories after success and failure' {
    $fixture = New-InstallerFixture
    try {
        $null = Install-AiAnalysisProjectRuntime -SourceRoot $fixture.Source -ProjectRoot $fixture.Project -InstallRoot $fixture.Install -SourceCommit $commitA -GitInvoker (Get-FixtureGitInvoker $fixture.Common) -UtcNow { $installedAt }
        Assert-Equal 0 @(Get-ChildItem -LiteralPath (Join-Path $fixture.Install 'runtime') -Directory -Filter '.*.staging-*').Count 'no staging after success'
        [IO.File]::Delete((Join-Path $fixture.Source 'config.json'))
        Assert-Throws { Install-AiAnalysisProjectRuntime -SourceRoot $fixture.Source -ProjectRoot $fixture.Project -InstallRoot $fixture.Install -SourceCommit $commitB -GitInvoker (Get-FixtureGitInvoker $fixture.Common) -UtcNow { $installedAt } } 'runtimeSourceIncomplete'
        Assert-Equal 0 @(Get-ChildItem -LiteralPath (Join-Path $fixture.Install 'runtime') -Directory -Filter '.*.staging-*').Count 'no staging after failure'
    } finally { Remove-InstallerFixture $fixture }
}

Invoke-AiAnalysisTest 'keeps launcher and active manifest consistent when post-commit cleanup fails' {
    $fixture = New-InstallerFixture
    try {
        $null = Install-AiAnalysisProjectRuntime -SourceRoot $fixture.Source -ProjectRoot $fixture.Project -InstallRoot $fixture.Install -SourceCommit $commitA -GitInvoker (Get-FixtureGitInvoker $fixture.Common) -UtcNow { $installedAt }
        [IO.File]::AppendAllText((Join-Path $fixture.Source 'runtime\lexiquest-ai-analysis.ps1'), ' updated')
        $fileDelete = {
            param($path)
            if ([IO.Path]::GetFileName($path) -like '.active-runtime.*.backup') { throw 'simulatedCleanupFailure' }
            [IO.File]::Delete($path)
        }
        Assert-Throws { Install-AiAnalysisProjectRuntime -SourceRoot $fixture.Source -ProjectRoot $fixture.Project -InstallRoot $fixture.Install -SourceCommit $commitA -GitInvoker (Get-FixtureGitInvoker $fixture.Common) -UtcNow { $installedAt } -FileDelete $fileDelete } 'activationCleanupFailed'
        $active = Get-Content -LiteralPath (Join-Path $fixture.Install 'active-runtime.json') -Raw -Encoding utf8 | ConvertFrom-Json
        $launcherPath = Join-Path $fixture.Install 'bin\lexiquest-ai-analysis.ps1'
        Assert-Equal ([string]$active.launcherSha256) ((Get-FileHash -LiteralPath $launcherPath -Algorithm SHA256).Hash.ToLowerInvariant()) 'active and launcher remain consistent'
    } finally { Remove-InstallerFixture $fixture }
}

Complete-AiAnalysisTests -Suite 'Runtime installer'
