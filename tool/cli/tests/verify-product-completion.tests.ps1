#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$gatePath = Join-Path $repoRoot 'tool/cli/verify-product-completion.ps1'
if (-not (Test-Path -LiteralPath $gatePath -PathType Leaf)) {
    Write-Error "Required P7 gate is missing: $gatePath"
}

$gate = Get-Content -LiteralPath $gatePath -Raw -Encoding utf8
foreach ($needle in @(
    'dart format --output=none --set-exit-if-changed',
    'flutter analyze',
    'test/features/account',
    'test/features/consent',
    'test/features/export',
    'lib/features/ai_tutor',
    'lib/features/device_model',
    'test/features/ai_tutor',
    'test/features/device_model',
    'test/features/gemini/retry_gemini_gateway_test.dart',
    'test/features/rewards',
    'test/features/sync',
    'test/features/progress',
    'test/architecture',
    'test/screens/accessibility_smoke_test.dart',
    'test/scenarios/runtime_kill_switch_journey_test.dart',
    'test/scenarios/complete_owner_export_delete_test.dart',
    "Invoke-Gate 'Production field-trial integration journeys'",
    '-d flutter-tester',
    'foreach ($integrationTest in $integrationTests)',
    'integration_test/field_trial_core_journey_test.dart',
    'integration_test/field_trial_feature_controls_test.dart',
    'integration_test/field_trial_media_smoke_test.dart',
    'integration_test/support/field_trial_external_fakes.dart',
    'npm run test:auth',
    'npm run test:rules',
    'flutter build apk --debug',
    'verify-apk-model-runtime.ps1',
    'git diff --check'
)) {
    if (-not $gate.Contains($needle)) {
        Write-Error "Missing P7 gate command or path: $needle"
    }
}

$dartFilesStart = $gate.IndexOf('$dartFiles = @(', [StringComparison]::Ordinal)
$flutterTestsStart = $gate.IndexOf('$flutterTests = @(', [StringComparison]::Ordinal)
$pushLocationStart = $gate.IndexOf('Push-Location', [StringComparison]::Ordinal)
if ($dartFilesStart -lt 0 -or $flutterTestsStart -le $dartFilesStart -or `
    $pushLocationStart -le $flutterTestsStart) {
    Write-Error 'Product gate file scopes are not structurally readable.'
}
$dartFilesBlock = $gate.Substring(
    $dartFilesStart,
    $flutterTestsStart - $dartFilesStart
)
$flutterTestsBlock = $gate.Substring(
    $flutterTestsStart,
    $pushLocationStart - $flutterTestsStart
)
$mandatoryScenarios = @(
    'test/scenarios/ai_voice_fallback_journey_test.dart',
    'test/scenarios/runtime_kill_switch_journey_test.dart',
    'test/scenarios/complete_owner_export_delete_test.dart'
)
foreach ($relativePath in $mandatoryScenarios) {
    if (-not $dartFilesBlock.Contains($relativePath)) {
        Write-Error "Mandatory scenario is absent from Dart format scope: $relativePath"
    }
    if (-not $flutterTestsBlock.Contains($relativePath)) {
        Write-Error "Mandatory scenario is absent from Flutter test scope: $relativePath"
    }
}

foreach ($relativePath in @(
    'test/scenarios/ai_voice_fallback_journey_test.dart',
    'test/scenarios/runtime_kill_switch_journey_test.dart',
    'test/scenarios/complete_owner_export_delete_test.dart',
    'test/runtime/central_cost_policy_test.dart',
    'test/features/ai_tutor/drift_ai_usage_repository_test.dart',
    'test/features/device_model/model_download_manager_test.dart',
    'test/features/gemini/retry_gemini_gateway_test.dart'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath) -PathType Leaf)) {
        Write-Error "Required Task 8 hardening test is missing: $relativePath"
    }
}

$integrationGateStart = $gate.IndexOf(
    "Invoke-Gate 'Production field-trial integration journeys'",
    [StringComparison]::Ordinal
)
$firebaseAuthGateStart = $gate.IndexOf(
    "Invoke-Gate 'Firebase Auth emulator journey'",
    [StringComparison]::Ordinal
)
if ($integrationGateStart -lt 0 -or `
    $firebaseAuthGateStart -le $integrationGateStart) {
    Write-Error (
        'Production field-trial integration journeys must run as a named ' +
        'phase before external emulator and physical-device assertions.'
    )
}

