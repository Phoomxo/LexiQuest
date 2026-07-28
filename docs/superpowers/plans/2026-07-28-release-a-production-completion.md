# Release A Production Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish, verify, review, and merge the complete Release A integrity and security candidate into `main` without weakening research integrity, economy authority, or repository protections.

**Architecture:** Treat `codex/release-a-economy-lockdown` as the immutable candidate lineage descending from PR #3 head `f66d0316daff57c83ed972a11f6425cb326f482a`. Publish that lineage by fast-forwarding the existing PR branch, then run local, GitHub, deployed-policy, and Codex Security gates against one frozen SHA. Merge only after the owner-controlled gates are evidenced; otherwise leave PR #3 open and report the exact external blocker.

**Tech Stack:** Git/GitHub CLI, Flutter 3.44.7, Dart, Firebase/Firestore emulator, Supabase CLI, Node.js 24, Python 3.11 with uv, OSV-Scanner, Gitleaks, Android Gradle build, Codex Security.

## Global Constraints

- Work only from the isolated worktree `C:\Users\Phet\Documents\LexiQuest\.worktrees\release-a-economy-lockdown`.
- Preserve `feature/associative-reading-loop@0077ef8791eac3ae72eb3bee3145ea90fd97ede3` unchanged as the Release B prototype.
- Remote economy, purchases, leaderboards, client-authoritative rewards, remote research output, research charts, and statistical claims remain disabled.
- Owner reads of legacy `state` and `purchased_items` data remain; clients may update only `selectedWallpaper` on an existing owner state document.
- Do not reintroduce fabricated pre/post values, sample sizes, latency values, p-values, or successful exports when observations are insufficient.
- The two OSV exceptions remain narrowly scoped to `GHSA-mh99-v99m-4gvg` and `GHSA-w5hq-g745-h8pq`, expire on `2026-10-26`, and require repository-owner risk acceptance.
- Never commit service-account JSON, `.env`, tokens, generated audio, model weights, APK/AAB outputs, or research exports.
- Do not force-push, squash, or rebase the Release A candidate. PR #3 must advance by fast-forward and merge with a merge commit.
- CI, OSV, Gitleaks, release verification, deployed-policy parity, and security closure must refer to the same frozen candidate SHA.
- Do not merge while branch protection, non-author approval, deployed-policy parity, or any required check remains unverified.
- Do not delete prototype or legacy branches during Release A completion.

---

### Task 1: Freeze and document the candidate lineage

**Files:**
- Create: `docs/superpowers/plans/2026-07-28-release-a-production-completion.md`
- Read: `firestore.rules`
- Read: `test/security/firestore-rules.test.cjs`
- Read: `docs/security/progress-authority.md`
- Read: `docs/security/firestore-access-inventory.md`

**Interfaces:**
- Consumes: PR #3 remote head `f66d0316daff57c83ed972a11f6425cb326f482a`.
- Produces: one clean candidate commit whose parent lineage contains every Release A integrity/security fix.

- [x] **Step 1: Verify isolation and cleanliness**

Run:

```powershell
git rev-parse --git-dir
git rev-parse --git-common-dir
git branch --show-current
git status --short
```

Expected: linked worktree, branch `codex/release-a-economy-lockdown`, and no uncommitted files before adding this plan.

- [x] **Step 2: Verify direct ancestry and enumerate the candidate commits**

Run:

```powershell
git merge-base --is-ancestor f66d0316daff57c83ed972a11f6425cb326f482a HEAD
git log --reverse --oneline f66d0316daff57c83ed972a11f6425cb326f482a..HEAD
```

Expected: exit `0` and the integrity/security chain beginning with research observation fixes and ending with `fix(security): close client-authoritative economy writes`.

- [x] **Step 3: Prove the alternate economy worktree has no missing production behavior**

Run:

```powershell
git diff --name-status 04e2f8f2183e15bf01cf4d10e98b84e9d2d75f7c 212764410714e590b296aa1f8d63e28a77bb4af2
```

