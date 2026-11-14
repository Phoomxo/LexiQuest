import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/listening_practice_menu_screen.dart';
import 'package:vocab_learning_app/screens/shadowing_challenge_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  testWidgets('denied mic keeps the listening sentence available at 200%', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final database = AppDatabase(NativeDatabase.memory());
    final microphone = _DeniedMicrophone();
    final speech = SpeechPracticeUseCases(microphone);
    final voice = _TestVoice();
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'shadowing-fixture-owner',
      nowUtc: () => DateTime.utc(2026, 11, 15),
    );
    final dependencies = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _UnusedGuestSession(),
      database: database,
      localOwners: owners,
      learning: LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'unexpected-learning-session',
        nowUtc: () => DateTime.utc(2026, 11, 15),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      ),
      speechPractice: speech,
      voice: VoiceUseCases(voice),
    );

    try {
      await tester.runAsync(() async {
        final owner = await owners.getOrCreateActiveOwner();
        await database
            .into(database.vocabularyCategories)
            .insert(
              VocabularyCategoriesCompanion.insert(
                id: 'travel',
                ownerId: owner.id,
                name: 'การเดินทาง',
                normalizedName: 'การเดินทาง',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
        for (final (word, meaning) in [
          ('station', 'สถานี'),
          ('ticket', 'ตั๋ว'),
        ]) {
          await database
              .into(database.vocabularyWords)
              .insert(
                VocabularyWordsCompanion.insert(
                  id: word,
                  ownerId: owner.id,
                  categoryId: 'travel',
                  spelling: word,
                  normalizedSpelling: word,
                  meaning: meaning,
                  normalizedMeaning: meaning,
                  partOfSpeech: 'noun',
                  createdAtUtcMs: 1,
                  updatedAtUtcMs: 1,
                ),
              );
        }
      });
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: dependencies,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const ListeningPracticeMenuScreen(
              fieldFeatures: BuildFieldFeatureRegistry.fieldDefaults(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final hub = tester.state(find.byType(ListeningPracticeMenuScreen));
      await _tap(tester, find.text('พูดตามประโยค'));
      final shadowing = tester.state(find.byType(ShadowingChallengeScreen));
      final sentence = find.text('Which platform does the train leave from?');
      expect(sentence.hitTestable(), findsOneWidget);
      expect(microphone.permissionRequests, 0);
      expect(voice.requests, isEmpty);

      await _tap(
        tester,
        find.byKey(const ValueKey<String>('shadowing-listen-button')),
      );
      final denied = find.text('ไม่ได้รับสิทธิ์ใช้ไมโครโฟน');
      await _reveal(tester, denied);
      expect(denied.hitTestable(), findsOneWidget);
      expect(microphone.permissionRequests, 1);
      expect(microphone.starts, 0);

      final pendingStop = Completer<void>();
      voice.pendingStop = pendingStop;
      await _tap(tester, find.text('ฝึกโดยไม่ใช้ไมค์'));
      await _reveal(tester, sentence);
      expect(sentence.hitTestable(), findsOneWidget);
      expect(find.byType(ShadowingChallengeScreen), findsNothing);
      expect(voice.requests, isEmpty);
      pendingStop.complete();
      await _tap(tester, find.text('กลับไปฝึกพูด'));
      expect(
        tester.state(find.byType(ShadowingChallengeScreen)),
        same(shadowing),
      );
      await _reveal(tester, sentence);
      expect(sentence.hitTestable(), findsOneWidget);

      await _tap(tester, find.text('กลับไปเลือกแบบฝึกฟัง'));
      expect(tester.state(find.byType(ListeningPracticeMenuScreen)), same(hub));
      expect(microphone.permissionRequests, 1);
      expect(microphone.starts, 0);
      final persistedCounts = await tester.runAsync(
        () async => [
          (await database.select(database.learningSessions).get()).length,
          (await database.select(database.answerAttempts).get()).length,
          (await database.select(database.eventsV2).get()).length,
          (await database.select(database.outboxOperations).get()).length,
        ],
      );
      expect(persistedCounts, [0, 0, 0, 0]);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await speech.dispose();
      await tester.runAsync(database.close);
    }
  });
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      150,
      scrollable: find.byType(Scrollable).hitTestable().last,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await _reveal(tester, target);
  await tester.tap(target.hitTestable());
  await tester.pumpAndSettle();
}

final class _UnusedGuestSession extends Fake implements GuestSessionService {}

final class _DeniedMicrophone implements SpeechRecognitionGateway {
  int permissionRequests = 0;
  int starts = 0;

  @override
  bool get isListening => false;

  @override
  Future<MediaPermissionState> requestPermission() async {
    permissionRequests++;
    return MediaPermissionState.denied;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {}

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    starts++;
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> stop() async {}
}

final class _TestVoice implements VoiceProvider {
  Completer<void>? pendingStop;
  final requests = <VoiceRequest>[];

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests.add(request);
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() => pendingStop?.future ?? Future<void>.value();
}
