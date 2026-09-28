#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Apk,
    [Parameter(Mandatory=$true)][string]$SourceManifest,
    [Parameter(Mandatory=$true)][string]$Aapt,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$RunId='bm-synthetic-01',
    [switch]$InspectOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'native-baseline-contract.ps1')
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$package='com.lexiquest.app.nativeBaselineBm'
$serial='9582188822004C6'
$apkPath=(Resolve-Path -LiteralPath $Apk).Path
$aaptPath=(Resolve-Path -LiteralPath $Aapt).Path
$pins=Get-Content -LiteralPath $SourceManifest -Raw | ConvertFrom-Json
$commands=[Collections.Generic.List[object]]::new()
$phaseEvidence=[Collections.Generic.List[object]]::new()
$result=@{status='NOT_RUN';runId=$RunId;packageId=$package;deviceId=$serial;commands=$commands;phases=$phaseEvidence}
function Adb-Baseline([string[]]$Arguments) {
    $started=[DateTime]::UtcNow
    # adb reports an absent synthetic receipt/PID on stderr while the phase is
    # still running. Preserve its exit status so the bounded poll can decide.
    $ErrorActionPreference='Continue'
    $output=@(& adb -s $serial @Arguments 2>&1)
    $code=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    $commands.Add(@{arguments=$Arguments;exitCode=$code;atUtc=$started.ToString('o');durationMs=([DateTime]::UtcNow-$started).TotalMilliseconds})
    return @{code=$code;text=($output -join "`n").Trim()}
}
function Protected-Metadata {
    $values=@{}
    foreach ($id in @('com.lexiquest.app','com.lexiquest.app.ariTest')) {
        $probe=Adb-Baseline @('shell','dumpsys','package',$id)
        if ($probe.code -ne 0) { throw 'Protected package metadata unavailable.' }
        $values[$id]=@($probe.text -split "`n" | Where-Object { $_ -match '^\s*(versionCode=|versionName=|firstInstallTime=|lastUpdateTime=)' } | ForEach-Object { $_.Trim() })
        if ($values[$id].Count -lt 3) { throw 'Protected package metadata incomplete.' }
    }
    return $values
}
# Output directory must be fresh: receipts from earlier attempts cannot pass.
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Evidence output collision.' }
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
try {
    if ($RunId -cnotmatch '^bm-[a-z0-9-]{1,48}$') { throw 'Invalid run identity.' }
    if ((git -C $repo rev-parse HEAD) -cne $pins.head) { throw 'Source HEAD mismatch.' }
    if (@($pins.sourcePins).Count -lt 10) { throw 'Incomplete source manifest.' }
    $currentPaths=Get-NativeBaselineSourcePaths $repo
    if (($currentPaths -join "`n") -cne (($pins.sourcePins.path | Sort-Object -Unique) -join "`n") -or @($pins.sourcePins).Count -ne $currentPaths.Count) { throw 'Source closure changed or contains duplicates.' }
    foreach ($pin in $pins.sourcePins) {
        if ($pin.path -match '(^|[/\\])\.\.([/\\]|$)' -or [IO.Path]::IsPathRooted($pin.path)) { throw 'Invalid source pin path.' }
        $file=Join-Path $repo $pin.path
        if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-NativeBaselineHash $file) -ine $pin.sha256) { throw ('Source pin changed: '+$pin.path) }
    }
    $apkHash=Get-NativeBaselineHash $apkPath
    if ($apkHash -cne $pins.apkSha256) { throw 'APK does not match build receipt.' }
    $badging=(& $aaptPath dump badging $apkPath) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'APK identity inspection failed.' }
    $apkId=[regex]::Match($badging,"(?m)^package: name='([^']+)'").Groups[1].Value
    $merged=(& $aaptPath dump xmltree $apkPath AndroidManifest.xml) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Merged manifest inspection failed.' }
    $isolation=$apkId -ceq $package -and
        $badging -notmatch "uses-permission[^\r\n]+android.permission.(INTERNET|ACCESS_NETWORK_STATE|CAMERA|RECORD_AUDIO|POST_NOTIFICATIONS|RECEIVE_BOOT_COMPLETED)" -and
        $merged -notmatch 'E: (provider|receiver|service)\b' -and
        ([regex]::Matches($merged,'E: activity \(').Count -eq 1) -and
        $merged -match 'com.lexiquest.app.NativeBaselineActivity' -and
        $merged -notmatch 'android.intent.action.VIEW|android.intent.category.BROWSABLE' -and
        $badging -match 'application-debuggable'
    # No API keys/resources or VM logs are collected.
    $merged | Set-Content -LiteralPath (Join-Path $OutputDirectory 'merged-manifest.txt')
    $result.isolationVerified=$isolation
    $result.apkSha256=$apkHash
    $result.apkId=$apkId
    if (-not $isolation) { throw 'Merged APK isolation rejected.' }
    $state=Adb-Baseline @('get-state')
    $model=Adb-Baseline @('shell','getprop','ro.product.model')
    $api=Adb-Baseline @('shell','getprop','ro.build.version.sdk')
    $emulator=Adb-Baseline @('shell','getprop','ro.kernel.qemu')
    if ($state.text -cne 'device' -or $model.text -cne 'V2041' -or $api.text -cne '33' -or $emulator.text -eq '1') { throw 'Expected physical V2041/API33 is not ready.' }
    $installed=Adb-Baseline @('shell','pm','list','packages','com.lexiquest')
    if ($installed.code -ne 0) { throw 'Cannot inspect package collisions.' }
    $ids=@($installed.text -split "`n" | ForEach-Object { ($_ -replace '^package:','').Trim() })
    $result.protectedBefore=Protected-Metadata
    if ($ids -contains $package) { throw 'Isolated package already installed; no replacement allowed.' }
    if ($InspectOnly) { $result.status='READINESS_PASS'; return }
    $context=@{Platform='android';DeviceId=$serial;PackageId=$package;ApkId=$apkId;Installed=$ids;RunId=$RunId;ApkSha=$apkHash;SourceVerified=$true;IsolationVerified=$isolation}
    $adapter={
        param($operation,$phase)
        switch ($operation) {
            'hash' { return Get-NativeBaselineHash $apkPath }
            'install' {
                $r=Adb-Baseline @('install','-t',$apkPath)
                return @{ok=($r.code -eq 0 -and $r.text -match 'Success')}
            }
            'launch' {
                $r=Adb-Baseline @('shell','am','start','-W','-n',"$package/com.lexiquest.app.NativeBaselineActivity",'--es','baselineRun',$RunId,'--es','baselinePhase',$phase)
                return @{ok=($r.code -eq 0 -and $r.text -notmatch 'Error:|Exception')}
            }
            'receipt' {
                $started=[DateTime]::UtcNow
                do {
                    $r=Adb-Baseline @('shell','run-as',$package,'cat',"files/$RunId-$phase.json")
                    if ($r.code -eq 0) {
                        $receipt=$r.text | ConvertFrom-Json
                        $phaseEvidence.Add(@{phase=$phase;atUtc=[DateTime]::UtcNow.ToString('o');durationMs=([DateTime]::UtcNow-$started).TotalMilliseconds;receipt=$receipt})
                        $r.text | Set-Content -LiteralPath (Join-Path $OutputDirectory "$phase-receipt.json")
                        # PowerShell 5.1 compatibility: contract consumes a hashtable.
                        $table=@{}; foreach ($prop in $receipt.PSObject.Properties) { $table[$prop.Name]=$prop.Value }
                        $caseMap=@{}; foreach ($prop in $receipt.cases.PSObject.Properties) { $caseMap[$prop.Name]=$prop.Value }; $table.cases=$caseMap
                        return $table
                    }
                    Start-Sleep -Milliseconds 1000
                } while (([DateTime]::UtcNow-$started).TotalSeconds -lt 180)
                throw "Native receipt timed out: $phase"
            }
            'pid' {
                $r=Adb-Baseline @('shell','pidof',$package)
                if ($r.code -notin @(0,1)) { throw 'PID inspection failed.' }
                $result["pid_$phase"]=$r.text
                return $r.text
            }
            'stop' { $r=Adb-Baseline @('shell','am','force-stop',$package); return @{ok=($r.code -eq 0)} }
            default { throw 'Unknown native operation.' }
        }
    }
    $result.contract=Invoke-NativeBaselineContract -Context $context -Invoke $adapter
    $result.status='PASS'
} catch {
    $result.status='FAIL'
    $result.failure=$_.Exception.Message
    throw
} finally {
    if ($result.ContainsKey('protectedBefore')) {
        $result.protectedAfter=Protected-Metadata
        foreach ($id in @('com.lexiquest.app','com.lexiquest.app.ariTest')) {
            if (($result.protectedBefore[$id] -join '|') -cne ($result.protectedAfter[$id] -join '|')) { $result.status='FAIL'; $result.failure='Protected package metadata changed.' }
        }
    }
    $result | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'result.json')
}
if ($result.status -ne 'PASS') { throw 'Native baseline did not pass.' }
Write-Output 'PASS: native N01-N04; test package and synthetic evidence retained.'
