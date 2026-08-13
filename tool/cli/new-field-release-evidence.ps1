#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ReleaseManifestPath = 'build/field-release/release-manifest.json',
    [string]$DeviceEvidenceDirectory = 'field/evidence/devices',
    [string]$OutputPath = 'field/evidence/release-evidence.json',
    [string]$CloudControlsRecordPath =
        'field/evidence/cloud/cloud-controls.json',
    [string]$CentralCostEvidencePath =
        'field/evidence/cloud/central-cost.json',
    [string]$ParticipantPackageRecordPath =
        'field/evidence/private/participant-package.json',
    [string]$BetaOperationsRecordPath =
        'field/evidence/private/beta-operations.json',
    [string]$RollbackEvidenceRecordPath =
        'field/evidence/private/rollback-evidence.json',
    [string]$OwnerApprovalRecordPath =
        'field/evidence/private/owner-approval.json'
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

function ConvertTo-StrictUtcText {
    param([Parameter(Mandatory)][DateTimeOffset]$Value)

    return $Value.UtcDateTime.ToString(
        "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",
        [Globalization.CultureInfo]::InvariantCulture
    )
}

function Read-OptionalJsonRecord {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = Resolve-RepositoryPath $Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        return $null
    }
    return Get-Content -LiteralPath $resolved -Raw -Encoding utf8 |
        ConvertFrom-Json
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

$centralCost = Read-OptionalJsonRecord $CentralCostEvidencePath
if ($null -eq $centralCost) {
    $centralCost = [pscustomobject][ordered]@{
        schemaVersion = 1
        mode = 'pending'
        scope = 'firebaseProjectTotal'
        projectId = 'vocab-learning-app-219ef'
        projectNumber = '145034183638'
        currencyCode = 'THB'
        approvedMonthlyMinimumSatang = 0
        approvedMonthlyMaximumSatang = 10000
        measurementBasis = 'pending'
        measurementMonthUtc = ''
        measuredAtUtc = ''
        measuredMonthlyCostSatang = $null
        budget = $null
        evidenceRef = ''
    }
}

