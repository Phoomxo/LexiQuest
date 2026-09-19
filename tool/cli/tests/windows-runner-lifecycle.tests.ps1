#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
& python (Join-Path $PSScriptRoot 'windows_runner_lifecycle.py')
exit $LASTEXITCODE
