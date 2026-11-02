#Requires -Version 5.1
Set-StrictMode -Version 3.0

function Assert-LexiQuestCommercialKeys {
    param([object]$Value, [string[]]$Names, [string]$Context)
    if ($null -eq $Value -or $Value -isnot [pscustomobject]) {
        throw "$Context must be a JSON object."
    }
    $actual = @($Value.PSObject.Properties.Name)
    if ($actual.Count -ne $Names.Count -or @($actual | Where-Object { $_ -cnotin $Names }).Count -gt 0) {
        throw "$Context contains missing or unsupported fields."
    }
}

function Assert-LexiQuestCommercialCode {
    param([object]$Value, [string]$Context)
    if ($Value -isnot [string] -or $Value -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' -or $Value -match '(?i)placeholder|owner_config|pending|todo|synthetic|example') {
        throw "$Context must be an explicit product-policy identifier."
    }
}

function ConvertTo-LexiQuestPublicOrigin {
    param([object]$Value, [string]$Context)
    $uri = $null
    if ($Value -isnot [string] -or -not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri)) {
        throw "$Context must be a public HTTPS origin."
    }
    $hostName = $uri.IdnHost.TrimEnd('.').ToLowerInvariant()
    if ($uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -ne '/' -or [Uri]::CheckHostName($hostName) -ne [UriHostNameType]::Dns -or $hostName -notmatch '\.' -or $hostName -match '(?i)(^|\.)(localhost|example\.(com|org|net))$|\.(local|localhost|localdomain|lan|home|internal|test|invalid|example)$') {
        throw "$Context must be a public HTTPS origin without credentials, path, query or fragment."
    }
    $port = if ($uri.IsDefaultPort) { '' } else { ':' + $uri.Port }
    return 'https://' + $hostName + $port + '/'
}

