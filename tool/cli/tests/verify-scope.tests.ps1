#Requires -Version 5.1
<#
.SYNOPSIS
    Dependency-free contract tests for the scoped verification runner.

.DESCRIPTION
    Keeps the anti-loop verification contract stable without launching Flutter,
    backend suites, Android builds, a network service, or a GPU consumer.
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

function Get-NormalizedText {
    param([string]$Path)
    $raw = [System.IO.File]::ReadAllText($Path)
    return (($raw -replace "`r`n", "`n") -replace "`r", "`n")
}

$repoToolCli = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path (Split-Path $repoToolCli -Parent) -Parent
$scopePath = Join-Path $repoToolCli 'verify-scope.ps1'
$verifyPath = Join-Path $repoToolCli 'verify.ps1'
$workflowPath = Join-Path $repoRoot '.github\workflows\ci.yml'

if (-not (Test-Path -LiteralPath $scopePath)) {
    Write-Fail 'verify-scope.ps1 exists'
    $scopeText = ''
} else {
    Write-Pass 'verify-scope.ps1 exists'
    $scopeText = Get-NormalizedText -Path $scopePath
}

$verifyText = Get-NormalizedText -Path $verifyPath
$workflowText = Get-NormalizedText -Path $workflowPath

Assert-RegexMatches $scopeText '\[ValidateSet\(''Targeted'',[ \t]*''Subsystem'',[ \t]*''Release''\)\]' 'level is a closed three-value contract'
Assert-RegexMatches $scopeText '\[ValidateSet\([^\]]*''Learning''[^\]]*''AI''[^\]]*''Voice''[^\]]*''Economy''[^\]]*''Runtime''[^\]]*''BackendAI''[^\]]*''BackendVoice''[^\]]*''BackendLM''[^\]]*''All''[^\]]*\)\]' 'area contract covers every planned subsystem'
Assert-ContainsString $scopeText '[switch]$Resume' 'resume is an explicit switch'
Assert-ContainsString $scopeText '[string]$BaseSha' 'base SHA is an explicit input'
Assert-RegexMatches $scopeText 'Targeted[ \t]*=[ \t]*600' 'targeted timeout is ten minutes'
Assert-RegexMatches $scopeText 'Subsystem[ \t]*=[ \t]*1200' 'subsystem timeout is twenty minutes'
Assert-RegexMatches $scopeText 'Release[ \t]*=[ \t]*2700' 'release timeout is forty-five minutes'
Assert-ContainsString $scopeText 'build\verification' 'results are stored below build/verification'
Assert-ContainsString $scopeText 'Get-FileHash' 'source fingerprints include file content hashes'
Assert-ContainsString $scopeText 'fingerprint' 'result records carry a source fingerprint'
Assert-ContainsString $scopeText 'headSha' 'result records carry the current commit SHA'
Assert-ContainsString $scopeText 'commandKey' 'resume decisions are command-scoped'
Assert-ContainsString $scopeText 'SourceArea' 'each command declares its own fingerprint boundary'
Assert-ContainsString $scopeText "PSObject.Properties['fingerprint']" 'resume tolerates result files written by the earlier schema'
Assert-RegexMatches $scopeText '(?s)\$previousCommand\.fingerprint[ \t]*-eq[ \t]*\$commandFingerprint' 'resume skips only a command with an unchanged command fingerprint'
Assert-ContainsString $scopeText 'TimedOut' 'timed-out commands are recorded distinctly'
Assert-ContainsString $scopeText '-EncodedCommand' 'commands run through an exit-code-preserving PowerShell wrapper'
Assert-ContainsString $scopeText '-ExecutionPolicy Bypass' 'bounded commands can invoke signed workspace command shims'
Assert-ContainsString $scopeText '$LASTEXITCODE' 'the wrapper returns the native command exit code'
Assert-ContainsString $scopeText '`$ErrorActionPreference = ''Continue''' 'native stderr does not terminate a successful command'
Assert-ContainsString $scopeText '`$commandSucceeded = `$?' 'the wrapper records PowerShell command resolution failures'
Assert-ContainsString $scopeText 'System.Diagnostics.ProcessStartInfo' 'bounded execution uses the .NET process API'
Assert-ContainsString $scopeText 'UseShellExecute = $false' 'bounded execution retains a queryable process handle'
Assert-ContainsString $scopeText 'RedirectStandardError = $true' 'wrapper errors are captured for diagnosis'
Assert-ContainsString $scopeText 'StandardError.ReadToEnd()' 'captured wrapper errors are persisted'
Assert-RegexNotMatches $scopeText '(?m)^[ \t]*\$process[ \t]*=[ \t]*Start-Process\b' 'bounded execution does not use Start-Process exit-code semantics'
Assert-RegexMatches $scopeText '(?s)\$finished[ \t]*=[^\n]*WaitForExit\([^\n]+\).*?\$process\.WaitForExit\(\).*?\$process\.Refresh\(\).*?\$process\.ExitCode' 'completed processes refresh their exit code before classification'
Assert-ContainsString $scopeText 'verify.ps1' 'release profile delegates to the canonical full verifier'
Assert-RegexNotMatches $scopeText '(?i)\b(retry|attempts?|maxRetries)\b' 'runner contains no automatic retry loop'
Assert-ContainsString $scopeText "-ExcludedGroup 'gpu'" 'voice backend checks exclude GPU dependencies'
Assert-ContainsString $scopeText "-AdditionalPytestArguments @('--ignore', 'backend\voice_api\tests\integration')" 'voice backend checks exclude live integration tests'
Assert-ContainsString $scopeText "'test\screens\quiz_score_persistence_regression_test.dart'" 'economy scope includes the client-writer regression contract'
Assert-ContainsString $scopeText "-FilePath 'npm'" 'economy scope can invoke npm'
Assert-ContainsString $scopeText "-Arguments @('--prefix', 'functions', 'test')" 'economy scope includes trusted writer tests'
Assert-ContainsString $verifyText "'verify-scope.tests.ps1'," 'full verification runs the scoped-runner contract'
Assert-ContainsString $verifyText '$env:LEXIQUEST_SUPABASE_PUBLISHABLE_KEY' 'release verification reads the Supabase publishable key from the environment'
Assert-ContainsString $verifyText 'Get-RequiredSupabasePublishableKey' 'release verification rejects a missing or malformed Supabase publishable key'
Assert-ContainsString $verifyText '--dart-define=LEXIQUEST_SUPABASE_PUBLISHABLE_KEY=' 'release build injects the Supabase publishable key'
Assert-ContainsString $workflowText './tool/cli/tests/verify-scope.tests.ps1' 'CI runs the scoped-runner contract'

$total = $script:PassedCount + $script:FailedCount
Write-Host ''
Write-Host (
    'Scoped verification contract tests: {0} passed, {1} failed (of {2})' -f
    $script:PassedCount,
    $script:FailedCount,
    $total
)
if ($script:FailedCount -gt 0) {
    Write-Host 'FAILED' -ForegroundColor Red
    exit 1
}

Write-Host 'PASS' -ForegroundColor Green
exit 0
