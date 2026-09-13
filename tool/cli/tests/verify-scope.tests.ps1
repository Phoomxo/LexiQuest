$ErrorActionPreference = 'Stop'
$runner = Join-Path (Split-Path $PSScriptRoot -Parent) 'verify-scope.ps1'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw $errors[0] }
foreach ($function in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    Invoke-Expression $function.Extent.Text
}
$repoRoot = Split-Path (Split-Path (Split-Path $runner -Parent) -Parent) -Parent
$scriptDir = Split-Path $runner -Parent
$hashFixture = Join-Path $repoRoot ('build/hash-vector-' + [guid]::NewGuid().ToString('N'))
[IO.File]::WriteAllBytes($hashFixture, [Text.Encoding]::ASCII.GetBytes('abc'))
if ((Get-VerificationFileHash -LiteralPath $hashFixture).Hash -ne 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD') { throw 'Portable file fingerprint differs from the standard SHA256 abc vector' }
Remove-Item -LiteralPath $hashFixture

$TestTargets = @(); $TestName = ''; $CliOnly = $false
$RulesOnly = $true
$rulesSelection = @(Get-VerificationCommands Targeted Economy)
if ($rulesSelection.Count -ne 1 -or $rulesSelection[0].Name -ne 'Firestore rules tests') { throw 'RulesOnly must isolate the local rules emulator from Flutter/trusted-writer suites' }
$rejected = $false
try { Get-VerificationCommands Release Economy | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'RulesOnly cannot replace a release gate' }
$RulesOnly = $false
$AndroidCompileOnly = $true
$nativeSelection = @(Get-VerificationCommands Targeted Integration)
if ($nativeSelection.Count -ne 1 -or $nativeSelection[0].Arguments -notcontains ':app:compileDebugKotlin' -or $nativeSelection[0].Arguments -notcontains '-x' -or $nativeSelection[0].Arguments -notcontains 'compileFlutterBuildDebug') { throw 'AndroidCompileOnly must isolate native Kotlin compile without Flutter packaging' }
foreach ($level in @('Subsystem','Release')) {
    $rejected = $false
    try { Get-VerificationCommands $level Integration | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'AndroidCompileOnly must not replace broader gates' }
}
$RulesOnly = $true
$rejected = $false
try { Get-VerificationCommands Targeted Economy | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Mixed native/rules selectors must fail' }
$RulesOnly = $false
$AndroidCompileOnly = $false
$LocalLearningPreview = $true
$TestTargets = @('test/runtime/app_bootstrap_test.dart')
$previewSelection = @(Get-VerificationCommands Targeted Runtime)
if ($previewSelection[0].Arguments -notcontains '--dart-define-from-file=tool/cli/profiles/local-learning-preview.json') { throw 'Preview must compile the canonical local profile' }
$TestTargets = @()
$rejected = $false
try { Get-VerificationCommands Release All | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Preview selector cannot replace release gate' }
$RulesOnly = $true
$rejected = $false
try { Get-VerificationCommands Targeted Economy | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Preview cannot mix with rules selector' }
$RulesOnly = $false
$LocalLearningPreview = $false
$TestTargets = @('test/architecture/fitness_test.dart')
if ('tool/feature_contract/generate_feature_map.dart' -notmatch (Get-AreaPathPattern Learning)) { throw 'Flutter fingerprint must include imported tool Dart helpers' }
$TestTargets = @()

$failures = [System.Collections.Generic.List[string]]::new()
foreach ($area in @('BackendAI','BackendVoice','BackendLM')) {
    $pattern = Get-AreaPathPattern $area
    if ('tool/cli/verify-scope.ps1' -notmatch $pattern) { $failures.Add("$area omits runner dependency") }
    $command = @(Get-VerificationCommands Targeted $area)[0]
    if ($command.Arguments -notcontains '--frozen' -or $command.Arguments -notcontains 'dev') { $failures.Add("$area lacks frozen dev environment") }
}
if ($failures.Count) { throw ($failures -join "`n") }
$missing = New-CommandSpec -Name 'Missing fixture runner' -FilePath powershell -Arguments @('-File','tool/cli/does-not-exist.ps1') -SourceArea Runtime
$rejected = $false
try { Assert-CommandPaths @($missing) } catch { $rejected = $true }
if (-not $rejected) { throw 'Missing command must be rejected before any suite starts' }

# Exercise the actual entry point in a disposable repository. Dummy child scripts
# count executions; no Flutter/backend/release suite is started by this fixture.
$fixture = Join-Path $repoRoot ('build/verification/scope-contract-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$fixture/tool/cli/tests" -Force | Out-Null
Copy-Item -LiteralPath $runner -Destination "$fixture/tool/cli/verify-scope.ps1"
foreach ($name in @('r15-scope.tests.ps1','verify-scope.tests.ps1')) {
    [IO.File]::WriteAllText("$fixture/tool/cli/tests/$name", 'Add-Content -LiteralPath (Join-Path $PSScriptRoot "../../../build/calls.txt") -Value "run"')
}
git -C $fixture init -q
git -C $fixture -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm fixture
if ($LASTEXITCODE) { throw 'Fixture git initialization failed' }
$head = (git -C $fixture rev-parse HEAD).Trim()
$fixtureRunner = "$fixture/tool/cli/verify-scope.ps1"
function Invoke-Fixture {
    param([string[]]$Extra = @(), [bool]$ShouldPass = $true)
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $fixtureRunner -Level Subsystem -Area Runtime -CliOnly @Extra 2>&1
    $code = $LASTEXITCODE
    $output | Add-Content "$fixture/transcript.log"
    if (($code -eq 0) -ne $ShouldPass) { throw "Fixture exit $code; see $fixture/transcript.log" }
}
function Assert-Calls([int]$Expected) {
    $count = if (Test-Path "$fixture/build/calls.txt") { @(Get-Content "$fixture/build/calls.txt").Count } else { 0 }
    if ($count -ne $Expected) { throw "Expected $Expected executions, got $count" }
}
Invoke-Fixture -Extra @('-PlanOnly')
Assert-Calls 0
$resultPath = "$fixture/build/verification/$head/subsystem-runtime-cli.json"
if (Test-Path $resultPath) { throw 'Plan-only must not create executable PASS evidence' }
Invoke-Fixture
Assert-Calls 2
Invoke-Fixture -Extra @('-Resume')
Assert-Calls 2
Add-Content "$fixture/tool/cli/tests/r15-scope.tests.ps1" '# relevant edit'
Invoke-Fixture -Extra @('-Resume')
Assert-Calls 4
$prior = Get-Content $resultPath -Raw | ConvertFrom-Json
Remove-Item -LiteralPath $prior.commands[0].Stdout
Invoke-Fixture -Extra @('-Resume')
Assert-Calls 5
$prior = Get-Content $resultPath -Raw | ConvertFrom-Json
$prior.commands[0].ExitCode = 17
$prior | ConvertTo-Json -Depth 12 | Set-Content $resultPath
Invoke-Fixture -Extra @('-Resume')
Assert-Calls 6
$old = $env:PYTEST_ADDOPTS
try {
    $env:PYTEST_ADDOPTS = '--g04-fixture-changed'
    Invoke-Fixture -Extra @('-Resume')
    Assert-Calls 8
} finally { $env:PYTEST_ADDOPTS = $old }
Write-Output "PASS: backend closure; plan-only zero execution; exact resume; source/environment/log/exit rejection. Fixture: $fixture"
