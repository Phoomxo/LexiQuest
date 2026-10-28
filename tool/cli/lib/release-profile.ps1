function Get-LexiQuestFileHash {
    param([string]$LiteralPath, [string]$Algorithm = 'SHA256')
    if ($Algorithm -ne 'SHA256') { throw 'Only SHA256 is supported.' }
    $stream = [IO.File]::OpenRead($LiteralPath)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return [pscustomobject]@{ Hash=([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-','') } }
    finally { $hasher.Dispose(); $stream.Dispose() }
}

function Get-LexiQuestBuildProfile {
    [CmdletBinding()]
    param(
        [switch]$LocalLearningPreview,
        [string]$ProfilePath = (Join-Path $PSScriptRoot '../profiles/local-learning-preview.json')
    )
    if (-not $LocalLearningPreview) {
        return [pscustomobject]@{ Name='field-cloud'; Learning=$false; Cloud=$true; Sha256=$null; Arguments=@('--dart-define=LEXIQUEST_CLOUD_SYNC_ENABLED=true') }
    }
    $profile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
    if (@($profile.PSObject.Properties).Count -ne 2 -or $profile.LEXIQUEST_LEARNING_PREVIEW -isnot [string] -or $profile.LEXIQUEST_CLOUD_SYNC_ENABLED -isnot [string] -or $profile.LEXIQUEST_LEARNING_PREVIEW -cne 'true' -or $profile.LEXIQUEST_CLOUD_SYNC_ENABLED -cne 'false') {
        throw 'Local preview requires exactly learning=true and cloud=false strings; extra endpoints or flags are forbidden.'
    }
    return [pscustomobject]@{
        Name='local-learning-preview'; Learning=$true; Cloud=$false
        Sha256=(Get-LexiQuestFileHash -LiteralPath $ProfilePath -Algorithm SHA256).Hash.ToLowerInvariant()
        Arguments=@('--dart-define-from-file=tool/cli/profiles/local-learning-preview.json')
    }
}
