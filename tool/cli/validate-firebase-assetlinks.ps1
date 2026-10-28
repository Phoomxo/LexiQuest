#Requires -Version 5.1
<#
.SYNOPSIS
    Read-only validator for LexiQuest's published Android Digital Asset Links.

.DESCRIPTION
    Reads either the published Hosting document or a supplied JSON fixture. It
    requires exactly one statement with exactly one approved relation and one
    protected release-certificate fingerprint. It never deploys Hosting or
    prints the fingerprint value.
#>
[CmdletBinding()]
param(
    [string]$AssetLinksUri = 'https://vocab-learning-app-219ef.web.app/.well-known/assetlinks.json',
    [string]$AssetLinksJson,
    [switch]$Quiet
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$requiredRelation = 'delegate_permission/common.handle_all_urls'
$requiredNamespace = 'android_app'
$requiredPackage = 'com.lexiquest.app'

function Fail-AssetLinksValidation {
    throw 'The published assetlinks.json does not match the required LexiQuest Android App Links contract.'
}

try {
    $expectedFingerprint = $env:ANDROID_RELEASE_CERT_SHA256
    if ([string]::IsNullOrWhiteSpace($expectedFingerprint) -or
        $expectedFingerprint -notmatch '^[A-Fa-f0-9]{2}(:[A-Fa-f0-9]{2}){31}$') {
        Fail-AssetLinksValidation
    }

    if ([string]::IsNullOrWhiteSpace($AssetLinksJson)) {
        $uri = [Uri]$AssetLinksUri
        if ($uri.Scheme -ne 'https' -or
            $uri.Host -ne 'vocab-learning-app-219ef.web.app' -or
            $uri.AbsolutePath -ne '/.well-known/assetlinks.json' -or
            -not [string]::IsNullOrEmpty($uri.Query) -or
            -not [string]::IsNullOrEmpty($uri.Fragment)) {
            Fail-AssetLinksValidation
        }
        $AssetLinksJson = (Invoke-WebRequest -UseBasicParsing -Uri $uri).Content
    }

    if ($AssetLinksJson -notmatch '^\s*\[') {
        Fail-AssetLinksValidation
    }
    $statements = @($AssetLinksJson | ConvertFrom-Json)
    if ($statements.Count -ne 1) {
        Fail-AssetLinksValidation
    }

    $statement = $statements[0]
    $relations = @($statement.relation)
    $fingerprints = @($statement.target.sha256_cert_fingerprints)
    if ($relations.Count -ne 1 -or
        $relations[0] -cne $requiredRelation -or
        $statement.target.namespace -cne $requiredNamespace -or
        $statement.target.package_name -cne $requiredPackage -or
        $fingerprints.Count -ne 1 -or
        $fingerprints[0] -cne $expectedFingerprint) {
        Fail-AssetLinksValidation
    }

    if (-not $Quiet) {
        Write-Host 'assetlinks.json contract verified.'
    }
    exit 0
} catch {
    if (-not $Quiet) {
        [Console]::Error.WriteLine('assetlinks.json contract validation failed.')
    }
    exit 1
}
