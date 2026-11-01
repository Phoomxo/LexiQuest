import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/features/research/domain/research_runtime_availability.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/research_transport_composition.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';
import 'package:vocab_learning_app/screens/export_center_screen.dart';
import 'package:vocab_learning_app/features/research/presentation/research_authority_screen.dart';
import 'package:vocab_learning_app/features/research/presentation/study_archive_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/assessment_authority_harness.dart';
import '../support/research_transport_composition_harness.dart';
import '../support/populated_owner_migration_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });
  test('disabled Research never invokes its transport factory', () async {
    var calls = 0;
    final dependencies = await _bootstrap(
      factory: (_) async {
        calls++;
        throw StateError('synthetic factory must stay disabled');
      },
    ).initialize();
    addTearDown(dependencies.dispose);
    expect(calls, 0);
    expect(dependencies.researchTransport, isNull);
    expect(dependencies.studyUploads, isNull);
    expect(dependencies.learning, isNotNull);
  });

  test(
    'failed enabled transport isolates Research without a legacy fallback',
    () async {
      var calls = 0;
      var legacyCalls = 0;
      final dependencies = await _bootstrap(
        availability: ResearchRuntimeAvailability.syntheticComplete,
        factory: (context) async {
          calls++;
          expect(context.study.database.schemaVersion, 23);
          expect(context.baseUri, Uri.parse('https://ai.example.com'));
          throw StateError('synthetic missing trusted configuration');
        },
        legacy: (_) {
          legacyCalls++;
          throw StateError('legacy must not replace a failed transport');
        },
      ).initialize();
      addTearDown(dependencies.dispose);
      expect(calls, 1);
      expect(legacyCalls, 0);
      expect(dependencies.researchTransport, isNull);
      expect(dependencies.studyRuntime, isNull);
      expect(dependencies.researchConsent, isNull);
      expect(dependencies.researchAvailability.isEnabled, isFalse);
      expect(dependencies.exports!.ownerWideResearchEnabled, isFalse);
      expect(dependencies.learning, isNotNull);
      expect(dependencies.learningPacks, isNotNull);
      expect(
        await dependencies.database!
            .select(dependencies.database!.researchConsents)
            .get(),
        isEmpty,
      );
      expect(
        await dependencies.database!
            .select(dependencies.database!.eventsV2)
            .get(),
        isEmpty,
      );
    },
  );

  test(
    'enabled transport shares the actual bootstrap learning writer',
    () async {
      final source = await AssessmentAuthorityFixture.open();
      final harness = SyntheticResearchCompositionHarness(
        source: source,
        store: _NoWriteStore(),
      );
      final dependencies = await _bootstrap(
        availability: ResearchRuntimeAvailability.syntheticComplete,
        factory: harness.create,
        database: source.study.database,
      ).initialize();
      addTearDown(() async {
        source.cache.dispose();
        await dependencies.dispose();
      });
      final composition = dependencies.researchTransport!;
      expect(harness.factoryCalls, 1);
      expect(harness.learningGetterCalls, 0);
      expect(dependencies.studyRuntime, same(composition.studyRuntime));
      expect(dependencies.studyArchives, same(composition.studyArchives));
      expect(dependencies.studyUploads, same(composition.studyUploads));
      expect(
        dependencies.researchConsent,
        same(composition.studyRuntime.consent),
      );
      expect(dependencies.exports!.ownerWideResearchEnabled, isFalse);
      final assessment = composition.studyRuntime.assessment!;
      final repository = assessment.repository as DriftAssessmentRepository;
      final reader = repository.cycleReader;
      expect(reader.learning, same(dependencies.learning!.repository));
      expect(reader.learning, isA<DriftLearningRepository>());
      expect(harness.gateway.enrollmentReads, 0);
      expect(harness.gateway.consentDecisions, 0);
      expect(harness.gateway.uploadWrites, 0);
      expect(composition.lifecycle.readGate.isOpen, isFalse);
      await dependencies.dispose();
      expect(harness.resourceDisposals, 1);
      expect(composition.lifecycle.readGate.isOpen, isFalse);
    },
  );

  for (final settings in [true, false]) {
    testWidgets(
      'actual ${settings ? 'Settings' : 'Export Center'} opens its scoped Study caller',
      (tester) async {
        final source = (await tester.runAsync(
          AssessmentAuthorityFixture.open,
        ))!;
        final harness = SyntheticResearchCompositionHarness(
          source: source,
          store: _NoWriteStore(),
        );
        final dependencies = (await tester.runAsync(
          () => _bootstrap(
            availability: ResearchRuntimeAvailability.syntheticComplete,
            factory: harness.create,
            database: source.study.database,
          ).initialize(),
        ))!;
        final before = (await tester.runAsync(
          () => ownerMigrationRows(source.study.database),
        ))!;
        try {
          await tester.pumpWidget(
            AppDependenciesScope(
              dependencies: dependencies,
              child: MaterialApp(
                home: settings
                    ? const SettingScreen()
                    : const ExportCenterScreen(),
              ),
            ),
          );
          final entry = find.byKey(
            ValueKey(
              settings
                  ? 'settings-research-authority'
                  : 'export-controlled-study',
            ),
          );
          await tester.scrollUntilVisible(
            entry,
            200,
            scrollable: find.byType(Scrollable).first,
            maxScrolls: 30,
          );
          await tester.tap(entry);
          await _until(
            tester,
            () => find
                .byType(settings ? ResearchAuthorityScreen : StudyArchiveScreen)
                .evaluate()
                .isNotEmpty,
          );
          if (settings) {
            await _until(
              tester,
              () => find
                  .byKey(const ValueKey('research-authority-accept'))
                  .evaluate()
                  .isNotEmpty,
            );
          }
          expect(harness.gateway.consentDecisions, 0);
          expect(harness.gateway.uploadWrites, 0);
          expect(
            (await tester.runAsync(
              () => ownerMigrationRows(source.study.database),
            ))!,
            before,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          source.cache.dispose();
          var closed = false;
          final closing = dependencies.dispose().whenComplete(
            () => closed = true,
          );
          await _until(tester, () => closed);
          await closing;
        }
      },
    );
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var index = 0; index < 150; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (ready()) return;
  }
  fail('Scoped Study caller did not become ready');
}

AppBootstrap _bootstrap({
  required ResearchTransportFactory factory,
  ResearchRuntimeAvailability availability =
      ResearchRuntimeAvailability.disabled,
  StudyRuntimeFactory? legacy,
  AppDatabase? database,
}) => AppBootstrap(
  initializeFirebase: () async {},
  initializeSupabase: () async {},
  loadConfig: () => AppConfig.fromValues(
    voiceApiUrl: 'https://voice.example.com',
    aiApiUrl: 'https://ai.example.com',
    isDebug: false,
  ),
  guestSessionService: _Guest(),
  createDatabase: () => database ?? AppDatabase(NativeDatabase.memory()),
  researchAvailability: availability,
  researchTransportFactory: factory,
  studyRuntimeFactory: legacy,
);

final class _NoWriteStore implements ExportArtifactStore {
  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
    required ExportWriteRevalidator revalidateBeforeWrite,
  }) => throw StateError('Bootstrap cannot save a Study archive');
}

final class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}
