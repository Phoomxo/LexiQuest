Set-StrictMode -Version Latest
function Get-NativeDraftHash([string]$LiteralPath) {
  $stream=[IO.File]::OpenRead($LiteralPath); $hash=[Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-','').ToLower() }
  finally { $hash.Dispose(); $stream.Dispose() }
}
function Get-NativeDraftSourcePaths([string]$Repository) {
  $paths=@(& git -C $Repository ls-files --cached --others --exclude-standard -- lib assets android integration_test test/support pubspec.yaml pubspec.lock tool/cli/native-baseline-contract.ps1 tool/cli/run-native-baseline-acceptance.ps1 tool/cli/native-recovery-contract.ps1 tool/cli/run-native-recovery-acceptance.ps1 tool/cli/native-terminal-contract.ps1 tool/cli/run-native-terminal-acceptance.ps1 tool/cli/native-draft-contract.ps1 tool/cli/run-native-draft-acceptance.ps1 tool/cli/tests/native-recovery-contract.tests.ps1 tool/cli/tests/native-recovery-isolation.tests.ps1 tool/cli/tests/native-recovery-runner.tests.ps1 tool/cli/tests/native-terminal-contract.tests.ps1 tool/cli/tests/native-terminal-isolation.tests.ps1 tool/cli/tests/native-terminal-runner.tests.ps1 tool/cli/tests/native-draft-contract.tests.ps1 tool/cli/tests/native-draft-isolation.tests.ps1 tool/cli/tests/native-draft-runner.tests.ps1 tool/cli/tests/native-draft-cd-contract.tests.ps1)
  if($LASTEXITCODE -ne 0){throw 'Cannot enumerate native source closure.'}
  return @($paths | Sort-Object -Unique)
}
function Invoke-NativeDraftContract {
  param([hashtable]$Context,[scriptblock]$Invoke)
  $package=if($Context.RunId -cmatch '^ce-'){'com.lexiquest.app.nativeDraftCe'}elseif($Context.RunId -cmatch '^cd-'){'com.lexiquest.app.nativeDraftCd'}else{'com.lexiquest.app.nativeDraftCb'}
  if($Context.Platform -cne 'android' -or $Context.DeviceId -cne '9582188822004C6'){throw 'Wrong device'}
  if($Context.PackageId -cne $package -or $Context.ApkId -cne $package){throw 'Wrong isolated package'}
  if($Context.Installed -contains $package){throw 'Package collision'}
  if($Context.RunId -cnotmatch '^(cb|cd|ce)-[a-z0-9-]{1,48}$'){throw 'Invalid run'}
  if(-not $Context.SourceVerified -or -not $Context.IsolationVerified -or $Context.ApkSha -cnotmatch '^[a-f0-9]{64}$'){throw 'Unproven source/isolation'}
  if((& $Invoke 'hash' '') -cne $Context.ApkSha){throw 'APK changed'}
  if(-not (& $Invoke 'install' '').ok){throw 'Install failed'}
  $previous=$null; $receipts=[Collections.Generic.List[object]]::new()
  foreach($phase in @('seed','resume')){
    if(-not (& $Invoke 'launch' $phase).ok){throw 'Launch failed'}
    $r=& $Invoke 'receipt' $phase
    if($r.status -cne 'PASS' -or -not $r.closed){throw 'Failed or unclosed phase'}
    if($r.phase -cne $phase -or $r.runId -cne $Context.RunId -or $r.packageId -cne $package){throw 'Receipt identity mismatch'}
    if($r.externalCalls -ne 0 -or $r.researchRows -ne 0 -or $r.outboxRows -ne 0 -or $r.ordinaryLocalOutboxRows -ne 0){throw 'Isolation violation'}
    $cases=if($phase -eq 'seed'){@('D01','D02')}else{@('D03','D04','D05')}
    foreach($case in $cases){if($r.cases[$case] -cne 'PASS'){throw 'Missing native case'}}
    foreach($field in @('fixtureDigest','planDigest','progressDigest','nonCheckpointEventsDigest')){if($r[$field] -cnotmatch '^[a-f0-9]{64}$'){throw 'Invalid digest'}}
    if($r.ownerId -cne "local:synthetic-$($Context.RunId)-owner" -or $r.sessionId -cnotmatch '^session:[a-zA-Z0-9-]+$'){throw 'Owner/session mismatch'}
    if($r.index -ne 0 -or $r.progressPhase -cne 'awaitingAnswer' -or $r.terminalAcknowledged -or -not $r.selected){throw 'Draft state mismatch'}
    $tableCount=if($r.tableDigests -is [System.Collections.IDictionary]){$r.tableDigests.Count}else{@($r.tableDigests.PSObject.Properties).Count}
    if(@($r.answerRows).Count -ne 0 -or @($r.checkpointRows).Count -ne 2 -or $tableCount -ne 58){throw 'Draft write boundary mismatch'}
    if($phase -eq 'seed'){
      if(-not $r.transitions.syntheticPreCommitFailure){throw 'Pre-commit failure not observed'}
    }else{
      if($r.beforeFixtureDigest -cne $previous.fixtureDigest -or $r.beforeProgressDigest -cne $previous.progressDigest -or $r.fixtureDigest -cne $previous.fixtureDigest -or $r.progressDigest -cne $previous.progressDigest){throw 'Process restart changed sealed draft'}
      foreach($field in @('planDigest','ownerId','sessionId','selected','nonCheckpointEventsDigest')){if($r[$field] -cne $previous[$field]){throw 'Frozen identity drift'}}
      if(-not $r.transitions.wrongOwnerRejected -or -not $r.transitions.wrongSessionRejected){throw 'Stale identity rejection missing'}
    }
    if(-not (& $Invoke 'pid' $phase)){throw 'Running process missing'}
    $receipts.Add($r)
    if($phase -eq 'seed'){
      if(-not (& $Invoke 'stop' '').ok){throw 'Stop failed'}
      if((& $Invoke 'pid' 'stopped-seed')){throw 'Process exit unproven'}
      if((& $Invoke 'hash' '') -cne $Context.ApkSha){throw 'APK drift across restart'}
    }
    $previous=$r
  }
  return @{status='PASS';phases=$receipts;runId=$Context.RunId;apkSha=$Context.ApkSha}
}