function Read-LexiQuestReleaseConfiguration {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-Item -LiteralPath $Path).Length -gt 65536) {
        throw 'A bounded public release configuration file is required.'
    }
    try { $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'Release configuration must be valid JSON.' }
    Assert-LexiQuestCommercialKeys $raw @('schemaVersion', 'packageName', 'version', 'minimumPreviousVersionCode', 'aiApiUrl', 'voiceMode', 'voiceApiUrl', 'cloudSyncEnabled', 'contentReportsEnabled', 'accountDeletionRecoveryRetentionHours', 'billing') 'Release configuration'
    if (($raw.schemaVersion -isnot [int] -and $raw.schemaVersion -isnot [long]) -or $raw.schemaVersion -ne 1 -or $raw.packageName -cne 'com.lexiquest.app') {
        throw 'Release configuration schema or Android package is unsupported.'
    }
    $version = [string]$raw.version
    if ($raw.version -isnot [string] -or $version -cnotmatch '^\d+\.\d+\.\d+\+([1-9]\d*)$') {
        throw 'Release configuration version must include a positive Android version code.'
    }
    $versionCode = 0L
    if (-not [long]::TryParse($Matches[1], [ref]$versionCode) -or $versionCode -gt 2147483647) {
        throw 'Release configuration Android version code is out of range.'
    }
    $previous = $raw.minimumPreviousVersionCode
    if (($previous -isnot [int] -and $previous -isnot [long]) -or $previous -lt 18 -or $versionCode -le $previous) {
        throw 'Release version must advance beyond the declared prior version and retained signed baseline 18.'
    }
    foreach ($name in @('cloudSyncEnabled', 'contentReportsEnabled')) {
        if ($raw.$name -isnot [bool]) { throw "$name must be a JSON boolean." }
    }
    $deletionRetention = $raw.accountDeletionRecoveryRetentionHours
    if (($deletionRetention -isnot [int] -and $deletionRetention -isnot [long]) -or $deletionRetention -lt 1 -or $deletionRetention -gt 720) {
        throw 'Account deletion recovery retention must be an integer from 1 to 720 hours.'
    }
    $aiOrigin = ConvertTo-LexiQuestPublicOrigin $raw.aiApiUrl 'AI API'
    if ($raw.voiceMode -cnotin @('native', 'remote')) { throw 'voiceMode must be native or remote.' }
    $voiceOrigin = $null
    if ($raw.voiceMode -eq 'remote') {
        $voiceOrigin = ConvertTo-LexiQuestPublicOrigin $raw.voiceApiUrl 'Voice API'
    } elseif ($null -ne $raw.voiceApiUrl) {
        throw 'Native voice configuration must not contain a remote Voice API origin.'
    }
    Assert-LexiQuestCommercialKeys $raw.billing @('enabled', 'policyRevision', 'products') 'Billing configuration'
    if ($raw.billing.enabled -isnot [bool] -or -not $raw.billing.enabled) {
        throw 'Public managed-AI membership must be explicitly enabled.'
    }
    Assert-LexiQuestCommercialCode $raw.billing.policyRevision 'Billing policy revision'
    if ($raw.billing.products -isnot [array] -or $raw.billing.products.Count -lt 1 -or $raw.billing.products.Count -gt 32) {
        throw 'Billing configuration must contain 1..32 store product/base-plan mappings.'
    }
    $products = [System.Collections.Generic.SortedDictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($product in $raw.billing.products) {
            Assert-LexiQuestCommercialKeys $product @('productId', 'basePlanId', 'entitlements', 'dailyManagedUnits') 'Billing product'
            Assert-LexiQuestCommercialCode $product.productId 'Product ID'
            Assert-LexiQuestCommercialCode $product.basePlanId 'Base-plan ID'
            $key = "$($product.productId)/$($product.basePlanId)"
            if ($products.ContainsKey($key)) { throw 'Duplicate billing product/base-plan mapping.' }
            if ($product.entitlements -isnot [array] -or $product.entitlements.Count -ne 1 -or $product.entitlements[0] -cne 'managedContent') {
                throw 'Commercial membership currently supports only managedContent.'
            }
            $units = $product.dailyManagedUnits
            if (($units -isnot [int] -and $units -isnot [long]) -or $units -lt 1 -or $units -gt 1000000) {
                throw 'Managed-AI product quota must be an integer from 1 to 1000000.'
            }
            $products.Add($key, [ordered]@{ productId = $product.productId; basePlanId = $product.basePlanId; entitlements = @('managedContent'); dailyManagedUnits = $units })
    }
    $value = [pscustomobject][ordered]@{
        schemaVersion = 1
        packageName = 'com.lexiquest.app'
        version = $version
        minimumPreviousVersionCode = $previous
        aiApiUrl = $aiOrigin
        voiceMode = $raw.voiceMode
        voiceApiUrl = $voiceOrigin
        cloudSyncEnabled = $raw.cloudSyncEnabled
        contentReportsEnabled = $raw.contentReportsEnabled
        accountDeletionRecoveryRetentionHours = $deletionRetention
        billing = [ordered]@{ enabled = $true; policyRevision = $raw.billing.policyRevision; products = @($products.Values) }
    }
    $json = $value | ConvertTo-Json -Depth 8 -Compress
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { $sha = [BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
    return [pscustomobject]@{ Value = $value; Json = $json; Sha256 = $sha }
}

function Get-LexiQuestReleaseBuildId {
    param([string]$SourceCommit, [string]$ConfigurationSha256)
    if ($SourceCommit -cnotmatch '^[a-f0-9]{40}$' -or $ConfigurationSha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Source and configuration identities must be full lowercase hashes.' }
    return "$SourceCommit-$ConfigurationSha256"
}

function Get-LexiQuestReleaseDartDefines {
    param([Parameter(Mandatory)][object]$Configuration, [Parameter(Mandatory)][string]$SourceCommit)
    $value = $Configuration.Value
    $buildId = Get-LexiQuestReleaseBuildId $SourceCommit $Configuration.Sha256
    $defines = @(
        "--dart-define=LEXIQUEST_CLOUD_SYNC_ENABLED=$($value.cloudSyncEnabled.ToString().ToLowerInvariant())"
        '--dart-define=LEXIQUEST_BILLING_ENABLED=true'
        "--dart-define=LEXIQUEST_CONTENT_REPORTS_ENABLED=$($value.contentReportsEnabled.ToString().ToLowerInvariant())"
        '--dart-define=LEXIQUEST_ACCOUNT_DELETION_ENABLED=true'
        '--dart-define=LEXIQUEST_ACCOUNT_DELETION_SERVER_EXPORT_AUTHORITY_CONFIGURED=true'
        "--dart-define=LEXIQUEST_ACCOUNT_DELETION_RECOVERY_RETENTION_HOURS=$($value.accountDeletionRecoveryRetentionHours)"
        "--dart-define=LEXIQUEST_AI_API_URL=$($value.aiApiUrl)"
        "--dart-define=LEXIQUEST_VERSION=$($value.version)"
        "--dart-define=LEXIQUEST_BUILD_ID=$buildId"
    )
    if ($value.voiceMode -eq 'remote') { $defines += "--dart-define=LEXIQUEST_VOICE_API_URL=$($value.voiceApiUrl)" }
    return $defines
}

function Test-LexiQuestReleaseConfigurationBinding {
    param([string]$PackagePath, [object]$Manifest)
    if ([string]$Manifest.releaseProfile -ne 'publicProduction') { return @() }
    try {
        if (-not $Manifest.PSObject.Properties['configuration']) { throw 'Commercial package configuration binding is required.' }
        Assert-LexiQuestCommercialKeys $Manifest.configuration @('path', 'sha256') 'Packaged configuration binding'
        if ($Manifest.configuration.path -cne 'release-configuration.json' -or $Manifest.configuration.sha256 -cnotmatch '^[a-f0-9]{64}$') {
            throw 'Commercial package configuration path or SHA-256 is invalid.'
        }
        $path = Get-LexiQuestContainedPath -Path $Manifest.configuration.path -RootPath $PackagePath
        $configuration = Read-LexiQuestReleaseConfiguration -Path $path
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -cne $Manifest.configuration.sha256 -or $configuration.Sha256 -cne $Manifest.configuration.sha256) {
            throw 'Packaged release configuration SHA-256 does not match its canonical manifest binding.'
        }
        $value = $configuration.Value
        if ($Manifest.artifact.packageName -cne $value.packageName -or $Manifest.artifact.versionName -cne $value.version.Split('+')[0] -or [string]$Manifest.artifact.versionCode -cne $value.version.Split('+')[1]) {
            throw 'Commercial configuration package/version does not match the artifact.'
        }
        $expectedBuildId = Get-LexiQuestReleaseBuildId -SourceCommit $Manifest.sourceCommit -ConfigurationSha256 $configuration.Sha256
        if ($Manifest.artifact.buildId -cne $expectedBuildId) { throw 'Commercial artifact build ID does not bind source and configuration.' }
    }
    catch { return @($_.Exception.Message) }
    return @()
}

function Get-LexiQuestRequiredBillingJourneys {
    return @('localizedOffers', 'purchasePending', 'purchaseVerified', 'nativeCompletion', 'restore', 'accountSwitch', 'cancellationRevocation', 'rtdn', 'quotaExhaustionRetry', 'accountExportDeletion', 'upgradeMigration')
}

function ConvertFrom-LexiQuestCommercialJson {
    param([Parameter(Mandatory)][string]$Text)
    Add-Type -AssemblyName System.Runtime.Serialization -ErrorAction Stop
    $quotas = [Xml.XmlDictionaryReaderQuotas]::new()
    $quotas.MaxDepth = 64
    $quotas.MaxStringContentLength = 65536
    $quotas.MaxArrayLength = 65536
    $quotas.MaxNameTableCharCount = 65536
    $reader = [Runtime.Serialization.Json.JsonReaderWriterFactory]::CreateJsonReader([Text.Encoding]::UTF8.GetBytes($Text), $quotas)
    $objects = @{}
    try {
        while ($reader.Read()) {
            if ($reader.NodeType -eq [Xml.XmlNodeType]::Element) {
                $parentDepth = $reader.Depth - 1
                if ($objects.ContainsKey($parentDepth)) {
                    $name = if ($reader.NamespaceURI -ceq 'item') { $reader.GetAttribute('item') } else { $reader.LocalName }
                    if (-not $objects[$parentDepth].Add($name)) { throw 'Commercial evidence JSON must not contain duplicate object member names.' }
                }
                if ($reader.GetAttribute('type') -ceq 'object') { $objects[$reader.Depth] = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal) }
            } elseif ($reader.NodeType -eq [Xml.XmlNodeType]::EndElement) {
                $objects.Remove($reader.Depth)
            }
        }
    } finally { $reader.Dispose() }
    $jsonOptions = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $jsonOptions.DateKind = 'String' }
    return $Text | ConvertFrom-Json @jsonOptions -ErrorAction Stop
}

