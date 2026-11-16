# LexiQuest V2 Implementation Documentation

**Last Updated:** 2026-08-04  
**Status:** Phase -1 Ready for Execution

---

## Overview

This directory contains the complete implementation plan for LexiQuest V2, a major architectural evolution that introduces:

- Event-sourced architecture with EventEnvelopeV2
- Unified identity and consent management
- LexiMotivation engine with ethical engagement
- Quest system replacing legacy implementations
- Expanded sync coverage and offline capabilities
- 35 capabilities across 5 architectural planes

---

## Quick Start

### For Product Owners
→ Read **IMPLEMENTATION_SUMMARY.md** first  
→ Then review spec: `../superpowers/specs/2026-08-03-lexiquest-v2-evolution-framework-design.md`

### For Developers
→ Read **PHASE_MINUS_1_COMPLETE_WORKFLOW.md** (1,850 lines)  
→ Start with Week 1 deliverables
→ Run fitness tests before any commit

### For QA/Testers
→ Review testing strategy in workflow Appendix A  
→ Focus on Golden Journey tests (15 scenarios)
→ Monitor shadow mode parity during Week 7-8

---

## Document Structure

```
docs/
├── superpowers/specs/
│   └── 2026-08-03-lexiquest-v2-evolution-framework-design.md
│       └── 877 lines: 35 capabilities, lifecycle gates, V2 vision
│
├── database/
│   ├── schema_ledger.md (create in Week 1)
│   └── schema_audit_2026_08_04.md (create in Week 1)
│
└── v2-implementation/ (this directory)
    ├── README.md (this file)
    ├── IMPLEMENTATION_SUMMARY.md
    │   └── Executive overview, timeline, resources
    │
    ├── PHASE_MINUS_1_COMPLETE_WORKFLOW.md ⭐ MAIN DOCUMENT
    │   ├── Week 1-2: Authority Mapping (5 deliverables)
    │   ├── Week 3-4: Safety Net (4 deliverables)
    │   ├── Week 5-6: V2 Contracts (5 deliverables)
    │   ├── Week 7-8: Vertical Slice (5 deliverables)
    │   ├── Week 9: Integration Gate (4 deliverables)
    │   └── Appendices: Testing, CI/CD, Troubleshooting
    │
    ├── authority_matrix.md (Week 1 deliverable)
    ├── semantic_contract.md (Week 1 deliverable)
    ├── service_quarantine_registry.md (Week 1 deliverable)
    ├── rollback_playbook.md (Week 8 deliverable)
    ├── phase_minus_1_completion_report.md (Week 9 deliverable)
    ├── monitoring_plan.md (Week 9 deliverable)
    └── phase_0_plan.md (Week 9, if Phase -1 approved)
```

---

## Phase -1 Timeline

```
Week 1-2: Current-State Audit & Authority Mapping
    ├─ Map all write paths
    ├─ Freeze semantics (XP, Coins, Mastery, Quest)
    ├─ Audit schema versions
    ├─ Create schema ledger
    └─ Quarantine 42 legacy services

Week 3-4: Architecture Safety Net & Fitness Tests
    ├─ Implement 15 architecture fitness tests
    ├─ Create VoiceUseCases boundary
    ├─ Implement TimezonePolicy
    └─ Split registries (Feature/Experiment/Consent/Entitlement)

Week 5-6: V2 Foundation Contracts (FREEZE CONTRACTS)
    ├─ EventEnvelopeV2 (22 fields)
    ├─ Schema v7 migration
    ├─ Identity Mapping
    ├─ V1→V2 Adapter
    └─ Quest Domain (replaces 2 legacy)

Week 7-8: Vertical Slice Proof (Shadow Mode)
    ├─ Learning Evidence → Reward Grant pipeline
    ├─ Shadow mode integration
    ├─ 7-day parity testing (target: ≥99%)
    ├─ Projection rebuild test
    └─ Rollback procedures

Week 9: Integration Gate & Phase 0 Approval
    ├─ Completion report
    ├─ Architecture review meeting
    ├─ GO/NO-GO decision
    └─ Phase 0 plan approval
```

**Total Duration:** 9 weeks  
**Total Effort:** ~480 hours (12 weeks 1 FTE or 9 weeks 1.33 FTE)

---

## Critical Rules

### 🚫 FORBIDDEN

- Skip any gate or verification step
- Merge without passing all fitness tests
- Change frozen contracts after Week 6
- Start Phase 0 before Phase -1 approval
- Use ambiguous "points" term in new code
- Import quarantined services in V2 code
- Reuse or skip schema version numbers

### ✅ REQUIRED

- Every deliverable has passing tests
- Every gate has rollback procedure
- Every contract approved before implementation
- Every schema change in ledger
- Shadow mode proves ≥99% parity
- Zero production incidents from V2 work

---

## Key Concepts

### Architecture Planes (5)

