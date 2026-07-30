#Requires -Version 5.1
param(
    [string]$ApkPath = 'build/app/outputs/flutter-apk/app-debug.apk',
    [string]$LiteRtNextAarPath =
        'build/flutter_litert/tmp/downloadLitertJni/litert-2.1.5.aar'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$resolvedApk = Join-Path $repoRoot $ApkPath
$resolvedAar = Join-Path $repoRoot $LiteRtNextAarPath
$expectedAarSha256 =
    'A162D1DDBDAD87C002B7EC7EB31A703F2761335E693F292F94091B3569D8AA37'

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
        'DCAF40FC640C99413DCD8652FB6C3B6F65CDAC50AF001922CB162C155B4E407F'
    'lib/armeabi-v7a/libLiteRt.so' =
        '836EE7A2321C9453F02658B6774FC4C5951716432B450BA6BC4E9A94FE524E6C'
    'lib/armeabi-v7a/libtensorflowlite_gpu_jni.so' =
        '222374E093DD0BD492F044F04C53CFB383754B4C5B96EF6B2BD266BE9425461E'
    'lib/armeabi-v7a/libtensorflowlite_jni.so' =
        '5C3280CBA72ED9563CFA47C39B79670BC8F4C2ED26FF545874B33DBA805D8E4B'
    'lib/armeabi-v7a/libtflite_custom_ops.so' =
        '43135F9C6E328D6F9597AF213AAF9333ABCCFE2CEECE228817E5854624BF77C6'
    'lib/x86_64/libLiteRt.so' =
        '6D5B2F35D536A3B2D38B26D26328CC9C259133EF2AA0413EC554CD7EF84F6604'
    'lib/x86_64/libtensorflowlite_gpu_jni.so' =
        '4960E910A8CEFA4DEDA380D5B4B270BFE2ABBCE0C8D6CE0F5A0E8CCCB32C1186'
    'lib/x86_64/libtensorflowlite_jni.so' =
        'F0B4F69DD1EC93E289A2A47CBF8623FF9403C1C71E72616B12FC25BA2D284A88'
    'lib/x86_64/libtflite_custom_ops.so' =
        '52143132085C15890859DB7DE74316AF109EC5A95D3F2C131131F33986A8B42F'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedApk)
try {
    foreach ($entryName in $expectedLibraries.Keys) {
        $entry = $archive.GetEntry($entryName)
        if ($null -eq $entry) {
            throw "Required model runtime library is missing: $entryName"
        }
        $stream = $entry.Open()
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = $sha256.ComputeHash($stream)
            $actual = ([BitConverter]::ToString($bytes)).Replace('-', '')
        }
        finally {
            $sha256.Dispose()
            $stream.Dispose()
        }
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
                    '^lib/[^/]+/(libLiteRt.*|libtensorflowlite.*|' +
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
}

Write-Host 'APK model runtime integrity: PASS' -ForegroundColor Green
exit 0
