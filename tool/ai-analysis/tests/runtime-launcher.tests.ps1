Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..\lib\repository-root.ps1')
. (Join-Path $PSScriptRoot '..\lib\project-binding.ps1')
. (Join-Path $PSScriptRoot '..\lib\secret-store.ps1')
. (Join-Path $PSScriptRoot '..\lib\runtime-installer.ps1')
. (Join-Path $PSScriptRoot '..\lib\runtime-health.ps1')

function New-RuntimeLauncherFixture {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('lexiquest-launcher-' + [guid]::NewGuid().ToString('N'))
    $project = Join-Path $root 'project'
    $install = Join-Path $root 'install'
    [IO.Directory]::CreateDirectory($project) | Out-Null
    [IO.Directory]::CreateDirectory($install) | Out-Null
    & git -C $project init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'fixture git init failed' }
    $sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $result = Install-AiAnalysisProjectRuntime -SourceRoot $sourceRoot -ProjectRoot $project -InstallRoot $install -SourceCommit ('c' * 40) -UtcNow { [datetime]'2026-08-01T02:03:04Z' }
    $secure = ConvertTo-SecureString ('ccsk-' + ('d' * 64)) -AsPlainText -Force
    Save-AiAnalysisSecret -SecretId 'gpt-stable' -SecureKey $secure -DestinationRoot (Join-Path $install 'secrets')
    Save-AiAnalysisSecret -SecretId 'claude-reviewer' -SecureKey $secure -DestinationRoot (Join-Path $install 'secrets')
    $secure = $null
    return [pscustomobject]@{
        Root = $root
        Project = $project
        Install = $install
        Runtime = $result.RuntimePath
        Launcher = Join-Path $install 'bin\lexiquest-ai-analysis.ps1'
    }
}

function Remove-RuntimeLauncherFixture {
    param([Parameter(Mandatory)]$Fixture)
    if ([IO.Directory]::Exists($Fixture.Root)) { [IO.Directory]::Delete($Fixture.Root, $true) }
}

function Invoke-InvalidRuntimeArguments {
    param(
        [Parameter(Mandatory)]$Fixture,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $Fixture.Launcher @Arguments 2>&1) -join "`n"
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    Assert-False ($exitCode -eq 0) 'irrelevant arguments rejected'
    Assert-Match 'invalidRuntimeCommand' $output 'stable irrelevant-argument category'
}

Invoke-AiAnalysisTest 'returns sanitized ready health in a subprocess' {
    $fixture = New-RuntimeLauncherFixture
    try {
        $json = & powershell -NoProfile -ExecutionPolicy Bypass -File $fixture.Launcher -Command Health -ProjectRoot $fixture.Project
        if ($LASTEXITCODE -ne 0) { throw 'health subprocess failed' }
        $health = $json | ConvertFrom-Json
        Assert-Equal 'ready' $health.Status 'ready health'
        Assert-Equal @('gpt-stable','claude-reviewer') @($health.Providers) 'provider ids only'
        Assert-Equal @('ProjectId','Providers','SourceCommit','Status') @($health.PSObject.Properties.Name | Sort-Object) 'sanitized health shape'
    } finally { Remove-RuntimeLauncherFixture $fixture }
}

Invoke-AiAnalysisTest 'rejects parameters irrelevant to Health' {
    $fixture = New-RuntimeLauncherFixture
    try {
        Invoke-InvalidRuntimeArguments -Fixture $fixture -Arguments @('-Command','Health','-ProjectRoot',$fixture.Project,'-Task','ignored')
    } finally { Remove-RuntimeLauncherFixture $fixture }
}

Invoke-AiAnalysisTest 'rejects parameters irrelevant to Analyze before provider access' {
    $fixture = New-RuntimeLauncherFixture
    try {
        [IO.File]::Delete((Get-AiAnalysisSecretPath -SecretId 'gpt-stable' -DestinationRoot (Join-Path $fixture.Install 'secrets')))
        Invoke-InvalidRuntimeArguments -Fixture $fixture -Arguments @('-Command','Analyze','-ProjectRoot',$fixture.Project,'-Task','bounded','-Provider','GptStable')
    } finally { Remove-RuntimeLauncherFixture $fixture }
}

