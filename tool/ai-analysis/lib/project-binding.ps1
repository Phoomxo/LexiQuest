Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'repository-root.ps1')

function Invoke-AiAnalysisGitCommonDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkingDirectory)

    $output = & git -C $WorkingDirectory rev-parse --git-common-dir 2>$null
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = [string]($output | Select-Object -First 1)
    }
}

function Resolve-AiAnalysisGitCommonDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [scriptblock]$GitInvoker = ${function:Invoke-AiAnalysisGitCommonDirectory}
    )

    if (-not [IO.Directory]::Exists($WorkingDirectory)) {
        throw 'repositoryRootNotFound'
    }

    $workingRoot = ConvertTo-AiAnalysisCanonicalDirectoryPath -Path $WorkingDirectory
    $result = & $GitInvoker $workingRoot
    if ($null -eq $result -or [int]$result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace([string]$result.Output)) {
        throw 'gitCommonDirectoryUnavailable'
    }

    $candidate = [string]$result.Output
    if (-not [IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path $workingRoot $candidate
    }

    try {
        return ConvertTo-AiAnalysisCanonicalDirectoryPath -Path $candidate
    } catch {
        throw 'gitCommonDirectoryUnavailable'
    }
}

function Assert-AiAnalysisProjectBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$ExpectedGitCommonDirectory,
        [scriptblock]$GitInvoker = ${function:Invoke-AiAnalysisGitCommonDirectory}
    )

    $actual = Resolve-AiAnalysisGitCommonDirectory -WorkingDirectory $WorkingDirectory -GitInvoker $GitInvoker
    try {
        $expected = ConvertTo-AiAnalysisCanonicalDirectoryPath -Path $ExpectedGitCommonDirectory
    } catch {
        throw 'projectMismatch'
    }

    if (-not [string]::Equals($actual, $expected, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'projectMismatch'
    }

    return $actual
}
