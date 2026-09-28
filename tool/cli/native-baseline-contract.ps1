Set-StrictMode -Version Latest

function Get-NativeBaselineHash([string]$LiteralPath) {
    $stream=[IO.File]::OpenRead($LiteralPath)
    $hash=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-','').ToLower() }
    finally { $hash.Dispose(); $stream.Dispose() }
}

function Get-NativeBaselineSourcePaths([string]$Repository) {
    $paths=@(& git -C $Repository ls-files --cached --others --exclude-standard -- lib assets android integration_test test/support pubspec.yaml pubspec.lock tool/cli/native-baseline-contract.ps1 tool/cli/run-native-baseline-acceptance.ps1)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate native source closure.' }
    return @($paths | Sort-Object -Unique)
}

# The adapter performs only explicit operations against this new development
# package. Preflight must finish before the first device mutation.
function Invoke-NativeBaselineContract {
    param([hashtable]$Context, [scriptblock]$Invoke)
    $package = 'com.lexiquest.app.nativeBaselineBm'
    if ($Context.Platform -cne 'android' -or $Context.DeviceId -cne '9582188822004C6') { throw 'Unexpected physical Android device.' }
    if ($Context.PackageId -cne $package -or $Context.ApkId -cne $package) { throw 'Package/APK identity rejected.' }
    if ($Context.Installed -contains $package) { throw 'Package collision; no replacement is allowed.' }
    if ($Context.RunId -cnotmatch '^bm-[a-z0-9-]{1,48}$') { throw 'Invalid synthetic run identity.' }
    if (-not $Context.SourceVerified -or -not $Context.IsolationVerified -or $Context.ApkSha -notmatch '^[a-f0-9]{64}$') { throw 'Unproven source/APK isolation.' }
    if ((& $Invoke 'hash' '') -cne $Context.ApkSha) { throw 'APK changed before install.' }
    if (-not (& $Invoke 'install' '').ok) { throw 'Install failed.' }
    $seed = $null
    foreach ($phase in @('seed','verify')) {
        if ($phase -eq 'verify' -and $null -eq $seed) { throw 'Verify requires successful closed seed.' }
        if (-not (& $Invoke 'launch' $phase).ok) { throw "Phase launch failed: $phase" }
        $receipt = & $Invoke 'receipt' $phase
        if ($receipt.status -cne 'PASS') { throw "Phase failed: $phase" }
        $requiredCases = if ($phase -eq 'seed') { @('N01','N02','N03') } else { @('N04') }
        foreach ($case in $requiredCases) {
            if ($receipt.cases[$case] -cne 'PASS') { throw "Native case did not pass: $case" }
        }
        if ($receipt.phase -cne $phase -or $receipt.runId -cne $Context.RunId -or $receipt.packageId -cne $package -or -not $receipt.closed) { throw 'Receipt identity/close mismatch.' }
        if ($receipt.externalCalls -ne 0 -or $receipt.researchRows -ne 0 -or $receipt.outboxRows -ne 0) { throw 'Isolation counters are nonzero.' }
        if ($phase -eq 'seed') {
            $seed = $receipt
            if (-not (& $Invoke 'pid' 'seed')) { throw 'Seed process unavailable before stop.' }
            if (-not (& $Invoke 'stop' '').ok) { throw 'Process stop failed.' }
            if ((& $Invoke 'pid' 'stopped')) { throw 'OS process exit unproven.' }
            if ((& $Invoke 'hash' '') -cne $Context.ApkSha) { throw 'APK changed across restart.' }
        } else {
            if ($receipt.fixtureDigest -cne $seed.fixtureDigest) { throw 'Fixture changed across process restart.' }
            if (-not (& $Invoke 'pid' 'verify')) { throw 'Relaunched process is unavailable.' }
        }
    }
    return @{status='PASS';runId=$Context.RunId;apkSha=$Context.ApkSha;seed=$seed;verify=$receipt}
}
