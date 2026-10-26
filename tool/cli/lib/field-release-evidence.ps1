#Requires -Version 5.1
Set-StrictMode -Version 3.0

function Get-LexiQuestRequiredFieldJourneys {
    return @(
        'consentGuestStartup',
        'offlineVocabulary',
        'learningCore',
        'offlineRestartSync',
        'accountLifecycle',
        'modelLifecycle',
        'cameraScanner',
        'speechTtsPronunciation',
        'geminiByok',
        'cleanInstall',
        'upgradeInstall',
        'rebootForegroundBackground',
        'cloudKillSwitch',
        'dataExport'
    )
}

function ConvertTo-NormalizedSha256 {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return ''
    }
    return ([string]$Value).Replace(':', '').Trim().ToUpperInvariant()
}

function Assert-LexiQuestNoReparsePoint {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
    $current = $pathRoot
    $relative = $fullPath.Substring($pathRoot.Length)
    $components = @(
        $relative.Split(
            [char[]]@(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            ),
            [System.StringSplitOptions]::RemoveEmptyEntries
        )
    )
    foreach ($component in $components) {
        $current = Join-Path $current $component
        if (-not (Test-Path -LiteralPath $current)) {
            continue
        }
        $item = Get-Item -LiteralPath $current -Force
        $isReparsePoint = ($item.Attributes -band
            [System.IO.FileAttributes]::ReparsePoint) -ne 0
        $linkTypeProperty = $item.PSObject.Properties['LinkType']
        $hasLinkType = $null -ne $linkTypeProperty -and
            -not [string]::IsNullOrWhiteSpace(
                [string]$linkTypeProperty.Value
            )
        if ($isReparsePoint -or $hasLinkType) {
            throw "Evidence paths cannot traverse a reparse point or link: $current"
        }
    }
}

function Get-LexiQuestDerivedDeviceTier {
    param(
        [Parameter(Mandatory)][double]$RamMb,
        [Parameter(Mandatory)][int]$Sdk
    )

    if ($RamMb -le 0 -or $Sdk -lt 26) {
        throw 'Device tier requires measured positive RAM and a supported API level.'
    }
    if ($RamMb -le 4096 -and $Sdk -ge 30 -and $Sdk -le 32) {
        return 'low'
    }
    if ($RamMb -ge 8192 -and $Sdk -ge 34) {
        return 'high'
    }
    return 'mid'
}

function Get-LexiQuestDerivedFormFactor {
    param(
        [Parameter(Mandatory)][double]$SmallestWidthDp,
        [Parameter(Mandatory)][bool]$HasHingeSensor,
        [Parameter(Mandatory)][bool]$FoldFeatureObserved,
        [Parameter(Mandatory)][bool]$UnsupportedFormFactorFeature
    )

    if ($UnsupportedFormFactorFeature) {
        throw 'Watch, TV, automotive, and embedded Android devices are unsupported.'
    }
    if ($SmallestWidthDp -le 0) {
        throw 'Form-factor derivation requires a measured smallest window width.'
    }
    if ($HasHingeSensor -or $FoldFeatureObserved) {
        return 'foldable'
    }
    if ($SmallestWidthDp -ge 600) {
        return 'tablet'
    }
    return 'phone'
}

function Test-LexiQuestEvidenceReferenceShape {
    param([AllowNull()][object]$Reference)

    if ($null -eq $Reference -or $Reference -is [string]) {
        return $false
    }
    $pathProperty = $Reference.PSObject.Properties['path']
    $hashProperty = $Reference.PSObject.Properties['sha256']
    return (
        $null -ne $pathProperty -and
        $null -ne $hashProperty -and
        -not [string]::IsNullOrWhiteSpace([string]$pathProperty.Value) -and
        (ConvertTo-NormalizedSha256 $hashProperty.Value) -match
            '^[A-F0-9]{64}$'
    )
}

function Get-LexiQuestContainedPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RootPath
    )

    $root = [System.IO.Path]::GetFullPath($RootPath).TrimEnd(
        [char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
    )
    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $root $Path))
    }
    $prefix = $root + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith(
        $prefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Evidence path must be contained by its evidence root: $Path"
    }
    Assert-LexiQuestNoReparsePoint -Path $root
    Assert-LexiQuestNoReparsePoint -Path $candidate
    return $candidate
}

function New-LexiQuestEvidenceReference {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$EvidenceRootPath
    )

    $root = [System.IO.Path]::GetFullPath($EvidenceRootPath).TrimEnd(
        [char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
    )
    $resolved = Get-LexiQuestContainedPath -Path $Path -RootPath $root
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "Evidence record is missing: $resolved"
    }
    $relative = $resolved.Substring($root.Length).TrimStart(
        [char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
    ).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
    return [pscustomobject]@{
        path = $relative
        sha256 = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
    }
}

function Resolve-LexiQuestEvidenceReference {
    param(
        [Parameter(Mandatory)][object]$Reference,
        [Parameter(Mandatory)][string]$EvidenceRootPath
    )

    $relative = [string]$Reference.path
    if (
        [string]::IsNullOrWhiteSpace($relative) -or
        [System.IO.Path]::IsPathRooted($relative)
    ) {
        throw 'Evidence record path must be a non-empty relative path.'
    }
    $resolved = Get-LexiQuestContainedPath `
        -Path $relative `
        -RootPath $EvidenceRootPath
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "Evidence record is missing: $relative"
    }
    $expected = ConvertTo-NormalizedSha256 $Reference.sha256
    $actual = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
    if ($expected -notmatch '^[A-F0-9]{64}$' -or $actual -ne $expected) {
        throw "Evidence record SHA-256 mismatch: $relative"
    }
    return $resolved
}

function Read-LexiQuestEvidenceRecord {
    param(
        [Parameter(Mandatory)][object]$Reference,
        [Parameter(Mandatory)][string]$EvidenceRootPath
    )

    $resolved = Resolve-LexiQuestEvidenceReference `
        -Reference $Reference `
        -EvidenceRootPath $EvidenceRootPath
    return Get-Content -LiteralPath $resolved -Raw -Encoding utf8 |
        ConvertFrom-Json
}

function Test-LexiQuestContainedEvidenceReferences {
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][string]$EvidenceRootPath,
        [string]$Context = 'evidence'
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    function Visit-ReferenceValue {
        param([AllowNull()][object]$Node, [string]$NodeContext)

        if ($null -eq $Node -or $Node -is [string] -or
            $Node -is [ValueType]) {
            return
        }
        if ($Node -is [System.Collections.IEnumerable] -and
            $Node -isnot [pscustomobject]) {
            $index = 0
            foreach ($item in $Node) {
                Visit-ReferenceValue $item "$NodeContext[$index]"
                $index++
            }
            return
        }
        foreach ($property in $Node.PSObject.Properties) {
            $propertyContext = "$NodeContext.$($property.Name)"
            if ($property.Name -match '(?i)(?:evidenceRef|channelRef|protocolRef)$') {
                try {
                    Resolve-LexiQuestEvidenceReference `
                        -Reference $property.Value `
                        -EvidenceRootPath $EvidenceRootPath | Out-Null
                }
                catch {
                    $errors.Add("${propertyContext}: $($_.Exception.Message)")
                }
            } else {
                Visit-ReferenceValue $property.Value $propertyContext
            }
        }
    }
    Visit-ReferenceValue $Value $Context
    return $errors.ToArray()
}

