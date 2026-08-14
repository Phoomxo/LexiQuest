# AllTCAS 8/44 Shared Compatibility Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the machine-verifiable contract and converge LexiQuest's current evidence, progression, streak, consent, experiment, and assessment authorities so the approved 8/44 capabilities can be added without creating parallel systems or contaminating educational-research data.

**Architecture:** Use a contract-first strangler approach. First add a behavior-neutral typed product catalog and drift gate, then introduce one versioned Evidence Gateway in front of the existing `AnswerAttempts` and `EventsV2` authorities, then converge XP/Coins and Streak, and only then persist research assignment and assessment runs. Every cutover is isolated behind focused tests, forward-only migrations, existing runtime kill switches, and a separate commit.

**Tech Stack:** Flutter/Dart, Drift/SQLite, Firebase Firestore rules, PowerShell product gates, SHA-256 canonical artifacts, Flutter unit/widget/integration tests, Node Firebase Rules tests.

## Global Constraints

- Execute in `C:\Users\Phet\Documents\LexiQuest\.worktrees\p0-integration` on `feature/alltcas-8-44-integration`, starting from design commit `c4ec20d` or a verified descendant.
- The main product scope remains exactly 8 domains and 44 capabilities; `expP1` and `expP2` remain outside the main count.
- Do not add TCAS/university scoring, online rooms/chat/friends, subscription/payment/entitlements, OCR handwriting, a public leaderboard, or a generic calculator.
- Do not create a third runtime feature registry, a second Vocabulary authority, a second Streak writer, a second scored-answer store, a Today Hub table, or a Learning History table.
- `FeatureRegistry` remains runtime availability authority; `ProductionFeatureContract` remains production delivery authority; `ExperimentRegistry` remains independent assignment authority.
- `AnswerAttempts` remains the canonical scored response; `EventsV2` remains the correlated immutable downstream event log. One source evidence identity must connect them.
- `legacy-v1` is a closed compatibility policy for migrated/current pre-cutover evidence only: it may reproduce the existing projections, but `classificationSource == legacyInferred` evidence is excluded from new research outcomes. New activities and assessments must use a declared, supported policy and fail closed otherwise.
- Schema sequence is fixed: v13 adds answer evidence metadata, v14 adds experiment assignments, and v15 adds assessment runs. Do not combine or renumber these migrations.
- Migrations are forward-only. Rollback disables invocation and preserves readable data; it never downgrades schema.
- Existing `Feature` enum names and order are persisted compatibility data and must not change.
- The Evidence Gateway is an always-on foundation after its cutover, not a sixteenth runtime `Feature`. Rollback uses the existing feature switches to stop affected activity entry points while preserving evidence/schema; it never bypasses eligibility policy.
- Keep the active field-release APK and its evidence frozen. These changes belong to a new development candidate and invalidate no existing release artifact because they are not merged into that candidate.
- Use TDD for every behavior change: observe the focused test fail for the intended reason, implement the smallest passing change, rerun focused tests, review the diff, then commit exact paths.
- Do not run implementation agents concurrently with security or repository-wide analysis. Use bounded Flutter, backend, Firestore, Supabase-policy, dependency, and manual-diff verification only.
- Stop a gate if the same filesystem/tool error repeats or if the gate makes no measurable progress for 10 minutes.
- Run broad product completion only at the final checkpoint. During individual tasks, run the named focused tests.

## Program Gate Order

```text
G0 Baseline proof
  -> G1 Machine-verifiable 8/44 catalog
  -> G2 Evidence contract and schema v13
  -> G3 Evidence enforcement and lifecycle
  -> G4 XP/Coins convergence
  -> G5 Streak single authority
  -> G6 Persisted research context and schema v14
  -> G7 Assessment isolation and schema v15
  -> G8 Full verification and rollout-off handoff
```

No new learner-facing 8/44 screen may be enabled before G3. Assessment stays unavailable before G7. Coin earning from new activities stays unavailable before both G3 and G4.

---

### Task 0: Prove the Starting Baseline Without Mixing Repairs

**Files:**
- Verify: `docs/superpowers/specs/2026-08-14-lexiquest-alltcas-idea-integration-feature-contract-design.md`
- Verify: `lib/data/local/app_database.dart`
- Verify: `lib/runtime/registries/feature_registry.dart`
- Verify: `lib/runtime/production_feature_contract.dart`
- Verify: `lib/features/identity/domain/owner_lifecycle_manifest.dart`
- Test: `test/architecture/production_feature_contract_test.dart`
- Test: `test/scenarios/complete_owner_export_delete_test.dart`

**Interfaces:**
- Consumes: design commit `c4ec20d`, Drift schema v12, current 15-value `Feature` enum, current 31-table lifecycle manifest.
- Produces: a recorded clean starting SHA and focused baseline evidence; no source modification.

- [ ] **Step 1: Verify exact branch and clean state**

```powershell
git branch --show-current
git rev-parse --short HEAD
git status --short
```

Expected: branch `feature/alltcas-8-44-integration`; HEAD is `c4ec20d` or a reviewed descendant; status is empty.

- [ ] **Step 2: Verify the design artifact is present in history**

```powershell
git log -1 --oneline -- docs/superpowers/specs/2026-08-14-lexiquest-alltcas-idea-integration-feature-contract-design.md
```

Expected: commit `c4ec20d` or a descendant commit that contains the unchanged approved design.

- [ ] **Step 3: Run focused baseline tests separately**

```powershell
flutter test --no-pub --timeout 90s test/architecture/production_feature_contract_test.dart
flutter test --no-pub --timeout 90s test/runtime/runtime_feature_controls_test.dart
flutter test --no-pub --timeout 90s test/scenarios/complete_owner_export_delete_test.dart
```

Expected: each command exits 0. Run them separately; do not combine them into one command whose timeout hides which suite stalled.

- [ ] **Step 4: Confirm current schema and lifecycle counts**

```powershell
Select-String -Path lib/data/local/app_database.dart -Pattern 'schemaVersion => 12'
(Select-String -Path lib/features/identity/domain/owner_lifecycle_manifest.dart -Pattern '^  OwnerLifecycleTableDescriptor\(').Count
```

Expected: schema v12 and 31 descriptors. If the descendant baseline intentionally changed either value, reconcile this plan and the design spec before Task 1 rather than guessing.

---

### Task 1: Extract Stable Runtime Identities and Add Product Contract Types

**Files:**
- Create: `lib/runtime/registries/feature.dart`
- Modify: `lib/runtime/registries/feature_registry.dart`
- Create: `lib/product/feature_contract/feature_contract_models.dart`
- Create: `test/architecture/alltcas_idea_feature_contract_models_test.dart`
- Test: `test/runtime/registries_test.dart`
- Test: `test/architecture/production_feature_contract_test.dart`

**Interfaces:**
- Consumes: current `Feature`, `FeatureState`, `FeatureRegistry`, and `ProductionFeatureContract` interfaces.
- Produces: pure-Dart stable runtime identities and typed immutable product-contract primitives. Existing imports through `feature_registry.dart` remain source-compatible.

- [ ] **Step 1: Write the failing identity/model test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_models.dart';
import 'package:vocab_learning_app/runtime/registries/feature.dart';

void main() {
  test('runtime feature identities remain the exact persisted 15 names', () {
    expect(Feature.values.map((value) => value.name), const <String>[
      'vocabulary',
      'quiz',
      'srs',
      'reading',
      'mastery',
      'weakness',
      'ghostDuel',
      'achievements',
      'shop',
      'objectScanner',
      'speechPractice',
      'aiTutor',
      'export',
      'shadowRewardV2',
      'questV2',
    ]);
  });

  test('product contract identities are the exact f01 through f44 range', () {
    expect(FeatureContractId.values, hasLength(44));
    expect(FeatureContractId.values.first.name, 'f01');
    expect(FeatureContractId.values.last.name, 'f44');
    expect(
      FeatureContractId.values.map((value) => value.ordinal),
      List<int>.generate(44, (index) => index + 1),
    );
  });

  test('eight product domains map one-to-one to C1 through C8', () {
    expect(FeatureDomain.values, hasLength(8));
    expect(
      FeatureDomain.values.map((value) => value.completionContract),
      CompletionContractId.values,
    );
  });
}
```

- [ ] **Step 2: Run the test and observe the intended compile failure**

```powershell
flutter test --no-pub test/architecture/alltcas_idea_feature_contract_models_test.dart
```

Expected: failure because `feature.dart` and `feature_contract_models.dart` do not exist.

- [ ] **Step 3: Extract the existing runtime enums without renaming or reordering**

```dart
// lib/runtime/registries/feature.dart
enum Feature {
  vocabulary,
  quiz,
  srs,
  reading,
  mastery,
  weakness,
  ghostDuel,
  achievements,
  shop,
  objectScanner,
  speechPractice,
  aiTutor,
  export,
  shadowRewardV2,
  questV2,
}

enum FeatureState { enabled, limited, hidden, disabled, emergencyOff }
```

In `feature_registry.dart`, remove only the two enum declarations, then add:

```dart
export 'feature.dart';
import 'feature.dart';
```

Do not change registry defaults, runtime override semantics, or any enum value.

- [ ] **Step 4: Add typed product-contract primitives**

```dart
enum FeatureContractId {
  f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11,
  f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22,
  f23, f24, f25, f26, f27, f28, f29, f30, f31, f32, f33,
  f34, f35, f36, f37, f38, f39, f40, f41, f42, f43, f44,
}

extension FeatureContractIdX on FeatureContractId {
  int get ordinal => index + 1;
}

enum CompletionContractId { c1, c2, c3, c4, c5, c6, c7, c8 }

enum FeatureDomain {
  learningContentAndPacks(CompletionContractId.c1),
  unifiedLearningExperience(CompletionContractId.c2),
  recallFeedbackAndControl(CompletionContractId.c3),
  reviewTimeAndAssessment(CompletionContractId.c4),
  motivationAndEngagement(CompletionContractId.c5),
  personalizationAndAccessibility(CompletionContractId.c6),
  localReliabilityOfflineAndRollout(CompletionContractId.c7),
  dailyContinuityAndHistory(CompletionContractId.c8);

  const FeatureDomain(this.completionContract);
  final CompletionContractId completionContract;
}

enum FeatureProvenance { alltcasConfirmed, adaptedToLexiQuest, lexiQuestControl }
enum FeatureCoverage { existing, partial, newCapability }
enum ResearchRole { neutral, infrastructure, intervention, measurement, engagement }
enum ContractEvidenceClass {
  assessment,
  independentRecall,
  recognition,
  guidedPractice,
  pronunciation,
  exposure,
  recreational,
}
enum ProjectionFamily {
  sessionOutcome,
  masterySrs,
  assessmentOutcome,
  activeLearningEffort,
  history,
  pronunciation,
  quest,
  streak,
  achievement,
  xp,
  coins,
}
enum ProjectionDecision { allow, deny, protocolControlled }
enum ActivationKind { alwaysOnFoundation, runtimeFlagged, protocolAssigned, readModelOnly }
enum DomainAuthority {
  vocabulary,
  responseEvidence,
  masterySrs,
  assessment,
  streak,
  lifetimeXp,
  spendableCoins,
  quest,
  history,
  downloadState,
}
enum ExperimentalCandidateId { expP1, expP2 }

