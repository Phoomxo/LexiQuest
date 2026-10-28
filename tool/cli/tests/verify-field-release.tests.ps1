#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0
$script:NowUtc = [DateTimeOffset]::UtcNow
$script:ManifestGeneratedAtUtc = $script:NowUtc.AddHours(-6)
$script:DeviceRecordedAtUtc = $script:NowUtc.AddHours(-5)
$script:CloudObservedAtUtc = $script:NowUtc.AddHours(-4)
$script:BetaStartedAtUtc = $script:NowUtc.AddHours(-3)
$script:BetaEndedAtUtc = $script:NowUtc.AddHours(-2)
$script:RollbackStartedAtUtc = $script:NowUtc.AddMinutes(-110)
$script:RollbackCompletedAtUtc = $script:NowUtc.AddMinutes(-90)
$script:RollbackDrillId = '11111111-1111-4111-8111-111111111111'
$script:OwnerApprovedAtUtc = $script:NowUtc.AddMinutes(-60)
$script:AssembledAtUtc = $script:NowUtc.AddMinutes(-30)
$script:SourceCommit = 'a' * 40

function Assert-True {
    param([object]$Value, [string]$Message)
    if ($Value) {
        $script:Passed++
    } else {
        $script:Failed++
        Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
    }
}

function New-PrivateEvidenceRef {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [string]$Directory = '',
        [AllowNull()][object]$Payload = $null,
        [AllowNull()][object]$SourcePayload = $null,
        [string]$CaptureMethod = '',
        [bool]$HostFake = $false,
        [switch]$OmitSourceExport,
        [AllowNull()][System.Security.Cryptography.RSA]$SigningRsa = $null
    )

    if ($null -eq $SigningRsa) {
        $SigningRsa = $script:EvidenceSigningRsa
    }

    $id = [Guid]::NewGuid().ToString('D')
    $origin = if ($Kind -like 'device-*') {
        'physical-android-collector'
    } elseif ($Kind -in @(
        'app-check',
        'billing',
        'asset-links'
    )) {
        'provider-console-export'
    } elseif ($Kind -eq 'owner-approval') {
        'owner-attestation'
    } else {
        'beta-ops-export'
    }
    $sourceExportSha256 = ''
    if (-not $OmitSourceExport) {
        if ([string]::IsNullOrWhiteSpace($CaptureMethod)) {
            $CaptureMethod = if ($Kind -like 'device-*') {
                'physical-android-collector'
            } elseif ($origin -ceq 'provider-console-export') {
                'provider-console-export'
            } elseif ($origin -ceq 'owner-attestation') {
                'owner-attestation'
            } else {
                'release-instrumentation-export'
            }
        }
        if ($null -eq $SourcePayload) {
            $SourcePayload = $Payload
        }
        $sourceEnvelope = [ordered]@{
            schemaVersion = 1
            kind = $Kind
            origin = $origin
            captureMethod = $CaptureMethod
            hostFake = $HostFake
            sourceCommit = $script:SourceCommit
            apkSha256 = 'A' * 64
            observedAtUtc = (
                ConvertTo-StrictUtcText $script:CloudObservedAtUtc
            )
            payload = $SourcePayload
        }
        $sourceBytes = [Text.UTF8Encoding]::new($false).GetBytes(
            ($sourceEnvelope | ConvertTo-Json -Depth 20 -Compress) + "`r`n"
        )
        $sourceSha = [Security.Cryptography.SHA256]::Create()
        try {
            $sourceExportSha256 = (
                [BitConverter]::ToString(
                    $sourceSha.ComputeHash($sourceBytes)
                )
            ).Replace('-', '')
        }
        finally {
            $sourceSha.Dispose()
        }
        if (-not [string]::IsNullOrWhiteSpace($Directory)) {
            $sourceDirectory = Join-Path $Directory 'sources'
            New-Item -ItemType Directory -Path $sourceDirectory -Force |
                Out-Null
            [IO.File]::WriteAllBytes(
                (Join-Path $sourceDirectory "$sourceExportSha256.source"),
                $sourceBytes
            )
        }
    }
    $receipt = [ordered]@{
        schemaVersion = 2
        kind = $Kind
        receiptId = $id
        origin = $origin
        observedAtUtc = (
            ConvertTo-StrictUtcText $script:CloudObservedAtUtc
        )
        sourceCommit = $script:SourceCommit
        apkSha256 = 'A' * 64
        sourceExportSha256 = $sourceExportSha256
        payload = $Payload
    }
    $signingJson = $receipt | ConvertTo-Json -Depth 20 -Compress
    $signingBytes = [Text.UTF8Encoding]::new($false).GetBytes($signingJson)
    $publicKeyXml = $SigningRsa.ToXmlString($false)
    $publicKeyBytes = [Text.UTF8Encoding]::new($false).GetBytes($publicKeyXml)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $publicKeyDigest = (
            [BitConverter]::ToString($sha.ComputeHash($publicKeyBytes))
        ).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
    $receipt.signingKeyId = "sha256:$publicKeyDigest"
    $receipt.signatureAlgorithm = 'rsa-sha256-pkcs1'
    $receipt.signatureBase64 = [Convert]::ToBase64String(
        $SigningRsa.SignData(
            $signingBytes,
            [Security.Cryptography.HashAlgorithmName]::SHA256,
            [Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
    )
    $json = $receipt | ConvertTo-Json -Depth 20 -Compress
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json + "`r`n")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace(
            '-',
            ''
        )
    }
    finally {
        $sha.Dispose()
    }
    if (-not [string]::IsNullOrWhiteSpace($Directory)) {
        $blobDirectory = Join-Path $Directory 'blobs'
        New-Item -ItemType Directory -Path $blobDirectory -Force |
            Out-Null
        [IO.File]::WriteAllBytes(
            (Join-Path $blobDirectory "$digest.receipt"),
            $bytes
        )
    }
    return "private-evidence:v1:$Kind`:$id`:sha256:$digest"
}

function ConvertTo-StrictUtcText {
    param([Parameter(Mandatory)][DateTimeOffset]$Value)

    return $Value.UtcDateTime.ToString(
        "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",
        [Globalization.CultureInfo]::InvariantCulture
    )
}

