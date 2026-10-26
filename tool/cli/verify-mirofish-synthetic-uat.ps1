#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReportPath,

    [Parameter(Mandatory)]
    [string]$ManifestPath,

    [Parameter(Mandatory)]
    [string]$SeedPath,

    [Parameter(Mandatory)]
    [string]$SimulationRequestPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'tool/cli/lib/mirofish-synthetic-uat.ps1')

foreach ($path in @(
    $ReportPath,
    $ManifestPath,
    $SeedPath,
    $SimulationRequestPath
)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required synthetic-UAT artifact is missing: $path"
    }
    if ((Get-Item -LiteralPath $path).Length -gt 1MB) {
        throw "Synthetic-UAT artifact exceeds the 1 MiB validation limit: $path"
    }
}

$rawReport = Get-Content -LiteralPath $ReportPath -Raw -Encoding utf8
$rawSeed = Get-Content -LiteralPath $SeedPath -Raw -Encoding utf8
$rawSimulationRequest = Get-Content -LiteralPath $SimulationRequestPath -Raw `
    -Encoding utf8
try {
    $report = $rawReport | ConvertFrom-Json
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding utf8 |
        ConvertFrom-Json
    $reportTree = ConvertFrom-LexiQuestJsonTree -Json $rawReport
    $manifestRaw = Get-Content -LiteralPath $ManifestPath -Raw -Encoding utf8
    $manifestTree = ConvertFrom-LexiQuestJsonTree -Json $manifestRaw
} catch {
    throw "Synthetic-UAT JSON is malformed: $($_.Exception.Message)"
}
$decodedReportText = $report | ConvertTo-Json -Depth 20 -Compress
$decodedManifestText = $manifest | ConvertTo-Json -Depth 20 -Compress
$actualSeedSha256 = (Get-FileHash -LiteralPath $SeedPath -Algorithm SHA256).Hash
$actualRequestSha256 = (
    Get-FileHash -LiteralPath $SimulationRequestPath -Algorithm SHA256
).Hash

$errors = @(
    Test-LexiQuestSyntheticText -Text $rawSeed
    Test-LexiQuestSyntheticText -Text $rawSimulationRequest
    Test-LexiQuestSyntheticText -Text $decodedManifestText
    Test-LexiQuestMiroFishManifestTypes -Manifest $manifestTree
    Test-LexiQuestMiroFishReportTypes -Report $reportTree
    Test-LexiQuestMiroFishManifest `
        -Manifest $manifest `
        -ActualSeedSha256 $actualSeedSha256 `
        -ActualSimulationRequestSha256 $actualRequestSha256
    Test-LexiQuestMiroFishReport `
        -Report $report `
        -Manifest $manifest `
        -RawText $decodedReportText
)
if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) {
        Write-Error $validationError -ErrorAction Continue
    }
    exit 1
}

$findings = @($report.findings)
$priorityFindings = @(
    $findings | Where-Object { $_.severity -in @('P0', 'P1') }
)
Write-Host 'MiroFish synthetic-UAT report: VALID'
Write-Host 'Disposition: REPORT_ONLY'
Write-Host ("Findings: {0}; P0/P1 hypotheses: {1}" -f `
    $findings.Count, $priorityFindings.Count)
exit 0
