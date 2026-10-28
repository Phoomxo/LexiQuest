Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..\lib\secret-store.ps1')

function Assert-SecureStringEqual {
    param(
        [Parameter(Mandatory)][Security.SecureString]$Expected,
        [Parameter(Mandatory)][Security.SecureString]$Actual,
        [string]$Message = 'secure strings differ'
    )

    $expectedPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Expected)
    $actualPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Actual)
    try {
        $expectedText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($expectedPointer)
        $actualText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($actualPointer)
        if ($expectedText -cne $actualText) { throw $Message }
    } finally {
        $expectedText = $null
        $actualText = $null
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($expectedPointer)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($actualPointer)
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("lexiquest-ai-secret-test-" + [guid]::NewGuid().ToString('N'))
$first = ConvertTo-SecureString ('ccsk-' + ('a' * 64)) -AsPlainText -Force
$second = ConvertTo-SecureString ('ccsk-' + ('b' * 64)) -AsPlainText -Force
$management = ConvertTo-SecureString ('ccmk-' + ('a' * 64)) -AsPlainText -Force
$malformed = ConvertTo-SecureString 'not-an-inference-key' -AsPlainText -Force

try {
    Invoke-AiAnalysisTest 'accepts only ccsk inference key shape' {
        Assert-True (Test-AiAnalysisInferenceKey -SecureKey $first) 'valid inference key'
        Assert-False (Test-AiAnalysisInferenceKey -SecureKey $management) 'management token rejected'
        Assert-False (Test-AiAnalysisInferenceKey -SecureKey $malformed) 'malformed key rejected'
    }

    Invoke-AiAnalysisTest 'resolves only the two known secret identifiers' {
        Assert-Match 'gpt-stable\.dpapi$' (Get-AiAnalysisSecretPath -SecretId gpt-stable -DestinationRoot $tempRoot) 'GPT path'
        Assert-Match 'claude-reviewer\.dpapi$' (Get-AiAnalysisSecretPath -SecretId claude-reviewer -DestinationRoot $tempRoot) 'Claude path'
        Assert-Throws { Get-AiAnalysisSecretPath -SecretId unknown -DestinationRoot $tempRoot } 'unknownSecretId'
    }

    Invoke-AiAnalysisTest 'round trips a current-user DPAPI secret' {
        Save-AiAnalysisSecret -SecretId gpt-stable -SecureKey $first -DestinationRoot $tempRoot
        $roundTrip = Read-AiAnalysisSecret -SecretId gpt-stable -DestinationRoot $tempRoot
        Assert-SecureStringEqual $first $roundTrip 'DPAPI round trip'
    }

    Invoke-AiAnalysisTest 'atomically replaces an existing DPAPI secret' {
        Save-AiAnalysisSecret -SecretId gpt-stable -SecureKey $second -DestinationRoot $tempRoot
        $roundTrip = Read-AiAnalysisSecret -SecretId gpt-stable -DestinationRoot $tempRoot
        Assert-SecureStringEqual $second $roundTrip 'atomic replacement'
        Assert-Equal 0 @(Get-ChildItem -LiteralPath $tempRoot -Filter '*.tmp' -File).Count 'no temporary files remain'
        Assert-Equal 0 @(Get-ChildItem -LiteralPath $tempRoot -Filter '*.bak' -File).Count 'no backup files remain'
    }

    Invoke-AiAnalysisTest 'restores the previous blob when post-replace work fails' {
        Save-AiAnalysisSecret -SecretId gpt-stable -SecureKey $first -DestinationRoot $tempRoot
        $script:OriginalAiAnalysisAclSetter = (Get-Item Function:\Set-AiAnalysisSecretFileAcl).ScriptBlock
        $script:AiAnalysisAclCallCount = 0
        Set-Item Function:\Set-AiAnalysisSecretFileAcl -Value {
            param([string]$Path)
            $script:AiAnalysisAclCallCount++
            if ($script:AiAnalysisAclCallCount -eq 2) { throw 'injectedPostReplaceFailure' }
            & $script:OriginalAiAnalysisAclSetter -Path $Path
        }
        try {
            Assert-Throws { Save-AiAnalysisSecret -SecretId gpt-stable -SecureKey $second -DestinationRoot $tempRoot } 'injectedPostReplaceFailure'
        } finally {
            Set-Item Function:\Set-AiAnalysisSecretFileAcl -Value $script:OriginalAiAnalysisAclSetter
        }
        $roundTrip = Read-AiAnalysisSecret -SecretId gpt-stable -DestinationRoot $tempRoot
        Assert-SecureStringEqual $first $roundTrip 'previous blob restored after failure'
    }

    Invoke-AiAnalysisTest 'restricts secret ACLs to current user and SYSTEM' {
        $path = Get-AiAnalysisSecretPath -SecretId gpt-stable -DestinationRoot $tempRoot
        $acl = Get-Acl -LiteralPath $path
        Assert-True $acl.AreAccessRulesProtected 'ACL inheritance disabled'
        $allowedSids = @(
            [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value,
            'S-1-5-18'
        )
        $actualSids = @($acl.Access | ForEach-Object {
            $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
        } | Sort-Object -Unique)
        Assert-Equal @($allowedSids | Sort-Object) $actualSids 'ACL principals'
    }

    Invoke-AiAnalysisTest 'removes a known blob once without deleting the directory' {
        Assert-True (Remove-AiAnalysisSecret -SecretId gpt-stable -DestinationRoot $tempRoot) 'first removal succeeds'
        Assert-False (Remove-AiAnalysisSecret -SecretId gpt-stable -DestinationRoot $tempRoot) 'second removal reports absent'
        Assert-True (Test-Path -LiteralPath $tempRoot -PathType Container) 'parent directory remains'
    }

    Invoke-AiAnalysisTest 'rejects malformed input before writing' {
        Assert-Throws { Save-AiAnalysisSecret -SecretId claude-reviewer -SecureKey $management -DestinationRoot $tempRoot } 'invalidInferenceKey'
        Assert-False (Test-Path -LiteralPath (Join-Path $tempRoot 'claude-reviewer.dpapi')) 'invalid key not persisted'
    }
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Complete-AiAnalysisTests -Suite 'Secret store'