function New-Journeys {
    param(
        [string]$PrivateEvidenceDirectory = '',
        [string]$EvidenceId,
        [string]$Tier,
        [string]$PseudonymousDeviceId
    )

    $journeys = [ordered]@{}
    foreach ($name in Get-LexiQuestRequiredFieldJourneys) {
        $payload = [pscustomobject][ordered]@{
            evidenceId = $EvidenceId
            tier = $Tier
            pseudonymousDeviceId = $PseudonymousDeviceId
            journey = $name
            status = 'pass'
        }
        $journeys[$name] = [pscustomobject]@{
            status = 'pass'
            evidenceRef = New-PrivateEvidenceRef `
                -Kind 'device-journey' `
                -Directory $PrivateEvidenceDirectory `
                -Payload $payload
        }
    }
    return [pscustomobject]$journeys
}

function New-Device {
    param(
        [string]$Tier,
        [string]$IdCharacter,
        [string]$PrivateEvidenceDirectory = '',
        [string]$CollectorScriptSha256 = ('E' * 64)
    )
    $evidenceId = "$Tier-device"
    $pseudonymousDeviceId = $IdCharacter * 64
    $recordedAtUtc = ConvertTo-StrictUtcText $script:DeviceRecordedAtUtc
    $deviceRecord = [pscustomobject][ordered]@{
        physical = $true
        model = "$Tier phone"
        androidVersion = '15'
        ramMb = 4096
        chipset = 'test chipset'
        gpu = 'test gpu'
        storageFreeMb = 10240
        networkProfile = 'offline-mixed'
    }
    $releaseRecord = [pscustomobject][ordered]@{
        apkSha256 = 'A' * 64
        signingCertificateSha256 = 'B' * 64
        modelSha256 = 'C' * 64
        versionName = '1.0.0'
        versionCode = 2
        buildId = 'abc123'
    }
    $collectorRecord = [ordered]@{
        schemaVersion = 1
        origin = 'physical-android-collector'
        collectorScriptSha256 = $CollectorScriptSha256
        connectedDeviceCount = 1
        roKernelQemu = '0'
        roBootQemu = '0'
        serialKind = 'physical'
        buildType = 'user'
        debuggable = '0'
        secure = '1'
        fingerprint = 'vendor/device/product:user/release-keys'
        brand = 'vendor'
        deviceName = 'device'
        hardware = 'chipset'
        verifiedApkSha256 = 'A' * 64
    }
    $collectorPayload = [pscustomobject][ordered]@{
        evidenceId = $evidenceId
        tier = $Tier
        pseudonymousDeviceId = $pseudonymousDeviceId
        recordedAtUtc = $recordedAtUtc
        device = $deviceRecord
        release = $releaseRecord
        collector = [pscustomobject]$collectorRecord
    }
    $collectorRecord['evidenceRef'] = New-PrivateEvidenceRef `
        -Kind 'device-attestation' `
        -Directory $PrivateEvidenceDirectory `
        -Payload $collectorPayload
    $cpuPayload = [pscustomobject][ordered]@{
        evidenceId = $evidenceId
        tier = $Tier
        pseudonymousDeviceId = $pseudonymousDeviceId
        benchmark = 'cpuXnnpack'
        status = 'pass'
        delegate = 'xnnpack'
        iterations = 20
        medianLatencyMs = 11.5
    }
    $gpuPayload = [pscustomobject][ordered]@{
        evidenceId = $evidenceId
        tier = $Tier
        pseudonymousDeviceId = $pseudonymousDeviceId
        benchmark = 'gpuDelegate'
        status = 'notApplicable'
        allowlisted = $false
        iterations = 0
        reason = 'GPU not allowlisted.'
    }
    $endurancePayload = [pscustomobject][ordered]@{
        evidenceId = $evidenceId
        tier = $Tier
        pseudonymousDeviceId = $pseudonymousDeviceId
        status = 'pass'
        durationMinutes = 30
        crashCount = 0
        anrCount = 0
        peakRssMb = 300
        batteryStartPercent = 90
        batteryEndPercent = 80
        temperatureStartC = 31
        temperatureEndC = 38
    }

    return [pscustomobject]@{
        evidenceId = $evidenceId
        tier = $Tier
        pseudonymousDeviceId = $pseudonymousDeviceId
        recordedAtUtc = $recordedAtUtc
        device = $deviceRecord
        release = $releaseRecord
        collector = [pscustomobject]$collectorRecord
        journeys = (New-Journeys `
            $PrivateEvidenceDirectory `
            $evidenceId `
            $Tier `
            $pseudonymousDeviceId)
        benchmarks = [pscustomobject]@{
            cpuXnnpack = [pscustomobject]@{
                status = 'pass'
                delegate = 'xnnpack'
                iterations = 20
                medianLatencyMs = 11.5
                evidenceRef = New-PrivateEvidenceRef `
                    -Kind 'device-benchmark' `
                    -Directory $PrivateEvidenceDirectory `
                    -Payload $cpuPayload
            }
            gpuDelegate = [pscustomobject]@{
                status = 'notApplicable'
                allowlisted = $false
                iterations = 0
                reason = 'GPU not allowlisted.'
                evidenceRef = New-PrivateEvidenceRef `
                    -Kind 'device-benchmark' `
                    -Directory $PrivateEvidenceDirectory `
                    -Payload $gpuPayload
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
            evidenceRef = New-PrivateEvidenceRef `
                -Kind 'device-endurance' `
                -Directory $PrivateEvidenceDirectory `
                -Payload $endurancePayload
        }
    }
}

$repoRoot = Split-Path -Parent (
    Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
)
. (Join-Path $repoRoot 'tool/cli/lib/field-release-evidence.ps1')

Assert-True (
    Test-LexiQuestPostPackageMetadataPath `
        'docs/field/2026-08-09-final-acceptance.md'
) 'final acceptance metadata may be committed after packaging'
Assert-True (-not (
    Test-LexiQuestPostPackageMetadataPath `
        'tool/cli/verify-field-release.ps1'
)) 'release-verifier changes invalidate a packaged source checkpoint'
Assert-True (-not (
    Test-LexiQuestPostPackageMetadataPath `
        'integration_test/field_runtime_journey_test.dart'
)) 'integration-harness changes invalidate a packaged source checkpoint'
Assert-True (-not (
    Test-LexiQuestPostPackageMetadataPath 'pubspec.yaml'
)) 'version changes must be committed before packaging'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'lexiquest-field-test-' + [Guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $privateEvidenceDirectory = Join-Path $tempRoot 'private-evidence'
    New-Item -ItemType Directory -Path $privateEvidenceDirectory -Force |
        Out-Null
    $script:EvidenceSigningRsa =
        [System.Security.Cryptography.RSA]::Create(3072)
    $trustedEvidencePublicKeyPath = Join-Path $tempRoot `
        'trusted-evidence-public-key.xml'
    [IO.File]::WriteAllText(
        $trustedEvidencePublicKeyPath,
        $script:EvidenceSigningRsa.ToXmlString($false),
        [Text.UTF8Encoding]::new($false)
    )
    foreach ($document in @(
        'install.md',
        'privacy.md',
        'data.md',
        'limitations.md',
        'feedback.md',
        'protocol.md'
    )) {
        Set-Content -LiteralPath (Join-Path $tempRoot $document) `
            -Value 'verified contract fixture' -Encoding utf8
    }
    $participantDocumentSha256 = [pscustomobject][ordered]@{
        installGuide = (Get-FileHash `
            -LiteralPath (Join-Path $tempRoot 'install.md') `
            -Algorithm SHA256).Hash
        privacyNotice = (Get-FileHash `
            -LiteralPath (Join-Path $tempRoot 'privacy.md') `
            -Algorithm SHA256).Hash
        dataRightsGuide = (Get-FileHash `
            -LiteralPath (Join-Path $tempRoot 'data.md') `
            -Algorithm SHA256).Hash
        knownLimitations = (Get-FileHash `
            -LiteralPath (Join-Path $tempRoot 'limitations.md') `
            -Algorithm SHA256).Hash
        feedbackGuide = (Get-FileHash `
            -LiteralPath (Join-Path $tempRoot 'feedback.md') `
            -Algorithm SHA256).Hash
        researchProtocol = (Get-FileHash `
            -LiteralPath (Join-Path $tempRoot 'protocol.md') `
            -Algorithm SHA256).Hash
    }
    $cloudObservedText = ConvertTo-StrictUtcText $script:CloudObservedAtUtc
    $appCheckPayload = [pscustomobject][ordered]@{
        configured = $true
        validTrafficObserved = $true
        enforced = $true
        observedAtUtc = $cloudObservedText
    }
    $budgetAlertsPayload = [pscustomobject][ordered]@{
        configured = $true
        notApplicable = $false
        billingMode = 'budgeted'
        observedAtUtc = $cloudObservedText
    }
    $assetLinksPayload = [pscustomobject][ordered]@{
        verified = $true
        observedAtUtc = $cloudObservedText
    }
    $cloudKillSwitchPayload = [pscustomobject][ordered]@{
        verified = $true
        observedAtUtc = $cloudObservedText
    }
    $rollbackKillSwitchPayload = [pscustomobject][ordered]@{
        drillId = $script:RollbackDrillId
        candidate = [pscustomobject][ordered]@{
            apkSha256 = 'A' * 64
            buildId = 'abc123'
            versionCode = 2
        }
        target = [pscustomobject][ordered]@{
            apkSha256 = 'D' * 64
            signingCertificateSha256 = 'B' * 64
            versionCode = 1
        }
        startedAtUtc = (
            ConvertTo-StrictUtcText $script:RollbackStartedAtUtc
        )
        completedAtUtc = (
            ConvertTo-StrictUtcText $script:RollbackCompletedAtUtc
        )
        status = 'pass'
        cloudSyncDisabledObserved = $true
        localLearningUsable = $true
        cloudSyncRestored = $true
    }
    $participantFeedbackPayload = [pscustomobject][ordered]@{
        channel = 'feedback'
        verifiedAtUtc = $cloudObservedText
        consentVersion = 1
        documentSha256 = $participantDocumentSha256
    }
    $participantSupportPayload = [pscustomobject][ordered]@{
        channel = 'support'
        verifiedAtUtc = $cloudObservedText
        consentVersion = 1
        documentSha256 = $participantDocumentSha256
    }
    $researchProtocolPayload = [pscustomobject][ordered]@{
        channel = 'research-protocol'
        verifiedAtUtc = $cloudObservedText
        consentVersion = 1
        documentSha256 = $participantDocumentSha256
    }
    $centralCostPayload = [pscustomobject][ordered]@{
        schemaVersion = 1
        mode = 'budgeted'
        scope = 'firebaseProjectTotal'
        projectId = 'vocab-learning-app-219ef'
        projectNumber = '145034183638'
        currencyCode = 'THB'
        approvedMonthlyMinimumSatang = 0
        approvedMonthlyMaximumSatang = 10000
        measurementBasis = 'calendarMonthToDateGrossCost'
        measurementMonthUtc = $script:NowUtc.ToString('yyyy-MM')
        measuredAtUtc = (
            ConvertTo-StrictUtcText $script:CloudObservedAtUtc
        )
        measuredMonthlyCostSatang = 7550
        budget = [pscustomobject][ordered]@{
            monthlyAmountSatang = 10000
            thresholds = @(0.5, 0.8, 1.0)
            spendBasis = 'CURRENT_SPEND'
            recipientsConfigured = $true
        }
    }
    $betaSessionsPayload = [pscustomobject][ordered]@{
        release = [pscustomobject][ordered]@{
            apkSha256 = 'A' * 64
            buildId = 'abc123'
            versionCode = 2
        }
        windowStartedAtUtc = (
            ConvertTo-StrictUtcText $script:BetaStartedAtUtc
        )
        windowEndedAtUtc = (
            ConvertTo-StrictUtcText $script:BetaEndedAtUtc
        )
        testerCount = 3
        consentVersion = 1
        totalCount = 30
        crashFreeCount = 30
        crashCount = 0
        anrCount = 0
    }
    $betaContext = [ordered]@{
        release = $betaSessionsPayload.release
        windowStartedAtUtc = $betaSessionsPayload.windowStartedAtUtc
        windowEndedAtUtc = $betaSessionsPayload.windowEndedAtUtc
        testerCount = $betaSessionsPayload.testerCount
        consentVersion = $betaSessionsPayload.consentVersion
    }
    $betaSyncPayload = [pscustomobject][ordered]@{
        release = $betaContext.release
        windowStartedAtUtc = $betaContext.windowStartedAtUtc
        windowEndedAtUtc = $betaContext.windowEndedAtUtc
        testerCount = $betaContext.testerCount
        consentVersion = $betaContext.consentVersion
        attemptCount = 10
        failureCount = 0
    }
    $betaIssuesPayload = [pscustomobject][ordered]@{
        release = $betaContext.release
        windowStartedAtUtc = $betaContext.windowStartedAtUtc
        windowEndedAtUtc = $betaContext.windowEndedAtUtc
        testerCount = $betaContext.testerCount
        consentVersion = $betaContext.consentVersion
        criticalCount = 0
        highCount = 0
        mediumCount = 0
        lowCount = 1
    }
    $betaProviderPayload = [pscustomobject][ordered]@{
        release = $betaContext.release
        windowStartedAtUtc = $betaContext.windowStartedAtUtc
        windowEndedAtUtc = $betaContext.windowEndedAtUtc
        testerCount = $betaContext.testerCount
        consentVersion = $betaContext.consentVersion
        requestCount = 5
        successCount = 5
        failureCount = 0
        indeterminateCount = 0
        costKnownRequestCount = 5
        providerReportedCostMicrosUsd = 12000
    }
    $betaDownloadsPayload = [pscustomobject][ordered]@{
        release = $betaContext.release
        windowStartedAtUtc = $betaContext.windowStartedAtUtc
        windowEndedAtUtc = $betaContext.windowEndedAtUtc
        testerCount = $betaContext.testerCount
        consentVersion = $betaContext.consentVersion
        successfulCount = 3
        failedCount = 0
        countMayBeSaturated = $false
    }
    $betaDecisionPayload = [pscustomobject][ordered]@{
        release = $betaContext.release
        windowStartedAtUtc = $betaContext.windowStartedAtUtc
        windowEndedAtUtc = $betaContext.windowEndedAtUtc
        testerCount = $betaContext.testerCount
        consentVersion = $betaContext.consentVersion
        decision = 'proceed'
        decidedAtUtc = (
            ConvertTo-StrictUtcText (
                $script:BetaEndedAtUtc.AddMinutes(5)
            )
        )
    }
    $rollbackPayload = [pscustomobject][ordered]@{
        drillId = $script:RollbackDrillId
        candidate = [pscustomobject][ordered]@{
            apkSha256 = 'A' * 64
            buildId = 'abc123'
            versionCode = 2
        }
        target = [pscustomobject][ordered]@{
            apkSha256 = 'D' * 64
            signingCertificateSha256 = 'B' * 64
            versionCode = 1
        }
        startedAtUtc = (
            ConvertTo-StrictUtcText $script:RollbackStartedAtUtc
        )
        completedAtUtc = (
            ConvertTo-StrictUtcText $script:RollbackCompletedAtUtc
        )
        targetLaunchVerified = $true
        coreOfflineJourneyVerified = $true
        serviceRestored = $true
        dataOutcome = 'preserved'
    }
    $ownerApprovalPayload = [pscustomobject][ordered]@{
        approved = $true
        apkSha256 = 'A' * 64
        sourceCommit = $script:SourceCommit
        signingCertificateSha256 = 'B' * 64
        modelSha256 = 'C' * 64
        versionName = '1.0.0'
        versionCode = 2
        buildId = 'abc123'
        approvedAtUtc = (
            ConvertTo-StrictUtcText $script:OwnerApprovedAtUtc
        )
        approverRole = 'owner'
    }
    $evidence = [pscustomobject]@{
        schemaVersion = 2
        sourceCommit = $script:SourceCommit
        releaseId = '{0}:{1}' -f $script:SourceCommit, ('A' * 64)
        manifestGeneratedAtUtc = (
            ConvertTo-StrictUtcText $script:ManifestGeneratedAtUtc
        )
        assembledAtUtc = (
            ConvertTo-StrictUtcText $script:AssembledAtUtc
        )
        artifact = [pscustomobject]@{
            apkSha256 = 'A' * 64
            signingCertificateSha256 = 'B' * 64
            modelSha256 = 'C' * 64
            packageName = 'com.lexiquest.app'
            versionName = '1.0.0'
            versionCode = 2
            buildId = 'abc123'
        }
        cloudControls = [pscustomobject]@{
            appCheckConfigured = $true
            appCheckValidTrafficObserved = $true
            appCheckEnforced = $true
            budgetAlertsConfigured = $true
            budgetAlertsNotApplicable = $false
            billingMode = 'budgeted'
            assetLinksVerified = $true
            cloudKillSwitchVerified = $true
            appCheckObservedAtUtc = (
                ConvertTo-StrictUtcText $script:CloudObservedAtUtc
            )
            assetLinksObservedAtUtc = (
                ConvertTo-StrictUtcText $script:CloudObservedAtUtc
            )
            cloudKillSwitchObservedAtUtc = (
                ConvertTo-StrictUtcText $script:CloudObservedAtUtc
            )
            appCheckEvidenceRef = New-PrivateEvidenceRef `
                -Kind 'app-check' `
                -Directory $privateEvidenceDirectory `
                -Payload $appCheckPayload
            budgetAlertsEvidenceRef = New-PrivateEvidenceRef `
                -Kind 'billing' `
                -Directory $privateEvidenceDirectory `
                -Payload $budgetAlertsPayload
            assetLinksEvidenceRef = New-PrivateEvidenceRef `
                -Kind 'asset-links' `
                -Directory $privateEvidenceDirectory `
                -Payload $assetLinksPayload
            cloudKillSwitchEvidenceRef = New-PrivateEvidenceRef `
                -Kind 'kill-switch' `
                -Directory $privateEvidenceDirectory `
                -Payload $cloudKillSwitchPayload
            centralCost = [pscustomobject][ordered]@{
                schemaVersion = $centralCostPayload.schemaVersion
                mode = $centralCostPayload.mode
                scope = $centralCostPayload.scope
                projectId = $centralCostPayload.projectId
                projectNumber = $centralCostPayload.projectNumber
                currencyCode = $centralCostPayload.currencyCode
                approvedMonthlyMinimumSatang =
                    $centralCostPayload.approvedMonthlyMinimumSatang
                approvedMonthlyMaximumSatang =
                    $centralCostPayload.approvedMonthlyMaximumSatang
                measurementBasis = $centralCostPayload.measurementBasis
                measurementMonthUtc =
                    $centralCostPayload.measurementMonthUtc
                measuredAtUtc = $centralCostPayload.measuredAtUtc
                measuredMonthlyCostSatang =
                    $centralCostPayload.measuredMonthlyCostSatang
                budget = $centralCostPayload.budget
                evidenceRef = New-PrivateEvidenceRef `
                    -Kind 'billing' `
                    -Directory $privateEvidenceDirectory `
                    -Payload $centralCostPayload
            }
        }
        participantPackage = [pscustomobject]@{
            installGuide = 'install.md'
            privacyNotice = 'privacy.md'
            dataRightsGuide = 'data.md'
            knownLimitations = 'limitations.md'
            feedbackGuide = 'feedback.md'
            researchProtocol = 'protocol.md'
            consentVersion = 1
            documentSha256 = $participantDocumentSha256
            verifiedAtUtc = (
                ConvertTo-StrictUtcText $script:CloudObservedAtUtc
            )
            feedbackChannelRef = New-PrivateEvidenceRef `
                -Kind 'feedback-channel' `
                -Directory $privateEvidenceDirectory `
                -Payload $participantFeedbackPayload
            supportChannelRef = New-PrivateEvidenceRef `
                -Kind 'support-channel' `
                -Directory $privateEvidenceDirectory `
                -Payload $participantSupportPayload
            researchProtocolRef = New-PrivateEvidenceRef `
                -Kind 'research-protocol' `
                -Directory $privateEvidenceDirectory `
                -Payload $researchProtocolPayload
        }
        devices = @(
            (New-Device 'low' '0' $privateEvidenceDirectory),
            (New-Device 'mid' '1' $privateEvidenceDirectory),
            (New-Device 'high' '2' $privateEvidenceDirectory)
        )
        betaOperations = [pscustomobject]@{
            status = 'pass'
            release = $betaSessionsPayload.release
            windowStartedAtUtc = $betaSessionsPayload.windowStartedAtUtc
            windowEndedAtUtc = $betaSessionsPayload.windowEndedAtUtc
            testerCount = $betaSessionsPayload.testerCount
            consentVersion = $betaSessionsPayload.consentVersion
            sessions = [pscustomobject]@{
                totalCount = $betaSessionsPayload.totalCount
                crashFreeCount = $betaSessionsPayload.crashFreeCount
                crashCount = $betaSessionsPayload.crashCount
                anrCount = $betaSessionsPayload.anrCount
                evidenceRef = New-PrivateEvidenceRef `
                    -Kind 'beta-operations' `
                    -Directory $privateEvidenceDirectory `
                    -Payload $betaSessionsPayload
            }
            sync = [pscustomobject]@{
                attemptCount = $betaSyncPayload.attemptCount
                failureCount = $betaSyncPayload.failureCount
                evidenceRef = New-PrivateEvidenceRef `
                    -Kind 'beta-operations' `
                    -Directory $privateEvidenceDirectory `
                    -Payload $betaSyncPayload
            }
            openIssues = [pscustomobject]@{
                criticalCount = $betaIssuesPayload.criticalCount
                highCount = $betaIssuesPayload.highCount
                mediumCount = $betaIssuesPayload.mediumCount
                lowCount = $betaIssuesPayload.lowCount
                evidenceRef = New-PrivateEvidenceRef `
                    -Kind 'beta-operations' `
                    -Directory $privateEvidenceDirectory `
                    -Payload $betaIssuesPayload
            }
            providerUsage = [pscustomobject]@{
                requestCount = $betaProviderPayload.requestCount
                successCount = $betaProviderPayload.successCount
                failureCount = $betaProviderPayload.failureCount
                indeterminateCount = $betaProviderPayload.indeterminateCount
                costKnownRequestCount =
                    $betaProviderPayload.costKnownRequestCount
                providerReportedCostMicrosUsd =
                    $betaProviderPayload.providerReportedCostMicrosUsd
                evidenceRef = New-PrivateEvidenceRef `
                    -Kind 'beta-operations' `
                    -Directory $privateEvidenceDirectory `
                    -Payload $betaProviderPayload
            }
            modelDownloads = [pscustomobject]@{
                successfulCount = $betaDownloadsPayload.successfulCount
                failedCount = $betaDownloadsPayload.failedCount
                countMayBeSaturated =
                    $betaDownloadsPayload.countMayBeSaturated
                evidenceRef = New-PrivateEvidenceRef `
                    -Kind 'beta-operations' `
                    -Directory $privateEvidenceDirectory `
                    -Payload $betaDownloadsPayload
            }
            ownerDecision = [pscustomobject]@{
                decision = $betaDecisionPayload.decision
                decidedAtUtc = $betaDecisionPayload.decidedAtUtc
                evidenceRef = New-PrivateEvidenceRef `
                    -Kind 'beta-operations' `
                    -Directory $privateEvidenceDirectory `
                    -Payload $betaDecisionPayload
            }
        }
        rollbackEvidence = [pscustomobject]@{
            status = 'pass'
            drillId = $script:RollbackDrillId
            candidate = [pscustomobject]@{
                apkSha256 = 'A' * 64
                buildId = 'abc123'
                versionCode = 2
            }
            target = [pscustomobject]@{
                apkSha256 = 'D' * 64
                signingCertificateSha256 = 'B' * 64
                versionCode = 1
            }
            startedAtUtc = (
                ConvertTo-StrictUtcText $script:RollbackStartedAtUtc
            )
            completedAtUtc = (
                ConvertTo-StrictUtcText $script:RollbackCompletedAtUtc
            )
            targetLaunchVerified = $true
            coreOfflineJourneyVerified = $true
            serviceRestored = $true
            dataOutcome = 'preserved'
            evidenceRef = New-PrivateEvidenceRef `
                -Kind 'rollback-drill' `
                -Directory $privateEvidenceDirectory `
                -Payload $rollbackPayload
            killSwitchDrill = [pscustomobject]@{
                drillId = $script:RollbackDrillId
                candidate = $rollbackPayload.candidate
                target = $rollbackPayload.target
                startedAtUtc = $rollbackPayload.startedAtUtc
                completedAtUtc = $rollbackPayload.completedAtUtc
                status = 'pass'
                cloudSyncDisabledObserved = $true
                localLearningUsable = $true
                cloudSyncRestored = $true
                evidenceRef = New-PrivateEvidenceRef `
                    -Kind 'kill-switch' `
                    -Directory $privateEvidenceDirectory `
                    -Payload $rollbackKillSwitchPayload
            }
        }
        ownerApproval = [pscustomobject]@{
            approved = $ownerApprovalPayload.approved
            apkSha256 = $ownerApprovalPayload.apkSha256
            sourceCommit = $ownerApprovalPayload.sourceCommit
            signingCertificateSha256 =
                $ownerApprovalPayload.signingCertificateSha256
            modelSha256 = $ownerApprovalPayload.modelSha256
            versionName = $ownerApprovalPayload.versionName
            versionCode = $ownerApprovalPayload.versionCode
            buildId = $ownerApprovalPayload.buildId
            approvedAtUtc = $ownerApprovalPayload.approvedAtUtc
            approverRole = $ownerApprovalPayload.approverRole
            evidenceRef = New-PrivateEvidenceRef `
                -Kind 'owner-approval' `
                -Directory $privateEvidenceDirectory `
                -Payload $ownerApprovalPayload
        }
    }

    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -ExpectedSourceCommit $script:SourceCommit `
            -NowUtc $script:NowUtc `
            -ManifestGeneratedAtUtc `
                (ConvertTo-StrictUtcText $script:ManifestGeneratedAtUtc) `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath `
                $trustedEvidencePublicKeyPath `
            -ExpectedCollectorScriptSha256 ('E' * 64)
    )
    if ($errors.Count -gt 0) {
        Write-Host ('  baseline errors: ' + ($errors -join ' | '))
    }
    Assert-True ($errors.Count -eq 0) `
        'complete, reconciled evidence passes the pure validator'

    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -PrivateEvidenceDirectory $privateEvidenceDirectory
    )
    Assert-True (
        ($errors -join "`n") -match
            'trusted evidence public key is required'
    ) 'content-addressed receipts without a pinned signer fail closed'

    $originalAppCheckObservedAtUtc =
        $evidence.cloudControls.appCheckObservedAtUtc
    $evidence.cloudControls.appCheckObservedAtUtc = ConvertTo-StrictUtcText (
        $script:CloudObservedAtUtc.AddMinutes(1)
    )
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $trustedEvidencePublicKeyPath
    )
    Assert-True (
        ($errors -join "`n") -match
            'appCheckEvidenceRef must be a verified app-check reference'
    ) 'App Check claims are cryptographically bound to their receipt payload'
    $evidence.cloudControls.appCheckObservedAtUtc =
        $originalAppCheckObservedAtUtc

    $originalPackageVerifiedAtUtc = $evidence.participantPackage.verifiedAtUtc
    $evidence.participantPackage.verifiedAtUtc = ConvertTo-StrictUtcText (
        $script:CloudObservedAtUtc.AddMinutes(1)
    )
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $trustedEvidencePublicKeyPath
    )
    Assert-True (
        ($errors -join "`n") -match
            'feedbackChannelRef must be a verified feedback-channel reference'
    ) 'private-channel claims are bound to their signed receipt payload'
    $evidence.participantPackage.verifiedAtUtc = $originalPackageVerifiedAtUtc

    $originalInstallGuide = $evidence.participantPackage.installGuide
    $evidence.participantPackage.installGuide = '..\outside.md'
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $trustedEvidencePublicKeyPath
    )
    Assert-True (
        ($errors -join "`n") -match
            'installGuide must stay inside the package'
    ) 'participant-document paths cannot escape the immutable package'
    $evidence.participantPackage.installGuide = $originalInstallGuide

    $installGuidePath = Join-Path $tempRoot 'install.md'
    Set-Content -LiteralPath $installGuidePath `
        -Value 'tampered participant package' `
        -Encoding utf8
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $trustedEvidencePublicKeyPath
    )
    Assert-True (
        ($errors -join "`n") -match
            'installGuide content hash does not match'
    ) 'participant documents cannot change after their signed hash is recorded'
    Set-Content -LiteralPath $installGuidePath `
        -Value 'verified contract fixture' `
        -Encoding utf8

    $originalLowDeviceId = $evidence.devices[0].pseudonymousDeviceId
    $evidence.devices[0].pseudonymousDeviceId = '9' * 64
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $trustedEvidencePublicKeyPath
    )
    Assert-True (
        ($errors -join "`n") -match
            'low journey consentGuestStartup needs a verified'
    ) 'physical-device receipts bind the pseudonymous device identity'
    $evidence.devices[0].pseudonymousDeviceId = $originalLowDeviceId

    $originalApprovedAtUtc = $evidence.ownerApproval.approvedAtUtc
    $evidence.ownerApproval.approvedAtUtc = ConvertTo-StrictUtcText (
        $script:OwnerApprovedAtUtc.AddMinutes(1)
    )
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $trustedEvidencePublicKeyPath
    )
    Assert-True (
        ($errors -join "`n") -match
            'ownerApproval.evidenceRef must be a verified owner-approval'
    ) 'owner approval timestamp is bound to the signed approval receipt'
    $evidence.ownerApproval.approvedAtUtc = $originalApprovedAtUtc

    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -ExpectedSourceCommit ('b' * 40)
    )
    Assert-True (
        ($errors -join "`n") -match
            'sourceCommit does not match the release manifest'
    ) 'evidence from another source commit fails closed'

    $validRecordedAtUtc = $evidence.devices[0].recordedAtUtc
    $evidence.devices[0].recordedAtUtc = 'not-a-utc-timestamp'
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -NowUtc $script:NowUtc `
            -ManifestGeneratedAtUtc `
                (ConvertTo-StrictUtcText $script:ManifestGeneratedAtUtc)
    )
    Assert-True (
        ($errors -join "`n") -match 'device recordedAtUtc must be strict UTC'
    ) 'malformed device time fails closed'
    $evidence.devices[0].recordedAtUtc = $validRecordedAtUtc

    $validAppCheckObservedAtUtc =
        $evidence.cloudControls.appCheckObservedAtUtc
    $evidence.cloudControls.appCheckObservedAtUtc = (
        ConvertTo-StrictUtcText ($script:NowUtc.AddHours(-25))
    )
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -NowUtc $script:NowUtc `
            -ManifestGeneratedAtUtc `
                (ConvertTo-StrictUtcText $script:ManifestGeneratedAtUtc)
    )
    Assert-True (
        ($errors -join "`n") -match 'App Check evidence must be fresh'
    ) 'stale mutable provider evidence fails closed'
    $evidence.cloudControls.appCheckObservedAtUtc =
        $validAppCheckObservedAtUtc

    $validAppCheckRef = $evidence.cloudControls.appCheckEvidenceRef
    $evidence.cloudControls.appCheckEvidenceRef =
        'private:synthetic-app-check'
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath `
                $trustedEvidencePublicKeyPath
    )
    Assert-True (
        ($errors -join "`n") -match
            'appCheckEvidenceRef must be a verified app-check reference'
    ) 'free-form private references cannot satisfy external evidence'
    $evidence.cloudControls.appCheckEvidenceRef = $validAppCheckRef

    $evidence.cloudControls.appCheckEvidenceRef = (
        'private-evidence:v1:app-check:' +
        '00000000-0000-4000-8000-000000000000:' +
        'sha256:' + ('F' * 64)
    )
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath `
                $trustedEvidencePublicKeyPath
    )
    Assert-True (
        ($errors -join "`n") -match
            'appCheckEvidenceRef must be a verified app-check reference'
    ) 'a well-shaped reference without its content-addressed blob fails closed'
    $evidence.cloudControls.appCheckEvidenceRef = $validAppCheckRef

    $attackerRsa = [System.Security.Cryptography.RSA]::Create(3072)
    try {
        $evidence.cloudControls.appCheckEvidenceRef =
            New-PrivateEvidenceRef `
                -Kind 'app-check' `
                -Directory $privateEvidenceDirectory `
                -SigningRsa $attackerRsa
        $errors = @(
            Test-LexiQuestFieldReleaseEvidence `
                -Evidence $evidence `
                -ActualApkSha256 ('A' * 64) `
                -ActualCertificateSha256 ('B' * 64) `
                -ParticipantPackagePath $tempRoot `
                -PrivateEvidenceDirectory $privateEvidenceDirectory `
                -TrustedEvidencePublicKeyPath `
                    $trustedEvidencePublicKeyPath
        )
    Assert-True (
        ($errors -join "`n") -match
            'appCheckEvidenceRef must be a verified app-check reference'
    ) 'a correctly shaped receipt signed by an untrusted key fails closed'
    }
    finally {
        $attackerRsa.Dispose()
        $evidence.cloudControls.appCheckEvidenceRef = $validAppCheckRef
    }

    $evidence.cloudControls.appCheckEvidenceRef = New-PrivateEvidenceRef `
        -Kind 'app-check' `
        -Directory $privateEvidenceDirectory `
        -Payload $appCheckPayload `
        -OmitSourceExport
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $trustedEvidencePublicKeyPath
    )
    Assert-True (
        ($errors -join "`n") -match
            'appCheckEvidenceRef must be a verified app-check reference'
    ) 'provider receipts without a source-export digest fail closed'
    $evidence.cloudControls.appCheckEvidenceRef = $validAppCheckRef

    $validCostRef = $evidence.cloudControls.centralCost.evidenceRef
    $evidence.cloudControls.centralCost.evidenceRef = 'private:cost-claim'
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match
            'centralCost.evidenceRef must be a verified billing reference'
    ) 'self-asserted cost evidence fails closed'
    $evidence.cloudControls.centralCost.evidenceRef = $validCostRef

    $validBetaSessionsRef = $evidence.betaOperations.sessions.evidenceRef
    $evidence.betaOperations.sessions.evidenceRef = 'private:beta-sessions'
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match
            'beta sessions evidenceRef must be verified'
    ) 'self-asserted beta operations evidence fails closed'
    $evidence.betaOperations.sessions.evidenceRef = $validBetaSessionsRef

    $validApprovalRef = $evidence.ownerApproval.evidenceRef
    $evidence.ownerApproval.evidenceRef = 'private:owner-approval'
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match
            'ownerApproval.evidenceRef must be a verified owner-approval reference'
    ) 'self-asserted owner approval fails closed'
    $evidence.ownerApproval.evidenceRef = $validApprovalRef

    $evidence.devices[0].collector.roKernelQemu = '1'
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -ExpectedCollectorScriptSha256 ('E' * 64)
    )
    Assert-True (
        ($errors -join "`n") -match
            'collector attestation does not prove a production physical device'
    ) 'self-asserted physical evidence with qemu markers fails closed'
    $evidence.devices[0].collector.roKernelQemu = '0'

    $completeBetaOperations = $evidence.betaOperations
    $evidence.betaOperations = $null
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -ExpectedSourceCommit $script:SourceCommit `
            -NowUtc $script:NowUtc `
            -ManifestGeneratedAtUtc `
                (ConvertTo-StrictUtcText $script:ManifestGeneratedAtUtc) `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath `
                $trustedEvidencePublicKeyPath `
            -ExpectedCollectorScriptSha256 ('E' * 64)
    )
    Assert-True (
        ($errors -join "`n") -match 'betaOperations is required'
    ) 'missing beta operations and rollback evidence blocks field acceptance'
    $evidence.betaOperations = $completeBetaOperations

    $evidence.betaOperations.status = 'pending'
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'betaOperations.status must be pass'
    ) 'pending beta operations cannot satisfy field acceptance'
    $evidence.betaOperations.status = 'pass'

    $evidence.betaOperations.release.apkSha256 = 'D' * 64
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'betaOperations release does not match'
    ) 'beta operations must bind the exact release artifact'
    $evidence.betaOperations.release.apkSha256 = 'A' * 64

    $evidence.betaOperations.testerCount = 4
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $trustedEvidencePublicKeyPath
    )
    Assert-True (
        ($errors -join "`n") -match
            'beta sessions evidenceRef must be verified'
    ) 'beta cohort size is bound to signed operations evidence'
    $evidence.betaOperations.testerCount = 3

    $validBetaStartedAtUtc = $evidence.betaOperations.windowStartedAtUtc
    $evidence.betaOperations.windowStartedAtUtc = ConvertTo-StrictUtcText (
        $script:BetaStartedAtUtc.AddMinutes(1)
    )
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $trustedEvidencePublicKeyPath
    )
    Assert-True (
        ($errors -join "`n") -match
            'beta sessions evidenceRef must be verified'
    ) 'beta window is bound to signed operations evidence'
    $evidence.betaOperations.windowStartedAtUtc = $validBetaStartedAtUtc

    $validBetaSyncRef = $evidence.betaOperations.sync.evidenceRef
    $crossCohortSyncPayload = [pscustomobject][ordered]@{
        release = $evidence.betaOperations.release
        windowStartedAtUtc = ConvertTo-StrictUtcText (
            $script:BetaStartedAtUtc.AddMinutes(-10)
        )
        windowEndedAtUtc = $evidence.betaOperations.windowEndedAtUtc
        testerCount = $evidence.betaOperations.testerCount
        consentVersion = $evidence.betaOperations.consentVersion
        attemptCount = $evidence.betaOperations.sync.attemptCount
        failureCount = $evidence.betaOperations.sync.failureCount
    }
    $evidence.betaOperations.sync.evidenceRef = New-PrivateEvidenceRef `
        -Kind 'beta-operations' `
        -Directory $privateEvidenceDirectory `
        -Payload $crossCohortSyncPayload
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $trustedEvidencePublicKeyPath
    )
    Assert-True (
        ($errors -join "`n") -match 'beta sync evidenceRef must be verified'
    ) 'beta receipts from another cohort window cannot be mixed'
    $evidence.betaOperations.sync.evidenceRef = $validBetaSyncRef

    $evidence.betaOperations.sessions.crashCount = 1
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'beta sessions must be crash-free'
    ) 'a beta crash blocks field acceptance'
    $evidence.betaOperations.sessions.crashCount = 0

    $evidence.betaOperations.providerUsage.costKnownRequestCount = 4
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'provider cost must be known'
    ) 'unknown provider cost blocks field acceptance'
    $evidence.betaOperations.providerUsage.costKnownRequestCount = 5

    $validProviderUsageRef = $evidence.betaOperations.providerUsage.evidenceRef
    $providerUsagePayload = [pscustomobject][ordered]@{
        release = $evidence.betaOperations.release
        windowStartedAtUtc = $evidence.betaOperations.windowStartedAtUtc
        windowEndedAtUtc = $evidence.betaOperations.windowEndedAtUtc
        testerCount = $evidence.betaOperations.testerCount
        consentVersion = $evidence.betaOperations.consentVersion
        requestCount = $evidence.betaOperations.providerUsage.requestCount
        successCount = $evidence.betaOperations.providerUsage.successCount
        failureCount = $evidence.betaOperations.providerUsage.failureCount
        indeterminateCount =
            $evidence.betaOperations.providerUsage.indeterminateCount
        costKnownRequestCount =
            $evidence.betaOperations.providerUsage.costKnownRequestCount
        providerReportedCostMicrosUsd =
            $evidence.betaOperations.providerUsage.providerReportedCostMicrosUsd
    }
    $evidence.betaOperations.providerUsage.evidenceRef =
        New-PrivateEvidenceRef `
            -Kind 'beta-operations' `
            -Directory $privateEvidenceDirectory `
            -Payload $providerUsagePayload `
            -SourcePayload ([pscustomobject]@{ arbitrary = 'unrelated' })
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $trustedEvidencePublicKeyPath
    )
    Assert-True (
        ($errors -join "`n") -match
            'beta providerUsage evidenceRef must be verified'
    ) 'provider operations cannot be signed from an unrelated local source'
    $evidence.betaOperations.providerUsage.evidenceRef = $validProviderUsageRef

    $validJourneyRef = $evidence.devices[0].journeys.offlineVocabulary.evidenceRef
    $hostFakeJourneyPayload = [pscustomobject][ordered]@{
        evidenceId = $evidence.devices[0].evidenceId
        tier = $evidence.devices[0].tier
        pseudonymousDeviceId = $evidence.devices[0].pseudonymousDeviceId
        journey = 'offlineVocabulary'
        status = 'pass'
    }
    $evidence.devices[0].journeys.offlineVocabulary.evidenceRef =
        New-PrivateEvidenceRef `
            -Kind 'device-journey' `
            -Directory $privateEvidenceDirectory `
            -Payload $hostFakeJourneyPayload `
            -CaptureMethod 'host-fake' `
            -HostFake $true
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $trustedEvidencePublicKeyPath `
            -ExpectedCollectorScriptSha256 ('E' * 64)
    )
    Assert-True (
        ($errors -join "`n") -match
            'offlineVocabulary needs a verified device-journey'
    ) 'a host-fake source cannot satisfy a physical journey'
    $evidence.devices[0].journeys.offlineVocabulary.evidenceRef =
        $validJourneyRef

    $completeRollbackEvidence = $evidence.rollbackEvidence
    $evidence.rollbackEvidence = $null
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'rollbackEvidence is required'
    ) 'missing rollback evidence blocks field acceptance'
    $evidence.rollbackEvidence = $completeRollbackEvidence

    $evidence.rollbackEvidence.target.versionCode = 2
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'rollback target version must be lower'
    ) 'a same-version reinstall is not a rollback drill'
    $evidence.rollbackEvidence.target.versionCode = 1

    $expectedRollbackDrillId =
        [string]$evidence.rollbackEvidence.killSwitchDrill.drillId
    $evidence.rollbackEvidence.killSwitchDrill.drillId =
        '22222222-2222-4222-8222-222222222222'
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $trustedEvidencePublicKeyPath
    )
    Assert-True (
        ($errors -join "`n") -match 'shared rollback drill identity'
    ) 'rollback and kill-switch receipts require one shared drill identity'
    $evidence.rollbackEvidence.killSwitchDrill.drillId =
        $expectedRollbackDrillId

    $completeDevices = @($evidence.devices)
    $evidence.devices = @(
        $completeDevices | Where-Object { $_.tier -cne 'low' }
    )
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'low-tier device record is required'
    ) 'missing low-tier physical evidence blocks field acceptance'
    $evidence.devices = $completeDevices

    $evidence.devices[0].benchmarks.cpuXnnpack.medianLatencyMs = [double]::NaN
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'CPU/XNNPACK benchmark must pass'
    ) 'NaN benchmark latency cannot satisfy physical evidence'
    $evidence.devices[0].benchmarks.cpuXnnpack.medianLatencyMs = 11.5

    $evidence.devices[1].endurance.peakRssMb = ''
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'endurance.peakRssMb is required'
    ) 'empty endurance measurements cannot satisfy physical evidence'
    $evidence.devices[1].endurance.peakRssMb = 300

    $budgetedCost = $evidence.cloudControls.centralCost
    $budgetedAlertsRef = $evidence.cloudControls.budgetAlertsEvidenceRef
    $evidence.cloudControls.budgetAlertsConfigured = $false
    $evidence.cloudControls.budgetAlertsNotApplicable = $true
    $evidence.cloudControls.billingMode = 'noBillingAccount'
    $noBillingAlertsPayload = [pscustomobject][ordered]@{
        configured = $false
        notApplicable = $true
        billingMode = 'noBillingAccount'
        observedAtUtc = $cloudObservedText
    }
    $evidence.cloudControls.budgetAlertsEvidenceRef =
        New-PrivateEvidenceRef `
            -Kind 'billing' `
            -Directory $privateEvidenceDirectory `
            -Payload $noBillingAlertsPayload
    $noBillingPayload = [pscustomobject][ordered]@{
        schemaVersion = 1
        mode = 'noBillingAccount'
        scope = 'firebaseProjectTotal'
        projectId = 'vocab-learning-app-219ef'
        projectNumber = '145034183638'
        currencyCode = 'THB'
        approvedMonthlyMinimumSatang = 0
        approvedMonthlyMaximumSatang = 10000
        measurementBasis = 'billingDisabled'
        measurementMonthUtc = $script:NowUtc.ToString('yyyy-MM')
        measuredAtUtc = (
            ConvertTo-StrictUtcText $script:CloudObservedAtUtc
        )
        measuredMonthlyCostSatang = 0
        budget = $null
    }
    $evidence.cloudControls.centralCost = [pscustomobject][ordered]@{
        schemaVersion = $noBillingPayload.schemaVersion
        mode = $noBillingPayload.mode
        scope = $noBillingPayload.scope
        projectId = $noBillingPayload.projectId
        projectNumber = $noBillingPayload.projectNumber
        currencyCode = $noBillingPayload.currencyCode
        approvedMonthlyMinimumSatang =
            $noBillingPayload.approvedMonthlyMinimumSatang
        approvedMonthlyMaximumSatang =
            $noBillingPayload.approvedMonthlyMaximumSatang
        measurementBasis = $noBillingPayload.measurementBasis
        measurementMonthUtc = $noBillingPayload.measurementMonthUtc
        measuredAtUtc = $noBillingPayload.measuredAtUtc
        measuredMonthlyCostSatang =
            $noBillingPayload.measuredMonthlyCostSatang
        budget = $noBillingPayload.budget
        evidenceRef = New-PrivateEvidenceRef `
            -Kind 'billing' `
            -Directory $privateEvidenceDirectory `
            -Payload $noBillingPayload
    }
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot `
            -PrivateEvidenceDirectory $privateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $trustedEvidencePublicKeyPath
    )
    Assert-True ($errors.Count -eq 0) `
        'verified no-billing mode is accepted as the strictest cost boundary'
    $evidence.cloudControls.centralCost = $budgetedCost
    $evidence.cloudControls.budgetAlertsConfigured = $true
    $evidence.cloudControls.budgetAlertsNotApplicable = $false
    $evidence.cloudControls.billingMode = 'budgeted'
    $evidence.cloudControls.budgetAlertsEvidenceRef = $budgetedAlertsRef

    $evidence.cloudControls.centralCost.measuredMonthlyCostSatang = 10001
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'measured monthly central cost must be 0..10000'
    ) 'central cost above 100 THB blocks field acceptance'
    $evidence.cloudControls.centralCost.measuredMonthlyCostSatang = 7550

    $evidence.cloudControls.centralCost.budget.monthlyAmountSatang = 50000
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'budget ceiling must be exactly 10000'
    ) 'a 500 THB alert budget cannot satisfy the 100 THB policy'
    $evidence.cloudControls.centralCost.budget.monthlyAmountSatang = 10000

    $evidence.cloudControls.appCheckEnforced = $false
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'appCheckEnforced must be true'
    ) 'provider registration alone cannot satisfy App Check acceptance'
    $evidence.cloudControls.appCheckEnforced = $true

    $evidence.cloudControls.appCheckValidTrafficObserved = $false
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match
            'appCheckValidTrafficObserved must be true'
    ) 'App Check enforcement requires observed valid signed-release traffic'
    $evidence.cloudControls.appCheckValidTrafficObserved = $true

    $validSupportChannelRef =
        $evidence.participantPackage.supportChannelRef
    $evidence.participantPackage.supportChannelRef =
        'missing:private-support'
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match
            'supportChannelRef must be a verified support-channel reference'
    ) 'an explicit missing private support channel blocks release'
    $evidence.participantPackage.supportChannelRef =
        $validSupportChannelRef

    $validResearchProtocolRef =
        $evidence.participantPackage.researchProtocolRef
    $evidence.participantPackage.researchProtocolRef =
        'https://example.invalid/draft'
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match
            'researchProtocolRef must be a verified research-protocol reference'
    ) 'a public draft cannot satisfy private protocol approval evidence'
    $evidence.participantPackage.researchProtocolRef =
        $validResearchProtocolRef

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
    if ($null -ne $script:EvidenceSigningRsa) {
        $script:EvidenceSigningRsa.Dispose()
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

$gateText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/verify-field-release.ps1'
) -Raw -Encoding utf8
foreach ($needle in @(
    'verify-field-package.ps1',
    "Join-Path `$resolvedPackage",
    "'apkPath'",
    'Get-FileHash',
    'verify-product-completion.ps1',
    'Test-LexiQuestFieldReleaseEvidence',
    'sourceCommit',
    'PrivateEvidenceDirectory',
    'TrustedEvidencePublicKeyPath',
    'trusted-field-evidence-public-key.xml',
    'ExpectedCollectorScriptSha256',
    'manifestGeneratedAtUtc',
    'status --porcelain --untracked-files=all',
    'requires a clean worktree',
    'Test-LexiQuestPostPackageMetadataPath',
    'merge-base --is-ancestor'
)) {
    Assert-True $gateText.Contains($needle) "final gate contains $needle"
}

