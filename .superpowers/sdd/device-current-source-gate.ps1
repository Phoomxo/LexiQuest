param(
 [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Label,
 [Parameter(Mandatory)][string]$Executable,
 [string[]]$ArgumentList=@()
)
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$root='C:/Users/Phet/.codex/worktrees/02fa/LexiQuest'
if([IO.Path]::GetFullPath((Get-Location).Path) -ne [IO.Path]::GetFullPath($root)){throw 'Wrong worktree'}
$stamp=[DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffZ',[Globalization.CultureInfo]::InvariantCulture)
$out=Join-Path $root "build/verification/remediation-20260907/$Label-$stamp"
New-Item -ItemType Directory -Path $out | Out-Null
function Snapshot {
 $files=@(& git ls-files -c -o --exclude-standard -- lib test integration_test android assets tool tools pubspec.yaml pubspec.lock analysis_options.yaml)
 if($LASTEXITCODE -ne 0){throw 'Source inventory failed'}
 $files += @(Get-ChildItem -LiteralPath "$root/.superpowers/sdd" -File -Filter 'device-*.dart' | ForEach-Object {'.superpowers/sdd/'+$_.Name})
 $files += '.dart_tool/package_config.json'
 $files += @('docs/generated/alltcas-8-44-final-test-plan.json','docs/generated/alltcas-8-44-final-test-plan.md','docs/generated/alltcas-idea-integration-feature-map.json')
 $deleted = [Collections.Generic.List[object]]::new()
 $knownDeletedPath = 'lib/learning/storage/learning_database.g.dart'
 $knownDeletedBlob = '8b137891791fe96927ad78e64b0aad7bded08bdc'
 $entries=@($files | Sort-Object -Unique | ForEach-Object {
   $full=[IO.Path]::GetFullPath((Join-Path $root $_))
   if(-not $full.StartsWith([IO.Path]::GetFullPath($root)+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Source outside worktree'}
   if(-not (Test-Path -LiteralPath $full -PathType Leaf)) {
     $existingItem = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
     if($_ -cne $knownDeletedPath -or $null -ne $existingItem){throw "Source missing: $_"}
     $index = @(& git ls-files --stage -- $_)
     if($LASTEXITCODE -ne 0 -or $index.Count -ne 1 -or $index[0] -cne "100644 $knownDeletedBlob 0`t$_") {
       throw "Unreviewed deleted source identity: $_"
     }
     $deleted.Add([ordered]@{path=$_;indexBlob=$knownDeletedBlob})
   } else {
     [ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()}
   }
 })
 $fingerprintEntries = @($entries | ForEach-Object {$_.path+[char]0+$_.sha256})
 $fingerprintEntries += @($deleted | ForEach-Object {$_.path+[char]0+'DELETED'+[char]0+$_.indexBlob})
 $canonical=($fingerprintEntries | Sort-Object) -join "\n"
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$fingerprint=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
 $head=((& git rev-parse HEAD)-join '').Trim()
 [ordered]@{baseHead=$head;fingerprint=$fingerprint;fileCount=$entries.Count;files=$entries;deletedTrackedFiles=@($deleted.ToArray())}
}
$before=Snapshot
$before | ConvertTo-Json -Depth 5 | Set-Content "$out/source-before.json" -Encoding utf8
$watch=[Diagnostics.Stopwatch]::StartNew()
& $Executable @ArgumentList 1> "$out/stdout.log" 2> "$out/stderr.log"
$nativeExit=$LASTEXITCODE
$watch.Stop()
$after=Snapshot
$after | ConvertTo-Json -Depth 5 | Set-Content "$out/source-after.json" -Encoding utf8
$stable=$before.fingerprint -eq $after.fingerprint -and $before.baseHead -eq $after.baseHead
$gateExit=if($nativeExit -eq 0 -and $stable){0}else{1}
$record=[ordered]@{label=$Label;command=$Executable;arguments=$ArgumentList;nativeExitCode=$nativeExit;gateExitCode=$gateExit;sourceStable=$stable;baseHead=$before.baseHead;sourceFingerprint=$before.fingerprint;sourceFileCount=$before.fileCount;durationSeconds=$watch.Elapsed.TotalSeconds;evidence=$out}
$record | ConvertTo-Json -Depth 4 | Set-Content "$out/result.json" -Encoding utf8
$record | ConvertTo-Json -Compress -Depth 4
exit $gateExit
