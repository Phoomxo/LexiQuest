param([ValidatePattern('^[a-z0-9-]+$')][string]$Stem='manual-ui-v5',[ValidatePattern('^[a-z0-9-]+$')][string]$PreviousStem='manual-ui-v4')
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$adb='C:/Users/Phet/AppData/Local/Microsoft/WinGet/Packages/Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe/platform-tools/adb.exe'
$serial='9582188822004C6'
$base='C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/remediation-20260907'
$out="$base/$stem-device"
if(Test-Path -LiteralPath $out){throw 'Existing update evidence requires reconciliation'}
$identity=Get-Content -LiteralPath "$base/$stem-identity.json" -Raw | ConvertFrom-Json
$apk="$base/$stem-debug.apk"
if((Get-FileHash -LiteralPath $apk).Hash.ToLowerInvariant() -ne $identity.sha256){throw 'Fixture archive changed'}
$original='C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/788e90e62b1694c20945734787723c168b6a6ab2/device-20260907/v2041-installed-before-testing.apk'
if((Get-FileHash -LiteralPath $original).Hash.ToLowerInvariant() -ne '632edb07f6882890c98e467871f98da02502c792df9dadbb854b9f40f17872a1'){throw 'Original backup changed'}
$installedPath=((& $adb -s $serial shell pm path com.lexiquest.app)-join '').Trim()
if($installedPath -notmatch '^package:(/data/app/[^\s]+/base\.apk)$'){throw 'Unexpected installed path'}
$installedHash=((& $adb -s $serial shell sha256sum $Matches[1])-join '').Split(' ')[0].Trim()
$priorIdentity=Get-Content -LiteralPath "$base/$PreviousStem-identity.json" -Raw | ConvertFrom-Json
if($installedHash -ne $priorIdentity.sha256){throw 'Installed app is not the known previous manual fixture'}
$prior=((& $adb -s $serial shell run-as com.lexiquest.app cat code_cache/lexiquest-manual-uat-owned-20260907.json)-join '') | ConvertFrom-Json
foreach($owned in $prior.roots){if($owned -notmatch '^/data/user/0/com\.lexiquest\.app/code_cache/lexiquest-manual-uat-[a-zA-Z0-9]+$'){throw 'Unexpected manual fixture root'}}
New-Item -ItemType Directory -Path $out | Out-Null
$prior | ConvertTo-Json | Set-Content "$out/prior-owned-roots.json" -Encoding utf8
& $adb -s $serial install -r -t $apk 1> "$out/install.log" 2> "$out/install.stderr.log"
if($LASTEXITCODE -ne 0 -or (Get-Content "$out/install.log" -Raw) -notmatch '(?m)^Success\s*$'){throw 'Install did not confirm success; reconcile before retry'}
& $adb -s $serial shell am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER com.lexiquest.app/.MainActivity 1> "$out/launch.log"
if($LASTEXITCODE -ne 0){throw 'Launch failed'}
$ready=$false
for($attempt=0;$attempt -lt 30;$attempt++){
  $fixturePid=((& $adb -s $serial shell pidof com.lexiquest.app)-join '').Trim()
  if($fixturePid -match '^\d+$'){
    $ready=@(& $adb -s $serial logcat -d --pid=$fixturePid -s flutter:I | Select-String 'MANUAL_UAT_READY').Count -gt 0
    if($ready){break}
  }
  Start-Sleep -Seconds 1
}
$newPath=((& $adb -s $serial shell pm path com.lexiquest.app)-join '').Trim()
if($newPath -notmatch '^package:(/data/app/[^\s]+/base\.apk)$'){throw 'Unexpected updated path'}
$newHash=((& $adb -s $serial shell sha256sum $Matches[1])-join '').Split(' ')[0].Trim()
if($newHash -ne $identity.sha256){throw 'Installed hash differs from fixture'}
[ordered]@{ready=$ready;device=$serial;pid=$fixturePid;priorSha256=$installedHash;installedSha256=$newHash;originalBackup=$original;priorRootsPreserved=$true;originalRestored=$false} | ConvertTo-Json | Set-Content "$out/setup.json" -Encoding utf8
if(-not $ready){throw 'No readiness marker; inspect installed app without repeating install'}
Write-Output "Updated $serial to $stem; retained prior fixture roots and original APK backup."
