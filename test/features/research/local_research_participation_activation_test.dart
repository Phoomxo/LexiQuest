import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/research/application/local_research_participation_activation.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/features/research/domain/research_authority_snapshot.dart';
import 'package:vocab_learning_app/runtime/research_transport_composition.dart';

import '../../support/assessment_authority_harness.dart';
import '../../support/research_authority_cache_harness.dart';
import '../../support/research_participation_harness.dart'
    show AfterParticipationWrite;
import '../../support/research_transport_composition_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'explicit activation imports the real current pair without learning writes',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.close);
      final source = fixture.source;
      final composition = fixture.composition;
      final harness = fixture.harness;
      final activation = fixture.activation;
      expect(
        await composition.lifecycle.refresh(stillCurrent: () => true),
        isTrue,
      );
      expect(
        (await composition.studyRuntime.load('owner-a')).phase,
        StudyPhase.unavailable,
      );
      final before = await _rows(source);
      expect(
        await activation.activate(
          expectedBinding: harness.binding!,
          stillCurrent: () => true,
        ),
        isTrue,
      );
      final after = await _rows(source);
      expect(after['experiment_assignments'], hasLength(1));
      expect(after['research_participation_permits'], hasLength(1));
      for (final entry in before.entries) {
        if (!{
          'experiment_assignments',
          'research_participation_permits',
        }.contains(entry.key)) {
          expect(after[entry.key], entry.value, reason: entry.key);
        }
      }
      expect(
        (await composition.studyRuntime.load('owner-a')).phase,
        StudyPhase.baseline,
      );
      expect(
        await activation.activate(
          expectedBinding: harness.binding!,
          stillCurrent: () => true,
        ),
        isTrue,
      );
      expect(await _rows(source), after);
      expect(harness.gateway.enrollmentReads, 0);
      expect(harness.gateway.consentDecisions, 0);
      expect(harness.gateway.uploadWrites, 0);
    },
  );

  for (final denial in [
    'unrefreshed pair',
    'missing approved permit',
    'revoked Motivation collect',
    'revoked Assessment collect',
    'withdrawal',
    'foreign expected generation',
    'ambient transaction',
    'deletion fence',
  ]) {
    test('$denial cannot admit research rows', () async {
      final f = await _Fixture.open(
        permitId: denial == 'missing approved permit'
            ? null
            : 'synthetic-participation',
      );
      addTearDown(f.close);
      if (denial == 'revoked Motivation collect') {
        final gateway =
            f.composition.lifecycle.caches.first.gateway
                as SyntheticAuthorityGateway;
        gateway
          ..revoked = true
          ..stateRevision = 2
          ..snapshotRevision = 2;
      }
      if (denial == 'revoked Assessment collect') {
        f.source.gateway
          ..revoked = true
          ..revision = 2;
      }
      if (denial != 'unrefreshed pair') {
        expect(
          await f.composition.lifecycle.refresh(stillCurrent: () => true),
          isTrue,
        );
      }
      if (denial == 'withdrawal') {
        final local = await f.composition.consent.loadLocalStatus();
        expect(
          await f.composition.consent.withdraw(local, DateTime.utc(2030)),
          isTrue,
        );
      }
      if (denial == 'deletion fence') {
        await f.composition.studyRuntime.context.ownerWrites.beginDeletion(
          ownerId: 'owner-a',
          firebaseUid: 'uid-a',
          idempotencyKey: 'synthetic-activation-deletion',
        );
      }
      final before = await _rows(f.source);
      final enrollmentReadsBeforeActivation = f.harness.gateway.enrollmentReads;
      final uploadWritesBeforeActivation = f.harness.gateway.uploadWrites;
      Future<bool> action() => f.activation.activate(
        expectedBinding: denial == 'foreign expected generation'
            ? ResearchAuthorityBinding(
                ownerId: 'owner-a',
                authSubjectId: 'uid-a',
                generation: 99,
              )
            : f.harness.binding!,
        stillCurrent: () => true,
      );
      expect(
        denial == 'ambient transaction'
            ? await f.source.study.database.transaction(action)
            : await action(),
        isFalse,
      );
      expect(await _rows(f.source), before);
      expect(
        f.harness.gateway.enrollmentReads,
        enrollmentReadsBeforeActivation,
      );
      expect(f.harness.gateway.uploadWrites, uploadWritesBeforeActivation);
    });
  }

  for (final retirement in ['caller', 'owner A-B-A']) {
    test(
      '$retirement retirement after participation INSERT rolls back admission',
      () async {
        final f = await _Fixture.open();
        addTearDown(f.close);
        expect(
          await f.composition.lifecycle.refresh(stillCurrent: () => true),
          isTrue,
        );
        final before = await _rows(f.source);
        final originalBinding = f.harness.binding!;
        var current = true;
        final interceptor = AfterParticipationWrite()
          ..afterWrite = () async {
            if (retirement == 'caller') {
              current = false;
            } else {
              f.harness.setBinding(null);
              f.harness.setBinding(
                ResearchAuthorityBinding(
                  ownerId: originalBinding.ownerId,
                  authSubjectId: originalBinding.authSubjectId,
                  generation: originalBinding.generation + 2,
                ),
              );
            }
          };
        final result = await f.source.study.database.runWithInterceptor(
          () => f.activation.activate(
            expectedBinding: originalBinding,
            stillCurrent: () => current,
          ),
          interceptor: interceptor,
        );
        expect(interceptor.didFire, isTrue);
        expect(result, isFalse);
        expect(await _rows(f.source), before);
        current = true;
        if (retirement != 'caller') {
          expect(f.composition.lifecycle.readGate.isOpen, isFalse);
          expect(
            await f.composition.lifecycle.refresh(stillCurrent: () => true),
            isTrue,
          );
        }
        expect(
          await f.activation.activate(
            expectedBinding: f.harness.binding!,
            stillCurrent: () => true,
          ),
          isTrue,
        );
        final after = await _rows(f.source);
        expect(after['experiment_assignments'], hasLength(1));
        expect(after['research_participation_permits'], hasLength(1));
      },
    );
  }
}

