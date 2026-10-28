#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the bounded P8-D real speech evidence release gate.

.DESCRIPTION
    Verifies real microphone/STT evidence persistence: centralized provenance,
    a typed unavailable state for silence/failure, the Drift SpeechEvidence
    table, the speech evidence repository, screen wiring that persists real
    transcript/score/provenance, removal of the unused evaluator, a privacy
    boundary scan, and an Android debug build. Every phase runs exactly once
    in sequence. The first failed phase stops the gate; no command is retried
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
                'lib/features/media_practice',
                'lib/data/local',
                'lib/screens/shadowing_challenge_screen.dart',
                'lib/screens/speak_to_text_screen.dart',
                'test/features/media_practice',
                'test/data/local',
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
        Name = 'Focused speech evidence tests'
        Action = {
            # Contract marker: flutter test
            & flutter test @(
                'test/features/media_practice',
                'test/data/local',
                'test/screens/shadowing_challenge_screen_test.dart',
                'test/screens/speak_to_text_screen_voice_test.dart'
            ) --reporter compact
        }.GetNewClosure()
    },
    @{
        Name = 'Privacy boundary scan'
        Action = {
            # No raw microphone audio may be persisted; only the recognized
            # transcript and derived metadata. git grep exits 1 on no matches,
            # which is the desired privacy outcome.
            $audioMatch = & git grep -n -i -E 'audioBytes|wavBytes|rawAudio|microphoneStream' `
                -- 'lib/features/media_practice' 'lib/data/local/tables/speech_evidence_tables.dart'
            $audioExit = $LASTEXITCODE
            if ($audioExit -eq 0 -and $audioMatch) {
                throw "Raw audio persisted in speech evidence boundary: $audioMatch"
            }
            if ($audioExit -ne 0 -and $audioExit -ne 1) {
                throw "git grep failed with exit $audioExit"
            }
            # The centralized provenance must use the supported method.
            $contract = Get-Content -LiteralPath `
                'lib/features/media_practice/domain/speech_evidence_contract.dart' -Raw -Encoding utf8
            if (-not $contract.Contains('transcript-edit-distance-v1')) {
                throw 'Speech evidence contract must use transcript-edit-distance-v1.'
            }
            # No fabricated scores: silence must be a typed unavailable state.
            $useCases = Get-Content -LiteralPath `
                'lib/features/media_practice/application/speech_practice_use_cases.dart' -Raw -Encoding utf8
            if (-not $useCases.Contains('SpeechEvidenceUnavailable.silence')) {
                throw 'assessEvidence must treat silence as a typed unavailable state.'
            }
            $global:LASTEXITCODE = 0
        }.GetNewClosure()
    },
    @{
        Name = 'Android debug APK'
        Action = {
            # Contract marker: flutter build apk --debug
            & flutter build apk --debug `
                --dart-define=LEXIQUEST_VERSION=1.0.0+p8d `
                --dart-define=LEXIQUEST_BUILD_ID=p8d-real-speech-evidence
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
    Write-Host 'LexiQuest P8-D real speech evidence gate: FAIL' -ForegroundColor Red
    foreach ($result in $results) {
        if ($result.ExitCode -ne 0) {
            Write-Host ('  {0}: FAIL (exit {1})' -f $result.Name, $result.ExitCode) -ForegroundColor Red
        }
    }
    $exitCode = if ($failedExitCode -ne 0) { $failedExitCode } else { 1 }
    exit $exitCode
}

Write-Host 'LexiQuest P8-D real speech evidence gate: PASS' -ForegroundColor Green
foreach ($result in $results) {
    Write-Host ('  {0}: PASS' -f $result.Name) -ForegroundColor Green
}
exit 0
