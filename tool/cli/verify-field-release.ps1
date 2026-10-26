#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$EvidenceRootPath,
    [string]$EvidencePath = 'release-evidence.json',
    [Parameter(Mandatory)]
    [string]$ParticipantPackagePath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'lib\field-release-evidence.ps1')

function Resolve-RepositoryPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

function Resolve-PackageArtifactPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        throw 'Release artifact paths must be package-relative.'
    }
    return [System.IO.Path]::GetFullPath((Join-Path $resolvedPackage $Path))
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
    throw 'apksigner is required to verify the release certificate.'
}

$resolvedEvidenceRoot = Resolve-RepositoryPath $EvidenceRootPath
if (-not (Test-Path -LiteralPath $resolvedEvidenceRoot -PathType Container)) {
    throw "Evidence root is missing: $resolvedEvidenceRoot"
}
$resolvedEvidence = Get-LexiQuestContainedPath `
    -Path $EvidencePath `
    -RootPath $resolvedEvidenceRoot
$resolvedPackage = Resolve-RepositoryPath $ParticipantPackagePath
if (-not (Test-Path -LiteralPath $resolvedEvidence -PathType Leaf)) {
    throw (
        (
            'Field evidence is missing: {0}. Collect physical low/mid/high, ' +
            'Fold, tablet, TalkBack, and UAT evidence; never replace it with ' +
            'simulation.'
        ) -f
        $resolvedEvidence
    )
}

$evidence = Get-Content -LiteralPath $resolvedEvidence -Raw -Encoding utf8 |
    ConvertFrom-Json
$releaseManifestPath = Join-Path $resolvedPackage 'release-manifest.json'
if (-not (Test-Path -LiteralPath $releaseManifestPath -PathType Leaf)) {
    throw "Packaged release manifest is missing: $releaseManifestPath"
}
$releaseManifest =
    Get-Content -LiteralPath $releaseManifestPath -Raw -Encoding utf8 |
        ConvertFrom-Json
if ([string]$evidence.releaseProfile -ne [string]$releaseManifest.releaseProfile) {
    throw 'Evidence releaseProfile does not match release-manifest.json.'
}
$packageErrors = @(
    Test-LexiQuestReleasePackage `
        -PackagePath $resolvedPackage `
        -Manifest $releaseManifest
)
if ($packageErrors.Count -gt 0) {
    throw (
        "Release package is not clean:`n - " +
        ($packageErrors -join "`n - ")
    )
}
$currentHead = (& git -C $repoRoot rev-parse HEAD).Trim()
$currentTree = (& git -C $repoRoot rev-parse 'HEAD^{tree}').Trim()
$relevantChanges = @(
    & git -C $repoRoot status --porcelain --untracked-files=all -- `
        android assets lib docs/field pubspec.yaml pubspec.lock `
        firebase.json firestore.rules firestore.indexes.json `
        tool/cli/package-field-release.ps1 `
        tool/cli/collect-android-field-evidence.ps1 `
        tool/cli/lib/field-release-evidence.ps1 `
        tool/cli/new-field-release-evidence.ps1 `
        tool/cli/verify-apk-model-runtime.ps1 `
        tool/cli/verify-field-release.ps1 `
        tool/cli/config/release-signing-trust.json
)
$sourceErrors = @(
    Test-LexiQuestReleaseSource `
        -ManifestSourceCommit ([string]$releaseManifest.sourceCommit) `
        -ManifestSourceTree ([string]$releaseManifest.sourceTree) `
        -CurrentHead $currentHead `
        -CurrentTree $currentTree `
        -RelevantChanges $relevantChanges
)
if ($sourceErrors.Count -gt 0) {
    throw (
        "Release source does not match the artifact manifest:`n - " +
        ($sourceErrors -join "`n - ")
    )
}
foreach ($field in @(
    'apkPath',
    'apkSha256',
    'aabPath',
    'aabSha256',
    'signingCertificateSha256',
    'packageName',
    'versionName',
    'versionCode',
    'buildId',
    'modelSha256'
)) {
    $evidenceValue = [string]$evidence.artifact.$field
    $manifestValue = [string]$releaseManifest.artifact.$field
    if ($evidenceValue -ne $manifestValue) {
        throw "Evidence artifact.$field does not match release-manifest.json."
    }
}
$apkPath = Resolve-PackageArtifactPath ([string]$evidence.artifact.apkPath)
if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
    throw "Release APK is missing: $apkPath"
}
$aabPath = Resolve-PackageArtifactPath ([string]$evidence.artifact.aabPath)
if (-not (Test-Path -LiteralPath $aabPath -PathType Leaf)) {
    throw "Release AAB is missing: $aabPath"
}

