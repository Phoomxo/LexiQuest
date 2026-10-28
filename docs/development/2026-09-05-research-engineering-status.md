# Research engineering status

Worktree: `.worktrees/research`; branch: `feature/adventure-research`.
Implementation base: `6968ce97ff9b383e244b17b77cf0ed0f61eaaf3d`.
Verified implementation commit: `ed89efaf32a1090505a84d4b55b2cc60003068b3`.
Plan: `docs/superpowers/plans/2026-09-05-adventure-research-implementation.md`.

## Status and release boundary

R1–R6 implementation and local integration acceptance checks are complete. This
document is not a production signoff, enrollment authorization, validated-instrument claim,
physical-device result, or evidence of research efficacy. The historical paused
checkpoint is superseded by the user's authorization to continue development.

Real enrollment and research upload remain default-off. Ordinary learning does
not require participation, an instrument, an issuer, or a receipt provider.
No production deployment, participant upload, or remote authority creation has
been performed. The engineering condition for the user's separate Pair Matching
task is satisfied; the source handoff is recorded below.

## Implemented boundaries

- Schema v24 adds exactly four owner-scoped tables: measurement runs, coded
  responses, signed participation permits, and measurement opportunities.
  The database inventory is 48 tables; the product catalog remains 8/44.
- A supplied immutable Thai/English paired instrument pins item/form/catalog
  versions and a canonical checksum. Missing or incomplete scores remain null.
  Motivation, behavior, retention, and learning outcomes are separate axes.
- P-256 signature verification, current consent, stable assignment, active owner,
  explicit owner-transition fences, permit pins/revisions/expiry/revocation, and
  consent/guardian/assent receipt authorities gate capture. An ordinary global
  Sync lease is not an owner-transition fence. External authority awaits are
  followed by fresh local validation.
- The baseline precedes treatment exposure; the post window ends inclusively
  30 minutes after the first accepted canonical session's completion. Eligibility
  also requires baseline responses within 24 hours of first exposure. The first
  incomplete session is not silently replaced by a later completed session.
- The durable opportunity exists before an optional baseline prompt. Skip keeps
  that denominator without creating exposure. Standard/Adventure switches reuse
  one Today snapshot, opening UUID and opportunity. Rendered transitions are
  queued in order: the first ten yield facts; further changes increment only the
  suppression count. Storage failures preserve an explicit retry identity.
- Four neutral EventsV2 types carry bounded coded metadata, not answers or raw
  text. The frozen 22-field envelope and learning/reward authorities are unchanged.
  UUIDv7 occurrence prefixes preserve milliseconds despite legacy second-resolution
  EventsV2 DateTime storage. Reconciliation reads canonical learning rows; its
  `session-plan:<configuration identity>` is a transport alias, not a second plan.
- Consent withdrawal preserves signed permits, responses and denominators while
  closing collection and superseding research upserts, including all four typed
  neutral events. Export and explicit local deletion remain available. Signed
  owner pins cannot be silently rewritten during guest/account migration.
- The allowlisted personal archive retains coded research/lifecycle data and
  uses archive-local aliases. It excludes raw signatures, issuer receipts,
  guardian PII and raw owner identifiers. It does not invent a learning score or
  substitute missing values with zero.
- Runtime and settings use the configured protocol's consent version. A local
  checkbox never creates an external receipt or signed permit. Enrollment accepts
  an explicitly pasted, bounded, masked signed document and validates it again.
  The UI has optional Skip/withdraw/continue actions and hides stale authority on
  owner/runtime changes, expiry, and lifecycle revalidation.
- Capture/import/withdrawal notify the existing sync queue after the local
  transaction commits. Queue failure does not undo a successful local decision.
  Claim scanning recovers durable changes after offline/busy enqueue attempts.

## Composition and server contract

`AdventureResearchRuntimeConfig.off()` is the shipped default. A configured
runtime must receive a versioned `MotivationStudyProtocol`, trusted public issuer
keys, and exactly one receipt instance or `createReceipts(database)` factory.
The deferred factory receives the actual bootstrap database once; do not create
a second database connection to construct the authority. Synthetic test material
is not shipped as an approved instrument or authority. The concrete server-only
`FirestoreResearchReceiptAuthority` implements the existing Firestore read-only
receipt contract and has passed its 72 focused checks. It requires the actual Firebase Auth and
Firestore instances, configured consent version, and UTC clock.

The adapter uses `Source.server`, rejects cache/pending writes and unexpected
fields, and snapshots the actual owner/consent binding before and after the
bounded read. Timeout/outage/missing authority denies research without logging
receipt contents. It never provisions an authority or creates a permit.
The composed capture and sync authorities share a millisecond UTC clock adapter;
signed document timestamps remain strict and are never rounded or rewritten.