Assert-True (
    $gateText.Contains('Field evidence is missing: $resolvedEvidence.')
) 'missing-evidence failure reports the resolved evidence path'
Assert-True (
    $gateText.Contains('Source changed after packaging outside')
) 'post-package non-metadata source changes invalidate the signed checkpoint'

$trackedEvidencePublicKeyPath = Join-Path $repoRoot `
    'tool/cli/trusted-field-evidence-public-key.xml'
$trackedEvidencePublicKeyText = Get-Content `
    -LiteralPath $trackedEvidencePublicKeyPath `
    -Raw `
    -Encoding utf8
Assert-True (
    $trackedEvidencePublicKeyText -notmatch
        '<(?:D|P|Q|DP|DQ|InverseQ)>[^<]+</(?:D|P|Q|DP|DQ|InverseQ)>'
) 'tracked evidence key contains public material only'
$trackedEvidenceRsa = Get-LexiQuestTrustedEvidenceRsa `
    $trackedEvidencePublicKeyPath
Assert-True ($null -ne $trackedEvidenceRsa) `
    'tracked evidence public key is valid RSA-3072 or stronger'
if ($null -ne $trackedEvidenceRsa) {
    $trackedEvidenceRsa.Dispose()
}

$collectorText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/collect-android-field-evidence.ps1'
) -Raw -Encoding utf8
foreach ($needle in @(
    'ro.kernel.qemu',
    'ro.boot.qemu',
    'ro.build.type',
    'ro.debuggable',
    'ro.secure',
    'collectorScriptSha256',
    'physical-android-collector',
    'PrivateEvidenceDirectory',
    'SigningCertificateThumbprint',
    'signatureBase64',
    'rsa-sha256-pkcs1',
    'pseudonymousDeviceId',
    "status = 'pending'",
    'install -r',
    'Get-InstalledVersionCode',
    'priorVersionCode',
    'targetVersionCode',
    'Get-LexiQuestRequiredFieldJourneys'
)) {
    Assert-True $collectorText.Contains($needle) "collector contains $needle"
}
Assert-True (
    $collectorText.Contains('$priorVersionCode -lt $targetVersionCode')
) 'collector distinguishes a real version upgrade from a same-version reinstall'
Assert-True (
    $collectorText -match (
        '(?s)if\s*\(\$null\s+-eq\s+\$priorVersionCode\)\s*\{' +
        '.*?\$journeys\.cleanInstall\s*=\s*\[ordered\]@\{' +
        '.*?status\s*=\s*''pass''.*?\}'
    )
) 'collector labels clean install pass only after proving the package was absent'
Assert-True (
    $collectorText -notmatch "(?m)status\s*=\s*'pass'.*(camera|speech|gemini)"
) 'collector never fabricates camera, speech, or Gemini passes'
Assert-True (
    $collectorText.Contains("-Kind 'device-attestation'") -and
    $collectorText.Contains('collectorAttestationPayload') -and
    $collectorText -notmatch 'payload\s*=\s*\[ordered\]@\{\s*claim'
) 'collector signs typed device identity and attestation payloads'

