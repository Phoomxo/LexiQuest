#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$RequireReachabilityEvidence
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failed = 0
$passed = 0

function Assert-ReleaseContract {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        $script:passed++
        Write-Host "PASS - $Message"
    } else {
        $script:failed++
        Write-Host "FAIL - $Message" -ForegroundColor Red
    }
}

function Read-RepoFile {
    param([string]$RelativePath)
    $path = Join-Path $repoRoot $RelativePath
    Assert-ReleaseContract (Test-Path -LiteralPath $path -PathType Leaf) `
        "required file exists: $RelativePath"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    return [System.IO.File]::ReadAllText($path)
}

function Test-ReleaseUrl {
    param(
        [object]$Value,
        [string[]]$ApprovedHosts,
        [string]$ExpectedPath = ''
    )
    if ($Value -isnot [string]) { return $false }
    $uri = $null
    if (-not [uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri)) {
        return $false
    }
    if ($uri.Scheme -ne 'https') { return $false }
    if (
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment) -or
        -not $uri.IsDefaultPort
    ) {
        return $false
    }
    $decodedPath = $uri.AbsolutePath
    try {
        foreach ($iteration in 1..2) {
            $nextPath = [uri]::UnescapeDataString($decodedPath)
            if ($nextPath -eq $decodedPath) { break }
            $decodedPath = $nextPath
        }
    }
    catch {
        return $false
    }
    if ($decodedPath -match '(?i)(token|secret|api[-_]?key|password)') {
        return $false
    }
    if ($ApprovedHosts -notcontains $uri.IdnHost.ToLowerInvariant()) {
        return $false
    }
    return [string]::IsNullOrEmpty($ExpectedPath) -or
        $uri.AbsolutePath -eq $ExpectedPath
}

$pages = [ordered]@{
    'hosting/public/privacy/index.html' = @(
        'Privacy notice',
        'What we process',
        'Your choices and data rights',
        '/release-contact.json',
        '/release-contact-policy.json',
        'rel="canonical"'
    )
    'hosting/public/delete-account/index.html' = @(
        'Delete account',
        'How to request deletion',
        'What deletion covers',
        'deletionRequestUrl',
        '/release-contact-policy.json',
        'rel="canonical"'
    )
    'hosting/public/field-support/index.html' = @(
        'Support',
        'Public reports',
        'Private support',
        'privateSupportUrl',
        '/release-contact-policy.json',
        'rel="canonical"'
    )
}

foreach ($entry in $pages.GetEnumerator()) {
    $html = Read-RepoFile $entry.Key
    if ([string]::IsNullOrEmpty($html)) { continue }
    Assert-ReleaseContract ($html -match '<html\s+lang="th"') `
        "$($entry.Key) declares Thai as the primary language"
    Assert-ReleaseContract ($html -match 'name="viewport"') `
        "$($entry.Key) is responsive"
    Assert-ReleaseContract ($html -match '<section\s+lang="en"') `
        "$($entry.Key) contains a substantive English section"
    Assert-ReleaseContract (
        $html -notmatch '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
    ) "$($entry.Key) does not publish an email address"
    Assert-ReleaseContract ($html -notmatch '(?i)<OWNER|TBD|PLACEHOLDER') `
        "$($entry.Key) contains no release placeholder"
    foreach ($needle in $entry.Value) {
        Assert-ReleaseContract ($html.Contains($needle)) `
            "$($entry.Key) contains $needle"
    }
}

