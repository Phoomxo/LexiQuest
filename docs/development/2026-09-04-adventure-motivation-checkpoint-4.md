# Adventure Motivation — Checkpoint 4 / MS-05

Date: 2026-09-04
Branch: `feature/adventure-motivation-plan`
Source range: `151cc2d1..f5745153`

## Outcome

MS-05 Preference, Canonical Motivation Projection and Companion is accepted.
Learner Preferences v2 persists the owner-scoped Standard/Adventure home
experience through schema v23, local lifecycle, sync v2, export, owner merge
and Firestore policy while preserving every v1 preference field. The
preference remains presentation-only and cannot grant feature or research
assignment access.

Adventure Result now waits for and reads canonical Quest, Gentle Streak,
Achievement and Reward receipts after the existing side-effect reconciler.
Evidence-scoped and session-scoped Achievement receipts are both projected.
Pending, recovered and exhausted states are truthful and bounded; Adventure
does not grant rewards or synthesize optimistic progress.

The scripted bilingual companion supports mission-ready, correct, incorrect,
hint, skipped, returned, completed and recovered triggers. Selection is
deterministic, contains no AI/free-text or relationship-score authority, has
semantic text and honors reduced motion and no-audio behavior. Skips are
presentation-only notifications and create no learning evidence.

## Verification evidence

| Gate | Evidence | Result |
|---|---|---|
| Preference migration/lifecycle | schema v23, preference, sync, identity and export suites | Pass; v1 fields preserved and v2 conflicts converge |
| Cloud preference policy | `npm run test:rules` | Pass, 85 / 85 |
| Canonical receipt projection | Adventure projection/result lifecycle suites | Pass; Quest, Streak, Reward and both Achievement scopes |
| No duplicate authority/grant | Adventure architecture boundary suite | Pass; read-only projection and unchanged evidence boundary |
| Companion catalog | reaction domain and companion widget suites | Pass; all production triggers reachable and deterministic |
| Accessibility behavior | Adventure widget semantics, reduced-motion and no-audio tests | Pass for automated scope |
| Product integration | bootstrap, navigation, quiz and Today Host suites | Pass; one shared diagnostics/composer authority and canonical millisecond clock |
| Focused verification | Adventure/Learning/bootstrap/navigation/scenario/architecture set | Pass, 391 tests |
| Authority regressions | Preferences/Sync/Identity/Export set | Pass, 387 tests |
| Static analysis | `flutter analyze --no-pub` | Pass, zero issues |
| Independent review | Task 4 and diagnostics/recovery re-review | Pass; no Critical or Important finding remains |
| Diff hygiene | `git diff --check` | Pass |

Checkpoint 6 Task 6.1 bounded diagnostics and offline catalog recovery were
implemented and verified in the same production integration because the
entry, composition, evidence and projection lifecycle needed one shared
diagnostic authority. Manual device accessibility, performance, UAT and
rollout certification remain outside this MS-05 acceptance.

## MS-05 decision

**Accept/Continue.** Product Extension is complete and the Adventure feature
remains hidden by field default. This decision does not authorize research
schema/capture or learner rollout; those retain the independent prerequisites
and gates defined for Checkpoints 5 and 6.
