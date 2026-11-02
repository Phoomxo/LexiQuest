#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$helper = Join-Path $repoRoot 'tool/cli/lib/commercial-release-configuration.ps1'
if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) {
    throw 'Commercial release configuration boundary is not implemented.'
}
. (Join-Path $repoRoot 'tool/cli/lib/field-release-evidence.ps1')
$script:passed = 0
$script:failed = 0
function Assert-True([bool]$Value, [string]$Message) {
    if ($Value) { $script:passed++ } else {
        $script:failed++
        Write-Host "FAIL: $Message"
    }
}
function New-Configuration {
    return [ordered]@{
        schemaVersion = 1
        packageName = 'com.lexiquest.app'
        version = '1.0.0+19'
        minimumPreviousVersionCode = 18
        aiApiUrl = 'https://api.lexiquest.app'
        voiceMode = 'native'
        voiceApiUrl = $null
        cloudSyncEnabled = $true
        contentReportsEnabled = $true
        accountDeletionRecoveryRetentionHours = 168
        billing = [ordered]@{
            enabled = $true
            policyRevision = 'managed-ai-v1'
            products = @([ordered]@{
                productId = 'lexiquest_ai_monthly'
                basePlanId = 'monthly'
                entitlements = @('managedContent')
                dailyManagedUnits = 10
            })
        }
    }
}
$taskTempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$taskTemp = Join-Path $taskTempBase ('lexiquest-commercial-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskTemp | Out-Null
$configurationPath = Join-Path $taskTemp 'configuration.json'
function Read-Fixture([object]$Value) {
    [System.IO.File]::WriteAllText($configurationPath, ($Value | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
    return Read-LexiQuestReleaseConfiguration -Path $configurationPath
}
function Expect-Rejected([object]$Value, [string]$Message) {
    $rejected = $false
    try { $null = Read-Fixture $Value } catch { $rejected = $true }
    Assert-True $rejected $Message
}
try {
    $missingRetention = New-Configuration
    $missingRetention.Remove('accountDeletionRecoveryRetentionHours')
    Expect-Rejected $missingRetention 'public configuration requires an explicit account deletion recovery retention'
    $configuration = Read-Fixture (New-Configuration)
    Assert-True ($configuration.Value.aiApiUrl -eq 'https://api.lexiquest.app/') 'HTTPS origin is canonicalized'
    Assert-True ($configuration.Sha256 -match '^[a-f0-9]{64}$') 'canonical configuration has a full SHA-256'
    $same = Read-Fixture ($configuration.Json | ConvertFrom-Json)
    Assert-True ($same.Sha256 -eq $configuration.Sha256) 'canonical roundtrip retains identity'
    Assert-True ($same.Value.accountDeletionRecoveryRetentionHours -eq 168) 'canonical configuration retains the explicit seven-day deletion recovery policy'
    $idn = New-Configuration
    $idn.aiApiUrl = 'https://b' + [char]0x00fc + 'cher.lexiquest.app/'
    Assert-True ((Read-Fixture $idn).Value.aiApiUrl -eq 'https://xn--bcher-kva.lexiquest.app/') 'IDN origins use deterministic ASCII bytes'
    $multiple = New-Configuration
    $multiple.billing.products = @(
        [ordered]@{ productId = 'lexiquest_ai_I'; basePlanId = 'monthly'; entitlements = @('managedContent'); dailyManagedUnits = 10 },
        [ordered]@{ productId = 'lexiquest_ai_i'; basePlanId = 'monthly'; entitlements = @('managedContent'); dailyManagedUnits = 10 }
    )
    $priorCulture = [Threading.Thread]::CurrentThread.CurrentCulture
    try {
        [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('en-US')
        $englishHash = (Read-Fixture $multiple).Sha256
        [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('tr-TR')
        Assert-True ((Read-Fixture $multiple).Sha256 -ceq $englishHash) 'product ordering is ordinal across process cultures'
    } finally { [Threading.Thread]::CurrentThread.CurrentCulture = $priorCulture }
    $sourceCommit = 'a' * 40
    $defines = @(Get-LexiQuestReleaseDartDefines -Configuration $configuration -SourceCommit $sourceCommit)
    $buildId = Get-LexiQuestReleaseBuildId -SourceCommit $sourceCommit -ConfigurationSha256 $configuration.Sha256
    Assert-True ($buildId -eq "$sourceCommit-$($configuration.Sha256)") 'build identity binds full source and full configuration hash'
    Assert-True ($defines -contains "--dart-define=LEXIQUEST_BUILD_ID=$buildId") 'artifact receives the bound build identity'
    Assert-True ($defines -contains '--dart-define=LEXIQUEST_AI_API_URL=https://api.lexiquest.app/') 'artifact receives managed AI origin'
    Assert-True ($defines -contains '--dart-define=LEXIQUEST_BILLING_ENABLED=true') 'managed membership is composed explicitly'
    foreach ($deletionDefine in @(
        '--dart-define=LEXIQUEST_ACCOUNT_DELETION_ENABLED=true',
        '--dart-define=LEXIQUEST_ACCOUNT_DELETION_SERVER_EXPORT_AUTHORITY_CONFIGURED=true',
        '--dart-define=LEXIQUEST_ACCOUNT_DELETION_RECOVERY_RETENTION_HOURS=168'
    )) {
        Assert-True (@($defines | Where-Object { $_ -ceq $deletionDefine }).Count -eq 1) 'public builds compose each required account deletion capability exactly once'
    }
    Assert-True (@($defines | Where-Object { $_ -like '*VOICE_API_URL*' }).Count -eq 0) 'native voice never receives a fake remote endpoint'
    Assert-True (@($defines | Where-Object { $_ -match 'APP_CHECK_DEBUG|RESEARCH' }).Count -eq 0) 'commercial configuration cannot activate debug App Check or Research'
    $changed = New-Configuration
    $changed.billing.products[0].dailyManagedUnits = 11
    $changed = Read-Fixture $changed
    Assert-True ($changed.Sha256 -ne $configuration.Sha256) 'quota change changes release identity'
    $retentionChanged = New-Configuration
    $retentionChanged.accountDeletionRecoveryRetentionHours = 169
    $retentionChanged = Read-Fixture $retentionChanged
    Assert-True ($retentionChanged.Sha256 -cne $configuration.Sha256) 'retention-only change changes canonical release configuration identity'
    Assert-True ((Get-LexiQuestReleaseBuildId -SourceCommit $sourceCommit -ConfigurationSha256 $retentionChanged.Sha256) -cne $buildId) 'retention-only change changes the source-bound artifact build identity'
    foreach ($hours in @(1, 720)) {
        $boundary = New-Configuration
        $boundary.accountDeletionRecoveryRetentionHours = $hours
        $boundary = Read-Fixture $boundary
        Assert-True ($boundary.Value.accountDeletionRecoveryRetentionHours -eq $hours -and @(Get-LexiQuestReleaseDartDefines -Configuration $boundary -SourceCommit $sourceCommit) -contains "--dart-define=LEXIQUEST_ACCOUNT_DELETION_RECOVERY_RETENTION_HOURS=$hours") 'valid deletion retention boundaries compose the exact integer hours'
    }
    foreach ($invalidHours in @($null, $false, $true, '168', 168.5, 0, -1, 721)) {
        $bad = New-Configuration
        $bad.accountDeletionRecoveryRetentionHours = $invalidHours
        Expect-Rejected $bad 'deletion retention rejects missing values, booleans, strings, fractional numbers and out-of-range hours'
    }
    $decimalRetentionJson = ((New-Configuration) | ConvertTo-Json -Depth 8) -replace '("accountDeletionRecoveryRetentionHours"\s*:\s*)168\b', '${1}168.0'
    [System.IO.File]::WriteAllText($configurationPath, $decimalRetentionJson, [System.Text.UTF8Encoding]::new($false))
    $decimalRejected = $false
    try { $null = Read-LexiQuestReleaseConfiguration $configurationPath } catch { $decimalRejected = $true }
    Assert-True $decimalRejected 'deletion retention rejects JSON decimal notation even when its numeric value is a whole number'
    $bad = New-Configuration
    $bad['accountDeletion'] = [ordered]@{ enabled = $false }
    Expect-Rejected $bad 'public deletion requirements cannot be replaced by unsupported optional capability knobs'
    $remote = New-Configuration
    $remote.voiceMode = 'remote'
    $remote.voiceApiUrl = 'https://voice.lexiquest.app/'
    $remote = Read-Fixture $remote
    Assert-True (@(Get-LexiQuestReleaseDartDefines -Configuration $remote -SourceCommit $sourceCommit) -contains '--dart-define=LEXIQUEST_VOICE_API_URL=https://voice.lexiquest.app/') 'explicit remote voice receives its own endpoint'

    foreach ($origin in @('http://api.lexiquest.app', 'https://localhost', 'https://localhost.', 'https://127.0.0.1', 'https://10.0.0.1', 'https://api.example.com', 'https://api.example.com.', 'https://api.invalid', 'https://api.test', 'https://api.local', 'https://api.lexiquest.app/path', 'https://api.lexiquest.app/?key=synthetic', 'https://user:synthetic@api.lexiquest.app')) {
        $bad = New-Configuration
        $bad.aiApiUrl = $origin
        Expect-Rejected $bad 'production rejects insecure, reserved, private or non-origin endpoints'
    }
    $bad = New-Configuration; $bad['password'] = 'synthetic-only'; Expect-Rejected $bad 'unknown top-level secret fields are rejected'
    $bad = New-Configuration; $bad.billing['secret'] = 'synthetic-only'; Expect-Rejected $bad 'unknown nested secret fields are rejected'
    $bad = New-Configuration; $bad.version = '1.0.0+18'; Expect-Rejected $bad 'candidate cannot reuse the declared prior version code'
    $bad = New-Configuration; $bad.minimumPreviousVersionCode = 1; Expect-Rejected $bad 'retained signed baseline cannot be lowered'
    $bad = New-Configuration; $bad.packageName = 'com.example.app'; Expect-Rejected $bad 'package identity is fixed'
    $bad = New-Configuration; $bad.voiceApiUrl = 'https://voice.lexiquest.app'; Expect-Rejected $bad 'native voice cannot silently configure remote speech'
    $bad = New-Configuration; $bad.voiceMode = 'remote'; Expect-Rejected $bad 'remote voice requires an origin'
    $bad = New-Configuration; $bad.billing.enabled = $false; Expect-Rejected $bad 'commercial managed subscription cannot silently disable membership'
    $bad = New-Configuration; $bad.billing.products[0].dailyManagedUnits = 0; Expect-Rejected $bad 'paid managed AI cannot advertise zero quota'
    $bad = New-Configuration; $bad.billing.products[0].dailyManagedUnits = 10.5; Expect-Rejected $bad 'quota must be an integer'
    $bad = New-Configuration; $bad.billing.products[0].entitlements = @('offlinePremium'); Expect-Rejected $bad 'commercial policy cannot promise an unimplemented premium gate'
    $bad = New-Configuration; $bad.billing.products = @($bad.billing.products[0], $bad.billing.products[0]); Expect-Rejected $bad 'duplicate store product/base-plan pairs are rejected'
    $bad = New-Configuration; $bad.contentReportsEnabled = 'true'; Expect-Rejected $bad 'capability flags must be JSON booleans'

    $null = Read-Fixture (New-Configuration)
    [System.IO.File]::WriteAllText($configurationPath, $configuration.Json, [System.Text.UTF8Encoding]::new($false))
    $packagedConfiguration = Join-Path $taskTemp 'release-configuration.json'
    Copy-Item -LiteralPath $configurationPath -Destination $packagedConfiguration
    $artifact = [pscustomobject]@{ apkSha256 = 'A' * 64; aabSha256 = 'B' * 64; signingCertificateSha256 = 'C' * 64; packageName = 'com.lexiquest.app'; versionName = '1.0.0'; versionCode = 19; buildId = $buildId }
    $manifest = [pscustomobject]@{ releaseProfile = 'publicProduction'; sourceCommit = $sourceCommit; artifact = $artifact; configuration = [pscustomobject]@{ path = 'release-configuration.json'; sha256 = $configuration.Sha256 } }
    Assert-True (@(Test-LexiQuestReleaseConfigurationBinding -PackagePath $taskTemp -Manifest $manifest).Count -eq 0) 'packaged canonical configuration binds the candidate'
    Add-Content -LiteralPath $packagedConfiguration -Value ' '
    Assert-True (@(Test-LexiQuestReleaseConfigurationBinding -PackagePath $taskTemp -Manifest $manifest).Count -gt 0) 'even canonical-equivalent package tampering changes file identity'
    Copy-Item -LiteralPath $configurationPath -Destination $packagedConfiguration -Force
    $manifest.artifact.buildId = $sourceCommit
    Assert-True (@(Test-LexiQuestReleaseConfigurationBinding -PackagePath $taskTemp -Manifest $manifest).Count -gt 0) 'a source-only build cannot claim commercial configuration'
    $manifest.artifact.buildId = $buildId

    $observations = Join-Path $taskTemp 'synthetic-observations.txt'
    Set-Content -LiteralPath $observations -Value 'Synthetic fixture only; no merchant or device acceptance.'
    $observationRef = New-LexiQuestEvidenceReference -Path 'synthetic-observations.txt' -EvidenceRootPath $taskTemp
    $journeys = [ordered]@{}
    foreach ($name in Get-LexiQuestRequiredBillingJourneys) {
        $record = [ordered]@{ recordType = 'lexiquestBillingJourney'; journey = $name; sourceCommit = $sourceCommit; configurationSha256 = $configuration.Sha256; policyRevision = $configuration.Value.billing.policyRevision; artifact = $artifact; observedAtUtc = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o'); environment = 'playLicenseTest'; result = 'pass'; observationsEvidenceRef = $observationRef }
        $recordPath = Join-Path $taskTemp ($name + '.json')
        [System.IO.File]::WriteAllText($recordPath, ($record | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
        $journeys[$name] = [pscustomobject]@{ status = 'pass'; evidenceRef = (New-LexiQuestEvidenceReference -Path ($name + '.json') -EvidenceRootPath $taskTemp) }
    }
    $backendCatalog = [pscustomobject]@{ schemaVersion = 2; packageName = 'com.lexiquest.app'; policyRevision = $configuration.Value.billing.policyRevision; accountIdentifier = 'a' * 64; managedContentRequired = $true; products = @($configuration.Value.billing.products) }
    $backendBaseline = $backendCatalog | ConvertTo-Json -Depth 8
    function Write-SyntheticBackendObservation([string]$Origin = 'https://api.lexiquest.app/') {
        [System.IO.File]::WriteAllText((Join-Path $taskTemp 'backend-response.json'), ($backendCatalog | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
        $record = [ordered]@{ recordType = 'lexiquestManagedBackendPolicyObservation'; origin = $Origin; path = '/v1/billing/catalog'; observedAtUtc = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o'); httpStatus = 200; responseEvidenceRef = (New-LexiQuestEvidenceReference -Path 'backend-response.json' -EvidenceRootPath $taskTemp) }
        [System.IO.File]::WriteAllText((Join-Path $taskTemp 'backend-policy.json'), ($record | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
        return New-LexiQuestEvidenceReference -Path 'backend-policy.json' -EvidenceRootPath $taskTemp
    }
    $controls = [pscustomobject]@{ commercialAcceptance = [pscustomobject]@{ configurationSha256 = $configuration.Sha256; policyRevision = $configuration.Value.billing.policyRevision; products = @($configuration.Value.billing.products); artifact = $artifact; journeys = [pscustomobject]$journeys; backendPolicyEvidenceRef = (Write-SyntheticBackendObservation) } }
    $controls = $controls | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $validErrors = @(Test-LexiQuestCommercialAcceptance -Configuration $configuration -Manifest $manifest -Controls $controls -EvidenceRootPath $taskTemp)
    if ($validErrors.Count -gt 0) { Write-Host ($validErrors -join '; ') }
    Assert-True ($validErrors.Count -eq 0) 'complete synthetic observations exercise the acceptance boundary'
    foreach ($invalid in @('origin', 'revision', 'quota', 'gate')) {
        $backendCatalog = $backendBaseline | ConvertFrom-Json
        $origin = 'https://api.lexiquest.app/'
        switch ($invalid) {
            'origin' { $origin = 'https://other.lexiquest.app/' }
            'revision' { $backendCatalog.policyRevision = 'different-policy' }
            'quota' { $backendCatalog.products[0].dailyManagedUnits = 11 }
            'gate' { $backendCatalog.managedContentRequired = $false }
        }
        $controls.commercialAcceptance.backendPolicyEvidenceRef = Write-SyntheticBackendObservation $origin
        Assert-True (@(Test-LexiQuestCommercialAcceptance -Configuration $configuration -Manifest $manifest -Controls $controls -EvidenceRootPath $taskTemp).Count -gt 0) "actual backend $invalid mismatch rejects otherwise matching acceptance"
    }
    $backendCatalog = $backendBaseline | ConvertFrom-Json
    $controls.commercialAcceptance.backendPolicyEvidenceRef = Write-SyntheticBackendObservation
    Assert-True (@(Test-LexiQuestCommercialAcceptance -Configuration $configuration -Manifest $manifest -Controls $controls -EvidenceRootPath $taskTemp).Count -eq 0) 'matching observed backend policy restores acceptance'
    $controls.commercialAcceptance.configurationSha256 = 'd' * 64
    Assert-True (@(Test-LexiQuestCommercialAcceptance -Configuration $configuration -Manifest $manifest -Controls $controls -EvidenceRootPath $taskTemp).Count -gt 0) 'acceptance from another configuration is rejected'
    $controls.commercialAcceptance.configurationSha256 = $configuration.Sha256
    $controls.commercialAcceptance.journeys.restore = $controls.commercialAcceptance.journeys.purchaseVerified
    Assert-True (@(Test-LexiQuestCommercialAcceptance -Configuration $configuration -Manifest $manifest -Controls $controls -EvidenceRootPath $taskTemp).Count -gt 0) 'a passed purchase cannot substitute for a restore observation'
    $controls.commercialAcceptance.journeys.restore = $journeys.restore
    $controls.commercialAcceptance.journeys.rtdn.status = 'pending'
    Assert-True (@(Test-LexiQuestCommercialAcceptance -Configuration $configuration -Manifest $manifest -Controls $controls -EvidenceRootPath $taskTemp).Count -gt 0) 'pending RTDN acceptance cannot pass'
    $controls.commercialAcceptance.journeys.rtdn.status = 'pass'
    Assert-True (@(Test-LexiQuestCommercialAcceptance -Configuration $configuration -Manifest $manifest -Controls $controls -EvidenceRootPath $taskTemp).Count -eq 0) 'restored candidate observations pass before raw-evidence tampering'
    Set-Content -LiteralPath $observations -Value 'tampered synthetic observations'
    Assert-True (@(Test-LexiQuestCommercialAcceptance -Configuration $configuration -Manifest $manifest -Controls $controls -EvidenceRootPath $taskTemp).Count -gt 0) 'raw observations are hash-bound instead of approved=true'

    $fakeBin = Join-Path $taskTemp 'bin'
    New-Item -ItemType Directory -Path $fakeBin | Out-Null
    $marker = Join-Path $taskTemp 'flutter-was-invoked.txt'
    [System.IO.File]::WriteAllText((Join-Path $fakeBin 'flutter.cmd'), "@echo off`r`necho called>`"$marker`"`r`nexit /b 99`r`n")
    $runner = (Get-Process -Id $PID).Path
    $packager = Join-Path $repoRoot 'tool/cli/package-field-release.ps1'
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $runner
    $start.Arguments = '-NoProfile -NonInteractive -File "' + $packager + '" -ReleaseProfile publicProduction -Version 1.0.0+19 -ConfigurationPath "' + $configurationPath + '" -OutputPath "' + (Join-Path $taskTemp 'output') + '"'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['PATH'] = $fakeBin + ';' + $env:PATH
    foreach ($invalidCapability in @('origin', 'deletionRetention')) {
        $bad = New-Configuration
        $expectedError = 'AI API must be a public HTTPS origin'
        if ($invalidCapability -eq 'origin') { $bad.aiApiUrl = 'http://api.lexiquest.app' }
        else { $bad.accountDeletionRecoveryRetentionHours = 0; $expectedError = 'Account deletion recovery retention must be an integer from 1 to 720 hours' }
        [System.IO.File]::WriteAllText($configurationPath, ($bad | ConvertTo-Json -Depth 8))
        $process = [System.Diagnostics.Process]::Start($start)
        try {
            $output = $process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            Assert-True ($process.ExitCode -ne 0 -and $output -match $expectedError) 'actual packager rejects invalid public capability configuration at preflight'
            Assert-True (-not (Test-Path -LiteralPath $marker)) 'rejected configuration never invokes Flutter'
        } finally { $process.Dispose() }
    }
}
finally {
    $resolved = [System.IO.Path]::GetFullPath($taskTemp)
    if (-not $resolved.StartsWith($taskTempBase, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected fixture cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host "Commercial release configuration: $script:passed PASS, $script:failed FAIL"
if ($script:failed -gt 0) { exit 1 }
