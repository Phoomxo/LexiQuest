[CmdletBinding()]
param(
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$inventoryPath = Join-Path $repositoryRoot 'docs\prototype\feature-inventory.md'
$allowlistPath = Join-Path $repositoryRoot 'tool\cli\prototype-production-paths.allowlist.json'

function ConvertFrom-PrototypeInventoryTable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Markdown
    )

    $expectedHeader = 'Feature ID | Visible entry | Screen/route | Current data/device/provider | Offline behavior | Permission/configuration | Truthful unavailable state | Known blocker | Target phase | Evidence'
    $lines = @([regex]::Split($Markdown, '\r?\n'))
    $headerIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -eq $expectedHeader) {
            $headerIndex = $index
            break
        }
    }
    if ($headerIndex -lt 0 -or $headerIndex + 1 -ge $lines.Count) {
        throw 'Inventory table header is missing.'
    }

    $separatorCells = @(
        $lines[$headerIndex + 1].Split('|') |
            ForEach-Object { $_.Trim() }
    )
    if ($separatorCells.Count -ne 10 -or
        @($separatorCells | Where-Object { $_ -notmatch '^:?-{3,}:?$' }).Count -gt 0) {
        throw 'Inventory table separator is malformed.'
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    for ($index = $headerIndex + 2; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ([string]::IsNullOrWhiteSpace($line) -or
            $line.TrimStart().StartsWith('#')) {
            break
        }

        $cells = @(
            $line.Split('|') |
                ForEach-Object { $_.Trim() }
        )
        if ($cells.Count -ne 10) {
            throw 'Inventory table row is malformed.'
        }

        $rows.Add(
            [pscustomobject]@{
                FeatureId = $cells[0]
                Evidence = $cells[9]
            }
        )
    }
    if ($rows.Count -eq 0) {
        throw 'Inventory table has no feature rows.'
    }

    return $rows
}

function Get-PrototypeInventoryCoverageErrors {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Rows,
        [Parameter(Mandatory = $true)]
        [string[]]$RequiredFeatureIds,
        [Parameter(Mandatory = $true)]
        [string[]]$RequiredScreenPaths
    )

    $featureIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $evidencePaths = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($row in $Rows) {
        [void]$featureIds.Add([string]$row.FeatureId)
        foreach ($pathMatch in [regex]::Matches(
            [string]$row.Evidence,
            '\blib/[A-Za-z0-9_./-]+\.dart\b'
        )) {
            [void]$evidencePaths.Add($pathMatch.Value)
        }
    }

    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($featureId in $RequiredFeatureIds) {
        if (-not $featureIds.Contains($featureId)) {
            $errors.Add("Inventory omits allowlisted feature: $featureId")
        }
    }
    foreach ($screenPath in $RequiredScreenPaths) {
        if (-not $evidencePaths.Contains($screenPath)) {
            $errors.Add("Inventory omits reachable screen: $screenPath")
        }
    }

    return $errors
}

function ConvertTo-RepositoryRelativeDartPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CurrentPath,
        [Parameter(Mandatory = $true)]
        [string]$ImportPath
    )

    if ($ImportPath.StartsWith('package:vocab_learning_app/')) {
        return 'lib/' + $ImportPath.Substring(
            'package:vocab_learning_app/'.Length
        )
    }
    if ($ImportPath.StartsWith('package:')) {
        return $null
    }

    $currentDirectory = Split-Path $CurrentPath -Parent
    $combined = (
        "$currentDirectory/$ImportPath" -replace '\\', '/'
    )
    $segments = [System.Collections.Generic.List[string]]::new()
    foreach ($segment in $combined.Split('/')) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq '.') {
            continue
        }
        if ($segment -eq '..') {
            if ($segments.Count -eq 0) {
                return $null
            }
            $segments.RemoveAt($segments.Count - 1)
            continue
        }
        $segments.Add($segment)
    }

    return ($segments -join '/')
}

