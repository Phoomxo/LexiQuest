# Pre-Release Security Sweep — 2026-08-05

A bounded, local security review of the LexiQuest repository performed before
the field-trial APK distribution. It follows the repo guardrails in
`AGENTS.md` (bounded local verification; no external/multi-agent security
scans): secret scan, dependency audit (OSV), and focused manual review of
security-critical paths.

## Scope

- Secret scan: gitleaks over the full history (504 commits).
- Dependency audit: osv-scanner over `pubspec.lock` and `package-lock.json`.
- Manual review (read-only): Firestore rules, Android manifest + build config,
  auth flows + API-key handling, local storage (Drift) + on-device model
  loading (LiteRT).

## Findings

### 1. Vulnerability fixed — brace-expansion ReDoS bypass (High → resolved)

`brace-expansion@2.1.2` reached the root npm tree transitively via
`firebase-admin → @google-cloud/firestore → google-gax → rimraf → glob →
minimatch → brace-expansion`. It is affected by
**GHSA-rgw5-rvv9-x895 / CVE-2026-69152** (ReDoS bypass of the earlier
`maxLength` mitigation, CVSS 7.5). This advisory is a *new bypass* and is
**not** covered by the previously-accepted ignore for `GHSA-mh99-v99m-4gvg`.

Reachability is narrow: the vulnerable code sits in the `rimraf`/`glob`
tooling chain, not on any network call path, and the sole project consumer is
an offline maintainer-run Firestore seed script. Still, the fix is trivial and
risk-free, so it was applied.

**Fix applied:**
- `package.json`: scoped npm override forces `brace-expansion@^2.1.4` under
  `firebase-admin`. Verified `2.1.4` (the patched release) now resolves.
- `osv-scanner.toml`: removed the now-stale `GHSA-mh99` ignore (no longer
  present in the tree); the single remaining accepted ignore is `uuid@9.0.1`
  (`GHSA-w5hq-g745-h8pq`, still documented + time-bounded to 2026-10-26).
- `tool/cli/tests/osv-config.tests.ps1`: contract updated to pin the new
  reality (one accepted ignore) and to guard against brace-expansion
  regressing back into the ignore set.

### 2. Known + accepted (documented, out of scope for this APK)

These were re-confirmed during the sweep and are **already documented** as
intentional design choices for the field trial, not regressions:

- **Client-writable point balances (`state/{uid}`, `users/{uid}`).** A signed-in
  user can self-award points within bounds. Documented in
  `docs/security/progress-authority.md` (lines 106-107); the planned hardening
  is a Firebase Callable / 2nd-gen Cloud Function owning all credit writes
  (lines 151, 160). Purchases themselves remain tamper-proof via the
  `purchaseIntegrityOk` atomic-debit rule.
- **App Check not enforced.** Rules rely on Firebase Auth only; `request.app`
  is not checked and Console enforcement is not yet on (`appCheckEnforced:
  false` in `docs/field/release-evidence-template.json`). This is the open
  Blocker 2 path tracked in `docs/runbooks/release-blockers-resolution.md` —
  enforcement is an owner action gated on SHA registration + valid-traffic
  observation, not a code change.

### 3. CLEAN surfaces (no issues)

- **Secrets:** 0 genuine leaks. gitleaks' 5 hits were all false positives
  (`WorkmanagerSyncScheduler(`/`PluginWorkmanagerClient()` misread as JWT in
  `main.dart`; `test-key-that-is-long-enough-123456` and `test-key-sentinel`
  test fixtures). No service-account private keys anywhere.
- **Dependencies:** `pubspec.lock` 0/202 vulnerable. `package-lock.json` 0
  vulnerable after the brace-expansion fix (uuid accepted-ignore documented).
- **Firestore rules:** default-deny catch-all, full `auth.uid == uid`
  isolation on every per-user path, field-allow-list + payload validators on
  all writes, create-only ledgers enforced both via `allow update, delete: if
  false` *and* payload `revision == 1` checks. No admin backdoors, no public
  grants. (31 emulator tests pass.)
- **Android build/manifest:** `allowBackup=false`, `usesCleartextTraffic=false`,
  debug-only network security config, release signing isolated from debug
  with a `whenReady` build-time gate, no exported components beyond the
  mandatory launcher activity. (15 manifest tests pass.)
- **Auth + API keys:** no shipped credentials; Gemini is true BYOK stored in
  `flutter_secure_storage` (RSA-wrapped AES-GCM, device-only) and sent as an
  `x-goog-api-key` header; Firebase ID tokens minted lazily per request as
  `Authorization: Bearer` (never in URLs/bodies/logs); URL parsing rejects
  embedded `userInfo`, query, fragment, and enforces HTTPS in release.
- **Local storage / models:** every dynamic SQL value is Drift-parameterized
  (no injection); LiteRT model is fetched over HTTPS from a hardcoded URL,
  filename-sanitized, SHA-256 verified both post-download and at runtime-open,
  CPU/XNNPACK only (no custom ops / GPU/NNAPI), input dimension-validated.
  Models are integrity-protected by APK signing + pinned hash constant.

### 4. Hygiene items (status after hardening pass — 2026-08-05)

- **Unencrypted Drift DB** (Medium, mitigated; **deferred**). Plain SQLite
  stores Firebase UID, points, SRS state, consent state. `allowBackup=false`
  blocks the easy `adb backup` path; residual exposure is rooted devices /
  forensics only. **Deferred for the field trial** — 0 real participants have
  a DB yet, `allowBackup=false` already blocks the easy extraction path, and
  an architectural change (SQLCipher via `LazyDatabase` + per-install key in
  `flutter_secure_storage`) pre-distribution risks the whole trial if it
  corrupts the DB. **Trigger to implement:** after the first trial cohort
  ships with a tested DB export/restore path, or before any cohort running on
  devices that may be rooted. Recommended approach then: `LazyDatabase`
  + `NativeDatabase` on the main isolate (cleanest, no isolate-boundary issue),
  accepting the UI-thread query cost (measured first).
- **~~Retry loop treats all non-`providerDisabled` failures as transient~~**
  (**resolved** in commit `826ce11`). The loop now hard-stops on
  `firebaseUnavailable` and `unknown` (configuration errors, not transient)
  after a single attempt; only `GuestSessionFailure.network` is retried. The
  default backoff now applies ±15% jitter to avoid thundering-herd on mass
  restart. Tests pin the new behavior.
- **~~`minSdk = 24`~~** (**resolved**). Raised to **26** (Android 8.0). Every
  plugin floor (highest is `flutter_tts` at 24) and every procured trial device
  (vivo V2041 = API 33, HONOR DNP-NX9 = API 36) are well above 26; no
  recruitment document promised Android 7+ support.

## Verification after changes

```
verify.ps1            — 11/11 gates PASS
flutter analyze       — No issues found
flutter test          — 1015/1015 pass
dart format check     — 0 changed (425 files)
gitleaks              — 0 genuine leaks (5 false positives)
osv-scanner (pub)     — 0 issues
osv-scanner (npm)     — 0 issues (1 documented accepted ignore)
security suites       — manifest 15/15, firestore 21/21, model 5/5,
                        seed 8/8, osv-config 6/6
```

## Honest bottom line

No zero-day was *claimed* — that cannot be guaranteed by any review. What this
sweep found: **one genuine vulnerability (brace-expansion ReDoS bypass), now
fixed**, plus two architectural risks that are **already documented and
accepted** for the field trial (client-writable points; App Check enforcement
pending owner action), and a short list of hygiene items tracked for later.
Secret handling, SQL parameterization, model integrity, and Android build
hardening are clean.
