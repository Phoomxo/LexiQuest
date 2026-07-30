#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputPath = 'build/field-release',
    [string]$Version = '1.0.0+1',
    [string]$ModelSha256 =
        'd3949e8a3556c79739cb675e0be7476503bcce76938031c6a1048e13e0cb7d8b'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if ($Version -notmatch '^\d+\.\d+\.\d+\+\d+$') {
    throw 'Version must use semantic version plus Android build number.'
}

function Find-ApkSigner {
    $command = Get-Command apksigner -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }
    $sdkCandidates = @(
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($sdk in $sdkCandidates) {
        $buildTools = Join-Path $sdk 'build-tools'
        if (-not (Test-Path -LiteralPath $buildTools -PathType Container)) {
            continue
        }
        $candidate = Get-ChildItem -LiteralPath $buildTools -Directory |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -First 1
        if ($null -ne $candidate) {
            return $candidate
        }
    }
    throw 'apksigner is required before packaging a field release.'
}

Push-Location -LiteralPath $repoRoot
try {
    if (-not (Test-Path -LiteralPath 'android/key.properties' -PathType Leaf)) {
        throw (
            'Release signing is not configured. Create android/key.properties ' +
            'from android/key.properties.example using owner-controlled secrets.'
        )
    }
    $relevantChanges = @(
        & git status --porcelain --untracked-files=all -- `
            android assets lib docs/field pubspec.yaml pubspec.lock `
            firebase.json firestore.rules firestore.indexes.json `
            tool/cli/package-field-release.ps1 `
            tool/cli/verify-apk-model-runtime.ps1 `
            tool/cli/verify-field-release.ps1
    )
    if ($relevantChanges.Count -gt 0) {
        throw (
            'Android-relevant release sources contain uncommitted changes: ' +
            ($relevantChanges -join ', ')
        )
    }

    $sourceCommit = (& git rev-parse HEAD).Trim()
    $buildId = $sourceCommit.Substring(0, 12)
    & flutter build apk --release --no-pub `
        "--build-name=$($Version.Split('+')[0])" `
        "--build-number=$($Version.Split('+')[1])" `
        --dart-define=LEXIQUEST_CLOUD_SYNC_ENABLED=true `
        "--dart-define=LEXIQUEST_VERSION=$Version" `
        "--dart-define=LEXIQUEST_BUILD_ID=$buildId"
    if ([int]$LASTEXITCODE -ne 0) {
        throw 'Flutter release APK build failed.'
    }

    $sourceApk = Join-Path $repoRoot `
        'build/app/outputs/flutter-apk/app-release.apk'
    $resolvedOutput = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
        [System.IO.Path]::GetFullPath($OutputPath)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputPath))
    }
    New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
    $releaseApk = Join-Path $resolvedOutput "lexiquest-$Version.apk"
    Copy-Item -LiteralPath $sourceApk -Destination $releaseApk -Force

    $apkSigner = Find-ApkSigner
    $signatureOutput = & $apkSigner verify --verbose --print-certs `
        $releaseApk 2>&1
    if ([int]$LASTEXITCODE -ne 0) {
        throw "apksigner rejected the packaged APK: $signatureOutput"
    }
    $certificateMatch = [regex]::Match(
        ($signatureOutput -join "`n"),
        '(?m)^(?:Signer #1|V\d+(?:\.\d+)? Signer): ' +
            'certificate SHA-256 digest:\s*([A-Fa-f0-9:]{64,95})$'
    )
    if (-not $certificateMatch.Success) {
        throw 'Unable to read the release signing certificate SHA-256.'
    }
    $certificateSha256 =
        $certificateMatch.Groups[1].Value.Replace(':', '').ToUpperInvariant()
    $apkSha256 = (Get-FileHash -LiteralPath $releaseApk -Algorithm SHA256).Hash

    $docsOutput = Join-Path $resolvedOutput 'docs'
    New-Item -ItemType Directory -Path $docsOutput -Force | Out-Null
    Copy-Item -Path 'docs/field/*.md' -Destination $docsOutput -Force

    $manifest = [ordered]@{
        schemaVersion = 1
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        sourceCommit = $sourceCommit
        artifact = [ordered]@{
            apkPath = $releaseApk
            apkSha256 = $apkSha256
            signingCertificateSha256 = $certificateSha256
            packageName = 'com.lexiquest.app'
            versionName = $Version.Split('+')[0]
            versionCode = [int]$Version.Split('+')[1]
            buildId = $buildId
            modelSha256 = $ModelSha256.ToUpperInvariant()
        }
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $resolvedOutput 'release-manifest.json'),
        (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine),
        [System.Text.UTF8Encoding]::new($false)
    )
    Write-Host "Field release package created: $resolvedOutput" `
        -ForegroundColor Green
}
finally {
    Pop-Location
}