function Read-LexiQuestCommercialObservation {
    param([object]$Reference, [string]$EvidenceRootPath, [string]$Context)
    $path = Resolve-LexiQuestEvidenceReference -Reference $Reference -EvidenceRootPath $EvidenceRootPath
    try { return ConvertFrom-LexiQuestCommercialJson (Get-Content -LiteralPath $path -Raw -Encoding utf8) }
    catch { throw "$Context must be valid JSON." }
}

function Assert-LexiQuestObservedProducts {
    param([object]$Products, [object]$Expected)
    if ($Products -isnot [array]) { throw 'Observed billing products must be a JSON list.' }
    $actual = @($Products)
    $expectedProducts = @($Expected)
    if ($actual.Count -ne $expectedProducts.Count) { throw 'Observed billing product mappings do not match configuration.' }
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($product in $actual) {
        Assert-LexiQuestCommercialKeys $product @('productId', 'basePlanId', 'entitlements', 'dailyManagedUnits') 'Observed billing product'
        Assert-LexiQuestCommercialCode $product.productId 'Observed product ID'
        Assert-LexiQuestCommercialCode $product.basePlanId 'Observed base-plan ID'
        $matches = @($expectedProducts | Where-Object { $_.productId -ceq $product.productId -and $_.basePlanId -ceq $product.basePlanId })
        if (-not $seen.Add("$($product.productId)/$($product.basePlanId)") -or $matches.Count -ne 1 -or ($product.dailyManagedUnits -isnot [int] -and $product.dailyManagedUnits -isnot [long]) -or $product.dailyManagedUnits -ne $matches[0].dailyManagedUnits -or $product.entitlements -isnot [array] -or $product.entitlements.Count -ne 1 -or $product.entitlements[0] -cne 'managedContent') {
            throw 'Observed billing product mappings do not match configuration.'
        }
    }
}

