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

function Set-TestEvidenceReferences {
    param([AllowNull()][object]$Value, [object]$Reference)

    if ($null -eq $Value -or $Value -is [string] -or
        $Value -is [ValueType]) {
        return
    }
    if ($Value -is [System.Collections.IEnumerable] -and
        $Value -isnot [pscustomobject]) {
        foreach ($item in $Value) {
            Set-TestEvidenceReferences -Value $item -Reference $Reference
        }
        return
    }
    foreach ($property in $Value.PSObject.Properties) {
        if ($property.Name -match
            '(?i)(?:evidenceRef|channelRef|protocolRef)$') {
            $property.Value = $Reference
        } else {
            Set-TestEvidenceReferences `
                -Value $property.Value `
                -Reference $Reference
        }
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

function New-PassEvidence {
    param([string]$Name)
    return [pscustomobject]@{
        status = 'pass'
        evidenceRef = "private:$Name"
    }
}

function New-Device {
    param(
        [string]$Tier,
        [string]$IdCharacter,
        [string]$FormFactor = 'phone'
    )
    $deviceFacts = switch ($Tier) {
        'low' { [pscustomobject]@{ ramMb = 4096; sdk = 31 } }
        'high' { [pscustomobject]@{ ramMb = 8192; sdk = 34 } }
        default { [pscustomobject]@{ ramMb = 6144; sdk = 33 } }
    }
    $smallestWidthDp = if ($FormFactor -eq 'tablet') { 800 } else { 411 }
    $hasHingeSensor = $FormFactor -eq 'foldable'
    $foldFeatureObserved = $FormFactor -eq 'foldable'
    return [pscustomobject]@{
        evidenceId = "$Tier-device"
        tier = $Tier
        formFactor = $FormFactor
        pseudonymousDeviceId = $IdCharacter * 64
        recordedAtUtc = '2026-07-30T00:00:00Z'
        device = [pscustomobject]@{
            physical = $true
            emulatorDetected = $false
            model = "$Tier phone"
            androidVersion = '15'
            sdk = $deviceFacts.sdk
            ramMb = $deviceFacts.ramMb
            chipset = 'test chipset'
            gpu = 'test gpu'
            storageFreeMb = 10240
            networkProfile = 'offline-mixed'
            smallestWidthDp = $smallestWidthDp
            hasHingeSensor = $hasHingeSensor
            foldFeatureObserved = $foldFeatureObserved
            unsupportedFormFactorFeature = $false
            featureSetSha256 = 'D' * 64
            windowStateSha256 = 'E' * 64
        }
        release = [pscustomobject]@{
            apkSha256 = 'A' * 64
            signingCertificateSha256 = 'B' * 64
            modelSha256 = 'C' * 64
            packageName = 'com.lexiquest.app'
            versionName = '1.0.0'
            versionCode = 1
            buildId = 'abc123'
        }
        installation = [pscustomobject]@{
            source = 'directAdb'
            localApkSha256 = 'A' * 64
            localApkSigningCertificateSha256 = 'B' * 64
            installedBaseApkSha256 = 'F' * 64
            installedPackageName = 'com.lexiquest.app'
            installedVersionName = '1.0.0'
            installedVersionCode = 1
            installedSigningCertificateSha256 = 'B' * 64
            installerPackageName = ''
            initiatingPackageName = 'com.android.shell'
        }
        journeys = (New-Journeys)
        acceptance = [pscustomobject]@{
            portrait = (New-PassEvidence 'portrait')
            landscape = (New-PassEvidence 'landscape')
            textScale100 = (New-PassEvidence 'text-scale-100')
            textScale200 = (New-PassEvidence 'text-scale-200')
            manualTalkBack = (New-PassEvidence 'manual-talkback')
            humanUat = (New-PassEvidence 'human-uat')
            foldPostures = if ($FormFactor -eq 'foldable') {
                [pscustomobject]@{
                    cover = (New-PassEvidence 'fold-cover')
                    book = (New-PassEvidence 'fold-book')
                    tabletop = (New-PassEvidence 'fold-tabletop')
                }
            } else {
                $null
            }
        }
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

function New-RequiredDevices {
    return @(
        (New-Device 'low' '1' 'phone'),
        (New-Device 'mid' '2' 'tablet'),
        (New-Device 'high' '3' 'foldable')
    )
}

$repoRoot = Split-Path -Parent (
    Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
)
. (Join-Path $repoRoot 'tool/cli/lib/field-release-evidence.ps1')
Set-Alias -Name Test-LexiQuestFieldReleaseEvidence `
    -Value Test-LexiQuestResolvedFieldReleaseEvidence

foreach ($requiredFunction in @(
    'New-LexiQuestEvidenceReference',
    'Read-LexiQuestEvidenceRecord',
    'Test-LexiQuestArtifactMetadata',
    'Test-LexiQuestAabEntryCoverage',
    'Test-LexiQuestJarSignerVerification',
    'Test-LexiQuestAndroidArtifactIdentity',
    'Get-LexiQuestMeasuredAabMetadata',
    'Get-LexiQuestDerivedDeviceTier',
    'Get-LexiQuestDerivedFormFactor',
    'Get-LexiQuestPinnedModelSha256'
)) {
    Assert-True ($null -ne (Get-Command $requiredFunction `
        -ErrorAction SilentlyContinue)) `
        "release gate exposes behavioral helper $requiredFunction"
}

$packagerCommand = Get-Command (
    Join-Path $repoRoot 'tool/cli/package-field-release.ps1'
)
$gateCommand = Get-Command (
    Join-Path $repoRoot 'tool/cli/verify-field-release.ps1'
)
$assemblerCommand = Get-Command (
    Join-Path $repoRoot 'tool/cli/new-field-release-evidence.ps1'
)
Assert-True (-not $packagerCommand.Parameters.ContainsKey('SigningTrustPath')) `
    'packager trust cannot be redirected to an arbitrary file'
Assert-True (-not $gateCommand.Parameters.ContainsKey('SigningTrustPath')) `
    'final gate trust cannot be redirected to an arbitrary file'
Assert-True ($gateCommand.Parameters.ContainsKey('EvidenceRootPath')) `
    'final gate requires an explicit private evidence root'
Assert-True (-not $packagerCommand.Parameters.ContainsKey('ModelSha256')) `
    'packager model pin is derived from committed source'
foreach ($removedSwitch in @(
    'AppCheckConfigured',
    'PlayAabAccepted',
    'EthicsApproved',
    'OwnerApproved'
)) {
    Assert-True (-not $assemblerCommand.Parameters.ContainsKey($removedSwitch)) `
        "assembler cannot self-assert $removedSwitch with a switch"
}
foreach ($recordParameter in @(
    'EvidenceRootPath',
    'ControlRecordPath',
    'OwnerApprovalRecordPath'
)) {
    Assert-True ($assemblerCommand.Parameters.ContainsKey($recordParameter)) `
        "assembler requires measured record parameter $recordParameter"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'lexiquest-field-test-' + [Guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    if (
        $null -ne (Get-Command New-LexiQuestEvidenceReference `
            -ErrorAction SilentlyContinue) -and
        $null -ne (Get-Command Read-LexiQuestEvidenceRecord `
            -ErrorAction SilentlyContinue) -and
        $null -ne (Get-Command Test-LexiQuestArtifactMetadata `
            -ErrorAction SilentlyContinue) -and
        $null -ne (Get-Command Test-LexiQuestAabEntryCoverage `
            -ErrorAction SilentlyContinue)
    ) {
        $recordRoot = Join-Path $tempRoot 'evidence'
        $records = Join-Path $recordRoot 'records'
        New-Item -ItemType Directory -Path $records | Out-Null
        $recordPath = Join-Path $records 'approval.json'
        Set-Content -LiteralPath $recordPath -Encoding utf8 -Value `
            '{"recordType":"ownerApproval","approved":true}'
        $recordRef = New-LexiQuestEvidenceReference `
            -Path $recordPath `
            -EvidenceRootPath $recordRoot
        $record = Read-LexiQuestEvidenceRecord `
            -Reference $recordRef `
            -EvidenceRootPath $recordRoot
        Assert-True ($record.approved -eq $true) `
            'a contained hash-matched evidence record resolves'

        $tamperedRef = [pscustomobject]@{
            path = $recordRef.path
            sha256 = '0' * 64
        }
        $tamperRejected = $false
        try {
            Read-LexiQuestEvidenceRecord `
                -Reference $tamperedRef `
                -EvidenceRootPath $recordRoot | Out-Null
        } catch {
            $tamperRejected = $_.Exception.Message -match 'SHA-256'
        }
        Assert-True $tamperRejected `
            'a tampered evidence-record hash is rejected behaviorally'

        $escapeRejected = $false
        try {
            Read-LexiQuestEvidenceRecord `
                -Reference ([pscustomobject]@{
                    path = '../outside.json'
                    sha256 = '0' * 64
                }) `
                -EvidenceRootPath $recordRoot | Out-Null
        } catch {
            $escapeRejected = $_.Exception.Message -match 'contained'
        }
        Assert-True $escapeRejected `
            'an evidence path escaping the evidence root is rejected'

        $outsideRoot = Join-Path $tempRoot 'outside-evidence'
        New-Item -ItemType Directory -Path $outsideRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $outsideRoot 'outside.json') `
            -Encoding utf8 -Value '{"outside":true}'
        $junctionPath = Join-Path $recordRoot 'junction-escape'
        New-Item -ItemType Junction -Path $junctionPath -Target $outsideRoot |
            Out-Null
        $reparseRejected = $false
        try {
            New-LexiQuestEvidenceReference `
                -Path (Join-Path $junctionPath 'outside.json') `
                -EvidenceRootPath $recordRoot | Out-Null
        } catch {
            $reparseRejected = $_.Exception.Message -match 'reparse|link'
        }
        Assert-True $reparseRejected `
            'a contained-looking evidence path cannot escape through a reparse point'

        $expectedArtifact = [pscustomobject]@{
            apkSha256 = 'A' * 64
            packageName = 'com.lexiquest.app'
            versionName = '1.0.0'
            versionCode = 27
            buildId = '1' * 40
            modelSha256 = 'C' * 64
            signingCertificateSha256 = 'B' * 64
        }
        $measuredArtifact = [pscustomobject]@{
            archiveSha256 = 'A' * 64
            packageName = 'com.lexiquest.app'
            versionName = '1.0.0'
            versionCode = 27
            embeddedBuildId = '1' * 40
            embeddedModelSha256 = 'C' * 64
            signingCertificateSha256 = 'B' * 64
        }
        $metadataErrors = @(Test-LexiQuestArtifactMetadata `
            -Measured $measuredArtifact `
            -Expected $expectedArtifact `
            -ExpectedCertificateSha256 ('B' * 64) `
            -ExpectedModelSha256 ('C' * 64))
        Assert-True ($metadataErrors.Count -eq 0) `
            'measured signed artifact metadata passes exact binding'
        $measuredArtifact.embeddedBuildId = '2' * 40
        $metadataErrors = @(Test-LexiQuestArtifactMetadata `
            -Measured $measuredArtifact `
            -Expected $expectedArtifact `
            -ExpectedCertificateSha256 ('B' * 64) `
            -ExpectedModelSha256 ('C' * 64))
        Assert-True (
            ($metadataErrors -join "`n") -match 'embedded build ID'
        ) 'a manifest cannot self-assert a build absent from the signed artifact'
        $measuredArtifact.embeddedBuildId = '1' * 40
        $expectedArtifact.modelSha256 = 'D' * 64
        $metadataErrors = @(Test-LexiQuestArtifactMetadata `
            -Measured $measuredArtifact `
            -Expected $expectedArtifact `
            -ExpectedCertificateSha256 ('B' * 64) `
            -ExpectedModelSha256 ('C' * 64))
        Assert-True (
            ($metadataErrors -join "`n") -match 'committed model pin'
        ) 'an arbitrary manifest model checksum is rejected'

        $aabSource = Join-Path $tempRoot 'unsigned-aab-source'
        New-Item -ItemType Directory -Path (
            Join-Path $aabSource 'META-INF'
        ) -Force | Out-Null
        New-Item -ItemType Directory -Path (
            Join-Path $aabSource 'base\assets'
        ) -Force | Out-Null
        Set-Content -LiteralPath (
            Join-Path $aabSource 'base\assets\signed.txt'
        ) -Encoding utf8 -Value 'signed fixture'
        Set-Content -LiteralPath (
            Join-Path $aabSource 'base\assets\unsigned.txt'
        ) -Encoding utf8 -Value 'unsigned fixture'
        Set-Content -LiteralPath (
            Join-Path $aabSource 'META-INF\unsigned-evidence.json'
        ) -Encoding utf8 -Value '{"unsigned":true}'
        Set-Content -LiteralPath (
            Join-Path $aabSource 'META-INF\MANIFEST.MF'
        ) -Encoding ascii -Value @(
            'Manifest-Version: 1.0',
            '',
            'Name: base/assets/signed.txt',
            'SHA-256-Digest: Zml4dHVyZQ==',
            ''
        )
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $aabFixture = Join-Path $tempRoot 'unsigned-entry.aab'
        [System.IO.Compression.ZipFile]::CreateFromDirectory(
            $aabSource,
            $aabFixture
        )
        $coverageErrors = @(
            Test-LexiQuestAabEntryCoverage -ArchivePath $aabFixture
        )
        Assert-True (
            $coverageErrors.Count -gt 0 -and
            ($coverageErrors -join "`n") -match
                'unsigned entry: META-INF/unsigned-evidence.json'
        ) 'AAB coverage rejects unsigned META-INF payloads'

        $duplicateArchive = [System.IO.Compression.ZipFile]::Open(
            $aabFixture,
            [System.IO.Compression.ZipArchiveMode]::Update
        )
        try {
            [void]$duplicateArchive.CreateEntry('base/assets/signed.txt')
        }
        finally {
            $duplicateArchive.Dispose()
        }
        $coverageErrors = @(
            Test-LexiQuestAabEntryCoverage -ArchivePath $aabFixture
        )
        Assert-True (
            ($coverageErrors -join "`n") -match
                'duplicate entry: base/assets/signed.txt'
        ) 'AAB coverage rejects duplicate ZIP entries'

        $jarSignerErrors = @(Test-LexiQuestJarSignerVerification `
            -ExitCode 0 `
            -Output @(
                'jar verified.',
                'This jar contains unsigned entries which have not been integrity-checked.'
            ))
        Assert-True (
            ($jarSignerErrors -join "`n") -match 'unsigned entries'
        ) 'jarsigner success text cannot mask unsigned entries'

        $identityErrors = @(Test-LexiQuestAndroidArtifactIdentity `
            -MeasuredApk ([pscustomobject]@{
                packageName = 'com.lexiquest.app'
                versionName = '1.0.0'
                versionCode = 27
            }) `
            -MeasuredAab ([pscustomobject]@{
                applicationId = 'com.lexiquest.other'
                packageName = 'com.lexiquest.other'
                versionName = '1.0.0'
                versionCode = 27
            }) `
            -Expected $expectedArtifact)
        Assert-True (
            ($identityErrors -join "`n") -match 'AAB application ID'
        ) 'measured AAB identity must match the APK and release manifest'
        $identityErrors = @(Test-LexiQuestAndroidArtifactIdentity `
            -MeasuredApk ([pscustomobject]@{
                packageName = 'com.lexiquest.app'
                versionName = '1.0.0'
                versionCode = 27
            }) `
            -MeasuredAab ([pscustomobject]@{
                applicationId = 'com.lexiquest.app'
                packageName = 'com.lexiquest.app'
                versionName = '9.9.9'
                versionCode = 99
            }) `
            -Expected $expectedArtifact)
        Assert-True (
            ($identityErrors -join "`n") -match 'AAB versionName' -and
            ($identityErrors -join "`n") -match 'AAB versionCode'
        ) 'measured AAB versions must match the APK and release manifest'

        Assert-True (
            (Get-LexiQuestDerivedDeviceTier -RamMb 4096 -Sdk 31) -eq 'low' -and
            (Get-LexiQuestDerivedDeviceTier -RamMb 6144 -Sdk 33) -eq 'mid' -and
            (Get-LexiQuestDerivedDeviceTier -RamMb 8192 -Sdk 34) -eq 'high'
        ) 'device tiers are derived from the fixed RAM and API policy'
        Assert-True (
            (Get-LexiQuestDerivedFormFactor `
                -SmallestWidthDp 411 `
                -HasHingeSensor $false `
                -FoldFeatureObserved $false `
                -UnsupportedFormFactorFeature $false) -eq 'phone' -and
            (Get-LexiQuestDerivedFormFactor `
                -SmallestWidthDp 800 `
                -HasHingeSensor $false `
                -FoldFeatureObserved $false `
                -UnsupportedFormFactorFeature $false) -eq 'tablet' -and
            (Get-LexiQuestDerivedFormFactor `
                -SmallestWidthDp 411 `
                -HasHingeSensor $true `
                -FoldFeatureObserved $true `
                -UnsupportedFormFactorFeature $false) -eq 'foldable'
        ) 'form factors are derived from measured window and fold features'

        Assert-True (
            (Get-LexiQuestPinnedModelSha256 -RepoRoot $repoRoot) -eq
                'D3949E8A3556C79739CB675E0BE7476503BCCE76938031C6A1048E13E0CB7D8B'
        ) 'model pin is derived from committed model_manifest.dart'
    }

    $participantDocsRoot = Join-Path $tempRoot 'docs'
    New-Item -ItemType Directory -Path $participantDocsRoot | Out-Null
    $participantDocumentPaths = [ordered]@{
        installGuide = 'docs/install-and-update.md'
        privacyNotice = 'docs/privacy-and-consent-v1.md'
        dataRightsGuide = 'docs/data-export-and-deletion.md'
        knownLimitations = 'docs/known-limitations.md'
        feedbackGuide = 'docs/feedback-and-support.md'
        researchProtocol = 'docs/research-protocol-v1.md'
    }
    foreach ($relativeDocument in $participantDocumentPaths.Values) {
        Set-Content -LiteralPath (Join-Path $tempRoot $relativeDocument) `
            -Value 'verified contract fixture' -Encoding utf8
    }
    $participantDocumentReferences = [ordered]@{}
    foreach ($field in $participantDocumentPaths.Keys) {
        $relativeDocument = $participantDocumentPaths[$field]
        $participantDocumentReferences[$field] = [pscustomobject]@{
            path = $relativeDocument
            sha256 = (Get-FileHash -LiteralPath (
                Join-Path $tempRoot $relativeDocument
            ) -Algorithm SHA256).Hash
        }
    }
    $evidence = [pscustomobject]@{
        schemaVersion = 3
        releaseProfile = 'fieldTrial'
        releaseId = 'release-1'
        artifact = [pscustomobject]@{
            apkSha256 = 'A' * 64
            aabSha256 = 'D' * 64
            signingCertificateSha256 = 'B' * 64
            modelSha256 = 'C' * 64
            packageName = 'com.lexiquest.app'
            versionName = '1.0.0'
            versionCode = 1
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
            appCheckEvidenceRef = 'private:app-check'
            budgetAlertsEvidenceRef = 'private:budget'
            assetLinksEvidenceRef = 'private:app-links'
            cloudKillSwitchEvidenceRef = 'private:kill-switch'
        }
        participantPackage = [pscustomobject]@{
            installGuide = $participantDocumentReferences.installGuide
            privacyNotice = $participantDocumentReferences.privacyNotice
            dataRightsGuide = $participantDocumentReferences.dataRightsGuide
            knownLimitations = $participantDocumentReferences.knownLimitations
            feedbackGuide = $participantDocumentReferences.feedbackGuide
            researchProtocol = $participantDocumentReferences.researchProtocol
            consentVersion = 1
            feedbackChannelRef = 'private:feedback-channel-record'
            supportChannelRef = 'private:support-channel-record'
            researchProtocolRef = 'private:research-protocol'
        }
        releaseControls = [pscustomobject]@{
            playAabAccepted = $false
            playAppSigningCertificateSha256 = ''
            playAcceptanceEvidenceRef = ''
            privacyPolicyPublished = $false
            privacyPolicyRef = ''
            accountDeletionVerified = $false
            accountDeletionEvidenceRef = ''
            dataSafetyApproved = $false
            dataSafetyEvidenceRef = ''
            rollbackDrillVerified = $false
            rollbackEvidenceRef = ''
        }
        researchControls = [pscustomobject]@{
            ethicsApproved = $true
            protocolApproved = $true
            trustedIssuerConfigured = $true
            researchRolloutApproved = $true
            ethicsEvidenceRef = 'private:ethics-approval'
            protocolEvidenceRef = 'private:protocol-approval'
            trustedIssuerEvidenceRef = 'private:issuer-approval'
            rolloutEvidenceRef = 'private:research-rollout-approval'
        }
        devices = @(New-RequiredDevices)
        ownerApproval = [pscustomobject]@{
            approved = $true
            apkSha256 = 'A' * 64
            aabSha256 = 'D' * 64
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
            -ExpectedCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True ($errors.Count -eq 0) `
        'complete, reconciled evidence passes the pure validator'

    $evidence.participantPackage.installGuide.path =
        'docs/privacy-and-consent-v1.md'
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ExpectedCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'installGuide must reference exactly'
    ) 'participant document fields cannot be redirected to another package file'
    $evidence.participantPackage.installGuide.path =
        $participantDocumentPaths.installGuide
    $evidence.participantPackage.installGuide.sha256 = '0' * 64
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ExpectedCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'installGuide SHA-256 mismatch'
    ) 'participant document fields are bound to exact content hashes'
    $evidence.participantPackage.installGuide.sha256 =
        (Get-FileHash -LiteralPath (
            Join-Path $tempRoot $participantDocumentPaths.installGuide
        ) -Algorithm SHA256).Hash

    $supportRecordPath = Join-Path $tempRoot 'support-record.json'
    Set-Content -LiteralPath $supportRecordPath -Encoding utf8 -Value `
        '{"recordType":"measuredEvidence","status":"pass"}'
    $supportReference = New-LexiQuestEvidenceReference `
        -Path $supportRecordPath `
        -EvidenceRootPath $tempRoot
    $controlsRecord = [pscustomobject]@{
        recordType = 'lexiquestReleaseControls'
        releaseProfile = $evidence.releaseProfile
        artifact = $evidence.artifact
        cloudControls = $evidence.cloudControls
        participantPackage = $evidence.participantPackage
        releaseControls = $evidence.releaseControls
        researchControls = $evidence.researchControls
    } | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    Set-TestEvidenceReferences `
        -Value $controlsRecord `
        -Reference $supportReference
    $controlsPath = Join-Path $tempRoot 'release-controls.json'
    $controlsRecord | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $controlsPath -Encoding utf8

    $approvalRecord = $evidence.ownerApproval |
        ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $approvalRecord | Add-Member -NotePropertyName recordType `
        -NotePropertyValue 'lexiquestOwnerApproval'
    Set-TestEvidenceReferences `
        -Value $approvalRecord `
        -Reference $supportReference
    $approvalPath = Join-Path $tempRoot 'owner-approval.json'
    $approvalRecord | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $approvalPath -Encoding utf8

    $deviceReferences = @()
    $deviceIndex = 0
    foreach ($device in $evidence.devices) {
        $deviceRecord = $device | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $deviceRecord | Add-Member -NotePropertyName recordType `
            -NotePropertyValue 'lexiquestPhysicalDeviceEvidence'
        Set-TestEvidenceReferences `
            -Value $deviceRecord `
            -Reference $supportReference
        $devicePath = Join-Path $tempRoot "device-$deviceIndex.json"
        $deviceRecord | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath $devicePath -Encoding utf8
        $deviceReferences += New-LexiQuestEvidenceReference `
            -Path $devicePath `
            -EvidenceRootPath $tempRoot
        $deviceIndex++
    }
    $referencedEvidence = [pscustomobject]@{
        schemaVersion = 3
        releaseProfile = $evidence.releaseProfile
        releaseId = $evidence.releaseId
        artifact = $evidence.artifact
        records = [pscustomobject]@{
            controls = New-LexiQuestEvidenceReference `
                -Path $controlsPath `
                -EvidenceRootPath $tempRoot
            ownerApproval = New-LexiQuestEvidenceReference `
                -Path $approvalPath `
                -EvidenceRootPath $tempRoot
        }
        devices = $deviceReferences
    }
    $referencedErrors = @(Test-LexiQuestReferencedFieldReleaseEvidence `
        -Evidence $referencedEvidence `
        -ActualApkSha256 ('A' * 64) `
        -ActualCertificateSha256 ('B' * 64) `
        -ExpectedCertificateSha256 ('B' * 64) `
        -ParticipantPackagePath $tempRoot `
        -EvidenceRootPath $tempRoot)
    Assert-True ($referencedErrors.Count -eq 0) `
        'final evidence resolves only hash-bound contained records'
    $referencedEvidence.records.controls.sha256 = '0' * 64
    $referencedErrors = @(Test-LexiQuestReferencedFieldReleaseEvidence `
        -Evidence $referencedEvidence `
        -ActualApkSha256 ('A' * 64) `
        -ActualCertificateSha256 ('B' * 64) `
        -ExpectedCertificateSha256 ('B' * 64) `
        -ParticipantPackagePath $tempRoot `
        -EvidenceRootPath $tempRoot)
    Assert-True (
        ($referencedErrors -join "`n") -match 'SHA-256 mismatch'
    ) 'final gate rejects a tampered controls-record reference'
    $referencedEvidence.records.controls = New-LexiQuestEvidenceReference `
        -Path $controlsPath `
        -EvidenceRootPath $tempRoot

    $validate = {
        @(
            Test-LexiQuestFieldReleaseEvidence `
                -Evidence $evidence `
                -ActualApkSha256 ('A' * 64) `
                -ActualCertificateSha256 ('B' * 64) `
                -ExpectedCertificateSha256 ('B' * 64) `
                -ParticipantPackagePath $tempRoot
        )
    }

    $evidence.ownerApproval.aabSha256 = 'E' * 64
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match
            'owner approval must reference the release AAB SHA-256'
    ) 'owner approval is bound to the exact release AAB'
    $evidence.ownerApproval.aabSha256 = 'D' * 64

    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ExpectedCertificateSha256 ('F' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'owner-approved signing certificate'
    ) 'a certificate outside the owner trust record blocks release'

    $evidence.devices = @(New-RequiredDevices)
    $evidence.devices += (New-Device 'mid' '4')
    $errors = @(& $validate)
    Assert-True ($errors.Count -eq 0) `
        'an additional valid physical device is allowed'

    foreach ($missingTier in @('low', 'mid', 'high')) {
        $evidence.devices = @(
            New-RequiredDevices | Where-Object { $_.tier -ne $missingTier }
        )
        $errors = @(& $validate)
        Assert-True (
            ($errors -join "`n") -match
                "At least one $missingTier-tier physical Android device"
        ) "a missing $missingTier-tier physical device blocks release"
    }

    foreach ($invalidTier in @('tablet', '   ')) {
        $evidence.devices = @(New-RequiredDevices)
        $evidence.devices += (New-Device $invalidTier '4')
        $errors = @(& $validate)
        Assert-True (
            ($errors -join "`n") -match
                'device tier must be low, mid, or high'
        ) 'an unknown or blank device tier blocks release'
    }

    foreach ($missingFormFactor in @('phone', 'tablet', 'foldable')) {
        $evidence.devices = @(
            New-RequiredDevices |
                Where-Object { $_.formFactor -ne $missingFormFactor }
        )
        $errors = @(& $validate)
        Assert-True (
            ($errors -join "`n") -match
                "At least one physical $missingFormFactor device"
        ) "a missing physical $missingFormFactor device blocks release"
    }

    $evidence.devices = @(New-RequiredDevices)
    $evidence.devices[0].formFactor = 'television'
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match
            'formFactor must be phone, foldable, or tablet'
    ) 'an unsupported form factor blocks release'

    $evidence.devices = @(New-RequiredDevices)
    $evidence.devices[1].acceptance.landscape.status = 'pending'
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match 'landscape acceptance must pass'
    ) 'missing tablet landscape evidence blocks release'

    $evidence.devices = @(New-RequiredDevices)
    $evidence.devices[0].acceptance.textScale200.status = 'pending'
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match 'textScale200 acceptance must pass'
    ) 'missing 200-percent text evidence blocks release'

    $evidence.devices = @(New-RequiredDevices)
    $evidence.devices[2].acceptance.manualTalkBack.status = 'pending'
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match 'manualTalkBack acceptance must pass'
    ) 'manual TalkBack cannot be replaced by an automated focus smoke'

    $evidence.devices = @(New-RequiredDevices)
    $evidence.devices[1].acceptance.humanUat.status = 'pending'
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match 'humanUat acceptance must pass'
    ) 'human UAT is mandatory for the tested release artifact'

    $evidence.devices = @(New-RequiredDevices)
    $evidence.devices[2].acceptance.foldPostures.book.status = 'pending'
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match 'fold posture book must pass'
    ) 'a foldable record requires cover, book, and tabletop evidence'

    $evidence.devices = @(New-RequiredDevices)

    $evidence.researchControls.ethicsApproved = $false
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match 'researchControls.ethicsApproved must be true'
    ) 'a field trial cannot collect research data without ethics authority'
    $evidence.researchControls.ethicsApproved = $true

    $evidence.releaseProfile = 'publicProduction'
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match 'releaseControls.playAabAccepted must be true'
    ) 'a public release requires Play acceptance'
    $evidence.releaseControls = [pscustomobject]@{
        playAabAccepted = $true
        playAabSha256 = 'D' * 64
        playPackageName = 'com.lexiquest.app'
        playVersionName = '1.0.0'
        playVersionCode = 1
        playAppSigningCertificateSha256 = 'E' * 64
        playAcceptanceEvidenceRef = 'private:play-acceptance'
        privacyPolicyPublished = $true
        privacyPolicyRef = 'https://example.com/privacy'
        privacyPolicyEvidenceRef = 'private:privacy-policy'
        accountDeletionVerified = $true
        accountDeletionEvidenceRef = 'private:account-deletion'
        dataSafetyApproved = $true
        dataSafetyEvidenceRef = 'private:data-safety'
        rollbackDrillVerified = $true
        rollbackEvidenceRef = 'private:rollback-drill'
    }
    foreach ($device in $evidence.devices) {
        $device.installation.source = 'play'
        $device.installation.installerPackageName = 'com.android.vending'
        $device.installation.initiatingPackageName = 'com.android.vending'
        $device.installation.installedSigningCertificateSha256 = 'E' * 64
    }
    $errors = @(& $validate)
    Assert-True ($errors.Count -eq 0) `
        'complete public-production evidence passes without research authority'
    $evidence.devices[0].installation.installerPackageName = 'com.android.shell'
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match 'Play installer'
    ) 'public production requires a measured Play-installed package'
    $evidence.devices[0].installation.installerPackageName =
        'com.android.vending'
    $evidence.releaseControls.playAabSha256 = 'F' * 64
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match 'exact release AAB'
    ) 'Play acceptance is bound to the exact AAB hash'
    $evidence.releaseControls.playAabSha256 = 'D' * 64
    $evidence.releaseProfile = 'fieldTrial'
    $evidence.devices = @(New-RequiredDevices)
    $evidence.devices[0].device.physical = $false
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match
            'low evidence must be from a physical device'
    ) 'emulator or nonphysical evidence blocks release'

    $evidence.devices = @(New-RequiredDevices)
    $evidence.devices[0].device.emulatorDetected = $true
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match 'emulator indicators'
    ) 'measured emulator indicators block physical-device evidence'

    $evidence.devices = @(New-RequiredDevices)
    $evidence.devices[0].device.ramMb = 6144
    $evidence.devices[0].device.sdk = 33
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match 'tier does not match measured RAM/API policy'
    ) 'caller-supplied tier labels cannot override measured RAM and API facts'

    $evidence.devices = @(New-RequiredDevices)
    $evidence.devices[2].device.hasHingeSensor = $false
    $evidence.devices[2].device.foldFeatureObserved = $false
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match
            'formFactor does not match measured window/fold facts'
    ) 'a wide or caller-labelled screen cannot fabricate Fold evidence'

    $evidence.devices = @(New-RequiredDevices)
    $duplicate = New-Device 'mid' '4'
    $duplicate.pseudonymousDeviceId = ('11:' * 31) + '11'
    $evidence.devices += $duplicate
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match
            'Physical device records must have distinct pseudonymous IDs'
    ) 'normalized duplicate device identities block release'

    $evidence.devices = @(New-RequiredDevices)
    $evidence.devices[0].release.apkSha256 = 'D' * 64
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match
            'low device was not tested with the release APK'
    ) 'a per-device artifact mismatch blocks release'

    $evidence.devices = @(New-RequiredDevices)
    $evidence.devices[0].installation.localApkSha256 = 'D' * 64
    $errors = @(& $validate)
    Assert-True (
        ($errors -join "`n") -match 'measured local APK'
    ) 'field evidence is bound to the APK measured before installation'

    $evidence.devices = @(New-RequiredDevices)

    $evidence.cloudControls.budgetAlertsConfigured = $false
    $evidence.cloudControls.budgetAlertsNotApplicable = $true
    $evidence.cloudControls.billingMode = 'noBillingAccount'
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ExpectedCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True ($errors.Count -eq 0) `
        'verified no-billing mode is accepted as the strictest cost boundary'
    $evidence.cloudControls.budgetAlertsConfigured = $true
    $evidence.cloudControls.budgetAlertsNotApplicable = $false
    $evidence.cloudControls.billingMode = 'budgeted'

    $evidence.cloudControls.appCheckEnforced = $false
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ExpectedCertificateSha256 ('B' * 64) `
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
            -ExpectedCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match
            'appCheckValidTrafficObserved must be true'
    ) 'App Check enforcement requires observed valid signed-release traffic'
    $evidence.cloudControls.appCheckValidTrafficObserved = $true

    $evidence.participantPackage.supportChannelRef =
        'missing:private-support'
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ExpectedCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match
            'supportChannelRef must reference a real private channel'
    ) 'an explicit missing private support channel blocks release'
    $evidence.participantPackage.supportChannelRef =
        'private:support-channel-record'

    $evidence.participantPackage.researchProtocolRef =
        'https://example.invalid/draft'
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ExpectedCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match
            'researchProtocolRef must reference a real private channel'
    ) 'a public draft cannot satisfy private protocol approval evidence'
    $evidence.participantPackage.researchProtocolRef =
        'private:research-protocol'

    $evidence.devices[0].journeys.offlineRestartSync.status = 'pending'
    $errors = @(
        Test-LexiQuestFieldReleaseEvidence `
            -Evidence $evidence `
            -ActualApkSha256 ('A' * 64) `
            -ActualCertificateSha256 ('B' * 64) `
            -ExpectedCertificateSha256 ('B' * 64) `
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
            -ExpectedCertificateSha256 ('B' * 64) `
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
            -ExpectedCertificateSha256 ('B' * 64) `
            -ParticipantPackagePath $tempRoot
    )
    Assert-True (
        ($errors -join "`n") -match 'ownerApproval.approved must be true'
    ) 'owner approval cannot be omitted'

    $sourceErrors = @(Test-LexiQuestReleaseSource `
        -ManifestSourceCommit ('1' * 40) `
        -ManifestSourceTree ('2' * 40) `
        -CurrentHead ('1' * 40) `
        -CurrentTree ('2' * 40) `
        -RelevantChanges @())
    Assert-True ($sourceErrors.Count -eq 0) `
        'exact clean manifest source passes source binding'
    $sourceErrors = @(Test-LexiQuestReleaseSource `
        -ManifestSourceCommit ('1' * 40) `
        -ManifestSourceTree ('2' * 40) `
        -CurrentHead ('3' * 40) `
        -CurrentTree ('2' * 40) `
        -RelevantChanges @())
    Assert-True (
        ($sourceErrors -join "`n") -match 'source commit does not match'
    ) 'a different checkout commit blocks verification'
    $sourceErrors = @(Test-LexiQuestReleaseSource `
        -ManifestSourceCommit ('1' * 40) `
        -ManifestSourceTree ('2' * 40) `
        -CurrentHead ('1' * 40) `
        -CurrentTree ('2' * 40) `
        -RelevantChanges @(' M lib/main.dart'))
    Assert-True (
        ($sourceErrors -join "`n") -match 'release-relevant source changes'
    ) 'release-relevant working-tree drift blocks verification'

    $packageRoot = Join-Path $tempRoot 'package'
    $packageDocs = Join-Path $packageRoot 'docs'
    New-Item -ItemType Directory -Path $packageDocs | Out-Null
    foreach ($file in @(
        'lexiquest-1.0.0+1.apk',
        'lexiquest-1.0.0+1.aab',
        'release-manifest.json'
    )) {
        Set-Content -LiteralPath (Join-Path $packageRoot $file) `
            -Value 'fixture' -Encoding utf8
    }
    foreach ($file in @(
        'install-and-update.md',
        'privacy-and-consent-v1.md',
        'data-export-and-deletion.md',
        'known-limitations.md',
        'feedback-and-support.md',
        'research-protocol-v1.md'
    )) {
        Set-Content -LiteralPath (Join-Path $packageDocs $file) `
            -Value 'verified participant fixture' -Encoding utf8
    }
    $packageManifest = [pscustomobject]@{
        schemaVersion = 3
        releaseProfile = 'fieldTrial'
        artifact = [pscustomobject]@{
            apkPath = 'lexiquest-1.0.0+1.apk'
            aabPath = 'lexiquest-1.0.0+1.aab'
        }
        participantDocuments = @(
            Get-LexiQuestParticipantDocumentNames `
                -ReleaseProfile 'fieldTrial' |
                ForEach-Object {
                    $path = 'docs/' + $_
                    [pscustomobject]@{
                        path = $path
                        sha256 = (Get-FileHash -LiteralPath (
                            Join-Path $packageRoot $path
                        ) -Algorithm SHA256).Hash
                    }
                }
        )
    }
    $packageErrors = @(Test-LexiQuestReleasePackage `
        -PackagePath $packageRoot `
        -Manifest $packageManifest)
    Assert-True ($packageErrors.Count -eq 0) `
        'a clean allowlisted field-trial package passes'
    Set-Content -LiteralPath (
        Join-Path $packageDocs 'known-limitations.md'
    ) -Value 'tampered participant document' -Encoding utf8
    $packageErrors = @(Test-LexiQuestReleasePackage `
        -PackagePath $packageRoot `
        -Manifest $packageManifest)
    Assert-True (
        ($packageErrors -join "`n") -match
            'participant document SHA-256 mismatch'
    ) 'participant document content is bound to its manifest hash'
    Set-Content -LiteralPath (
        Join-Path $packageDocs 'known-limitations.md'
    ) -Value 'verified participant fixture' -Encoding utf8
    Remove-Item -LiteralPath (
        Join-Path $packageDocs 'research-protocol-v1.md'
    )
    $packageManifest.releaseProfile = 'publicProduction'
    $packageManifest.participantDocuments = @(
        Get-LexiQuestParticipantDocumentNames `
            -ReleaseProfile 'publicProduction' |
            ForEach-Object {
                $path = 'docs/' + $_
                [pscustomobject]@{
                    path = $path
                    sha256 = (Get-FileHash -LiteralPath (
                        Join-Path $packageRoot $path
                    ) -Algorithm SHA256).Hash
                }
            }
    )
    $packageErrors = @(Test-LexiQuestReleasePackage `
        -PackagePath $packageRoot `
        -Manifest $packageManifest)
    Assert-True ($packageErrors.Count -eq 0) `
        'a public package excludes the research protocol'
    $packageManifest.releaseProfile = 'fieldTrial'
    Set-Content -LiteralPath (
        Join-Path $packageDocs 'research-protocol-v1.md'
    ) -Value 'verified participant fixture' -Encoding utf8
    $packageManifest.participantDocuments = @(
        Get-LexiQuestParticipantDocumentNames `
            -ReleaseProfile 'fieldTrial' |
            ForEach-Object {
                $path = 'docs/' + $_
                [pscustomobject]@{
                    path = $path
                    sha256 = (Get-FileHash -LiteralPath (
                        Join-Path $packageRoot $path
                    ) -Algorithm SHA256).Hash
                }
            }
    )
    Set-Content -LiteralPath (Join-Path $packageDocs 'internal-checkpoint.md') `
        -Value 'must not ship' -Encoding utf8
    $packageErrors = @(Test-LexiQuestReleasePackage `
        -PackagePath $packageRoot `
        -Manifest $packageManifest)
    Assert-True (
        ($packageErrors -join "`n") -match 'unexpected packaged file'
    ) 'internal or stale files cannot enter the participant package'
    Remove-Item -LiteralPath (Join-Path $packageDocs 'internal-checkpoint.md')
    $packageManifest.artifact.apkPath = 'C:\\private\\lexiquest.apk'
    $packageErrors = @(Test-LexiQuestReleasePackage `
        -PackagePath $packageRoot `
        -Manifest $packageManifest)
    Assert-True (
        ($packageErrors -join "`n") -match 'artifact paths must be package-relative'
    ) 'absolute workstation paths cannot enter the release manifest'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

$gateText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/verify-field-release.ps1'
) -Raw -Encoding utf8
Assert-True (
    $gateText -match (
        '(?s)throw\s*\(\s*\(\s*''Field evidence is missing: \{0\}\.' +
        '.*?\)\s*-f\s*\$resolvedEvidence\s*\)'
    )
) 'missing-evidence diagnostics format the resolved path instead of literal {0}'
foreach ($needle in @(
    'apksigner',
    'jarsigner',
    'keytool',
    'V\d+',
    'Get-FileHash',
    'aabSha256',
    'verify-product-completion.ps1',
    'verify-apk-model-runtime.ps1',
    'Test-LexiQuestReferencedFieldReleaseEvidence',
    'Test-LexiQuestReleaseSource',
    'Test-LexiQuestReleasePackage',
    'sourceTree',
    'release-signing-trust.json',
    'Test-LexiQuestJarSignerVerification',
    'Get-LexiQuestMeasuredAabMetadata',
    'Test-LexiQuestAndroidArtifactIdentity',
    '-ArchivePath $aabPath'
)) {
    Assert-True $gateText.Contains($needle) "final gate contains $needle"
}

$collectorText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/collect-android-field-evidence.ps1'
) -Raw -Encoding utf8
$collectorCommand = Get-Command (
    Join-Path $repoRoot 'tool/cli/collect-android-field-evidence.ps1'
)
Assert-True (-not $collectorCommand.Parameters.ContainsKey('SigningTrustPath')) `
    'collector trust cannot be redirected to an arbitrary file'
foreach ($needle in @(
    'ro.kernel.qemu',
    'ro.boot.qemu',
    'Get-LexiQuestDerivedDeviceTier',
    'Get-LexiQuestDerivedFormFactor',
    'featureSetSha256',
    'windowStateSha256',
    'emulatorDetected',
    'pseudonymousDeviceId',
    "status = 'pending'",
    'install --no-streaming -r',
    'Get-InstalledVersionCode',
    'priorVersionCode',
    'targetVersionCode',
    'Get-LexiQuestRequiredFieldJourneys',
    "ValidateSet('phone', 'foldable', 'tablet')",
    'manualTalkBack',
    'humanUat',
    'foldPostures',
    'release-signing-trust.json',
    'Get-LexiQuestMeasuredApkMetadata',
    'installedBaseApkSha256',
    'installedSigningCertificateSha256',
    'installerPackageName',
    'com.android.vending',
    'lexiquestPhysicalDeviceEvidence',
    '.device.json'
)) {
    Assert-True $collectorText.Contains($needle) "collector contains $needle"
}
Assert-True (
    $collectorText.IndexOf('Get-LexiQuestMeasuredApkMetadata') -ge 0 -and
    $collectorText.IndexOf('Get-LexiQuestMeasuredApkMetadata') -lt
        $collectorText.IndexOf('install --no-streaming -r')
) 'collector verifies APK hash, metadata, and signer before installation'
Assert-True (
    $collectorText.Contains('$priorVersionCode -lt $targetVersionCode')
) 'collector distinguishes a real version upgrade from a same-version reinstall'
Assert-True (
    $collectorText.Contains('$installedVersionCode -ne $targetVersionCode')
) 'collector reconciles installation success from the installed package version'
foreach ($needle in @(
    'get-state',
    'transportReady',
    'priorLastUpdateTime',
    'installedLastUpdateTime'
)) {
    Assert-True $collectorText.Contains($needle) `
        "collector reconciles transport loss with $needle"
}
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
    ([regex]::Matches(
        $collectorText,
        'CultureInfo\]::InvariantCulture'
    )).Count -ge 2
) 'collector writes machine-readable evidence timestamps with invariant UTC years'

$packagerText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/package-field-release.ps1'
) -Raw -Encoding utf8
foreach ($needle in @(
    'android/key.properties',
    'flutter build apk --release',
    'flutter build appbundle --release',
    'app-release.aab',
    'apksigner',
    'jarsigner',
    'Test-LexiQuestJarSignerVerification',
    'Get-LexiQuestMeasuredAabMetadata',
    'Test-LexiQuestAndroidArtifactIdentity',
    'keytool',
    'aabPath',
    'aabSha256',
    'signingCertificateSha256',
    'Get-FileHash',
    'git status --porcelain',
    'docs/field',
    'tool/cli/package-field-release.ps1',
    'tool/cli/lib/field-release-evidence.ps1',
    'tool/cli/new-field-release-evidence.ps1',
    'tool/cli/collect-android-field-evidence.ps1',
    'releaseProfile',
    'sourceTree',
    '$participantDocuments'
)) {
    Assert-True $packagerText.Contains($needle) "packager contains $needle"
}
Assert-True (-not $packagerText.Contains("Copy-Item -Path 'docs/field/*.md'")) `
    'packager never copies every internal field checkpoint'
Assert-True ($packagerText.Contains('must be empty')) `
    'packager refuses to merge a release into stale staging files'