$actualApkSha256 = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash
$actualAabSha256 = (Get-FileHash -LiteralPath $aabPath -Algorithm SHA256).Hash
if ($actualAabSha256 -ne [string]$evidence.artifact.aabSha256) {
    throw 'Release AAB SHA-256 does not match field evidence.'
}
$jarSigner = Get-Command jarsigner -ErrorAction SilentlyContinue
if ($null -eq $jarSigner) {
    throw 'jarsigner is required to verify the release AAB.'
}
$aabSignatureOutput = & $jarSigner.Source -verify $aabPath 2>&1
$aabSignatureErrors = @(Test-LexiQuestJarSignerVerification `
    -ExitCode ([int]$LASTEXITCODE) `
    -Output @($aabSignatureOutput))
if ($aabSignatureErrors.Count -gt 0) {
    throw (
        "jarsigner rejected the release AAB:`n - " +
        ($aabSignatureErrors -join "`n - ")
    )
}
$aabCoverageErrors = @(
    Test-LexiQuestAabEntryCoverage -ArchivePath $aabPath
)
if ($aabCoverageErrors.Count -gt 0) {
    throw (
        "Release AAB contains unsigned or duplicate payload entries:`n - " +
        ($aabCoverageErrors -join "`n - ")
    )
}
$apkSigner = Find-ApkSigner
$signatureOutput = & $apkSigner verify --verbose --print-certs $apkPath 2>&1
if ([int]$LASTEXITCODE -ne 0) {
    throw "apksigner rejected the release APK: $signatureOutput"
}
$certificateMatch = [regex]::Match(
    ($signatureOutput -join "`n"),
    '(?m)^(?:Signer #1|V\d+(?:\.\d+)? Signer): ' +
        'certificate SHA-256 digest:\s*([A-Fa-f0-9:]{64,95})$'
)
if (-not $certificateMatch.Success) {
    throw 'apksigner did not report a SHA-256 signing certificate digest.'
}
$actualCertificateSha256 = $certificateMatch.Groups[1].Value
$keyTool = Get-Command keytool -ErrorAction SilentlyContinue
if ($null -eq $keyTool) {
    throw 'keytool is required to verify the release AAB certificate.'
}
$aabCertificateOutput = & $keyTool.Source -printcert -jarfile $aabPath 2>&1
$aabCertificateMatch = [regex]::Match(
    ($aabCertificateOutput -join "`n"),
    '(?im)^\s*SHA256:\s*([A-Fa-f0-9:]{95})\s*$'
)
if (-not $aabCertificateMatch.Success) {
    throw 'Unable to read the AAB signing certificate SHA-256.'
}
$aabCertificateSha256 = $aabCertificateMatch.Groups[1].Value.Replace(
    ':',
    ''
).ToUpperInvariant()
$normalizedApkCertificateSha256 = $actualCertificateSha256.Replace(
    ':',
    ''
).ToUpperInvariant()
if ($aabCertificateSha256 -ne $normalizedApkCertificateSha256) {
    throw 'APK and AAB signing certificates do not match.'
}
$resolvedTrust = Join-Path $repoRoot `
    'tool/cli/config/release-signing-trust.json'
if (-not (Test-Path -LiteralPath $resolvedTrust -PathType Leaf)) {
    throw 'The owner-approved release signing trust record is missing.'
}
$signingTrust = Get-Content -LiteralPath $resolvedTrust -Raw -Encoding utf8 |
    ConvertFrom-Json
$expectedCertificateSha256 =
    ConvertTo-NormalizedSha256 $signingTrust.uploadCertificateSha256
$expectedModelSha256 = Get-LexiQuestPinnedModelSha256 -RepoRoot $repoRoot
$expectedVersion = '{0}+{1}' -f
    $releaseManifest.artifact.versionName,
    $releaseManifest.artifact.versionCode
$measuredApk = Get-LexiQuestMeasuredApkMetadata `
    -ApkPath $apkPath `
    -ExpectedBuildId ([string]$releaseManifest.sourceCommit) `
    -ExpectedModelSha256 $expectedModelSha256 `
    -ExpectedVersion $expectedVersion
$measuredAab = Get-LexiQuestMeasuredAabMetadata -AabPath $aabPath
$metadataErrors = @(Test-LexiQuestArtifactMetadata `
    -Measured $measuredApk `
    -Expected $releaseManifest.artifact `
    -ExpectedCertificateSha256 $expectedCertificateSha256 `
    -ExpectedModelSha256 $expectedModelSha256)
if ($metadataErrors.Count -gt 0) {
    throw (
        "Signed APK metadata does not match source or manifest:`n - " +
        ($metadataErrors -join "`n - ")
    )
}
$identityErrors = @(Test-LexiQuestAndroidArtifactIdentity `
    -MeasuredApk $measuredApk `
    -MeasuredAab $measuredAab `
    -Expected $releaseManifest.artifact)
if ($identityErrors.Count -gt 0) {
    throw (
        "Signed APK/AAB identities do not match release-manifest.json:`n - " +
        ($identityErrors -join "`n - ")
    )
}
foreach ($token in @(
    [string]$releaseManifest.sourceCommit,
    $expectedModelSha256.ToLowerInvariant(),
    $expectedVersion
)) {
    if (-not (Test-LexiQuestArchiveContainsAsciiToken `
        -ArchivePath $aabPath `
        -Token $token)) {
        throw "Signed AAB does not embed the required provenance token: $token"
    }
}

