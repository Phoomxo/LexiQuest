import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/research/application/assigned_learning_event_context_provider.dart';
import 'package:vocab_learning_app/features/research/application/experiment_assignment_use_cases.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/runtime/registries/consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/drift_consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/experiment_registry.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';

void main() {
  late AppDatabase database;
  late DriftExperimentAssignmentRepository assignmentRepository;
  late DriftExperimentRegistry experimentRegistry;
  late DriftConsentRegistry consentRegistry;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    assignmentRepository = DriftExperimentAssignmentRepository(database);
    experimentRegistry = DriftExperimentRegistry(assignmentRepository);
    consentRegistry = DriftConsentRegistry(database);
    await _insertOwner(database, 'owner-a');
    await _insertOwner(database, 'owner-b');
    await _insertOwner(database, 'owner-c');
    await _insertOwner(database, 'owner-d');
    await _insertOwner(database, 'owner-e');
    await _insertOwner(database, 'owner-f');
    await _insertOwner(database, 'owner-g');
  });

  tearDown(() => database.close());

  group('persisted experiment registry', () {
    test('lookup returns the exact persisted experiment version', () async {
      final assignedAt = DateTime.utc(2026, 8, 14, 9);
      await assignmentRepository.assignIfAbsent(
        ownerId: 'owner-a',
        experimentId: 'retrieval-policy',
        experimentVersion: 1,
        cohort: 'control-v1',
        protocolVersion: 'protocol-1',
        assignedAtUtc: assignedAt,
      );
      final expected = await assignmentRepository.assignIfAbsent(
        ownerId: 'owner-a',
        experimentId: 'retrieval-policy',
        experimentVersion: 2,
        cohort: 'intervention-v2',
        protocolVersion: 'protocol-2',
        assignedAtUtc: assignedAt.add(const Duration(minutes: 1)),
      );

      final assignment = await experimentRegistry.getAssignment(
        ownerId: 'owner-a',
        experimentId: 'retrieval-policy',
        experimentVersion: 2,
      );

      expect(assignment, expected);
      expect(assignment!.experimentVersion, 2);
      expect(assignment.cohort, 'intervention-v2');
      expect(
        await experimentRegistry.getAssignment(
          ownerId: 'owner-a',
          experimentId: 'retrieval-policy',
          experimentVersion: 3,
        ),
        isNull,
      );
      expect(await _assignmentCount(database), 2);
    });

    test('explicit no-op registry always returns unassigned', () async {
      const ExperimentRegistry registry = NoOpExperimentRegistry();

      expect(
        await registry.getAssignment(
          ownerId: 'owner-a',
          experimentId: 'any-experiment',
          experimentVersion: 1,
        ),
        isNull,
      );
      expect(
        await registry.getAssignment(
          ownerId: 'owner-b',
          experimentId: 'any-experiment',
          experimentVersion: 99,
        ),
        isNull,
      );
      expect(await _assignmentCount(database), 0);
    });

    test(
      'feature visibility and kill switches never assign a cohort',
      () async {
        final features = MutableFeatureRegistry();
        final runtimeFeatures = RuntimeFeatureRegistry(features);
        addTearDown(runtimeFeatures.dispose);

        features.enable(Feature.shadowRewardV2);
        expect(features.isVisible(Feature.shadowRewardV2), isTrue);
        expect(
          await experimentRegistry.getAssignment(
            ownerId: 'owner-a',
            experimentId: 'visibility-independent',
            experimentVersion: 1,
          ),
          isNull,
        );
        runtimeFeatures.emergencyOff(Feature.shadowRewardV2);
        expect(runtimeFeatures.isVisible(Feature.shadowRewardV2), isFalse);
        runtimeFeatures.clearOverride(Feature.shadowRewardV2);

        expect(await _assignmentCount(database), 0);
      },
    );
  });

  group('persisted consent snapshots', () {
    test('accepted requested research version is granted exactly', () async {
      final decidedAt = DateTime.utc(2026, 8, 14, 8);
      await _putConsent(
        database,
        ownerId: 'owner-a',
        version: 7,
        state: 'accepted',
        decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
      );

      final snapshot = await consentRegistry.snapshot(
        purpose: ConsentPurpose.researchDataUpload,
        ownerId: 'owner-a',
        consentVersion: 7,
      );

      expect(snapshot.purpose, ConsentPurpose.researchDataUpload);
      expect(snapshot.ownerId, 'owner-a');
      expect(snapshot.consentVersion, 7);
      expect(snapshot.state, ConsentState.granted);
      expect(snapshot.decisionUtc, decidedAt);
      expect(snapshot.decisionUtc!.isUtc, isTrue);
      expect(snapshot.withdrawalUtc, isNull);
    });

    test('declined and withdrawn research consent are denied', () async {
      final decidedAt = DateTime.utc(2026, 8, 14, 8);
      final withdrawnAt = decidedAt.add(const Duration(hours: 1));
      await _putConsent(
        database,
        ownerId: 'owner-a',
        version: 1,
        state: 'declined',
        decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
      );
      await _putConsent(
        database,
        ownerId: 'owner-b',
        version: 1,
        state: 'accepted',
        decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
        withdrawnAtUtcMs: withdrawnAt.millisecondsSinceEpoch,
      );

      final declined = await consentRegistry.snapshot(
        purpose: ConsentPurpose.researchDataUpload,
        ownerId: 'owner-a',
        consentVersion: 1,
      );
      final withdrawn = await consentRegistry.snapshot(
        purpose: ConsentPurpose.researchDataUpload,
        ownerId: 'owner-b',
        consentVersion: 1,
      );

      expect(declined.state, ConsentState.denied);
      expect(declined.decisionUtc, decidedAt);
      expect(declined.withdrawalUtc, isNull);
      expect(withdrawn.state, ConsentState.denied);
      expect(withdrawn.decisionUtc, decidedAt);
      expect(withdrawn.withdrawalUtc, withdrawnAt);
      expect(withdrawn.withdrawalUtc!.isUtc, isTrue);
    });

    test(
      'missing malformed and version-mismatched consent are unknown',
      () async {
        await _putConsent(
          database,
          ownerId: 'owner-a',
          version: 2,
          state: 'accepted',
          decidedAtUtcMs: -1,
        );
        await _putConsent(
          database,
          ownerId: 'owner-b',
          version: 3,
          state: 'accepted',
          decidedAtUtcMs: DateTime.utc(2026, 8, 14).millisecondsSinceEpoch,
        );

        final missing = await consentRegistry.snapshot(
          purpose: ConsentPurpose.researchDataUpload,
          ownerId: 'owner-c',
          consentVersion: 1,
        );
        final malformed = await consentRegistry.snapshot(
          purpose: ConsentPurpose.researchDataUpload,
          ownerId: 'owner-a',
          consentVersion: 2,
        );
        final wrongVersion = await consentRegistry.snapshot(
          purpose: ConsentPurpose.researchDataUpload,
          ownerId: 'owner-b',
          consentVersion: 4,
        );

        expect(missing.state, ConsentState.unknown);
        expect(missing.decisionUtc, isNull);
        expect(malformed.state, ConsentState.unknown);
        expect(malformed.decisionUtc, isNull);
        expect(wrongVersion.state, ConsentState.unknown);
        expect(wrongVersion.consentVersion, 4);
      },
    );

    test('unsupported consent purposes remain unknown', () async {
      await _putConsent(
        database,
        ownerId: 'owner-a',
        version: 5,
        state: 'accepted',
        decidedAtUtcMs: DateTime.utc(2026, 8, 14).millisecondsSinceEpoch,
      );

      for (final purpose in const [
        ConsentPurpose.aiProviderDataSharing,
        ConsentPurpose.personalDataExport,
      ]) {
        final snapshot = await consentRegistry.snapshot(
          purpose: purpose,
          ownerId: 'owner-a',
          consentVersion: 5,
        );
        expect(snapshot.purpose, purpose);
        expect(snapshot.ownerId, 'owner-a');
        expect(snapshot.consentVersion, 5);
        expect(snapshot.state, ConsentState.unknown);
        expect(snapshot.decisionUtc, isNull);
        expect(snapshot.withdrawalUtc, isNull);
      }
    });
  });

  group('consent-gated assignment and event context', () {
    test('assignment creation is explicit and consent-gated', () async {
      final decidedAt = DateTime.utc(2026, 8, 14, 8);
      final assignedAt = decidedAt.add(const Duration(minutes: 1));
      await _putConsent(
        database,
        ownerId: 'owner-a',
        version: 7,
        state: 'accepted',
        decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
      );
      final useCases = ExperimentAssignmentUseCases(
        repository: assignmentRepository,
        consentRegistry: consentRegistry,
      );

      expect(await _assignmentCount(database), 0);
      final assignment = await useCases.assignIfConsented(
        ownerId: 'owner-a',
        experimentId: 'explicit-assignment',
        experimentVersion: 2,
        cohort: 'intervention',
        protocolVersion: 'protocol-2',
        consentVersion: 7,
        assignedAtUtc: assignedAt,
      );

      expect(assignment, isNotNull);
      expect(assignment!.ownerId, 'owner-a');
      expect(assignment!.cohort, 'intervention');
      expect(assignment!.assignedAtUtc, assignedAt);
      expect(await _assignmentCount(database), 1);
    });

    test('withdrawn and unknown consent block new assignment', () async {
      final decidedAt = DateTime.utc(2026, 8, 14, 8);
      await _putConsent(
        database,
        ownerId: 'owner-a',
        version: 7,
        state: 'accepted',
        decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
        withdrawnAtUtcMs: decidedAt
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      );
      final useCases = ExperimentAssignmentUseCases(
        repository: assignmentRepository,
        consentRegistry: consentRegistry,
      );

      expect(
        await useCases.assignIfConsented(
          ownerId: 'owner-a',
          experimentId: 'blocked-withdrawn',
          experimentVersion: 1,
          cohort: 'intervention',
          protocolVersion: 'protocol-1',
          consentVersion: 7,
          assignedAtUtc: DateTime.utc(2026, 8, 14, 9),
        ),
        isNull,
      );
      expect(
        await useCases.assignIfConsented(
          ownerId: 'owner-b',
          experimentId: 'blocked-unknown',
          experimentVersion: 1,
          cohort: 'intervention',
          protocolVersion: 'protocol-1',
          consentVersion: 7,
          assignedAtUtc: DateTime.utc(2026, 8, 14, 9),
        ),
        isNull,
      );
      expect(await _assignmentCount(database), 0);
    });

    test('assigned granted owner yields immutable learning context', () async {
      final decidedAt = DateTime.utc(2026, 8, 14, 8);
      final assignedAt = decidedAt.add(const Duration(minutes: 1));
      final occurredAt = assignedAt.add(const Duration(minutes: 1));
      await _putConsent(
        database,
        ownerId: 'owner-a',
        version: 7,
        state: 'accepted',
        decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
      );
      final assignment = await assignmentRepository.assignIfAbsent(
        ownerId: 'owner-a',
        experimentId: 'context-experiment',
        experimentVersion: 2,
        cohort: 'intervention',
        protocolVersion: 'protocol-2',
        assignedAtUtc: assignedAt,
      );
      final provider = AssignedLearningEventContextProvider(
        experimentRegistry: experimentRegistry,
        consentRegistry: consentRegistry,
      );
      final evidence = _researchEvidence(assignment);

      final context = await provider.resolve(
        ownerId: 'owner-a',
        evidenceContext: evidence,
        occurredAtUtc: occurredAt,
      );

      expect(context.consentContext.researchConsentVersion, 7);
      expect(context.experimentContext!.experimentId, 'context-experiment');
      expect(context.experimentContext!.variantId, 'intervention');
      expect(context.experimentContext!.assignedAtUtc, assignedAt);
      expect(context.protocolId, 'study-protocol');
      expect(context.protocolVersion, 'protocol-2');
      expect(context.experimentVersion, 2);
      expect(context.assignmentId, assignment.id);
      context.validateAgainst(
        evidenceContext: evidence,
        occurredAtUtc: occurredAt,
      );
      expect(await _assignmentCount(database), 1);
    });

    test(
      'unassigned research context fails closed without assignment',
      () async {
        await _putConsent(
          database,
          ownerId: 'owner-a',
          version: 7,
          state: 'accepted',
          decidedAtUtcMs: DateTime.utc(2026, 8, 14, 8).millisecondsSinceEpoch,
        );
        final provider = AssignedLearningEventContextProvider(
          experimentRegistry: experimentRegistry,
          consentRegistry: consentRegistry,
        );
        final evidence = _researchEvidenceForMissingAssignment();

        await expectLater(
          provider.resolve(
            ownerId: 'owner-a',
            evidenceContext: evidence,
            occurredAtUtc: DateTime.utc(2026, 8, 14, 9),
          ),
          throwsStateError,
        );
        expect(await _assignmentCount(database), 0);
      },
    );

    test(
      'conflicting assignment metadata yields no research context',
      () async {
        final assignedAt = DateTime.utc(2026, 8, 14, 8, 1);
        await _putConsent(
          database,
          ownerId: 'owner-a',
          version: 7,
          state: 'accepted',
          decidedAtUtcMs: DateTime.utc(2026, 8, 14, 8).millisecondsSinceEpoch,
        );
        final assignment = await assignmentRepository.assignIfAbsent(
          ownerId: 'owner-a',
          experimentId: 'context-experiment',
          experimentVersion: 2,
          cohort: 'control',
          protocolVersion: 'protocol-2',
          assignedAtUtc: assignedAt,
        );
        final provider = AssignedLearningEventContextProvider(
          experimentRegistry: experimentRegistry,
          consentRegistry: consentRegistry,
        );
        final conflictingEvidence = _researchEvidence(
          assignment,
          cohort: 'intervention',
        );

        await expectLater(
          provider.resolve(
            ownerId: 'owner-a',
            evidenceContext: conflictingEvidence,
            occurredAtUtc: assignedAt.add(const Duration(minutes: 1)),
          ),
          throwsStateError,
        );
        expect(await _assignmentCount(database), 1);
      },
    );

    test('withdrawal blocks context without deleting assignment', () async {
      final decidedAt = DateTime.utc(2026, 8, 14, 8);
      final assignedAt = decidedAt.add(const Duration(minutes: 1));
      await _putConsent(
        database,
        ownerId: 'owner-a',
        version: 7,
        state: 'accepted',
        decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
      );
      final assignment = await assignmentRepository.assignIfAbsent(
        ownerId: 'owner-a',
        experimentId: 'context-experiment',
        experimentVersion: 2,
        cohort: 'intervention',
        protocolVersion: 'protocol-2',
        assignedAtUtc: assignedAt,
      );
      await _putConsent(
        database,
        ownerId: 'owner-a',
        version: 7,
        state: 'accepted',
        decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
        withdrawnAtUtcMs: assignedAt
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      );
      final provider = AssignedLearningEventContextProvider(
        experimentRegistry: experimentRegistry,
        consentRegistry: consentRegistry,
      );

      await expectLater(
        provider.resolve(
          ownerId: 'owner-a',
          evidenceContext: _researchEvidence(assignment),
          occurredAtUtc: assignedAt.add(const Duration(minutes: 2)),
        ),
        throwsStateError,
      );
      expect(await _assignmentCount(database), 1);
    });
  });

  group('persisted evidence policy rollout', () {
    test(
      'exact assignment consent and protocol mapping resolve the mapped mode',
      () async {
        final decidedAt = DateTime.utc(2026, 8, 14, 8);
        final assignedAt = decidedAt.add(const Duration(minutes: 1));
        await _putConsent(
          database,
          ownerId: 'owner-a',
          version: 7,
          state: 'accepted',
          decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
        );
        final assignment = await assignmentRepository.assignIfAbsent(
          ownerId: 'owner-a',
          experimentId: 'context-experiment',
          experimentVersion: 2,
          cohort: 'intervention',
          protocolVersion: 'protocol-2',
          assignedAtUtc: assignedAt,
        );
        final provider = _persistedRolloutProvider(
          experimentRegistry,
          consentRegistry,
        );

        final mode = await provider.resolve(
          ownerId: 'owner-a',
          evidenceContext: _researchEvidence(
            assignment,
            rolloutMode: EvidencePolicyRolloutMode.enforced,
          ),
        );

        expect(mode, EvidencePolicyRolloutMode.shadow);
        expect(await _assignmentCount(database), 1);
      },
    );

    test(
      'missing malformed conflicting unknown or non-granted state fails closed',
      () async {
        final decidedAt = DateTime.utc(2026, 8, 14, 8);
        final assignedAt = decidedAt.add(const Duration(minutes: 1));
        await _putConsent(
          database,
          ownerId: 'owner-a',
          version: 7,
          state: 'accepted',
          decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
        );
        final assignedA = await assignmentRepository.assignIfAbsent(
          ownerId: 'owner-a',
          experimentId: 'context-experiment',
          experimentVersion: 2,
          cohort: 'intervention',
          protocolVersion: 'protocol-2',
          assignedAtUtc: assignedAt,
        );
        await _putConsent(
          database,
          ownerId: 'owner-f',
          version: 7,
          state: 'accepted',
          decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
        );

        await _putConsent(
          database,
          ownerId: 'owner-b',
          version: 7,
          state: 'declined',
          decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
        );
        final assignedB = await assignmentRepository.assignIfAbsent(
          ownerId: 'owner-b',
          experimentId: 'context-experiment',
          experimentVersion: 2,
          cohort: 'intervention',
          protocolVersion: 'protocol-2',
          assignedAtUtc: assignedAt,
        );

        await _putConsent(
          database,
          ownerId: 'owner-c',
          version: 7,
          state: 'accepted',
          decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
          withdrawnAtUtcMs: assignedAt.millisecondsSinceEpoch,
        );
        final assignedC = await assignmentRepository.assignIfAbsent(
          ownerId: 'owner-c',
          experimentId: 'context-experiment',
          experimentVersion: 2,
          cohort: 'intervention',
          protocolVersion: 'protocol-2',
          assignedAtUtc: assignedAt,
        );

        await _putConsent(
          database,
          ownerId: 'owner-d',
          version: 7,
          state: 'accepted',
          decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
        );
        final assignedD = await assignmentRepository.assignIfAbsent(
          ownerId: 'owner-d',
          experimentId: 'context-experiment',
          experimentVersion: 2,
          cohort: 'intervention',
          protocolVersion: 'protocol-2',
          assignedAtUtc: assignedAt,
        );
        await database.customUpdate(
          'UPDATE experiment_assignments SET id = ? WHERE id = ?',
          variables: [
            const Variable<String>('conflicting-assignment-id'),
            Variable<String>(assignedD.id),
          ],
        );

        await _putConsent(
          database,
          ownerId: 'owner-e',
          version: 7,
          state: 'accepted',
          decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
        );
        final assignedE = await assignmentRepository.assignIfAbsent(
          ownerId: 'owner-e',
          experimentId: 'context-experiment',
          experimentVersion: 2,
          cohort: 'intervention',
          protocolVersion: 'protocol-2',
          assignedAtUtc: assignedAt,
        );
        await database.customUpdate(
          'UPDATE experiment_assignments SET protocol_version = ? '
          'WHERE id = ?',
          variables: [
            const Variable<String>(' protocol-2'),
            Variable<String>(assignedE.id),
          ],
        );
        final assignedG = await assignmentRepository.assignIfAbsent(
          ownerId: 'owner-g',
          experimentId: 'context-experiment',
          experimentVersion: 2,
          cohort: 'intervention',
          protocolVersion: 'protocol-2',
          assignedAtUtc: assignedAt,
        );

        final provider = _persistedRolloutProvider(
          experimentRegistry,
          consentRegistry,
        );
        final cases =
            <({String label, String ownerId, EvidenceContext context})>[
              (
                label: 'unassigned',
                ownerId: 'owner-f',
                context: _researchEvidenceForUnassignedOwner('owner-f'),
              ),
              (
                label: 'unknown protocol',
                ownerId: 'owner-a',
                context: _researchEvidence(
                  assignedA,
                  protocolVersion: 'protocol-unknown',
                ),
              ),
              (
                label: 'consent version mismatch',
                ownerId: 'owner-a',
                context: _researchEvidence(assignedA, consentVersion: 8),
              ),
              (
                label: 'declined',
                ownerId: 'owner-b',
                context: _researchEvidence(assignedB),
              ),
              (
                label: 'withdrawn',
                ownerId: 'owner-c',
                context: _researchEvidence(assignedC),
              ),
              (
                label: 'unknown consent',
                ownerId: 'owner-g',
                context: _researchEvidence(assignedG),
              ),
              (
                label: 'conflicting',
                ownerId: 'owner-d',
                context: _researchEvidence(assignedD),
              ),
              (
                label: 'malformed',
                ownerId: 'owner-e',
                context: _researchEvidence(assignedE),
              ),
            ];

        for (final entry in cases) {
          expect(
            await provider.resolve(
              ownerId: entry.ownerId,
              evidenceContext: entry.context,
            ),
            EvidencePolicyRolloutMode.legacy,
            reason: entry.label,
          );
        }
        expect(await _assignmentCount(database), 6);
      },
    );

    test(
      'feature visibility and kill switches cannot change persisted mode',
      () async {
        final decidedAt = DateTime.utc(2026, 8, 14, 8);
        final assignedAt = decidedAt.add(const Duration(minutes: 1));
        await _putConsent(
          database,
          ownerId: 'owner-a',
          version: 7,
          state: 'accepted',
          decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
        );
        final assignment = await assignmentRepository.assignIfAbsent(
          ownerId: 'owner-a',
          experimentId: 'context-experiment',
          experimentVersion: 2,
          cohort: 'intervention',
          protocolVersion: 'protocol-2',
          assignedAtUtc: assignedAt,
        );
        final provider = _persistedRolloutProvider(
          experimentRegistry,
          consentRegistry,
        );
        final evidence = _researchEvidence(assignment);
        final features = RuntimeFeatureRegistry(
          const BuildFeatureRegistry.allEnabled(),
        );
        addTearDown(features.dispose);

        expect(features.isVisible(Feature.shadowRewardV2), isTrue);
        expect(
          await provider.resolve(ownerId: 'owner-a', evidenceContext: evidence),
          EvidencePolicyRolloutMode.shadow,
        );
        features.emergencyOff(Feature.shadowRewardV2);
        expect(features.isEnabled(Feature.shadowRewardV2), isFalse);
        expect(
          await provider.resolve(ownerId: 'owner-a', evidenceContext: evidence),
          EvidencePolicyRolloutMode.shadow,
        );
        expect(await _assignmentCount(database), 1);
      },
    );

    test(
      'visible broad feature cannot activate an unassigned assessment',
      () async {
        final features = RuntimeFeatureRegistry(
          const BuildFeatureRegistry.allEnabled(),
        );
        addTearDown(features.dispose);
        final provider = _persistedRolloutProvider(
          experimentRegistry,
          consentRegistry,
        );
        final assessment = _missingAssessmentEvidence();

        expect(features.isVisible(Feature.shadowRewardV2), isTrue);
        expect(
          await provider.resolve(
            ownerId: 'owner-b',
            evidenceContext: assessment,
          ),
          EvidencePolicyRolloutMode.legacy,
        );
        await expectLater(
          AssignedLearningEventContextProvider(
            experimentRegistry: experimentRegistry,
            consentRegistry: consentRegistry,
          ).resolve(
            ownerId: 'owner-b',
            evidenceContext: assessment,
            occurredAtUtc: DateTime.utc(2026, 8, 14, 9),
          ),
          throwsStateError,
        );
        expect(await _assignmentCount(database), 0);
      },
    );

    test('resolved mode survives a file-backed close and reopen', () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-persisted-evidence-mode-',
      );
      final file = File('${directory.path}${Platform.pathSeparator}app.sqlite');
      AppDatabase? fileDatabase;
      try {
        fileDatabase = AppDatabase(NativeDatabase(file));
        await _insertOwner(fileDatabase, 'reopen-owner');
        final decidedAt = DateTime.utc(2026, 8, 14, 8);
        final assignedAt = decidedAt.add(const Duration(minutes: 1));
        await _putConsent(
          fileDatabase,
          ownerId: 'reopen-owner',
          version: 7,
          state: 'accepted',
          decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
        );
        final firstRepository = DriftExperimentAssignmentRepository(
          fileDatabase,
        );
        final assignment = await firstRepository.assignIfAbsent(
          ownerId: 'reopen-owner',
          experimentId: 'context-experiment',
          experimentVersion: 2,
          cohort: 'intervention',
          protocolVersion: 'protocol-2',
          assignedAtUtc: assignedAt,
        );
        final evidence = _researchEvidence(assignment);
        expect(
          await _persistedRolloutProvider(
            DriftExperimentRegistry(firstRepository),
            DriftConsentRegistry(fileDatabase),
          ).resolve(ownerId: 'reopen-owner', evidenceContext: evidence),
          EvidencePolicyRolloutMode.shadow,
        );
        await fileDatabase.close();

        fileDatabase = AppDatabase(NativeDatabase(file));
        final reopenedRepository = DriftExperimentAssignmentRepository(
          fileDatabase,
        );
        expect(
          await _persistedRolloutProvider(
            DriftExperimentRegistry(reopenedRepository),
            DriftConsentRegistry(fileDatabase),
          ).resolve(ownerId: 'reopen-owner', evidenceContext: evidence),
          EvidencePolicyRolloutMode.shadow,
        );
        expect(await _assignmentCount(fileDatabase), 1);
        expect(
          await fileDatabase
              .customSelect('SELECT COUNT(*) AS count FROM outbox_operations')
              .map((row) => row.read<int>('count'))
              .getSingle(),
          1,
        );
      } finally {
        await fileDatabase?.close();
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    });
  });
}

