$ErrorActionPreference = 'Stop'
$runner = Join-Path (Split-Path $PSScriptRoot -Parent) 'verify-scope.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw $errors[0] }
foreach ($function in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    Invoke-Expression $function.Extent.Text
}
$repoRoot = Split-Path (Split-Path (Split-Path $runner -Parent) -Parent) -Parent
$scriptDir = Split-Path $runner -Parent
$TestName = ''; $CliOnly = $false; $RulesOnly = $false
$AndroidCompileOnly = $false; $LocalLearningPreview = $false; $PreviewBundleOnly = $false
$CliTestTargets = @()
$TestTargets = @('integration_test/field_trial_feature_controls_test.dart')
$selection = @(Get-VerificationCommands Targeted Integration)
if ($selection.Count -ne 1 -or $selection[0].Arguments -notcontains 'flutter-tester' -or $selection[0].Arguments -notcontains $TestTargets[0]) {
    throw 'Explicit local integration selection must target flutter-tester, not an arbitrary connected device'
}
if ('integration_test/support/field_trial_external_fakes.dart' -notmatch (Get-AreaPathPattern Integration)) {
    throw 'Integration helper changes must invalidate a cached local integration pass'
}
foreach ($pair in @(@('Release','Integration'), @('Targeted','Learning'), @('Subsystem','Integration'))) {
    $rejected = $false
    try { Get-VerificationCommands $pair[0] $pair[1] | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Local integration selection cannot replace another verification scope' }
}
$TestTargets = @('integration_test/../test/runtime/app_bootstrap_test.dart')
$rejected = $false
try { Get-VerificationCommands Targeted Integration | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Integration selection must reject parent traversal' }
$TestTargets = @()
foreach ($level in @('Targeted','Subsystem')) {
    Assert-CommandPaths @(Get-VerificationCommands $level Integration)
}
Write-Output 'PASS: bounded local integration device, input closure, scope/traversal rejection and existing default paths'
