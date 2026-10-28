Set-StrictMode -Version Latest

function Test-AiAnalysisDeniedPath {
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = $RelativePath.Replace('\', '/')
    while ($path.StartsWith('./', [System.StringComparison]::Ordinal)) { $path = $path.Substring(2) }
    $path = $path.TrimStart('/')
    $name = [System.IO.Path]::GetFileName($path)

    if ($name -like '.env*') { return $true }
    if ($name -like '*.jks' -or $name -like '*.keystore' -or $name -like '*.p12' -or
        $name -like '*.pem' -or $name -like '*.key' -or $name -like '*.dpapi') { return $true }
    if ($name -ieq 'key.properties' -or $name -ieq 'google-services.json' -or
        $name -ieq 'GoogleService-Info.plist') { return $true }
    if ($path -imatch '(^|/)android/local\.properties$') { return $true }
    if ($path -imatch '(^|/)field/evidence(/|$)') { return $true }
    if ($path -imatch '(^|/)build(/|$)') { return $true }
    return $false
}

function Get-AiAnalysisRelativePath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )

    $rootUri = New-Object System.Uri(($Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar))
    $pathUri = New-Object System.Uri($Path)
    return [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('\', '/')
}

function Test-AiAnalysisBinaryFile {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        $length = [Math]::Min(8192, [int]$stream.Length)
        $buffer = New-Object byte[] $length
        $read = $stream.Read($buffer, 0, $length)
        for ($index = 0; $index -lt $read; $index++) {
            if ($buffer[$index] -eq 0) { return $true }
        }
        return $false
    } finally {
        $stream.Dispose()
    }
}

function Assert-AiAnalysisNoReparsePoint {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Candidate
    )

    if ($Candidate.Equals($Root, [System.StringComparison]::OrdinalIgnoreCase)) { return }
    $relative = $Candidate.Substring($Root.Length).TrimStart(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $current = $Root
    foreach ($segment in $relative.Split(@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ), [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $current = [System.IO.Path]::Combine($current, $segment)
        if ([System.IO.File]::Exists($current) -or [System.IO.Directory]::Exists($current)) {
            $attributes = [System.IO.File]::GetAttributes($current)
            if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'reparsePoint'
            }
        }
    }
}

