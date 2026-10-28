# Release A plan command-safety fix report

## Result

- Commit: `9c7e606a297d26d7c6d068de269baed25972aac3`
- Commit subject: `docs: close Release A plan review findings`
- Tracked scope: `docs/superpowers/plans/2026-07-28-release-a-production-completion.md` only
- No production code, cloud state, PR state, or remote branch was changed.

## Changes

1. Wrapped every local Supabase/Docker native command in explicit
   `$LASTEXITCODE` assertions, including start, reset, lint, advisors, SQL
   contract execution, and cleanup. Cleanup remains in `finally`.
2. Replaced the display-only PR review output with assertions requiring the
   frozen head, `reviewDecision == APPROVED`, and at least one `APPROVED`
   review whose author is not `Petch1910`.
3. Added an idempotent OSV acceptance flow:
   - verifies the repository owner and frozen PR head;
   - accepts an existing qualifying owner/non-author comment;
   - permits a missing comment to be created only from an authenticated
     repository-owner/non-author session;
   - re-fetches and asserts both GHSA IDs, `2026-10-26`, and the frozen SHA.
4. Replaced the loose post-merge workflow loop with exact assertions for one
   `CI`, one `Secret Scan`, and one `OSV Scanner` push run on the merge SHA,
   followed by watch and final status/conclusion/SHA verification.

## Verification

- Parsed all 30 PowerShell fenced blocks with the Windows PowerShell AST
  parser: 0 syntax errors.
- Counted 70 Markdown fence markers: balanced.
- Verified required workflow names, GHSA IDs, expiry, review assertion, and
  Supabase failure assertions are present.
- `git diff --check`: passed before staging.
- `git diff --cached --check`: passed before commit.
- Staged and committed exactly one tracked file.
- GitHub CLI field validation:
  - `gh repo view ... --json owner` returned owner `Phoomxo`;
  - PR JSON fields for author, comments, head, reviews, and review decision
    were accepted;
  - run-view fields `databaseId`, `workflowName`, `status`, `conclusion`, and
    `headSha` were accepted (the deliberate run ID `0` returned only the
    expected HTTP 404).

## Preserved fail-closed gates

- The plan does not claim that `main` protection exists.
- The plan does not claim a non-author approval exists.
- The plan does not claim OSV owner acceptance exists.
- The plan does not claim deployed Firebase/Storage/Supabase parity exists.
- Missing owner credentials or missing evidence leaves the relevant gate open
  and prevents merge.