function Get-SourceDerivedReachableScreenPaths {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Sources,
        [Parameter(Mandatory = $true)]
        [string[]]$RootPaths
    )

    $queue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($rootPath in $RootPaths) {
        if (-not $Sources.Contains($rootPath)) {
            throw "Navigation graph root is not tracked: $rootPath"
        }
        $queue.Enqueue($rootPath)
    }

    $visited = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $reachableScreens = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $importPattern = '(?m)^\s*import\s+[''"]([^''"]+\.dart)[''"]'
    $destinationClassPattern =
        '(?m)^\s*(?:(?:abstract|base|final|interface|sealed)\s+)*' +
        'class\s+([A-Za-z]\w*)\b'

    while ($queue.Count -gt 0) {
        $currentPath = $queue.Dequeue()
        if (-not $visited.Add($currentPath)) {
            continue
        }
        if ($currentPath.StartsWith('lib/screens/')) {
            [void]$reachableScreens.Add($currentPath)
        }

        $currentSource = [string]$Sources[$currentPath]
        foreach ($importMatch in [regex]::Matches(
            $currentSource,
            $importPattern
        )) {
            $targetPath = ConvertTo-RepositoryRelativeDartPath `
                -CurrentPath $currentPath `
                -ImportPath $importMatch.Groups[1].Value
            if ($null -eq $targetPath -or
                -not $targetPath.StartsWith('lib/screens/') -or
                -not $Sources.Contains($targetPath)) {
                continue
            }

            $targetSource = [string]$Sources[$targetPath]
            $isConstructedDestination = $false
            foreach ($classMatch in [regex]::Matches(
                $targetSource,
                $destinationClassPattern
            )) {
                $className = [regex]::Escape($classMatch.Groups[1].Value)
                if ([regex]::IsMatch(
                    $currentSource,
                    "\b$className\s*\("
                )) {
                    $isConstructedDestination = $true
                    break
                }
            }
            if ($isConstructedDestination) {
                $queue.Enqueue($targetPath)
            }
        }
    }

    return @($reachableScreens | Sort-Object)
}

if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
    Write-Error 'Prototype feature inventory is missing.'
    exit 1
}
if (-not (Test-Path -LiteralPath $allowlistPath -PathType Leaf)) {
    Write-Error 'Prototype production-path allowlist is missing.'
    exit 1
}

$ruleSpecs = @(
    [pscustomobject]@{
        Name = 'sample-user-history'
        Pattern = '\b(?:sample|mock|fake)(?:User)?(?:History|Progress|Attempts?|Sessions?|Scores?|Metrics?|Stats?)\b|this\.listeningScore\s*=\s*85\.0|widget\.customItems\s*\?\?\s*\[|_ghostSnapshot\s*=\s*GhostSnapshot\s*\('
        ScreensOnly = $false
    },
    [pscustomobject]@{
        Name = 'mock-production-provider'
        Pattern = '(?:=|return)\s*(?:const\s+)?Mock[A-Z]\w*(?:Provider|Service|Repository|Gateway)\s*\('
        ScreensOnly = $false
    },
    [pscustomobject]@{
        Name = 'simulated-device-result'
        Pattern = '\b(?:simulated|mock)(?:Device|Camera|Speech|Scan|Detection|Recognition|Transcription|Confidence|Result)\w*|object-scanner-simulate-button|_toggleMicListening\s*\(\)\s*\{.*?Future\.delayed.*?_sendMessage\s*\(\s*'''
        ScreensOnly = $false
    },
    [pscustomobject]@{
        Name = 'random-fabricated-measurement'
        Pattern = 'Random\s*\(\s*\)\.nextDouble\s*\(\s*\)'
        ScreensOnly = $false
    },
    [pscustomobject]@{
        Name = 'placeholder-transaction-feature'
        Pattern = '\bplaceholder\b|\bnot\s+implemented\b'
        ScreensOnly = $false
    },
    [pscustomobject]@{
        Name = 'canned-ai-response'
        Pattern = '\b_cannedFallbackReply\s*\('
        ScreensOnly = $false
    },
    [pscustomobject]@{
        Name = 'direct-screen-firebase-access'
        Pattern = '(?m)^\s*import\s+''package:(?:cloud_firestore|firebase_[^/''"]+)/'
        ScreensOnly = $true
    },
    [pscustomobject]@{
        Name = 'direct-screen-http-access'
        Pattern = '(?m)^\s*import\s+''package:http/'
        ScreensOnly = $true
    },
    [pscustomobject]@{
        Name = 'direct-screen-plugin-access'
        Pattern = '(?m)^\s*import\s+''package:(?:speech_to_text|shared_preferences|image_picker|camera|google_mlkit[^/''"]*|flutter_tts|audioplayers|file_picker|permission_handler)/'
        ScreensOnly = $true
    }
)