function Get-LexiQuestPinnedModelSha256 {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $manifestPath = Join-Path $RepoRoot `
        'lib/features/device_model/domain/model_manifest.dart'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Committed model manifest is missing: $manifestPath"
    }
    $source = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8
    $match = [regex]::Match(
        $source,
        "(?s)fieldImageClassifier\s*=\s*ModelManifest\(.*?" +
            "expectedSha256:\s*'([0-9a-f]{64})'"
    )
    if (-not $match.Success) {
        throw 'Unable to resolve the committed field model SHA-256 pin.'
    }
    return $match.Groups[1].Value.ToUpperInvariant()
}

function Test-LexiQuestArtifactMetadata {
    param(
        [Parameter(Mandatory)][object]$Measured,
        [Parameter(Mandatory)][object]$Expected,
        [Parameter(Mandatory)][string]$ExpectedCertificateSha256,
        [Parameter(Mandatory)][string]$ExpectedModelSha256
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    if (
        (ConvertTo-NormalizedSha256 $Measured.archiveSha256) -ne
        (ConvertTo-NormalizedSha256 $Expected.apkSha256)
    ) {
        $errors.Add('measured artifact SHA-256 does not match the manifest.')
    }
    foreach ($field in @('packageName', 'versionName', 'versionCode')) {
        if ([string]$Measured.$field -ne [string]$Expected.$field) {
            $errors.Add("measured artifact $field does not match the manifest.")
        }
    }
    if ([string]$Measured.embeddedBuildId -ne [string]$Expected.buildId) {
        $errors.Add(
            'signed artifact embedded build ID does not match the source commit.'
        )
    }
    $sourceModel = ConvertTo-NormalizedSha256 $ExpectedModelSha256
    if ((ConvertTo-NormalizedSha256 $Expected.modelSha256) -ne $sourceModel) {
        $errors.Add('manifest model SHA-256 does not match the committed model pin.')
    }
    if ((ConvertTo-NormalizedSha256 $Measured.embeddedModelSha256) -ne
        $sourceModel) {
        $errors.Add('signed artifact does not embed the committed model pin.')
    }
    $trustedCertificate = ConvertTo-NormalizedSha256 `
        $ExpectedCertificateSha256
    if ((ConvertTo-NormalizedSha256 `
        $Expected.signingCertificateSha256) -ne $trustedCertificate) {
        $errors.Add('manifest signing certificate is outside committed trust.')
    }
    if ((ConvertTo-NormalizedSha256 `
        $Measured.signingCertificateSha256) -ne $trustedCertificate) {
        $errors.Add('measured signing certificate is outside committed trust.')
    }
    return $errors.ToArray()
}

function Find-LexiQuestAndroidSdkTool {
    param([Parameter(Mandatory)][string]$ToolName)

    $command = Get-Command $ToolName -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }
    $sdkRoots = @(
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($sdkRoot in @($sdkRoots | Select-Object -Unique)) {
        $candidates = if ($ToolName -eq 'apkanalyzer') {
            @(
                Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'cmdline-tools') `
                    -Recurse -File -Filter 'apkanalyzer.bat' `
                    -ErrorAction SilentlyContinue |
                    Sort-Object FullName -Descending |
                    Select-Object -ExpandProperty FullName
            )
        } else {
            @(
                Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'build-tools') `
                    -Directory -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending |
                    ForEach-Object {
                        Join-Path $_.FullName "$ToolName.bat"
                    } |
                    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
            )
        }
        if ($candidates.Count -gt 0) {
            return [string]$candidates[0]
        }
    }
    throw "$ToolName is required for Android release verification."
}

function Get-LexiQuestApkCertificateSha256 {
    param(
        [Parameter(Mandatory)][string]$ApkPath,
        [string]$ApkSignerPath = ''
    )

    $signer = if ([string]::IsNullOrWhiteSpace($ApkSignerPath)) {
        Find-LexiQuestAndroidSdkTool -ToolName 'apksigner'
    } else {
        $ApkSignerPath
    }
    $LASTEXITCODE = 0
    $output = & $signer verify --verbose --print-certs $ApkPath 2>&1
    if ([int]$LASTEXITCODE -ne 0) {
        throw "apksigner rejected the APK: $output"
    }
    $match = [regex]::Match(
        ($output -join "`n"),
        '(?m)^(?:Signer #1|V\d+(?:\.\d+)? Signer): ' +
            'certificate SHA-256 digest:\s*([A-Fa-f0-9:]{64,95})$'
    )
    if (-not $match.Success) {
        throw 'apksigner did not report a SHA-256 certificate digest.'
    }
    return ConvertTo-NormalizedSha256 $match.Groups[1].Value
}

function Test-LexiQuestArchiveContainsAsciiToken {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$Token
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $appLibraries = @(
            $archive.Entries |
                Where-Object {
                    $_.FullName.Replace([char]92, [char]47) -match
                        '^(?:base/)?lib/[^/]+/libapp\.so$'
                }
        )
        if ($appLibraries.Count -eq 0) {
            return $false
        }
        foreach ($entry in $appLibraries) {
            $stream = $entry.Open()
            $memory = [System.IO.MemoryStream]::new()
            try {
                $stream.CopyTo($memory)
                $text = [System.Text.Encoding]::ASCII.GetString(
                    $memory.ToArray()
                )
                if (-not $text.Contains($Token)) {
                    return $false
                }
            }
            finally {
                $memory.Dispose()
                $stream.Dispose()
            }
        }
        return $true
    }
    finally {
        $archive.Dispose()
    }
}