Expected: differences are confined to research-integrity files because commit `04e2f8f` already contains the final economy behavior from the alternate branch.

- [x] **Step 4: Commit the initial execution plan**

Run:

```powershell
git add -- docs/superpowers/plans/2026-07-28-release-a-production-completion.md
git diff --cached --check
git commit -m "docs: add Release A production completion plan"
```

Expected and recorded: commit `cfbe3ae5f6e0cc672f4ceec2e1f83ebf7fd7bbfd` and a clean worktree.

### Task 2: Run independent candidate, GitHub, and deployment-readiness audits

**Files:**
- Create ignored report: `.superpowers/sdd/audits/release-a-candidate.md`
- Create ignored report: `.superpowers/sdd/audits/release-a-github.md`
- Create ignored report: `.superpowers/sdd/audits/release-a-deployment-readiness.md`

**Interfaces:**
- Consumes: frozen candidate SHA from Task 1.
- Produces: three read-only audit receipts with exact blockers and no repository or cloud mutations.

- [x] **Step 1: Dispatch bounded read-only agents**

Each agent must inspect only its assigned domain: candidate/spec coverage, GitHub PR/protection state, deployed-policy readiness, or plan safety. Agents write only their assigned ignored report.

- [x] **Step 2: Review all four receipts**

Run:

```powershell
Get-Content .superpowers/sdd/audits/release-a-candidate.md
Get-Content .superpowers/sdd/audits/release-a-github.md
Get-Content .superpowers/sdd/audits/release-a-deployment-readiness.md
Get-Content .superpowers/sdd/audits/release-a-plan-review.md
```

Recorded result: candidate code blockers move to Task 2A. GitHub protection, non-author review, deployed-policy parity, and credential blockers remain fail-closed owner gates in Tasks 5 and 7.

### Task 2A: Close validated research-export and Firestore authorization blockers

**Files:**
- Create: `lib/services/research_export_errors.dart`
- Modify: `lib/services/research_data_exporter_service.dart`
- Modify: `lib/services/research_report_pdf_exporter_service.dart`
- Modify: `firestore.rules`
- Modify: `test/services/research_data_exporter_service_test.dart`
- Modify: `test/services/research_report_pdf_exporter_service_test.dart`
- Modify: `test/security/firestore-rules.test.cjs`
- Modify: `docs/security/firestore-access-inventory.md`
- Modify: `docs/security/progress-authority.md`
- Modify: `docs/security/2026-07-26-stabilization-gate.md`

**Interfaces:**
- Consumes: `ResearchDataExporterService.generateCsvReport(...)`, existing PDF `InsufficientData`, Firebase registered/anonymous identity predicates, and the Release A A2 authorization contract.
- Produces: one shared `InsufficientData` type, fail-closed empty research exports, profile-only registered-user writes, non-anonymous owner-private records, and admin-only shared curated writes.

- [ ] **Step 1: Write failing research-export tests**

Add a zero-row CSV assertion:

```dart
expect(
  () => service.generateCsvReport(const []),
  throwsA(isA<InsufficientData>()),
);
```

Retain the existing PDF assertion that fewer than two paired observations throws the same public type.

- [ ] **Step 2: Run the focused research tests and verify RED**

Run:

```powershell
flutter test test/services/research_data_exporter_service_test.dart test/services/research_report_pdf_exporter_service_test.dart
```

Expected: the new CSV case fails because the current exporter returns a header-only CSV.

- [ ] **Step 3: Introduce the shared error and fail closed before writing a CSV header**

Create:

```dart
class InsufficientData implements Exception {
  const InsufficientData([
    this.message = 'Insufficient real observations for this report.',
  ]);

  final String message;

  @override
  String toString() => 'InsufficientData: $message';
}
```

Both exporter files import and re-export `research_export_errors.dart`. `generateCsvReport` throws `const InsufficientData()` when `records.isEmpty`; the PDF exporter retains its two-observation requirement.

