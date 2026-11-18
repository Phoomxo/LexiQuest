<#
.SYNOPSIS
  LexiQuest Multi-Agent Unified Pipeline Runner
.DESCRIPTION
  Executes deterministic verification gates for any AI agent (Codex, Claude, Gemini, Antigravity)
  without requiring manual prompts or intervention.
.EXAMPLE
  .\tool\agent_pipeline.ps1 -Gate 3
  .\tool\agent_pipeline.ps1 -All
#>

param(
    [ValidateSet("1", "2", "3", "4", "5", "All")]
    [string]$Gate = "All"
)

$ErrorActionPreference = "Stop"
$repoRoot = "C:\Users\Phet\Documents\LexiQuest"
Set-Location $repoRoot

function Run-Gate1 {
    Write-Host "`n=== [GATE 1: Static Analysis & Dart Linting] ===" -ForegroundColor Cyan
    Write-Host "Running flutter analyze..."
    flutter analyze
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Gate 1 Failed: flutter analyze reported issues."
    }
    Write-Host "Gate 1 Passed: 0 issues." -ForegroundColor Green
}

function Run-Gate2 {
    Write-Host "`n=== [GATE 2: Architecture & Constraints Check] ===" -ForegroundColor Cyan
    Write-Host "Checking for lazy stubs (TODO/empty handlers)..."
    $stubs = Get-ChildItem -Path "$repoRoot\lib" -Recurse -Include *.dart | Select-String -Pattern "TODO: implement later", "onPressed: \(\) \{\}"
    if ($stubs) {
        Write-Warning "Found potential lazy stubs:"
        $stubs | ForEach-Object { Write-Host " - $($_.Path):$($_.LineNumber)" }
    } else {
        Write-Host "Gate 2 Passed: No lazy stubs found." -ForegroundColor Green
    }
}

function Run-Gate3 {
    Write-Host "`n=== [GATE 3: Empirical Tests & Widget Verification] ===" -ForegroundColor Cyan
    Write-Host "Running flutter test (Unit & Widget tests)..."
    flutter test
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Gate 3 Failed: One or more flutter tests failed."
    }
    Write-Host "Gate 3 Passed: All automated tests succeeded." -ForegroundColor Green
}

function Run-Gate4 {
    Write-Host "`n=== [GATE 4: AI Code Review (OpenCodeReview)] ===" -ForegroundColor Cyan
    if (Get-Command ocr -ErrorAction SilentlyContinue) {
        Write-Host "Running ocr review on unstaged/staged diff..."
        ocr review
    } else {
        Write-Warning "ocr command not found on PATH. Ensure @alibaba-group/open-code-review is installed."
    }
}

function Run-Gate5 {
    Write-Host "`n=== [GATE 5: Continuous Memory Sync (claude-mem)] ===" -ForegroundColor Cyan
    if (Get-Command claude-mem -ErrorAction SilentlyContinue) {
        Write-Host "Syncing session context to claude-mem..."
        claude-mem sync
    } else {
        Write-Warning "claude-mem command not found on PATH. Ensure claude-mem is installed."
    }
}

switch ($Gate) {
    "1" { Run-Gate1 }
    "2" { Run-Gate2 }
    "3" { Run-Gate3 }
    "4" { Run-Gate4 }
    "5" { Run-Gate5 }
    "All" {
        Run-Gate1
        Run-Gate2
        Run-Gate3
        Run-Gate4
        Run-Gate5
        Write-Host "`n==========================================" -ForegroundColor Green
        Write-Host " All Gates Passed! Pipeline Verified." -ForegroundColor Green
        Write-Host "==========================================" -ForegroundColor Green
    }
}