$directScreenPluginRule = @(
    $ruleSpecs |
        Where-Object Name -eq 'direct-screen-plugin-access'
)
$sharedPreferencesProbe = @'
import 'package:shared_preferences/shared_preferences.dart';
'@
$sharedPreferencesProbeCount = [regex]::Matches(
    $sharedPreferencesProbe,
    $directScreenPluginRule[0].Pattern,
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [System.Text.RegularExpressions.RegexOptions]::Singleline
).Count
if ($directScreenPluginRule.Count -ne 1 -or
    $sharedPreferencesProbeCount -ne 1) {
    Write-Error 'Rule self-test failed: SharedPreferences screen import.'
    exit 1
}

$knownRuleNames = @{}
foreach ($ruleSpec in $ruleSpecs) {
    $knownRuleNames[$ruleSpec.Name] = $true
}

$validationErrors = [System.Collections.Generic.List[string]]::new()

try {
    $allowlistText = [System.IO.File]::ReadAllText($allowlistPath)
    $allowlist = $allowlistText | ConvertFrom-Json
}
catch {
    Write-Error 'Allowlist JSON is malformed.'
    exit 1
}

$allowlistPropertyNames = @(
    if ($null -ne $allowlist) {
        $allowlist.PSObject.Properties.Name
    }
)
$parsedSchemaVersion = 0
if ($null -eq $allowlist -or
    -not ($allowlistPropertyNames -contains 'schemaVersion') -or
    -not [int]::TryParse(
        [string]$allowlist.schemaVersion,
        [ref]$parsedSchemaVersion
    ) -or
    $parsedSchemaVersion -ne 1) {
    $validationErrors.Add('Allowlist schemaVersion must equal 1.')
}
if ($null -eq $allowlist -or
    -not ($allowlistPropertyNames -contains 'entries') -or
    $null -eq $allowlist.entries) {
    $validationErrors.Add('Allowlist entries must be present.')
    $allowlistEntries = @()
}
else {
    $allowlistEntries = @($allowlist.entries)
}

$allowByKey = @{}
foreach ($entry in $allowlistEntries) {
    $entryPropertyNames = @(
        if ($null -ne $entry) {
            $entry.PSObject.Properties.Name
        }
    )
    $requiredEntryProperties = @(
        'path',
        'rule',
        'targetPhase',
        'featureId'
    )
    $missingEntryProperties = @(
        $requiredEntryProperties |
            Where-Object { -not ($entryPropertyNames -contains $_) }
    )
    if ($null -eq $entry -or $missingEntryProperties.Count -gt 0) {
        $validationErrors.Add('Allowlist entry is missing required fields.')
        continue
    }

    $path = [string]$entry.path
    $rule = [string]$entry.rule
    $featureId = [string]$entry.featureId
    $targetPhase = 0
    $phaseIsValid = [int]::TryParse(
        [string]$entry.targetPhase,
        [ref]$targetPhase
    )

    if ([string]::IsNullOrWhiteSpace($path) -or
        [System.IO.Path]::IsPathRooted($path) -or
        $path.Contains('\') -or
        $path.Contains('..') -or
        -not $path.StartsWith('lib/')) {
        $validationErrors.Add('Allowlist entry has an invalid relative path.')
        continue
    }
    if (-not $knownRuleNames.ContainsKey($rule)) {
        $validationErrors.Add("Allowlist entry has unknown rule: $rule")
        continue
    }
    if (-not $phaseIsValid -or $targetPhase -lt 1 -or $targetPhase -gt 10) {
        $validationErrors.Add("Allowlist entry has invalid target phase: $path")
    }
    if ([string]::IsNullOrWhiteSpace($featureId)) {
        $validationErrors.Add("Allowlist entry has no feature ID: $path")
    }

    $absolutePath = Join-Path $repositoryRoot ($path.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
        $validationErrors.Add("Allowlist entry names a missing file: $path")
    }

    $key = "$path::$rule"
    if ($allowByKey.ContainsKey($key)) {
        $validationErrors.Add("Duplicate allowlist pair: $path / $rule")
    }
    else {
        $allowByKey[$key] = [pscustomobject]@{
            Path = $path
            Rule = $rule
            FeatureId = $featureId
            TargetPhase = $targetPhase
        }
    }
}

Push-Location $repositoryRoot
try {
    $candidatePaths = @(
        & git ls-files -- 'lib/' |
            Where-Object { $_ -match '\.dart$' } |
            Sort-Object -Unique
    )
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'git ls-files failed for the bounded lib/ scan.'
        exit 1
    }
}
finally {
    Pop-Location
}

