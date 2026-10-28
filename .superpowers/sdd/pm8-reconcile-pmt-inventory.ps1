param(
    [Parameter(Mandatory = $true)][string]$DefaultInventory,
    [Parameter(Mandatory = $true)][string]$SerialInventory,
    [Parameter(Mandatory = $true)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$pm8Default = @(Get-Content -LiteralPath $DefaultInventory -Raw | ConvertFrom-Json)
$pm8Serial = @(Get-Content -LiteralPath $SerialInventory -Raw | ConvertFrom-Json)
function Get-Pm8ResultKeys([object[]]$Inventory) {
    $keys = [string[]]@($Inventory | ForEach-Object {
        $_.path.Replace('\', '/') + [char]0 + $_.name + [char]0 + $_.result + [char]0 + $_.skipped
    })
    [Array]::Sort($keys, [StringComparer]::Ordinal)
    return ,$keys
}
$pm8DefaultKeys = Get-Pm8ResultKeys $pm8Default
$pm8SerialKeys = Get-Pm8ResultKeys $pm8Serial
$pm8Same = $pm8DefaultKeys.Length -eq $pm8SerialKeys.Length
if ($pm8Same) {
    for ($pm8Index = 0; $pm8Index -lt $pm8DefaultKeys.Length; $pm8Index++) {
        if ($pm8DefaultKeys[$pm8Index] -cne $pm8SerialKeys[$pm8Index]) { $pm8Same = $false; break }
    }
}
$pm8Record = 'docs/development/2026-09-07-pair-matching-pm8-local-verification.md'
$pm8Groups = [Collections.Generic.List[object]]::new()
$pm8CaseIds = [Collections.Generic.List[int]]::new()
$pm8AllPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$pm8MissingOrFailed = [Collections.Generic.List[object]]::new()
foreach ($pm8Line in Get-Content -LiteralPath $pm8Record) {
    if ($pm8Line -notmatch '^\| TC-PMT-(.*?) \|') { continue }
    $pm8CaseRange = $Matches[1]
    foreach ($pm8Segment in $pm8CaseRange.Split(',')) {
        $pm8Ends = $pm8Segment -split '[–-]'
        foreach ($pm8Case in ([int]$pm8Ends[0]..[int]$pm8Ends[-1])) { $pm8CaseIds.Add($pm8Case) }
    }
    $pm8Paths = @([regex]::Matches($pm8Line, '`([^`]+\.dart)`') | ForEach-Object {
        $pm8Candidate = $_.Groups[1].Value
        if (-not $pm8Candidate.StartsWith('test/')) { $pm8Candidate = 'test/features/learning/pair_matching/' + $pm8Candidate }
        $pm8Candidate
    })
    if ($pm8Paths.Count -eq 0) { throw ('No mapped evidence paths: ' + $pm8CaseRange) }
    $pm8GroupResults = [Collections.Generic.List[object]]::new()
    foreach ($pm8Path in $pm8Paths) {
        [void]$pm8AllPaths.Add($pm8Path)
        $pm8Absolute = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $pm8Path)).Replace('\', '/')
        $pm8DefaultRows = @($pm8Default | Where-Object { $_.path.Replace('\', '/') -ceq $pm8Absolute })
        $pm8SerialRows = @($pm8Serial | Where-Object { $_.path.Replace('\', '/') -ceq $pm8Absolute })
        $pm8AllPassed = $pm8DefaultRows.Count -gt 0 -and $pm8SerialRows.Count -eq $pm8DefaultRows.Count -and @($pm8DefaultRows + $pm8SerialRows | Where-Object { $_.result -cne 'success' -or $_.skipped }).Count -eq 0
        $pm8Result = [pscustomobject]@{path=$pm8Path; defaultTests=$pm8DefaultRows.Count; serialTests=$pm8SerialRows.Count; allPassed=$pm8AllPassed}
        $pm8GroupResults.Add($pm8Result)
        if (-not $pm8AllPassed) { $pm8MissingOrFailed.Add($pm8Result) }
    }
    $pm8Groups.Add([pscustomobject]@{plannedCases=('TC-PMT-' + $pm8CaseRange); evidence=$pm8GroupResults.ToArray()})
}
$pm8UniqueCases = @($pm8CaseIds | Sort-Object -Unique)
$pm8CasesComplete = $pm8CaseIds.Count -eq 44 -and $pm8UniqueCases.Count -eq 44 -and $pm8UniqueCases[0] -eq 1 -and $pm8UniqueCases[-1] -eq 44
$pm8Summary = [ordered]@{
    defaultInventory = (Resolve-Path -LiteralPath $DefaultInventory).Path
    serialInventory = (Resolve-Path -LiteralPath $SerialInventory).Path
    actualNamedInventoriesEqual = $pm8Same
    defaultVisibleTests = $pm8Default.Count
    serialVisibleTests = $pm8Serial.Count
    mappedCaseGroups = $pm8Groups.Count
    mappedCaseCount = $pm8CaseIds.Count
    all44PlannedCasesMappedExactlyOnce = $pm8CasesComplete
    uniqueMappedTestPaths = $pm8AllPaths.Count
    missingOrFailed = $pm8MissingOrFailed.ToArray()
    mapping = $pm8Groups.ToArray()
    evidenceLimit = 'Automated fixture execution, not human UAT or acceptance of every manual requirement.'
}
$pm8Summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8
[pscustomobject]@{namedInventoriesEqual=$pm8Same; visibleTests=$pm8Default.Count; caseGroups=$pm8Groups.Count; cases=$pm8CaseIds.Count; uniqueMappedPaths=$pm8AllPaths.Count; missingOrFailed=$pm8MissingOrFailed.Count} | ConvertTo-Json -Compress
if (-not $pm8Same -or -not $pm8CasesComplete -or $pm8MissingOrFailed.Count -gt 0) { exit 1 }
exit 0
