#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the bounded P8-B hybrid voice release gate.

.DESCRIPTION
    Verifies the provider-neutral Flutter voice path, the backend standard
    VoxCPM adapter, reproducible pack tooling, and an Android debug build.
    Every phase runs exactly once in sequence. The first failed phase stops the
    gate; no command is retried automatically.
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
                'test/voice',
                'test/runtime/app_bootstrap_test.dart'
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
        Name = 'Standard voice pack contract'
        Action = {
            # Contract marker: build-standard-voice-pack.tests.ps1
            & powershell -NoProfile -ExecutionPolicy Bypass -File `
                'tool/cli/tests/build-standard-voice-pack.tests.ps1'
        }.GetNewClosure()
    },
    @{
        Name = 'Android debug APK'
        Action = {
            # Contract marker: flutter build apk --debug
            & flutter build apk --debug `
                --dart-define=LEXIQUEST_VERSION=1.0.0+p8b `
                --dart-define=LEXIQUEST_BUILD_ID=p8b-hybrid-voice
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
    Write-Host 'LexiQuest P8-B hybrid voice gate: FAIL' -ForegroundColor Red
    foreach ($result in $results) {
        if ($result.ExitCode -ne 0) {
            Write-Host ('  {0}: FAIL (exit {1})' -f $result.Name, $result.ExitCode) -ForegroundColor Red
        }
    }
    $exitCode = if ($failedExitCode -ne 0) { $failedExitCode } else { 1 }
    exit $exitCode
}

Write-Host 'LexiQuest P8-B hybrid voice gate: PASS' -ForegroundColor Green
foreach ($result in $results) {
    Write-Host ('  {0}: PASS' -f $result.Name) -ForegroundColor Green
}
exit 0
