param([ValidateSet('focused','media','full','analyze')][string]$Check='focused')
$flutter='C:/Users/Phet/AppData/Local/Programs/flutter/bin/flutter.bat'
switch($Check) {
 'focused' {$argsForCheck=@('test','--no-pub','test/features/adventure/presentation/adventure_hub_screen_test.dart','test/features/adventure/presentation/adventure_map_list_parity_test.dart','test/features/adventure/presentation/adventure_companion_panel_test.dart','test/features/adventure/presentation/today_experience_host_test.dart','test/features/adventure/domain/adventure_reaction_test.dart','--reporter','expanded')}
 'media' {$argsForCheck=@('test','-d','flutter-tester','--no-pub','integration_test/field_trial_media_smoke_test.dart','--reporter','expanded')}
 'full' {$argsForCheck=@('test','--no-pub','--exclude-tags','release-excluded','--reporter','json')}
 'analyze' {$argsForCheck=@('analyze','--no-pub')}
}
& "$PSScriptRoot/device-current-source-gate.ps1" -Label ("remediation-"+$Check) -Executable $flutter -ArgumentList $argsForCheck
exit $LASTEXITCODE
