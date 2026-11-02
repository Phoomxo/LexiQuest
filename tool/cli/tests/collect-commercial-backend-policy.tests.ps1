#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$collector = Join-Path (Split-Path -Parent $PSScriptRoot) 'collect-commercial-backend-policy.ps1'
if (-not (Test-Path -LiteralPath $collector -PathType Leaf)) { throw 'Commercial backend policy collector is not implemented.' }
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/field-release-evidence.ps1')
$script:passed = 0
$script:failed = 0
function Assert-True([bool]$Value, [string]$Message) {
    if ($Value) { $script:passed++ } else { $script:failed++; Write-Host "FAIL: $Message" }
}
$taskTempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$taskTemp = Join-Path $taskTempBase ('lexiquest-backend-policy-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $taskTemp
$configurationPath = Join-Path $taskTemp 'configuration.json'
$tokenVariable = 'LEXIQUEST_SYNTHETIC_POLICY_' + [guid]::NewGuid().ToString('N')
$requestState = [pscustomobject]@{
    Token = 'syntheticHeader.syntheticPayload.syntheticSignature'
    Count = 0
    Status = 200
    Uri = 'https://api.lexiquest.app/v1/billing/catalog'
    Failure = $false
    Captured = $null
    Body = $null
}
$configuration = [ordered]@{
    schemaVersion = 1; packageName = 'com.lexiquest.app'; version = '1.0.0+19'; minimumPreviousVersionCode = 18
    aiApiUrl = 'https://api.lexiquest.app/'; voiceMode = 'native'; voiceApiUrl = $null; cloudSyncEnabled = $true; contentReportsEnabled = $true
    accountDeletionRecoveryRetentionHours = 168
    billing = [ordered]@{ enabled = $true; policyRevision = 'managed-ai-v1'; products = @([ordered]@{ productId = 'lexiquest_ai_monthly'; basePlanId = 'monthly'; entitlements = @('managedContent'); dailyManagedUnits = 10 }) }
}
[IO.File]::WriteAllText($configurationPath, ($configuration | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
$parsedConfiguration = Read-LexiQuestReleaseConfiguration $configurationPath
function New-Catalog {
    return [ordered]@{ schemaVersion = 2; packageName = 'com.lexiquest.app'; policyRevision = 'managed-ai-v1'; accountIdentifier = ('a' * 64); managedContentRequired = $true; products = @([ordered]@{ productId = 'lexiquest_ai_monthly'; basePlanId = 'monthly'; entitlements = @('managedContent'); dailyManagedUnits = 10 }) }
}
$requestState.Body = (New-Catalog | ConvertTo-Json -Depth 8) + "`n"
function Invoke-WebRequest {
    [CmdletBinding()]
    param([Uri]$Uri, [string]$Method, [hashtable]$Headers, [int]$TimeoutSec, [int]$MaximumRedirection, [switch]$UseBasicParsing)
    $requestState.Count++
    $requestState.Captured = [pscustomobject]@{ Uri = $Uri; Method = $Method; Headers = $Headers; TimeoutSec = $TimeoutSec; MaximumRedirection = $MaximumRedirection; UseBasicParsing = $UseBasicParsing.IsPresent }
    if ($requestState.Failure) { throw ('Transport echoed ' + $requestState.Token + ' and private-account@example.org') }
    $stream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($requestState.Body))
    return [pscustomobject]@{
        StatusCode = $requestState.Status
        Headers = @{ 'Content-Type' = 'application/json; charset=utf-8' }
        RawContentStream = $stream
        BaseResponse = if ($PSVersionTable.PSVersion.Major -ge 7) { [pscustomobject]@{ RequestMessage = [pscustomobject]@{ RequestUri = [Uri]$requestState.Uri } } } else { [pscustomobject]@{ ResponseUri = [Uri]$requestState.Uri } }
    }
}
function Invoke-Collector([string]$Directory) {
    $result = @()
    $success = $false
    try {
        $result = @(& $collector -ConfigurationPath $configurationPath -OutputDirectory $Directory -IdTokenEnvironmentVariable $tokenVariable *>&1)
        $success = $true
    } catch { $result += $_.ToString() }
    return [pscustomobject]@{ Success = $success; Text = ($result | Out-String) }
}
try {
    $trialConfiguration = $configuration | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $trialConfiguration.billing = [pscustomobject]@{ enabled = $false }
    [IO.File]::WriteAllText($configurationPath, ($trialConfiguration | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    $trialOutput = Join-Path $taskTemp 'trial-rejected'
    $trialResult = Invoke-Collector $trialOutput
    Assert-True (-not $trialResult.Success -and $trialResult.Text.Contains('configuration validation') -and $requestState.Count -eq 0 -and -not (Test-Path -LiteralPath $trialOutput) -and -not (Test-Path -LiteralPath ($trialOutput + '.pending'))) 'trial input is refused at public configuration preflight before authentication, HTTP or output staging'
    [IO.File]::WriteAllText($configurationPath, ($configuration | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    $separateObjects = ConvertFrom-LexiQuestCommercialJson '{"groups":[{"id":"one"},{"id":"two"}]}'
    Assert-True ($separateObjects.groups.Count -eq 2 -and $separateObjects.groups[1].id -ceq 'two') 'member names may repeat in different objects within arrays'
    [Environment]::SetEnvironmentVariable($tokenVariable, $requestState.Token, 'Process')
    $output = Join-Path $taskTemp 'capture'
    $result = Invoke-Collector $output
    Assert-True $result.Success 'valid observed backend policy publishes evidence'
    if (-not $result.Success) { throw ('The positive collector fixture must pass before dependent checks. ' + $result.Text) }
    Assert-True ($requestState.Count -eq 1 -and $requestState.Captured.Uri.AbsoluteUri -ceq $requestState.Uri -and $requestState.Captured.Method -ceq 'Get') 'the real request boundary receives only the configured catalog GET'
    Assert-True ($requestState.Captured.Headers.Authorization -ceq ('Bearer ' + $requestState.Token) -and $requestState.Captured.Headers.Accept -ceq 'application/json') 'authentication uses only the named environment token'
    Assert-True ($requestState.Captured.TimeoutSec -eq 20 -and $requestState.Captured.MaximumRedirection -eq 0 -and $requestState.Captured.UseBasicParsing) 'request is bounded and redirects are disabled on both PowerShell runtimes'
    $reference = Get-Content -LiteralPath (Join-Path $output 'backend-policy-reference.json') -Raw | ConvertFrom-Json
    $record = Read-LexiQuestCommercialObservation $reference.backendPolicyEvidenceRef $output 'Collected policy'
    $rawPath = Resolve-LexiQuestEvidenceReference $record.responseEvidenceRef $output
    Assert-True ([IO.File]::ReadAllText($rawPath) -ceq $requestState.Body) 'raw actual response whitespace and bytes are retained'
    Assert-True ($record.recordType -ceq 'lexiquestManagedBackendPolicyObservation' -and $record.origin -ceq 'https://api.lexiquest.app/' -and $record.path -ceq '/v1/billing/catalog' -and $record.httpStatus -eq 200 -and $reference.configurationSha256 -ceq $parsedConfiguration.Sha256) 'typed observation and returned hash reference bind the actual configured policy'
    $stored = (@(Get-ChildItem -LiteralPath $output -File | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join '') + $result.Text
    Assert-True (-not $stored.Contains($requestState.Token) -and -not $stored.Contains('private-account@example.org')) 'files and completion output contain no token or transport PII'
    Assert-True ((Get-Acl -LiteralPath $output).AreAccessRulesProtected) 'published evidence inherits a private protected directory ACL'
    $before = (Get-FileHash -LiteralPath $rawPath).Hash
    $result = Invoke-Collector $output
    Assert-True (-not $result.Success -and $requestState.Count -eq 1 -and (Get-FileHash -LiteralPath $rawPath).Hash -ceq $before) 'existing output is never overwritten or fetched again'

    $recovered = Join-Path $taskTemp 'recovered'
    [IO.Directory]::Move($output, ($recovered + '.pending'))
    [Environment]::SetEnvironmentVariable($tokenVariable, $null, 'Process')
    $result = Invoke-Collector $recovered
    Assert-True ($result.Success -and $requestState.Count -eq 1 -and (Get-FileHash -LiteralPath (Join-Path $recovered 'backend-catalog-response.json')).Hash -ceq $before) 'complete interrupted staging is reconciled without another request or token read'
    [Environment]::SetEnvironmentVariable($tokenVariable, $requestState.Token, 'Process')

    $partial = Join-Path $taskTemp 'partial'
    $partialDirectory = [IO.Path]::GetFullPath($partial + '.pending')
    if (-not $partialDirectory.StartsWith([IO.Path]::GetFullPath($taskTemp).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Synthetic partial capture path must remain inside its fixture root.' }
    [IO.Directory]::Move($recovered, $partialDirectory)
    [IO.File]::Delete((Join-Path $partialDirectory 'backend-policy-reference.json'))
    [IO.File]::Delete((Join-Path $partialDirectory 'backend-policy-observation.json'))
    $result = Invoke-Collector $partial
    Assert-True (-not $result.Success -and $requestState.Count -eq 1 -and -not (Test-Path -LiteralPath $partial) -and (Test-Path -LiteralPath ($partial + '.pending'))) 'incomplete staging is preserved and no duplicate request is issued'

    [Environment]::SetEnvironmentVariable($tokenVariable, $null, 'Process')
    $result = Invoke-Collector (Join-Path $taskTemp 'unauthenticated')
    Assert-True (-not $result.Success -and $requestState.Count -eq 1) 'missing environment authentication never issues a request'
    [Environment]::SetEnvironmentVariable($tokenVariable, $requestState.Token, 'Process')

    foreach ($change in @('gate', 'revision', 'quota', 'package', 'schema', 'origin', 'wrongPath', 'redirect', 'unknownPrivateField', 'oversize', 'reflectedToken', 'escapedCredentialDuplicate', 'escapedEqualName', 'nestedDuplicate', 'transport')) {
        $value = New-Catalog
        $requestState.Status = 200
        $requestState.Uri = 'https://api.lexiquest.app/v1/billing/catalog'
        $requestState.Failure = $false
        switch ($change) {
            gate { $value.managedContentRequired = $false }
            revision { $value.policyRevision = 'managed-ai-v2' }
            quota { $value.products[0].dailyManagedUnits = 11 }
            package { $value.packageName = 'com.other.app' }
            schema { $value.schemaVersion = 1 }
            origin { $requestState.Uri = 'https://other.lexiquest.app/v1/billing/catalog' }
            wrongPath { $requestState.Uri = 'https://api.lexiquest.app/v1/billing/catalog?redirected=true' }
            redirect { $requestState.Status = 302 }
            unknownPrivateField { $value['privateAccount'] = 'private-account@example.org' }
            transport { $requestState.Failure = $true }
        }
        $requestState.Body = $value | ConvertTo-Json -Depth 8
        if ($change -eq 'oversize') { $requestState.Body += ' ' * 65536 }
        if ($change -eq 'reflectedToken') { $requestState.Body = $requestState.Body.Replace('"accountIdentifier":', ('"accountIdentifier":"' + $requestState.Token + '","accountIdentifier":')) }
        if ($change -eq 'escapedCredentialDuplicate') { $requestState.Body = $requestState.Body.Replace('"accountIdentifier":', ('"accountIdentifier":"\u0073' + $requestState.Token.Substring(1) + '","accountIdentifier":')) }
        if ($change -eq 'escapedEqualName') { $requestState.Body = $requestState.Body.Replace('"accountIdentifier":', ('"account\u0049dentifier":"' + ('a' * 64) + '","accountIdentifier":')) }
        if ($change -eq 'nestedDuplicate') { $requestState.Body = $requestState.Body.Replace('"dailyManagedUnits":', '"dailyManagedUnits":11,"dailyManagedUnits":') }
        $destination = Join-Path $taskTemp $change
        $result = Invoke-Collector $destination
        Assert-True (-not $result.Success -and -not (Test-Path -LiteralPath $destination)) "invalid $change cannot publish backend policy evidence"
        Assert-True (-not $result.Text.Contains($requestState.Token) -and -not $result.Text.Contains('private-account@example.org')) "invalid $change emits only sanitized diagnostics"
        $storedDirectory = if (Test-Path -LiteralPath ($destination + '.pending')) { $destination + '.pending' } else { $destination }
        Assert-True (@(Get-ChildItem -LiteralPath $storedDirectory -File -Force).Count -eq 0) "invalid $change never persists an unvalidated response"
    }
    $requestState.Failure = $false
    $requestState.Body = (New-Catalog | ConvertTo-Json -Depth 8).Replace('"accountIdentifier":', '"account\u0049dentifier":')
    $escapedNameOutput = Join-Path $taskTemp 'valid-escaped-name'
    $result = Invoke-Collector $escapedNameOutput
    Assert-True $result.Success 'a unique escaped JSON member name remains valid'
    Assert-True ([IO.File]::ReadAllText((Join-Path $escapedNameOutput 'backend-catalog-response.json')) -ceq $requestState.Body) 'valid escaped member names retain the actual raw bytes'
} finally {
    [Environment]::SetEnvironmentVariable($tokenVariable, $null, 'Process')
    $resolvedTaskTemp = [IO.Path]::GetFullPath($taskTemp)
    if ($resolvedTaskTemp.StartsWith($taskTempBase.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolvedTaskTemp -Recurse -Force }
}
Write-Host "Commercial backend policy collector checks: $script:passed passed, $script:failed failed."
if ($script:failed -gt 0) { exit 1 }
