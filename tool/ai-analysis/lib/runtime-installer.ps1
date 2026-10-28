Set-StrictMode -Version Latest

function Get-AiAnalysisRuntimeRelativePaths {
    return @(
        'config.json',
        'initialize-secrets.ps1',
        'invoke-analysis.ps1',
        'remove-secrets.ps1',
        'test-provider-smoke.ps1',
        'lib\analysis-command.ps1',
        'lib\config.ps1',
        'lib\context-builder.ps1',
        'lib\effort-router.ps1',
        'lib\maxplus-client.ps1',
        'lib\project-binding.ps1',
        'lib\repository-root.ps1',
        'lib\report-writer.ps1',
        'lib\reviewer.ps1',
        'lib\runtime-health.ps1',
        'lib\secret-store.ps1',
        'lib\smoke-command.ps1'
    )
}

function Write-AiAnalysisUtf8Json {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
}

function Get-AiAnalysisSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Remove-AiAnalysisOwnedStagingDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RuntimeRoot,
        [Parameter(Mandatory)][string]$SourceCommit
    )

    if (-not [IO.Directory]::Exists($Path)) { return }
    $resolvedPath = ConvertTo-AiAnalysisCanonicalDirectoryPath -Path $Path
    $resolvedRuntimeRoot = ConvertTo-AiAnalysisCanonicalDirectoryPath -Path $RuntimeRoot
    $parent = ConvertTo-AiAnalysisCanonicalDirectoryPath -Path ([IO.Path]::GetDirectoryName($resolvedPath))
    $leaf = [IO.Path]::GetFileName($resolvedPath)
    $expectedPattern = '^\.' + [regex]::Escape($SourceCommit) + '\.staging-[a-f0-9]{32}$'
    if (-not [string]::Equals($parent, $resolvedRuntimeRoot, [StringComparison]::OrdinalIgnoreCase) -or $leaf -cnotmatch $expectedPattern) {
        throw 'unsafeRuntimeCleanup'
    }
    [IO.Directory]::Delete($resolvedPath, $true)
}

function Get-AiAnalysisRuntimeManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RuntimePath,
        [Parameter(Mandatory)][string]$SourceCommit,
        [Parameter(Mandatory)][string]$GitCommonDirectory
    )

    $manifestPath = Join-Path $RuntimePath 'runtime-manifest.json'
    if (-not [IO.File]::Exists($manifestPath)) { throw 'runtimeIntegrityFailure' }
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    } catch {
        throw 'runtimeIntegrityFailure'
    }

    $expectedRuntime = ConvertTo-AiAnalysisCanonicalDirectoryPath -Path $RuntimePath
    $expectedCommon = ConvertTo-AiAnalysisCanonicalDirectoryPath -Path $GitCommonDirectory
    if ([int]$manifest.schemaVersion -ne 1 -or [string]$manifest.projectId -cne 'lexiquest' -or
        [string]$manifest.sourceCommit -cne $SourceCommit -or
        -not [string]::Equals((ConvertTo-AiAnalysisCanonicalDirectoryPath -Path ([string]$manifest.runtimePath)), $expectedRuntime, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals((ConvertTo-AiAnalysisCanonicalDirectoryPath -Path ([string]$manifest.gitCommonDirectory)), $expectedCommon, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'runtimeIntegrityFailure'
    }

    $expectedPaths = @((Get-AiAnalysisRuntimeRelativePaths) | ForEach-Object { $_.Replace('\', '/') } | Sort-Object)
    $actualPaths = @($manifest.files | ForEach-Object { [string]$_.path } | Sort-Object)
    if ((ConvertTo-Json $expectedPaths -Compress) -cne (ConvertTo-Json $actualPaths -Compress)) {
        throw 'runtimeIntegrityFailure'
    }

    foreach ($record in @($manifest.files)) {
        if ([string]$record.path -notmatch '^[a-zA-Z0-9._/-]+$' -or [string]$record.path -match '(^|/)\.\.(/|$)') {
            throw 'runtimeIntegrityFailure'
        }
        $filePath = Join-Path $RuntimePath ([string]$record.path).Replace('/', '\')
        if (-not [IO.File]::Exists($filePath) -or (Get-AiAnalysisSha256 -Path $filePath) -cne [string]$record.sha256) {
            throw 'runtimeIntegrityFailure'
        }
    }

    $installedFiles = @(Get-ChildItem -LiteralPath $RuntimePath -Recurse -File | ForEach-Object {
        $_.FullName.Substring($RuntimePath.Length + 1).Replace('\', '/')
    } | Sort-Object)
    $allowedFiles = @($expectedPaths + 'runtime-manifest.json' | Sort-Object)
    if ((ConvertTo-Json $installedFiles -Compress) -cne (ConvertTo-Json $allowedFiles -Compress)) {
        throw 'runtimeIntegrityFailure'
    }

    return $manifest
}

function Install-AiAnalysisProjectRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][string]$SourceCommit,
        [scriptblock]$GitInvoker = ${function:Invoke-AiAnalysisGitCommonDirectory},
        [scriptblock]$UtcNow = { [DateTime]::UtcNow },
        [scriptblock]$FileDelete = { param($path) [IO.File]::Delete($path) }
    )

    if ($SourceCommit -cnotmatch '^[a-f0-9]{40}$') { throw 'runtimeSourceCommitInvalid' }
    foreach ($root in @($SourceRoot, $ProjectRoot)) {
        if (-not [IO.Directory]::Exists($root)) { throw 'repositoryRootNotFound' }
    }

    $source = ConvertTo-AiAnalysisCanonicalDirectoryPath -Path $SourceRoot
    $project = ConvertTo-AiAnalysisCanonicalDirectoryPath -Path $ProjectRoot
    $install = ConvertTo-AiAnalysisCanonicalDirectoryPath -Path $InstallRoot
    $gitCommonDirectory = Resolve-AiAnalysisGitCommonDirectory -WorkingDirectory $project -GitInvoker $GitInvoker
    $relativePaths = @(Get-AiAnalysisRuntimeRelativePaths)
    foreach ($relativePath in $relativePaths) {
        if (-not [IO.File]::Exists((Join-Path $source $relativePath))) { throw 'runtimeSourceIncomplete' }
    }
    $launcherSource = Join-Path $source 'runtime\lexiquest-ai-analysis.ps1'
    if (-not [IO.File]::Exists($launcherSource)) { throw 'runtimeSourceIncomplete' }

    [IO.Directory]::CreateDirectory($install) | Out-Null
    $runtimeRoot = Join-Path $install 'runtime'
    $binRoot = Join-Path $install 'bin'
    [IO.Directory]::CreateDirectory($runtimeRoot) | Out-Null
    [IO.Directory]::CreateDirectory($binRoot) | Out-Null
    $finalRuntimeRoot = Join-Path $runtimeRoot $SourceCommit
    $stagingRoot = Join-Path $runtimeRoot ('.' + $SourceCommit + '.staging-' + [guid]::NewGuid().ToString('N'))
    $activePath = Join-Path $install 'active-runtime.json'
    $activeTemp = Join-Path $install ('.active-runtime.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $activeBackup = Join-Path $install ('.active-runtime.' + [guid]::NewGuid().ToString('N') + '.backup')
    $launcherPath = Join-Path $binRoot 'lexiquest-ai-analysis.ps1'
    $launcherTemp = Join-Path $install ('.launcher.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $launcherBackup = Join-Path $install ('.launcher.' + [guid]::NewGuid().ToString('N') + '.backup')
    $launcherDiscard = Join-Path $install ('.launcher.' + [guid]::NewGuid().ToString('N') + '.discard')
    $launcherReplaced = $false
    $launcherCreated = $false

    try {
        Copy-Item -LiteralPath $launcherSource -Destination $launcherTemp
        [IO.Directory]::CreateDirectory($stagingRoot) | Out-Null
        foreach ($relativePath in $relativePaths) {
            $destination = Join-Path $stagingRoot $relativePath
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
            Copy-Item -LiteralPath (Join-Path $source $relativePath) -Destination $destination
        }

        $installedAtUtc = (& $UtcNow).ToUniversalTime().ToString('o')
        $hashRecords = @($relativePaths | ForEach-Object {
            $installedPath = Join-Path $stagingRoot $_
            [pscustomobject][ordered]@{
                path = ($_ -replace '\\', '/')
                sha256 = Get-AiAnalysisSha256 -Path $installedPath
            }
        } | Sort-Object path)

        $runtimeManifest = [pscustomobject][ordered]@{
            schemaVersion = 1
            projectId = 'lexiquest'
            sourceCommit = $SourceCommit
            gitCommonDirectory = $gitCommonDirectory
            runtimePath = $finalRuntimeRoot
            installedAtUtc = $installedAtUtc
            files = $hashRecords
        }
        Write-AiAnalysisUtf8Json -Path (Join-Path $stagingRoot 'runtime-manifest.json') -Value $runtimeManifest

        if ([IO.Directory]::Exists($finalRuntimeRoot)) {
            $existingManifest = Get-AiAnalysisRuntimeManifest -RuntimePath $finalRuntimeRoot -SourceCommit $SourceCommit -GitCommonDirectory $gitCommonDirectory
            $stagedHashes = @($hashRecords | ForEach-Object {
                [pscustomobject][ordered]@{ path = [string]$_.path; sha256 = [string]$_.sha256 }
            } | Sort-Object path)
            $existingHashes = @($existingManifest.files | ForEach-Object {
                [pscustomobject][ordered]@{ path = [string]$_.path; sha256 = [string]$_.sha256 }
            } | Sort-Object path)
            if ((ConvertTo-Json $stagedHashes -Depth 4 -Compress) -cne (ConvertTo-Json $existingHashes -Depth 4 -Compress)) {
                throw 'runtimeIntegrityFailure'
            }
            Remove-AiAnalysisOwnedStagingDirectory -Path $stagingRoot -RuntimeRoot $runtimeRoot -SourceCommit $SourceCommit
        } else {
            [IO.Directory]::Move($stagingRoot, $finalRuntimeRoot)
        }

        $manifestPath = Join-Path $finalRuntimeRoot 'runtime-manifest.json'
        $activeManifest = [pscustomobject][ordered]@{
            schemaVersion = 1
            projectId = 'lexiquest'
            sourceCommit = $SourceCommit
            gitCommonDirectory = $gitCommonDirectory
            runtimePath = $finalRuntimeRoot
            installedAtUtc = $installedAtUtc
            runtimeManifestSha256 = Get-AiAnalysisSha256 -Path $manifestPath
            launcherSha256 = Get-AiAnalysisSha256 -Path $launcherTemp
        }
        Write-AiAnalysisUtf8Json -Path $activeTemp -Value $activeManifest

        if ([IO.File]::Exists($launcherPath)) {
            [IO.File]::Replace($launcherTemp, $launcherPath, $launcherBackup, $true)
            $launcherReplaced = $true
        } else {
            [IO.File]::Move($launcherTemp, $launcherPath)
            $launcherCreated = $true
        }
        try {
            if ([IO.File]::Exists($activePath)) {
                [IO.File]::Replace($activeTemp, $activePath, $activeBackup, $true)
            } else {
                [IO.File]::Move($activeTemp, $activePath)
            }
        } catch {
            if ($launcherReplaced -and [IO.File]::Exists($launcherBackup)) {
                [IO.File]::Replace($launcherBackup, $launcherPath, $launcherDiscard, $true)
                if ([IO.File]::Exists($launcherDiscard)) { [IO.File]::Delete($launcherDiscard) }
                $launcherReplaced = $false
            } elseif ($launcherCreated -and [IO.File]::Exists($launcherPath)) {
                [IO.File]::Delete($launcherPath)
                $launcherCreated = $false
            }
            throw
        }

        $cleanupFailed = $false
        foreach ($committedBackup in @($activeBackup, $launcherBackup, $launcherDiscard)) {
            if ([IO.File]::Exists($committedBackup)) {
                try { & $FileDelete $committedBackup } catch { $cleanupFailed = $true }
            }
        }
        $launcherReplaced = $false
        $launcherCreated = $false
        if ($cleanupFailed) { throw 'activationCleanupFailed' }

        return [pscustomobject]@{
            ProjectId = 'lexiquest'
            SourceCommit = $SourceCommit
            RuntimePath = $finalRuntimeRoot
            GitCommonDirectory = $gitCommonDirectory
            InstalledAtUtc = $installedAtUtc
        }
    } finally {
        if ([IO.Directory]::Exists($stagingRoot)) {
            Remove-AiAnalysisOwnedStagingDirectory -Path $stagingRoot -RuntimeRoot $runtimeRoot -SourceCommit $SourceCommit
        }
        foreach ($ownedFile in @($activeTemp, $activeBackup, $launcherTemp, $launcherBackup, $launcherDiscard)) {
            if ([IO.File]::Exists($ownedFile)) {
                try { & $FileDelete $ownedFile } catch { }
            }
        }
    }
}
