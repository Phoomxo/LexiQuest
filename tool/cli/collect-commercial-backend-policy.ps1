#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigurationPath,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z_][A-Za-z0-9_]{0,127}$')][string]$IdTokenEnvironmentVariable
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/field-release-evidence.ps1')

function Assert-CaptureDirectory {
    param([string]$Path)
    $cursor = Get-Item -LiteralPath $Path -Force
    while ($null -ne $cursor) {
        if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Evidence paths must not traverse filesystem links.' }
        $cursor = $cursor.Parent
    }
}

function Set-PrivateCaptureDirectory {
    param([string]$Path)
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($owner)
    $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $rule = [Security.AccessControl.FileSystemAccessRule]::new($owner, [Security.AccessControl.FileSystemRights]::FullControl, $inheritance, [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Write-CaptureFile {
    param([string]$Path, [byte[]]$Bytes)
    $file = [IO.FileStream]::new($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $file.Write($Bytes, 0, $Bytes.Length); $file.Flush($true) }
    finally { $file.Dispose() }
}

function Assert-PrivateCaptureDirectory {
    param([string]$Path)
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = Get-Acl -LiteralPath $Path
    $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
    if (-not $acl.AreAccessRulesProtected -or $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $owner.Value -or $rules.Count -ne 1 -or $rules[0].IdentityReference.Value -cne $owner.Value -or $rules[0].AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or $rules[0].FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl) { throw 'Interrupted evidence must retain its private owner-only directory ACL.' }
}

function Read-CompletedCapture {
    param([string]$Path, [object]$Configuration)
    Assert-CaptureDirectory $Path
    $files = @(Get-ChildItem -LiteralPath $Path -Force)
    $names = @('backend-catalog-response.json', 'backend-policy-observation.json', 'backend-policy-reference.json')
    if ($files.Count -ne 3 -or @($files | Where-Object { $_.PSIsContainer -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $_.Name -cnotin $names -or $_.Length -gt 65536 }).Count -gt 0) { throw 'Interrupted capture is incomplete or contains unknown files.' }
    $reference = ConvertFrom-LexiQuestCommercialJson (Get-Content -LiteralPath (Join-Path $Path 'backend-policy-reference.json') -Raw -Encoding utf8)
    Assert-LexiQuestCommercialKeys $reference @('schemaVersion', 'configurationSha256', 'backendPolicyEvidenceRef') 'Backend policy capture reference'
    if ($reference.schemaVersion -ne 1 -or $reference.configurationSha256 -cne $Configuration.Sha256 -or -not (Test-LexiQuestEvidenceReferenceShape $reference.backendPolicyEvidenceRef) -or $reference.backendPolicyEvidenceRef.path -cne 'backend-policy-observation.json') { throw 'Interrupted capture belongs to another configuration.' }
    $record = Read-LexiQuestCommercialObservation $reference.backendPolicyEvidenceRef $Path 'Backend policy observation'
    Assert-LexiQuestObservedBackendPolicyRecord $record $Configuration
    if ($record.responseEvidenceRef.path -cne 'backend-catalog-response.json') { throw 'Interrupted capture has an unsupported response path.' }
    $catalog = Read-LexiQuestCommercialObservation $record.responseEvidenceRef $Path 'Observed backend catalog'
    Assert-LexiQuestObservedBackendCatalog $catalog $Configuration
    return $reference
}

$phase = 'configuration validation'
$token = $null
$headers = $null
$response = $null
try {
    $configuration = Read-LexiQuestReleaseConfiguration -Path $ConfigurationPath -ReleaseProfile publicProduction
    $phase = 'output preflight'
    $output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\', '/')
    if ([string]::IsNullOrWhiteSpace($output) -or (Test-Path -LiteralPath $output)) { throw 'Output directory must be new.' }
    $parent = Split-Path -Parent $output
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Output parent must already exist.' }
    Assert-CaptureDirectory $parent
    $staging = $output + '.pending'
    if (Test-Path -LiteralPath $staging) {
        $phase = 'interrupted capture reconciliation'
        Assert-PrivateCaptureDirectory $staging
        $reference = Read-CompletedCapture $staging $configuration
    } else {
        $null = New-Item -ItemType Directory -Path $staging
        Set-PrivateCaptureDirectory $staging
        $phase = 'environment authentication'
        $token = [Environment]::GetEnvironmentVariable($IdTokenEnvironmentVariable, 'Process')
        if ($null -eq $token -or $token.Length -gt 16384 -or $token -cnotmatch '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$') { throw 'A valid ID token is required in the named process environment variable.' }
        $headers = @{ Authorization = 'Bearer ' + $token; Accept = 'application/json' }
        $uri = [Uri]::new([Uri]$configuration.Value.aiApiUrl, 'v1/billing/catalog')
        $phase = 'catalog request'
        $response = Invoke-WebRequest -Uri $uri -Method Get -Headers $headers -TimeoutSec 20 -MaximumRedirection 0 -UseBasicParsing -ErrorAction Stop -WarningAction SilentlyContinue -Verbose:$false -Debug:$false
        $phase = 'catalog response validation'
        $effectiveUri = if ($PSVersionTable.PSVersion.Major -ge 7) { $response.BaseResponse.RequestMessage.RequestUri } else { $response.BaseResponse.ResponseUri }
        if ([int]$response.StatusCode -ne 200 -or $null -eq $effectiveUri -or $effectiveUri.AbsoluteUri -cne $uri.AbsoluteUri -or [string]$response.Headers['Content-Type'] -notmatch '(?i)^application/json(?:\s*;|$)') { throw 'A successful JSON response from the exact configured endpoint is required.' }
        $bytes = $response.RawContentStream.ToArray()
        if ($bytes.Length -lt 1 -or $bytes.Length -gt 65536) { throw 'Catalog response size is outside the evidence bound.' }
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        if ($text.Contains($token)) { throw 'Reflected authentication material cannot be captured.' }
        $catalog = ConvertFrom-LexiQuestCommercialJson $text
        Assert-LexiQuestObservedBackendCatalog $catalog $configuration
        $observedAt = [DateTimeOffset]::UtcNow.ToString('o')
        $phase = 'private evidence staging'
        Write-CaptureFile (Join-Path $staging 'backend-catalog-response.json') $bytes
        $record = [ordered]@{
            recordType = 'lexiquestManagedBackendPolicyObservation'
            origin = $configuration.Value.aiApiUrl
            path = '/v1/billing/catalog'
            observedAtUtc = $observedAt
            httpStatus = 200
            responseEvidenceRef = New-LexiQuestEvidenceReference -Path 'backend-catalog-response.json' -EvidenceRootPath $staging
        }
        Write-CaptureFile (Join-Path $staging 'backend-policy-observation.json') ([Text.Encoding]::UTF8.GetBytes(($record | ConvertTo-Json -Depth 6 -Compress)))
        $reference = [ordered]@{ schemaVersion = 1; configurationSha256 = $configuration.Sha256; backendPolicyEvidenceRef = New-LexiQuestEvidenceReference -Path 'backend-policy-observation.json' -EvidenceRootPath $staging }
        Write-CaptureFile (Join-Path $staging 'backend-policy-reference.json') ([Text.Encoding]::UTF8.GetBytes(($reference | ConvertTo-Json -Depth 6 -Compress)))
        $null = Read-CompletedCapture $staging $configuration
    }
    $phase = 'atomic evidence publication'
    [IO.Directory]::Move($staging, $output)
    [pscustomobject]@{ evidenceRootPath = $output; backendPolicyEvidenceRef = $reference.backendPolicyEvidenceRef }
} catch {
    throw "Commercial backend policy collection failed during $phase. Existing or pending files were preserved; no new evidence was published."
} finally {
    $token = $null
    $headers = $null
    if ($null -ne $response -and $null -ne $response.RawContentStream) { $response.RawContentStream.Dispose() }
    $response = $null
}