$deletePage = Read-RepoFile 'hosting/public/delete-account/index.html'
if (-not [string]::IsNullOrEmpty($deletePage)) {
    Assert-ReleaseContract ($deletePage -notmatch '(?i)<form\b') `
        'static deletion page does not collect credentials or personal data'
}

$firebase = Read-RepoFile 'firebase.json'
if (-not [string]::IsNullOrEmpty($firebase)) {
    Assert-ReleaseContract ($firebase.Contains('Content-Security-Policy')) `
        'Firebase Hosting applies a content security policy'
    Assert-ReleaseContract ($firebase.Contains('/release-contact.json')) `
        'owner-supplied contact configuration is never cached'
}

$contactConfigRelative = 'hosting/public/release-contact.json'
$trustedPolicyRelative = 'tool/cli/config/release-contact-policy.json'
$publicPolicyRelative = 'hosting/public/release-contact-policy.json'
$resolvedConfig = Join-Path $repoRoot $contactConfigRelative
$resolvedPolicy = Join-Path $repoRoot $trustedPolicyRelative
$resolvedPublicPolicy = Join-Path $repoRoot $publicPolicyRelative
Assert-ReleaseContract (Test-Path -LiteralPath $resolvedConfig -PathType Leaf) `
    'deployable release contact configuration exists at its fixed path'
Assert-ReleaseContract (Test-Path -LiteralPath $resolvedPolicy -PathType Leaf) `
    'trusted contact host policy exists at its fixed path'
Assert-ReleaseContract (Test-Path -LiteralPath $resolvedPublicPolicy -PathType Leaf) `
    'deployable contact host policy copy exists'
if (
    (Test-Path -LiteralPath $resolvedPolicy -PathType Leaf) -and
    (Test-Path -LiteralPath $resolvedPublicPolicy -PathType Leaf)
) {
    Assert-ReleaseContract (
        [System.IO.File]::ReadAllText($resolvedPolicy) -ceq
        [System.IO.File]::ReadAllText($resolvedPublicPolicy)
    ) 'deployable contact host policy exactly matches the trusted policy'
}

$policy = $null
if (Test-Path -LiteralPath $resolvedPolicy -PathType Leaf) {
    try {
        $policy = Get-Content -LiteralPath $resolvedPolicy -Raw |
            ConvertFrom-Json
        Assert-ReleaseContract ($policy.schemaVersion -eq 1) `
            'contact host policy schema is version 1'
        foreach ($property in @(
            'privacyNoticeHosts',
            'privateSupportHosts',
            'deletionRequestHosts'
        )) {
            $hosts = @($policy.$property)
            Assert-ReleaseContract (
                $hosts.Count -gt 0 -and
                @($hosts | Where-Object {
                    $_ -notmatch `
                        '^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$'
                }).Count -eq 0
            ) "$property contains explicit approved hosts"
        }
    }
    catch {
        Assert-ReleaseContract $false `
            ('contact host policy is valid JSON: ' + $_.Exception.Message)
    }
}

if (
    (Test-Path -LiteralPath $resolvedConfig -PathType Leaf) -and
    $null -ne $policy
) {
    try {
        $config = Get-Content -LiteralPath $resolvedConfig -Raw |
            ConvertFrom-Json
        Assert-ReleaseContract ($config.schemaVersion -eq 1) `
            'contact configuration schema is version 1'
        Assert-ReleaseContract (
            Test-ReleaseUrl $config.privacyNoticeUrl `
                @($policy.privacyNoticeHosts) '/privacy/'
        ) 'privacyNoticeUrl is pinned to the canonical privacy page'
        Assert-ReleaseContract (
            Test-ReleaseUrl $config.privateSupportUrl `
                @($policy.privateSupportHosts)
        ) 'privateSupportUrl is pinned to a repository-approved host'
        Assert-ReleaseContract (
            Test-ReleaseUrl $config.deletionRequestUrl `
                @($policy.deletionRequestHosts)
        ) 'deletionRequestUrl is pinned to a repository-approved host'
        foreach ($property in @('dataControllerName', 'retentionSummary')) {
            $value = [string]$config.$property
            Assert-ReleaseContract (
                -not [string]::IsNullOrWhiteSpace($value) -and
                $value -notmatch '(?i)<OWNER|TBD|PLACEHOLDER' -and
                $value -notmatch `
                    '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
            ) "$property is configured"
        }
        $reachabilityProperty = $config.PSObject.Properties[
            'reachabilityEvidence'
        ]
        $hasReachability = $null -ne $reachabilityProperty
        Assert-ReleaseContract (
            -not $RequireReachabilityEvidence -or $hasReachability
        ) 'reachability evidence is present when required'
        if ($hasReachability) {
            $evidence = $config.reachabilityEvidence
            $verifiedAt = [DateTimeOffset]::MinValue
            $timestampValue = $evidence.verifiedAtUtc
            $timestampText = if ($timestampValue -is [DateTime]) {
                $timestampValue.ToUniversalTime().ToString('o')
            } else {
                [string]$timestampValue
            }
            Assert-ReleaseContract (
                [DateTimeOffset]::TryParse(
                    $timestampText,
                    [ref]$verifiedAt
                ) -and
                (
                    $timestampValue -is [DateTime] -and
                    $timestampValue.Kind -eq [DateTimeKind]::Utc -or
                    $timestampText -match '(Z|\+00:00)$'
                )
            ) 'reachability timestamp is ISO UTC'
            Assert-ReleaseContract (
                [int]$evidence.httpStatus -ge 200 -and
                [int]$evidence.httpStatus -lt 300
            ) 'reachability status is successful'
            $evidenceRef = [string]$evidence.evidenceRef
            Assert-ReleaseContract (
                -not [string]::IsNullOrWhiteSpace($evidenceRef) -and
                $evidenceRef -notmatch '(?i)<OWNER|TBD|PLACEHOLDER|https?://|@'
            ) 'reachability evidence reference is private and non-sensitive'
        }
    }
    catch {
        Assert-ReleaseContract $false `
            ('release contact configuration is valid JSON: ' + `
                $_.Exception.Message)
    }
}

