$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$pm8Root = 'C:\Users\Phet\.codex\worktrees\02fa\LexiQuest'
if ((Get-Location).Path -cne $pm8Root) { throw 'Wrong PM8 worktree.' }
$pm8Modules = [IO.Path]::GetFullPath((Join-Path $pm8Root 'node_modules'))
if ($pm8Modules -cne ($pm8Root + '\node_modules')) { throw 'Unexpected dependency target.' }
$pm8Head = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot record HEAD.' }
$pm8LocksBefore = @('package.json','package-lock.json') | ForEach-Object {
    [pscustomobject]@{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$pm8Stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfff',[Globalization.CultureInfo]::InvariantCulture)
$pm8Prefix = Join-Path $pm8Root ('.superpowers/sdd/pm8-node-prerequisites-' + $pm8Stamp)
$pm8Executable = 'C:\Program Files\nodejs\npm.cmd'
if (-not (Test-Path -LiteralPath $pm8Executable -PathType Leaf)) { throw 'Verified npm executable is missing.' }
$pm8Arguments = @('ci','--ignore-scripts','--no-audit','--no-fund')
$pm8Start = [DateTimeOffset]::UtcNow
$pm8InvocationFailure = $null
$pm8Exit = $null
try {
    $global:LASTEXITCODE = $null
    & $pm8Executable @pm8Arguments 1> ($pm8Prefix+'.stdout.log') 2> ($pm8Prefix+'.stderr.log')
    $pm8Exit = $global:LASTEXITCODE
    if ($null -eq $pm8Exit) { throw 'npm reported no exit code.' }
} catch {
    $pm8InvocationFailure = $_.Exception.Message
    if ($null -eq $pm8Exit) { $pm8Exit = 1 }
}
$pm8End = [DateTimeOffset]::UtcNow
$pm8LocksAfter = @('package.json','package-lock.json') | ForEach-Object {
    [pscustomobject]@{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$pm8Drift = @($pm8LocksBefore | Where-Object {
    $pm8Expected = $_
    @($pm8LocksAfter | Where-Object { $_.path -ceq $pm8Expected.path -and $_.sha256 -ceq $pm8Expected.sha256 }).Count -ne 1
})
$pm8Metadata = [ordered]@{
    scope='Dependency prerequisites only; not a final release test gate'
    checkoutHead=$pm8Head; workingDirectory=$pm8Root; executable=$pm8Executable
    arguments=$pm8Arguments; startUtc=$pm8Start.ToString('o'); endUtc=$pm8End.ToString('o')
    durationSeconds=($pm8End-$pm8Start).TotalSeconds; nativeExitCode=$pm8Exit; invocationFailure=$pm8InvocationFailure
    before=@($pm8LocksBefore); after=@($pm8LocksAfter); lockDrift=@($pm8Drift)
    stdout=($pm8Prefix+'.stdout.log'); stderr=($pm8Prefix+'.stderr.log')
}
$pm8Metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ($pm8Prefix+'.metadata.json') -Encoding utf8
[pscustomobject]@{nativeExitCode=$pm8Exit;lockDrift=$pm8Drift.Count;metadata=($pm8Prefix+'.metadata.json')} | ConvertTo-Json -Compress
if ($pm8Exit -ne 0) { exit $pm8Exit }
if ($pm8Drift.Count -ne 0) { exit 1 }
exit 0
