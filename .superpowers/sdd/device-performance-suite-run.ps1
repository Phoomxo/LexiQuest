$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$root = 'C:/Users/Phet/.codex/worktrees/02fa/LexiQuest'
Set-Location -LiteralPath $root
$adb = 'C:/Users/Phet/AppData/Local/Microsoft/WinGet/Packages/Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe/platform-tools/adb.exe'
$device = '9582188822004C6'
$prior = Join-Path $root 'build/verification/788e90e62b1694c20945734787723c168b6a6ab2/device-20260907'
$stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffZ', [Globalization.CultureInfo]::InvariantCulture)
$out = Join-Path $prior ('performance-suite-' + $stamp)
New-Item -ItemType Directory -Path $out | Out-Null
$fixture = Join-Path $prior 'performance-device-suite-v2-profile.apk'
$original = Join-Path $prior 'v2041-installed-before-testing.apk'
$fixtureIdentity = Get-Content (Join-Path $prior 'performance-device-suite-v2-identity.json') -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $fixture).Hash.ToLowerInvariant() -ne $fixtureIdentity.sha256) { throw 'Fixture hash mismatch' }
if ((Get-FileHash -LiteralPath $original).Hash.ToLowerInvariant() -ne '632edb07f6882890c98e467871f98da02502c792df9dadbb854b9f40f17872a1') { throw 'Original hash mismatch' }
$record = [ordered]@{startedUtc=[DateTimeOffset]::UtcNow.ToString('o'); userReauthorized=$true; device=$device; smokeExit=$null; error=$null; restored=$false; installedOriginalHash=$null; evidence=$out}
$installed = $false
$forward = $null
$priorFlutterLog = ((& $adb -s $device shell getprop log.tag.flutter) -join '').Trim()
try {
    & $adb -s $device shell setprop log.tag.flutter I
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enable scoped Flutter discovery log' }
    & $adb -s $device install -r -t $fixture 1> "$out/install.stdout.log" 2> "$out/install.stderr.log"
    if ($LASTEXITCODE -ne 0 -or (Get-Content "$out/install.stdout.log" -Raw) -notmatch '(?m)^Success\s*$') { throw 'Safe fixture install failed; no uninstall fallback' }
    $installed = $true
    & $adb -s $device shell run-as com.lexiquest.app test ! -e code_cache/lexiquest-core-service-20260907.json
    if ($LASTEXITCODE -ne 0) { throw 'Existing task discovery file requires reconciliation' }
    & $adb -s $device shell am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -f 0x20000000 --ez enable-dart-profiling true --ez enable-checked-mode true --ez verify-entry-points true com.lexiquest.app/.MainActivity 1> "$out/launch.stdout.log" 2> "$out/launch.stderr.log"
    if ($LASTEXITCODE -ne 0 -or (Get-Content "$out/launch.stdout.log" -Raw) -match 'Error:') { throw 'Fixture launch failed' }
    $serviceInfo = $null
    for ($attempt=0; $attempt -lt 20; $attempt++) {
        $rawInfo = ((& $adb -s $device shell run-as com.lexiquest.app cat code_cache/lexiquest-core-service-20260907.json 2> "$out/discovery.stderr.log") -join '')
        if ($LASTEXITCODE -eq 0) {
            try { $serviceInfo = $rawInfo | ConvertFrom-Json; break } catch { }
        }
        Start-Sleep -Seconds 1
    }
    if ($null -eq $serviceInfo) { throw 'Private fixture discovery file unavailable' }
    $parsedUri = [Uri]$serviceInfo.uri
    if ($parsedUri.Host -ne '127.0.0.1' -or $parsedUri.Scheme -ne 'http' -or $parsedUri.AbsolutePath -eq '/') { throw 'Expected loopback service with authentication path' }
    $uri = $parsedUri.AbsoluteUri
    $devicePort = $parsedUri.Port.ToString()
    $fixturePid = ((& $adb -s $device shell pidof com.lexiquest.app) -join '').Trim()
    if ($fixturePid -notmatch '^\d+$') { throw 'Cannot capture exact fixture process' }
    $forward = ((& $adb -s $device forward tcp:0 ('tcp:' + $devicePort)) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or $forward -notmatch '^\d+$') { throw 'Task forwarding failed' }
    $localUri = $uri.Replace(':' + $devicePort + '/', ':' + $forward + '/')
    $env:LEXIQUEST_DEVICE_RESPONSE_PATH = Join-Path $out 'response.json'
    Write-Output ('Running original core fixture on V2041; evidence ' + $out)
    & flutter drive --profile --no-dds --no-pub -d $device --use-existing-app=$localUri --driver=.superpowers/sdd/device-suite-driver.dart --no-keep-app-running 1> "$out/drive.stdout.log" 2> "$out/drive.stderr.log"
    $record.smokeExit = $LASTEXITCODE
    $testLogs = @(& $adb -s $device logcat -d --pid=$fixturePid -s flutter:I)
    $testLogs | Where-Object { $_ -notmatch 'VM service is listening' } | Set-Content "$out/core-fixture-test.log" -Encoding utf8
    $record.unhandledError = @($testLogs | Select-String 'Unhandled Exception').Count -gt 0
    $record.finalSentinelObserved = (Test-Path "$out/response.json") -and (Get-Content "$out/response.json" -Raw) -match 'adventurePerformance'
    $record.reporterFailures = (($testLogs -join "\n") + (Get-Content "$out/drive.stdout.log" -Raw)) -match '\[E\]|Some tests failed|EXCEPTION CAUGHT|failed after the test'
    $record.suiteVerified = $record.smokeExit -eq 0 -and $record.finalSentinelObserved -and -not $record.unhandledError -and -not $record.reporterFailures
    if (-not $record.suiteVerified) { throw 'Device suite has failures or incomplete sentinel evidence' }

} catch {
    $record.error = $_.Exception.Message
} finally {
    if ([string]::IsNullOrEmpty($priorFlutterLog)) { & $adb -s $device shell 'setprop log.tag.flutter ""' } else { & $adb -s $device shell setprop log.tag.flutter $priorFlutterLog }
    if ($null -ne $forward -and $forward -match '^\d+$') { & $adb -s $device forward --remove ('tcp:' + $forward) 1> "$out/remove-forward.log" }
    if ($installed) {
        & $adb -s $device shell am force-stop com.lexiquest.app
        & $adb -s $device shell run-as com.lexiquest.app rm -f code_cache/lexiquest-core-service-20260907.json
        & $adb -s $device install -r -t $original 1> "$out/restore.stdout.log" 2> "$out/restore.stderr.log"
        if ($LASTEXITCODE -eq 0 -and (Get-Content "$out/restore.stdout.log" -Raw) -match '(?m)^Success\s*$') {
            $path = ((& $adb -s $device shell pm path com.lexiquest.app) -join '').Trim()
            if ($path -match '^package:(/data/app/[^\s]+/base.apk)$') {
                $hash = ((& $adb -s $device shell sha256sum $Matches[1]) -join '').Trim()
                if ($hash -match '^([0-9a-f]{64})\s') {
                    $record.installedOriginalHash = $Matches[1]
                    $record.restored = $Matches[1] -eq '632edb07f6882890c98e467871f98da02502c792df9dadbb854b9f40f17872a1'
                }
            }
        }
    }
    $record.endedUtc = [DateTimeOffset]::UtcNow.ToString('o')
    $record | ConvertTo-Json -Depth 4 | Set-Content "$out/result.json" -Encoding utf8
    $record | ConvertTo-Json -Compress
}
if ($record.smokeExit -ne 0 -or $null -ne $record.error -or -not $record.restored) { exit 1 }
exit 0
