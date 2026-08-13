#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:Passed = 0
$script:Failed = 0

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)

    if ($Text -match $Pattern) {
        $script:Passed++
        return
    }
    $script:Failed++
    Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
}

function Assert-True {
    param([object]$Value, [string]$Message)

    if ($Value) {
        $script:Passed++
        return
    }
    $script:Failed++
    Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
}

$repoRoot = Split-Path -Parent (
    Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
)
$overlayPath = Join-Path $repoRoot `
    'android\app\src\release\AndroidManifest.xml'
$gradlePath = Join-Path $repoRoot 'android\app\build.gradle.kts'
$packagerPath = Join-Path $repoRoot `
    'tool\cli\package-field-release.ps1'

Assert-True (Test-Path -LiteralPath $overlayPath -PathType Leaf) `
    'release-only Android manifest overlay exists'
if (Test-Path -LiteralPath $overlayPath -PathType Leaf) {
    $overlay = Get-Content -LiteralPath $overlayPath -Raw -Encoding utf8
    foreach ($entry in @(
        @{ Name = 'SOURCE_COMMIT'; Placeholder = 'lexiquestSourceCommit' },
        @{ Name = 'BUILD_ID'; Placeholder = 'lexiquestBuildId' },
        @{ Name = 'MODEL_SHA256'; Placeholder = 'lexiquestModelSha256' }
    )) {
        Assert-Match $overlay (
            'android:name="com\.lexiquest\.release\.' +
            $entry.Name + '"[\s\S]*?android:value="\$\{' +
            $entry.Placeholder + '\}"'
        ) "release manifest binds $($entry.Name) to its Gradle placeholder"
    }
}

$gradle = Get-Content -LiteralPath $gradlePath -Raw -Encoding utf8
foreach ($needle in @(
    'gradleProperty("lexiquestSourceCommit")',
    'gradleProperty("lexiquestBuildId")',
    'gradleProperty("lexiquestModelSha256")',
    'releaseBuildId == releaseSourceCommit.take(12)',
    'manifestPlaceholders.putAll',
    'releaseProvenanceReady'
)) {
    Assert-True $gradle.Contains($needle) "Gradle release gate contains $needle"
}
Assert-Match $gradle `
    'Regex\("\^\[0-9a-f\]\{40\}\$"\)[\s\S]*Regex\("\^\[0-9a-f\]\{12\}\$"\)[\s\S]*Regex\("\^\[0-9A-F\]\{64\}\$"\)' `
    'Gradle strictly validates commit, build, and model hash lengths'
Assert-True $gradle.Contains('rootProject.file(it).canonicalFile') `
    'relative signing storeFile resolves from android root'
Assert-Match $gradle `
    'if\s*\(isReleaseArtifact\s*&&\s*!releaseProvenanceReady\)[\s\S]*?throw GradleException' `
    'release Gradle tasks fail closed when any provenance value is missing or invalid'

$packager = Get-Content -LiteralPath $packagerPath -Raw -Encoding utf8
foreach ($needle in @(
    'Find-ApkAnalyzer',
    'verify-field-package.ps1',
    '--android-project-arg=lexiquestSourceCommit=',
    '--android-project-arg=lexiquestBuildId=',
    '--android-project-arg=lexiquestModelSha256=',
    "-Verb 'application-id'",
    "-Verb 'version-name'",
    "-Verb 'version-code'",
    'manifest print',
    'com.lexiquest.release.SOURCE_COMMIT',
    'com.lexiquest.release.BUILD_ID',
    'com.lexiquest.release.MODEL_SHA256'
)) {
    Assert-True $packager.Contains($needle) "release packager contains $needle"
}
Assert-True (-not $packager.Contains('ORG_GRADLE_PROJECT_lexiquest')) `
    'release provenance has one explicit Flutter-to-Gradle argument source'

Write-Host (
    'Android release provenance tests: {0} passed, {1} failed' -f
    $script:Passed,
    $script:Failed
)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
