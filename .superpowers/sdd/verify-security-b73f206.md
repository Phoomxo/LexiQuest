# Release A security verification receipt

- Status: PASS
- Scope: Final Verification Lane 3B only
- Timestamp (UTC): 2026-07-28T18:25:59.3730621Z
- Worktree: `C:\Users\Phet\Documents\LexiQuest\.worktrees\release-a-verify-security-b73f206`
- HEAD: `b73f206b94b217101836007d92e8444faa3e69da`
- Git tree: `70e1ed93e6986fd4b5248246644af2e21f8951b5`
- Git state: detached linked worktree; initial porcelain entry count `0`; pre-receipt porcelain entry count `0`; unstaged diff exit `0`; staged diff exit `0`
- Receipt ignore proof: exit `0`; `C:/Users/Phet/Documents/LexiQuest/.git/info/exclude:7:.superpowers/sdd/`
- Scope exclusions: no cloud writes, no credentialed OmniVoice/Firebase smoke, no code fixes, no commit, no push

## Tool versions

| Tool | Version | Exit |
| --- | --- | ---: |
| Node.js | `v24.16.0` | 0 |
| npm | `12.0.1` | 0 |
| Firebase CLI | `15.24.0` | 0 |
| Gitleaks | `8.30.1` | 0 |
| OSV-Scanner | `2.4.0` (`osv-scalibr 0.4.5`, commit `b56b5191101d5f27d4787d5583d8d01e9518a7af`) | 0 |
| Supabase CLI | `2.109.1` | 0 |
| Docker client/server | `29.5.2` / `29.5.2` | 0 |

## Firestore emulator contract

Command environment: `NODE_PATH=C:\Users\Phet\Documents\LexiQuest\node_modules`

Command: `npm run test:rules`

- Exit: `0`
- Tests: `45`
- Suites: `6`
- Passed: `45`
- Failed: `0`
- Cancelled: `0`
- Skipped: `0`
- Todo: `0`
- Node test duration: `14719.0243 ms`
- Firebase emulator wrapper: script exit `0`; emulator shut down after the run

## Structural Firestore contract

Command: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\cli\tests\firestore-rules-security.tests.ps1`

- Exit: `0`
- Passed assertions: `21`
- Failed assertions: `0`
- Status: `PASS`

## Commit-scoped Gitleaks

Command: `gitleaks git --log-opts="f66d0316daff57c83ed972a11f6425cb326f482a..HEAD" --config .gitleaks.toml --redact --no-banner --exit-code 1`

- Resolved HEAD: `b73f206b94b217101836007d92e8444faa3e69da`
- Range commits: `13`
- Bytes scanned: `145093`
- Leaks found: `0`
- Exit: `0`

## Exact six-input OSV scan

Command: `osv-scanner scan source --config osv-scanner.toml` with exactly the six inputs below.

| Input | Packages | SHA-256 |
| --- | ---: | --- |
| `package-lock.json` | 242 | `677229a3ef8566cf6026507a9de3941bba94e7ef669d6dc3611ad2b77799be0f` |
| `pubspec.lock` | 122 | `2e1ca57a5d7c27769592112dd97e47467c45deff7f5f1c507a3fb865c56fe1a5` |
| `backend/ai_api/uv.lock` | 63 | `a4df74515c13e6eb909733ff5430ab861411ee0e9c9cd3a3c92269011fde9c8d` |
| `backend/voice_api/uv.lock` | 143 | `c57d5e16cf1e102da7257ac1abc5d3c707df6fbeade488a346e1000154a02d5e` |
| `backend/lexiquest_lm/uv.lock` | 85 | `c0c3c357733cbf355f9d0cd68979098404ecd8e2b5a5cc01217055d9c199b6cd` |
| `backend/lexiquest_lm/deploy/hf_space/requirements.txt` | 8 | `a3cc365514221c7e18aea6128cc5368ff879d6839d9689266034c2f1ec20e087` |

- Inputs visited/extracted: `6` / `6`
- Package records: `663`
- Policy-filtered vulnerabilities: `2`
- Filtered IDs: `GHSA-mh99-v99m-4gvg` (plus 1 alias), `GHSA-w5hq-g745-h8pq` (plus 2 aliases)
- Unignored issues: `0`
- Result: `No issues found`
- Exit: `0`
- Policy SHA-256 (`osv-scanner.toml`): `4bf56884ba346ae2c40218ab660bbe31920eae0c4838a33ee0414cf9e45a82b1`

## Local Supabase security chain

The sequence was fail-fast inside `try`, with `supabase stop --no-backup` and a Docker running-container check in `finally`.

| Stage | Exit/result |
| --- | --- |
| `supabase db start` | 0 |
| `supabase db reset --local --no-seed` | 0 |
| `supabase db lint --local --level warning` | 0; result count 0; `No schema errors found` |
| `supabase db advisors --local --type security --level warn --fail-on error` | 0; result count 0; `No issues found` |
| SQL storage contract through local `psql -v ON_ERROR_STOP=1` | 0 |
| `supabase stop --no-backup` | 0 |
| Running containers matching `lexiquest-local` after stop | 0 |

SQL contract output counts: `BEGIN` x1, `DO` x8, `INSERT 0 1` x1, `SET` x2, `ROLLBACK` x1. The sentinel/probes were transaction-local and rolled back.

## Reviewed input hashes

| Input | Bytes | SHA-256 |
| --- | ---: | --- |
| `firestore.rules` | 15432 | `c01be0039e1fca492e12edb851c3cc1be8070791adbd4c3f703b6f6485601370` |
| `firebase.json` | 244 | `be17931415f0f2743a7829c13389715d76ddf9f90c81b1dd56721420c2f0faba` |
| `test/security/firestore-rules.test.cjs` | 21693 | `33123fcaf85714a1f2e34f39cd393c44593fb8db6aef0635daaa286655f0c331` |
| `tool/cli/tests/firestore-rules-security.tests.ps1` | 6429 | `f8fbbb20f7e69642d705814801dbfb23e6cd2f3113c06c4d2e97c8f8f4a9ede2` |
| `.gitleaks.toml` | 1362 | `ddf34f1c3fa9b7a3d941c5bdccd99c3817a208583f05f510a44fd06c5c2c25d9` |
| `supabase/config.toml` | 448 | `0677f703ee7481b1d60284742044f144bcd60f3914185c0bfb936de46f52a527` |
| `supabase/migrations/20260727000000_image_bucket_public_readonly.sql` | 2782 | `f6ed3e00364007da523ffd0dfe1c5325faef85213fa2051146befacc049cfc7e` |
| `test/security/supabase_storage_contract.sql` | 7023 | `50208ac5611d84881dec77bce6bb4cbde9c259371a53eb2c2167847da7c62736` |

## Aggregate

Every assigned Lane 3B command completed with exit `0`; all reported test/finding/failure counts are zero where required. This receipt is evidence only for commit `b73f206b94b217101836007d92e8444faa3e69da`.
