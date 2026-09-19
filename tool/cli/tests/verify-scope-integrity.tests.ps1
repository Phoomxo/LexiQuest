$ErrorActionPreference = 'Stop'
$runner = Join-Path (Split-Path $PSScriptRoot -Parent) 'verify-scope.ps1'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw $errors[0] }
foreach ($function in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    Invoke-Expression $function.Extent.Text
}
$actualRoot = Split-Path (Split-Path (Split-Path $runner -Parent) -Parent) -Parent
$repoRoot = Join-Path $actualRoot ('build/verification/integrity-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$repoRoot/tool/cli/tests", "$repoRoot/docs", "$repoRoot/build" -Force | Out-Null
Copy-Item $runner "$repoRoot/tool/cli/verify-scope.ps1"
[IO.File]::WriteAllText("$repoRoot/.gitignore", "build/`n")
[IO.File]::WriteAllText("$repoRoot/package.json", '{"oracle":1}')
[IO.File]::WriteAllText("$repoRoot/docs/contract.txt", 'one')
$child = "$repoRoot/tool/cli/tests/oracle.tests.ps1"
[IO.File]::WriteAllText($child, @'
$root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$package = Get-Content "$root/package.json" -Raw | ConvertFrom-Json
if ($package.oracle -lt 1) { exit 1 }
if (-not (Get-Content "$root/docs/contract.txt" -Raw)) { exit 1 }
Add-Content "$root/build/calls.txt" 'run'
'@)
git -C $repoRoot init -q
git -C $repoRoot -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm fixture
if ($LASTEXITCODE) { throw 'Fixture initialization failed' }
$head = (git -C $repoRoot rev-parse HEAD).Trim()
$failures = [Collections.Generic.List[string]]::new()
function Invoke-Fixture([bool]$Pass = $true) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$repoRoot/tool/cli/verify-scope.ps1" -Level Targeted -Area Runtime -CliTestTargets oracle.tests.ps1 -Resume *> "$repoRoot/build/latest.log"
    if (($LASTEXITCODE -eq 0) -ne $Pass) { $failures.Add("Unexpected fixture exit $LASTEXITCODE (expected pass=$Pass)") }
    $p = Get-ChildItem "$repoRoot/build/verification/$head" -Filter '*.json' | Select-Object -First 1
    return Get-Content $p.FullName -Raw | ConvertFrom-Json
}
function Assert-Calls([int]$Count, [string]$Label) {
    if (@(Get-Content "$repoRoot/build/calls.txt").Count -ne $Count) { $failures.Add($Label) }
}
$null = Invoke-Fixture
$null = Invoke-Fixture
Assert-Calls 1 'Unchanged input must reuse'
[IO.File]::WriteAllText("$repoRoot/package.json", '{"oracle":2}')
$null = Invoke-Fixture
Assert-Calls 2 'Changed package.json must rerun'
[IO.File]::WriteAllText("$repoRoot/docs/contract.txt", 'two')
$null = Invoke-Fixture
Assert-Calls 3 'Changed document input must rerun'

# Command changes a covered input after the verifier takes its pre-run hash.
$originalChild = [IO.File]::ReadAllText($child)
[IO.File]::WriteAllText($child, $originalChild + "`nAdd-Content (Join-Path `$PSScriptRoot 'input.txt') 'changed'`n")
$drift = Invoke-Fixture $false
if ($drift.status -ne 'InputDrift') { $failures.Add('Source mutation must record InputDrift') }
# Restoring the old input later cannot make the drifted PASS reusable.
Remove-Item "$repoRoot/tool/cli/tests/input.txt" -ErrorAction SilentlyContinue
$again = Invoke-Fixture $false
if ($again.commands[0].PSObject.Properties['Resumed'] -and $again.commands[0].Resumed) { $failures.Add('Drift must never resume') }
[IO.File]::WriteAllText($child, $originalChild)
$null = Invoke-Fixture

# A legitimate setup change still invalidates that run; only stable verification passes.
[IO.File]::WriteAllText($child, $originalChild + "`nif (-not (Test-Path `"`$root/.env`")) { [IO.File]::WriteAllText(`"`$root/.env`", 'fixture=ready') }`n")
$null = Invoke-Fixture $false
$null = Invoke-Fixture

# Console.Error bypasses PowerShell stream redirection and fills the wrapper pipe.
$noisy = "$repoRoot/noisy.ps1"
[IO.File]::WriteAllText($noisy, "[Console]::Error.Write(('x' * 262144) + 'END-OF-WRAPPER'); exit 7")
$command = New-CommandSpec -Name 'Wrapper stderr pressure' -FilePath $noisy -Arguments @() -SourceArea Runtime
$r = Invoke-BoundedCommand $command 10 "$repoRoot/build/noisy" ('a' * 64)
if ($r.Status -ne 'Failed' -or $r.ExitCode -ne 7) { $failures.Add('Wrapper stderr must drain without timeout') }
if (-not (Test-Path $r.Stderr) -or -not ([IO.File]::ReadAllText($r.Stderr).Contains('END-OF-WRAPPER'))) { $failures.Add('Complete wrapper stderr must be retained') }
# Timeout must terminate descendants while retaining stderr already drained.
$timeoutScript = "$repoRoot/timeout.ps1"
[IO.File]::WriteAllText($timeoutScript, @'
$child = Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile -Command Start-Sleep -Seconds 60' -PassThru
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'build/descendant.pid'), [string]$child.Id)
[Console]::Error.Write('before-timeout')
Start-Sleep -Seconds 60
'@)
$command = New-CommandSpec -Name 'Timeout tree' -FilePath $timeoutScript -Arguments @() -SourceArea Runtime
$r = Invoke-BoundedCommand $command 3 "$repoRoot/build/timeout" ('b' * 64)
if ($r.Status -ne 'TimedOut') { $failures.Add('Timeout must remain a failure') }
$descendant = [int](Get-Content "$repoRoot/build/descendant.pid")
if (Get-Process -Id $descendant -ErrorAction SilentlyContinue) { $failures.Add('Timeout left a descendant running') }
if (-not ([IO.File]::ReadAllText($r.Stderr).Contains('before-timeout'))) { $failures.Add('Timeout lost wrapper stderr') }
Write-Output "Fixture: $repoRoot"
if ($failures.Count) { throw ($failures -join "`n") }
Write-Output 'PASS: CLI input closure, unchanged reuse, source/environment drift, stderr pressure'
