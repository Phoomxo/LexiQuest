#Requires -Version 5.1
Set-StrictMode -Version 3.0

function Get-LexiQuestRequiredFieldJourneys {
    return @(
        'consentGuestStartup',
        'offlineVocabulary',
        'learningCore',
        'offlineRestartSync',
        'accountLifecycle',
        'modelLifecycle',
        'cameraScanner',
        'speechTtsPronunciation',
        'geminiByok',
        'cleanInstall',
        'upgradeInstall',
        'rebootForegroundBackground',
        'cloudKillSwitch',
        'dataExport'
    )
}

function Test-LexiQuestPostPackageMetadataPath {
    param([AllowNull()][object]$Value)

    $path = ([string]$Value).Replace('\', '/').TrimStart('./')
    return $path -cin @(
        'docs/field/2026-08-09-internal-apk-checkpoint.md',
        'docs/field/2026-08-09-device-beta-matrix.md',
        'docs/field/2026-08-09-current-release-readiness.md',
        'docs/field/2026-08-09-final-acceptance.md',
        'docs/field/2026-08-09-runtime-feature-ledger.md'
    )
}

function ConvertTo-NormalizedSha256 {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return ''
    }
    return ([string]$Value).Replace(':', '').Trim().ToUpperInvariant()
}

function Test-LexiQuestIntegerValue {
    param([AllowNull()][object]$Value)

    return (
        $Value -is [byte] -or
        $Value -is [sbyte] -or
        $Value -is [int16] -or
        $Value -is [uint16] -or
        $Value -is [int32] -or
        $Value -is [uint32] -or
        $Value -is [int64] -or
        $Value -is [uint64]
    )
}

function Test-LexiQuestFiniteNumber {
    param([AllowNull()][object]$Value)

    if (
        $Value -isnot [byte] -and
        $Value -isnot [sbyte] -and
        $Value -isnot [int16] -and
        $Value -isnot [uint16] -and
        $Value -isnot [int32] -and
        $Value -isnot [uint32] -and
        $Value -isnot [int64] -and
        $Value -isnot [uint64] -and
        $Value -isnot [single] -and
        $Value -isnot [double] -and
        $Value -isnot [decimal]
    ) {
        return $false
    }
    $number = [double]$Value
    return -not [double]::IsNaN($number) -and
        -not [double]::IsInfinity($number)
}

function ConvertFrom-LexiQuestStrictUtcTimestamp {
    param([AllowNull()][object]$Value)

    $text = [string]$Value
    if (
        $text -cnotmatch
            '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$'
    ) {
        return $null
    }
    [string[]]$formats = @(
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'"
    )
    $parsed = [DateTimeOffset]::MinValue
    $styles =
        [Globalization.DateTimeStyles]::AssumeUniversal -bor
        [Globalization.DateTimeStyles]::AdjustToUniversal
    if (
        [DateTimeOffset]::TryParseExact(
            $text,
            $formats,
            [Globalization.CultureInfo]::InvariantCulture,
            $styles,
            [ref]$parsed
        )
    ) {
        return $parsed
    }
    return $null
}

function Get-LexiQuestEvidencePublicKeyId {
    param([Parameter(Mandatory)][System.Security.Cryptography.RSA]$Rsa)

    $publicKeyXml = $Rsa.ToXmlString($false)
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($publicKeyXml)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = (
            [BitConverter]::ToString($sha.ComputeHash($bytes))
        ).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
    return "sha256:$digest"
}

function ConvertTo-LexiQuestEvidenceSigningBytes {
    param([Parameter(Mandatory)][object]$Receipt)

    $payloadProperty = $Receipt.PSObject.Properties['payload']
    if ($null -eq $payloadProperty) {
        throw 'Evidence receipt payload is missing.'
    }
    $sourceExportProperty =
        $Receipt.PSObject.Properties['sourceExportSha256']
    $sourceExportSha256 = if ($null -eq $sourceExportProperty) {
        ''
    } else {
        [string]$sourceExportProperty.Value
    }
    $signedFields = [ordered]@{
        schemaVersion = [int]$Receipt.schemaVersion
        kind = [string]$Receipt.kind
        receiptId = [string]$Receipt.receiptId
        origin = [string]$Receipt.origin
        observedAtUtc = [string]$Receipt.observedAtUtc
        sourceCommit = [string]$Receipt.sourceCommit
        apkSha256 = [string]$Receipt.apkSha256
        sourceExportSha256 = $sourceExportSha256
        payload = $payloadProperty.Value
    }
    $json = $signedFields | ConvertTo-Json -Depth 20 -Compress
    return [Text.UTF8Encoding]::new($false).GetBytes($json)
}

function Get-LexiQuestTrustedEvidenceRsa {
    param([AllowNull()][AllowEmptyString()][string]$PublicKeyPath)

    if (
        [string]::IsNullOrWhiteSpace($PublicKeyPath) -or
        -not (Test-Path -LiteralPath $PublicKeyPath -PathType Leaf)
    ) {
        return $null
    }
    $rsa = $null
    try {
        $publicKeyXml = [IO.File]::ReadAllText($PublicKeyPath)
        if (
            $publicKeyXml -match
                '<(?:D|P|Q|DP|DQ|InverseQ)>[^<]+</(?:D|P|Q|DP|DQ|InverseQ)>'
        ) {
            return $null
        }
        $rsa = [System.Security.Cryptography.RSA]::Create()
        $rsa.FromXmlString($publicKeyXml)
        if ($rsa.KeySize -lt 3072) {
            $rsa.Dispose()
            return $null
        }
        return $rsa
    }
    catch {
        if ($null -ne $rsa) {
            $rsa.Dispose()
        }
        return $null
    }
}

