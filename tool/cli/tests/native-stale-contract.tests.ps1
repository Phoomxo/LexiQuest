Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $repo 'tool/cli/native-stale-contract.ps1')
$runner=Get-Content -LiteralPath (Join-Path $repo 'tool/cli/run-native-stale-acceptance.ps1') -Raw
$cases=Get-Content -LiteralPath (Join-Path $repo 'integration_test/support/native_stale_cases.dart') -Raw
$test=Get-Content -LiteralPath (Join-Path $repo 'integration_test/native_stale_acceptance_test.dart') -Raw
$gradle=Get-Content -LiteralPath (Join-Path $repo 'android/app/build.gradle.kts') -Raw
if($runner -notmatch "native-stale-contract.ps1" -or $runner -notmatch 'nativeStaleCf' -or $runner -notmatch 'SourceManifest' -or $runner -notmatch 'installInvocation') {throw 'CF runner isolation/journal guard missing.'}
if($runner -notmatch 'nativeDraftCe' -or $runner -notmatch 'nativeDraftCd' -or $runner -notmatch 'Protected-Metadata') {throw 'CF protected package preflight missing.'}
if($cases -notmatch 'coveredRouteRejected' -or $cases -notmatch 'contentRevisionRejected' -or $cases -notmatch 'afterRejection,\s*afterRevision' -or $cases -notmatch 'afterRoute, before') {throw 'CF stale rejection assertions missing.'}
if($test -notmatch 'CF03' -or $test -notmatch 'CF05' -or $gradle -notmatch 'nativeStaleCfTest') {throw 'CF test identity missing.'}
$paths=Get-NativeStaleSourcePaths $repo
foreach($path in @('integration_test/native_stale_acceptance_test.dart','integration_test/support/native_stale_fixture.dart','integration_test/support/native_stale_cases.dart','tool/cli/native-stale-contract.ps1','tool/cli/run-native-stale-acceptance.ps1')) {
  if($paths -cnotcontains $path) {throw "CF source closure omitted $path"}
}
Write-Output 'PASS: CF source and runner contract guards'
