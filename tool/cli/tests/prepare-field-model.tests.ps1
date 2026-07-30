#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'prepare-field-model.ps1'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    Write-Error 'prepare-field-model.ps1 is missing.'
}

$source = Get-Content -LiteralPath $scriptPath -Raw -Encoding utf8
$required = @(
    'mobilenet_v1_1.0_224_quantized_1_metadata_1.tflite',
    'D3949E8A3556C79739CB675E0BE7476503BCCE76938031C6A1048E13E0CB7D8B',
    '4287874',
    'Get-FileHash',
    'Move-Item'
)
foreach ($needle in $required) {
    if (-not $source.Contains($needle)) {
        Write-Error ("Missing model preparation contract: {0}" -f $needle)
    }
}
if ($source -match '\bwhile\s*\(' -or $source -match '\bfor\s*\(\s*;\s*;') {
    Write-Error 'Model preparation must not contain an unbounded retry loop.'
}

Write-Host 'prepare-field-model contract: PASS' -ForegroundColor Green
exit 0
