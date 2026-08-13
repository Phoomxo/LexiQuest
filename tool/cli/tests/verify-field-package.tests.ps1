#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:Passed = 0
$script:Failed = 0

function Assert-True {
    param([object]$Value, [string]$Message)

    if ($Value) {
        $script:Passed++
        return
    }
    $script:Failed++
    Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
}

function Write-Utf8File {
    param([string]$Path, [string]$Content)

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText(
        $Path,
        $Content,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Invoke-Verifier {
    param(
        [string]$VerifierPath,
        [string]$PackagePath,
        [string]$SigningMetadataPath,
        [string]$FakeBin,
        [string]$RuntimeVerifierPath
    )

    $previousPath = $env:PATH
    $previousErrorAction = $ErrorActionPreference
    try {
        $env:PATH = $FakeBin + [System.IO.Path]::PathSeparator + $previousPath
        $ErrorActionPreference = 'Continue'
        $arguments = @(
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $VerifierPath,
            '-PackagePath',
            $PackagePath,
            '-SigningMetadataPath',
            $SigningMetadataPath
        )
        if (-not [string]::IsNullOrWhiteSpace($RuntimeVerifierPath)) {
            $arguments += @('-RuntimeVerifierPath', $RuntimeVerifierPath)
        }
        $output = & powershell @arguments 2>&1
        return [pscustomobject]@{
            ExitCode = [int]$LASTEXITCODE
            Output = ($output -join "`n")
        }
    }
    finally {
        $env:PATH = $previousPath
        $ErrorActionPreference = $previousErrorAction
    }
}

$repoRoot = Split-Path -Parent (
    Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
)
$verifierPath = Join-Path $repoRoot 'tool\cli\verify-field-package.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'lexiquest-package-verify-' + [Guid]::NewGuid().ToString('N')
)
$packageRoot = Join-Path $tempRoot 'package'
$fakeBin = Join-Path $tempRoot 'bin'
$signingMetadataPath = Join-Path $tempRoot 'signing-metadata.json'
$runtimeVerifierPath = Join-Path $tempRoot 'runtime-verifier.ps1'
$apkName = 'lexiquest-1.0.0+13.apk'
$apkPath = Join-Path $packageRoot $apkName
$sourceCommit = 'a' * 40
$buildId = 'a' * 12
$modelSha256 = 'D' * 64
$certificateSha256 = 'A' * 64

New-Item -ItemType Directory -Path $packageRoot, $fakeBin -Force | Out-Null
try {
    [System.IO.File]::WriteAllBytes(
        $apkPath,
        [System.Text.Encoding]::UTF8.GetBytes('verified-fixture-apk')
    )
    $apkSha256 = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash
    $manifest = [ordered]@{
        schemaVersion = 1
        generatedAtUtc = '2026-08-13T00:00:00Z'
        sourceCommit = $sourceCommit
        artifact = [ordered]@{
            apkPath = $apkName
            apkSha256 = $apkSha256
            signingCertificateSha256 = $certificateSha256
            packageName = 'com.lexiquest.app'
            versionName = '1.0.0'
            versionCode = 13
            buildId = $buildId
            modelSha256 = $modelSha256
        }
    }
    Write-Utf8File -Path (Join-Path $packageRoot 'release-manifest.json') `
        -Content (($manifest | ConvertTo-Json -Depth 8) + "`n")
    Write-Utf8File -Path $signingMetadataPath -Content (([ordered]@{
        schemaVersion = 1
        keyStorePath = 'not-needed-for-read-only-verification'
        alias = 'upload'
        storeType = 'PKCS12'
        certificateSha256 = $certificateSha256
    } | ConvertTo-Json -Depth 4) + "`n")
    Write-Utf8File -Path $runtimeVerifierPath -Content @'
param([string]$ApkPath, [string]$BuildMode)
if ($BuildMode -cne 'Release') { exit 19 }
exit 0
'@
    $standaloneVerifierPath = Join-Path $tempRoot `
        'standalone\tool\cli\verify-field-package.ps1'
    New-Item -ItemType Directory -Path (
        Split-Path -Parent $standaloneVerifierPath
    ) -Force | Out-Null
    Copy-Item -LiteralPath $verifierPath -Destination $standaloneVerifierPath
    Copy-Item -LiteralPath $runtimeVerifierPath -Destination (
        Join-Path (Split-Path -Parent $standaloneVerifierPath) `
            'verify-apk-model-runtime.ps1'
    )
    Write-Utf8File -Path (Join-Path $fakeBin 'apksigner.cmd') -Content @'
@echo off
echo Signer #1 certificate SHA-256 digest: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
exit /b 0
'@
    Write-Utf8File -Path (Join-Path $fakeBin 'apkanalyzer.cmd') -Content @"
@echo off
if "%1 %2"=="manifest application-id" echo com.lexiquest.app
if "%1 %2"=="manifest version-name" echo 1.0.0
if "%1 %2"=="manifest version-code" echo 13
if "%1 %2"=="manifest print" (
  echo ^<manifest xmlns:android="http://schemas.android.com/apk/res/android"^>^<application^>
  echo ^<meta-data android:name="com.lexiquest.release.SOURCE_COMMIT" android:value="$sourceCommit" /^>
  echo ^<meta-data android:name="com.lexiquest.release.BUILD_ID" android:value="$buildId" /^>
  echo ^<meta-data android:name="com.lexiquest.release.MODEL_SHA256" android:value="$modelSha256" /^>
  echo ^</application^>^</manifest^>
)
exit /b 0
"@

    $result = Invoke-Verifier -VerifierPath $standaloneVerifierPath `
        -PackagePath $packageRoot `
        -SigningMetadataPath $signingMetadataPath `
        -FakeBin $fakeBin
    Assert-True ($result.ExitCode -eq 0) `
        'standalone package verification resolves its sibling runtime verifier'

    $result = Invoke-Verifier -VerifierPath $verifierPath `
        -PackagePath $packageRoot `
        -SigningMetadataPath $signingMetadataPath `
        -FakeBin $fakeBin `
        -RuntimeVerifierPath $runtimeVerifierPath
    Assert-True ($result.ExitCode -eq 0) `
        'a complete signed package passes independent verification'

    Write-Utf8File -Path (Join-Path $fakeBin 'apksigner.cmd') -Content @'
@echo off
echo Signer #1 certificate SHA-256 digest: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
echo Signer #2 certificate SHA-256 digest: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
exit /b 0
'@
    $result = Invoke-Verifier -VerifierPath $verifierPath `
        -PackagePath $packageRoot `
        -SigningMetadataPath $signingMetadataPath `
        -FakeBin $fakeBin `
        -RuntimeVerifierPath $runtimeVerifierPath
    Assert-True ($result.ExitCode -ne 0) `
        'a multi-signer APK fails independent verification'
    Write-Utf8File -Path (Join-Path $fakeBin 'apksigner.cmd') -Content @'
@echo off
echo Signer #1 certificate SHA-256 digest: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
exit /b 0
'@

    [System.IO.File]::AppendAllText($apkPath, 'tamper')
    $result = Invoke-Verifier -VerifierPath $verifierPath `
        -PackagePath $packageRoot `
        -SigningMetadataPath $signingMetadataPath `
        -FakeBin $fakeBin `
        -RuntimeVerifierPath $runtimeVerifierPath
    Assert-True ($result.ExitCode -ne 0) `
        'APK byte tampering fails independent verification'

    [System.IO.File]::WriteAllBytes(
        $apkPath,
        [System.Text.Encoding]::UTF8.GetBytes('verified-fixture-apk')
    )
    $manifest.artifact.apkPath = '..\escape.apk'
    Write-Utf8File -Path (Join-Path $packageRoot 'release-manifest.json') `
        -Content (($manifest | ConvertTo-Json -Depth 8) + "`n")
    $result = Invoke-Verifier -VerifierPath $verifierPath `
        -PackagePath $packageRoot `
        -SigningMetadataPath $signingMetadataPath `
        -FakeBin $fakeBin `
        -RuntimeVerifierPath $runtimeVerifierPath
    Assert-True ($result.ExitCode -ne 0) `
        'a manifest APK path traversal fails independent verification'
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host (
    'Field package verifier tests: {0} passed, {1} failed' -f
    $script:Passed,
    $script:Failed
)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
