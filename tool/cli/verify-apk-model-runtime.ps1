#Requires -Version 5.1
param(
    [string]$ApkPath = 'build/app/outputs/flutter-apk/app-debug.apk',
    [string]$ArchivePath = '',
    [string]$LiteRtNextAarPath =
        'build/flutter_litert/tmp/downloadLitertJni/litert-2.1.5.aar',
    [ValidateSet('Auto', 'Debug', 'Release')]
    [string]$BuildMode = 'Auto'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$selectedArchivePath = if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $ApkPath
} else {
    $ArchivePath
}
$resolvedApk = if ([System.IO.Path]::IsPathRooted($selectedArchivePath)) {
    [System.IO.Path]::GetFullPath($selectedArchivePath)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $selectedArchivePath))
}
$archiveKind = if (
    [System.IO.Path]::GetExtension($resolvedApk) -eq '.aab'
) { 'AAB' } else { 'APK' }
$entryPrefix = if ($archiveKind -eq 'AAB') { 'base/' } else { '' }
$resolvedAar = if ([System.IO.Path]::IsPathRooted($LiteRtNextAarPath)) {
    [System.IO.Path]::GetFullPath($LiteRtNextAarPath)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $LiteRtNextAarPath))
}
$expectedAarSha256 =
    'A162D1DDBDAD87C002B7EC7EB31A703F2761335E693F292F94091B3569D8AA37'
$resolvedBuildMode = if ($BuildMode -ne 'Auto') {
    $BuildMode
} elseif ([System.IO.Path]::GetFileName($resolvedApk) -match '(?i)debug') {
    'Debug'
} else {
    'Release'
}

if (-not (Test-Path -LiteralPath $resolvedApk -PathType Leaf)) {
    throw "APK is missing: $resolvedApk"
}
if (-not (Test-Path -LiteralPath $resolvedAar -PathType Leaf)) {
    throw "LiteRT Next AAR is missing: $resolvedAar"
}

$actualAarSha256 = (Get-FileHash -LiteralPath $resolvedAar -Algorithm SHA256).Hash
if ($actualAarSha256 -ne $expectedAarSha256) {
    throw (
        'LiteRT Next AAR checksum mismatch. Expected {0}, got {1}.' -f
        $expectedAarSha256,
        $actualAarSha256
    )
}

$expectedLibraries = [ordered]@{
    'lib/arm64-v8a/libLiteRt.so' =
        '366E3E040B00692158F9F8F9105870672C93348A3D8E9024120B40045A074B0B'
    'lib/arm64-v8a/libtensorflowlite_gpu_jni.so' =
        '03D7EAE3457E3805D7173875E777CB7F79CCF9F837E394EBDB555415A3503C58'
    'lib/arm64-v8a/libtensorflowlite_jni.so' =
        '3BA28CE98B0E6AB7E417B9CC8D9AD0E7E1616EF86DD83CF1EA16EF109A029FA4'
    'lib/arm64-v8a/libtflite_custom_ops.so' =
        'CE5E655AB1E9CA1AF96EE41FE038B6EDA8977CBB704459183908C68FDC916828'
    'lib/armeabi-v7a/libLiteRt.so' =
        '836EE7A2321C9453F02658B6774FC4C5951716432B450BA6BC4E9A94FE524E6C'
    'lib/armeabi-v7a/libtensorflowlite_gpu_jni.so' =
        '222374E093DD0BD492F044F04C53CFB383754B4C5B96EF6B2BD266BE9425461E'
    'lib/armeabi-v7a/libtensorflowlite_jni.so' =
        '5C3280CBA72ED9563CFA47C39B79670BC8F4C2ED26FF545874B33DBA805D8E4B'
    'lib/armeabi-v7a/libtflite_custom_ops.so' =
        '15247385DCC008F33DCAE730D71A23A7D1E2D185605D2A652E4B4CCE0D41CB19'
    'lib/x86_64/libLiteRt.so' =
        '6D5B2F35D536A3B2D38B26D26328CC9C259133EF2AA0413EC554CD7EF84F6604'
    'lib/x86_64/libtensorflowlite_gpu_jni.so' =
        '4960E910A8CEFA4DEDA380D5B4B270BFE2ABBCE0C8D6CE0F5A0E8CCCB32C1186'
    'lib/x86_64/libtensorflowlite_jni.so' =
        'F0B4F69DD1EC93E289A2A47CBF8623FF9403C1C71E72616B12FC25BA2D284A88'
    'lib/x86_64/libtflite_custom_ops.so' =
        'C26344121F8AAFEBA56FBF71329CE4C82A22DD87BA808424AA7C725B2AFB332B'
}

if ($resolvedBuildMode -eq 'Release') {
    # flutter_litert compiles this project-owned JNI shim as RelWithDebInfo for
    # release while the vendor LiteRT binaries remain byte-identical.
    $expectedLibraries['lib/arm64-v8a/libtflite_custom_ops.so'] =
        '82CC19156495E9C3845AE00B3A4DF4ED196124CA6586884C80F702BFC4BC35B2'
    $expectedLibraries['lib/armeabi-v7a/libtflite_custom_ops.so'] =
        '5236E8BAEFEB9705DB086DECA2EABD6F7901CCD30525A45B4D0A755F73E189DC'
    $expectedLibraries['lib/x86_64/libtflite_custom_ops.so'] =
        '50416556054A668ED145EA224275BEE107DC52291C61E636249C2AFAAA1C6090'
}
if ($archiveKind -eq 'AAB') {
    $aabLibraries = [ordered]@{}
    foreach ($entryName in $expectedLibraries.Keys) {
        $aabLibraries[$entryPrefix + $entryName] = $expectedLibraries[$entryName]
    }
    $expectedLibraries = $aabLibraries
}

