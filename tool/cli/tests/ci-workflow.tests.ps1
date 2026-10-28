#Requires -Version 5.1
<#
.SYNOPSIS
    Dependency-free contract test for the LexiQuest GitHub Actions CI workflow.

.DESCRIPTION
    Validates triggers, least-privilege permissions, concurrency cancellation,
    immutable action pins, CPU-only verification coverage, frozen uv commands,
    the npm/Firebase test toolchain, and the absence of embedded secrets. The
    workflow is read as normalized raw text, so YAML indentation and CRLF/LF
    line endings do not affect the checks.
#>
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:PassedCount = 0
$script:FailedCount = 0

function Write-Pass {
    param([string]$Message)
    $script:PassedCount++
}

function Write-Fail {
    param([string]$Message)
    $script:FailedCount++
    Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
}

function Assert-True {
    param([object]$Value, [string]$Message)
    if ($Value) { Write-Pass $Message } else { Write-Fail $Message }
}

function Assert-ContainsString {
    param([string]$Haystack, [string]$Needle, [string]$Message)
    if (-not [string]::IsNullOrEmpty($Haystack) -and $Haystack.Contains($Needle)) {
        Write-Pass $Message
    } else {
        Write-Fail ($Message + " (missing '" + $Needle + "')")
    }
}

function Assert-NotContainsString {
    param(
        [string] $Text,
        [string] $Needle,
        [string] $Message
    )
    if ($Text.Contains($Needle)) {
        throw $Message
    }
    Write-Pass $Message
}

function Assert-RegexMatches {
    param([string]$Haystack, [string]$Pattern, [string]$Message)
    if (-not [string]::IsNullOrEmpty($Haystack) -and ($Haystack -match $Pattern)) {
        Write-Pass $Message
    } else {
        Write-Fail ($Message + ' (regex did not match: ' + $Pattern + ')')
    }
}

function Assert-RegexNotMatches {
    param([string]$Haystack, [string]$Pattern, [string]$Message)
    if (-not [string]::IsNullOrEmpty($Haystack) -and ($Haystack -match $Pattern)) {
        Write-Fail ($Message + ' (forbidden match: ' + $Pattern + ')')
    } else {
        Write-Pass $Message
    }
}

function Get-CiWorkflowText {
    param([string]$Path)
    $raw = [System.IO.File]::ReadAllText($Path)
    $normalized = $raw -replace "`r`n", "`n"
    return ($normalized -replace "`r", "`n")
}

function Invoke-TriggerTests {
    param([string]$Text)
    Assert-RegexMatches $Text '\bpull_request\b' 'workflow triggers on pull_request'
    Assert-RegexMatches $Text '\bpush\b' 'workflow triggers on push'
    Assert-RegexMatches $Text '\bmain\b' 'push target includes the main branch'
}

function Invoke-PermissionTests {
    param([string]$Text)
    Assert-RegexMatches $Text '(?m)^permissions[ \t]*:' 'top-level permissions block exists'
    Assert-RegexMatches $Text '(?i)contents[ \t]*:[ \t]*read\b' 'contents permission is read'
}

function Invoke-ConcurrencyTests {
    param([string]$Text)
    Assert-RegexMatches $Text '(?m)^concurrency[ \t]*:' 'top-level concurrency block exists'
    Assert-RegexMatches $Text '(?m)^[ \t]*group[ \t]*:' 'concurrency declares a group'
    Assert-RegexMatches $Text 'github\.ref' 'concurrency group keys on the same ref'
    Assert-RegexMatches $Text '(?i)cancel-in-progress[ \t]*:[ \t]*true\b' 'obsolete run for the same ref is cancelled'
}

function Invoke-ActionPinTests {
    param([string]$Text)
    $uses = [regex]::Matches($Text, '(?m)^[ \t]*-?[ \t]*uses[ \t]*:[ \t]*(\S+)')
    Assert-True ($uses.Count -ge 1) 'workflow pins at least one third-party action'

    $shaPattern = '^[A-Za-z0-9._/-]+@[0-9A-Fa-f]{40}$'
    foreach ($match in $uses) {
        $reference = $match.Groups[1].Value.Trim('"').Trim("'")
        if ($reference -cmatch $shaPattern) {
            Write-Pass ('action reference is a pinned SHA: ' + $reference)
        } else {
            Write-Fail ('action reference must be an exact 40-char hex SHA, got: ' + $reference)
        }
    }
}