$assemblerText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/new-field-release-evidence.ps1'
) -Raw -Encoding utf8
foreach ($needle in @(
    'EvidenceRootPath',
    'ControlRecordPath',
    'OwnerApprovalRecordPath',
    'New-LexiQuestEvidenceReference',
    'Read-LexiQuestEvidenceRecord',
    'DeviceEvidenceDirectory',
    '*.device.json',
    'schemaVersion = 3'
)) {
    Assert-True $assemblerText.Contains($needle) "assembler contains $needle"
}

$templateText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'docs/field/release-evidence-template.json'
) -Raw -Encoding utf8
Assert-True (
    ([regex]::Matches($templateText, '"aabSha256"')).Count -ge 2
) 'release evidence template binds artifact and owner approval to the AAB'
foreach ($needle in @(
    '"schemaVersion": 3',
    '"releaseProfile"',
    '"records"',
    '"path"',
    '"sha256"',
    '"releaseControls"',
    '"researchControls"',
    '"formFactor"',
    '"manualTalkBack"',
    '"humanUat"',
    '"foldPostures"'
)) {
    Assert-True $templateText.Contains($needle) `
        "release evidence template contains $needle"
}
Assert-True (
    $templateText -match
        '(?s)"installGuide"\s*:\s*\{\s*"path"\s*:\s*"docs/install-and-update\.md".*?"sha256"'
) 'release evidence template hashes fixed participant-document paths'

$budgetText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/configure-firebase-budget.cjs'
) -Raw -Encoding utf8
foreach ($needle in @(
    'monthlyAmountThb = "500"',
    '[0.5, 0.8, 1.0]',
    'CURRENT_SPEND',
    'disableDefaultIamRecipients: false',
    'budgetAlertsNotApplicable: true',
    'billingMode: "noBillingAccount"',
    'A budget sends alerts; it is not a hard spending cap.'
)) {
    Assert-True $budgetText.Contains($needle) "budget control contains $needle"
}

$firebaseShaText = Get-Content -LiteralPath (
    Join-Path $repoRoot 'tool/cli/configure-firebase-release-sha.cjs'
) -Raw -Encoding utf8
Assert-True (
    -not $firebaseShaText.Contains(
        'build/field-release/release-manifest.json'
    )
) 'Firebase SHA registration cannot silently use a stale root manifest'
Assert-True ($firebaseShaText.Contains('process.argv[2]')) `
    'Firebase SHA registration requires an explicit versioned manifest'

$assetLinksCommand = Get-Command (
    Join-Path $repoRoot 'tool/cli/verify-hosted-asset-links.ps1'
)
$manifestParameter = $assetLinksCommand.Parameters['ReleaseManifestPath']
$manifestMandatory = @(
    $manifestParameter.Attributes |
        Where-Object {
            $_ -is [System.Management.Automation.ParameterAttribute] -and
            $_.Mandatory
        }
).Count -gt 0
Assert-True $manifestMandatory `
    'hosted Asset Links verification requires an explicit versioned manifest'

$fieldReadme = Get-Content -LiteralPath (
    Join-Path $repoRoot 'docs/field/README.md'
) -Raw -Encoding utf8
foreach ($needle in @(
    '-ReleaseManifestPath $releaseManifest',
    '-ParticipantPackagePath $releasePackage',
    '-EvidenceRootPath $evidenceRoot'
)) {
    Assert-True $fieldReadme.Contains($needle) `
        "field runbook uses mandatory versioned path: $needle"
}

$releaseBlockersRunbook = Get-Content -LiteralPath (
    Join-Path $repoRoot 'docs/runbooks/release-blockers-resolution.md'
) -Raw -Encoding utf8
foreach ($needle in @(
    '$releaseManifest',
    '$releasePackage',
    '$evidenceRoot',
    'configure-firebase-release-sha.cjs $releaseManifest',
    '-ParticipantPackagePath $releasePackage',
    '-EvidenceRootPath $evidenceRoot'
)) {
    Assert-True $releaseBlockersRunbook.Contains($needle) `
        "release-blockers runbook uses mandatory current caller: $needle"
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