- [ ] **Step 4: Run the focused research tests and verify GREEN**

Run the Step 2 command.

Expected: all focused exporter tests pass.

- [ ] **Step 5: Write failing Firestore emulator cases**

Add explicit assertions that:

- registered owners cannot add, change, or remove `points`, `totalPoints`, or `gamesPlayed` on `users/{uid}`;
- registered owners can change only validated profile fields on a legacy document while counters remain unchanged;
- anonymous identities cannot read or write `users`, `state`, `purchased_items`, `categories`, or category words;
- registered and anonymous clients cannot create/update/delete shared `vocabulary` or `global_words`;
- signed-in users may retain read-only access to shared curated vocabulary required by the current quiz path;
- registered owner and cross-owner behavior remains least-privilege.

- [ ] **Step 6: Run the Firestore emulator suite and verify RED**

Run:

```powershell
$env:NODE_PATH='C:\Users\Phet\Documents\LexiQuest\node_modules'
npm run test:rules
```

Expected: the new assertions expose the current writable legacy counters, anonymous private records, and registered shared-word creation.

- [ ] **Step 7: Apply the minimal authorization rules**

Implement these exact boundaries:

```javascript
// users/{uid}
// registered owner read/create only; updates may affect profile fields only.
request.resource.data.diff(resource.data).affectedKeys()
  .hasOnly(['first_name', 'last_name', 'email', 'age'])

// state, purchased_items, categories, and category words
// replace write/read identity checks with isRegisteredUser() plus owner scope.

// vocabulary and global_words
allow read: if isSignedIn();
allow create, update, delete: if false;
```

Preserve strict create validation, immutable `createdAt`, legacy counter values already stored on profile documents, state wallpaper-only updates, owner legacy reads, and the recursive default deny.

- [ ] **Step 8: Re-run the Firestore emulator suite and verify GREEN**

Run the Step 6 command.

Expected: every economy, anonymous, shared-curated, owner-isolation, and telemetry case passes.

- [ ] **Step 9: Reconcile security documentation**

Document that authenticated anonymous guests may enter the product shell and read shared curated content but cannot create remote private/shared learning records. Document that `users` legacy counters are preserved read-only to clients and that deployed policy parity remains unverified. Remove the obsolete statement that Supabase migrations are absent.

- [ ] **Step 10: Run focused analysis and commit each reviewed slice**

Run:

```powershell
flutter analyze
git diff --check
```

Commit research export and Firestore authorization as separate reviewable commits:

```powershell
git add -- `
  lib/services/research_export_errors.dart `
  lib/services/research_data_exporter_service.dart `
  lib/services/research_report_pdf_exporter_service.dart `
  test/services/research_data_exporter_service_test.dart `
  test/services/research_report_pdf_exporter_service_test.dart
git commit -m "fix(research): reject empty CSV exports"

git add -- `
  firestore.rules `
  test/security/firestore-rules.test.cjs `
  docs/security/firestore-access-inventory.md `
  docs/security/progress-authority.md `
  docs/security/2026-07-26-stabilization-gate.md
git commit -m "fix(firestore): close anonymous and shared write boundaries"
```

### Task 3: Publish the candidate to PR #3 without rewriting history

**Files:**
- Modify remotely: branch `feature/production-vertical-slices`
- Modify remotely: PR #3 body and review request

**Interfaces:**
- Consumes: clean candidate SHA and successful Task 2 candidate audit.
- Produces: PR #3 head exactly equal to the candidate SHA.

- [ ] **Step 1: Re-read remote state immediately before push**

Run:

