#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the bounded P8-C session voice mirror release gate.

.DESCRIPTION
    Verifies the participant-transient voice mirror: backend mirror sessions,
    VoxCPM2 mirror engine, Flutter gateway/controller/recorder, provider and
    factory wiring, the Shadowing Challenge consent journey, privacy boundary
    scans, and an Android debug build. Every phase runs exactly once in
    sequence. The first failed phase stops the gate; no command is retried
    automatically.
#>
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Repository-root resolution: cli -> tool -> repo root.
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$phases = @(
    @{
        Name = 'Dart format'
        Action = {
            # Contract marker: dart format --output=none --set-exit-if-changed
            & dart format --output=none --set-exit-if-changed @(
                'lib/voice',
                'lib/runtime',
                'lib/screens/shadowing_challenge_screen.dart',
                'test/voice',
                'test/screens/shadowing_challenge_screen_test.dart'
            )
        }.GetNewClosure()
    },
    @{
        Name = 'Static analysis'
        Action = {
            # Contract marker: flutter analyze
            & flutter analyze
        }.GetNewClosure()
    },
    @{
        Name = 'Focused Flutter voice tests'
        Action = {
            # Contract marker: flutter test
            & flutter test @(
                'test/voice/voice_mirror_gateway_test.dart',
                'test/voice/voice_mirror_session_controller_test.dart',
                'test/voice/voice_mirror_recorder_test.dart',
                'test/voice/vox_cpm_mirror_provider_test.dart',
                'test/voice/voice_service_factory_test.dart',
                'test/voice/voice_policy_test.dart',
                'test/voice/voice_orchestrator_test.dart'
            ) --reporter compact
        }.GetNewClosure()
    },
    @{
        Name = 'Shadowing challenge consent journey'
        Action = {
            & flutter test @(
                'test/screens/shadowing_challenge_screen_test.dart'
            ) --reporter compact
        }.GetNewClosure()
    },
    @{
        Name = 'Runtime bootstrap tests'
        Action = {
            & flutter test @(
                'test/runtime'
            ) --reporter compact
        }.GetNewClosure()
    },
    @{
        Name = 'Backend voice API tests'
        Action = {
            Push-Location -LiteralPath 'backend/voice_api'
            try {
                # Contract marker: uv lock --check
                & uv lock --check
                if ($LASTEXITCODE -ne 0) {
                    return
                }
                # Contract marker: uv run --group dev pytest -q
                & uv run --group dev pytest -q
            }
            finally {
                Pop-Location
            }
        }.GetNewClosure()
    },
    @{
        Name = 'Privacy boundary scan'
        Action = {
            # No audio/session/voiceprint may enter Drift persistence or sync.
            # git grep exits 1 when there are no matches, which is the desired
            # privacy outcome; any other failure fails the phase.
            $localMatch = & git grep -n -i -E 'voice_mirror|mirror_session|referenceAudio|voiceprint' `
                -- 'lib/data/local' 'lib/features/sync'
            $localExit = $LASTEXITCODE
            if ($localExit -eq 0 -and $localMatch) {
                throw "Mirror/private data found in persistence: $localMatch"
            }
            if ($localExit -ne 0 -and $localExit -ne 1) {
                throw "git grep failed with exit $localExit"
            }
            # Mirror output must never be cached.
            $mirrorProvider = Get-Content -LiteralPath `
                'lib/voice/vox_cpm_mirror_provider.dart' -Raw -Encoding utf8
            if (-not $mirrorProvider.Contains('allowsStandardCache: false')) {
                throw 'Mirror provider must forbid standard cache.'
            }
            # No session identifier, token, or raw audio may be logged.
            $logMatch = & git grep -n -E 'print\(|debugPrint\(' `
                -- 'lib/voice/voice_mirror_gateway.dart' `
                'lib/voice/voice_mirror_session_controller.dart' `
                'lib/voice/voice_mirror_recorder.dart' `
                'lib/voice/vox_cpm_mirror_provider.dart'
            $logExit = $LASTEXITCODE
            if ($logExit -eq 0 -and $logMatch) {
                throw "Raw logging found in mirror boundary: $logMatch"
            }
            if ($logExit -ne 0 -and $logExit -ne 1) {
                throw "git grep failed with exit $logExit"
            }
            # All privacy checks passed; reset the exit code so the phase is
            # recorded as success even though git grep returned "no matches".
            $global:LASTEXITCODE = 0
        }.GetNewClosure()
    },
    @{
        Name = 'Android debug APK'
        Action = {
            # Contract marker: flutter build apk --debug
            & flutter build apk --debug `
                --dart-define=LEXIQUEST_VERSION=1.0.0+p8c `
                --dart-define=LEXIQUEST_BUILD_ID=p8c-session-voice-mirror
        }.GetNewClosure()
    },
    @{
        Name = 'Whitespace and conflict markers'
        Action = {
            # Contract marker: git diff --check
            & git diff --check
        }.GetNewClosure()
    }
)

$results = New-Object System.Collections.Generic.List[object]
$failedPhase = $null
$failedExitCode = 0

Push-Location -LiteralPath $repoRoot
try {
    foreach ($phase in $phases) {
        $phaseError = $null
        try {
            & $phase.Action
            $code = [int]$LASTEXITCODE
        }
        catch {
            $phaseError = $_
            $code = 1
        }
        $results.Add([pscustomobject]@{ Name = $phase.Name; ExitCode = $code })
        if ($code -ne 0) {
            $failedPhase = $phase.Name
            $failedExitCode = $code
            if ($null -ne $phaseError) {
                Write-Host $phaseError.ToString() -ForegroundColor Red
            }
            break
        }
    }
}
finally {
    Pop-Location
}

if ($null -ne $failedPhase) {
    Write-Host 'LexiQuest P8-C session voice mirror gate: FAIL' -ForegroundColor Red
    foreach ($result in $results) {
        if ($result.ExitCode -ne 0) {
            Write-Host ('  {0}: FAIL (exit {1})' -f $result.Name, $result.ExitCode) -ForegroundColor Red
        }
    }
    $exitCode = if ($failedExitCode -ne 0) { $failedExitCode } else { 1 }
    exit $exitCode
}

Write-Host 'LexiQuest P8-C session voice mirror gate: PASS' -ForegroundColor Green
foreach ($result in $results) {
    Write-Host ('  {0}: PASS' -f $result.Name) -ForegroundColor Green
}
exit 0