foreach ($relativePath in @(
    'integration_test/field_trial_core_journey_test.dart',
    'integration_test/field_trial_feature_controls_test.dart',
    'integration_test/field_trial_media_smoke_test.dart'
)) {
    $source = Get-Content -LiteralPath (Join-Path $repoRoot $relativePath) `
        -Raw -Encoding utf8
    foreach ($factory in @(
        'exportStoreFactory:',
        'cameraGatewayFactory:',
        'speechRecognitionGatewayFactory:'
    )) {
        if (-not $source.Contains($factory)) {
            Write-Error "$relativePath must explicitly inject $factory"
        }
    }
}

$hardeningEvidencePath = Join-Path $repoRoot `
    'docs/field/2026-08-09-p8-hardening-evidence.md'
if (-not (Test-Path -LiteralPath $hardeningEvidencePath -PathType Leaf)) {
    Write-Error "Required Task 8 evidence is missing: $hardeningEvidencePath"
}
$hardeningEvidence = Get-Content -LiteralPath $hardeningEvidencePath `
    -Raw -Encoding utf8
$checkpointHeading = '## Checkpoint C execution ledger'
$checkpointStart = $hardeningEvidence.IndexOf(
    $checkpointHeading,
    [StringComparison]::Ordinal
)
if ($checkpointStart -lt 0) {
    Write-Error 'Task 8 evidence has no Checkpoint C execution ledger.'
}
$checkpointSection = $hardeningEvidence.Substring($checkpointStart)
$checkpointNormalized = [regex]::Replace($checkpointSection, '\s+', ' ')
if ($checkpointSection.Contains('[PENDING]')) {
    foreach ($needle in @(
        'Unbound WIP diagnostics',
        'are not Checkpoint C evidence',
        'do not populate the ledger above',
        'must be rerun sequentially',
        'source SHA, numeric exit code, and result'
    )) {
        if (-not $checkpointNormalized.Contains($needle)) {
            Write-Error (
                'Pending Checkpoint C rows require an explicit unbound-WIP ' +
                "disclaimer: $needle"
            )
        }
    }
    foreach ($forbiddenClaim in @(
        'completed successfully',
        'found no unsuppressed leak',
        'All six scans exit zero',
        '`flutter pub outdated` completed'
    )) {
        if ($checkpointNormalized.Contains($forbiddenClaim)) {
            Write-Error (
                'Pending Checkpoint C rows cannot coexist with an unbound ' +
                "completion claim: $forbiddenClaim"
            )
        }
    }
}

$settings = Get-Content -LiteralPath (
    Join-Path $repoRoot 'android/settings.gradle.kts'
) -Raw -Encoding utf8
foreach ($needle in @(
    'com.android.application") version "9.0.1"',
    'org.jetbrains.kotlin.android") version "2.3.20"'
)) {
    if (-not $settings.Contains($needle)) {
        Write-Error "Android toolchain is not aligned with Flutter stable: $needle"
    }
}

$appGradle = Get-Content -LiteralPath (
    Join-Path $repoRoot 'android/app/build.gradle.kts'
) -Raw -Encoding utf8
if (-not $appGradle.Contains('ndkVersion = "28.2.13676358"')) {
    Write-Error 'The NDK must remain pinned for reproducible LiteRT custom-op hashes.'
}

$pubspec = Get-Content -LiteralPath (Join-Path $repoRoot 'pubspec.yaml') `
    -Raw -Encoding utf8
foreach ($needle in @(
    'firebase_app_check: 0.4.5+2',
    'pdf: 3.13.0',
    'file_selector: 1.1.0',
    'assets/fonts/NotoSansThai-Variable.ttf'
)) {
    if (-not $pubspec.Contains($needle)) {
        Write-Error "P7 dependency or asset is missing: $needle"
    }
}
if ($pubspec -match '(?m)^  google_fonts:') {
    Write-Error 'Runtime font downloads must not be used in the field build.'
}

$exportUseCases = Get-Content -LiteralPath (
    Join-Path $repoRoot 'lib/features/export/application/export_use_cases.dart'
) -Raw -Encoding utf8
if ($exportUseCases -match '\.take\(\d+\)') {
    Write-Error 'A selected export dataset must not be silently truncated.'
}
if (-not $exportUseCases.Contains('_spreadsheetSafe')) {
    Write-Error 'CSV and Anki exports must neutralize spreadsheet formulas.'
}

$rewardRepository = Get-Content -LiteralPath (
    Join-Path $repoRoot 'lib/features/rewards/data/drift_reward_repository.dart'
) -Raw -Encoding utf8
foreach ($needle in @('rewardTransaction', 'outboxOperations')) {
    if (-not $rewardRepository.Contains($needle)) {
        Write-Error "Reward mutations must enter the sync outbox: $needle"
    }
}

$manifest = Get-Content -LiteralPath (
    Join-Path $repoRoot 'android/app/src/main/AndroidManifest.xml'
) -Raw -Encoding utf8
foreach ($needle in @(
    'android:autoVerify="true"',
    'android:host="vocab-learning-app-219ef.firebaseapp.com"',
    'android:pathPrefix="/auth/action"'
)) {
    if (-not $manifest.Contains($needle)) {
        Write-Error "Android email action App Link is missing: $needle"
    }
}

$operations = Get-Content -LiteralPath (
    Join-Path $repoRoot 'docs/runbooks/firebase-field-operations.md'
) -Raw -Encoding utf8
foreach ($needle in @('50%', '80%', '100%', 'kill switch', 'App Check')) {
    if ($operations.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        Write-Error "Firebase field operation is undocumented: $needle"
    }
}

$obsolete = @(
    'lib/services/achievement_service.dart',
    'lib/services/shop_service.dart',
    'lib/services/avatar_equipment_service.dart',
    'lib/services/quiz_service.dart',
    'lib/services/category_service.dart',
    'lib/services/vocab_service.dart',
    'lib/screens/home.dart',
    'lib/screens/main_vocabulary.dart',
    'lib/screens/register_form_screen.dart'
)
foreach ($relativePath in $obsolete) {
    if (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath)) {
        Write-Error "Obsolete duplicate runtime path remains: $relativePath"
    }
}

