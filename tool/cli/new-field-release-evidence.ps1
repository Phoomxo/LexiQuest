#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReleaseManifestPath,
    [Parameter(Mandatory)]
    [string]$EvidenceRootPath,
    [string]$DeviceEvidenceDirectory = 'devices',
    [Parameter(Mandatory)]
    [string]$ControlRecordPath,
    [Parameter(Mandatory)]
    [string]$OwnerApprovalRecordPath,
    [string]$OutputPath = 'release-evidence.json'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'lib\field-release-evidence.ps1')

function Resolve-RepositoryPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

$manifestPath = Resolve-RepositoryPath $ReleaseManifestPath
$evidenceRoot = Resolve-RepositoryPath $EvidenceRootPath
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Release manifest is missing: $manifestPath"
}
if (-not (Test-Path -LiteralPath $evidenceRoot -PathType Container)) {
    throw "Evidence root is missing: $evidenceRoot"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 |
    ConvertFrom-Json
if ([int]$manifest.schemaVersion -ne 3) {
    throw 'Release manifest schemaVersion must be 3.'
}

$controlReference = New-LexiQuestEvidenceReference `
    -Path $ControlRecordPath `
    -EvidenceRootPath $evidenceRoot
$ownerReference = New-LexiQuestEvidenceReference `
    -Path $OwnerApprovalRecordPath `
    -EvidenceRootPath $evidenceRoot
$controls = Read-LexiQuestEvidenceRecord `
    -Reference $controlReference `
    -EvidenceRootPath $evidenceRoot
$approval = Read-LexiQuestEvidenceRecord `
    -Reference $ownerReference `
    -EvidenceRootPath $evidenceRoot
if ([string]$controls.recordType -ne 'lexiquestReleaseControls') {
    throw 'ControlRecordPath must contain a LexiQuest release-controls record.'
}
if ([string]$controls.releaseProfile -ne [string]$manifest.releaseProfile) {
    throw 'Release controls profile does not match release-manifest.json.'
}
if ([string]$approval.recordType -ne 'lexiquestOwnerApproval') {
    throw 'OwnerApprovalRecordPath must contain a LexiQuest owner approval record.'
}

$deviceDirectory = Get-LexiQuestContainedPath `
    -Path $DeviceEvidenceDirectory `
    -RootPath $evidenceRoot
$deviceReferences = @()
if (Test-Path -LiteralPath $deviceDirectory -PathType Container) {
    $deviceReferences = @(
        Get-ChildItem -LiteralPath $deviceDirectory -File `
            -Filter '*.device.json' |
            Sort-Object Name |
            ForEach-Object {
                $reference = New-LexiQuestEvidenceReference `
                    -Path $_.FullName `
                    -EvidenceRootPath $evidenceRoot
                $device = Read-LexiQuestEvidenceRecord `
                    -Reference $reference `
                    -EvidenceRootPath $evidenceRoot
                if ([string]$device.recordType -ne
                    'lexiquestPhysicalDeviceEvidence') {
                    throw "Invalid device evidence record: $($_.Name)"
                }
                $reference
            }
    )
}

$evidence = [ordered]@{
    schemaVersion = 3
    releaseProfile = [string]$manifest.releaseProfile
    releaseId = '{0}-{1}' -f
        $manifest.artifact.versionName,
        $manifest.artifact.buildId
    artifact = $manifest.artifact
    records = [ordered]@{
        controls = $controlReference
        ownerApproval = $ownerReference
    }
    devices = $deviceReferences
}
$outputFile = Get-LexiQuestContainedPath `
    -Path $OutputPath `
    -RootPath $evidenceRoot
$parent = Split-Path -Parent $outputFile
New-Item -ItemType Directory -Path $parent -Force | Out-Null
[System.IO.File]::WriteAllText(
    $outputFile,
    (($evidence | ConvertTo-Json -Depth 12) + [Environment]::NewLine),
    [System.Text.UTF8Encoding]::new($false)
)
Write-Host "Field release evidence assembled: $outputFile" `
    -ForegroundColor Yellow