1. **Learning Truth Plane** - Evidence, Curriculum, Mastery
2. **Decision Intelligence Plane** - Adaptive, Placement, Motivation
3. **Experience Plane** - Dialogue, Quiz, World, Social
4. **Operations Plane** - Teacher, Research, Creator, School
5. **Platform Plane** - Sync, Privacy, AI Governance, Observability

### Authority Principle

**One domain owns each write path.**

- Learning Evidence → Learning Domain
- Mastery Projection → Learner Model
- Reward Grant → Reward Domain
- Quest Progress → Quest Domain
- Motivation never writes mastery or rewards directly

### Shadow Mode

**V2 runs alongside V1 without affecting users.**

- Production uses V1 (existing code)
- Shadow V2 processes same events
- Logs decisions but doesn't commit
- Parity analysis over 7 days
- If ≥99% match → safe to cutover

---

## Testing Strategy

```
                    E2E (Golden Journeys)
                   /                    \
              Integration Tests
             /                          \
        Contract Tests            Architecture Tests
       /                                           \
  Unit Tests                                  Migration Tests
(80% coverage)                              (100% coverage)
```

**Test Counts:**
- Unit: ~500+ tests
- Contract: ~50 tests
- Architecture (Fitness): 15 tests (ALL MUST PASS)
- Integration: ~30 tests
- Migration: 1 per schema change
- Golden Journey: 15 end-to-end scenarios

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| R1: Duplicate Quest Authority | V2 Quest domain replaces both legacy |
| R2: Reward Double-spend | Idempotency tested in shadow mode |
| R3: Voice/AI Direct Call | VoiceUseCases boundary, fitness test enforces |
| R4: Sync Coverage Gap | Phase 0 deliverable (not Phase -1 blocker) |
| R5: Schema Migration Conflict | Audit complete, v7-9 verified safe |
| R6: Two Learning Layers | Phase 0 reconciliation plan |

---

## Success Metrics

### Phase -1 Exit Criteria

- ✅ Authority matrix: 100% coverage
- ✅ Fitness tests: 15/15 passing
- ✅ Shadow parity: ≥99%
- ✅ Production incidents: 0
- ✅ Contracts: frozen and approved
- ✅ All 23 deliverables: complete
- ✅ Stakeholder sign-off: obtained

---

## Getting Started

### Step 1: Read Core Documents

```bash
# 1. Read spec (30 min)
code docs/superpowers/specs/2026-08-03-lexiquest-v2-evolution-framework-design.md

# 2. Read summary (10 min)
code docs/v2-implementation/IMPLEMENTATION_SUMMARY.md

# 3. Read complete workflow (60 min)
code docs/v2-implementation/PHASE_MINUS_1_COMPLETE_WORKFLOW.md
```

### Step 2: Verify Current System

```bash
# Check current schema
grep "schemaVersion" lib/data/local/app_database.dart
# Should show: 6

# Run existing tests
flutter test

# Check for quarantined services
ls lib/services/ | wc -l
# Should show: 42 files
```

### Step 3: Start Week 1

```bash
# Create authority matrix
touch docs/v2-implementation/authority_matrix.md

# Create semantic contract
touch docs/v2-implementation/semantic_contract.md

# Audit schema versions (check production DB)
# Document in: docs/database/schema_audit_2026_08_04.md

# Create schema ledger
touch docs/database/schema_ledger.md
# Use template from workflow Deliverable 1.4

# Create service registry
touch docs/v2-implementation/service_quarantine_registry.md
```

---

## AI Assistant Recommendations

### Model Selection

| Task | Model | Effort | Reason |
|------|-------|--------|--------|
| Authority Mapping | Opus | xhigh | Must catch all risks |
| Contract Design | Opus | xhigh | Frozen after Week 6 |
| Implementation | Sonnet | high | Fast + accurate |
| Refactoring | Sonnet | medium | Pattern-based |
| Boilerplate | Haiku | low | Cost-efficient |

**Token Budget:** ~1.5M tokens for Phase -1 (~$150-200)

---

## Contact & Support

**Tech Lead:** [Your Name]  
**Slack Channel:** #v2-implementation  
**Documentation:** docs/v2-implementation/  
**Issue Tracker:** GitHub Issues with `v2` label

---

## Next Actions

### For Product Owner
→ Review IMPLEMENTATION_SUMMARY.md  
→ Approve Phase -1 timeline (9 weeks)  
→ Allocate team resources (1.33 FTE)

### For Tech Lead
→ Set up #v2-implementation Slack channel  
→ Schedule Week 1 kickoff meeting  
→ Assign Week 1 deliverables to team

### For Developers
→ Read complete workflow document  
→ Familiarize with fitness tests concept  
→ Prepare local environment

---

**Status:** 📋 READY FOR EXECUTION

**Last Review:** 2026-08-04  
**Next Review:** After Week 1 completion
