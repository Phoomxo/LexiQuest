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
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

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

function New-PackagerFixture {
    param([switch]$IncludeSigningMetadata)

    $root = Join-Path ([System.IO.Path]::GetTempPath()) (
        'lexiquest-package-test-' + [Guid]::NewGuid().ToString('N')
    )
    $repository = Join-Path $root 'repo'
    $fakeHome = Join-Path $root 'home'
    $fakeBin = Join-Path $root 'bin'
    $callLog = Join-Path $root 'calls.log'
    $argumentLog = Join-Path $root 'flutter-args.log'
    foreach ($directory in @($repository, $fakeHome, $fakeBin)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $realRepoRoot = Split-Path -Parent (
        Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    )
    $packagerPath = Join-Path $repository `
        'tool\cli\package-field-release.ps1'
    New-Item -ItemType Directory -Path (Split-Path -Parent $packagerPath) `
        -Force | Out-Null
    Copy-Item -LiteralPath (
        Join-Path $realRepoRoot 'tool\cli\package-field-release.ps1'
    ) -Destination $packagerPath
    Copy-Item -LiteralPath (
        Join-Path $realRepoRoot 'tool\cli\verify-field-package.ps1'
    ) -Destination (Join-Path (Split-Path -Parent $packagerPath) `
        'verify-field-package.ps1')

    Write-Utf8File -Path (Join-Path $repository '.gitignore') -Content @'
build/
android/key.properties
'@
    Write-Utf8File -Path (Join-Path $repository 'pubspec.yaml') -Content @'
name: packager_fixture
version: 1.0.0+13
'@
    Write-Utf8File -Path (
        Join-Path $repository `
            'lib\features\device_model\domain\model_manifest.dart'
    ) -Content @'
const expectedSha256 =
    'd3949e8a3556c79739cb675e0be7476503bcce76938031c6a1048e13e0cb7d8b';
'@
    Write-Utf8File -Path (
        Join-Path $repository 'docs\field\install-and-update.md'
    ) -Content "fixture participant guide`n"
    Write-Utf8File -Path (
        Join-Path $repository 'tool\cli\verify-apk-model-runtime.ps1'
    ) -Content @'
param([string]$ApkPath, [string]$BuildMode)
Add-Content -LiteralPath $env:LEXIQUEST_PACKAGE_TEST_LOG -Value 'runtime-verifier'
if ($env:LEXIQUEST_PACKAGE_TEST_RUNTIME_FAIL -eq '1') { exit 23 }
exit 0
'@

    $signingDirectory = Join-Path $fakeHome '.lexiquest\signing'
    New-Item -ItemType Directory -Path $signingDirectory -Force | Out-Null
    $keyStorePath = Join-Path $signingDirectory 'lexiquest-release.p12'
    [System.IO.File]::WriteAllBytes($keyStorePath, [byte[]](1, 2, 3, 4))
    Write-Utf8File -Path (
        Join-Path $repository 'android\key.properties'
    ) -Content @"
storeFile=$($keyStorePath.Replace('\', '/'))
storePassword=TEST_ONLY_NON_SECRET_VALUE
keyAlias=upload
keyPassword=TEST_ONLY_NON_SECRET_VALUE
"@
    if ($IncludeSigningMetadata) {
        $metadata = [ordered]@{
            schemaVersion = 1
            keyStorePath = $keyStorePath
            alias = 'upload'
            storeType = 'PKCS12'
            certificateSha256 = 'A' * 64
        }
        Write-Utf8File -Path (
            Join-Path $signingDirectory 'signing-metadata.json'
        ) -Content (($metadata | ConvertTo-Json -Depth 4) + "`n")
    }

    Write-Utf8File -Path (Join-Path $fakeBin 'fake-flutter.ps1') -Content @'
Add-Content -LiteralPath $env:LEXIQUEST_PACKAGE_TEST_LOG -Value 'flutter'
[System.IO.File]::WriteAllLines(
    $env:LEXIQUEST_PACKAGE_TEST_ARGS,
    [string[]]$args,
    [System.Text.UTF8Encoding]::new($false)
)
$apk = Join-Path (Get-Location) 'build\app\outputs\flutter-apk\app-release.apk'
New-Item -ItemType Directory -Path (Split-Path -Parent $apk) -Force | Out-Null
[System.IO.File]::WriteAllBytes($apk, [System.Text.Encoding]::UTF8.GetBytes('fixture-apk'))
if ($env:LEXIQUEST_PACKAGE_TEST_SKIP_APK -eq '1') {
    Remove-Item -LiteralPath $apk -Force -ErrorAction SilentlyContinue
}
if ($env:LEXIQUEST_PACKAGE_TEST_DIRTY_AFTER_BUILD -eq '1') {
    [System.IO.File]::WriteAllText(
        (Join-Path (Get-Location) 'source-drift.txt'),
        'changed during build'
    )
}
exit 0
'@
    Write-Utf8File -Path (Join-Path $fakeBin 'flutter.cmd') -Content @'
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fake-flutter.ps1" %*
exit /b %ERRORLEVEL%
'@
    Write-Utf8File -Path (Join-Path $fakeBin 'apksigner.cmd') -Content @'
@echo off
echo apksigner>>"%LEXIQUEST_PACKAGE_TEST_LOG%"
echo Signer #1 certificate SHA-256 digest: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
exit /b 0
'@
    Write-Utf8File -Path (Join-Path $fakeBin 'fake-apkanalyzer.ps1') -Content @'
Add-Content -LiteralPath $env:LEXIQUEST_PACKAGE_TEST_LOG -Value 'apkanalyzer'
$verb = "$($args[0]) $($args[1])"
if ($verb -ceq 'manifest application-id') { 'com.lexiquest.app'; exit 0 }
if ($verb -ceq 'manifest version-name') { '1.0.0'; exit 0 }
if ($verb -ceq 'manifest version-code') { '13'; exit 0 }
if ($verb -ceq 'manifest debuggable') { 'false'; exit 0 }
if ($verb -ceq 'manifest print') {
    $projectArguments = @{}
    if (Test-Path -LiteralPath $env:LEXIQUEST_PACKAGE_TEST_ARGS) {
        foreach ($argument in Get-Content -LiteralPath `
            $env:LEXIQUEST_PACKAGE_TEST_ARGS -Encoding utf8) {
            if (
                $argument -match
                    '^--android-project-arg=(?<name>[^=]+)=(?<value>.+)$'
            ) {
                $projectArguments[$Matches.name] = $Matches.value
            }
        }
    }
    $sourceCommit = if ($projectArguments.ContainsKey(
        'lexiquestSourceCommit'
    )) {
        $projectArguments.lexiquestSourceCommit
    } else {
        ''
    }
    $buildId = if ($projectArguments.ContainsKey('lexiquestBuildId')) {
        $projectArguments.lexiquestBuildId
    } else {
        ''
    }
    $modelSha256 = if ($projectArguments.ContainsKey(
        'lexiquestModelSha256'
    )) {
        $projectArguments.lexiquestModelSha256
    } else {
        ''
    }
    @"
<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application>
<meta-data android:name="com.lexiquest.release.SOURCE_COMMIT" android:value="$sourceCommit" />
<meta-data android:name="com.lexiquest.release.BUILD_ID" android:value="$buildId" />
<meta-data android:name="com.lexiquest.release.MODEL_SHA256" android:value="$modelSha256" />
</application></manifest>
"@
}
exit 0
'@
    Write-Utf8File -Path (Join-Path $fakeBin 'apkanalyzer.cmd') -Content @'
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fake-apkanalyzer.ps1" %*
exit /b %ERRORLEVEL%
'@

    Push-Location -LiteralPath $repository
    try {
        & git init --quiet
        & git config user.email 'packager-fixture@example.invalid'
        & git config user.name 'Packager Fixture'
        & git add --all
        & git commit --quiet -m 'fixture'
        if ([int]$LASTEXITCODE -ne 0) {
            throw 'Unable to commit the packager fixture.'
        }
        $sourceCommit = (& git rev-parse HEAD).Trim()
    }
    finally {
        Pop-Location
    }

    return [pscustomobject]@{
        Root = $root
        Repository = $repository
        FakeHome = $fakeHome
        FakeBin = $fakeBin
        CallLog = $callLog
        ArgumentLog = $argumentLog
        PackagerPath = $packagerPath
        SourceCommit = $sourceCommit
    }
}

function Invoke-PackagerFixture {
    param(
        [Parameter(Mandatory)][pscustomobject]$Fixture,
        [string]$OutputPath,
        [hashtable]$Environment = @{}
    )

    $previousPath = $env:PATH
    $previousUserProfile = $env:USERPROFILE
    $previousHome = $env:HOME
    $previousLog = $env:LEXIQUEST_PACKAGE_TEST_LOG
    $previousArguments = $env:LEXIQUEST_PACKAGE_TEST_ARGS
    $previousErrorAction = $ErrorActionPreference
    $previousEnvironment = @{}
    try {
        $env:PATH = $Fixture.FakeBin + [System.IO.Path]::PathSeparator +
            $previousPath
        $env:USERPROFILE = $Fixture.FakeHome
        $env:HOME = $Fixture.FakeHome
        $env:LEXIQUEST_PACKAGE_TEST_LOG = $Fixture.CallLog
        $env:LEXIQUEST_PACKAGE_TEST_ARGS = $Fixture.ArgumentLog
        foreach ($name in $Environment.Keys) {
            $existing = Get-Item -LiteralPath "Env:$name" `
                -ErrorAction SilentlyContinue
            $previousEnvironment[$name] = if ($null -eq $existing) {
                $null
            } else {
                $existing.Value
            }
            Set-Item -LiteralPath "Env:$name" `
                -Value ([string]$Environment[$name])
        }
        $ErrorActionPreference = 'Continue'
        $arguments = @(
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $Fixture.PackagerPath,
            '-Version',
            '1.0.0+13'
        )
        if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
            $arguments += @('-OutputPath', $OutputPath)
        }
        $arguments += @(
            '-SigningMetadataPath',
            (Join-Path $Fixture.FakeHome `
                '.lexiquest\signing\signing-metadata.json')
        )
        $output = & powershell @arguments 2>&1
        return [pscustomobject]@{
            ExitCode = [int]$LASTEXITCODE
            Output = ($output -join "`n")
        }
    }
    finally {
        $env:PATH = $previousPath
        $env:USERPROFILE = $previousUserProfile
        $env:HOME = $previousHome
        $env:LEXIQUEST_PACKAGE_TEST_LOG = $previousLog
        $env:LEXIQUEST_PACKAGE_TEST_ARGS = $previousArguments
        $ErrorActionPreference = $previousErrorAction
        foreach ($name in $Environment.Keys) {
            if ($null -eq $previousEnvironment[$name]) {
                Remove-Item -LiteralPath "Env:$name" `
                    -ErrorAction SilentlyContinue
            } else {
                Set-Item -LiteralPath "Env:$name" `
                    -Value ([string]$previousEnvironment[$name])
            }
        }
    }
}

$fixture = New-PackagerFixture
try {
    $result = Invoke-PackagerFixture -Fixture $fixture
    Assert-True ($result.ExitCode -ne 0) `
        'missing pinned signing metadata stops packaging'
    $calls = if (Test-Path -LiteralPath $fixture.CallLog) {
        Get-Content -LiteralPath $fixture.CallLog -Raw -Encoding utf8
    } else {
        ''
    }
    Assert-True (-not $calls.Contains('flutter')) `
        'missing signing metadata stops before the build command'
}
finally {
    if (Test-Path -LiteralPath $fixture.Root -PathType Container) {
        Remove-Item -LiteralPath $fixture.Root -Recurse -Force
    }
}

$fixture = New-PackagerFixture -IncludeSigningMetadata
try {
    Write-Utf8File -Path (
        Join-Path $fixture.Repository 'untracked-release-input.txt'
    ) -Content "must block packaging`n"
    $result = Invoke-PackagerFixture -Fixture $fixture
    Assert-True ($result.ExitCode -ne 0) `
        'any uncommitted repository path stops packaging'
    $calls = if (Test-Path -LiteralPath $fixture.CallLog) {
        Get-Content -LiteralPath $fixture.CallLog -Raw -Encoding utf8
    } else {
        ''
    }
    Assert-True (-not $calls.Contains('flutter')) `
        'a dirty repository stops before the build command'
}
finally {
    if (Test-Path -LiteralPath $fixture.Root -PathType Container) {
        Remove-Item -LiteralPath $fixture.Root -Recurse -Force
    }
}

$fixture = New-PackagerFixture -IncludeSigningMetadata
try {
    $outsideOutput = Join-Path $fixture.Root 'outside-release'
    $result = Invoke-PackagerFixture -Fixture $fixture `
        -OutputPath $outsideOutput
    Assert-True ($result.ExitCode -ne 0) `
        'release output cannot escape build/field-release'
    $calls = if (Test-Path -LiteralPath $fixture.CallLog) {
        Get-Content -LiteralPath $fixture.CallLog -Raw -Encoding utf8
    } else {
        ''
    }
    Assert-True (-not $calls.Contains('flutter')) `
        'an invalid output path stops before the build command'
}
finally {
    if (Test-Path -LiteralPath $fixture.Root -PathType Container) {
        Remove-Item -LiteralPath $fixture.Root -Recurse -Force
    }
}

$fixture = New-PackagerFixture -IncludeSigningMetadata
try {
    $result = Invoke-PackagerFixture -Fixture $fixture
    Assert-True ($result.ExitCode -eq 0) `
        'a valid frozen fixture produces a release package'
    $calls = Get-Content -LiteralPath $fixture.CallLog -Raw -Encoding utf8
    Assert-True ($calls.Contains('runtime-verifier')) `
        'the release runtime verifier runs before publication'
    $flutterArguments = @(
        Get-Content -LiteralPath $fixture.ArgumentLog -Encoding utf8
    )
    Assert-True ($flutterArguments -ccontains (
        '--android-project-arg=lexiquestSourceCommit=' +
            $fixture.SourceCommit
    )) 'Flutter receives the exact frozen source commit as a Gradle property'
    Assert-True ($flutterArguments -ccontains (
        '--android-project-arg=lexiquestBuildId=' +
            $fixture.SourceCommit.Substring(0, 12)
    )) 'Flutter receives the exact build ID as a Gradle property'
    Assert-True ($flutterArguments -ccontains (
        '--android-project-arg=lexiquestModelSha256=' +
            'D3949E8A3556C79739CB675E0BE7476503BCCE76938031C6A1048E13E0CB7D8B'
    )) 'Flutter receives the exact model SHA-256 as a Gradle property'
    $packageRoot = Join-Path $fixture.Repository 'build\field-release'
    $manifestPath = Join-Path $packageRoot 'release-manifest.json'
    Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) `
        'successful packaging writes release-manifest.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 |
            ConvertFrom-Json
        Assert-True (
            [string]$manifest.artifact.apkPath -ceq
                'lexiquest-1.0.0+13.apk'
        ) 'release manifest stores an APK filename relative to the package'
        Assert-True (
            [string]$manifest.sourceCommit -ceq $fixture.SourceCommit
        ) 'release manifest records the frozen source commit'
        $apkPath = Join-Path $packageRoot ([string]$manifest.artifact.apkPath)
        Assert-True (
            (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash -ceq
                [string]$manifest.artifact.apkSha256
        ) 'release manifest APK hash matches the packaged bytes'
    }
}
finally {
    if (Test-Path -LiteralPath $fixture.Root -PathType Container) {
        Remove-Item -LiteralPath $fixture.Root -Recurse -Force
    }
}

$fixture = New-PackagerFixture -IncludeSigningMetadata
try {
    $output = Join-Path $fixture.Repository 'build\field-release'
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    Write-Utf8File -Path (Join-Path $output 'sentinel.txt') `
        -Content "preserve me`n"
    $result = Invoke-PackagerFixture -Fixture $fixture
    Assert-True ($result.ExitCode -ne 0) `
        'an existing release output stops packaging'
    Assert-True (
        Test-Path -LiteralPath (Join-Path $output 'sentinel.txt') -PathType Leaf
    ) 'an existing release output is never deleted or overwritten'
    Assert-True (
        -not (Test-Path -LiteralPath $fixture.CallLog -PathType Leaf)
    ) 'an existing release output stops before tool invocation'
}
finally {
    if (Test-Path -LiteralPath $fixture.Root -PathType Container) {
        Remove-Item -LiteralPath $fixture.Root -Recurse -Force
    }
}

$fixture = New-PackagerFixture -IncludeSigningMetadata
try {
    $sourceApk = Join-Path $fixture.Repository `
        'build\app\outputs\flutter-apk\app-release.apk'
    Write-Utf8File -Path $sourceApk -Content 'stale-apk'
    $result = Invoke-PackagerFixture -Fixture $fixture -Environment @{
        LEXIQUEST_PACKAGE_TEST_SKIP_APK = '1'
    }
    Assert-True ($result.ExitCode -ne 0) `
        'a zero-exit build without a fresh APK stops packaging'
    Assert-True (
        -not (Test-Path -LiteralPath (
            Join-Path $fixture.Repository 'build\field-release'
        ))
    ) 'a stale source APK is never published'
}
finally {
    if (Test-Path -LiteralPath $fixture.Root -PathType Container) {
        Remove-Item -LiteralPath $fixture.Root -Recurse -Force
    }
}

$fixture = New-PackagerFixture -IncludeSigningMetadata
try {
    $result = Invoke-PackagerFixture -Fixture $fixture -Environment @{
        LEXIQUEST_PACKAGE_TEST_RUNTIME_FAIL = '1'
    }
    Assert-True ($result.ExitCode -ne 0) `
        'a runtime-integrity failure stops packaging'
    Assert-True (
        -not (Test-Path -LiteralPath (
            Join-Path $fixture.Repository 'build\field-release'
        ))
    ) 'runtime-integrity failure publishes no release package'
    $stagingDirectories = @(
        Get-ChildItem -LiteralPath (Join-Path $fixture.Repository 'build') `
            -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name.StartsWith('.field-release-stage-') }
    )
    Assert-True ($stagingDirectories.Count -eq 0) `
        'runtime-integrity failure drains the staging directory'
}
finally {
    if (Test-Path -LiteralPath $fixture.Root -PathType Container) {
        Remove-Item -LiteralPath $fixture.Root -Recurse -Force
    }
}

$fixture = New-PackagerFixture -IncludeSigningMetadata
try {
    $result = Invoke-PackagerFixture -Fixture $fixture -Environment @{
        LEXIQUEST_PACKAGE_TEST_DIRTY_AFTER_BUILD = '1'
    }
    Assert-True ($result.ExitCode -ne 0) `
        'source drift during the build stops packaging'
    Assert-True (
        -not (Test-Path -LiteralPath (
            Join-Path $fixture.Repository 'build\field-release'
        ))
    ) 'source drift publishes no release package'
}
finally {
    if (Test-Path -LiteralPath $fixture.Root -PathType Container) {
        Remove-Item -LiteralPath $fixture.Root -Recurse -Force
    }
}
Write-Host (
    'Release packager tests: {0} passed, {1} failed' -f
    $script:Passed,
    $script:Failed
)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