function Assert-LexiQuestObservedBackendPolicyRecord {
    param([object]$Observation, [object]$Configuration)
    Assert-LexiQuestCommercialKeys $Observation @('recordType', 'origin', 'path', 'observedAtUtc', 'httpStatus', 'responseEvidenceRef') 'Backend policy observation'
    $backendOrigin = ConvertTo-LexiQuestPublicOrigin $Observation.origin 'Observed backend'
    $observed = [DateTimeOffset]::MinValue
    if ($Observation.recordType -cne 'lexiquestManagedBackendPolicyObservation' -or $backendOrigin -cne $Configuration.Value.aiApiUrl -or $Observation.path -cne '/v1/billing/catalog' -or ($Observation.httpStatus -isnot [int] -and $Observation.httpStatus -isnot [long]) -or $Observation.httpStatus -ne 200 -or $Observation.observedAtUtc -isnot [string] -or $Observation.observedAtUtc -notmatch '(Z|[+-]\d\d:\d\d)$' -or -not [DateTimeOffset]::TryParse($Observation.observedAtUtc, [ref]$observed) -or $observed -gt [DateTimeOffset]::UtcNow.AddMinutes(5) -or $observed -lt [DateTimeOffset]::UtcNow.AddHours(-24)) {
        throw 'Backend policy observation must be a recent successful catalog read from the configured origin.'
    }
    if (-not (Test-LexiQuestEvidenceReferenceShape $Observation.responseEvidenceRef)) { throw 'Backend catalog response must be hash-bound.' }
}

function Assert-LexiQuestObservedBackendCatalog {
    param([object]$Catalog, [object]$Configuration)
    Assert-LexiQuestCommercialKeys $Catalog @('schemaVersion', 'packageName', 'policyRevision', 'accountIdentifier', 'managedContentRequired', 'products') 'Observed backend catalog'
    if (($Catalog.schemaVersion -isnot [int] -and $Catalog.schemaVersion -isnot [long]) -or $Catalog.schemaVersion -ne 2 -or $Catalog.packageName -isnot [string] -or $Catalog.packageName -cne $Configuration.Value.packageName -or $Catalog.policyRevision -isnot [string] -or $Catalog.policyRevision -cne $Configuration.Value.billing.policyRevision -or $Catalog.accountIdentifier -isnot [string] -or $Catalog.accountIdentifier -cnotmatch '^[a-f0-9]{64}$' -or $Catalog.managedContentRequired -isnot [bool] -or -not $Catalog.managedContentRequired) {
        throw 'Observed backend package, policy or managed-content enforcement does not match configuration.'
    }
    Assert-LexiQuestObservedProducts $Catalog.products $Configuration.Value.billing.products
}

