Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $repo 'tool/cli/native-draft-contract.ps1')
$appGradle=Get-Content (Join-Path $repo 'android/app/build.gradle.kts') -Raw
$rootGradle=Get-Content (Join-Path $repo 'android/build.gradle.kts') -Raw
$activity=Get-Content (Join-Path $repo 'android/app/src/nativeDraft/kotlin/com/lexiquest/app/NativeDraftActivity.kt') -Raw
$fixture=Get-Content (Join-Path $repo 'integration_test/support/native_draft_fixture.dart') -Raw
$integration=Get-Content (Join-Path $repo 'integration_test/native_draft_acceptance_test.dart') -Raw
$runner=Get-Content (Join-Path $repo 'tool/cli/run-native-draft-acceptance.ps1') -Raw
foreach($piece in @('nativeDraftCdTest','nativeDraftCd','src/nativeDraft/AndroidManifest.xml')) {
  if(-not $appGradle.Contains($piece)){throw "Missing CD debug identity: $piece"}
}
if(-not $rootGradle.Contains('build/native-draft/S01-CD/gradle')){throw 'CD output would overwrite an old APK'}
foreach($source in @($activity,$fixture,$runner)) {
  if(-not $source.Contains('nativeDraftCd')){throw 'CD identity missing in device/fixture/runner path'}
}
if(-not $integration.Contains('runIsolatedDraftPackage')){throw 'Integration test does not bind package to run identity'}
if(-not $activity.Contains('cd-') -or -not $fixture.Contains('cd-') -or -not $runner.Contains('$runPrefix')){throw 'CD run identity missing'}
if($activity -match 'super.configureFlutterEngine|GeneratedPluginRegistrant'){throw 'Automatic plugin registration forbidden'}
$ctx=@{Platform='android';DeviceId='9582188822004C6';PackageId='com.lexiquest.app.nativeDraftCd';ApkId='com.lexiquest.app.nativeDraftCd';Installed=@();RunId='cd-stub';ApkSha=('a'*64);SourceVerified=$true;IsolationVerified=$true}
$calls=[Collections.Generic.List[string]]::new()
$invoke={param($op,$phase)
  $calls.Add("$op/$phase")
  switch($op){
    'hash'{return $ctx.ApkSha}
    'install'{return @{ok=$true}}
    'launch'{return @{ok=$true}}
    'stop'{return @{ok=$true}}
    'pid'{if($phase -eq 'stopped-seed'){return ''};return '123'}
    'receipt'{
      $digests=@{};1..58|ForEach-Object{$digests["table$_"]='b'*64}
      return @{status='PASS';closed=$true;phase=$phase;runId=$ctx.RunId;packageId=$ctx.PackageId;externalCalls=0;researchRows=0;outboxRows=0;ordinaryLocalOutboxRows=0;fixtureDigest=('b'*64);progressDigest=('c'*64);beforeFixtureDigest=('b'*64);beforeProgressDigest=('c'*64);planDigest=('d'*64);nonCheckpointEventsDigest=('e'*64);ownerId="local:synthetic-$($ctx.RunId)-owner";sessionId="session:$($ctx.RunId)";selected='cat';index=0;progressPhase='awaitingAnswer';terminalAcknowledged=$false;answerRows=@();checkpointRows=@(1,2);tableDigests=$digests;transitions=@{syntheticPreCommitFailure=$true;wrongOwnerRejected=$true;wrongSessionRejected=$true};cases=@{D01='PASS';D02='PASS';D03='PASS';D04='PASS';D05='PASS'}}
    }
  }
}.GetNewClosure()
$result=Invoke-NativeDraftContract $ctx $invoke
if($result.status -ne 'PASS' -or @($calls | Where-Object {$_ -eq 'install/'}).Count -ne 1){throw 'CD contract did not make one install'}
$ctx.Installed=@('com.lexiquest.app.nativeDraftCd')
$calls.Clear()
try{Invoke-NativeDraftContract $ctx $invoke | Out-Null;throw 'CD collision accepted'}catch{if($_.Exception.Message -eq 'CD collision accepted'){throw}}
if($calls.Count -ne 0){throw 'CD collision reached device'}
foreach($piece in @('nativeDraftCeTest','nativeDraftCe')){if(-not $appGradle.Contains($piece)){throw "Missing CE debug identity: $piece"}}
if($appGradle -notmatch 'nativeDraftCeTest\) && name == "processDebugGoogleServices"'){throw 'CE could run Google Services task'}
if($appGradle -notmatch 'nativeDraftCeTest\) && allTasks.any'){throw 'CE release/profile guard missing'}
if(-not $rootGradle.Contains('build/native-draft/S01-CE/gradle')){throw 'CE output would overwrite an old APK'}
foreach($source in @($activity,$fixture,$runner)){if(-not $source.Contains('nativeDraftCe')){throw 'CE identity missing in device/fixture/runner path'}}
$ctx.PackageId='com.lexiquest.app.nativeDraftCe';$ctx.ApkId=$ctx.PackageId;$ctx.RunId='ce-stub';$ctx.Installed=@();$calls.Clear()
$result=Invoke-NativeDraftContract $ctx $invoke
if($result.status -ne 'PASS' -or @($calls | Where-Object {$_ -eq 'install/'}).Count -ne 1){throw 'CE contract did not make one install'}
$ctx.Installed=@($ctx.PackageId);$calls.Clear()
try{Invoke-NativeDraftContract $ctx $invoke | Out-Null;throw 'CE collision accepted'}catch{if($_.Exception.Message -eq 'CE collision accepted'){throw}}
if($calls.Count -ne 0){throw 'CE collision reached device'}
Write-Output 'PASS: CD/CE debug source and two-phase contracts, collision rejected'
