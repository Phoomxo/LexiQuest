# S01-AC — existing offline catalog recovery and lifecycle

Status: source findings only, RED/implementation NOT_STARTED. Coherent user journey: open offline content, recover an initial catalog failure, safely handle changed runtime manager while reads or operations are pending. Approved plan-v5 UX01/UX12, no new instruction/content.

## Concrete source and acceptance

- Read AGENTS.md, state/receipt/handoff, S01.md, readiness-12-groups.md and evidence/S01-AB-backlog-reassessment.json. Verify complete overlay before sole-writer claim; preserve original data/evidence/pre-edit bytes.
- `lib/screens/offline_content_manager_screen.dart` initial FutureBuilder error renders only Thai text; `_states` stays failed, so no in-page retry. `_load` awaits `widget.manager.catalog()` then reads `widget.manager` again for `canRemove` and `requiredBytes`. Confirm replacement and late-operation behavior with real widget interactions/completers before fixes.
- Save pre-edit bytes, write meaningful RED. Implement Thai accessible retry using existing read-only catalog authority, bounded loading/double activation, no automatic download/remove/repair. Check canInvoke/live gate and correct menu action identity without inventing a new provider or flag.
- Keep each asynchronous catalog load tied to its initiating manager and dependencies; replacement/disposal must not mix metadata, revive stale controls or report a prior operation as current. Reproduce concrete failures first; preserve busy/download/cancel semantics and pinned identity. Inspect `_perform`/`_cancel` completion as part of this same journey, not separate per-handler work.
- Cover failure-to-retry success, repeated failure without raw errors, empty catalog, 360px/200% semantics/tap, disposal/manager replacement/late results, canInvoke revocation and existing download/cancel/remove/reverify controls. No byte deletion or policy change beyond existing service authority.
- Sequential bounded verify-scope.ps1 tests: discover offline_content_manager_screen_test.dart, offline_content_settings_entry_test.dart, offline_content_manager_test.dart and relevant runtime/menu gate tests. Do not rerun passed unchanged inputs. No full tests/build/GPU concurrency; full release only frozen SHA. Self-review only.
- Reassess useful plan-v5 work across all twelve groups after this package. Native/device/visual/keyboard/screen-reader/user/trial/release acceptance remains separate; UX-D01–25 OPEN, dates unchanged.

## Continuation and recovery

One writer/package, no subagents/background workers. Continue authorized ready work automatically; no repeated permission. Repeated failures require stopping the failed METHOD, discovering/diagnosing/correcting and retesting, never abandoning or hiding RED. Stop only explicit user pause or indispensable external prerequisite with no useful independent work. At justified context boundary preserve complete immutable source/evidence, release writer, then dispatch exactly one saved-project successor; reuse its ID.

No Security/Codex Security/Deep Scan, deployment, paid provider, purchase, research work or browser rejection bypass. Current Astra/medium deterministic fallback, not Jev-selected; Standard/default requested, runtime tier unexposed. Original Jev USD5 guard/ledger/cache unchanged; live routing requires fresh executor/free-credit/auto-reload/shared-spend/quota evidence and reservation; no reset/pending clearance/top-up or repeated unchanged login probes. Existing controller heartbeat unchanged.
