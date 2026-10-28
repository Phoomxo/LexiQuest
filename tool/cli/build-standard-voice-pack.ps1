#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ContentPath,
    [Parameter(Mandatory)][string]$AudioDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][string]$PackId,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][ValidateSet('en', 'th')][string]$Locale,
    [Parameter(Mandatory)][string]$VoiceId,
    [Parameter(Mandatory)][string]$ModelVersion,
    [Parameter(Mandatory)][string]$MinimumAppVersion,
    [Parameter(Mandatory)][uri]$BaseUri,
    [Parameter(Mandatory)][string]$GeneratedAtUtc
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Get-Sha256Text {
    param([Parameter(Mandatory)][string]$Value)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).
            Replace('-', '').ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
    }
}

function Assert-SafeRelativePath {
    param([Parameter(Mandatory)][string]$Path)
    if (
        [IO.Path]::IsPathRooted($Path) -or
        $Path.Contains('\') -or
        ($Path -split '/') -contains '..' -or
        ($Path -split '/') -contains '.' -or
        ($Path -split '/') -contains ''
    ) {
        throw "Unsafe relativePath: $Path"
    }
}

$contentFile = [IO.Path]::GetFullPath($ContentPath)
$audioRoot = [IO.Path]::GetFullPath($AudioDirectory).
    TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$output = [IO.Path]::GetFullPath($OutputDirectory)
$outputParent = Split-Path -Parent $output
$staging = $output + '.partial-' + [Guid]::NewGuid().ToString('N')

if (-not (Test-Path -LiteralPath $contentFile -PathType Leaf)) {
    throw "Approved content file is missing: $contentFile"
}
if (-not (Test-Path -LiteralPath $audioRoot -PathType Container)) {
    throw "Generated audio directory is missing: $audioRoot"
}
if (Test-Path -LiteralPath $output) {
    throw "Output directory already exists: $output"
}
if ($BaseUri.Scheme -ne 'https') {
    throw 'BaseUri must use HTTPS.'
}
$generatedTimestamp = [datetimeoffset]::MinValue
if (-not $GeneratedAtUtc.EndsWith('Z', [StringComparison]::Ordinal) -or
    -not [datetimeoffset]::TryParse(
        $GeneratedAtUtc,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$generatedTimestamp
    ) -or $generatedTimestamp.Offset -ne [timespan]::Zero) {
    throw 'GeneratedAtUtc must be UTC.'
}
if ($PackId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -or
    $VoiceId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -or
    $Version -notmatch '^\d+\.\d+\.\d+(?:\+\d+)?$' -or
    $MinimumAppVersion -notmatch '^\d+\.\d+\.\d+(?:\+\d+)?$') {
    throw 'Pack identifiers or versions are invalid.'
}

$approved = Get-Content -LiteralPath $contentFile -Raw -Encoding utf8 |
    ConvertFrom-Json
if ($approved.Count -lt 1 -or $approved.Count -gt 2000) {
    throw 'Approved content count must be between 1 and 2000.'
}

New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
New-Item -ItemType Directory -Path $staging | Out-Null
$activated = $false
try {
    $seenIds = @{}
    $seenPaths = @{}
    $files = [Collections.Generic.List[object]]::new()
    [long]$totalBytes = 0
    foreach ($item in $approved) {
        $contentId = [string]$item.contentId
        $text = ([regex]::Replace([string]$item.text, '\s+', ' ')).Trim()
        $relativePath = [string]$item.relativePath
        Assert-SafeRelativePath $relativePath
        if ($contentId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -or
            [string]::IsNullOrWhiteSpace($text)) {
            throw 'Approved content contains an invalid ID or empty text.'
        }
        $pathKey = $relativePath.ToLowerInvariant()
        if ($seenIds.ContainsKey($contentId) -or $seenPaths.ContainsKey($pathKey)) {
            throw 'Approved content contains duplicate IDs or paths.'
        }
        $seenIds[$contentId] = $true
        $seenPaths[$pathKey] = $true

        $source = [IO.Path]::GetFullPath((Join-Path $audioRoot $relativePath))
        if (-not $source.StartsWith($audioRoot, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Approved audio is missing or outside the source root: $relativePath"
        }
        $destination = Join-Path $staging $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force |
            Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
        $audio = Get-Item -LiteralPath $destination
        if ($audio.Length -le 0) {
            throw "Approved audio is empty: $relativePath"
        }
        $totalBytes += $audio.Length
        if ($totalBytes -gt 268435456) {
            throw 'Pack exceeds the 256 MiB byte ceiling.'
        }
        $files.Add([ordered]@{
            contentId = $contentId
            normalizedTextSha256 = Get-Sha256Text $text
            relativePath = $relativePath.Replace('\', '/')
            byteSize = [long]$audio.Length
            sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).
                Hash.ToLowerInvariant()
        })
    }

    $manifest = [ordered]@{
        schemaVersion = 1
        packId = $PackId
        version = $Version
        locale = $Locale
        voiceId = $VoiceId
        engine = 'voxcpm2'
        modelVersion = $ModelVersion
        license = 'Apache-2.0'
        licenseUri = 'https://github.com/OpenBMB/VoxCPM/blob/main/LICENSE'
        minimumAppVersion = $MinimumAppVersion
        baseUri = $BaseUri.AbsoluteUri
        generatedAtUtc = $generatedTimestamp.UtcDateTime.
            ToString('yyyy-MM-ddTHH:mm:ssZ')
        totalBytes = $totalBytes
        files = @($files)
    }
    $manifestPath = Join-Path $staging 'manifest.json'
    [IO.File]::WriteAllText(
        $manifestPath,
        (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine),
        [Text.UTF8Encoding]::new($false)
    )
    Move-Item -LiteralPath $staging -Destination $output
    $activated = $true
    Write-Host "Standard voice pack built: $output"
}
finally {
    if (-not $activated -and
        (Test-Path -LiteralPath $staging -PathType Container)) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
}
