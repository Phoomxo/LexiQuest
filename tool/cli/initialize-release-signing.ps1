#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$KeyStorePath = (
        Join-Path $env:USERPROFILE `
            '.lexiquest\signing\lexiquest-release.p12'
    ),
    [string]$KeyPropertiesPath = 'android/key.properties'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Resolve-RepositoryPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

function New-CryptographicPassword {
    $bytes = New-Object byte[] 32
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
    }
    finally {
        $generator.Dispose()
    }
    return [Convert]::ToBase64String($bytes).
        TrimEnd('=').
        Replace('+', '-').
        Replace('/', '_')
}

function Protect-ForCurrentWindowsUser {
    param(
        [Parameter(Mandatory)][string]$PlainText,
        [Parameter(Mandatory)][string]$Destination
    )

    $secure = ConvertTo-SecureString $PlainText -AsPlainText -Force
    ConvertFrom-SecureString $secure |
        Set-Content -LiteralPath $Destination -Encoding ascii
}

$keytool = Get-Command keytool -ErrorAction SilentlyContinue
if ($null -eq $keytool) {
    throw 'keytool is required to initialize Android release signing.'
}

$resolvedKeyStore = Resolve-RepositoryPath $KeyStorePath
$resolvedProperties = Resolve-RepositoryPath $KeyPropertiesPath
if (
    (Test-Path -LiteralPath $resolvedKeyStore) -or
    (Test-Path -LiteralPath $resolvedProperties)
) {
    throw (
        'Release signing already exists. Refusing to overwrite the permanent ' +
        'key or key.properties.'
    )
}

$signingDirectory = Split-Path -Parent $resolvedKeyStore
New-Item -ItemType Directory -Path $signingDirectory -Force | Out-Null
$password = New-CryptographicPassword
try {
    & $keytool.Source -genkeypair -noprompt `
        -keystore $resolvedKeyStore `
        -storetype PKCS12 `
        -storepass $password `
        -keypass $password `
        -alias upload `
        -keyalg RSA `
        -keysize 4096 `
        -validity 10000 `
        -dname (
            'CN=LexiQuest Release, OU=Field Trial, O=LexiQuest, ' +
            'L=Bangkok, ST=Bangkok, C=TH'
        )
    if ([int]$LASTEXITCODE -ne 0) {
        throw 'keytool failed to generate the release key.'
    }

    $properties = @(
        '# Generated locally. Never commit or share this file.',
        ('storeFile=' + $resolvedKeyStore.Replace('\', '/')),
        ('storePassword=' + $password),
        'keyAlias=upload',
        ('keyPassword=' + $password)
    ) -join [Environment]::NewLine
    [System.IO.File]::WriteAllText(
        $resolvedProperties,
        $properties + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )

    $recoveryPath = Join-Path $signingDirectory 'release-password.dpapi'
    Protect-ForCurrentWindowsUser `
        -PlainText $password `
        -Destination $recoveryPath

    $certificateOutput = & $keytool.Source -list -v `
        -keystore $resolvedKeyStore `
        -storepass $password `
        -alias upload 2>&1
    if ([int]$LASTEXITCODE -ne 0) {
        throw 'The generated release certificate could not be verified.'
    }
    $certificateMatch = [regex]::Match(
        ($certificateOutput -join "`n"),
        'SHA256:\s*([A-Fa-f0-9:]{64,95})'
    )
    if (-not $certificateMatch.Success) {
        throw 'keytool did not report the release certificate SHA-256.'
    }
    $metadata = [ordered]@{
        schemaVersion = 1
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
        keyStorePath = $resolvedKeyStore
        alias = 'upload'
        storeType = 'PKCS12'
        certificateSha256 = $certificateMatch.Groups[1].Value.
            Replace(':', '').
            ToUpperInvariant()
        recovery = 'Password is DPAPI-protected for the current Windows user.'
    }
    $metadata |
        ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath (
            Join-Path $signingDirectory 'signing-metadata.json'
        ) -Encoding utf8

    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls $signingDirectory /inheritance:r `
        /grant:r "*$sid`:(OI)(CI)(F)" | Out-Null
    if ([int]$LASTEXITCODE -ne 0) {
        throw "Unable to restrict signing directory ACL: $signingDirectory"
    }
    foreach ($artifact in Get-ChildItem -LiteralPath $signingDirectory -Force) {
        & icacls $artifact.FullName /inheritance:r `
            /grant:r "*$sid`:(F)" | Out-Null
        if ([int]$LASTEXITCODE -ne 0) {
            throw "Unable to restrict signing artifact ACL: $($artifact.FullName)"
        }
    }
    & icacls $resolvedProperties /inheritance:r `
        /grant:r "*$sid`:(F)" | Out-Null
    if ([int]$LASTEXITCODE -ne 0) {
        throw "Unable to restrict key.properties ACL: $resolvedProperties"
    }
}
finally {
    $password = $null
}

Write-Host (
    'Release signing initialized. Back up the private signing directory ' +
    'offline before participant distribution.'
) -ForegroundColor Green
