import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';
import 'package:vocab_learning_app/features/research/presentation/research_authority_screen.dart';
import 'package:vocab_learning_app/features/research/domain/research_authority_snapshot.dart';
import 'package:vocab_learning_app/features/research/domain/research_runtime_availability.dart';
import 'package:vocab_learning_app/features/research/domain/research_transport_contracts.dart';
import 'package:vocab_learning_app/runtime/configured_research_transport_factory.dart';
import 'package:vocab_learning_app/runtime/research_transport_composition.dart';

import '../support/assessment_writer_harness.dart';
import '../support/research_authority_cache_harness.dart';
import '../support/research_transport_wire.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final invalid in ['disabled', 'mismatched notice']) {
    test(
      '$invalid configuration creates no identity, HTTP or research rows',
      () async {
        final f = await _Fixture.open();
        addTearDown(f.close);
        final before = await f.rows();
        await expectLater(
          f
              .factory(
                enabled: invalid != 'disabled',
                mismatchedNotice: invalid == 'mismatched notice',
              )
              .create(f.context),
          invalid == 'disabled'
              ? throwsA(isA<StateError>())
              : throwsA(isA<ArgumentError>()),
        );
        expect(f.identities, 0);
        expect(f.clients, 0);
        expect(f.requests, 0);
        expect(f.learningReads, 0);
        expect(await f.rows(), before);
      },
    );
  }

  test(
    'failed HTTPS construction disposes exactly its owned resources',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await expectLater(
        f
            .factory(enabled: true)
            .create(
              ResearchTransportFactoryContext(
                study: f.context.study,
                baseUri: Uri.http('synthetic-research.invalid'),
              ),
            ),
        throwsA(isA<ArgumentError>()),
      );
      expect(f.identities, 1);
      expect(f.clients, 1);
      expect(f.identityDisposals, 1);
      expect(f.clientDisposals, 1);
      expect(f.requests, 0);
      expect(f.learningReads, 0);
    },
  );

  test(
    'real configured HTTP factory requires explicit pair refresh and activation',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final before = await f.rows();
      final composition = await f.factory(enabled: true).create(f.context);
      addTearDown(composition.dispose);
      composition.validate(f.context);
      expect(composition.studyRuntime.context, same(f.context.study));
      expect(
        composition.consent.repository,
        same(f.context.study.consentRepository),
      );
      expect(f.identities, 1);
      expect(f.clients, 1);
      expect(f.requests, 0);
      expect(f.tokens, 0);
      expect(f.learningReads, 0);
      expect(await f.rows(), before);
      final context = f.context.study;
      f.learning = LearningUseCases(
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
      final activation = composition.participationActivation!;
      expect(
        await activation.activate(
          expectedBinding: f.binding!,
          stillCurrent: () => true,
        ),
        isFalse,
      );
      expect(await f.rows(), before);
      expect(
        await composition.lifecycle.refresh(stillCurrent: () => true),
        isTrue,
      );
      expect(f.requests, 2);
      expect(f.tokens, 2);
      expect(await f.rows(), before);
      expect(
        await activation.activate(
          expectedBinding: f.binding!,
          stillCurrent: () => true,
        ),
        isTrue,
      );
      final after = await f.rows();
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
      expect(f.requests, 2);
      final originalAssessment = composition.studyRuntime.assessment!;
      f.permitId = 'synthetic-reissued-participation';
      final reissuedAssessment = composition.studyRuntime.assessment!;
      expect(reissuedAssessment, isNot(same(originalAssessment)));
      expect(
        (reissuedAssessment.repository as DriftAssessmentRepository)
            .participationPermitId,
        f.permitId,
      );
      f.permitId = null;
      expect(composition.studyRuntime.assessment, isNull);
      f.binding = null;
      f.changes.add(null);
      expect(composition.lifecycle.readGate.isOpen, isFalse);
      final first = composition.dispose();
      expect(composition.dispose(), same(first));
      await first;
      expect(f.identityDisposals, 1);
      expect(f.clientDisposals, 1);
      expect(await f.rows(), after);
    },
  );

  testWidgets(
    'actual authority controls refresh then explicitly activate local admission',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.open))!;
      ResearchTransportComposition? composition;
      try {
        final before = (await tester.runAsync(f.rows))!;
        composition = (await tester.runAsync(
          () => f.factory(enabled: true).create(f.context),
        ))!;
        final runtime = composition.studyRuntime;
        final context = f.context.study;
        f.learning = LearningUseCases(
          owners: context.owners,
          repository: DriftLearningRepository(
            context.database,
            ownerWrites: context.ownerWrites,
            lifecycleObserver: runtime.lifecycleObserver,
          ),
          generateId: context.generateId,
          nowUtc: context.nowUtc,
          buildInfo: context.buildInfo,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ResearchAuthorityScreen(
              consent: composition.consent,
              authority: composition.lifecycle,
              notice: composition.notice,
              participationActivation: composition.participationActivation,
            ),
          ),
        );
        final refresh = find.byKey(
          const ValueKey('research-authority-refresh'),
        );
        final activate = find.byKey(
          const ValueKey('research-authority-activate'),
        );
        await _until(
          tester,
          () =>
              activate.evaluate().isNotEmpty &&
              refresh.evaluate().isNotEmpty &&
              tester.widget<OutlinedButton>(refresh).onPressed != null,
        );
        expect(tester.widget<OutlinedButton>(activate).onPressed, isNull);
        expect(f.requests, 1);
        expect((await tester.runAsync(f.rows))!, before);
        await tester.ensureVisible(refresh);
        await tester.tap(refresh);
        await _until(
          tester,
          () =>
              find.text('ตรวจสิทธิ์ Study ปัจจุบันแล้ว').evaluate().isNotEmpty,
        );
        expect((await tester.runAsync(f.rows))!, before);
        expect(f.requests, 3);
        await tester.ensureVisible(activate);
        expect(tester.widget<OutlinedButton>(activate).onPressed, isNotNull);
        await tester.tap(activate);
        await _until(
          tester,
          () => find
              .text('เปิดใช้ Study ที่ได้รับสิทธิ์ในเครื่องแล้ว')
              .evaluate()
              .isNotEmpty,
        );
        final after = (await tester.runAsync(f.rows))!;
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
        expect(f.requests, 3);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        if (composition != null) await tester.runAsync(composition.dispose);
        await tester.runAsync(f.close);
      }
    },
  );
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var count = 0; count < 100; count++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (done()) return;
  }
  fail('Synthetic configured authority controls did not finish');
}

