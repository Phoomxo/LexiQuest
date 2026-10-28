Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..\lib\repository-root.ps1')

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('lexiquest-root-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tempRoot) | Out-Null
try {
    Invoke-AiAnalysisTest 'uses the source-tree default when no root is supplied' {
        Assert-Equal ([IO.Path]::GetFullPath($tempRoot)) (Resolve-AiAnalysisRepositoryRoot -RepositoryRoot '' -DefaultRoot $tempRoot) 'default root'
    }

    Invoke-AiAnalysisTest 'normalizes an explicit worktree root' {
        $nested = Join-Path $tempRoot 'nested\..'
        Assert-Equal ([IO.Path]::GetFullPath($tempRoot)) (Resolve-AiAnalysisRepositoryRoot -RepositoryRoot $nested -DefaultRoot 'unused') 'explicit root'
    }

    Invoke-AiAnalysisTest 'rejects a missing root' {
        Assert-Throws { Resolve-AiAnalysisRepositoryRoot -RepositoryRoot (Join-Path $tempRoot 'missing') -DefaultRoot $tempRoot } 'repositoryRootNotFound'
    }

    Invoke-AiAnalysisTest 'rejects a file as a root' {
        $file = Join-Path $tempRoot 'file.txt'
        [IO.File]::WriteAllText($file, 'x')
        Assert-Throws { Resolve-AiAnalysisRepositoryRoot -RepositoryRoot $file -DefaultRoot $tempRoot } 'repositoryRootNotFound'
    }

    Invoke-AiAnalysisTest 'preserves a filesystem drive root' {
        $driveRoot = [IO.Path]::GetPathRoot($tempRoot)
        Assert-Equal $driveRoot (Resolve-AiAnalysisRepositoryRoot -RepositoryRoot $driveRoot -DefaultRoot $tempRoot) 'drive root preserved'
    }

    Invoke-AiAnalysisTest 'wires both public commands through the resolver' {
        foreach ($name in @('invoke-analysis.ps1', 'test-provider-smoke.ps1')) {
            $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\$name") -Raw -Encoding utf8
            Assert-Match 'RepositoryRoot' $source "$name exposes root"
            Assert-Match 'Resolve-AiAnalysisRepositoryRoot' $source "$name resolves root"
        }
    }
} finally {
    [IO.Directory]::Delete($tempRoot, $true)
}

Complete-AiAnalysisTests -Suite 'Repository root'
