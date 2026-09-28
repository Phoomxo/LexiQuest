Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $repo 'tool/cli/native-terminal-contract.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ca-runner-stub-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$oldPath=$env:PATH
$original=@{}
foreach ($name in @('CA_STUB_LOG','CA_STUB_CASE')) { $original[$name]=[Environment]::GetEnvironmentVariable($name) }
try {
    $log=Join-Path $temp 'commands.txt'
    $env:CA_STUB_LOG=$log
    $env:PATH="$temp;$oldPath"
    @'
$a=$args
Add-Content -LiteralPath $env:CA_STUB_LOG -Value ($a -join ' ')
if ($a[2] -eq 'get-state') { 'device'; exit 0 }
if ($a[2] -eq 'install') { 'Success'; exit 0 }
switch ($a[3]) {
 'getprop' { switch ($a[4]) { 'ro.product.model' {'V2041'} 'ro.build.version.sdk' {'33'} 'ro.kernel.qemu' {'0'} }; exit 0 }
 'pm' { if ($env:CA_STUB_CASE -eq 'success') { 'package:com.lexiquest.app' } else { 'package:com.lexiquest.app.nativeTerminalCa' }; exit 0 }
 'dumpsys' { 'versionCode=23'; 'versionName=1.0'; 'lastUpdateTime=synthetic'; exit 0 }
 'am' {
   if ($a[4] -eq 'force-stop') { 'stopped' | Set-Content ($env:CA_STUB_LOG+'.phase') }
   else { $a[-1] | Set-Content ($env:CA_STUB_LOG+'.phase') }
   'Status: ok'; exit 0
 }
 'pidof' {
   $phase=(Get-Content ($env:CA_STUB_LOG+'.phase') -Raw).Trim()
   switch($phase){'stopped'{exit 1};'seed'{'111'};'resume'{'222'};'closed'{'333'}}
   exit 0
 }
 'run-as' {
   if (-not (Test-Path ($env:CA_STUB_LOG+'.polled'))) {
     'polled' | Set-Content ($env:CA_STUB_LOG+'.polled')
     [Console]::Error.WriteLine('missing-receipt'); exit 1
   }
   $phase=(Get-Content ($env:CA_STUB_LOG+'.phase') -Raw).Trim()
   @{status='PASS';phase=$phase;runId='ca-synthetic-01';packageId='com.lexiquest.app.nativeTerminalCa';closed=$true;externalCalls=0;researchRows=0;outboxRows=0;fixtureDigest=('b'*64);planDigest=('c'*64);progressDigest=('d'*64);beforeFixtureDigest=('b'*64);beforeProgressDigest=('d'*64);ownerId='local:synthetic-ca-synthetic-01-owner';sessionId='session:synthetic-ca-synthetic-01-session';index=0;progressPhase='closing';terminalAcknowledged=($phase -ne 'seed');cases=@{C01='PASS';C02='PASS';C03='PASS';C04='PASS';C05='PASS';C06='PASS';C07='PASS'}} | ConvertTo-Json -Compress
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
 if "%CA_STUB_CASE%"=="apk-id" (echo package: name='com.lexiquest.app'& exit /b 0)
 echo package: name='com.lexiquest.app.nativeTerminalCa'
 echo application-debuggable
 if "%CA_STUB_CASE%"=="internet" echo uses-permission: name='android.permission.INTERNET'
 if "%CA_STUB_CASE%"=="storage" echo uses-permission: name='android.permission.READ_EXTERNAL_STORAGE'
 exit /b 0
)
echo E: activity ^(
echo com.lexiquest.app.NativeTerminalActivity
if "%CA_STUB_CASE%"=="provider" echo E: provider ^(
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $temp 'aapt.cmd') -Encoding Ascii
    $apk=Join-Path $temp 'synthetic.apk'
    'Synthetic stub bytes, not an APK' | Set-Content -LiteralPath $apk
    $source=@(Get-NativeTerminalSourcePaths $repo | ForEach-Object { @{path=$_;sha256=(Get-NativeTerminalHash (Join-Path $repo $_))} })
    $pins=@{head=(& git -C $repo rev-parse HEAD);sourcePins=$source;apkSha256=(Get-NativeTerminalHash $apk)}
    $manifest=Join-Path $temp 'pins.json'
    $pins | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifest
    foreach ($case in @('apk-id','internet','storage','provider','collision','success')) {
        $env:CA_STUB_CASE=$case
        '' | Set-Content -LiteralPath $log
        $run=Join-Path $temp $case
        $ErrorActionPreference='Continue'
        & powershell -NoProfile -File (Join-Path $repo 'tool/cli/run-native-terminal-acceptance.ps1') -Apk $apk -SourceManifest $manifest -Aapt (Join-Path $temp 'aapt.cmd') -OutputDirectory $run *> (Join-Path $temp "$case.log")
        $ErrorActionPreference='Stop'
        if ($case -eq 'success') {
            if ($LASTEXITCODE -ne 0) { throw ('Successful runner failed: '+(Get-Content (Join-Path $temp "$case.log") -Raw)) }
            $result=Get-Content (Join-Path $run 'result.json') -Raw | ConvertFrom-Json
            if ($result.status -ne 'PASS' -or $result.pid_seed -ne '111' -or $result.'pid_stopped-seed' -ne '' -or $result.pid_resume -ne '222' -or $result.'pid_stopped-resume' -ne '' -or $result.pid_closed -ne '333') { throw 'Restart PID evidence incorrect.' }
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

