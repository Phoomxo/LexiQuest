Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$implementation = Join-Path $PSScriptRoot '../native-resume-contract.ps1'
if (-not (Test-Path -LiteralPath $implementation)) { throw 'RED: native baseline contract is not implemented.' }
. $implementation
$script:cases = 0
function Check([bool]$condition, [string]$message) { if (-not $condition) { throw $message } }
function Run-Case([string]$name, [hashtable]$changes, [string]$failure, [bool]$rejectBeforeWrite) {
    $context = @{
        Platform='android'; DeviceId='9582188822004C6'; PackageId='com.lexiquest.app.nativeResumeBw';
        ApkId='com.lexiquest.app.nativeResumeBw'; Installed=@(); RunId='bw-synthetic-01';
        ApkSha=('a' * 64); SourceVerified=$true; IsolationVerified=$true
    }
    foreach ($key in $changes.Keys) { $context[$key] = $changes[$key] }
    $calls = [Collections.Generic.List[string]]::new()
    $invoke = {
        param($operation, $phase)
        $calls.Add("$operation/$phase")
        switch ($operation) {
            'install' { return @{ok=$true} }
            'launch' { return @{ok=$true} }
            'receipt' {
                if ($failure -eq $phase) { return @{status='FAIL'} }
                if ($failure -eq 'missing-seed') { return @{status='NOT_RUN'} }
                if ($failure -eq 'bad-case') { $caseResults=@{N01='FAIL';N02='PASS';N03='PASS'} } else { $caseResults=@{N01='PASS';N02='PASS';N03='PASS';N04='PASS'} }
                return @{status='PASS';phase=$phase;runId=$context.RunId;packageId=$context.PackageId;closed=($failure -ne 'unclosed');externalCalls=$(if ($failure -eq 'external') { 1 } else { 0 });researchRows=0;outboxRows=0;fixtureDigest=$(if ($phase -eq 'verify' -and $failure -eq 'digest') { 'changed' } else { ('b'*64) });planDigest=('c'*64);progressDigest=('d'*64);ownerId="local:synthetic-$($context.RunId)-owner";sessionId="session:synthetic-$($context.RunId)-session";cases=$caseResults}
            }
            'pid' { if ($phase -eq 'stopped' -and $failure -ne 'still-running') { return '' }; return '1234' }
            'stop' { return @{ok=$true} }
            'hash' { return $context.ApkSha }
        }
        throw 'Unknown operation'
    }.GetNewClosure()
    $caught=$null
    try { Invoke-NativeResumeContract -Context $context -Invoke $invoke | Out-Null } catch { $caught=$_.Exception.Message }
    if ($name -eq 'valid restart') {
        Check ($null -eq $caught) "$name failed: $caught"
        Check (($calls -join ',') -eq 'hash/,install/,launch/seed,receipt/seed,pid/seed,stop/,pid/stopped,hash/,launch/verify,receipt/verify,pid/verify') 'Restart sequence changed or reseeded.'
    } else { Check ($null -ne $caught) "$name was accepted" }
    if ($rejectBeforeWrite) { Check ($calls.Count -eq 0) "$name reached device adapter before rejection" }
    if ($failure -eq 'seed') { Check (-not $calls.Contains('launch/verify')) 'Failed seed advanced to verify' }
    Check (-not (($calls -join ',') -match 'clear|uninstall|reinstall')) 'Forbidden mutation'
    $script:cases++
}
Run-Case 'non Android' @{Platform='windows'} '' $true
Run-Case 'collision' @{Installed=@('com.lexiquest.app.nativeResumeBw')} '' $true
Run-Case 'production' @{PackageId='com.lexiquest.app'} '' $true
Run-Case 'ariTest' @{PackageId='com.lexiquest.app.ariTest'} '' $true
Run-Case 'APK mismatch' @{ApkId='com.lexiquest.app'} '' $true
Run-Case 'source mismatch' @{SourceVerified=$false} '' $true
Run-Case 'isolation unproven' @{IsolationVerified=$false} '' $true
Run-Case 'invalid run' @{RunId='../outside'} '' $true
Run-Case 'wrong device' @{DeviceId='emulator-5554'} '' $true
Run-Case 'seed failure' @{} 'seed' $false
Run-Case 'verify without seed receipt' @{} 'missing-seed' $false
Run-Case 'verify failure' @{} 'verify' $false
Run-Case 'phase case failure' @{} 'bad-case' $false
Run-Case 'unclosed database' @{} 'unclosed' $false
Run-Case 'external calls' @{} 'external' $false
Run-Case 'process still alive' @{} 'still-running' $false
Run-Case 'fixture changed' @{} 'digest' $false
Run-Case 'valid restart' @{} '' $false
foreach ($field in @('fixtureDigest','planDigest','progressDigest','ownerId','sessionId')) {
    $ctx=@{Platform='android';DeviceId='9582188822004C6';PackageId='com.lexiquest.app.nativeResumeBw';ApkId='com.lexiquest.app.nativeResumeBw';Installed=@();RunId='bw-check';ApkSha=('a'*64);SourceVerified=$true;IsolationVerified=$true}
    $adapter={ param($op,$phase)
        switch($op) {
            'hash' { return $ctx.ApkSha }
            'install' { return @{ok=$true} }
            'launch' { return @{ok=$true} }
            'stop' { return @{ok=$true} }
            'pid' { if($phase -eq 'stopped'){return ''}; return '123' }
            'receipt' {
                $r=@{status='PASS';phase=$phase;runId=$ctx.RunId;packageId=$ctx.PackageId;closed=$true;externalCalls=0;researchRows=0;outboxRows=0;fixtureDigest=('b'*64);planDigest=('c'*64);progressDigest=('d'*64);ownerId='local:synthetic-bw-check-owner';sessionId='session:synthetic-bw-check-session';cases=@{N01='PASS';N02='PASS';N03='PASS';N04='PASS'}}
                if($phase -eq 'verify'){$r[$field]='changed'}
                return $r
            }
        }
    }.GetNewClosure()
    $rejected=$false
    try { Invoke-NativeResumeContract $ctx $adapter | Out-Null } catch { $rejected=$true }
    Check $rejected "Changed $field accepted"
    $script:cases++
}
Write-Output "PASS: $script:cases native baseline runner contracts"
