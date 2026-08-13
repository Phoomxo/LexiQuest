#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ScannerPath = 'osv-scanner'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Invoke-LockScan {
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [Parameter(Mandatory)]
        [string]$Lockfile
    )

    $resolvedConfig = Join-Path $repoRoot $ConfigPath
    $resolvedLockfile = Join-Path $repoRoot $Lockfile
    if (-not (Test-Path -LiteralPath $resolvedConfig -PathType Leaf)) {
        throw "Missing OSV policy: $ConfigPath"
    }
    if (-not (Test-Path -LiteralPath $resolvedLockfile -PathType Leaf)) {
        throw "Missing dependency inventory: $Lockfile"
    }

    & $ScannerPath scan source `
        --config $resolvedConfig `
        --lockfile $resolvedLockfile
    if ($LASTEXITCODE -ne 0) {
        throw "OSV scan failed for $Lockfile (exit $LASTEXITCODE)."
    }
}

Push-Location -LiteralPath $repoRoot
try {
    Invoke-LockScan -ConfigPath 'osv-scanner.toml' -Lockfile 'pubspec.lock'
    Invoke-LockScan -ConfigPath 'osv-scanner.toml' -Lockfile 'package-lock.json'
    Invoke-LockScan -ConfigPath 'osv-scanner.toml' -Lockfile 'backend/ai_api/uv.lock'
    Invoke-LockScan -ConfigPath 'backend/voice_api/osv-scanner.toml' -Lockfile 'backend/voice_api/uv.lock'
    Invoke-LockScan -ConfigPath 'osv-scanner.toml' -Lockfile 'backend/lexiquest_lm/uv.lock'
    Invoke-LockScan -ConfigPath 'osv-scanner.toml' -Lockfile 'backend/lexiquest_lm/deploy/hf_space/requirements.txt'
}
finally {
    Pop-Location
}

Write-Host 'OSV literal-lock gate: PASS' -ForegroundColor Green
exit 0
