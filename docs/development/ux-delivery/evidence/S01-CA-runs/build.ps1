$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../../../..')).Path
Set-Location -LiteralPath $repo
. ./tool/cli/native-terminal-contract.ps1
$out=Join-Path $repo 'build/S01-CA'
if(-not(Test-Path -LiteralPath $out)){New-Item -ItemType Directory -Path $out | Out-Null}
$source=@(Get-NativeTerminalSourcePaths $repo | ForEach-Object { @{path=$_;sha256=(Get-NativeTerminalHash (Join-Path $repo $_))} })
$head=(git rev-parse HEAD).Trim()
$oldPins=@(Get-Content docs/development/ux-delivery/evidence/S01-BZ-runs/old-apks.json -Raw | ConvertFrom-Json) + @(@{path='build/native-recovery/S01-BZ/gradle/app/outputs/apk/debug/app-debug.apk';sha256='97ad0d35438a334541f9b90c18229b0acdddc8d1473d78106ecc0d9830858b18'})
foreach($pin in $oldPins){if(-not(Test-Path -LiteralPath $pin.path) -or (Get-NativeTerminalHash $pin.path) -cne $pin.sha256){throw "Prior APK changed: $($pin.path)"}}
@{head=$head;sourcePins=$source;oldApks=$oldPins} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'build-source-pre.json')
$code=1
Push-Location android
try {
  & ./gradlew.bat :app:assembleDebug -PnativeTerminalTest=true "-Ptarget=$repo/integration_test/native_terminal_acceptance_test.dart" -Ptarget-platform=android-arm64 -Ptrack-widget-creation=true --console=plain *> ../build/S01-CA/build.log
  $code=$LASTEXITCODE
} finally { Pop-Location }
if($code -ne 0){throw "CA build failed with exit $code"}
foreach($pin in $source){if((Get-NativeTerminalHash (Join-Path $repo $pin.path)) -cne $pin.sha256){throw "Build source changed: $($pin.path)"}}
foreach($pin in $oldPins){if((Get-NativeTerminalHash $pin.path) -cne $pin.sha256){throw "Prior APK changed: $($pin.path)"}}
$apk='build/native-terminal/S01-CA/gradle/app/outputs/apk/debug/app-debug.apk'
if(-not(Test-Path -LiteralPath $apk)){throw 'Expected CA APK missing'}
@{head=$head;sourcePins=$source;apk=$apk;apkSha256=(Get-NativeTerminalHash $apk);oldApks=$oldPins;sourceDrift=0;buildExitCode=$code} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'build-manifest.json')
'PASS: isolated CA build and source/APK preservation'
