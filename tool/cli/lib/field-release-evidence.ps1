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

function ConvertTo-NormalizedSha256 {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return ''
    }
    return ([string]$Value).Replace(':', '').Trim().ToUpperInvariant()
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
        [string]$ParticipantPackagePath
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $shaPattern = '^[A-F0-9]{64}$'
    $actualApk = ConvertTo-NormalizedSha256 $ActualApkSha256
    $actualCertificate = ConvertTo-NormalizedSha256 $ActualCertificateSha256

    if ([int]$Evidence.schemaVersion -ne 1) {
        $errors.Add('schemaVersion must be 1.')
    }
    if ([string]::IsNullOrWhiteSpace([string]$Evidence.releaseId)) {
        $errors.Add('releaseId is required.')
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
    if ([string]$Evidence.cloudControls.billingMode -eq 'noBillingAccount') {
        if (
            $Evidence.cloudControls.budgetAlertsConfigured -ne $false -or
            $Evidence.cloudControls.budgetAlertsNotApplicable -ne $true
        ) {
            $errors.Add(
                'No-billing mode requires alerts=false and notApplicable=true.'
            )
        }
    } elseif ([string]$Evidence.cloudControls.billingMode -eq 'budgeted') {
        if (
            $Evidence.cloudControls.budgetAlertsConfigured -ne $true -or
            $Evidence.cloudControls.budgetAlertsNotApplicable -ne $false
        ) {
            $errors.Add(
                'Budgeted mode requires configured 50/80/100 alerts.'
            )
        }
    } else {
        $errors.Add(
            'cloudControls.billingMode must be budgeted or noBillingAccount.'
        )
    }
    foreach ($reference in @(
        'appCheckEvidenceRef',
        'budgetAlertsEvidenceRef',
        'assetLinksEvidenceRef',
        'cloudKillSwitchEvidenceRef'
    )) {
        if (
            [string]::IsNullOrWhiteSpace(
                [string]$Evidence.cloudControls.$reference
            )
        ) {
            $errors.Add("cloudControls.$reference is required.")
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
        $documentPath = Join-Path $ParticipantPackagePath $relative
        if (-not (Test-Path -LiteralPath $documentPath -PathType Leaf)) {
            $errors.Add("participant document is missing: $relative")
        }
    }
    if ([int]$package.consentVersion -ne 1) {
        $errors.Add('participantPackage.consentVersion must be 1.')
    }
    foreach ($channel in @(
        'feedbackChannelRef',
        'supportChannelRef',
        'researchProtocolRef'
    )) {
        $value = [string]$package.$channel
        if (
            [string]::IsNullOrWhiteSpace($value) -or
            $value -match (
                '(?i)placeholder|owner_config|pending|todo|missing|' +
                'draft|unapproved|not.?configured|<.+>'
            ) -or
            (
                $channel -in @('supportChannelRef', 'researchProtocolRef') -and
                $value -notmatch '^private:'
            )
        ) {
            $errors.Add(
                "participantPackage.$channel must reference a real private channel."
            )
        }
    }

    $devices = @($Evidence.devices)
    if ($devices.Count -ne 2) {
        $errors.Add('Exactly two physical Android device records are required (mid and high tier).')
    }
    $tiers = @($devices | ForEach-Object { [string]$_.tier })
    foreach ($tier in @('mid', 'high')) {
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
        if ([string]::IsNullOrWhiteSpace([string]$device.recordedAtUtc)) {
            $errors.Add("$label device recordedAtUtc is required.")
        }
        if ($device.device.physical -ne $true) {
            $errors.Add("$label evidence must be from a physical device.")
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

        foreach ($journeyName in $requiredJourneys) {
            $journey = $device.journeys.$journeyName
            if ([string]$journey.status -ne 'pass') {
                $errors.Add("$label journey $journeyName must pass.")
            }
            if ([string]::IsNullOrWhiteSpace([string]$journey.evidenceRef)) {
                $errors.Add("$label journey $journeyName needs an evidenceRef.")
            }
        }

        $cpu = $device.benchmarks.cpuXnnpack
        if (
            [string]$cpu.status -ne 'pass' -or
            [string]$cpu.delegate -ne 'xnnpack' -or
            [int]$cpu.iterations -lt 10 -or
            [double]$cpu.medianLatencyMs -le 0 -or
            [string]::IsNullOrWhiteSpace([string]$cpu.evidenceRef)
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
                [string]::IsNullOrWhiteSpace([string]$gpu.evidenceRef)
            ) {
                $errors.Add(
                    "$label GPU pass requires allowlisting and >=10 iterations."
                )
            }
        } elseif ([string]$gpu.status -eq 'notApplicable') {
            if (
                $gpu.allowlisted -ne $false -or
                [string]::IsNullOrWhiteSpace([string]$gpu.reason) -or
                [string]::IsNullOrWhiteSpace([string]$gpu.evidenceRef)
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
            [double]$endurance.durationMinutes -lt 30 -or
            [int]$endurance.crashCount -ne 0 -or
            [int]$endurance.anrCount -ne 0 -or
            [string]::IsNullOrWhiteSpace([string]$endurance.evidenceRef)
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
            if ($null -eq $endurance.$metric) {
                $errors.Add("$label endurance.$metric is required.")
            }
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
    foreach ($field in @('approvedAtUtc', 'approverRole', 'evidenceRef')) {
        if ([string]::IsNullOrWhiteSpace([string]$approval.$field)) {
            $errors.Add("ownerApproval.$field is required.")
        }
    }

    return $errors.ToArray()
}
