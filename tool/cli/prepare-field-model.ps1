#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixtureDirectory = Join-Path $repoRoot 'build\model-fixtures'
$target = Join-Path $fixtureDirectory 'mobilenet.tflite'
$temporary = Join-Path $fixtureDirectory 'mobilenet.tflite.download'
$expectedHash = 'D3949E8A3556C79739CB675E0BE7476503BCCE76938031C6A1048E13E0CB7D8B'
$expectedBytes = 4287874
$sourceUrl = 'https://storage.googleapis.com/download.tensorflow.org/models/tflite/task_library/image_classification/android/mobilenet_v1_1.0_224_quantized_1_metadata_1.tflite'

New-Item -ItemType Directory -Path $fixtureDirectory -Force | Out-Null

if (Test-Path -LiteralPath $target -PathType Leaf) {
    $existing = Get-Item -LiteralPath $target
    $existingHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if ($existing.Length -eq $expectedBytes -and $existingHash -eq $expectedHash) {
        Write-Host 'Field model fixture: VERIFIED' -ForegroundColor Green
        exit 0
    }
}

if (Test-Path -LiteralPath $temporary) {
    Remove-Item -LiteralPath $temporary -Force
}
Invoke-WebRequest -Uri $sourceUrl -OutFile $temporary
$download = Get-Item -LiteralPath $temporary
$downloadHash = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash
if ($download.Length -ne $expectedBytes -or $downloadHash -ne $expectedHash) {
    throw 'Downloaded field model failed size or SHA-256 verification.'
}

Move-Item -LiteralPath $temporary -Destination $target -Force
Write-Host 'Field model fixture: DOWNLOADED AND VERIFIED' -ForegroundColor Green
exit 0