extension type const ProductionEntryId(String value) {}
extension type const VerificationRef(String value) {}
extension type const AuthorityProfileId(String value) {}
extension type const EvidenceProfileId(String value) {}
extension type const LifecycleProfileId(String value) {}
extension type const ActivationProfileId(String value) {}
extension type const RolloutProfileId(String value) {}
extension type const RollbackProfileId(String value) {}
```

Add immutable `ProductFeatureContract`, `ExperimentalCandidate`, and `ProductFeatureCatalog` classes with final fields for ID, name, purpose, domain, provenance, coverage, research role, runtime features, dependencies, profile IDs, production entry IDs, verification references, and introduction revision. Constructors must copy sets/lists with `Set.unmodifiable` and `List.unmodifiable` in non-const validation factories; const seed records remain deeply immutable by convention and are verified by tests.

- [ ] **Step 5: Run compatibility tests**

```powershell
flutter test --no-pub test/architecture/alltcas_idea_feature_contract_models_test.dart test/runtime/registries_test.dart test/architecture/production_feature_contract_test.dart test/runtime/runtime_feature_controls_test.dart
```

Expected: all tests pass and existing feature imports remain valid.

- [ ] **Step 6: Commit the isolated identity change**

```powershell
git add -- lib/runtime/registries/feature.dart lib/runtime/registries/feature_registry.dart lib/product/feature_contract/feature_contract_models.dart test/architecture/alltcas_idea_feature_contract_models_test.dart
git diff --cached --check
git commit -m "refactor: extract stable runtime feature identities"
```

---

### Task 2: Add the Exact 8/44 Catalog and Compatibility Profiles

**Files:**
- Create: `lib/product/feature_contract/compatibility_profiles.dart`
- Create: `lib/product/feature_contract/alltcas_idea_integration_catalog.dart`
- Create: `test/architecture/alltcas_idea_feature_contract_test.dart`
- Read: `lib/runtime/production_feature_contract.dart`
- Read: `docs/superpowers/specs/2026-08-14-lexiquest-alltcas-idea-integration-feature-contract-design.md`

**Interfaces:**
- Consumes: Task 1 types and the exact approved inventory in design §6.
- Produces: `allTcasIdeaIntegrationCatalog`, `singleWriterAuthorityMatrix`, complete evidence/profile maps, and typed mappings to all current runtime features.

- [ ] **Step 1: Write the failing catalog test**

The test must assert:

```dart
expect(allTcasIdeaIntegrationCatalog.records, hasLength(44));
expect(
  allTcasIdeaIntegrationCatalog.records.map((record) => record.id),
  FeatureContractId.values,
);
expect(
  allTcasIdeaIntegrationCatalog.experimentalCandidates.map((item) => item.id),
  ExperimentalCandidateId.values,
);
expect(domainCounts, <FeatureDomain, int>{
  FeatureDomain.learningContentAndPacks: 4,
  FeatureDomain.unifiedLearningExperience: 9,
  FeatureDomain.recallFeedbackAndControl: 8,
  FeatureDomain.reviewTimeAndAssessment: 7,
  FeatureDomain.motivationAndEngagement: 6,
  FeatureDomain.personalizationAndAccessibility: 5,
  FeatureDomain.localReliabilityOfflineAndRollout: 3,
  FeatureDomain.dailyContinuityAndHistory: 2,
});
expect(coverageCounts[FeatureCoverage.existing], 8);
expect(coverageCounts[FeatureCoverage.partial], 23);
expect(coverageCounts[FeatureCoverage.newCapability], 13);
```

Also assert exact Existing IDs:

```dart
const <FeatureContractId>{
  FeatureContractId.f06,
  FeatureContractId.f07,
  FeatureContractId.f17,
  FeatureContractId.f29,
  FeatureContractId.f30,
  FeatureContractId.f31,
  FeatureContractId.f40,
  FeatureContractId.f41,
};
```

Assert exact Partial IDs:

```dart
const <FeatureContractId>{
  FeatureContractId.f01, FeatureContractId.f02, FeatureContractId.f03,
  FeatureContractId.f04, FeatureContractId.f08, FeatureContractId.f09,
  FeatureContractId.f11, FeatureContractId.f13, FeatureContractId.f14,
  FeatureContractId.f15, FeatureContractId.f16, FeatureContractId.f19,
  FeatureContractId.f22, FeatureContractId.f24, FeatureContractId.f25,
  FeatureContractId.f32, FeatureContractId.f33, FeatureContractId.f36,
  FeatureContractId.f37, FeatureContractId.f38, FeatureContractId.f39,
  FeatureContractId.f43, FeatureContractId.f44,
};
```

Assert exact New IDs:

```dart
const <FeatureContractId>{
  FeatureContractId.f05, FeatureContractId.f10, FeatureContractId.f12,
  FeatureContractId.f18, FeatureContractId.f20, FeatureContractId.f21,
  FeatureContractId.f23, FeatureContractId.f26, FeatureContractId.f27,
  FeatureContractId.f28, FeatureContractId.f34, FeatureContractId.f35,
  FeatureContractId.f42,
};
```

Assert exact domain membership, not counts alone: C1 `{f01–f04}`, C2 `{f05–f13}`, C3 `{f14–f21}`, C4 `{f22–f28}`, C5 `{f29–f34}`, C6 `{f35–f39}`, C7 `{f40,f41,f44}`, and C8 `{f42,f43}`.

Assert every dependency resolves, depth-first search finds no cycle, every profile reference resolves, the evidence matrix is a complete Cartesian product, and assessment denies Mastery/SRS, Quest, Streak, Achievement, XP, and Coins.

- [ ] **Step 2: Run the test and observe the missing-catalog failure**

```powershell
flutter test --no-pub test/architecture/alltcas_idea_feature_contract_test.dart
```

Expected: compile failure because catalog/profile files do not exist.

- [ ] **Step 3: Add the exact catalog constants**

```dart
const String featureContractRevision = '1.0.0';
const String featureContractBaselineCommit = '61a4fec';
const int featureContractSchemaVersion = 1;
const String featureContractGeneratorVersion = '1.0.0';
```

Create records in numeric `f01` through `f44` order. Use the exact names and responsibilities from design §6. Map domains so C1/C2/C3/C4/C5/C6 contain `f01–f04`, `f05–f13`, `f14–f21`, `f22–f28`, `f29–f34`, `f35–f39`; C7 contains `f40`, `f41`, `f44`; C8 contains `f42`, `f43`.

Use these exact runtime mappings:

| Runtime feature | Product contracts |
|---|---|
| `vocabulary` | f01, f02, f03 |
| `quiz` | f07, f08, f09, f11 |
| `srs` | f06, f14, f22 |
| `reading` | f13 |
| `mastery` | f36 |
| `weakness` | f36 |
| `ghostDuel` | f13 |
| `achievements` | f31 |
| `shop` | f32 |
| `objectScanner` | f13 |
| `speechPractice` | f13 |
| `aiTutor` | f19, f33 |
| `export` | f40 |
| `shadowRewardV2` | f29 |
| `questV2` | f29 |

Production entry IDs must wrap the exact non-empty values from `productionFeatureContract`; no product record may invent a route string.

- [ ] **Step 4: Add single-writer and evidence matrices**

Define exactly one writer profile for Vocabulary, Response Evidence, Mastery/SRS, Assessment, Streak, Lifetime XP, Spendable Coins, Quest, History, and Download State. Define all seven evidence classes and all projection families as explicit map keys; no `Map` lookup may fall back to Allow.

Use this exact v1 matrix (`A` Allow, `D` Deny, `P` ProtocolControlled):

| Evidence class | Session | Mastery/SRS | Assessment | Active Learning Effort | History | Pronunciation | Quest | Streak | Achievement | XP | Coins |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Assessment | A | D | A | A | A | D | D | D | D | D | D |
| Independent Recall | A | A | D | A | A | D | P | P | P | P | P |
| Recognition | A | D | D | A | A | D | P | P | P | P | P |
| Guided Practice | A | D | D | A | A | D | D | D | D | D | D |
| Pronunciation | A | D | D | A | A | A | D | D | D | D | D |
| Exposure | A | D | D | A | A | D | D | D | D | D | D |
| Recreational | A | D | D | D | A | D | D | D | D | D | D |

Recognition remains excluded from binary SRS v1 because the current algorithm has no calibrated lower-weight update. A later weighted policy requires a new policy version rather than silently treating recognition as independent recall.

The assessment row must be:

```dart
const <ProjectionFamily, ProjectionDecision>{
  ProjectionFamily.sessionOutcome: ProjectionDecision.allow,
  ProjectionFamily.masterySrs: ProjectionDecision.deny,
  ProjectionFamily.assessmentOutcome: ProjectionDecision.allow,
  ProjectionFamily.activeLearningEffort: ProjectionDecision.allow,
  ProjectionFamily.history: ProjectionDecision.allow,
  ProjectionFamily.pronunciation: ProjectionDecision.deny,
  ProjectionFamily.quest: ProjectionDecision.deny,
  ProjectionFamily.streak: ProjectionDecision.deny,
  ProjectionFamily.achievement: ProjectionDecision.deny,
  ProjectionFamily.xp: ProjectionDecision.deny,
  ProjectionFamily.coins: ProjectionDecision.deny,
};
```

- [ ] **Step 5: Run catalog compatibility tests**

```powershell
flutter test --no-pub test/architecture/alltcas_idea_feature_contract_models_test.dart test/architecture/alltcas_idea_feature_contract_test.dart test/architecture/production_feature_contract_test.dart test/runtime/registries_test.dart
```

Expected: all pass; runtime feature count remains 15 while product contract count is 44.

- [ ] **Step 6: Commit the catalog**

```powershell
git add -- lib/product/feature_contract/compatibility_profiles.dart lib/product/feature_contract/alltcas_idea_integration_catalog.dart test/architecture/alltcas_idea_feature_contract_test.dart
git diff --cached --check
git commit -m "feat: add typed 8-44 product feature contract"
```

---

### Task 3: Generate Deterministic Markdown and JSON and Enforce Drift

**Files:**
- Create: `lib/product/feature_contract/feature_contract_digest.dart`
- Create: `tool/feature_contract/generate_feature_map.dart`
- Create: `test/architecture/alltcas_idea_feature_contract_docs_test.dart`
- Generate: `docs/generated/alltcas-idea-integration-feature-map.md`
- Generate: `docs/generated/alltcas-idea-integration-feature-map.json`
- Modify: `lib/runtime/production_feature_contract.dart`
- Modify: `tool/cli/tests/verify-product-completion.tests.ps1`
- Modify: `tool/cli/verify-product-completion.ps1`

**Interfaces:**
- Consumes: `allTcasIdeaIntegrationCatalog`.
- Produces: deterministic `FeatureMapArtifacts`, a reusable executable contract-identity registry, `--write`, `--check`, SHA-256 semantic hash, and two product-completion gates.

- [ ] **Step 1: Write failing generator tests**

Define and test these signatures:

```dart
final class FeatureMapArtifacts {
  const FeatureMapArtifacts({
    required this.markdown,
    required this.normalizedJson,
    required this.semanticHash,
  });

  final String markdown;
  final String normalizedJson;
  final String semanticHash;
}

FeatureMapArtifacts buildFeatureMapArtifacts(ProductFeatureCatalog catalog);
String canonicalSemanticCatalogJson(ProductFeatureCatalog catalog);
String catalogSemanticSha256(ProductFeatureCatalog catalog);
int runFeatureMapGenerator(
  List<String> arguments, {
  Directory? repositoryRoot,
  void Function(String message)? stdout,
  void Function(String message)? stderr,
});
```

Keep canonical semantic serialization and SHA-256 calculation in `feature_contract_digest.dart`, which imports neither `dart:io` nor generator code. Expose `FeatureContractIdentity(revision, semanticHash)`, `currentFeatureContractIdentity`, and an append-only `supportedFeatureContractIdentities` registry. The current identity is derived from `featureContractRevision` plus `catalogSemanticSha256(allTcasIdeaIntegrationCatalog)`; a future revision must retain any identity that already appears in persisted evidence so replay never depends on whichever catalog happens to be current.

Tests must cover double-render equality, valid JSON, lowercase 64-character hash, LF-only output, one final newline, missing-output detection, tamper detection without writes, unsupported argument exit 64, and numeric JSON order. Also test that `--write` rejects a semantic-hash change under the same contract revision, while a revision-only bump with the same semantic hash succeeds with a warning. Markdown may group f44 in Domain 7 before f42/f43 in Domain 8.

- [ ] **Step 2: Observe the missing-generator failure**

```powershell
flutter test --no-pub test/architecture/alltcas_idea_feature_contract_docs_test.dart
```

Expected: compile failure because the generator does not exist.

- [ ] **Step 3: Implement canonical serialization and modes**

Use `dart:convert` and `package:crypto/crypto.dart` in the reusable digest module; use `dart:io` only in the CLI generator. Insert JSON keys in fixed order; sort sets by serialized identifier; exclude revision, generator presentation metadata, and hash from the semantic hash input. Before overwriting an existing JSON artifact, compare its stored revision/hash with the new values: same revision plus changed semantic hash exits 1 without writes; changed revision plus unchanged hash emits a warning and may write. `--check` performs no writes and exits 1 on byte drift; `--write` writes UTF-8 LF output only.

Import `registries/feature.dart` directly from `lib/runtime/production_feature_contract.dart` so the catalog remains reachable by the pure-Dart generator without transitively loading Flutter's `dart:ui` dependency.

- [ ] **Step 4: Generate and re-check artifacts**

```powershell
dart run tool/feature_contract/generate_feature_map.dart --check
dart run tool/feature_contract/generate_feature_map.dart --write
dart run tool/feature_contract/generate_feature_map.dart --check
flutter test --no-pub test/architecture/alltcas_idea_feature_contract_docs_test.dart
```

Expected: first check exits 1 because files are absent; write succeeds; second check and test exit 0.

- [ ] **Step 5: Write the failing PowerShell gate contract**

Require exact gate labels `Feature contract tests` and `Feature contract generated artifacts`, plus this command:

```powershell
& dart run 'tool/feature_contract/generate_feature_map.dart' --check
```

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/verify-product-completion.tests.ps1
```

Expected: failure indicating the new gate or command is missing.

- [ ] **Step 6: Add focused gates before the existing product-completion suite**

