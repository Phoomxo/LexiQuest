$ErrorActionPreference = 'Stop'
$root = 'C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest'
Set-Location -LiteralPath $root
$dir = 'docs/development/ux-delivery/evidence'
$runs = "$dir/S01-BQ-runs"
$now = [DateTime]::UtcNow.ToString('o')
$thread = '01a0e0f5-20cf-7781-b9d3-4d80d71c6329'
$controller = '01a0ce9e-23a6-7931-88e6-6390da748f39'
$head = (git rev-parse HEAD).Trim()
$branch = (git branch --show-current).Trim()
if ($head -ne '4e70a26b0bf3c44c269bbcbaf9d6d37a273b4dd1' -or $branch -ne 'codex/ux-current-after-s01-bc') { throw 'Source changed' }
function Hash([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function SaveJson([string]$path, $value) { [IO.File]::WriteAllText((Join-Path $root $path), ($value | ConvertTo-Json -Depth 100) + "`n", [Text.UTF8Encoding]::new($false)) }
function Pin([string]$path) { @{path=$path;sha256=(Hash $path)} }
$predecessor = "$dir/S01-BP-checkpoint.json"
if ((Hash $predecessor) -ne 'b65f819e3bb724ad940eb52e4c1d9bec54b8321fd6716860ec72ea0722f1caaa') { throw 'Predecessor changed' }
$bp = Get-Content "$dir/S01-BP-validation.json" -Raw | ConvertFrom-Json
$bpCheckpoint = Get-Content $predecessor -Raw | ConvertFrom-Json
$preserved = @($bp.preservedPins) + @($bp.artifactPins) + @($bpCheckpoint.sourcePins)
foreach ($pin in $preserved) { if ((Hash $pin.path) -ne $pin.sha256) { throw "Preservation mismatch: $($pin.path)" } }
$gates = @()
$closure = @()
foreach ($name in @('final','reader','overview','profile')) {
  $line = Get-Content "$runs/verify-$name.log" | Where-Object { $_ -like 'Result: *' } | Select-Object -Last 1
  if (!$line) { throw "Missing gate $name" }
  $gatePath = $line.Substring(8).Trim()
  $gate = Get-Content -LiteralPath $gatePath -Raw | ConvertFrom-Json
  if ($gate.status -ne 'Passed' -or $gate.fingerprint -ne '1364cf977f9e3d5ecc4ee5c49785248bf8811bf3e28640e51d3e271478a0a2d0' -or $gate.postFingerprint -ne $gate.fingerprint) { throw "Invalid gate $name" }
  $command = $gate.commands[0]
  if ($command.Status -ne 'Passed' -or $command.ExitCode -ne 0 -or $command.postFingerprint -ne $gate.fingerprint) { throw "Invalid command $name" }
  $stdout = Get-Content -LiteralPath $command.Stdout -Raw
  if ($stdout -notmatch 'All tests passed!') { throw "Missing test completion $name" }
  Copy-Item -LiteralPath $gatePath -Destination "$runs/gate-$name.json"
  Copy-Item -LiteralPath $command.Stdout -Destination "$runs/$name.stdout.log"
  Copy-Item -LiteralPath $command.Stderr -Destination "$runs/$name.stderr.log"
  $gates += @{name=$name;status=$gate.status;fingerprint=$gate.fingerprint;postFingerprint=$gate.postFingerprint;tests=$(if($name -eq 'final'){2}else{1});gate="$runs/gate-$name.json";selection=$gate.selection}
  $closure = @($gate.inputClosure)
}
foreach ($pin in $closure) { if ((Hash $pin.path) -ne $pin.sha256) { throw "Source mismatch: $($pin.path)" } }
if ((Get-Content "$runs/analysis.log" -Raw) -notmatch 'No issues found!') { throw 'Analyzer not clean' }
# Preserve the failed plain-name selection, which ran zero tests.
$failedDir = 'build/verification/4e70a26b0bf3c44c269bbcbaf9d6d37a273b4dd1/2ba86d9c10fe-1364cf977f9e-0d98aa91'
Copy-Item "$failedDir/Explicit-Flutter-tests.stdout.log" "$runs/selection-failed.stdout.log"
Copy-Item "$failedDir/Explicit-Flutter-tests.stderr.log" "$runs/selection-failed.stderr.log"
git -c core.whitespace=cr-at-eol diff --check *> "$runs/diff-check.log"
if ($LASTEXITCODE -ne 0) { throw 'Diff check failed' }
$renderPins = @(Get-ChildItem "$runs/host-renders" -File | Sort-Object Name | ForEach-Object { Pin "$runs/host-renders/$($_.Name)" })
if ($renderPins.Count -ne 20) { throw 'Render count changed' }
$routing = 'Current-model deterministic fallback; Standard/default requested; runtime tier unverified; no Jev/billing/login/quota/ledger changes'
$claim = @{package='S01-BQ';threadId=$thread;controllerThreadId=$controller;recordedAtUtc=$now;writerStatus='RELEASED';authority='Controller assignment after BP RELEASED state141; no successor dispatch';worktree=$root;head=$head;branch=$branch;predecessorCheckpointSha256=(Hash $predecessor);preservedPinsVerified=$preserved.Count;routing=$routing}
SaveJson "$dir/S01-BQ-claim.json" $claim
$statePath = 'docs/development/ux-delivery/state.json'
$s = Get-Content $statePath -Raw | ConvertFrom-Json -AsHashtable
if ($s.revision -ne 141) { throw 'Concurrent state writer' }
$s.revision = 142
$s.currentItem = 'S01-BQ-populated-profile-host-audit'
$s.items = @(@{id=$s.currentItem;status='COMPLETE';acceptance='PASS_HOST_SYNTHETIC_ONLY';acceptanceScope='5 tests, 20 inspected host renders; populated Profile/details/overview; no production edits or native/user acceptance';report='docs/development/ux-delivery/S01-BQ.md'}) + @($s.items)
$s.writer = @{status='RELEASED';threadId=$thread;currentItem=$s.currentItem;sourceReceipt="$dir/S01-BQ-claim.json";predecessorReleased=$true;releasedAtUtc=$now;releaseReason='Bounded populated Profile host audit complete; finite remaining checklist; no successor';routing=$routing}
$s.evidence.reportPath = 'docs/development/ux-delivery/S01-BQ.md'
$s.evidence.sourceReceipt = "$dir/S01-BQ-claim.json"
$s.evidence.latestValidation = "$dir/S01-BQ-validation.json"
$s.evidence.latestBacklogReassessment = 'docs/development/ux-delivery/S01-BQ.md'
$s.nextAction = 'Controller review BQ checkpoint. Populated Profile host gap closed for representative synthetic data. Today routed success stays gated; native IME/TalkBack NOT_RUN; actual-user trials DEFERRED. No new host package or successor selected without a concrete finding.'
$s.checkpoint = @{sprintAccepted=$false;nativeProcessObservation='Not observed or changed by BQ';hostFlutterTests=5;hostRenderedImages=20;sourcePinsVerified=$closure.Count;writerRetained=$false;atUtc=$now;runningHostProcesses=@();kind='BQ_BOUNDED_HOST_POPULATED_PROFILE_PASS'}
$s.continuation.writerRetained = $false
$s.continuation.currentThreadId = $thread
$s.continuation.currentItem = $s.currentItem
$s.continuation.nextReadyPackage = $null
$s.nextDispatch = @{status='READY_FOR_CONTROLLER_REVIEW';successorThreadId=$null}
$s.BQCompletedAtUtc = $now
$s.BQAudit = @{host='PASS_5_TESTS_20_RENDERS';native='NOT_RUN';userParticipation='DEFERRED';report='docs/development/ux-delivery/S01-BQ.md';productionChangedFiles=@();allTablesUnchangedByUi=58;seedChangedOnly=@('learning_sessions','answer_attempts','learning_time_segments');todayRoutedSuccess='NOT_RUN_GATED';successorDispatched=$false;remainingChecklist=@('Today route gated','Native IME/TalkBack current snapshot','Actual-user trials deferred','Reviewed media/qualified trials','Provider/device/budget and frozen release prerequisites')}
SaveJson $statePath $s
$artifacts = @(Get-ChildItem $runs -File -Recurse | Sort-Object FullName | ForEach-Object { Pin ($_.FullName.Substring($root.Length+1).Replace('\','/')) })
$validation = @{schemaVersion=1;package='S01-BQ';atUtc=$now;worktree=$root;branch=$branch;head=$head;scope='HOST SYNTHETIC populated Profile/details/overview only';hostTests=5;renderCount=20;allFinalRendersInspectedVia='view_image';productionChangedFiles=@();gates=$gates;gateFingerprint=$gates[0].fingerprint;inputClosure=$closure;sourceClosureVerified=$closure.Count;preservedPins=$preserved;preExistingPinsVerified=$preserved.Count;artifactPins=$artifacts;renderPins=$renderPins;syntheticIsolation=@{tablesUnchangedByUi=58;seedChangedOnly=@('learning_sessions','answer_attempts','learning_time_segments');httpCalls=0;gatewayCalls=0;realParticipants=$false};analysis='No issues found in new harness';failedInvocation='Literal TestName regex selected zero tests; corrected names passed individually; failure logs retained';native='NOT_RUN';todayRoutedSuccess='NOT_RUN_GATED';userParticipation='DEFERRED';fullRelease='NOT_RUN';routing=$routing;hostBuildTestProcesses=@();generated7Preserved=$true}
SaveJson "$dir/S01-BQ-validation.json" $validation
$checkpoint = @{schemaVersion=1;package=$s.currentItem;atUtc=$now;threadId=$thread;controllerThreadId=$controller;worktree=$root;branch=$branch;head=$head;writerStatus='RELEASED';status='READY_FOR_CONTROLLER';engineering='COMPLETE_BOUNDED_HOST_AUDIT';hostTests=5;renderCount=20;gateFingerprint=$gates[0].fingerprint;sourceClosureVerified=$closure.Count;preExistingPinsVerified=$preserved.Count;sourcePins=@((Pin 'test/support/populated_profile_host_ui_audit_test.dart'));report='docs/development/ux-delivery/S01-BQ.md';reportSha256=(Hash 'docs/development/ux-delivery/S01-BQ.md');validation="$dir/S01-BQ-validation.json";validationSha256=(Hash "$dir/S01-BQ-validation.json");stateRevision=142;stateSha256=(Hash $statePath);readmeSha256=(Hash 'docs/development/ux-delivery/README.md');readyBacklogSha256=(Hash 'docs/development/ux-delivery/ready-backlog.md');claimSha256=(Hash "$dir/S01-BQ-claim.json");predecessorCheckpointSha256=(Hash $predecessor);productionSourceChanged=$false;hostBuildTestProcesses=@();nativeProcess='Not observed or changed';nativeDelta='NOT_RUN';userTrials='DEFERRED';openPrototypeDefects='UX-D01-D25 remain OPEN';routing=$routing;remaining=$s.BQAudit.remainingChecklist;nextExecutableStep=$s.nextAction;changedFiles=@('test/support/populated_profile_host_ui_audit_test.dart','docs/development/ux-delivery/S01-BQ.md',$statePath,'docs/development/ux-delivery/README.md','docs/development/ux-delivery/ready-backlog.md',"$dir/S01-BQ-*")}
SaveJson "$dir/S01-BQ-checkpoint.json" $checkpoint
[pscustomobject]@{checkpointSha256=(Hash "$dir/S01-BQ-checkpoint.json");validationSha256=$checkpoint.validationSha256;stateRevision=$s.revision;gates=$gates.Count;hostTests=5;renders=20;sourcePins=$closure.Count;preservedPins=$preserved.Count} | ConvertTo-Json
