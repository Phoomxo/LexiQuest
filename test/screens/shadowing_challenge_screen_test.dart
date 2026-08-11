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
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/media_dependency_unavailable.dart';
import 'package:vocab_learning_app/screens/shadowing_challenge_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  testWidgets('uses real transcript provenance and never fabricates pitch', (
    tester,
  ) async {
    final voice = _FakeVoice();
    final speech = SpeechPracticeUseCases(_FakeSpeechGateway());
    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          referenceSentence: 'Practice makes perfect',
          voice: VoiceUseCases(provider: voice, disposeProvider: () async {}),
          speechPractice: speech,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('shadowing-play-reference')));
    await tester.pumpAndSettle();
    expect(voice.requests.single.text, 'Practice makes perfect');

    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('ข้อความที่ได้ยิน: Practice makes perfect'),
      findsOneWidget,
    );
    expect(find.textContaining('ความเหมือนของข้อความ: 100%'), findsOneWidget);
    expect(
      find.textContaining('ไม่ได้ส่งข้อมูล pitch หรือ phoneme'),
      findsOneWidget,
    );
    expect(find.textContaining('Pitch Contour'), findsNothing);
  });

  testWidgets('cancels microphone when app leaves foreground', (tester) async {
    final gateway = _FakeSpeechGateway(
      emitFinal: false,
      cancelError: StateError('recognizer cancel failed'),
    );
    final speech = SpeechPracticeUseCases(gateway);
    final provider = _FakeVoice();
    final voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: ShadowingChallengeScreen(
            referenceSentence: 'Keep going',
            voice: voice,
            speechPractice: speech,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('shadowing-play-reference')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
      await tester.pump();
      expect(gateway.isListening, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.runAsync(
        () => provider.stopEntered.future.timeout(
          const Duration(milliseconds: 250),
        ),
      );

      expect(gateway.cancelCalls, 1);
      expect(provider.stopCalls, 1);
      expect(tester.takeException(), isNull);
    } finally {
      if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() async {
        await voice.dispose().timeout(const Duration(seconds: 1));
        try {
          await speech.dispose().timeout(const Duration(seconds: 1));
        } on Object {
          // The recognizer cleanup failure is deliberately injected.
        }
      });
    }
  });

  testWidgets('persists the actual assessment method in learning provenance', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 7, 30, 9);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'guest',
      nowUtc: () => now,
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: owner.id,
            name: 'Practice',
            normalizedName: 'practice',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'word-1',
            ownerId: owner.id,
            categoryId: 'category-1',
            spelling: 'Practice makes perfect',
            normalizedSpelling: 'practice makes perfect',
            meaning: 'practice sentence',
            normalizedMeaning: 'practice sentence',
            partOfSpeech: 'phrase',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    var nextId = 0;
    final learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => '${++nextId}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
          speechPractice: SpeechPracticeUseCases(_FakeSpeechGateway()),
          learning: learning,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pumpAndSettle();

    final attempt = await database.select(database.answerAttempts).getSingle();
    expect(
      attempt.providerProvenance,
      'device-stt|en-US|transcript-edit-distance-v1',
    );
  });

  testWidgets('missing media dependencies cannot start a durable quiz', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 7, 30, 9);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'guest',
      nowUtc: () => now,
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: owner.id,
            name: 'Practice',
            normalizedName: 'practice',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'word-1',
            ownerId: owner.id,
            categoryId: 'category-1',
            spelling: 'Keep going',
            normalizedSpelling: 'keep going',
            meaning: 'continue',
            normalizedMeaning: 'continue',
            partOfSpeech: 'phrase',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    var nextId = 0;
    final learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => '${++nextId}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );

    await tester.pumpWidget(
      MaterialApp(home: ShadowingChallengeScreen(learning: learning)),
    );
    await tester.pumpAndSettle();

    final state = tester.widget<MediaDependencyUnavailable>(
      find.byType(MediaDependencyUnavailable),
    );
    expect(state.reason, MediaDependencyUnavailableReason.voice);
    expect(await database.select(database.learningSessions).get(), isEmpty);
  });

  testWidgets('late microphone start cancels itself after route disposal', (
    tester,
  ) async {
    final gateway = _PendingSpeechGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          referenceSentence: 'Keep going',
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
          speechPractice: SpeechPracticeUseCases(gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pump();
    expect(gateway.startCalls, 1);
    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pump();
    expect(gateway.startCalls, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('shadowing-listen-button')),
          )
          .onPressed,
      isNull,
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(gateway.cancelCalls, 0);

    gateway.allowStart.complete();
    await tester.pump();
    await tester.pump();

    expect(gateway.isListening, isFalse);
    expect(gateway.cancelCalls, 1);
  });

  testWidgets('stale pending route cannot cancel replacement listening', (
    tester,
  ) async {
    final gateway = _TwoStartSpeechGateway();
    final speech = SpeechPracticeUseCases(gateway);
    final voice = VoiceUseCases(
      provider: _FakeVoice(),
      disposeProvider: () async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          referenceSentence: 'First route',
          voice: voice,
          speechPractice: speech,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pump();
    expect(gateway.startCalls, 1);

    final context = tester.element(find.byType(ShadowingChallengeScreen));
    unawaited(
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => ShadowingChallengeScreen(
            referenceSentence: 'Second route',
            voice: voice,
            speechPractice: speech,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pump();

    expect(gateway.startCalls, 1);
    gateway.startCompletions.first.complete();
    await tester.pump();
    await tester.pump();
    expect(gateway.cancelCalls, 1);
    expect(gateway.startCalls, 2);

    gateway.startCompletions.last.complete();
    await tester.pump();
    await tester.pump();

    expect(gateway.isListening, isTrue);
    expect(gateway.cancelCalls, 1);
  });

  testWidgets('covered route reacquires speech after child pop', (
    tester,
  ) async {
    final gateway = _TwoStartSpeechGateway();
    final speech = SpeechPracticeUseCases(gateway);
    final voice = VoiceUseCases(
      provider: _FakeVoice(),
      disposeProvider: () async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          referenceSentence: 'Parent route',
          voice: voice,
          speechPractice: speech,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pump();
    expect(gateway.startCalls, 1);

    final parentContext = tester.element(find.byType(ShadowingChallengeScreen));
    unawaited(
      Navigator.of(parentContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ShadowingChallengeScreen(
            referenceSentence: 'Child route',
            voice: voice,
            speechPractice: speech,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    gateway.startCompletions.first.complete();
    await tester.pump();
    await tester.pump();
    expect(gateway.cancelCalls, 1);

    Navigator.of(tester.element(find.byType(ShadowingChallengeScreen))).pop();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('shadowing-listen-button')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pump();
    expect(gateway.startCalls, 2);
    gateway.startCompletions.last.complete();
    await tester.pump();
    await tester.pump();
    expect(gateway.isListening, isTrue);
  });
}

final class _FakeSpeechGateway implements SpeechRecognitionGateway {
  _FakeSpeechGateway({this.emitFinal = true, this.cancelError});

  final bool emitFinal;
  final Object? cancelError;
  int cancelCalls = 0;
  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    isListening = false;
    final error = cancelError;
    if (error != null) throw error;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {}

  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.granted;

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    isListening = true;
    if (!emitFinal) return;
    onEvent(
      SpeechRecognitionEvent(
        transcript: 'Practice makes perfect',
        isFinal: true,
        recognizedAtUtc: DateTime.utc(2026, 7, 30),
        engine: 'device-stt',
        locale: locale,
      ),
    );
    isListening = false;
  }

  @override
  Future<void> stop() async {
    isListening = false;
  }
}

final class _FakeVoice implements VoiceProvider {
  final List<VoiceRequest> requests = [];
  final Completer<void> stopEntered = Completer<void>();
  int stopCalls = 0;

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
  Future<void> stop() async {
    stopCalls += 1;
    if (!stopEntered.isCompleted) stopEntered.complete();
  }
}

final class _PendingSpeechGateway implements SpeechRecognitionGateway {
  final Completer<void> allowStart = Completer<void>();
  int startCalls = 0;
  int cancelCalls = 0;

  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    isListening = false;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {}

  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.granted;

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    startCalls += 1;
    await allowStart.future;
    isListening = true;
  }

  @override
  Future<void> stop() async {
    isListening = false;
  }
}

final class _TwoStartSpeechGateway implements SpeechRecognitionGateway {
  final List<Completer<void>> startCompletions = [
    Completer<void>(),
    Completer<void>(),
  ];
  int startCalls = 0;
  int cancelCalls = 0;

  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    isListening = false;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {}

  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.granted;

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    final call = startCalls++;
    await startCompletions[call].future;
    isListening = true;
  }

  @override
  Future<void> stop() async {
    isListening = false;
  }
}
