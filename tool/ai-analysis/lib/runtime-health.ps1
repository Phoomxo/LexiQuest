Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'repository-root.ps1')
. (Join-Path $PSScriptRoot 'project-binding.ps1')
. (Join-Path $PSScriptRoot 'secret-store.ps1')

function Get-AiAnalysisHealthRuntimeRelativePaths {
    return @(
        'config.json',
        'initialize-secrets.ps1',
        'invoke-analysis.ps1',
        'remove-secrets.ps1',
        'test-provider-smoke.ps1',
        'lib\analysis-command.ps1',
        'lib\config.ps1',
        'lib\context-builder.ps1',
        'lib\effort-router.ps1',
        'lib\maxplus-client.ps1',
        'lib\project-binding.ps1',
        'lib\repository-root.ps1',
        'lib\report-writer.ps1',
        'lib\reviewer.ps1',
        'lib\runtime-health.ps1',
        'lib\secret-store.ps1',
        'lib\smoke-command.ps1'
    )
}

function Get-AiAnalysisRuntimeHealthSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-AiAnalysisRuntimeProperties {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string[]]$Expected
    )

    $actual = @($Value.PSObject.Properties.Name | Sort-Object)
    $expectedSorted = @($Expected | Sort-Object)
    if ((ConvertTo-Json $actual -Compress) -cne (ConvertTo-Json $expectedSorted -Compress)) {
        throw 'runtimeIntegrityFailure'
    }
}

function Test-AiAnalysisSecretAclObject {
    param(
        [Parameter(Mandatory)]$Acl,
        [Parameter(Mandatory)][Security.Principal.SecurityIdentifier]$CurrentSid
    )

    try {
        if (-not $Acl.AreAccessRulesProtected) { throw 'secretAclFailure' }
        $ownerSid = $Acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        if ($ownerSid -cne $CurrentSid.Value) { throw 'secretAclFailure' }
        $allowedSids = @($CurrentSid.Value, 'S-1-5-18') | Sort-Object
        $rules = @($Acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
        if ($rules.Count -ne 2) { throw 'secretAclFailure' }
        $actualSids = @($rules | ForEach-Object {
            if ($_.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
                ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -ne [Security.AccessControl.FileSystemRights]::FullControl) {
                throw 'secretAclFailure'
            }
            $_.IdentityReference.Value
        } | Sort-Object)
        if ((ConvertTo-Json $allowedSids -Compress) -cne (ConvertTo-Json $actualSids -Compress)) { throw 'secretAclFailure' }
        return $true
    } catch {
        if ($_.Exception.Message -match 'secretAclFailure') { throw }
        throw 'secretAclFailure'
    }
}

function Assert-AiAnalysisSecretAcl {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('Directory','File')][string]$Kind
    )

    try {
        $acl = if ($Kind -ceq 'Directory') { [IO.Directory]::GetAccessControl($Path) } else { [IO.File]::GetAccessControl($Path) }
        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $null = Test-AiAnalysisSecretAclObject -Acl $acl -CurrentSid $currentSid
    } finally {
        $acl = $null
        $currentSid = $null
    }
}

