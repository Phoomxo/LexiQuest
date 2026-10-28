#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputPath = 'build/field-release',
    [string]$Version = '1.0.0+1',
    [string]$SigningMetadataPath = (
        Join-Path $env:USERPROFILE `
            '.lexiquest\signing\signing-metadata.json'
    )
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$canonicalOutputRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'build\field-release')
).TrimEnd('\', '/')

function Resolve-ReleaseOutputPath {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
    }
    if ($resolved.TrimEnd('\', '/') -cne $canonicalOutputRoot) {
        throw 'OutputPath must resolve exactly to build/field-release.'
    }
    return $resolved
}

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

function Find-ApkAnalyzer {
    $command = Get-Command apkanalyzer -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }
    $sdkCandidates = @(
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($sdk in $sdkCandidates) {
        $commandLineTools = Join-Path $sdk 'cmdline-tools'
        if (Test-Path -LiteralPath $commandLineTools -PathType Container) {
            $candidate = Get-ChildItem -LiteralPath $commandLineTools `
                -Directory |
                Sort-Object Name -Descending |
                ForEach-Object {
                    Join-Path $_.FullName 'bin\apkanalyzer.bat'
                } |
                Where-Object {
                    Test-Path -LiteralPath $_ -PathType Leaf
                } |
                Select-Object -First 1
            if ($null -ne $candidate) {
                return $candidate
            }
        }
        $legacy = Join-Path $sdk 'tools\bin\apkanalyzer.bat'
        if (Test-Path -LiteralPath $legacy -PathType Leaf) {
            return $legacy
        }
    }
    throw 'apkanalyzer is required before packaging a field release.'
}

function Read-KeyProperties {
    param([Parameter(Mandatory)][string]$Path)

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path -Encoding utf8) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
            continue
        }
        $separator = $line.IndexOf('=')
        if ($separator -le 0) {
            throw 'android/key.properties contains an invalid entry.'
        }
        $key = $line.Substring(0, $separator).Trim()
        if ($values.ContainsKey($key)) {
            throw "android/key.properties contains duplicate $key."
        }
        $values[$key] = $line.Substring($separator + 1).Trim()
    }
    foreach ($key in @(
        'storeFile',
        'storePassword',
        'keyAlias',
        'keyPassword'
    )) {
        if (
            -not $values.ContainsKey($key) -or
            [string]::IsNullOrWhiteSpace([string]$values[$key]) -or
            [string]$values[$key] -match '^__REPLACE'
        ) {
            throw "android/key.properties has no usable $key."
        }
    }
    return $values
}

function Invoke-ApkAnalyzerValue {
    param(
        [Parameter(Mandatory)][string]$Analyzer,
        [Parameter(Mandatory)][string]$Verb,
        [Parameter(Mandatory)][string]$ApkPath
    )

    $value = (& $Analyzer manifest $Verb $ApkPath 2>&1) -join "`n"
    if ([int]$LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($value)) {
        throw "apkanalyzer failed to read manifest $Verb."
    }
    return $value.Trim()
}

function Read-ApkMetadataValue {
    param(
        [Parameter(Mandatory)][xml]$Manifest,
        [Parameter(Mandatory)][string]$Name
    )

    $androidNamespace = 'http://schemas.android.com/apk/res/android'
    $matches = @(
        $Manifest.manifest.application.'meta-data' |
            Where-Object {
                $_.GetAttribute('name', $androidNamespace) -ceq $Name
            }
    )
    if ($matches.Count -ne 1) {
        throw "APK must contain exactly one $Name metadata entry."
    }
    $value = $matches[0].GetAttribute('value', $androidNamespace)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "APK metadata $Name is empty."
    }
    return $value
}

