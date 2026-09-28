Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $repo 'tool/cli/native-draft-contract.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('cb-runner-stub-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$oldPath=$env:PATH
$original=@{}
foreach ($name in @('CB_STUB_LOG','CB_STUB_CASE','CB_STUB_RUN_ID')) { $original[$name]=[Environment]::GetEnvironmentVariable($name) }
try {
    $log=Join-Path $temp 'commands.txt'
    $env:CB_STUB_LOG=$log
    $env:PATH="$temp;$oldPath"
    @'
$a=$args
Add-Content -LiteralPath $env:CB_STUB_LOG -Value ($a -join ' ')
if ($a[2] -eq 'get-state') { 'device'; exit 0 }
if ($a[2] -eq 'install') {
 if ($env:CB_STUB_CASE -in @('closed-install','cd-closed-install','ce-closed-install')) { [Console]::Error.WriteLine('error: closed'); exit 1 }
 'Success'; exit 0
}
switch ($a[3]) {
 'getprop' { switch ($a[4]) { 'ro.product.model' {'V2041'} 'ro.build.version.sdk' {'33'} 'ro.kernel.qemu' {'0'} }; exit 0 }
 'pm' { if ($env:CB_STUB_CASE -in @('success','failed-receipt') -or $env:CB_STUB_CASE -like 'closed-*' -or $env:CB_STUB_CASE -like 'cd-*' -or $env:CB_STUB_CASE -like 'ce-*') { 'package:com.lexiquest.app' } else { 'package:com.lexiquest.app.nativeDraftCb' }; exit 0 }
 'dumpsys' {
   $countFile=$env:CB_STUB_LOG+'.dumpsys'
   $count=if (Test-Path $countFile) {[int](Get-Content $countFile)} else {0}
   $count++; Set-Content $countFile $count
   if (($env:CB_STUB_CASE -eq 'closed-before' -and $count -eq 1) -or
       ($env:CB_STUB_CASE -in @('closed-install','closed-postcheck') -and $count -eq 9) -or
       ($env:CB_STUB_CASE -eq 'cd-closed-install' -and $count -eq 8) -or
       ($env:CB_STUB_CASE -eq 'ce-closed-install' -and $count -eq 9)) {
     [Console]::Error.WriteLine('error: closed'); exit 1
   }
   'versionCode=23'; 'versionName=1.0'; 'lastUpdateTime=synthetic'; exit 0
 }
 'am' {
   if ($a[4] -eq 'force-stop') { 'stopped' | Set-Content ($env:CB_STUB_LOG+'.phase') }
   else { $a[-1] | Set-Content ($env:CB_STUB_LOG+'.phase') }
   'Status: ok'; exit 0
 }
 'pidof' {
   $phase=(Get-Content ($env:CB_STUB_LOG+'.phase') -Raw).Trim()
   switch($phase){'stopped'{exit 1};'seed'{'111'};'resume'{'222'}}
   exit 0
 }
 'run-as' {
   if ($env:CB_STUB_CASE -eq 'failed-receipt') {
     @{status='FAIL';closed=$false;phase='seed';runId=$env:CB_STUB_RUN_ID;packageId='com.lexiquest.app.nativeDraftCb';failureType='StateError'} | ConvertTo-Json -Compress
     exit 0
   }
   if (-not (Test-Path ($env:CB_STUB_LOG+'.polled'))) {
     'polled' | Set-Content ($env:CB_STUB_LOG+'.polled')
     [Console]::Error.WriteLine('missing-receipt'); exit 1
   }
   $phase=(Get-Content ($env:CB_STUB_LOG+'.phase') -Raw).Trim()
   $digests=@{}; 1..58 | ForEach-Object { $digests["table$_"]='b'*64 }
   $pkg=if ($env:CB_STUB_CASE -like 'ce-*') {'com.lexiquest.app.nativeDraftCe'} elseif ($env:CB_STUB_CASE -like 'cd-*') {'com.lexiquest.app.nativeDraftCd'} else {'com.lexiquest.app.nativeDraftCb'}
   $runId=$env:CB_STUB_RUN_ID
   @{status='PASS';phase=$phase;runId=$runId;packageId=$pkg;closed=$true;externalCalls=0;researchRows=0;outboxRows=0;ordinaryLocalOutboxRows=0;fixtureDigest=('b'*64);planDigest=('c'*64);progressDigest=('d'*64);nonCheckpointEventsDigest=('e'*64);beforeFixtureDigest=('b'*64);beforeProgressDigest=('d'*64);ownerId="local:synthetic-$runId-owner";sessionId="session:synthetic-$runId-session";selected='cat';index=0;progressPhase='awaitingAnswer';terminalAcknowledged=$false;answerRows=@();checkpointRows=@(1,2);tableDigests=$digests;transitions=@{syntheticPreCommitFailure=$true;wrongOwnerRejected=$true;wrongSessionRejected=$true};cases=@{D01='PASS';D02='PASS';D03='PASS';D04='PASS';D05='PASS'}} | ConvertTo-Json -Depth 8 -Compress
   exit 0
 }
}
exit 90
'@ | Set-Content -LiteralPath (Join-Path $temp 'adb-stub.ps1') -Encoding Ascii
    @'
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0adb-stub.ps1" %*
exit /b %errorlevel%
'@ | Set-Content -LiteralPath (Join-Path $temp 'adb.cmd') -Encoding Ascii
    @'
@echo off
if "%~2"=="badging" (
 if "%CB_STUB_CASE%"=="apk-id" (echo package: name='com.lexiquest.app'& exit /b 0)
 if "%CB_STUB_CASE:~0,3%"=="ce-" (echo package: name='com.lexiquest.app.nativeDraftCe') else if "%CB_STUB_CASE:~0,3%"=="cd-" (echo package: name='com.lexiquest.app.nativeDraftCd') else (echo package: name='com.lexiquest.app.nativeDraftCb')
 echo application-debuggable
 if "%CB_STUB_CASE%"=="internet" echo uses-permission: name='android.permission.INTERNET'
 if "%CB_STUB_CASE%"=="storage" echo uses-permission: name='android.permission.READ_EXTERNAL_STORAGE'
 exit /b 0
)
echo E: activity ^(
echo com.lexiquest.app.NativeDraftActivity
if "%CB_STUB_CASE%"=="provider" echo E: provider ^(
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $temp 'aapt.cmd') -Encoding Ascii
    $apk=Join-Path $temp 'synthetic.apk'
    'Synthetic stub bytes, not an APK' | Set-Content -LiteralPath $apk
    $source=@(Get-NativeDraftSourcePaths $repo | ForEach-Object { @{path=$_;sha256=(Get-NativeDraftHash (Join-Path $repo $_))} })
    $pins=@{head=(& git -C $repo rev-parse HEAD);sourcePins=$source;apkSha256=(Get-NativeDraftHash $apk)}
    $manifest=Join-Path $temp 'pins.json'
    $pins | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifest
    foreach ($case in @('apk-id','internet','storage','provider','collision','success','closed-before','closed-install','closed-postcheck','cd-success','cd-closed-install','ce-success','ce-closed-install','failed-receipt')) {
        $env:CB_STUB_CASE=$case
        $env:CB_STUB_RUN_ID=if ($case -like 'ce-*') {'ce-synthetic-01'} elseif ($case -like 'cd-*') {'cd-synthetic-01'} else {'cb-synthetic-01'}
        '' | Set-Content -LiteralPath $log
        $countFile=$log+'.dumpsys'
        if (Test-Path $countFile) { Remove-Item -LiteralPath $countFile }
        $run=Join-Path $temp $case
        $ErrorActionPreference='Continue'
        $identity=if ($case -like 'ce-*') {'com.lexiquest.app.nativeDraftCe'} elseif ($case -like 'cd-*') {'com.lexiquest.app.nativeDraftCd'} else {'com.lexiquest.app.nativeDraftCb'}
        & powershell -NoProfile -File (Join-Path $repo 'tool/cli/run-native-draft-acceptance.ps1') -Apk $apk -SourceManifest $manifest -Aapt (Join-Path $temp 'aapt.cmd') -OutputDirectory $run -PackageId $identity -RunId $env:CB_STUB_RUN_ID *> (Join-Path $temp "$case.log")
        $ErrorActionPreference='Stop'
        if ($case -in @('success','cd-success','ce-success')) {
            if ($LASTEXITCODE -ne 0) { throw ('Successful runner failed: '+(Get-Content (Join-Path $temp "$case.log") -Raw)) }
            $result=Get-Content (Join-Path $run 'result.json') -Raw | ConvertFrom-Json
            if ($result.status -ne 'PASS' -or $result.packageId -ne $identity -or $result.pid_seed -ne '111' -or $result.'pid_stopped-seed' -ne '' -or $result.pid_resume -ne '222') { throw 'Restart PID evidence incorrect.' }
            $protectedExpected=if ($case -eq 'cd-success') {7} else {8}
            if (@($result.protectedBefore.PSObject.Properties).Count -ne $protectedExpected -or @($result.protectedAfter.PSObject.Properties).Count -ne $protectedExpected) { throw 'Installed CD not protected for other packages' }
            if (@(Get-Content $log | Where-Object { $_ -match '\binstall\b' }).Count -ne 1) { throw 'Expected exactly one installation.' }
            if (@(Get-Content $log | Where-Object { $_ -match 'force-stop' }).Count -ne 1) { throw 'Expected one process stop.' }
            if ((Get-Content $log -Raw) -match 'install -r|pm clear|uninstall|shell input|logcat|screencap') { throw 'Forbidden command' }
            continue
        }
        if ($LASTEXITCODE -eq 0) { throw "$case was accepted" }
        $result=Get-Content (Join-Path $run 'result.json') -Raw | ConvertFrom-Json
        if ($case -like 'closed-*' -or $case -in @('cd-closed-install','ce-closed-install')) {
            if ($result.status -ne 'FAIL' -or $result.failure -notmatch 'closed|metadata unavailable|Install failed') { throw "Missing primary failure for $case" }
            if ($case -eq 'closed-before' -and (Get-Content $log -Raw) -match '\binstall\b') { throw 'Install after failed preflight' }
            if ($case -in @('closed-install','cd-closed-install','ce-closed-install')) {
                if ($result.postcheckFailure -notmatch 'Protected package metadata unavailable') { throw 'Postcheck masked or lost' }
                if ($result.installInvocation.status -ne 'OUTCOME_UNKNOWN_OR_FAILED') { throw 'Install attempt was not recorded' }
                $journal=Get-Content (Join-Path $run 'install-attempt.json') -Raw | ConvertFrom-Json
                if ($journal.status -ne 'ATTEMPTED_OUTCOME_UNKNOWN' -or $journal.arguments[0] -ne 'install') { throw 'Install was not journaled before execution' }
                if ($result.installInvocation.exitCode -ne 1 -or $result.installInvocation.error -notmatch 'error: closed') { throw 'ADB install failure detail lost' }
                if (@(Get-Content $log | Where-Object { $_ -match '\binstall\b' }).Count -ne 1) { throw 'Install retried' }
            }
            if ($case -eq 'closed-postcheck' -and $result.postcheckFailure -notmatch 'Protected package metadata unavailable') { throw 'Postcheck failure missing' }
            if ($case -eq 'closed-postcheck' -and $result.installInvocation.status -ne 'SUCCESS_RETURNED') { throw 'Install result lost' }
            if ((Get-Content $log -Raw) -match 'install -r|pm clear|uninstall|shell input|logcat|screencap') { throw 'Forbidden command' }
            continue
        }
        if ($case -eq 'failed-receipt') {
            if ($result.status -ne 'FAIL' -or $result.failure -notmatch 'Failed or unclosed phase') { throw 'Failed receipt was masked by missing optional fields' }
            if (@(Get-Content $log | Where-Object { $_ -match '\binstall\b' }).Count -ne 1) { throw 'Failed receipt caused install retry' }
            if ((Get-Content $log -Raw) -match 'force-stop|uninstall|pm clear') { throw 'Failed receipt caused mutation' }
            continue
        }
        $expected=switch ($case) { 'collision' {'already installed'} default {'isolation rejected'} }
        if ($result.failure -notmatch $expected) { throw "Wrong rejection for $case : $($result.failure)" }
        if ((Get-Content $log -Raw) -match '\b(install|uninstall|clear|force-stop|start)\b') { throw "$case mutated device before rejection" }
    }
    Write-Output 'PASS: 14 executable CB/CD/CE runner cases including failed native receipt (stub adb/aapt only)'
    $global:LASTEXITCODE=0
} finally {
    $env:PATH=$oldPath
    foreach ($name in $original.Keys) { [Environment]::SetEnvironmentVariable($name,$original[$name]) }
}

