#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Repository-root resolution: tests -> cli -> tool -> repo root.
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$gatePath = Join-Path $repoRoot 'tool/cli/verify-voice-architecture.ps1'

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

# The gate file must exist; a missing gate fails closed.
Assert-True 'verify-voice-architecture.ps1 gate exists' {
    Test-Path -LiteralPath $gatePath -PathType Leaf
}

$gateSource = ''
if (Test-Path -LiteralPath $gatePath -PathType Leaf) {
    $gateSource = Get-Content -LiteralPath $gatePath -Raw -Encoding utf8
}

# The gate must not be invoked here; only its raw source is inspected.
foreach ($needle in @(
    'flutter analyze',
    'flutter test',
    'flutter build apk --debug',
    'test/voice',
    'participant_screen_boundary_test.dart',
    'git diff --check'
)) {
    $current = $needle
    Assert-True "gate source contains '$current'" { $gateSource.Contains($current) }
}

# Fail-closed contract: the gate lives at tool/cli/verify-voice-architecture.ps1,
# so its repository root is reached by ascending exactly two parent levels
# (cli -> tool -> repo root). Three levels would overshoot the repo root. This
# is verified statically against the gate source only; the expensive gate is
# never invoked here.
$repoRootLine = ($gateSource -split "`r?`n" |
    Where-Object { $_ -match '^\s*\$repoRoot\s*=' -and $_ -match 'Split-Path' })
if ($null -ne $repoRootLine) {
    $splitPathCount = ([regex]::Matches($repoRootLine, 'Split-Path\s+-Parent')).Count
    Assert-True 'gate resolves repo root in exactly two Split-Path -Parent hops (cli -> tool -> repo)' {
        $splitPathCount -eq 2
    }
    Assert-True 'gate does not resolve repo root with three Split-Path -Parent hops (overshoot)' {
        $splitPathCount -ne 3
    }
}
else {
    # A gate with no recognizable $repoRoot resolution cannot satisfy the
    # contract; fail closed rather than silently passing.
    Assert-True 'gate source declares a Split-Path-based $repoRoot resolution' { $false }
}

# Production presentation must not construct or reference legacy voice services.
$screensRoot = Join-Path $repoRoot 'lib/screens'
$forbiddenVoiceSymbols = @('VoiceServiceFactory', 'ManagedVoiceService')
if (Test-Path -LiteralPath $screensRoot -PathType Container) {
    $screenFiles = Get-ChildItem -LiteralPath $screensRoot -File -Filter '*.dart' -Recurse
    foreach ($file in $screenFiles) {
        $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8
        foreach ($symbol in $forbiddenVoiceSymbols) {
            $relative = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
            $sym = $symbol
            Assert-True "$relative must not reference $sym" { -not $text.Contains($sym) }
        }
    }
}
else {
    Assert-True 'lib/screens production directory exists' { $false }
}

# The deprecated hybrid voice service must be absent.
Assert-True 'lib/voice/hybrid_voice_service.dart is absent' {
    -not (Test-Path -LiteralPath (Join-Path $repoRoot 'lib/voice/hybrid_voice_service.dart') -PathType Leaf)
}

Write-Host ("verify-voice-architecture contract: PASS={0} FAIL={1}" -f $pass, $fail)
if ($fail -gt 0) {
    exit 1
}
exit 0
