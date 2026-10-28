$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$root = 'C:/Users/Phet/.codex/worktrees/02fa/LexiQuest'
if ([IO.Path]::GetFullPath((Get-Location).Path) -ne [IO.Path]::GetFullPath($root)) { throw 'Wrong worktree' }
$flutter = 'C:/Users/Phet/AppData/Local/Programs/flutter/bin/flutter.bat'
$dart = 'C:/Users/Phet/AppData/Local/Programs/flutter/bin/dart.bat'
$records = [Collections.Generic.List[object]]::new()
$evidence = "$root/build/verification/contextual-practice-20260908"
function Invoke-CurrentGate([string]$label, [string[]]$arguments) {
    & "$root/.superpowers/sdd/device-current-source-gate.ps1" -Label $label -Executable $flutter -ArgumentList $arguments
    if ($LASTEXITCODE -ne 0) { throw "Verification failed: $label" }
    $folder = Get-ChildItem -LiteralPath "$root/build/verification/remediation-20260907" -Directory -Filter "$label-*" | Sort-Object Name -Descending | Select-Object -First 1
    $record = Get-Content -LiteralPath (Join-Path $folder.FullName 'result.json') -Raw | ConvertFrom-Json
    $records.Add($record)
    ConvertTo-Json -InputObject @($records.ToArray()) -Depth 6 | Set-Content -LiteralPath "$evidence/final-gates.json" -Encoding utf8
}
$sourceHead = ((& git rev-parse HEAD) -join '').Trim()
& $dart run tool/final_test_plan/generate_final_test_plan.dart --write --source-commit $sourceHead
if ($LASTEXITCODE -ne 0) { throw 'Test plan generation failed' }
& $dart run tool/final_test_plan/generate_final_test_plan.dart --check --source-commit $sourceHead
if ($LASTEXITCODE -ne 0) { throw 'Test plan check failed' }
& $dart run tool/feature_contract/generate_feature_map.dart --check
if ($LASTEXITCODE -ne 0) { throw 'Feature map check failed' }
Invoke-CurrentGate 'contextual-focused-final' @('test','--no-pub','--timeout','90s','--reporter','expanded','test/features/learning/sentence_practice_panel_test.dart','test/features/learning/cloze_mode_adapter_test.dart','test/screens/fill_in_the_blanks_screen_test.dart','test/screens/word_scramble_screen_test.dart','test/features/adventure/application/adventure_mixed_review_prompt_catalog_test.dart','test/screens/choose_mode_screen_test.dart','test/scenarios/production_feature_navigation_test.dart')
Invoke-CurrentGate 'contextual-analyze-final' @('analyze','--no-pub','lib','test','integration_test','test_driver','assets','tool','tools')
Invoke-CurrentGate 'contextual-accessibility-final' @('test','--no-pub','--timeout','90s','--reporter','expanded','test/screens/accessibility_smoke_test.dart')
Invoke-CurrentGate 'contextual-visual-final' @('test','--no-pub','--reporter','expanded','.superpowers/sdd/contextual-visual-test.dart','.superpowers/sdd/contextual-media-visual-test.dart')
Invoke-CurrentGate 'contextual-regression-final' @('test','--no-pub','--exclude-tags','release-excluded','--reporter','json')
$regression = $records | Where-Object label -eq 'contextual-regression-final'
& "$root/.superpowers/sdd/pm8-summarize-flutter.ps1" -JsonlPath (Join-Path $regression.evidence 'stdout.log') -OutputPrefix "$evidence/full-final"
if ($LASTEXITCODE -ne 0) { throw 'Regression inventory failed' }
Invoke-CurrentGate 'contextual-core-final' @('test','-d','flutter-tester','--no-pub','--timeout','90s','--reporter','expanded','integration_test/field_trial_core_journey_test.dart')
Invoke-CurrentGate 'contextual-controls-final' @('test','-d','flutter-tester','--no-pub','--timeout','90s','--reporter','expanded','integration_test/field_trial_feature_controls_test.dart')
Invoke-CurrentGate 'contextual-media-final' @('test','-d','flutter-tester','--no-pub','--timeout','90s','--reporter','expanded','integration_test/field_trial_media_smoke_test.dart')
Invoke-CurrentGate 'contextual-apk-final' @('build','apk','--debug','--no-pub')
$apkSource = "$root/build/app/outputs/flutter-apk/app-debug.apk"
$apkTarget = "$evidence/lexiquest-contextual-practice-debug.apk"
Copy-Item -LiteralPath $apkSource -Destination $apkTarget
$sourceHash = (Get-FileHash -LiteralPath $apkSource -Algorithm SHA256).Hash.ToLowerInvariant()
$targetHash = (Get-FileHash -LiteralPath $apkTarget -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sourceHash -ne $targetHash) { throw 'APK archive hash mismatch' }
[ordered]@{path=$apkTarget;bytes=(Get-Item -LiteralPath $apkTarget).Length;sha256=$targetHash;sourceFingerprint=$records[0].sourceFingerprint} | ConvertTo-Json | Set-Content -LiteralPath "$evidence/final-apk-identity.json" -Encoding utf8
if (@($records | Select-Object -ExpandProperty sourceFingerprint -Unique).Count -ne 1) { throw 'Final source fingerprints differ' }
'FINAL_VERIFICATION_COMPLETE'
