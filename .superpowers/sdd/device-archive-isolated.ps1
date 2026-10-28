param([Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Stem,[ValidateSet('debug','profile')][string]$Mode='debug')
$ErrorActionPreference='Stop'
$root='C:/Users/Phet/.codex/worktrees/02fa/LexiQuest'
$out="$root/build/verification/remediation-20260907"
$source="$root/build/app/outputs/flutter-apk/app-$Mode.apk"
$target="$out/$Stem-$Mode.apk"
if(Test-Path -LiteralPath $target){throw 'Archive exists'}
$builds=@(Get-ChildItem -LiteralPath $out -Directory -Filter "$Stem-build-*" | Sort-Object LastWriteTime -Descending)
if($builds.Count -ne 1){throw 'Require one unambiguous successful build for this stem'}
$build=Get-Content -LiteralPath ($builds[0].FullName+'/result.json') -Raw | ConvertFrom-Json
if($build.gateExitCode -ne 0 -or -not $build.sourceStable){throw 'Build source not verified'}
& 'C:/Users/Phet/AppData/Local/Android/Sdk/build-tools/36.0.0/apksigner.bat' verify --print-certs $source 1> "$out/$Stem-signature.log" 2> "$out/$Stem-signature.stderr.log"
if($LASTEXITCODE -ne 0){throw 'Signature verification failed'}
$expected=(Select-String -LiteralPath "$root/build/verification/788e90e62b1694c20945734787723c168b6a6ab2/device-20260907/installed-before-signature.stdout.log" -Pattern '^Signer #1 certificate SHA-256 digest:').Line
$actual=(Select-String -LiteralPath "$out/$Stem-signature.log" -Pattern '^Signer #1 certificate SHA-256 digest:').Line
if([string]::IsNullOrWhiteSpace($expected) -or $expected -ne $actual){throw 'Wrong signer'}
Copy-Item -LiteralPath $source -Destination $target
[ordered]@{stem=$Stem;mode=$Mode;sha256=(Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $target).Length;sourceFingerprint=$build.sourceFingerprint;sourceFileCount=$build.sourceFileCount;baseHead=$build.baseHead;buildEvidence=$build.evidence} | ConvertTo-Json | Set-Content "$out/$Stem-identity.json" -Encoding utf8
Write-Output "Archived $Stem $Mode with current-source evidence"
