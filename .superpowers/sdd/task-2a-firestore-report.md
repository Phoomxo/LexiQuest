# Task 2A-F Firestore authorization receipt

Date: 2026-07-29 (Asia/Bangkok)
Base: `9c7e606a297d26d7c6d068de269baed25972aac3`
Outcome: fixed locally; deployment parity remains an external Release A gate
Commit: `844563f2a8899ff1b90f14b141492eedf009c23d`

## Patch contract

- Vulnerable boundary: client Firestore rules used `isSignedIn()` for private
  owner records, so a Firebase anonymous guest could act as an owner.
- Vulnerable boundary: `users/{uid}` update accepted legacy economy counters,
  allowing a registered client to add, change, or remove `points`,
  `totalPoints`, and `gamesPlayed`.
- Vulnerable boundary: registered clients could create shared `vocabulary`
  and `global_words` documents.
- Security invariant: remote private learning/economy records require a
  matching non-anonymous UID; client economy counters and shared curated
  collections are not client-authoritative.
- Preserved behavior: registered profile create/update/read, legacy counter
  reads with counters unchanged, owner state wallpaper update, owner legacy
  purchase reads/query, registered private category/word CRUD, registered
  telemetry create-only behavior, and registered/anonymous reads of
  admin-seeded shared content.
- Narrow enforcement point: `firestore.rules`; no production Dart caller,
  dependency, backend, or cloud state was changed.

## RED evidence

Rules were unchanged when this command ran:

```powershell
$env:NODE_PATH='C:\Users\Phet\Documents\LexiQuest\node_modules'
npm run test:rules
```

Result: exit `1`; 41 tests, 24 passed, 17 failed.

The 17 expected failures were:

- nine registered-owner counter cases covering add/change/remove for
  `points`, `totalPoints`, and `gamesPlayed`;
- one invalid blank resulting profile accepted;
- five anonymous private-record reads accepted (`users`, `state`,
  `purchased_items`, `categories`, and nested category words);
- two registered shared-content creates accepted (`vocabulary` and
  `global_words`).

Each failed because `assertFails(...)` observed the vulnerable request
succeeding. Existing positive controls remained green during RED.

## GREEN implementation

- Replaced `isSignedIn()` with `isRegisteredUser()` at `users`, `state`,
  `purchased_items`, `categories`, and nested category-word owner boundaries.
- Replaced the `users` whole-document update allowlist with a diff allowlist
  restricted to `first_name`, `last_name`, `email`, and `age`.
- Kept `createdAt` immutable and validated the complete resulting profile.
- Made `vocabulary` and `global_words` signed-in read-only; Admin SDK imports
  remain possible because privileged Admin writes bypass client rules.
- Added emulator coverage for malicious and legitimate controls.
- Reconciled the three authorized security documents, including the existing
  Supabase migration/local SQL contract and the still-unverified deployed
  policy/privileged-writer gate.

Initial GREEN result after the minimal rules change:

```text
npm run test:rules
exit 0; 41/41 tests passed; 5/5 suites passed
```

Fresh final GREEN result after positive registered-owner coverage was added:

```text
npm run test:rules
exit 0; 43/43 tests passed; 6/6 suites passed
```

## Ordered verification

### Applicability and buildability

- `node --check test/security/firestore-rules.test.cjs`
  - exit `0`, no syntax errors.
- `powershell -NoProfile -ExecutionPolicy Bypass -File
  .\tool\cli\tests\firestore-rules-security.tests.ps1`
  - exit `0`; 21 passed, 0 failed.

### Security closure

- Final Firebase emulator run: exit `0`; 43 passed, 0 failed.
- The original owner-counter, anonymous-private, and registered shared-create
  requests now receive Firestore `PERMISSION_DENIED`.
- Add/change/remove counter variants prove that field transforms and legacy
  fields cannot bypass the update diff boundary.
- Read/create/update/delete guest variants cover every required private
  collection.

### Preserved behavior

- Registered profile create/read passes.
- Validated profile update over a legacy document passes and preserves all
  three counters exactly.
- Registered category and nested-word create/read/update/delete passes while
  cross-owner reads fail.
