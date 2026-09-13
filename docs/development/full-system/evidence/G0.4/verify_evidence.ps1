$ErrorActionPreference = 'Stop'
$repo = (git rev-parse --show-toplevel).Trim()
$verification = Get-Content (Join-Path $PSScriptRoot 'verification.json') -Raw | ConvertFrom-Json
$result = Get-Content (Join-Path $PSScriptRoot 'cli-result.json') -Raw | ConvertFrom-Json
if ($verification.sourceFingerprint -ne $result.fingerprint -or $result.status -ne 'Passed') { throw 'Invalid verification source/status' }
if ($result.inputClosure.Count -ne 1325 -or $result.commands.Count -ne 2) { throw 'Unexpected accepted closure or commands' }
foreach ($row in $result.inputClosure) {
    if ((Get-FileHash -LiteralPath (Join-Path $repo $row.path)).Hash -ne $row.sha256) { throw ('Changed gate input: ' + $row.path) }
}
foreach ($pin in $verification.pins) {
    if ((Get-FileHash -LiteralPath (Join-Path $repo $pin.path)).Hash -ne $pin.sha256) { throw ('Changed source pin: ' + $pin.path) }
    if ((git hash-object -- $pin.path) -ne $pin.gitBlob) { throw ('Changed source blob: ' + $pin.path) }
}
foreach ($log in $verification.logs) {
    if ((Get-FileHash -LiteralPath (Join-Path $repo $log.path)).Hash -ne $log.sha256) { throw ('Changed log copy: ' + $log.path) }
}
foreach ($command in $verification.commands) {
    if ($command.Status -ne 'Passed' -or $command.ExitCode -ne 0 -or !$command.Resumed -or $command.durationSeconds -le 0) { throw 'Invalid command evidence' }
}
$audit = Get-Content (Join-Path $PSScriptRoot 'registry-verification.json') -Raw | ConvertFrom-Json
if ($audit.registryEntries -ne 20 -or $audit.parameterRejections.Count -ne 10 -or $audit.releaseExecuted) { throw 'Invalid registry evidence' }
$ledger = Get-Content (Join-Path $repo 'docs/development/2026-09-13-full-system-work-ledger.json') -Raw | ConvertFrom-Json
if (($ledger.packages | Where-Object id -eq 'P0.4').status -ne 'accepted') { throw 'Missing package acceptance' }
Write-Output 'PASS: 1325 unchanged input hashes, source blobs, preserved logs, positive durations, two resumed commands, registry and ledger'
