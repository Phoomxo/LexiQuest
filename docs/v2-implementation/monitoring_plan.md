# V2 Monitoring & Observability Plan

**Version:** 1.0  
**Date:** 2026-08-04  
**Scope:** Phase 0 and beyond  
**Owner:** Petch1910  

---

## 1. Architecture Fitness (CI — Continuous)

| Metric | Target | Alert |
|---|---|---|
| Fitness tests passing | 100% (15/15+) | Any failure blocks PR merge |
| `flutter analyze` errors | 0 | Blocks CI |
| `flutter analyze` warnings | 0 | Blocks CI |

**How:** GitHub Actions on every PR + push to `main`.  
**Command:**
```bash
flutter test test/architecture/fitness_test.dart
flutter analyze --fatal-warnings
```

---

## 2. Shadow Mode Parity (Phase 0+)

| Metric | Target | Alert |
|---|---|---|
| V2 reward parity vs production | ≥99% | Page on-call if parity < 98% for 24 h |
| Shadow error rate | < 1% | Investigate if > 0.5% |
| Idempotency violations | 0 | Immediate investigation |

**How:** `tools/shadow_rewards_analyzer.dart` runs nightly against `shadow_rewards.jsonl`.
```bash
dart tools/shadow_rewards_analyzer.dart
# Exit 0 = healthy (parity ≥99%, errors <1%)
# Exit 1 = degraded — create P1 issue
# Exit 2 = log missing — create P2 issue
```

**Retention:** Shadow log rotated weekly; 30-day archive kept.

---

## 3. Schema Migration Success Rate

| Metric | Target | Alert |
|---|---|---|
| Devices migrating successfully | ≥99.5% | P1 if failure rate > 0.5% |
| Migration duration (p95) | < 500 ms | Investigate if > 2 s |

**How:** Migration outcome logged to Firestore `/telemetry/migrations/{deviceId}` on first
launch after schema upgrade. Dashboard query: failures in last 7 days / total upgrades.

**Rollback trigger:** If failure rate > 0.5% within 24 h of a release → execute
`docs/v2-implementation/rollback_playbook.md` Scenario 2.

---

## 4. Feature Flag Coverage

| Metric | Target | Alert |
|---|---|---|
| V2 features behind a flag | 100% | Architecture fitness test T-flag blocks merge |
| Flags enabled in production build | As per release plan | Manual review before tag |

**How:** Fitness test scans `lib/features/` for V2 service instantiation without a
`features.isEnabled(Feature.*)` guard.

---

## 5. Rollback Frequency

| Metric | Target | Alert |
|---|---|---|
| Rollbacks per release | 0 | Any rollback → mandatory incident report within 48 h |
| Time-to-rollback (if needed) | < 15 min | Drill quarterly |

**How:** Manual tracking in `docs/v2-implementation/rollback_playbook.md` incident log section.

---

## 6. Performance Budget

| Metric | Baseline (Phase -1 exit) | Budget | Alert |
|---|---|---|---|
| App cold-start time (p50) | measured at release | +5% max | P2 if +10% |
| Memory usage (p95, foreground) | measured at release | +5% max | P2 if +10% |
| CPU (shadow hook, per event) | +0.3% | +1% max | P2 if +2% |
| Battery (1-hour session) | no change measured | no measurable change | P2 if +5% |

**How:** Flutter DevTools timeline + Firebase Performance SDK (added in Phase 0 Week 12-13).  
**Baseline snapshot:** Taken from commit `10ab13b` benchmark run on Pixel 6 + iPhone 13.

---

## 7. Sync Health (Phase 0 Week 12-13+)

| Metric | Target | Alert |
|---|---|---|
| Sync success rate | ≥99.5% | P1 if < 99% for 1 h |
| Outbox queue depth (p95) | < 50 operations | P2 if > 200 |
| Dead-letter queue depth | 0 | P1 if any entry |
| Firestore read quota usage | < 70% daily budget | P2 if > 85% |

**How:** Outbox depth sampled at app foreground + background; emitted to Firestore
`/telemetry/sync/{deviceId}/snapshots`.

---

## Dashboards

### Developer Dashboard (Firebase Console + local scripts)
- [ ] Fitness test results — CI badge on `main` branch README
- [ ] Shadow mode parity — last 7 days, nightly job output
- [ ] Migration progress — schema version distribution per device cohort
- [ ] Feature flag states — `BuildFeatureRegistry` audit script

### Product Dashboard (Phase 0 Week 12-13)
- [ ] Beta user adoption — V2 features enabled vs total beta users
- [ ] Crash rate V2 path vs V1 path (Firebase Crashlytics)
- [ ] Engagement metrics — session length, DAU, quest completion rate

### Operations Dashboard (Phase 0 Week 12-13)
- [ ] Sync success rate (hourly)
- [ ] Outbox queue depth (real-time)
- [ ] Firestore quota usage (daily budget %)

---

## Incident Response Playbook

### Severity Levels

**P0 — Critical** (respond immediately, any hour)
- Production app crash affecting >1% of users
- Data loss or data corruption confirmed
- Reward double-spend in production
- **Response:** Immediate feature-flag disable → rollback if needed → incident review within 24 h

**P1 — High** (respond within 4 hours)
- Feature broken for >10% of users
- Parity below 98% for >24 h
- Sync failure rate >1% sustained
- Schema migration failure rate >0.5%
- **Response:** Hotfix within 4 h OR rollback per `rollback_playbook.md`

**P2 — Medium** (respond within next business day)
- Minor bug affecting <10% of users
- Performance regression >10% on any metric
- Shadow error rate >0.5%
- **Response:** Fix in next scheduled release

**P3 — Low** (backlog)
- Cosmetic issues
- Edge cases affecting <0.1% of users
- **Response:** Add to backlog, prioritize in next sprint

---

## Quarterly Reviews

| Activity | Frequency | Owner |
|---|---|---|
| Fitness test suite review (add/update tests) | Per phase gate | Tech Lead |
| Shadow log archive + parity trend analysis | Monthly | Tech Lead |
| Feature flag audit (remove stale flags) | Quarterly | Tech Lead |
| Rollback drill | Quarterly | Tech Lead + QA |
| Performance baseline re-measurement | Each major release | Tech Lead |

---

## Alert Contacts

| Severity | Channel |
|---|---|
| P0 | Immediate — all team members |
| P1 | GitHub issue (label: `incident`) + team notification |
| P2/P3 | GitHub issue (label: `bug`) |
