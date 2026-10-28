param(
    [Parameter(Mandatory = $true)][string]$SourceCommit,
    [Parameter(Mandatory = $true)][string]$SourceFingerprint,
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][string]$Executable,
    [string[]]$ArgumentList = @()
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Get-Pm8Sha256Hex {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = [BitConverter]::ToString($sha256.ComputeHash($Bytes))
        return $hash.Replace('-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Get-Pm8FileSha256Hex {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read
    )
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = [BitConverter]::ToString($sha256.ComputeHash($stream))
        return $hash.Replace('-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
        $stream.Dispose()
    }
}

function Get-Pm8CanonicalSourceHash {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [IO.Path]::IsPathRooted($RelativePath)) {
        throw "Canonical source path must be a non-empty relative path: $RelativePath"
    }
    $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $platformPath = $RelativePath.Replace(
        '/',
        [IO.Path]::DirectorySeparatorChar
    )
    $absolutePath = [IO.Path]::GetFullPath((Join-Path $resolvedRoot $platformPath))
    $rootPrefix = $resolvedRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $absolutePath.StartsWith(
            $rootPrefix,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        throw "Canonical source escapes the repository root: $RelativePath"
    }
    if ([IO.File]::Exists($absolutePath)) {
        return Get-Pm8FileSha256Hex -Path $absolutePath
    }
    if (-not [IO.Directory]::Exists($absolutePath)) {
        throw "Canonical source is missing: $RelativePath"
    }

    $pending = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
    $pending.Push([IO.DirectoryInfo]::new($absolutePath))
    $absoluteFiles = [Collections.Generic.List[string]]::new()
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($child in Get-ChildItem -LiteralPath $directory.FullName -Force) {
            $isReparsePoint = (
                $child.Attributes -band [IO.FileAttributes]::ReparsePoint
            ) -ne 0
            if ($isReparsePoint) {
                continue
            }
            if ($child.PSIsContainer) {
                $pending.Push([IO.DirectoryInfo]$child)
            } else {
                $absoluteFiles.Add($child.FullName)
            }
        }
    }
    if ($absoluteFiles.Count -eq 0) {
        throw "Canonical source directory is empty: $RelativePath"
    }
    $sortedFiles = [string[]]$absoluteFiles.ToArray()
    [Array]::Sort($sortedFiles, [StringComparer]::Ordinal)
    $directoryPath = $absolutePath.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $entries = [Collections.Generic.List[string]]::new()
    foreach ($filePath in $sortedFiles) {
        $nativeChildPath = $filePath.Substring($directoryPath.Length + 1)
        $childPath = $nativeChildPath.Replace('\', '/')
        $fileHash = Get-Pm8FileSha256Hex -Path $filePath
        $entries.Add($childPath + [char]0 + $fileHash)
    }
    $canonical = $entries -join "`n"
    $canonicalBytes = [Text.Encoding]::UTF8.GetBytes($canonical)
    return Get-Pm8Sha256Hex -Bytes $canonicalBytes
}

function Get-Pm8SourceSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object[]]$Sources,
        [Parameter(Mandatory = $true)][string]$Phase
    )

    $checkedAt = [DateTimeOffset]::UtcNow
    $entries = [Collections.Generic.List[object]]::new()
    $seenPaths = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    $mismatchCount = 0
    $errorCount = 0
    for ($index = 0; $index -lt $Sources.Count; $index += 1) {
        $source = $Sources[$index]
        $pathProperty = $source.PSObject.Properties['path']
        $hashProperty = $source.PSObject.Properties['sha256']
        $relativePath = if ($null -ne $pathProperty) {
            [string]$pathProperty.Value
        } else {
            ''
        }
        $expectedHash = if ($null -ne $hashProperty) {
            [string]$hashProperty.Value
        } else {
            ''
        }
        $actualHash = $null
        $entryError = $null
        if ([string]::IsNullOrWhiteSpace($relativePath) -or
            $expectedHash -cnotmatch '^[0-9a-f]{64}$') {
            $entryError = "Malformed sources[$index] entry."
        } elseif (-not $seenPaths.Add($relativePath)) {
            $entryError = "Duplicate canonical source path: $relativePath"
        } else {
            try {
                $actualHash = Get-Pm8CanonicalSourceHash `
                    -Root $Root `
                    -RelativePath $relativePath
            } catch {
                $entryError = $_.Exception.Message
            }
        }
        $matches = $null -eq $entryError -and
            $actualHash -ceq $expectedHash
        if ($null -ne $entryError) {
            $errorCount += 1
        } elseif (-not $matches) {
            $mismatchCount += 1
        }
        $entries.Add([ordered]@{
            path = $relativePath
            expectedSha256 = $expectedHash
            actualSha256 = $actualHash
            matches = $matches
            error = $entryError
        })
    }
    $status = if ($errorCount -gt 0) {
        'error'
    } elseif ($mismatchCount -gt 0) {
        'mismatch'
    } else {
        'match'
    }
    return [ordered]@{
        phase = $Phase
        checkedAtUtc = $checkedAt.ToString('o')
        status = $status
        entryCount = $Sources.Count
        mismatchCount = $mismatchCount
        errorCount = $errorCount
        entries = $entries.ToArray()
    }
}

