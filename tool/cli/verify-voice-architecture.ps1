#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the bounded P8-A voice architecture release gate.

.DESCRIPTION
    Verifies only the provider-neutral voice orchestrator, application voice
    lifecycle, participant screen boundary, affected learning screens, and an
    Android debug build. Each phase runs exactly once, sequentially. The gate
    stops after the first failed phase, prints one phase failure summary, and
    never retries a failed command automatically.
#>
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Repository-root resolution: cli -> tool -> repo root.
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Ordered phases. Each entry is run exactly once, in array order, and the gate
# stops on the first nonzero child exit code without retrying.
$phases = @(
    @{
        Name = 'Dart format'
        Action = {
            # Contract marker: dart format --output=none --set-exit-if-changed
            & dart format --output=none --set-exit-if-changed @(
                'lib/voice',
                'lib/runtime',
                'test/voice'
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
        Name = 'Focused Flutter tests'
        Action = {
            # Contract marker: flutter test
            & flutter test @(
                'test/voice',
                'test/runtime/app_bootstrap_test.dart',
                'test/architecture/participant_screen_boundary_test.dart',
                'test/screens/ai_tutor_screen_test.dart',
                'test/screens/cefr_article_reader_screen_test.dart',
                'test/screens/dictation_quiz_screen_test.dart',
                'test/screens/object_scanner_screen_test.dart',
                'test/screens/phonetic_explorer_screen_test.dart',
                'test/screens/shadowing_challenge_screen_test.dart',
                'test/screens/smart_audio_playlist_screen_test.dart',
                'test/screens/speak_to_text_screen_voice_test.dart',
                'test/screens/sentence_scramble_screen_test.dart',
                'test/screens/srs_flashcards_screen_test.dart'
            ) --reporter compact
        }.GetNewClosure()
    },
    @{
        Name = 'Android debug APK'
        Action = {
            # Contract marker: flutter build apk --debug
            & flutter build apk --debug `
                --dart-define=LEXIQUEST_VERSION=1.0.0+p8a `
                --dart-define=LEXIQUEST_BUILD_ID=p8a-voice-architecture
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
        # Run the phase once. A terminating error (for example a missing
        # dart/flutter/git on PATH) is treated as a failed phase so the gate
        # still fails closed with one concise summary instead of aborting.
        $phaseError = $null
        try {
            & $phase.Action
            $code = [int]$LASTEXITCODE
        }
        catch {
            $phaseError = $_
            # No child process completed; record a nonzero exit code.
            $code = 1
        }
        $results.Add([pscustomobject]@{ Name = $phase.Name; ExitCode = $code })
        if ($code -ne 0) {
            # Stop on first failure: do not run remaining phases or retry.
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

# Fail closed with one concise phase summary when a child process failed.
if ($null -ne $failedPhase) {
    Write-Host 'LexiQuest P8-A voice architecture gate: FAIL' -ForegroundColor Red
    foreach ($result in $results) {
        if ($result.ExitCode -ne 0) {
            Write-Host ('  {0}: FAIL (exit {1})' -f $result.Name, $result.ExitCode) -ForegroundColor Red
        }
    }
    # Preserve the failed child process exit code robustly. Guard against a
    # caller-context $LASTEXITCODE that does not map to the failing phase.
    $exitCode = if ($failedExitCode -ne 0) { $failedExitCode } else { 1 }
    exit $exitCode
}

Write-Host 'LexiQuest P8-A voice architecture gate: PASS' -ForegroundColor Green
foreach ($result in $results) {
    Write-Host ('  {0}: PASS' -f $result.Name) -ForegroundColor Green
}
exit 0
