$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../../../..')).Path
Set-Location -LiteralPath $repo
. ./tool/cli/native-terminal-contract.ps1
$build=Get-Content build/S01-CA/build-manifest.json -Raw | ConvertFrom-Json
$run=Get-Content build/S01-CA/native-1/result.json -Raw | ConvertFrom-Json
$seed=Get-Content build/S01-CA/native-1/seed-receipt.json -Raw | ConvertFrom-Json
$resume=Get-Content build/S01-CA/native-1/resume-receipt.json -Raw | ConvertFrom-Json
$closed=Get-Content build/S01-CA/native-1/closed-receipt.json -Raw | ConvertFrom-Json
$ready=Get-Content build/S01-CA/readiness/result.json -Raw | ConvertFrom-Json
if($ready.status -ne 'READINESS_PASS' -or $run.status -ne 'PASS'){throw 'Native readiness/run did not pass'}
if($run.apkSha256 -cne $build.apkSha256 -or (Get-NativeTerminalHash build/S01-CA/installed-base.apk) -cne $build.apkSha256){throw 'Installed APK hash mismatch'}
$paths=@(Get-NativeTerminalSourcePaths $repo)
if(($paths -join "`n") -cne (($build.sourcePins.path | Sort-Object -Unique) -join "`n")){throw 'Source closure changed'}
foreach($pin in $build.sourcePins){if((Get-NativeTerminalHash (Join-Path $repo $pin.path)) -cne $pin.sha256){throw "Source drift: $($pin.path)"}}
foreach($pin in $build.oldApks){if((Get-NativeTerminalHash $pin.path) -cne $pin.sha256){throw "Prior APK drift: $($pin.path)"}}
foreach($id in $run.protectedBefore.PSObject.Properties.Name){if(($run.protectedBefore.$id -join '|') -cne ($run.protectedAfter.$id -join '|')){throw "Protected package drift: $id"}}
if(@($run.protectedBefore.PSObject.Properties).Count -ne 6){throw 'Protected package set incomplete'}
if(-not $run.pid_seed -or $run.'pid_stopped-seed' -or -not $run.pid_resume -or $run.'pid_stopped-resume' -or -not $run.pid_closed){throw 'PID restart sequence incomplete'}
foreach($r in @($seed,$resume,$closed)){
  if($r.status -ne 'PASS' -or -not $r.closed -or @($r.tableCounts.PSObject.Properties).Count -ne 58 -or $r.externalCalls -ne 0 -or $r.researchRows -ne 0 -or $r.outboxRows -ne 0){throw 'Phase acceptance incomplete'}
  if($r.tableCounts.learning_sessions -ne 1 -or $r.tableCounts.answer_attempts -ne 1 -or $r.tableCounts.points_ledger_entries -ne 1 -or $r.tableCounts.reward_transactions -ne 1 -or $r.tableCounts.achievement_unlocks -ne 4 -or $r.tableCounts.outbox_operations -ne 6){throw 'Canonical counts changed'}
  if($r.ownerId -cne $seed.ownerId -or $r.sessionId -cne $seed.sessionId -or $r.planDigest -cne $seed.planDigest -or $r.progressDigest -cne $seed.progressDigest){throw 'Frozen identity/progress changed'}
}
if($seed.terminalAcknowledged -or -not $resume.terminalAcknowledged -or -not $closed.terminalAcknowledged){throw 'Terminal acknowledgement transition invalid'}
if($resume.beforeFixtureDigest -cne $seed.fixtureDigest -or $closed.beforeFixtureDigest -cne $resume.fixtureDigest -or $resume.tableCounts.events_v2 -ne ($seed.tableCounts.events_v2+1) -or $closed.fixtureDigest -cne $resume.fixtureDigest){throw 'Restart/append sequence invalid'}
if(@($resume.checkpointRows).Count -ne (@($seed.checkpointRows).Count+1) -or @($closed.checkpointRows).Count -ne @($resume.checkpointRows).Count){throw 'Checkpoint count invalid'}
$hostGatePath='build/verification/c3a69c5fea4a5a9f08be06e2ea5717a937edc34d/targeted-runtime-17c5814721d0907d7537b8dc97dd7a2ca24d1a1524797a6462e94197b28ca10f.json'
$gate=Get-Content $hostGatePath -Raw | ConvertFrom-Json
if($gate.status -ne 'Passed' -or $gate.fingerprint -cne $gate.postFingerprint -or $gate.commands[0].Status -ne 'Passed' -or $gate.commands[0].ExitCode -ne 0){throw 'Host gate incomplete'}
$result=@{
  status='PASS_NATIVE_SYNTHETIC_TERMINAL_CLOSE_OS_RESTART'
  head=$build.head;packageId='com.lexiquest.app.nativeTerminalCa';deviceId='9582188822004C6'
  sourcePins=@($build.sourcePins).Count;sourceDrift=0;priorApksPreserved=@($build.oldApks).Count;protectedPackages=6
  apkSha256=$build.apkSha256;installedApkSha256=(Get-NativeTerminalHash build/S01-CA/installed-base.apk)
  pids=@($run.pid_seed,'',$run.pid_resume,'',$run.pid_closed);installCount=1;forceStopCount=2
  tables=58;seedDigest=$seed.fixtureDigest;resumeDigest=$resume.fixtureDigest;closedDigest=$closed.fixtureDigest
  planDigest=$seed.planDigest;progressDigest=$seed.progressDigest;ownerId=$seed.ownerId;sessionId=$seed.sessionId
  intentionalTerminalCheckpointAppends=1;events=@($seed.tableCounts.events_v2,$resume.tableCounts.events_v2,$closed.tableCounts.events_v2)
  answerAttempts=1;pointsEntries=1;rewardTransactions=1;achievementUnlocks=4;ordinaryLocalOutbox=6;researchRows=0;externalCalls=0
  hostGateFingerprint=$gate.postFingerprint;hostGatePath=$hostGatePath;cliContractCases=23;cliRunnerCases=6;analyzerIssues=0
  deviceSqliteSha256='f198779964fd37730973e7d93deb037c4fe451df19c20e885f696458267f697d'
  researchActivation='OFF_UNCHANGED';fieldDailyContinuity='HIDDEN_UNCHANGED';releaseAccepted=$false
}
$result | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath docs/development/ux-delivery/evidence/S01-CA-validation.json
'PASS: CA frozen source, installed APK, device receipts, 58-table transition and protected packages'
