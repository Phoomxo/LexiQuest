# S01-BA — existing display preference recovery

HOST_PASS **371 scoped tests**: 87 core/widget/preference/merge/erasure + 284 runtime/navigation. 51 new cases; 26 original-source RED and 7 additional boundary/companion RED resolved. Self-review only. No remaining BA RED.

Theme and reduced-motion controls capture their controller and display lifetime. Replacement/removal, owner change, read retirement, route/tab/pop/disposal and lifecycle transitions retire retained native, semantics and menu actions. Ordinary rebuilds and current controls remain usable. Duplicate selections stay single-flight; existing controller commands remain serialized.

Initial/error reads expose an explicit Thai read action. Uncertain acknowledgement disables new choices until a canonical read; recovery never resubmits a write. Display reads recheck canonical owner after IO. Each explicit choice reads the current row to preserve its companion field and evaluate no-op against durable values rather than an old controller cache. App-wide listeners still receive committed settings.

The existing display transaction checks active owner and caller lifetime after insert/update, before commit. Tests use isolated SQLite, including a transaction trigger that retires the owner: preference and owner changes roll back together. Once committed, a preference remains committed even after screen retirement or lost acknowledgement. No new store, schema, outbox, preference, provider call or cost.

Account/password/logout/research-consent/local-erasure method bodies are unchanged; their existing regressions pass. Vocabulary/import/content/scoring/research/provider source is unchanged.

Evidence: [validation](evidence/S01-BA-validation.json), [source receipt](evidence/S01-BA-source-receipt.json), [writer claim](evidence/S01-BA-writer-claim.json). All 1,557 final path/hash pins agree and match current source. All 200 inherited original ZIPs remain byte-identical. RED/candidate/final snapshots and original streams retained in `build/ux-delivery/S01-BA/`. Prototype 115+3 reused on eight unchanged pins. Final scoped analysis: no issues. Drift warnings: core 0, runtime 25 inherited, none suppressed.

Recovery diagnostics: initial environment InputDrift retained; source was not edited during gates. Two introduced notifier regressions were fixed without changing inherited F01 assertions. The committed-readback fixture now waits bounded real IO before assertions; pending writes await the menu Future before controller disposal. Original snapshots/results remain available. Earlier nine brace-style infos were corrected.

Native/device/real restart/keyboard/screen-reader/visual/user/trial/release remain pending. UX-D01–25 remain OPEN. S01 started 2026-09-24T05:52:58.6746244Z; due 2026-10-22T05:52:58.6746244Z. This is not sprint acceptance.

All twelve plan-v5 groups reassessed in [backlog evidence](evidence/S01-BA-backlog-reassessment.json). Next coherent independent scope: existing password dialog recovery, S01-BB. Its source hypotheses require fresh RED; no real account/provider operation is authorized by host tests.