```powershell
$remoteHead = (git ls-remote origin refs/heads/feature/production-vertical-slices).Split("`t")[0]
$prHead = gh pr view 3 --json headRefOid --jq .headRefOid
$remoteHead
$prHead
```

Expected: both values equal `f66d0316daff57c83ed972a11f6425cb326f482a`. If either differs, stop and audit the new commits before pushing.

- [ ] **Step 2: Fast-forward the PR branch**

Run:

```powershell
git push origin HEAD:refs/heads/feature/production-vertical-slices
```

Expected: a normal fast-forward update; no `--force` option is used.

- [ ] **Step 3: Verify remote and PR heads**

Run:

```powershell
$candidate = git rev-parse HEAD
$remoteHead = (git ls-remote origin refs/heads/feature/production-vertical-slices).Split("`t")[0]
$prHead = gh pr view 3 --json headRefOid --jq .headRefOid
if ($candidate -ne $remoteHead -or $candidate -ne $prHead) { throw "PR #3 head mismatch" }
```

Expected: all three SHAs are identical.

- [ ] **Step 4: Replace the stale PR body with current evidence and limitations**

Create a temporary Markdown file outside the repository containing:

```markdown
## Release A completion
- Research exporters fail closed on insufficient observations.
- Fabricated research outcomes and production research navigation are removed.
- Remote economy, purchases, leaderboards, and client-authoritative rewards remain disabled.
- Firestore denies client economy counter and purchase writes while preserving owner legacy reads and wallpaper-only preference updates.

## Required gates
- CI, OSV, Gitleaks, APK, local verification, deployed-policy parity, owner review, and security closure must refer to the same head SHA.
- OSV risk acceptance is limited to GHSA-mh99-v99m-4gvg and GHSA-w5hq-g745-h8pq through 2026-10-26.
- Research mode and remote research reporting remain disabled.

## Operator-controlled blockers
- Non-author approval and main branch protection are required before merge.
- Firebase/Storage/Supabase deployed-policy parity requires authenticated owner access.
```

Run:

```powershell
$prBodyPath = 'C:\Users\Phet\AppData\Local\Temp\lexiquest-pr3-release-a.md'
if (-not (Test-Path -LiteralPath $prBodyPath -PathType Leaf)) {
  throw "PR body file is missing: $prBodyPath"
}
gh pr edit 3 --body-file $prBodyPath
gh pr edit 3 --add-reviewer Phoomxo
Remove-Item -LiteralPath $prBodyPath
```

Expected: PR body updated and a non-author owner review requested. If GitHub rejects the reviewer request, record the exact API response and leave the review gate open.

### Task 4: Run local release verification on the frozen candidate SHA

**Files:**
- Read: `tool/cli/verify.ps1`
- Read: `package.json`
- Read: `osv-scanner.toml`
- Generated and ignored: Flutter/Gradle build outputs

**Interfaces:**
- Consumes: PR #3 head from Task 3.
- Produces: local verification receipts tied to the exact SHA.

- [ ] **Step 1: Capture the frozen SHA and assert a clean worktree**

Run:

```powershell
$releaseSha = git rev-parse HEAD
if (git status --porcelain) { throw "Candidate worktree is dirty" }
$releaseSha
```

Use `apply_patch` to write exactly that SHA plus a trailing newline to the ignored receipt `.superpowers/sdd/release-a-frozen-sha.txt`. Every later task reloads this receipt and compares it to the PR head before trusting a check.

- [ ] **Step 2: Run the Firestore emulator contract**

Run:

```powershell
$env:NODE_PATH='C:\Users\Phet\Documents\LexiQuest\node_modules'
npm run test:rules
```

Expected: all rule tests pass, including economy mutation denial, purchase immutability, owner reads, and cross-owner denial.

- [ ] **Step 3: Run the CPU-safe full repository verification**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\cli\verify.ps1
```

Expected: CLI contracts, dependency resolution, Dart format, Flutter analysis/tests, all three backend CPU suites, debug APK, and read-only GPU doctor pass.

- [ ] **Step 3A: Run the local Supabase policy contract**

Run:

