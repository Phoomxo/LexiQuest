#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Image,
    [string]$EvidencePath,
    [switch]$SelfTest
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Assert-LocalDockerEndpoint {
    param([string]$Endpoint)
    if ($Endpoint -notmatch '^npipe:/{2,4}\./pipe/(docker_engine|dockerDesktopLinuxEngine)$' -and
        $Endpoint -ne 'unix:///var/run/docker.sock') {
        throw 'Use a local Docker socket. Remote Docker contexts are refused.'
    }
}

function Assert-SmokeContainer {
    param($Container, [string]$Name, [string]$RunId, [string]$ImageId)
    if ($Container.Id -notmatch '^[a-f0-9]{64}$' -or
        $Container.Name -cne "/$Name" -or
        $Container.Config.Labels.'io.lexiquest.ai-smoke' -cne $RunId -or
        $Container.Image -cne $ImageId) {
        throw 'Container identity does not match this smoke run. Cleanup refused.'
    }
}

function Assert-NoContainerMounts {
    param($Container)
    $mounts = $Container.PSObject.Properties['Mounts']
    if ($null -ne $mounts -and $null -ne $mounts.Value -and
        @($mounts.Value).Count -ne 0) {
        throw 'Container mounts are refused.'
    }
}

if ($SelfTest) {
    Assert-LocalDockerEndpoint 'npipe:////./pipe/dockerDesktopLinuxEngine'
    Assert-LocalDockerEndpoint 'unix:///var/run/docker.sock'
    $rejected = $false
    try { Assert-LocalDockerEndpoint 'tcp://127.0.0.1:2375' } catch { $rejected = $true }
    if (-not $rejected) { throw 'Remote context rejection failed.' }
    $fixture = [pscustomobject]@{
        Id = 'a' * 64
        Name = '/synthetic-smoke'
        Image = 'sha256:' + ('b' * 64)
        Config = [pscustomobject]@{
            Labels = [pscustomobject]@{'io.lexiquest.ai-smoke' = 'synthetic-run'}
        }
    }
    Assert-SmokeContainer $fixture 'synthetic-smoke' 'synthetic-run' $fixture.Image
    foreach ($invalid in @(
        @('foreign-name', 'synthetic-run', $fixture.Image),
        @('synthetic-smoke', 'different-run', $fixture.Image),
        @('synthetic-smoke', 'synthetic-run', 'sha256:' + ('c' * 64))
    )) {
        $rejected = $false
        try {
            Assert-SmokeContainer $fixture $invalid[0] $invalid[1] $invalid[2]
        } catch { $rejected = $true }
        if (-not $rejected) { throw 'Foreign container rejection failed.' }
    }
    foreach ($empty in @(
        [pscustomobject]@{},
        [pscustomobject]@{Mounts = $null},
        [pscustomobject]@{Mounts = @()}
    )) {
        Assert-NoContainerMounts $empty
    }
    foreach ($mount in @(
        [pscustomobject]@{Type = 'bind'; Source = '/synthetic/host'},
        [pscustomobject]@{Type = 'volume'; Name = 'synthetic'},
        'malformed'
    )) {
        $rejected = $false
        try { Assert-NoContainerMounts ([pscustomobject]@{Mounts = @($mount)}) }
        catch { $rejected = $true }
        if (-not $rejected) { throw 'Container mount rejection failed.' }
    }
    Write-Output 'AI container self-checks passed. Docker was not called.'
    return
}

if ([string]::IsNullOrWhiteSpace($Image) -or
    [string]::IsNullOrWhiteSpace($EvidencePath)) {
    throw 'Supply a prebuilt local -Image and a new -EvidencePath, or use -SelfTest.'
}
$evidenceFile = [System.IO.Path]::GetFullPath($EvidencePath)
if (Test-Path -LiteralPath $evidenceFile) {
    throw 'The evidence file already exists. Choose a new path.'
}
$evidenceParent = Split-Path -Parent $evidenceFile
if (-not (Test-Path -LiteralPath $evidenceParent -PathType Container)) {
    throw 'Create the evidence directory before running this check.'
}
$docker = (Get-Command docker -CommandType Application -ErrorAction Stop |
    Select-Object -First 1).Source

function Invoke-SmokeDocker {
    param([string[]]$Arguments, [string]$InputText)
    $result = if ([string]::IsNullOrEmpty($InputText)) {
        & $docker @Arguments 2>$null
    } else {
        $InputText | & $docker @Arguments 2>$null
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Docker operation failed: $($Arguments[0]). No build or pull was attempted."
    }
    return ($result -join "`n")
}