Invoke-AiAnalysisTest 'rejects parameters irrelevant to Smoke' {
    $fixture = New-RuntimeLauncherFixture
    try {
        Invoke-InvalidRuntimeArguments -Fixture $fixture -Arguments @('-Command','Smoke','-ProjectRoot',$fixture.Project,'-Path','config.json')
    } finally { Remove-RuntimeLauncherFixture $fixture }
}

Invoke-AiAnalysisTest 'rejects parameters irrelevant to CertifyEfforts' {
    $fixture = New-RuntimeLauncherFixture
    try {
        Invoke-InvalidRuntimeArguments -Fixture $fixture -Arguments @('-Command','CertifyEfforts','-ProjectRoot',$fixture.Project,'-NoReport')
    } finally { Remove-RuntimeLauncherFixture $fixture }
}

Invoke-AiAnalysisTest 'rejects parameters irrelevant to Initialize before prompting' {
    $fixture = New-RuntimeLauncherFixture
    try {
        Invoke-InvalidRuntimeArguments -Fixture $fixture -Arguments @('-Command','Initialize','-ProjectRoot',$fixture.Project,'-Task','ignored')
    } finally { Remove-RuntimeLauncherFixture $fixture }
}

Invoke-AiAnalysisTest 'rejects parameters irrelevant to Remove' {
    $fixture = New-RuntimeLauncherFixture
    try {
        Invoke-InvalidRuntimeArguments -Fixture $fixture -Arguments @('-Command','Remove','-ProjectRoot',$fixture.Project,'-TimeoutSeconds','99')
    } finally { Remove-RuntimeLauncherFixture $fixture }
}

Invoke-AiAnalysisTest 'keeps health local-only with no network-capable dependency' {
    $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\runtime-health.ps1') -Raw -Encoding utf8
    Assert-NotMatch "(?i)\.\s*\([^\r\n]*maxplus|invoke-webrequest|httpclient|test-maxpluscredential" $source 'health network boundary'
    Assert-Match 'Read-AiAnalysisSecret' $source 'health validates DPAPI locally'
}

Invoke-AiAnalysisTest 'rejects either missing provider secret' {
    $fixture = New-RuntimeLauncherFixture
    try {
        [IO.File]::Delete((Get-AiAnalysisSecretPath -SecretId 'gpt-stable' -DestinationRoot (Join-Path $fixture.Install 'secrets')))
        Assert-Throws { Test-AiAnalysisProjectRuntime -InstallRoot $fixture.Install -ProjectRoot $fixture.Project -RequireSecrets } 'secretNotFound'
    } finally { Remove-RuntimeLauncherFixture $fixture }
}

Invoke-AiAnalysisTest 'rejects a corrupt DPAPI blob' {
    $fixture = New-RuntimeLauncherFixture
    try {
        $path = Get-AiAnalysisSecretPath -SecretId 'claude-reviewer' -DestinationRoot (Join-Path $fixture.Install 'secrets')
        [IO.File]::WriteAllText($path, 'corrupt', (New-Object Text.UTF8Encoding($false)))
        Assert-Throws { Test-AiAnalysisProjectRuntime -InstallRoot $fixture.Install -ProjectRoot $fixture.Project -RequireSecrets } 'secretDecryptFailed'
    } finally { Remove-RuntimeLauncherFixture $fixture }
}

Invoke-AiAnalysisTest 'rejects a protected secret ACL owned by another SID' {
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $systemSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetOwner($systemSid)
    $acl.SetAccessRuleProtection($true, $false)
    $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $rights = [Security.AccessControl.FileSystemRights]::FullControl
    $allow = [Security.AccessControl.AccessControlType]::Allow
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($currentSid, $rights, $inheritance, [Security.AccessControl.PropagationFlags]::None, $allow))) | Out-Null
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($systemSid, $rights, $inheritance, [Security.AccessControl.PropagationFlags]::None, $allow))) | Out-Null
    Assert-Throws { Test-AiAnalysisSecretAclObject -Acl $acl -CurrentSid $currentSid } 'secretAclFailure'
}

