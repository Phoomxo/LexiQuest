Import-Module Microsoft.PowerShell.Utility
Write-Output ('initial hash function: ' + [bool](Get-Command Get-FileHash -ErrorAction SilentlyContinue))
foreach ($candidate in @('powershell.exe','git','flutter','dart','uv','python','node','npm','java')) {
 $found = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
 Write-Output ($candidate + ' resolved=' + [bool]$found + ' hash=' + [bool](Get-Command Get-FileHash -ErrorAction SilentlyContinue))
}

$runner = (Resolve-Path tool/cli/verify-scope.ps1).Path
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($runner,[ref]$tokens,[ref]$errors)
foreach ($function in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true)) { Invoke-Expression $function.Extent.Text }
Write-Output ('after import hash: '+[bool](Get-Command Get-FileHash -ErrorAction SilentlyContinue))
$repoRoot=(Get-Location).Path
Write-Output (Get-EnvironmentFingerprint)
