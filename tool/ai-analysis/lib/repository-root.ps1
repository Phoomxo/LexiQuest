Set-StrictMode -Version Latest

function ConvertTo-AiAnalysisCanonicalDirectoryPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $pathRoot = [IO.Path]::GetPathRoot($fullPath)
    if ([string]::Equals($fullPath, $pathRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return $pathRoot
    }
    return $fullPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Resolve-AiAnalysisRepositoryRoot {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$DefaultRoot
    )

    $candidate = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $DefaultRoot
    } else {
        $RepositoryRoot
    }

    try {
        $resolved = [IO.Path]::GetFullPath($candidate)
    } catch {
        throw 'repositoryRootNotFound'
    }

    if (-not [IO.Directory]::Exists($resolved)) {
        throw 'repositoryRootNotFound'
    }

    return ConvertTo-AiAnalysisCanonicalDirectoryPath -Path $resolved
}
