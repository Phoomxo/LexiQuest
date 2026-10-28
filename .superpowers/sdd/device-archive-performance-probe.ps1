param([Parameter(Mandatory)][ValidateSet('native','performance')][string]$Suite,[ValidateSet('v1','v2','v3')][string]$Revision='v1')
$ErrorActionPreference='Stop'
$root='C:/Users/Phet/.codex/worktrees/02fa/LexiQuest'
Set-Location -LiteralPath $root
$out=Join-Path $root 'build/verification/788e90e62b1694c20945734787723c168b6a6ab2/device-20260907'
$mode=if($Suite -eq 'performance'){'profile'}else{'debug'}
$source=Join-Path $root "build/app/outputs/flutter-apk/app-$mode.apk"
$stem=if($Revision -eq 'v1'){"$Suite-device-suite"}else{"$Suite-device-suite-$Revision"}
$target=Join-Path $out "$stem-$mode.apk"
if(-not (Test-Path -LiteralPath $source)){throw 'Built APK missing'}
if(Test-Path -LiteralPath $target){throw 'Archive exists; reconcile before overwriting'}
$signer='C:/Users/Phet/AppData/Local/Android/Sdk/build-tools/36.0.0/apksigner.bat'
& $signer verify --verbose --print-certs $source 1> "$out/$stem-signature.stdout.log" 2> "$out/$stem-signature.stderr.log"
if($LASTEXITCODE -ne 0){throw 'APK signature verification failed'}
$expected=(Select-String -LiteralPath "$out/installed-before-signature.stdout.log" -Pattern '^Signer #1 certificate SHA-256 digest:').Line
$actual=(Select-String -LiteralPath "$out/$stem-signature.stdout.log" -Pattern '^Signer #1 certificate SHA-256 digest:').Line
if([string]::IsNullOrWhiteSpace($expected) -or $actual -ne $expected){throw 'APK signer differs from original'}
Copy-Item -LiteralPath $source -Destination $target
$wrapper=Join-Path $root ".superpowers/sdd/device-performance-probe-suite.dart"
[ordered]@{createdUtc=[DateTimeOffset]::UtcNow.ToString('o');suite=$Suite;revision=$Revision;mode=$mode;sha256=(Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $target).Length;wrapper=$wrapper;wrapperSha256=(Get-FileHash -LiteralPath $wrapper).Hash.ToLowerInvariant();checkout='788e90e62b1694c20945734787723c168b6a6ab2';source='1875a61854490e0493cc084bffb705f5d3bd4b0b';fingerprint='50ddab9318080e5dd7cd4b640cfb63dbbf52fb9613d7d61fa8064a59132d22fc'} | ConvertTo-Json | Set-Content "$out/$stem-identity.json" -Encoding utf8
Write-Output "Archived signed $Suite $mode APK"