```powershell
supabase db start
try {
  supabase db reset --local --no-seed
  supabase db lint --local --level warning
  supabase db advisors --local --type security --level warn --fail-on error
  Get-Content -Raw test/security/supabase_storage_contract.sql |
    docker exec -i supabase_db_lexiquest-local `
      psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f -
} finally {
  supabase stop --no-backup
}
```

Expected: migration/reset, schema lint, security advisors, and the SQL storage contract pass without persistent probe data.

- [ ] **Step 4: Run commit-scoped secret scanning**

Run:

```powershell
gitleaks git --log-opts="f66d0316daff57c83ed972a11f6425cb326f482a..HEAD" --config .gitleaks.toml --redact --no-banner --exit-code 1
```

Expected: no leaks.

- [ ] **Step 5: Scan every lockfile with the repository OSV policy**

Run:

```powershell
osv-scanner scan source --config osv-scanner.toml `
  --lockfile package-lock.json `
  --lockfile pubspec.lock `
  --lockfile backend/ai_api/uv.lock `
  --lockfile backend/voice_api/uv.lock `
  --lockfile backend/lexiquest_lm/uv.lock `
  --lockfile backend/lexiquest_lm/deploy/hf_space/requirements.txt
```

Expected: no unignored vulnerability; output may filter only the two documented exceptions.

- [ ] **Step 6: Run one bounded real OmniVoice/Firebase smoke only when credentials are already available**

Preflight:

```powershell
if ($env:LEXIQUEST_E2E_ENABLE -ne '1') { throw "LEXIQUEST_E2E_ENABLE is not enabled" }
if ([string]::IsNullOrWhiteSpace($env:LEXIQUEST_E2E_TEST_TOKEN)) { throw "LEXIQUEST_E2E_TEST_TOKEN is unavailable" }
if ([string]::IsNullOrWhiteSpace($env:GOOGLE_APPLICATION_CREDENTIALS)) { throw "Firebase credentials are unavailable" }
```

Run:

```powershell
uv run --project backend/voice_api --frozen --no-sync --all-groups `
  pytest backend/voice_api/tests/integration/test_firebase_omnivoice_e2e.py -q
```

Expected: exactly one bounded request returns a non-empty mono RIFF/WAV at 24 kHz with duration below 30 seconds. If credential preflight fails, record this as an operator-controlled gate; do not substitute a fake smoke.

### Task 5: Monitor GitHub PR gates on the same SHA

**Files:**
- No repository changes.

**Interfaces:**
- Consumes: published candidate SHA.
- Produces: completed CI, OSV, and Gitleaks check receipts for that SHA.

- [ ] **Step 1: Poll PR checks in bounded calls**

Run:

```powershell
$releaseSha = (Get-Content -Raw .superpowers/sdd/release-a-frozen-sha.txt).Trim()
$prHead = gh pr view 3 --json headRefOid --jq .headRefOid
if ($prHead -ne $releaseSha) { throw "PR #3 head changed" }
gh pr checks 3
```

Repeat the one-shot command after bounded waits while checks are pending; do not hold an unbounded watcher. Expected pre-merge contexts are `ci`, `Gitleaks`, and `osv-scanner-pr / osv-scan`. The scheduled workflow context `osv-scanner` runs on `main`/schedule and is verified on the merge commit after Task 8, not substituted for a PR-head check.

- [ ] **Step 2: Verify every check belongs to the frozen head**

Run:

```powershell
$releaseSha = (Get-Content -Raw .superpowers/sdd/release-a-frozen-sha.txt).Trim()
$pr = gh pr view 3 --json headRefOid,statusCheckRollup | ConvertFrom-Json
if ($pr.headRefOid -ne $releaseSha) { throw "PR #3 head changed" }
$required = @('ci', 'Gitleaks', 'osv-scanner-pr / osv-scan')
foreach ($name in $required) {
  $check = @($pr.statusCheckRollup | Where-Object name -eq $name)
  if ($check.Count -ne 1 -or $check[0].status -ne 'COMPLETED' -or
      $check[0].conclusion -ne 'SUCCESS') {
    throw "Required PR check is not successful: $name"
  }
}
```

Expected: `headRefOid` equals `$releaseSha`; every required PR context exists exactly once and has conclusion `SUCCESS`.