const _protocolModeCatalog = ResearchProtocolModeCatalog(
  mappings: <ResearchProtocolModeMapping>[
    ResearchProtocolModeMapping(
      protocolId: 'study-protocol',
      protocolVersion: 'protocol-2',
      experimentId: 'context-experiment',
      experimentVersion: 2,
      consentVersion: 7,
      mode: EvidencePolicyRolloutMode.shadow,
    ),
  ],
);

PersistedEvidencePolicyRolloutModeProvider _persistedRolloutProvider(
  ExperimentRegistry experiments,
  ConsentRegistry consents,
) {
  return PersistedEvidencePolicyRolloutModeProvider(
    experimentRegistry: experiments,
    consentRegistry: consents,
    protocolModeCatalog: _protocolModeCatalog,
  );
}

EvidenceContext _researchEvidence(
  ExperimentAssignment assignment, {
  String? cohort,
  String protocolId = 'study-protocol',
  String? protocolVersion,
  int consentVersion = 7,
  EvidencePolicyRolloutMode rolloutMode = EvidencePolicyRolloutMode.shadow,
}) {
  return EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.independentRecall,
    skillId: 'vocabulary-recall',
    hintLevel: 0,
    contentRevision: 'content-v1',
    rolloutMode: rolloutMode,
    protocolId: protocolId,
    protocolVersion: protocolVersion ?? assignment.protocolVersion,
    experimentId: assignment.experimentId,
    experimentVersion: assignment.experimentVersion,
    assignmentId: assignment.id,
    cohort: cohort ?? assignment.cohort,
    researchConsentVersion: consentVersion,
    engagementAllowed: true,
  );
}

