#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0

function Assert-True {
    param([object]$Value, [string]$Message)
    if ($Value) {
        $script:Passed++
    } else {
        $script:Failed++
        Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
    }
}

function New-Journeys {
    $journeys = [ordered]@{}
    foreach ($name in Get-LexiQuestRequiredFieldJourneys) {
        $journeys[$name] = [pscustomobject]@{
            status = 'pass'
            evidenceRef = "private:$name"
        }
    }
    return [pscustomobject]$journeys
}

function New-Device {
    param([string]$Tier, [string]$IdCharacter)
    return [pscustomobject]@{
        evidenceId = "$Tier-device"
        tier = $Tier
        pseudonymousDeviceId = $IdCharacter * 64
        recordedAtUtc = '2026-07-30T00:00:00Z'
        device = [pscustomobject]@{
            physical = $true
            model = "$Tier phone"
            androidVersion = '15'
            ramMb = 4096
            chipset = 'test chipset'
            gpu = 'test gpu'
            storageFreeMb = 10240
            networkProfile = 'offline-mixed'
        }
        release = [pscustomobject]@{
            apkSha256 = 'A' * 64
            signingCertificateSha256 = 'B' * 64
            modelSha256 = 'C' * 64
            versionName = '1.0.0'
            versionCode = 1
            buildId = 'abc123'
        }
        journeys = (New-Journeys)
        benchmarks = [pscustomobject]@{
            cpuXnnpack = [pscustomobject]@{
                status = 'pass'
                delegate = 'xnnpack'
                iterations = 20
                medianLatencyMs = 11.5
                evidenceRef = 'private:cpu-benchmark'
            }
            gpuDelegate = [pscustomobject]@{
                status = 'notApplicable'
                allowlisted = $false
                iterations = 0
                reason = 'GPU not allowlisted.'
                evidenceRef = 'private:gpu-policy'
            }
        }
        endurance = [pscustomobject]@{
            status = 'pass'
            durationMinutes = 30
            crashCount = 0
            anrCount = 0
            peakRssMb = 300
            batteryStartPercent = 90
            batteryEndPercent = 80
            temperatureStartC = 31
            temperatureEndC = 38
            evidenceRef = 'private:endurance'
        }
    }
}

$repoRoot = Split-Path -Parent (
    Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
)
. (Join-Path $repoRoot 'tool/cli/lib/field-release-evidence.ps1')

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'lexiquest-field-test-' + [Guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    foreach ($document in @(
        'install.md',
        'privacy.md',
        'data.md',
        'limitations.md',
        'feedback.md'
    )) {
        Set-Content -LiteralPath (Join-Path $tempRoot $document) `
            -Value 'verified contract fixture' -Encoding utf8
    }
    $evidence = [pscustomobject]@{
        schemaVersion = 1
        releaseId = 'release-1'
        artifact = [pscustomobject]@{
            apkSha256 = 'A' * 64
            signingCertificateSha256 = 'B' * 64
            modelSha256 = 'C' * 64
            packageName = 'com.lexiquest.app'
            versionName = '1.0.0'
            versionCode = 1
            buildId = 'abc123'
        }
        cloudControls = [pscustomobject]@{
            appCheckConfigured = $true
            budgetAlertsConfigured = $true
            assetLinksVerified = $true
            cloudKillSwitchVerified = $true
            appCheckEvidenceRef = 'private:app-check'
            budgetAlertsEvidenceRef = 'private:budget'
            assetLinksEvidenceRef = 'private:app-links'
            cloudKillSwitchEvidenceRef = 'private:kill-switch'
        }
        participantPackage = [pscustomobject]@{
            installGuide = 'install.md'
            privacyNotice = 'privacy.md'
            dataRightsGuide = 'data.md'
            knownLimitations = 'limitations.md'
            feedbackGuide = 'feedback.md'
            consentVersion = 1
            feedbackChannelRef = 'private:feedback-channel-record'
            supportChannelRef = 'private:support-channel-record'
            researchProtocolRef = 'private:research-protocol'
        }
        devices = @(
            (New-Device 'low' '1'),
            (New-Device 'mid' '2'),
            (New-Device 'high' '3')
        )
        ownerApproval = [pscustomobject]@{
            approved = $true
            apkSha256 = 'A' * 64
            approvedAtUtc = '2026-07-30T00:00:00Z'
            approverRole = 'owner'
            evidenceRef = 'private:owner-smoke'
        }
    }

    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True ($errors.Count -eq 0) `
        'complete, reconciled evidence passes the pure validator'

    $evidence.devices[0].journeys.offlineRestartSync.status = 'pending'
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'offlineRestartSync must pass'
    ) 'a pending mandatory journey blocks release'
    $evidence.devices[0].journeys.offlineRestartSync.status = 'pass'

    $evidence.devices[1].endurance.durationMinutes = 29
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'endurance must pass >=30 minutes'
    ) 'an incomplete endurance run blocks release'
    $evidence.devices[1].endurance.durationMinutes = 30

    $evidence.ownerApproval.approved = $false
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'ownerApproval.approved must be true'
    ) 'owner approval cannot be omitted'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

$gateText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/verify-field-release.ps1'
) -Raw -Encoding utf8
foreach ($needle in @(
    'apksigner',
    'Get-FileHash',
    'verify-product-completion.ps1',
    'verify-apk-model-runtime.ps1',
    'Test-LexiQuestFieldReleaseEvidence'
)) {
    Assert-True $gateText.Contains($needle) "final gate contains $needle"
}

$collectorText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/collect-android-field-evidence.ps1'
) -Raw -Encoding utf8
foreach ($needle in @(
    'ro.kernel.qemu',
    'pseudonymousDeviceId',
    "status = 'pending'",
    'install -r',
    'Get-LexiQuestRequiredFieldJourneys'
)) {
    Assert-True $collectorText.Contains($needle) "collector contains $needle"
}
Assert-True (
    $collectorText -notmatch "(?m)status\s*=\s*'pass'.*(camera|speech|gemini)"
) 'collector never fabricates camera, speech, or Gemini passes'

$packagerText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/package-field-release.ps1'
) -Raw -Encoding utf8
foreach ($needle in @(
    'android/key.properties',
    'flutter build apk --release',
    'apksigner',
    'signingCertificateSha256',
    'Get-FileHash',
    'git status --porcelain'
)) {
    Assert-True $packagerText.Contains($needle) "packager contains $needle"
}

$assemblerText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/new-field-release-evidence.ps1'
) -Raw -Encoding utf8
foreach ($needle in @(
    'FeedbackChannelRef',
    'SupportChannelRef',
    'ResearchProtocolRef',
    'AppCheckConfigured',
    'BudgetAlertsConfigured',
    'AssetLinksVerified',
    'CloudKillSwitchVerified',
    'OwnerApproved',
    'DeviceEvidenceDirectory'
)) {
    Assert-True $assemblerText.Contains($needle) "assembler contains $needle"
}

Write-Host (
    'Field release tests: {0} passed, {1} failed' -f
    $script:Passed,
    $script:Failed
)
if ($script:Failed -gt 0) {
    exit 1
}
Write-Host 'PASS' -ForegroundColor Green
exit 0