### Task 6: Run Codex Security closure and Deep Security Scan

**Files:**
- Generated outside repository: Codex Security scan artifacts.

**Interfaces:**
- Consumes: exact base `f66d0316daff57c83ed972a11f6425cb326f482a` and head `$releaseSha`.
- Produces: a completed security-diff closure scan and a completed codebase Deep Security Scan with no unresolved validated Critical/High finding.

- [ ] **Step 1: Run security-diff closure**

Load the immutable head from `.superpowers/sdd/release-a-frozen-sha.txt`, prove it still equals PR #3 `headRefOid`, then use the Codex Security `security-diff-scan` workflow for base `f66d0316daff57c83ed972a11f6425cb326f482a` and that exact head. Focus on authentication, authorization, owner isolation, score/economy integrity, research-data integrity, CSV/PDF injection or fabrication, API/AI/voice boundaries, secrets, and supply chain.

Expected: the previous client-only economy finding is no longer reproducible and every reportable finding has canonical artifacts.

- [ ] **Step 2: Run repository-wide Deep Security Scan**

Use the Codex Security `deep-security-scan` workflow on the same immutable candidate commit read from the receipt. Do not claim zero-day absence; report only validated findings and coverage.

Expected: scan completes rather than being cancelled. Any validated Critical/High finding returns the workflow to implementation and requires a fresh candidate SHA plus complete rerun of Tasks 4–6.

### Task 7: Satisfy owner-controlled release gates

**Files:**
- No repository changes unless deployed policy differs from the reviewed files.

**Interfaces:**
- Consumes: owner/admin access and completed verification receipts.
- Produces: non-author approval, protected `main`, OSV risk acceptance, and deployed-policy parity.

- [ ] **Step 1: Verify non-author approval**

Run:

```powershell
$releaseSha = (Get-Content -Raw .superpowers/sdd/release-a-frozen-sha.txt).Trim()
$pr = gh pr view 3 --json headRefOid,reviews,reviewDecision,reviewRequests |
  ConvertFrom-Json
if ($pr.headRefOid -ne $releaseSha) { throw "PR #3 head changed" }
$pr | ConvertTo-Json -Depth 8
```

Expected: at least one approving review from a user other than PR author `Petch1910`.

- [ ] **Step 2: Verify main branch protection**

Run with an admin-authorized GitHub identity:

```powershell
gh api repos/Phoomxo/LexiQuest/branches/main/protection
gh api repos/Phoomxo/LexiQuest/rulesets
```

Expected: required PR review, at least one approval, required `ci`, `Gitleaks`, and `osv-scanner-pr / osv-scan` contexts, conversation resolution, strict up-to-date branch, force-push denial, deletion denial, and merge commits permitted. A `404` plus an empty ruleset list leaves the gate open.

- [ ] **Step 3: Record OSV owner acceptance**

Add an owner-authored PR comment:

```text
Risk accepted through 2026-10-26 for GHSA-mh99-v99m-4gvg and GHSA-w5hq-g745-h8pq under osv-scanner.toml. No dependency override is authorized. Re-evaluate and remove each exception when a safe upstream dependency tree ships.
```

Verify:

```powershell
gh pr view 3 --comments
```

- [ ] **Step 4: Verify deployed Firebase and Supabase policy parity**

Before authentication, the owner supplies the exact Firebase project/database/Storage bucket and Supabase project ref/data region. Authenticate using owner-controlled CLI or ADC sessions without copying credentials into the repository. Retrieve active Firebase Rules releases/rulesets through supported Firebaserules API/admin tooling and query deployed Supabase `storage.buckets`, `pg_class`, and `pg_policies` through read-only access. Compare normalized deployed sources/state to `firestore.rules`, `storage.rules`, and `supabase/migrations/20260727000000_image_bucket_public_readonly.sql`.

