$ErrorActionPreference='Stop'
& node (Join-Path $PSScriptRoot 'firebase-budget-contract.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Budget reconciliation contract failed' }
