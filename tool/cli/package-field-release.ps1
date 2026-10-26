#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputPath = 'build/field-release',
    [string]$Version = '1.0.0+1',
    [ValidateSet('fieldTrial', 'publicProduction')]
    [string]$ReleaseProfile = 'fieldTrial'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'lib\field-release-evidence.ps1')

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
    if ($env:OS -eq 'Windows_NT') {
        $keyPropertiesAcl = Get-Acl -LiteralPath 'android/key.properties'
        $sandboxRead = @(
            $keyPropertiesAcl.Access |
                Where-Object {
                    $_.AccessControlType -eq 'Allow' -and
                    $_.IdentityReference.Value -match 'CodexSandboxUsers'
                }
        )
        if (-not $keyPropertiesAcl.AreAccessRulesProtected -or $sandboxRead) {
            throw (
                'android/key.properties ACL is not owner-restricted; ' +
                'CodexSandboxUsers or inherited readers can access it.'
            )
        }
    }
    $trustFile = Join-Path $repoRoot `
        'tool/cli/config/release-signing-trust.json'
    if (-not (Test-Path -LiteralPath $trustFile -PathType Leaf)) {
        throw 'The owner-approved upload certificate trust record is missing.'
    }
    $signingTrust = Get-Content -LiteralPath $trustFile -Raw -Encoding utf8 |
        ConvertFrom-Json
    $expectedCertificateSha256 =
        ConvertTo-NormalizedSha256 $signingTrust.uploadCertificateSha256
    if ($expectedCertificateSha256 -notmatch '^[A-F0-9]{64}$') {
        throw 'The owner-approved upload certificate SHA-256 is invalid.'
    }

    $resolvedOutputRoot = if (
        [System.IO.Path]::IsPathRooted($OutputPath)
    ) {
        [System.IO.Path]::GetFullPath($OutputPath)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputPath))
    }
    $resolvedOutput = Join-Path $resolvedOutputRoot "lexiquest-$Version"
    if (
        (Test-Path -LiteralPath $resolvedOutput) -and
        @(Get-ChildItem -LiteralPath $resolvedOutput -Force).Count -gt 0
    ) {
        throw "Release staging directory must be empty: $resolvedOutput"
    }
    $relevantChanges = @(
        & git status --porcelain --untracked-files=all -- `
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
    if ($relevantChanges.Count -gt 0) {
        throw (
            'Android-relevant release sources contain uncommitted changes: ' +
            ($relevantChanges -join ', ')
        )
    }

    $sourceCommit = (& git rev-parse HEAD).Trim()
    $sourceTree = (& git rev-parse 'HEAD^{tree}').Trim()
    $buildId = $sourceCommit
    $modelSha256 = Get-LexiQuestPinnedModelSha256 -RepoRoot $repoRoot
    & flutter build apk --release --no-pub `
        "--build-name=$($Version.Split('+')[0])" `
        "--build-number=$($Version.Split('+')[1])" `
        --dart-define=LEXIQUEST_CLOUD_SYNC_ENABLED=true `
        "--dart-define=LEXIQUEST_VERSION=$Version" `
        "--dart-define=LEXIQUEST_BUILD_ID=$buildId"
    if ([int]$LASTEXITCODE -ne 0) {
        throw 'Flutter release APK build failed.'
    }
    & flutter build appbundle --release --no-pub `
        "--build-name=$($Version.Split('+')[0])" `
        "--build-number=$($Version.Split('+')[1])" `
        --dart-define=LEXIQUEST_CLOUD_SYNC_ENABLED=true `
        "--dart-define=LEXIQUEST_VERSION=$Version" `
        "--dart-define=LEXIQUEST_BUILD_ID=$buildId"
    if ([int]$LASTEXITCODE -ne 0) {
        throw 'Flutter release AAB build failed.'
    }

    $sourceApk = Join-Path $repoRoot `
        'build/app/outputs/flutter-apk/app-release.apk'
    $sourceAab = Join-Path $repoRoot `
        'build/app/outputs/bundle/release/app-release.aab'
    New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
    $releaseApkName = "lexiquest-$Version.apk"
    $releaseAabName = "lexiquest-$Version.aab"
    $releaseApk = Join-Path $resolvedOutput $releaseApkName
    $releaseAab = Join-Path $resolvedOutput $releaseAabName
    Copy-Item -LiteralPath $sourceApk -Destination $releaseApk -Force
    Copy-Item -LiteralPath $sourceAab -Destination $releaseAab -Force

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
    if ($certificateSha256 -ne $expectedCertificateSha256) {
        throw (
            'Packaged APK does not use the owner-approved upload certificate.'
        )
    }
    $jarSigner = Get-Command jarsigner -ErrorAction SilentlyContinue
    if ($null -eq $jarSigner) {
        throw 'jarsigner is required before packaging a field release.'
    }
    $aabSignatureOutput = & $jarSigner.Source -verify $releaseAab 2>&1
    $aabSignatureErrors = @(Test-LexiQuestJarSignerVerification `
        -ExitCode ([int]$LASTEXITCODE) `
        -Output @($aabSignatureOutput))
    if ($aabSignatureErrors.Count -gt 0) {
        throw (
            "jarsigner rejected the packaged AAB:`n - " +
            ($aabSignatureErrors -join "`n - ")
        )
    }
    $aabCoverageErrors = @(
        Test-LexiQuestAabEntryCoverage -ArchivePath $releaseAab
    )
    if ($aabCoverageErrors.Count -gt 0) {
        throw (
            "Packaged AAB contains unsigned or duplicate payload entries:`n - " +
            ($aabCoverageErrors -join "`n - ")
        )
    }
    $keyTool = Get-Command keytool -ErrorAction SilentlyContinue
    if ($null -eq $keyTool) {
        throw 'keytool is required before packaging a field release.'
    }
    $aabCertificateOutput = & $keyTool.Source -printcert -jarfile `
        $releaseAab 2>&1
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
    if ($aabCertificateSha256 -ne $certificateSha256) {
        throw 'APK and AAB signing certificates do not match.'
    }
    $apkSha256 = (Get-FileHash -LiteralPath $releaseApk -Algorithm SHA256).Hash
    $aabSha256 = (Get-FileHash -LiteralPath $releaseAab -Algorithm SHA256).Hash
    $measuredApk = Get-LexiQuestMeasuredApkMetadata `
        -ApkPath $releaseApk `
        -ExpectedBuildId $buildId `
        -ExpectedModelSha256 $modelSha256 `
        -ExpectedVersion $Version
    $measuredAab = Get-LexiQuestMeasuredAabMetadata -AabPath $releaseAab
    $expectedArtifact = [pscustomobject]@{
        apkSha256 = $apkSha256
        signingCertificateSha256 = $certificateSha256
        packageName = 'com.lexiquest.app'
        versionName = $Version.Split('+')[0]
        versionCode = [int]$Version.Split('+')[1]
        buildId = $buildId
        modelSha256 = $modelSha256
    }
    $metadataErrors = @(Test-LexiQuestArtifactMetadata `
        -Measured $measuredApk `
        -Expected $expectedArtifact `
        -ExpectedCertificateSha256 $expectedCertificateSha256 `
        -ExpectedModelSha256 $modelSha256)
    if ($metadataErrors.Count -gt 0) {
        throw (
            "Signed APK metadata does not match the build inputs:`n - " +
            ($metadataErrors -join "`n - ")
        )
    }
    $identityErrors = @(Test-LexiQuestAndroidArtifactIdentity `
        -MeasuredApk $measuredApk `
        -MeasuredAab $measuredAab `
        -Expected $expectedArtifact)
    if ($identityErrors.Count -gt 0) {
        throw (
            "Signed APK/AAB identities do not match build inputs:`n - " +
            ($identityErrors -join "`n - ")
        )
    }
    foreach ($token in @($buildId, $modelSha256.ToLowerInvariant(), $Version)) {
        if (-not (Test-LexiQuestArchiveContainsAsciiToken `
            -ArchivePath $releaseAab `
            -Token $token)) {
            throw "Signed AAB does not embed the required provenance token: $token"
        }
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File `
        (Join-Path $PSScriptRoot 'verify-apk-model-runtime.ps1') `
        -ArchivePath $releaseAab `
        -BuildMode Release
    if ([int]$LASTEXITCODE -ne 0) {
        throw 'Release AAB model runtime integrity failed.'
    }

    $docsOutput = Join-Path $resolvedOutput 'docs'
    New-Item -ItemType Directory -Path $docsOutput -Force | Out-Null
    $participantDocuments = Get-LexiQuestParticipantDocumentNames `
        -ReleaseProfile $ReleaseProfile
    foreach ($document in $participantDocuments) {
        Copy-Item -LiteralPath (Join-Path 'docs/field' $document) `
            -Destination $docsOutput
    }
    $participantDocumentManifest = @(
        $participantDocuments |
            ForEach-Object {
                $relative = 'docs/' + $_
                [ordered]@{
                    path = $relative
                    sha256 = (Get-FileHash -LiteralPath (
                        Join-Path $resolvedOutput $relative
                    ) -Algorithm SHA256).Hash
                }
            }
    )

    $manifest = [ordered]@{
        schemaVersion = 3
        releaseProfile = $ReleaseProfile
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        sourceCommit = $sourceCommit
        sourceTree = $sourceTree
        artifact = [ordered]@{
            apkPath = $releaseApkName
            apkSha256 = $measuredApk.archiveSha256
            aabPath = $releaseAabName
            aabSha256 = $measuredAab.archiveSha256
            signingCertificateSha256 = $certificateSha256
            packageName = $measuredAab.applicationId
            versionName = $measuredAab.versionName
            versionCode = $measuredAab.versionCode
            buildId = $buildId
            modelSha256 = $modelSha256
        }
        participantDocuments = $participantDocumentManifest
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $resolvedOutput 'release-manifest.json'),
        (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine),
        [System.Text.UTF8Encoding]::new($false)
    )
    $packageErrors = @(
        Test-LexiQuestReleasePackage `
            -PackagePath $resolvedOutput `
            -Manifest ([pscustomobject]$manifest)
    )
    if ($packageErrors.Count -gt 0) {
        throw (
            "Release package is not clean:`n - " +
            ($packageErrors -join "`n - ")
        )
    }
    Write-Host "Field release package created: $resolvedOutput" `
        -ForegroundColor Green
}
finally {
    Pop-Location
}
