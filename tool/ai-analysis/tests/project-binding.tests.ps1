Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..\lib\project-binding.ps1')

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('lexiquest-binding-' + [guid]::NewGuid().ToString('N'))
$worktreeRoot = Join-Path $tempRoot 'worktree'
$sharedGit = Join-Path $tempRoot 'shared\.git'
$otherRoot = Join-Path $tempRoot 'other'
$otherGit = Join-Path $tempRoot 'other-shared\.git'
$prefixRoot = Join-Path $tempRoot 'prefix'
$prefixGit = Join-Path $tempRoot 'shared\.git-copy'
foreach ($directory in @($worktreeRoot, $sharedGit, $otherRoot, $otherGit, $prefixRoot, $prefixGit)) {
    [IO.Directory]::CreateDirectory($directory) | Out-Null
}

try {
    $gitInvoker = {
        param($workingDirectory)
        [pscustomobject]@{ ExitCode = 0; Output = '..\shared\.git' }
    }

    Invoke-AiAnalysisTest 'resolves a relative Git common directory' {
        $resolved = Resolve-AiAnalysisGitCommonDirectory -WorkingDirectory $worktreeRoot -GitInvoker $gitInvoker
        Assert-Equal ([IO.Path]::GetFullPath($sharedGit)) $resolved 'relative git common dir'
    }

    Invoke-AiAnalysisTest 'accepts an exact project binding' {
        $resolved = Resolve-AiAnalysisGitCommonDirectory -WorkingDirectory $worktreeRoot -GitInvoker $gitInvoker
        Assert-Equal $resolved (Assert-AiAnalysisProjectBinding -WorkingDirectory $worktreeRoot -ExpectedGitCommonDirectory $resolved -GitInvoker $gitInvoker) 'exact binding'
    }

    Invoke-AiAnalysisTest 'accepts Windows path casing differences' {
        $resolved = Resolve-AiAnalysisGitCommonDirectory -WorkingDirectory $worktreeRoot -GitInvoker $gitInvoker
        Assert-Equal $resolved (Assert-AiAnalysisProjectBinding -WorkingDirectory $worktreeRoot -ExpectedGitCommonDirectory $resolved.ToUpperInvariant() -GitInvoker $gitInvoker) 'case insensitive binding'
    }

    Invoke-AiAnalysisTest 'preserves a Git common directory at a drive root' {
        $driveRoot = [IO.Path]::GetPathRoot($tempRoot)
        $rootInvoker = { param($workingDirectory) [pscustomobject]@{ ExitCode = 0; Output = $driveRoot } }.GetNewClosure()
        Assert-Equal $driveRoot (Resolve-AiAnalysisGitCommonDirectory -WorkingDirectory $worktreeRoot -GitInvoker $rootInvoker) 'drive root preserved'
    }

    Invoke-AiAnalysisTest 'rejects an unrelated repository' {
        $otherGitInvoker = { param($workingDirectory) [pscustomobject]@{ ExitCode = 0; Output = $otherGit } }.GetNewClosure()
        Assert-Throws { Assert-AiAnalysisProjectBinding -WorkingDirectory $otherRoot -ExpectedGitCommonDirectory $sharedGit -GitInvoker $otherGitInvoker } 'projectMismatch'
    }

    Invoke-AiAnalysisTest 'rejects a path-prefix lookalike' {
        $prefixGitInvoker = { param($workingDirectory) [pscustomobject]@{ ExitCode = 0; Output = $prefixGit } }.GetNewClosure()
        Assert-Throws { Assert-AiAnalysisProjectBinding -WorkingDirectory $prefixRoot -ExpectedGitCommonDirectory $sharedGit -GitInvoker $prefixGitInvoker } 'projectMismatch'
    }

    Invoke-AiAnalysisTest 'rejects Git failure and a missing working directory' {
        Assert-Throws { Resolve-AiAnalysisGitCommonDirectory -WorkingDirectory $tempRoot -GitInvoker { param($workingDirectory) [pscustomobject]@{ ExitCode = 128; Output = '' } } } 'gitCommonDirectoryUnavailable'
        Assert-Throws { Resolve-AiAnalysisGitCommonDirectory -WorkingDirectory (Join-Path $tempRoot 'missing') -GitInvoker $gitInvoker } 'repositoryRootNotFound'
    }
} finally {
    [IO.Directory]::Delete($tempRoot, $true)
}

Complete-AiAnalysisTests -Suite 'Project binding'