function Invoke-OfficialActionTests {
    param([string]$Text)
    Assert-RegexMatches $Text '(?m)^[ \t]*-?[ \t]*uses[ \t]*:[ \t]*actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1[ \t]+#[ \t]+v7\.0\.1\b' 'actions/checkout is pinned to 3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1'
    Assert-RegexMatches $Text '(?m)^[ \t]*-?[ \t]*uses[ \t]*:[ \t]*actions/setup-java@03ad4de0992f5dab5e18fcb136590ce7c4a0ac95[ \t]+#[ \t]+v5\.6\.0\b' 'actions/setup-java is pinned to 03ad4de0992f5dab5e18fcb136590ce7c4a0ac95 # v5.6.0'
    Assert-RegexMatches $Text '(?m)^[ \t]*-?[ \t]*uses[ \t]*:[ \t]*actions/setup-node@820762786026740c76f36085b0efc47a31fe5020[ \t]+#[ \t]+v7\.0\.0\b' 'actions/setup-node is pinned to 820762786026740c76f36085b0efc47a31fe5020 # v7.0.0'
}

function Invoke-JobCoverageTests {
    param([string]$Text)
    Assert-ContainsString $Text 'flutter pub get' 'job resolves Flutter dependencies'
    Assert-ContainsString $Text 'git ls-files' 'format check selects tracked sources'
    Assert-ContainsString $Text 'dart format' 'job checks tracked Dart formatting'
    Assert-ContainsString $Text '--set-exit-if-changed' 'format check fails on changes'
    Assert-ContainsString $Text 'flutter analyze' 'job runs flutter analyze'
    Assert-ContainsString $Text 'flutter test' 'job runs flutter test'
    Assert-ContainsString $Text 'flutter test test/account/account_models_test.dart test/navigation/account_link_coordinator_test.dart' 'job runs focused account action-link tests'
    Assert-ContainsString $Text 'timeout --kill-after=5s 120s flutter test integration_test/account_lifecycle_test.dart -d linux --timeout 2m' 'job applies a bounded Linux account recovery integration process limit'
    Assert-ContainsString $Text '--timeout 2m' 'job retains the per-test account recovery timeout'
    Assert-ContainsString $Text 'pytest' 'backend suites run via pytest'
    Assert-ContainsString $Text 'voice_api' 'job covers backend/voice_api CPU tests'
    Assert-ContainsString $Text 'ai_api' 'job covers backend/ai_api CPU tests'
    Assert-ContainsString $Text 'lexiquest_lm' 'job covers backend/lexiquest_lm CPU tests'
    Assert-ContainsString $Text 'runtime-probes.tests.ps1' 'job runs runtime probe tests'
    Assert-ContainsString $Text 'run-android.tests.ps1' 'job runs Android command tests'
    Assert-ContainsString $Text 'firebase-auth-actions.tests.ps1' 'job runs Firebase Auth action-link contracts'
    Assert-ContainsString $Text 'firebase-assetlinks-validator.tests.ps1' 'job runs asset links validator fixtures'
    Assert-ContainsString $Text 'flutter build' 'job builds the Android app'
    Assert-ContainsString $Text 'apk' 'Android build produces an APK'
    Assert-ContainsString $Text '--debug' 'Android build is a debug build'
    Assert-NotContainsString $Text 'supabase/setup-cli@' 'CI must not provision Supabase'
    Assert-NotContainsString $Text 'supabase db start' 'CI must not start Supabase'
    Assert-NotContainsString $Text 'LEXIQUEST_SUPABASE' 'CI builds must not require Supabase'
    Assert-ContainsString $Text '--dart-define=LEXIQUEST_VERSION=0.1.0+1' 'CI builds v0.1'
    Assert-ContainsString $Text 'Create ephemeral release signing key' 'CI creates a disposable release signing key'
    Assert-ContainsString $Text 'flutter build appbundle --release' 'CI builds a release candidate AAB'
    Assert-ContainsString $Text 'jarsigner -verify -verbose -certs' 'CI verifies the release candidate signature'
    Assert-ContainsString $Text 'grep -q "jar verified."' 'CI rejects unsigned release candidates'
    Assert-ContainsString $Text 'mkdir -p build/sbom' 'CI prepares the SBOM output directory'
    Assert-ContainsString $Text 'release-candidate.cdx.json' 'CI creates an artifact SBOM'
    Assert-ContainsString $Text 'source.cdx.json' 'CI creates a source SBOM'
    Assert-ContainsString $Text 'Remove ephemeral signing material' 'CI removes disposable signing material'
}

