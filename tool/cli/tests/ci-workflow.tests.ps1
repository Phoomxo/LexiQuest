#Requires -Version 5.1
<#
.SYNOPSIS
    Dependency-free contract test for the LexiQuest GitHub Actions CI workflow.

.DESCRIPTION
    Validates triggers, least-privilege permissions, concurrency cancellation,
    immutable action pins, CPU-only verification coverage, frozen uv commands,
    and the absence of embedded secrets. The workflow is read as normalized raw
    text, so YAML indentation and CRLF/LF line endings do not affect the checks.

    RED state: .github/workflows/ci.yml does not exist yet, so the runner fails
    fast with a non-zero exit code before any assertion runs.
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

function Invoke-JobCoverageTests {
    param([string]$Text)
    Assert-ContainsString $Text 'flutter pub get' 'job resolves Flutter dependencies'
    Assert-ContainsString $Text 'git ls-files' 'format check selects tracked sources'
    Assert-ContainsString $Text 'dart format' 'job checks tracked Dart formatting'
    Assert-ContainsString $Text '--set-exit-if-changed' 'format check fails on changes'
    Assert-ContainsString $Text 'flutter analyze' 'job runs flutter analyze'
    Assert-ContainsString $Text 'flutter test' 'job runs flutter test'
    Assert-ContainsString $Text 'pytest' 'backend suites run via pytest'
    Assert-ContainsString $Text 'voice_api' 'job covers backend/voice_api CPU tests'
    Assert-ContainsString $Text 'ai_api' 'job covers backend/ai_api CPU tests'
    Assert-ContainsString $Text 'lexiquest_lm' 'job covers backend/lexiquest_lm CPU tests'
    Assert-ContainsString $Text 'runtime-probes.tests.ps1' 'job runs runtime probe tests'
    Assert-ContainsString $Text 'run-android.tests.ps1' 'job runs Android command tests'
    Assert-ContainsString $Text 'flutter build' 'job builds the Android app'
    Assert-ContainsString $Text 'apk' 'Android build produces an APK'
    Assert-ContainsString $Text '--debug' 'Android build is a debug build'
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

$repoToolCli = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path (Split-Path $repoToolCli -Parent) -Parent
$workflowPath = Join-Path $repoRoot (Join-Path '.github' (Join-Path 'workflows' 'ci.yml'))

if (-not (Test-Path -LiteralPath $workflowPath)) {
    Write-Host ("FAIL: missing CI workflow '{0}'." -f $workflowPath) -ForegroundColor Red
    Write-Host 'CI workflow contract tests: 0 passed, 1 failed' -ForegroundColor Red
    Write-Host 'FAILED' -ForegroundColor Red
    exit 1
}

$workflowText = Get-CiWorkflowText -Path $workflowPath

Write-Host '-> Triggers' -ForegroundColor Cyan
try { Invoke-TriggerTests -Text $workflowText } catch { Write-Fail ('Trigger suite threw: ' + $_.Exception.Message) }

Write-Host '-> Permissions' -ForegroundColor Cyan
try { Invoke-PermissionTests -Text $workflowText } catch { Write-Fail ('Permission suite threw: ' + $_.Exception.Message) }

Write-Host '-> Concurrency' -ForegroundColor Cyan
try { Invoke-ConcurrencyTests -Text $workflowText } catch { Write-Fail ('Concurrency suite threw: ' + $_.Exception.Message) }

Write-Host '-> Action pins' -ForegroundColor Cyan
try { Invoke-ActionPinTests -Text $workflowText } catch { Write-Fail ('Action pin suite threw: ' + $_.Exception.Message) }

Write-Host '-> Job coverage' -ForegroundColor Cyan
try { Invoke-JobCoverageTests -Text $workflowText } catch { Write-Fail ('Job coverage suite threw: ' + $_.Exception.Message) }

Write-Host '-> uv safety' -ForegroundColor Cyan
try { Invoke-UvFrozenTests -Text $workflowText } catch { Write-Fail ('uv suite threw: ' + $_.Exception.Message) }

Write-Host '-> Secret embedding' -ForegroundColor Cyan
try { Invoke-SecretEmbeddingTests -Text $workflowText } catch { Write-Fail ('secret suite threw: ' + $_.Exception.Message) }

$total = $script:PassedCount + $script:FailedCount
Write-Host ''
Write-Host ("CI workflow contract tests: {0} passed, {1} failed (of {2})" -f $script:PassedCount, $script:FailedCount, $total)

if ($script:FailedCount -gt 0) {
    Write-Host 'FAILED' -ForegroundColor Red
    exit 1
}

Write-Host 'PASS' -ForegroundColor Green
exit 0