```powershell
Invoke-Gate 'Feature contract tests' {
    & flutter test --no-pub --timeout 90s --reporter compact `
        'test/architecture/alltcas_idea_feature_contract_test.dart' `
        'test/architecture/alltcas_idea_feature_contract_docs_test.dart'
}
Invoke-Gate 'Feature contract generated artifacts' {
    & dart run 'tool/feature_contract/generate_feature_map.dart' --check
}
```

- [ ] **Step 7: Verify and commit**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/verify-product-completion.tests.ps1
dart run tool/feature_contract/generate_feature_map.dart --check
flutter test --no-pub test/architecture/alltcas_idea_feature_contract_models_test.dart test/architecture/alltcas_idea_feature_contract_test.dart test/architecture/alltcas_idea_feature_contract_docs_test.dart
dart format --output=none --set-exit-if-changed lib/runtime/registries/feature.dart lib/runtime/registries/feature_registry.dart lib/product/feature_contract tool/feature_contract test/architecture/alltcas_idea_feature_contract_models_test.dart test/architecture/alltcas_idea_feature_contract_test.dart test/architecture/alltcas_idea_feature_contract_docs_test.dart
git add -- lib/runtime/production_feature_contract.dart lib/product/feature_contract/feature_contract_digest.dart tool/feature_contract/generate_feature_map.dart test/architecture/alltcas_idea_feature_contract_docs_test.dart docs/generated/alltcas-idea-integration-feature-map.md docs/generated/alltcas-idea-integration-feature-map.json tool/cli/tests/verify-product-completion.tests.ps1 tool/cli/verify-product-completion.ps1
git diff --cached --check
git commit -m "build: enforce generated feature contract drift"
```

---

### Task 4: Add the Pure Evidence Context and Eligibility Matrix

**Files:**
- Create: `lib/features/learning/domain/evidence_context.dart`
- Create: `lib/features/learning/domain/evidence_eligibility_policy.dart`
- Create: `test/features/learning/evidence_context_test.dart`
- Create: `test/features/learning/evidence_eligibility_policy_test.dart`
- Modify: `test/architecture/alltcas_idea_feature_contract_test.dart`

**Interfaces:**
- Consumes: Task 2 evidence profile semantics.
- Produces: runtime `EvidenceContext`, `EvidenceEligibilityPolicy`, and exact parity tests between product metadata and runtime policy. No schema or behavior change.

- [ ] **Step 1: Write failing 7×11 matrix and serialization tests**

```dart
enum EvidenceClass {
  assessment,
  independentRecall,
  recognition,
  guidedPractice,
  pronunciation,
  exposure,
  recreational,
}

enum LearningProjection {
  sessionOutcome,
  masterySrs,
  assessmentOutcome,
  activeLearningEffort,
  history,
  pronunciation,
  quest,
  streak,
  achievement,
  xp,
  coins,
}

enum ProjectionDisposition { allow, deny, protocolControlled }
enum EvidencePolicyRolloutMode { legacy, shadow, enforced }
```

Test every pair. Unknown policy versions and invalid serialized enum names must throw a typed `FormatException` and must never default to Allow.

- [ ] **Step 2: Observe the intended missing-type failure**

```powershell
flutter test --no-pub test/features/learning/evidence_context_test.dart test/features/learning/evidence_eligibility_policy_test.dart
```

Expected: compile failure because the two domain files do not exist.

- [ ] **Step 3: Implement the immutable context**

```dart
enum EvidenceClassificationSource { declared, legacyInferred }

final class EvidenceContext {
  static const int schemaVersion = 1;

  const EvidenceContext({
    required this.evidenceClass,
    required this.skillId,
    required this.hintLevel,
    required this.policyVersion,
    required this.contentRevision,
    required this.featureContractRevision,
    required this.featureContractHash,
    required this.classificationSource,
    required this.rolloutMode,
    this.protocolId,
    this.protocolVersion,
    this.experimentId,
    this.experimentVersion,
    this.assignmentId,
    this.cohort,
    this.researchConsentVersion,
    this.instrumentId,
    this.instrumentVersion,
    this.formId,
    this.formVersion,
    this.assessmentItemId,
    this.assessmentResponseCode,
    this.scoringRuleVersion,
    this.engagementAllowed = false,
  });

  final EvidenceClass evidenceClass;
  final String skillId;
  final int hintLevel;
  final String policyVersion;
  final String contentRevision;
  final String featureContractRevision;
  final String featureContractHash;
  final EvidenceClassificationSource classificationSource;
  final EvidencePolicyRolloutMode rolloutMode;
  final String? protocolId;
  final String? protocolVersion;
  final String? experimentId;
  final int? experimentVersion;
  final String? assignmentId;
  final String? cohort;
  final int? researchConsentVersion;
  final String? instrumentId;
  final String? instrumentVersion;
  final String? formId;
  final String? formVersion;
  final String? assessmentItemId;
  final String? assessmentResponseCode;
  final String? scoringRuleVersion;
  final bool engagementAllowed;

  Map<String, Object?> toJson();
  factory EvidenceContext.fromJson(Map<String, Object?> json);
}
```

`fromJson` requires the exact schema version, bounded nonblank identifiers, `hintLevel >= 0`, known enums, explicit `rolloutMode`, and explicit `engagementAllowed`. `legacyInferred` requires `rolloutMode == legacy`, `featureContractRevision == 'legacy-unversioned'`, and `featureContractHash == '0000000000000000000000000000000000000000000000000000000000000000'`. Every declared context requires a lowercase 64-character SHA-256 and a revision/hash pair present in the append-only executable `supportedFeatureContractIdentities`; new evidence creation must use `currentFeatureContractIdentity`, while replay may use a retained historical identity. Declared Shadow/Enforced evidence additionally requires protocol ID/version, experiment ID/version, assignment ID, cohort, and a positive research-consent version. Assessment context additionally requires nonblank instrument, form, assessment-item, controlled response-code, and scoring-rule IDs/versions; non-assessment contexts may omit the instrument/form/response fields.

- [ ] **Step 4: Implement policy v1**

```dart
abstract interface class EvidenceEligibilityPolicy {
  String get version;
  ProjectionDisposition disposition(
    EvidenceContext context,
    LearningProjection projection,
  );
}

final class EvidenceEligibilityPolicySet implements EvidenceEligibilityPolicy {
  const EvidenceEligibilityPolicySet();

  @override
  String get version => 'policy-set-v1';

  @override
  ProjectionDisposition disposition(
    EvidenceContext context,
    LearningProjection projection,
  ) {
    return switch (context.policyVersion) {
      EvidenceEligibilityPolicyV1.policyVersion =>
        const EvidenceEligibilityPolicyV1().disposition(context, projection),
      'legacy-v1' when
          context.classificationSource ==
              EvidenceClassificationSource.legacyInferred =>
        legacyEvidenceEligibilityV1[projection]!,
      _ => throw StateError(
        'Unsupported evidence policy ${context.policyVersion}.',
      ),
    };
  }
}

final class EvidenceEligibilityPolicyV1 implements EvidenceEligibilityPolicy {
  const EvidenceEligibilityPolicyV1();
  static const String policyVersion = 'learning-evidence-v1';

  @override
  String get version => policyVersion;

  @override
  ProjectionDisposition disposition(
    EvidenceContext context,
    LearningProjection projection,
  ) {
    if (context.policyVersion != policyVersion) {
      throw StateError('Unsupported evidence policy ${context.policyVersion}.');
    }
    return evidenceEligibilityV1[context.evidenceClass]![projection]!;
  }
}
```

Make `evidenceEligibilityV1` exhaustive across all 11 projection families and fail construction tests if a row or column is missing. Define `legacyEvidenceEligibilityV1` as this exact compatibility row: Allow `sessionOutcome`, `masterySrs`, `activeLearningEffort`, `history`, `quest`, `streak`, `achievement`, `xp`, and `coins`; Deny `assessmentOutcome` and `pronunciation`. It is valid only with `classificationSource == legacyInferred`; it never contributes to a new research outcome/export cohort, and a declared context using `legacy-v1` fails closed. Unknown policies always fail closed.

Add a pure `EvidenceProjectionDecision` resolver. In Legacy mode it uses the compatibility row. In Shadow mode it returns both the compatibility decision to apply and the v1 candidate decision to record, without changing a sink. In Enforced mode it applies the v1 decision. Shadow evidence is excluded from efficacy outcomes but retained for projection comparison.

- [ ] **Step 5: Verify policy/catalog parity and commit**

```powershell
flutter test --no-pub test/features/learning/evidence_context_test.dart test/features/learning/evidence_eligibility_policy_test.dart test/architecture/alltcas_idea_feature_contract_test.dart
git add -- lib/features/learning/domain/evidence_context.dart lib/features/learning/domain/evidence_eligibility_policy.dart test/features/learning/evidence_context_test.dart test/features/learning/evidence_eligibility_policy_test.dart test/architecture/alltcas_idea_feature_contract_test.dart
git diff --cached --check
git commit -m "feat: define versioned learning evidence eligibility"
```

---

### Task 5: Persist Evidence Metadata with Forward-Only Schema v13

**Files:**
- Modify: `lib/data/local/tables/learning_tables.dart`
- Modify: `lib/data/local/app_database.dart`
- Regenerate: `lib/data/local/app_database.g.dart`
- Modify: `lib/features/learning/domain/learning_models.dart`
- Modify: `lib/features/learning/domain/learning_evidence_contract.dart`
- Modify: `lib/features/learning/application/learning_use_cases.dart`
- Modify: `lib/features/learning/data/drift_learning_repository.dart`
- Modify: `lib/features/sync/data/drift_sync_store.dart`
- Modify: `lib/features/identity/domain/owner_lifecycle_manifest.dart`
- Modify: `lib/features/export/application/owner_lifecycle_archive.dart`
- Create: `test/database/migration_v12_to_v13_test.dart`
- Modify: `test/data/local/app_database_migration_test.dart`
- Modify: `test/features/learning/drift_learning_repository_test.dart`
- Modify: `test/features/learning/learning_use_cases_test.dart`
- Modify: `test/features/sync/learning_event_sync_test.dart`
- Modify: `test/features/progress/progress_projector_test.dart`
- Modify: `test/data/local/app_database_test.dart`
- Modify: `test/database/migration_v11_to_v12_test.dart`
- Modify: `test/database/migration_v9_to_v10_test.dart`
- Modify: `test/database/migration_v8_to_v9_test.dart`
- Modify: `test/database/migration_v7_to_v8_test.dart`
- Modify: `test/features/ai_tutor/secure_ai_tutor_settings_store_test.dart`
- Modify: `test/features/ai_tutor/drift_ai_usage_repository_test.dart`
- Modify: `test/features/export/export_use_cases_test.dart`
- Modify: `test/scenarios/complete_owner_export_delete_test.dart`
- Modify: `test/scenarios/file_backed_sync_recovery_test.dart`
- Modify: `test/scenarios/guest_upgrade_restart_test.dart`
- Modify: `test/features/identity/drift_owner_upgrade_repository_test.dart`
- Modify: `docs/database/schema_ledger.md`

**Interfaces:**
- Consumes: `EvidenceContext` and the existing `RecordAnswerCommand`/`AnswerAttempts` transaction.
- Produces: schema v13 with exact evidence metadata persisted on the existing canonical attempt row. It creates no new table.

- [ ] **Step 1: Write failing v12→v13 migration tests**

Create a v12 fixture with one attempt, upgrade it, and assert the old attempt remains while these columns exist and decode as legacy evidence:

```dart
expect(attempt.evidenceClass, EvidenceClass.independentRecall.name);
final context = EvidenceContext.fromJson(
  (jsonDecode(attempt.evidenceContextJson) as Map).cast<String, Object?>(),
);
expect(context.classificationSource, EvidenceClassificationSource.legacyInferred);
expect(context.policyVersion, 'legacy-v1');
expect(context.engagementAllowed, isTrue);
```

- [ ] **Step 2: Observe the missing-column failure**

```powershell
flutter test --no-pub test/database/migration_v12_to_v13_test.dart
```

Expected: failure because schema is v12 and evidence columns do not exist.

- [ ] **Step 3: Add columns and migration**

```dart
TextColumn get evidenceClass =>
    text().withDefault(const Constant('independentRecall'))();

