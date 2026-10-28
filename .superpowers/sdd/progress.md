# Adventure Research progress ledger

Source base 6968ce97; branch feature/adventure-research; worktree .worktrees/research.
User resumed 2026-09-05 after AGENTS recovery-policy revision. No blanket error pause.
Plan: docs/superpowers/plans/2026-09-05-adventure-research-implementation.md.

## Current integration snapshot (supersedes historical bullets below)

- R1: 97 GREEN. R2: full database/migration inventory plus research export and
  owner-upgrade batch 241/241 GREEN, including the additional forward SQL guards.
- R3/R5: main174 batch, Host22, form/panel52, participation screen16,
  real signed authorizer98 and actual runtime/sync8 passed in scoped executions.
  Independent capture and Host findings closed. Latest runtime clock/request
  regression11/11 and bootstrap `--name research`7/7 GREEN. Clock precision is
  adapted only at composition/process-local requests, never signed documents.
- R4: old focused sync209/209 and rules123/123 GREEN. Independent review P1
  transaction race fixed: fresh authority after each await, every retry, before
  staging writes. Additive trusted-server provenance + gateway regression68/68
  GREEN, five-file analyzer clean; scoped independent review approves.
- R4 P2 historical delivery/renewal: finished57/57 GREEN and191/191 affected
  regression including genuine raw-clock integration; independent review
  approves. Mencius closed. New-device history requires same-UID server provenance + current
  signed authority; historical references never authorize stale uploads.
- R5 concrete receipt provider: Sartre completed72/72 GREEN after formatting,
  two-file analyzer clean; agent closed. Server-only SDK reads, strict schemas,
  actual owner/consent snapshots before/after awaits and timeout denial. Gibbs
  approved provider, gateway/P2 and clock composition, then closed.
- R6: main whole-project analyzer GREEN, codegeneration35s GREEN, feature map
  8/44 unchanged, Auth3/3 and rules123/123 fresh GREEN, OSV six inventories PASS
  under unchanged existing exceptions. Gitleaks working-source scopes PASS after
  classifying16 fixed mock key/lease/idempotency false positives with narrow
  exact-value/path exceptions (no broad skips). Final-plan generator updated
  stale44-table assumption to48 plus research rules revision;18 contracts GREEN.
- R6 integration corrections: typed Settings navigation boundary reproducedRED
  and corrected,21 focusedGREEN. First complete default inventory4325pass/3fail:
  old lifecycle scenario counts/fixture. Updated v24 counts, seeded actual new
  research rows in both-owner export/deletion fixture, retained nonparticipant
  zero-research prerequisite for successful guest binding and existing signed-pin
  rejection tests. Latest lifecycle/export/upgrade45/45 GREEN, fullanalyzerclean.
- R6 final default completed4328/4328 GREEN, exit0,247.607seconds.
  Report `.superpowers/sdd/research-full-default-final.jsonl`; no later code edits.
  Finalworking-sourceGitleaksrerunPASS9targets(session33013exit0).
- R6 serial full suite4328/4328 GREEN, exit0,853.710seconds, same code as default.
  Report `.superpowers/sdd/research-full-serial-final.jsonl`. All three host-fake
  integration journeys passed separately1/1each. Final968Dartfilesformat0changes,
  analyzer noissues7.6seconds. No code edits after either complete regression.
- Implementation committed locally as ed89efaf32a1090505a84d4b55b2cc60003068b3.
  Final generated-plan metadata now pins that source commit; fingerprint remains
   8e9ac9a8d74eba3cf2807ff6b02f6e57c4fa97ee6e3b49b8a8acb8f84a173988.
  Only generated docs changed after commit; native/LF-only noise preserved.
- R6 Android debug build passed188.1seconds, packaged native-library integrityPASS.
  APK223579309bytes SHA256=1623D8DA7FF886170F5A2086EC1B624A36E982638F22AF94BA925DE502B11898.
  LEXIQUEST_VERSION=1.0.0+1 and BUILD_ID=research-ed89efaf32a1090505a84d4b55b2cc60003068b3.
  Evidence-only commit ca123dddc1349acc4ed67bdd8f5476b02165307c; engineering closed.
  All agents closed and every test/build/scan session ended. No deployment,
  enrollment, upload, UAT or physical-device claim.