$cloudControls = Read-OptionalJsonRecord $CloudControlsRecordPath
if ($null -eq $cloudControls) {
    $cloudControls = [pscustomobject][ordered]@{
        appCheckConfigured = $false
        appCheckValidTrafficObserved = $false
        appCheckEnforced = $false
        assetLinksVerified = $false
        cloudKillSwitchVerified = $false
        appCheckObservedAtUtc = ''
        assetLinksObservedAtUtc = ''
        cloudKillSwitchObservedAtUtc = ''
        appCheckEvidenceRef = ''
        budgetAlertsEvidenceRef = ''
        assetLinksEvidenceRef = ''
        cloudKillSwitchEvidenceRef = ''
    }
}
$cloudControls | Add-Member -NotePropertyName centralCost `
    -NotePropertyValue $centralCost -Force

$participantPackage = Read-OptionalJsonRecord $ParticipantPackageRecordPath
if ($null -eq $participantPackage) {
    $participantPackage = [pscustomobject][ordered]@{
        installGuide = 'docs/install-and-update.md'
        privacyNotice = 'docs/privacy-and-consent-v1.md'
        dataRightsGuide = 'docs/data-export-and-deletion.md'
        knownLimitations = 'docs/known-limitations.md'
        feedbackGuide = 'docs/feedback-and-support.md'
        researchProtocol = 'docs/research-protocol-v1.md'
        consentVersion = 1
        documentSha256 = [pscustomobject][ordered]@{
            installGuide = ''
            privacyNotice = ''
            dataRightsGuide = ''
            knownLimitations = ''
            feedbackGuide = ''
            researchProtocol = ''
        }
        verifiedAtUtc = ''
        feedbackChannelRef = ''
        supportChannelRef = ''
        researchProtocolRef = ''
    }
}

$betaOperations = Read-OptionalJsonRecord $BetaOperationsRecordPath
if ($null -eq $betaOperations) {
    $betaOperations = [pscustomobject][ordered]@{
        status = 'pending'
        release = [ordered]@{
            apkSha256 = [string]$manifest.artifact.apkSha256
            buildId = [string]$manifest.artifact.buildId
            versionCode = [int]$manifest.artifact.versionCode
        }
        windowStartedAtUtc = ''
        windowEndedAtUtc = ''
        testerCount = 0
        consentVersion = 1
        sessions = [ordered]@{
            totalCount = 0
            crashFreeCount = 0
            crashCount = $null
            anrCount = $null
            evidenceRef = ''
        }
        sync = [ordered]@{
            attemptCount = 0
            failureCount = $null
            evidenceRef = ''
        }
        openIssues = [ordered]@{
            criticalCount = $null
            highCount = $null
            mediumCount = $null
            lowCount = $null
            evidenceRef = ''
        }
        providerUsage = [ordered]@{
            requestCount = 0
            successCount = 0
            failureCount = $null
            indeterminateCount = $null
            costKnownRequestCount = 0
            providerReportedCostMicrosUsd = $null
            evidenceRef = ''
        }
        modelDownloads = [ordered]@{
            successfulCount = 0
            failedCount = $null
            countMayBeSaturated = $false
            evidenceRef = ''
        }
        ownerDecision = [ordered]@{
            decision = 'hold'
            decidedAtUtc = ''
            evidenceRef = ''
        }
    }
}

$rollbackEvidence = Read-OptionalJsonRecord $RollbackEvidenceRecordPath
if ($null -eq $rollbackEvidence) {
    $rollbackDrillId = [Guid]::NewGuid().ToString('D')
    $rollbackCandidate = [ordered]@{
        apkSha256 = [string]$manifest.artifact.apkSha256
        buildId = [string]$manifest.artifact.buildId
        versionCode = [int]$manifest.artifact.versionCode
    }
    $rollbackTarget = [ordered]@{
        apkSha256 = ''
        signingCertificateSha256 = ''
        versionCode = 0
    }
    $rollbackEvidence = [pscustomobject][ordered]@{
        status = 'pending'
        drillId = $rollbackDrillId
        candidate = $rollbackCandidate
        target = $rollbackTarget
        startedAtUtc = ''
        completedAtUtc = ''
        targetLaunchVerified = $false
        coreOfflineJourneyVerified = $false
        serviceRestored = $false
        dataOutcome = 'pending'
        evidenceRef = ''
        killSwitchDrill = [ordered]@{
            drillId = $rollbackDrillId
            candidate = $rollbackCandidate
            target = $rollbackTarget
            startedAtUtc = ''
            completedAtUtc = ''
            status = 'pending'
            cloudSyncDisabledObserved = $false
            localLearningUsable = $false
            cloudSyncRestored = $false
            evidenceRef = ''
        }
    }
}

$ownerApproval = Read-OptionalJsonRecord $OwnerApprovalRecordPath
if ($null -eq $ownerApproval) {
    $ownerApproval = [pscustomobject][ordered]@{
        approved = $false
        apkSha256 = [string]$manifest.artifact.apkSha256
        sourceCommit = [string]$manifest.sourceCommit
        signingCertificateSha256 =
            [string]$manifest.artifact.signingCertificateSha256
        modelSha256 = [string]$manifest.artifact.modelSha256
        versionName = [string]$manifest.artifact.versionName
        versionCode = [int]$manifest.artifact.versionCode
        buildId = [string]$manifest.artifact.buildId
        approvedAtUtc = ''
        approverRole = 'owner'
        evidenceRef = ''
    }
}

$evidence = [ordered]@{
    schemaVersion = 2
    sourceCommit = [string]$manifest.sourceCommit
    releaseId = '{0}:{1}' -f
        $manifest.sourceCommit,
        $manifest.artifact.apkSha256
    manifestGeneratedAtUtc = [string]$manifest.generatedAtUtc
    assembledAtUtc = (
        ConvertTo-StrictUtcText ([DateTimeOffset]::UtcNow)
    )
    artifact = $manifest.artifact
    cloudControls = $cloudControls
    participantPackage = $participantPackage
    devices = $devices
    betaOperations = $betaOperations
    rollbackEvidence = $rollbackEvidence
    ownerApproval = $ownerApproval
}

$parent = Split-Path -Parent $outputFile
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$evidence | ConvertTo-Json -Depth 20 |
    Set-Content -LiteralPath $outputFile -Encoding utf8
Write-Host "Field release evidence shell assembled: $outputFile" `
    -ForegroundColor Yellow