EvidenceContext _missingAssessmentEvidence() {
  return EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.assessment,
    skillId: 'assessment-vocabulary-recall',
    hintLevel: 0,
    contentRevision: 'assessment-content-v1',
    rolloutMode: EvidencePolicyRolloutMode.enforced,
    protocolId: 'study-protocol',
    protocolVersion: 'protocol-2',
    experimentId: 'missing-assessment-experiment',
    experimentVersion: 2,
    assignmentId: 'missing-assessment-assignment',
    cohort: 'intervention',
    researchConsentVersion: 7,
    instrumentId: 'instrument-1',
    instrumentVersion: '1',
    formId: 'form-a',
    formVersion: '1',
    assessmentItemId: 'item-1',
    assessmentResponseCode: 'correct',
    scoringRuleVersion: '1',
    engagementAllowed: false,
  );
}

EvidenceContext _researchEvidenceForMissingAssignment() {
  return EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.independentRecall,
    skillId: 'vocabulary-recall',
    hintLevel: 0,
    contentRevision: 'content-v1',
    rolloutMode: EvidencePolicyRolloutMode.shadow,
    protocolId: 'study-protocol',
    protocolVersion: 'protocol-2',
    experimentId: 'missing-experiment',
    experimentVersion: 2,
    assignmentId: 'missing-assignment',
    cohort: 'intervention',
    researchConsentVersion: 7,
    engagementAllowed: true,
  );
}

