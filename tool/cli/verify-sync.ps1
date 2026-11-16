[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$startedAt = Get-Date
$completedPhases = [System.Collections.Generic.List[string]]::new()

function Invoke-CheckedPhase {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    Write-Host "[$($completedPhases.Count + 1)/7] $Name"
    & $Action
    $completedPhases.Add($Name)
}

Push-Location $repositoryRoot
try {
    $formatTargets = @(
        'lib/data/local',
        'lib/features/identity',
        'lib/features/sync',
        'lib/features/vocabulary',
        'lib/runtime',
        'lib/services/guest_session_service.dart',
        'lib/main.dart',
        'test/data/local',
        'test/features/identity',
        'test/features/sync',
        'test/features/vocabulary',
        'test/runtime',
        'test/services/guest_session_service_test.dart',
        'test/screens/offline_vocabulary_journey_test.dart'
    )
    Invoke-CheckedPhase 'Scoped formatting' {
        & dart format --output=none --set-exit-if-changed @formatTargets
        if ($LASTEXITCODE -ne 0) {
            throw "Formatting failed with exit code $LASTEXITCODE."
        }
    }

    $analyzeTargets = @(
        'lib/data/local',
        'lib/features/identity',
        'lib/features/sync',
        'lib/features/vocabulary',
        'lib/runtime',
        'lib/services/guest_session_service.dart',
        'lib/main.dart'
    )
    Invoke-CheckedPhase 'Scoped static analysis' {
        & flutter analyze @analyzeTargets
        if ($LASTEXITCODE -ne 0) {
            throw "Static analysis failed with exit code $LASTEXITCODE."
        }
    }

    $testTargets = @(
        'test/data/local',
        'test/features/identity',
        'test/features/sync',
        'test/features/vocabulary',
        'test/runtime',
        'test/services/guest_session_service_test.dart',
        'test/screens/offline_vocabulary_journey_test.dart',
        'test/screens/production_shell_navigation_test.dart'
    )
    Invoke-CheckedPhase 'Local-first and sync tests' {
        & flutter test --no-pub --reporter compact @testTargets
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter tests failed with exit code $LASTEXITCODE."
        }
    }

    Invoke-CheckedPhase 'Screen infrastructure boundary' {
        $screenTargets = @(
            'lib/screens/categories_page.dart',
            'lib/screens/vocab_list_screen.dart',
            'lib/screens/add_vocab_screen.dart',
            'lib/screens/add_multiple_words_screen.dart'
        )
        & rg -n 'cloud_firestore|firebase_auth|FirebaseFirestore|FirebaseAuth|package:http|package:drift' @screenTargets
        if ($LASTEXITCODE -eq 0) {
            throw 'A local-first vocabulary screen imports infrastructure directly.'
        }
        if ($LASTEXITCODE -ne 1) {
            throw "Infrastructure scan failed with exit code $LASTEXITCODE."
        }
        $global:LASTEXITCODE = 0
    }

    Invoke-CheckedPhase 'Firestore emulator rules' {
        & npm run test:rules
        if ($LASTEXITCODE -ne 0) {
            throw "Firestore rules tests failed with exit code $LASTEXITCODE."
        }
    }

    Invoke-CheckedPhase 'Android sync debug APK' {
        & flutter build apk --debug --no-pub `
            --dart-define=LEXIQUEST_CLOUD_SYNC_ENABLED=true `
            --dart-define=LEXIQUEST_VERSION=1.0.0+1 `
            --dart-define=LEXIQUEST_BUILD_ID=p2-sync
        if ($LASTEXITCODE -ne 0) {
            throw "Android debug build failed with exit code $LASTEXITCODE."
        }
    }

    Invoke-CheckedPhase 'Working-tree whitespace check' {
        & git diff --check
        if ($LASTEXITCODE -ne 0) {
            throw "Whitespace check failed with exit code $LASTEXITCODE."
        }
    }

    $elapsed = (Get-Date) - $startedAt
    Write-Host (
        "PASS: P2 sync gate completed {0} phases in {1:mm\:ss}." -f
        $completedPhases.Count,
        $elapsed
    )
}
catch {
    $elapsed = (Get-Date) - $startedAt
    Write-Error (
        "FAIL: P2 sync gate stopped after {0} completed phases in {1:mm\:ss}. {2}" -f
        $completedPhases.Count,
        $elapsed,
        $_.Exception.Message
    )
    exit 1
}
finally {
    Pop-Location
}