function Find-LlvmObjCopy {
    $command = Get-Command llvm-objcopy -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $sdkRoots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)
    if ($env:OS -eq 'Windows_NT') {
        $sdkRoots += Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    }
    foreach ($sdkRoot in @($sdkRoots | Where-Object { $_ } | Select-Object -Unique)) {
        $ndkRoot = Join-Path $sdkRoot 'ndk'
        if (-not (Test-Path -LiteralPath $ndkRoot -PathType Container)) {
            continue
        }
        foreach ($ndk in @(Get-ChildItem -LiteralPath $ndkRoot -Directory |
                Sort-Object Name -Descending)) {
            $prebuiltRoot = Join-Path $ndk.FullName 'toolchains\llvm\prebuilt'
            if (-not (Test-Path -LiteralPath $prebuiltRoot -PathType Container)) {
                continue
            }
            foreach ($prebuilt in @(Get-ChildItem -LiteralPath $prebuiltRoot -Directory)) {
                $executable = if ($env:OS -eq 'Windows_NT') {
                    'llvm-objcopy.exe'
                } else {
                    'llvm-objcopy'
                }
                $candidate = Join-Path $prebuilt.FullName "bin\$executable"
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    return $candidate
                }
            }
        }
    }
    throw 'llvm-objcopy is required to normalize the JNI shim build ID.'
}

function Get-PackagedLibrarySha256 {
    param(
        [Parameter(Mandatory)][object]$Entry,
        [Parameter(Mandatory)][string]$EntryName,
        [AllowNull()][string]$LlvmObjCopy,
        [AllowNull()][string]$TemporaryDirectory
    )

    if (-not $EntryName.EndsWith('/libtflite_custom_ops.so')) {
        $stream = $Entry.Open()
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            return ([BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-', '')
        }
        finally {
            $sha256.Dispose()
            $stream.Dispose()
        }
    }

    $temporaryFile = Join-Path $TemporaryDirectory (
        ($EntryName -replace '[^A-Za-z0-9_.-]', '_')
    )
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile(
        $Entry,
        $temporaryFile,
        $true
    )
    & $LlvmObjCopy --remove-section=.note.gnu.build-id $temporaryFile
    if ([int]$LASTEXITCODE -ne 0) {
        throw "Unable to normalize native build ID for $EntryName."
    }
    return (Get-FileHash -LiteralPath $temporaryFile -Algorithm SHA256).Hash
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$llvmObjCopy = Find-LlvmObjCopy
$temporaryDirectory = Join-Path (
    [System.IO.Path]::GetTempPath()
) ('lexiquest-apk-runtime-' + [Guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($temporaryDirectory) | Out-Null
$archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedApk)
try {
    foreach ($entryName in $expectedLibraries.Keys) {
        $entry = $archive.GetEntry($entryName)
        if ($null -eq $entry) {
            throw "Required model runtime library is missing: $entryName"
        }
        $actual = Get-PackagedLibrarySha256 `
            -Entry $entry `
            -EntryName $entryName `
            -LlvmObjCopy $llvmObjCopy `
            -TemporaryDirectory $temporaryDirectory
        if ($actual -ne $expectedLibraries[$entryName]) {
            throw (
                'Packaged native checksum mismatch for {0}. Expected {1}, got {2}.' -f
                $entryName,
                $expectedLibraries[$entryName],
                $actual
            )
        }
    }

    $runtimeLibraries = @(
        $archive.Entries |
            Where-Object {
                $_.FullName -match (
                    '^(?:base/)?lib/[^/]+/(libLiteRt.*|libtensorflowlite.*|' +
                    'libtflite.*)\.so$'
                )
            }
    )
    $unexpected = @(
        $runtimeLibraries |
            Where-Object { -not $expectedLibraries.Contains($_.FullName) }
    )
    if ($unexpected.Count -ne 0) {
        $names = ($unexpected | ForEach-Object { $_.FullName }) -join ', '
        throw "Unexpected model runtime libraries or ABIs: $names"
    }
    if (
        $runtimeLibraries.FullName -match 'libLiteRt.*Accelerator\.so$'
    ) {
        throw 'GPU accelerator libraries must not be packaged before hardware certification.'
    }
}
finally {
    $archive.Dispose()
    Get-ChildItem -LiteralPath $temporaryDirectory -File |
        ForEach-Object { [System.IO.File]::Delete($_.FullName) }
    [System.IO.Directory]::Delete($temporaryDirectory, $false)
}

Write-Host (
    'APK/AAB model runtime integrity ({0}, {1}): PASS' -f
        $archiveKind,
        $resolvedBuildMode
) -ForegroundColor Green
exit 0
