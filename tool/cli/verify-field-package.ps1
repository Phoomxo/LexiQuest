#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$PackagePath = 'build/field-release',
    [string]$SigningMetadataPath = (
        Join-Path $env:USERPROFILE `
            '.lexiquest\signing\signing-metadata.json'
    ),
    [string]$RuntimeVerifierPath = ''
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($RuntimeVerifierPath)) {
    $RuntimeVerifierPath = Join-Path $PSScriptRoot `
        'verify-apk-model-runtime.ps1'
}

function Resolve-InputPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

function Find-ApkSigner {
    $command = Get-Command apksigner -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
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
        if ($null -ne $candidate) { return $candidate }
    }
    throw 'apksigner is required to verify the field package.'
}

function Find-ApkAnalyzer {
    $command = Get-Command apkanalyzer -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
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
            if ($null -ne $candidate) { return $candidate }
        }
        $legacy = Join-Path $sdk 'tools\bin\apkanalyzer.bat'
        if (Test-Path -LiteralPath $legacy -PathType Leaf) { return $legacy }
    }
    throw 'apkanalyzer is required to verify the field package.'
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

$resolvedPackage = Resolve-InputPath -Path $PackagePath
$resolvedSigningMetadata = Resolve-InputPath -Path $SigningMetadataPath
$resolvedRuntimeVerifier = Resolve-InputPath -Path $RuntimeVerifierPath
foreach ($requiredFile in @(
    (Join-Path $resolvedPackage 'release-manifest.json'),
    $resolvedSigningMetadata,
    $resolvedRuntimeVerifier
)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required field-package input is missing: $requiredFile"
    }
}

$manifestPath = Join-Path $resolvedPackage 'release-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 |
    ConvertFrom-Json
$signingMetadata = Get-Content -LiteralPath $resolvedSigningMetadata `
    -Raw -Encoding utf8 | ConvertFrom-Json
if ([int]$manifest.schemaVersion -ne 1) {
    throw 'Unsupported field-package manifest schema.'
}
$sourceCommit = [string]$manifest.sourceCommit
$apkName = [string]$manifest.artifact.apkPath
$apkSha256 = ([string]$manifest.artifact.apkSha256).ToUpperInvariant()
$certificateSha256 = (
    [string]$manifest.artifact.signingCertificateSha256
).Replace(':', '').ToUpperInvariant()
$pinnedCertificateSha256 = (
    [string]$signingMetadata.certificateSha256
).Replace(':', '').ToUpperInvariant()
$packageName = [string]$manifest.artifact.packageName
$versionName = [string]$manifest.artifact.versionName
$versionCode = [string]$manifest.artifact.versionCode
$buildId = [string]$manifest.artifact.buildId
$modelSha256 = ([string]$manifest.artifact.modelSha256).ToUpperInvariant()
if (
    $sourceCommit -notmatch '^[0-9a-f]{40}$' -or
    $buildId -notmatch '^[0-9a-f]{12}$' -or
    $buildId -cne $sourceCommit.Substring(0, 12) -or
    $apkSha256 -notmatch '^[A-F0-9]{64}$' -or
    $certificateSha256 -notmatch '^[A-F0-9]{64}$' -or
    $pinnedCertificateSha256 -notmatch '^[A-F0-9]{64}$' -or
    $modelSha256 -notmatch '^[A-F0-9]{64}$' -or
    $packageName -cne 'com.lexiquest.app' -or
    $versionName -notmatch '^\d+\.\d+\.\d+$' -or
    $versionCode -notmatch '^\d+$'
) {
    throw 'Field-package manifest identity is invalid.'
}
if ($certificateSha256 -cne $pinnedCertificateSha256) {
    throw 'Field-package certificate does not match pinned signing metadata.'
}
if (
    [System.IO.Path]::IsPathRooted($apkName) -or
    [System.IO.Path]::GetFileName($apkName) -cne $apkName -or
    $apkName -notmatch '^lexiquest-\d+\.\d+\.\d+\+\d+\.apk$'
) {
    throw 'Field-package APK path must be a confined versioned filename.'
}
$apkPath = [System.IO.Path]::GetFullPath((Join-Path $resolvedPackage $apkName))
if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
    throw "Field-package APK is missing: $apkPath"
}
if ((Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash -cne $apkSha256) {
    throw 'Field-package APK SHA-256 does not match its manifest.'
}

$apkSigner = Find-ApkSigner
$signatureOutput = & $apkSigner verify --verbose --print-certs $apkPath 2>&1
if ([int]$LASTEXITCODE -ne 0) {
    throw 'apksigner rejected the field-package APK.'
}
$certificateMatches = [regex]::Matches(
    ($signatureOutput -join "`n"),
    '(?m)^(?:Signer #\d+|V\d+(?:\.\d+)? Signer):?\s+' +
        'certificate SHA-256 digest:\s*([A-Fa-f0-9:]{64,95})$'
)
if ($certificateMatches.Count -ne 1) {
    throw 'Field-package APK must contain exactly one signing certificate.'
}
$actualCertificateSha256 = $certificateMatches[0].Groups[1].Value.
    Replace(':', '').
    ToUpperInvariant()
if ($actualCertificateSha256 -cne $certificateSha256) {
    throw 'Field-package APK certificate does not match its manifest.'
}

$apkAnalyzer = Find-ApkAnalyzer
if (
    (Invoke-ApkAnalyzerValue -Analyzer $apkAnalyzer `
        -Verb 'application-id' -ApkPath $apkPath) -cne $packageName -or
    (Invoke-ApkAnalyzerValue -Analyzer $apkAnalyzer `
        -Verb 'version-name' -ApkPath $apkPath) -cne $versionName -or
    (Invoke-ApkAnalyzerValue -Analyzer $apkAnalyzer `
        -Verb 'version-code' -ApkPath $apkPath) -cne $versionCode
) {
    throw 'Field-package APK package or version identity does not match.'
}
$manifestText = (& $apkAnalyzer manifest print $apkPath 2>&1) -join "`n"
if ([int]$LASTEXITCODE -ne 0) {
    throw 'apkanalyzer could not decode the field-package APK manifest.'
}
[xml]$decodedManifest = $manifestText
$embeddedSourceCommit = Read-ApkMetadataValue -Manifest $decodedManifest `
    -Name 'com.lexiquest.release.SOURCE_COMMIT'
$embeddedBuildId = Read-ApkMetadataValue -Manifest $decodedManifest `
    -Name 'com.lexiquest.release.BUILD_ID'
$embeddedModelSha256 = Read-ApkMetadataValue -Manifest $decodedManifest `
    -Name 'com.lexiquest.release.MODEL_SHA256'
if (
    $embeddedSourceCommit -cne $sourceCommit -or
    $embeddedBuildId -cne $buildId -or
    $embeddedModelSha256 -cne $modelSha256
) {
    throw 'Embedded APK provenance does not match release-manifest.json.'
}

& powershell -NoProfile -ExecutionPolicy Bypass -File `
    $resolvedRuntimeVerifier -ApkPath $apkPath -BuildMode Release
if ([int]$LASTEXITCODE -ne 0) {
    throw 'Field-package APK model runtime integrity failed.'
}

Write-Host 'LexiQuest field package verification: PASS' -ForegroundColor Green
exit 0
