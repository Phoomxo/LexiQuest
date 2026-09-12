$ErrorActionPreference = 'Stop'
$path = Join-Path (Split-Path $PSScriptRoot -Parent) 'verify-scope.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw $errors[0] }
$functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
foreach ($function in $functions) { Invoke-Expression $function.Extent.Text }
$repoRoot = Split-Path (Split-Path (Split-Path $path -Parent) -Parent) -Parent
$scriptDir = Split-Path $path -Parent
$TestName = 'R15 final pair'
$TestTargets = @('test/screens/main_navigation_screen_test.dart', 'test/screens/learning_history_screen_test.dart')
$commands = @(Get-VerificationCommands -SelectedLevel Targeted -SelectedArea Learning)
if ($commands.Count -ne 1 -or $commands[0].Arguments[1] -ne $TestTargets[0]) { throw 'Explicit targets must select precisely the requested R15 files' }
if ($commands[0].Arguments -notcontains '--plain-name' -or $commands[0].Arguments -notcontains $TestName) { throw 'A focused reproduction must select the requested test name' }
$pattern = Get-AreaPathPattern -SelectedArea Learning
foreach ($dependency in @('lib/features/learning/pair_matching/presentation/pair_board_view.dart', 'assets/content/example.json', 'pubspec.lock', 'tool/cli/verify-scope.ps1')) {
    if ($dependency -notmatch $pattern) { throw "Fingerprint excludes $dependency" }
}
$TestTargets = @('test/does-not-exist.dart')
$rejected = $false
try { Get-VerificationCommands -SelectedLevel Targeted -SelectedArea Learning | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Missing explicit target must fail closed' }
$TestTargets = @()
$rejected = $false
try { Get-VerificationCommands -SelectedLevel Targeted -SelectedArea Learning | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'A test name must require explicit targets to preserve full-gate identity' }
Write-Output 'PASS: R15 target selection, dependency coverage and missing-target rejection'
