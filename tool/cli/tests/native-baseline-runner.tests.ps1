Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $repo 'tool/cli/native-baseline-contract.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bm-runner-stub-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$oldPath=$env:PATH
$original=@{}
foreach ($name in @('BM_STUB_LOG','BM_STUB_CASE')) { $original[$name]=[Environment]::GetEnvironmentVariable($name) }
try {
    $log=Join-Path $temp 'commands.txt'
    $env:BM_STUB_LOG=$log
    $env:PATH="$temp;$oldPath"
    @'
$a=$args
Add-Content -LiteralPath $env:BM_STUB_LOG -Value ($a -join ' ')
if ($a[2] -eq 'get-state') { 'device'; exit 0 }
if ($a[2] -eq 'install') { 'Success'; exit 0 }
switch ($a[3]) {
 'getprop' { switch ($a[4]) { 'ro.product.model' {'V2041'} 'ro.build.version.sdk' {'33'} 'ro.kernel.qemu' {'0'} }; exit 0 }
 'pm' { if ($env:BM_STUB_CASE -eq 'success') { 'package:com.lexiquest.app' } else { 'package:com.lexiquest.app.nativeBaselineBm' }; exit 0 }
 'dumpsys' { 'versionCode=23'; 'versionName=1.0'; 'lastUpdateTime=synthetic'; exit 0 }
 'am' {
   if ($a[4] -eq 'force-stop') { 'stopped' | Set-Content ($env:BM_STUB_LOG+'.stopped') }
   elseif ($a[-1] -eq 'verify') { 'verify' | Set-Content ($env:BM_STUB_LOG+'.verify') }
   'Status: ok'; exit 0
 }
 'pidof' {
   if (Test-Path ($env:BM_STUB_LOG+'.verify')) { '222'; exit 0 }
   if (Test-Path ($env:BM_STUB_LOG+'.stopped')) { exit 1 }
   '111'; exit 0
 }
 'run-as' {
   if (-not (Test-Path ($env:BM_STUB_LOG+'.polled'))) {
     'polled' | Set-Content ($env:BM_STUB_LOG+'.polled')
     [Console]::Error.WriteLine('missing-receipt'); exit 1
   }
   $phase=if (Test-Path ($env:BM_STUB_LOG+'.verify')) { 'verify' } else { 'seed' }
   @{status='PASS';phase=$phase;runId='bm-synthetic-01';packageId='com.lexiquest.app.nativeBaselineBm';closed=$true;externalCalls=0;researchRows=0;outboxRows=0;fixtureDigest='synthetic';cases=@{N01='PASS';N02='PASS';N03='PASS';N04='PASS'}} | ConvertTo-Json -Compress
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
 if "%BM_STUB_CASE%"=="apk-id" (echo package: name='com.lexiquest.app'& exit /b 0)
 echo package: name='com.lexiquest.app.nativeBaselineBm'
 echo application-debuggable
 if "%BM_STUB_CASE%"=="internet" echo uses-permission: name='android.permission.INTERNET'
 exit /b 0
)
echo E: activity ^(
echo com.lexiquest.app.NativeBaselineActivity
if "%BM_STUB_CASE%"=="provider" echo E: provider ^(
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $temp 'aapt.cmd') -Encoding Ascii
    $apk=Join-Path $temp 'synthetic.apk'
    'Synthetic stub bytes, not an APK' | Set-Content -LiteralPath $apk
    $source=@(Get-NativeBaselineSourcePaths $repo | ForEach-Object { @{path=$_;sha256=(Get-NativeBaselineHash (Join-Path $repo $_))} })
    $pins=@{head=(& git -C $repo rev-parse HEAD);sourcePins=$source;apkSha256=(Get-NativeBaselineHash $apk)}
    $manifest=Join-Path $temp 'pins.json'
    $pins | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifest
    foreach ($case in @('apk-id','internet','provider','collision','success')) {
        $env:BM_STUB_CASE=$case
        '' | Set-Content -LiteralPath $log
        $run=Join-Path $temp $case
        $ErrorActionPreference='Continue'
        & powershell -NoProfile -File (Join-Path $repo 'tool/cli/run-native-baseline-acceptance.ps1') -Apk $apk -SourceManifest $manifest -Aapt (Join-Path $temp 'aapt.cmd') -OutputDirectory $run *> (Join-Path $temp "$case.log")
        $ErrorActionPreference='Stop'
        if ($case -eq 'success') {
            if ($LASTEXITCODE -ne 0) { throw ('Successful runner failed: '+(Get-Content (Join-Path $temp "$case.log") -Raw)) }
            $result=Get-Content (Join-Path $run 'result.json') -Raw | ConvertFrom-Json
            if ($result.status -ne 'PASS' -or $result.pid_seed -ne '111' -or $result.pid_stopped -ne '' -or $result.pid_verify -ne '222') { throw 'Restart PID evidence incorrect.' }
            if (@(Get-Content $log | Where-Object { $_ -match '\binstall\b' }).Count -ne 1) { throw 'Expected exactly one installation.' }
            continue
        }
        if ($LASTEXITCODE -eq 0) { throw "$case was accepted" }
        $result=Get-Content (Join-Path $run 'result.json') -Raw | ConvertFrom-Json
        $expected=switch ($case) { 'collision' {'already installed'} default {'isolation rejected'} }
        if ($result.failure -notmatch $expected) { throw "Wrong rejection for $case : $($result.failure)" }
        if ((Get-Content $log -Raw) -match '\b(install|uninstall|clear|force-stop|start)\b') { throw "$case mutated device before rejection" }
    }
    Write-Output 'PASS: 5 executable runner cases including delayed receipt and OS restart (stub adb/aapt only)'
    $global:LASTEXITCODE=0
} finally {
    $env:PATH=$oldPath
    foreach ($name in $original.Keys) { [Environment]::SetEnvironmentVariable($name,$original[$name]) }
}