$deviceResultSignerText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/sign-android-field-evidence-result.ps1'
) -Raw -Encoding utf8
foreach ($needle in @(
    "'Journey', 'CpuBenchmark', 'GpuBenchmark', 'Endurance'",
    'InstrumentedResultPath',
    'Get-LexiQuestRequiredFieldJourneys',
    'Test-LexiQuestPrivateEvidenceReference',
    "-ExpectedKind 'device-attestation'",
    "'Journey' { 'device-journey' }",
    "'CpuBenchmark' { 'device-benchmark' }",
    "'Endurance' { 'device-endurance' }",
    "origin = 'physical-android-instrumentation'",
    'pseudonymousDeviceId',
    'sourceExportSha256',
    'signatureBase64'
)) {
    Assert-True $deviceResultSignerText.Contains($needle) `
        "device result signer contains $needle"
}

$receiptSignerText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/new-field-evidence-receipt.ps1'
) -Raw -Encoding utf8
foreach ($needle in @(
    'SigningCertificateThumbprint',
    'TrustedEvidencePublicKeyPath',
    'Get-LexiQuestEvidencePublicKeyId',
    'ConvertTo-LexiQuestEvidenceSigningBytes',
    'rsa-sha256-pkcs1',
    'sourceCommit',
    'apkSha256',
    'captureMethod',
    'hostFake',
    'sourceEnvelope.payload'
)) {
    Assert-True $receiptSignerText.Contains($needle) `
        "receipt signer contains $needle"
}
Assert-True (
    $receiptSignerText -notmatch "'device-(journey|benchmark|endurance)'"
) 'generic receipt signer cannot mint physical-device evidence'
Assert-True (
    $receiptSignerText -notmatch '\[string\]\$PayloadPath'
) 'generic receipt signer derives the payload from the raw source envelope'