function Invoke-ProductionReleaseTests {
    param([string]$Text)
    Assert-NotContainsString $Text 'LEXIQUEST_SUPABASE' 'production release must not require Supabase'
    Assert-ContainsString $Text '--dart-define=LEXIQUEST_VERSION=0.1.0+1' 'production release builds v0.1'
    Assert-ContainsString $Text 'LEXIQUEST_BUILD_ID' 'production release retains the build ID input'
    Assert-ContainsString $Text 'LEXIQUEST_VOICE_API_URL' 'production release retains the Voice API input'
    Assert-ContainsString $Text 'LEXIQUEST_AI_API_URL' 'production release retains the AI API input'
    Assert-ContainsString $Text 'firebase-auth-actions.tests.ps1' 'production release runs Firebase Auth action-link contracts'
    Assert-ContainsString $Text 'flutter test test/account/account_models_test.dart test/navigation/account_link_coordinator_test.dart' 'production release runs focused account action-link tests'
    Assert-ContainsString $Text 'vars.ANDROID_RELEASE_CERT_SHA256' 'production release reads the release certificate fingerprint variable'
    Assert-ContainsString $Text 'test -n "${ANDROID_RELEASE_CERT_SHA256}"' 'production release requires the release certificate fingerprint'
    Assert-ContainsString $Text '^[A-Fa-f0-9]{2}(:[A-Fa-f0-9]{2}){31}$' 'production release validates the SHA-256 fingerprint format'
    Assert-ContainsString $Text 'test -n "${LEXIQUEST_VOICE_API_URL}"' 'production release requires the Voice API URL'
    Assert-ContainsString $Text 'test -n "${LEXIQUEST_AI_API_URL}"' 'production release requires the AI API URL'
    Assert-ContainsString $Text 'urlsplit' 'production release parses endpoint URLs before building'
    Assert-ContainsString $Text "parsed.scheme != 'https'" 'production release requires the exact HTTPS scheme'
    Assert-ContainsString $Text 'not parsed.netloc' 'production release requires endpoint authority'
    Assert-ContainsString $Text 'not parsed.hostname' 'production release requires a non-empty endpoint host'
    Assert-ContainsString $Text 'parsed.username is not None' 'production release rejects endpoint usernames'
    Assert-ContainsString $Text 'parsed.password is not None' 'production release rejects endpoint passwords'
    Assert-ContainsString $Text "'@' in parsed.netloc" 'production release rejects endpoint userinfo'
    Assert-ContainsString $Text "'?' in raw" 'production release rejects endpoint queries'
    Assert-ContainsString $Text "'#' in raw" 'production release rejects endpoint fragments'
    Assert-ContainsString $Text "parsed.path not in ('', '/')" 'production release accepts only origin paths'
    Assert-ContainsString $Text '"--dart-define=LEXIQUEST_VERSION=0.1.0+1"' 'production release quotes the version define'
    Assert-ContainsString $Text '"--dart-define=LEXIQUEST_BUILD_ID=${LEXIQUEST_BUILD_ID}"' 'production release quotes the build ID define'
    Assert-ContainsString $Text '"--dart-define=LEXIQUEST_VOICE_API_URL=${LEXIQUEST_VOICE_API_URL}"' 'production release quotes the Voice API define'
    Assert-ContainsString $Text '"--dart-define=LEXIQUEST_AI_API_URL=${LEXIQUEST_AI_API_URL}"' 'production release quotes the AI API define'
    Assert-ContainsString $Text 'Restore protected signing material' 'production release restores protected signing material'
    Assert-ContainsString $Text 'ANDROID_RELEASE_KEYSTORE_BASE64' 'production release checks the protected keystore secret'
    Assert-ContainsString $Text 'flutter build appbundle --release' 'production release builds a signed AAB'
    Assert-ContainsString $Text 'jarsigner -verify -verbose -certs' 'production release verifies the AAB signature'
    Assert-ContainsString $Text 'Generate source SBOM' 'production release generates a source SBOM'
    Assert-ContainsString $Text 'production-aab.cdx.json' 'production release generates an artifact SBOM'
    Assert-ContainsString $Text 'Upload protected release artifacts' 'production release uploads the signed AAB and SBOM'
    Assert-ContainsString $Text 'Remove protected signing material' 'production release cleans up signing material'
    Assert-ContainsString $Text 'if: always()' 'production release always cleans up signing material'
}

