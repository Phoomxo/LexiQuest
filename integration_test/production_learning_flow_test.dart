import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/ai/content_provider.dart';
import 'package:vocab_learning_app/ai/generated_reading_content_source.dart';
import 'package:vocab_learning_app/learning/associative_reading_coordinator.dart';
import 'package:vocab_learning_app/learning/reading_content_source.dart';
import 'package:vocab_learning_app/learning/reading_session.dart';
import 'package:vocab_learning_app/learning/secure_id_generator.dart';
import 'package:vocab_learning_app/learning/storage/drift_learning_repository.dart';
import 'package:vocab_learning_app/learning/storage/learning_database_factory_native.dart';
import 'package:vocab_learning_app/learning/vocabulary_mixer.dart';
import 'package:vocab_learning_app/progress/local_progress_repository.dart';
import 'package:vocab_learning_app/progress/progress_remote_writer.dart';
import 'package:vocab_learning_app/progress/progress_repository.dart';
import 'package:vocab_learning_app/progress/progress_sync_service.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';
import 'package:vocab_learning_app/voice/reading_voice_enrichment.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'lexiquest-device-e2e-',
    );
  });

  tearDown(() async {
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  testWidgets(
    'completes six stages after durable restart with validated fallback',
    (tester) async {
      final factory = LearningDatabaseFactory.nativeForTesting(
        directoryProvider: () async => databaseDirectory,
      );
      final firstDatabase = await factory.open();
      final firstRepository = DriftLearningRepository(firstDatabase);
      final firstCoordinator = _coordinator(firstRepository);
      final initial = await firstCoordinator.start(_startRequest);

      expect(initial.content.provenance, ReadingContentProvenance.curated);
      expect(initial.content.passage, contains('resilient'));

      await tester.pumpWidget(
        MaterialApp(
          home: AssociativeReadingSessionScreen(
            coordinator: firstCoordinator,
            initialState: initial,
          ),
        ),
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Cue Fading'), findsOneWidget);

      final sessionId = firstCoordinator.state!.session.sessionId;
      await tester.pumpWidget(const SizedBox.shrink());
      await firstDatabase.close();

      final reopenedDatabase = await factory.open();
      addTearDown(reopenedDatabase.close);
      final reopenedRepository = DriftLearningRepository(reopenedDatabase);
      final resumedCoordinator = _coordinator(reopenedRepository);
      final resumed = await resumedCoordinator.resume(
        ownerId: 'owner-a',
        sessionId: sessionId,
      );

      expect(resumed.session.currentStage, ReadingSessionStage.cueFading);
      expect(
        await reopenedRepository.readSession(
          ownerId: 'owner-b',
          sessionId: sessionId,
        ),
        isNull,
      );
      await expectLater(
        resumedCoordinator.resume(ownerId: 'owner-b', sessionId: sessionId),
        throwsA(
          isA<ReadingCoordinatorException>().having(
            (error) => error.code,
            'code',
            ReadingCoordinatorErrorCode.sessionNotFound,
          ),
        ),
      );

      final active = await resumedCoordinator.resume(
        ownerId: 'owner-a',
        sessionId: sessionId,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AssociativeReadingSessionScreen(
            coordinator: resumedCoordinator,
            initialState: active,
          ),
        ),
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'resilient');
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'She is resilient after a difficult day.',
      );
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();

      expect(find.text('Completed'), findsOneWidget);
      expect(
        resumedCoordinator.state!.session.currentStage,
        ReadingSessionStage.completed,
      );
      expect(
        await reopenedDatabase.select(reopenedDatabase.learningEvents).get(),
        hasLength(1),
      );
      expect(
        await reopenedRepository.readMemoryState(
          ownerId: 'owner-a',
          wordKey: 'resilient',
        ),
        isNotNull,
      );
    },
  );

  testWidgets('voice failure does not advance and abandonment is idempotent', (
    tester,
  ) async {
    final factory = LearningDatabaseFactory.nativeForTesting(
      directoryProvider: () async => databaseDirectory,
    );
    final database = await factory.open();
    addTearDown(database.close);
    final repository = DriftLearningRepository(database);
    final coordinator = _coordinator(repository);
    final initial = await coordinator.start(_startRequest);

    await tester.pumpWidget(
      MaterialApp(
        home: AssociativeReadingSessionScreen(
          coordinator: coordinator,
          initialState: initial,
          readingVoice: ReadingVoiceEnrichment(
            provider: _UnavailableVoiceProvider(),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Listen'));
    await tester.pumpAndSettle();

    expect(find.text('Supported Reading'), findsOneWidget);
    expect(
      find.text('Voice is unavailable. Continue reading.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Abandon session'));
    await tester.pumpAndSettle();
    expect(find.text('Abandoned'), findsOneWidget);

    final first = coordinator.state!.session;
    final replay = await coordinator.abandon();
    expect(replay.session.currentStage, ReadingSessionStage.abandoned);
    expect(replay.session.updatedAtUtc, first.updatedAtUtc);
  });

  test(
    'offline progress queue survives a failed pass and acknowledges once',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove('lexiquest_local_progress_v1');
      addTearDown(() => preferences.remove('lexiquest_local_progress_v1'));
      final firstRepository = LocalProgressRepository(
        preferences,
        clock: () => DateTime.utc(2026, 7, 29, 12),
      );
      await firstRepository.recordSession(
        const ProgressSession(
          sessionId: 'device-offline-session',
          correctAnswers: 2,
          wrongAnswers: 1,
        ),
      );

      final restoredRepository = LocalProgressRepository(preferences);
      final failed = await ProgressSyncService(
        repository: restoredRepository,
        remoteWriter: const _UnavailableProgressWriter(),
      ).synchronize();

      expect(
        failed,
        const ProgressSyncIncomplete(
          synchronizedSessions: 0,
          failure: ProgressRemoteFailure.unavailable,
        ),
      );
      expect(await restoredRepository.pendingSessions(), hasLength(1));

      final completed = await ProgressSyncService(
        repository: restoredRepository,
        remoteWriter: const _AcceptedProgressWriter(),
      ).synchronize();

      expect(completed, const ProgressSyncCompleted(synchronizedSessions: 1));
      expect(await restoredRepository.pendingSessions(), isEmpty);
      expect((await restoredRepository.readSnapshot()).totalPoints, 2);
    },
  );
}

const _startRequest = ReadingStartRequest(
  ownerId: 'owner-a',
  cefrLevel: 'A2',
  mixRequest: VocabularyMixRequest(
    dueWords: ['resilient'],
    weakWords: [],
    newWords: [],
    targetCount: 1,
    maxNewWords: 1,
    seed: 29,
  ),
);

final _curatedSource = CuratedReadingContentSource(const [
  ReadingContent(
    contentId: 'a2-resilient-device',
    contentVersion: 'curated-v1',
    cefrLevel: 'A2',
    passage: 'Mali stays resilient when a difficult plan changes suddenly.',
    targetWords: ['resilient'],
    provenance: ReadingContentProvenance.curated,
  ),
]);

AssociativeReadingCoordinator _coordinator(DriftLearningRepository repository) {
  return AssociativeReadingCoordinator(
    repository: repository,
    reader: repository,
    contentSource: GeneratedReadingContentSource(
      provider: const _InvalidContentProvider(),
      curatedFallback: _curatedSource,
    ),
    mixer: const VersionedVocabularyMixer(),
    idGenerator: _DeviceIdGenerator(),
    clock: DateTime.now,
    appVersion: 'device-e2e',
    buildId: 'local',
  );
}

final class _DeviceIdGenerator implements SecureIdGenerator {
  _DeviceIdGenerator() : prefix = 'device-${++_instances}';

  static var _instances = 0;
  final String prefix;
  var value = 0;

  @override
  String nextId() => '$prefix-${++value}';
}

final class _InvalidContentProvider implements ContentProvider {
  const _InvalidContentProvider();

  @override
  Future<ContentResponse> generate(ContentRequest request) async {
    return const ContentResponse(
      text: 'Missing target.',
      kind: ContentKind.story,
      cefr: CefrLevel.a2,
      language: 'en',
      modelVersion: 'invalid-v1',
      cached: false,
    );
  }
}

final class _UnavailableVoiceProvider implements VoiceProvider {
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) {
    throw const VoiceFailure(
      category: VoiceFailureCategory.modelUnavailable,
      message: 'unavailable',
    );
  }

  @override
  Future<void> stop() async {}
}

final class _UnavailableProgressWriter implements ProgressRemoteWriter {
  const _UnavailableProgressWriter();

  @override
  Future<ProgressRemoteResult> recordProgressSession(
    ProgressSession session,
  ) async {
    return const ProgressRemoteRejected(ProgressRemoteFailure.unavailable);
  }
}

final class _AcceptedProgressWriter implements ProgressRemoteWriter {
  const _AcceptedProgressWriter();

  @override
  Future<ProgressRemoteResult> recordProgressSession(
    ProgressSession session,
  ) async {
    return const ProgressRemoteAccepted(duplicate: false);
  }
}
