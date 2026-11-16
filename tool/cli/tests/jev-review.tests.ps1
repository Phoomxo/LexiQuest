#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
& python -m unittest discover -s (Join-Path $PSScriptRoot '../../experiments/jev_review') -p 'test_*.py' -v
exit $LASTEXITCODE
