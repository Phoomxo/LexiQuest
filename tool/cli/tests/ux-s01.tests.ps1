$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
Push-Location $repo
try {
    & node --test docs/design/check-s01-navigation.cjs
    if ($LASTEXITCODE -ne 0) { throw 'S01 host navigation regressions failed' }
    foreach ($check in @('check-full-ux.cjs','check-worksheet-lab.cjs','check-exam-ux.cjs')) {
        & node (Join-Path 'docs/design' $check)
        if ($LASTEXITCODE -ne 0) { throw "Prototype compatibility failed: $check" }
    }
} finally { Pop-Location }
