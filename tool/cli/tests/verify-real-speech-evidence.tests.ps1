#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Repository-root resolution: tests -> cli -> tool -> repo root.
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$gatePath = Join-Path $repoRoot 'tool/cli/verify-real-speech-evidence.ps1'

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

Assert-True 'verify-real-speech-evidence.ps1 gate exists' {
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
    'lib/features/media_practice/domain/speech_evidence_contract.dart',
    'lib/features/media_practice/domain/speech_evidence_use_cases.dart',
    'lib/features/media_practice/data/drift_speech_evidence_repository.dart',
    'lib/data/local/tables/speech_evidence_tables.dart'
)
foreach ($relativePath in $requiredFiles) {
    $current = $relativePath
    Assert-True "$current exists" {
        Test-Path -LiteralPath (Join-Path $repoRoot $current) -PathType Leaf
    }
}

# The centralized provenance must use the supported method version.
$contractPath = Join-Path $repoRoot 'lib/features/media_practice/domain/speech_evidence_contract.dart'
$contractSource = Get-Content -LiteralPath $contractPath -Raw -Encoding utf8
Assert-True 'speech evidence contract declares the transcript-edit-distance method' {
    $contractSource.Contains('transcript-edit-distance-v1')
}
Assert-True 'speech evidence contract exposes a typed unavailable reason' {
    $contractSource.Contains('SpeechEvidenceUnavailable')
}

# The dead cosine-similarity evaluator must be gone.
Assert-True 'unused cosine similarity evaluator is removed' {
    -not (Test-Path -LiteralPath (Join-Path $repoRoot 'lib/services/cosine_similarity_evaluator_service.dart') -PathType Leaf)
}

Write-Host ("verify-real-speech-evidence contract: PASS={0} FAIL={1}" -f $pass, $fail)
if ($fail -gt 0) {
    exit 1
}
exit 0
