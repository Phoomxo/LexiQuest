#Requires -Version 5.1
<#
.SYNOPSIS
    Dependency-free security contract for the Firebase category seed module.
#>
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0

function Assert-True {
    param([object]$Value, [string]$Message)
    if ($Value) { $script:Passed++ } else {
        $script:Failed++
        Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
    }
}

function Assert-False {
    param([object]$Value, [string]$Message)
    Assert-True (-not $Value) $Message
}

$repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$modulePath = Join-Path $repoRoot 'lib/add_default_categories.js'
if (-not (Test-Path -LiteralPath $modulePath)) {
    Write-Host "FAIL: missing $modulePath" -ForegroundColor Red
    exit 1
}
$source = [System.IO.File]::ReadAllText($modulePath)

Assert-False ($source -match '[A-Za-z]:[\\/](Users|Documents and Settings)[\\/]') 'no absolute Windows user path'
Assert-False ($source -match 'firebase-adminsdk') 'no firebase-adminsdk credential filename'
Assert-False ($source -match 'admin\.credential\.cert') 'no admin.credential.cert initialization'
Assert-False ($source -match 'databaseURL\s*:') 'no hard-coded databaseURL'
Assert-True ($source -match 'applicationDefault') 'seed uses Application Default Credentials'
Assert-True ($source -match 'require\.main\s*===\s*module') 'importing the module is side-effect free'
Assert-True ($source -match 'module\.exports') 'module exports maintenance functions'
Assert-True ($source -match 'module\.exports\s*=\s*\{[^}]*addDefaultCategories') 'module exports addDefaultCategories'

Write-Host ("Firebase seed security tests: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
