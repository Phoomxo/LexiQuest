# R5 Firestore receipt authority implementation plan and evidence

Worktree: `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`.
Branch: `feature/adventure-research`; HEAD `6968ce97ff9b383e244b17b77cf0ed0f61eaaf3d`.
This sidecar did not edit the previous 209-GREEN sync/rules scope. Subsequent
gateway/P2 review fixes are owned independently by MAIN/Mencius.

Goal: supply a read-only concrete receipt authority against the actual Firebase SDK,
bound to the same AppDatabase used by runtime composition. Never enable research,
create authority, refresh receipts, or make any server write.

Architecture: one explicit SDK factory and one injected reader/immutable document
DTO seam share the same validator. Read exactly
`field_users/{currentFirebaseUid}/research_receipts/{receiptId}` with
`GetOptions(source: Source.server)`. Reject cached or pending-write snapshots.
Require one active local owner bound to that auth UID and accepted, unwithdrawn
consent at the configured version. Snapshot before and after network await;
require unchanged identity, version, and decision timestamp. Enforce exact receipt
schema (consent 6 fields; guardianPermission/learnerAssent 4), owner, kind, active,
integer expiry at the finish clock, and exact consent version/decision. Missing,
unavailable, malformed, stale or timed-out authority returns false.

Allowed new files only:

- `lib/features/research/data/firestore_research_receipt_authority.dart`
- `test/features/research/firestore_research_receipt_authority_test.dart`
- `.superpowers/sdd/research-receipt-authority-report.md`

## API sent before implementation

```dart
factory FirestoreResearchReceiptAuthority({
  required AppDatabase database,
  required FirebaseFirestore firestore,
  required FirebaseAuth auth,
  required int consentVersion,
  required DateTime Function() nowUtc,
  Duration readTimeout = const Duration(seconds: 5),
});
```

`withReader` substitutes `currentFirebaseUid` and `ResearchReceiptReader` for
FirebaseFirestore/FirebaseAuth; other parameters identical. Reader returns
`ResearchReceiptDocument(documentPath, exists, isFromCache, hasPendingWrites, data)`
using required named fields. It is an explicit dependency-injection trust boundary,
not an independent authorization callback. No runtime config defaults are changed.
MAIN owns optional `createReceipts(AppDatabase)` runtime composition, resolving once.

Composition fragment for an explicitly configured runtime (not a default config):

```dart
createReceipts: (database) => FirestoreResearchReceiptAuthority(
  database: database,
  firestore: firestore,
  auth: auth,
  consentVersion: study.consentVersion,
  nowUtc: nowUtc,
),
```

Receipt fields are exact, with no transport wrapper:

| Kind | Allowed fields |
| --- | --- |
| guardianPermission / learnerAssent | kind, ownerId, active, expiresAtUtcMs |
| consent | the four above, consentVersion, decidedAtUtcMs |

Timeout defaults to 5 seconds and accepts only positive durations up to 10 seconds.
No cache fallback, retries, or refreshed authority is synthesized. The SDK factory
uses the supplied Firebase instances, not globals or a duplicate AppDatabase.

## TDD steps / chronology

- [x] Read active AGENTS, R5 plan, actual interface, consent/owner schema and local SDK types.
- [x] Send concrete constructor before implementation.
- [x] Write synthetic actual-DB tests first, with SDK-only fakes and injected readers.
- [x] Obtain explicit Dart/Flutter slot and observe behavioral RED (72 tests, 64 pass / 8 fail).
- [x] Implement SDK adapter and shared fail-closed validation within the new source file.
- [x] Run focused GREEN, format/analyze only these two Dart files under granted slot.
- [x] Release slot promptly; record exact commands/results/hashes and inspect scoped source.

Exact focused command (compile RED, behavioral RED, then GREEN):

```text
flutter test --no-pub test/features/research/firestore_research_receipt_authority_test.dart --reporter expanded
```

Tests cover exact 4/6 fields, missing/invalid server data, cache and pending writes,
actual local owner and consent state, identity/consent changes across await,
decision replacement, timeout/late completion, expiry/clock rollback, safe document
segments, and the genuine factory's server-only SDK call and metadata mapping.

