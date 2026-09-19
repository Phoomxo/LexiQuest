$ErrorActionPreference='Stop'
$runner=Join-Path (Split-Path $PSScriptRoot -Parent) 'verify-scope.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($runner,[ref]$tokens,[ref]$errors)
foreach($function in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){Invoke-Expression $function.Extent.Text}
$CliOnly=$false;$CliTestTargets=@();$TestTargets=@()
$failures=@()
foreach($area in @('Runtime','All')){
    foreach($path in @('package.json','.github/dependabot.yml','docs/field/contract.md')){
        if($path -notmatch (Get-AreaPathPattern $area)){$failures+="$area omits $path for implicit CLI command"}
    }
}
$root=Split-Path (Split-Path (Split-Path $runner -Parent) -Parent) -Parent
$fixture=Join-Path $root ('build/mixed-scope-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$fixture/tool/cli/tests","$fixture/lib","$fixture/backend/ai_api","$fixture/build" -Force | Out-Null
[IO.File]::WriteAllText("$fixture/.gitignore","build/`n")
[IO.File]::WriteAllText("$fixture/lib/input.dart",'before')
[IO.File]::WriteAllText("$fixture/backend/ai_api/input.py",'before')
[IO.File]::WriteAllText("$fixture/tool/cli/tests/first.ps1", "Add-Content (Join-Path `$PSScriptRoot '../../../backend/ai_api/input.py') 'mutated'")
[IO.File]::WriteAllText("$fixture/tool/cli/tests/second.ps1", "Get-Content (Join-Path `$PSScriptRoot '../../../backend/ai_api/input.py') | Out-Null")
$override=@'
function Get-VerificationCommands {
    @(
        New-CommandSpec -Name first -FilePath powershell -Arguments @('-NoProfile','-File',(Join-Path $repoRoot 'tool/cli/tests/first.ps1')) -SourceArea AI
        New-CommandSpec -Name second -FilePath powershell -Arguments @('-NoProfile','-File',(Join-Path $repoRoot 'tool/cli/tests/second.ps1')) -SourceArea BackendAI
    )
}
'@
$text=[IO.File]::ReadAllText($runner)
$needle='Push-Location -LiteralPath $repoRoot'
if(($text.Split(@($needle),[StringSplitOptions]::None)).Count -ne 2){throw 'Runner fixture insertion is ambiguous'}
[IO.File]::WriteAllText("$fixture/tool/cli/verify-scope.ps1",$text.Replace($needle,$override+"`n"+$needle))
git -C $fixture init -q
git -C $fixture -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm fixture
& powershell -NoProfile -ExecutionPolicy Bypass -File "$fixture/tool/cli/verify-scope.ps1" -Level Targeted -Area AI *> "$fixture/build/run.log"
if($LASTEXITCODE -eq 0){$failures+='Mutation of later command area certified stale initial closure'}
$head=(git -C $fixture rev-parse HEAD).Trim()
$result=Get-Content "$fixture/build/verification/$head/targeted-ai.json" -Raw | ConvertFrom-Json
if($result.status -ne 'InputDrift'){$failures+='Mixed-area mutation must record InputDrift'}
if($failures.Count){throw ($failures -join '; ')}
Write-Output 'PASS: implicit CLI root inputs and mixed-area initial closure remain bound'