final class _Fixture {
  _Fixture(this.source);
  final AssessmentAuthorityFixture source;
  final changes = StreamController<ResearchAuthorityBinding?>.broadcast(
    sync: true,
  );
  ResearchAuthorityBinding? binding;
  String? permitId = 'synthetic-participation';
  late ResearchTransportFactoryContext context;
  late LearningUseCases learning;
  int learningReads = 0;
  int identities = 0;
  int clients = 0;
  int requests = 0;
  int tokens = 0;
  int identityDisposals = 0;
  int clientDisposals = 0;

  static Future<_Fixture> open() async {
    final f = _Fixture(await AssessmentAuthorityFixture.open());
    final old = f.source.study.runtime.context;
    await old.database.customStatement(
      'DELETE FROM research_participation_permits',
    );
    await old.database.customStatement('DELETE FROM experiment_assignments');
    f.binding = f.source.scope!.binding;
    f.context = ResearchTransportFactoryContext(
      baseUri: Uri.https('synthetic-research.invalid'),
      study: StudyRuntimeContext(
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
        getLearning: () {
          f.learningReads++;
          return f.learning;
        },
      ),
    );
    return f;
  }

  ConfiguredResearchTransportFactory factory({
    bool enabled = false,
    bool mismatchedNotice = false,
  }) {
    final template = source.study.authorities;
    final pins = source.study.participation.assignments.authorizer.requirements;
    return ConfiguredResearchTransportFactory(
      configuration: ResearchTransportConfiguration(
        binding: template.binding,
        catalog: source.study.catalog,
        assessmentDefinition: source.definition,
        assessmentMapping: source.mapping,
        assessmentContent: WriterContentAuthority(source, source.definition),
        operationSignatures: template.operationSignatures,
        participationSignatures: template.participationSignatures,
        trustedIssuerId: pins.trustedIssuerId,
        trustedIssuerKeyId: pins.trustedIssuerKeyId,
        notice: SuppliedResearchConsentNotice(
          version: mismatchedNotice ? 1 : 4,
          protocolVersion: template.binding.study.protocolVersion,
          title: 'Synthetic supplied notice',
          body: 'Synthetic engineering configuration; no production approval.',
        ),
        supportedPresentations: template.supportedPresentations,
        participationPermitId: (_) => permitId,
        availability: enabled
            ? ResearchRuntimeAvailability.syntheticComplete
            : ResearchRuntimeAvailability.disabled,
      ),
      createIdentity: (_) async {
        identities++;
        return ResearchTransportIdentityPorts(
          currentBinding: () => binding,
          bindingChanges: changes.stream,
          loadIdToken: (_) async {
            tokens++;
            return 'synthetic-test-token';
          },
          dispose: () async {
            identityDisposals++;
            await changes.close();
          },
        );
      },
      store: _NoWriteStore(),
      initiallyForeground: true,
      monotonicElapsed: () => Duration.zero,
      createHttpClient: () {
        clients++;
        return _TrackingClient((request) async {
          requests++;
          if (request.url.path == '/v1/research/enrollment-context') {
            final motivation = AuthorityCacheFixture(
              source.study,
            ).scopeFor('owner-a', 'uid-a', 1);
            return http.Response(
              jsonEncode({
                'schemaVersion': 1,
                'enrollmentId': 'synthetic-configured-enrollment',
                'ownerId': binding!.ownerId,
                'authSubjectId': binding!.authSubjectId,
                'consentVersion': motivation.consentVersion,
                'protocolVersion': motivation.protocolVersion,
                'scopes': [
                  {
                    'role': 'motivation',
                    'requirements': _requirements(motivation.requirements),
                  },
                  {
                    'role': 'assessment',
                    'requirements': _requirements(source.scope!.requirements),
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          expect(request.url.path, '/v1/research/authority/refresh');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final scopeJson = body['scope'] as Map<String, dynamic>;
          final requirements =
              scopeJson['requirements'] as Map<String, dynamic>;
          final isAssessment =
              requirements['instrumentId'] == source.definition.instrumentId;
          final motivation = AuthorityCacheFixture(source.study);
          final scope = isAssessment
              ? source.scope!
              : motivation.scopeFor('owner-a', 'uid-a', 1);
          final refresh = ResearchAuthorityRefreshRequest(
            scope: scope,
            requestId: body['requestId'] as String,
            clockSessionId: body['clockSessionId'] as String,
            monotonicEpoch: body['monotonicEpoch'] as int,
            startedAtMonotonic: Duration.zero,
            monotonicElapsed: () => Duration.zero,
          );
          final packet = isAssessment
              ? (await source.gateway.fetchCurrent(refresh))!
              : SyntheticAuthorityGateway(motivation).build(refresh);
          return http.Response(
            jsonEncode(researchAuthorityWire(packet, body['scope'])),
            200,
            headers: {'content-type': 'application/json'},
          );
        }, () => clientDisposals++);
      },
    );
  }

  Future<Map<String, List<Map<String, Object?>>>> rows() async => {
    for (final table in source.study.database.allTables)
      table.actualTableName:
          (await source.study.database
                  .customSelect('SELECT * FROM "${table.actualTableName}"')
                  .get())
              .map((row) => row.data)
              .toList(),
  };

  Future<void> close() async {
    if (!changes.isClosed) await changes.close();
    await source.close();
  }
}

Map<String, Object> _requirements(ResearchPermitRequirements value) => {
  'supportedFormatVersion': value.supportedFormatVersion,
  'trustedIssuerId': value.trustedIssuerId,
  'trustedIssuerKeyId': value.trustedIssuerKeyId,
  'signatureAlgorithm': value.signatureAlgorithm,
  'assignmentId': value.assignmentId,
  'assignmentRevision': value.assignmentRevision,
  'protocolId': value.protocolId,
  'protocolRevision': value.protocolRevision,
  'instrumentId': value.instrumentId,
  'instrumentRevision': value.instrumentRevision,
};

final class _TrackingClient extends MockClient {
  _TrackingClient(super.handler, this.onClose);
  final void Function() onClose;
  @override
  void close() {
    onClose();
    super.close();
  }
}

final class _NoWriteStore implements ExportArtifactStore {
  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
    required Future<void> Function() revalidateBeforeWrite,
  }) => throw StateError('Factory must not export automatically');
}