$screenFiles = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'lib/screens') `
    -File -Filter '*.dart'
$screenText = (
    $screenFiles |
        ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8 }
) -join "`n"
if ($screenText -match 'MaterialPageRoute|(?<!App)Navigator\.(push|pushNamed|pushReplacement)') {
    Write-Error 'Participant presentation still bypasses typed navigation.'
}
if ($screenText -match 'package:(cloud_firestore|firebase_auth|http|drift|shared_preferences|camera|speech_to_text|flutter_tts|permission_handler|file_selector|flutter_secure_storage)') {
    Write-Error 'Participant presentation still imports infrastructure directly.'
}

$enabledScreens = @(
    'mastery_dashboard_screen.dart',
    'weakness_clinic_screen.dart',
    'ghost_shadow_duel_screen.dart',
    'shadowing_challenge_screen.dart',
    'ai_tutor_screen.dart',
    'achievements_screen.dart',
    'shop_page.dart',
    'export_center_screen.dart'
)
$enabledText = (
    $enabledScreens |
        ForEach-Object {
        Get-Content -LiteralPath (Join-Path $repoRoot "lib/screens/$_") `
            -Raw -Encoding utf8
        }
) -join "`n"
if ($enabledText -match 'Random\(|sample(Data|Card|User)|mock|canned|Future\.delayed\(') {
    Write-Error 'An enabled field feature still fabricates participant output.'
}

Write-Host 'verify-product-completion contract: PASS' -ForegroundColor Green
exit 0