$contextName = Invoke-SmokeDocker @('context', 'show')
$context = @(Invoke-SmokeDocker @('context', 'inspect', $contextName) | ConvertFrom-Json)[0]
Assert-LocalDockerEndpoint ([string]$context.Endpoints.docker.Host)
$contextArgs = @('--context', $contextName)
$engine = Invoke-SmokeDocker ($contextArgs + @('info', '--format', '{{json .}}')) | ConvertFrom-Json
if ($engine.OSType -ne 'linux') {
    throw 'This check requires a running Linux Docker engine. No engine is started automatically.'
}
$imageInfo = @(Invoke-SmokeDocker ($contextArgs + @('image', 'inspect', $Image)) | ConvertFrom-Json)[0]
if ($imageInfo.Os -ne 'linux' -or $imageInfo.Config.User -cne '65532:65532' -or
    $imageInfo.Config.WorkingDir -cne '/app' -or $imageInfo.Id -notmatch '^sha256:[a-f0-9]{64}$') {
    throw 'The prebuilt image must be the Linux AI API image with user 65532:65532 and workdir /app.'
}
$engineArchitecture = switch ($engine.Architecture) {
    'x86_64' { 'amd64' }
    'aarch64' { 'arm64' }
    default { [string]$engine.Architecture }
}
$declaredVolumes = $imageInfo.Config.PSObject.Properties['Volumes']
if ($imageInfo.Architecture -ne $engineArchitecture -or
    ($null -ne $declaredVolumes -and $null -ne $declaredVolumes.Value)) {
    throw 'Image architecture must match the local engine, and image-declared volumes are refused.'
}

$probe = @'
import importlib.metadata as metadata
import importlib.util
import json
import os
from pathlib import Path
import platform
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, build_opener, ProxyHandler
import lexiquest_ai
import lexiquest_ai.app

assert os.getuid() == 65532 and os.getgid() == 65532, "Runtime user mismatch"
assert platform.python_version_tuple()[:2] == ("3", "11"), "Python runtime mismatch"
expected = {
    "cryptography": "50.0.2", "fastapi": "0.140.0", "firebase-admin": "7.5.0",
    "google-cloud-kms": "3.18.0", "google-crc32c": "1.8.0",
    "pydantic-settings": "2.14.2", "uvicorn": "0.51.0",
}
versions = {name: metadata.version(name) for name in expected}
assert versions == expected, "Locked dependency version mismatch"
absent = [name for name in ("pytest", "torch", "torchaudio") if importlib.util.find_spec(name) is None]
assert len(absent) == 3, "Test or GPU packages found in runtime image"
sources = {module.__name__: str(Path(module.__file__).resolve()) for module in (lexiquest_ai, lexiquest_ai.app)}
assert all(path.startswith("/app/src/lexiquest_ai/") for path in sources.values()), "Wrong application import source"
assert not list(Path("/app").rglob(".env")), "An environment file was included"
opener = build_opener(ProxyHandler({}))