function Get-Pm8CheckoutHead {
    $head = (& git rev-parse HEAD).Trim()
    if ($global:LASTEXITCODE -ne 0 -or $head -cnotmatch '^[0-9a-f]{40}$') {
        throw 'Cannot read checkout identity.'
    }
    return $head
}

$pm8Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$pm8ExpectedRoot = 'C:\Users\Phet\.codex\worktrees\02fa\LexiQuest'
if ($pm8Root -cne $pm8ExpectedRoot -or
    (Get-Location).Path -cne $pm8ExpectedRoot) {
    throw 'Run this task-owned gate only from the exact PM8 worktree.'
}
if ($SourceCommit -cnotmatch '^[0-9a-f]{40}$' -or
    $SourceFingerprint -cnotmatch '^[0-9a-f]{64}$' -or
    $Label -cnotmatch '^[a-z0-9][a-z0-9-]{0,80}$') {
    throw 'Invalid source identity or evidence label.'
}
$pm8PlanPath = Join-Path $pm8Root `
    'docs/generated/alltcas-8-44-final-test-plan.json'
$pm8PlanBytes = [IO.File]::ReadAllBytes($pm8PlanPath)
$pm8PlanSha256Before = Get-Pm8Sha256Hex -Bytes $pm8PlanBytes
$pm8PlanText = [Text.Encoding]::UTF8.GetString($pm8PlanBytes)
if ($pm8PlanText.Length -gt 0 -and $pm8PlanText[0] -eq [char]0xfeff) {
    $pm8PlanText = $pm8PlanText.Substring(1)
}
$pm8Plan = $pm8PlanText | ConvertFrom-Json
if ($pm8Plan.sourceCommit -cne $SourceCommit -or
    $pm8Plan.sourceFingerprint -cne $SourceFingerprint) {
    throw 'Generated plan does not match the declared frozen source.'
}
$pm8PlanSources = [object[]]@($pm8Plan.sources)
if ($pm8PlanSources.Count -eq 0) {
    throw 'Generated plan has no canonical source entries.'
}
$pm8Branch = (& git branch --show-current).Trim()
if ($global:LASTEXITCODE -ne 0 -or $pm8Branch -cne 'codex/pair-matching-pm0-pm8') {
    throw 'Unexpected PM8 branch.'
}
$pm8Command = Get-Command $Executable -ErrorAction Stop | Select-Object -First 1
if ($pm8Command.CommandType -notin @('Application', 'ExternalScript')) {
    throw 'Gate executable must resolve to an explicit native command or script.'
}

$pm8Start = [DateTimeOffset]::UtcNow
$pm8Timestamp = $pm8Start.UtcDateTime.ToString(
    "yyyyMMdd'T'HHmmssfff'Z'",
    [Globalization.CultureInfo]::InvariantCulture
)
$pm8EvidenceDirectory = Join-Path $pm8Root `
    ('build/verification/' + $SourceCommit)
