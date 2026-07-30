#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ReleaseManifestPath = 'build/field-release/release-manifest.json',
    [string]$DeviceEvidenceDirectory = 'field/evidence/devices',
    [string]$OutputPath = 'field/evidence/release-evidence.json',
    [Parameter(Mandatory)]
    [string]$FeedbackChannelRef,
    [Parameter(Mandatory)]
    [string]$SupportChannelRef,
    [Parameter(Mandatory)]
    [string]$ResearchProtocolRef,
    [switch]$AppCheckConfigured,
    [switch]$BudgetAlertsConfigured,
    [switch]$AssetLinksVerified,
    [switch]$CloudKillSwitchVerified,
    [string]$AppCheckEvidenceRef = '',
    [string]$BudgetAlertsEvidenceRef = '',
    [string]$AssetLinksEvidenceRef = '',
    [string]$CloudKillSwitchEvidenceRef = '',
    [switch]$OwnerApproved,
    [string]$OwnerApprovalEvidenceRef = ''
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Resolve-RepositoryPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

$manifestPath = Resolve-RepositoryPath $ReleaseManifestPath
$deviceDirectory = Resolve-RepositoryPath $DeviceEvidenceDirectory
$outputFile = Resolve-RepositoryPath $OutputPath
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Release manifest is missing: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 |
    ConvertFrom-Json
$devices = @()
if (Test-Path -LiteralPath $deviceDirectory -PathType Container) {
    $devices = @(
        Get-ChildItem -LiteralPath $deviceDirectory -File -Filter '*.json' |
            Sort-Object Name |
            ForEach-Object {
                Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8 |
                    ConvertFrom-Json
            }
    )
}

$approvedAt = if ($OwnerApproved) {
    [DateTime]::UtcNow.ToString('o')
} else {
    ''
}
$evidence = [ordered]@{
    schemaVersion = 1
    releaseId = '{0}-{1}' -f
        $manifest.artifact.versionName,
        $manifest.artifact.buildId
    artifact = $manifest.artifact
    cloudControls = [ordered]@{
        appCheckConfigured = [bool]$AppCheckConfigured
        budgetAlertsConfigured = [bool]$BudgetAlertsConfigured
        assetLinksVerified = [bool]$AssetLinksVerified
        cloudKillSwitchVerified = [bool]$CloudKillSwitchVerified
        appCheckEvidenceRef = $AppCheckEvidenceRef
        budgetAlertsEvidenceRef = $BudgetAlertsEvidenceRef
        assetLinksEvidenceRef = $AssetLinksEvidenceRef
        cloudKillSwitchEvidenceRef = $CloudKillSwitchEvidenceRef
    }
    participantPackage = [ordered]@{
        installGuide = 'docs/install-and-update.md'
        privacyNotice = 'docs/privacy-and-consent-v1.md'
        dataRightsGuide = 'docs/data-export-and-deletion.md'
        knownLimitations = 'docs/known-limitations.md'
        feedbackGuide = 'docs/feedback-and-support.md'
        consentVersion = 1
        feedbackChannelRef = $FeedbackChannelRef
        supportChannelRef = $SupportChannelRef
        researchProtocolRef = $ResearchProtocolRef
    }
    devices = $devices
    ownerApproval = [ordered]@{
        approved = [bool]$OwnerApproved
        apkSha256 = $manifest.artifact.apkSha256
        approvedAtUtc = $approvedAt
        approverRole = 'owner'
        evidenceRef = $OwnerApprovalEvidenceRef
    }
}

$parent = Split-Path -Parent $outputFile
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$evidence | ConvertTo-Json -Depth 16 |
    Set-Content -LiteralPath $outputFile -Encoding utf8
Write-Host "Field release evidence assembled: $outputFile" `
    -ForegroundColor Yellow