function Invoke-UvFrozenTests {
    param([string]$Text)
    $uvRun = ([regex]::Matches($Text, '\buv[ \t]+run\b')).Count
    $uvSync = ([regex]::Matches($Text, '\buv[ \t]+sync\b')).Count
    $frozen = ([regex]::Matches($Text, '--frozen')).Count
    $uvCommands = $uvRun + $uvSync
    Assert-True ($uvCommands -ge 1) 'workflow invokes uv run or sync'
    Assert-True ($frozen -ge $uvCommands) ('every uv run or sync is frozen')
    Assert-RegexNotMatches $Text '(?i)--group[ \t]+(gpu|train)\b' 'uv never includes the gpu or train group'
    Assert-RegexNotMatches $Text '(?i)--extra[ \t=]*(gpu|train)\b' 'uv never includes a gpu or train extra'
    Assert-RegexNotMatches $Text '(?i)--all-(groups|extras)\b' 'uv never includes every optional group'
}

function Invoke-SecretEmbeddingTests {
    param([string]$Text)
    Assert-RegexNotMatches $Text '-----BEGIN[ A-Z]*PRIVATE KEY-----' 'no embedded private key'
    Assert-RegexNotMatches $Text 'ghp_[0-9A-Za-z]{36,}' 'no embedded GitHub token'
    Assert-RegexNotMatches $Text 'github_pat_[0-9A-Za-z_]+' 'no embedded fine-grained GitHub token'
    Assert-RegexNotMatches $Text 'xox[baprs]-[0-9A-Za-z-]+' 'no embedded Slack token'
    Assert-RegexNotMatches $Text 'AKIA[0-9A-Z]{16}' 'no embedded AWS access key'
    Assert-RegexNotMatches $Text 'AIza[0-9A-Za-z_-]{35}' 'no embedded Google API key'
    Assert-RegexNotMatches $Text '\bsk-[A-Za-z0-9]{20,}' 'no embedded OpenAI-style key'
}

function Invoke-GitleaksConfigTests {
    param([string]$Text)

    $block = [regex]::Match(
        $Text,
        '(?s)\[\[allowlists\]\]\s*description\s*=\s*"Retired public Supabase anon key in three historical commits\."(?<Body>.*?)(?=\[\[allowlists\]\]|\z)'
    )
    Assert-True $block.Success 'Gitleaks documents the retired public Supabase anon-key exception'
    if (-not $block.Success) { return }

    $body = $block.Groups['Body'].Value
    Assert-ContainsString $body 'condition = "AND"' 'historical exception requires every constraint'
    Assert-ContainsString $body "'''(?:^|/)lib/main\.dart$'''" 'historical exception is limited to lib/main.dart'
    foreach ($commit in @(
        'ff2364209c53bf3b4ff5e3bff7630484d9c5fd05',
        '15ae3e0e6b510296c4d064f974993f167730f8c4',
        '52a478a7a9589766bfbdf8a88bff97e3a6c771b7'
    )) {
        Assert-ContainsString $body $commit ('historical exception includes only reviewed commit ' + $commit)
    }
}

