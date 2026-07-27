#Requires -Version 5.1
<#
.SYNOPSIS
    Dependency-free security contract for the root Firestore rules and the
    Firebase deployment configuration.

.DESCRIPTION
    LexiQuest keeps every per-user document in Firestore. The stabilization
    gate (docs/security/2026-07-26-stabilization-gate.md) records the absence
    of a reviewed firestore.rules and firebase.json as a production release
    blocker. These static, CPU-only contract tests pin the least-privilege
    posture the Flutter client already assumes (lib/services/*.dart and
    lib/screens/*.dart):

      - users, state, categories and purchased_items are owner-scoped;
      - words nested under categories inherit the parent category owner;
      - products are a read-only catalog (no client writes);
      - quiz is a server-managed bank with no client access;
      - voice_telemetry_events accept authenticated create events only;
      - every other path is recursively denied by default.

    The checks read the rules and configuration files as text and assert the
    required clauses are present. They never start the Firebase emulator,
    contact the network, or install a package. Until the GREEN pass lands the
    files, the existence guard keeps this test RED.
#>
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) { $script:Passed++ } else {
        $script:Failed++
        Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
    }
}

function Assert-NoMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) {
        $script:Failed++
        Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
    } else { $script:Passed++ }
}

# Returns the body of a single-level match block (a collection with no nested
# subcollections) so per-collection clauses can be checked in isolation.
function Get-RuleBlock {
    param([string]$Source, [string]$Collection)
    $pattern = 'match\s+/' + $Collection + '/\{[^}]+\}\s*\{([^{}]*)\}'
    if ($Source -match $pattern) { return $matches[1] }
    return ''
}

$repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$rulesPath = Join-Path $repoRoot 'firestore.rules'
$configPath = Join-Path $repoRoot 'firebase.json'

$missing = @()
if (-not (Test-Path -LiteralPath $rulesPath)) { $missing += 'firestore.rules' }
if (-not (Test-Path -LiteralPath $configPath)) { $missing += 'firebase.json' }
if ($missing.Count -gt 0) {
    Write-Host ('FAIL: missing ' + ($missing -join ' and ')) -ForegroundColor Red
    exit 1
}

$rules = ([System.IO.File]::ReadAllText($rulesPath) -replace "`r`n", "`n") -replace "`r", "`n"
$config = ([System.IO.File]::ReadAllText($configPath) -replace "`r`n", "`n") -replace "`r", "`n"

# --- firestore.rules structural contract -------------------------------------

Assert-Match $rules "rules_version\s*=\s*['""]2['""]" 'rules_version is 2'
Assert-Match $rules 'service\s+cloud\.firestore' 'firestore rules service is declared'
Assert-Match $rules 'request\.auth\.uid\s*!=\s*null' 'authentication is required for access'

# Self-ownership by document id (users, state).
Assert-Match $rules 'match\s+/users/\{[^}]+\}' 'users collection is matched'
Assert-Match $rules 'match\s+/state/\{[^}]+\}' 'state collection is matched'
Assert-Match $rules 'request\.auth\.uid\s*==\s*\w+' 'caller uid is compared to a path variable'

# Self-ownership by owner field (categories, purchased_items).
Assert-Match $rules 'match\s+/categories/\{[^}]+\}' 'categories collection is matched'
Assert-Match $rules 'resource\.data\.uid\s*==\s*request\.auth\.uid|request\.auth\.uid\s*==\s*resource\.data\.uid' 'categories gated by owner uid field'
Assert-Match $rules 'match\s+/purchased_items/\{[^}]+\}' 'purchased_items collection is matched'
Assert-Match $rules 'resource\.data\.user_id\s*==\s*request\.auth\.uid|request\.auth\.uid\s*==\s*resource\.data\.user_id' 'purchased_items gated by owner user_id field'

# Parent ownership for words nested under categories.
Assert-Match $rules 'match\s+/words/\{wordId\}' 'nested words subcollection is matched'
Assert-Match $rules 'get\(/databases' 'parent category is read via get() for nested ownership'

# Read-only catalog: products may be read but never written by clients.
$productsBlock = Get-RuleBlock -Source $rules -Collection 'products'
Assert-Match $productsBlock 'allow\s+write\s*:\s*if\s*false' 'products deny client writes'

# Server-managed quiz bank: no client access at all.
$quizBlock = Get-RuleBlock -Source $rules -Collection 'quiz'
Assert-Match $quizBlock 'allow\s+read,\s*write\s*:\s*if\s*false' 'quiz denies all client access'

# Authenticated create-only telemetry.
$telemetryBlock = Get-RuleBlock -Source $rules -Collection 'voice_telemetry_events'
Assert-Match $telemetryBlock 'allow\s+create\s*:\s*if\s+(request\.auth\.uid\s*!=\s*null|isSignedIn\(\)|isRegisteredUser\(\))' 'telemetry allows authenticated create only'
Assert-NoMatch $telemetryBlock 'allow\s+(read|get|list|update|delete)[^:]*:\s*if\s+(request\.auth\.uid\s*!=\s*null|request\.auth\s*!=\s*null|true|isSignedIn\(\))' 'telemetry does not grant read/update/delete'

# Recursive default deny for any path not explicitly allow-listed.
Assert-Match $rules 'match\s+/\{document=\*\*\}' 'recursive catch-all match is present'
Assert-Match $rules 'allow\s+read,\s*write\s*:\s*if\s*false' 'recursive default deny denies read and write'

# --- firebase.json deployment contract ---------------------------------------

Assert-Match $config '"firestore"' 'firebase.json declares a firestore block'
Assert-Match $config '"rules"\s*:\s*"firestore\.rules"' 'firebase.json points firestore rules at the root firestore.rules'
$configValid = $false
try {
    ConvertFrom-Json -InputObject $config | Out-Null
    $configValid = $true
} catch {
    $configValid = $false
}
if ($configValid) { $script:Passed++ } else {
    $script:Failed++
    Write-Host '  [FAIL] firebase.json is valid JSON' -ForegroundColor Red
}

Write-Host ("Firestore rules security tests: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
