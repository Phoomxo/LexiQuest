$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$workflow=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/ci.yml'))
$match=[regex]::Match($workflow,'(?m)^      - name: CLI contract tests\r?\n        shell: pwsh\r?\n        run: \|\r?\n(?<body>(?:          [^\r\n]*\r?\n)+)')
if(-not $match.Success){throw 'Cannot locate actual CLI step'}
$body=[regex]::Replace($match.Groups['body'].Value,'(?m)^          ','')
$scripts=@([regex]::Matches($body,'\./tool/cli/tests/[a-z0-9.-]+\.ps1') | ForEach-Object Value | Sort-Object -Unique)
if($scripts.Count -ne 10){throw 'Expected all ten existing CLI contracts'}
$fixture=Join-Path $root ('build/ci-exit-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$fixture/tool/cli/tests" -Force | Out-Null
# GitHub documented pwsh wrapper: Stop preference plus final LASTEXITCODE propagation.
# https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#exit-codes-and-error-action-preference
$wrapper="`$ErrorActionPreference = 'Stop'`n"+$body+"`nif (Test-Path -LiteralPath variable:\LASTEXITCODE) { exit `$LASTEXITCODE }"
[IO.File]::WriteAllText("$fixture/step.ps1",$wrapper)
$ordered=@([regex]::Matches($body,'\./tool/cli/tests/[a-z0-9.-]+\.ps1') | ForEach-Object Value)
$failures=@()
foreach($failing in @(-1,0,4,9)){
    for($i=0;$i -lt $ordered.Count;$i++){
        $code=if($i -eq $failing){7}else{0}
        [IO.File]::WriteAllText((Join-Path $fixture $ordered[$i]),"exit $code")
    }
    Push-Location $fixture
    try { & pwsh -NoProfile -NonInteractive -File "$fixture/step.ps1" *> "$fixture/case-$failing.log"; $code=$LASTEXITCODE } finally {Pop-Location}
    if(($code -eq 0) -ne ($failing -eq -1)){$failures += "position $failing returned $code"}
}
if($failures.Count){throw ($failures -join '; ')}
Write-Output 'PASS: actual CI body, success and first/middle/last exit failures in local pwsh'
