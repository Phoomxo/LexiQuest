import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/research/application/local_study_runtime.dart';
import 'package:vocab_learning_app/features/research/data/drift_study_archive_repository.dart';
import 'package:vocab_learning_app/features/research/data/local_research_authority_cache.dart';
import 'package:vocab_learning_app/features/research/domain/research_authority_snapshot.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';
import 'package:vocab_learning_app/features/research/domain/research_permit_json_codec.dart';
import 'package:vocab_learning_app/features/research/domain/research_transport_contracts.dart';
import 'package:vocab_learning_app/features/research/domain/study_archive.dart';
import 'package:vocab_learning_app/features/research/presentation/research_authority_screen.dart';
import 'package:vocab_learning_app/runtime/research_transport_composition.dart';

import '../../support/assessment_authority_harness.dart';
import '../../support/research_admission_signing.dart';
import '../../support/research_authority_cache_harness.dart';
import '../../support/research_transport_composition_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final configured in [false, true]) {
    test(
      configured
          ? 'configured unavailable Assessment cannot downgrade export to Motivation-only'
          : 'explicit Motivation-only runtime retains its authorized legacy export',
      () async {
        final source = await AuthorityCacheFixture.open();
        addTearDown(source.close);
        final run = (await source.study.baseline()).run!;
        source.cache.dispose();
        source.cache = LocalResearchAuthorityCache(
          ownerWrites: source.study.participation.ownerWrites,
          currentScope: () => source.scope,
          gateway: _SignedExportGateway(source),
          operationSignatures: source.study.authorities.operationSignatures,
          participationSignatures:
              source.study.authorities.participationSignatures,
          generateRequestId: () => 'synthetic-independent-export',
          maximumAcceptedAge: const Duration(minutes: 10),
          initiallyForeground: true,
          monotonicElapsed: () => source.elapsed,
        );
        source.bindRuntime();
        expect(await source.cache.refresh(), isTrue);
        final original = source.study.runtime;
        if (configured) {
          source.study.runtime = LocalStudyRuntime(
            context: original.context,
            authorities: original.authorities,
            catalog: original.catalog,
            assessmentFactory: () => null,
          );
          source.study.bindLearning();
          expect(
            (await source.study.runtime.load('owner-a')).phase.name,
            'unavailable',
          );
        }
        final repository = DriftStudyArchiveRepository(
          study: source.study.runtime,
          motivationAuthority: source.cache,
        );
        final before = await _rows(source.study.database);
        final prepared = repository.prepare(
          StudyArchiveTarget(expectedOwnerId: 'owner-a', studyCycleId: run.id),
          stillCurrent: () => true,
        );
        if (configured) {
          await expectLater(prepared, throwsA(isA<ExportException>()));
        } else {
          final payload = jsonDecode(
            utf8.decode((await prepared).artifact.bytes),
          );
          expect(payload['schema'], 'lexiquest.controlled-study-archive.v1');
          expect(payload['assessments'], isEmpty);
        }
        expect(await _rows(source.study.database), before);
      },
    );
  }

  testWidgets('a currently reviewed consent action reaches the server', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(_ConsentUiReview.open))!;
    try {
      await tester.pumpWidget(fixture.app());
      final action = await _review(tester);
      action();
      await _idle(tester);
      expect(fixture.harness.gateway.consentDecisions, 1);
      final rows = (await tester.runAsync(
        () => fixture.source.study.database
            .select(fixture.source.study.database.researchConsents)
            .get(),
      ))!;
      expect(rows.single.consentState, 'accepted');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(fixture.close);
    }
  });

  for (final change in ['notice', 'owner A-B-A']) {
    testWidgets('a retained consent action is retired after $change changes', (
      tester,
    ) async {
      final fixture = (await tester.runAsync(_ConsentUiReview.open))!;
      try {
        await tester.pumpWidget(fixture.app());
        final retained = await _review(tester);
        if (change == 'notice') {
          await tester.pumpWidget(fixture.app(changedNotice: true));
        } else {
          fixture.harness.setBinding(null);
          await tester.pump();
          fixture.harness.setBinding(
            ResearchAuthorityBinding(
              ownerId: 'owner-a',
              authSubjectId: 'uid-a',
              generation: 3,
            ),
          );
          await tester.pump();
        }
        await _idle(tester);
        final accept = find.byKey(const ValueKey('research-authority-accept'));
        expect(tester.widget<FilledButton>(accept).onPressed, isNull);
        expect(
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          isFalse,
        );
        retained();
        await _idle(tester);
        expect(fixture.harness.gateway.consentDecisions, 0);
        expect(
          (await tester.runAsync(
            () => fixture.source.study.database
                .select(fixture.source.study.database.researchConsents)
                .get(),
          ))!,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(fixture.close);
      }
    });
  }
}