Invoke-AiAnalysisTest 'rejects a modified installed runtime file' {
    $fixture = New-RuntimeLauncherFixture
    try {
        [IO.File]::AppendAllText((Join-Path $fixture.Runtime 'config.json'), 'tampered')
        Assert-Throws { Test-AiAnalysisProjectRuntime -InstallRoot $fixture.Install -ProjectRoot $fixture.Project -RequireSecrets } 'runtimeIntegrityFailure'
    } finally { Remove-RuntimeLauncherFixture $fixture }
}

Invoke-AiAnalysisTest 'verifies every runtime script before dot-sourcing it' {
    $fixture = New-RuntimeLauncherFixture
    try {
        $sentinel = Join-Path $fixture.Root 'tampered-code-executed.txt'
        $escapedSentinel = $sentinel.Replace("'", "''")
        $tamperedHealth = "[IO.File]::WriteAllText('$escapedSentinel','executed'); throw 'tamperedRuntimeExecuted'"
        [IO.File]::WriteAllText((Join-Path $fixture.Runtime 'lib\runtime-health.ps1'), $tamperedHealth, (New-Object Text.UTF8Encoding($false)))
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $fixture.Launcher -Command Health -ProjectRoot $fixture.Project 2>&1) -join "`n"
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousPreference
        Assert-False ($exitCode -eq 0) 'tampered runtime rejected'
        Assert-Match 'runtimeIntegrityFailure' $output 'integrity category before load'
        Assert-False (Test-Path -LiteralPath $sentinel) 'tampered code never executed'
    } finally {
        $ErrorActionPreference = 'Stop'
        Remove-RuntimeLauncherFixture $fixture
    }
}

Invoke-AiAnalysisTest 'rejects another Git common directory before disclosure' {
    $fixture = New-RuntimeLauncherFixture
    $other = Join-Path $fixture.Root 'other'
    [IO.Directory]::CreateDirectory($other) | Out-Null
    & git -C $other init --quiet
    try {
        Assert-Throws { Test-AiAnalysisProjectRuntime -InstallRoot $fixture.Install -ProjectRoot $other -RequireSecrets } 'projectMismatch'
    } finally { Remove-RuntimeLauncherFixture $fixture }
}

Invoke-AiAnalysisTest 'projects every launcher command to one exact public script' {
    $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\runtime\lexiquest-ai-analysis.ps1') -Raw -Encoding utf8
    foreach ($command in @('Health','Analyze','Smoke','CertifyEfforts','Initialize','Remove')) {
        Assert-Match "'$command'\s*\{" $source "$command switch branch"
    }
    Assert-Match 'invoke-analysis\.ps1' $source 'analyze script'
    Assert-Match 'test-provider-smoke\.ps1' $source 'smoke script'
    Assert-Match 'initialize-secrets\.ps1' $source 'initialize script'
    Assert-Match 'remove-secrets\.ps1' $source 'remove script'
    Assert-NotMatch '(?i)Invoke-Expression|Start-Process' $source 'no generated execution'
}

Invoke-AiAnalysisTest 'rejects an invalid runtime command before dispatch' {
    $fixture = New-RuntimeLauncherFixture
    try {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $fixture.Launcher -Command Unknown -ProjectRoot $fixture.Project 2>&1) -join "`n"
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousPreference
        Assert-False ($exitCode -eq 0) 'invalid command exit'
        Assert-Match 'invalidRuntimeCommand' $output 'stable failure category'
    } finally {
        $ErrorActionPreference = 'Stop'
        Remove-RuntimeLauncherFixture $fixture
    }
}

Complete-AiAnalysisTests -Suite 'Runtime launcher'
