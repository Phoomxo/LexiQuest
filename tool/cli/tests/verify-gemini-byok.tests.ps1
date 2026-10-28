#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$gatePath = Join-Path $repoRoot 'tool/cli/verify-gemini-byok.ps1'
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$manifestPath = Join-Path $repoRoot 'android/app/src/main/AndroidManifest.xml'
$gatewayPath = Join-Path $repoRoot 'lib/features/gemini/data/gemini_rest_gateway.dart'
$storePath = Join-Path $repoRoot 'lib/features/gemini/data/secure_gemini_settings_store.dart'
$aiStorePath = Join-Path $repoRoot 'lib/features/ai_tutor/data/ai_tutor_settings_store.dart'
$versionIndexPath = Join-Path $repoRoot 'lib/features/ai_tutor/data/ai_credential_version_index.dart'
$bootstrapPath = Join-Path $repoRoot 'lib/runtime/app_bootstrap.dart'
$tutorPath = Join-Path $repoRoot 'lib/screens/ai_tutor_screen.dart'
$settingsPath = Join-Path $repoRoot 'lib/screens/ai_tutor_settings_screen.dart'
$databasePath = Join-Path $repoRoot 'lib/data/local/app_database.dart'
$secureAiStoreTestPath = Join-Path $repoRoot 'test/features/ai_tutor/secure_ai_tutor_settings_store_test.dart'
$architectureTestPath = Join-Path $repoRoot 'test/architecture/provider_composition_boundary_test.dart'

foreach ($path in @(
    $gatePath,
    $pubspecPath,
    $manifestPath,
    $gatewayPath,
    $storePath,
    $aiStorePath,
    $versionIndexPath,
    $bootstrapPath,
    $tutorPath,
    $settingsPath,
    $databasePath,
    $secureAiStoreTestPath,
    $architectureTestPath
)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Error "Required P6 contract file is missing: $path"
    }
}

$gate = Get-Content -LiteralPath $gatePath -Raw -Encoding utf8
foreach ($needle in @(
    'dart format --output=none --set-exit-if-changed',
    'flutter analyze',
    'test/features/ai_tutor',
    'test/features/gemini',
    'test/architecture/provider_composition_boundary_test.dart',
    'test/screens/ai_tutor_screen_test.dart',
    'test/screens/gemini_settings_screen_test.dart',
    'flutter build apk --debug',
    'verify-apk-model-runtime.ps1',
    'git diff --check',
    '$dartExecutable',
    '$flutterExecutable',
    'LocalApplicationData'
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
    "storageNamespace: 'lexiquest_gemini_byok_v2'",
    'resetOnError: false',
    'migrateOnAlgorithmChange: false',
    'KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding',
    'StorageCipherAlgorithm.AES_GCM_NoPadding'
)) {
    if (-not $store.Contains($needle)) {
        Write-Error "Secure Gemini store is missing: $needle"
    }
}

$aiStore = Get-Content -LiteralPath $aiStorePath -Raw -Encoding utf8
foreach ($needle in @(
    'SecureAiTutorSettingsStore.production',
    'FlutterSecureValueStore()',
    'AiCredentialVersionIndex',
    '''$_profile:$ownerToken:version:${version.trim()}'''
)) {
    if (-not $aiStore.Contains($needle)) {
        Write-Error "Versioned AI credential store is missing: $needle"
    }
}

$versionIndex = Get-Content -LiteralPath $versionIndexPath -Raw -Encoding utf8
foreach ($needle in @(
    "'aiCredentialPointer:'",
    "'aiCredentialIntent:'",
    'UPDATE runtime_flags',
    'DriftOwnerOperationGate.gateKey'
)) {
    if (-not $versionIndex.Contains($needle)) {
        Write-Error "Schema-12 AI credential index is missing: $needle"
    }
}

$bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw -Encoding utf8
foreach ($needle in @(
    'DriftAiCredentialVersionIndex(database)',
    'SecureAiTutorSettingsStore.production'
)) {
    if (-not $bootstrap.Contains($needle)) {
        Write-Error "Bootstrap AI credential composition is missing: $needle"
    }
}

$database = Get-Content -LiteralPath $databasePath -Raw -Encoding utf8
if (-not $database.Contains('int get schemaVersion => 12')) {
    Write-Error 'AI credential metadata must remain on schema 12.'
}

$secureAiStoreTest = Get-Content -LiteralPath $secureAiStoreTestPath -Raw -Encoding utf8
foreach ($needle in @(
    'expect(database.schemaVersion, 12)',
    'SELECT "key", source FROM runtime_flags',
    "isNot(contains('first-secret'))",
    "isNot(contains('second-secret'))"
)) {
    if (-not $secureAiStoreTest.Contains($needle)) {
        Write-Error "AI credential no-secret regression is missing: $needle"
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

$resolvedTools = @(& powershell -NoProfile -ExecutionPolicy Bypass -File `
    $gatePath -ResolveToolsOnly 2>&1)
if ($LASTEXITCODE -ne 0) {
    Write-Error 'Gemini BYOK gate could not resolve Flutter and Dart tools.'
}
$resolvedText = $resolvedTools -join "`n"
if ($resolvedText -notmatch '(?m)^Flutter: .+' -or
    $resolvedText -notmatch '(?m)^Dart: .+') {
    Write-Error 'Gemini BYOK gate did not report both resolved tool paths.'
}

Write-Host 'verify-gemini-byok contract: PASS' -ForegroundColor Green
exit 0