final class _Fixture {
  _Fixture(this.source, this.harness, this.composition, this.activation);
  final AssessmentAuthorityFixture source;
  final SyntheticResearchCompositionHarness harness;
  final ResearchTransportComposition composition;
  final LocalResearchParticipationActivation activation;

  static Future<_Fixture> open({
    String? permitId = 'synthetic-participation',
  }) async {
    final source = await AssessmentAuthorityFixture.open();
    final old = source.study.runtime.context;
    await old.database.customStatement(
      'DELETE FROM research_participation_permits',
    );
    await old.database.customStatement('DELETE FROM experiment_assignments');
    late LearningUseCases learning;
    final context = StudyRuntimeContext(
      database: old.database,
      owners: old.owners,
      ownerWrites: old.ownerWrites,
      consentRepository: DriftResearchConsentRepository(
        old.database,
        ownerWrites: old.ownerWrites,
      ),
      generateId: old.generateId,
      nowUtc: old.nowUtc,
      buildInfo: old.buildInfo,
      getLearning: () => learning,
    );
    final harness = SyntheticResearchCompositionHarness(
      source: source,
      store: _NoWriteStore(),
    );
    final composition = await harness.create(
      ResearchTransportFactoryContext(
        study: context,
        baseUri: Uri.https('synthetic-research.invalid'),
      ),
    );
    learning = LearningUseCases(
      owners: context.owners,
      repository: DriftLearningRepository(
        context.database,
        ownerWrites: context.ownerWrites,
        lifecycleObserver: composition.studyRuntime.lifecycleObserver,
      ),
      generateId: context.generateId,
      nowUtc: context.nowUtc,
      buildInfo: context.buildInfo,
    );
    final activation = LocalResearchParticipationActivation(
      study: composition.studyRuntime,
      lifecycle: composition.lifecycle,
      participationPermitId: (_) => permitId,
    );
    return _Fixture(source, harness, composition, activation);
  }

  Future<void> close() async {
    await composition.dispose();
    await source.close();
  }
}

Future<Map<String, List<Map<String, Object?>>>> _rows(
  AssessmentAuthorityFixture source,
) async => {
  for (final table in source.study.database.allTables)
    table.actualTableName:
        (await source.study.database
                .customSelect('SELECT * FROM "${table.actualTableName}"')
                .get())
            .map((row) => row.data)
            .toList(),
};

final class _NoWriteStore implements ExportArtifactStore {
  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
    required Future<void> Function() revalidateBeforeWrite,
  }) => throw StateError('Activation must not export');
}
