# PM4 integration decisions

Worktree: C:/Users/Phet/.codex/worktrees/02fa/LexiQuest; branch codex/pair-matching-pm0-pm8.

This records decisions for the later explicit PM4 dispatch. It does not transfer ownership while PM3 is running. Read pm4-brief.md, pm4-preflight.md, pm4-checkpoint-audit.md and the final accepted PM3 report/source before implementation.

- Follow the preflight's single coordinator authority, referenceable pause leases, monotonic active time, durable timeout decision, once-per-session extension, candidate-budgeted restart, and actual three-receipt canonical close. Do not implement a second timer or close authority in presentation.
- Repair spacing after restart must count distinct correct OTHER words since that ticket's failure. A session-global matched set is insufficient when previously correct words are correctly answered again in a new round. Separate current-round progress, ticket-local spacing, and session-wide spent repair/support history. Test partial round -> restart -> new wrong -> previously correct other words, reaching exactly 2/3 spacing.
- Preserve PM3 strict new-write scheduling even when reading historical codec versions. No old-codec append path may renew repair entitlement or discard support. Prior authenticated attempt prefixes remain immutable.
- Extend the same byte/revision capacity projection for all allowed PM3 remaining work, timer decisions, restart and actual terminal metadata. Optional denial must occur before state publication or evidence capture, while Continue and full completion remain feasible.
- Restore exactly the last acknowledged durable elapsed/decision state, initially paused until current host readiness. Abrupt death can lose an unflushed active interval; record this limitation rather than claiming per-instant recovery or adding tick writes.
- Keep first PM1 checkpoint bytes and frozen plan stable. Timer choice is pinned OFF/60/90/120, fresh setup defaults OFF; no preference from a previous session. PM6 owns actual host/voice wiring.
- Use the write set in pm4-preflight.md. Minimal shared Pair repository/adapter changes are authorized for these boundaries, with no concurrent writer. No production gates, navigation activation, schema changes or deployment.

Acceptance requires actual fake-clock and SQLite fault/reopen evidence, strict tamper rejection, completed real close recovery, full admitted adversarial completion within limits, impacted legacy checks and clean focused analysis. Save exact commands/counts and source write set in pm4-report.md, release tooling, then await independent review. Do not stage or commit.
