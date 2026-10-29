# Durable presentation changes and Assessment isolation

Application source `853d4c13eeaa953e4564f811d94f971dd17532ea`, branch
`codex/remaining-system-readiness`, existing `cycle12-release` worktree.
Schema is v17/34 tables. Production Research remains default-off; this checkpoint
does not authorize enrollment, upload or deployment. The 8/44 catalog and frozen
EvidenceContext/EventEnvelopeV2 contracts remain unchanged.

## Implemented behavior

Standard/Adventure now switch through their actual shared Study Host. One short
transaction durably prepares the exact pending receipt before a target frame;
a separate transaction captures its actual frame after fresh authority and the
final visible-binding check. No SQLite transaction spans a UI frame. Both
renderers keep the same accepted canonical plan and original first index.

The four existing-opportunity columns retain capped ordinal, excess-transition
count, immutable Started presentation and pending canonical JSON. The first
Presented presentation stays immutable. Current presentation derives from
committed parity; Started snapshots it once. Twelve committed rendered changes
produce ten exact frozen Changed envelopes and suppression2. No Research sync
entity or outbox type was added.

Private process handles bind owner, opportunity, attempt, original receipt,
revision and target. Unknown/foreign/restarted attempts cannot manufacture ACK
or capture. A known pre-frame preparation can reconcile its lost ACK. After
possible exposure, failed capture stays uncertain and cannot be backfilled or
replaced. Exact retained committed ACK creates no new fact; a newer preparation
replaces the previous handle. The original display lease is checked around a
new capture, even when current authority has a fresh rolling lease.

Two actual RED cases showed canonical completion during final authority awaits
could pass prepare/commit. The existing active-run boundary now supports a
narrow DB-only inspection after its last participant await. It rereads actual
canonical state before the existing owner/fence, run, consent, pure trusted-time
and synchronous visibility guards. Both RED cases pass after the fix, including
missing completion sidecar. Ordinary learning still commits while pending
Research timing and completion capture remain unavailable.

Current ordinary writers and projections exclude Assessment facts from SRS,
XP, rewards, achievements, practice history, progress, Quest and Streak. The reserved assessment activity
also excludes corrupt/mislabeled metadata. Ordinary ingress and sync wire
admission remain ordinary-only. A separate strict stored-shape predicate checks
the Assessment DTO without claiming run/catalog/current authority. Rebuilders
handle an Assessment-only word without creating SRS, and the sync alias path
retains incoming ordinary SRS when no ordinary local evidence exists. Known
Assessment XP cannot be laundered through legacy reward carry.

## Migration, lifecycle and review

The genuine v16 fixture was captured before the bump through normal database
open:34 tables, six explicit indexes,15 opportunity columns and accepted quiz
fields. SHA-256 is
`52e331cff2584e21e634f9c3804861dfae006fcf5204f390f5093664d945c9ac`.
All old columns/rows across34 tables in the populated synthetic database,
accepted plan/checkpoint bytes and pending deletion intent survive. Unrelated
tables may be empty. New counters default0; pending defaultsNULL.
Linked Started metadata backfills from immutable first presentation; unlinked
staysNULL. Missing/tampered Started events remain invalid and are never repaired.
The migration data are genuine current signed synthetic facts projected into
the captured historical DDL, with their current explicit content/schema pins
preserved; no historical collection/UAT is invented.

Actual owner lifecycle tests create12 changes plus pending13, then complete
ordinary learning. Personal export preserves all19 opportunity fields, exact
pending bytes and22-field events. Persistent cloud-confirmed local purge removes
the owner's complete graph and preserves the other owner's export byte for
byte. The new fixture initially supplied a raw cloud receipt to local purge;
using the existing durable-marker contract fixes its deterministic guest proof
without changing any production deletion guard. The test helper recognizes the
frozen fourth Changed type and still rejects every unsupported event type.

Independent reviews accepted the core/storage design, actual transaction probe,
Assessment isolation, public Runtime/Host process handles, original lease and
the final canonical-state inspection. Earlier four opening-order RED cases,
the two final-state RED cases and the display-lease RED case remain in evidence.

## Current verification

Analysis0; focused Assessment/policy/projection33, expanded contracts500,
Runtime9 plus actual Host4, populated migration5 and owner lifecycle2 pass.
The earlier1042-pass/1-failure integration run exposed a stale schema16 export
assertion; current expectations are17/19 columns while preserving every old
field assertion. Full Flutter passes3054 cases on this source; final analysis reports0 issues.
The620 tracked Dart inputs are frozen in `wave10-frozen-dart-source.json`;
all620 match after the full suite and normal APK build.
The saved verification is `wave10-source-verification.json`. The focused
documentation/architecture consistency check passes39 cases after the update.

Windows PowerShell5 CLI passes23/23 suites. Backend CPU passes AI186, Voice64
and LM140, with one existing opt-in real Firebase/OmniVoice E2E skipped. An
initial test-only socket guard incorrectly blocked Windows' standard-library
loopback self-pipe; a bounded corrected guard passes, with no backend source
change, install, model download, GPU or live credential use. Exact commands,
counts and logs are in `wave10-backend-manifest.json`.

Remaining engineering includes the actual Assessment writer, compatible paired
comparison and UI, genuine production authority gateway/lifecycle composition,
and collection/upload integration. v18 is unreserved. Runtime coverage remains
10 connected/19 partial/15 missing; these counts do not certify readiness,
instrument validity or efficacy. Physical-device UAT and production approval
remain separate. The previously denied emulator/preview cleanup was not retried.


## Normal debug artifact

The normal `lib/main.dart` debug APK, version1.0.0+1/buildID853d4c13,
builds successfully with process-local Gradle heap3G/workers2. It replaces the
previous debug output at
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest\build\app\outputs\flutter-apk\app-debug.apk`.
Bytes251688634; SHA-256
`d611118d66086db8419ee2db8da87101df7700966085170377de48ad49942f17`.
The source/trees and host timestamp are recorded in
`wave10-normal-debug-apk-manifest.json`. Lib tree
`2145873fa6d3758bc2947e98e8f6e1a6a6752ea6`, test tree
`417b6774b659af0e53ef818092743f66d8984421`, Android tree
`c9abd4fd1187a4af13b306f1f077127f96884bac`.
No install/publication occurred. Existing Flutter future-KGP and SDK XML
compatibility warnings remain; this build succeeds. Signed field baseline+18
and its tag remain separate and unchanged.

Automatic approval previously rejected the owned disposable emulator/preview
stop/delete command with `blocked by policy`. Those artifacts remain retained;
the denied action was not retried and is excluded from cleanup savings.