$rollback = Read-RepoFile 'docs/v2-implementation/rollback_playbook.md'
if (-not [string]::IsNullOrEmpty($rollback)) {
    Assert-ReleaseContract ($rollback -match '(?i)schema\s+v10') `
        'rollback playbook targets schema v10'
    Assert-ReleaseContract ($rollback -match '(?i)forward[- ]fix') `
        'rollback playbook uses a forward fix'
    Assert-ReleaseContract ($rollback -notmatch 'schemaVersion\s*=>\s*6') `
        'rollback playbook never instructs a schema downgrade'
}

$firebaseRunbook = Read-RepoFile 'docs/runbooks/firebase-field-operations.md'
if (-not [string]::IsNullOrEmpty($firebaseRunbook)) {
    Assert-ReleaseContract (
        $firebaseRunbook.Contains('noBillingAccount') -and
        $firebaseRunbook.Contains('budgeted')
    ) 'Firebase runbook documents both billing modes'
}

$supabase = Read-RepoFile 'docs/security/supabase-access-inventory.md'
if (-not [string]::IsNullOrEmpty($supabase)) {
    Assert-ReleaseContract (
        $supabase -match '(?i)no runtime data callers' -and
        $supabase -match '(?i)local-only even when'
    ) 'Supabase inventory states initialization-only local behavior'
    Assert-ReleaseContract (
        $supabase.Contains('LEXIQUEST_SUPABASE_PUBLISHABLE_KEY')
    ) 'Supabase inventory names the explicit release key boundary'
}

$allDart = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'lib') `
    -Recurse -File -Filter '*.dart' |
    ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) } |
    Out-String
Assert-ReleaseContract (
    $allDart -notmatch 'Supabase\.instance' -and
    $allDart -notmatch '\.storage\.from\('
) 'Flutter source has no Supabase runtime data caller'

$issueTemplate = Read-RepoFile '.github/ISSUE_TEMPLATE/field-feedback.yml'
if (-not [string]::IsNullOrEmpty($issueTemplate)) {
    Assert-ReleaseContract (
        $issueTemplate -notmatch '(?i)participant_code|pseudonymous participant'
    ) 'public issue template never requests participant linkage'
}

$supportGuide = Read-RepoFile 'docs/field/feedback-and-support.md'
if (-not [string]::IsNullOrEmpty($supportGuide)) {
    Assert-ReleaseContract (
        $supportGuide -notmatch '(?i)รหัสผู้เข้าร่วมแบบนามแฝง|pseudonymous participant'
    ) 'public feedback guidance excludes participant-linked reports'
}

$privacyGuide = Read-RepoFile 'docs/field/privacy-and-consent-v1.md'
$dataSafety = Read-RepoFile 'docs/store/play-data-safety.md'
Assert-ReleaseContract (
    $dataSafety -match '(?i)initialization[- ]only' -and
    $dataSafety -match '(?i)no runtime data caller' -and
    $dataSafety -match '(?i)local-only even when' -and
    $dataSafety -notmatch `
        '(?i)Supabase is used only for public marketplace image reads'
) 'Play Data Safety states Supabase is initialization-only, has no runtime data caller, and remains local-only'
Assert-ReleaseContract (
    $privacyGuide.Contains('onDevice: false') -and
    $dataSafety.Contains('onDevice: false')
) 'privacy and Data Safety disclose platform speech processing'

foreach ($storeFile in @(
    'docs/store/play-data-safety.md',
    'docs/store/play-listing-th.md',
    'docs/store/public-release-checklist.md'
)) {
    [void](Read-RepoFile $storeFile)
}

Write-Host "Public release verifier: $passed passed, $failed failed"
if ($failed -gt 0) { exit 1 }
Write-Host 'PASS'
