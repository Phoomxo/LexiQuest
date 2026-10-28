#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$scriptPath = Join-Path $repoRoot 'tool/cli/build-standard-voice-pack.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'lexiquest-voice-pack-' + [Guid]::NewGuid().ToString('N')
)
$audioRoot = Join-Path $tempRoot 'audio'
$output = Join-Path $tempRoot 'pack'
$content = Join-Path $tempRoot 'content.json'
$passed = 0

function Assert-True {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw $Message }
    $script:passed++
}

New-Item -ItemType Directory -Path (Join-Path $audioRoot 'words') -Force |
    Out-Null
try {
    [IO.File]::WriteAllBytes(
        (Join-Path $audioRoot 'words/cat.wav'),
        [byte[]](82, 73, 70, 70, 1)
    )
    [IO.File]::WriteAllBytes(
        (Join-Path $audioRoot 'words/dog.wav'),
        [byte[]](82, 73, 70, 70, 2, 3)
    )
    Copy-Item -LiteralPath (
        Join-Path $repoRoot `
            'tool/voice_pack/fixtures/approved-standard-voice-content.json'
    ) -Destination $content

    & $scriptPath `
        -ContentPath $content `
        -AudioDirectory $audioRoot `
        -OutputDirectory $output `
        -PackId 'core-en' `
        -Version '1.0.0' `
        -Locale 'en' `
        -VoiceId 'teacher_female' `
        -ModelVersion '2.0.3' `
        -MinimumAppVersion '1.0.0+1' `
        -BaseUri 'https://assets.example.com/voice/core-en/1.0.0/' `
        -GeneratedAtUtc '2026-07-31T00:00:00Z'

    $manifestPath = Join-Path $output 'manifest.json'
    Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) `
        'manifest is atomically activated'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 |
        ConvertFrom-Json
    Assert-True ($manifest.files.Count -eq 2) 'manifest contains two files'
    Assert-True ($manifest.totalBytes -eq 11) 'manifest totals actual bytes'
    Assert-True (
        $manifest.files[0].normalizedTextSha256 -eq
        '48735c4fae42d1501164976afec76730b9e5fe467f680bdd8daff4bb77674045'
    ) 'manifest hashes normalized approved text'
    foreach ($file in $manifest.files) {
        $built = Join-Path $output ([string]$file.relativePath)
        Assert-True (Test-Path -LiteralPath $built -PathType Leaf) `
            "built audio exists: $($file.relativePath)"
        Assert-True (
            (Get-FileHash -LiteralPath $built -Algorithm SHA256).Hash.
                ToLowerInvariant() -eq $file.sha256
        ) "built audio hash matches: $($file.relativePath)"
    }

    $badContent = Join-Path $tempRoot 'bad.json'
    '[{"contentId":"bad","text":"Bad","relativePath":"../escape.wav"}]' |
        Set-Content -LiteralPath $badContent -Encoding utf8
    $badOutput = Join-Path $tempRoot 'bad-pack'
    $failedClosed = $false
    try {
        & $scriptPath `
            -ContentPath $badContent `
            -AudioDirectory $audioRoot `
            -OutputDirectory $badOutput `
            -PackId 'bad' `
            -Version '1.0.0' `
            -Locale 'en' `
            -VoiceId 'teacher_female' `
            -ModelVersion '2.0.3' `
            -MinimumAppVersion '1.0.0+1' `
            -BaseUri 'https://assets.example.com/' `
            -GeneratedAtUtc '2026-07-31T00:00:00Z'
    }
    catch {
        $failedClosed = $true
    }
    Assert-True $failedClosed 'traversal input fails closed'
    Assert-True (-not (Test-Path -LiteralPath $badOutput)) `
        'failed pack is never activated'

    Write-Host "build-standard-voice-pack contract: PASS=$passed FAIL=0"
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
