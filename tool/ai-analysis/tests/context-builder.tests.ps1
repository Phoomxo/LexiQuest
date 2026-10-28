Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..\lib\config.ps1')
. (Join-Path $PSScriptRoot '..\lib\context-builder.ps1')

function Write-Utf8TestFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    $parent = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [string]::IsNullOrEmpty($parent)) { [System.IO.Directory]::CreateDirectory($parent) | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("lexiquest-ai-context-test-" + [guid]::NewGuid().ToString('N'))
$repo = Join-Path $tempRoot 'repo'
$outside = Join-Path $tempRoot 'outside.dart'
$junction = Join-Path $repo 'lib\outside-link'
[System.IO.Directory]::CreateDirectory($repo) | Out-Null
$config = Get-AiAnalysisConfig -ConfigPath (Join-Path $PSScriptRoot '..\config.json')

try {
    & git -C $repo init --quiet
    & git -C $repo config user.email 'tests@example.invalid'
    & git -C $repo config user.name 'LexiQuest Tests'
    Write-Utf8TestFile -Path (Join-Path $repo 'lib\sample.dart') -Content "void main() {`n  print('safe');`n}"
    Write-Utf8TestFile -Path (Join-Path $repo 'lib\tracked.dart') -Content "const value = 1;"
    & git -C $repo add -- lib/sample.dart lib/tracked.dart
    & git -C $repo commit --quiet -m baseline
    Write-Utf8TestFile -Path (Join-Path $repo 'lib\tracked.dart') -Content "const value = 2;"
    Write-Utf8TestFile -Path (Join-Path $repo 'lib\untracked.dart') -Content "const untracked = true;"
    Write-Utf8TestFile -Path $outside -Content 'outside'

    Invoke-AiAnalysisTest 'builds deterministic line-numbered explicit context' {
        $context = New-AiAnalysisContext -RepositoryRoot $repo -Config $config -Paths @('lib/sample.dart')
        Assert-Equal @('lib/sample.dart') $context.Files 'explicit source file'
        Assert-Match '^--- FILE: lib/sample\.dart ---\r?\n\s*1 \| void main' $context.Text 'line numbered excerpt'
        Assert-Equal 'explicit' $context.Mode 'explicit mode'
        Assert-Equal $context.Text.Length $context.CharacterCount 'character count'
        Assert-NotMatch ([regex]::Escape($repo)) $context.Text 'no absolute repository path'
    }

    Invoke-AiAnalysisTest 'changed-file mode includes modified tracked files only' {
        $context = New-AiAnalysisContext -RepositoryRoot $repo -Config $config -ChangedFiles
        Assert-Equal @('lib/tracked.dart') $context.Files 'tracked changes only'
        Assert-Equal 'changedFiles' $context.Mode 'changed-files mode'
    }

    Invoke-AiAnalysisTest 'rejects paths outside the repository' {
        Assert-Throws { New-AiAnalysisContext -RepositoryRoot $repo -Config $config -Paths @($outside) } 'outsideRepository'
        Assert-Throws { New-AiAnalysisContext -RepositoryRoot $repo -Config $config -Paths @('..\outside.dart') } 'outsideRepository'
    }

    Invoke-AiAnalysisTest 'rejects repository paths that traverse a junction' {
        $outsideDirectory = Join-Path $tempRoot 'external-source'
        [System.IO.Directory]::CreateDirectory($outsideDirectory) | Out-Null
        Write-Utf8TestFile -Path (Join-Path $outsideDirectory 'external.dart') -Content 'const external = true;'
        New-Item -ItemType Junction -Path $junction -Target $outsideDirectory | Out-Null
        Assert-Throws { New-AiAnalysisContext -RepositoryRoot $repo -Config $config -Paths @('lib/outside-link/external.dart') } 'reparsePoint'
    }

    Invoke-AiAnalysisTest 'rejects denylisted paths even when explicit' {
        Write-Utf8TestFile -Path (Join-Path $repo '.env.local') -Content 'SAFE_NAME=value'
        Write-Utf8TestFile -Path (Join-Path $repo 'build\generated.dart') -Content 'generated'
        Write-Utf8TestFile -Path (Join-Path $repo 'field\evidence\private.md') -Content 'private'
        Assert-Throws { New-AiAnalysisContext -RepositoryRoot $repo -Config $config -Paths @('.env.local') } 'denylistedPath'
        Assert-Throws { New-AiAnalysisContext -RepositoryRoot $repo -Config $config -Paths @('build/generated.dart') } 'denylistedPath'
        Assert-Throws { New-AiAnalysisContext -RepositoryRoot $repo -Config $config -Paths @('field/evidence/private.md') } 'denylistedPath'
    }

    Invoke-AiAnalysisTest 'rejects disallowed extensions, binary files, and oversized files' {
        Write-Utf8TestFile -Path (Join-Path $repo 'lib\archive.zip') -Content 'text but disallowed'
        [System.IO.File]::WriteAllBytes((Join-Path $repo 'lib\binary.dart'), [byte[]](65, 0, 66))
        [System.IO.File]::WriteAllBytes((Join-Path $repo 'lib\oversized.dart'), (New-Object byte[] ($config.context.maxFileBytes + 1)))
        Assert-Throws { New-AiAnalysisContext -RepositoryRoot $repo -Config $config -Paths @('lib/archive.zip') } 'unsupportedFileType'
        Assert-Throws { New-AiAnalysisContext -RepositoryRoot $repo -Config $config -Paths @('lib/binary.dart') } 'binaryFile'
        Assert-Throws { New-AiAnalysisContext -RepositoryRoot $repo -Config $config -Paths @('lib/oversized.dart') } 'fileTooLarge'
    }

    Invoke-AiAnalysisTest 'enforces file-count and total-character limits' {
        $many = @()
        foreach ($index in 1..21) {
            $relative = "many/file-$index.dart"
            Write-Utf8TestFile -Path (Join-Path $repo $relative) -Content "const value$index = $index;"
            $many += $relative
        }
        Assert-Throws { New-AiAnalysisContext -RepositoryRoot $repo -Config $config -Paths $many } 'tooManyFiles'

        Write-Utf8TestFile -Path (Join-Path $repo 'large\first.dart') -Content ('a' * 48000)
        Write-Utf8TestFile -Path (Join-Path $repo 'large\second.dart') -Content ('b' * 48000)
        Assert-Throws { New-AiAnalysisContext -RepositoryRoot $repo -Config $config -Paths @('large/first.dart', 'large/second.dart') } 'contextTooLarge'
    }

    Invoke-AiAnalysisTest 'blocks every configured embedded-secret signature by rule id' {
        $fixtures = @(
            @{ File = 'leaks/maxplus.dart'; Rule = 'maxplusInferenceKey'; Value = ('ccsk-' + ('c' * 64)) },
            @{ File = 'leaks/management.dart'; Rule = 'maxplusManagementToken'; Value = ('ccmk-' + ('d' * 32)) },
            @{ File = 'leaks/openai.dart'; Rule = 'openAiKey'; Value = ('sk-proj-' + ('e' * 32)) },
            @{ File = 'leaks/anthropic.dart'; Rule = 'anthropicKey'; Value = ('sk-ant-api03-' + ('f' * 32)) },
            @{ File = 'leaks/gemini.dart'; Rule = 'geminiKey'; Value = ('AIza' + ('G' * 32)) }
        )
        foreach ($fixture in $fixtures) {
            Write-Utf8TestFile -Path (Join-Path $repo $fixture.File) -Content ("const leaked = '" + $fixture.Value + "';")
            try {
                New-AiAnalysisContext -RepositoryRoot $repo -Config $config -Paths @($fixture.File) | Out-Null
                throw "expected embeddedSecret for $($fixture.Rule)"
            } catch {
                Assert-Match 'embeddedSecret' $_.Exception.Message "$($fixture.Rule) category"
                Assert-Match $fixture.Rule $_.Exception.Message "$($fixture.Rule) identifier"
                Assert-NotMatch ([regex]::Escape($fixture.Value)) $_.Exception.Message "$($fixture.Rule) value not disclosed"
            }
        }
    }
} finally {
    if ([System.IO.Directory]::Exists($junction)) {
        [System.IO.Directory]::Delete($junction)
    }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Complete-AiAnalysisTests -Suite 'Context builder'
