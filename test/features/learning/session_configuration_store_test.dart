import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_session_configuration_store.dart';
import 'package:vocab_learning_app/features/learning/application/session_configuration_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/research/application/assigned_learning_event_context_provider.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/runtime/registries/drift_consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/experiment_registry.dart';

void main() {
  test(
    'durable store restores exact stable serialization for a fresh owner',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'owner:f16-store',
        nowUtc: () => DateTime.utc(2026, 8, 26),
      );
      final owner = await owners.getOrCreateActiveOwner();
      final configuration = _configuration(owner.id);

      await DriftSessionConfigurationStore(
        database,
      ).save(configuration, updatedAtUtc: DateTime.utc(2026, 8, 26, 9));
      final restored = await DriftSessionConfigurationStore(
        database,
      ).read(ownerId: owner.id, mode: LessonMode.meaningQuiz);

      expect(restored, configuration);
      expect(restored!.stableSerialization, configuration.stableSerialization);
      expect(restored.contentIdentity, configuration.contentIdentity);
    },
  );

  test('atomic save persists for the sole matching active owner', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'f16-atomic-matching',
      nowUtc: () => DateTime.utc(2026, 9, 5),
    );
    final owner = await owners.getOrCreateActiveOwner();
    final configuration = _configuration(owner.id);
    final ActiveOwnerSessionConfigurationStore store =
        DriftSessionConfigurationStore(database);

    await store.saveForActiveOwner(
      configuration,
      updatedAtUtc: DateTime.utc(2026, 9, 5, 9),
    );

    expect(
      await store.read(ownerId: owner.id, mode: LessonMode.meaningQuiz),
      configuration,
    );
  });

  test(
    'atomic save rejects a stale inactive owner without writing a row',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'f16-atomic-stale',
        nowUtc: () => DateTime.utc(2026, 9, 5),
      );
      final staleOwner = await owners.getOrCreateActiveOwner();
      await (database.update(database.localOwners)
            ..where((row) => row.id.equals(staleOwner.id)))
          .write(const LocalOwnersCompanion(isActive: Value(false)));
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'local:f16-atomic-current',
              createdAtUtcMs: DateTime.utc(
                2026,
                9,
                5,
                8,
              ).millisecondsSinceEpoch,
            ),
          );
      final store = DriftSessionConfigurationStore(database);

      await expectLater(
        store.saveForActiveOwner(
          _configuration(staleOwner.id),
          updatedAtUtc: DateTime.utc(2026, 9, 5, 9),
        ),
        throwsA(
          isA<SessionConfigurationResetRequired>().having(
            (error) => error.reason,
            'reason',
            SessionConfigurationResetReason.ownerDrift,
          ),
        ),
      );

      expect(
        await database.select(database.sessionConfigurations).get(),
        isEmpty,
      );
    },
  );

  test(
    'atomic save rejects ambiguous active owners without writing a row',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'f16-atomic-ambiguous',
        nowUtc: () => DateTime.utc(2026, 9, 5),
      );
      final owner = await owners.getOrCreateActiveOwner();
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'local:f16-atomic-also-active',
              createdAtUtcMs: DateTime.utc(
                2026,
                9,
                5,
                8,
              ).millisecondsSinceEpoch,
            ),
          );
      final store = DriftSessionConfigurationStore(database);

      await expectLater(
        store.saveForActiveOwner(
          _configuration(owner.id),
          updatedAtUtc: DateTime.utc(2026, 9, 5, 9),
        ),
        throwsA(
          isA<SessionConfigurationResetRequired>().having(
            (error) => error.reason,
            'reason',
            SessionConfigurationResetReason.ownerDrift,
          ),
        ),
      );

      expect(
        await database.select(database.sessionConfigurations).get(),
        isEmpty,
      );
    },
  );

  test(
    'tampered durable configuration fails closed with typed reset',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'owner:f16-tamper',
        nowUtc: () => DateTime.utc(2026, 8, 26),
      );
      final owner = await owners.getOrCreateActiveOwner();
      final configuration = _configuration(owner.id);
      final store = DriftSessionConfigurationStore(database);
      await store.save(
        configuration,
        updatedAtUtc: DateTime.utc(2026, 8, 26, 9),
      );
      await (database.update(database.sessionConfigurations)..where(
            (row) =>
                row.ownerId.equals(owner.id) &
                row.mode.equals(LessonMode.meaningQuiz.name),
          ))
          .write(
            SessionConfigurationsCompanion(
              stableSerialization: Value(
                configuration.stableSerialization.replaceFirst(
                  '"itemCount":1',
                  '"itemCount":2',
                ),
              ),
            ),
          );

      await expectLater(
        store.read(ownerId: owner.id, mode: LessonMode.meaningQuiz),
        throwsA(
          isA<SessionConfigurationResetRequired>().having(
            (error) => error.reason,
            'reason',
            SessionConfigurationResetReason.tampered,
          ),
        ),
      );
    },
  );

  test(
    'protocol provider applies only a current consent-gated persisted binding',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'owner:f16-protocol',
        nowUtc: () => DateTime.utc(2026, 8, 26),
      );
      final owner = await owners.getOrCreateActiveOwner();
      final repository = DriftExperimentAssignmentRepository(database);
      final assignedAt = DateTime.utc(2026, 8, 26, 8);
      final assignment = await repository.assignIfAbsent(
        ownerId: owner.id,
        experimentId: 'experiment:f16-config',
        experimentVersion: 2,
        cohort: 'bounded-four',
        protocolVersion: '7',
        assignedAtUtc: assignedAt,
      );
      final consent = DriftResearchConsentRepository(database);
      await consent.decide(
        ownerId: owner.id,
        version: 4,
        accepted: true,
        decidedAtUtc: assignedAt.subtract(const Duration(minutes: 1)),
      );
      final registry = DriftExperimentRegistry(repository);
      final researchCatalog = ResearchProtocolModeCatalog(
        mappings: const <ResearchProtocolModeMapping>[
          ResearchProtocolModeMapping(
            protocolId: 'protocol:f16-config',
            experimentId: 'experiment:f16-config',
            experimentVersion: 2,
            protocolVersion: '7',
            consentVersion: 4,
            mode: EvidencePolicyRolloutMode.enforced,
          ),
        ],
      );
      final researchState = AssignedLearningEventContextProvider(
        experimentRegistry: registry,
        consentRegistry: DriftConsentRegistry(database),
        protocolModeCatalog: researchCatalog,
      );
      final provider = PersistedSessionConfigurationProtocolProvider(
        currentResearchState: researchState,
        rolloutMode: PersistedEvidencePolicyRolloutModeProvider(
          experimentRegistry: registry,
          consentRegistry: DriftConsentRegistry(database),
          protocolModeCatalog: researchCatalog,
          currentActivityResearchStateProvider: researchState,
        ),
        nowUtc: () => assignedAt.add(const Duration(minutes: 1)),
        catalog: SessionConfigurationProtocolCatalog(
          baseline: const SessionConfigurationProtocolLimits.standard(),
          bindings: <SessionConfigurationProtocolBinding>[
            SessionConfigurationProtocolBinding(
              experimentId: 'experiment:f16-config',
              experimentVersion: 2,
              cohort: 'bounded-four',
              protocolVersion: '7',
              consentVersion: 4,
              limits: const SessionConfigurationProtocolLimits.standard()
                  .copyWith(
                    protocolId: 'protocol:f16-config',
                    protocolVersion: '7',
                    maximumItemCount: 4,
                  ),
            ),
          ],
        ),
      );

      final resolved = await provider.resolveForOwner(owner.id);
      final persisted = await repository.listAssignmentsForOwner(
        ownerId: owner.id,
      );

      expect(resolved.maximumItemCount, 4);
      expect(resolved.authorityIdentity, contains(assignment.id));
      expect(persisted, <Object>[assignment]);
    },
  );

  test(
    'an assignment without current consent never changes production limits',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'owner:f16-no-consent',
        nowUtc: () => DateTime.utc(2026, 8, 26),
      );
      final owner = await owners.getOrCreateActiveOwner();
      final repository = DriftExperimentAssignmentRepository(database);
      final assignedAt = DateTime.utc(2026, 8, 26, 8);
      await repository.assignIfAbsent(
        ownerId: owner.id,
        experimentId: 'experiment:f16-config',
        experimentVersion: 2,
        cohort: 'bounded-four',
        protocolVersion: '7',
        assignedAtUtc: assignedAt,
      );
      final registry = DriftExperimentRegistry(repository);
      final researchCatalog = ResearchProtocolModeCatalog(
        mappings: const <ResearchProtocolModeMapping>[
          ResearchProtocolModeMapping(
            protocolId: 'protocol:f16-config',
            experimentId: 'experiment:f16-config',
            experimentVersion: 2,
            protocolVersion: '7',
            consentVersion: 4,
            mode: EvidencePolicyRolloutMode.enforced,
          ),
        ],
      );
      final researchState = AssignedLearningEventContextProvider(
        experimentRegistry: registry,
        consentRegistry: DriftConsentRegistry(database),
        protocolModeCatalog: researchCatalog,
      );
      final provider = PersistedSessionConfigurationProtocolProvider(
        currentResearchState: researchState,
        rolloutMode: PersistedEvidencePolicyRolloutModeProvider(
          experimentRegistry: registry,
          consentRegistry: DriftConsentRegistry(database),
          protocolModeCatalog: researchCatalog,
          currentActivityResearchStateProvider: researchState,
        ),
        nowUtc: () => assignedAt.add(const Duration(minutes: 1)),
        catalog: SessionConfigurationProtocolCatalog(
          baseline: const SessionConfigurationProtocolLimits.standard(),
          bindings: <SessionConfigurationProtocolBinding>[
            SessionConfigurationProtocolBinding(
              experimentId: 'experiment:f16-config',
              experimentVersion: 2,
              cohort: 'bounded-four',
              protocolVersion: '7',
              consentVersion: 4,
              limits: const SessionConfigurationProtocolLimits.standard()
                  .copyWith(maximumItemCount: 4),
            ),
          ],
        ),
      );

      final resolved = await provider.resolveForOwner(owner.id);

      expect(
        resolved.contentIdentity,
        const SessionConfigurationProtocolLimits.standard().contentIdentity,
      );
    },
  );
}

SessionConfiguration _configuration(String ownerId) =>
    SessionConfiguration.validated(
      schemaVersion: sessionConfigurationSchemaVersion,
      policyVersion: sessionConfigurationPolicyVersion,
      ownerId: ownerId,
      mode: LessonMode.meaningQuiz,
      itemCount: 1,
      direction: SessionDirection.reverse,
      difficulty: SessionDifficulty.standard,
      hintBudget: 0,
      timing: const SessionTiming.untimedAlternative(
        maximumActiveEffort: Duration(minutes: 20),
      ),
      packIdentity: null,
      protocolId: 'protocol:f16-store',
      protocolVersion: '1',
      protocolLimitsIdentity: 'sha256:f16-store-limits',
    );