- Pair creation dispatched once using LexiQuest project e0d28f74-0d26-40bc-b126-4cfebe4ff7a0,
  separate app-managed worktree starting feature/adventure-research. Pending clientId
  client-new-thread:507f41f7-53b1-40ef-87f2-fe009c3ae854, host local.
  Requested title: พัฒนา Pair Matching รุ่นใหม่ PM0–PM8. Do not create a duplicate.
  Resolve ready thread via app listing, then wait_threads once for startup progress.

Test slot: FREE; all Research processes ended. Never infer a grant from this ledger. Releases must reach MAIN by
an explicit agent/task message, since worker commentary does not notify MAIN.

## Historical component checkpoints

- R1 instrument: current97 tests GREEN within MAIN174-test batch; independent review approve-with-nit fixed with valid-length malformed-element test.
- R2 schema: v24/four tables. Lorentz fixed reverse parent-pin updates and strict minor receipt references with six forward-compatible SQL guards; 102/102 focused migration tests passed. Agent closed. Full matrix pending.
- R3 capture: opportunity+measurement21/21 GREEN before baselineSkip addition. Exact exposure from Presented UUIDv7 milliseconds; first ACCEPTED canonical session remains index even if later session completes. New shared reconciliation6tests + baselineSkip case observed RED; implementation now pending GREEN.
- R3 crypto: DONE76/76, focused analyzer clean, independent review approves component.
- R3 lifecycle: current42 dedicated cases GREEN in MAIN174-test batch, including legacy-generic AND four typed neutral-event outbox supersession on withdrawal. Prior13 associated repository cases also passed previously. Independent bounded six-file capture/schema review approves with hashes; report research-capture-independent-review.md.
- R4a lifecycle/export:31focused tests +T25 pass; independent review no additional findings. Ordinary upgrade inventory fixture corrected after old81pass/2fail; pending recheck. Sync schema24 bound remains with sync worker.
- R4b sync/policy: Sartre owns lib/features/sync/** and Firestore tests/rules; reports123/123 rules tests passed. Local queue/pull-renewal/withdrawal gaps pending focused RED/GREEN. Default-off enqueueResearchForOwner hook composes after local commit; deny-only remote withdrawal uses existing outbox, never changes signed authority.
- R4b real authorizer: Mencius observed94cases RED (+71/-23), final98/98 GREEN with clean2file analyzer/formatter. Real read-only P256/receipt/owner/gate/pin authority now injected into bootstrap/store/gateway; no permissive callback. Ordinary sync lease is NOT an owner-transition fence. Eight new actual runtime→real authority→store integration cases prepared, not yet run.
- R5 UI: Copernicus52/52 widget tests GREEN, four-file analyzer clean; agent closed. Runtime parser8/config2 passed. Shared reconciliation7 tests passed, including distinct watch regression preventing no-op owner-lock notification loops.
- R5 runtime/Host: MAIN174/174 GREEN across Host20/runtime5/usecases7/consent3/lifecycle42/instrument97; configured bootstrap/default f42 5/5 GREEN. Form tests now tap real UI rather than mixing callback futures across fake/real async zones. New aftercommit hooks preserve successful capture when queue fails; old settings consent route uses configured version and same enqueue hook.
- R5 independent Host review: Gibbs found post-deadline timer (fixed with observedRED→GREEN), delayed-hook rendered switch loss and renewal timer not rearmed. Both latter findings now have observedbehavioralRED, patches pendingGREEN: FIFO rendered transitions with opening/owner identities + renewed permit timer. No coalescing first10facts. CurrentHost22cases. See research-runtime-host-independent-review.md; reviewer closed.
- R5 participation screen: Copernicus16cases ready; partialRED0/7 then aborted stalled fixture wait, not full16 result. Fixed synchronous setState bodies, didUpdate/expiry/resume/stalecallback guards + bounded test async; GREEN pending. Only screen+own test/report changed, prior52form/paneltests frozen.
- R6 final verification/review/APK/source/handoff: not started. No Pair task yet.

Historical slot grants above have expired. Main coordinates explicit handoff.
No concurrent Flutter/build/generator commands in this worktree. No scans while
implementation writers are active.

Important correction: open the durable opportunity BEFORE baseline prompt, even
when answers are incomplete; only Presented requires complete baseline. Skip must
retain a denominator without a treatment exposure. No extra tables/envelope fields.
Legacy EventsV2 DateTime storage is whole seconds; own UUIDv7 occurrence prefix
preserves exact milliseconds without changing the frozen global mapping.