function Get-LexiQuestMeasuredApkMetadata {
    param(
        [Parameter(Mandatory)][string]$ApkPath,
        [Parameter(Mandatory)][string]$ExpectedBuildId,
        [Parameter(Mandatory)][string]$ExpectedModelSha256,
        [Parameter(Mandatory)][string]$ExpectedVersion,
        [string[]]$ProvenanceArchivePaths = @()
    )

    $analyzer = Find-LexiQuestAndroidSdkTool -ToolName 'apkanalyzer'
    $LASTEXITCODE = 0
    $packageName = (& $analyzer manifest application-id $ApkPath 2>$null |
        Select-Object -First 1)
    if ([int]$LASTEXITCODE -ne 0) {
        throw 'apkanalyzer could not read the APK application ID.'
    }
    $LASTEXITCODE = 0
    $versionCode = (& $analyzer manifest version-code $ApkPath 2>$null |
        Select-Object -First 1)
    if ([int]$LASTEXITCODE -ne 0) {
        throw 'apkanalyzer could not read the APK version code.'
    }
    $LASTEXITCODE = 0
    $versionName = (& $analyzer manifest version-name $ApkPath 2>$null |
        Select-Object -First 1)
    if ([int]$LASTEXITCODE -ne 0) {
        throw 'apkanalyzer could not read the APK version name.'
    }
    $model = ConvertTo-NormalizedSha256 $ExpectedModelSha256
    $provenanceArchives = if ($ProvenanceArchivePaths.Count -gt 0) {
        @($ProvenanceArchivePaths)
    } else {
        @($ApkPath)
    }
    $provenanceArchive = @(
        $provenanceArchives |
            Where-Object {
                (Test-LexiQuestArchiveContainsAsciiToken `
                    -ArchivePath $_ `
                    -Token $ExpectedBuildId) -and
                (Test-LexiQuestArchiveContainsAsciiToken `
                    -ArchivePath $_ `
                    -Token $model.ToLowerInvariant()) -and
                (Test-LexiQuestArchiveContainsAsciiToken `
                    -ArchivePath $_ `
                    -Token $ExpectedVersion)
            }
    ) | Select-Object -First 1
    if ($null -eq $provenanceArchive) {
        throw 'Signed APK set does not embed the expected build, model, and version provenance.'
    }
    return [pscustomobject]@{
        archiveSha256 = (Get-FileHash -LiteralPath $ApkPath `
            -Algorithm SHA256).Hash
        packageName = ([string]$packageName).Trim()
        versionName = ([string]$versionName).Trim()
        versionCode = [int]([string]$versionCode).Trim()
        embeddedBuildId = $ExpectedBuildId
        embeddedModelSha256 = $model
        signingCertificateSha256 = Get-LexiQuestApkCertificateSha256 `
            -ApkPath $ApkPath
    }
}

function Find-LexiQuestBundletoolClasspath {
    $java = Get-Command java -ErrorAction SilentlyContinue
    if ($null -eq $java) {
        throw 'Java is required to measure Android App Bundle metadata.'
    }
    $userProfile = [Environment]::GetFolderPath('UserProfile')
    $gradleHome = if (-not [string]::IsNullOrWhiteSpace(
        [string]$env:GRADLE_USER_HOME
    )) {
        [string]$env:GRADLE_USER_HOME
    } else {
        Join-Path $userProfile '.gradle'
    }
    $bundletoolRoot = Join-Path $gradleHome (
        'caches/modules-2/files-2.1/com.android.tools.build/bundletool'
    )
    $bundletoolVersions = @(
        Get-ChildItem -LiteralPath $bundletoolRoot -Directory `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -as [version] } |
            Sort-Object { [version]$_.Name } -Descending
    )
    $bundletoolJar = @(
        foreach ($version in $bundletoolVersions) {
            Get-ChildItem -LiteralPath $version.FullName -Recurse -File `
                -Filter 'bundletool-*.jar' -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty FullName
        }
    ) | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace([string]$bundletoolJar)) {
        throw 'A cached Gradle bundletool JAR is required to measure the AAB manifest.'
    }

    $joseRoot = Join-Path $gradleHome (
        'caches/modules-2/files-2.1/org.bitbucket.b_c/jose4j'
    )
    $joseVersions = @(
        Get-ChildItem -LiteralPath $joseRoot -Directory `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -as [version] } |
            Sort-Object { [version]$_.Name } -Descending
    )
    $joseJar = @(
        foreach ($version in $joseVersions) {
            Get-ChildItem -LiteralPath $version.FullName -Recurse -File `
                -Filter 'jose4j-*.jar' -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty FullName
        }
    ) | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace([string]$joseJar)) {
        throw 'A cached jose4j JAR is required by bundletool.'
    }

    $sdkRoots = @(
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $analyzerClasspath = @(
        foreach ($sdkRoot in @($sdkRoots | Select-Object -Unique)) {
            Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'cmdline-tools') `
                -Recurse -File -Filter 'apkanalyzer-classpath.jar' `
                -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                Select-Object -ExpandProperty FullName
        }
    ) | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace([string]$analyzerClasspath)) {
        throw 'Android cmdline-tools apkanalyzer classpath is required by bundletool.'
    }
    return [pscustomobject]@{
        java = $java.Source
        classpath = @($bundletoolJar, $analyzerClasspath, $joseJar) -join
            [System.IO.Path]::PathSeparator
    }
}

function Get-LexiQuestMeasuredAabMetadata {
    param([Parameter(Mandatory)][string]$AabPath)

    $tooling = Find-LexiQuestBundletoolClasspath
    $LASTEXITCODE = 0
    $output = @(
        & $tooling.java -cp $tooling.classpath `
            com.android.tools.build.bundletool.BundleToolMain `
            dump manifest "--bundle=$AabPath" --module=base 2>&1
    )
    if ([int]$LASTEXITCODE -ne 0) {
        throw "bundletool could not read the AAB manifest: $output"
    }
    $manifestMatch = [regex]::Match(
        ($output -join "`n"),
        '(?s)<manifest\b.*?</manifest>'
    )
    if (-not $manifestMatch.Success) {
        throw 'bundletool did not return an Android manifest.'
    }
    [xml]$manifestXml = $manifestMatch.Value
    $manifest = $manifestXml.DocumentElement
    $androidNamespace = 'http://schemas.android.com/apk/res/android'
    $applicationId = $manifest.GetAttribute('package')
    $versionName = $manifest.GetAttribute('versionName', $androidNamespace)
    $versionCode = $manifest.GetAttribute('versionCode', $androidNamespace)
    if (
        [string]::IsNullOrWhiteSpace($applicationId) -or
        [string]::IsNullOrWhiteSpace($versionName) -or
        $versionCode -notmatch '^\d+$'
    ) {
        throw 'AAB manifest package/version metadata is incomplete.'
    }
    return [pscustomobject]@{
        archiveSha256 = (Get-FileHash -LiteralPath $AabPath `
            -Algorithm SHA256).Hash
        applicationId = $applicationId
        packageName = $applicationId
        versionName = $versionName
        versionCode = [int]$versionCode
    }
}

function Test-LexiQuestAndroidArtifactIdentity {
    param(
        [Parameter(Mandatory)][object]$MeasuredApk,
        [Parameter(Mandatory)][object]$MeasuredAab,
        [Parameter(Mandatory)][object]$Expected
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $aabApplicationId = [string]$MeasuredAab.applicationId
    if (
        $aabApplicationId -ne [string]$MeasuredApk.packageName -or
        $aabApplicationId -ne [string]$Expected.packageName
    ) {
        $errors.Add('measured AAB application ID does not match the APK and manifest.')
    }
    foreach ($field in @('versionName', 'versionCode')) {
        if (
            [string]$MeasuredAab.$field -ne [string]$MeasuredApk.$field -or
            [string]$MeasuredAab.$field -ne [string]$Expected.$field
        ) {
            $errors.Add(
                "measured AAB $field does not match the APK and manifest."
            )
        }
    }
    return $errors.ToArray()
}

function Test-LexiQuestJarSignerVerification {
    param(
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][object[]]$Output
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $text = $Output -join "`n"
    if ($ExitCode -ne 0 -or $text -notmatch '(?im)^jar verified\.$') {
        $errors.Add('jarsigner did not verify the AAB.')
    }
    if ($text -match '(?i)contains unsigned entries') {
        $errors.Add('jarsigner reports that the AAB contains unsigned entries.')
    }
    return $errors.ToArray()
}

function Test-LexiQuestAabEntryCoverage {
    param([Parameter(Mandatory)][string]$ArchivePath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $errors = [System.Collections.Generic.List[string]]::new()
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $manifestEntry = @(
            $archive.Entries |
                Where-Object {
                    $_.FullName.Replace([char]92, [char]47) -eq
                        'META-INF/MANIFEST.MF'
                }
        ) | Select-Object -First 1
        if ($null -eq $manifestEntry) {
            return @('AAB signed manifest is missing.')
        }
        $reader = [System.IO.StreamReader]::new($manifestEntry.Open())
        try {
            $manifestText = $reader.ReadToEnd() -replace '\r?\n ', ''
        }
        finally {
            $reader.Dispose()
        }
        $signedNames = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($section in @($manifestText -split '(?:\r?\n){2,}')) {
            $name = [regex]::Match($section, '(?m)^Name:\s*(.+)$')
            $digest = [regex]::Match(
                $section,
                '(?m)^SHA-(?:256|384|512)-Digest:\s*\S+'
            )
            if ($name.Success -and $digest.Success) {
                [void]$signedNames.Add($name.Groups[1].Value.Trim())
            }
        }
        $entryNames = @(
            $archive.Entries |
                Where-Object {
                    -not $_.FullName.EndsWith('/')
                } |
                ForEach-Object {
                    $_.FullName.Replace([char]92, [char]47)
                }
        )
        $duplicates = @(
            $entryNames | Group-Object | Where-Object Count -gt 1
        )
        foreach ($duplicate in $duplicates) {
            $errors.Add("AAB contains duplicate entry: $($duplicate.Name)")
        }
        $payloadNames = @(
            $entryNames |
                Where-Object {
                    $_ -notmatch (
                        '^(?i)META-INF/(?:MANIFEST\.MF|' +
                        '[^/]+\.(?:SF|RSA|DSA|EC))$'
                    )
                }
        )
        foreach ($entryName in $payloadNames) {
            if (-not $signedNames.Contains($entryName)) {
                $errors.Add("AAB contains unsigned entry: $entryName")
            }
        }
    }
    finally {
        $archive.Dispose()
    }
    return $errors.ToArray()
}

function Get-LexiQuestParticipantDocumentNames {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('fieldTrial', 'publicProduction')]
        [string]$ReleaseProfile
    )

    $documents = @(
        'install-and-update.md',
        'privacy-and-consent-v1.md',
        'data-export-and-deletion.md',
        'known-limitations.md',
        'feedback-and-support.md'
    )
    if ($ReleaseProfile -eq 'fieldTrial') {
        $documents += 'research-protocol-v1.md'
    }
    return $documents
}