New-Item -ItemType Directory -Path $pm8EvidenceDirectory -Force | Out-Null
$pm8Prefix = Join-Path $pm8EvidenceDirectory `
    ('pm8-' + $pm8Timestamp + '-' + $Label)
$pm8Stdout = $pm8Prefix + '.stdout.log'
$pm8Stderr = $pm8Prefix + '.stderr.log'
$pm8MetadataPath = $pm8Prefix + '.metadata.json'
if ((Test-Path -LiteralPath $pm8Stdout) -or
    (Test-Path -LiteralPath $pm8Stderr) -or
    (Test-Path -LiteralPath $pm8MetadataPath)) {
    throw 'Evidence prefix already exists; preserve the original run.'
}

$pm8GateFailures = [Collections.Generic.List[string]]::new()
$pm8HeadBefore = $null
$pm8HeadAfter = $null
$pm8HeadMatchBefore = $false
$pm8HeadMatchAfter = $false
$pm8SourceCheckBefore = $null
$pm8SourceCheckAfter = $null
$pm8PlanSha256After = $null
$pm8PlanUnchanged = $false
$pm8CommandStarted = $false
$pm8NativeExitCode = $null
$pm8GateExitCode = 1
$pm8InvocationFailure = $null

try {
    try {
        $pm8HeadBefore = Get-Pm8CheckoutHead
        $pm8HeadMatchBefore = $pm8HeadBefore -ceq $SourceCommit
        if (-not $pm8HeadMatchBefore) {
            $pm8GateFailures.Add(
                'Checkout HEAD did not match SourceCommit before the command.'
            )
        }
    } catch {
        $pm8GateFailures.Add($_.Exception.Message)
    }
    $pm8SourceCheckBefore = Get-Pm8SourceSnapshot `
        -Root $pm8Root `
        -Sources $pm8PlanSources `
        -Phase 'before'
    if ($pm8SourceCheckBefore.status -cne 'match') {
        $pm8GateFailures.Add(
            'Canonical sources did not match the generated plan before the command.'
        )
    }

    if ($pm8GateFailures.Count -eq 0) {
        $pm8CommandStarted = $true
        try {
            $global:LASTEXITCODE = $null
            & $pm8Command.Source @ArgumentList `
                1> $pm8Stdout `
                2> $pm8Stderr
            $pm8NativeExitCode = $global:LASTEXITCODE
            if ($null -eq $pm8NativeExitCode) {
                throw 'Gate did not report a native exit code.'
            }
        } catch {
            $pm8InvocationFailure = $_.Exception.Message
        }
    }
} catch {
    $pm8InvocationFailure = $_.Exception.Message
} finally {
    try {
        $pm8HeadAfter = Get-Pm8CheckoutHead
        $pm8HeadMatchAfter = $pm8HeadAfter -ceq $SourceCommit
        if (-not $pm8HeadMatchAfter) {
            $pm8GateFailures.Add(
                'Checkout HEAD did not match SourceCommit after the command.'
            )
        }
    } catch {
        $pm8GateFailures.Add($_.Exception.Message)
    }
    try {
        $pm8SourceCheckAfter = Get-Pm8SourceSnapshot `
            -Root $pm8Root `
            -Sources $pm8PlanSources `
            -Phase 'after'
        if ($pm8SourceCheckAfter.status -cne 'match') {
            $pm8GateFailures.Add(
                'Canonical sources did not match the generated plan after the command.'
            )
        }
    } catch {
        $pm8GateFailures.Add(
            'Unable to verify canonical sources after the command: ' +
            $_.Exception.Message
        )
    }
    try {
        $pm8PlanSha256After = Get-Pm8FileSha256Hex -Path $pm8PlanPath
        $pm8PlanUnchanged = $pm8PlanSha256After -ceq $pm8PlanSha256Before
        if (-not $pm8PlanUnchanged) {
            $pm8GateFailures.Add(
                'Generated plan changed during the command.'
            )
        }
    } catch {
        $pm8GateFailures.Add(
            'Unable to verify the generated plan after the command: ' +
            $_.Exception.Message
        )
    }

    if ($null -ne $pm8NativeExitCode -and $pm8NativeExitCode -ne 0) {
        $pm8GateExitCode = $pm8NativeExitCode
    } elseif ($null -ne $pm8InvocationFailure -or
        $pm8GateFailures.Count -gt 0 -or
        -not $pm8CommandStarted) {
        $pm8GateExitCode = 1
    } else {
        $pm8GateExitCode = 0
    }
    $pm8End = [DateTimeOffset]::UtcNow
    $pm8Metadata = [ordered]@{
        sourceCommit = $SourceCommit
        sourceFingerprint = $SourceFingerprint
        planSha256Before = $pm8PlanSha256Before
        planSha256After = $pm8PlanSha256After
        planUnchanged = $pm8PlanUnchanged
        checkoutHeadBefore = $pm8HeadBefore
        checkoutHeadAfter = $pm8HeadAfter
        headMatchBefore = $pm8HeadMatchBefore
        headMatchAfter = $pm8HeadMatchAfter
        sourceCheckBefore = $pm8SourceCheckBefore
        sourceCheckAfter = $pm8SourceCheckAfter
        branch = $pm8Branch
        workingDirectory = $pm8Root
        label = $Label
        executable = $pm8Command.Source
        arguments = @($ArgumentList)
        startUtc = $pm8Start.ToString('o')
        endUtc = $pm8End.ToString('o')
        durationSeconds = [Math]::Round(($pm8End - $pm8Start).TotalSeconds, 3)
        commandStarted = $pm8CommandStarted
        nativeExitCode = $pm8NativeExitCode
        gateExitCode = $pm8GateExitCode
        exitCode = $pm8GateExitCode
        invocationFailure = $pm8InvocationFailure
        gateFailures = $pm8GateFailures.ToArray()
        stdout = $pm8Stdout
        stderr = $pm8Stderr
    }
    $pm8Metadata | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $pm8MetadataPath -Encoding utf8
    [pscustomobject]@{
        label = $Label
        nativeExitCode = $pm8NativeExitCode
        gateExitCode = $pm8GateExitCode
        durationSeconds = $pm8Metadata.durationSeconds
        metadata = $pm8MetadataPath
    } | ConvertTo-Json -Compress
}
exit $pm8GateExitCode
