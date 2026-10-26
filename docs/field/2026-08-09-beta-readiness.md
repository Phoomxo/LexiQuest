# P9 Beta Readiness Assessment

**Date:** 2026-08-09
**Branch:** `integration/p0-baseline`
**Integration commits:** P0→P8 complete (8 phases)

## Device Matrix

| Tier | Device | Status | Evidence |
|---|---|---|---|
| Mid | vivo V2041 (Android 13, 7.5 GB) | **PARTIALLY CERTIFIED** | APK 1.0.0+9 tested: vocab, quiz, scanner, shadowing PASS. Auth→Firestore INCONCLUSIVE (v12). |
| High | HONOR DNP-NX9 (Android 16, 11 GB) | **PARTIALLY CERTIFIED** | APK 1.0.0+10 tested: install, XNNPACK 18ms. Sync unverified. |
| Low | Not procured | **OPTIONAL** | Device tier requirement relaxed from 3→2 (commit 3989a57). Best-effort. |
| Emulator | AVD API 26 | **PENDING** | minSdk 26. Smoke test on emulator needed. |

## Scenario Test Suite (6/6 PASS)

| Scenario | Description | Status |
|---|---|---|
| S1 | Guest creates vocabulary + records answers offline | ✅ PASS |
| S2 | Session resume — abandoned session detectable | ✅ PASS |
| S3 | Learning history queryable after completion | ✅ PASS |
| S4 | Guest→registered upgrade preserves data | ✅ PASS |
| S5 | Reward balance starts at 0, increases with quiz | ✅ PASS |
| S6 | Data deletion erases all owner-scoped records | ✅ PASS |

## Certification Scenarios (for physical device testing)

The following scenarios MUST be executed on physical devices before beta release:

### Mandatory (both device tiers)
1. **Install/upgrade/uninstall** — APK installs cleanly, upgrades preserve data
2. **Guest → registered** — signup doesn't lose local progress
3. **Offline learning → sync** — learn offline, reconnect, verify sync
4. **Low storage** — app handles gracefully when storage is low
5. **Process kill/resume** — kill app mid-session, reopen, verify state
6. **Permission deny/re-enable** — deny camera/mic, verify app degrades, re-enable
7. **Background/foreground** — backgrounding pauses/cancels active operations
8. **Scanner/TTS/STT** — hardware features work on real device
9. **AI server unavailable** — app falls back to local content
10. **Kill-switch propagation** — feature disable works
11. **Long session + memory pressure** — 30+ min session without OOM
12. **Thai text/font scaling** — UI renders correctly at 130% font scale

### Best-effort
- GPU delegate (needs allowlist-qualifying device)
- Low-tier device (if procured)

## Known Blockers (MUST resolve before beta distribution)

| Blocker | Severity | Status |
|---|---|---|
| Anonymous Auth → Firestore sync INCONCLUSIVE | HIGH | Needs owner confirmation on freshly-restarted device |
| App Check enforcement not enabled | MEDIUM | Currently UNENFORCED; rules tested via emulator |
| Owner approval not recorded | HIGH | Evidence template has `approved: false` |
| Private channel refs are placeholders | LOW | Owner must fill feedback/support/protocol refs |

## Known Limitations (for beta participants)

See `docs/field/known-limitations.md` for participant-facing documentation.

Key points:
- Offline learning works; signup, sync, Gemini require internet
- Object Scanner downloads model on first use (~4 MB)
- GPU disabled (CPU/XNNPACK default); "not ready" shown instead of fake results
- Gemini is BYOK (participant's own key/quota)
- SRS review empty on day 1 (FSRS schedules future due dates)
- Cloud kill-switch preserves learning + outbox

## APK Build Info

| Property | Value |
|---|---|
| Version | 1.0.0+1 (pubspec) — will be incremented for release |
| minSdk | 26 (Android 8.0) |
| Firebase appId | Production (719eb38067864496be5a77) |
| Build | debug APK verified (Exit Gate: `app-debug.apk`) |

## Beta Exit Gate Criteria

- [ ] Mid/high physical devices pass all mandatory scenarios
- [ ] API 26 emulator smoke test passes
- [ ] No HIGH severity blockers open
- [ ] Zero crash/data-loss/security defects
- [ ] Known limitations documented
- [ ] Beta evidence linked to APK hash