TextColumn get evidenceContextJson => text().withDefault(
  const Constant(
    '{"schemaVersion":1,"evidenceClass":"independentRecall",'
     '"skillId":"legacy-unspecified","hintLevel":0,'
     '"policyVersion":"legacy-v1","contentRevision":"legacy-unknown",'
     '"featureContractRevision":"legacy-unversioned",'
     '"featureContractHash":"0000000000000000000000000000000000000000000000000000000000000000",'
     '"classificationSource":"legacyInferred","rolloutMode":"legacy",'
     '"protocolId":null,"protocolVersion":null,'
     '"experimentId":null,"experimentVersion":null,'
     '"assignmentId":null,"cohort":null,"researchConsentVersion":null,'
     '"instrumentId":null,"instrumentVersion":null,'
     '"formId":null,"formVersion":null,'
     '"assessmentItemId":null,"assessmentResponseCode":null,'
     '"scoringRuleVersion":null,'
    '"engagementAllowed":true}',
  ),
)();
```

The migration JSON keeps every nullable canonical key present as explicit JSON `null` so strict schema-v1 decoding remains stable.

Introduce `AppDatabase.currentSchemaVersion = 13` and make `schemaVersion` return that constant. Replace every test assertion that means "the current schema"—including the v7→v8 and export inventories—with `AppDatabase.currentSchemaVersion`; keep historical fixture setup and historical-version assertions literal. Rename misleading "fresh v12" test titles to "fresh current schema preserves the v12 contract." In `onUpgrade`, for `from < 13`, add both columns with `_addColumnIfMissing`. Do not alter existing answer IDs, SRS rows, points, achievements, events, or outbox rows.

- [ ] **Step 4: Extend the command and replay equality**

Add required `EvidenceContext evidenceContext` to `RecordAnswerCommand`. Insert both fields and require exact top-level and nested equality, including `evidence_class == decoded evidenceContext.evidenceClass.name`, on local write, read, replay, and the existing owner-lifecycle archive. Extend `_sameAttempt` and `LearningEvidenceContract.validAttempt` to compare every serialized field, including the feature-contract revision/hash, so the same ID with different evidence metadata throws `StateError`. Payload-v1 sync ingress has no declared research metadata, so it must materialize the frozen `EvidenceContext.legacyCompatibility(...)` context before inserting the canonical attempt. Keep the existing public `LearningUseCases.recordAnswer` signature during this task; it constructs the explicit compatibility context below so every current caller continues to compile and every commit remains releasable.

Outbound/cloud sync v2, Firestore rules/config, and flattened research export v2 remain owned by Task 8. Declared research evidence is unavailable to those paths until that cutover; Task 5 must not silently serialize declared metadata into the legacy payload-v1 contract.

For existing production callers during this task, pass one explicit compatibility context:

```dart
EvidenceContext.legacyCompatibility(
  evidenceClass: EvidenceClass.independentRecall,
  skillId: 'legacy-current-activity',
  hintLevel: 0,
  contentRevision: 'legacy-unknown',
  engagementAllowed: true,
)
```

This preserves behavior but makes legacy origin auditable. It is not valid for new research assessment.

- [ ] **Step 5: Regenerate Drift code and run focused tests**

```powershell
dart run build_runner build --delete-conflicting-outputs
flutter test --no-pub test/database/migration_v12_to_v13_test.dart test/data/local/app_database_migration_test.dart test/data/local/app_database_test.dart
flutter test --no-pub test/features/learning/drift_learning_repository_test.dart test/features/learning/learning_use_cases_test.dart
flutter test --no-pub test/database/migration_v11_to_v12_test.dart test/database/migration_v9_to_v10_test.dart test/database/migration_v8_to_v9_test.dart
flutter test --no-pub test/database/migration_v7_to_v8_test.dart test/features/export/export_use_cases_test.dart
flutter test --no-pub test/features/ai_tutor/secure_ai_tutor_settings_store_test.dart test/features/ai_tutor/drift_ai_usage_repository_test.dart test/scenarios/complete_owner_export_delete_test.dart
flutter test --no-pub test/features/sync/learning_event_sync_test.dart test/features/progress/progress_projector_test.dart
flutter test --no-pub test/scenarios/file_backed_sync_recovery_test.dart test/scenarios/guest_upgrade_restart_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart
```

Expected: migration and replay tests pass; old attempts rebuild exactly as before.

- [ ] **Step 6: Update the schema ledger and commit**

```powershell
git add -- lib/data/local/tables/learning_tables.dart lib/data/local/app_database.dart lib/data/local/app_database.g.dart lib/features/learning/domain/learning_models.dart lib/features/learning/domain/learning_evidence_contract.dart lib/features/learning/application/learning_use_cases.dart lib/features/learning/data/drift_learning_repository.dart lib/features/sync/data/drift_sync_store.dart lib/features/identity/domain/owner_lifecycle_manifest.dart lib/features/export/application/owner_lifecycle_archive.dart test/database/migration_v12_to_v13_test.dart test/data/local/app_database_migration_test.dart test/data/local/app_database_test.dart test/database/migration_v11_to_v12_test.dart test/database/migration_v9_to_v10_test.dart test/database/migration_v8_to_v9_test.dart test/database/migration_v7_to_v8_test.dart test/features/ai_tutor/secure_ai_tutor_settings_store_test.dart test/features/ai_tutor/drift_ai_usage_repository_test.dart test/features/export/export_use_cases_test.dart test/features/learning/drift_learning_repository_test.dart test/features/learning/learning_use_cases_test.dart test/features/sync/learning_event_sync_test.dart test/features/progress/progress_projector_test.dart test/scenarios/complete_owner_export_delete_test.dart test/scenarios/file_backed_sync_recovery_test.dart test/scenarios/guest_upgrade_restart_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart docs/database/schema_ledger.md
git diff --cached --check
git commit -m "feat: persist evidence context in schema v13"
```

Rollback after deployment: disable all new activity invocation and continue reading v13; never downgrade to v12.

---

### Task 6: Reuse One Evidence Identity Across Attempt, Event, Outbox, and Receipt

**Files:**
- Create: `lib/features/learning/domain/learning_event_context.dart`
- Modify: `lib/features/learning/application/learning_use_cases.dart`
- Modify: `lib/features/events/application/event_v1_to_v2_adapter.dart`
- Modify: `lib/features/learning/domain/learning_models.dart`
- Modify: `lib/features/learning/data/drift_learning_repository.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Modify: `test/features/learning/learning_use_cases_test.dart`
- Modify: `test/features/events/event_v1_to_v2_adapter_test.dart`
- Modify: `test/features/learning/drift_learning_repository_test.dart`

**Interfaces:**
- Consumes: schema v13 attempt metadata.
- Produces: a new caller-owned `recordEvidence` API, versioned learning-event context, optional SRS result, and Event V2 payload version 2 with serialized evidence context while preserving the old compatibility entry point until all production callers migrate.

- [ ] **Step 1: Write failing deterministic identity tests**

Test that two retries with the same ID/context/time create one attempt, one `learning-event:{sourceEvidenceId}`, one attempt outbox row, and at most one receipt per projection. Test that the same ID with a changed answer, time, or evidence context throws.

```powershell
flutter test --no-pub test/features/learning/learning_use_cases_test.dart --plain-name "recordEvidence reuses one source identity across retry"
```

Expected: compile/test failure because `recordEvidence` and `LearningEventContextProvider` do not exist.

- [ ] **Step 2: Add the evidence-first use-case without breaking callers**

```dart
Future<AnswerRecordResult> recordEvidence({
  required String sourceEvidenceId,
  required DateTime occurredAtUtc,
  required String sessionId,
  required String wordId,
  required String promptMode,
  required bool isCorrect,
  required int? responseTimeMs,
  required int attemptNumber,
  required EvidenceContext evidenceContext,
  String? providerProvenance,
});
```

Move the shared implementation behind `recordEvidence`. Validate the supplied UTC time and stable identifier. Keep `recordAnswer` as a clearly deprecated compatibility wrapper that generates identity/time once per invocation and supplies `legacyInferred/legacy-v1`; Task 8 removes every production-screen dependency on that wrapper. An architecture test later forbids `recordAnswer` calls under `lib/screens/`.

Define an injected asynchronous `LearningEventContextProvider`. Its baseline implementation returns an explicit no-research context only for Legacy evidence. Shadow or Enforced evidence requires a nonzero consent snapshot, experiment assignment, protocol version, assignment ID, and a feature-contract identity equal to the declared `EvidenceContext`; before Task 11 provides a persisted implementation it fails closed. Widgets never construct ConsentContext, ExperimentContext, or contract identity.

- [ ] **Step 3: Make SRS result nullable**

```dart
final class AnswerRecordResult {
  const AnswerRecordResult({required this.inserted, required this.srs});
  final bool inserted;
  final SrsSnapshot? srs;
}
```

Existing independent-recall callers still receive a non-null SRS result. Denied future evidence receives null.

- [ ] **Step 4: Put evidence context in the existing event payload**

Keep frozen `EventEnvelopeV2` fields unchanged. `adaptFromCommand` must use:

```dart
eventId: 'learning-event:$sourceEvidenceId',
eventVersion: 2,
idempotencyKey: 'learning-attempt:$sourceEvidenceId:v2',
policyVersion: evidenceContext.policyVersion,
contentRevision: evidenceContext.contentRevision,
payload: <String, Object?>{
  'attemptId': sourceEvidenceId,
  'wordId': wordId,
  'promptMode': promptMode,
  'correct': isCorrect,
  'score': isCorrect ? 100 : 0,
  'attemptNumber': attemptNumber,
  'evidenceContext': evidenceContext.toJson(),
},
```

Populate the envelope's existing `consentContext` and `experimentContext` from `LearningEventContextProvider`; do not leave hard-coded zero/null research context for Shadow, Enforced, or Assessment evidence. Require envelope experiment ID/variant/assigned-at, consent version, and the provider's contract identity to agree with `EvidenceContext`; version, assignment ID, protocol, and feature-contract revision/hash remain in the complete serialized context inside the payload because the frozen envelope has no fields for them. Do not change Quest event types in this task; eligibility becomes the authoritative gate in Task 7.

- [ ] **Step 5: Run focused tests and commit**

```powershell
flutter test --no-pub test/features/learning/learning_use_cases_test.dart test/features/events/event_v1_to_v2_adapter_test.dart test/features/learning/drift_learning_repository_test.dart
git add -- lib/features/learning/domain/learning_event_context.dart lib/features/learning/application/learning_use_cases.dart lib/features/events/application/event_v1_to_v2_adapter.dart lib/features/learning/domain/learning_models.dart lib/features/learning/data/drift_learning_repository.dart lib/runtime/app_bootstrap.dart test/features/learning/learning_use_cases_test.dart test/features/events/event_v1_to_v2_adapter_test.dart test/features/learning/drift_learning_repository_test.dart
git diff --cached --check
git commit -m "refactor: reuse one learning evidence identity"
```

---

### Task 7: Enforce Evidence Eligibility at Every Projection Boundary

