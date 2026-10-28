# Adventure Motivation — Checkpoint 2 / MS-03

Date: 2026-09-04  
Branch: `feature/adventure-motivation-plan`  
Source range: `e707cd7a..10341bcf`

## Outcome

MS-03 Read-only Preview is accepted. The implementation provides the
deterministic journey projection, canonical Today-derived session plan,
guarded `home/learn/today-experience` child route, Map/List parity, explicit
fallback states and the shared Standard/Adventure Today snapshot host.

The feature remains hidden by field default. Enabling it adds exactly one Learn
card and no bottom-navigation destination. Hidden and stale/direct entry paths
remain lazy and do not invoke the Today loader.

## Verification evidence

| Gate | Evidence | Result |
|---|---|---|
| Journey determinism | `flutter test test/features/adventure` | Pass |
| Standard Today equivalence | `flutter test test/screens/today_hub_screen_test.dart` | Pass (11/11) |
| Learn entry and route | `flutter test test/screens/main_navigation_screen_test.dart` | Pass |
| Map/List and fallback/accessibility widgets | `flutter test test/features/adventure/presentation` | Pass |
| Runtime delivery contract | Production contract/cardinality/gate tests | Pass |
| Bootstrap composition | `flutter test test/runtime/app_bootstrap_test.dart` | Pass |
| Static analysis | Focused `flutter analyze` over changed runtime/UI/tests | Pass, zero issues |
| Schema version | `AppDatabase.currentSchemaVersion` | `22` |
| Table inventory | Fitness T25 + current database contract | Pass, exactly `44` tables |
| Database schema diff | `git diff d00a7f34..10341bcf -- lib/data/local` | Empty |
| Adventure write snapshot | Added-line scan for Drift mutation calls and `adventure_progress` | Zero matches |

The shared-host test additionally proves one `TodayHubSnapshotLoader.load()`
call per opening, exact Today snapshot object identity in the journey request,
one UUID v4 reused across rebuild/switch, a new UUID only on explicit refresh,
and stale-owner result suppression.

## MS-03 decision

**Accepted.** Read-only preview scope is closed. No Adventure progress table,
parallel learning catalog, reward grant API, or database mutation boundary was
introduced. Checkpoint 3 may build only through the existing canonical Learning
controller and evidence contracts.
