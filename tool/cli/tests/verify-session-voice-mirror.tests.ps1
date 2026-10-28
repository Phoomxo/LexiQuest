#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Repository-root resolution: tests -> cli -> tool -> repo root.
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$gatePath = Join-Path $repoRoot 'tool/cli/verify-session-voice-mirror.ps1'

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

Assert-True 'verify-session-voice-mirror.ps1 gate exists' {
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
    'backend/voice_api/src/lexiquest_voice/mirror_sessions.py',
    'backend/voice_api/src/lexiquest_voice/engines/voxcpm_mirror_engine.py',
    'lib/voice/voice_mirror_gateway.dart',
    'lib/voice/voice_mirror_session_controller.dart',
    'lib/voice/voice_mirror_recorder.dart',
    'lib/voice/vox_cpm_mirror_provider.dart'
)
foreach ($relativePath in $requiredFiles) {
    $current = $relativePath
    Assert-True "$current exists" {
        Test-Path -LiteralPath (Join-Path $repoRoot $current) -PathType Leaf
    }
}

$mirrorProviderPath = Join-Path $repoRoot 'lib/voice/vox_cpm_mirror_provider.dart'
$mirrorProviderSource = Get-Content -LiteralPath $mirrorProviderPath -Raw -Encoding utf8
Assert-True 'mirror provider is participant-transient and never cached' {
    $mirrorProviderSource.Contains('VoicePrivacyScope.participantTransient') -and
    $mirrorProviderSource.Contains('allowsStandardCache: false')
}

$recorderPath = Join-Path $repoRoot 'lib/voice/voice_mirror_recorder.dart'
$recorderSource = Get-Content -LiteralPath $recorderPath -Raw -Encoding utf8
Assert-True 'recorder keeps enrollment in a dedicated directory only' {
    $recorderSource.Contains('voice_mirror_enrollment')
}
Assert-True 'recorder never uses a backup directory accessor' {
    -not $recorderSource.Contains('Backup') -and
    -not $recorderSource.Contains('getBackup')
}

Write-Host ("verify-session-voice-mirror contract: PASS={0} FAIL={1}" -f $pass, $fail)
if ($fail -gt 0) {
    exit 1
}
exit 0
