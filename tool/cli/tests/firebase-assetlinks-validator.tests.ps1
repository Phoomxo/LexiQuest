#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:Passed = 0
$script:Failed = 0
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$validatorPath = Join-Path $repoRoot 'tool\cli\validate-firebase-assetlinks.ps1'
$expectedFingerprint = ((@('AA') * 32) -join ':')
$unexpectedFingerprint = ((@('BB') * 32) -join ':')

function Write-Pass { param([string]$Message) $script:Passed++ }
function Write-Fail {
    param([string]$Message)
    $script:Failed++
    Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
}

function New-AssetLinksJson {
    param(
        [string[]]$Relation = @('delegate_permission/common.handle_all_urls'),
        [string]$Namespace = 'android_app',
        [string]$PackageName = 'com.lexiquest.app',
        [string[]]$Fingerprints = @($expectedFingerprint),
        [switch]$ExtraStatement
    )

    $statement = [ordered]@{
        relation = @($Relation)
        target = [ordered]@{
            namespace = $Namespace
            package_name = $PackageName
            sha256_cert_fingerprints = @($Fingerprints)
        }
    }
    $statementJson = $statement | ConvertTo-Json -Depth 5 -Compress
    if ($ExtraStatement) {
        return '[' + $statementJson + ',' + $statementJson + ']'
    }
    return '[' + $statementJson + ']'
}

function Assert-Validation {
    param([string]$Name, [string]$Json, [bool]$ShouldPass)

    & $validatorPath -AssetLinksJson $Json -Quiet
    $succeeded = $LASTEXITCODE -eq 0
    if ($succeeded -eq $ShouldPass) {
        Write-Pass $Name
    } else {
        Write-Fail $Name
    }
}

if (-not (Test-Path -LiteralPath $validatorPath)) {
    Write-Fail 'asset links validator script exists'
} else {
    $previousFingerprint = $env:ANDROID_RELEASE_CERT_SHA256
    try {
        $env:ANDROID_RELEASE_CERT_SHA256 = $expectedFingerprint
        Assert-Validation -Name 'valid single approved statement passes' -Json (New-AssetLinksJson) -ShouldPass $true
        Assert-Validation -Name 'extra relation fails' -Json (New-AssetLinksJson -Relation @('delegate_permission/common.handle_all_urls', 'other')) -ShouldPass $false
        Assert-Validation -Name 'wrong relation fails' -Json (New-AssetLinksJson -Relation @('other')) -ShouldPass $false
        Assert-Validation -Name 'wrong namespace fails' -Json (New-AssetLinksJson -Namespace 'web') -ShouldPass $false
        Assert-Validation -Name 'wrong package fails' -Json (New-AssetLinksJson -PackageName 'com.example.other') -ShouldPass $false
        Assert-Validation -Name 'extra statement fails' -Json (New-AssetLinksJson -ExtraStatement) -ShouldPass $false
        Assert-Validation -Name 'extra fingerprint fails' -Json (New-AssetLinksJson -Fingerprints @($expectedFingerprint, $unexpectedFingerprint)) -ShouldPass $false
        Assert-Validation -Name 'wrong fingerprint fails' -Json (New-AssetLinksJson -Fingerprints @($unexpectedFingerprint)) -ShouldPass $false
    } finally {
        $env:ANDROID_RELEASE_CERT_SHA256 = $previousFingerprint
    }
}

Write-Host ("Firebase asset links validator tests: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