function Invoke-NpmFirebaseToolchainTests {
    param([string]$WorkflowText, [string]$PackageJsonText)

    $engineMatch = [regex]::Match(
        $PackageJsonText,
        '(?s)"engines"[ \t]*:[ \t]*\{[^}]*?"node"[ \t]*:[ \t]*"([^"]+)"'
    )
    Assert-True ($engineMatch.Success) 'package.json declares an engines.node constraint'
    $engineMajor = 0
    if ($engineMatch.Success) {
        $engineNumber = [regex]::Match($engineMatch.Groups[1].Value, '\d+')
        if ($engineNumber.Success) { $engineMajor = [int]$engineNumber.Value }
    }

    $nodeMatches = [regex]::Matches(
        $WorkflowText,
        'node-version[ \t]*:[ \t]*(\S+)'
    )
    Assert-True ($nodeMatches.Count -ge 1) 'workflow provisions an explicit Node version'
    foreach ($match in $nodeMatches) {
        $nodeToken = $match.Groups[1].Value.Trim('"').Trim("'")
        $nodeMajorMatch = [regex]::Match($nodeToken, '^\d+')
        if ($nodeMajorMatch.Success) {
            $nodeMajor = [int]$nodeMajorMatch.Value
            Assert-True (
                $engineMajor -gt 0 -and $nodeMajor -ge $engineMajor
            ) ('Node major version satisfies engines.node (>=' + $engineMajor + ')')
        } else {
            Write-Fail ('Node version is not explicit and numeric: ' + $nodeToken)
        }
    }

    Assert-ContainsString $WorkflowText 'npm ci' 'workflow installs npm dependencies reproducibly'

    $firebaseRefs = [regex]::Matches(
        $WorkflowText,
        'firebase-tools[ \t]*@[ \t]*(\d+(?:\.\d+){1,3})'
    )
    Assert-True ($firebaseRefs.Count -ge 1) 'workflow provisions firebase-tools as a CI tool'
    foreach ($match in $firebaseRefs) {
        Assert-True (
            $match.Groups[1].Value -eq '15.24.0'
        ) 'firebase-tools is pinned to exactly 15.24.0'
    }
    Assert-RegexMatches $WorkflowText '(?m)^[ \t]*java-version[ \t]*:[ \t]*[''"]?21\b' 'setup-java selects Java 21 (firebase-tools 15.24.0 requires Java 21+)'
    Assert-RegexNotMatches $PackageJsonText '"firebase-tools"[ \t]*:' 'package.json excludes firebase-tools'
    Assert-ContainsString $WorkflowText 'npm run test:rules' 'workflow executes Firestore rules tests'
    Assert-ContainsString $WorkflowText 'npm --prefix functions ci --ignore-scripts' 'workflow installs trusted writer dependencies reproducibly'
    Assert-ContainsString $WorkflowText 'npm --prefix functions test' 'workflow executes trusted writer tests'
    Assert-ContainsString $WorkflowText 'npm run test:functions-emulator' 'workflow executes trusted writer emulator tests'
}

$repoToolCli = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path (Split-Path $repoToolCli -Parent) -Parent
$workflowPath = Join-Path $repoRoot (Join-Path '.github' (Join-Path 'workflows' 'ci.yml'))
$productionReleaseWorkflowPath = Join-Path $repoRoot (Join-Path '.github' (Join-Path 'workflows' 'production-release.yml'))

if (-not (Test-Path -LiteralPath $workflowPath)) {
    Write-Host ("FAIL: missing CI workflow '{0}'." -f $workflowPath) -ForegroundColor Red
    Write-Host 'CI workflow contract tests: 0 passed, 1 failed' -ForegroundColor Red
    Write-Host 'FAILED' -ForegroundColor Red
    exit 1
}

$workflowText = Get-CiWorkflowText -Path $workflowPath

if (-not (Test-Path -LiteralPath $productionReleaseWorkflowPath)) {
    Write-Host ("FAIL: missing production release workflow '{0}'." -f $productionReleaseWorkflowPath) -ForegroundColor Red
    Write-Host 'CI workflow contract tests: 0 passed, 1 failed' -ForegroundColor Red
    Write-Host 'FAILED' -ForegroundColor Red
    exit 1
}