`AppBootstrap` composes the database-backed runtime and the real
`DriftResearchSyncAuthorizer`. Optional research sync uses an explicit
`ResearchSyncGatewayFactory`; bootstrap requires the same rollout and authorizer
instances in the gateway and local store. The only enabled rollout constructor is
`ResearchMeasurementSyncRollout.localEmulatorV1`, with exact rules revision
`research-measurement-v1-r1`. The Firestore gateway also checks its actual emulator
host. The default background entrypoint remains off; no provider is fabricated
or implicitly persisted across isolates.

The trusted server provisions permits, `research_sync_authorities` (including
exact `runPins`/`eventPins`) and separate `research_receipts`. Clients do not create
or update those authorities. Consent receipt version/decision time and each
receipt's owner/kind/active/expiry must match. The existing experiment-assignment
authority must be available locally before active enrollment can be accepted.

Withdrawal is a deny-only, create-once `research_withdrawals/{permitId}` marker.
It uses the existing local outbox, has priority over research upserts, survives
offline retry, and can be sent after local consent/receipt/permit activity ends.
It cannot create participation or update/delete a signed authority. Server rules
reject new research writes after the marker; withdrawal is not remote erasure.

## Component evidence

These are scoped executions, not one aggregate count or final release gate.
Mechanical formatting after an execution is followed by the final regression.
Detailed commands and hashes are retained in `.superpowers/sdd/` reports.

| Scope | Latest observed result |
| --- | --- |
| Core Host/runtime/use cases/consent/lifecycle/instrument batch | 174/174 passed |
| Host after independent review corrections | 22/22 passed; both new defects first reproduced RED |
| Bootstrap shared-authority/default-off composition | Final research subset 7/7 passed |
| Standalone form/panel accessibility and callback behavior | 52/52 passed |
| Participation screen with real runtime/synthetic authorities | 16/16 passed |
| Real P-256 read-only sync authorizer | 98/98 passed |
| Runtime, genuine synthetic P-256, capture, real authorizer, outbox/claims/preflight | 8/8 passed |
| Sync focused/regression batch (worker evidence) | 209/209 passed across seven files |
| Firestore rules (worker evidence) | 123/123 passed |
| Full migration directory plus research export and owner-upgrade tests | 241/241 passed |
| Main 20-file targeted analyzer | No issues found |
| Deferred receipt factory config/runtime/real-runtime-sync batch | 17/17 passed |
| Actual gateway transaction-fence tests plus existing gateway suite | 57/57 passed before additive history-provenance tests |
| Typed server-read provenance plus actual gateway and existing gateway suite | 68/68 passed; five-file analyzer clean |
| Concrete Firestore receipt authority, actual local DB and SDK-shaped fixtures | 72/72 passed after format; two-file analyzer clean |
| Runtime/system-clock precision and process-local request regressions | 11/11 passed after two observed behavioral failures; five-file analyzer clean |

Independent capture/schema/lifecycle review approved its six-file snapshot.
Host review found delayed-switch and timer defects; each was reproduced and
corrected. Independent sync review found two issues: a local withdrawal during
asynchronous transaction reads, and replay of an already-delivered historical
fact after signed permit renewal. Both are fixed and independently approved.
Gateway authorization is repeated inside every transaction retry immediately
before writes. Historical recovery passes 57 focused cases and the affected
191-case regression, including a genuine-signature pipeline with a raw system
clock. Receipt-provider independent review also approved its exact snapshot.
Pull provenance is process-local and bound
to authenticated server reads; it is not a document field, signature, or authority
to upload stale revisions. Current consent, signed permits, and all pins still apply.

## Engineering closure

1. Component implementation and independent review are complete. The final
   integration pass also corrected Settings to use the typed navigation port
   (21 focused tests passed after the architecture failure was reproduced).
2. All implementation agents are closed. Whole-project analysis, current contract
   and generated-plan checks, default/serial full inventories, three host journeys
   and Firebase Auth/Firestore policy checks passed on the final implementation.
3. Bounded working-source Gitleaks and dependency checks passed under the documented
   existing exceptions. Android debug build, SHA-256 and packaged native-library
   integrity checks passed. Exact evidence is below.
4. Final main diff review found no additional blocking defect. The source was
   committed locally; no merge, push, deployment or unrelated worktree cleanup
   occurred. The Pair task inherits this completed source, not the dirty root branch.

Production rollout still requires the approved instrument/protocol and consent
process, real trusted issuer/receipt provisioning, explicit deployment/enrollment
authorization, and physical-device/UAT evidence. None can be inferred from these
synthetic/emulator engineering results.

## Final R6 verification

- Whole-project analyzer passed after bounded formatting/style corrections;
  the final repeat also reported no issues (7.6 seconds). Final tracked plus
  untracked Dart formatting checked 968 files with zero changes. No tests were
  deleted, skipped, or weakened to fix a
  failure. The pre-existing `release-excluded` platform/model classification is
  retained; it is not a pass for those four checks.
- `dart run build_runner build`: exit 0, 35 seconds. Fresh Auth emulator 3/3
  and Firestore rules 123/123 passed; both demo-only emulators shut down normally.
