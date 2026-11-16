#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (
    Split-Path -Parent $PSScriptRoot
) 'verify-apk-model-runtime.ps1'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    Write-Error 'verify-apk-model-runtime.ps1 is missing.'
}

$source = Get-Content -LiteralPath $scriptPath -Raw -Encoding utf8
$required = @(
    'A162D1DDBDAD87C002B7EC7EB31A703F2761335E693F292F94091B3569D8AA37',
    'lib/arm64-v8a/libLiteRt.so',
    'lib/armeabi-v7a/libLiteRt.so',
    'lib/x86_64/libLiteRt.so',
    'libtensorflowlite_jni.so',
    'libtensorflowlite_gpu_jni.so',
    'libtflite_custom_ops.so',
    "ValidateSet('Auto', 'Debug', 'Release')",
    'RelWithDebInfo',
    '570E067F5EED5F3EB27C653D7650CB65846FECED0F5A4543CBFF80260493B10E',
    'ED8A789CDE1266E388818DFA259101628942D336AF4B1A2D7D4264571D923FAB',
    'B1E7A49EE12AEF57A65717536F205E4D0E6E17DE857A5BD4B75F02EEF9328D95',
    'Get-FileHash',
    'Unexpected model runtime libraries or ABIs',
    'GPU accelerator libraries must not be packaged'
)
foreach ($needle in $required) {
    if (-not $source.Contains($needle)) {
        Write-Error ("Missing APK runtime integrity contract: {0}" -f $needle)
    }
}
if ($source -match '\bwhile\s*\(' -or $source -match '\bfor\s*\(\s*;\s*;') {
    Write-Error 'APK runtime verification must not contain an unbounded retry loop.'
}

Write-Host 'verify-apk-model-runtime contract: PASS' -ForegroundColor Green
exit 0