- Existing wallpaper-only update, legacy state/purchase reads and query,
  telemetry create-only, cross-owner denial, shared signed-in reads, and
  recursive default deny tests pass.

### Repository hygiene

- `git diff --check`
  - exit `0`; no whitespace errors.
  - Git emitted only the existing Windows checkout warning that LF would be
    replaced by CRLF if Git later rewrites the five files.
- `git diff --name-only`
  - exactly the five authorized tracked files:
    - `firestore.rules`
    - `test/security/firestore-rules.test.cjs`
    - `docs/security/firestore-access-inventory.md`
    - `docs/security/progress-authority.md`
    - `docs/security/2026-07-26-stabilization-gate.md`

## Self-review

- No production Dart, dependency manifest, generated file, or unrelated
  policy was changed.
- `products` remains signed-in read-only, `quiz` remains denied,
  `voice_telemetry_events` remains registered-user create-only,
  `state` remains create/delete denied and wallpaper-only update, and
  `purchased_items` remains client-write denied.
- Shared read access was intentionally preserved for both registered and
  Firebase anonymous signed-in identities.
- Tests seed legacy/Admin documents only through
  `withSecurityRulesDisabled`.
- No push, cloud deployment, credential access, or force/rebase operation was
  performed.

## Remaining uncertainty

- Repository/emulator evidence does not prove that deployed Firestore,
  Firebase Storage, or Supabase policies match this commit.
- Firebase Admin SDK and other privileged writers bypass these client rules;
  their deployed inventory and policy parity remain required before merge.
- The LF/CRLF warning is a checkout configuration notice, not a diff error;
  no line-ending normalization was attempted in this task.

## Reviewer defense-in-depth follow-up

Base: `844563f2a8899ff1b90f14b141492eedf009c23d`
Commit: `57e12ca940c88cb64fb2843f6ba60fa85d9e1675`
Requested invariant: a registered-only rule must fail closed when an
authenticated token lacks `firebase.sign_in_provider`.

### Harness diagnosis

The first test passed `{}` as token options. It produced an apparent RED, but
the first GREEN attempt still failed after the rule was hardened. Inspection
of the installed Firebase test runtime showed why:

- `RulesTestEnvironment.authenticatedContext` forwards the token options.
- `@firebase/util` `createMockUserToken` supplies
  `firebase.sign_in_provider = 'custom'` by default, then overlays provided
  token options.

Therefore `{}` did not model a missing provider. The test was corrected to
pass `{ firebase: {} }`, which overrides the default Firebase claim while
intentionally omitting `sign_in_provider`. The prior fail-open rule was
restored with `apply_patch` before rerunning RED, so the authoritative
red-green cycle remained valid.

### Authoritative RED

Command:

```powershell
$env:NODE_PATH='C:\Users\Phet\Documents\LexiQuest\node_modules'
npm run test:rules
```

State: corrected `{ firebase: {} }` test plus the pre-fix
`isRegisteredUser()` implementation.

Result: exit `1`; 45 tests, 44 passed, 1 failed. The sole failure was
`denies a provider-less authenticated token from private records`, because
the provider-less identity could read its seeded `users/{uid}` profile.

### Minimal fix and preserved controls

- `isRegisteredUser()` now requires both `firebase` and
  `firebase.sign_in_provider` claims and rejects `anonymous`.
- Normal registered test identities explicitly use the `password` provider.
- A positive `custom` provider profile create/read test was added.
- Existing anonymous shared-content read tests remain unchanged.

### Final GREEN and verification

- `npm run test:rules`
  - exit `0`; 45 passed, 0 failed; 6 suites passed.
  - The provider-less private read now receives `PERMISSION_DENIED`.
  - Password/custom registered access and anonymous shared reads pass.
- `powershell -NoProfile -ExecutionPolicy Bypass -File
  .\tool\cli\tests\firestore-rules-security.tests.ps1`
  - exit `0`; 21 passed, 0 failed.
- `node --check test/security/firestore-rules.test.cjs`
  - exit `0`.
- `git diff --check`
  - exit `0`; only the existing LF/CRLF checkout notices were emitted.
- Scope inspection:
  - only `firestore.rules`;
  - only `test/security/firestore-rules.test.cjs`.

No push, cloud mutation, dependency change, or line-ending normalization was
performed.
