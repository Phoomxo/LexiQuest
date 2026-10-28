Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tests = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.tests.ps1' -File |
    Sort-Object Name)

foreach ($test in $tests) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $test.FullName
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "AI analysis tests: $($tests.Count) files passed"
