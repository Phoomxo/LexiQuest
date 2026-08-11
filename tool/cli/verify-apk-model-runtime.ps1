#Requires -Version 5.1
param(
    [string]$ApkPath = 'build/app/outputs/flutter-apk/app-debug.apk',
    [string]$LiteRtNextAarPath =
        'build/flutter_litert/tmp/downloadLitertJni/litert-2.1.5.aar',
    [ValidateSet('Auto', 'Debug', 'Release')]
    [string]$BuildMode = 'Auto'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$canonicalHashPath = Join-Path `
    (Join-Path (Join-Path $repoRoot 'tool') 'cli') `
    'lib/elf-canonical-hash.ps1'
if (-not (Test-Path -LiteralPath $canonicalHashPath -PathType Leaf)) {
    throw "ELF canonical hash policy is missing: $canonicalHashPath"
}
. $canonicalHashPath

$resolvedApk = if ([System.IO.Path]::IsPathRooted($ApkPath)) {
    [System.IO.Path]::GetFullPath($ApkPath)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $ApkPath))
}
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

$expectedRawLibraries = [ordered]@{
    'lib/arm64-v8a/libLiteRt.so' =
        '366E3E040B00692158F9F8F9105870672C93348A3D8E9024120B40045A074B0B'
    'lib/arm64-v8a/libtensorflowlite_gpu_jni.so' =
        '03D7EAE3457E3805D7173875E777CB7F79CCF9F837E394EBDB555415A3503C58'
    'lib/arm64-v8a/libtensorflowlite_jni.so' =
        '3BA28CE98B0E6AB7E417B9CC8D9AD0E7E1616EF86DD83CF1EA16EF109A029FA4'
    'lib/armeabi-v7a/libLiteRt.so' =
        '836EE7A2321C9453F02658B6774FC4C5951716432B450BA6BC4E9A94FE524E6C'
    'lib/armeabi-v7a/libtensorflowlite_gpu_jni.so' =
        '222374E093DD0BD492F044F04C53CFB383754B4C5B96EF6B2BD266BE9425461E'
    'lib/armeabi-v7a/libtensorflowlite_jni.so' =
        '5C3280CBA72ED9563CFA47C39B79670BC8F4C2ED26FF545874B33DBA805D8E4B'
    'lib/x86_64/libLiteRt.so' =
        '6D5B2F35D536A3B2D38B26D26328CC9C259133EF2AA0413EC554CD7EF84F6604'
    'lib/x86_64/libtensorflowlite_gpu_jni.so' =
        '4960E910A8CEFA4DEDA380D5B4B270BFE2ABBCE0C8D6CE0F5A0E8CCCB32C1186'
    'lib/x86_64/libtensorflowlite_jni.so' =
        'F0B4F69DD1EC93E289A2A47CBF8623FF9403C1C71E72616B12FC25BA2D284A88'
}

$expectedCanonicalCustomOps = @{
    # Debug pins were derived from the stripped entries in the Task 6 debug APK.
    # Release pins were derived from the exact output of
    # :flutter_litert:stripReleaseDebugSymbols using pinned NDK 28.2.13676358.
    # Only the 20-byte GNU build-id descriptor is zeroed. Source, ELF structure,
    # ABI machine, mode-specific code, and every other byte remain integrity
    # sensitive. Immutable Maven/vendor libraries above remain raw-pinned.
    Debug = [ordered]@{
        'lib/arm64-v8a/libtflite_custom_ops.so' =
            '4D57B6CCCB974930E6FAE223020862128F9B411AC2D33455B2C1D566D7186BB1'
        'lib/armeabi-v7a/libtflite_custom_ops.so' =
            'F414A52EE4200CAF06A411CC089AEE19A829F6A970FA7A6253357D5FB977D427'
        'lib/x86_64/libtflite_custom_ops.so' =
            '39C312A9144A9DC9248FACB7D040B3D532921203D3C60E0A02B2EBFD2025B04F'
    }
    Release = [ordered]@{
        'lib/arm64-v8a/libtflite_custom_ops.so' =
            'A6E4E4A4B160525E70788CBFD78F4F3D85C3CA93B24A0E9FC61D8F6C293A12E8'
        'lib/armeabi-v7a/libtflite_custom_ops.so' =
            '6ADAD6189B89023A511A97C95B1BF1532D2509CE0AA4E65207FB13E3928CDAD3'
        'lib/x86_64/libtflite_custom_ops.so' =
            '5A1F4249AB30AF158CA9966D6518EB13EEB38AB9DEEFDEDEF7F203E4031AD6ED'
    }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedApk)
try {
    $runtimeLibraryBytes = Read-LexiQuestNativeLibraryBytes -Archive $archive

    Assert-LexiQuestNativeLibrarySetIntegrity `
        -LibraryBytesByEntry $runtimeLibraryBytes `
        -BuildMode $resolvedBuildMode `
        -ExpectedRawSha256ByEntry $expectedRawLibraries `
        -ExpectedCanonicalSha256ByMode $expectedCanonicalCustomOps

    if ($runtimeLibraryBytes.Keys -match 'libLiteRt.*Accelerator\.so$') {
        throw 'GPU accelerator libraries must not be packaged before hardware certification.'
    }
}
finally {
    $archive.Dispose()
}

Write-Host (
    'APK model runtime integrity ({0}): PASS' -f $resolvedBuildMode
) -ForegroundColor Green
exit 0
