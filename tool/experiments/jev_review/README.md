# Optional Jev development pilot

## UX v5 continuation amendment — 2026-09-24

`choice_transport.route` now provides an opt-in TypeSafe-compatible Gateway
Choice adapter using the unchanged original Guard/ledger/cache. It never creates
a ledger or launches a worker. The historical R3 text below describes the prior
no-transport state. Offline tests use disposable ledgers only; live Choice is
still NOT_TESTED pending current account free-credit/shared-spend/price/quota
evidence. No old billing snapshot is eligible and no inference was called by this
amendment. Current executor schema, availability/quota and manually sanitized
summary must be supplied. Public model pricing is not account billing evidence.

The fixed catalog is an authorization upper bound, not runtime availability:
Astra/Sol permit ultra; Luna does not. The adapter intersects fresh executor
capabilities and per-candidate quota observations. Antigravity is excluded from
this adapter until fresh CLI/quota/isolation evidence is integrated. Default
execution stays on the current coordinator with explicit deterministic fallback.

Guard reservation precedes credit lookup and inference. One uncertain request
remains pending; no retries or paid fallback. Candidate/question/risk changes
change cache schema identity; source identity remains pinned separately. Recheck
capabilities/quota/source/writer at dispatch even after Jev returns a choice.
Ledger settlement proves only the validated billing receipt, never task quality.

Primary contract sources checked 2026-09-24:
- https://docs.typesafe.ai/primitives/choice
- https://vercel.com/i/jev-integrations (Gateway `/typesafe` preserves Noul)
- https://vercel.com/changelog/ai-gateway-now-supports-typesafe-clients-and-http-api-for-jev

Remaining prerequisite for production use: real billing/free classification,
shared usage bound and fresh executor quota/schema; then controlled live receipt
validation under the original USD5 tranche. Do not infer successful routing from
the offline adapter or this README. No runtime tier enforcement is claimed.

This tool is outside the application runtime. Disabling it leaves baseline
learning and optional MCP workflows unchanged. It never edits source code.

Run offline checks through `tool/cli/verify-scope.ps1 -Level Targeted -Area Runtime
-CliTestTargets jev-review.tests.ps1 -Resume`.

`pilot.py` is disabled unless `--live` is supplied. It accepts a manually reviewed
case, a fresh billing observation, and the existing durable ledger. The live
ledger is `%LOCALAPPDATA%/LexiQuestDevSecrets/jev-review-ledger.sqlite`; never
delete or recreate it to clear a limit. Initialize a tranche only once, with the
user's existing USD5 free-credit authorization and a fixed expiry. Credentials
are passed in `LEXIQUEST_JEV_GATEWAY_KEY` only for the child process, decoded from
the existing DPAPI store; do not print keys, headers, or provider error bodies.

The guard reserves a conservative token-and-surcharge upper bound before
inference. It allows one unresolved request across all purposes. Schema v2 fixes
three purpose batches (synthetic-v1, review-v1, routing-v1), each capped at12
requests, sharing the original USD5 tranche. Renaming a batch cannot reset quota. Current free balance and the
remaining authorized tranche both constrain the next reservation. Invalid,
stale, paid, expired, insufficient, or unknown evidence fails closed. Expiry or
insufficient balance latches a pause; a monthly refill does not resume it.

Evidence is a reviewed local observation, not an authenticated provider-side
spending cap. The credit API exposes total balance, so a current dashboard free
classification is also required. Shared usage needs a conservative allowance;
if its bound, rates, surcharge, billing mode or free classification is unknown,
do not invoke live. Never purchase credits or enable auto-reload.

Timeout, malformed response, rate limit and uncertain billing leave a pending
reservation. There is no retry or paid fallback. Reconcile only after matching
provider logs, the exact pending summary, generation and free-credit debit;
`Guard.reconcile` requires a reviewed evidence reference. Never clear pending
state merely because a balance looks unchanged or ingestion is delayed.

Only manually sanitized summaries are eligible. The input scanner is defense
in depth, not a general anonymizer. Do not submit raw source/logs, credentials,
private paths, account identifiers or learner records.12 synthetic cases were
labelled before live output. Live coverage and receipts are recorded in
`docs/development/ari/jev-review-115.json`; a partial pilot does not establish
accuracy, speed, cost savings or reduced Astra tokens.

## R3-03 ledger and routing contract

Upgrade an existing ledger only with `Guard.migrate` after a SQLite backup and
reviewed hash-to-purpose mapping for every old call. Migration preserves the
original policy, request hash, reservation, cost, state, receipt and result,
including pending reservations. It is transactional and idempotent. The actual
two calls were migrated and verified; never recreate the live ledger.

`pilot.py --purpose review` charges the review batch; the default is synthetic.
A reviewed case may bind `source_fingerprint`. Routing is not a pilot CLI purpose:
`model_route.py` still has no live Choice transport. Explicit deterministic
fallback permits the authorized coordinator to continue without a worker launch.
Fresh balance/free classification/eligibility and an accepted live adapter remain
prerequisites for actual Jev model selection. No old billing snapshot is reusable.

Cache and local request identity bind model, schema, summary, purpose, fixed batch,
source and policy version. A changed candidate/question contract must change the
request schema identity. Legacy triage cache is reused only in its original
unpinned context and mapped purpose, after the fresh billing gate. Receipt
generation IDs cannot settle multiple requests. Nonfinite timestamps fail closed.

`eligible_candidates` intersects the authorized catalog with fresh availability
and quota observations, then applies the critical risk floor. `incident_decision`
returns bounded advice, never executes: billing uncertainty defers, data safety
escalates, source/writer/evidence conflicts veto progress, command failures require
diagnosis, and corrected idempotent read/reroute attempts are limited to one before
the deadline. The controller must retain incident IDs and attempt counts in its
audit; dispatcher integration is R3-04. No function certifies acceptance or PASS.

## R3-04 reviewed coordinator journal

`dispatch_review.ReviewController` records a bounded task card, exact source pins,
fallback route, observed cwd/model/effort and sequential state transitions in a
separate SQLite audit file. Never point it at the real Jev budget ledger. One
active package per audit database is enforced across connections, including
REVIEW and RECOVERY. VERIFIED requires the owning coordinator's explicit review
and evidence references. Changed files outside scope, read-only mutations and
nonzero exits enter RECOVERY; they cannot be accepted as a passing review.

The coordinator supplies freshly observed pins and runtime metadata. Evidence
references and supplied observations still require human/owning-coordinator
inspection: this journal is neither an evidence oracle nor an OS sandbox or a
cross-database writer lease. It does not hash the filesystem, launch commands,
call Jev, or execute incident advice. Repository ownership remains mandatory.
Unknown runtime tier is retained as unverified; observed Fast/priority is vetoed.

Incident IDs bind immutable facts to the package source. Retry/reroute advice
consumes its one attempt transactionally when issued, so a restart cannot reset
it. New evidence may justify a new incident; renaming an incident to replay the
same failed method is prohibited. Review source drift before creating a new card.

Current execution is explicit DETERMINISTIC_FALLBACK for the sole authorized
coordinator. Worker dispatch is disabled. Live Jev Choice/fresh billing, live
worker model binding and provider A/B efficiency remain unverified. GODKILLER
repo-map can locate symbols but omitted required provenance and acceptance in
the synthetic trial; use canonical reads. Local prune retained requirements but
did not reduce that fixture. No provider token-saving claim follows.
