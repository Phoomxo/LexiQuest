#Requires -Version 5.1
<#
.SYNOPSIS
    CPU-safe LexiQuest production-foundation verification.

.DESCRIPTION
    Runs every mandatory foundation check fail-fast. It never starts Voice API,
    AI API, Ollama, OmniVoice, a local LM server, model loading, or another CUDA
    consumer. Backend tests reuse the installed project environments without
    syncing optional GPU/training dependency groups.
#>
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$script:phaseResults = @()

function Write-VerifySummary {
    param([string]$Title)

    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    foreach ($result in $script:phaseResults) {
        $status = if ([int]$result.Code -eq 0) {
            'PASS'
        } else {
            'FAIL exit ' + [int]$result.Code
        }
        $color = if ([int]$result.Code -eq 0) { 'Green' } else { 'Red' }
        Write-Host ('  {0}. {1} [{2}]' -f $result.Number, $result.Name, $status) -ForegroundColor $color
    }
}

function Invoke-VerifyPhase {
    param(
        [string]$Number,
        [string]$Name,
        [scriptblock]$Body
    )

    Write-Host ''
    Write-Host ('[{0}] {1}' -f $Number, $Name) -ForegroundColor Cyan
    $exitCode = 0
    $global:LASTEXITCODE = 0
    try {
        & $Body
        $exitCode = [int]$global:LASTEXITCODE
    } catch {
        Write-Host ('  {0}' -f $_.Exception.Message) -ForegroundColor Red
        $recordedCode = $_.Exception.Data['LexiQuestExitCode']
        $exitCode = if ($null -ne $recordedCode) {
            [int]$recordedCode
        } else {
            1
        }
    }

    $script:phaseResults += [pscustomobject]@{
        Number = $Number
        Name = $Name
        Code = $exitCode
    }
    if ($exitCode -ne 0) {
        Write-VerifySummary -Title 'LexiQuest verification: FAIL'
        exit $exitCode
    }
    Write-Host '  PASS' -ForegroundColor Green
}

$requiredTools = @('git', 'flutter', 'dart', 'uv', 'powershell')
$missingTools = @()
foreach ($toolName in $requiredTools) {
    if ($null -eq (Get-Command -Name $toolName -ErrorAction SilentlyContinue)) {
        $missingTools += $toolName
    }
}
if ($missingTools.Count -gt 0) {
    Write-Host ('Missing required tools: {0}' -f ($missingTools -join ', ')) -ForegroundColor Red
    exit 1
}

Push-Location -LiteralPath $repoRoot
try {
    Invoke-VerifyPhase '01' 'Protected runtime probe tests' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File `
            (Join-Path $scriptDir 'tests\runtime-probes.tests.ps1')
    }

    Invoke-VerifyPhase '02' 'Android command construction tests' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File `
            (Join-Path $scriptDir 'tests\run-android.tests.ps1')
    }

    Invoke-VerifyPhase '02.1' 'CI/CD contract tests' {
        $contractTests = @(
            'ci-workflow.tests.ps1',
            'dependabot-config.tests.ps1',
            'osv-pr-workflow.tests.ps1',
            'osv-scheduled-workflow.tests.ps1',
            'osv-config.tests.ps1',
            'firebase-seed-security.tests.ps1',
            'firestore-rules-security.tests.ps1',
            'model-loading-security.tests.ps1',
            'android-manifest-security.tests.ps1',
            'android-release-signing.tests.ps1',
            'verify-field-release.tests.ps1'
        )
        foreach ($contractTest in $contractTests) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File `
                (Join-Path $scriptDir ('tests\' + $contractTest))
            $contractExitCode = [int]$LASTEXITCODE
            if ($contractExitCode -ne 0) {
                $exception = New-Object System.Exception(
                    ('Contract test failed: {0}' -f $contractTest)
                )
                $exception.Data['LexiQuestExitCode'] = $contractExitCode
                throw $exception
            }
        }
    }

    Invoke-VerifyPhase '03' 'Flutter dependency resolution' {
        & flutter pub get
    }

    Invoke-VerifyPhase '04' 'Dart format check (tracked sources only)' {
        $trackedDart = @(
            & git ls-files -- '*.dart' |
                Where-Object {
                    $_ -and
                    ($_ -notmatch '(^|/)(build|\.dart_tool|generated|vendor|checkpoints?)(/|$)')
                }
        )
        if ($trackedDart.Count -eq 0) {
            throw 'No tracked Dart sources were found.'
        }
        $batchSize = 40
        for ($offset = 0; $offset -lt $trackedDart.Count; $offset += $batchSize) {
            $lastIndex = [Math]::Min($offset + $batchSize - 1, $trackedDart.Count - 1)
            $batch = @($trackedDart[$offset..$lastIndex])
            & dart format --output=none --set-exit-if-changed $batch
            $batchExitCode = [int]$LASTEXITCODE
            if ($batchExitCode -ne 0) {
                $exception = New-Object System.Exception(
                    'Dart format check failed for tracked source batch.'
                )
                $exception.Data['LexiQuestExitCode'] = $batchExitCode
                throw $exception
            }
        }
    }

    Invoke-VerifyPhase '05' 'Flutter static analysis' {
        & flutter analyze
    }

    Invoke-VerifyPhase '06' 'Flutter unit and widget tests' {
        & flutter test --reporter compact
    }

    Invoke-VerifyPhase '07' 'Voice API CPU-only tests' {
        & uv run `
            --project (Join-Path $repoRoot 'backend\voice_api') `
            --frozen `
            --no-sync `
            --group dev `
            pytest backend/voice_api/tests -q `
            --ignore=backend/voice_api/tests/integration
    }

    Invoke-VerifyPhase '08' 'AI API CPU-only tests' {
        & uv run `
            --project (Join-Path $repoRoot 'backend\ai_api') `
            --frozen `
            --no-sync `
            --group dev `
            pytest backend/ai_api/tests -q
    }

    Invoke-VerifyPhase '09' 'Local LM CPU-only tests' {
        & uv run `
            --project (Join-Path $repoRoot 'backend\lexiquest_lm') `
            --frozen `
            --no-sync `
            --group dev `
            pytest backend/lexiquest_lm/tests -q
    }

    Invoke-VerifyPhase '10' 'Android debug APK build (emulator loopback)' {
        $shortSha = (& git rev-parse --short HEAD 2>$null | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($shortSha)) {
            $shortSha = 'unknown'
        } else {
            $shortSha = $shortSha.Trim()
        }
        $dirtySuffix = ''
        if (-not [string]::IsNullOrWhiteSpace((& git status --porcelain 2>$null))) {
            $dirtySuffix = '-dirty'
        }
        $buildId = $shortSha + $dirtySuffix
        $buildArguments = @(
            'build',
            'apk',
            '--debug',
            '--dart-define=LEXIQUEST_VERSION=1.0.0+1',
            ('--dart-define=LEXIQUEST_BUILD_ID=' + $buildId),
            '--dart-define=LEXIQUEST_VOICE_API_URL=http://10.0.2.2:8001',
            '--dart-define=LEXIQUEST_AI_API_URL=http://10.0.2.2:8000'
        )
        & flutter $buildArguments
    }

    Invoke-VerifyPhase '11' 'Read-only live GPU doctor' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File `
            (Join-Path $scriptDir 'doctor.ps1')
    }
}
finally {
    Pop-Location
}

Write-VerifySummary -Title 'LexiQuest verification: PASS'
exit 0