function Test-LexiQuestEvidenceReceiptSignature {
    param(
        [Parameter(Mandatory)][object]$Receipt,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$TrustedEvidencePublicKeyPath
    )

    $rsa = Get-LexiQuestTrustedEvidenceRsa $TrustedEvidencePublicKeyPath
    if ($null -eq $rsa) {
        return $false
    }
    try {
        if (
            [string]$Receipt.signingKeyId -cne
                (Get-LexiQuestEvidencePublicKeyId $rsa) -or
            [string]$Receipt.signatureAlgorithm -cne
                'rsa-sha256-pkcs1'
        ) {
            return $false
        }
        $signature = [Convert]::FromBase64String(
            [string]$Receipt.signatureBase64
        )
        $signingBytes = ConvertTo-LexiQuestEvidenceSigningBytes $Receipt
        return $rsa.VerifyData(
            $signingBytes,
            $signature,
            [Security.Cryptography.HashAlgorithmName]::SHA256,
            [Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
    }
    catch {
        return $false
    }
    finally {
        $rsa.Dispose()
    }
}

function Test-LexiQuestPrivateEvidenceReference {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][string]$ExpectedKind,
        [string]$PrivateEvidenceDirectory = '',
        [string]$TrustedEvidencePublicKeyPath = '',
        [string]$ExpectedSourceCommit = '',
        [string]$ExpectedApkSha256 = '',
        [switch]$RequireSourceExport,
        [string[]]$AllowedOrigins = @(),
        [DateTimeOffset]$NowUtc = [DateTimeOffset]::UtcNow,
        [TimeSpan]$MaximumAge = ([TimeSpan]::FromHours(24)),
        [AllowNull()][object]$ExpectedPayload = $null
    )

    $text = [string]$Value
    $kind = [regex]::Escape($ExpectedKind)
    $pattern = (
        '^private-evidence:v1:{0}:' +
        '[0-9a-f]{{8}}-[0-9a-f]{{4}}-4[0-9a-f]{{3}}-' +
        '[89ab][0-9a-f]{{3}}-[0-9a-f]{{12}}:' +
        'sha256:([A-F0-9]{{64}})$'
    ) -f $kind
    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success) {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace($PrivateEvidenceDirectory)) {
        return $false
    }
    $digest = $match.Groups[1].Value
    $blobPath = Join-Path (
        Join-Path $PrivateEvidenceDirectory 'blobs'
    ) "$digest.receipt"
    if (-not (Test-Path -LiteralPath $blobPath -PathType Leaf)) {
        return $false
    }
    $actualDigest = (Get-FileHash -LiteralPath $blobPath -Algorithm SHA256).Hash
    if ($actualDigest -cne $digest) {
        return $false
    }
    try {
        $receipt = Get-Content -LiteralPath $blobPath -Raw -Encoding utf8 |
            ConvertFrom-Json
    }
    catch {
        return $false
    }
    if (
        [int]$receipt.schemaVersion -ne 2 -or
        [string]$receipt.kind -cne $ExpectedKind -or
        [string]$receipt.receiptId -cne $match.Groups[0].Value.Split(':')[3]
    ) {
        return $false
    }
    if (-not (Test-LexiQuestEvidenceReceiptSignature `
        -Receipt $receipt `
        -TrustedEvidencePublicKeyPath $TrustedEvidencePublicKeyPath
    )) {
        return $false
    }
    if (
        -not [string]::IsNullOrWhiteSpace($ExpectedSourceCommit) -and
        [string]$receipt.sourceCommit -cne $ExpectedSourceCommit
    ) {
        return $false
    }
    if (
        -not [string]::IsNullOrWhiteSpace($ExpectedApkSha256) -and
        (ConvertTo-NormalizedSha256 $receipt.apkSha256) -cne
            (ConvertTo-NormalizedSha256 $ExpectedApkSha256)
    ) {
        return $false
    }
    $sourceExportProperty = $receipt.PSObject.Properties['sourceExportSha256']
    $sourceExportSha256 = if ($null -eq $sourceExportProperty) {
        ''
    } else {
        ConvertTo-NormalizedSha256 $sourceExportProperty.Value
    }
    if (
        $RequireSourceExport -and
        $sourceExportSha256 -notmatch '^[A-F0-9]{64}$'
    ) {
        return $false
    }
    if ($RequireSourceExport) {
        $sourceExportPath = Join-Path (
            Join-Path $PrivateEvidenceDirectory 'sources'
        ) "$sourceExportSha256.source"
        if (
            -not (Test-Path -LiteralPath $sourceExportPath -PathType Leaf) -or
            (Get-FileHash -LiteralPath $sourceExportPath -Algorithm SHA256).Hash `
                -cne $sourceExportSha256
        ) {
            return $false
        }
        try {
            $sourceEnvelope = Get-Content `
                -LiteralPath $sourceExportPath `
                -Raw `
                -Encoding utf8 |
                    ConvertFrom-Json
        }
        catch {
            return $false
        }
        $allowedCaptureMethods = if ($ExpectedKind -like 'device-*') {
            @(
                'physical-android-collector',
                'physical-android-instrumentation'
            )
        } elseif ($ExpectedKind -in @(
            'app-check',
            'billing',
            'asset-links'
        )) {
            @('provider-console-export')
        } elseif ($ExpectedKind -eq 'owner-approval') {
            @('owner-attestation')
        } else {
            @('release-instrumentation-export')
        }
        $sourcePayloadProperty =
            $sourceEnvelope.PSObject.Properties['payload']
        if (
            [int]$sourceEnvelope.schemaVersion -ne 1 -or
            [string]$sourceEnvelope.kind -cne $ExpectedKind -or
            [string]$sourceEnvelope.origin -cne [string]$receipt.origin -or
            [string]$sourceEnvelope.captureMethod -cnotin
                $allowedCaptureMethods -or
            $sourceEnvelope.hostFake -isnot [bool] -or
            $sourceEnvelope.hostFake -ne $false -or
            [string]$sourceEnvelope.sourceCommit -cne
                [string]$receipt.sourceCommit -or
            (ConvertTo-NormalizedSha256 $sourceEnvelope.apkSha256) -cne
                (ConvertTo-NormalizedSha256 $receipt.apkSha256) -or
            [string]$sourceEnvelope.observedAtUtc -cne
                [string]$receipt.observedAtUtc -or
            $null -eq $sourcePayloadProperty
        ) {
            return $false
        }
        $sourcePayloadJson = $sourcePayloadProperty.Value |
            ConvertTo-Json -Depth 20 -Compress
        $receiptPayloadJson = $receipt.payload |
            ConvertTo-Json -Depth 20 -Compress
        if ($sourcePayloadJson -cne $receiptPayloadJson) {
            return $false
        }
    }
    if (
        $AllowedOrigins.Count -gt 0 -and
        [string]$receipt.origin -cnotin $AllowedOrigins
    ) {
        return $false
    }
    $observedAt = ConvertFrom-LexiQuestStrictUtcTimestamp `
        $receipt.observedAtUtc
    if (
        $null -eq $observedAt -or
        $observedAt -lt $NowUtc.Subtract($MaximumAge) -or
        $observedAt -gt $NowUtc.AddMinutes(5)
    ) {
        return $false
    }
    if ($null -ne $ExpectedPayload) {
        $actualPayloadProperty = $receipt.PSObject.Properties['payload']
        if ($null -eq $actualPayloadProperty) {
            return $false
        }
        $expectedJson = $ExpectedPayload | ConvertTo-Json -Depth 20 -Compress
        $actualJson = $actualPayloadProperty.Value |
            ConvertTo-Json -Depth 20 -Compress
        if ($actualJson -cne $expectedJson) {
            return $false
        }
    }
    return $true
}

function Test-LexiQuestFieldReleaseEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Evidence,

        [Parameter(Mandatory)]
        [string]$ActualApkSha256,

        [Parameter(Mandatory)]
        [string]$ActualCertificateSha256,

        [Parameter(Mandatory)]
        [string]$ParticipantPackagePath,

        [string]$ExpectedSourceCommit = '',

        [DateTimeOffset]$NowUtc = [DateTimeOffset]::UtcNow,

        [string]$ManifestGeneratedAtUtc = '',

        [string]$PrivateEvidenceDirectory = '',

        [string]$TrustedEvidencePublicKeyPath = '',

        [string]$ExpectedCollectorScriptSha256 = ''
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $shaPattern = '^[A-F0-9]{64}$'
    $actualApk = ConvertTo-NormalizedSha256 $ActualApkSha256
    $actualCertificate = ConvertTo-NormalizedSha256 $ActualCertificateSha256

    if (-not [string]::IsNullOrWhiteSpace($PrivateEvidenceDirectory)) {
        $trustedEvidenceRsa = Get-LexiQuestTrustedEvidenceRsa `
            $TrustedEvidencePublicKeyPath
        if ($null -eq $trustedEvidenceRsa) {
            $errors.Add(
                'A trusted evidence public key is required for private receipts.'
            )
        } else {
            $trustedEvidenceRsa.Dispose()
        }
    }

    if ([int]$Evidence.schemaVersion -ne 2) {
        $errors.Add('schemaVersion must be 2.')
    }
    $sourceCommit = [string]$Evidence.sourceCommit
    if ($sourceCommit -cnotmatch '^[0-9a-f]{40}$') {
        $errors.Add('sourceCommit must be a lowercase 40-character Git SHA.')
    }
    if (
        -not [string]::IsNullOrWhiteSpace($ExpectedSourceCommit) -and
        $sourceCommit -cne $ExpectedSourceCommit
    ) {
        $errors.Add('sourceCommit does not match the release manifest.')
    }

    $evidenceManifestText = [string]$Evidence.manifestGeneratedAtUtc
    $manifestText = if (
        [string]::IsNullOrWhiteSpace($ManifestGeneratedAtUtc)
    ) {
        $evidenceManifestText
    } else {
        $ManifestGeneratedAtUtc
    }
    $manifestTime = ConvertFrom-LexiQuestStrictUtcTimestamp $manifestText
    $evidenceManifestTime =
        ConvertFrom-LexiQuestStrictUtcTimestamp $evidenceManifestText
    if (
        $null -eq $manifestTime -or
        $null -eq $evidenceManifestTime -or
        $manifestTime -ne $evidenceManifestTime
    ) {
        $errors.Add(
            'manifestGeneratedAtUtc must be strict UTC and match the manifest.'
        )
    }
    $assembledTime = ConvertFrom-LexiQuestStrictUtcTimestamp `
        $Evidence.assembledAtUtc
    if ($null -eq $assembledTime) {
        $errors.Add('assembledAtUtc must be strict UTC.')
    } elseif (
        $assembledTime -gt $NowUtc.AddMinutes(5) -or
        ($null -ne $manifestTime -and $assembledTime -lt $manifestTime)
    ) {
        $errors.Add('assembledAtUtc is outside the valid release window.')
    }

    $artifactApk = ConvertTo-NormalizedSha256 $Evidence.artifact.apkSha256
    $artifactCertificate =
        ConvertTo-NormalizedSha256 $Evidence.artifact.signingCertificateSha256
    $artifactModel = ConvertTo-NormalizedSha256 $Evidence.artifact.modelSha256
    if ($artifactApk -notmatch $shaPattern -or $artifactApk -ne $actualApk) {
        $errors.Add('artifact APK SHA-256 does not match the verified APK.')
    }
    if (
        $artifactCertificate -notmatch $shaPattern -or
        $artifactCertificate -ne $actualCertificate
    ) {
        $errors.Add(
            'artifact signing certificate SHA-256 does not match apksigner.'
        )
    }
    if ($artifactModel -notmatch $shaPattern) {
        $errors.Add('artifact modelSha256 must be a 64-character SHA-256.')
    }
    $expectedReleaseId = '{0}:{1}' -f $sourceCommit, $artifactApk
    if ([string]$Evidence.releaseId -cne $expectedReleaseId) {
        $errors.Add('releaseId must bind sourceCommit and artifact APK SHA-256.')
    }
    if ([string]$Evidence.artifact.packageName -ne 'com.lexiquest.app') {
        $errors.Add('artifact packageName must be com.lexiquest.app.')
    }
    foreach ($field in @('versionName', 'versionCode', 'buildId')) {
        if ([string]::IsNullOrWhiteSpace([string]$Evidence.artifact.$field)) {
            $errors.Add("artifact $field is required.")
        }
    }

    foreach ($control in @(
        'appCheckConfigured',
        'appCheckValidTrafficObserved',
        'appCheckEnforced',
        'assetLinksVerified',
        'cloudKillSwitchVerified'
    )) {
        if ($Evidence.cloudControls.$control -ne $true) {
            $errors.Add("cloudControls.$control must be true.")
        }
    }
    $centralCostProperty =
        $Evidence.cloudControls.PSObject.Properties['centralCost']
    $costMeasuredAtText = ''
    if ($null -eq $centralCostProperty -or $null -eq $centralCostProperty.Value) {
        $errors.Add('cloudControls.centralCost is required.')
    } else {
        $cost = $centralCostProperty.Value
        $costMeasuredAtText = [string]$cost.measuredAtUtc
        if (
            [int]$cost.schemaVersion -ne 1 -or
            [string]$cost.scope -ne 'firebaseProjectTotal' -or
            [string]$cost.projectId -ne 'vocab-learning-app-219ef' -or
            [string]$cost.projectNumber -ne '145034183638' -or
            [string]$cost.currencyCode -ne 'THB' -or
            -not (Test-LexiQuestIntegerValue `
                $cost.approvedMonthlyMinimumSatang) -or
            [long]$cost.approvedMonthlyMinimumSatang -ne 0 -or
            -not (Test-LexiQuestIntegerValue `
                $cost.approvedMonthlyMaximumSatang) -or
            [long]$cost.approvedMonthlyMaximumSatang -ne 10000
        ) {
            $errors.Add(
                'central cost policy must bind the approved Firebase ' +
                'project and 0..10000 satang range.'
            )
        }
        if (
            -not (Test-LexiQuestIntegerValue `
                $cost.measuredMonthlyCostSatang) -or
            [long]$cost.measuredMonthlyCostSatang -lt 0 -or
            [long]$cost.measuredMonthlyCostSatang -gt 10000
        ) {
            $errors.Add(
                'measured monthly central cost must be 0..10000 satang.'
            )
        }
        if ([string]$cost.mode -eq 'budgeted') {
            if (
                [string]$cost.measurementBasis -ne
                    'calendarMonthToDateGrossCost' -or
                $null -eq $cost.budget
            ) {
                $errors.Add(
                    'budgeted cost requires a gross month-to-date measurement ' +
                    'and budget controls.'
                )
            } else {
                $budget = $cost.budget
                $thresholds = @($budget.thresholds)
                if (
                    -not (Test-LexiQuestIntegerValue `
                        $budget.monthlyAmountSatang) -or
                    [long]$budget.monthlyAmountSatang -ne 10000
                ) {
                    $errors.Add(
                        'budget ceiling must be exactly 10000 satang.'
                    )
                }
                if (
                    $thresholds.Count -ne 3 -or
                    [double]$thresholds[0] -ne 0.5 -or
                    [double]$thresholds[1] -ne 0.8 -or
                    [double]$thresholds[2] -ne 1.0 -or
                    [string]$budget.spendBasis -ne 'CURRENT_SPEND' -or
                    $budget.recipientsConfigured -ne $true
                ) {
                    $errors.Add(
                        'budget controls require 50/80/100 CURRENT_SPEND ' +
                        'alerts with recipients.'
                    )
                }
            }
        } elseif ([string]$cost.mode -eq 'noBillingAccount') {
            if (
                [string]$cost.measurementBasis -ne 'billingDisabled' -or
                [long]$cost.measuredMonthlyCostSatang -ne 0 -or
                $null -ne $cost.budget
            ) {
                $errors.Add(
                    'no-billing cost evidence requires billingDisabled, ' +
                    'zero measured cost, and no budget object.'
                )
            }
        } else {
            $errors.Add(
                'central cost mode must be budgeted or noBillingAccount.'
            )
        }
        if (-not (Test-LexiQuestPrivateEvidenceReference `
            -Value $cost.evidenceRef `
            -ExpectedKind 'billing' `
            -PrivateEvidenceDirectory $PrivateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $TrustedEvidencePublicKeyPath `
            -ExpectedSourceCommit $sourceCommit `
            -ExpectedApkSha256 $artifactApk `
            -RequireSourceExport `
            -AllowedOrigins @('provider-console-export') `
            -NowUtc $NowUtc `
            -ExpectedPayload ([pscustomobject][ordered]@{
                schemaVersion = $cost.schemaVersion
                mode = $cost.mode
                scope = $cost.scope
                projectId = $cost.projectId
                projectNumber = $cost.projectNumber
                currencyCode = $cost.currencyCode
                approvedMonthlyMinimumSatang =
                    $cost.approvedMonthlyMinimumSatang
                approvedMonthlyMaximumSatang =
                    $cost.approvedMonthlyMaximumSatang
                measurementBasis = $cost.measurementBasis
                measurementMonthUtc = $cost.measurementMonthUtc
                measuredAtUtc = $cost.measuredAtUtc
                measuredMonthlyCostSatang =
                    $cost.measuredMonthlyCostSatang
                budget = $cost.budget
            })
        )) {
            $errors.Add(
                'centralCost.evidenceRef must be a verified billing reference.'
            )
        }
        $costMeasuredAt = ConvertFrom-LexiQuestStrictUtcTimestamp `
            $cost.measuredAtUtc
        if ($null -eq $costMeasuredAt) {
            $errors.Add('centralCost.measuredAtUtc must be strict UTC.')
        } elseif (
            $costMeasuredAt -lt $NowUtc.AddHours(-24) -or
            $costMeasuredAt -gt $NowUtc.AddMinutes(5) -or
            ($null -ne $manifestTime -and $costMeasuredAt -lt $manifestTime) -or
            ($null -ne $assembledTime -and $costMeasuredAt -gt $assembledTime) -or
            [string]$cost.measurementMonthUtc -cne
                $costMeasuredAt.ToString('yyyy-MM') -or
            [string]$cost.measurementMonthUtc -cne $NowUtc.ToString('yyyy-MM')
        ) {
            $errors.Add(
                'central cost measurement must be current, fresh, and ordered.'
            )
        }
    }
    $costMode = if ($null -eq $centralCostProperty) {
        ''
    } else {
        [string]$centralCostProperty.Value.mode
    }
    if ($costMode -eq 'budgeted') {
        if (
            $Evidence.cloudControls.budgetAlertsConfigured -ne $true -or
            $Evidence.cloudControls.budgetAlertsNotApplicable -ne $false -or
            [string]$Evidence.cloudControls.billingMode -cne 'budgeted'
        ) {
            $errors.Add(
                'budgeted mode requires configured 50/80/100 budget alerts.'
            )
        }
    } elseif ($costMode -eq 'noBillingAccount') {
        if (
            $Evidence.cloudControls.budgetAlertsConfigured -ne $false -or
            $Evidence.cloudControls.budgetAlertsNotApplicable -ne $true -or
            [string]$Evidence.cloudControls.billingMode -cne
                'noBillingAccount'
        ) {
            $errors.Add(
                'no-billing mode must mark budget alerts not applicable.'
            )
        }
    }
    $cloudReferenceContracts = [ordered]@{
        appCheckEvidenceRef = [pscustomobject]@{
            kind = 'app-check'
            origins = @('provider-console-export')
            payload = [pscustomobject][ordered]@{
                configured = $Evidence.cloudControls.appCheckConfigured
                validTrafficObserved =
                    $Evidence.cloudControls.appCheckValidTrafficObserved
                enforced = $Evidence.cloudControls.appCheckEnforced
                observedAtUtc =
                    $Evidence.cloudControls.appCheckObservedAtUtc
            }
        }
        budgetAlertsEvidenceRef = [pscustomobject]@{
            kind = 'billing'
            origins = @('provider-console-export')
            payload = [pscustomobject][ordered]@{
                configured = $Evidence.cloudControls.budgetAlertsConfigured
                notApplicable =
                    $Evidence.cloudControls.budgetAlertsNotApplicable
                billingMode = $Evidence.cloudControls.billingMode
                observedAtUtc = $costMeasuredAtText
            }
        }
        assetLinksEvidenceRef = [pscustomobject]@{
            kind = 'asset-links'
            origins = @('provider-console-export')
            payload = [pscustomobject][ordered]@{
                verified = $Evidence.cloudControls.assetLinksVerified
                observedAtUtc =
                    $Evidence.cloudControls.assetLinksObservedAtUtc
            }
        }
        cloudKillSwitchEvidenceRef = [pscustomobject]@{
            kind = 'kill-switch'
            origins = @('beta-ops-export')
            payload = [pscustomobject][ordered]@{
                verified = $Evidence.cloudControls.cloudKillSwitchVerified
                observedAtUtc =
                    $Evidence.cloudControls.cloudKillSwitchObservedAtUtc
            }
        }
    }
    foreach ($reference in $cloudReferenceContracts.Keys) {
        $contract = $cloudReferenceContracts[$reference]
        if (-not (Test-LexiQuestPrivateEvidenceReference `
            -Value $Evidence.cloudControls.$reference `
            -ExpectedKind $contract.kind `
            -PrivateEvidenceDirectory $PrivateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $TrustedEvidencePublicKeyPath `
            -ExpectedSourceCommit $sourceCommit `
            -ExpectedApkSha256 $artifactApk `
            -RequireSourceExport `
            -AllowedOrigins $contract.origins `
            -NowUtc $NowUtc `
            -ExpectedPayload $contract.payload
        )) {
            $errors.Add(
                "cloudControls.$reference must be a verified " +
                "$($contract.kind) reference."
            )
        }
    }

    $cloudTimes = [ordered]@{
        appCheckObservedAtUtc = 'App Check'
        assetLinksObservedAtUtc = 'asset-links'
        cloudKillSwitchObservedAtUtc = 'cloud kill-switch'
    }
    foreach ($timestampField in $cloudTimes.Keys) {
        $observedAt = ConvertFrom-LexiQuestStrictUtcTimestamp `
            $Evidence.cloudControls.$timestampField
        $label = $cloudTimes[$timestampField]
        if ($null -eq $observedAt) {
            $errors.Add("$label observedAtUtc must be strict UTC.")
        } elseif (
            $observedAt -lt $NowUtc.AddHours(-24) -or
            $observedAt -gt $NowUtc.AddMinutes(5) -or
            ($null -ne $manifestTime -and $observedAt -lt $manifestTime) -or
            ($null -ne $assembledTime -and $observedAt -gt $assembledTime)
        ) {
            $errors.Add("$label evidence must be fresh for this release.")
        }
    }

    $package = $Evidence.participantPackage
    foreach ($document in @(
        'installGuide',
        'privacyNotice',
        'dataRightsGuide',
        'knownLimitations',
        'feedbackGuide',
        'researchProtocol'
    )) {
        $relative = [string]$package.$document
        if ([string]::IsNullOrWhiteSpace($relative)) {
            $errors.Add("participantPackage.$document is required.")
            continue
        }
        if (
            [IO.Path]::IsPathRooted($relative) -or
            $relative -match '(^|[\\/])\.\.([\\/]|$)'
        ) {
            $errors.Add(
                "participantPackage.$document must stay inside the package."
            )
            continue
        }
        $packageRoot = [IO.Path]::GetFullPath($ParticipantPackagePath).
            TrimEnd('\', '/')
        $documentPath = [IO.Path]::GetFullPath(
            (Join-Path $packageRoot $relative)
        )
        if (-not $documentPath.StartsWith(
            $packageRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            $errors.Add(
                "participantPackage.$document must stay inside the package."
            )
            continue
        }
        if (-not (Test-Path -LiteralPath $documentPath -PathType Leaf)) {
            $errors.Add("participant document is missing: $relative")
            continue
        }
        $expectedDocumentSha = ConvertTo-NormalizedSha256 `
            $package.documentSha256.$document
        $actualDocumentSha = (
            Get-FileHash -LiteralPath $documentPath -Algorithm SHA256
        ).Hash
        if (
            $expectedDocumentSha -notmatch '^[A-F0-9]{64}$' -or
            $expectedDocumentSha -cne $actualDocumentSha
        ) {
            $errors.Add(
                "participantPackage.$document content hash does not match."
            )
        }
    }
    if ([int]$package.consentVersion -ne 1) {
        $errors.Add('participantPackage.consentVersion must be 1.')
    }
    $participantReferenceContracts = [ordered]@{
        feedbackChannelRef = [pscustomobject]@{
            kind = 'feedback-channel'
            channel = 'feedback'
        }
        supportChannelRef = [pscustomobject]@{
            kind = 'support-channel'
            channel = 'support'
        }
        researchProtocolRef = [pscustomobject]@{
            kind = 'research-protocol'
            channel = 'research-protocol'
        }
    }
    foreach ($channel in $participantReferenceContracts.Keys) {
        $contract = $participantReferenceContracts[$channel]
        if (-not (Test-LexiQuestPrivateEvidenceReference `
            -Value $package.$channel `
            -ExpectedKind $contract.kind `
            -PrivateEvidenceDirectory $PrivateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $TrustedEvidencePublicKeyPath `
            -ExpectedSourceCommit $sourceCommit `
            -ExpectedApkSha256 $artifactApk `
            -RequireSourceExport `
            -AllowedOrigins @('beta-ops-export') `
            -NowUtc $NowUtc `
            -MaximumAge ([TimeSpan]::FromDays(30)) `
            -ExpectedPayload ([pscustomobject][ordered]@{
                channel = $contract.channel
                verifiedAtUtc = $package.verifiedAtUtc
                consentVersion = $package.consentVersion
                documentSha256 = $package.documentSha256
            })
        )) {
            $errors.Add(
                "participantPackage.$channel must be a verified " +
                "$($contract.kind) reference to a real private channel."
            )
        }
    }
    $participantVerifiedAt = ConvertFrom-LexiQuestStrictUtcTimestamp `
        $package.verifiedAtUtc
    if ($null -eq $participantVerifiedAt) {
        $errors.Add('participantPackage.verifiedAtUtc must be strict UTC.')
    } elseif (
        $participantVerifiedAt -lt $NowUtc.AddDays(-30) -or
        $participantVerifiedAt -gt $NowUtc.AddMinutes(5) -or
        ($null -ne $manifestTime -and $participantVerifiedAt -lt $manifestTime) -or
        ($null -ne $assembledTime -and $participantVerifiedAt -gt $assembledTime)
    ) {
        $errors.Add('participant package verification is stale or out of order.')
    }

    $devices = @($Evidence.devices)
    if ($devices.Count -ne 3) {
        $errors.Add(
            'Exactly three physical Android device records are required ' +
                '(low, mid, and high tier).'
        )
    }
    $tiers = @($devices | ForEach-Object { [string]$_.tier })
    foreach ($tier in @('low', 'mid', 'high')) {
        if (@($tiers | Where-Object { $_ -eq $tier }).Count -ne 1) {
            $errors.Add("Exactly one $tier-tier device record is required.")
        }
    }
    $deviceIds = @($devices | ForEach-Object {
        ([string]$_.pseudonymousDeviceId).ToUpperInvariant()
    })
    if (@($deviceIds | Sort-Object -Unique).Count -ne $devices.Count) {
        $errors.Add('Physical device records must have distinct pseudonymous IDs.')
    }

    $requiredJourneys = Get-LexiQuestRequiredFieldJourneys
    foreach ($device in $devices) {
        $label = if ([string]::IsNullOrWhiteSpace([string]$device.tier)) {
            'unknown-tier'
        } else {
            [string]$device.tier
        }
        if (
            (ConvertTo-NormalizedSha256 $device.pseudonymousDeviceId) -notmatch
            $shaPattern
        ) {
            $errors.Add("$label device pseudonymousDeviceId is invalid.")
        }
        if ([string]::IsNullOrWhiteSpace([string]$device.evidenceId)) {
            $errors.Add("$label device evidenceId is required.")
        }
        $deviceRecordedAt = ConvertFrom-LexiQuestStrictUtcTimestamp `
            $device.recordedAtUtc
        if ($null -eq $deviceRecordedAt) {
            $errors.Add("$label device recordedAtUtc must be strict UTC.")
        } elseif (
            $deviceRecordedAt -lt $NowUtc.AddDays(-30) -or
            $deviceRecordedAt -gt $NowUtc.AddMinutes(5) -or
            ($null -ne $manifestTime -and $deviceRecordedAt -lt $manifestTime) -or
            ($null -ne $assembledTime -and $deviceRecordedAt -gt $assembledTime)
        ) {
            $errors.Add("$label device evidence is stale or out of order.")
        }
        if ($device.device.physical -ne $true) {
            $errors.Add("$label evidence must be from a physical device.")
        }

        $collector = $device.collector
        $collectorHash = ConvertTo-NormalizedSha256 `
            $collector.collectorScriptSha256
        $markerText = @(
            $device.device.model,
            $device.device.chipset,
            $device.device.gpu,
            $collector.fingerprint,
            $collector.brand,
            $collector.deviceName,
            $collector.hardware
        ) -join ' '
        if (
            [int]$collector.schemaVersion -ne 1 -or
            [string]$collector.origin -cne 'physical-android-collector' -or
            $collectorHash -notmatch $shaPattern -or
            (
                -not [string]::IsNullOrWhiteSpace(
                    $ExpectedCollectorScriptSha256
                ) -and
                $collectorHash -cne (
                    ConvertTo-NormalizedSha256 `
                        $ExpectedCollectorScriptSha256
                )
            ) -or
            [int]$collector.connectedDeviceCount -ne 1 -or
            [string]$collector.roKernelQemu -cnotin @('0', 'absent') -or
            [string]$collector.roBootQemu -cnotin @('0', 'absent') -or
            [string]$collector.serialKind -cne 'physical' -or
            [string]$collector.buildType -cne 'user' -or
            [string]$collector.debuggable -cne '0' -or
            [string]$collector.secure -cne '1' -or
            $markerText -match (
                '(?i)goldfish|ranchu|cuttlefish|vbox|generic|' +
                'sdk_gphone|emulator'
            ) -or
            (ConvertTo-NormalizedSha256 `
                $collector.verifiedApkSha256) -cne $artifactApk
        ) {
            $errors.Add(
                "$label collector attestation does not prove a production " +
                'physical device.'
            )
        }
        foreach ($field in @(
            'model',
            'androidVersion',
            'ramMb',
            'chipset',
            'gpu',
            'storageFreeMb',
            'networkProfile'
        )) {
            if ([string]::IsNullOrWhiteSpace([string]$device.device.$field)) {
                $errors.Add("$label device.device.$field is required.")
            }
        }
        $deviceApk =
            ConvertTo-NormalizedSha256 $device.release.apkSha256
        $deviceCertificate =
            ConvertTo-NormalizedSha256 `
                $device.release.signingCertificateSha256
        $deviceModel =
            ConvertTo-NormalizedSha256 $device.release.modelSha256
        if ($deviceApk -ne $artifactApk) {
            $errors.Add("$label device was not tested with the release APK.")
        }
        if ($deviceCertificate -ne $artifactCertificate) {
            $errors.Add("$label device certificate does not match the release.")
        }
        if ($deviceModel -ne $artifactModel) {
            $errors.Add("$label device model checksum does not match the release.")
        }
        foreach ($field in @('versionName', 'versionCode', 'buildId')) {
            if ([string]$device.release.$field -ne
                [string]$Evidence.artifact.$field) {
                $errors.Add("$label device release.$field does not match.")
            }
        }
        if (-not (Test-LexiQuestPrivateEvidenceReference `
            -Value $collector.evidenceRef `
            -ExpectedKind 'device-attestation' `
            -PrivateEvidenceDirectory $PrivateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $TrustedEvidencePublicKeyPath `
            -ExpectedSourceCommit $sourceCommit `
            -ExpectedApkSha256 $artifactApk `
            -AllowedOrigins @('physical-android-collector') `
            -NowUtc $NowUtc `
            -MaximumAge ([TimeSpan]::FromDays(30)) `
            -ExpectedPayload ([pscustomobject][ordered]@{
                evidenceId = $device.evidenceId
                tier = $device.tier
                pseudonymousDeviceId = $device.pseudonymousDeviceId
                recordedAtUtc = $device.recordedAtUtc
                device = $device.device
                release = $device.release
                collector = [pscustomobject][ordered]@{
                    schemaVersion = $collector.schemaVersion
                    origin = $collector.origin
                    collectorScriptSha256 =
                        $collector.collectorScriptSha256
                    connectedDeviceCount = $collector.connectedDeviceCount
                    roKernelQemu = $collector.roKernelQemu
                    roBootQemu = $collector.roBootQemu
                    serialKind = $collector.serialKind
                    buildType = $collector.buildType
                    debuggable = $collector.debuggable
                    secure = $collector.secure
                    fingerprint = $collector.fingerprint
                    brand = $collector.brand
                    deviceName = $collector.deviceName
                    hardware = $collector.hardware
                    verifiedApkSha256 = $collector.verifiedApkSha256
                }
            })
        )) {
            $errors.Add(
                "$label collector evidenceRef must be a verified " +
                'device-attestation receipt.'
            )
        }

        foreach ($journeyName in $requiredJourneys) {
            $journey = $device.journeys.$journeyName
            if ([string]$journey.status -ne 'pass') {
                $errors.Add("$label journey $journeyName must pass.")
            }
            if (-not (Test-LexiQuestPrivateEvidenceReference `
                -Value $journey.evidenceRef `
                -ExpectedKind 'device-journey' `
                -PrivateEvidenceDirectory $PrivateEvidenceDirectory `
                -TrustedEvidencePublicKeyPath $TrustedEvidencePublicKeyPath `
                -ExpectedSourceCommit $sourceCommit `
                -ExpectedApkSha256 $artifactApk `
                -RequireSourceExport `
                -AllowedOrigins @(
                    'physical-android-collector',
                    'physical-android-instrumentation'
                ) `
                -NowUtc $NowUtc `
                -MaximumAge ([TimeSpan]::FromDays(30)) `
                -ExpectedPayload ([pscustomobject][ordered]@{
                    evidenceId = $device.evidenceId
                    tier = $device.tier
                    pseudonymousDeviceId = $device.pseudonymousDeviceId
                    journey = $journeyName
                    status = $journey.status
                })
            )) {
                $errors.Add(
                    "$label journey $journeyName needs a verified " +
                    'device-journey evidenceRef.'
                )
            }
        }

        $cpu = $device.benchmarks.cpuXnnpack
        if (
            [string]$cpu.status -ne 'pass' -or
            [string]$cpu.delegate -ne 'xnnpack' -or
            [int]$cpu.iterations -lt 10 -or
            -not (Test-LexiQuestFiniteNumber $cpu.medianLatencyMs) -or
            [double]$cpu.medianLatencyMs -le 0 -or
            -not (Test-LexiQuestPrivateEvidenceReference `
                -Value $cpu.evidenceRef `
                -ExpectedKind 'device-benchmark' `
                -PrivateEvidenceDirectory $PrivateEvidenceDirectory `
                -TrustedEvidencePublicKeyPath $TrustedEvidencePublicKeyPath `
                -ExpectedSourceCommit $sourceCommit `
                -ExpectedApkSha256 $artifactApk `
                -RequireSourceExport `
                -AllowedOrigins @(
                    'physical-android-collector',
                    'physical-android-instrumentation'
                ) `
                -NowUtc $NowUtc `
                -MaximumAge ([TimeSpan]::FromDays(30)) `
                -ExpectedPayload ([pscustomobject][ordered]@{
                    evidenceId = $device.evidenceId
                    tier = $device.tier
                    pseudonymousDeviceId = $device.pseudonymousDeviceId
                    benchmark = 'cpuXnnpack'
                    status = $cpu.status
                    delegate = $cpu.delegate
                    iterations = $cpu.iterations
                    medianLatencyMs = $cpu.medianLatencyMs
                })
            )
        ) {
            $errors.Add(
                "$label CPU/XNNPACK benchmark must pass with >=10 iterations."
            )
        }
        $gpu = $device.benchmarks.gpuDelegate
        if ([string]$gpu.status -eq 'pass') {
            if (
                $gpu.allowlisted -ne $true -or
                [int]$gpu.iterations -lt 10 -or
                -not (Test-LexiQuestPrivateEvidenceReference `
                    -Value $gpu.evidenceRef `
                    -ExpectedKind 'device-benchmark' `
                    -PrivateEvidenceDirectory $PrivateEvidenceDirectory `
                    -TrustedEvidencePublicKeyPath $TrustedEvidencePublicKeyPath `
                    -ExpectedSourceCommit $sourceCommit `
                    -ExpectedApkSha256 $artifactApk `
                    -RequireSourceExport `
                    -AllowedOrigins @(
                        'physical-android-collector',
                        'physical-android-instrumentation'
                    ) `
                    -NowUtc $NowUtc `
                    -MaximumAge ([TimeSpan]::FromDays(30)) `
                    -ExpectedPayload ([pscustomobject][ordered]@{
                        evidenceId = $device.evidenceId
                        tier = $device.tier
                        pseudonymousDeviceId =
                            $device.pseudonymousDeviceId
                        benchmark = 'gpuDelegate'
                        status = $gpu.status
                        allowlisted = $gpu.allowlisted
                        iterations = $gpu.iterations
                        reason = $gpu.reason
                    })
                )
            ) {
                $errors.Add(
                    "$label GPU pass requires allowlisting and >=10 iterations."
                )
            }
        } elseif ([string]$gpu.status -eq 'notApplicable') {
            if (
                $gpu.allowlisted -ne $false -or
                [string]::IsNullOrWhiteSpace([string]$gpu.reason) -or
                -not (Test-LexiQuestPrivateEvidenceReference `
                    -Value $gpu.evidenceRef `
                    -ExpectedKind 'device-benchmark' `
                    -PrivateEvidenceDirectory $PrivateEvidenceDirectory `
                    -TrustedEvidencePublicKeyPath $TrustedEvidencePublicKeyPath `
                    -ExpectedSourceCommit $sourceCommit `
                    -ExpectedApkSha256 $artifactApk `
                    -RequireSourceExport `
                    -AllowedOrigins @(
                        'physical-android-collector',
                        'physical-android-instrumentation'
                    ) `
                    -NowUtc $NowUtc `
                    -MaximumAge ([TimeSpan]::FromDays(30)) `
                    -ExpectedPayload ([pscustomobject][ordered]@{
                        evidenceId = $device.evidenceId
                        tier = $device.tier
                        pseudonymousDeviceId =
                            $device.pseudonymousDeviceId
                        benchmark = 'gpuDelegate'
                        status = $gpu.status
                        allowlisted = $gpu.allowlisted
                        iterations = $gpu.iterations
                        reason = $gpu.reason
                    })
                )
            ) {
                $errors.Add(
                    "$label GPU N/A requires allowlisted=false and a reason."
                )
            }
        } else {
            $errors.Add("$label GPU status must be pass or notApplicable.")
        }

        $endurance = $device.endurance
        if (
            [string]$endurance.status -ne 'pass' -or
            -not (Test-LexiQuestFiniteNumber $endurance.durationMinutes) -or
            [double]$endurance.durationMinutes -lt 30 -or
            [int]$endurance.crashCount -ne 0 -or
            [int]$endurance.anrCount -ne 0 -or
            -not (Test-LexiQuestPrivateEvidenceReference `
                -Value $endurance.evidenceRef `
                -ExpectedKind 'device-endurance' `
                -PrivateEvidenceDirectory $PrivateEvidenceDirectory `
                -TrustedEvidencePublicKeyPath $TrustedEvidencePublicKeyPath `
                -ExpectedSourceCommit $sourceCommit `
                -ExpectedApkSha256 $artifactApk `
                -RequireSourceExport `
                -AllowedOrigins @(
                    'physical-android-collector',
                    'physical-android-instrumentation'
                ) `
                -NowUtc $NowUtc `
                -MaximumAge ([TimeSpan]::FromDays(30)) `
                -ExpectedPayload ([pscustomobject][ordered]@{
                    evidenceId = $device.evidenceId
                    tier = $device.tier
                    pseudonymousDeviceId = $device.pseudonymousDeviceId
                    status = $endurance.status
                    durationMinutes = $endurance.durationMinutes
                    crashCount = $endurance.crashCount
                    anrCount = $endurance.anrCount
                    peakRssMb = $endurance.peakRssMb
                    batteryStartPercent = $endurance.batteryStartPercent
                    batteryEndPercent = $endurance.batteryEndPercent
                    temperatureStartC = $endurance.temperatureStartC
                    temperatureEndC = $endurance.temperatureEndC
                })
            )
        ) {
            $errors.Add(
                "$label endurance must pass >=30 minutes with zero crash/ANR."
            )
        }
        foreach ($metric in @(
            'peakRssMb',
            'batteryStartPercent',
            'batteryEndPercent',
            'temperatureStartC',
            'temperatureEndC'
        )) {
            if (-not (Test-LexiQuestFiniteNumber $endurance.$metric)) {
                $errors.Add("$label endurance.$metric is required.")
            }
        }
    }

    $betaCompletedTime = $null
    $betaOperationsProperty =
        $Evidence.PSObject.Properties['betaOperations']
    if (
        $null -eq $betaOperationsProperty -or
        $null -eq $betaOperationsProperty.Value
    ) {
        $errors.Add('betaOperations is required.')
    } else {
        $beta = $betaOperationsProperty.Value
        if ([string]$beta.status -ne 'pass') {
            $errors.Add('betaOperations.status must be pass.')
        }
        if (
            (ConvertTo-NormalizedSha256 $beta.release.apkSha256) -ne
                $artifactApk -or
            [string]$beta.release.buildId -ne
                [string]$Evidence.artifact.buildId -or
            [string]$beta.release.versionCode -ne
                [string]$Evidence.artifact.versionCode
        ) {
            $errors.Add('betaOperations release does not match the artifact.')
        }
        if (
            -not (Test-LexiQuestIntegerValue $beta.testerCount) -or
            [long]$beta.testerCount -lt 1
        ) {
            $errors.Add('betaOperations.testerCount must be at least 1.')
        }
        if ([int]$beta.consentVersion -ne [int]$package.consentVersion) {
            $errors.Add(
                'betaOperations.consentVersion must match the participant package.'
            )
        }

        $sessions = $beta.sessions
        if (
            -not (Test-LexiQuestIntegerValue $sessions.totalCount) -or
            -not (Test-LexiQuestIntegerValue $sessions.crashFreeCount) -or
            -not (Test-LexiQuestIntegerValue $sessions.crashCount) -or
            -not (Test-LexiQuestIntegerValue $sessions.anrCount) -or
            [long]$sessions.totalCount -lt 1 -or
            [long]$sessions.crashFreeCount -ne [long]$sessions.totalCount -or
            [long]$sessions.crashCount -ne 0 -or
            [long]$sessions.anrCount -ne 0
        ) {
            $errors.Add(
                'beta sessions must be crash-free with at least one session.'
            )
        }

        $sync = $beta.sync
        if (
            -not (Test-LexiQuestIntegerValue $sync.attemptCount) -or
            -not (Test-LexiQuestIntegerValue $sync.failureCount) -or
            [long]$sync.attemptCount -lt 1 -or
            [long]$sync.failureCount -ne 0
        ) {
            $errors.Add(
                'beta sync must record at least one attempt and zero failures.'
            )
        }

        $issues = $beta.openIssues
        $issueCounts = @(
            $issues.criticalCount,
            $issues.highCount,
            $issues.mediumCount,
            $issues.lowCount
        )
        if (
            @($issueCounts | Where-Object {
                -not (Test-LexiQuestIntegerValue $_) -or [long]$_ -lt 0
            }).Count -gt 0 -or
            [long]$issues.criticalCount -ne 0 -or
            [long]$issues.highCount -ne 0
        ) {
            $errors.Add(
                'beta issues require nonnegative counts and zero critical/high.'
            )
        }

        $usage = $beta.providerUsage
        $usageCounts = @(
            $usage.requestCount,
            $usage.successCount,
            $usage.failureCount,
            $usage.indeterminateCount,
            $usage.costKnownRequestCount,
            $usage.providerReportedCostMicrosUsd
        )
        if (
            @($usageCounts | Where-Object {
                -not (Test-LexiQuestIntegerValue $_) -or [long]$_ -lt 0
            }).Count -gt 0 -or
            [long]$usage.requestCount -lt 1 -or
            (
                [long]$usage.successCount +
                [long]$usage.failureCount +
                [long]$usage.indeterminateCount
            ) -ne [long]$usage.requestCount -or
            [long]$usage.failureCount -ne 0 -or
            [long]$usage.indeterminateCount -ne 0 -or
            [long]$usage.costKnownRequestCount -ne [long]$usage.requestCount
        ) {
            $errors.Add(
                'provider cost must be known and every beta request successful.'
            )
        }

        $downloads = $beta.modelDownloads
        if (
            -not (Test-LexiQuestIntegerValue $downloads.successfulCount) -or
            -not (Test-LexiQuestIntegerValue $downloads.failedCount) -or
            [long]$downloads.successfulCount -lt 1 -or
            [long]$downloads.failedCount -lt 0 -or
            $downloads.countMayBeSaturated -isnot [bool]
        ) {
            $errors.Add(
                'beta model-download counters are incomplete or invalid.'
            )
        }
        if ([string]$beta.ownerDecision.decision -ne 'proceed') {
            $errors.Add('beta owner decision must be proceed.')
        }
        $betaReferenceContracts = [ordered]@{
            'sessions' = [pscustomobject]@{
                reference = $sessions.evidenceRef
                payload = [pscustomobject][ordered]@{
                    release = $beta.release
                    windowStartedAtUtc = $beta.windowStartedAtUtc
                    windowEndedAtUtc = $beta.windowEndedAtUtc
                    testerCount = $beta.testerCount
                    consentVersion = $beta.consentVersion
                    totalCount = $sessions.totalCount
                    crashFreeCount = $sessions.crashFreeCount
                    crashCount = $sessions.crashCount
                    anrCount = $sessions.anrCount
                }
            }
            'sync' = [pscustomobject]@{
                reference = $sync.evidenceRef
                payload = [pscustomobject][ordered]@{
                    attemptCount = $sync.attemptCount
                    failureCount = $sync.failureCount
                }
            }
            'openIssues' = [pscustomobject]@{
                reference = $issues.evidenceRef
                payload = [pscustomobject][ordered]@{
                    criticalCount = $issues.criticalCount
                    highCount = $issues.highCount
                    mediumCount = $issues.mediumCount
                    lowCount = $issues.lowCount
                }
            }
            'providerUsage' = [pscustomobject]@{
                reference = $usage.evidenceRef
                payload = [pscustomobject][ordered]@{
                    requestCount = $usage.requestCount
                    successCount = $usage.successCount
                    failureCount = $usage.failureCount
                    indeterminateCount = $usage.indeterminateCount
                    costKnownRequestCount = $usage.costKnownRequestCount
                    providerReportedCostMicrosUsd =
                        $usage.providerReportedCostMicrosUsd
                }
            }
            'modelDownloads' = [pscustomobject]@{
                reference = $downloads.evidenceRef
                payload = [pscustomobject][ordered]@{
                    successfulCount = $downloads.successfulCount
                    failedCount = $downloads.failedCount
                    countMayBeSaturated = $downloads.countMayBeSaturated
                }
            }
            'ownerDecision' = [pscustomobject]@{
                reference = $beta.ownerDecision.evidenceRef
                payload = [pscustomobject][ordered]@{
                    decision = $beta.ownerDecision.decision
                    decidedAtUtc = $beta.ownerDecision.decidedAtUtc
                }
            }
        }
        $betaContext = [pscustomobject][ordered]@{
            release = $beta.release
            windowStartedAtUtc = $beta.windowStartedAtUtc
            windowEndedAtUtc = $beta.windowEndedAtUtc
            testerCount = $beta.testerCount
            consentVersion = $beta.consentVersion
        }
        foreach ($betaReferenceName in $betaReferenceContracts.Keys) {
            $contract = $betaReferenceContracts[$betaReferenceName]
            $payloadWithContext = [ordered]@{
                release = $betaContext.release
                windowStartedAtUtc = $betaContext.windowStartedAtUtc
                windowEndedAtUtc = $betaContext.windowEndedAtUtc
                testerCount = $betaContext.testerCount
                consentVersion = $betaContext.consentVersion
            }
            foreach ($property in $contract.payload.PSObject.Properties) {
                if (-not $payloadWithContext.Contains($property.Name)) {
                    $payloadWithContext[$property.Name] = $property.Value
                }
            }
            $contract.payload = [pscustomobject]$payloadWithContext
        }
        foreach ($betaReferenceName in $betaReferenceContracts.Keys) {
            $contract = $betaReferenceContracts[$betaReferenceName]
            if (-not (Test-LexiQuestPrivateEvidenceReference `
                -Value $contract.reference `
                -ExpectedKind 'beta-operations' `
                -PrivateEvidenceDirectory $PrivateEvidenceDirectory `
                -TrustedEvidencePublicKeyPath $TrustedEvidencePublicKeyPath `
                -ExpectedSourceCommit $sourceCommit `
                -ExpectedApkSha256 $artifactApk `
                -RequireSourceExport `
                -AllowedOrigins @('beta-ops-export') `
                -NowUtc $NowUtc `
                -ExpectedPayload $contract.payload
            )) {
                $errors.Add(
                    "beta $betaReferenceName evidenceRef must be verified."
                )
            }
        }
        $betaStartedTime = ConvertFrom-LexiQuestStrictUtcTimestamp `
            $beta.windowStartedAtUtc
        $betaEndedTime = ConvertFrom-LexiQuestStrictUtcTimestamp `
            $beta.windowEndedAtUtc
        $betaDecisionTime = ConvertFrom-LexiQuestStrictUtcTimestamp `
            $beta.ownerDecision.decidedAtUtc
        if (
            $null -eq $betaStartedTime -or
            $null -eq $betaEndedTime -or
            $null -eq $betaDecisionTime
        ) {
            $errors.Add('beta operations timestamps must be strict UTC.')
        } elseif (
            $betaEndedTime -lt $betaStartedTime -or
            $betaDecisionTime -lt $betaEndedTime -or
            $betaEndedTime -lt $NowUtc.AddHours(-24) -or
            $betaDecisionTime -gt $NowUtc.AddMinutes(5) -or
            ($null -ne $manifestTime -and $betaStartedTime -lt $manifestTime) -or
            ($null -ne $assembledTime -and $betaDecisionTime -gt $assembledTime)
        ) {
            $errors.Add('beta operations timestamps are stale or out of order.')
        } else {
            $betaCompletedTime = $betaDecisionTime
        }
    }

    $rollbackCompletedTime = $null
    $rollbackProperty = $Evidence.PSObject.Properties['rollbackEvidence']
    if ($null -eq $rollbackProperty -or $null -eq $rollbackProperty.Value) {
        $errors.Add('rollbackEvidence is required.')
    } else {
        $rollback = $rollbackProperty.Value
        if ([string]$rollback.status -ne 'pass') {
            $errors.Add('rollbackEvidence.status must be pass.')
        }
        if (
            (ConvertTo-NormalizedSha256 $rollback.candidate.apkSha256) -ne
                $artifactApk -or
            [string]$rollback.candidate.buildId -ne
                [string]$Evidence.artifact.buildId -or
            [string]$rollback.candidate.versionCode -ne
                [string]$Evidence.artifact.versionCode
        ) {
            $errors.Add('rollback candidate does not match the artifact.')
        }
        $rollbackTargetApk =
            ConvertTo-NormalizedSha256 $rollback.target.apkSha256
        if (
            $rollbackTargetApk -notmatch $shaPattern -or
            $rollbackTargetApk -eq $artifactApk
        ) {
            $errors.Add('rollback target APK SHA-256 must be valid and distinct.')
        }
        if (
            (ConvertTo-NormalizedSha256 `
                $rollback.target.signingCertificateSha256) -ne
                $artifactCertificate
        ) {
            $errors.Add('rollback target must use the release signing identity.')
        }
        if (
            -not (Test-LexiQuestIntegerValue $rollback.target.versionCode) -or
            [long]$rollback.target.versionCode -lt 1 -or
            [long]$rollback.target.versionCode -ge
                [long]$Evidence.artifact.versionCode
        ) {
            $errors.Add('rollback target version must be lower than the candidate.')
        }
        if (
            $rollback.targetLaunchVerified -ne $true -or
            $rollback.coreOfflineJourneyVerified -ne $true -or
            $rollback.serviceRestored -ne $true -or
            [string]$rollback.dataOutcome -notin @(
                'preserved',
                'exportedAndReset'
            )
        ) {
            $errors.Add('rollback drill outcomes are incomplete.')
        }
        $killSwitch = $rollback.killSwitchDrill
        $drillId = [string]$rollback.drillId
        $killSwitchDrillId = [string]$killSwitch.drillId
        $rollbackCandidateJson = $rollback.candidate |
            ConvertTo-Json -Depth 10 -Compress
        $killSwitchCandidateJson = $killSwitch.candidate |
            ConvertTo-Json -Depth 10 -Compress
        $rollbackTargetJson = $rollback.target |
            ConvertTo-Json -Depth 10 -Compress
        $killSwitchTargetJson = $killSwitch.target |
            ConvertTo-Json -Depth 10 -Compress
        if (
            $drillId -cnotmatch (
                '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-' +
                '[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
            ) -or
            $killSwitchDrillId -cne $drillId -or
            $killSwitchCandidateJson -cne $rollbackCandidateJson -or
            $killSwitchTargetJson -cne $rollbackTargetJson -or
            [string]$killSwitch.startedAtUtc -cne
                [string]$rollback.startedAtUtc -or
            [string]$killSwitch.completedAtUtc -cne
                [string]$rollback.completedAtUtc
        ) {
            $errors.Add(
                'Rollback and kill-switch evidence require one shared ' +
                'rollback drill identity and context.'
            )
        }
        if (
            [string]$killSwitch.status -ne 'pass' -or
            $killSwitch.cloudSyncDisabledObserved -ne $true -or
            $killSwitch.localLearningUsable -ne $true -or
            $killSwitch.cloudSyncRestored -ne $true
        ) {
            $errors.Add('rollback kill-switch drill must pass all outcomes.')
        }
        if (-not (Test-LexiQuestPrivateEvidenceReference `
            -Value $rollback.evidenceRef `
            -ExpectedKind 'rollback-drill' `
            -PrivateEvidenceDirectory $PrivateEvidenceDirectory `
            -TrustedEvidencePublicKeyPath $TrustedEvidencePublicKeyPath `
            -ExpectedSourceCommit $sourceCommit `
            -ExpectedApkSha256 $artifactApk `
            -RequireSourceExport `
            -AllowedOrigins @('beta-ops-export') `
            -NowUtc $NowUtc `
            -ExpectedPayload ([pscustomobject][ordered]@{
                drillId = $rollback.drillId
                candidate = $rollback.candidate
                target = $rollback.target
                startedAtUtc = $rollback.startedAtUtc
                completedAtUtc = $rollback.completedAtUtc
                targetLaunchVerified = $rollback.targetLaunchVerified
                coreOfflineJourneyVerified =
                    $rollback.coreOfflineJourneyVerified
                serviceRestored = $rollback.serviceRestored
                dataOutcome = $rollback.dataOutcome
            })
        )) {
            $errors.Add(
                'rollbackEvidence.evidenceRef must be a verified ' +
                'rollback-drill reference.'
            )
        }
        if (
            -not (Test-LexiQuestPrivateEvidenceReference `
                -Value $killSwitch.evidenceRef `
                -ExpectedKind 'kill-switch' `
                -PrivateEvidenceDirectory $PrivateEvidenceDirectory `
                -TrustedEvidencePublicKeyPath $TrustedEvidencePublicKeyPath `
                -ExpectedSourceCommit $sourceCommit `
                -ExpectedApkSha256 $artifactApk `
                -RequireSourceExport `
                -AllowedOrigins @('beta-ops-export') `
                -NowUtc $NowUtc `
                -ExpectedPayload ([pscustomobject][ordered]@{
                    drillId = $killSwitch.drillId
                    candidate = $killSwitch.candidate
                    target = $killSwitch.target
                    startedAtUtc = $killSwitch.startedAtUtc
                    completedAtUtc = $killSwitch.completedAtUtc
                    status = $killSwitch.status
                    cloudSyncDisabledObserved =
                        $killSwitch.cloudSyncDisabledObserved
                    localLearningUsable =
                        $killSwitch.localLearningUsable
                    cloudSyncRestored = $killSwitch.cloudSyncRestored
                })
            )
        ) {
            $errors.Add(
                'rollback kill-switch reference must be independently verified.'
            )
        }
        $rollbackStartedTime = ConvertFrom-LexiQuestStrictUtcTimestamp `
            $rollback.startedAtUtc
        $rollbackEndedTime = ConvertFrom-LexiQuestStrictUtcTimestamp `
            $rollback.completedAtUtc
        if ($null -eq $rollbackStartedTime -or $null -eq $rollbackEndedTime) {
            $errors.Add('rollback timestamps must be strict UTC.')
        } elseif (
            $rollbackEndedTime -lt $rollbackStartedTime -or
            $rollbackEndedTime -lt $NowUtc.AddHours(-24) -or
            $rollbackEndedTime -gt $NowUtc.AddMinutes(5) -or
            ($null -ne $manifestTime -and
                $rollbackStartedTime -lt $manifestTime) -or
            ($null -ne $assembledTime -and
                $rollbackEndedTime -gt $assembledTime)
        ) {
            $errors.Add('rollback timestamps are stale or out of order.')
        } else {
            $rollbackCompletedTime = $rollbackEndedTime
        }
    }

    $approval = $Evidence.ownerApproval
    if ($approval.approved -ne $true) {
        $errors.Add('ownerApproval.approved must be true.')
    }
    if (
        (ConvertTo-NormalizedSha256 $approval.apkSha256) -ne
        $artifactApk
    ) {
        $errors.Add('owner approval must reference the release APK SHA-256.')
    }
    if (
        [string]$approval.sourceCommit -cne $sourceCommit -or
        (ConvertTo-NormalizedSha256 `
            $approval.signingCertificateSha256) -cne $artifactCertificate -or
        (ConvertTo-NormalizedSha256 `
            $approval.modelSha256) -cne $artifactModel -or
        [string]$approval.versionName -cne
            [string]$Evidence.artifact.versionName -or
        [string]$approval.versionCode -cne
            [string]$Evidence.artifact.versionCode -or
        [string]$approval.buildId -cne [string]$Evidence.artifact.buildId
    ) {
        $errors.Add('owner approval must bind every release identity field.')
    }
    if ([string]$approval.approverRole -cne 'owner') {
        $errors.Add('ownerApproval.approverRole must be owner.')
    }
    if (-not (Test-LexiQuestPrivateEvidenceReference `
        -Value $approval.evidenceRef `
        -ExpectedKind 'owner-approval' `
        -PrivateEvidenceDirectory $PrivateEvidenceDirectory `
        -TrustedEvidencePublicKeyPath $TrustedEvidencePublicKeyPath `
        -ExpectedSourceCommit $sourceCommit `
        -ExpectedApkSha256 $artifactApk `
        -RequireSourceExport `
        -AllowedOrigins @('owner-attestation') `
        -NowUtc $NowUtc `
        -ExpectedPayload ([pscustomobject][ordered]@{
            approved = $approval.approved
            apkSha256 = $approval.apkSha256
            sourceCommit = $approval.sourceCommit
            signingCertificateSha256 =
                $approval.signingCertificateSha256
            modelSha256 = $approval.modelSha256
            versionName = $approval.versionName
            versionCode = $approval.versionCode
            buildId = $approval.buildId
            approvedAtUtc = $approval.approvedAtUtc
            approverRole = $approval.approverRole
        })
    )) {
        $errors.Add(
            'ownerApproval.evidenceRef must be a verified owner-approval ' +
            'reference.'
        )
    }
    $approvalTime = ConvertFrom-LexiQuestStrictUtcTimestamp `
        $approval.approvedAtUtc
    if ($null -eq $approvalTime) {
        $errors.Add('ownerApproval.approvedAtUtc must be strict UTC.')
    } elseif (
        $approvalTime -lt $NowUtc.AddHours(-24) -or
        $approvalTime -gt $NowUtc.AddMinutes(5) -or
        ($null -ne $betaCompletedTime -and
            $approvalTime -lt $betaCompletedTime) -or
        ($null -ne $rollbackCompletedTime -and
            $approvalTime -lt $rollbackCompletedTime) -or
        ($null -ne $assembledTime -and $approvalTime -gt $assembledTime)
    ) {
        $errors.Add('owner approval is stale or predates required evidence.')
    }

    return $errors.ToArray()
}