$evidenceErrors = Test-LexiQuestReferencedFieldReleaseEvidence `
    -Evidence $evidence `
    -ActualApkSha256 $actualApkSha256 `
    -ActualCertificateSha256 $actualCertificateSha256 `
    -ExpectedCertificateSha256 $expectedCertificateSha256 `
    -ParticipantPackagePath $resolvedPackage `
    -EvidenceRootPath $resolvedEvidenceRoot
if ($evidenceErrors.Count -gt 0) {
    $message = "Field release evidence is incomplete:`n - " +
        ($evidenceErrors -join "`n - ")
    throw $message
}

& powershell -NoProfile -ExecutionPolicy Bypass -File `
    (Join-Path $PSScriptRoot 'verify-product-completion.ps1')
if ([int]$LASTEXITCODE -ne 0) {
    throw 'P7 product completion gate failed.'
}

& powershell -NoProfile -ExecutionPolicy Bypass -File `
    (Join-Path $PSScriptRoot 'verify-apk-model-runtime.ps1') `
    -ArchivePath $aabPath `
    -BuildMode Release
if ([int]$LASTEXITCODE -ne 0) {
    throw 'Release AAB model runtime integrity failed.'
}

& powershell -NoProfile -ExecutionPolicy Bypass -File `
    (Join-Path $PSScriptRoot 'verify-apk-model-runtime.ps1') `
    -ApkPath $apkPath
if ([int]$LASTEXITCODE -ne 0) {
    throw 'Release APK model runtime integrity failed.'
}

Write-Host 'LexiQuest P8 field release gate: PASS' -ForegroundColor Green
exit 0