- Feature map is still revision 1.3.0, semantic SHA-256
  `41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4`.
  The final test-plan generator's stale database count was reproduced failing
  at 48, then updated for v24 and the research rules revision; its two contract
  suites passed 18/18. Generated source fingerprints are refreshed after final
  formatting. After the verified implementation was committed, the metadata was
  regenerated and checked against `ed89efaf32a1090505a84d4b55b2cc60003068b3`;
  only source-commit metadata/command changed, not the source fingerprint.
- `tool/cli/verify-osv-locks.ps1`: all six literal dependency inventories passed
  under the existing bounded uuid/optional GPU exceptions. No exception was
  extended and no excluded GPU/runtime capability was enabled.
- Gitleaks working-source scans passed for lib, test, docs, pubspec files,
  Firestore rules and AGENTS. The first test-directory scan reported 16 instances
  of pre-existing mock keys/local lease/idempotency labels, not credentials.
  Each was inspected in context; four path-specific, exact-value allowlists
  record those fixed public fixtures. No directory, rule, or credential type is
  broadly excluded, and production source had no finding.
- Final default Flutter inventory: **4,328/4,328 passed**, exit 0, 247.607 seconds,
  with only the existing `release-excluded` tag excluded. Report:
  `.superpowers/sdd/research-full-default-final.jsonl`.
  The preceding full run's three stale lifecycle-fixture failures are closed:
  v24 inventory assertions match 48 tables, full export/deletion includes actual
  research rows for both owners, and a successful nonparticipant guest bind
  explicitly retains zero research rows. Signed-owner-pin upgrade rejection is
  still tested separately and unchanged. Focused lifecycle regression: 45/45.
- The generated plan is current at source fingerprint
  `8e9ac9a8d74eba3cf2807ff6b02f6e57c4fa97ee6e3b49b8a8acb8f84a173988`.
  Final working-source Gitleaks rerun passed after fixture changes, including
  the changed test-plan generator; no new finding.
- Final serial Flutter inventory: **4,328/4,328 passed**, exit 0,
  853.710 seconds, on the same implementation source as the default run.
  Report: `.superpowers/sdd/research-full-serial-final.jsonl`.
- All three host-fake integration journeys passed separately, 1/1 each:
  `field_trial_core_journey_test.dart`, `field_trial_feature_controls_test.dart`
  and `field_trial_media_smoke_test.dart`. Each used
  `flutter test -d flutter-tester --no-pub --timeout 90s --reporter failures-only`
  with its path under `integration_test/`. Core journey completed all 23 phases,
  including reopen, export and sign-out. These are not physical-device results.
- Android debug build passed, exit 0, Gradle assemble 188.1 seconds. Packaged model
  runtime integrity passed via `tool/cli/verify-apk-model-runtime.ps1 -BuildMode Debug`.
  No GPU accelerator was enabled or packaged outside the existing integrity policy.
  Final documentation Gitleaks rerun also passed, no leaks found.

## Android artifact and source handoff

- Implementation source: `ed89efaf32a1090505a84d4b55b2cc60003068b3`.
- Build command: `flutter build apk --debug --no-pub --dart-define=LEXIQUEST_VERSION=1.0.0+1 --dart-define=LEXIQUEST_BUILD_ID=research-ed89efaf32a1090505a84d4b55b2cc60003068b3`.
- Local artifact: `build/app/outputs/flutter-apk/app-debug.apk` in the Research worktree.
- Size: 223,579,309 bytes.
- SHA-256: `1623D8DA7FF886170F5A2086EC1B624A36E982638F22AF94BA925DE502B11898`.
- Research runtime and upload are default-off in this APK. It contains no synthetic
  approved questionnaire, issuer private key, receipt provisioning or enrollment authority.
- Subsequent handoff commits change documentation/source metadata only. The generated
  plan pins the verified implementation commit above; its fingerprint is unchanged.
  Existing native registrant/learning-generated-file line-ending/stat noise was
  preserved and excluded from the implementation commit because it has no Git content diff.
- Pair Matching PM0–PM8 dispatch: ready after this engineering closure; record the
  new task identifier after creation. Preserve the Research worktree and root user's edits.

Machine-readable test logs and scoped independent review reports remain locally
under `.superpowers/sdd/`; the committed evidence summary above is the portable
handoff. These logs contain synthetic test evidence only.

## Explicit non-results and follow-up boundaries

The four existing `release-excluded` checks (one iOS notification-platform check
and three physical LiteRT/model checks) were not run as part of the full inventory.
No physical-device accessibility/performance/UAT, desktop release certification,
research efficacy or participant-data result is claimed. Unchanged backend CPU
and Supabase suites were not rerun for this scoped Research closure; older results
are not counted as current evidence.

The successful Android build emitted dependency KGP future-migration, Android SDK
XML compatibility and Java deprecated/unchecked API warnings. These are recorded
maintenance follow-ups, not a claim that those dependencies were upgraded here.
Optional remote Voice/GPU remains outside this approval. Real research activation
still requires the protocol/issuer/receipt and explicit rollout gates above.
