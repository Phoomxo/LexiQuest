#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [switch]$ConfirmOwnerControlledKeyCreation,

    [string]$PublicKeyPath =
        'tool/cli/trusted-field-evidence-public-key.xml',
    [string]$Subject = 'CN=LexiQuest Field Evidence Operations'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if (-not $ConfirmOwnerControlledKeyCreation) {
    throw 'Explicit owner confirmation is required to create an evidence key.'
}
if ([IO.Path]::IsPathRooted($PublicKeyPath)) {
    $resolvedPublicKeyPath = [IO.Path]::GetFullPath($PublicKeyPath)
} else {
    $resolvedPublicKeyPath = [IO.Path]::GetFullPath(
        (Join-Path $repoRoot $PublicKeyPath)
    )
}
if (Test-Path -LiteralPath $resolvedPublicKeyPath) {
    throw (
        'The trusted evidence public key already exists. Refusing silent ' +
        'signing-identity rotation.'
    )
}
if ($null -eq (Get-Command New-SelfSignedCertificate -ErrorAction SilentlyContinue)) {
    throw 'New-SelfSignedCertificate is required on Windows.'
}

$certificate = New-SelfSignedCertificate `
    -Type Custom `
    -Subject $Subject `
    -FriendlyName 'LexiQuest Field Evidence Operations' `
    -KeyAlgorithm RSA `
    -KeyLength 3072 `
    -HashAlgorithm SHA256 `
    -KeyExportPolicy NonExportable `
    -KeyUsage DigitalSignature `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -NotAfter ([DateTime]::UtcNow.AddYears(3))
if ($null -eq $certificate -or -not $certificate.HasPrivateKey) {
    throw 'The owner-controlled evidence-signing certificate was not created.'
}
$publicRsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey(
    $certificate
)
if ($null -eq $publicRsa -or $publicRsa.KeySize -lt 3072) {
    if ($null -ne $publicRsa) {
        $publicRsa.Dispose()
    }
    throw 'The generated evidence key did not meet the RSA-3072 requirement.'
}
$publicKeyXml = $publicRsa.ToXmlString($false)
$publicRsa.Dispose()
if ($publicKeyXml -match '<(?:D|P|Q|DP|DQ|InverseQ)>') {
    throw 'Refusing to write private key material into the repository.'
}
$parent = Split-Path -Parent $resolvedPublicKeyPath
New-Item -ItemType Directory -Path $parent -Force | Out-Null
[IO.File]::WriteAllText(
    $resolvedPublicKeyPath,
    $publicKeyXml,
    [Text.UTF8Encoding]::new($false)
)
Write-Host 'Field-evidence signing identity created.' -ForegroundColor Green
Write-Host "Public key: $resolvedPublicKeyPath"
Write-Host "Certificate thumbprint: $($certificate.Thumbprint)"
Write-Host (
    'Commit the public key before packaging; the non-exportable private key ' +
    'remains in the current Windows user certificate store.'
)