Future<Map<String, List<Map<String, Object?>>>> _rows(
  AppDatabase database,
) async => {
  for (final table in database.allTables)
    table.actualTableName: [
      for (final row
          in await database
              .customSelect('SELECT * FROM "${table.actualTableName}"')
              .get())
        row.data,
    ],
};

Future<VoidCallback> _review(WidgetTester tester) async {
  await _idle(tester);
  final checkbox = find.byType(CheckboxListTile);
  expect(checkbox, findsOneWidget);
  await tester.ensureVisible(checkbox);
  await tester.tap(checkbox);
  await tester.pump();
  final accept = find.byKey(const ValueKey('research-authority-accept'));
  final callback = tester.widget<FilledButton>(accept).onPressed;
  expect(callback, isNotNull);
  return callback!;
}

Future<void> _idle(WidgetTester tester) async {
  for (var count = 0; count < 100; count++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) return;
  }
  fail('Synthetic independent consent action did not finish');
}

final class _ConsentUiReview {
  _ConsentUiReview(this.source, this.harness, this.composition);
  final AssessmentAuthorityFixture source;
  final SyntheticResearchCompositionHarness harness;
  final ResearchTransportComposition composition;

  static Future<_ConsentUiReview> open() async {
    final source = await AssessmentAuthorityFixture.open();
    await source.study.database
        .delete(source.study.database.researchConsents)
        .go();
    final harness = SyntheticResearchCompositionHarness(
      source: source,
      store: _NoWriteStore(),
    );
    final composition = await harness.create(
      ResearchTransportFactoryContext(
        study: source.study.runtime.context,
        baseUri: Uri.https('synthetic-research.invalid'),
      ),
    );
    return _ConsentUiReview(source, harness, composition);
  }

  Widget app({bool changedNotice = false}) => MaterialApp(
    home: ResearchAuthorityScreen(
      consent: composition.consent,
      authority: composition.lifecycle,
      notice: changedNotice
          ? SuppliedResearchConsentNotice(
              version: composition.notice!.version,
              protocolVersion: composition.notice!.protocolVersion,
              title: composition.notice!.title,
              body: '${composition.notice!.body} Changed supplied information.',
            )
          : composition.notice,
    ),
  );

  Future<void> close() async {
    await composition.dispose();
    await source.close();
  }
}

final class _NoWriteStore implements ExportArtifactStore {
  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
    required Future<void> Function() revalidateBeforeWrite,
  }) => throw StateError('The independent consent fixture never exports');
}

final class _SignedExportGateway implements ResearchAuthorityGateway {
  const _SignedExportGateway(this.fixture);
  final AuthorityCacheFixture fixture;

  @override
  Future<ServerAttestedResearchAuthorityPacket?> fetchCurrent(
    ResearchAuthorityRefreshRequest request,
  ) async {
    final original = fixture.gateway.build(request);
    final source = participationOperation();
    final permit = signAdmissionOperation(
      ResearchPermit(
        formatVersion: source.formatVersion,
        permitId: 'synthetic-independent-export',
        issuerId: source.issuerId,
        issuerKeyId: source.issuerKeyId,
        signatureAlgorithm: source.signatureAlgorithm,
        ownerId: source.ownerId,
        operation: ResearchOperation.export,
        assignmentId: source.assignmentId,
        assignmentRevision: source.assignmentRevision,
        protocolId: source.protocolId,
        protocolRevision: source.protocolRevision,
        instrumentId: source.instrumentId,
        instrumentRevision: source.instrumentRevision,
        revision: 1,
        issuedAtUtc: source.issuedAtUtc,
        expiresAtUtc: source.expiresAtUtc,
        signature: const [1],
      ),
    );
    return ServerAttestedResearchAuthorityPacket(
      scope: original.scope,
      requestId: original.requestId,
      clockSessionId: original.clockSessionId,
      monotonicEpoch: original.monotonicEpoch,
      snapshotRevision: original.snapshotRevision,
      anchorUtc: original.anchorUtc,
      ageAtObservation: original.ageAtObservation,
      observedAtMonotonic: original.observedAtMonotonic,
      validUntilUtc: original.validUntilUtc,
      maximumAge: original.maximumAge,
      operationDocuments: [const ResearchPermitJsonCodec().encode(permit)],
      operationStates: {
        permit.permitId: const ResearchPermitState(
          currentRevision: 1,
          revoked: false,
        ),
      },
      participationDocuments: original.participationDocuments,
      receipts: original.receipts,
    );
  }
}