function Get-AiAnalysisDirectoryFiles {
    param([Parameter(Mandatory)][string]$Directory)

    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($Directory)
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        $attributes = [System.IO.File]::GetAttributes($current)
        if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparsePoint' }
        foreach ($file in [System.IO.Directory]::GetFiles($current)) {
            $fileAttributes = [System.IO.File]::GetAttributes($file)
            if (($fileAttributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparsePoint' }
            Write-Output $file
        }
        foreach ($child in [System.IO.Directory]::GetDirectories($current)) {
            $childAttributes = [System.IO.File]::GetAttributes($child)
            if (($childAttributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparsePoint' }
            $pending.Push($child)
        }
    }
}

function New-AiAnalysisContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Config,
        [string[]]$Paths = @(),
        [switch]$ChangedFiles
    )

    if ($ChangedFiles -and @($Paths).Count -gt 0) { throw 'ambiguousScope' }

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    if (-not [System.IO.Directory]::Exists($root)) { throw 'repositoryNotFound' }
    $rootPrefix = $root + [System.IO.Path]::DirectorySeparatorChar

    $requested = @()
    $mode = 'explicit'
    if ($ChangedFiles -or @($Paths).Count -eq 0) {
        $mode = 'changedFiles'
        $gitOutput = @(& git -C $root diff --name-only --diff-filter=ACMRTUXB HEAD -- 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'gitDiffFailed' }
        $requested = @($gitOutput | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    } else {
        $requested = @($Paths)
    }

    $allowedExtensions = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($extension in @($Config.context.allowedExtensions)) { $allowedExtensions.Add([string]$extension) | Out-Null }

    $resolvedFiles = New-Object 'System.Collections.Generic.List[string]'
    foreach ($requestedPath in $requested) {
        if ([string]::IsNullOrWhiteSpace($requestedPath)) { throw 'invalidPath' }
        $candidate = if ([System.IO.Path]::IsPathRooted($requestedPath)) {
            [System.IO.Path]::GetFullPath($requestedPath)
        } else {
            [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($root, $requestedPath))
        }

        $inside = $candidate.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) -or
            $candidate.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $inside) { throw 'outsideRepository' }
        Assert-AiAnalysisNoReparsePoint -Root $root -Candidate $candidate

        $relativeCandidate = if ($candidate -eq $root) { '' } else { Get-AiAnalysisRelativePath -Root $root -Path $candidate }
        if (-not [string]::IsNullOrEmpty($relativeCandidate) -and (Test-AiAnalysisDeniedPath -RelativePath $relativeCandidate)) {
            throw "denylistedPath:$relativeCandidate"
        }

        if ([System.IO.Directory]::Exists($candidate)) {
            foreach ($file in @(Get-AiAnalysisDirectoryFiles -Directory $candidate)) {
                $relative = Get-AiAnalysisRelativePath -Root $root -Path $file
                if ((Test-AiAnalysisDeniedPath -RelativePath $relative)) { continue }
                if ($allowedExtensions.Contains([System.IO.Path]::GetExtension($file))) { $resolvedFiles.Add($file) }
            }
        } elseif ([System.IO.File]::Exists($candidate)) {
            if (-not $allowedExtensions.Contains([System.IO.Path]::GetExtension($candidate))) { throw 'unsupportedFileType' }
            $resolvedFiles.Add($candidate)
        } else {
            throw 'pathNotFound'
        }
    }

    $uniqueFiles = @($resolvedFiles | Sort-Object -Unique)
    if ($uniqueFiles.Count -eq 0) { throw 'noContextFiles' }
    if ($uniqueFiles.Count -gt [int]$Config.context.maxFiles) { throw 'tooManyFiles' }

    $builder = New-Object System.Text.StringBuilder
    $relativeFiles = New-Object 'System.Collections.Generic.List[string]'
    $utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
    $secretRules = @($Config.secretPatterns | Sort-Object { ([string]$_.pattern).Length } -Descending)

    foreach ($file in $uniqueFiles) {
        $relative = Get-AiAnalysisRelativePath -Root $root -Path $file
        if (Test-AiAnalysisDeniedPath -RelativePath $relative) { throw "denylistedPath:$relative" }

        $info = New-Object System.IO.FileInfo($file)
        if ($info.Length -gt [long]$Config.context.maxFileBytes) { throw "fileTooLarge:$relative" }
        if (Test-AiAnalysisBinaryFile -Path $file) { throw "binaryFile:$relative" }

        try {
            $bytes = [System.IO.File]::ReadAllBytes($file)
            $content = $utf8Strict.GetString($bytes)
        } catch [System.Text.DecoderFallbackException] {
            throw "invalidUtf8:$relative"
        }

        foreach ($rule in $secretRules) {
            try { $matched = [regex]::IsMatch($content, [string]$rule.pattern) } catch { throw 'invalidSecretPattern' }
            if ($matched) { throw "embeddedSecret:${relative}:$($rule.id)" }
        }

        $part = New-Object System.Text.StringBuilder
        [void]$part.Append("--- FILE: $relative ---`n")
        $lines = @($content -split "\r\n|\n|\r")
        for ($index = 0; $index -lt $lines.Count; $index++) {
            [void]$part.Append(($index + 1).ToString().PadLeft(6))
            [void]$part.Append(' | ')
            [void]$part.Append($lines[$index])
            [void]$part.Append("`n")
        }

        if (($builder.Length + $part.Length) -gt [int]$Config.context.maxCharacters) {
            throw 'contextTooLarge'
        }
        [void]$builder.Append($part.ToString())
        $relativeFiles.Add($relative)
    }

    [pscustomobject]@{
        Files = @($relativeFiles)
        Text = $builder.ToString()
        CharacterCount = $builder.Length
        Mode = $mode
    }
}