def request(path, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    req = Request("http://127.0.0.1:8080" + path, data=data,
                  headers={} if data is None else {"Content-Type": "application/json"})
    try:
        response = opener.open(req, timeout=1)
    except HTTPError as error:
        response = error
    with response:
        return response.status, response.read(65536)

deadline = time.monotonic() + 30
while True:
    try:
        status, body = request("/health/live")
        assert status == 200 and json.loads(body) == {"status": "live"}, "Liveness contract failed"
        break
    except URLError:
        if time.monotonic() >= deadline:
            raise AssertionError("Liveness did not start within 30 seconds") from None
        time.sleep(0.25)
checks = [{"path": "/health/live", "status": status}]
for path, payload, expected_status, expected_code in (
    ("/health/ready", None, 503, "PROVIDER_UNAVAILABLE"),
    ("/docs", None, 404, None),
    ("/v1/content", {"text": "cat", "kind": "sentence", "cefr": "a1", "language": "en"}, 401, "UNAUTHENTICATED"),
):
    status, body = request(path, payload)
    assert status == expected_status, "HTTP contract failed: " + path
    if expected_code:
        assert json.loads(body)["detail"]["code"] == expected_code, "Error contract failed: " + path
    checks.append({"path": path, "status": status, "code": expected_code})
print(json.dumps({"python": platform.python_version(), "uid": os.getuid(), "gid": os.getgid(),
                  "versions": versions, "sources": sources, "absentPackages": absent, "checks": checks}))
'@

$runId = [Guid]::NewGuid().ToString('N')
$containerName = "lexiquest-ai-smoke-$runId"
$containerId = $null
$cleanupComplete = $false
$proof = $null
$creationAttempted = $false
try {
    $createArgs = $contextArgs + @(
        'container', 'create', '--pull', 'never', '--name', $containerName,
        '--label', "io.lexiquest.ai-smoke=$runId", '--network', 'none',
        '--read-only', '--tmpfs', '/tmp:rw,noexec,nosuid,nodev,size=16m',
        '--user', '65532:65532', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges', '--pids-limit', '128',
        '--memory', '512m', '--cpus', '1'
    )
    $environment = @(
        'PORT=8080', 'LEXIQUEST_AI_ENVIRONMENT=production',
        'GOOGLE_CLOUD_PROJECT=lexiquest-container-smoke',
        'GCLOUD_PROJECT=lexiquest-container-smoke', 'GCE_METADATA_DISABLED=true',
        'GOOGLE_APPLICATION_CREDENTIALS=',
        'FIREBASE_CONFIG=',
        'LEXIQUEST_AI_ACCOUNT_DELETION_ENABLED=false',
        'LEXIQUEST_AI_ACCOUNT_DELETION_SERVER_EXPORT_AUTHORITY=',
        'LEXIQUEST_AI_BILLING_ENABLED=false',
        'LEXIQUEST_AI_BILLING_MANAGED_CONTENT_REQUIRED=false',
        'LEXIQUEST_AI_RESEARCH_ENABLED=false',
        'LEXIQUEST_AI_CONTENT_REPORTS_ENABLED=false',
        'LEXIQUEST_AI_LLM_MODEL=', 'LEXIQUEST_AI_FALLBACK_LLM_MODEL=',
        'LEXIQUEST_AI_LLM_BASE_URL=https://example.invalid/v1/',
        'LEXIQUEST_AI_FALLBACK_LLM_BASE_URL=https://example.invalid/v1/',
        'LEXIQUEST_AI_LLM_API_KEY=', 'LEXIQUEST_AI_FALLBACK_LLM_API_KEY=',
        'LEXIQUEST_AI_GEMINI_KEYS='
    )
    foreach ($entry in $environment) { $createArgs += @('--env', $entry) }
    $creationAttempted = $true
    $containerId = Invoke-SmokeDocker ($createArgs + @([string]$imageInfo.Id))
    $container = @(Invoke-SmokeDocker ($contextArgs + @('container', 'inspect', $containerId)) | ConvertFrom-Json)[0]
    Assert-SmokeContainer $container $containerName $runId $imageInfo.Id
    Assert-NoContainerMounts $container
    $portBindings = $container.HostConfig.PSObject.Properties['PortBindings']
    if ($container.Config.User -cne '65532:65532' -or
        -not $container.HostConfig.ReadonlyRootfs -or
        $container.HostConfig.NetworkMode -cne 'none' -or
        $container.HostConfig.Privileged -or
        ($null -ne $portBindings -and $null -ne $portBindings.Value -and
            @($portBindings.Value.PSObject.Properties).Count -ne 0) -or
        @($container.HostConfig.Tmpfs.PSObject.Properties.Name) -cne '/tmp') {
        throw 'Container isolation does not match the smoke policy.'
    }
    Invoke-SmokeDocker ($contextArgs + @('container', 'start', $containerId)) | Out-Null
    $proof = Invoke-SmokeDocker -Arguments ($contextArgs + @('container', 'exec', '-i', $containerId, 'python', '-')) -InputText $probe | ConvertFrom-Json
} finally {
    if ($creationAttempted) {
        $remaining = & $docker @contextArgs container inspect $containerName 2>$null
        if ($LASTEXITCODE -eq 0) {
            $owned = @($remaining -join "`n" | ConvertFrom-Json)[0]
            Assert-SmokeContainer $owned $containerName $runId $imageInfo.Id
            Invoke-SmokeDocker ($contextArgs + @('container', 'rm', '--force', [string]$owned.Id)) | Out-Null
            $cleanupComplete = $true
        } else {
            Write-Warning "Could not verify cleanup for task container $containerName. No other container was touched."
        }
    }
}
if (-not $cleanupComplete) { throw 'Task container cleanup was not verified.' }
$evidence = [ordered]@{
    schemaVersion = 1
    recordedAtUtc = [DateTime]::UtcNow.ToString('o')
    dockerContext = $contextName
    engine = [ordered]@{os = $engine.OSType; architecture = $engineArchitecture; version = $engine.ServerVersion}
    image = [ordered]@{id = $imageInfo.Id; os = $imageInfo.Os; architecture = $imageInfo.Architecture; user = $imageInfo.Config.User}
    container = [ordered]@{id = $containerId; name = $containerName; runId = $runId; network = 'none'; readOnly = $true; cleanupVerified = $cleanupComplete}
    runtime = $proof
    providerAcceptance = $false
    productionAcceptance = $false
}
$json = ($evidence | ConvertTo-Json -Depth 12) + [Environment]::NewLine
$stream = [System.IO.File]::Open($evidenceFile, [System.IO.FileMode]::CreateNew)
try {
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json)
    $stream.Write($bytes, 0, $bytes.Length)
} finally { $stream.Dispose() }
Write-Output "AI container smoke passed. Evidence saved to $evidenceFile"