function Read-PinnedModelSha256 {
    $manifestPath = Join-Path $repoRoot `
        'lib\features\device_model\domain\model_manifest.dart'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'The authoritative device-model manifest is missing.'
    }
    $source = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8
    $matches = [regex]::Matches(
        $source,
        "expectedSha256\s*[:=]\s*'([a-f0-9]{64})'"
    )
    if ($matches.Count -ne 1) {
        throw 'The authoritative device-model SHA-256 is ambiguous or missing.'
    }
    return $matches[0].Groups[1].Value.ToUpperInvariant()
}

Push-Location -LiteralPath $repoRoot
$stagingRoot = $null
$published = $false
$keyProperties = $null
try {
    $resolvedOutput = Resolve-ReleaseOutputPath -Path $OutputPath
    if (-not (Test-Path -LiteralPath 'android/key.properties' -PathType Leaf)) {
        throw (
            'Release signing is not configured. Create android/key.properties ' +
            'from android/key.properties.example using owner-controlled secrets.'
        )
    }
    if (-not (
        Test-Path -LiteralPath $SigningMetadataPath -PathType Leaf
    )) {
        throw 'Pinned Android release signing metadata is missing.'
    }
    $signingMetadata = Get-Content -LiteralPath $SigningMetadataPath `
        -Raw -Encoding utf8 | ConvertFrom-Json
    $pinnedCertificateSha256 =
        ([string]$signingMetadata.certificateSha256).
            Replace(':', '').
            ToUpperInvariant()
    if ($pinnedCertificateSha256 -notmatch '^[A-F0-9]{64}$') {
        throw 'Pinned Android release signing certificate is invalid.'
    }
    if (
        [int]$signingMetadata.schemaVersion -ne 1 -or
        [string]$signingMetadata.storeType -cne 'PKCS12'
    ) {
        throw 'Pinned Android release signing metadata is invalid.'
    }
    $keyProperties = Read-KeyProperties -Path 'android/key.properties'
    $configuredStoreFile = if (
        [System.IO.Path]::IsPathRooted([string]$keyProperties.storeFile)
    ) {
        [System.IO.Path]::GetFullPath([string]$keyProperties.storeFile)
    } else {
        [System.IO.Path]::GetFullPath(
            (Join-Path (Join-Path $repoRoot 'android') `
                ([string]$keyProperties.storeFile))
        )
    }
    if (-not (Test-Path -LiteralPath $configuredStoreFile -PathType Leaf)) {
        throw 'The configured Android release keystore is missing.'
    }
    if (
        $configuredStoreFile -cne
            [System.IO.Path]::GetFullPath(
                [string]$signingMetadata.keyStorePath
            ) -or
        [string]$keyProperties.keyAlias -cne [string]$signingMetadata.alias
    ) {
        throw 'Android signing configuration does not match pinned metadata.'
    }
    $modelSha256 = Read-PinnedModelSha256
    $apkSigner = Find-ApkSigner
    $apkAnalyzer = Find-ApkAnalyzer
    if (Test-Path -LiteralPath $resolvedOutput) {
        throw 'The release output already exists; refusing to overwrite it.'
    }
    $sourceChanges = @(& git status --porcelain --untracked-files=all)
    if ($sourceChanges.Count -gt 0) {
        throw (
            'The release source worktree must be completely clean: ' +
            ($sourceChanges -join ', ')
        )
    }

    $sourceCommit = (& git rev-parse HEAD).Trim()
    if ($sourceCommit -notmatch '^[0-9a-f]{40}$') {
        throw 'Unable to resolve a full frozen source commit.'
    }
    $buildId = $sourceCommit.Substring(0, 12)
    $sourceApk = Join-Path $repoRoot `
        'build/app/outputs/flutter-apk/app-release.apk'
    if (Test-Path -LiteralPath $sourceApk -PathType Leaf) {
        Remove-Item -LiteralPath $sourceApk -Force
    }
    # Keep Flutter's pub freshness step: release-mode plugin filtering excludes dev dependencies when it regenerates the Android registrant.
    & flutter build apk --release `
        "--android-project-arg=lexiquestSourceCommit=$sourceCommit" `
        "--android-project-arg=lexiquestBuildId=$buildId" `
        "--android-project-arg=lexiquestModelSha256=$modelSha256" `
        "--build-name=$($Version.Split('+')[0])" `
        "--build-number=$($Version.Split('+')[1])" `
        --dart-define=LEXIQUEST_CLOUD_SYNC_ENABLED=true `
        "--dart-define=LEXIQUEST_VERSION=$Version" `
        "--dart-define=LEXIQUEST_BUILD_ID=$buildId"
    if ([int]$LASTEXITCODE -ne 0) {
        throw 'Flutter release APK build failed.'
    }
    if (-not (Test-Path -LiteralPath $sourceApk -PathType Leaf)) {
        throw 'Flutter did not produce a fresh release APK.'
    }
    if ((& git rev-parse HEAD).Trim() -cne $sourceCommit) {
        throw 'Source HEAD changed during the release build.'
    }
    $postBuildChanges = @(& git status --porcelain --untracked-files=all)
    if ($postBuildChanges.Count -gt 0) {
        throw 'The source worktree changed during the release build.'
    }

    $stagingRoot = Join-Path (Join-Path $repoRoot 'build') (
        '.field-release-stage-' + [Guid]::NewGuid().ToString('N')
    )
    New-Item -ItemType Directory -Path $stagingRoot | Out-Null
    $releaseApkName = "lexiquest-$Version.apk"
    $releaseApk = Join-Path $stagingRoot $releaseApkName
    Copy-Item -LiteralPath $sourceApk -Destination $releaseApk

    $signatureOutput = & $apkSigner verify --verbose --print-certs `
        $releaseApk 2>&1
    if ([int]$LASTEXITCODE -ne 0) {
        throw "apksigner rejected the packaged APK: $signatureOutput"
    }
    $certificateMatches = [regex]::Matches(
        ($signatureOutput -join "`n"),
        '(?m)^(?:Signer #\d+|V\d+(?:\.\d+)? Signer):?\s+' +
            'certificate SHA-256 digest:\s*([A-Fa-f0-9:]{64,95})$'
    )
    if ($certificateMatches.Count -ne 1) {
        throw 'Release APK must contain exactly one signing certificate.'
    }
    $certificateSha256 =
        $certificateMatches[0].Groups[1].Value.
            Replace(':', '').
            ToUpperInvariant()
    if ($certificateSha256 -cne $pinnedCertificateSha256) {
        throw 'The APK signing certificate does not match pinned metadata.'
    }
    $apkSha256 = (Get-FileHash -LiteralPath $releaseApk -Algorithm SHA256).Hash

    $packageName = Invoke-ApkAnalyzerValue -Analyzer $apkAnalyzer `
        -Verb 'application-id' -ApkPath $releaseApk
    $versionName = Invoke-ApkAnalyzerValue -Analyzer $apkAnalyzer `
        -Verb 'version-name' -ApkPath $releaseApk
    $versionCodeText = Invoke-ApkAnalyzerValue -Analyzer $apkAnalyzer `
        -Verb 'version-code' -ApkPath $releaseApk
    if ($versionCodeText -notmatch '^\d+$') {
        throw 'APK version code is invalid.'
    }
    $versionCode = [int]$versionCodeText
    $manifestText = (& $apkAnalyzer manifest print $releaseApk 2>&1) `
        -join "`n"
    if ([int]$LASTEXITCODE -ne 0) {
        throw 'apkanalyzer could not decode the produced APK manifest.'
    }
    [xml]$decodedManifest = $manifestText
    $embeddedSourceCommit = Read-ApkMetadataValue `
        -Manifest $decodedManifest `
        -Name 'com.lexiquest.release.SOURCE_COMMIT'
    $embeddedBuildId = Read-ApkMetadataValue `
        -Manifest $decodedManifest `
        -Name 'com.lexiquest.release.BUILD_ID'
    $embeddedModelSha256 = Read-ApkMetadataValue `
        -Manifest $decodedManifest `
        -Name 'com.lexiquest.release.MODEL_SHA256'
    if (
        $packageName -cne 'com.lexiquest.app' -or
        $versionName -cne $Version.Split('+')[0] -or
        $versionCode -ne [int]$Version.Split('+')[1] -or
        $embeddedSourceCommit -cne $sourceCommit -or
        $embeddedBuildId -cne $buildId -or
        $embeddedModelSha256 -cne $modelSha256
    ) {
        throw 'Produced APK identity or embedded provenance does not match.'
    }

    $docsOutput = Join-Path $stagingRoot 'docs'
    New-Item -ItemType Directory -Path $docsOutput -Force | Out-Null
    foreach ($document in Get-ChildItem -LiteralPath 'docs/field' -File |
        Where-Object { $_.Extension -ceq '.md' }) {
        Copy-Item -LiteralPath $document.FullName -Destination $docsOutput
    }

    $manifest = [ordered]@{
        schemaVersion = 1
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        sourceCommit = $sourceCommit
        artifact = [ordered]@{
            apkPath = $releaseApkName
            apkSha256 = $apkSha256
            signingCertificateSha256 = $certificateSha256
            packageName = $packageName
            versionName = $versionName
            versionCode = $versionCode
            buildId = $embeddedBuildId
            modelSha256 = $embeddedModelSha256
        }
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $stagingRoot 'release-manifest.json'),
        (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine),
        [System.Text.UTF8Encoding]::new($false)
    )
    & powershell -NoProfile -ExecutionPolicy Bypass -File `
        (Join-Path $PSScriptRoot 'verify-field-package.ps1') `
        -PackagePath $stagingRoot `
        -SigningMetadataPath $SigningMetadataPath `
        -RuntimeVerifierPath (
            Join-Path $PSScriptRoot 'verify-apk-model-runtime.ps1'
        )
    if ([int]$LASTEXITCODE -ne 0) {
        throw 'Independent field-package verification failed.'
    }
    if (
        (& git rev-parse HEAD).Trim() -cne $sourceCommit -or
        @(& git status --porcelain --untracked-files=all).Count -gt 0
    ) {
        throw 'Frozen source changed before release publication.'
    }
    Move-Item -LiteralPath $stagingRoot -Destination $resolvedOutput
    $published = $true
    Write-Host "Field release package created: $resolvedOutput" `
        -ForegroundColor Green
}
finally {
    if (
        -not $published -and
        -not [string]::IsNullOrWhiteSpace($stagingRoot) -and
        (Test-Path -LiteralPath $stagingRoot -PathType Container)
    ) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
    $keyProperties = $null
    Pop-Location
}
