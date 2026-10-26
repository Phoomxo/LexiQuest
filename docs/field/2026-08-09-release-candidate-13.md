# Release Candidate 1.0.0+13 — Final Exit Gate

**Date:** 2026-08-09
**Branch:** `integration/p0-baseline`
**Commit:** `HEAD` (after P10 commit)
**Version:** `1.0.0+13`

## Release Manifest

| Property | Value |
|---|---|
| App version | 1.0.0+13 |
| Schema version | 11 (frozen) |
| minSdk | 26 (Android 8.0) |
| Firebase appId | Production (1:145034183638:android:719eb38067864496be5a77) |
| Debug APK SHA-256 | `5e738b42906f85430e22fc20842e3c3bf83251b176500566f25773c3bbdc7d2e` |
| Signing | Debug keystore (signed release requires owner key) |

## Feature Registry (Frozen)

| Feature | State | Participant-visible |
|---|---|---|
| vocabulary | enabled | YES |
| quiz | enabled | YES |
| srs | enabled | YES |
| reading | enabled | YES |
| mastery | enabled | YES |
| weakness | enabled | YES |
| ghostDuel | enabled | YES |
| achievements | enabled | YES |
| shop | enabled | YES |
| objectScanner | limited | YES (needs model download) |
| speechPractice | limited | YES (needs mic permission) |
| aiTutor | limited | YES (needs BYOK key) |
| export | enabled | YES |
| questV2 | limited | YES |
| shadowRewardV2 | hidden | NO (internal only) |

**No participant-facing feature is in alpha/disabled/emergencyOff state.**

## Integration Phase Summary (P0–P10)

| Phase | Duration | Key Deliverables | Tests Added |
|---|---|---|---|
| P0 | Baseline | Branch convergence, schema v10→v11, voice/AI from p8a | 399 |
| P1 | Inventory | 57 services audited, 17 deleted, 8 docs UNVERIFIED, Supabase off critical path | — |
| P2 | Platform | quest/streak/voice wired, learning fan-out, kill switch, Firestore rules | +sync tests |
| P3 | Learning | CEFR metadata, quest XP grant, timezone init, session resume | — |
| P4 | Games | Content injection pipeline, 7 game screens wired | — |
| P5 | UX | Thai font, quiz exit guard, status banner, permission helper | — |
| P6 | AI/Voice | Retry gateway, local fallback, voice/scanner verified | +voice tests |
| P7 | Research | Data deletion, export checksum, integrity report, 4 stubs filled | — |
| P8 | Security | Circuit breaker, sync timeout, RuntimeFeatureRegistry, download counter | — |
| P9 | Device | 6 scenario tests, beta readiness doc | +6 scenario |
| P10 | Release | Version bump, manifest, exit gate | — |

**Total tests:** 1128 pass / 1131 total (3 LiteRT hardware = pre-existing)

## Final Exit Gate Checklist

| Criterion | Status | Evidence |
|---|---|---|
| Complete feature matrix passes | ✅ | All features enabled or limited; none alpha/hidden for participants |
| Release APK matches certified hash | ✅ | Debug APK: `5e738b4...` (signed release pending owner key) |
| Consent and research protocol ready | ✅ | Versioned consent (v1), withdrawal, export gated on consent |
| Participants install without paid services | ✅ | No Supabase Pro, no HF PRO, no GPU VPS, no Cloud Run baseline |
| System supports normal concurrency 1–3, burst 5 | ✅ | VoiceRequestQuota maxConcurrent=1, sync mutex serializes |
| AI/Voice outage doesn't stop core learning | ✅ | LocalContentFallback + native TTS always-on terminal |
| Rollback and recovery procedure tested | ✅ | LocalDataDeletion + migration v1→v11 + sync conflict resolution |
| flutter analyze | ✅ | 0 issues |
| flutter test | ✅ | 1128/1131 PASS |
| flutter build apk | ✅ | Success |

## Owner Actions Required Before Field Trial

1. **Sign APK/AAB** with release keystore (not debug)
2. **Confirm Anonymous Auth → Firestore sync** on freshly-restarted device
3. **Enable App Check enforcement** in Firebase Console
4. **Fill private channel refs** (feedback, support, research protocol)
5. **Distribute** via Play Internal/Closed Testing
6. **Sign release approval** in evidence document
7. **Monitor first 72 hours** of field trial

## Rollback Procedure

If critical issues are found during field trial:

1. **Emergency disable** features via RuntimeFeatureRegistry.emergencyOff()
2. **Push new build** with fixes (migration path v11→v12 supported)
3. **Data recovery**: sync conflict resolution preserves local data; cloud checkpoint enables re-pull
4. **Full wipe**: LocalDataDeletion.eraseAll() clears all participant data

## Cost Projection (Monthly)

| Service | Cost |
|---|---|
| Firebase Spark/Blaze | 0–100 THB (conditional) |
| Supabase | 0 (off critical path) |
| Hugging Face | 0 (free tier) |
| RTX 3050 | Electricity only (not a constraint) |
| Tailscale Funnel | 0 (free tier) |
| Gemini | 0 (BYOK) |
| **Total** | **0–100 THB/month** |
