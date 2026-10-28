# PM2 interim root inspection

Implementation is evolving; these are targeted review leads, not final defects or acceptance.

- Historical firstOpportunity roles were initially validated against current support set, so wrong -> later reveal -> restore rejected valid earlier independent evidence. Worker notified and changed predicate; require positive regression plus strict temporal support negative case. Durable support revision/history is preferable to merely allowing arbitrary past role changes.
- Commands initially lacked session identity despite owner/round/revision fences. Worker added sessionId and reducer binding; require same-owner new-session stale callback test.
- Owner upgrade v6 compatibility is explicitly deferred to PM8 with actual code evidence in pm8-compatibility-preflight.md. PM2 owner-switch tests do not cover rehome/collision.
- Final review should inspect capture/freeze/append/answer/clear failures and exact retry state, live+deleted canonical repository validation, full frozen context binding, initial-versus-progressed codec identities, measured UTF-8/checkpoint reservations and terminal/read-only recovery. Do not equate pure reducer success with UI or replay readiness.
- Root found budget liveness edge: old canAnswer permitted mismatch at revision46/remaining6 but then rejected a correct answer at revision48/remaining6, despite reserved completion capacity fitting. Worker notified to cost actual resolution and prove completion at ceiling; no claim closed yet.
- Repository source/build versus immutable initial operation, revision1 empty state, exact support acquisition revisions, and neutral shared LearningActivityRecoveryLimits were requested; worker reports focused22 green after changes. Await final source review.
- Worker found generic exact-pinned start could bypass Pair capability. Authorized private admission helper; root also requested direct generic start-with-checkpoint and two-step generic startSession then append-v6 tests. First v6 checkpoint must require real internal admission, not just valid shape/ID. Existing accepted retry and legacy paths must remain valid.