First explicitly granted focused RED command ran with exit 1 (`+0 -1` loading
failure): provider file/types did not exist. No behavioral test executed; this is
compile evidence only, NOT behavioral RED. Slot immediately RELEASED.

After release, added declaration-level, fail-closed scaffold so the suite compiled.
Under a new explicit grant, observed 72 tests: 64 pass / 8 assertion failures,
exit 1, no compile error. Failed positive consent/guardian/assent and SDK reads,
three invalid timeout configurations and invalid consent version. Released slot.
After the user interrupted and requested an immediate confirmation run under a
fresh explicit grant, repeated the same focused command: identical 64/8 outcome,
exit 1. Released immediately again. Neither behavioral run implemented validation.

Then replaced scaffold with actual server-only SDK factory, immutable document
DTO, positive bounded timeout/config checks and shared local/server validation.
One SQL statement per pre/post snapshot joins active owners and configured-version
consent (LIMIT 2 detects competing active owners). Auth checked around each await;
all selected identity/consent pins must be unchanged. Entire operation is bounded;
late SDK responses cannot resurrect a timed-out result. No writes, logs, caches,
new local tables, receipt refreshes, or config changes. Changed null-data test's
DTO construction from const to ordinary constructor for immutable map copying.

Under the explicit GREEN grant, the focused suite passed **72/72**, exit 0.
Formatting then analysis found 10 diagnostics (3 warnings, 7 infos): two SDK
sealed-interface fake declarations, a mutable fake capture, constructor style,
and three missing braces. Fixed within the two files: factory/private constructor
preserves the public named API, braces are explicit, and mutable SDK capture lives
in a separate final-reference probe. The two SDK fake declarations have narrow,
documented `subtype_of_sealed_class` allowances to exercise the genuine factory;
no production warning or authority check is suppressed.

Exact scoped commands:

```text
dart format lib/features/research/data/firestore_research_receipt_authority.dart test/features/research/firestore_research_receipt_authority_test.dart
dart analyze lib/features/research/data/firestore_research_receipt_authority.dart test/features/research/firestore_research_receipt_authority_test.dart
```

Final analyzer: **No issues found**, exit 0 (command chunk `bf2a85`). Final focused
test rerun after formatting/style changes: **72/72**, exit 0 (chunk `468880`).
All commands completed directly; no live process/session remained. Explicit
`send_message_to_thread` RELEASE delivered to MAIN
`01a06b97-5af8-7640-b41c-b4a1a51db375` immediately after the final test. `send_input`
is not an available tool in this session. No Dart commands after release.

## Verified source snapshot

2026-09-05 08:40 UTC. Provider/test source frozen after final GREEN. Report-only
updates followed. No existing files, dependencies, generators, runtime defaults,
sync/rules or production data were changed by this sidecar. Report is under the
repository's existing ignored `.superpowers` tree; not staged or committed.

| New source path | SHA-256 |
| --- | --- |
| lib/features/research/data/firestore_research_receipt_authority.dart | 2a210d39be1ab4be1decee9ce12a4f25d6d2dd524cf1ab598564d13ca3a3c5ed |
| test/features/research/firestore_research_receipt_authority_test.dart | 07c5ca1e95c9f731d0134c830f6a0da779c74849528146dfa0e5fa7b5a94a2bf |

No full regression, full analysis, emulator, deployment or device test was run for
this sidecar. MAIN's actual runtime composition and independent review are separate
integration evidence; this 72-case suite is not end-to-end readiness.

## Release-only limits

This provider does not provision receipts, sign permits, authorize rollout or
replace the permit signature/protocol validator. Real trusted issuer provisioning,
deployment authorization and production enrollment remain external/default-off.
Unit SDK fakes do not constitute live Firestore or device/network evidence.
Before/after checks establish freshness at this call's observation points, not an
atomic lease over subsequent uploads. Callers retain their real permit/owner gate
and boundary revalidation responsibilities; this class never takes an owner lock.
Underlying SDK reads cannot be cancelled, but timeout results remain false and
late completion starts no further local reads or writes.