function Test-AiAnalysisProjectRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [switch]$RequireSecrets,
        [scriptblock]$GitInvoker = ${function:Invoke-AiAnalysisGitCommonDirectory}
    )

    $install = ConvertTo-AiAnalysisCanonicalDirectoryPath -Path $InstallRoot
    $activePath = Join-Path $install 'active-runtime.json'
    if (-not [IO.File]::Exists($activePath)) { throw 'runtimeMissing' }
    try {
        $active = Get-Content -LiteralPath $activePath -Raw -Encoding utf8 | ConvertFrom-Json
    } catch {
        throw 'runtimeIntegrityFailure'
    }

    Assert-AiAnalysisRuntimeProperties -Value $active -Expected @('schemaVersion','projectId','sourceCommit','gitCommonDirectory','runtimePath','installedAtUtc','runtimeManifestSha256','launcherSha256')
    if ([int]$active.schemaVersion -ne 1 -or [string]$active.projectId -cne 'lexiquest' -or [string]$active.sourceCommit -cnotmatch '^[a-f0-9]{40}$') {
        throw 'runtimeIntegrityFailure'
    }

    $sourceCommit = [string]$active.sourceCommit
    $expectedRuntime = ConvertTo-AiAnalysisCanonicalDirectoryPath -Path (Join-Path $install "runtime\$sourceCommit")
    $activeRuntime = ConvertTo-AiAnalysisCanonicalDirectoryPath -Path ([string]$active.runtimePath)
    if (-not [string]::Equals($expectedRuntime, $activeRuntime, [StringComparison]::OrdinalIgnoreCase)) { throw 'runtimeIntegrityFailure' }
    $null = Assert-AiAnalysisProjectBinding -WorkingDirectory $ProjectRoot -ExpectedGitCommonDirectory ([string]$active.gitCommonDirectory) -GitInvoker $GitInvoker

    $launcherPath = Join-Path $install 'bin\lexiquest-ai-analysis.ps1'
    $manifestPath = Join-Path $expectedRuntime 'runtime-manifest.json'
    if (-not [IO.File]::Exists($launcherPath) -or -not [IO.File]::Exists($manifestPath)) { throw 'runtimeIntegrityFailure' }
    if ((Get-AiAnalysisRuntimeHealthSha256 -Path $launcherPath) -cne [string]$active.launcherSha256 -or
        (Get-AiAnalysisRuntimeHealthSha256 -Path $manifestPath) -cne [string]$active.runtimeManifestSha256) {
        throw 'runtimeIntegrityFailure'
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    } catch {
        throw 'runtimeIntegrityFailure'
    }
    Assert-AiAnalysisRuntimeProperties -Value $manifest -Expected @('schemaVersion','projectId','sourceCommit','gitCommonDirectory','runtimePath','installedAtUtc','files')
    if ([int]$manifest.schemaVersion -ne 1 -or [string]$manifest.projectId -cne 'lexiquest' -or
        [string]$manifest.sourceCommit -cne $sourceCommit -or
        -not [string]::Equals((ConvertTo-AiAnalysisCanonicalDirectoryPath -Path ([string]$manifest.runtimePath)), $expectedRuntime, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals((ConvertTo-AiAnalysisCanonicalDirectoryPath -Path ([string]$manifest.gitCommonDirectory)), (ConvertTo-AiAnalysisCanonicalDirectoryPath -Path ([string]$active.gitCommonDirectory)), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'runtimeIntegrityFailure'
    }

    $expectedPaths = @((Get-AiAnalysisHealthRuntimeRelativePaths) | ForEach-Object { $_.Replace('\','/') } | Sort-Object)
    $actualPaths = @($manifest.files | ForEach-Object { [string]$_.path } | Sort-Object)
    if ((ConvertTo-Json $expectedPaths -Compress) -cne (ConvertTo-Json $actualPaths -Compress)) { throw 'runtimeIntegrityFailure' }
    foreach ($record in @($manifest.files)) {
        if ([string]$record.path -notmatch '^[a-zA-Z0-9._/-]+$' -or [string]$record.path -match '(^|/)\.\.(/|$)') { throw 'runtimeIntegrityFailure' }
        $path = Join-Path $expectedRuntime ([string]$record.path).Replace('/','\')
        if (-not [IO.File]::Exists($path) -or (Get-AiAnalysisRuntimeHealthSha256 -Path $path) -cne [string]$record.sha256) { throw 'runtimeIntegrityFailure' }
    }
    $installedFiles = @(Get-ChildItem -LiteralPath $expectedRuntime -Recurse -File | ForEach-Object {
        $_.FullName.Substring($expectedRuntime.Length + 1).Replace('\','/')
    } | Sort-Object)
    if ((ConvertTo-Json $installedFiles -Compress) -cne (ConvertTo-Json @($expectedPaths + 'runtime-manifest.json' | Sort-Object) -Compress)) {
        throw 'runtimeIntegrityFailure'
    }

    if ($RequireSecrets) {
        $secretRoot = Join-Path $install 'secrets'
        if (-not [IO.Directory]::Exists($secretRoot)) { throw 'secretNotFound' }
        Assert-AiAnalysisSecretAcl -Path $secretRoot -Kind Directory
        foreach ($secretId in @('gpt-stable','claude-reviewer')) {
            $secretPath = Get-AiAnalysisSecretPath -SecretId $secretId -DestinationRoot $secretRoot
            if (-not [IO.File]::Exists($secretPath)) { throw 'secretNotFound' }
            Assert-AiAnalysisSecretAcl -Path $secretPath -Kind File
            $secure = $null
            try {
                $secure = Read-AiAnalysisSecret -SecretId $secretId -DestinationRoot $secretRoot
                if ($secure -isnot [Security.SecureString]) { throw 'secretDecryptFailed' }
            } finally {
                $secure = $null
            }
        }
    }

    return [pscustomobject][ordered]@{
        Status = 'ready'
        ProjectId = 'lexiquest'
        SourceCommit = $sourceCommit
        Providers = @('gpt-stable','claude-reviewer')
    }
}
