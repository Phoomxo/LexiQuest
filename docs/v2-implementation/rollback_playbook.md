# V2 Rollback Playbook

**Owner:** Tech Lead  
**Last updated:** 2026-08-04  
**Applies to:** Phase -1 Week 7-8 and beyond

---

## When to use this playbook

Invoke immediately if ANY of the following occur:

- App crashes when recording learning events
- Performance regression > 20% on `recordAnswer` call time
- Memory growth > 50 MB over 10 minutes during shadow mode
- Shadow log grows > 10 000 entries per hour unexpectedly
- Parity divergence > 1% in shadow vs production rewards

---

## Scenario 1: Shadow Mode Causes Production Issues

**Symptom:** App crashes, freezes, or slows after enabling `shadowRewardV2`.

### Immediate fix (< 5 minutes)

```dart
// lib/runtime/registries/feature_registry.dart
// In BuildFeatureRegistry.fieldDefaults(), the feature is already
// hidden by default.  If you enabled it manually in bootstrap, revert:

// REMOVE THIS LINE from app_bootstrap.dart or wherever you enabled it:
// features.enable(Feature.shadowRewardV2);
```

Redeploy. Shadow mode is opt-in and disabled in production by default.

### Verification

1. `flutter analyze` — no errors
2. Run `flutter test test/features/rewards/shadow_reward_orchestrator_test.dart`
3. Monitor crash reports — should stop immediately after redeploy
4. Shadow logs should stop growing

---

## Scenario 2: Schema v7 Migration Fails

**Symptom:** App fails to start; `SqliteException` during migration.

### Why this is safe

Schema v7 **only added** the `events_v2` table. It did not modify or delete any
existing tables. Rolling back to v6 is safe: all V1 user data remains intact.

### Rollback steps

```dart
// lib/data/local/app_database.dart

// Step 1: Revert schema version
@override
int get schemaVersion => 6; // was 7

// Step 2: Remove EventsV2 from @DriftDatabase tables list
// Step 3: Remove `if (from < 7)` migration block
// Step 4: Remove EventsV2 from _createMissingTables
// Step 5: Remove _createEventIndexes() call from beforeOpen
```

Run `dart run build_runner build --delete-conflicting-outputs` after the revert.

### Data safety contract

| Table | Status after rollback |
|---|---|
| All V1 tables | ✅ Intact, unchanged |
| `events_v2` | ⚠️ Inaccessible (schema reverted), but rows remain on disk |
| Shadow log entries | ✅ Safe to discard — no production data |

### Recovery (after fixing the migration bug)

1. Fix the migration issue in a test environment
2. Run `test/database/migration_v6_to_v7_test.dart` — all 5 must pass
3. Stage deploy and confirm migration completes
4. Redeploy to production

---

## Scenario 3: Parity Issues Discovered (> 1% divergence)

**Symptom:** Shadow analysis script reports > 1% difference between V2
decisions and production V1 reward grants.

### Action

```
DO NOT cut over to V2.
Keep production V1 running unchanged.
```

### Investigation steps

1. Run `dart tools/shadow_rewards_analyzer.dart` to identify diverging events
2. Check `reason` field on diverging entries — common causes:
   - `quiz_answered_incorrectly` vs production granting reward → V1 had looser rules
   - `no_matching_rule` → new event type not in policy v1
3. Fix the eligibility policy or adapter, bump `policyVersion` to `v1.1`
4. Reset the shadow log: `cp shadow_rewards.jsonl shadow_rewards.backup.jsonl && echo > shadow_rewards.jsonl`
5. Re-enable shadow mode and run for another 7 days
6. Re-run analysis — must show ≥ 99% parity before any cutover

---

## Scenario 4: Idempotency Violations

**Symptom:** `wouldSucceed: false` count is unexpectedly high (> 5% of eligible events).

### Investigation

```dart
// Run the analyzer with --idempotency flag
dart tools/shadow_rewards_analyzer.dart --show-idempotency-failures
```

Common causes:
- Same `LearningEvent` being adapted twice (check duplicate event creation)
- Idempotency key collision (check `_idempotencyKey` in `EventV1ToV2Adapter`)
- Production already granted due to a different path

### Fix

Review `EventV1ToV2Adapter._idempotencyKey()` and ensure the key derivation
is deterministic and covers all event-producing code paths.

---

## Emergency contacts

| Role | Contact |
|---|---|
| Tech Lead | Petch1910 |
| On-call engineer | Check #lexiquest-oncall Slack channel |
| Drift schema questions | See `docs/database/schema_ledger.md` |

---

## Gate checklist before any cutover to V2

- [ ] Shadow mode ran for ≥ 7 days without production incidents
- [ ] Parity ≥ 99% confirmed by analysis script
- [ ] Zero production crashes attributable to shadow mode
- [ ] Rollback procedure tested in staging
- [ ] `test/database/migration_v6_to_v7_test.dart` all 5 PASS
- [ ] `test/features/rewards/` all tests PASS
- [ ] Tech lead sign-off recorded in `docs/v2-implementation/`
