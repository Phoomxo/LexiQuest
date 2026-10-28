param(
    [Parameter(Mandatory = $true)][string]$JsonlPath,
    [Parameter(Mandatory = $true)][string]$OutputPrefix
)

$ErrorActionPreference = 'Stop'
$pm8Suites = @{}
$pm8Tests = @{}
$pm8Visible = [Collections.Generic.List[object]]::new()
$pm8ParseFailures = [Collections.Generic.List[object]]::new()
$pm8GeneratorFixtureOutput = [Collections.Generic.List[object]]::new()
$pm8ErrorEvents = 0
$pm8WarningLines = 0
$pm8Done = $null
$pm8LineNumber = 0
foreach ($pm8Line in [IO.File]::ReadLines((Resolve-Path -LiteralPath $JsonlPath).Path)) {
    $pm8LineNumber++
    if ([string]::IsNullOrWhiteSpace($pm8Line)) { continue }
    try { $pm8Event = $pm8Line | ConvertFrom-Json -Depth 40 }
    catch {
        # Flutter forwards these subprocess lines from the generator contract
        # fixtures outside JSON events. Retain each exact line separately;
        # unknown non-JSON output is still a fatal parse failure.
        $pm8KnownGeneratorLine =
            $pm8Line -cmatch '^Shell: Generated feature-map artifact has drifted: docs/generated/alltcas-idea-integration-feature-map\.(md|json)$' -or
            $pm8Line -cmatch '^Shell: Generated final Test Plan artifact has drifted: docs/generated/alltcas-8-44-final-test-plan\.(md|json)$' -or
            $pm8Line -cmatch '^Shell: Wrote docs/generated/alltcas-idea-integration-feature-map\.md and docs/generated/alltcas-idea-integration-feature-map\.json \([0-9a-f]{64}, revision [0-9]+\.[0-9]+\.[0-9]+\)\.$' -or
            $pm8Line -cmatch '^Shell: Feature-map artifacts are current \([0-9a-f]{64}, revision [0-9]+\.[0-9]+\.[0-9]+\)\.$'
        if ($pm8KnownGeneratorLine) {
            $pm8GeneratorFixtureOutput.Add([pscustomobject]@{line = $pm8LineNumber; text = $pm8Line})
            continue
        }
        $pm8ParseFailures.Add([pscustomobject]@{line = $pm8LineNumber})
        continue
    }
    switch ($pm8Event.type) {
        'suite' { $pm8Suites[[string]$pm8Event.suite.id] = $pm8Event.suite.path }
        'testStart' { $pm8Tests[[string]$pm8Event.test.id] = $pm8Event.test }
        'testDone' {
            if ($pm8Event.hidden -ceq $false) {
                $pm8Test = $pm8Tests[[string]$pm8Event.testID]
                if ($null -eq $pm8Test) { throw 'Visible result has no testStart identity.' }
                $pm8Path = $pm8Suites[[string]$pm8Test.suiteID]
                if ($null -eq $pm8Path) { throw 'Visible result has no suite path.' }
                $pm8Visible.Add([pscustomobject]@{
                    path = $pm8Path
                    name = $pm8Test.name
                    result = $pm8Event.result
                    skipped = [bool]$pm8Event.skipped
                })
            }
        }
        'error' { $pm8ErrorEvents++ }
        'print' {
            if ($pm8Event.message -match 'WARNING \(drift\)|multiple.*AppDatabase') {
                $pm8WarningLines++
            }
        }
        'done' { $pm8Done = $pm8Event }
    }
}
if ($null -eq $pm8Done) { throw 'No final done event; this is incomplete output.' }
$pm8Inventory = @($pm8Visible | Sort-Object path, name, result, skipped)
$pm8Summary = [ordered]@{
    input = (Resolve-Path -LiteralPath $JsonlPath).Path
    visibleTests = $pm8Inventory.Count
    passed = @($pm8Inventory | Where-Object { $_.result -ceq 'success' -and -not $_.skipped }).Count
    failed = @($pm8Inventory | Where-Object { $_.result -cne 'success' -and -not $_.skipped }).Count
    skipped = @($pm8Inventory | Where-Object skipped).Count
    errorEvents = $pm8ErrorEvents
    driftWarningPrintEvents = $pm8WarningLines
    parseFailures = @($pm8ParseFailures.ToArray())
    generatorFixtureOutput = @($pm8GeneratorFixtureOutput.ToArray())
    doneSuccess = $pm8Done.success
    reporterElapsedMs = $pm8Done.time
}
$pm8Summary | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath ($OutputPrefix + '.summary.json') -Encoding utf8
ConvertTo-Json -InputObject $pm8Inventory -Depth 5 |
    Set-Content -LiteralPath ($OutputPrefix + '.inventory.json') -Encoding utf8
$pm8Summary | ConvertTo-Json -Depth 5 -Compress
if ($pm8ParseFailures.Count -gt 0 -or -not $pm8Done.success -or
    $pm8Summary.failed -gt 0 -or $pm8Summary.errorEvents -gt 0) {
    exit 1
}
exit 0
