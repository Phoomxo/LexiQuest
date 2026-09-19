#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
& python (Join-Path $PSScriptRoot 'android_export_lifecycle.py')
exit $LASTEXITCODE