**Files:**
- Modify: `lib/features/learning/data/drift_learning_repository.dart`
- Modify: `lib/features/learning/data/drift_learning_projection_rebuilder.dart`
- Modify: `lib/features/learning/application/learning_side_effect_reconciler.dart`
- Modify: `lib/features/learning/data/drift_learning_event_store.dart`
- Modify: `lib/features/progress/data/drift_progress_queries.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Modify: `test/features/learning/data/drift_learning_projection_rebuilder_test.dart`
- Modify: `test/features/learning/learning_side_effect_reconciler_test.dart`
- Create: `test/features/learning/drift_learning_event_store_test.dart`
- Modify: `test/features/quest/quest_learning_integration_test.dart`
- Modify: `test/features/motivation/streak_learning_integration_test.dart`
- Modify: `test/features/progress/progress_projector_test.dart`
- Create: `test/features/learning/assessment_evidence_isolation_test.dart`

**Interfaces:**
- Consumes: `EvidenceEligibilityPolicyV1` and persisted evidence context.
- Produces: one projection router that records applied/not-applicable receipts and prevents forbidden side effects while preserving explicitly legacy-inferred replay.

- [ ] **Step 1: Write the failing assessment-isolation test**

Inject a deterministic granted `LearningEventContextProvider` whose consent snapshot, stable assignment, protocol, instrument/form/item/scoring metadata, and current feature-contract identity exactly match the test context. Assert this fixture resolves successfully before taking any projection snapshots, so the RED failure is specifically forbidden projection mutation rather than baseline-provider research validation. Then record one declared, Enforced `EvidenceClass.assessment` answer and assert:

```dart
expect(await countRows(database.answerAttempts), 1);
expect(await countRows(database.eventsV2), greaterThanOrEqualTo(1));
expect(await countRows(database.srsStates), 0);
expect(await countRows(database.pointsLedgerEntries), 0);
expect(await countRows(database.achievementUnlocks), 0);
expect(await countRows(database.questObjectiveProgress), 0);
expect(await countRows(database.streakStates), 0);
expect(await countRows(database.rewardTransactions), 0);
```

Also snapshot the practice Progress read model and assert its accuracy, weaknesses, recommendations, mastery counts, XP, level, and achievements are unchanged. Assessment session/score remains available only to the Assessment outcome reader and effort/history views. Assert a `LearningProjectionSkipped` receipt exists for each denied asynchronous projection so the durable cursor advances.

Add two cutover fixtures: (a) a pre-v13 source event whose payload has only `attemptId`, correlated to a migrated `legacyInferred/legacy-v1` attempt; and (b) one owner containing an already-applied v1 event, a pending v1 event, and a new declared event.

For every source evidence ID, assert one deterministic `LearningEvidenceDecisionSet` audit event at `learning-evidence-decisions:{sourceEvidenceId}:v1` contains exactly eleven entries—one per `LearningProjection`—with rollout mode, effective decision, candidate v1 decision, policy version, and divergence. This event is not a new score authority and cannot invoke sinks; it makes Shadow comparison and forbidden-side-effect audits reproducible without an elevenfold event-row expansion.

- [ ] **Step 2: Observe forbidden side effects before the fix**

```powershell
flutter test --no-pub test/features/learning/assessment_evidence_isolation_test.dart
```

Expected: failure because the current projection path and rebuilders apply learning/motivation effects to every answer.

- [ ] **Step 3: Gate synchronous rebuilds**

Persist attempt, event, attempt outbox, and session outcome for all valid evidence. Rebuild SRS and SRS outbox only when `masterySrs == allow`. Rebuild achievements and lifetime XP only when their decisions allow. `rebuildWord` and `rebuildAchievements` must filter stored attempts by decoded context so replay produces the same result.

Make `DriftProgressQueries` an explicit practice/read-model consumer: Assessment attempts/sessions cannot enter practice accuracy, skill, weakness, recommendation, mastery, or latest-learning calculations. Assessment outcome and effort/history are queried through their own readers; do not solve this by deleting the canonical attempt.

- [ ] **Step 4: Gate asynchronous reconciliation**

Before each sink, resolve context with this exact order:

1. If `payload.evidenceContext` exists, decode it and require its attempt ID/class to match the canonical attempt.
2. If it is absent, correlate `payload.attemptId` to `AnswerAttempts`; accept only a migrated `legacyInferred/legacy-v1/legacy` context.
3. If correlation is missing, mismatched, or non-legacy, fail closed by writing a terminal `LearningProjectionBlocked` receipt with a reason code and advance the cursor without invoking a sink.

Cut reconciliation to applied projection version 2 for every source event. Before invoking a v2 sink, look for the deterministic v1 receipt `learning-projection:{projection}:{sourceEventId}:v1`. If it exists, copy its applied/not-applicable outcome into a v2 bridge receipt tagged `bridgedFromVersion: 1`, advance the v2 cursor, and do not invoke the sink. If no v1 receipt exists, evaluate the resolved context: Deny skips; `protocolControlled` requires `engagementAllowed`; Shadow applies the compatibility decision and records the v1 candidate decision/divergence; Enforced applies v1. Quest prerequisite bridging must happen before Reward so its v2 receipt can be joined. This prevents duplicate Quest, Streak, Reward, XP, and Coin effects while allowing pending legacy events to finish exactly once.

Extend `LearningProjectionOutcome` to `applied`, `notApplicable`, and `blocked`. All three write immutable terminal receipts and advance only the matching projection cursor; only `applied` may satisfy Reward's Quest prerequisite. Blocked receipts carry a stable machine reason and never masquerade as an ordinary policy denial.

Write the decision-set audit event in the same database transaction as every new canonical attempt/event. For migrated legacy attempts, the bounded reconciler materializes the same deterministic set from the frozen `legacyInferred/legacy-v1/legacy` context before any v2 execution/bridge; it never rewrites the attempt. Synchronous consumers (session, SRS, assessment, effort, pronunciation, achievement, XP, Coins) and asynchronous reconcilers must read the same stored decision set rather than independently re-evaluating mutable configuration. A same-ID/different-decision replay fails closed.

- [ ] **Step 5: Wire one policy instance at the composition root**

```dart
const evidencePolicy = EvidenceEligibilityPolicySet();
```

Inject it and one `EvidencePolicyRolloutModeProvider` into `DriftLearningRepository`, `LearningSideEffectReconciler`, and every evidence-aware rebuilder. The production provider defaults to Legacy. Screens do not instantiate policy objects or choose enforcement directly.

Do not add an Evidence Gateway enum value or a second registry. Existing activity feature switches remain the invocation rollback boundary; new assessment/activity entry points stay absent or disabled.

- [ ] **Step 6: Run focused isolation and integration tests**

```powershell
flutter test --no-pub test/features/learning/assessment_evidence_isolation_test.dart test/features/learning/data/drift_learning_projection_rebuilder_test.dart
flutter test --no-pub test/features/learning/drift_learning_event_store_test.dart test/features/learning/learning_side_effect_reconciler_test.dart
flutter test --no-pub test/features/quest/quest_learning_integration_test.dart test/features/motivation/streak_learning_integration_test.dart
flutter test --no-pub test/features/progress/progress_projector_test.dart
```

Expected: all pass; legacy/current learning behavior remains unchanged and assessment effects are isolated.

- [ ] **Step 7: Commit the policy cutover**

```powershell
git add -- lib/features/learning/data/drift_learning_repository.dart lib/features/learning/data/drift_learning_projection_rebuilder.dart lib/features/learning/application/learning_side_effect_reconciler.dart lib/features/learning/data/drift_learning_event_store.dart lib/features/progress/data/drift_progress_queries.dart lib/runtime/app_bootstrap.dart test/features/learning/data/drift_learning_projection_rebuilder_test.dart test/features/learning/drift_learning_event_store_test.dart test/features/learning/learning_side_effect_reconciler_test.dart test/features/quest/quest_learning_integration_test.dart test/features/motivation/streak_learning_integration_test.dart test/features/progress/progress_projector_test.dart test/features/learning/assessment_evidence_isolation_test.dart
git diff --cached --check
git commit -m "feat: enforce evidence eligibility across projections"
```

---

### Task 8: Classify Current Activities and Complete Sync/Export Lifecycle

**Files:**
- Create: `lib/features/learning/application/current_activity_evidence.dart`
- Modify: `lib/screens/quiz_screen.dart`
- Modify: `lib/screens/srs_flashcards_screen.dart`
- Modify: `lib/screens/associative_reading_session_screen.dart`
- Modify: `lib/screens/ghost_shadow_duel_screen.dart`
- Modify: `lib/screens/speak_to_text_screen.dart`
- Modify: `lib/screens/shadowing_challenge_screen.dart`
- Modify: `test/screens/quiz_screen_test.dart`
- Modify: `test/screens/srs_flashcards_screen_test.dart`
- Modify: `test/screens/associative_reading_session_screen_test.dart`
- Modify: `test/screens/ghost_shadow_duel_screen_test.dart`
- Modify: `test/screens/speak_to_text_screen_voice_test.dart`
- Modify: `test/screens/shadowing_challenge_screen_test.dart`
- Modify: `lib/features/sync/domain/sync_entity.dart`
- Modify: `lib/features/sync/data/drift_sync_store.dart`
- Modify: `lib/features/sync/data/firestore_sync_gateway.dart`
- Create: `lib/config/research_runtime_config.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Modify: `firestore.rules`
- Modify: `test/features/sync/learning_event_sync_test.dart`
- Modify: `test/features/sync/sync_contract_test.dart`
- Modify: `test/features/sync/firestore_sync_gateway_test.dart`
- Create: `test/config/research_runtime_config_test.dart`
- Modify: `test/runtime/app_bootstrap_test.dart`
- Modify: `test/security/firestore-rules.test.cjs`
- Modify: `lib/features/export/data/drift_export_reader.dart`
- Modify: `lib/features/export/application/export_use_cases.dart`
- Modify: `test/features/export/export_use_cases_test.dart`
- Verify: `test/scenarios/complete_owner_export_delete_test.dart`

**Interfaces:**
- Consumes: evidence-aware record API and schema v13.
- Produces: explicit current-mode classification, attempt sync payload v2, research export schema v2, and unchanged deletion authority.

- [ ] **Step 1: Add failing adapter/call-site tests**

Require these default declarations:

| Current mode | Evidence class |
|---|---|
| Meaning multiple choice | `recognition` |
| SRS remembered/not-remembered recall | `independentRecall` |
| Typed recall / associative recall | `independentRecall` |
| Ghost Duel | `recreational` unless a protocol explicitly overrides it |
| Speak-to-text / shadowing | `pronunciation` |
| Reading exposure without recall | `exposure` |

Each retry test must reuse the same `sourceEvidenceId`, `occurredAtUtc`, and context after a simulated local failure.

```powershell
flutter test --no-pub test/screens/quiz_screen_test.dart --plain-name "retry reuses pending evidence identity"
```

Expected: failure because the screen still calls the compatibility wrapper and regenerates evidence identity.

- [ ] **Step 2: Update call sites through adapters, not policy duplication**

Create focused factories in `current_activity_evidence.dart`; screens choose only an activity/input declaration and receive a validated `EvidenceContext`. Migrate all six screens from the compatibility `recordAnswer` wrapper to `recordEvidence`. The injected rollout/research-context providers—not widgets—supply policy mode, consent/assignment metadata, and `engagementAllowed`. Production defaults to Legacy, which emits the compatibility context while retaining the typed semantic declaration. Shadow emits declared context but keeps compatibility side effects and records comparison; Enforced emits declared context and applies v1. Each screen stores the pending source ID, UTC occurrence time, and context until local commit succeeds. Do not paste policy decisions into widgets and do not generate a new identity on retry. This task does not promote production beyond Legacy.

- [ ] **Step 3: Verify and commit explicit activity classification**

```powershell
flutter test --no-pub test/screens/quiz_screen_test.dart test/screens/srs_flashcards_screen_test.dart test/screens/associative_reading_session_screen_test.dart test/screens/ghost_shadow_duel_screen_test.dart test/screens/speak_to_text_screen_voice_test.dart test/screens/shadowing_challenge_screen_test.dart
git add -- lib/features/learning/application/current_activity_evidence.dart lib/screens/quiz_screen.dart lib/screens/srs_flashcards_screen.dart lib/screens/associative_reading_session_screen.dart lib/screens/ghost_shadow_duel_screen.dart lib/screens/speak_to_text_screen.dart lib/screens/shadowing_challenge_screen.dart test/screens/quiz_screen_test.dart test/screens/srs_flashcards_screen_test.dart test/screens/associative_reading_session_screen_test.dart test/screens/ghost_shadow_duel_screen_test.dart test/screens/speak_to_text_screen_voice_test.dart test/screens/shadowing_challenge_screen_test.dart
git diff --cached --check
git commit -m "feat: classify current learning evidence"
```

- [ ] **Step 4: Write failing sync v2 tests and rules tests**

Attempt payload v2 adds:

```json
{
  "evidenceClass": "independentRecall",
  "evidenceContext": {
    "schemaVersion": 1,
    "evidenceClass": "independentRecall",
    "skillId": "meaning-recall",
    "hintLevel": 0,
    "policyVersion": "learning-evidence-v1",
    "contentRevision": "built-in-v1",
    "featureContractRevision": "1.0.0",
    "featureContractHash": "<lowercase 64-character catalog semantic SHA-256>",
    "classificationSource": "declared",
    "rolloutMode": "shadow",
    "protocolId": "evidence-pilot",
    "protocolVersion": "1.0.0",
    "experimentId": "evidence-eligibility",
    "experimentVersion": 1,
    "assignmentId": "assignment-1",
    "cohort": "shadow",
    "researchConsentVersion": 1,
    "engagementAllowed": true
  }
}
```

New clients read AnswerAttempt payload v1 as `legacyInferred`; new clients emit AnswerAttempt v2 only after rules accept both exact schemas. Rules reject unknown keys, invalid enum values, mismatched top-level/nested classes, or oversized JSON fields.

- [ ] **Step 5: Implement sync v2 and exact rules validation**

Replace the single global payload-version assumption with an exhaustive per-`SyncCollection` policy. `answerAttempts` can read versions 1/2; every existing non-attempt collection remains version 1. An injected `SyncPayloadRollout` selects AnswerAttempt writes and defaults to v1 until the updated rules are actually deployed; internal tests exercise v2. Later `experimentAssignments` and `assessmentRuns` start at version 1. Tests must assert every collection's supported versions and production-default write version so adding one cannot silently bump all others. Preserve immutable comparison of the complete evidence context, including feature-contract revision/hash. Deploy rules before changing the AnswerAttempt write rollout on research devices.

Apply that policy inside `FirestoreSyncGateway`, not only the Drift codec: reject an unsupported mutation version before opening a transaction, decode entity versions against the requested collection, and validate acknowledgement `entityType`/schema version against that collection. Add gateway tests proving AnswerAttempt v1/v2 acceptance, v2 rejection for every legacy-v1-only collection, and no Firestore write on preflight rejection. Task 11 and Task 12 extend the same exhaustive test when their collections are introduced.

