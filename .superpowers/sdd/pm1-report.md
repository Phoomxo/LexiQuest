# PM1 implementation handoff — 2026-09-05

## State / ownership

- Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`
- Branch: `codex/pair-matching-pm0-pm8`; baseline `a32e25d5`.
- PM1 implementation ready for root acceptance review. No commit, deployment, enrollment, production navigation, schema migration, generated-source edit, or security worker.
- Flutter/Dart tooling RELEASED after the checks below; no running process remains.
- Parent-owned docs/status and pre-existing generated registrant line-ending noise were preserved.

## Delivered

- Immutable `PairMatchingLaunchIntent`, `PairMatchingPlanV1`, closed direction/density/timer/purpose/source enums, exact JSON codecs and SHA-256 fingerprints. Plan binds owner/session/source snapshot/entry/time, lexical pins/reasons, independent board orders, seed, allowlist and policy versions. Checkpoint policy 6 reserved by root; old matching v1–v5 writer/reader unchanged.
- Session ID uses structured `[ownerId, operationId]` hashing. Board shuffle also hashes structured tuples, avoiding delimiter ambiguity and runtime Random changes. Adventure receives the same plan object without recomposition.
- Learn merges all reasons before deterministic rank and select. Today consumes the supplied `TodayHubSnapshot`, with no reader/reload on the seam. Review captures exact selected snapshots/order and fails closed if filtering/density would silently substitute a subset.
- Curated manifest pins exact ID/revision/checksum/labels/EN–TH locales; delivery has no boolean `isCurated` shortcut. Default manifest and internal delivery capability remain disabled. Source filters delete/report/stale/collision inputs. Both label sides are checked again at start.
- Bounded Unicode visible-key profile supports ASCII English, specified Latin-1 accent decompositions and Thai. Canonical mark ordering preserves accents and tone marks; Thai SARA AM/NIKHAHIT+SARA AA visible equivalence is explicitly folded. Unsupported scripts/controls/marks fail closed instead of claiming universal normalization.
- Exact 4/6, typed one-time density choice, explicit six-to-four acceptance, and unavailable below four. Product guardian override precedes explicit request/learner preference; no age/performance/research inference.
- Real `PairPinnedLearningActivityRepository` extension implemented in existing Drift learning authority. It checks owner, report, available category, deletion/rejection/retirement, current lexical checksum/revision/labels, capability, and canonical active-session conflict in one transaction. New session + initial event checkpoint commit or roll back together.
- Durable start operation serialization pins IDs, original time, app/build identity and plan. Exact retries reconcile the immutable initial event even after later checkpoints or delivery gate-off, with owner/full identity checks. New starts remain gated; post-write gate revocation rolls back.
- DATA-019 persists density/provenance in the existing owner/matching `SessionConfiguration` row, via optional v2 metadata. Old v1 bytes remain unchanged. One-time fallback/choice survives store reload. Draft edits, real policy revalidation, owner upgrade, and bounded export preserve metadata. No guardian identity or research receipt stored.

## Changed files (PM1 write set)

New:

- `lib/features/learning/pair_matching/domain/pair_matching_launch.dart`
- `lib/features/learning/pair_matching/domain/pair_matching_plan.dart`
- `lib/features/learning/pair_matching/application/pair_matching_source_composer.dart`
- `lib/features/learning/pair_matching/application/pair_matching_atomic_start.dart`
- `test/features/learning/pair_matching/pair_matching_plan_test.dart`
- `test/features/learning/pair_matching/pair_matching_source_composer_test.dart`
- `test/features/learning/pair_matching/pair_matching_source_property_test.dart`
- `test/features/learning/pair_matching/pair_matching_atomic_start_test.dart`
- `test/features/learning/pair_matching/pair_matching_density_preference_test.dart`

Narrow extensions authorized by root:

- `lib/features/learning/domain/learning_repository.dart`
- `lib/features/learning/data/drift_learning_repository.dart`
- `lib/features/learning/domain/session_configuration.dart`
- `lib/features/learning/application/session_configuration_policy.dart`
- `lib/features/identity/data/drift_owner_upgrade_repository.dart` (two optional-metadata copies only)
- `lib/features/export/application/owner_lifecycle_archive.dart` (optional bounded density field only)
- `test/features/identity/drift_owner_upgrade_repository_test.dart` (original v1 test retained and parameterized for v2)
- `test/features/learning/session_configuration_policy_test.dart`

## RED and recovery evidence

All commands ran in this worktree. `--reporter compact` used throughout.

1. `flutter test test/features/learning/pair_matching/pair_matching_source_composer_test.dart`: exit 1, missing planned new APIs (compilation RED). This first invocation unintentionally performed Flutter's default dependency resolution; all subsequent invocations used `--no-pub`. No explicit pub/generation command was issued.
2. `flutter test --no-pub test/features/learning/pair_matching/pair_matching_atomic_start_test.dart`: exit 1, missing planned atomic adapter APIs. First implemented fixture run then exposed canonical checksum mismatch: fixture hashes were corrected to actual `ContentQualityPolicy.vocabularyChecksumSha256`, preserving production verification.
3. `flutter test --no-pub test/features/learning/pair_matching/pair_matching_density_preference_test.dart`: exit 1, missing v2 preference APIs; subsequent focused codec/store run passed.
4. Source test with Thai SARA AM equivalence: exit 1, expected unavailable but got ready. Bounded Thai shaping equivalence fix produced GREEN.
5. Atomic category-deletion test: exit 1, expected rejection but start succeeded. Added category/status checks; GREEN.
6. `flutter test --no-pub test/features/learning/pair_matching/pair_matching_source_composer_test.dart --plain-name 'Review exact selection'`: exit 1, expected unavailable but got ready. Exact Review count binding fixed; GREEN.
7. `flutter test --no-pub test/features/learning/session_configuration_policy_test.dart --plain-name 'Pair metadata'`: exit 1, real `SessionConfigurationResetRequired(tampered)` on valid v2. Draft/policy metadata preservation fixed; GREEN without weakening identity/protocol checks.
8. `flutter test --no-pub test/features/learning/pair_matching/pair_matching_atomic_start_test.dart --plain-name 'gate-off after commit'`: exit 1, committed retry rejected by delivery gate. Moved new-start capability check after full existing-event reconciliation; GREEN.
9. Added file-backed close/reopen test. An import inserted at EOF caused one format/compiler error; inspected the file and moved the import to the directive section. A Drift multiple-open-instance warning was removed by closing the source memory DB before opening the isolated file DB. Final run is green without that warning.

## Final verification

1. Impacted regression command (241 passed, exit 0):

```text
flutter test --no-pub test/features/learning/pair_matching test/features/learning/drift_learning_repository_test.dart test/features/learning/learning_use_cases_test.dart test/features/learning/matching_mode_adapter_test.dart test/features/learning/session_configuration_policy_test.dart test/features/learning/session_configuration_store_test.dart test/features/learning/session_configuration_sheet_test.dart test/features/today_hub/today_hub_reader_test.dart test/scenarios/complete_owner_export_delete_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart --reporter compact
```

2. After the final Pair-only gate/retry change and additional file-reopen/density tests, reran the touched Pair + canonical repository boundary (58 passed, exit 0; 27 Pair tests + 31 repository tests):

```text
flutter test --no-pub test/features/learning/pair_matching test/features/learning/drift_learning_repository_test.dart --reporter compact
```

3. Focused static analysis after final edits: no issues, exit 0:

```text
dart analyze lib/features/learning/pair_matching lib/features/learning/domain/learning_repository.dart lib/features/learning/domain/session_configuration.dart lib/features/learning/application/session_configuration_policy.dart lib/features/learning/data/drift_learning_repository.dart lib/features/identity/data/drift_owner_upgrade_repository.dart lib/features/export/application/owner_lifecycle_archive.dart test/features/learning/pair_matching test/features/identity/drift_owner_upgrade_repository_test.dart test/features/learning/session_configuration_policy_test.dart
```

4. Touched files formatted. Final diff inspected; `git diff --check` clean (only pre-existing/generated line-ending warnings).
5. Property coverage: 100 deterministic synthetic candidate permutations; deep nested mutation rejection; exact codec key/version/order/fingerprint tampering; Today/Review order; bilingual direction; exact density and explicit downgrade; accent/Thai display collisions; real Drift rollback, owner switch at SQL boundary, duplicate starts, advancing checkpoint retry, file DB close/reopen, gate-off-after-commit reconciliation, revoked gate rollback, report/delete/retirement gates; owner preference export/rebind and legacy v1 compatibility.

## Remaining integration / limits

- PM1 is an internal API implementation, not end-to-end gameplay or release readiness. Full suite/build/device/UAT were not run by this worker.
- TC-PMT-002–010 and source-collision portion of 012 covered here. TC-PMT-011 mismatch evidence attachment belongs to PM2/PM3 reducer/evidence integration; do not mark it passed from plan-direction tests alone.
- Initial v6 checkpoint is intentionally a minimal internal start state. PM2 must add the complete strict reducer/checkpoint codec, including remaining timer/repair/terminal reserve fields. PM4/PM5 own timer/replay lifecycle. Practice Replay enum/lineage exists but internal start capability rejects it until typed projection isolation is implemented.
- PM6 must compose the existing active-owner preference store save with actual one-time density UI and an externally authorized product guardian input. Persistence and policy roundtrip exist now; no UI is activated by PM1.
- An actual rollout must supply reviewed curated manifest pins and explicit delivery capability. No production curated data is fabricated; default delivery remains hidden/off.
- No schema/table or frozen evidence contract changed (v24 / 48 tables retained).

Next executable step: root acceptance review of PM1, then PM2 consumes immutable plan and `PairMatchingStartOperation.initialCheckpoint` v6, preserving canonical repository ownership and checkpoint reserve ceilings.

## Acceptance follow-up — density invariant and checksum evidence

- Root requested a bounded fix after independent review: the public const preference constructor admitted `fallback + standard6`, although the codec rejected it. Reproduced with `flutter test --no-pub test/features/learning/pair_matching/pair_matching_density_preference_test.dart --plain-name 'fallback six' --reporter compact`: exit 1, expected `ArgumentError` but constructor returned an invalid object.
- Public `PairDensityPreference` now validates the invariant at runtime construction. Removed `const` at four existing test callsites only. Invalid metadata cannot reach `withPairDensityPreference`; decoder still rejects invalid fallback as `FormatException`. Regression covers invalid construction/use/decoding and roundtrip for every valid density/provenance combination.
- Corrected the prior atomic test name from checksum drift to revision drift, matching its mutation. Added separate actual **same-revision checksum tampering** test: revision remains 1, stored checksum changes, canonical `ContentQualityFailure` rejects start, and session/event/answer tables stay empty. No production checksum logic changed.
- GREEN command: `flutter test --no-pub test/features/learning/pair_matching test/features/learning/session_configuration_policy_test.dart test/features/learning/session_configuration_store_test.dart --reporter compact` — 49 passed, exit 0 (29 Pair + 20 policy/store).
- GREEN owner compatibility: `flutter test --no-pub test/features/identity/drift_owner_upgrade_repository_test.dart --plain-name 'f16 upgrade' --reporter compact` — 2 passed, exit 0.
- After a test-only braces lint correction: density file rerun — 3 passed, exit 0. Focused `dart analyze lib/features/learning/pair_matching/domain/pair_matching_launch.dart test/features/learning/pair_matching test/features/learning/session_configuration_policy_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart` — no issues, exit 0.
- Two atomic `apply_patch` verifications failed before any writes (first stale unused context, then out-of-order hunks). Inspected exact file state and reordered the corrected hunks; third attempt succeeded within the recovery budget.
- No commit or index mutation. Root's staged snapshot remains intact; follow-up edits are unstaged. Tooling RELEASED again with no running process.
