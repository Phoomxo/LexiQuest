# PM7 Standard contextual entry seam

## Confirmed missing seam

`TodayExperienceHost` does not use `onStartMission` for Standard. `lib/features/adventure/presentation/today_experience_host.dart:275–277` returns Standard model before journey/reward reads; only Adventure branch `:797–803` captures `AdventureMissionLaunchContext`. Standard `:822–826` forwards `widget.actions` directly. `lib/screens/today_hub_view.dart:11–17` delegate receives individual session/recommendation/review/assessment payloads, not the exact loaded Today snapshot and entry decision

The PM7 integration brief must replace its claim that existing mission callback suffices for both presentations. This bounded source addition is needed; do not force Standard through Adventure journey/reward loading

## Smallest suggested API and call site

Add one optional synchronous factory to `TodayExperienceHost`:

```dart
typedef ContextualTodayActionsFactory = TodayHubActionDelegate Function({
  required TodayHubSnapshot today,
  required AdventureProductEntryDecision entryDecision,
  required TodayHubActionDelegate fallback,
});

final ContextualTodayActionsFactory? contextualStandardActions;
```

At Standard `TodayHubView(actions: ...)`, after the existing research prompt and Presented handling, pass:

```dart
actions: widget.contextualStandardActions?.call(
  today: today,
  entryDecision: result.decision,
  fallback: widget.actions,
) ?? widget.actions,
```

Factory only builds a delegate capturing the already-loaded objects. It must not generate operation IDs, reload Today, query research, navigate, reserve a session, or do async work during build. No factory provided means the exact original delegate is passed and existing production behavior, Standard early-return path, journey/reward call counts and navigation stay unchanged. No changes to `TodayHubView`/delegate method signatures are necessary

The explicitly opted-in internal delegate intercepts **openReview** for Pair and forwards unsupported actions unchanged. `today_hub_view.dart:389–393` passes the captured `snapshot.reviewWork`; this fits `PairSourceSnapshot.today` which derives items specifically from reviewWork (`pair_matching_source_composer.dart:97–110`). Do not intercept an arbitrary recommendation and substitute review words: recommendation authority may describe different content. Keep resume as exact resume, assessment/history unchanged, and use fallback for unsupported Pair content

`adventure_pair_experience.dart` remains the internal Adventure adapter from actual `AdventureMissionLaunchContext`. Standard may use a named constructor/helper there taking captured Today + entryDecision to mount the same Pair host without fabricating AdventureMissionRef/RewardAccount. This is one shared Pair launch construction path with two genuine contextual inputs, not another learning runtime. BOTH paths use `PairSourceSnapshot.today(snapshot: capturedToday, allowlist: ...)`, surface today and its exact reference. Adventure mission content/kind must actually agree with that source; do not fabricate a mission to disguise incompatible content

## Identity and owner guards

- Preserve captured object identities: Today and decision come from the same resolved `AdventureEntryHostResult`; do not reread either on click. Decision `entryAttemptId` and permit/assignment/treatment remain the original values (`adventure_entry.dart:108–131`)
- Today has ownerId/evaluatedAtUtc (`today_hub_models.dart:109–133`); Adventure mission also has owner/sourceEvaluatedAtUtc/content (`adventure_journey.dart:37–59`). Verify these match captured source and current Pair runtime owner before async launch, and recheck owner before canonical admission/navigation. Do not claim decision has ownerId—it does not
- `RewardAccount` has NO ownerId (`rewards/domain/reward_models.dart:179–193`). Adventure reward provenance is the actual `rewardAccounts.loadForOwner(widget.ownerId)` call (`today_experience_host.dart:291–293`) guarded by host generation checks, not a field comparison. Internal adapter must treat it as display data, never evidence of active ownership. Standard needs no reward query/account
- Create launch operation/time exactly once on actual selected action or route-state initialization, then retain through rebuilds and uncertain start ACK. A synchronous factory may run on every build: do not store start identity solely in a fresh factory-created delegate. Own pending launch in stable internal adapter/router state keyed to captured entryAttemptId + source identity + action; concurrent click guards and accepted route state prevent duplicate starts. New explicit attempt/replay alone creates fresh identity
- Owner or entry refresh invalidates old unaccepted contextual actions. Existing host generation checks (`today_experience_host.dart:201–205`, `:294–296`) cover loads; optional factory cannot inspect private generations itself. Internal opt-in composition should retain a current owner/entry token and check captured token before launching after await. A small host-owned guarded delegate is an alternative only if required by an actual stale-callback test; do not add global state
- For already accepted operations, keep PM6 exact recovery/lease semantics even if presentation changes. Changing Standard↔Adventure chrome must not replace the accepted Pair runtime/controller or recompose source words

## Real UI fixture flow

1. Real TodayExperienceHost + signed synthetic research fixture resolves Standard assignment, opens baseline prompt, submits via actual form callback, resolves original Today and records Presented. Opt in contextual factory; capture same Today/decision in internal wrapper, then tap **real Standard review action**. Do not invoke an invented Standard onStartMission callback
2. Wrapper validates the action belongs to captured reviewWork; constructs one normal Pair from `PairSourceSnapshot.today` and real policy configuration, then navigates/mounts real Pair host. Use an eligible curated 4/6-word review fixture and both directions. Finish actual wrong→repair→close path; return and reconcile existing Today research authority, submit real post form. Assert one original entryAttempt/opportunity and exact configured session linkage
3. Adventure fixture uses the actual review mission composed from that same captured Today source; tap `adventure-start-mission`, consume existing context in Adventure adapter, mount same Pair implementation with decoration. Existing actual callback identity test is `test/features/adventure/presentation/today_experience_host_test.dart:1105–1127`; extend from capture-only to real Pair completion
4. Baseline nonparticipant controls use real providers and both entry paths; ordinary learning succeeds and research-specific rows/events/uploads stay zero. Do not require global ordinary sync outbox zero
5. Add default-caller regression: no factory → same delegate methods/payloads and Standard does not query journey/rewards. Add same-object capture, unrelated rebuild no new ID/query, double tap, async owner switch, refreshed entry invalidates stale action, unsupported recommendation forwards unchanged, accepted same-host decoration fallback tests

## Scope and evidence

Report-only read in `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; no source/test/git/tooling mutation or test execution. Focused checks: Standard callback gap; delegate payload/source compatibility; captured owner/reward contracts; actual Adventure UI fixture. Only this file written. Root should authorize the one TodayExperienceHost optional factory and update PM7 brief before implementation

Read snapshot SHA256:

- `lib/features/adventure/presentation/today_experience_host.dart`: `18220D732A854562937A7A5A2D664CDB6177A2491D9880C34BFFEBB9196278CA`
- `lib/screens/today_hub_view.dart`: `C96AC952520A3E6C65FAFA89C17B0E7D8B2AC2D9AC76EAFF03F4131EF42CC117`

No claimed research/physical/UAT acceptance or running processes
