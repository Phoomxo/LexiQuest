Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../native-draft-contract.ps1')
$count=0
foreach($fault in @('none','collision','source','isolation','device','package','seed-fail','resume-fail','unclosed','external','case','alive','fixtureDigest','progressDigest','planDigest','ownerId','sessionId','selected','phase','runId','packageId','index','progressPhase','answerRows','tableDigests','wrongOwnerRejected','wrongSessionRejected')) {
  $ctx=@{Platform='android';DeviceId='9582188822004C6';PackageId='com.lexiquest.app.nativeDraftCb';ApkId='com.lexiquest.app.nativeDraftCb';Installed=@();RunId='cb-test';ApkSha=('a'*64);SourceVerified=$true;IsolationVerified=$true}
  switch($fault){'collision'{$ctx.Installed=@($ctx.PackageId)} 'source'{$ctx.SourceVerified=$false} 'isolation'{$ctx.IsolationVerified=$false} 'device'{$ctx.DeviceId='wrong'} 'package'{$ctx.PackageId='com.lexiquest.app.nativeTerminalCa'}}
  $calls=[Collections.Generic.List[string]]::new()
  $adapter={param($op,$phase)
    $calls.Add("$op/$phase")
    switch($op){
      'hash'{return $ctx.ApkSha}
      'install'{return @{ok=$true}}
      'launch'{return @{ok=$true}}
      'stop'{return @{ok=$true}}
      'pid'{if($phase -eq 'stopped-seed' -and $fault -ne 'alive'){return ''};return '123'}
      'receipt'{
        $digests=@{}; 1..58 | ForEach-Object {$digests["table$_"]='b'*64}
        $r=@{status='PASS';closed=$true;phase=$phase;runId=$ctx.RunId;packageId=$ctx.PackageId;externalCalls=0;researchRows=0;outboxRows=0;ordinaryLocalOutboxRows=0;fixtureDigest=('b'*64);progressDigest=('c'*64);beforeFixtureDigest=('b'*64);beforeProgressDigest=('c'*64);planDigest=('d'*64);nonCheckpointEventsDigest=('e'*64);ownerId='local:synthetic-cb-test-owner';sessionId='session:cb-test';selected='cat';index=0;progressPhase='awaitingAnswer';terminalAcknowledged=$false;answerRows=@();checkpointRows=@(1,2);tableDigests=$digests;transitions=@{syntheticPreCommitFailure=$true;wrongOwnerRejected=$true;wrongSessionRejected=$true};cases=@{D01='PASS';D02='PASS';D03='PASS';D04='PASS';D05='PASS'}}
        if($fault -eq "$phase-fail"){$r.status='FAIL'}
        if($fault -eq 'unclosed'){$r.closed=$false}
        if($fault -eq 'external'){$r.externalCalls=1}
        if($fault -eq 'case'){$r.cases.D03='FAIL'}
        if($phase -eq 'resume' -and $fault -in @('fixtureDigest','progressDigest','planDigest','ownerId','sessionId','selected','phase','runId','packageId','index','progressPhase')){$r[$fault]='changed'}
        if($phase -eq 'resume' -and $fault -in @('wrongOwnerRejected','wrongSessionRejected')){$r.transitions[$fault]=$false}
        if($phase -eq 'resume' -and $fault -eq 'answerRows'){$r.answerRows=@(1)}
        if($phase -eq 'resume' -and $fault -eq 'tableDigests'){$r.tableDigests=@{one='b'*64}}
        return $r
      }
    }
  }.GetNewClosure()
  $caught=$false
  try { Invoke-NativeDraftContract $ctx $adapter | Out-Null } catch { $caught=$true }
  if($fault -eq 'none'){
    if($caught){throw 'Valid two-phase contract rejected'}
    if(($calls -join ',') -cne 'hash/,install/,launch/seed,receipt/seed,pid/seed,stop/,pid/stopped-seed,hash/,launch/resume,receipt/resume,pid/resume'){throw 'Wrong two-phase sequence'}
  }elseif(-not $caught){throw "Accepted fault: $fault"}
  if($fault -in @('collision','source','isolation','device','package') -and $calls.Count -ne 0){throw 'Preflight fault reached device'}
  if($fault -eq 'seed-fail' -and $calls.Contains('launch/resume')){throw 'Failed seed continued'}
  $count++
}
Write-Output "PASS: $count CB two-phase contract cases"