#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$gatePath = Join-Path $repoRoot 'tool/cli/verify-gemini-byok.ps1'
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$manifestPath = Join-Path $repoRoot 'android/app/src/main/AndroidManifest.xml'
$gatewayPath = Join-Path $repoRoot 'lib/features/gemini/data/gemini_rest_gateway.dart'
$storePath = Join-Path $repoRoot 'lib/features/gemini/data/secure_gemini_settings_store.dart'
$tutorPath = Join-Path $repoRoot 'lib/screens/ai_tutor_screen.dart'

foreach ($path in @(
    $gatePath,
    $pubspecPath,
    $manifestPath,
    $gatewayPath,
    $storePath,
    $tutorPath
)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Error "Required P6 contract file is missing: $path"
    }
}

$gate = Get-Content -LiteralPath $gatePath -Raw -Encoding utf8
foreach ($needle in @(
    'dart format --output=none --set-exit-if-changed',
    'flutter analyze',
    'test/features/gemini',
    'test/screens/ai_tutor_screen_test.dart',
    'test/screens/gemini_settings_screen_test.dart',
    'flutter build apk --debug',
    'verify-apk-model-runtime.ps1',
    'git diff --check'
)) {
    if (-not $gate.Contains($needle)) {
        Write-Error "Missing P6 gate command or path: $needle"
    }
}

$pubspec = Get-Content -LiteralPath $pubspecPath -Raw -Encoding utf8
if (-not $pubspec.Contains('flutter_secure_storage: 10.3.1')) {
    Write-Error 'The Android Keystore-backed storage dependency must be pinned.'
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8
if ($manifest -notmatch 'android:allowBackup="false"') {
    Write-Error 'Android backup must remain disabled for Keystore-bound ciphertext.'
}

$store = Get-Content -LiteralPath $storePath -Raw -Encoding utf8
foreach ($needle in @(
    "storageNamespace: 'lexiquest_gemini_byok'",
    'KeyCipherAlgorithm.AES_GCM_NoPadding',
    'StorageCipherAlgorithm.AES_GCM_NoPadding'
)) {
    if (-not $store.Contains($needle)) {
        Write-Error "Secure Gemini store is missing: $needle"
    }
}

$gateway = Get-Content -LiteralPath $gatewayPath -Raw -Encoding utf8
foreach ($needle in @(
    "'x-goog-api-key'",
    "'gemini-2.5-flash-lite'",
    'http.AbortableRequest',
    'GeminiFailureCode.invalidKey',
    'GeminiFailureCode.quota',
    'GeminiFailureCode.offline',
    'GeminiFailureCode.timeout',
    'GeminiFailureCode.providerUnavailable',
    'GeminiFailureCode.malformedResponse'
)) {
    if (-not $gateway.Contains($needle)) {
        Write-Error "Gemini REST contract is missing: $needle"
    }
}
if ($gateway -match '\?key=|key=\$') {
    Write-Error 'Gemini key must never be placed in the request URI.'
}

$tutor = Get-Content -LiteralPath $tutorPath -Raw -Encoding utf8
if ($tutor -match 'package:(http|flutter_secure_storage)') {
    Write-Error 'AI Tutor presentation must not import HTTP or secure storage.'
}
if ($tutor -match 'canned|Grammar:\s*(Excellent|Good)|Future\.delayed\(') {
    Write-Error 'AI Tutor still contains a fabricated success path.'
}
if ($tutor -match 'debugPrint|print\s*\(') {
    Write-Error 'AI Tutor must not log provider data or secrets.'
}

$settingsPath = Join-Path $repoRoot 'lib/screens/gemini_settings_screen.dart'
$settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding utf8
if (-not $settings.Contains('obscureText: true')) {
    Write-Error 'Gemini key input must remain permanently obscured.'
}
if ($settings -match 'Icons\.visibility|obscureKey') {
    Write-Error 'Gemini key reveal controls can leak plaintext into task snapshots.'
}

$allGemini = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'lib/features/gemini') `
    -Recurse -File -Filter '*.dart' |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8 }
$combined = $allGemini -join "`n"
if ($combined -match 'debugPrint|print\s*\(') {
    Write-Error 'Gemini feature code must not log keys, prompts, or responses.'
}

Write-Host 'verify-gemini-byok contract: PASS' -ForegroundColor Green
exit 0
