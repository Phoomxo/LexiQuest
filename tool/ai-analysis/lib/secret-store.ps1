Set-StrictMode -Version Latest

function Get-AiAnalysisDefaultSecretRoot {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'localAppDataUnavailable' }
    return (Join-Path $env:LOCALAPPDATA 'LexiQuest\ai-analysis\secrets')
}

function Test-AiAnalysisInferenceKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Security.SecureString]$SecureKey)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureKey)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) -cmatch '^ccsk-[a-f0-9]{64}$'
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Get-AiAnalysisSecretPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SecretId,
        [string]$DestinationRoot = (Get-AiAnalysisDefaultSecretRoot)
    )

    if ($SecretId -cnotin @('gpt-stable', 'claude-reviewer')) { throw 'unknownSecretId' }
    if ([string]::IsNullOrWhiteSpace($DestinationRoot)) { throw 'invalidSecretRoot' }
    return [System.IO.Path]::Combine([System.IO.Path]::GetFullPath($DestinationRoot), "$SecretId.dpapi")
}

function Set-AiAnalysisSecretDirectoryAcl {
    param([Parameter(Mandatory)][string]$Path)

    $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $systemSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetOwner($currentSid)
    $acl.SetAccessRuleProtection($true, $false)
    $inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $propagation = [System.Security.AccessControl.PropagationFlags]::None
    $rights = [System.Security.AccessControl.FileSystemRights]::FullControl
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($currentSid, $rights, $inheritance, $propagation, $allow))) | Out-Null
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, $rights, $inheritance, $propagation, $allow))) | Out-Null
    [System.IO.Directory]::SetAccessControl($Path, $acl)
}

function Set-AiAnalysisSecretFileAcl {
    param([Parameter(Mandatory)][string]$Path)

    $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $systemSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetOwner($currentSid)
    $acl.SetAccessRuleProtection($true, $false)
    $rights = [System.Security.AccessControl.FileSystemRights]::FullControl
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($currentSid, $rights, $allow))) | Out-Null
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, $rights, $allow))) | Out-Null
    [System.IO.File]::SetAccessControl($Path, $acl)
}

function Save-AiAnalysisSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SecretId,
        [Parameter(Mandatory)][Security.SecureString]$SecureKey,
        [string]$DestinationRoot = (Get-AiAnalysisDefaultSecretRoot)
    )

    $destination = Get-AiAnalysisSecretPath -SecretId $SecretId -DestinationRoot $DestinationRoot
    if (-not (Test-AiAnalysisInferenceKey -SecureKey $SecureKey)) { throw 'invalidInferenceKey' }

    $root = [System.IO.Path]::GetDirectoryName($destination)
    [System.IO.Directory]::CreateDirectory($root) | Out-Null
    Set-AiAnalysisSecretDirectoryAcl -Path $root

    $temporary = [System.IO.Path]::Combine($root, ".$SecretId.$([guid]::NewGuid().ToString('N')).tmp")
    $backup = [System.IO.Path]::Combine($root, ".$SecretId.$([guid]::NewGuid().ToString('N')).bak")
    $rollbackDiscard = [System.IO.Path]::Combine($root, ".$SecretId.$([guid]::NewGuid().ToString('N')).discard")
    $replacementCommitted = $false
    $createdDestination = $false
    try {
        $encrypted = ConvertFrom-SecureString -SecureString $SecureKey
        [System.IO.File]::WriteAllText($temporary, $encrypted, (New-Object System.Text.UTF8Encoding($false)))
        $encrypted = $null
        Set-AiAnalysisSecretFileAcl -Path $temporary

        if ([System.IO.File]::Exists($destination)) {
            [System.IO.File]::Replace($temporary, $destination, $backup, $true)
            $replacementCommitted = $true
        } else {
            [System.IO.File]::Move($temporary, $destination)
            $createdDestination = $true
        }
        Set-AiAnalysisSecretFileAcl -Path $destination
        if ($replacementCommitted -and [System.IO.File]::Exists($backup)) {
            [System.IO.File]::Delete($backup)
        }
        $replacementCommitted = $false
        $createdDestination = $false
    } catch {
        $originalError = $_
        if ($replacementCommitted -and [System.IO.File]::Exists($backup)) {
            try {
                [System.IO.File]::Replace($backup, $destination, $rollbackDiscard, $true)
                if ([System.IO.File]::Exists($rollbackDiscard)) { [System.IO.File]::Delete($rollbackDiscard) }
                $replacementCommitted = $false
            } catch {
                throw 'secretRollbackFailed'
            }
        } elseif ($createdDestination -and [System.IO.File]::Exists($destination)) {
            [System.IO.File]::Delete($destination)
            $createdDestination = $false
        }
        throw $originalError
    } finally {
        $encrypted = $null
        if ([System.IO.File]::Exists($temporary)) { [System.IO.File]::Delete($temporary) }
        if (-not $replacementCommitted -and [System.IO.File]::Exists($backup)) { [System.IO.File]::Delete($backup) }
        if (-not $replacementCommitted -and [System.IO.File]::Exists($rollbackDiscard)) { [System.IO.File]::Delete($rollbackDiscard) }
    }
}

function Read-AiAnalysisSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SecretId,
        [string]$DestinationRoot = (Get-AiAnalysisDefaultSecretRoot)
    )

    $path = Get-AiAnalysisSecretPath -SecretId $SecretId -DestinationRoot $DestinationRoot
    if (-not [System.IO.File]::Exists($path)) { throw 'secretNotFound' }
    try {
        $encrypted = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        return ConvertTo-SecureString -String $encrypted
    } catch {
        throw 'secretDecryptFailed'
    } finally {
        $encrypted = $null
    }
}

function Remove-AiAnalysisSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SecretId,
        [string]$DestinationRoot = (Get-AiAnalysisDefaultSecretRoot)
    )

    $path = Get-AiAnalysisSecretPath -SecretId $SecretId -DestinationRoot $DestinationRoot
    if (-not [System.IO.File]::Exists($path)) { return $false }
    [System.IO.File]::Delete($path)
    return $true
}
