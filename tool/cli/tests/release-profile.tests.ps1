$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/release-profile.ps1')
$profile = Get-LexiQuestBuildProfile -LocalLearningPreview
if ($profile.Arguments.Count -ne 1 -or $profile.Arguments[0] -cne '--dart-define-from-file=tool/cli/profiles/local-learning-preview.json') { throw 'Canonical profile must be passed as one exact argument' }
if ($profile.Name -cne 'local-learning-preview' -or $profile.Learning -ne $true -or $profile.Cloud -ne $false -or $profile.Sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Profile identity and flags must be pinned' }
$legacy = Get-LexiQuestBuildProfile
if ($legacy.Arguments[0] -cne '--dart-define=LEXIQUEST_CLOUD_SYNC_ENABLED=true' -or $legacy.Name -cne 'field-cloud') { throw 'Historical field profile must remain explicit' }
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture = Join-Path $repo ('../build/profile-fixture-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    [IO.File]::WriteAllBytes($fixture, [Text.Encoding]::ASCII.GetBytes('abc'))
    if ((Get-LexiQuestFileHash -LiteralPath $fixture).Hash -cne 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD') { throw 'SHA256 standard vector failed' }
    foreach ($invalid in @('{"LEXIQUEST_LEARNING_PREVIEW":"true","LEXIQUEST_CLOUD_SYNC_ENABLED":"true"}', '{"LEXIQUEST_LEARNING_PREVIEW":true,"LEXIQUEST_CLOUD_SYNC_ENABLED":false}', '{"LEXIQUEST_LEARNING_PREVIEW":"true","LEXIQUEST_CLOUD_SYNC_ENABLED":"false","LEXIQUEST_AI_API_URL":"https://provider.example"}')) {
        [IO.File]::WriteAllText($fixture,$invalid)
        $rejected = $false
        try { Get-LexiQuestBuildProfile -LocalLearningPreview -ProfilePath $fixture | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw 'Modified profile must fail closed' }
    }
} finally { if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture } }
Write-Output 'PASS: canonical profile, legacy defaults, invalid flags/types/extra endpoint rejected'
