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

- [ ] **Step 1: Verify isolation and cleanliness**

Run:

```powershell
git rev-parse --git-dir
git rev-parse --git-common-dir
git branch --show-current
git status --short
```

Expected: linked worktree, branch `codex/release-a-economy-lockdown`, and no uncommitted files before adding this plan.

- [ ] **Step 2: Verify direct ancestry and enumerate the candidate commits**

Run:

```powershell
git merge-base --is-ancestor f66d0316daff57c83ed972a11f6425cb326f482a HEAD
git log --reverse --oneline f66d0316daff57c83ed972a11f6425cb326f482a..HEAD
```

Expected: exit `0` and the integrity/security chain beginning with research observation fixes and ending with `fix(security): close client-authoritative economy writes`.

- [ ] **Step 3: Prove the alternate economy worktree has no missing production behavior**

Run:

```powershell
git diff --name-status 04e2f8f2183e15bf01cf4d10e98b84e9d2d75f7c 212764410714e590b296aa1f8d63e28a77bb4af2
```

Expected: differences are confined to research-integrity files because commit `04e2f8f` already contains the final economy behavior from the alternate branch.

- [ ] **Step 4: Commit this execution plan**

Run:

```powershell
git add -- docs/superpowers/plans/2026-07-28-release-a-production-completion.md
git diff --cached --check
git commit -m "docs: add Release A production completion plan"
```

Expected: one documentation commit and a clean worktree.

### Task 2: Run independent candidate, GitHub, and deployment-readiness audits

**Files:**
- Create ignored report: `.superpowers/sdd/audits/release-a-candidate.md`
- Create ignored report: `.superpowers/sdd/audits/release-a-github.md`
- Create ignored report: `.superpowers/sdd/audits/release-a-deployment-readiness.md`

**Interfaces:**
- Consumes: frozen candidate SHA from Task 1.
- Produces: three read-only audit receipts with exact blockers and no repository or cloud mutations.

- [ ] **Step 1: Dispatch three bounded read-only agents**

Each agent must inspect only its assigned domain: candidate/spec coverage, GitHub PR/protection state, or deployed-policy readiness. Agents write only their assigned ignored report.

- [ ] **Step 2: Review all three receipts**

Run:

```powershell
Get-Content .superpowers/sdd/audits/release-a-candidate.md
Get-Content .superpowers/sdd/audits/release-a-github.md
Get-Content .superpowers/sdd/audits/release-a-deployment-readiness.md
```

Expected: no unresolved code-integrity blocker. External permission or credential blockers must be carried into Tasks 5 and 7 rather than silently waived.

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
gh pr edit 3 --body-file $prBodyPath
gh pr edit 3 --add-reviewer Phoomxo
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

### Task 5: Monitor GitHub gates on the same SHA

**Files:**
- No repository changes.

**Interfaces:**
- Consumes: published candidate SHA.
- Produces: completed CI, OSV, and Gitleaks check receipts for that SHA.

- [ ] **Step 1: Watch PR checks**

Run:

```powershell
gh pr checks 3 --watch --interval 10
```

Expected: `ci`, `Gitleaks`, `osv-scanner-pr / osv-scan`, and `osv-scanner` complete successfully.

- [ ] **Step 2: Verify every check belongs to the frozen head**

Run:

```powershell
gh pr view 3 --json headRefOid,statusCheckRollup
```

Expected: `headRefOid` equals `$releaseSha`; no required check is pending, skipped, cancelled, or failed.

### Task 6: Run Codex Security closure and Deep Security Scan

**Files:**
- Generated outside repository: Codex Security scan artifacts.

**Interfaces:**
- Consumes: exact base `f66d0316daff57c83ed972a11f6425cb326f482a` and head `$releaseSha`.
- Produces: a completed security-diff closure scan and a completed codebase Deep Security Scan with no unresolved validated Critical/High finding.

- [ ] **Step 1: Run security-diff closure**

Use the Codex Security `security-diff-scan` workflow for the exact immutable revision range. Focus on authentication, authorization, owner isolation, score/economy integrity, research-data integrity, CSV/PDF injection or fabrication, API/AI/voice boundaries, secrets, and supply chain.

Expected: the previous client-only economy finding is no longer reproducible and every reportable finding has canonical artifacts.

- [ ] **Step 2: Run repository-wide Deep Security Scan**

Use the Codex Security `deep-security-scan` workflow on the same candidate commit. Do not claim zero-day absence; report only validated findings and coverage.

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
gh pr view 3 --json reviews,reviewDecision,reviewRequests
```

Expected: at least one approving review from a user other than PR author `Petch1910`.

- [ ] **Step 2: Verify main branch protection**

Run with an admin-authorized GitHub identity:

```powershell
gh api repos/Phoomxo/LexiQuest/branches/main/protection
```

Expected: required PR review, at least one approval, required CI/Gitleaks/OSV contexts, conversation resolution, strict up-to-date branch, force-push denial, and deletion denial. A `404` under a `WRITE`-only identity does not prove protection and leaves the gate open.

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

Authenticate using owner-controlled CLI sessions without copying credentials into the repository. Export or retrieve the deployed Firestore, Storage, and Supabase policies through supported admin tooling, compare them to `firestore.rules`, repository Storage policy, and Supabase migrations, and record only hashes/diffs without secrets.

Expected: no deployed rule is broader than the reviewed repository policy. If access is unavailable or parity differs, do not merge.

### Task 8: Merge Release A and verify main

**Files:**
- Remote Git history only.

**Interfaces:**
- Consumes: every Task 4–7 gate on the same SHA.
- Produces: one merge commit on `main`.

- [ ] **Step 1: Recheck the terminal gate immediately before merge**

Run:

```powershell
gh pr view 3 --json headRefOid,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup
```

Expected: unchanged frozen SHA, mergeable, clean, approved, and all checks successful.

- [ ] **Step 2: Merge using a merge commit**

Run:

```powershell
gh pr merge 3 --merge --delete-branch=false
```

Expected: PR #3 merged without squash/rebase and the remote feature branch retained.

- [ ] **Step 3: Verify ancestry and push-triggered main checks**

Run:

```powershell
$mergeSha = gh pr view 3 --json mergeCommit --jq .mergeCommit.oid
gh api repos/Phoomxo/LexiQuest/commits/$mergeSha --jq .sha
gh run list --branch main --limit 10
```

Expected: the merge commit exists on `main`; CI, OSV, and Gitleaks for `main` complete successfully.

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
