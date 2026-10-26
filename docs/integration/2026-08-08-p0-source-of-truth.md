# P0.3 Source of Truth — Authority Table

**Date:** 2026-08-08
**Integration branch:** `integration/p0-baseline` (created from `feature/associative-reading-loop` @ `f43aa0f`)
**Worktree:** `.worktrees/p0-integration`

## Authority Table

| System | Primary Source | Reason |
|---|---|---|
| Integration history | `main` @ `7b8ac6c` | Integration baseline; all branches stem from `eb684f0` |
| Device/Auth production shell | `feature/associative-reading-loop` | Field-verified minSdk 26, Production Firebase appId, Play Integrity retry fixes |
| Schema v7–v10, Quest, Streak, Associative Reading | `feature/associative-reading-loop` | Highest schema (v10), complete migration path v6→v10 with tests |
| Firebase appId, Play Integrity, retry/minSdk fixes | `feature/associative-reading-loop` | Verified on vivo V2041 + HONOR DNP-NX9 |
| AI/Voice/backend hardening | `feature/p8a-voice-architecture` + `feature/production-readiness-integration` | Voice architecture (35+ voice files), AI tutor stack, backend hardening |
| Research integrity / fabricated-result removal | Version with evidence + tests only | Per plan §P1.3 |

## Schema Migration Plan

- **Baseline:** associative schema v10 (authoritative)
- **v11 migration (new):** adds `ai_usage_tables` + `speech_evidence_tables` from p8a/prodrdy
- **Test coverage:** existing migration tests v6→v10 + new v10→v11 test

## Composition Root Unification

| Dependency | Source | Type after merge |
|---|---|---|
| `voice` | p8a-voice `VoiceProvider` | required, wrapped in `VoiceUseCases` adapter |
| `quest` | associative `QuestUseCases` | required (no-op fallback adapter) |
| `streak` | associative `StreakUseCases` | required (no-op fallback adapter) |
| `associativeLearning` | associative | required |
| `objectScanner` | both | nullable (needs LiteRT model) |

## Branches Kept Read-Only

All source branches preserved as-is until RC passes:
- `feature/associative-reading-loop` ✓
- `release/v0.1-complete-system` ✓
- `feature/p8a-voice-architecture` ✓
- `feature/production-readiness-integration` ✓

## User Work Preserved

Stash `stash@{0}`: "P0.1 preserve user work: field docs + auth png 2026-08-08"
Contents:
- `docs/field/2026-08-05-v12-verification-attempt.md` (modified)
- `docs/field/2026-08-06-v12-gms-recovery-auth-verified.md` (new)
- `lexiquest_auth.png` (new)
