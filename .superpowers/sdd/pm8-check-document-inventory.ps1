param([string]$OutputPath = '.superpowers/sdd/pm8-document-inventory.json')
$ErrorActionPreference = 'Stop'
$pm8Rtm = 'docs/adventure-motivation-mode/08-requirements-traceability-matrix.md'
$pm8Plan = 'docs/adventure-motivation-mode/06-test-plan-and-test-cases.md'
$pm8Uat = 'docs/adventure-motivation-mode/07-uat-script.md'
$pm8Cases = @(Get-Content -LiteralPath $pm8Plan | ForEach-Object {
    if ($_ -match '^\| (TC-([A-Z]+)-\d{3}) \|') {
        [pscustomobject]@{id = $Matches[1]; family = $Matches[2]}
    }
})
$pm8UatIds = @(Get-Content -LiteralPath $pm8Uat | ForEach-Object {
    if ($_ -match '^### (UAT-\d{3}) ') { $Matches[1] }
})
$pm8Requirements = [Collections.Generic.List[object]]::new()
$pm8Missing = [Collections.Generic.List[object]]::new()
$pm8MappedTestReferences = 0
$pm8MappedUatReferences = 0
foreach ($pm8Line in Get-Content -LiteralPath $pm8Rtm) {
    if ($pm8Line -notmatch '^\| (AMM-(FR|DATA|UI|NFR|BR)-\d{3}) \|') { continue }
    $pm8Id = $Matches[1]
    $pm8Family = $Matches[2]
    $pm8Columns = $pm8Line.Split('|')
    if ($pm8Columns.Count -ne 9) { throw ('Unexpected RTM column count: ' + $pm8Id) }
    $pm8Requirements.Add([pscustomobject]@{id = $pm8Id; family = $pm8Family})
    foreach ($pm8Reference in [regex]::Matches(
        $pm8Columns[5],
        '(ENT|JRN|LRN|REC|DAT|RSH|UX|OPS|PMT)-(\d{3}(?:[–-]\d{3})?(?:/\d{3}(?:[–-]\d{3})?)*)'
    )) {
        foreach ($pm8Part in $pm8Reference.Groups[2].Value.Split('/')) {
            $pm8Ends = $pm8Part -split '[–-]'
            $pm8First = [int]$pm8Ends[0]
            $pm8Last = [int]$pm8Ends[-1]
            if ($pm8Last -lt $pm8First) { throw 'Descending test reference range.' }
            foreach ($pm8Number in $pm8First..$pm8Last) {
                $pm8TestId = 'TC-' + $pm8Reference.Groups[1].Value + '-' + $pm8Number.ToString('000')
                $pm8MappedTestReferences++
                if ($pm8TestId -cnotin $pm8Cases.id) {
                    $pm8Missing.Add([pscustomobject]@{requirement = $pm8Id; missing = $pm8TestId})
                }
            }
        }
    }
    foreach ($pm8UatReference in [regex]::Matches($pm8Columns[6], '\d{3}(?:[–-]\d{3})?')) {
        $pm8Ends = $pm8UatReference.Value -split '[–-]'
        $pm8First = [int]$pm8Ends[0]
        $pm8Last = [int]$pm8Ends[-1]
        if ($pm8Last -lt $pm8First) { throw 'Descending UAT reference range.' }
        foreach ($pm8Number in $pm8First..$pm8Last) {
            $pm8UatId = 'UAT-' + $pm8Number.ToString('000')
            $pm8MappedUatReferences++
            if ($pm8UatId -cnotin $pm8UatIds) {
                $pm8Missing.Add([pscustomobject]@{requirement = $pm8Id; missing = $pm8UatId})
            }
        }
    }
}
$pm8Result = [ordered]@{
    evidenceType = 'document inventory and reference resolution only; not execution or acceptance'
    capturedUtc = [DateTimeOffset]::UtcNow.ToString('o')
    rtmRows = $pm8Requirements.Count
    rtmUnique = @($pm8Requirements.id | Sort-Object -Unique).Count
    rtmFamilies = @($pm8Requirements | Group-Object family | ForEach-Object {
        [pscustomobject]@{family = $_.Name; count = $_.Count}
    })
    testCaseRows = $pm8Cases.Count
    testCaseUnique = @($pm8Cases.id | Sort-Object -Unique).Count
    pairCaseRows = @($pm8Cases | Where-Object family -CEQ 'PMT').Count
    uatHeadings = $pm8UatIds.Count
    uatUnique = @($pm8UatIds | Sort-Object -Unique).Count
    resolvedTestReferences = $pm8MappedTestReferences
    resolvedUatReferences = $pm8MappedUatReferences
    missingReferences = @($pm8Missing.ToArray())
}
$pm8Result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8
$pm8Result | ConvertTo-Json -Depth 6 -Compress
if ($pm8Result.rtmRows -ne 258 -or $pm8Result.rtmUnique -ne 258 -or
    $pm8Result.testCaseRows -ne 188 -or $pm8Result.testCaseUnique -ne 188 -or
    $pm8Result.pairCaseRows -ne 44 -or $pm8Result.uatHeadings -ne 50 -or
    $pm8Result.uatUnique -ne 50 -or $pm8Missing.Count -gt 0) { exit 1 }
exit 0
