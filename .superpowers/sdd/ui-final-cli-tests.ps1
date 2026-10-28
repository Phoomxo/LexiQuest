param([Parameter(Mandatory)][string]$EvidenceDirectory)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$uiRoot = 'C:/Users/Phet/.codex/worktrees/02fa/LexiQuest'
if ([IO.Path]::GetFullPath((Get-Location).Path) -ne [IO.Path]::GetFullPath($uiRoot)) { throw 'Wrong worktree' }
$uiOutput = [IO.Path]::GetFullPath($EvidenceDirectory)
$uiAllowed = [IO.Path]::GetFullPath((Join-Path $uiRoot 'build/verification/ui-implementation-20260908')) + '\'
if (-not $uiOutput.StartsWith($uiAllowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence outside task root' }
if (Test-Path -LiteralPath $uiOutput) { throw 'Use a new evidence directory; preserve prior results' }
New-Item -ItemType Directory -Path $uiOutput | Out-Null
$uiTests = @(Get-ChildItem -LiteralPath (Join-Path $uiRoot 'tool/cli/tests') -File -Filter '*.tests.ps1' | Sort-Object Name)
if ($uiTests.Count -ne 25) { throw 'Re-audit CLI safety inventory before running a changed runner set' }
$uiResults = @()
foreach ($uiTest in $uiTests) {
    $uiWatch = [Diagnostics.Stopwatch]::StartNew()
    $uiBefore = (Get-FileHash -LiteralPath $uiTest.FullName -Algorithm SHA256).Hash
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uiTest.FullName 1> (Join-Path $uiOutput ($uiTest.Name + '.stdout.log')) 2> (Join-Path $uiOutput ($uiTest.Name + '.stderr.log'))
    $uiExit = $LASTEXITCODE
    $uiWatch.Stop()
    $uiAfter = (Get-FileHash -LiteralPath $uiTest.FullName -Algorithm SHA256).Hash
    $uiResult = [ordered]@{ runner=$uiTest.Name; exitCode=$uiExit; durationSeconds=$uiWatch.Elapsed.TotalSeconds; sourceSha256=$uiBefore.ToLowerInvariant(); sourceStable=($uiBefore -eq $uiAfter) }
    $uiResults += $uiResult
    $uiResult | ConvertTo-Json -Compress
    $uiResults | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $uiOutput 'results.json') -Encoding utf8
}
if (@($uiResults | Where-Object { $_.exitCode -ne 0 -or -not $_.sourceStable }).Count -gt 0) { exit 1 }
exit 0