Add a separate, non-secret `ResearchRuntimeConfig` for evidence rollout, AnswerAttempt write version, and Firestore-rules revision. Do not put this safety configuration through the existing tolerant `_loadConfig()` path, which intentionally converts Voice/AI endpoint errors to `null`. Inject a `ResearchRuntimeConfigLoader` into `AppBootstrap`; the general constructor defaults it to an explicit Legacy/v1 safe value so existing tests and non-production composition remain source compatible, while `production()` explicitly loads `LEXIQUEST_EVIDENCE_ROLLOUT`, `LEXIQUEST_ANSWER_ATTEMPT_WRITE_VERSION`, and `LEXIQUEST_FIRESTORE_RULES_REVISION` before composing repositories. Any production parse/invariant error propagates from `initialize()`. Define one reviewed constant (for example `answerAttemptV2RulesRevision = 'answer-attempt-v2-r1'`) beside the sync policy. Shadow or Enforced is invalid unless AnswerAttempt write version is 2 and the configured rules revision equals that reviewed constant. Legacy defaults to AnswerAttempt v1 and the legacy rules sentinel; malformed values or an unsafe combination fail startup closed. Never silently down-convert declared evidence to payload v1. Unit tests cover environment/value parsing, production defaults, every invalid combination, propagation through bootstrap, and a valid explicitly configured research combination.

- [ ] **Step 6: Add research export v2 fields**

Export `evidenceClass`, `skillId`, `hintLevel`, `policyVersion`, `contentRevision`, `featureContractRevision`, `featureContractHash`, `classificationSource`, `rolloutMode`, `protocolId`, `protocolVersion`, `experimentId`, `experimentVersion`, `assignmentId`, `cohort`, `researchConsentVersion`, `instrumentId`, `instrumentVersion`, `formId`, `formVersion`, `assessmentItemId`, `assessmentResponseCode`, and `scoringRuleVersion`. Do not export raw provider secrets. Withdrawal/delete continue using the existing `answer_attempts` lifecycle row; no new table is added in this task.

- [ ] **Step 7: Verify lifecycle and commit in two reviewable commits**

```powershell
flutter test --no-pub test/features/sync/learning_event_sync_test.dart test/features/sync/sync_contract_test.dart test/features/sync/firestore_sync_gateway_test.dart
flutter test --no-pub test/config/research_runtime_config_test.dart test/runtime/app_bootstrap_test.dart
npm run test:rules
git add -- lib/features/sync/domain/sync_entity.dart lib/features/sync/data/drift_sync_store.dart lib/features/sync/data/firestore_sync_gateway.dart lib/config/research_runtime_config.dart lib/runtime/app_bootstrap.dart firestore.rules test/features/sync/learning_event_sync_test.dart test/features/sync/sync_contract_test.dart test/features/sync/firestore_sync_gateway_test.dart test/config/research_runtime_config_test.dart test/runtime/app_bootstrap_test.dart test/security/firestore-rules.test.cjs
git diff --cached --check
git commit -m "feat: sync evidence context with payload v2"

flutter test --no-pub test/features/export/export_use_cases_test.dart test/scenarios/complete_owner_export_delete_test.dart
git add -- lib/features/export/data/drift_export_reader.dart lib/features/export/application/export_use_cases.dart test/features/export/export_use_cases_test.dart
git diff --cached --check
git commit -m "feat: export versioned learning evidence"
```

---

### Task 9: Separate Lifetime XP from Spendable Coins Without a Schema Bump

**Files:**
- Create: `lib/features/rewards/domain/economy_transaction_policy.dart`
- Create: `lib/features/rewards/data/drift_economy_cutover.dart`
- Modify: `lib/features/rewards/domain/reward_models.dart`
- Modify: `lib/features/rewards/data/drift_reward_repository.dart`
- Modify: `lib/features/rewards/data/drift_reward_projection_rebuilder.dart`
- Modify: `lib/features/rewards/application/reward_use_cases.dart`
- Modify: `lib/features/learning/application/learning_side_effect_reconciler.dart`
- Modify: `lib/features/learning/data/drift_learning_event_store.dart`
- Modify: `lib/features/progress/data/drift_progress_queries.dart`
- Modify: `lib/features/sync/data/drift_sync_store.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Modify: `firestore.rules`
- Modify: `test/features/progress/progress_projector_test.dart`
- Modify: `test/features/rewards/reward_use_cases_test.dart`
- Modify: `test/features/rewards/data/drift_reward_projection_rebuilder_test.dart`
- Modify: `test/features/learning/learning_side_effect_reconciler_test.dart`
- Modify: `test/features/learning/drift_learning_event_store_test.dart`
- Modify: `test/features/sync/reward_transaction_sync_test.dart`
- Modify: `test/runtime/app_bootstrap_test.dart`
- Modify: `test/security/firestore-rules.test.cjs`
- Modify: `test/scenarios/production_learning_restart_test.dart`

**Interfaces:**
- Consumes: existing `PointsLedgerEntries` and `RewardTransactions`.
- Produces: Points ledger as lifetime XP only; RewardTransactions as Coin grants/spend/equip evidence; idempotent legacy cutover.

- [ ] **Step 1: Write the failing invariant test**

Grant XP, buy a cosmetic, reload progress, and assert:

```dart
expect(afterPurchase.totalXp, beforePurchase.totalXp);
expect(afterPurchase.gameLevel, beforePurchase.gameLevel);
expect(afterPurchase.coinBalance, beforePurchase.coinBalance - item.price);
```

```powershell
flutter test --no-pub test/features/progress/progress_projector_test.dart --plain-name "cosmetic purchase never changes lifetime xp or level"
```

Expected: failure because the current purchase projection inserts a negative Points row included in `totalXp`.

- [ ] **Step 2: Add typed economy transactions**

```dart
enum EconomyTransactionType { legacyEarningBackfill, coinGrant, purchase, equip }

Future<void> grantCoins({
  required String ownerId,
  required String idempotencyKey,
  required int amount,
  required String sourceEventId,
  required DateTime occurredAtUtc,
});
```

Legacy earning backfills and Coin grants are positive with no item and use `catalogVersion == 0`; purchases are negative and require a current-catalog item; equip is zero and requires an owned item. Firestore and local sync validators accept exactly these four shapes and reject every other type/amount/item/catalog combination.

Add a versioned `EconomyAwardPolicyV1` that preserves the current earning trajectory by issuing separate, idempotent XP and Coin grants from each eligible legacy/current award source using the same source evidence ID and distinct ledger keys. The initial amounts may be equal for compatibility, but they are stored and reconstructed independently. Assessment, denied evidence, and blocked projections grant neither.

- [ ] **Step 3: Implement idempotent cutover**

`DriftEconomyCutover.ensureSeparated(ownerId)` atomically scans positive legacy earning rows and writes one deterministic `legacyEarningBackfill` transaction per source Points row, retaining existing purchase/equip transactions and every legacy `rewardPurchase` point row as immutable audit evidence. IDs and idempotency keys derive from the Points row ID. Exactly one path may represent each earning: if a same-source Coin transaction already exists, skip; if the Points row correlates to an Event V2 payload that the evidence-aware Coin projection owns, leave it pending for that projection; otherwise backfill it. Thus a late v1/cloud row is backfilled on the next guard pass, while a new v2 earning cannot be both backfilled and granted. Existing accepted purchase transactions are subtracted exactly once. A same-ID/different-payload collision fails closed.

Call the cutover before every public reward read/write through one serialized repository guard. Use a private already-separated load method inside purchase/equip transactions so nested calls cannot run or double-count the cutover.

- [ ] **Step 4: Remove purchases from XP projection**

`DriftProgressQueries.totalXp` sums positive lifetime-XP entries only and explicitly excludes `rewardPurchase`; all negative/unknown types are excluded from the XP total and surfaced by a diagnostic assertion in tests. `DriftRewardProjectionRebuilder` derives Coin balance and ownership exclusively from accepted `RewardTransactions` and neither inserts nor deletes point rows. Add reconstruction tests proving `legacyEarningBackfill + coinGrant + accepted purchases` equals the account balance after restart, an eligible post-cutover award increases XP and Coins independently, a purchase changes Coins only, a late legacy earning is backfilled exactly once, legacy purchase rows remain queryable, and cloud replay/rollback readers cannot reintroduce those rows into XP.

Keep user-facing purchase/equip history counts separate from migration/grant ledger counts so the cutover cannot inflate a UI metric merely by creating backfill evidence.

Add an independent `coins` reconciliation sink and cursor; it must not depend on Quest success. If a source earning already has `legacyEarningBackfill`, the sink records not-applicable with reason `capturedByLegacyBackfill`. Otherwise an eligible new correct-answer event writes one `coinGrant`; incorrect/denied/shadow-effective-denied evidence writes a terminal not-applicable receipt. Quest completion uses one atomic repository method that grants Quest XP and the paired Coin amount with distinct idempotency keys. App bootstrap wires both through `EconomyAwardPolicyV1`.

- [ ] **Step 5: Run focused tests and commit**

```powershell
flutter test --no-pub test/features/progress/progress_projector_test.dart test/features/rewards/reward_use_cases_test.dart test/features/rewards/data/drift_reward_projection_rebuilder_test.dart test/features/sync/reward_transaction_sync_test.dart
flutter test --no-pub test/features/learning/drift_learning_event_store_test.dart test/features/learning/learning_side_effect_reconciler_test.dart test/runtime/app_bootstrap_test.dart
flutter test --no-pub test/scenarios/production_learning_restart_test.dart --plain-name "retrying the same durable answer keeps XP quest and streak idempotent"
npm run test:rules
git add -- lib/features/rewards/domain/economy_transaction_policy.dart lib/features/rewards/data/drift_economy_cutover.dart lib/features/rewards/domain/reward_models.dart lib/features/rewards/data/drift_reward_repository.dart lib/features/rewards/data/drift_reward_projection_rebuilder.dart lib/features/rewards/application/reward_use_cases.dart lib/features/learning/application/learning_side_effect_reconciler.dart lib/features/learning/data/drift_learning_event_store.dart lib/features/progress/data/drift_progress_queries.dart lib/features/sync/data/drift_sync_store.dart lib/runtime/app_bootstrap.dart firestore.rules test/features/progress/progress_projector_test.dart test/features/rewards/reward_use_cases_test.dart test/features/rewards/data/drift_reward_projection_rebuilder_test.dart test/features/learning/drift_learning_event_store_test.dart test/features/learning/learning_side_effect_reconciler_test.dart test/features/sync/reward_transaction_sync_test.dart test/runtime/app_bootstrap_test.dart test/security/firestore-rules.test.cjs test/scenarios/production_learning_restart_test.dart
git diff --cached --check
git commit -m "refactor: separate lifetime xp from spendable coins"
```

After deployment, rollback disables Coin earning/purchase invocation but retains the separated readers; never return purchases to XP.

---

### Task 10: Make StreakStates the Only Operational Streak Authority

**Files:**
- Modify: `lib/features/progress/data/drift_progress_queries.dart`
- Modify: `test/features/progress/progress_projector_test.dart`
- Create: `test/architecture/streak_authority_test.dart`
- Modify: `docs/v2-implementation/authority_matrix.md`
- Modify: `docs/v2-implementation/service_quarantine_registry.md`

**Interfaces:**
- Consumes: `StreakUseCases`, `DriftStreakRepository`, `streak_states`, and `learning_day_log`.
- Produces: Progress as a streak read model; no second date-based streak calculation.

- [ ] **Step 1: Write failing authority tests**

Insert seven dated attempts and a `streak_states.currentStreakDays` value of 3. Expect Progress to report 3. With no row, expect zero. Add an architecture test that allows operational streak writes only in `drift_streak_repository.dart`; `drift_owner_upgrade_repository.dart` is the explicit lifecycle-migration exception.

```powershell
flutter test --no-pub test/features/progress/progress_projector_test.dart --plain-name "progress reads the dedicated streak authority"
flutter test --no-pub test/architecture/streak_authority_test.dart
```

Expected: first test reports recomputed 7 instead of authoritative 3; second fails because the architecture test/file is not implemented.

- [ ] **Step 2: Replace recomputation with an authority read**

Query `streakStates` by owner, use `currentStreakDays`, and delete `_streakDays()`. Do not infer a streak from attempts when a row is absent.

- [ ] **Step 3: Preserve quarantine declarations**

Keep `streak_and_daily_quest_service.dart` and `local_user_progress_store.dart` out of production composition and document them as non-authoritative.

- [ ] **Step 4: Verify and commit**

```powershell
flutter test --no-pub test/features/progress/progress_projector_test.dart test/features/motivation/streak_use_cases_test.dart test/features/motivation/streak_learning_integration_test.dart test/architecture/streak_authority_test.dart
git add -- lib/features/progress/data/drift_progress_queries.dart test/features/progress/progress_projector_test.dart test/architecture/streak_authority_test.dart docs/v2-implementation/authority_matrix.md docs/v2-implementation/service_quarantine_registry.md
git diff --cached --check
git commit -m "refactor: make streak state the single authority"
```

---

### Task 11: Persist Stable Experiment Assignment and Real Consent Snapshots in Schema v14

**Files:**
- Create: `lib/data/local/tables/research_tables.dart`
- Modify: `lib/data/local/app_database.dart`
- Regenerate: `lib/data/local/app_database.g.dart`
- Create: `lib/features/research/domain/experiment_assignment.dart`
- Create: `lib/features/research/data/drift_experiment_assignment_repository.dart`
- Create: `lib/features/research/application/experiment_assignment_use_cases.dart`
- Create: `lib/features/research/application/assigned_learning_event_context_provider.dart`
- Modify: `lib/runtime/registries/experiment_registry.dart`
- Modify: `lib/runtime/registries/consent_registry.dart`
- Create: `lib/runtime/registries/drift_consent_registry.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Modify: `lib/runtime/app_dependencies.dart`
- Modify: `lib/features/sync/domain/sync_entity.dart`
- Modify: `lib/features/sync/data/drift_sync_store.dart`
- Modify: `lib/features/sync/data/firestore_sync_gateway.dart`
- Modify: `firestore.rules`
- Modify: `lib/features/identity/domain/owner_lifecycle_manifest.dart`
- Modify: `lib/features/identity/data/drift_owner_upgrade_repository.dart`
- Modify: `lib/features/export/application/owner_lifecycle_archive.dart`
- Modify: `lib/features/export/data/drift_export_reader.dart`
- Modify: `lib/features/export/application/export_use_cases.dart`
- Modify: `test/features/identity/drift_owner_upgrade_repository_test.dart`
- Modify: `test/features/export/export_use_cases_test.dart`
- Modify: `test/runtime/app_bootstrap_test.dart`
- Modify: `test/scenarios/guest_upgrade_restart_test.dart`
- Modify: `test/scenarios/complete_owner_export_delete_test.dart`
- Modify: `docs/database/schema_ledger.md`
- Create: `test/database/migration_v13_to_v14_test.dart`
- Create: `test/features/research/drift_experiment_assignment_repository_test.dart`
- Create: `test/runtime/persisted_registries_test.dart`
- Modify: `test/runtime/registries_test.dart`
- Create: `test/features/sync/experiment_assignment_sync_test.dart`
- Modify: `test/features/sync/firestore_sync_gateway_test.dart`
- Modify: `test/security/firestore-rules.test.cjs`

