#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) { $script:Passed++ } else {
        $script:Failed++
        Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
    }
}

function Assert-NoMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) {
        $script:Failed++
        Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
    } else { $script:Passed++ }
}

$repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$workflowPath = Join-Path $repoRoot '.github\workflows\production-release.yml'
if (-not (Test-Path -LiteralPath $workflowPath)) {
    Write-Host "FAIL: missing $workflowPath" -ForegroundColor Red
    exit 1
}
$text = ([System.IO.File]::ReadAllText($workflowPath) -replace "`r`n", "`n") -replace "`r", "`n"

Assert-Match $text '(?m)^[ \t]*workflow_dispatch[ \t]*:' 'release requires an explicit workflow dispatch'
Assert-NoMatch $text '(?m)^[ \t]*(pull_request|push)[ \t]*:' 'release never runs from pull requests or pushes'
Assert-Match $text '(?m)^[ \t]*environment[ \t]*:[ \t]*production[ \t]*$' 'release uses the protected production environment'
Assert-Match $text '(?m)^[ \t]*contents[ \t]*:[ \t]*read[ \t]*$' 'release uses read-only repository contents permission'
Assert-Match $text '(?m)^[ \t]*cancel-in-progress[ \t]*:[ \t]*false[ \t]*$' 'an active production release is never cancelled by another run'
Assert-Match $text 'secrets\.ANDROID_RELEASE_KEYSTORE_BASE64' 'keystore is read from a protected secret'
Assert-Match $text 'secrets\.ANDROID_RELEASE_STORE_PASSWORD' 'store password is read from a protected secret'
Assert-Match $text 'secrets\.ANDROID_RELEASE_KEY_ALIAS' 'key alias is read from a protected secret'
Assert-Match $text 'secrets\.ANDROID_RELEASE_KEY_PASSWORD' 'key password is read from a protected secret'
Assert-Match $text 'flutter build appbundle --release' 'workflow builds a production AAB'
Assert-Match $text 'jarsigner -verify -verbose -certs' 'workflow verifies the signed AAB'
Assert-Match $text 'grep -q "jar verified."' 'workflow rejects unsigned AABs'
Assert-Match $text 'mkdir -p build/sbom' 'workflow prepares the SBOM output directory'
Assert-Match $text 'anchore/sbom-action@e22c389904149dbc22b58101806040fa8d37a610' 'SBOM generator is pinned'
Assert-Match $text 'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a' 'artifact upload is pinned'
Assert-Match $text 'production-aab\.cdx\.json' 'production AAB SBOM is retained'
Assert-Match $text 'source\.cdx\.json' 'source SBOM is retained'
Assert-Match $text 'test -n "\$\{LEXIQUEST_VOICE_API_URL\}"' 'production release requires a voice endpoint'
Assert-Match $text 'test -n "\$\{LEXIQUEST_AI_API_URL\}"' 'production release requires a generated-content endpoint'
Assert-Match $text "parsed\.scheme != 'https'" 'production release requires the exact HTTPS scheme'
Assert-Match $text 'not parsed\.netloc' 'production release requires endpoint authority'
Assert-Match $text 'not parsed\.hostname' 'production release requires a non-empty endpoint host'
Assert-Match $text 'parsed\.username is not None' 'production release rejects endpoint usernames'
Assert-Match $text 'parsed\.password is not None' 'production release rejects endpoint passwords'
Assert-Match $text "'@' in parsed\.netloc" 'production release rejects endpoint userinfo'
Assert-Match $text "'\?' in raw" 'production release rejects endpoint queries'
Assert-Match $text "'#' in raw" 'production release rejects endpoint fragments'
Assert-Match $text "parsed\.path not in \('', '/'\)" 'production release accepts only origin paths'
Assert-Match $text '"--dart-define=LEXIQUEST_VERSION=0\.1\.0\+1"' 'production release quotes the version define'
Assert-Match $text '"--dart-define=LEXIQUEST_BUILD_ID=\$\{LEXIQUEST_BUILD_ID\}"' 'production release quotes the build ID define'
Assert-Match $text '"--dart-define=LEXIQUEST_VOICE_API_URL=\$\{LEXIQUEST_VOICE_API_URL\}"' 'production release quotes the voice URL define'
Assert-Match $text '"--dart-define=LEXIQUEST_AI_API_URL=\$\{LEXIQUEST_AI_API_URL\}"' 'production release quotes the AI URL define'
Assert-Match $text 'rm -f android/key\.properties' 'temporary signing properties are removed'
Assert-Match $text 'rm -f "\$\{RUNNER_TEMP\}/lexiquest-release\.jks"' 'temporary keystore is removed'
Assert-NoMatch $text '-----BEGIN[ A-Z]*PRIVATE KEY-----' 'workflow contains no embedded private key'
Assert-NoMatch $text '(?m)^[ \t]*(storePassword|keyPassword)[ \t]*=[ \t]*[^$]' 'workflow contains no embedded production password'

$uses = [regex]::Matches($text, '(?m)^[ \t]*-?[ \t]*uses[ \t]*:[ \t]*(\S+)')
foreach ($match in $uses) {
    $reference = $match.Groups[1].Value.Trim('"').Trim("'")
    if ($reference -cmatch '^[A-Za-z0-9._/-]+@[0-9A-Fa-f]{40}$') {
        $script:Passed++
    } else {
        $script:Failed++
        Write-Host ('  [FAIL] unpinned action: ' + $reference) -ForegroundColor Red
    }
}

Write-Host ("Production release workflow tests: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
