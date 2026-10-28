#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$verifierPath = Join-Path $repoRoot 'tool\cli\verify-public-release-pages.ps1'
$failed = 0
$passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        $script:passed++
        Write-Host "PASS - $Message"
    } else {
        $script:failed++
        Write-Host "FAIL - $Message" -ForegroundColor Red
    }
}

function Invoke-Verifier {
    param([string[]]$ExtraArguments = @())
    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    $arguments = @('-NoProfile', '-File', $verifierPath) + $ExtraArguments
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # An expected child rejection is an exit code, including on Windows PowerShell.
        $ErrorActionPreference = 'Continue'
        $output = & $pwsh @arguments 2>&1
        $verifierExitCode = [int]$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    return [pscustomobject]@{
        ExitCode = $verifierExitCode
        Output = ($output -join "`n")
    }
}

Assert-True (Test-Path -LiteralPath $verifierPath -PathType Leaf) `
    'public release page verifier exists'

if (Test-Path -LiteralPath $verifierPath -PathType Leaf) {
    $source = [System.IO.File]::ReadAllText($verifierPath)
    Assert-True ($source -notmatch '\$ContactConfigPath') `
        'contact configuration path cannot be selected by a caller'
    Assert-True ($source -notmatch '\$HostPolicyPath') `
        'trusted host policy path cannot be selected by a caller'

    $trustedPolicyPath = Join-Path $repoRoot `
        'tool\cli\config\release-contact-policy.json'
    $publicPolicyPath = Join-Path $repoRoot `
        'hosting\public\release-contact-policy.json'
    Assert-True (Test-Path -LiteralPath $trustedPolicyPath -PathType Leaf) `
        'trusted contact host policy exists at the pinned repository path'
    Assert-True (
        (Test-Path -LiteralPath $trustedPolicyPath -PathType Leaf) -and
        (Test-Path -LiteralPath $publicPolicyPath -PathType Leaf) -and
        [System.IO.File]::ReadAllText($trustedPolicyPath) -eq
            [System.IO.File]::ReadAllText($publicPolicyPath)
    ) 'deployable policy copy exactly matches the trusted policy'

    $defaultGate = Invoke-Verifier `
        -ExtraArguments @('-RequireReachabilityEvidence')
    Assert-True ($defaultGate.ExitCode -ne 0) `
        'repository production gate stays closed without deployable contact config'
    Assert-True (
        $defaultGate.Output.Contains(
            'PASS - Play Data Safety states Supabase is initialization-only, has no runtime data caller, and remains local-only'
        )
    ) 'verifier enforces the Supabase release boundary in Data Safety'

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
        ('lexiquest-public-pages-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    try {
        $policyPath = Join-Path $tempRoot 'approved-contact-hosts.json'
        $configPath = Join-Path $tempRoot 'release-contact.json'
        [System.IO.File]::WriteAllText(
            $policyPath,
            '{"schemaVersion":1,"privacyNoticeHosts":["vocab-learning-app-219ef.web.app"],"privateSupportHosts":["support.lexiquest.app"],"deletionRequestHosts":["support.lexiquest.app"]}',
            [System.Text.UTF8Encoding]::new($false)
        )
        [System.IO.File]::WriteAllText(
            $configPath,
            '{"schemaVersion":1,"privacyNoticeUrl":"https://vocab-learning-app-219ef.web.app/privacy/","privateSupportUrl":"https://support.lexiquest.app/private-request","deletionRequestUrl":"https://support.lexiquest.app/delete-account","dataControllerName":"Synthetic controller","retentionSummary":"Synthetic retention","reachabilityEvidence":{"verifiedAtUtc":"2026-10-26T00:00:00Z","httpStatus":200,"evidenceRef":"private:synthetic"}}',
            [System.Text.UTF8Encoding]::new($false)
        )
        $overrideAttempt = Invoke-Verifier -ExtraArguments @(
            '-ContactConfigPath', $configPath,
            '-HostPolicyPath', $policyPath,
            '-RequireReachabilityEvidence'
        )
        Assert-True ($overrideAttempt.ExitCode -ne 0) `
            'temporary caller-selected policy and config cannot generate PASS'
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

$checklist = [System.IO.File]::ReadAllText(
    (Join-Path $repoRoot 'docs\store\public-release-checklist.md')
)
Assert-True ($checklist -notmatch '(ContactConfigPath|HostPolicyPath)') `
    'release checklist does not advertise caller-selectable trust paths'

$dataSafety = [System.IO.File]::ReadAllText(
    (Join-Path $repoRoot 'docs\store\play-data-safety.md')
)
Assert-True (
    $dataSafety -match '(?i)initialization[- ]only' -and
    $dataSafety -match '(?i)no runtime data caller' -and
    $dataSafety -match '(?i)local-only even when' -and
    $dataSafety -notmatch '(?i)Supabase is used only for public marketplace image reads'
) 'Play Data Safety matches the source-grounded Supabase inventory'

Write-Host "Public release page tests: $passed passed, $failed failed"
if ($failed -gt 0) { exit 1 }
Write-Host 'PASS'
exit 0