Write a redacted operator receipt outside the repository containing candidate SHA, exact non-secret target identifiers, identity name, timestamp, repository artifact SHA-256 hashes, deployed artifact hashes, semantic diff result, and privileged Admin SDK/service-role writer inventory. Expected: no deployed rule or bypass writer is broader than the reviewed Release A policy. If target binding, access, export, or parity is unavailable, do not merge.

### Task 8: Merge Release A and verify main

**Files:**
- Remote Git history only.

**Interfaces:**
- Consumes: every Task 4–7 gate on the same SHA.
- Produces: one merge commit on `main`.

- [ ] **Step 1: Recheck the terminal gate immediately before merge**

Run:

```powershell
$releaseSha = (Get-Content -Raw .superpowers/sdd/release-a-frozen-sha.txt).Trim()
$pr = gh pr view 3 --json headRefOid,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup |
  ConvertFrom-Json
if ($pr.headRefOid -ne $releaseSha) { throw "PR #3 head changed" }
if ($pr.mergeable -ne 'MERGEABLE' -or $pr.mergeStateStatus -ne 'CLEAN' -or
    $pr.reviewDecision -ne 'APPROVED') {
  throw "PR #3 terminal gate is not satisfied"
}
```

Expected: unchanged frozen SHA, mergeable, clean, approved, and all checks successful.

- [ ] **Step 2: Merge using a merge commit**

Run:

```powershell
gh pr merge 3 --merge --match-head-commit $releaseSha
```

Expected: PR #3 merged without squash/rebase and the remote feature branch retained.

- [ ] **Step 3: Verify ancestry and push-triggered main checks**

Run:

```powershell
$mergeSha = gh pr view 3 --json mergeCommit --jq .mergeCommit.oid
$remoteMain = gh api repos/Phoomxo/LexiQuest/commits/main --jq .sha
if ($remoteMain -ne $mergeSha) { throw "main does not point to the PR merge commit" }
$runs = gh run list --branch main --commit $mergeSha --event push `
  --json databaseId,workflowName,status,conclusion,headSha | ConvertFrom-Json
if (-not $runs) { throw "No main push runs found for merge SHA" }
foreach ($run in $runs) {
  gh run watch $run.databaseId --exit-status
  if ($LASTEXITCODE -ne 0) { throw "main workflow failed: $($run.workflowName)" }
}
```

Expected: `main` points to the merge commit; push-triggered CI, Gitleaks, and scheduled/main OSV contexts associated with the merge commit complete successfully.

### Task 9: Post-merge cleanup without deleting audit history

**Files:**
- Create in a separate PR: `.gitattributes`

**Interfaces:**
- Consumes: verified Release A merge SHA.
- Produces: audited legacy PR decisions and deterministic line endings.

- [ ] **Step 1: Audit old PR patches against merged main**

Run for PRs `1`, `2`, `4`, and `5`:

```powershell
gh pr diff 1
gh pr diff 2
gh pr diff 4
gh pr diff 5
```

Then fetch `main` and use `git cherry` against each head branch. Close only when no unique production patch remains; reference the Release A merge SHA in each closing comment.

- [ ] **Step 2: Normalize generated plugin line endings in a separate branch**

Create a new `codex/line-ending-normalization` worktree from merged `main`. Add:

```gitattributes
* text=auto
*.dart text eol=lf
*.yaml text eol=lf
*.yml text eol=lf
*.json text eol=lf
*.toml text eol=lf
*.ps1 text eol=crlf
linux/flutter/generated_plugin_registrant.* text eol=lf
linux/flutter/generated_plugins.cmake text eol=lf
macos/Flutter/GeneratedPluginRegistrant.swift text eol=lf
windows/flutter/generated_plugin_registrant.* text eol=crlf
windows/flutter/generated_plugins.cmake text eol=crlf
```

Normalize only the explicitly covered files, verify semantic diffs are empty, run Flutter dependency resolution and analysis, then open a separate PR.

- [ ] **Step 3: Preserve prototype and legacy branches**

Do not delete `feature/associative-reading-loop`, OmniVoice branches, Release A audit branches, or their worktrees until Release B and the final audit are complete.
