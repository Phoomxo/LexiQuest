import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_repository.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_lifecycle_manifest.dart';
import 'package:vocab_learning_app/features/research/application/assigned_learning_event_context_provider.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/research/domain/experiment_assignment.dart';
import 'package:vocab_learning_app/features/learning/application/learning_side_effect_reconciler.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_event_store.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_eligibility_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/motivation/application/streak_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_projection_rebuilder.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/data/firestore_sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_segment.dart';
import 'package:vocab_learning_app/runtime/registries/drift_consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/experiment_registry.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';

void main() {
  setUpAll(tz.initializeTimeZones);

  late AppDatabase database;
  late DriftOwnerUpgradeRepository repository;
  late List<String> deletedSecretOwnerIds;
  var conflictSequence = 0;
  var ownerOperationSequence = 0;

  setUp(() async {
    deletedSecretOwnerIds = <String>[];
    ownerOperationSequence = 0;
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      generateConflictId: () => 'upgrade-conflict-${conflictSequence++}',
      generateOwnerId: () => 'new-guest-owner',
      generateOwnerOperationToken: () =>
          'owner-operation-${ownerOperationSequence++}',
      deleteOwnerSecrets: (ownerId) async {
        deletedSecretOwnerIds.add(ownerId);
      },
    );
    await _seedOwners(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('owner upgrade forwards the identical evidence policy pair', () {
    expect(
      repository.rolloutModeProvider,
      isA<FixedEvidencePolicyRolloutModeProvider>().having(
        (provider) => provider.mode,
        'mode',
        EvidencePolicyRolloutMode.legacy,
      ),
    );
    final policy = EvidenceEligibilityPolicySet();
    final rollout = FixedEvidencePolicyRolloutModeProvider.legacy();
    final injected = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      generateConflictId: () => 'policy-conflict',
      generateOwnerId: () => 'policy-owner',
      generateOwnerOperationToken: () => 'policy-operation',
      deleteOwnerSecrets: (_) async {},
      evidencePolicy: policy,
      rolloutModeProvider: rollout,
    );

    expect(identical(injected.evidencePolicy, policy), isTrue);
    expect(identical(injected.rolloutModeProvider, rollout), isTrue);
  });

  test('migration inventory covers every owner-scoped Drift table', () async {
    final rows = await database.customSelect('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND sql LIKE '%owner_id%'
      ORDER BY name
    ''').get();
    final actual = rows.map((row) => row.read<String>('name')).toSet();

    expect(ownerUpgradeInventory, actual);
  });

  test(
    'f16 upgrade rebinds preference and durable session configuration identity',
    () async {
      final configuration = SessionConfiguration.validated(
        schemaVersion: sessionConfigurationSchemaVersion,
        policyVersion: sessionConfigurationPolicyVersion,
        ownerId: 'guest-owner',
        mode: LessonMode.meaningQuiz,
        itemCount: 3,
        direction: SessionDirection.mixed,
        difficulty: SessionDifficulty.standard,
        hintBudget: 1,
        timing: const SessionTiming.untimedAlternative(
          maximumActiveEffort: Duration(minutes: 15),
        ),
        packIdentity: null,
        protocolId: 'protocol:f16-owner-upgrade',
        protocolVersion: '1',
        protocolLimitsIdentity: 'sha256:f16-owner-upgrade-limits',
      );
      await database
          .into(database.learningSessions)
          .insert(
            LearningSessionsCompanion.insert(
              id: 'session:f16-upgrade',
              ownerId: 'guest-owner',
              activityType: 'quiz',
              state: 'active',
              startedAtUtcMs: 10,
              appVersion: '1',
              buildId: 'f16-upgrade-test',
              sessionConfigurationIdentity: Value(
                configuration.contentIdentity,
              ),
              sessionConfigurationJson: Value(
                configuration.stableSerialization,
              ),
              configurationActiveEffortUs: const Value(750000),
            ),
          );
      await database
          .into(database.sessionConfigurations)
          .insert(
            SessionConfigurationsCompanion.insert(
              ownerId: 'guest-owner',
              mode: LessonMode.meaningQuiz.name,
              contentIdentity: configuration.contentIdentity,
              stableSerialization: configuration.stableSerialization,
              updatedAtUtcMs: 20,
            ),
          );

      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      final session = await (database.select(
        database.learningSessions,
      )..where((row) => row.id.equals('session:f16-upgrade'))).getSingle();
      final rebound = SessionConfiguration.fromStableSerialization(
        session.sessionConfigurationJson!,
      );
      final preference = await database
          .select(database.sessionConfigurations)
          .getSingle();
      expect(session.ownerId, 'account-owner');
      expect(session.configurationActiveEffortUs, 750000);
      expect(rebound.ownerId, 'account-owner');
      expect(rebound.contentIdentity, session.sessionConfigurationIdentity);
      expect(preference.ownerId, 'account-owner');
      expect(preference.stableSerialization, rebound.stableSerialization);
    },
  );

  test(
    'merge resolves saved natural-key collisions and moves report lifecycle',
    () async {
      await database.customInsert('''
      INSERT INTO saved_learning_items(
        id, owner_id, content_type, content_id, content_revision,
        saved_at_utc_ms, updated_at_utc_ms, local_revision, cloud_revision,
        is_deleted
      ) VALUES
        ('saved:guest', 'guest-owner', 'lexicalMetadata', 'word:station', 3,
         10, 30, 2, 0, 1),
        ('saved:account', 'account-owner', 'lexicalMetadata', 'word:station', 3,
         5, 20, 4, 4, 0)
    ''');
      await database.customInsert('''
      INSERT INTO content_quality_reports(
        id, owner_id, content_type, content_id, content_revision,
        reason_code, comment, submitted_at_utc_ms
      ) VALUES (
        'report:guest', 'guest-owner', 'lexicalMetadata', 'word:station', 3,
        'incorrectMeaning', NULL, 15
      )
    ''');

      final result = await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      expect(result.mode, OwnerUpgradeMode.mergedExisting);
      final saved = await database.customSelect('''
      SELECT owner_id, saved_at_utc_ms, local_revision, cloud_revision,
             is_deleted
      FROM saved_learning_items
    ''').get();
      expect(saved, hasLength(1));
      expect(saved.single.read<String>('owner_id'), 'account-owner');
      expect(saved.single.read<int>('saved_at_utc_ms'), 5);
      expect(saved.single.read<int>('is_deleted'), 1);
      expect(saved.single.read<int>('local_revision'), 5);
      expect(saved.single.read<int>('cloud_revision'), 4);
      final savedOutbox = await database.customSelect('''
      SELECT base_revision, operation_kind, state
      FROM outbox_operations
      WHERE entity_type = 'savedLearningItem'
        AND entity_id = 'saved:account'
    ''').getSingle();
      expect(savedOutbox.read<int>('base_revision'), 4);
      expect(savedOutbox.read<String>('operation_kind'), 'delete');
      expect(savedOutbox.read<String>('state'), 'pending');
      expect(
        await database
            .customSelect('''
            SELECT owner_id FROM content_quality_reports
            WHERE id = 'report:guest'
          ''')
            .map((row) => row.read<String>('owner_id'))
            .getSingle(),
        'account-owner',
      );
      expect(
        await database.customSelect('''
          SELECT operation_id FROM outbox_operations
          WHERE entity_type = 'contentQualityReport'
        ''').get(),
        isEmpty,
        reason: 'owner upgrade must not opt a local-only report into upload',
      );
    },
  );

  test('content tables have explicit non-owner lifecycle classifications', () {
    final packaged = ownerLifecycleManifest
        .where(
          (entry) => const <String>{
            'learning_packs',
            'learning_pack_items',
            'content_manifests',
          }.contains(entry.tableName),
        )
        .toList(growable: false);
    final downloads = ownerLifecycleManifest.singleWhere(
      (entry) => entry.tableName == 'content_download_states',
    );

    expect(packaged, hasLength(3));
    expect(packaged.map((entry) => entry.authority).toSet(), {
      OwnerLifecycleAuthority.packagedContent,
    });
    expect(packaged.map((entry) => entry.deletionDisposition).toSet(), {
      OwnerLifecycleDeletionDisposition.preserveGlobal,
    });
    expect(downloads.authority, OwnerLifecycleAuthority.deviceLocal);
    expect(
      downloads.deletionDisposition,
      OwnerLifecycleDeletionDisposition.preserveGlobal,
    );
  });

  test(
    'anonymous owner upgrade preserves lexical content provenance',
    () async {
      await database.customInsert(
        "INSERT INTO vocabulary_categories "
        "(id, owner_id, name, normalized_name, created_at_utc_ms, "
        "updated_at_utc_ms) VALUES "
        "('category:content', 'guest-owner', 'Content', 'content', 1, 1)",
      );
      await database.customInsert(
        "INSERT INTO vocabulary_words "
        "(id, owner_id, category_id, spelling, normalized_spelling, meaning, "
        "normalized_meaning, part_of_speech, content_revision, "
        "content_checksum_sha256, content_provenance, content_review_state, "
        "content_publication_state, created_at_utc_ms, updated_at_utc_ms) "
        "VALUES ('word:content', 'guest-owner', 'category:content', 'station', "
        "'station', 'station', 'station', 'noun', 3, "
        "'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', "
        "'userAuthored', 'unreviewed', 'private', 1, 1)",
      );
      await (database.delete(
        database.localOwners,
      )..where((row) => row.id.equals('account-owner'))).go();

      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'content-user',
      );

      final row = await database.customSelect('''
          SELECT owner_id, content_revision, content_checksum_sha256,
                 content_provenance, content_review_state,
                 content_publication_state
          FROM vocabulary_words WHERE id = 'word:content'
        ''').getSingle();
      expect(row.read<String>('owner_id'), 'guest-owner');
      expect(row.read<int>('content_revision'), 3);
      expect(
        row.read<String>('content_checksum_sha256'),
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      expect(row.read<String>('content_provenance'), 'userAuthored');
      expect(row.read<String>('content_review_state'), 'unreviewed');
      expect(row.read<String>('content_publication_state'), 'private');
    },
  );

  test(
    'alreadyBound materializes legacy coins and reward projections before returning',
    () async {
      await (database.update(
        database.localOwners,
      )..where((row) => row.id.equals('guest-owner'))).write(
        const LocalOwnersCompanion(
          firebaseUid: Value('already-bound-user'),
          accountState: Value('firebaseBound'),
        ),
      );
      await _seedMinimalLegacyRewardHistory(database, 'guest-owner');

      final result = await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'already-bound-user',
      );

      expect(result.mode, OwnerUpgradeMode.alreadyBound);
      expect(result.targetOwnerId, 'guest-owner');
      await _expectLegacyRewardCutover(database, 'guest-owner');
    },
  );

  test(
    'anonymousBound materializes legacy coins before namespace requeue and bind completes',
    () async {
      await (database.delete(
        database.localOwners,
      )..where((row) => row.id.equals('account-owner'))).go();
      await _seedMinimalLegacyRewardHistory(database, 'guest-owner');

      final result = await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'new-firebase-user',
      );

      expect(result.mode, OwnerUpgradeMode.anonymousBound);
      expect(result.targetOwnerId, 'guest-owner');
      final owner = await (database.select(
        database.localOwners,
      )..where((row) => row.id.equals('guest-owner'))).getSingle();
      expect(owner.firebaseUid, 'new-firebase-user');
      await _expectLegacyRewardCutover(database, 'guest-owner');
    },
  );

  test(
    'anonymous bind without a prior UID owner retains one local owner',
    () async {
      await (database.delete(
        database.localOwners,
      )..where((row) => row.id.equals('account-owner'))).go();

      final result = await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'new-firebase-user',
      );

      final owners = await database.select(database.localOwners).get();
      expect(result.mode, OwnerUpgradeMode.anonymousBound);
      expect(result.targetOwnerId, 'guest-owner');
      expect(owners, hasLength(1));
      expect(owners.single.id, 'guest-owner');
      expect(owners.single.firebaseUid, 'new-firebase-user');
      expect(owners.single.isActive, isTrue);
    },
  );

  test(
    'anonymous bind rehomes assignment cloud identity and survives restart context',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-assignment-anonymous-bind-',
      );
      final file = File('${directory.path}${Platform.pathSeparator}app.sqlite');
      AppDatabase? fileDatabase;
      try {
        fileDatabase = AppDatabase(NativeDatabase(file));
        await fileDatabase.customInsert(
          'INSERT INTO local_owners '
          '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
          "VALUES ('restart-guest', NULL, 'localGuest', 1, 1)",
        );
        await _putResearchConsent(
          fileDatabase,
          ownerId: 'restart-guest',
          consentVersion: 1,
        );
        final assignedAtUtc = DateTime.utc(2026, 8, 14, 8, 1);
        final assignmentRepository = DriftExperimentAssignmentRepository(
          fileDatabase,
        );
        final sourceAssignment = await assignmentRepository.assignIfAbsent(
          ownerId: 'restart-guest',
          experimentId: 'restart-study',
          experimentVersion: 1,
          cohort: 'intervention',
          protocolVersion: 'protocol-v1',
          assignedAtUtc: assignedAtUtc,
        );
        final declaredEvidence = _assignmentEvidence(
          sourceAssignment,
          consentVersion: 1,
        );
        final localAssignmentId = sourceAssignment.id;
        final cloudAssignmentId =
            DriftExperimentAssignmentRepository.canonicalAssignmentId(
              ownerId: 'restart-firebase-user',
              experimentId: sourceAssignment.experimentId,
              experimentVersion: sourceAssignment.experimentVersion,
            );
        expect(localAssignmentId, isNot(cloudAssignmentId));
        final isolatedUpgrade = DriftOwnerUpgradeRepository(
          fileDatabase,
          nowUtc: () => DateTime.utc(2026, 8, 14, 9),
          generateConflictId: () => 'restart-upgrade-conflict',
          generateOwnerId: () => 'unused-restart-owner',
          generateOwnerOperationToken: () => 'restart-upgrade-operation',
          deleteOwnerSecrets: (_) async {},
        );

        final result = await isolatedUpgrade.upgrade(
          activeOwnerId: 'restart-guest',
          firebaseUid: 'restart-firebase-user',
        );
        expect(result.mode, OwnerUpgradeMode.anonymousBound);
        expect(result.targetOwnerId, 'restart-guest');
        await fileDatabase.close();

        fileDatabase = AppDatabase(NativeDatabase(file));
        final reopenedRepository = DriftExperimentAssignmentRepository(
          fileDatabase,
        );
        final persisted = await reopenedRepository.getAssignment(
          ownerId: 'restart-guest',
          experimentId: 'restart-study',
          experimentVersion: 1,
        );
        expect(persisted.id, localAssignmentId);
        expect(persisted.cohort, sourceAssignment.cohort);
        expect(persisted.protocolVersion, sourceAssignment.protocolVersion);
        expect(persisted.assignedAtUtc, sourceAssignment.assignedAtUtc);
        final outbox = await _experimentAssignmentOutbox(fileDatabase);
        expect(outbox, hasLength(1));
        expect(outbox.single.ownerId, 'restart-guest');
        expect(outbox.single.entityId, cloudAssignmentId);
        expect(
          outbox.single.operationId,
          DriftExperimentAssignmentRepository.canonicalOutboxOperationId(
            cloudAssignmentId,
          ),
        );
        expect(outbox.single.state, 'pending');
        expect(
          outbox.where((operation) => operation.entityId == localAssignmentId),
          isEmpty,
        );

        final replay = await reopenedRepository.assignIfAbsent(
          ownerId: 'restart-guest',
          experimentId: persisted.experimentId,
          experimentVersion: persisted.experimentVersion,
          cohort: persisted.cohort,
          protocolVersion: persisted.protocolVersion,
          assignedAtUtc: persisted.assignedAtUtc,
        );
        expect(replay, persisted);
        expect(await _experimentAssignmentOutbox(fileDatabase), hasLength(1));

        final context =
            await AssignedLearningEventContextProvider(
              experimentRegistry: DriftExperimentRegistry(reopenedRepository),
              consentRegistry: DriftConsentRegistry(fileDatabase),
            ).resolve(
              ownerId: 'restart-guest',
              evidenceContext: declaredEvidence,
              occurredAtUtc: DateTime.utc(2026, 8, 14, 9, 1),
            );
        expect(context.assignmentId, persisted.id);
        expect(context.experimentContext?.variantId, persisted.cohort);
        expect(
          context.experimentContext?.assignedAtUtc,
          persisted.assignedAtUtc,
        );

        const gateToken = 'restart-assignment-claim-gate';
        final claimCatalog = ResearchProtocolModeCatalog(
          mappings: <ResearchProtocolModeMapping>[
            ResearchProtocolModeMapping(
              experimentId: persisted.experimentId,
              experimentVersion: persisted.experimentVersion,
              protocolVersion: persisted.protocolVersion,
              consentVersion: 1,
              mode: EvidencePolicyRolloutMode.shadow,
            ),
          ],
        );
        expect(
          await DriftOwnerOperationGate(fileDatabase).tryAcquire(
            token: gateToken,
            nowUtc: DateTime.utc(2026, 8, 14, 9, 2),
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );
        final claims =
            await DriftSyncStore(
              fileDatabase,
              researchSyncRollout:
                  ResearchCollectionSyncRollout.experimentAssignmentsV1(
                    deployedRulesRevision: experimentAssignmentV1RulesRevision,
                    protocolModeCatalog: claimCatalog,
                  ),
              consentRegistry: DriftConsentRegistry(fileDatabase),
            ).claimPending(
              ownerId: 'restart-guest',
              firebaseUid: 'restart-firebase-user',
              limit: 1,
              leaseToken: 'restart-assignment-claim-lease',
              ownerGateToken: gateToken,
              leaseDuration: const Duration(minutes: 5),
              nowUtc: DateTime.utc(2026, 8, 14, 9, 2),
            );
        expect(claims, hasLength(1));
        expect(claims.single.mutation.entityId, cloudAssignmentId);
        final encoded = FirestoreSyncCodec.encodeOperation(
          claims.single.mutation,
          acknowledgedAt: 'server-timestamp',
        );
        expect(encoded['entityId'], cloudAssignmentId);
      } finally {
        await fileDatabase?.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'later guest withdrawal replaces canonical target consent decision',
    () async {
      await database.customInsert(
        "INSERT INTO research_consents VALUES "
        "('consent-target', 'account-owner', 1, 'accepted', 100, NULL)",
      );
      await database.customInsert(
        "INSERT INTO research_consents VALUES "
        "('consent-guest', 'guest-owner', 1, 'withdrawn', 200, 200)",
      );
      await database.customInsert(
        'INSERT INTO local_owners '
        '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
        "VALUES ('foreign-owner', 'firebase-foreign', 'firebaseBound', 3, 0)",
      );
      await database.customInsert(
        "INSERT INTO research_consents VALUES "
        "('consent-foreign', 'foreign-owner', 1, 'accepted', 300, NULL)",
      );
      final foreignBefore = await database
          .customSelect(
            'SELECT * FROM research_consents WHERE id = ?',
            variables: const [Variable<String>('consent-foreign')],
          )
          .getSingle()
          .then((row) => Map<String, Object?>.from(row.data));

      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      final consent = await (database.select(
        database.researchConsents,
      )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
      expect(consent.id, 'consent-target');
      expect(consent.consentState, 'withdrawn');
      expect(consent.decidedAtUtcMs, 200);
      expect(consent.withdrawnAtUtcMs, 200);
      expect(
        await database
            .customSelect(
              'SELECT * FROM research_consents WHERE id = ?',
              variables: const [Variable<String>('consent-foreign')],
            )
            .getSingle()
            .then((row) => Map<String, Object?>.from(row.data)),
        foreignBefore,
      );
      expect(
        await (database.select(
          database.researchConsents,
        )..where((row) => row.ownerId.equals('guest-owner'))).get(),
        isEmpty,
      );
    },
  );

  test('newer target withdrawal beats an older guest acceptance', () async {
    await database.customInsert(
      "INSERT INTO research_consents VALUES "
      "('consent-target', 'account-owner', 1, 'withdrawn', 300, 300)",
    );
    await database.customInsert(
      "INSERT INTO research_consents VALUES "
      "('consent-guest', 'guest-owner', 1, 'accepted', 200, NULL)",
    );

    await repository.upgrade(
      activeOwnerId: 'guest-owner',
      firebaseUid: 'firebase-user',
    );

    final consent = await (database.select(
      database.researchConsents,
    )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
    expect(consent.id, 'consent-target');
    expect(consent.consentState, 'withdrawn');
    expect(consent.decidedAtUtcMs, 300);
    expect(consent.withdrawnAtUtcMs, 300);
  });

  test('withdrawal wins an exact consent decision tie', () async {
    await database.customInsert(
      "INSERT INTO research_consents VALUES "
      "('consent-target', 'account-owner', 1, 'accepted', 300, NULL)",
    );
    await database.customInsert(
      "INSERT INTO research_consents VALUES "
      "('consent-guest', 'guest-owner', 1, 'withdrawn', 300, 300)",
    );

    await repository.upgrade(
      activeOwnerId: 'guest-owner',
      firebaseUid: 'firebase-user',
    );

    final consent = await (database.select(
      database.researchConsents,
    )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
    expect(consent.id, 'consent-target');
    expect(consent.consentState, 'withdrawn');
    expect(consent.decidedAtUtcMs, 300);
    expect(consent.withdrawnAtUtcMs, 300);
  });

  test(
    'merge conflict evidence identifies target guest and merged outcomes',
    () async {
      await database.customInsert(
        'INSERT INTO association_records '
        '(id, owner_id, word_key, type, content, created_at_utc_ms) VALUES '
        "('association-target', 'account-owner', 'station', 'keyword', "
        "'target-newer', 200)",
      );
      await database.customInsert(
        'INSERT INTO association_records '
        '(id, owner_id, word_key, type, content, created_at_utc_ms) VALUES '
        "('association-guest', 'guest-owner', 'station', 'keyword', "
        "'guest-older', 100)",
      );
      await database.customInsert(
        'INSERT INTO associative_memory_states '
        '(id, owner_id, word_key, stability, difficulty, cue_dependency, '
        'lapse_count, last_reviewed_at_utc_ms, next_due_at_utc_ms, '
        'algorithm_version) VALUES '
        "('memory-target', 'account-owner', 'station', 2, 4, 0.2, 1, "
        "100, 200, 'v1')",
      );
      await database.customInsert(
        'INSERT INTO associative_memory_states '
        '(id, owner_id, word_key, stability, difficulty, cue_dependency, '
        'lapse_count, last_reviewed_at_utc_ms, next_due_at_utc_ms, '
        'algorithm_version) VALUES '
        "('memory-guest', 'guest-owner', 'station', 9, 3, 0.1, 2, "
        "200, 300, 'v2')",
      );
      await database.customInsert(
        'INSERT INTO learning_day_log '
        '(id, owner_id, learning_day, first_session_at_utc_ms) VALUES '
        "('day-target', 'account-owner', '2026-08-11', 200)",
      );
      await database.customInsert(
        'INSERT INTO learning_day_log '
        '(id, owner_id, learning_day, first_session_at_utc_ms) VALUES '
        "('day-guest', 'guest-owner', '2026-08-11', 100)",
      );

      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      final association = await (database.select(
        database.associationRecords,
      )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
      final associationConflict = await _mergeConflictFor(
        database,
        'associationRecord',
      );
      expect(
        associationConflict.read<String>('resolution_policy'),
        'guestUpgradeLatestAssociation',
      );
      expect(associationConflict.read<String>('outcome'), 'targetRetained');
      final associationTarget =
          jsonDecode(associationConflict.read<String>('cloud_snapshot_json'))
              as Map<String, dynamic>;
      expect(association.id, associationTarget['id']);
      expect(association.content, associationTarget['content']);
      expect(association.createdAtUtcMs, associationTarget['createdAtUtcMs']);

      final memory = await (database.select(
        database.associativeMemoryStates,
      )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
      final memoryConflict = await _mergeConflictFor(
        database,
        'associativeMemoryState',
      );
      expect(
        memoryConflict.read<String>('resolution_policy'),
        'guestUpgradeLatestMemory',
      );
      expect(memoryConflict.read<String>('outcome'), 'guestRetained');
      final memoryGuest =
          jsonDecode(memoryConflict.read<String>('local_snapshot_json'))
              as Map<String, dynamic>;
      expect(memory.stability, memoryGuest['stability']);
      expect(memory.lastReviewedAtUtcMs, memoryGuest['lastReviewedAtUtcMs']);
      expect(memory.nextDueAtUtcMs, memoryGuest['nextDueAtUtcMs']);

      final day = await (database.select(
        database.learningDayLog,
      )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
      final dayConflict = await _mergeConflictFor(database, 'learningDay');
      expect(
        dayConflict.read<String>('resolution_policy'),
        'guestUpgradeEarliestLearningDay',
      );
      expect(dayConflict.read<String>('outcome'), 'evidenceMerged');
      final guestDay =
          jsonDecode(dayConflict.read<String>('local_snapshot_json'))
              as Map<String, dynamic>;
      final targetDay =
          jsonDecode(dayConflict.read<String>('cloud_snapshot_json'))
              as Map<String, dynamic>;
      expect(day.id, targetDay['id']);
      expect(
        day.firstSessionAtUtcMs,
        <int>[
          guestDay['firstSessionAtUtcMs'] as int,
          targetDay['firstSessionAtUtcMs'] as int,
        ].reduce((left, right) => left < right ? left : right),
      );
    },
  );

  test('anonymous rehome creates an anchored SRS operation identity', () async {
    await (database.delete(
      database.localOwners,
    )..where((row) => row.id.equals('account-owner'))).go();
    await database.customInsert(
      "INSERT INTO vocabulary_categories "
      "(id, owner_id, name, normalized_name, created_at_utc_ms, "
      "updated_at_utc_ms) VALUES "
      "('category-srs', 'guest-owner', 'SRS', 'srs', 1, 1)",
    );
    await database.customInsert(
      "INSERT INTO vocabulary_words "
      "(id, owner_id, category_id, spelling, normalized_spelling, meaning, "
      "normalized_meaning, part_of_speech, created_at_utc_ms, "
      "updated_at_utc_ms) VALUES "
      "('word-srs', 'guest-owner', 'category-srs', 'one', 'one', 'one', "
      "'one', 'noun', 1, 1)",
    );
    await database.customInsert(
      "INSERT INTO learning_sessions (id, owner_id, activity_type, state, "
      "started_at_utc_ms, ended_at_utc_ms, correct_count, wrong_count, score, "
      "app_version, build_id) VALUES "
      "('session-srs', 'guest-owner', 'quiz', 'completed', 1, 2, 1, 0, "
      "100, '1', '1')",
    );
    await database.customInsert(
      'INSERT INTO answer_attempts '
      '(id, owner_id, session_id, word_id, prompt_mode, is_correct, '
      'response_time_ms, attempt_number, occurred_at_utc_ms, '
      'provider_provenance) VALUES '
      "('answer-srs', 'guest-owner', 'session-srs', 'word-srs', 'meaning', "
      '1, 10, 1, 2, NULL)',
    );
    await database.customInsert(
      "INSERT INTO srs_states VALUES "
      "('state-srs', 'guest-owner', 'word-srs', 1, 1, 1, 1, 0, 2, 3, 1)",
    );

    await repository.upgrade(
      activeOwnerId: 'guest-owner',
      firebaseUid: 'new-firebase-user',
    );

    final operation = await (database.select(
      database.outboxOperations,
    )..where((row) => row.entityType.equals('srsState'))).getSingle();
    expect(
      operation.operationId,
      matches(RegExp(r'^srsState:v2:[0-9a-f]{64}:r1$')),
    );
    expect(operation.entityId, 'word-srs');
    expect(operation.baseRevision, 0);
  });

  test('moves every owner-scoped row and replays as a no-op', () async {
    await _seedEveryOwnerScopedTable(database);

    final result = await repository.upgrade(
      activeOwnerId: 'guest-owner',
      firebaseUid: 'firebase-user',
    );
    final replayed = await repository.upgrade(
      activeOwnerId: result.targetOwnerId,
      firebaseUid: 'firebase-user',
    );

    expect(result.mode, OwnerUpgradeMode.mergedExisting);
    expect(result.targetOwnerId, 'account-owner');
    expect(deletedSecretOwnerIds, ['guest-owner']);
    expect(replayed.mode, OwnerUpgradeMode.alreadyBound);
    for (final table in ownerUpgradeInventory) {
      expect(
        await _ownerCount(database, table, 'guest-owner'),
        0,
        reason: '$table retained guest ownership',
      );
      expect(
        await _ownerCount(database, table, 'account-owner'),
        greaterThanOrEqualTo(1),
        reason: '$table did not reach the account owner',
      );
    }
    expect(
      await database
          .customSelect(
            'SELECT COUNT(*) AS count FROM vocabulary_import_rows '
            'WHERE import_id = ? AND word_id = ?',
            variables: const [
              Variable<String>('import-1'),
              Variable<String>('word-1'),
            ],
          )
          .getSingle()
          .then((row) => row.read<int>('count')),
      1,
    );
    final migratedEvidenceOutbox = await database
        .customSelect(
          'SELECT entity_type FROM outbox_operations '
          'WHERE owner_id = ? AND entity_type IN (?, ?) ORDER BY entity_type',
          variables: const [
            Variable<String>('account-owner'),
            Variable<String>('attempt'),
            Variable<String>('readingEvent'),
          ],
        )
        .map((row) => row.read<String>('entity_type'))
        .get();
    expect(migratedEvidenceOutbox, ['attempt', 'readingEvent']);
    final timeSegment = await database
        .select(database.learningTimeSegments)
        .getSingle();
    final timeOutbox =
        await (database.select(database.outboxOperations)
              ..where((row) => row.entityType.equals('learningTimeSegment')))
            .getSingle();
    expect(timeSegment.ownerId, 'account-owner');
    expect(timeOutbox.ownerId, 'account-owner');
    expect(
      timeOutbox.operationId,
      LearningTimeSegment.canonicalOperationId(timeSegment.id),
    );
    final goal = await database.select(database.learningGoals).getSingle();
    final reminder = await database.select(database.studyReminders).getSingle();
    final goalOutbox =
        await (database.select(database.outboxOperations)..where(
              (row) =>
                  row.entityType.equals('learningGoal') &
                  row.entityId.equals(goal.id),
            ))
            .getSingle();
    expect(goal.ownerId, 'account-owner');
    expect(reminder.ownerId, 'account-owner');
    expect(reminder.goalId, goal.id);
    expect(goalOutbox.ownerId, 'account-owner');
    expect(goalOutbox.operationKind, 'upsert');
  });

  test(
    'resolves category and word collisions and remaps dependent rows',
    () async {
      await _seedCollisionGraph(database);

      final result = await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      expect(result.conflictCount, 2);
      expect(
        await database
            .customSelect(
              'SELECT word_id FROM answer_attempts WHERE id = ?',
              variables: const [Variable<String>('attempt-guest')],
            )
            .getSingle()
            .then((row) => row.read<String>('word_id')),
        'word-target',
      );
      final operation = await database
          .customSelect(
            'SELECT owner_id, entity_id, state FROM outbox_operations '
            'WHERE operation_id = ?',
            variables: const [Variable<String>('operation-guest')],
          )
          .getSingle();
      expect(operation.read<String>('owner_id'), 'account-owner');
      expect(operation.read<String>('entity_id'), 'word-target');
      expect(operation.read<String>('state'), 'superseded');
      expect(
        await database
            .customSelect(
              'SELECT COUNT(*) AS count FROM sync_conflicts '
              'WHERE owner_id = ? AND resolution_policy = ? AND outcome = ?',
              variables: const [
                Variable<String>('account-owner'),
                Variable<String>('guestUpgradeCanonicalTarget'),
                Variable<String>('targetRetained'),
              ],
            )
            .getSingle()
            .then((row) => row.read<int>('count')),
        2,
      );
    },
  );

  test(
    'collision remaps leave a third owner bookkeeping byte-equivalent',
    () async {
      await _seedCollisionGraph(database);
      await database.customInsert(
        "INSERT INTO local_owners "
        "(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES "
        "('foreign-owner', 'firebase-foreign', 'firebaseBound', 3, 0)",
      );
      await database.customInsert(
        "INSERT INTO outbox_operations "
        "(operation_id, owner_id, entity_type, entity_id, operation_kind, "
        "state, attempt_count, created_at_utc_ms) VALUES "
        "('foreign-operation', 'foreign-owner', 'word', 'word-guest', "
        "'upsert', 'retryWaiting', 2, 3)",
      );
      await database.customInsert(
        "INSERT INTO sync_conflicts "
        "(id, owner_id, entity_type, entity_id, local_revision, cloud_revision, "
        "resolution_policy, outcome, local_snapshot_json, cloud_snapshot_json, "
        "resolved_at_utc_ms) VALUES "
        "('foreign-conflict', 'foreign-owner', 'word', 'word-guest', 1, 2, "
        "'foreignPolicy', 'foreignOutcome', '{\"foreign\":true}', "
        "'{\"foreign\":false}', 3)",
      );
      final outboxBefore = await database
          .customSelect(
            'SELECT * FROM outbox_operations WHERE operation_id = ?',
            variables: const [Variable<String>('foreign-operation')],
          )
          .getSingle()
          .then((row) => Map<String, Object?>.from(row.data));
      final conflictBefore = await database
          .customSelect(
            'SELECT * FROM sync_conflicts WHERE id = ?',
            variables: const [Variable<String>('foreign-conflict')],
          )
          .getSingle()
          .then((row) => Map<String, Object?>.from(row.data));

      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      final outboxAfter = await database
          .customSelect(
            'SELECT * FROM outbox_operations WHERE operation_id = ?',
            variables: const [Variable<String>('foreign-operation')],
          )
          .getSingle()
          .then((row) => Map<String, Object?>.from(row.data));
      final conflictAfter = await database
          .customSelect(
            'SELECT * FROM sync_conflicts WHERE id = ?',
            variables: const [Variable<String>('foreign-conflict')],
          )
          .getSingle()
          .then((row) => Map<String, Object?>.from(row.data));

      expect(outboxAfter, outboxBefore);
      expect(conflictAfter, conflictBefore);
    },
  );

  test(
    'file-backed merge retires colliding SRS and unlock outbox before claim',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-owner-merge-outbox-',
      );
      final path = '${directory.path}${Platform.pathSeparator}identity.sqlite';
      final firstDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await firstDatabase.customSelect('SELECT 1').getSingle();
        await _seedOwners(firstDatabase);
        await _seedProjectionCollisionGraph(firstDatabase);
        await firstDatabase.customInsert(
          "INSERT INTO achievement_unlocks VALUES "
          "('unlock-target', 'account-owner', 'first_answer', 1, "
          "'target-source', 1)",
        );
        await firstDatabase.customInsert(
          "INSERT INTO achievement_unlocks VALUES "
          "('unlock-guest', 'guest-owner', 'first_answer', 1, "
          "'guest-source', 2)",
        );
        await firstDatabase.customInsert(
          "INSERT INTO achievement_unlocks VALUES "
          "('unlock-guest-v7', 'guest-owner', 'first_answer', 7, "
          "'guest-source-v7', 3)",
        );
        await firstDatabase.customInsert(
          "INSERT INTO outbox_operations "
          "(operation_id, owner_id, entity_type, entity_id, operation_kind, "
          "created_at_utc_ms) VALUES "
          "('srsState:word-guest:1', 'guest-owner', 'srsState', "
          "'word-guest', 'upsert', 2)",
        );
        await firstDatabase.customInsert(
          "INSERT INTO outbox_operations "
          "(operation_id, owner_id, entity_type, entity_id, operation_kind, "
          "created_at_utc_ms) VALUES "
          "('achievementUnlock:unlock-guest:1', 'guest-owner', "
          "'achievementUnlock', 'unlock-guest', 'upsert', 2)",
        );
        await firstDatabase.customInsert(
          "INSERT INTO outbox_operations "
          "(operation_id, owner_id, entity_type, entity_id, operation_kind, "
          "created_at_utc_ms) VALUES "
          "('achievementUnlock:unlock-guest-v7:1', 'guest-owner', "
          "'achievementUnlock', 'unlock-guest-v7', 'upsert', 3)",
        );
        var tokenSequence = 0;
        await DriftOwnerUpgradeRepository(
          firstDatabase,
          nowUtc: () => DateTime.utc(2026, 7, 30, 12),
          generateConflictId: () => 'merge-conflict-${tokenSequence++}',
          generateOwnerId: () => 'unused-owner',
          generateOwnerOperationToken: () => 'merge-operation',
          deleteOwnerSecrets: (_) async {},
        ).upgrade(activeOwnerId: 'guest-owner', firebaseUid: 'firebase-user');
      } finally {
        await firstDatabase.close();
      }

      final reopenedDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await reopenedDatabase.customSelect('SELECT 1').getSingle();
        final now = DateTime.utc(2026, 7, 30, 12, 1);
        expect(
          await DriftOwnerOperationGate(reopenedDatabase).tryAcquire(
            token: 'sync-after-merge',
            nowUtc: now,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );
        final claims = await DriftSyncStore(reopenedDatabase).claimPending(
          ownerId: 'account-owner',
          firebaseUid: 'firebase-user',
          limit: 50,
          leaseToken: 'claim-after-merge',
          ownerGateToken: 'sync-after-merge',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: now,
        );
        final retired =
            await (reopenedDatabase.select(reopenedDatabase.outboxOperations)
                  ..where(
                    (row) => row.operationId.isIn(const [
                      'srsState:word-guest:1',
                      'achievementUnlock:unlock-guest:1',
                    ]),
                  ))
                .get();

        expect(retired.map((row) => row.state).toSet(), {'superseded'});
        expect(
          retired
              .singleWhere((row) => row.operationId == 'srsState:word-guest:1')
              .entityId,
          'word-target',
        );
        expect(
          claims.map((claim) => claim.mutation.operationId),
          isNot(contains('srsState:word-guest:1')),
        );
        expect(
          claims.map((claim) => claim.mutation.operationId),
          isNot(contains('achievementUnlock:unlock-guest:1')),
        );
        expect(
          await (reopenedDatabase.select(
            reopenedDatabase.achievementUnlocks,
          )..where((row) => row.id.equals('unlock-target'))).getSingleOrNull(),
          isNot(equals(null)),
          reason: 'projection rebuild must preserve the target unlock identity',
        );
        final auditRows = await (reopenedDatabase.select(
          reopenedDatabase.achievementUnlocks,
        )..where((row) => row.achievementId.equals('first_answer'))).get();
        expect(auditRows, hasLength(2));
        final progress = await DriftProgressQueries(
          reopenedDatabase,
        ).load(ownerId: 'account-owner', nowUtc: now);
        final firstAnswer = progress.achievements.where(
          (achievement) => achievement.id == 'first_answer',
        );
        expect(firstAnswer, hasLength(1));
        expect(firstAnswer.single.sourceEventId, 'target-source');
      } finally {
        await reopenedDatabase.close();
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
        await directory.delete(recursive: true);
      }
    },
  );

  test('deduplicates AI usage event ids while merging owners', () async {
    for (final owner in ['guest-owner', 'account-owner']) {
      await database.customInsert(
        "INSERT INTO ai_usage_events "
        "(event_id, owner_id, occurred_at_utc_ms, provider_id, model, "
        "request_type, outcome, latency_ms) VALUES "
        "('shared-event', ?, 20, 'gemini', 'model', "
        "'tutorReply', 'success', 10)",
        variables: [Variable<String>(owner)],
      );
    }

    final result = await repository.upgrade(
      activeOwnerId: 'guest-owner',
      firebaseUid: 'firebase-user',
    );

    expect(result.mode, OwnerUpgradeMode.mergedExisting);
    expect(await _ownerCount(database, 'ai_usage_events', 'account-owner'), 1);
  });

  test(
    'mergedExisting normalizes cursor prefix and quest reward owner',
    () async {
      final guestFirst = DateTime.utc(2026, 8, 9, 10);
      final guestPending = DateTime.utc(2026, 8, 9, 11);
      final accountLater = DateTime.utc(2026, 8, 9, 12);
      await _insertLearningEvent(
        database,
        ownerId: 'guest-owner',
        eventId: 'learning-event:guest-first',
        occurredAt: guestFirst,
      );
      await _insertLearningEvent(
        database,
        ownerId: 'guest-owner',
        eventId: 'learning-event:guest-pending',
        occurredAt: guestPending,
      );
      await _insertLearningEvent(
        database,
        ownerId: 'account-owner',
        eventId: 'learning-event:account-later',
        occurredAt: accountLater,
      );
      await _insertProjectionResult(
        database,
        ownerId: 'guest-owner',
        sourceEventId: 'learning-event:guest-first',
        projection: 'quest',
        occurredAt: guestFirst,
        result: {
          'eligible': true,
          'rewardGrants': [
            {
              'ownerId': 'guest-owner',
              'idempotencyKey': 'quest-complete:guest-first',
              'xpAmount': 25,
            },
          ],
        },
      );
      await _insertProjectionCursor(
        database,
        ownerId: 'guest-owner',
        sourceEventId: 'learning-event:guest-first',
        projection: 'quest',
        occurredAt: guestFirst,
      );
      await _insertProjectionResult(
        database,
        ownerId: 'account-owner',
        sourceEventId: 'learning-event:account-later',
        projection: 'quest',
        occurredAt: accountLater,
        result: const {'eligible': true, 'rewardGrants': []},
      );
      await _insertProjectionCursor(
        database,
        ownerId: 'account-owner',
        sourceEventId: 'learning-event:account-later',
        projection: 'quest',
        occurredAt: accountLater,
      );

      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      final cursors =
          await (database.select(database.eventsV2)..where(
                (row) =>
                    row.ownerId.equals('account-owner') &
                    row.eventType.equals('LearningProjectionCursor'),
              ))
              .get();
      expect(cursors, hasLength(1));
      expect(
        (cursors.single.eventId, cursors.single.aggregateId),
        (
          'learning-projection-cursor:account-owner:quest:v1',
          'learning-event:guest-first',
        ),
        reason: 'the safe merged prefix is the earlier guest cursor',
      );

      final guestReceipt =
          await (database.select(database.eventsV2)..where(
                (row) => row.eventId.equals(
                  'learning-projection:quest:'
                  'learning-event:guest-first:v1',
                ),
              ))
              .getSingle();
      final payload =
          jsonDecode(guestReceipt.payloadJson) as Map<String, dynamic>;
      final result = (payload['result'] as Map).cast<String, dynamic>();
      final grants = (result['rewardGrants'] as List).cast<Map>();
      expect(grants.single['ownerId'], 'account-owner');

      final replayed = <String>[];
      final rewarded = <String>[];
      String? rewardOwner;
      var questUnavailable = true;
      final reconciler = LearningSideEffectReconciler(
        database,
        questSink: (event) async {
          replayed.add(event.eventId);
          if (questUnavailable &&
              event.eventId == 'learning-event:guest-pending') {
            throw StateError('quest projection unavailable');
          }
          return const LearningProjectionResult.applied(
            payload: {'eligible': true, 'rewardGrants': <Object>[]},
          );
        },
        rewardSink: (event, questResult) async {
          rewarded.add(event.eventId);
          final grants = (questResult['rewardGrants'] as List? ?? const []);
          if (grants.isNotEmpty) {
            rewardOwner = (grants.single as Map)['ownerId'] as String;
          }
          return const LearningProjectionResult.applied();
        },
      );
      await reconciler.reconcileOwner('account-owner');
      expect(replayed, contains('learning-event:guest-pending'));
      expect(
        rewarded,
        ['learning-event:guest-first'],
        reason: 'missing earlier quest result must block the reward prefix',
      );
      expect(rewardOwner, 'account-owner');

      questUnavailable = false;
      await reconciler.reconcileOwner('account-owner');
      expect(rewarded, [
        'learning-event:guest-first',
        'learning-event:guest-pending',
        'learning-event:account-later',
      ]);
    },
  );

  test(
    'guest streak marker crash rebinds and replays once after owner merge',
    () async {
      final firstAt = DateTime.utc(2026, 7, 30, 10);
      final laterAt = DateTime.utc(2026, 7, 31, 10);
      await DriftStreakRepository(database).establishCutover(
        ownerId: 'guest-owner',
        establishedAtUtc: DateTime.utc(2026, 7, 30, 9),
      );
      final guestSource = await _insertCanonicalStreakEvent(
        database,
        ownerId: 'guest-owner',
        attemptId: 'guest-streak-crash',
        occurredAt: firstAt,
      );
      final guestStreak = StreakUseCases(
        repository: DriftStreakRepository(database),
        owners: DriftLocalOwnerRepository(
          database,
          generateId: () => 'unexpected-owner',
          nowUtc: () => firstAt,
        ),
        nowUtc: () => firstAt,
        timezoneId: 'Asia/Bangkok',
      );
      await database.customStatement('''
        CREATE TEMP TRIGGER fail_guest_streak_receipt
        BEFORE INSERT ON events_v2
        WHEN NEW.event_type = 'LearningProjectionApplied'
          AND NEW.aggregate_id = '${guestSource.eventId}'
        BEGIN SELECT RAISE(ABORT, 'injected guest streak receipt crash'); END
      ''');
      await _streakReconciler(
        database,
        guestStreak,
      ).reconcileOwner('guest-owner');
      await database.customStatement('DROP TRIGGER fail_guest_streak_receipt');
      const markerId = 'streak-application:learning-event:guest-streak-crash';
      expect(
        await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(markerId))).get(),
        hasLength(1),
      );
      const receiptId =
          'learning-projection:streak:'
          'learning-event:guest-streak-crash:v2';
      expect(
        await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(receiptId))).get(),
        isEmpty,
      );

      final upgraded = await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );
      expect(upgraded.targetOwnerId, 'account-owner');
      final accountStreak = StreakUseCases(
        repository: DriftStreakRepository(database),
        owners: DriftLocalOwnerRepository(
          database,
          generateId: () => 'unexpected-owner',
          nowUtc: () => laterAt,
        ),
        nowUtc: () => laterAt,
        timezoneId: 'Pacific/Pago_Pago',
      );
      final restarted = _streakReconciler(database, accountStreak);
      await Future.wait<void>([
        restarted.reconcileOwner('account-owner'),
        restarted.reconcileOwner('account-owner'),
      ]);

      final marker = await (database.select(
        database.eventsV2,
      )..where((row) => row.eventId.equals(markerId))).getSingle();
      final markerPayload =
          jsonDecode(marker.payloadJson) as Map<String, dynamic>;
      final markerResult = (markerPayload['result'] as Map)
          .cast<String, dynamic>();
      expect(marker.ownerId, 'account-owner');
      expect(markerResult['ownerId'], 'account-owner');
      expect(
        markerResult['receiptId'],
        'gentle-streak:account-owner:2026-07-30:v2',
      );
      final receipt = await (database.select(
        database.eventsV2,
      )..where((row) => row.eventId.equals(receiptId))).getSingle();
      final receiptPayload =
          jsonDecode(receipt.payloadJson) as Map<String, dynamic>;
      expect(receipt.ownerId, 'account-owner');
      expect(receiptPayload['result'], markerResult);
      expect(
        await database
            .customSelect(
              'SELECT 1 FROM events_v2 WHERE owner_id = ? LIMIT 1',
              variables: const [Variable<String>('guest-owner')],
              readsFrom: {database.eventsV2},
            )
            .getSingleOrNull(),
        isNull,
      );

      await _insertCanonicalStreakEvent(
        database,
        ownerId: 'account-owner',
        attemptId: 'account-streak-later',
        occurredAt: laterAt,
      );
      await restarted.reconcileOwner('account-owner');
      final state = await accountStreak.getCurrentStreak();
      expect(state.currentStreakDays, 2);
      expect(
        await (database.select(database.eventsV2)..where(
              (row) =>
                  row.ownerId.equals('account-owner') &
                  row.eventType.equals('StreakPolicyApplied'),
            ))
            .get(),
        hasLength(2),
      );
    },
  );

  test(
    'marker-era target merge blocks markerless legacy source at cutover',
    () async {
      final targetAt = DateTime.utc(2026, 7, 29, 10);
      final legacySourceAt = DateTime.utc(2026, 7, 30, 10);
      final laterAt = DateTime.utc(2026, 7, 31, 10);
      final streakRepository = DriftStreakRepository(database);
      await streakRepository.establishCutover(
        ownerId: 'account-owner',
        establishedAtUtc: DateTime.utc(2026, 7, 29, 9),
      );
      final targetSource = await _insertCanonicalStreakEvent(
        database,
        ownerId: 'account-owner',
        attemptId: 'account-marker-era',
        occurredAt: targetAt,
      );
      await streakRepository.applyProjection(
        source: targetSource,
        timezoneId: 'Asia/Bangkok',
      );
      await (database.delete(database.eventsV2)..where(
            (row) =>
                row.ownerId.equals('account-owner') &
                row.eventType.equals('StreakPolicyCutover'),
          ))
          .go();
      final legacySource = await _insertCanonicalStreakEvent(
        database,
        ownerId: 'guest-owner',
        attemptId: 'guest-markerless-legacy',
        occurredAt: legacySourceAt,
      );

      final upgraded = await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );
      expect(upgraded.targetOwnerId, 'account-owner');
      final accountStreak = StreakUseCases(
        repository: DriftStreakRepository(database),
        owners: DriftLocalOwnerRepository(
          database,
          generateId: () => 'unexpected-owner',
          nowUtc: () => laterAt,
        ),
        nowUtc: () => laterAt,
        timezoneId: 'Asia/Bangkok',
      );
      final restarted = _streakReconciler(database, accountStreak);

      await restarted.reconcileOwner('account-owner');

      final legacyReceipt =
          await (database.select(database.eventsV2)..where(
                (row) => row.eventId.equals(
                  'learning-projection:streak:${legacySource.eventId}:v2',
                ),
              ))
              .getSingle();
      final legacyPayload =
          jsonDecode(legacyReceipt.payloadJson) as Map<String, dynamic>;
      expect(legacyReceipt.eventType, 'LearningProjectionBlocked');
      expect(legacyPayload['reasonCode'], 'preMarkerCutover');
      expect(
        await (database.select(database.eventsV2)..where(
              (row) => row.eventId.equals(
                'streak-application:${legacySource.eventId}',
              ),
            ))
            .get(),
        isEmpty,
      );
      expect(
        await (database.select(database.eventsV2)..where(
              (row) => row.eventId.equals(
                'streak-application:${targetSource.eventId}',
              ),
            ))
            .get(),
        hasLength(1),
      );

      await _insertCanonicalStreakEvent(
        database,
        ownerId: 'account-owner',
        attemptId: 'account-after-merged-cutover',
        occurredAt: laterAt,
      );
      await restarted.reconcileOwner('account-owner');

      final state = await accountStreak.getCurrentStreak();
      expect(state.currentStreakDays, 1);
      expect(state.lastLearnedAtUtcMs, laterAt.millisecondsSinceEpoch);
      expect(
        await (database.select(database.eventsV2)..where(
              (row) =>
                  row.ownerId.equals('account-owner') &
                  row.eventType.equals('StreakPolicyApplied'),
            ))
            .get(),
        hasLength(2),
      );
      final cutovers =
          await (database.select(database.eventsV2)..where(
                (row) =>
                    row.ownerId.equals('account-owner') &
                    row.eventType.equals('StreakPolicyCutover'),
              ))
              .get();
      expect(cutovers, hasLength(1));
      expect(
        (jsonDecode(cutovers.single.payloadJson)
            as Map<String, dynamic>)['horizonEventId'],
        legacySource.eventId,
      );
    },
  );

  test(
    'owner upgrade drains guest replay and schedules buffered work on account',
    () async {
      final firstAt = DateTime.utc(2026, 8, 9, 10);
      final secondAt = DateTime.utc(2026, 8, 9, 11);
      await _insertLearningEvent(
        database,
        ownerId: 'guest-owner',
        eventId: 'learning-event:guest-in-flight',
        occurredAt: firstAt,
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      final projected = <String>[];
      final scheduler = LearningReconciliationScheduler(
        LearningSideEffectReconciler(
          database,
          streakSink: (event) async {
            projected.add(event.eventId);
            if (event.eventId == 'learning-event:guest-in-flight') {
              entered.complete();
              await release.future;
            }
            return const LearningProjectionResult.applied();
          },
        ),
      );
      final upgrade = UpgradeGuestOwner(
        repository,
        coordinate: (sourceOwnerId, operation) =>
            scheduler.coordinateOwnerChange(
              sourceOwnerId,
              operation,
              (result) => result.targetOwnerId,
            ),
      );

      scheduler.request('guest-owner');
      await entered.future;
      final upgrading = upgrade.call(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );
      await _insertLearningEvent(
        database,
        ownerId: 'guest-owner',
        eventId: 'learning-event:guest-buffered',
        occurredAt: secondAt,
      );
      scheduler.request('guest-owner');
      release.complete();

      final result = await upgrading;
      expect(result.targetOwnerId, 'account-owner');
      await scheduler.drain();
      expect(projected, [
        'learning-event:guest-in-flight',
        'learning-event:guest-buffered',
      ]);
      final guestProjectionRows =
          await (database.select(database.eventsV2)..where(
                (row) =>
                    row.ownerId.equals('guest-owner') &
                    (row.eventType.equals('LearningProjectionApplied') |
                        row.eventType.equals('LearningProjectionCursor')),
              ))
              .get();
      expect(guestProjectionRows, isEmpty);
      expect(
        await (database.select(database.eventsV2)..where(
              (row) =>
                  row.ownerId.equals('account-owner') &
                  row.eventType.equals('LearningProjectionApplied'),
            ))
            .get(),
        hasLength(2),
      );
      await scheduler.dispose();
    },
  );

  test('rolls back the whole upgrade when any table update fails', () async {
    await _seedEveryOwnerScopedTable(database);
    await database.customStatement('''
      CREATE TRIGGER fail_owner_upgrade
      BEFORE UPDATE OF owner_id ON reading_events
      WHEN NEW.owner_id = 'account-owner'
      BEGIN
        SELECT RAISE(ABORT, 'injected migration failure');
      END
    ''');

    await expectLater(
      repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      ),
      throwsA(isA<Object>()),
    );

    expect(
      await _ownerCount(database, 'vocabulary_categories', 'guest-owner'),
      1,
    );
    expect(await _ownerCount(database, 'reading_events', 'guest-owner'), 1);
    final guest = await (database.select(
      database.localOwners,
    )..where((row) => row.id.equals('guest-owner'))).getSingle();
    expect(guest.isActive, isTrue);
    expect(deletedSecretOwnerIds, ['guest-owner']);
  });

  test('owner upgrade waits for the persisted owner-operation gate', () async {
    final gate = DriftOwnerOperationGate(database);
    final gateReleased = Completer<void>();
    final waitingRepository = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      generateConflictId: () => 'waiting-conflict',
      generateOwnerId: () => 'waiting-owner',
      generateOwnerOperationToken: () => 'waiting-upgrade-token',
      deleteOwnerSecrets: (ownerId) async {
        deletedSecretOwnerIds.add(ownerId);
      },
      ownerOperationGate: gate,
      ownerGateDelay: (_) => gateReleased.future,
    );
    expect(
      await gate.tryAcquire(
        token: 'active-sync-token',
        nowUtc: DateTime.utc(2026, 7, 30, 12),
        leaseDuration: const Duration(minutes: 10),
      ),
      isTrue,
    );
    var completed = false;

    final upgrading = waitingRepository
        .upgrade(activeOwnerId: 'guest-owner', firebaseUid: 'firebase-user')
        .whenComplete(() => completed = true);
    await Future<void>.delayed(Duration.zero);

    expect(completed, isFalse);
    await gate.release(token: 'active-sync-token');
    gateReleased.complete();
    final result = await upgrading;
    expect(result.targetOwnerId, 'account-owner');
  });

  test(
    'owner transition heartbeat renews while external work is held',
    () async {
      final initialNow = DateTime.utc(2026, 7, 30, 12);
      var heartbeatNow = initialNow;
      final scheduler = _ManualOwnerGateDelay();
      final secretsEntered = Completer<void>();
      final releaseSecrets = Completer<void>();
      final trackingGate = _TrackingOwnerGate(
        DriftOwnerOperationGate(database),
      );
      final heartbeatRepository = DriftOwnerUpgradeRepository(
        database,
        nowUtc: () => heartbeatNow,
        generateConflictId: () => 'heartbeat-conflict',
        generateOwnerId: () => 'heartbeat-owner',
        generateOwnerOperationToken: () => 'heartbeat-owner-operation',
        deleteOwnerSecrets: (_) async {
          secretsEntered.complete();
          await releaseSecrets.future;
        },
        ownerOperationGate: trackingGate,
        ownerGateDelay: scheduler.wait,
      );

      final upgrading = heartbeatRepository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );
      await secretsEntered.future;
      expect(
        scheduler.delays.single,
        heartbeatRepository.ownerGateHeartbeatInterval,
      );
      heartbeatNow = heartbeatNow.add(scheduler.delays.single);
      scheduler.elapseNext();
      await trackingGate.renewed.future;
      heartbeatNow = initialNow.add(heartbeatRepository.ownerGateLeaseDuration);

      expect(
        await DriftOwnerOperationGate(database).tryAcquire(
          token: 'competing-transition',
          nowUtc: heartbeatNow,
          leaseDuration: const Duration(minutes: 10),
        ),
        isFalse,
      );
      releaseSecrets.complete();
      final result = await upgrading;
      expect(result.targetOwnerId, 'account-owner');
    },
  );

  test('owner transition transaction rejects a stale acquired token', () async {
    final gate = _StealingOwnerGate(
      DriftOwnerOperationGate(database),
      replacementToken: 'replacement-owner-operation',
    );
    final fencedRepository = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      generateConflictId: () => 'fenced-conflict',
      generateOwnerId: () => 'fenced-owner',
      generateOwnerOperationToken: () => 'stale-owner-operation',
      deleteOwnerSecrets: (ownerId) async {
        deletedSecretOwnerIds.add(ownerId);
      },
      ownerOperationGate: gate,
    );

    await expectLater(
      fencedRepository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      ),
      throwsA(isA<StateError>()),
    );

    final guest = await (database.select(
      database.localOwners,
    )..where((row) => row.id.equals('guest-owner'))).getSingle();
    final account = await (database.select(
      database.localOwners,
    )..where((row) => row.id.equals('account-owner'))).getSingle();
    expect(guest.isActive, isTrue);
    expect(guest.firebaseUid, isNull);
    expect(account.isActive, isFalse);
    expect(deletedSecretOwnerIds, ['guest-owner']);
  });

  test(
    'logout activates a fresh local guest without deleting account rows',
    () async {
      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );
      await database.customInsert(
        "INSERT INTO reading_events VALUES "
        "('account-reading', 'account-owner', 'doc-2', 1, 'opened', 0, 30)",
      );

      final result = await repository.createLocalGuestAfterLogout();

      expect(result.mode, OwnerUpgradeMode.localGuestCreated);
      expect(result.targetOwnerId, 'local:new-guest-owner');
      expect(await _ownerCount(database, 'reading_events', 'account-owner'), 1);
      final active = await (database.select(
        database.localOwners,
      )..where((row) => row.isActive.equals(true))).getSingle();
      expect(active.id, 'local:new-guest-owner');
      expect(active.firebaseUid, isNull);
      final cutovers =
          await (database.select(database.eventsV2)..where(
                (row) =>
                    row.ownerId.equals(active.id) &
                    row.eventType.equals('StreakPolicyCutover'),
              ))
              .get();
      expect(cutovers, hasLength(1));
      final payload =
          jsonDecode(cutovers.single.payloadJson) as Map<String, dynamic>;
      expect(payload['ownerId'], active.id);
      expect(payload['horizonEventId'], isNull);
      expect(payload['horizonOccurredAtUtcMs'], isNull);
    },
  );

  test(
    'logout cutover failure rolls back owner activation atomically',
    () async {
      await database.customStatement('''
        CREATE TEMP TRIGGER reject_logout_streak_cutover
        BEFORE INSERT ON events_v2
        WHEN NEW.event_type = 'StreakPolicyCutover'
          AND NEW.owner_id = 'local:new-guest-owner'
        BEGIN SELECT RAISE(ABORT, 'injected logout cutover failure'); END
      ''');

      await expectLater(
        repository.createLocalGuestAfterLogout(),
        throwsA(anything),
      );
      await database.customStatement(
        'DROP TRIGGER reject_logout_streak_cutover',
      );

      final active = await (database.select(
        database.localOwners,
      )..where((row) => row.isActive.equals(true))).getSingle();
      expect(active.id, 'guest-owner');
      expect(
        await (database.select(
          database.localOwners,
        )..where((row) => row.id.equals('local:new-guest-owner'))).get(),
        isEmpty,
      );
      expect(
        await (database.select(
          database.eventsV2,
        )..where((row) => row.ownerId.equals('local:new-guest-owner'))).get(),
        isEmpty,
      );
    },
  );

  test('logout rollback restores the previous account owner', () async {
    final guest = await repository.createLocalGuestAfterLogout();

    await repository.rollbackLocalGuestLogout(
      previousOwnerId: 'guest-owner',
      guestOwnerId: guest.targetOwnerId,
    );

    final active = await (database.select(
      database.localOwners,
    )..where((row) => row.isActive.equals(true))).getSingle();
    expect(active.id, 'guest-owner');
    expect(
      await (database.select(
        database.localOwners,
      )..where((row) => row.id.equals(guest.targetOwnerId))).getSingleOrNull(),
      isNull,
    );
    expect(
      await (database.select(database.eventsV2)..where(
            (row) =>
                row.eventId.equals('streak-cutover:${guest.targetOwnerId}:v1'),
          ))
          .get(),
      isEmpty,
    );
  });

  test(
    'merge rebuilds SRS and reading projections from combined evidence',
    () async {
      await _seedProjectionCollisionGraph(database);

      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      final srs =
          await (database.select(database.srsStates)..where(
                (row) =>
                    row.ownerId.equals('account-owner') &
                    row.wordId.equals('word-target'),
              ))
              .getSingle();
      expect(srs.repetitions, 2);
      final reading =
          await (database.select(database.readingProgressEntries)..where(
                (row) =>
                    row.ownerId.equals('account-owner') &
                    row.documentId.equals('shared-doc') &
                    row.documentRevision.equals(1),
              ))
              .getSingle();
      expect(reading.lastPosition, 42);
      expect(reading.isCompleted, isTrue);
    },
  );

  test(
    'merge preserves colliding reward evidence, debits duplicate purchase once, and keeps lifetime xp',
    () async {
      for (final ownerId in ['guest-owner', 'account-owner']) {
        await database.customInsert(
          "INSERT INTO points_ledger_entries "
          "(id, owner_id, idempotency_key, entry_type, amount, "
          "occurred_at_utc_ms) VALUES "
          "('seed:$ownerId', '$ownerId', 'seed:$ownerId', 'quizCorrect', 100, 1)",
        );
      }
      await database.customInsert(
        "INSERT INTO reward_transactions VALUES "
        "('reward-target', 'account-owner', 'same-tap', 'purchase', -80, "
        "'theme_ocean', 1, NULL, 2)",
      );
      await database.customInsert(
        "INSERT INTO reward_transactions VALUES "
        "('reward-guest', 'guest-owner', 'same-tap', 'purchase', -80, "
        "'theme_ocean', 1, NULL, 2)",
      );

      final result = await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      expect(result.conflictCount, 1);
      final transactions = await (database.select(
        database.rewardTransactions,
      )..where((row) => row.ownerId.equals('account-owner'))).get();
      expect(transactions, hasLength(4));
      expect(
        transactions.where((row) => row.transactionType == 'purchase'),
        hasLength(2),
      );
      expect(
        transactions.where(
          (row) => row.transactionType == 'legacyEarningBackfill',
        ),
        hasLength(2),
      );
      final rewardAccount = await DriftRewardRepository(
        database,
      ).load('account-owner');
      expect(
        await (database.select(
          database.ownedRewardItems,
        )..where((row) => row.ownerId.equals('account-owner'))).get(),
        hasLength(1),
      );
      final ledger = await (database.select(
        database.pointsLedgerEntries,
      )..where((row) => row.ownerId.equals('account-owner'))).get();
      expect(ledger.fold<int>(0, (sum, row) => sum + row.amount), 200);
      expect(rewardAccount.coinBalance, 120);
    },
  );

  test(
    'merge rehomes acknowledged anonymous cloud data to account sync',
    () async {
      await _seedEveryOwnerScopedTable(database);
      await database.customInsert(
        'INSERT INTO outbox_operations '
        '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
        'attempt_count, state, failure_code, created_at_utc_ms) VALUES '
        "('srs:word-1:stable', 'guest-owner', 'srsState', 'word-1', "
        "'upsert', 5, 'permanentFailure', 'offline', 20)",
      );
      await database.customInsert(
        'INSERT INTO outbox_operations '
        '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
        'attempt_count, state, failure_code, created_at_utc_ms) VALUES '
        "('achievement:stable', 'guest-owner', 'achievementUnlock', "
        "'achievement-1', 'upsert', 5, 'permanentFailure', 'offline', 20)",
      );
      await database.customUpdate(
        "UPDATE local_owners SET firebase_uid = 'anonymous-user' "
        "WHERE id = 'guest-owner'",
      );
      await database.customUpdate(
        'UPDATE vocabulary_categories SET cloud_revision = 4, '
        'last_acknowledged_at_utc_ms = 40, server_updated_at_utc_ms = 40 '
        "WHERE owner_id = 'guest-owner'",
      );
      await database.customUpdate(
        'UPDATE vocabulary_words SET cloud_revision = 4, '
        'last_acknowledged_at_utc_ms = 40, server_updated_at_utc_ms = 40 '
        "WHERE owner_id = 'guest-owner'",
      );
      await database.customUpdate(
        "UPDATE outbox_operations SET state = 'acknowledged', "
        'base_revision = 3, acknowledged_at_utc_ms = 40 '
        "WHERE owner_id = 'guest-owner'",
      );
      await database.customUpdate(
        "UPDATE sync_checkpoints SET server_cursor = 'anonymous-cursor', "
        "last_success_at_utc_ms = 40 WHERE owner_id = 'guest-owner'",
      );

      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      final category = await (database.select(
        database.vocabularyCategories,
      )..where((row) => row.id.equals('category-1'))).getSingle();
      final word = await (database.select(
        database.vocabularyWords,
      )..where((row) => row.id.equals('word-1'))).getSingle();
      expect(category.cloudRevision, 0);
      expect(category.lastAcknowledgedAtUtcMs, isNull);
      expect(word.cloudRevision, 0);
      expect(word.serverUpdatedAtUtcMs, isNull);
      final rehomedOutbox = await (database.select(
        database.outboxOperations,
      )..where((row) => row.ownerId.equals('account-owner'))).get();
      for (final entityType in const [
        'category',
        'word',
        'attempt',
        'readingEvent',
        'rewardTransaction',
        'srsState',
        'achievementUnlock',
      ]) {
        expect(
          rehomedOutbox.where((row) => row.entityType == entityType),
          isNotEmpty,
          reason: '$entityType was not queued for the account namespace',
        );
      }
      expect(
        rehomedOutbox
            .where(
              (row) => const {
                'category',
                'word',
                'attempt',
                'readingEvent',
                'rewardTransaction',
                'srsState',
                'achievementUnlock',
              }.contains(row.entityType),
            )
            .every(
              (row) =>
                  row.state == 'pending' &&
                  row.baseRevision == 0 &&
                  row.attemptCount == 0 &&
                  row.nextAttemptAtUtcMs == null &&
                  row.failureCode == null,
            ),
        isTrue,
      );
      expect(
        rehomedOutbox.where((row) => row.entityType == 'contentQualityReport'),
        isEmpty,
        reason: 'local-only reports remain local-only after owner rehome',
      );
      expect(
        rehomedOutbox
            .singleWhere((row) => row.operationId == 'srs:word-1:stable')
            .entityId,
        'word-1',
      );
      expect(
        rehomedOutbox
            .singleWhere((row) => row.operationId == 'achievement:stable')
            .entityId,
        'achievement-1',
      );
      final checkpoint = await (database.select(
        database.syncCheckpoints,
      )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
      expect(checkpoint.serverCursor, isNull);
      expect(checkpoint.lastSuccessAtUtcMs, isNull);

      await database.customUpdate(
        "UPDATE outbox_operations SET state = 'permanentFailure' "
        "WHERE operation_id <> 'srs:word-1:stable'",
        updates: {database.outboxOperations},
      );
      final reservationNow = DateTime.utc(2026, 7, 30, 13);
      final gate = DriftOwnerOperationGate(database);
      expect(
        await gate.tryAcquire(
          token: 'new-namespace-gate',
          nowUtc: reservationNow,
          leaseDuration: const Duration(days: 1),
        ),
        isTrue,
      );
      final syncStore = DriftSyncStore(database);
      for (var reservation = 1; reservation <= 5; reservation++) {
        final claim = (await syncStore.claimPending(
          ownerId: 'account-owner',
          firebaseUid: 'firebase-user',
          limit: 1,
          leaseToken: 'new-namespace-attempt-$reservation',
          ownerGateToken: 'new-namespace-gate',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: reservationNow,
        )).single;
        final attempted = (await syncStore.beginAttempt(
          claim: claim,
          ownerGateToken: 'new-namespace-gate',
          nowUtc: reservationNow,
        ))!;
        expect(attempted.mutation.operationId, 'srs:word-1:stable');
        expect(attempted.attemptCount, reservation);
        await syncStore.markRetry(
          operationId: attempted.mutation.operationId,
          leaseToken: attempted.leaseToken,
          ownerGateToken: 'new-namespace-gate',
          nowUtc: reservationNow,
          nextAttemptAtUtc: reservationNow,
          failure: const OfflineSyncFailure(),
        );
      }
      expect(
        await syncStore.claimPending(
          ownerId: 'account-owner',
          firebaseUid: 'firebase-user',
          limit: 1,
          leaseToken: 'new-namespace-attempt-6',
          ownerGateToken: 'new-namespace-gate',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: reservationNow,
        ),
        isEmpty,
      );
    },
  );

  test(
    'lifecycle manifest declares experiment assignments once before owner deletion',
    () {
      final assignments = ownerLifecycleManifest
          .where(
            (descriptor) => descriptor.tableName == 'experiment_assignments',
          )
          .toList(growable: false);

      expect(assignments, hasLength(1));
      expect(assignments.single.authority, OwnerLifecycleAuthority.directOwner);
      expect(
        assignments.single.deletionDisposition,
        OwnerLifecycleDeletionDisposition.deleteDirect,
      );
      final assignmentIndex = ownerLifecyclePhysicalDeletionOrder.indexOf(
        'experiment_assignments',
      );
      expect(assignmentIndex, greaterThanOrEqualTo(0));
      expect(
        assignmentIndex,
        lessThan(ownerLifecyclePhysicalDeletionOrder.indexOf('local_owners')),
      );
    },
  );

  test(
    'lifecycle manifest declares assessment runs once before every parent',
    () {
      final runs = ownerLifecycleManifest
          .where((descriptor) => descriptor.tableName == 'assessment_runs')
          .toList(growable: false);

      expect(runs, hasLength(1));
      expect(runs.single.authority, OwnerLifecycleAuthority.directOwner);
      expect(
        runs.single.deletionDisposition,
        OwnerLifecycleDeletionDisposition.deleteDirect,
      );
      final runIndex = ownerLifecyclePhysicalDeletionOrder.indexOf(
        'assessment_runs',
      );
      expect(runIndex, greaterThanOrEqualTo(0));
      for (final parent in const [
        'learning_sessions',
        'experiment_assignments',
        'local_owners',
      ]) {
        expect(
          runIndex,
          lessThan(ownerLifecyclePhysicalDeletionOrder.indexOf(parent)),
          reason: 'assessment_runs must be deleted before $parent',
        );
      }
      expect(ownerUpgradeInventory, contains('assessment_runs'));
    },
  );

  test(
    'merge coalesces only byte-equivalent assessment runs under owner mapping',
    () async {
      final pair = await _seedEquivalentAssessmentPair(database);
      final guestBefore = await _assessmentRunSnapshot(
        database,
        pair.guestRun.id,
      );

      final result = await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      expect(result.mode, OwnerUpgradeMode.mergedExisting);
      expect(result.targetOwnerId, 'account-owner');
      expect(await _assessmentRunsForOwner(database, 'guest-owner'), isEmpty);
      final targetRuns = await _assessmentRunsForOwner(
        database,
        'account-owner',
      );
      expect(targetRuns, hasLength(1));
      expect(targetRuns.single['study_cycle_id'], 'assessment-cycle');
      expect(targetRuns.single['phase'], 'pre');
      expect(targetRuns.single['state'], 'active');
      expect(targetRuns.single['protocol_id'], guestBefore['protocol_id']);
      expect(
        targetRuns.single['protocol_version'],
        guestBefore['protocol_version'],
      );
      expect(targetRuns.single['cohort'], guestBefore['cohort']);
      expect(
        targetRuns.single['instrument_checksum_sha256'],
        guestBefore['instrument_checksum_sha256'],
      );
      expect(
        targetRuns.single['form_checksum_sha256'],
        guestBefore['form_checksum_sha256'],
      );
      expect(
        targetRuns.single['feature_contract_hash'],
        guestBefore['feature_contract_hash'],
      );
      expect(targetRuns.single['assignment_id'], pair.targetAssignment.id);
      expect(
        targetRuns.single['learning_session_id'],
        pair.targetRun.learningSessionId,
      );
      expect(await _experimentAssignmentOutbox(database), hasLength(1));
      expect(
        (await _experimentAssignmentOutbox(database)).single.ownerId,
        'account-owner',
      );
    },
  );

  test(
    'equivalent terminal run merge retires source revisions and keeps target '
    'sync claimable',
    () async {
      final pair = await _seedEquivalentAssessmentPair(database);
      final terminalAtUtc = DateTime.fromMillisecondsSinceEpoch(
        40,
        isUtc: true,
      );
      final assessments = DriftAssessmentRepository(database);
      await assessments.complete(
        runId: pair.guestRun.id,
        completedAtUtc: terminalAtUtc,
      );
      await assessments.complete(
        runId: pair.targetRun.id,
        completedAtUtc: terminalAtUtc,
      );
      final result = await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      expect(result.mode, OwnerUpgradeMode.mergedExisting);
      final operations =
          await (database.select(database.outboxOperations)
                ..where((row) => row.entityType.equals('assessmentRun'))
                ..orderBy([
                  (row) => OrderingTerm.asc(row.baseRevision),
                  (row) => OrderingTerm.asc(row.operationId),
                ]))
              .get();
      expect(operations.map((row) => row.operationId), <String>[
        'assessmentRun:${pair.targetRun.id}:1',
        'assessmentRun:${pair.targetRun.id}:2',
      ]);
      expect(
        operations.map((row) => row.ownerId),
        everyElement('account-owner'),
      );
      expect(
        operations.map((row) => row.entityId),
        everyElement(pair.targetRun.id),
      );
      expect(operations.map((row) => row.state), everyElement('pending'));

      final claimAtUtc = DateTime.fromMillisecondsSinceEpoch(50, isUtc: true);
      const gateToken = 'assessment-coalescence-owner-gate';
      expect(
        await DriftOwnerOperationGate(database).tryAcquire(
          token: gateToken,
          nowUtc: claimAtUtc,
          leaseDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );
      final catalog = ResearchProtocolModeCatalog(
        mappings: <ResearchProtocolModeMapping>[
          ResearchProtocolModeMapping(
            protocolId: 'assessment-protocol',
            experimentId: pair.targetAssignment.experimentId,
            experimentVersion: pair.targetAssignment.experimentVersion,
            protocolVersion: pair.targetAssignment.protocolVersion,
            consentVersion: 1,
            mode: EvidencePolicyRolloutMode.enforced,
          ),
        ],
      );
      expect(
        await database.customUpdate(
          "UPDATE outbox_operations SET state = 'acknowledged', "
          'acknowledged_at_utc_ms = 45 '
          "WHERE entity_type = 'experimentAssignment'",
        ),
        1,
        reason: 'the canonical assignment prerequisite is cloud-durable',
      );
      final claims =
          await DriftSyncStore(
            database,
            researchSyncRollout:
                ResearchCollectionSyncRollout.researchAssessmentV1(
                  deployedExperimentAssignmentRulesRevision:
                      experimentAssignmentV1RulesRevision,
                  deployedAssessmentRunRulesRevision:
                      assessmentRunV1RulesRevision,
                  protocolModeCatalog: catalog,
                ),
            consentRegistry: DriftConsentRegistry(database),
          ).claimPending(
            ownerId: 'account-owner',
            firebaseUid: 'firebase-user',
            limit: 1,
            leaseToken: 'assessment-coalescence-lease',
            ownerGateToken: gateToken,
            leaseDuration: const Duration(minutes: 5),
            nowUtc: claimAtUtc,
          );
      expect(claims, hasLength(1));
      expect(claims.single.localOperationId, operations.first.operationId);
      expect(claims.single.mutation.collection, SyncCollection.assessmentRuns);
      expect(claims.single.mutation.entityId, pair.targetRun.id);
      expect(claims.single.mutation.localRevision, 1);
    },
  );

  test(
    'assessment metadata state timestamp and evidence conflicts roll back owner upgrade',
    () async {
      final cases = <String, Future<void> Function(AppDatabase)>{
        'cohort': (db) => _updateAssessmentRun(db, 'cohort', 'other-arm'),
        'protocol': (db) =>
            _updateAssessmentRun(db, 'protocol_version', 'other-protocol'),
        'form': (db) => _updateAssessmentRun(db, 'form_id', 'other-form'),
        'instrument': (db) =>
            _updateAssessmentRun(db, 'instrument_id', 'other-instrument'),
        'checksum': (db) => _updateAssessmentRun(
          db,
          'form_checksum_sha256',
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
        'content': (db) =>
            _updateAssessmentRun(db, 'content_revision', 'other-content'),
        'policy': (db) =>
            _updateAssessmentRun(db, 'evidence_policy_version', 'other-policy'),
        'contract': (db) => _updateAssessmentRun(
          db,
          'feature_contract_hash',
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        ),
        'state': (db) async {
          await db.customUpdate(
            "UPDATE assessment_runs SET state = 'completed', "
            'completed_at_utc_ms = 40 WHERE id = ?',
            variables: const [Variable<String>('target-assessment-run')],
          );
        },
        'timestamp': (db) => _updateAssessmentRun(db, 'started_at_utc_ms', 31),
        'evidence set': _seedGuestOnlyAssessmentEvidence,
      };

      for (final entry in cases.entries) {
        final caseDatabase = AppDatabase(NativeDatabase.memory());
        try {
          await _seedOwners(caseDatabase);
          await _seedEquivalentAssessmentPair(caseDatabase);
          await entry.value(caseDatabase);
          final beforeRuns = await _assessmentRunInventory(caseDatabase);
          final beforeAssignments = await _experimentAssignmentOutboxSnapshot(
            caseDatabase,
          );
          final caseRepository = DriftOwnerUpgradeRepository(
            caseDatabase,
            nowUtc: () => DateTime.utc(2026, 8, 14, 12),
            generateConflictId: () => 'assessment-${entry.key}-conflict',
            generateOwnerId: () => 'unused-assessment-owner',
            generateOwnerOperationToken: () =>
                'assessment-${entry.key}-operation',
            deleteOwnerSecrets: (_) async {},
          );

          await expectLater(
            caseRepository.upgrade(
              activeOwnerId: 'guest-owner',
              firebaseUid: 'firebase-user',
            ),
            throwsA(isA<AssessmentRunConflict>()),
            reason: entry.key,
          );

          expect(
            await _assessmentRunInventory(caseDatabase),
            beforeRuns,
            reason: entry.key,
          );
          expect(
            await _experimentAssignmentOutboxSnapshot(caseDatabase),
            beforeAssignments,
            reason: entry.key,
          );
          final owners = await caseDatabase
              .customSelect(
                'SELECT id, firebase_uid, is_active FROM local_owners '
                'ORDER BY id',
              )
              .map((row) => row.data)
              .get();
          expect(owners, [
            {
              'id': 'account-owner',
              'firebase_uid': 'firebase-user',
              'is_active': 0,
            },
            {'id': 'guest-owner', 'firebase_uid': null, 'is_active': 1},
          ], reason: entry.key);
        } finally {
          await caseDatabase.close();
        }
      }
    },
  );

  test(
    'merge reconciles equivalent assignment and cloud outbox exactly once',
    () async {
      const assignedAtUtcMs = 1723651200000;
      final assignmentRepository = DriftExperimentAssignmentRepository(
        database,
      );
      final guestAssignment = await assignmentRepository.assignIfAbsent(
        ownerId: 'guest-owner',
        experimentId: 'research-assessment',
        experimentVersion: 1,
        cohort: 'treatment-a',
        protocolVersion: '2026.08',
        assignedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          assignedAtUtcMs,
          isUtc: true,
        ),
      );
      final guestDeclaredEvidence = _assignmentEvidence(
        guestAssignment,
        consentVersion: 1,
      );
      final accountAssignment = await assignmentRepository.assignIfAbsent(
        ownerId: 'account-owner',
        experimentId: 'research-assessment',
        experimentVersion: 1,
        cohort: 'treatment-a',
        protocolVersion: '2026.08',
        assignedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          assignedAtUtcMs,
          isUtc: true,
        ),
      );
      await _putResearchConsent(
        database,
        ownerId: 'account-owner',
        consentVersion: 1,
      );
      final cloudAssignmentId =
          DriftExperimentAssignmentRepository.canonicalAssignmentId(
            ownerId: 'firebase-user',
            experimentId: accountAssignment.experimentId,
            experimentVersion: accountAssignment.experimentVersion,
          );

      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      final rows = await database
          .customSelect(
            '''
          SELECT id, owner_id, experiment_id, experiment_version, cohort,
                 protocol_version, assigned_at_utc_ms
          FROM experiment_assignments
          WHERE owner_id = ?
        ''',
            variables: [Variable<String>('account-owner')],
          )
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.data['id'], accountAssignment.id);
      expect(rows.single.data['experiment_id'], 'research-assessment');
      expect(rows.single.data['experiment_version'], 1);
      expect(rows.single.data['cohort'], 'treatment-a');
      expect(rows.single.data['protocol_version'], '2026.08');
      expect(rows.single.data['assigned_at_utc_ms'], assignedAtUtcMs);
      expect(
        await _experimentAssignmentCount(database, ownerId: 'guest-owner'),
        0,
      );
      final assignmentOutbox = await _experimentAssignmentOutbox(database);
      expect(assignmentOutbox, hasLength(1));
      expect(assignmentOutbox.single.ownerId, 'account-owner');
      expect(assignmentOutbox.single.entityId, cloudAssignmentId);
      expect(
        assignmentOutbox.single.operationId,
        DriftExperimentAssignmentRepository.canonicalOutboxOperationId(
          cloudAssignmentId,
        ),
      );
      expect(
        assignmentOutbox.where(
          (operation) => operation.entityId == guestAssignment.id,
        ),
        isEmpty,
      );
      final replay = await assignmentRepository.assignIfAbsent(
        ownerId: 'account-owner',
        experimentId: accountAssignment.experimentId,
        experimentVersion: accountAssignment.experimentVersion,
        cohort: accountAssignment.cohort,
        protocolVersion: accountAssignment.protocolVersion,
        assignedAtUtc: accountAssignment.assignedAtUtc,
      );
      expect(replay, accountAssignment);
      expect(await _experimentAssignmentOutbox(database), hasLength(1));
      final mergedContext =
          await AssignedLearningEventContextProvider(
            experimentRegistry: DriftExperimentRegistry(assignmentRepository),
            consentRegistry: DriftConsentRegistry(database),
          ).resolve(
            ownerId: 'account-owner',
            evidenceContext: guestDeclaredEvidence,
            occurredAtUtc: DateTime.utc(2026, 8, 14, 8, 30),
          );
      expect(mergedContext.assignmentId, guestAssignment.id);
      expect(
        mergedContext.experimentContext?.variantId,
        guestAssignment.cohort,
      );
      expect(
        mergedContext.experimentContext?.assignedAtUtc,
        guestAssignment.assignedAtUtc,
      );

      const gateToken = 'merged-assignment-claim-gate';
      final claimAt = DateTime.utc(2026, 8, 14, 9);
      final claimCatalog = ResearchProtocolModeCatalog(
        mappings: <ResearchProtocolModeMapping>[
          ResearchProtocolModeMapping(
            experimentId: accountAssignment.experimentId,
            experimentVersion: accountAssignment.experimentVersion,
            protocolVersion: accountAssignment.protocolVersion,
            consentVersion: 1,
            mode: EvidencePolicyRolloutMode.shadow,
          ),
        ],
      );
      expect(
        await DriftOwnerOperationGate(database).tryAcquire(
          token: gateToken,
          nowUtc: claimAt,
          leaseDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );
      final claims =
          await DriftSyncStore(
            database,
            researchSyncRollout:
                ResearchCollectionSyncRollout.experimentAssignmentsV1(
                  deployedRulesRevision: experimentAssignmentV1RulesRevision,
                  protocolModeCatalog: claimCatalog,
                ),
            consentRegistry: DriftConsentRegistry(database),
          ).claimPending(
            ownerId: 'account-owner',
            firebaseUid: 'firebase-user',
            limit: 1,
            leaseToken: 'merged-assignment-claim-lease',
            ownerGateToken: gateToken,
            leaseDuration: const Duration(minutes: 5),
            nowUtc: claimAt,
          );
      expect(claims, hasLength(1));
      expect(claims.single.mutation.entityId, cloudAssignmentId);
      expect(
        () => FirestoreSyncCodec.encodeOperation(
          claims.single.mutation,
          acknowledgedAt: 'server-timestamp',
        ),
        returnsNormally,
      );
    },
  );

  test(
    'conflicting experiment assignment aborts owner upgrade without partial migration',
    () async {
      final assignmentRepository = DriftExperimentAssignmentRepository(
        database,
      );
      await assignmentRepository.assignIfAbsent(
        ownerId: 'guest-owner',
        experimentId: 'research-assessment',
        experimentVersion: 1,
        cohort: 'control',
        protocolVersion: '2026.08',
        assignedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          1723651200000,
          isUtc: true,
        ),
      );
      await assignmentRepository.assignIfAbsent(
        ownerId: 'account-owner',
        experimentId: 'research-assessment',
        experimentVersion: 1,
        cohort: 'treatment-a',
        protocolVersion: '2026.08',
        assignedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          1723651200000,
          isUtc: true,
        ),
      );
      final outboxBefore = await _experimentAssignmentOutboxSnapshot(database);
      await database.customInsert(
        '''
          INSERT INTO vocabulary_categories
            (id, owner_id, name, normalized_name, created_at_utc_ms,
             updated_at_utc_ms)
          VALUES (?, ?, ?, ?, ?, ?)
        ''',
        variables: const [
          Variable<String>('guest-category'),
          Variable<String>('guest-owner'),
          Variable<String>('guest category'),
          Variable<String>('guest category'),
          Variable<int>(1723651200000),
          Variable<int>(1723651200000),
        ],
      );

      await expectLater(
        repository.upgrade(
          activeOwnerId: 'guest-owner',
          firebaseUid: 'firebase-user',
        ),
        throwsA(isA<ExperimentAssignmentConflict>()),
      );

      expect(
        await _experimentAssignmentCount(database, ownerId: 'guest-owner'),
        1,
      );
      expect(
        await _experimentAssignmentCount(database, ownerId: 'account-owner'),
        1,
      );
      final guest = await database
          .customSelect(
            'SELECT firebase_uid FROM local_owners WHERE id = ?',
            variables: [Variable<String>('guest-owner')],
          )
          .getSingle();
      expect(guest.data['firebase_uid'], isNull);
      final category = await database
          .customSelect(
            'SELECT owner_id FROM vocabulary_categories WHERE id = ?',
            variables: [Variable<String>('guest-category')],
          )
          .getSingle();
      expect(category.data['owner_id'], 'guest-owner');
      expect(await _experimentAssignmentOutboxSnapshot(database), outboxBefore);
    },
  );
}

final class _ManualOwnerGateDelay {
  final List<Duration> delays = <Duration>[];
  final List<Completer<void>> _scheduled = <Completer<void>>[];

  Future<void> wait(Duration delay) {
    delays.add(delay);
    final completer = Completer<void>();
    _scheduled.add(completer);
    return completer.future;
  }

  void elapseNext() {
    _scheduled.firstWhere((item) => !item.isCompleted).complete();
  }
}

final class _TrackingOwnerGate implements OwnerOperationGate {
  _TrackingOwnerGate(this.delegate);

  final OwnerOperationGate delegate;
  final Completer<void> renewed = Completer<void>();

  @override
  Future<bool> tryAcquire({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) => delegate.tryAcquire(
    token: token,
    nowUtc: nowUtc,
    leaseDuration: leaseDuration,
  );

  @override
  Future<bool> renew({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    final result = await delegate.renew(
      token: token,
      nowUtc: nowUtc,
      leaseDuration: leaseDuration,
    );
    if (!renewed.isCompleted) renewed.complete();
    return result;
  }

  @override
  Future<bool> isOwned({required String token, required DateTime nowUtc}) =>
      delegate.isOwned(token: token, nowUtc: nowUtc);

  @override
  Future<void> release({required String token}) =>
      delegate.release(token: token);
}

final class _StealingOwnerGate implements OwnerOperationGate {
  _StealingOwnerGate(this.delegate, {required this.replacementToken});

  final OwnerOperationGate delegate;
  final String replacementToken;
  bool _stolen = false;

  @override
  Future<bool> tryAcquire({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    final acquired = await delegate.tryAcquire(
      token: token,
      nowUtc: nowUtc,
      leaseDuration: leaseDuration,
    );
    if (acquired && !_stolen) {
      _stolen = true;
      await delegate.release(token: token);
      await delegate.tryAcquire(
        token: replacementToken,
        nowUtc: nowUtc,
        leaseDuration: leaseDuration,
      );
    }
    return acquired;
  }

  @override
  Future<bool> renew({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) => delegate.renew(
    token: token,
    nowUtc: nowUtc,
    leaseDuration: leaseDuration,
  );

  @override
  Future<bool> isOwned({required String token, required DateTime nowUtc}) =>
      delegate.isOwned(token: token, nowUtc: nowUtc);

  @override
  Future<void> release({required String token}) =>
      delegate.release(token: token);
}

Future<QueryRow> _mergeConflictFor(AppDatabase database, String entityType) {
  return database
      .customSelect(
        'SELECT * FROM sync_conflicts '
        'WHERE owner_id = ? AND entity_type = ?',
        variables: [
          const Variable<String>('account-owner'),
          Variable<String>(entityType),
        ],
      )
      .getSingle();
}

const _legacyRewardPointId = 'legacy-reward-point';
const _legacyRewardDigest =
    'b4efae5822d88f42a3a3d90cc3a371c92bdc24a73cefe6559ec36c6907473934';
const _legacyBackfillTransactionId = 'reward:legacy:$_legacyRewardDigest';
const _legacyBackfillIdempotencyKey = 'economy:v1:legacy:$_legacyRewardDigest';
const _legacyBackfillOutboxId =
    'rewardTransaction:$_legacyBackfillTransactionId:1';

Future<void> _seedMinimalLegacyRewardHistory(
  AppDatabase database,
  String ownerId,
) async {
  await database
      .into(database.pointsLedgerEntries)
      .insert(
        PointsLedgerEntriesCompanion.insert(
          id: _legacyRewardPointId,
          ownerId: ownerId,
          idempotencyKey: 'legacy-reward-point-key',
          entryType: 'quizCorrect',
          amount: 100,
          occurredAtUtcMs: 10,
        ),
      );
  await database
      .into(database.rewardTransactions)
      .insert(
        RewardTransactionsCompanion.insert(
          id: 'historical-theme-purchase',
          ownerId: ownerId,
          idempotencyKey: 'historical-theme-purchase',
          transactionType: 'purchase',
          amount: -80,
          itemId: const Value('theme_ocean'),
          catalogVersion: 1,
          occurredAtUtcMs: 20,
        ),
      );
  await database
      .into(database.rewardTransactions)
      .insert(
        RewardTransactionsCompanion.insert(
          id: 'historical-theme-equip',
          ownerId: ownerId,
          idempotencyKey: 'historical-theme-equip',
          transactionType: 'equip',
          amount: 0,
          itemId: const Value('theme_ocean'),
          catalogVersion: 1,
          occurredAtUtcMs: 21,
        ),
      );
}

Future<void> _expectLegacyRewardCutover(
  AppDatabase database,
  String ownerId,
) async {
  final backfill = await (database.select(
    database.rewardTransactions,
  )..where((row) => row.id.equals(_legacyBackfillTransactionId))).getSingle();
  expect(backfill.id, _legacyBackfillTransactionId);
  expect(backfill.ownerId, ownerId);
  expect(backfill.idempotencyKey, _legacyBackfillIdempotencyKey);
  expect(backfill.transactionType, 'legacyEarningBackfill');
  expect(backfill.amount, 100);
  expect(backfill.itemId, isNull);
  expect(backfill.catalogVersion, 0);
  expect(backfill.sourceEventId, _legacyRewardPointId);
  expect(backfill.occurredAtUtcMs, 10);

  final outbox =
      await (database.select(database.outboxOperations)
            ..where((row) => row.operationId.equals(_legacyBackfillOutboxId)))
          .getSingle();
  expect(outbox.operationId, _legacyBackfillOutboxId);
  expect(outbox.ownerId, ownerId);
  expect(outbox.entityType, 'rewardTransaction');
  expect(outbox.entityId, _legacyBackfillTransactionId);
  expect(outbox.operationKind, 'upsert');
  expect(outbox.payloadVersion, 1);
  expect(outbox.baseRevision, 0);
  expect(outbox.state, 'pending');
  expect(outbox.attemptCount, 0);
  expect(outbox.nextAttemptAtUtcMs, isNull);
  expect(outbox.leaseToken, isNull);
  expect(outbox.leaseExpiresAtUtcMs, isNull);
  expect(outbox.lastAttemptAtUtcMs, isNull);
  expect(outbox.createdAtUtcMs, 10);
  expect(outbox.acknowledgedAtUtcMs, isNull);
  expect(outbox.failureCode, isNull);

  final owned = await (database.select(
    database.ownedRewardItems,
  )..where((row) => row.ownerId.equals(ownerId))).getSingle();
  expect(owned.id, 'owned:$ownerId:theme_ocean');
  expect(owned.itemId, 'theme_ocean');
  expect(owned.catalogVersion, 1);
  expect(owned.acquiredByTransactionId, 'historical-theme-purchase');
  expect(owned.acquiredAtUtcMs, 20);

  final equipped = await (database.select(
    database.equippedRewardItems,
  )..where((row) => row.ownerId.equals(ownerId))).getSingle();
  expect(equipped.id, 'equipped:$ownerId:theme');
  expect(equipped.slot, 'theme');
  expect(equipped.itemId, 'theme_ocean');
  expect(equipped.equippedAtUtcMs, 21);
  expect(
    await DriftRewardProjectionRebuilder(database).coinBalance(ownerId),
    20,
  );
}

Future<
  ({
    AssessmentRun guestRun,
    AssessmentRun targetRun,
    ExperimentAssignment guestAssignment,
    ExperimentAssignment targetAssignment,
  })
>
_seedEquivalentAssessmentPair(AppDatabase database) async {
  await _putResearchConsent(
    database,
    ownerId: 'guest-owner',
    consentVersion: 1,
    decidedAtUtcMs: 20,
  );
  await _putResearchConsent(
    database,
    ownerId: 'account-owner',
    consentVersion: 1,
    decidedAtUtcMs: 20,
  );
  final assignments = DriftExperimentAssignmentRepository(database);
  final assignedAtUtc = DateTime.fromMillisecondsSinceEpoch(25, isUtc: true);
  final guestAssignment = await assignments.assignIfAbsent(
    ownerId: 'guest-owner',
    experimentId: 'assessment-study',
    experimentVersion: 1,
    cohort: 'enforced-a',
    protocolVersion: 'assessment-protocol-v1',
    assignedAtUtc: assignedAtUtc,
  );
  final targetAssignment = await assignments.assignIfAbsent(
    ownerId: 'account-owner',
    experimentId: 'assessment-study',
    experimentVersion: 1,
    cohort: 'enforced-a',
    protocolVersion: 'assessment-protocol-v1',
    assignedAtUtc: assignedAtUtc,
  );
  await database.customInsert(
    'INSERT INTO learning_sessions '
    '(id, owner_id, activity_type, state, started_at_utc_ms, app_version, '
    'build_id) VALUES '
    "('guest-assessment-session', 'guest-owner', 'assessment', 'active', "
    "30, '1.0.0', 'task-12-owner-upgrade'), "
    "('target-assessment-session', 'account-owner', 'assessment', 'active', "
    "30, '1.0.0', 'task-12-owner-upgrade')",
  );
  final repository = DriftAssessmentRepository(database);
  final guestRun = await repository.start(
    _assessmentRun(
      id: 'guest-assessment-run',
      ownerId: 'guest-owner',
      learningSessionId: 'guest-assessment-session',
      assignment: guestAssignment,
    ),
  );
  final targetRun = await repository.start(
    _assessmentRun(
      id: 'target-assessment-run',
      ownerId: 'account-owner',
      learningSessionId: 'target-assessment-session',
      assignment: targetAssignment,
    ),
  );
  return (
    guestRun: guestRun,
    targetRun: targetRun,
    guestAssignment: guestAssignment,
    targetAssignment: targetAssignment,
  );
}

AssessmentRun _assessmentRun({
  required String id,
  required String ownerId,
  required String learningSessionId,
  required ExperimentAssignment assignment,
}) {
  return AssessmentRun(
    id: id,
    ownerId: ownerId,
    learningSessionId: learningSessionId,
    studyCycleId: 'assessment-cycle',
    phase: AssessmentPhase.pre,
    state: AssessmentRunState.active,
    protocolId: 'assessment-protocol',
    protocolVersion: assignment.protocolVersion,
    experimentId: assignment.experimentId,
    experimentVersion: assignment.experimentVersion,
    assignmentId: assignment.id,
    cohort: assignment.cohort,
    consentVersion: 1,
    consentDecidedAtUtc: DateTime.fromMillisecondsSinceEpoch(20, isUtc: true),
    instrumentId: 'vocabulary-outcome',
    instrumentVersion: '1.0.0',
    formId: 'form-a',
    formVersion: '1.0.0',
    instrumentChecksumSha256:
        '1111111111111111111111111111111111111111111111111111111111111111',
    formChecksumSha256:
        '2222222222222222222222222222222222222222222222222222222222222222',
    appVersion: '1.0.0',
    buildId: 'task-12-owner-upgrade',
    databaseSchemaVersion: AppDatabase.currentSchemaVersion,
    contentRevision: 'assessment-content-r1',
    evidencePolicyVersion: EvidenceContext.currentPolicyVersion,
    featureContractRevision: currentFeatureContractIdentity.revision,
    featureContractHash: currentFeatureContractIdentity.semanticHash,
    startedAtUtc: DateTime.fromMillisecondsSinceEpoch(30, isUtc: true),
    completedAtUtc: null,
    abandonedAtUtc: null,
  );
}

Future<void> _updateAssessmentRun(
  AppDatabase database,
  String column,
  Object value,
) async {
  await database.customUpdate(
    'UPDATE assessment_runs SET "$column" = ? WHERE id = ?',
    variables: [
      if (value is int)
        Variable<int>(value)
      else
        Variable<String>(value as String),
      const Variable<String>('target-assessment-run'),
    ],
  );
}

Future<void> _seedGuestOnlyAssessmentEvidence(AppDatabase database) async {
  final assignment = await database
      .customSelect(
        'SELECT id FROM experiment_assignments WHERE owner_id = ?',
        variables: const [Variable<String>('guest-owner')],
      )
      .map((row) => row.read<String>('id'))
      .getSingle();
  final context = EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.assessment,
    skillId: 'guest-assessment-word',
    hintLevel: 0,
    contentRevision: 'assessment-content-r1',
    rolloutMode: EvidencePolicyRolloutMode.enforced,
    protocolId: 'assessment-protocol',
    protocolVersion: 'assessment-protocol-v1',
    experimentId: 'assessment-study',
    experimentVersion: 1,
    assignmentId: assignment,
    cohort: 'enforced-a',
    researchConsentVersion: 1,
    instrumentId: 'vocabulary-outcome',
    instrumentVersion: '1.0.0',
    formId: 'form-a',
    formVersion: '1.0.0',
    assessmentItemId: 'item-1',
    assessmentResponseCode: 'choice-a',
    scoringRuleVersion: 'binary-v1',
    engagementAllowed: false,
  );
  await database.customInsert(
    'INSERT INTO vocabulary_categories '
    '(id, owner_id, name, normalized_name, created_at_utc_ms, '
    'updated_at_utc_ms) VALUES '
    "('guest-assessment-category', 'guest-owner', 'Assessment', "
    "'assessment', 30, 30)",
  );
  await database.customInsert(
    'INSERT INTO vocabulary_words '
    '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
    'normalized_meaning, part_of_speech, created_at_utc_ms, '
    'updated_at_utc_ms) VALUES '
    "('guest-assessment-word', 'guest-owner', 'guest-assessment-category', "
    "'word', 'word', 'meaning', 'meaning', 'noun', 30, 30)",
  );
  await database.customInsert(
    'INSERT INTO answer_attempts '
    '(id, owner_id, session_id, word_id, prompt_mode, is_correct, '
    'response_time_ms, attempt_number, occurred_at_utc_ms, evidence_class, '
    'evidence_context_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>('guest-assessment-evidence'),
      const Variable<String>('guest-owner'),
      const Variable<String>('guest-assessment-session'),
      const Variable<String>('guest-assessment-word'),
      const Variable<String>('meaningChoice'),
      const Variable<bool>(true),
      const Variable<int>(50),
      const Variable<int>(1),
      const Variable<int>(31),
      const Variable<String>('assessment'),
      Variable<String>(jsonEncode(context.toJson())),
    ],
  );
}

Future<Map<String, Object?>> _assessmentRunSnapshot(
  AppDatabase database,
  String id,
) {
  return database
      .customSelect(
        'SELECT * FROM assessment_runs WHERE id = ?',
        variables: [Variable<String>(id)],
      )
      .map((row) => row.data)
      .getSingle();
}

Future<List<Map<String, Object?>>> _assessmentRunsForOwner(
  AppDatabase database,
  String ownerId,
) {
  return database
      .customSelect(
        'SELECT * FROM assessment_runs WHERE owner_id = ? ORDER BY id',
        variables: [Variable<String>(ownerId)],
      )
      .map((row) => row.data)
      .get();
}

Future<List<String>> _assessmentRunInventory(AppDatabase database) async {
  final rows = await database
      .customSelect('SELECT * FROM assessment_runs ORDER BY id')
      .get();
  return rows.map((row) => row.data.toString()).toList(growable: false);
}

Future<void> _putResearchConsent(
  AppDatabase database, {
  required String ownerId,
  required int consentVersion,
  int decidedAtUtcMs = 1723622400000,
}) {
  return database.customInsert(
    'INSERT INTO research_consents '
    '(id, owner_id, consent_version, consent_state, decided_at_utc_ms, '
    'withdrawn_at_utc_ms) VALUES (?, ?, ?, ?, ?, NULL)',
    variables: [
      Variable<String>('consent:$ownerId:$consentVersion'),
      Variable<String>(ownerId),
      Variable<int>(consentVersion),
      const Variable<String>('accepted'),
      Variable<int>(decidedAtUtcMs),
    ],
  );
}

EvidenceContext _assignmentEvidence(
  ExperimentAssignment assignment, {
  required int consentVersion,
}) {
  return EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.independentRecall,
    skillId: 'meaning-recall',
    hintLevel: 0,
    contentRevision: 'content-v1',
    rolloutMode: EvidencePolicyRolloutMode.shadow,
    protocolId: 'study-protocol',
    protocolVersion: assignment.protocolVersion,
    experimentId: assignment.experimentId,
    experimentVersion: assignment.experimentVersion,
    assignmentId: assignment.id,
    cohort: assignment.cohort,
    researchConsentVersion: consentVersion,
    engagementAllowed: true,
  );
}

Future<List<OutboxOperation>> _experimentAssignmentOutbox(
  AppDatabase database,
) {
  return (database.select(database.outboxOperations)..where(
        (row) => row.entityType.equals(
          SyncCollection.experimentAssignments.entityType,
        ),
      ))
      .get();
}

Future<List<String>> _experimentAssignmentOutboxSnapshot(
  AppDatabase database,
) async {
  final rows = await _experimentAssignmentOutbox(database);
  return rows
      .map(
        (row) => <Object?>[
          row.operationId,
          row.ownerId,
          row.entityType,
          row.entityId,
          row.operationKind,
          row.payloadVersion,
          row.baseRevision,
          row.state,
          row.createdAtUtcMs,
        ].join('|'),
      )
      .toList(growable: false)
    ..sort();
}

Future<int> _experimentAssignmentCount(
  AppDatabase database, {
  required String ownerId,
}) async {
  final row = await database
      .customSelect(
        'SELECT COUNT(*) AS count FROM experiment_assignments WHERE owner_id = ?',
        variables: [Variable<String>(ownerId)],
      )
      .getSingle();
  return row.read<int>('count');
}

Future<void> _seedOwners(AppDatabase database) async {
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
    "VALUES ('guest-owner', NULL, 'localGuest', 1, 1)",
  );
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
    "VALUES ('account-owner', 'firebase-user', 'firebaseBound', 2, 0)",
  );
}

Future<void> _seedEveryOwnerScopedTable(AppDatabase database) async {
  final assignmentId =
      DriftExperimentAssignmentRepository.canonicalAssignmentId(
        ownerId: 'guest-owner',
        experimentId: 'research-assessment',
        experimentVersion: 1,
      );
  await database.customInsert(
    'INSERT INTO experiment_assignments '
    '(id, owner_id, experiment_id, experiment_version, cohort, '
    'protocol_version, assigned_at_utc_ms) VALUES '
    "(?, 'guest-owner', 'research-assessment', 1, 'treatment-a', "
    "'2026.08', 1723651200000)",
    variables: [Variable<String>(assignmentId)],
  );
  await database.customInsert(
    "INSERT INTO research_consents VALUES "
    "('consent-1', 'guest-owner', 1, 'accepted', 10, NULL)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_categories "
    "(id, owner_id, name, normalized_name, sort_order, local_revision, "
    "cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) "
    "VALUES ('category-1', 'guest-owner', 'Travel', 'travel', 0, 1, 0, 0, 10, 10)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_words "
    "(id, owner_id, category_id, spelling, normalized_spelling, meaning, "
    "normalized_meaning, part_of_speech, source, is_global, local_revision, "
    "cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) "
    "VALUES ('word-1', 'guest-owner', 'category-1', 'station', 'station', "
    "'สถานี', 'สถานี', 'noun', 'manual', 0, 1, 0, 0, 10, 10)",
  );
  await database.customInsert(
    'INSERT INTO saved_learning_items '
    '(id, owner_id, content_type, content_id, content_revision, '
    'saved_at_utc_ms, updated_at_utc_ms, local_revision, cloud_revision, '
    'is_deleted) VALUES '
    "('saved-1', 'guest-owner', 'lexicalMetadata', 'word-1', 1, "
    '10, 10, 1, 0, 0)',
  );
  await database.customInsert(
    'INSERT INTO content_quality_reports '
    '(id, owner_id, content_type, content_id, content_revision, '
    'reason_code, comment, submitted_at_utc_ms) VALUES '
    "('report-1', 'guest-owner', 'lexicalMetadata', 'word-1', 1, "
    "'incorrectMeaning', NULL, 10)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_imports VALUES "
    "('import-1', 'guest-owner', 'category-1', 'csv', 'travel.csv', "
    "'hash-1', 'complete', 1, 0, 0, 10, 11)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_import_rows VALUES "
    "('import-row-1', 'import-1', 1, 'row-hash-1', 'accepted', NULL, 'word-1')",
  );
  await database.customInsert(
    "INSERT INTO learning_sessions (id, owner_id, activity_type, state, "
    "started_at_utc_ms, ended_at_utc_ms, correct_count, wrong_count, score, "
    "app_version, build_id) VALUES "
    "('session-1', 'guest-owner', 'quiz', 'completed', 10, 20, 1, 0, 100, '1', '1')",
  );
  final learningTimeSegmentId = LearningTimeSegment.canonicalId(
    sessionId: 'session-1',
    activeStartOffsetMs: 0,
    captureSource: LearningTimeCaptureSource.automaticLesson,
  );
  await database.customInsert(
    'INSERT INTO learning_time_segments '
    '(id, owner_id, session_id, active_start_offset_ms, active_duration_ms, '
    'started_at_utc_ms, ended_at_utc_ms, timezone_id, '
    'timezone_offset_minutes, capture_source) VALUES '
    "(?, 'guest-owner', 'session-1', 0, 10, 10, 20, 'Asia/Bangkok', 420, "
    "'automaticLesson')",
    variables: [Variable<String>(learningTimeSegmentId)],
  );
  await database.customInsert(
    'INSERT INTO learning_goals '
    '(id, owner_id, kind, title, deadline_at_utc_ms, timezone_id, '
    'timezone_offset_minutes, status, created_at_utc_ms, updated_at_utc_ms) '
    "VALUES ('goal-1', 'guest-owner', 'languageTest', "
    "'IELTS practice target', 1788238800000, 'Asia/Bangkok', 420, "
    "'active', 10, 10)",
  );
  await database.customInsert(
    'INSERT INTO study_reminders '
    '(id, owner_id, goal_id, source_kind, scheduled_at_utc_ms, timezone_id, '
    'timezone_offset_minutes, is_enabled, created_at_utc_ms, '
    'updated_at_utc_ms) '
    "VALUES ('reminder-1', 'guest-owner', 'goal-1', 'goalDeadline', "
    "1788152400000, 'Asia/Bangkok', 420, 0, 10, 10)",
  );
  await _seedCompleteInventoryAssessmentRun(
    database,
    runId: 'assessment-inventory-run',
    ownerId: 'guest-owner',
    learningSessionId: 'session-1',
    assignmentId: assignmentId,
  );
  await database.customInsert(
    'INSERT INTO answer_attempts '
    '(id, owner_id, session_id, word_id, prompt_mode, is_correct, '
    'response_time_ms, attempt_number, occurred_at_utc_ms, '
    'provider_provenance) VALUES '
    "('attempt-1', 'guest-owner', 'session-1', 'word-1', 'meaning', 1, "
    '100, 1, 15, NULL)',
  );
  await database.customInsert(
    "INSERT INTO srs_states VALUES "
    "('srs-1', 'guest-owner', 'word-1', 1, 1, 1, 1, 0, 15, 30, 1)",
  );
  await database.customInsert(
    "INSERT INTO reading_progress_entries VALUES "
    "('reading-progress-1', 'guest-owner', 'doc-1', 1, 5, 0, 20)",
  );
  await database.customInsert(
    "INSERT INTO reading_events VALUES "
    "('reading-event-1', 'guest-owner', 'doc-1', 1, 'position', 5, 20)",
  );
  await database.customInsert(
    "INSERT INTO points_ledger_entries VALUES "
    "('points-1', 'guest-owner', 'answer:1', 'quizCorrect', 200, NULL, 20)",
  );
  await database.customInsert(
    "INSERT INTO achievement_unlocks VALUES "
    "('achievement-1', 'guest-owner', 'first-answer', 1, 'attempt-1', 20)",
  );
  await database.customInsert(
    "INSERT INTO reward_transactions VALUES "
    "('reward-1', 'guest-owner', 'reward-key-1', 'purchase', -80, "
    "'theme_ocean', 1, NULL, 20)",
  );
  await database.customInsert(
    "INSERT INTO reward_transactions VALUES "
    "('reward-equip-1', 'guest-owner', 'reward-equip-key-1', 'equip', 0, "
    "'theme_ocean', 1, NULL, 21)",
  );
  await database.customInsert(
    "INSERT INTO owned_reward_items VALUES "
    "('owned-1', 'guest-owner', 'theme_ocean', 1, 'reward-1', 20)",
  );
  await database.customInsert(
    "INSERT INTO equipped_reward_items VALUES "
    "('equipped-1', 'guest-owner', 'theme', 'theme_ocean', 20)",
  );
  await database.customInsert(
    "INSERT INTO outbox_operations "
    "(operation_id, owner_id, entity_type, entity_id, operation_kind, "
    "created_at_utc_ms) VALUES "
    "('operation-1', 'guest-owner', 'word', 'word-1', 'upsert', 20)",
  );
  await database.customInsert(
    "INSERT INTO outbox_operations "
    "(operation_id, owner_id, entity_type, entity_id, operation_kind, "
    "created_at_utc_ms) VALUES "
    "('attempt:attempt-1:1', 'guest-owner', 'attempt', 'attempt-1', "
    "'upsert', 20)",
  );
  await database.customInsert(
    "INSERT INTO outbox_operations "
    "(operation_id, owner_id, entity_type, entity_id, operation_kind, "
    "created_at_utc_ms) VALUES "
    "('readingEvent:reading-event-1:1', 'guest-owner', 'readingEvent', "
    "'reading-event-1', 'upsert', 20)",
  );
  await database.customInsert(
    "INSERT INTO sync_checkpoints VALUES "
    "('checkpoint-1', 'guest-owner', 'words', NULL, NULL)",
  );
  await database.customInsert(
    "INSERT INTO sync_conflicts "
    "(id, owner_id, entity_type, entity_id, local_revision, cloud_revision, "
    "resolution_policy, outcome, resolved_at_utc_ms) VALUES "
    "('conflict-1', 'guest-owner', 'word', 'word-1', 1, 2, "
    "'cloudWins', 'cloudApplied', 20)",
  );
  await database.customInsert(
    "INSERT INTO events_v2 "
    "(event_id, event_type, event_version, occurred_at_utc, recorded_at_utc, "
    "actor_identity, owner_id, aggregate_type, aggregate_id, idempotency_key, "
    "consent_context_json, app_version, build_id, privacy_classification, "
    "payload_json) VALUES "
    "('evt-seed-1', 'QuizCompleted', 1, '2026-08-04T10:00:00.000Z', "
    "'2026-08-04T10:00:01.000Z', 'guest-owner', 'guest-owner', "
    "'LearningSession', 'sess-1', 'idem-seed-1', '{}', "
    "'1.0.0', 'sha1', 'anonymized', '{}')",
  );
  // Phase 0 Week 10-11 — quest catalog row (no owner_id) + instance row.
  await database.customInsert(
    "INSERT INTO quest_definitions "
    "(quest_id, catalog_version, title, description, type, "
    "objectives_json, reward_json) VALUES "
    "('q-seed-1', 1, 'Seed Quest', 'Seed', 'daily', '[]', "
    "'{\"xpAmount\":10,\"rewardItemId\":null}')",
  );
  await database.customInsert(
    "INSERT INTO quest_instances "
    "(instance_id, quest_id, owner_id, catalog_version, "
    "assigned_at_utc_ms, state) VALUES "
    "('inst-seed-1', 'q-seed-1', 'guest-owner', 1, 20, 'active')",
  );
  // Phase 1 D7.2 — streak state and learning day log (owner-scoped).
  await database.customInsert(
    "INSERT INTO streak_states "
    "(owner_id, current_streak_days, longest_streak_days, freeze_count, "
    "updated_at_utc_ms) VALUES "
    "('guest-owner', 1, 1, 0, 20)",
  );
  await database.customInsert(
    "INSERT INTO learning_day_log "
    "(id, owner_id, learning_day, first_session_at_utc_ms) VALUES "
    "('day:guest-owner:2026-08-04', 'guest-owner', '2026-08-04', 20)",
  );
  // Phase 2 D8.3 — associative learning data (owner-scoped).
  await database.customInsert(
    "INSERT INTO association_records "
    "(id, owner_id, word_key, type, content, created_at_utc_ms) VALUES "
    "('assoc-seed-1', 'guest-owner', 'banana', 'keyword', 'yellow fruit', 20)",
  );
  await database.customInsert(
    "INSERT INTO associative_memory_states "
    "(id, owner_id, word_key, stability, difficulty, cue_dependency, "
    "lapse_count, next_due_at_utc_ms, algorithm_version) VALUES "
    "('ams-seed-1', 'guest-owner', 'banana', 1.0, 5.0, 0.0, "
    "0, 1722844800000, 'v1.0.0')",
  );
  // Schema v11 — speech evidence (owner-scoped).
  await database.customInsert(
    "INSERT INTO speech_evidence "
    "(id, owner_id, session_id, word_id, prompt_mode, target_content, "
    "recognized_transcript, locale, stt_engine, similarity_algorithm, "
    "similarity_score, is_exact_match, recognition_confidence, sample_size, "
    "occurred_at_utc_ms, duration_ms) VALUES "
    "('evidence-seed-1', 'guest-owner', 'session-1', 'word-1', 'meaning', "
    "'station', 'station', 'en-US', 'speech_to_text', 'levenshtein', "
    "100, 1, 0.95, 1, 20, 500)",
  );

  // Schema v12 — provider-neutral AI usage is owner-scoped.
  await database.customInsert(
    "INSERT INTO ai_usage_events "
    "(event_id, owner_id, occurred_at_utc_ms, provider_id, model, "
    "request_type, outcome, latency_ms) VALUES "
    "('ai-usage-seed-1', 'guest-owner', 20, 'gemini', 'model', "
    "'tutorReply', 'success', 10)",
  );
}

Future<void> _seedCompleteInventoryAssessmentRun(
  AppDatabase database, {
  required String runId,
  required String ownerId,
  required String learningSessionId,
  required String assignmentId,
}) async {
  final repository = DriftAssessmentRepository(database);
  final startedAtUtc = DateTime.fromMillisecondsSinceEpoch(
    1723651200010,
    isUtc: true,
  );
  await repository.start(
    AssessmentRun(
      id: runId,
      ownerId: ownerId,
      learningSessionId: learningSessionId,
      studyCycleId: 'inventory-assessment-cycle',
      phase: AssessmentPhase.pre,
      state: AssessmentRunState.active,
      protocolId: 'research-assessment-protocol',
      protocolVersion: '2026.08',
      experimentId: 'research-assessment',
      experimentVersion: 1,
      assignmentId: assignmentId,
      cohort: 'treatment-a',
      consentVersion: 1,
      consentDecidedAtUtc: DateTime.fromMillisecondsSinceEpoch(10, isUtc: true),
      instrumentId: 'vocabulary-outcome',
      instrumentVersion: '1.0.0',
      formId: 'inventory-form-a',
      formVersion: '1.0.0',
      instrumentChecksumSha256:
          '1111111111111111111111111111111111111111111111111111111111111111',
      formChecksumSha256:
          '2222222222222222222222222222222222222222222222222222222222222222',
      appVersion: '1.0.0',
      buildId: 'owner-inventory-fixture',
      databaseSchemaVersion: AppDatabase.currentSchemaVersion,
      contentRevision: 'assessment-content-r1',
      evidencePolicyVersion: EvidenceContext.currentPolicyVersion,
      featureContractRevision: currentFeatureContractIdentity.revision,
      featureContractHash: currentFeatureContractIdentity.semanticHash,
      startedAtUtc: startedAtUtc,
      completedAtUtc: null,
      abandonedAtUtc: null,
    ),
  );
  await repository.complete(
    runId: runId,
    completedAtUtc: startedAtUtc.add(const Duration(milliseconds: 10)),
  );
}

Future<void> _seedCollisionGraph(AppDatabase database) async {
  for (final values in [
    "('category-target', 'account-owner', 'Travel', 'travel', 0, 1, 0, 0, 1, 1)",
    "('category-guest', 'guest-owner', 'Travel', 'travel', 0, 1, 0, 0, 1, 1)",
  ]) {
    await database.customInsert(
      'INSERT INTO vocabulary_categories '
      '(id, owner_id, name, normalized_name, sort_order, local_revision, '
      'cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) '
      'VALUES $values',
    );
  }
  for (final values in [
    "('word-target', 'account-owner', 'category-target', 'station', 'station', "
        "'สถานี', 'สถานี', 'noun', 'manual', 0, 1, 0, 0, 1, 1)",
    "('word-guest', 'guest-owner', 'category-guest', 'station', 'station', "
        "'สถานี', 'สถานี', 'noun', 'manual', 0, 1, 0, 0, 1, 1)",
  ]) {
    await database.customInsert(
      'INSERT INTO vocabulary_words '
      '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
      'normalized_meaning, part_of_speech, source, is_global, local_revision, '
      'cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) '
      'VALUES $values',
    );
  }
  await database.customInsert(
    "INSERT INTO learning_sessions (id, owner_id, activity_type, state, "
    "started_at_utc_ms, ended_at_utc_ms, correct_count, wrong_count, score, "
    "app_version, build_id) VALUES "
    "('session-guest', 'guest-owner', 'quiz', 'completed', 1, 2, 1, 0, 1, '1', '1')",
  );
  await database.customInsert(
    'INSERT INTO answer_attempts '
    '(id, owner_id, session_id, word_id, prompt_mode, is_correct, '
    'response_time_ms, attempt_number, occurred_at_utc_ms, '
    'provider_provenance) VALUES '
    "('attempt-guest', 'guest-owner', 'session-guest', 'word-guest', "
    "'meaning', 1, 10, 1, 2, NULL)",
  );
  await database.customInsert(
    "INSERT INTO outbox_operations "
    "(operation_id, owner_id, entity_type, entity_id, operation_kind, "
    "created_at_utc_ms) VALUES "
    "('operation-guest', 'guest-owner', 'word', 'word-guest', 'upsert', 2)",
  );
}

Future<void> _seedProjectionCollisionGraph(AppDatabase database) async {
  await _seedCollisionGraph(database);
  await database.customInsert(
    "INSERT INTO learning_sessions (id, owner_id, activity_type, state, "
    "started_at_utc_ms, ended_at_utc_ms, correct_count, wrong_count, score, "
    "app_version, build_id) VALUES "
    "('session-target', 'account-owner', 'quiz', 'completed', 1, 2, 1, 0, 100, '1', '1')",
  );
  await database.customInsert(
    'INSERT INTO answer_attempts '
    '(id, owner_id, session_id, word_id, prompt_mode, is_correct, '
    'response_time_ms, attempt_number, occurred_at_utc_ms, '
    'provider_provenance) VALUES '
    "('attempt-target', 'account-owner', 'session-target', 'word-target', "
    "'meaning', 1, 10, 1, 1, NULL)",
  );
  await database.customInsert(
    "INSERT INTO srs_states VALUES "
    "('srs-target', 'account-owner', 'word-target', 1, 1, 1, 1, 0, 1, 2, 1)",
  );
  await database.customInsert(
    "INSERT INTO srs_states VALUES "
    "('srs-guest', 'guest-owner', 'word-guest', 1, 1, 1, 1, 0, 2, 3, 1)",
  );
  await database.customInsert(
    "INSERT INTO reading_progress_entries VALUES "
    "('reading-target', 'account-owner', 'shared-doc', 1, 5, 0, 1)",
  );
  await database.customInsert(
    "INSERT INTO reading_progress_entries VALUES "
    "('reading-guest', 'guest-owner', 'shared-doc', 1, 42, 1, 2)",
  );
  await database.customInsert(
    "INSERT INTO reading_events VALUES "
    "('reading-event-target', 'account-owner', 'shared-doc', 1, "
    "'position', 5, 1)",
  );
  await database.customInsert(
    "INSERT INTO reading_events VALUES "
    "('reading-event-guest', 'guest-owner', 'shared-doc', 1, "
    "'completed', 42, 2)",
  );
}

Future<int> _ownerCount(
  AppDatabase database,
  String table,
  String ownerId,
) async {
  final row = await database
      .customSelect(
        'SELECT COUNT(*) AS count FROM $table WHERE owner_id = ?',
        variables: [Variable<String>(ownerId)],
      )
      .getSingle();
  return row.read<int>('count');
}

Future<void> _insertLearningEvent(
  AppDatabase database, {
  required String ownerId,
  required String eventId,
  required DateTime occurredAt,
}) async {
  const sourcePrefix = 'learning-event:';
  if (!eventId.startsWith(sourcePrefix)) {
    throw ArgumentError.value(eventId, 'eventId', 'invalid learning event ID');
  }
  final attemptId = eventId.substring(sourcePrefix.length);
  final categoryId = 'category:$ownerId';
  final wordId = 'word:$ownerId';
  final sessionId = 'session:$ownerId';
  final context = LearningEvidenceContract.frozenV13LegacyEvidenceContext();
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: categoryId,
          ownerId: ownerId,
          name: 'Owner replay',
          normalizedName: 'owner replay',
          createdAtUtcMs: occurredAt.millisecondsSinceEpoch,
          updatedAtUtcMs: occurredAt.millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: wordId,
          ownerId: ownerId,
          categoryId: categoryId,
          spelling: 'replay',
          normalizedSpelling: 'replay',
          meaning: 'replay',
          normalizedMeaning: 'replay',
          partOfSpeech: 'noun',
          createdAtUtcMs: occurredAt.millisecondsSinceEpoch,
          updatedAtUtcMs: occurredAt.millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: sessionId,
          ownerId: ownerId,
          activityType: 'quiz',
          state: 'completed',
          startedAtUtcMs: occurredAt.millisecondsSinceEpoch,
          appVersion: '1.0.0',
          buildId: 'owner-upgrade-test',
        ),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: attemptId,
          ownerId: ownerId,
          sessionId: sessionId,
          wordId: wordId,
          promptMode: 'meaningChoice',
          isCorrect: true,
          attemptNumber: 1,
          occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
          evidenceClass: Value(context.evidenceClass.name),
          evidenceContextJson: Value(jsonEncode(context.toJson())),
        ),
      );
  await database
      .into(database.eventsV2)
      .insert(
        EventsV2Companion.insert(
          eventId: eventId,
          eventType: 'QuizCompleted',
          eventVersion: 1,
          occurredAtUtc: occurredAt,
          recordedAtUtc: occurredAt,
          actorIdentity: ownerId,
          ownerId: ownerId,
          aggregateType: 'LearningSession',
          aggregateId: sessionId,
          idempotencyKey: 'learning-attempt:$attemptId:v1',
          consentContextJson: '{}',
          appVersion: '1.0.0',
          buildId: 'owner-upgrade-test',
          privacyClassification: 'anonymized',
          payloadJson: jsonEncode(<String, dynamic>{'attemptId': attemptId}),
        ),
      );
}

LearningSideEffectReconciler _streakReconciler(
  AppDatabase database,
  StreakUseCases streak,
) => LearningSideEffectReconciler(
  database,
  streakSink: (event) async {
    final projection = await streak.projectEvent(event);
    return switch (projection.disposition) {
      StreakProjectionDisposition.applied => LearningProjectionResult.applied(
        payload: projection.payload,
      ),
      StreakProjectionDisposition.notApplicable =>
        LearningProjectionResult.notApplicable(
          payload: <String, dynamic>{'reasonCode': projection.reasonCode},
        ),
      StreakProjectionDisposition.blocked => LearningProjectionResult.blocked(
        reasonCode: projection.reasonCode!,
      ),
    };
  },
);

Future<EventEnvelopeV2> _insertCanonicalStreakEvent(
  AppDatabase database, {
  required String ownerId,
  required String attemptId,
  required DateTime occurredAt,
}) async {
  final categoryId = 'streak-category:$attemptId';
  final wordId = 'streak-word:$attemptId';
  final sessionId = 'streak-session:$attemptId';
  final context = EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.independentRecall,
    skillId: 'streak-skill',
    hintLevel: 0,
    contentRevision: 'streak-content-v1',
    rolloutMode: EvidencePolicyRolloutMode.legacy,
    engagementAllowed: true,
  );
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: categoryId,
          ownerId: ownerId,
          name: 'Streak replay $attemptId',
          normalizedName: 'streak replay $attemptId',
          createdAtUtcMs: occurredAt.millisecondsSinceEpoch,
          updatedAtUtcMs: occurredAt.millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: wordId,
          ownerId: ownerId,
          categoryId: categoryId,
          spelling: 'streak-$attemptId',
          normalizedSpelling: 'streak-$attemptId',
          meaning: 'streak',
          normalizedMeaning: 'streak',
          partOfSpeech: 'noun',
          createdAtUtcMs: occurredAt.millisecondsSinceEpoch,
          updatedAtUtcMs: occurredAt.millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: sessionId,
          ownerId: ownerId,
          activityType: 'quiz',
          state: 'completed',
          startedAtUtcMs: occurredAt.millisecondsSinceEpoch,
          appVersion: '1.0.0',
          buildId: 'owner-upgrade-streak-test',
        ),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: attemptId,
          ownerId: ownerId,
          sessionId: sessionId,
          wordId: wordId,
          promptMode: 'meaningChoice',
          isCorrect: true,
          attemptNumber: 1,
          occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
          evidenceClass: Value(context.evidenceClass.name),
          evidenceContextJson: Value(jsonEncode(context.toJson())),
        ),
      );
  final event = EventEnvelopeV2(
    eventId: LearningEvidenceContract.learningEventId(attemptId),
    eventType: 'QuizCompleted',
    eventVersion: 2,
    occurredAtUtc: occurredAt,
    recordedAtUtc: occurredAt,
    actorIdentity: ownerId,
    ownerIdentity: ownerId,
    aggregateType: 'LearningSession',
    aggregateId: sessionId,
    idempotencyKey: LearningEvidenceContract.learningAttemptIdempotencyKey(
      attemptId,
    ),
    consentContext: const ConsentContext.none(),
    contentRevision: context.contentRevision,
    policyVersion: context.policyVersion,
    appVersion: '1.0.0',
    buildId: 'owner-upgrade-streak-test',
    privacyClassification: PrivacyClassification.anonymized,
    payload: <String, dynamic>{
      'attemptId': attemptId,
      'wordId': wordId,
      'promptMode': 'meaningChoice',
      'correct': true,
      'score': 100,
      'attemptNumber': 1,
      'evidenceContext': context.toJson(),
    },
  );
  await DriftLearningEventStore(database).append(event);
  return event;
}

Future<void> _insertProjectionResult(
  AppDatabase database, {
  required String ownerId,
  required String sourceEventId,
  required String projection,
  required DateTime occurredAt,
  required Map<String, dynamic> result,
}) {
  final key = 'learning-projection:$projection:$sourceEventId:v1';
  return database
      .into(database.eventsV2)
      .insert(
        EventsV2Companion.insert(
          eventId: key,
          eventType: 'LearningProjectionApplied',
          eventVersion: 1,
          occurredAtUtc: occurredAt,
          recordedAtUtc: occurredAt,
          actorIdentity: ownerId,
          ownerId: ownerId,
          aggregateType: 'LearningProjection',
          aggregateId: sourceEventId,
          causationId: Value(sourceEventId),
          idempotencyKey: key,
          consentContextJson: '{}',
          appVersion: '1.0.0',
          buildId: 'owner-upgrade-test',
          privacyClassification: 'anonymized',
          payloadJson: jsonEncode({
            'sourceEventId': sourceEventId,
            'projection': projection,
            'appliedVersion': 1,
            'outcome': 'applied',
            'result': result,
          }),
        ),
      );
}

Future<void> _insertProjectionCursor(
  AppDatabase database, {
  required String ownerId,
  required String sourceEventId,
  required String projection,
  required DateTime occurredAt,
}) {
  final key = 'learning-projection-cursor:$ownerId:$projection:v1';
  return database
      .into(database.eventsV2)
      .insert(
        EventsV2Companion.insert(
          eventId: key,
          eventType: 'LearningProjectionCursor',
          eventVersion: 1,
          occurredAtUtc: occurredAt,
          recordedAtUtc: occurredAt,
          actorIdentity: ownerId,
          ownerId: ownerId,
          aggregateType: 'LearningProjectionCursor',
          aggregateId: sourceEventId,
          causationId: Value(sourceEventId),
          idempotencyKey: key,
          consentContextJson: '{}',
          appVersion: '1.0.0',
          buildId: 'owner-upgrade-test',
          privacyClassification: 'anonymized',
          payloadJson: jsonEncode({
            'sourceEventId': sourceEventId,
            'projection': projection,
            'appliedVersion': 1,
          }),
        ),
      );
}
