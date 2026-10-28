param([ValidatePattern('^[a-z0-9-]+$')][string]$Stem='manual-uat-v2')
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$root='C:/Users/Phet/.codex/worktrees/02fa/LexiQuest'
$adb='C:/Users/Phet/AppData/Local/Microsoft/WinGet/Packages/Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe/platform-tools/adb.exe'
$device='9582188822004C6'
$base="$root/build/verification/remediation-20260907"
$stamp=[DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffZ',[Globalization.CultureInfo]::InvariantCulture)
$out="$base/$Stem-manual-$stamp"
New-Item -ItemType Directory -Path $out | Out-Null
$identity=Get-Content "$base/$Stem-identity.json" -Raw | ConvertFrom-Json
$fixture="$base/$Stem-debug.apk"
if((Get-FileHash -LiteralPath $fixture).Hash.ToLowerInvariant() -ne $identity.sha256){throw 'Manual fixture hash differs'}
$original="$root/build/verification/788e90e62b1694c20945734787723c168b6a6ab2/device-20260907/v2041-installed-before-testing.apk"
if((Get-FileHash -LiteralPath $original).Hash.ToLowerInvariant() -ne '632edb07f6882890c98e467871f98da02502c792df9dadbb854b9f40f17872a1'){throw 'Original APK hash differs'}
& $adb -s $device shell run-as com.lexiquest.app test ! -e code_cache/lexiquest-manual-uat-owned-20260907.json
if($LASTEXITCODE -ne 0){throw 'Prior manual fixture needs reconciliation'}
$record=[ordered]@{startedUtc=[DateTimeOffset]::UtcNow.ToString('o');device=$device;fixture=$fixture;fixtureSha256=$identity.sha256;original=$original;installed=$false;ready=$false;pid=$null;error=$null;evidence=$out}
try {
 & $adb -s $device install -r -t $fixture 1> "$out/install.stdout.log" 2> "$out/install.stderr.log"
 if($LASTEXITCODE -ne 0 -or (Get-Content "$out/install.stdout.log" -Raw) -notmatch '(?m)^Success\s*$'){throw 'Safe install failed; no uninstall fallback'}
 $record.installed=$true
 & $adb -s $device shell am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER com.lexiquest.app/.MainActivity 1> "$out/launch.stdout.log" 2> "$out/launch.stderr.log"
 if($LASTEXITCODE -ne 0){throw 'Manual fixture launch failed'}
 for($i=0;$i -lt 30;$i++){
   $appPid=((& $adb -s $device shell pidof com.lexiquest.app)-join '').Trim()
   if($appPid -match '^\d+$'){
     $record.pid=$appPid
     $ready=@(& $adb -s $device logcat -d --pid=$appPid -s flutter:I | Select-String 'MANUAL_UAT_READY')
     if($ready.Count -gt 0){$record.ready=$true;break}
   }
   Start-Sleep -Seconds 1
 }
 if(-not $record.ready){throw 'Manual app readiness not observed; inspect exact fixture process'}
} catch {$record.error=$_.Exception.Message}
$record | ConvertTo-Json | Set-Content "$out/setup.json" -Encoding utf8
$record | ConvertTo-Json -Compress
if(-not $record.ready){exit 1}
