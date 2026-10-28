$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'collect-android-field-evidence.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
$function = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-InstalledVersionCode' }, $true)
Invoke-Expression $function.Extent.Text
function adb {
    $script:calls++
    if ($args -contains 'dumpsys') { $global:LASTEXITCODE = $script:dumpCode; return $script:dump }
    $global:LASTEXITCODE = $script:listCode; return $script:list
}
$failures = @(); $passed = 0
foreach ($case in @(
    @{ name='absent'; list=@(); dump=@(); result=$null },
    @{ name='present'; list=@('package:com.lexiquest.app'); dump=@('  versionCode=12 minSdk=23'); result=12 },
    @{ name='list failure'; list=@(); dump=@(); listCode=1; denied=$true },
    @{ name='malformed list'; list=@('error: device offline'); dump=@(); denied=$true },
    @{ name='dump failure'; list=@('package:com.lexiquest.app'); dump=@('versionCode=12'); dumpCode=1; denied=$true },
    @{ name='malformed dump'; list=@('package:com.lexiquest.app'); dump=@('unavailable'); denied=$true },
    @{ name='missing version'; list=@('package:com.lexiquest.app'); dump=@(); denied=$true },
    @{ name='zero version'; list=@('package:com.lexiquest.app'); dump=@('versionCode=0'); denied=$true }
)) {
    $script:list=$case.list; $script:dump=$case.dump
    $script:listCode=[int]$case.listCode; $script:dumpCode=[int]$case.dumpCode; $script:calls=0
    $denied=$false; $value=$null
    try { $value=Get-InstalledVersionCode -Serial fixture -PackageName com.lexiquest.app } catch { $denied=$true }
    if ($denied -ne [bool]$case.denied -or (-not $denied -and $value -ne $case.result)) { $failures += $case.name } else { $passed++ }
}
if ($failures.Count) { throw ('Prior state failures: ' + ($failures -join ', ')) }
Write-Output "PASS: $passed prior-state cases; fake ADB only, no install or signing"