$findingsByKey = @{}
$trackedDartSources = @{}
$regexOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
    [System.Text.RegularExpressions.RegexOptions]::Singleline

foreach ($relativePath in $candidatePaths) {
    $absolutePath = Join-Path $repositoryRoot ($relativePath.Replace('/', '\'))
    $content = [System.IO.File]::ReadAllText($absolutePath)
    $trackedDartSources[$relativePath] = $content

    foreach ($ruleSpec in $ruleSpecs) {
        if ($ruleSpec.ScreensOnly -and
            -not $relativePath.StartsWith('lib/screens/')) {
            continue
        }

        $matchCount = [regex]::Matches(
            $content,
            $ruleSpec.Pattern,
            $regexOptions
        ).Count
        if ($matchCount -eq 0) {
            continue
        }

        $key = "$relativePath::$($ruleSpec.Name)"
        $findingsByKey[$key] = [pscustomobject]@{
            Path = $relativePath
            Rule = $ruleSpec.Name
            Count = $matchCount
        }
    }
}

foreach ($findingKey in $findingsByKey.Keys) {
    if (-not $allowByKey.ContainsKey($findingKey)) {
        $finding = $findingsByKey[$findingKey]
        $validationErrors.Add(
            "New finding: $($finding.Path) / $($finding.Rule) / targetPhase=unassigned / count=$($finding.Count)"
        )
    }
}
foreach ($allowKey in $allowByKey.Keys) {
    if (-not $findingsByKey.ContainsKey($allowKey)) {
        $entry = $allowByKey[$allowKey]
        $validationErrors.Add(
            "Stale entry: $($entry.Path) / $($entry.Rule) / targetPhase=$($entry.TargetPhase) / count=0"
        )
    }
}

$inventoryCoverageProbe = @'
# Probe

Prose mentions prose.only and lib/screens/prose_only.dart.

Feature ID | Visible entry | Screen/route | Current data/device/provider | Offline behavior | Permission/configuration | Truthful unavailable state | Known blocker | Target phase | Evidence
--- | --- | --- | --- | --- | --- | --- | --- | --- | ---
actual.row | Actual | Direct route | Local | Works | None | Empty | ready | 2 | `lib/screens/actual_row.dart`
'@
$inventoryCoverageProbeRows = @(
    ConvertFrom-PrototypeInventoryTable -Markdown $inventoryCoverageProbe
)
$proseOnlyCoverageErrors = @(
    Get-PrototypeInventoryCoverageErrors `
        -Rows $inventoryCoverageProbeRows `
        -RequiredFeatureIds @('prose.only') `
        -RequiredScreenPaths @('lib/screens/prose_only.dart')
)
$actualRowCoverageErrors = @(
    Get-PrototypeInventoryCoverageErrors `
        -Rows $inventoryCoverageProbeRows `
        -RequiredFeatureIds @('actual.row') `
        -RequiredScreenPaths @('lib/screens/actual_row.dart')
)
if ($proseOnlyCoverageErrors.Count -ne 2 -or
    $actualRowCoverageErrors.Count -ne 0) {
    Write-Error 'Inventory table coverage self-test failed.'
    exit 1
}

$navigationDriftProbeRows = @(
    [pscustomobject]@{
        FeatureId = 'probe.root'
        Evidence = 'lib/screens/root_screen.dart'
    }
)
$destinationBaseClassFixtures = @(
    'ConsumerWidget',
    'HookWidget',
    'ProductDestinationBase'
)
foreach ($destinationBaseClass in $destinationBaseClassFixtures) {
    $navigationDriftProbeSources = @{
        'lib/navigation/app_router.dart' = @'
import '../screens/root_screen.dart';
Widget route() => const RootScreen();
'@
        'lib/screens/root_screen.dart' = @'
import 'new_destination_screen.dart';
class RootScreen extends StatelessWidget {
  const RootScreen();
  Widget build(context) => const NewDestinationScreen();
}
'@
        'lib/screens/new_destination_screen.dart' = @"
class NewDestinationScreen extends $destinationBaseClass {
  const NewDestinationScreen();
}
"@
    }
    $navigationDriftProbeReachable = @(
        Get-SourceDerivedReachableScreenPaths `
            -Sources $navigationDriftProbeSources `
            -RootPaths @('lib/navigation/app_router.dart')
    )
    $navigationDriftProbeErrors = @(
        Get-PrototypeInventoryCoverageErrors `
            -Rows $navigationDriftProbeRows `
            -RequiredFeatureIds @('probe.root') `
            -RequiredScreenPaths $navigationDriftProbeReachable
    )
    if ($navigationDriftProbeErrors.Count -ne 1 -or
        $navigationDriftProbeErrors[0] -ne
            'Inventory omits reachable screen: lib/screens/new_destination_screen.dart') {
        Write-Error (
            'Source-derived navigation drift self-test failed for base: ' +
            $destinationBaseClass
        )
        exit 1
    }
}

$navigationGraphRoots = @(
    'lib/navigation/app_router.dart',
    'lib/screens/main_navigation_screen.dart',
    'lib/screens/choose_mode_screen.dart',
    'lib/screens/profile_settings_screen.dart',
    'lib/screens/setting_screen.dart'
)
# No exclusion list is needed. Hidden legacy screens remain outside the set
# because no constructor edge reachable from these bounded roots points to them.
$reachableScreenPaths = @(
    Get-SourceDerivedReachableScreenPaths `
        -Sources $trackedDartSources `
        -RootPaths $navigationGraphRoots
)

$inventory = [System.IO.File]::ReadAllText($inventoryPath)
try {
    $inventoryRows = @(
        ConvertFrom-PrototypeInventoryTable -Markdown $inventory
    )
}
catch {
    $validationErrors.Add('Inventory table is malformed.')
    $inventoryRows = @()
}

$requiredFeatureIds = @(
    $allowByKey.Values |
        ForEach-Object FeatureId |
        Sort-Object -Unique
)
$inventoryCoverageErrors = @(
    Get-PrototypeInventoryCoverageErrors `
        -Rows $inventoryRows `
        -RequiredFeatureIds $requiredFeatureIds `
        -RequiredScreenPaths $reachableScreenPaths
)
foreach ($inventoryCoverageError in $inventoryCoverageErrors) {
    $validationErrors.Add($inventoryCoverageError)
}

$duplicateInventoryFeatureIds = @(
    $inventoryRows |
        Group-Object FeatureId |
        Where-Object Count -gt 1
)
foreach ($duplicateInventoryFeatureId in $duplicateInventoryFeatureIds) {
    if (-not [string]::IsNullOrWhiteSpace($duplicateInventoryFeatureId.Name)) {
        $validationErrors.Add(
            "Inventory has duplicate feature ID: $($duplicateInventoryFeatureId.Name)"
        )
    }
}

if ($validationErrors.Count -gt 0) {
    foreach ($validationError in $validationErrors) {
        Write-Error $validationError
    }
    exit 1
}

$sortedFindings = @(
    $findingsByKey.Values |
        Sort-Object Path, Rule
)
$totalMatchCount = 0
foreach ($finding in $sortedFindings) {
    $entry = $allowByKey["$($finding.Path)::$($finding.Rule)"]
    $totalMatchCount += $finding.Count
    Write-Output (
        'path={0} rule={1} targetPhase={2} count={3}' -f
        $finding.Path,
        $finding.Rule,
        $entry.TargetPhase,
        $finding.Count
    )
}

$knownDebtCount = $sortedFindings.Count
Write-Output (
    'summary candidateFiles={0} knownDebt={1} matches={2} new=0 stale=0' -f
    $candidatePaths.Count,
    $knownDebtCount,
    $totalMatchCount
)

if ($Strict -and $knownDebtCount -gt 0) {
    Write-Error "Strict mode: knownDebt=$knownDebtCount"
    exit 1
}

exit 0
