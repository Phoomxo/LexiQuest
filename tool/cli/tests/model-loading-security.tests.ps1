#Requires -Version 5.1
<#
.SYNOPSIS
    Dependency-free security gate for model loading under backend/lexiquest_lm.
#>
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0
$script:Violations = @()

function Strip-PythonComment {
    param([string]$Line)
    $inSingle = $false
    $inDouble = $false
    $code = ''
    foreach ($character in $Line.ToCharArray()) {
        if ($character -eq "'" -and -not $inDouble) { $inSingle = -not $inSingle }
        elseif ($character -eq '"' -and -not $inSingle) { $inDouble = -not $inDouble }
        elseif ($character -eq '#' -and -not $inSingle -and -not $inDouble) { break }
        $code += $character
    }
    return $code
}

function Write-Fail {
    param([string]$Message)
    $script:Failed++
    Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
}

$repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$lmRoot = Join-Path $repoRoot 'backend/lexiquest_lm'
$pythonFiles = Get-ChildItem -LiteralPath $lmRoot -Recurse -File -Filter *.py |
    Where-Object { $_.FullName -notmatch '[\\/](\.venv|__pycache__|checkpoints?|\.cache)[\\/]' }

foreach ($file in $pythonFiles) {
    $relativePath = $file.FullName.Substring($repoRoot.Length).Replace('\', '/').TrimStart('/')
    $lines = @(Get-Content -LiteralPath $file.FullName)
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ((Strip-PythonComment $lines[$index]) -match 'trust_remote_code\s*[:=]\s*True') {
            $script:Violations += ("{0}:{1}" -f $relativePath, ($index + 1))
        }
    }
}
if ($script:Violations.Count -eq 0) { $script:Passed++ } else {
    Write-Fail ("executable trust_remote_code=True in {0} line(s)" -f $script:Violations.Count)
    foreach ($violation in $script:Violations) { Write-Host ('    ' + $violation) -ForegroundColor Yellow }
}

$entryPoints = @(
    'backend/lexiquest_lm/train/tokenise_dataset.py',
    'backend/lexiquest_lm/train/lora_finetune.py',
    'backend/lexiquest_lm/train/evaluate.py',
    'backend/lexiquest_lm/deploy/hf_space/app.py'
)
foreach ($entryPoint in $entryPoints) {
    $content = [System.IO.File]::ReadAllText((Join-Path $repoRoot $entryPoint))
    if ($content -match 'from_pretrained\s*\(' -and $content -match 'Qwen2\.5') {
        $script:Passed++
    } else { Write-Fail ("model loading missing from {0}" -f $entryPoint) }
}

Write-Host ("Model loading security tests: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
