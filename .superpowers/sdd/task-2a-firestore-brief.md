# Task 2A-F: Close anonymous, economy-counter, and shared-write boundaries

## Goal

Implement the Release A A2 authorization contract at the Firestore rules
boundary without breaking registered-owner profile updates, existing legacy
reads, or shared curated reads required by the quiz path.

## Files

- Modify: `firestore.rules`
- Modify: `test/security/firestore-rules.test.cjs`
- Modify: `docs/security/firestore-access-inventory.md`
- Modify: `docs/security/progress-authority.md`
- Modify: `docs/security/2026-07-26-stabilization-gate.md`

## Authoritative requirements

From
`docs/superpowers/specs/2026-07-27-stabilization-to-associative-reading-program-design.md`
Release A A2:

- Direct client writes to `state/{uid}.totalPoints`, user points,
  `gamesPlayed`, shop ownership, prices, and purchase ledger state are denied.
- Until an authoritative reward path exists, remote economy mutation stays
  disabled and local progress is non-spendable.
- Anonymous users cannot write shared `global_words`, curated `vocabulary`,
  economy collections, or research telemetry.
- Shared curated word creation is an admin/controlled import operation.
- User-owned private learning records are scoped to a matching non-anonymous
  UID.

## Required TDD coverage

Add emulator tests that prove:

1. A registered owner cannot add, change, or remove any of
   `points`, `totalPoints`, or `gamesPlayed` on `users/{uid}`.
2. A registered owner can update validated profile fields on a pre-existing
   legacy document containing those counters; the counters remain unchanged.
3. A registered user cannot read or update another user's profile.
4. An anonymous identity cannot read, create, update, or delete:
   - `users/{uid}`;
   - `state/{uid}`;
   - `purchased_items/{purchaseId}`;
   - `categories/{categoryId}`;
   - `categories/{categoryId}/words/{wordId}`.
5. Registered and anonymous clients cannot create, update, or delete:
   - `vocabulary/{vocabId}`;
   - `global_words/{word}`.
6. Registered and anonymous signed-in identities may read admin-seeded shared
   `vocabulary` and `global_words` documents.
7. Existing registered-owner state wallpaper-only update, owner legacy
   purchase read/query, telemetry create-only contract, cross-owner denial,
   and recursive default deny remain covered.

Use the Firebase emulator, not mocks. Seed legacy/admin documents only inside
`testEnv.withSecurityRulesDisabled`.

## RED command

After writing the new assertions and before changing rules:

```powershell
$env:NODE_PATH='C:\Users\Phet\Documents\LexiQuest\node_modules'
npm run test:rules
```

The new owner-counter, anonymous-private, and registered shared-create cases
must fail for the expected permission reason.

## Minimal rules implementation

### `users/{uid}`

- `read` and `create` require `isRegisteredUser()` and matching path UID.
- Retain the existing strict create schema and server-controlled `createdAt`.
- `update` requires a registered matching owner and:

```javascript
request.resource.data.diff(resource.data).affectedKeys()
  .hasOnly(['first_name', 'last_name', 'email', 'age'])
```

- Preserve `createdAt` unchanged.
- Validate the resulting `first_name`, `last_name`, `email`, and `age`.
- Do not use a whole-document key allowlist for updates because legacy counter
  fields already stored on the document must remain readable and unchanged.
- `delete` remains false.

### Registered private/economy records

Replace `isSignedIn()` with `isRegisteredUser()` for owner access to:

- `state/{uid}`;
- `purchased_items/{purchaseId}`;
- `categories/{categoryId}`;
- `categories/{categoryId}/words/{wordId}`.

Retain every existing owner-scope, field, diff, and immutability check.

### Shared curated collections

Use:

```javascript
match /vocabulary/{vocabId} {
  allow read: if isSignedIn();
  allow create, update, delete: if false;
}

match /global_words/{word} {
  allow read: if isSignedIn();
  allow create, update, delete: if false;
}
```

Do not add a client seeding exception. Firebase Admin SDK controlled imports
remain possible because Admin writes bypass client rules.

### Unchanged boundaries

- `products` remains client read-only.
- `voice_telemetry_events` remains registered-user create-only.
- Remote research collections remain covered by recursive default deny.
- `state` remains create/delete denied and wallpaper-only update.
- `purchased_items` remains write-denied.

## GREEN and focused verification

Run:

```powershell
$env:NODE_PATH='C:\Users\Phet\Documents\LexiQuest\node_modules'
npm run test:rules
powershell -NoProfile -ExecutionPolicy Bypass -File `
  .\tool\cli\tests\firestore-rules-security.tests.ps1
node --check test/security/firestore-rules.test.cjs
git diff --check
```

All emulator and structural contract tests must pass.

## Documentation reconciliation

- State that Firebase anonymous guest authentication exists for entry to the
  product shell and shared read-only content.
- State that anonymous users cannot persist remote private/shared learning
  records.
- State that legacy `users` counter fields are preserved but immutable to
  clients.
- State that `vocabulary` and `global_words` are admin-seeded/read-only.
- Remove the obsolete statement that the Supabase migration is absent; the
  migration and local SQL contract now exist.
- Preserve the explicit deployed-policy-parity and privileged-writer
  limitations.

## Commit

Stage only the five listed files and commit:

```text
fix(firestore): close anonymous and shared write boundaries
```

## Report

Write the full RED/GREEN/self-review report to:

`C:\Users\Phet\Documents\LexiQuest\.worktrees\release-a-economy-lockdown\.superpowers\sdd\task-2a-firestore-report.md`