$signingInitializerText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/initialize-field-evidence-signing.ps1'
) -Raw -Encoding utf8
foreach ($needle in @(
    'ConfirmOwnerControlledKeyCreation',
    'KeyLength 3072',
    'KeyExportPolicy NonExportable',
    'Refusing silent',
    'trusted-field-evidence-public-key.xml'
)) {
    Assert-True $signingInitializerText.Contains($needle) `
        "evidence signing initializer contains $needle"
}

$packagerText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/package-field-release.ps1'
) -Raw -Encoding utf8
foreach ($needle in @(
    'android/key.properties',
    'flutter build apk --release',
    'apksigner',
    'signingCertificateSha256',
    'Get-FileHash',
    'git status --porcelain',
    'docs/field',
    '--untracked-files=all'
)) {
    Assert-True $packagerText.Contains($needle) "packager contains $needle"
}

$assemblerText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/new-field-release-evidence.ps1'
) -Raw -Encoding utf8
foreach ($needle in @(
    'schemaVersion = 2',
    'sourceCommit',
    'manifestGeneratedAtUtc',
    'assembledAtUtc',
    'CloudControlsRecordPath',
    'CentralCostEvidencePath',
    'ParticipantPackageRecordPath',
    'BetaOperationsRecordPath',
    'RollbackEvidenceRecordPath',
    'OwnerApprovalRecordPath',
    'DeviceEvidenceDirectory',
    "status = 'pending'"
)) {
    Assert-True $assemblerText.Contains($needle) "assembler contains $needle"
}
foreach ($requiredCloudDefault in @(
    'budgetAlertsConfigured = $false',
    'budgetAlertsNotApplicable = $false',
    "billingMode = 'pending'"
)) {
    Assert-True $assemblerText.Contains($requiredCloudDefault) `
        "pending evidence shell contains $requiredCloudDefault"
}
Assert-True (
    $assemblerText -notmatch
        '\[switch\]\$(BudgetAlertsConfigured|NoBillingAccount|OwnerApproved)'
) 'assembler cannot turn self-asserted switches into accepted evidence'

$budgetText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/configure-firebase-budget.cjs'
) -Raw -Encoding utf8
foreach ($needle in @(
    'monthlyAmountThb = "100"',
    '[0.5, 0.8, 1.0]',
    'CURRENT_SPEND',
    'disableDefaultIamRecipients: false',
    'budgetAlertsNotApplicable: true',
    'billingMode: "noBillingAccount"',
    'A budget sends alerts; it is not a hard spending cap.'
)) {
    Assert-True $budgetText.Contains($needle) "budget control contains $needle"
}

$killSwitchText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/set-firebase-cloud-policy.cjs'
) -Raw -Encoding utf8
foreach ($needle in @(
    'enable|disable|status',
    'app_control/field',
    'cloudSyncEnabled',
    'Cloud sync policy did not reconcile.'
)) {
    Assert-True $killSwitchText.Contains($needle) `
        "kill switch control contains $needle"
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
