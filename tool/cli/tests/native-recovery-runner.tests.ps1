Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $repo 'tool/cli/native-recovery-contract.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bz-runner-stub-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$oldPath=$env:PATH
$original=@{}
foreach ($name in @('BZ_STUB_LOG','BZ_STUB_CASE')) { $original[$name]=[Environment]::GetEnvironmentVariable($name) }
try {
    $log=Join-Path $temp 'commands.txt'
    $env:BZ_STUB_LOG=$log
    $env:PATH="$temp;$oldPath"
    @'
$a=$args
Add-Content -LiteralPath $env:BZ_STUB_LOG -Value ($a -join ' ')
if ($a[2] -eq 'get-state') { 'device'; exit 0 }
if ($a[2] -eq 'install') { 'Success'; exit 0 }
switch ($a[3]) {
 'getprop' { switch ($a[4]) { 'ro.product.model' {'V2041'} 'ro.build.version.sdk' {'33'} 'ro.kernel.qemu' {'0'} }; exit 0 }
 'pm' { if ($env:BZ_STUB_CASE -eq 'success') { 'package:com.lexiquest.app' } else { 'package:com.lexiquest.app.nativeRecoveryBz' }; exit 0 }
 'dumpsys' { 'versionCode=23'; 'versionName=1.0'; 'lastUpdateTime=synthetic'; exit 0 }
 'am' {
   if ($a[4] -eq 'force-stop') { 'stopped' | Set-Content ($env:BZ_STUB_LOG+'.phase') }
   else { $a[-1] | Set-Content ($env:BZ_STUB_LOG+'.phase') }
   'Status: ok'; exit 0
 }
 'pidof' {
   $phase=(Get-Content ($env:BZ_STUB_LOG+'.phase') -Raw).Trim()
   switch($phase){'stopped'{exit 1};'seed'{'111'};'pending'{'222'};'next'{'333'}}
   exit 0
 }
 'run-as' {
   if (-not (Test-Path ($env:BZ_STUB_LOG+'.polled'))) {
     'polled' | Set-Content ($env:BZ_STUB_LOG+'.polled')
     [Console]::Error.WriteLine('missing-receipt'); exit 1
   }
   $phase=(Get-Content ($env:BZ_STUB_LOG+'.phase') -Raw).Trim()
   @{status='PASS';phase=$phase;runId='bz-synthetic-01';packageId='com.lexiquest.app.nativeRecoveryBz';closed=$true;externalCalls=0;researchRows=0;outboxRows=0;fixtureDigest=('b'*64);planDigest=('c'*64);progressDigest=('d'*64);beforeFixtureDigest=('b'*64);beforeProgressDigest=('d'*64);ownerId='local:synthetic-bz-synthetic-01-owner';sessionId='session:synthetic-bz-synthetic-01-session';index=$(if($phase -eq 'seed'){0}else{1});progressPhase=$(if($phase -eq 'seed'){'pending'}else{'awaitingAnswer'});cases=@{N01='PASS';N02='PASS';N03='PASS';N04='PASS';N06='PASS';N07='PASS'}} | ConvertTo-Json -Compress
   exit 0
 }
}
exit 90
'@ | Set-Content -LiteralPath (Join-Path $temp 'adb-stub.ps1') -Encoding Ascii
    @'
@echo off
powershell -NoProfile -File "%~dp0adb-stub.ps1" %*
exit /b %errorlevel%
'@ | Set-Content -LiteralPath (Join-Path $temp 'adb.cmd') -Encoding Ascii
    @'
@echo off
if "%~2"=="badging" (
 if "%BZ_STUB_CASE%"=="apk-id" (echo package: name='com.lexiquest.app'& exit /b 0)
 echo package: name='com.lexiquest.app.nativeRecoveryBz'
 echo application-debuggable
 if "%BZ_STUB_CASE%"=="internet" echo uses-permission: name='android.permission.INTERNET'
 if "%BZ_STUB_CASE%"=="storage" echo uses-permission: name='android.permission.READ_EXTERNAL_STORAGE'
 exit /b 0
)
echo E: activity ^(
echo com.lexiquest.app.NativeRecoveryActivity
if "%BZ_STUB_CASE%"=="provider" echo E: provider ^(
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $temp 'aapt.cmd') -Encoding Ascii
    $apk=Join-Path $temp 'synthetic.apk'
    'Synthetic stub bytes, not an APK' | Set-Content -LiteralPath $apk
    $source=@(Get-NativeRecoverySourcePaths $repo | ForEach-Object { @{path=$_;sha256=(Get-NativeRecoveryHash (Join-Path $repo $_))} })
    $pins=@{head=(& git -C $repo rev-parse HEAD);sourcePins=$source;apkSha256=(Get-NativeRecoveryHash $apk)}
    $manifest=Join-Path $temp 'pins.json'
    $pins | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifest
    foreach ($case in @('apk-id','internet','storage','provider','collision','success')) {
        $env:BZ_STUB_CASE=$case
        '' | Set-Content -LiteralPath $log
        $run=Join-Path $temp $case
        $ErrorActionPreference='Continue'
        & powershell -NoProfile -File (Join-Path $repo 'tool/cli/run-native-recovery-acceptance.ps1') -Apk $apk -SourceManifest $manifest -Aapt (Join-Path $temp 'aapt.cmd') -OutputDirectory $run *> (Join-Path $temp "$case.log")
        $ErrorActionPreference='Stop'
        if ($case -eq 'success') {
            if ($LASTEXITCODE -ne 0) { throw ('Successful runner failed: '+(Get-Content (Join-Path $temp "$case.log") -Raw)) }
            $result=Get-Content (Join-Path $run 'result.json') -Raw | ConvertFrom-Json
            if ($result.status -ne 'PASS' -or $result.pid_seed -ne '111' -or $result.'pid_stopped-seed' -ne '' -or $result.pid_pending -ne '222' -or $result.'pid_stopped-pending' -ne '' -or $result.pid_next -ne '333') { throw 'Restart PID evidence incorrect.' }
            if (@(Get-Content $log | Where-Object { $_ -match '\binstall\b' }).Count -ne 1) { throw 'Expected exactly one installation.' }
            if (@(Get-Content $log | Where-Object { $_ -match 'force-stop' }).Count -ne 2) { throw 'Expected two process stops.' }
            if ((Get-Content $log -Raw) -match 'install -r|pm clear|uninstall|shell input|logcat|screencap') { throw 'Forbidden command' }
            continue
        }
        if ($LASTEXITCODE -eq 0) { throw "$case was accepted" }
        $result=Get-Content (Join-Path $run 'result.json') -Raw | ConvertFrom-Json
        $expected=switch ($case) { 'collision' {'already installed'} default {'isolation rejected'} }
        if ($result.failure -notmatch $expected) { throw "Wrong rejection for $case : $($result.failure)" }
        if ((Get-Content $log -Raw) -match '\b(install|uninstall|clear|force-stop|start)\b') { throw "$case mutated device before rejection" }
    }
    Write-Output 'PASS: 6 executable runner cases including denied storage and delayed receipt/OS restart (stub adb/aapt only)'
    $global:LASTEXITCODE=0
} finally {
    $env:PATH=$oldPath
    foreach ($name in $original.Keys) { [Environment]::SetEnvironmentVariable($name,$original[$name]) }
}