**Interfaces:**
- Consumes: existing research consent rows and independent runtime registries.
- Produces: immutable per-owner assignment with conflict detection and a Drift-backed consent snapshot. No feature flag can create or mutate assignment.

- [ ] **Step 1: Write failing migration and persistence tests**

Schema v14 table contract:

```text
experiment_assignments(
  id,
  owner_id,
  experiment_id,
  experiment_version,
  cohort,
  protocol_version,
  assigned_at_utc_ms,
  unique(owner_id, experiment_id, experiment_version)
)
```

Test the targeted v13→v14 transition: `experiment_assignments` is the one table introduced at v14 and all 31 v13 tables/data remain intact. Because this fixture upgrades through `AppDatabase.currentSchemaVersion`, its final inventory assertion must use the named current-version expectation rather than freeze `32` after Task 12 advances the application to v15. Also test reopen persistence, identical replay, conflicting cohort rejection, guest upgrade, export, withdrawal/delete, and kill-switch independence.

Guest upgrade may merge an equivalent assignment for the same experiment/version, but a different cohort or protocol aborts the owner-upgrade transaction with a typed research conflict; it never chooses a winner.

```powershell
flutter test --no-pub test/database/migration_v13_to_v14_test.dart
flutter test --no-pub test/features/research/drift_experiment_assignment_repository_test.dart
```

Expected: compile/test failure because the table and persisted repository do not exist.

- [ ] **Step 2: Add typed repositories and registry APIs**

```dart
Future<ExperimentAssignment> getAssignment({
  required String experimentId,
  required int experimentVersion,
  required String ownerId,
});

Future<ExperimentAssignment> assignIfAbsent({
  required String ownerId,
  required String experimentId,
  required int experimentVersion,
  required String cohort,
  required String protocolVersion,
  required DateTime assignedAtUtc,
});

Future<ConsentSnapshot> snapshot({
  required ConsentPurpose purpose,
  required String ownerId,
  required int consentVersion,
});
```

`ConsentSnapshot` carries state, consent version, decision UTC, and withdrawal UTC. For `researchDataUpload`, the Drift adapter reads the explicitly requested protocol consent version: accepted with no withdrawal is Granted; declined/withdrawn is Denied; missing or malformed is Unknown. `aiProviderDataSharing` and `personalDataExport` remain Unknown until their own authorities exist. Conflicting assignment throws `ExperimentAssignmentConflict`; unknown/malformed/withdrawn consent never becomes granted.

Move the existing runtime `ExperimentAssignment` value object into `lib/features/research/domain/experiment_assignment.dart`; `experiment_registry.dart` imports and re-exports that one type. Do not leave a second class with the same responsibility. Extend the registry method with experiment version and make the persisted lookup asynchronous. The no-op implementation remains available only for explicitly injected tests and always returns an unassigned result.

- [ ] **Step 3: Add schema v14 and complete lifecycle coverage**

Set `AppDatabase.currentSchemaVersion = 14`. Add the table to `AppDatabase`, `_createMissingTables`, `ownerLifecycleManifest`, guest upgrade, archive/export, deletion order, and exact-set lifecycle tests. Update schema ledger. Regenerate Drift code. Migration tests from every older fixture continue to assert the named current-version constant while verifying their own historical contract.

- [ ] **Step 4: Add immutable assignment sync before exposing the registry**

Add `SyncCollection.experimentAssignments` at payload version 1. Assignment creation writes one outbox operation. Pull accepts an absent row or a byte-equivalent replay; any different cohort/protocol/version for the same owner/experiment/version records a conflict and keeps intervention fail-closed. Extend `FirestoreSyncGateway` and its exhaustive version-policy tests so this collection is encoded/decoded generically at v1 and no collection inherits AnswerAttempt v2 support. Firestore rules require exact keys, immutable create-only documents, bounded IDs/cohort, positive versions, and owner-path equality. Test local retry, push/pull/reopen, remote equivalent replay, remote conflict, and unchanged v1 versions for every existing collection.

Research-collection sync has its own rollout switch, defaults Off, and requires the matching deployed-rules revision before claiming an assignment operation. Implementing rules locally does not enable uploads.

Consent withdrawal immediately blocks new assignment, research sync claims, and intervention use. It does not silently erase local audit data: assignment rows remain available for participant export until explicit owner deletion or a separately approved retention cleanup; owner deletion removes local rows and queued operations. Encode and test that lifecycle policy in the manifest/profile.

- [ ] **Step 5: Replace production no-op registries at bootstrap**

Construct Drift-backed registries after active owner/database composition. Keep no-op registries only for tests that explicitly inject them. A feature visibility override must not call `assignIfAbsent`.

Back `EvidencePolicyRolloutModeProvider` with the persisted assignment plus a versioned protocol-to-mode mapping. Unassigned, conflicting, malformed, or consent-withdrawn owners resolve to Legacy for ordinary activities and cannot start Assessment. Feature visibility never creates or changes the assignment. Tests must prove the mode survives restart and is independent from kill switches.

- [ ] **Step 6: Verify and commit**

```powershell
dart run build_runner build --delete-conflicting-outputs
flutter test --no-pub test/database/migration_v13_to_v14_test.dart test/features/research/drift_experiment_assignment_repository_test.dart
flutter test --no-pub test/features/sync/experiment_assignment_sync_test.dart test/features/sync/firestore_sync_gateway_test.dart test/runtime/persisted_registries_test.dart test/runtime/registries_test.dart test/runtime/app_bootstrap_test.dart
flutter test --no-pub test/features/identity/drift_owner_upgrade_repository_test.dart test/features/export/export_use_cases_test.dart test/scenarios/guest_upgrade_restart_test.dart test/scenarios/complete_owner_export_delete_test.dart
npm run test:rules
git add -- lib/data/local/tables/research_tables.dart lib/data/local/app_database.dart lib/data/local/app_database.g.dart lib/features/research/domain/experiment_assignment.dart lib/features/research/data/drift_experiment_assignment_repository.dart lib/features/research/application/experiment_assignment_use_cases.dart lib/features/research/application/assigned_learning_event_context_provider.dart lib/runtime/registries/experiment_registry.dart lib/runtime/registries/consent_registry.dart lib/runtime/registries/drift_consent_registry.dart lib/runtime/app_bootstrap.dart lib/runtime/app_dependencies.dart lib/features/sync/domain/sync_entity.dart lib/features/sync/data/drift_sync_store.dart lib/features/sync/data/firestore_sync_gateway.dart firestore.rules lib/features/identity/domain/owner_lifecycle_manifest.dart lib/features/identity/data/drift_owner_upgrade_repository.dart lib/features/export/application/owner_lifecycle_archive.dart lib/features/export/data/drift_export_reader.dart lib/features/export/application/export_use_cases.dart test/database/migration_v13_to_v14_test.dart test/features/research/drift_experiment_assignment_repository_test.dart test/features/sync/experiment_assignment_sync_test.dart test/features/sync/firestore_sync_gateway_test.dart test/runtime/persisted_registries_test.dart test/runtime/registries_test.dart test/runtime/app_bootstrap_test.dart test/security/firestore-rules.test.cjs test/features/identity/drift_owner_upgrade_repository_test.dart test/features/export/export_use_cases_test.dart test/scenarios/guest_upgrade_restart_test.dart test/scenarios/complete_owner_export_delete_test.dart docs/database/schema_ledger.md
git diff --cached --check
git commit -m "feat: persist research assignment in schema v14"
```

Rollback keeps v14 readable, leaves participants assigned, and disables intervention invocation. It never deletes assignments or moves cohorts.

---

### Task 12: Add Isolated Pre/Post Assessment Runs in Schema v15

**Files:**
- Modify: `lib/data/local/tables/research_tables.dart`
- Modify: `lib/data/local/app_database.dart`
- Regenerate: `lib/data/local/app_database.g.dart`
- Create: `lib/features/assessment/domain/assessment_models.dart`
- Create: `lib/features/assessment/domain/assessment_repository.dart`
- Create: `lib/features/assessment/domain/assessment_instrument_catalog.dart`
- Create: `lib/features/assessment/data/drift_assessment_repository.dart`
- Create: `lib/features/assessment/application/assessment_use_cases.dart`
- Create: `lib/features/assessment/application/assessment_comparison.dart`
- Modify: `lib/features/identity/domain/owner_lifecycle_manifest.dart`
- Modify: `lib/features/identity/data/drift_owner_upgrade_repository.dart`
- Modify: `lib/features/export/application/owner_lifecycle_archive.dart`
- Modify: `lib/features/export/data/drift_export_reader.dart`
- Modify: `lib/features/export/application/export_use_cases.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Modify: `lib/runtime/app_dependencies.dart`
- Modify: `lib/features/sync/domain/sync_entity.dart`
- Modify: `lib/features/sync/data/drift_sync_store.dart`
- Modify: `lib/features/sync/data/firestore_sync_gateway.dart`
- Modify: `firestore.rules`
- Create: `test/database/migration_v14_to_v15_test.dart`
- Modify: `test/database/migration_v13_to_v14_test.dart`
- Create: `test/features/assessment/drift_assessment_repository_test.dart`
- Create: `test/features/assessment/assessment_use_cases_test.dart`
- Create: `test/features/assessment/assessment_isolation_test.dart`
- Create: `test/features/assessment/assessment_comparison_test.dart`
- Create: `test/features/sync/assessment_run_sync_test.dart`
- Modify: `test/features/sync/firestore_sync_gateway_test.dart`
- Modify: `test/security/firestore-rules.test.cjs`
- Modify: `test/features/identity/drift_owner_upgrade_repository_test.dart`
- Modify: `test/features/export/export_use_cases_test.dart`
- Modify: `test/runtime/app_bootstrap_test.dart`
- Modify: `test/scenarios/guest_upgrade_restart_test.dart`
- Modify: `test/scenarios/complete_owner_export_delete_test.dart`
- Modify: `docs/database/schema_ledger.md`

**Interfaces:**
- Consumes: persisted assignment/consent, Evidence Gateway, and contract revision/hash.
- Produces: version-pinned assessment runs linked to the existing `LearningSession` and existing canonical attempts. No assessment-attempt table and no UI/navigation entry.

- [ ] **Step 1: Write failing schema v15 and isolation tests**

`assessment_runs` pins:

```text
id, owner_id, learning_session_id, study_cycle_id, phase, state,
protocol_id, protocol_version, experiment_id, experiment_version,
assignment_id, cohort, consent_version, consent_decided_at_utc_ms,
instrument_id, instrument_version, form_id, form_version,
instrument_checksum_sha256, form_checksum_sha256,
app_version, build_id, database_schema_version,
content_revision, evidence_policy_version,
feature_contract_revision, feature_contract_hash,
started_at_utc_ms, completed_at_utc_ms, abandoned_at_utc_ms,
foreign key(owner_id), foreign key(learning_session_id),
foreign key(assignment_id), unique(learning_session_id),
unique(owner_id, study_cycle_id, phase)
```

Snapshot SRS, points, rewards, Quest, Streak, and achievements before and after an assessment response; assert byte-for-byte equality while one canonical attempt and one correlated event are stored.

Guest upgrade may coalesce an equivalent run replay, but conflicting metadata for the same owner/study-cycle/phase aborts atomically; it never overwrites a research run.

```powershell
flutter test --no-pub test/database/migration_v14_to_v15_test.dart
flutter test --no-pub test/features/assessment/assessment_isolation_test.dart
```

Expected: compile/test failure because AssessmentRun persistence/application types do not exist.

- [ ] **Step 2: Add typed assessment contracts**

```dart
enum AssessmentPhase { pre, post }
enum AssessmentRunState { active, completed, abandoned }