function Get-LexiQuestParticipantDocumentFields {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('fieldTrial', 'publicProduction')]
        [string]$ReleaseProfile
    )

    $fields = [ordered]@{
        installGuide = 'docs/install-and-update.md'
        privacyNotice = 'docs/privacy-and-consent-v1.md'
        dataRightsGuide = 'docs/data-export-and-deletion.md'
        knownLimitations = 'docs/known-limitations.md'
        feedbackGuide = 'docs/feedback-and-support.md'
    }
    if ($ReleaseProfile -eq 'fieldTrial') {
        $fields.researchProtocol = 'docs/research-protocol-v1.md'
    }
    return $fields
}

function Test-LexiQuestParticipantDocumentBindings {
    param(
        [Parameter(Mandatory)][object]$ParticipantPackage,
        [Parameter(Mandatory)][string]$ParticipantPackagePath,
        [Parameter(Mandatory)]
        [ValidateSet('fieldTrial', 'publicProduction')]
        [string]$ReleaseProfile
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $required = Get-LexiQuestParticipantDocumentFields `
        -ReleaseProfile $ReleaseProfile
    foreach ($field in $required.Keys) {
        $reference = $ParticipantPackage.$field
        if (-not (Test-LexiQuestEvidenceReferenceShape $reference)) {
            $errors.Add(
                "participantPackage.$field must be a path + SHA-256 reference."
            )
            continue
        }
        $expectedPath = [string]$required[$field]
        $actualPath = ([string]$reference.path).Replace([char]92, [char]47)
        if ($actualPath -cne $expectedPath) {
            $errors.Add(
                "participantPackage.$field must reference exactly $expectedPath."
            )
            continue
        }
        try {
            $resolved = Get-LexiQuestContainedPath `
                -Path $actualPath `
                -RootPath $ParticipantPackagePath
        }
        catch {
            $errors.Add(
                "participantPackage.${field}: $($_.Exception.Message)"
            )
            continue
        }
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            $errors.Add("participant document is missing: $actualPath")
            continue
        }
        $actualHash = (Get-FileHash -LiteralPath $resolved `
            -Algorithm SHA256).Hash
        if ((ConvertTo-NormalizedSha256 $reference.sha256) -ne $actualHash) {
            $errors.Add("participantPackage.$field SHA-256 mismatch.")
        }
    }
    return $errors.ToArray()
}

