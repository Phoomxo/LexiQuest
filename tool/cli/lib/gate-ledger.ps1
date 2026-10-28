#Requires -Version 5.1
Set-StrictMode -Version 3.0

function New-LexiQuestGateLedger {
    return [pscustomobject]@{
        schemaVersion = 1
        records = @()
    }
}

function Test-LexiQuestGateRecord {
    param([Parameter(Mandatory)][object]$Record)

    $errors = [System.Collections.Generic.List[string]]::new()
    $sha256 = '^[A-Fa-f0-9]{64}$'
    $commit = '^[A-Fa-f0-9]{7,40}$'
    if ([string]$Record.gate -notin @(
        'microtask', 'package', 'integration', 'release'
    )) {
        $errors.Add('gate must be microtask, package, integration, or release.')
    }
    if ([string]$Record.commitSha -notmatch $commit) {
        $errors.Add('commitSha must be a Git commit hash.')
    }
    if ([string]$Record.dependencyLockSha256 -notmatch $sha256) {
        $errors.Add('dependencyLockSha256 must be a SHA-256 hash.')
    }
    if (
        [string]$Record.gate -eq 'release' -and
        [string]$Record.apkSha256 -notmatch $sha256
    ) {
        $errors.Add('release gate apkSha256 must be a SHA-256 hash.')
    }
    if ([string]$Record.result -notin @('pass', 'fail')) {
        $errors.Add('result must be pass or fail.')
    }
    if ([string]::IsNullOrWhiteSpace([string]$Record.command)) {
        $errors.Add('command is required.')
    }
    $timestamp = [DateTimeOffset]::MinValue
    if (
        -not [DateTimeOffset]::TryParse(
            [string]$Record.recordedAtUtc,
            [ref]$timestamp
        ) -or
        $timestamp.Offset -ne [TimeSpan]::Zero
    ) {
        $errors.Add('recordedAtUtc must be an ISO-8601 UTC timestamp.')
    }
    return $errors
}

function Test-LexiQuestGateMayRun {
    param(
        [Parameter(Mandatory)][object]$Ledger,
        [Parameter(Mandatory)][string]$Gate,
        [Parameter(Mandatory)][string]$CommitSha,
        [Parameter(Mandatory)][string]$DependencyLockSha256,
        [AllowEmptyString()][string]$ApkSha256 = '',
        [Parameter(Mandatory)][string]$Command
    )

    foreach ($record in @($Ledger.records)) {
        if (
            [string]$record.gate -eq $Gate -and
            [string]$record.commitSha -eq $CommitSha -and
            [string]$record.dependencyLockSha256 -eq
                $DependencyLockSha256 -and
            [string]$record.apkSha256 -eq $ApkSha256 -and
            [string]$record.command -eq $Command
        ) {
            return $false
        }
    }
    return $true
}

function Get-LexiQuestDependencyLockSha256 {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $candidates = @(
        (Join-Path $RepositoryRoot 'pubspec.lock'),
        (Join-Path $RepositoryRoot 'package-lock.json')
    )
    $backendRoot = Join-Path $RepositoryRoot 'backend'
    if (Test-Path -LiteralPath $backendRoot -PathType Container) {
        $candidates += @(
            Get-ChildItem -LiteralPath $backendRoot -Directory |
                ForEach-Object { Join-Path $_.FullName 'uv.lock' }
        )
    }
    $lockFiles = @(
        $candidates |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            ForEach-Object { Get-Item -LiteralPath $_ } |
            Sort-Object FullName
    )
    if ($lockFiles.Count -eq 0) {
        throw 'No supported dependency lock files were found.'
    }
    $builder = [System.Text.StringBuilder]::new()
    foreach ($file in $lockFiles) {
        $relative = $file.FullName.Substring($RepositoryRoot.Length)
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        [void]$builder.AppendLine("$relative=$hash")
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString(
            $algorithm.ComputeHash($bytes)
        ) -replace '-', '')
    } finally {
        $algorithm.Dispose()
    }
}