Future<AssessmentRun> start(AssessmentStartCommand command);
Future<AssessmentResponseResult> recordResponse({
  required String runId,
  required String sourceEvidenceId,
  required String itemId,
  required Object submittedResponse,
  required int responseTimeMs,
  required DateTime occurredAtUtc,
});
Future<AssessmentRun> complete(String runId);
Future<AssessmentComparisonResult> compare(String studyCycleId);
```

`recordResponse` loads the run's pinned instrument/form from `AssessmentInstrumentCatalog`, validates the item, reduces the submitted value to a bounded catalog-owned response code, derives `wordId`, `promptMode`, correctness, and scoring-rule version inside the application layer, constructs declared Enforced `EvidenceClass.assessment` with the pinned IDs/versions, item ID, response code, scoring version, and the run's exact feature-contract revision/hash, then calls the shared learning application port using the run's consent/assignment context and research privacy classification. Reject a response if its constructed evidence identity differs from the run or is no longer in the supported identity registry. The caller cannot supply its own correctness result. Instrument v1 accepts only controlled response codes; arbitrary free text is rejected rather than persisted. It never imports Drift tables directly and does not persist an unbounded raw response.

- [ ] **Step 3: Enforce fail-closed start and immutable completion**

Start requires Enforced evidence rollout, granted consent, an existing stable assignment for the exact experiment version, and an AssessmentInstrumentCatalog entry whose source/review state is Approved and whose instrument/form SHA-256 values match the packaged content. It pins app/build/schema, contract, protocol/assignment, consent, content, policy, instrument/form/scoring versions and both checksums. Same run ID plus identical metadata is idempotent; changed metadata conflicts. Completed/abandoned runs reject later responses. Because production rollout defaults to Legacy and the dependency is nullable/off-only, no assessment run can start in the final handoff state.

- [ ] **Step 4: Enforce compatible comparisons**

Define sealed `AssessmentComparisonResult` variants for Ready, MissingPair, and IncompatibleMetadata. Compare only pre/post runs with the same study cycle, protocol, instrument, form, instrument/form checksums, content revision, scoring rule, and evidence policy. Return the typed non-ready variant for missing/mismatched runs; do not merge them and do not produce one combined Outcome/Learning/Effort/Engagement score.

- [ ] **Step 5: Add schema/lifecycle and keep invocation off**

Set `AppDatabase.currentSchemaVersion = 15`, migrate forward, assert the targeted v14→v15 transition adds only `assessment_runs` (32→33), and update `migration_v13_to_v14_test.dart` so its full-upgrade inventory expects the named current v15 inventory of 33 while retaining the assertion that `experiment_assignments` is the sole v14 addition. Add exact lifecycle coverage and expose a nullable/off-only application dependency. Assessment responses reuse `AnswerAttempts`; do not create an assessment-response table. Do not add a screen, navigation entry, or enabled runtime feature in this task.

- [ ] **Step 6: Add version-1 assessment-run sync**

Add `SyncCollection.assessmentRuns` at payload version 1. Start writes one create outbox row; complete/abandon writes an update. Immutable pinned metadata can never change. The only accepted state transitions are Active→Completed and Active→Abandoned; terminal states cannot reopen. Completed requires only `completedAtUtc`; Abandoned requires only `abandonedAtUtc`; Active has neither. Pull accepts identical replay, rejects incompatible metadata/state transitions into a durable conflict, and never creates SRS/motivation effects. Extend `FirestoreSyncGateway` and its exhaustive version-policy tests so this collection is encoded/decoded generically at v1 and AnswerAttempt remains the only collection allowed to read v2. Firestore rules enforce exact keys, owner-path equality, bounded pinned identifiers, and the same transition graph. Test push/pull/reopen, offline completion replay, conflict, deletion/withdrawal, and unchanged versions for all other collections.

Assessment-run sync uses the same research-collection rollout and remains Off in production handoff. A rules-revision mismatch or missing consent leaves the outbox row pending without repeated claim attempts.

Consent withdrawal immediately prevents new runs/responses and blocks unsent assessment-run/attempt research uploads. Existing local runs and attempts stay exportable to the participant until explicit owner deletion or approved retention cleanup; deletion removes them in foreign-key-safe order. No automatic purge is introduced without a protocol-specific retention rule.

- [ ] **Step 7: Verify and commit**

```powershell
dart run build_runner build --delete-conflicting-outputs
flutter test --no-pub test/database/migration_v13_to_v14_test.dart test/database/migration_v14_to_v15_test.dart test/features/assessment/drift_assessment_repository_test.dart test/features/assessment/assessment_use_cases_test.dart test/runtime/app_bootstrap_test.dart
flutter test --no-pub test/features/assessment/assessment_isolation_test.dart test/features/assessment/assessment_comparison_test.dart test/features/sync/assessment_run_sync_test.dart test/features/sync/firestore_sync_gateway_test.dart
flutter test --no-pub test/features/identity/drift_owner_upgrade_repository_test.dart test/features/export/export_use_cases_test.dart test/scenarios/guest_upgrade_restart_test.dart test/scenarios/complete_owner_export_delete_test.dart
npm run test:rules
git add -- lib/data/local/tables/research_tables.dart lib/data/local/app_database.dart lib/data/local/app_database.g.dart lib/features/assessment/domain/assessment_models.dart lib/features/assessment/domain/assessment_repository.dart lib/features/assessment/domain/assessment_instrument_catalog.dart lib/features/assessment/data/drift_assessment_repository.dart lib/features/assessment/application/assessment_use_cases.dart lib/features/assessment/application/assessment_comparison.dart lib/features/identity/domain/owner_lifecycle_manifest.dart lib/features/identity/data/drift_owner_upgrade_repository.dart lib/features/export/application/owner_lifecycle_archive.dart lib/features/export/data/drift_export_reader.dart lib/features/export/application/export_use_cases.dart lib/runtime/app_bootstrap.dart lib/runtime/app_dependencies.dart lib/features/sync/domain/sync_entity.dart lib/features/sync/data/drift_sync_store.dart lib/features/sync/data/firestore_sync_gateway.dart firestore.rules test/database/migration_v13_to_v14_test.dart test/database/migration_v14_to_v15_test.dart test/features/assessment/drift_assessment_repository_test.dart test/features/assessment/assessment_use_cases_test.dart test/features/assessment/assessment_isolation_test.dart test/features/assessment/assessment_comparison_test.dart test/features/sync/assessment_run_sync_test.dart test/features/sync/firestore_sync_gateway_test.dart test/security/firestore-rules.test.cjs test/features/identity/drift_owner_upgrade_repository_test.dart test/features/export/export_use_cases_test.dart test/runtime/app_bootstrap_test.dart test/scenarios/guest_upgrade_restart_test.dart test/scenarios/complete_owner_export_delete_test.dart docs/database/schema_ledger.md
git diff --cached --check
git commit -m "feat: add isolated assessment runs in schema v15"
```

Rollback after deployment leaves v15 data intact and keeps Assessment unavailable. It never deletes research evidence or downgrades schema.

---

### Task 13: Final Architecture, Regression, and Rollout-Off Gate

**Files:**
- Modify: `test/architecture/fitness_test.dart`
- Create: `docs/development/2026-08-14-alltcas-shared-foundation-verification.md`.

**Interfaces:**
- Consumes: Tasks 1–12.
- Produces: one reproducible verification record and rollout state `implementedOff`; it does not activate learner-facing 8/44 features.

- [ ] **Step 1: Add architecture invariants**

Tests must enforce:

- exactly 44 product contracts and 15 runtime features;
- generated docs match catalog;
- no production usage of legacy `FieldFeatureRegistry`;
- one operational Streak writer;
- no purchase writes to XP ledger;
- every current activity has a typed evidence declaration and no file under `lib/screens/` calls the deprecated compatibility `recordAnswer` wrapper;
- production Evidence rollout defaults to Legacy and AnswerAttempt sync writes default to payload v1 until separately promoted;
- research-collection sync defaults Off and no local rules test is treated as deployment evidence;
- v2 projection receipts bridge matching v1 receipts without invoking a sink;
- assessment cannot reach learning/motivation projections;
- every owner-scoped table is in lifecycle manifest exactly once;
- ExperimentAssignment and AssessmentRun have exact sync/rules coverage;
- runtime feature flags never assign an experiment cohort;
- Today Hub, History, Review Center, and Recommendation have no competing source table.

- [ ] **Step 2: Verify and commit the final architecture invariant**

```powershell
flutter test --no-pub test/architecture/fitness_test.dart
git add -- test/architecture/fitness_test.dart
git diff --cached --check
git commit -m "test: enforce shared foundation architecture"
```

- [ ] **Step 3: Run format and analysis**

```powershell
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
```

Expected: both exit 0.

- [ ] **Step 4: Run focused domain gates**

```powershell
dart run tool/feature_contract/generate_feature_map.dart --check
flutter test --no-pub test/architecture
flutter test --no-pub test/features/learning
flutter test --no-pub test/features/progress
flutter test --no-pub test/features/rewards
flutter test --no-pub test/features/research
flutter test --no-pub test/features/assessment
flutter test --no-pub test/features/sync
flutter test --no-pub test/features/export
flutter test --no-pub test/features/identity
flutter test --no-pub test/database
flutter test --no-pub test/data/local
flutter test --no-pub test/scenarios/complete_owner_export_delete_test.dart
npm run test:rules
```

Expected: all commands exit 0. Run each Flutter suite separately to keep failures attributable and bounded.

- [ ] **Step 5: Run product completion**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-product-completion.ps1
```

Expected: exit 0 with the feature-contract focused gate and generated-artifact gate passing before the existing product suite.

- [ ] **Step 6: Build a debug candidate only**

```powershell
flutter build apk --debug
Get-FileHash -Algorithm SHA256 build/app/outputs/flutter-apk/app-debug.apk
```

Expected: build exits 0 and the SHA-256 is recorded. Do not sign, package, or replace the frozen field-release candidate.

- [ ] **Step 7: Review the final diff against the design**

```powershell
git diff c4ec20d...HEAD --stat
git diff c4ec20d...HEAD -- lib test tool firestore.rules docs
git status --short
```

Expected: only planned paths; no secrets, release artifacts, TCAS/payment/social code, or untracked generated files; status empty after commits.

- [ ] **Step 8: Create and commit only the verification record**

Record the exact HEAD SHA, schema version/table count, contract revision/hash, production rollout modes, every command above with exit code, debug APK path/hash, any intentionally skipped external deployment, and a statement that no learner-facing feature was enabled. Do not claim Firestore rules were deployed merely because local rules tests passed.

```powershell
git add -- docs/development/2026-08-14-alltcas-shared-foundation-verification.md
git diff --cached --check
git commit -m "docs: record shared compatibility foundation verification"
```

## Completion Definition

This plan is complete only when:

1. catalog, Markdown, JSON, and runtime mappings are machine-verifiable;
2. current activity answers carry declared or explicitly legacy-inferred evidence context;
3. assessment evidence is demonstrably isolated from SRS, Mastery, Quest, Streak, Achievement, XP, and Coins;
4. one evidence ID survives retry and connects attempt/event/outbox/receipts;
5. XP never decreases from a cosmetic purchase and Coins are independently reconstructible;
6. Progress reads the dedicated Streak authority;
7. experiment assignment persists independently from feature flags;
8. consent snapshots are Drift-backed and withdrawal-aware;
9. pre/post assessment pins all research versions and remains invocation-off;
10. every new table passes migration, guest upgrade, sync/export, withdrawal/delete, retention, and exact lifecycle coverage;
11. all focused gates, product completion, analysis, rules tests, and debug build pass; and
12. no learner-facing 8/44 capability is enabled merely because the foundation exists.