$productionReleaseWorkflowText = Get-CiWorkflowText -Path $productionReleaseWorkflowPath

$packageJsonPath = Join-Path $repoRoot 'package.json'
if (-not (Test-Path -LiteralPath $packageJsonPath)) {
    Write-Host ("FAIL: missing package.json '{0}'." -f $packageJsonPath) -ForegroundColor Red
    Write-Host 'CI workflow contract tests: 0 passed, 1 failed' -ForegroundColor Red
    Write-Host 'FAILED' -ForegroundColor Red
    exit 1
}

$packageJsonText = Get-CiWorkflowText -Path $packageJsonPath

$gitleaksConfigPath = Join-Path $repoRoot '.gitleaks.toml'
if (-not (Test-Path -LiteralPath $gitleaksConfigPath)) {
    Write-Host ("FAIL: missing Gitleaks config '{0}'." -f $gitleaksConfigPath) -ForegroundColor Red
    exit 1
}
$gitleaksConfigText = Get-CiWorkflowText -Path $gitleaksConfigPath

Write-Host '-> Triggers' -ForegroundColor Cyan
try { Invoke-TriggerTests -Text $workflowText } catch { Write-Fail ('Trigger suite threw: ' + $_.Exception.Message) }

Write-Host '-> Permissions' -ForegroundColor Cyan
try { Invoke-PermissionTests -Text $workflowText } catch { Write-Fail ('Permission suite threw: ' + $_.Exception.Message) }

Write-Host '-> Concurrency' -ForegroundColor Cyan
try { Invoke-ConcurrencyTests -Text $workflowText } catch { Write-Fail ('Concurrency suite threw: ' + $_.Exception.Message) }

Write-Host '-> Action pins' -ForegroundColor Cyan
try { Invoke-ActionPinTests -Text $workflowText } catch { Write-Fail ('Action pin suite threw: ' + $_.Exception.Message) }

Write-Host '-> Official actions' -ForegroundColor Cyan
try { Invoke-OfficialActionTests -Text $workflowText } catch { Write-Fail ('Official action suite threw: ' + $_.Exception.Message) }

Write-Host '-> Job coverage' -ForegroundColor Cyan
try { Invoke-JobCoverageTests -Text $workflowText } catch { Write-Fail ('Job coverage suite threw: ' + $_.Exception.Message) }

Write-Host '-> Production release' -ForegroundColor Cyan
try { Invoke-ProductionReleaseTests -Text $productionReleaseWorkflowText } catch { Write-Fail ('Production release suite threw: ' + $_.Exception.Message) }

Write-Host '-> uv safety' -ForegroundColor Cyan
try { Invoke-UvFrozenTests -Text $workflowText } catch { Write-Fail ('uv suite threw: ' + $_.Exception.Message) }

Write-Host '-> Secret embedding' -ForegroundColor Cyan
try { Invoke-SecretEmbeddingTests -Text $workflowText } catch { Write-Fail ('secret suite threw: ' + $_.Exception.Message) }

Write-Host '-> Gitleaks config' -ForegroundColor Cyan
try { Invoke-GitleaksConfigTests -Text $gitleaksConfigText } catch { Write-Fail ('Gitleaks config suite threw: ' + $_.Exception.Message) }

Write-Host '-> npm/Firebase toolchain' -ForegroundColor Cyan
try {
    Invoke-NpmFirebaseToolchainTests `
        -WorkflowText $workflowText `
        -PackageJsonText $packageJsonText
} catch {
    Write-Fail ('npm/Firebase toolchain suite threw: ' + $_.Exception.Message)
}

$total = $script:PassedCount + $script:FailedCount
Write-Host ''
Write-Host ("CI workflow contract tests: {0} passed, {1} failed (of {2})" -f $script:PassedCount, $script:FailedCount, $total)

if ($script:FailedCount -gt 0) {
    Write-Host 'FAILED' -ForegroundColor Red
    exit 1
}

Write-Host 'PASS' -ForegroundColor Green
exit 0
