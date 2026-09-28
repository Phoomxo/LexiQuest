$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location -LiteralPath $repo
$dest='docs/development/ux-delivery/evidence/S01-BZ-runs'
. ./tool/cli/native-recovery-contract.ps1
function Pin([string]$path) { @{path=$path;sha256=(Get-NativeRecoveryHash $path)} }
function Same($a,$b,[string]$reason) { if(($a | ConvertTo-Json -Depth 30 -Compress) -cne ($b | ConvertTo-Json -Depth 30 -Compress)){throw $reason} }
$native=Get-Content "$dest/native-1/result.json" -Raw | ConvertFrom-Json
$bm=Get-Content "$dest/build-manifest.json" -Raw | ConvertFrom-Json
$hg=Get-Content "$dest/host-gate.json" -Raw | ConvertFrom-Json
$cg=Get-Content "$dest/cli-gate.json" -Raw | ConvertFrom-Json
$device=Get-Content "$dest/device-final.json" -Raw | ConvertFrom-Json
$readiness=Get-Content "$dest/readiness/result.json" -Raw | ConvertFrom-Json
if($native.status -ne 'PASS' -or $readiness.status -ne 'READINESS_PASS'){throw 'Native/readiness not passed'}
if($device.installedApkSha256 -cne $bm.apkSha256){throw 'Installed mismatch'}
if(@($native.commands | Where-Object {$_.arguments[0] -eq 'install'}).Count -ne 1){throw 'Install count'}
$stops=@($native.commands | Where-Object {$_.arguments -contains 'force-stop'})
if($stops.Count -ne 2 -or @($stops | Where-Object {$_.arguments[-1] -cne 'com.lexiquest.app.nativeRecoveryBz'}).Count){throw 'Wrong stops'}
foreach($cmd in $native.commands){if(($cmd.arguments -join ' ') -match 'install -r|pm clear|uninstall|logcat|screencap|shell input'){throw 'Forbidden operation'}}
foreach($id in @('com.lexiquest.app','com.lexiquest.app.ariTest','com.lexiquest.app.nativeBaselineBm','com.lexiquest.app.nativeResumeBw','com.lexiquest.app.nativeTodayBy')){
  Same $native.protectedBefore.$id $native.protectedAfter.$id 'Protected metadata drift'
  Same $readiness.protectedBefore.$id $native.protectedBefore.$id 'Metadata drift since readiness'
}
$seed=Get-Content "$dest/native-1/seed-receipt.json" -Raw | ConvertFrom-Json
$pending=Get-Content "$dest/native-1/pending-receipt.json" -Raw | ConvertFrom-Json
$next=Get-Content "$dest/native-1/next-receipt.json" -Raw | ConvertFrom-Json
Same $seed.transitions.after $pending.transitions.before 'Pending process DB changed'
Same $pending.transitions.after $next.transitions.before 'Next process DB changed'
Same $next.transitions.before $next.transitions.after 'Next UI changed DB'
foreach($r in @($seed,$pending,$next)){
  if(@($r.tableDigests.PSObject.Properties).Count -ne 58){throw 'Table coverage'}
  if($r.tableCounts.answer_attempts -ne 1 -or $r.tableCounts.points_ledger_entries -ne 1 -or $r.tableCounts.reward_transactions -ne 1 -or $r.tableCounts.srs_states -ne 0){throw 'Duplicate effect'}
  if($r.externalCalls -ne 0 -or $r.researchRows -ne 0 -or $r.outboxRows -ne 0 -or -not $r.closed){throw 'Isolation/closure'}
}
Same $pending.transitions.before.operation $pending.transitions.replayed.operation 'Frozen operation changed'
Same $pending.transitions.before.answerRows $pending.transitions.replayed.answerRows 'Answer changed'
foreach($pair in @(@($pending.transitions.before,$pending.transitions.replayed),@($pending.transitions.replayed,$pending.transitions.after))){
  Same $pair[0].nonCheckpointEventsDigest $pair[1].nonCheckpointEventsDigest 'Evidence events changed'
  foreach($property in $pair[0].tableDigests.PSObject.Properties){if($property.Name -ne 'events_v2'){Same $property.Value $pair[1].tableDigests.($property.Name) 'Non-journal table changed'}}
  if($pair[1].checkpointRows.Count -ne $pair[0].checkpointRows.Count+1){throw 'Checkpoint append count'}
}
$drift=@()
foreach($pin in @($bm.sourcePins)+@($hg.inputClosure)){
  if((Get-NativeRecoveryHash $pin.path) -ine $pin.sha256){$drift+=$pin.path}
}
if($drift.Count){throw ('Executable source drift: '+($drift -join ','))}
$cliPublicationChanges=@()
foreach($pin in $cg.inputClosure){if((Get-NativeRecoveryHash $pin.path) -ine $pin.sha256){$cliPublicationChanges+=$pin.path}}
$allowedPublication=@('docs/development/ux-delivery/README.md','docs/development/ux-delivery/state.json')
if(@($cliPublicationChanges | Where-Object {$_ -notin $allowedPublication}).Count){throw 'Unexpected CLI source drift'}
foreach($gate in @($hg,$cg)){foreach($command in $gate.commands){if($command.Status -ne 'Passed' -or $command.ExitCode -ne 0 -or $command.fingerprint -cne $command.postFingerprint){throw 'Invalid gate'}}}
$base=Get-Content "$dest/baseline.json" -Raw | ConvertFrom-Json
$changed=@()
foreach($pin in $base){if(-not(Test-Path -LiteralPath $pin.path -PathType Leaf)){throw ('Missing baseline: '+$pin.path)};if((Get-NativeRecoveryHash $pin.path) -ine $pin.sha256){$changed+=$pin.path}}
$allowedChanges=@('android/app/build.gradle.kts','android/build.gradle.kts')+$allowedPublication
if(@($changed | Where-Object {$_ -notin $allowedChanges}).Count){throw ('Unrelated changed files: '+($changed -join ','))}
$old=Get-Content "$dest/old-apks.json" -Raw | ConvertFrom-Json
foreach($pin in $old){if((Get-NativeRecoveryHash $pin.path) -ine $pin.sha256){throw 'Old APK drift'}}
$artifacts=@(rg --files --hidden --no-ignore $dest | Sort-Object | ForEach-Object {Pin ($_.Replace('\','/'))})
$validation=@{
  schemaVersion=1;status='PASS_NATIVE_SYNTHETIC_PENDING_AND_NEXT_OS_RESTART';atUtc=[DateTime]::UtcNow.ToString('o');worktree=$repo;head=(& git rev-parse HEAD).Trim();branch=(& git branch --show-current).Trim();
  hostTests=51;cliContractCases=23;cliRunnerCases=6;isolationSuites=4;analyzer=@{files=4;issues=0;pin=(Pin "$dest/analyzer-final.log")};
  gatePrePost=@(@{scope='HOST';pre=$hg.fingerprint;post=$hg.commands[0].postFingerprint;pin=(Pin "$dest/host-gate.json")},@{scope='CLI';pre=$cg.fingerprint;post=$cg.commands[0].postFingerprint;pin=(Pin "$dest/cli-gate.json")});
  sourceClosure=@{nativeEntries=$bm.sourcePins.Count;hostEntries=$hg.inputClosure.Count;cliEntries=$cg.inputClosure.Count;executableMismatches=$drift;cliPostGateDocumentationChanges=$cliPublicationChanges;prePublicationAllMismatches=0};
  preservation=@{baselinePaths=$base.Count;changedOnly=$changed;oldApkFiles=$old.Count;protectedPackages=5;allRetainedPackages=6;byReceipt=(Pin 'docs/development/ux-delivery/evidence/S01-BY-checkpoint.json')};
  native=@{packageId=$native.packageId;deviceId=$native.deviceId;model='V2041';api=33;installCount=1;forceStopCount=2;pids=@($native.pid_seed,$native.'pid_stopped-seed',$native.pid_pending,$native.'pid_stopped-pending',$native.pid_next);apkSha256=$bm.apkSha256;tables=58;intentionalCheckpointAppends=2;pendingDigest=$seed.fixtureDigest;nextDigest=$next.fixtureDigest;ownerId=$seed.ownerId;sessionId=$seed.sessionId;planDigest=$seed.planDigest;databaseEvidence=(Pin "$dest/device-final.json")};
  productionLibChanges=@();releaseAccepted=$false;notRun=@('native terminal close/completion acknowledgement','native draft','native stale route','N05 visual','N05 IME','N05 TalkBack','mid-transaction/power-loss crash','frozen-source full release');deferred=@('actual-user/UAT/learning trials');
  artifacts=$artifacts
}
$validation | ConvertTo-Json -Depth 12 | Set-Content docs/development/ux-delivery/evidence/S01-BZ-validation.json
Write-Output ('PASS: final validation; baseline '+$base.Count+', native '+$bm.sourcePins.Count+', host '+$hg.inputClosure.Count+', CLI '+$cg.inputClosure.Count)