function Test-LexiQuestReleaseSource {
    param(
        [Parameter(Mandatory)][string]$ManifestSourceCommit,
        [Parameter(Mandatory)][string]$ManifestSourceTree,
        [Parameter(Mandatory)][string]$CurrentHead,
        [Parameter(Mandatory)][string]$CurrentTree,
        [AllowEmptyCollection()][string[]]$RelevantChanges = @()
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    if ($ManifestSourceCommit -notmatch '^[A-Fa-f0-9]{40}$') {
        $errors.Add('manifest source commit is invalid.')
    } elseif ($ManifestSourceCommit -ne $CurrentHead) {
        $errors.Add('manifest source commit does not match the checkout HEAD.')
    }
    if ($ManifestSourceTree -notmatch '^[A-Fa-f0-9]{40}$') {
        $errors.Add('manifest source tree is invalid.')
    } elseif ($ManifestSourceTree -ne $CurrentTree) {
        $errors.Add('manifest source tree does not match the checkout tree.')
    }
    if (@($RelevantChanges).Count -gt 0) {
        $errors.Add(
            'release-relevant source changes exist: ' +
            (@($RelevantChanges) -join ', ')
        )
    }
    return $errors.ToArray()
}

function Test-LexiQuestReleasePackage {
    param(
        [Parameter(Mandatory)][string]$PackagePath,
        [Parameter(Mandatory)][object]$Manifest
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    if ([int]$Manifest.schemaVersion -ne 3) {
        $errors.Add('release package schemaVersion must be 3.')
    }
    $profile = [string]$Manifest.releaseProfile
    if ($profile -notin @('fieldTrial', 'publicProduction')) {
        $errors.Add('releaseProfile must be fieldTrial or publicProduction.')
        return $errors.ToArray()
    }
    $apkPath = [string]$Manifest.artifact.apkPath
    $aabPath = [string]$Manifest.artifact.aabPath
    foreach ($artifactPath in @($apkPath, $aabPath)) {
        if (
            [System.IO.Path]::IsPathRooted($artifactPath) -or
            [System.IO.Path]::GetFileName($artifactPath) -ne $artifactPath
        ) {
            $errors.Add('artifact paths must be package-relative file names.')
        }
    }
    $expectedDocumentPaths = @(
        Get-LexiQuestParticipantDocumentNames -ReleaseProfile $profile |
            ForEach-Object { 'docs/' + $_ }
    )
    $manifestDocuments = @($Manifest.participantDocuments)
    $manifestDocumentPaths = @(
        $manifestDocuments | ForEach-Object { [string]$_.path }
    )
    foreach ($expectedPath in $expectedDocumentPaths) {
        if (@($manifestDocumentPaths | Where-Object {
            $_ -eq $expectedPath
        }).Count -ne 1) {
            $errors.Add(
                "participant document manifest must contain exactly: $expectedPath"
            )
        }
    }
    foreach ($document in $manifestDocuments) {
        $relative = [string]$document.path
        if ($relative -notin $expectedDocumentPaths) {
            $errors.Add("unexpected participant document manifest path: $relative")
            continue
        }
        $documentPath = Get-LexiQuestContainedPath `
            -Path $relative `
            -RootPath $PackagePath
        if (-not (Test-Path -LiteralPath $documentPath -PathType Leaf)) {
            $errors.Add("required packaged file is missing: $relative")
            continue
        }
        $expectedHash = ConvertTo-NormalizedSha256 $document.sha256
        $actualHash = (Get-FileHash -LiteralPath $documentPath `
            -Algorithm SHA256).Hash
        if ($expectedHash -notmatch '^[A-F0-9]{64}$' -or
            $actualHash -ne $expectedHash) {
            $errors.Add(
                "participant document SHA-256 mismatch: $relative"
            )
        }
    }
    $expectedFiles = @($apkPath, $aabPath, 'release-manifest.json')
    $expectedFiles += $expectedDocumentPaths
    $packageRoot = [System.IO.Path]::GetFullPath($PackagePath)
    $actualFiles = @(
        Get-ChildItem -LiteralPath $packageRoot -Recurse -File |
            ForEach-Object {
                $_.FullName.Substring($packageRoot.Length).TrimStart(
                    [char[]]@(
                        [System.IO.Path]::DirectorySeparatorChar,
                        [System.IO.Path]::AltDirectorySeparatorChar
                    )
                ).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
            }
    )
    foreach ($expected in $expectedFiles) {
        if ($expected -notin $actualFiles) {
            $errors.Add("required packaged file is missing: $expected")
        }
    }
    foreach ($actual in $actualFiles) {
        if ($actual -notin $expectedFiles) {
            $errors.Add("unexpected packaged file: $actual")
        }
    }
    return $errors.ToArray()
}

function Test-LexiQuestResolvedFieldReleaseEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Evidence,

        [Parameter(Mandatory)]
        [string]$ActualApkSha256,

        [Parameter(Mandatory)]
        [string]$ActualCertificateSha256,

        [Parameter(Mandatory)]
        [string]$ExpectedCertificateSha256,

        [Parameter(Mandatory)]
        [string]$ParticipantPackagePath
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $shaPattern = '^[A-F0-9]{64}$'
    $actualApk = ConvertTo-NormalizedSha256 $ActualApkSha256
    $actualCertificate = ConvertTo-NormalizedSha256 $ActualCertificateSha256
    $expectedCertificate =
        ConvertTo-NormalizedSha256 $ExpectedCertificateSha256

    if ([int]$Evidence.schemaVersion -ne 3) {
        $errors.Add('schemaVersion must be 3.')
    }
    $releaseProfile = [string]$Evidence.releaseProfile
    if ($releaseProfile -notin @('fieldTrial', 'publicProduction')) {
        $errors.Add('releaseProfile must be fieldTrial or publicProduction.')
    }
    if ([string]::IsNullOrWhiteSpace([string]$Evidence.releaseId)) {
        $errors.Add('releaseId is required.')
    }

    $artifactApk = ConvertTo-NormalizedSha256 $Evidence.artifact.apkSha256
    $artifactAab = ConvertTo-NormalizedSha256 $Evidence.artifact.aabSha256
    $artifactCertificate =
        ConvertTo-NormalizedSha256 $Evidence.artifact.signingCertificateSha256
    $artifactModel = ConvertTo-NormalizedSha256 $Evidence.artifact.modelSha256
    if ($artifactApk -notmatch $shaPattern -or $artifactApk -ne $actualApk) {
        $errors.Add('artifact APK SHA-256 does not match the verified APK.')
    }
    if ($artifactAab -notmatch $shaPattern) {
        $errors.Add('artifact aabSha256 must be a 64-character SHA-256.')
    }
    if (
        $artifactCertificate -notmatch $shaPattern -or
        $artifactCertificate -ne $actualCertificate
    ) {
        $errors.Add(
            'artifact signing certificate SHA-256 does not match apksigner.'
        )
    }
    if (
        $expectedCertificate -notmatch $shaPattern -or
        $actualCertificate -ne $expectedCertificate
    ) {
        $errors.Add(
            'artifact certificate does not match the owner-approved signing certificate.'
        )
    }
    if ($artifactModel -notmatch $shaPattern) {
        $errors.Add('artifact modelSha256 must be a 64-character SHA-256.')
    }
    if ([string]$Evidence.artifact.packageName -ne 'com.lexiquest.app') {
        $errors.Add('artifact packageName must be com.lexiquest.app.')
    }
    foreach ($field in @('versionName', 'versionCode', 'buildId')) {
        if ([string]::IsNullOrWhiteSpace([string]$Evidence.artifact.$field)) {
            $errors.Add("artifact $field is required.")
        }
    }

    foreach ($control in @(
        'appCheckConfigured',
        'appCheckValidTrafficObserved',
        'appCheckEnforced',
        'assetLinksVerified',
        'cloudKillSwitchVerified'
    )) {
        if ($Evidence.cloudControls.$control -ne $true) {
            $errors.Add("cloudControls.$control must be true.")
        }
    }
    if ([string]$Evidence.cloudControls.billingMode -eq 'noBillingAccount') {
        if (
            $Evidence.cloudControls.budgetAlertsConfigured -ne $false -or
            $Evidence.cloudControls.budgetAlertsNotApplicable -ne $true
        ) {
            $errors.Add(
                'No-billing mode requires alerts=false and notApplicable=true.'
            )
        }
    } elseif ([string]$Evidence.cloudControls.billingMode -eq 'budgeted') {
        if (
            $Evidence.cloudControls.budgetAlertsConfigured -ne $true -or
            $Evidence.cloudControls.budgetAlertsNotApplicable -ne $false
        ) {
            $errors.Add(
                'Budgeted mode requires configured 50/80/100 alerts.'
            )
        }
    } else {
        $errors.Add(
            'cloudControls.billingMode must be budgeted or noBillingAccount.'
        )
    }
    foreach ($reference in @(
        'appCheckEvidenceRef',
        'budgetAlertsEvidenceRef',
        'assetLinksEvidenceRef',
        'cloudKillSwitchEvidenceRef'
    )) {
        if (
            [string]::IsNullOrWhiteSpace(
                [string]$Evidence.cloudControls.$reference
            )
        ) {
            $errors.Add("cloudControls.$reference is required.")
        }
    }

    $package = $Evidence.participantPackage
    $playCertificate = ''
    foreach ($documentError in @(Test-LexiQuestParticipantDocumentBindings `
        -ParticipantPackage $package `
        -ParticipantPackagePath $ParticipantPackagePath `
        -ReleaseProfile $releaseProfile)) {
        $errors.Add([string]$documentError)
    }
    if ([int]$package.consentVersion -ne 1) {
        $errors.Add('participantPackage.consentVersion must be 1.')
    }
    $requiredChannels = @('feedbackChannelRef', 'supportChannelRef')
    if ($releaseProfile -eq 'fieldTrial') {
        $requiredChannels += 'researchProtocolRef'
    }
    foreach ($channel in $requiredChannels) {
        $reference = $package.$channel
        $value = [string]$reference
        $isHashedReference = Test-LexiQuestEvidenceReferenceShape $reference
        if (-not $isHashedReference -and (
            [string]::IsNullOrWhiteSpace($value) -or
            $value -match (
                '(?i)placeholder|owner_config|pending|todo|missing|' +
                'draft|unapproved|not.?configured|<.+>'
            ) -or
            ($releaseProfile -eq 'fieldTrial' -and
                $channel -in @('supportChannelRef', 'researchProtocolRef') -and
                $value -notmatch '^private:')
        )) {
            $errors.Add(
                "participantPackage.$channel must reference a real private channel."
            )
        }
    }

    if ($releaseProfile -eq 'fieldTrial') {
        foreach ($control in @(
            'ethicsApproved',
            'protocolApproved',
            'instrumentApproved',
            'trustedIssuerConfigured',
            'trustedTimeConfigured',
            'researchRolloutApproved'
        )) {
            if ($Evidence.researchControls.$control -ne $true) {
                $errors.Add("researchControls.$control must be true.")
            }
        }
        foreach ($reference in @(
            'ethicsEvidenceRef',
            'protocolEvidenceRef',
            'instrumentEvidenceRef',
            'trustedIssuerEvidenceRef',
            'trustedTimeEvidenceRef',
            'rolloutEvidenceRef'
        )) {
            $referenceValue = $Evidence.researchControls.$reference
            $value = [string]$referenceValue
            if (-not (Test-LexiQuestEvidenceReferenceShape $referenceValue) -and
                ([string]::IsNullOrWhiteSpace($value) -or
                    $value -notmatch '^private:')) {
                $errors.Add(
                    "researchControls.$reference must reference private evidence."
                )
            }
        }
    } elseif ($releaseProfile -eq 'publicProduction') {
        foreach ($control in @(
            'playAabAccepted',
            'privacyPolicyPublished',
            'accountDeletionVerified',
            'dataSafetyApproved',
            'rollbackDrillVerified'
        )) {
            if ($Evidence.releaseControls.$control -ne $true) {
                $errors.Add("releaseControls.$control must be true.")
            }
        }
        $playCertificate = ConvertTo-NormalizedSha256 `
            $Evidence.releaseControls.playAppSigningCertificateSha256
        if ($playCertificate -notmatch $shaPattern) {
            $errors.Add(
                'releaseControls.playAppSigningCertificateSha256 is invalid.'
            )
        }
        $playAabProperty =
            $Evidence.releaseControls.PSObject.Properties['playAabSha256']
        $playAabValue = if ($null -eq $playAabProperty) {
            ''
        } else {
            $playAabProperty.Value
        }
        if ((ConvertTo-NormalizedSha256 $playAabValue) -ne $artifactAab) {
            $errors.Add(
                'releaseControls must reference the exact release AAB SHA-256.'
            )
        }
        foreach ($field in @('packageName', 'versionName', 'versionCode')) {
            $playField = 'play' + $field.Substring(0, 1).ToUpperInvariant() +
                $field.Substring(1)
            $playProperty =
                $Evidence.releaseControls.PSObject.Properties[$playField]
            $playValue = if ($null -eq $playProperty) {
                ''
            } else {
                $playProperty.Value
            }
            if ([string]$playValue -ne
                [string]$Evidence.artifact.$field) {
                $errors.Add(
                    "releaseControls.$playField must match the exact release AAB."
                )
            }
        }
        foreach ($reference in @(
            'playAcceptanceEvidenceRef',
            'privacyPolicyEvidenceRef',
            'accountDeletionEvidenceRef',
            'dataSafetyEvidenceRef',
            'rollbackEvidenceRef'
        )) {
            $referenceProperty =
                $Evidence.releaseControls.PSObject.Properties[$reference]
            $value = if ($null -eq $referenceProperty) {
                ''
            } else {
                [string]$referenceProperty.Value
            }
            if ([string]::IsNullOrWhiteSpace($value)) {
                $errors.Add("releaseControls.$reference is required.")
            }
        }
        if (
            [string]$Evidence.releaseControls.privacyPolicyRef -notmatch
            '^https://'
        ) {
            $errors.Add('releaseControls.privacyPolicyRef must use HTTPS.')
        }
    }

    $devices = @($Evidence.devices)
    $tiers = @($devices | ForEach-Object { [string]$_.tier })
    $requiredTiers = @('low', 'mid', 'high')
    foreach ($tier in $requiredTiers) {
        if (@($tiers | Where-Object { $_ -eq $tier }).Count -lt 1) {
            $errors.Add(
                "At least one $tier-tier physical Android device record is required."
            )
        }
    }
    foreach ($tier in $tiers) {
        if ($tier -notin $requiredTiers) {
            $errors.Add('Every device tier must be low, mid, or high.')
        }
    }
    $formFactors = @($devices | ForEach-Object { [string]$_.formFactor })
    $requiredFormFactors = @('phone', 'foldable', 'tablet')
    foreach ($formFactor in $requiredFormFactors) {
        if (@($formFactors | Where-Object { $_ -eq $formFactor }).Count -lt 1) {
            $errors.Add(
                "At least one physical $formFactor device record is required."
            )
        }
    }
    foreach ($formFactor in $formFactors) {
        if ($formFactor -notin $requiredFormFactors) {
            $errors.Add(
                'Every device formFactor must be phone, foldable, or tablet.'
            )
        }
    }
    $deviceIds = @($devices | ForEach-Object {
        ConvertTo-NormalizedSha256 $_.pseudonymousDeviceId
    })
    if (@($deviceIds | Sort-Object -Unique).Count -ne $devices.Count) {
        $errors.Add('Physical device records must have distinct pseudonymous IDs.')
    }

    $requiredJourneys = Get-LexiQuestRequiredFieldJourneys
    foreach ($device in $devices) {
        $label = if ([string]::IsNullOrWhiteSpace([string]$device.tier)) {
            'unknown-tier'
        } else {
            [string]$device.tier
        }
        if (
            (ConvertTo-NormalizedSha256 $device.pseudonymousDeviceId) -notmatch
            $shaPattern
        ) {
            $errors.Add("$label device pseudonymousDeviceId is invalid.")
        }
        if ([string]::IsNullOrWhiteSpace([string]$device.evidenceId)) {
            $errors.Add("$label device evidenceId is required.")
        }
        if ([string]::IsNullOrWhiteSpace([string]$device.recordedAtUtc)) {
            $errors.Add("$label device recordedAtUtc is required.")
        }
        if ($device.device.physical -ne $true) {
            $errors.Add("$label evidence must be from a physical device.")
        }
        if ($device.device.emulatorDetected -ne $false) {
            $errors.Add(
                "$label evidence contains emulator indicators and is not physical."
            )
        }
        foreach ($field in @(
            'model',
            'androidVersion',
            'sdk',
            'ramMb',
            'chipset',
            'gpu',
            'storageFreeMb',
            'networkProfile',
            'smallestWidthDp',
            'featureSetSha256',
            'windowStateSha256'
        )) {
            if ([string]::IsNullOrWhiteSpace([string]$device.device.$field)) {
                $errors.Add("$label device.device.$field is required.")
            }
        }
        foreach ($hashField in @('featureSetSha256', 'windowStateSha256')) {
            if ((ConvertTo-NormalizedSha256 `
                $device.device.$hashField) -notmatch $shaPattern) {
                $errors.Add("$label device.device.$hashField is invalid.")
            }
        }
        foreach ($booleanField in @(
            'hasHingeSensor',
            'foldFeatureObserved',
            'unsupportedFormFactorFeature'
        )) {
            $booleanProperty =
                $device.device.PSObject.Properties[$booleanField]
            if ($null -eq $booleanProperty -or
                $booleanProperty.Value -isnot [bool]) {
                $errors.Add(
                    "$label device.device.$booleanField must be measured boolean data."
                )
            }
        }
        try {
            $derivedTier = Get-LexiQuestDerivedDeviceTier `
                -RamMb ([double]$device.device.ramMb) `
                -Sdk ([int]$device.device.sdk)
            if ([string]$device.tier -ne $derivedTier) {
                $errors.Add(
                    "$label tier does not match measured RAM/API policy."
                )
            }
        }
        catch {
            $errors.Add("$label tier could not be derived: $($_.Exception.Message)")
        }
        try {
            $derivedFormFactor = Get-LexiQuestDerivedFormFactor `
                -SmallestWidthDp ([double]$device.device.smallestWidthDp) `
                -HasHingeSensor ([bool]$device.device.hasHingeSensor) `
                -FoldFeatureObserved ([bool]$device.device.foldFeatureObserved) `
                -UnsupportedFormFactorFeature (
                    [bool]$device.device.unsupportedFormFactorFeature
                )
            if ([string]$device.formFactor -ne $derivedFormFactor) {
                $errors.Add(
                    "$label formFactor does not match measured window/fold facts."
                )
            }
        }
        catch {
            $errors.Add(
                "$label formFactor could not be derived: $($_.Exception.Message)"
            )
        }
        $deviceApk =
            ConvertTo-NormalizedSha256 $device.release.apkSha256
        $deviceCertificate =
            ConvertTo-NormalizedSha256 `
                $device.release.signingCertificateSha256
        $deviceModel =
            ConvertTo-NormalizedSha256 $device.release.modelSha256
        if ($deviceApk -ne $artifactApk) {
            $errors.Add("$label device was not tested with the release APK.")
        }
        if ($deviceCertificate -ne $artifactCertificate) {
            $errors.Add("$label device certificate does not match the release.")
        }
        if ($deviceModel -ne $artifactModel) {
            $errors.Add("$label device model checksum does not match the release.")
        }
        foreach ($field in @('versionName', 'versionCode', 'buildId')) {
            if ([string]$device.release.$field -ne
                [string]$Evidence.artifact.$field) {
                $errors.Add("$label device release.$field does not match.")
            }
        }

        $installation = $device.installation
        if ((ConvertTo-NormalizedSha256 `
            $installation.localApkSha256) -ne $artifactApk) {
            $errors.Add(
                "$label measured local APK does not match the release APK."
            )
        }
        if ((ConvertTo-NormalizedSha256 `
            $installation.localApkSigningCertificateSha256) -ne
            $artifactCertificate) {
            $errors.Add(
                "$label measured local APK signer does not match the release."
            )
        }
        if ((ConvertTo-NormalizedSha256 `
            $installation.installedBaseApkSha256) -notmatch $shaPattern) {
            $errors.Add("$label installed base APK SHA-256 is invalid.")
        }
        if ([string]$installation.installedPackageName -ne
            [string]$Evidence.artifact.packageName) {
            $errors.Add("$label installed package name does not match.")
        }
        foreach ($field in @('versionName', 'versionCode')) {
            $installedField = 'installed' +
                $field.Substring(0, 1).ToUpperInvariant() +
                $field.Substring(1)
            if ([string]$installation.$installedField -ne
                [string]$Evidence.artifact.$field) {
                $errors.Add(
                    "$label $installedField does not match the release."
                )
            }
        }
        $installedCertificate = ConvertTo-NormalizedSha256 `
            $installation.installedSigningCertificateSha256
        if ($releaseProfile -eq 'publicProduction') {
            if (
                [string]$installation.source -ne 'play' -or
                [string]$installation.installerPackageName -ne
                    'com.android.vending'
            ) {
                $errors.Add(
                    "$label public evidence must come from the measured Play installer."
                )
            }
            if ($installedCertificate -ne $playCertificate) {
                $errors.Add(
                    "$label installed signer does not match the Play certificate."
                )
            }
        } else {
            if ([string]$installation.source -ne 'directAdb') {
                $errors.Add(
                    "$label field-trial evidence must use the verified direct APK."
                )
            }
            if ($installedCertificate -ne $artifactCertificate) {
                $errors.Add(
                    "$label installed signer does not match the release APK."
                )
            }
        }

        foreach ($journeyName in $requiredJourneys) {
            $journey = $device.journeys.$journeyName
            if ([string]$journey.status -ne 'pass') {
                $errors.Add("$label journey $journeyName must pass.")
            }
            if ([string]::IsNullOrWhiteSpace([string]$journey.evidenceRef)) {
                $errors.Add("$label journey $journeyName needs an evidenceRef.")
            }
        }

        foreach ($acceptanceName in @(
            'portrait',
            'landscape',
            'textScale100',
            'textScale200',
            'manualTalkBack',
            'humanUat'
        )) {
            $acceptance = $device.acceptance.$acceptanceName
            if (
                [string]$acceptance.status -ne 'pass' -or
                [string]::IsNullOrWhiteSpace(
                    [string]$acceptance.evidenceRef
                )
            ) {
                $errors.Add(
                    "$label $acceptanceName acceptance must pass with evidence."
                )
            }
        }
        if ([string]$device.formFactor -eq 'foldable') {
            foreach ($posture in @('cover', 'book', 'tabletop')) {
                $postureEvidence = $device.acceptance.foldPostures.$posture
                if (
                    [string]$postureEvidence.status -ne 'pass' -or
                    [string]::IsNullOrWhiteSpace(
                        [string]$postureEvidence.evidenceRef
                    )
                ) {
                    $errors.Add(
                        "$label fold posture $posture must pass with evidence."
                    )
                }
            }
        }

        $cpu = $device.benchmarks.cpuXnnpack
        if (
            [string]$cpu.status -ne 'pass' -or
            [string]$cpu.delegate -ne 'xnnpack' -or
            [int]$cpu.iterations -lt 10 -or
            [double]$cpu.medianLatencyMs -le 0 -or
            [string]::IsNullOrWhiteSpace([string]$cpu.evidenceRef)
        ) {
            $errors.Add(
                "$label CPU/XNNPACK benchmark must pass with >=10 iterations."
            )
        }
        $gpu = $device.benchmarks.gpuDelegate
        if ([string]$gpu.status -eq 'pass') {
            if (
                $gpu.allowlisted -ne $true -or
                [int]$gpu.iterations -lt 10 -or
                [string]::IsNullOrWhiteSpace([string]$gpu.evidenceRef)
            ) {
                $errors.Add(
                    "$label GPU pass requires allowlisting and >=10 iterations."
                )
            }
        } elseif ([string]$gpu.status -eq 'notApplicable') {
            if (
                $gpu.allowlisted -ne $false -or
                [string]::IsNullOrWhiteSpace([string]$gpu.reason) -or
                [string]::IsNullOrWhiteSpace([string]$gpu.evidenceRef)
            ) {
                $errors.Add(
                    "$label GPU N/A requires allowlisted=false and a reason."
                )
            }
        } else {
            $errors.Add("$label GPU status must be pass or notApplicable.")
        }

        $endurance = $device.endurance
        if (
            [string]$endurance.status -ne 'pass' -or
            [double]$endurance.durationMinutes -lt 30 -or
            [int]$endurance.crashCount -ne 0 -or
            [int]$endurance.anrCount -ne 0 -or
            [string]::IsNullOrWhiteSpace([string]$endurance.evidenceRef)
        ) {
            $errors.Add(
                "$label endurance must pass >=30 minutes with zero crash/ANR."
            )
        }
        foreach ($metric in @(
            'peakRssMb',
            'batteryStartPercent',
            'batteryEndPercent',
            'temperatureStartC',
            'temperatureEndC'
        )) {
            if ($null -eq $endurance.$metric) {
                $errors.Add("$label endurance.$metric is required.")
            }
        }
    }

    $approval = $Evidence.ownerApproval
    if ($approval.approved -ne $true) {
        $errors.Add('ownerApproval.approved must be true.')
    }
    if (
        (ConvertTo-NormalizedSha256 $approval.apkSha256) -ne
        $artifactApk
    ) {
        $errors.Add('owner approval must reference the release APK SHA-256.')
    }
    if (
        (ConvertTo-NormalizedSha256 $approval.aabSha256) -ne
        $artifactAab
    ) {
        $errors.Add('owner approval must reference the release AAB SHA-256.')
    }
    foreach ($field in @('approvedAtUtc', 'approverRole', 'evidenceRef')) {
        if ([string]::IsNullOrWhiteSpace([string]$approval.$field)) {
            $errors.Add("ownerApproval.$field is required.")
        }
    }
    return $errors.ToArray()
}

function Test-LexiQuestReferencedFieldReleaseEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Evidence,
        [Parameter(Mandatory)][string]$ActualApkSha256,
        [Parameter(Mandatory)][string]$ActualCertificateSha256,
        [Parameter(Mandatory)][string]$ExpectedCertificateSha256,
        [Parameter(Mandatory)][string]$ParticipantPackagePath,
        [Parameter(Mandatory)][string]$EvidenceRootPath
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    if ([int]$Evidence.schemaVersion -ne 3) {
        return @('schemaVersion must be 3.')
    }
    try {
        $controls = Read-LexiQuestEvidenceRecord `
            -Reference $Evidence.records.controls `
            -EvidenceRootPath $EvidenceRootPath
        $approval = Read-LexiQuestEvidenceRecord `
            -Reference $Evidence.records.ownerApproval `
            -EvidenceRootPath $EvidenceRootPath
        $devices = @(
            $Evidence.devices |
                ForEach-Object {
                    Read-LexiQuestEvidenceRecord `
                        -Reference $_ `
                        -EvidenceRootPath $EvidenceRootPath
                }
        )
    }
    catch {
        return @($_.Exception.Message)
    }
    if ([string]$controls.recordType -ne 'lexiquestReleaseControls') {
        $errors.Add('controls recordType is invalid.')
    }
    if ([string]$approval.recordType -ne 'lexiquestOwnerApproval') {
        $errors.Add('owner approval recordType is invalid.')
    }
    foreach ($device in $devices) {
        if ([string]$device.recordType -ne
            'lexiquestPhysicalDeviceEvidence') {
            $errors.Add('device evidence recordType is invalid.')
        }
    }
    if ([string]$controls.releaseProfile -ne [string]$Evidence.releaseProfile) {
        $errors.Add('controls releaseProfile does not match release evidence.')
    }
    foreach ($field in @(
        'apkSha256',
        'aabSha256',
        'signingCertificateSha256',
        'packageName',
        'versionName',
        'versionCode',
        'buildId',
        'modelSha256'
    )) {
        if ([string]$controls.artifact.$field -ne
            [string]$Evidence.artifact.$field) {
            $errors.Add("controls artifact.$field does not match release evidence.")
        }
    }
    $referenceErrors = @(
        Test-LexiQuestContainedEvidenceReferences `
            -Value $controls `
            -EvidenceRootPath $EvidenceRootPath `
            -Context 'controls'
        Test-LexiQuestContainedEvidenceReferences `
            -Value $approval `
            -EvidenceRootPath $EvidenceRootPath `
            -Context 'ownerApproval'
        foreach ($device in $devices) {
            Test-LexiQuestContainedEvidenceReferences `
                -Value $device `
                -EvidenceRootPath $EvidenceRootPath `
                -Context "device:$($device.evidenceId)"
        }
    )
    foreach ($referenceError in $referenceErrors) {
        $errors.Add([string]$referenceError)
    }
    if ($errors.Count -gt 0) {
        return $errors.ToArray()
    }
    $resolved = [pscustomobject]@{
        schemaVersion = 3
        releaseProfile = $Evidence.releaseProfile
        releaseId = $Evidence.releaseId
        artifact = $Evidence.artifact
        cloudControls = $controls.cloudControls
        participantPackage = $controls.participantPackage
        releaseControls = $controls.releaseControls
        researchControls = $controls.researchControls
        devices = $devices
        ownerApproval = $approval
    }
    return Test-LexiQuestResolvedFieldReleaseEvidence `
        -Evidence $resolved `
        -ActualApkSha256 $ActualApkSha256 `
        -ActualCertificateSha256 $ActualCertificateSha256 `
        -ExpectedCertificateSha256 $ExpectedCertificateSha256 `
        -ParticipantPackagePath $ParticipantPackagePath
}