EvidenceContext _researchEvidenceForUnassignedOwner(String ownerId) {
  return EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.independentRecall,
    skillId: 'vocabulary-recall',
    hintLevel: 0,
    contentRevision: 'content-v1',
    rolloutMode: EvidencePolicyRolloutMode.shadow,
    protocolId: 'study-protocol',
    protocolVersion: 'protocol-2',
    experimentId: 'context-experiment',
    experimentVersion: 2,
    assignmentId: DriftExperimentAssignmentRepository.canonicalAssignmentId(
      ownerId: ownerId,
      experimentId: 'context-experiment',
      experimentVersion: 2,
    ),
    cohort: 'intervention',
    researchConsentVersion: 7,
    engagementAllowed: true,
  );
}

Future<void> _insertOwner(AppDatabase database, String ownerId) {
  return database.customInsert(
    'INSERT INTO local_owners(id, account_state, created_at_utc_ms) '
    'VALUES (?, ?, ?)',
    variables: [
      Variable<String>(ownerId),
      const Variable<String>('localGuest'),
      const Variable<int>(1),
    ],
  );
}

Future<void> _putConsent(
  AppDatabase database, {
  required String ownerId,
  required int version,
  required String state,
  required int decidedAtUtcMs,
  int? withdrawnAtUtcMs,
}) {
  final withdrawal = withdrawnAtUtcMs;
  return database.transaction(() async {
    await database.customStatement(
      'DELETE FROM research_consents '
      'WHERE owner_id = ? AND consent_version = ?',
      [ownerId, version],
    );
    await database.customInsert(
      'INSERT INTO research_consents('
      'id, owner_id, consent_version, consent_state, decided_at_utc_ms, '
      'withdrawn_at_utc_ms'
      ') VALUES (?, ?, ?, ?, ?, ${withdrawal == null ? 'NULL' : '?'})',
      variables: [
        Variable<String>('consent:$ownerId:$version'),
        Variable<String>(ownerId),
        Variable<int>(version),
        Variable<String>(state),
        Variable<int>(decidedAtUtcMs),
        if (withdrawal != null) Variable<int>(withdrawal),
      ],
    );
  });
}

Future<int> _assignmentCount(AppDatabase database) {
  return database
      .customSelect('SELECT COUNT(*) AS count FROM experiment_assignments')
      .map((row) => row.read<int>('count'))
      .getSingle();
}