function Test-LexiQuestCommercialAcceptance {
    param([object]$Configuration, [object]$Manifest, [object]$Controls, [string]$EvidenceRootPath)
    $errors = [System.Collections.Generic.List[string]]::new()
    try {
        if (-not $Controls.PSObject.Properties['commercialAcceptance']) { throw 'Commercial membership acceptance evidence is required.' }
        $acceptance = $Controls.commercialAcceptance
        Assert-LexiQuestCommercialKeys $acceptance @('configurationSha256', 'policyRevision', 'products', 'artifact', 'journeys', 'backendPolicyEvidenceRef') 'Commercial acceptance'
        if ($acceptance.configurationSha256 -cne $Configuration.Sha256 -or $acceptance.policyRevision -cne $Configuration.Value.billing.policyRevision) {
            throw 'Commercial acceptance does not match configuration or billing policy.'
        }
        Assert-LexiQuestObservedProducts $acceptance.products $Configuration.Value.billing.products
        if (-not (Test-LexiQuestEvidenceReferenceShape $acceptance.backendPolicyEvidenceRef)) { throw 'Hash-bound backend policy observation is required.' }
        $backend = Read-LexiQuestCommercialObservation $acceptance.backendPolicyEvidenceRef $EvidenceRootPath 'Backend policy observation'
        Assert-LexiQuestObservedBackendPolicyRecord $backend $Configuration
        $catalog = Read-LexiQuestCommercialObservation $backend.responseEvidenceRef $EvidenceRootPath 'Observed backend catalog'
        Assert-LexiQuestObservedBackendCatalog $catalog $Configuration
        Assert-LexiQuestCommercialKeys $acceptance.artifact @('apkSha256', 'aabSha256', 'signingCertificateSha256', 'packageName', 'versionName', 'versionCode', 'buildId') 'Commercial acceptance artifact'
        foreach ($field in @('apkSha256', 'aabSha256', 'signingCertificateSha256', 'packageName', 'versionName', 'versionCode', 'buildId')) {
            if ([string]$acceptance.artifact.$field -cne [string]$Manifest.artifact.$field) { throw "Commercial acceptance artifact.$field does not match the candidate." }
        }
        Assert-LexiQuestCommercialKeys $acceptance.journeys @(Get-LexiQuestRequiredBillingJourneys) 'Commercial billing journeys'
        foreach ($name in Get-LexiQuestRequiredBillingJourneys) {
            $journey = $acceptance.journeys.$name
            Assert-LexiQuestCommercialKeys $journey @('status', 'evidenceRef') "Billing journey $name"
            if ($journey.status -cne 'pass' -or -not (Test-LexiQuestEvidenceReferenceShape $journey.evidenceRef)) {
                throw "Billing journey $name requires passed, hash-bound evidence."
            }
            $record = Read-LexiQuestCommercialObservation $journey.evidenceRef $EvidenceRootPath "Billing journey record $name"
            Assert-LexiQuestCommercialKeys $record @('recordType', 'journey', 'sourceCommit', 'configurationSha256', 'policyRevision', 'artifact', 'observedAtUtc', 'environment', 'result', 'observationsEvidenceRef') "Billing journey record $name"
            if ($record.recordType -cne 'lexiquestBillingJourney' -or $record.journey -cne $name -or $record.result -cne 'pass' -or $record.environment -cnotin @('playLicenseTest', 'production') -or $record.sourceCommit -cne $Manifest.sourceCommit -or $record.configurationSha256 -cne $Configuration.Sha256 -or $record.policyRevision -cne $Configuration.Value.billing.policyRevision) {
                throw "Billing journey record $name does not establish this candidate's observed result."
            }
            Assert-LexiQuestCommercialKeys $record.artifact @('apkSha256', 'aabSha256', 'signingCertificateSha256', 'packageName', 'versionName', 'versionCode', 'buildId') "Billing journey artifact $name"
            foreach ($field in @('apkSha256', 'aabSha256', 'signingCertificateSha256', 'packageName', 'versionName', 'versionCode', 'buildId')) {
                if ([string]$record.artifact.$field -cne [string]$Manifest.artifact.$field) { throw "Billing journey record $name belongs to another artifact." }
            }
            $observed = [DateTimeOffset]::MinValue
            if ($record.observedAtUtc -isnot [string] -or $record.observedAtUtc -notmatch '(Z|[+-]\d\d:\d\d)$' -or -not [DateTimeOffset]::TryParse($record.observedAtUtc, [ref]$observed) -or $observed -gt [DateTimeOffset]::UtcNow.AddMinutes(5)) {
                throw "Billing journey record $name has an invalid observation time."
            }
            if (-not (Test-LexiQuestEvidenceReferenceShape $record.observationsEvidenceRef)) { throw "Billing journey record $name requires hash-bound observations." }
            $null = Resolve-LexiQuestEvidenceReference -Reference $record.observationsEvidenceRef -EvidenceRootPath $EvidenceRootPath
        }
    }
    catch { $errors.Add($_.Exception.Message) }
    return $errors.ToArray()
}
