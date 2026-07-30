#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$scriptPath = Join-Path $repoRoot 'tool/cli/verify-camera-speech.ps1'
$manifestPath = Join-Path $repoRoot 'android/app/src/main/AndroidManifest.xml'
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'

foreach ($path in @($scriptPath, $manifestPath, $pubspecPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Error "Required P5 contract file is missing: $path"
    }
}

$source = Get-Content -LiteralPath $scriptPath -Raw -Encoding utf8
$requiredGate = @(
    'prepare-field-model.ps1',
    'dart format --output=none --set-exit-if-changed',
    'flutter analyze',
    'test/features/media_practice',
    'test/voice/native_tts_provider_test.dart',
    'flutter build apk --debug',
    'verify-apk-model-runtime.ps1',
    'git diff --check'
)
foreach ($needle in $requiredGate) {
    if (-not $source.Contains($needle)) {
        Write-Error "Missing P5 gate command or path: $needle"
    }
}

$pubspec = Get-Content -LiteralPath $pubspecPath -Raw -Encoding utf8
foreach ($dependency in @('camera: 0.12.0+2', 'permission_handler: 12.0.3', 'image: 4.9.1')) {
    if (-not $pubspec.Contains($dependency)) {
        Write-Error "Missing pinned P5 dependency: $dependency"
    }
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8
foreach ($permission in @(
    'android.permission.CAMERA',
    'android.permission.RECORD_AUDIO'
)) {
    if (-not $manifest.Contains($permission)) {
        Write-Error "Missing Android runtime permission: $permission"
    }
}
if ($manifest.Contains('com.google.mlkit.vision.DEPENDENCIES')) {
    Write-Error 'Obsolete ML Kit placeholder metadata must be absent.'
}

$screenFiles = @(
    'lib/screens/object_scanner_screen.dart',
    'lib/screens/speak_to_text_screen.dart',
    'lib/screens/shadowing_challenge_screen.dart'
)
foreach ($relative in $screenFiles) {
    $text = Get-Content -LiteralPath (Join-Path $repoRoot $relative) `
        -Raw -Encoding utf8
    if ($text -match 'package:(camera|speech_to_text|permission_handler|flutter_tts)') {
        Write-Error "Presentation imports a platform plugin directly: $relative"
    }
    if ($text -match '\bRandom\s*\(' -or $text -match 'simulate-button') {
        Write-Error "Participant media screen still contains simulation: $relative"
    }
}

$obsolete = @(
    'lib/services/ml_image_labeling_service.dart',
    'lib/services/phoneme_alignment_clinic_service.dart',
    'lib/services/multi_accent_pitch_calibration_service.dart',
    'lib/widgets/visual_pitch_contour_widget.dart'
)
foreach ($relative in $obsolete) {
    if (Test-Path -LiteralPath (Join-Path $repoRoot $relative)) {
        Write-Error "Obsolete fabricated media path remains: $relative"
    }
}

Write-Host 'verify-camera-speech contract: PASS' -ForegroundColor Green
exit 0
