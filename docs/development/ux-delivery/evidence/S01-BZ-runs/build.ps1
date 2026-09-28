$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location -LiteralPath $repo
. ./tool/cli/native-recovery-contract.ps1
$source=@(Get-NativeRecoverySourcePaths $repo | ForEach-Object { @{path=$_;sha256=(Get-NativeRecoveryHash (Join-Path $repo $_))} })
$head=(git rev-parse HEAD).Trim()
@{head=$head;sourcePins=$source} | ConvertTo-Json -Depth 5 | Set-Content build/S01-BZ/build-source-pre.json
$oldApks=@(Get-Content build/S01-BZ/old-apks.json -Raw | ConvertFrom-Json)
foreach($pin in $oldApks) { if((Get-NativeRecoveryHash $pin.path) -cne $pin.sha256){throw "Prior APK changed before BZ: $($pin.path)"} }
$code=1
Push-Location android
try {
  & ./gradlew.bat :app:assembleDebug -PnativeRecoveryTest=true "-Ptarget=$repo/integration_test/native_recovery_acceptance_test.dart" -Ptarget-platform=android-arm64 -Ptrack-widget-creation=true --console=plain *> ../build/S01-BZ/build.log
  $code=$LASTEXITCODE
} finally { Pop-Location }
if($code -ne 0){ throw "BZ build failed with exit $code" }
foreach($pin in $source) { if((Get-NativeRecoveryHash $pin.path) -cne $pin.sha256){throw "Build source changed: $($pin.path)"} }
foreach($pin in $oldApks) { if((Get-NativeRecoveryHash $pin.path) -cne $pin.sha256){throw "Prior APK changed after BZ: $($pin.path)"} }
$apk='build/native-recovery/S01-BZ/gradle/app/outputs/apk/debug/app-debug.apk'
if(-not(Test-Path -LiteralPath $apk)){throw 'Expected isolated BZ APK missing'}
@{head=$head;sourcePins=$source;apk=$apk;apkSha256=(Get-NativeRecoveryHash $apk);oldApks=$oldApks;sourceDrift=0;buildExitCode=$code;command='android/gradlew.bat :app:assembleDebug -PnativeRecoveryTest=true -Ptarget=integration_test/native_recovery_acceptance_test.dart -Ptarget-platform=android-arm64 -Ptrack-widget-creation=true --console=plain'} | ConvertTo-Json -Depth 6 | Set-Content build/S01-BZ/build-manifest.json
'PASS: isolated build, source closure and all prior APK files preserved.'
