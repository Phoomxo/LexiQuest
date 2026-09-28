Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$implementation=Join-Path $PSScriptRoot '../native-terminal-contract.ps1'
if (-not (Test-Path -LiteralPath $implementation)) { throw 'RED: CA three-phase contract missing' }
. $implementation
$count=0
foreach($fault in @('none','collision','source','isolation','device','package','seed-fail','resume-fail','closed-fail','unclosed','external','case','alive','beforeFixtureDigest','beforeProgressDigest','planDigest','ownerId','sessionId','phase','runId','packageId','index','progressPhase')) {
  $ctx=@{Platform='android';DeviceId='9582188822004C6';PackageId='com.lexiquest.app.nativeTerminalCa';ApkId='com.lexiquest.app.nativeTerminalCa';Installed=@();RunId='ca-test';ApkSha=('a'*64);SourceVerified=$true;IsolationVerified=$true}
  switch($fault){'collision'{$ctx.Installed=@($ctx.PackageId)} 'source'{$ctx.SourceVerified=$false} 'isolation'{$ctx.IsolationVerified=$false} 'device'{$ctx.DeviceId='wrong'} 'package'{$ctx.PackageId='com.lexiquest.app.nativeTodayBy'}}
  $calls=[Collections.Generic.List[string]]::new()
  $adapter={param($op,$phase)
    $calls.Add("$op/$phase")
    switch($op){
      'hash'{return $ctx.ApkSha}
      'install'{return @{ok=$true}}
      'launch'{return @{ok=$true}}
      'stop'{return @{ok=$true}}
      'pid'{if($phase -like 'stopped*' -and $fault -ne 'alive'){return ''};return '123'}
      'receipt'{
        $r=@{status='PASS';closed=$true;phase=$phase;runId=$ctx.RunId;packageId=$ctx.PackageId;externalCalls=0;researchRows=0;outboxRows=0;fixtureDigest=('b'*64);progressDigest=('c'*64);beforeFixtureDigest=('b'*64);beforeProgressDigest=('c'*64);planDigest=('d'*64);ownerId='local:synthetic-ca-test-owner';sessionId='session:ca-test';index=0;progressPhase='closing';terminalAcknowledged=($phase -ne 'seed');cases=@{C01='PASS';C02='PASS';C03='PASS';C04='PASS';C05='PASS';C06='PASS';C07='PASS'}}
        if($fault -eq "$phase-fail"){$r.status='FAIL'}
        if($fault -eq 'unclosed'){$r.closed=$false}
        if($fault -eq 'external'){$r.externalCalls=1}
        if($fault -eq 'case'){$r.cases.C04='FAIL'}
        if($phase -eq 'resume' -and $r.ContainsKey($fault)){$r[$fault]='changed'}
        return $r
      }
    }
  }.GetNewClosure()
  $caught=$false
  try { Invoke-NativeTerminalContract $ctx $adapter | Out-Null } catch { $caught=$true }
  if($fault -eq 'none'){
    if($caught){throw 'Valid three-phase contract rejected'}
    if(($calls -join ',') -cne 'hash/,install/,launch/seed,receipt/seed,pid/seed,stop/,pid/stopped-seed,hash/,launch/resume,receipt/resume,pid/resume,stop/,pid/stopped-resume,hash/,launch/closed,receipt/closed,pid/closed'){throw 'Wrong three-phase sequence'}
  }elseif(-not $caught){throw "Accepted fault: $fault"}
  if($fault -in @('collision','source','isolation','device','package') -and $calls.Count -ne 0){throw 'Preflight fault reached device'}
  if($fault -eq 'seed-fail' -and $calls.Contains('launch/resume')){throw 'Failed seed continued'}
  if($fault -eq 'resume-fail' -and $calls.Contains('launch/closed')){throw 'Failed resume continued'}
  $count++
}
Write-Output "PASS: $count CA multi-phase contract cases"

