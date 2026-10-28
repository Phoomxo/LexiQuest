#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Repository-root resolution: tests -> cli -> tool -> repo root.
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$gatePath = Join-Path $repoRoot 'tool/cli/verify-hybrid-voice.ps1'

$pass = 0
$fail = 0

function Assert-True {
    param(
        [string]$Description,
        [scriptblock]$Condition
    )
    if (& $Condition) {
        $script:pass++
    }
    else {
        Write-Host "FAIL: $Description" -ForegroundColor Red
        $script:fail++
    }
}

Assert-True 'verify-hybrid-voice.ps1 gate exists' {
    Test-Path -LiteralPath $gatePath -PathType Leaf
}

$gateSource = ''
if (Test-Path -LiteralPath $gatePath -PathType Leaf) {
    $gateSource = Get-Content -LiteralPath $gatePath -Raw -Encoding utf8
}

foreach ($needle in @(
    'dart format --output=none --set-exit-if-changed',
    'flutter analyze',
    'flutter test',
    'uv lock --check',
    'uv run --group dev pytest -q',
    'build-standard-voice-pack.tests.ps1',
    'flutter build apk --debug',
    'git diff --check'
)) {
    $current = $needle
    Assert-True "gate source contains '$current'" { $gateSource.Contains($current) }
}

$repoRootLine = ($gateSource -split "`r?`n" |
    Where-Object { $_ -match '^\s*\$repoRoot\s*=' -and $_ -match 'Split-Path' })
if ($null -ne $repoRootLine) {
    $splitPathCount = ([regex]::Matches($repoRootLine, 'Split-Path\s+-Parent')).Count
    Assert-True 'gate resolves repo root in exactly two parent hops' {
        $splitPathCount -eq 2
    }
}
else {
    Assert-True 'gate declares a Split-Path-based repository root' { $false }
}

$requiredFiles = @(
    'backend/voice_api/src/lexiquest_voice/engines/voxcpm_engine.py',
    'lib/voice/standard_voice_pack_manifest.dart',
    'lib/voice/standard_voice_pack_download_manager.dart',
    'lib/voice/installed_voice_pack_provider.dart',
    'lib/voice/voice_request_quota.dart'
)
foreach ($relativePath in $requiredFiles) {
    $current = $relativePath
    Assert-True "$current exists" {
        Test-Path -LiteralPath (Join-Path $repoRoot $current) -PathType Leaf
    }
}

$voxProviderPath = Join-Path $repoRoot 'lib/voice/vox_cpm_standard_provider.dart'
$voxProviderSource = Get-Content -LiteralPath $voxProviderPath -Raw -Encoding utf8
Assert-True 'VoxCPM standard provider cannot declare session mirroring' {
    -not $voxProviderSource.Contains('VoiceCapability.sessionVoiceMirror')
}
Assert-True 'VoxCPM standard provider cannot send participant reference audio' {
    -not $voxProviderSource.Contains('referenceAudio')
}

Write-Host ("verify-hybrid-voice contract: PASS={0} FAIL={1}" -f $pass, $fail)
if ($fail -gt 0) {
    exit 1
}
exit 0
