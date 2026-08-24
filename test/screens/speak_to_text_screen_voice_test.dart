import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/media_dependency_unavailable.dart';
import 'package:vocab_learning_app/screens/speak_to_text_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

class FakeVoiceProvider implements VoiceProvider {
  final List<VoiceRequest> spokenRequests = [];
  final Completer<void> stopEntered = Completer<void>();
  int stopCalls = 0;
  VoicePlaybackResult? resultToReturn;
  Object? errorToThrow;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    spokenRequests.add(request);
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return resultToReturn ??
        const VoicePlaybackResult(
          requestedEngine: VoiceEngine.omniVoice,
          actualEngine: VoiceEngine.omniVoice,
          usedFallback: false,
          cacheHit: false,
          requestId: 'test-req-123',
          modelVersion: '0.2.1',
        );
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (!stopEntered.isCompleted) stopEntered.complete();
  }
}

void main() {
  testWidgets(
    'SpeakToTextScreen automatically speaks word on start using VoiceProvider',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: SpeakToTextScreen(
            correctWord: 'apple',
            voice: VoiceUseCases(
              provider: fakeVoice,
              disposeProvider: () async {},
            ),
            speechPractice: SpeechPracticeUseCases(_LifecycleSpeechGateway()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeVoice.spokenRequests.length, 1);
      final req = fakeVoice.spokenRequests.first;
      expect(req.text, 'apple');
      expect(req.language, 'en');
      expect(req.mode, VoiceMode.practice);
      expect(req.contentId, 'apple');
      expect(req.contentType, 'vocabulary_word');
    },
  );

  testWidgets('Tapping audio button replays speech via VoiceProvider', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: SpeakToTextScreen(
          correctWord: 'banana',
          voice: VoiceUseCases(
            provider: fakeVoice,
            disposeProvider: () async {},
          ),
          speechPractice: SpeechPracticeUseCases(_LifecycleSpeechGateway()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(fakeVoice.spokenRequests.length, 1);

    // Find and tap speaker / audio replay button
    final speakerFinder = find.byIcon(Icons.volume_up);
    expect(speakerFinder, findsOneWidget);

    await tester.tap(speakerFinder);
    await tester.pumpAndSettle();

    expect(fakeVoice.spokenRequests.length, 2);
    expect(fakeVoice.spokenRequests[1].text, 'banana');
  });

  testWidgets('route takeover stops old playback but never the replacement', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();
    final sharedVoice = VoiceUseCases(
      provider: fakeVoice,
      disposeProvider: () async {},
    );
    final sharedGateway = _LifecycleSpeechGateway();
    final sharedSpeech = SpeechPracticeUseCases(sharedGateway);

    await tester.pumpWidget(
      MaterialApp(
        home: SpeakToTextScreen(
          correctWord: 'cat',
          voice: sharedVoice,
          speechPractice: sharedSpeech,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(SpeakToTextScreen));
    unawaited(
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => SpeakToTextScreen(
            correctWord: 'banana',
            voice: sharedVoice,
            speechPractice: sharedSpeech,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(fakeVoice.spokenRequests.map((request) => request.text), [
      'cat',
      'banana',
    ]);
    // The replacement session owns one takeover stop before speaking banana.
    // The disposed cat route's stale release must not add a second stop.
    expect(fakeVoice.stopCalls, 1);
    expect(sharedGateway.cancelCalls, 0);
  });

  testWidgets('cancels microphone when app leaves foreground', (tester) async {
    final gateway = _LifecycleSpeechGateway(
      cancelError: StateError('recognizer cancel failed'),
    );
    final provider = FakeVoiceProvider();
    final voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    final speech = SpeechPracticeUseCases(gateway);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SpeakToTextScreen(
            correctWord: 'cat',
            voice: voice,
            speechPractice: speech,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
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

  testWidgets('missing speech fails closed before automatic voice playback', (
    tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: SpeakToTextScreen(
          correctWord: 'cat',
          voice: VoiceUseCases(
            provider: fakeVoice,
            disposeProvider: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.widget<MediaDependencyUnavailable>(
      find.byType(MediaDependencyUnavailable),
    );
    expect(state.reason, MediaDependencyUnavailableReason.speechPractice);
    expect(fakeVoice.spokenRequests, isEmpty);
  });

  testWidgets('late microphone start cancels itself after route disposal', (
    tester,
  ) async {
    final gateway = _PendingSpeechGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: SpeakToTextScreen(
          correctWord: 'cat',
          voice: VoiceUseCases(
            provider: FakeVoiceProvider(),
            disposeProvider: () async {},
          ),
          speechPractice: SpeechPracticeUseCases(gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
    await tester.pump();
    expect(gateway.startCalls, 1);
    await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
    await tester.pump();
    expect(gateway.startCalls, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('speech-listen-button')),
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

  testWidgets('outgoing route cannot cancel replacement microphone', (
    tester,
  ) async {
    final gateway = _SharedSpeechGateway();
    final speech = SpeechPracticeUseCases(gateway);
    final voice = VoiceUseCases(
      provider: FakeVoiceProvider(),
      disposeProvider: () async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SpeakToTextScreen(
          correctWord: 'cat',
          voice: voice,
          speechPractice: speech,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(SpeakToTextScreen));
    unawaited(
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => SpeakToTextScreen(
            correctWord: 'banana',
            voice: voice,
            speechPractice: speech,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
    await tester.pump();
    expect(gateway.isListening, isTrue);

    if (gateway.cancelCalls > 0) {
      gateway.allowCancel.complete();
      await tester.pump();
      await tester.pump();
    }

    expect(gateway.isListening, isTrue);
    expect(gateway.cancelCalls, 0);
    gateway.allowCancel.complete();
  });

  testWidgets('stale pending route cannot cancel replacement listening', (
    tester,
  ) async {
    final gateway = _TwoStartSpeechGateway();
    final speech = SpeechPracticeUseCases(gateway);
    final voice = VoiceUseCases(
      provider: FakeVoiceProvider(),
      disposeProvider: () async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SpeakToTextScreen(
          correctWord: 'cat',
          voice: voice,
          speechPractice: speech,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
    await tester.pump();
    expect(gateway.startCalls, 1);

    final context = tester.element(find.byType(SpeakToTextScreen));
    unawaited(
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => SpeakToTextScreen(
            correctWord: 'banana',
            voice: voice,
            speechPractice: speech,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
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
      provider: FakeVoiceProvider(),
      disposeProvider: () async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SpeakToTextScreen(
          correctWord: 'cat',
          voice: voice,
          speechPractice: speech,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
    await tester.pump();
    expect(gateway.startCalls, 1);

    final parentContext = tester.element(find.byType(SpeakToTextScreen));
    unawaited(
      Navigator.of(parentContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => SpeakToTextScreen(
            correctWord: 'banana',
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

    Navigator.of(tester.element(find.byType(SpeakToTextScreen))).pop();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('speech-listen-button')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
    await tester.pump();
    expect(gateway.startCalls, 2);
    gateway.startCompletions.last.complete();
    await tester.pump();
    await tester.pump();
    expect(gateway.isListening, isTrue);
  });

  for (final idCase
      in <
        ({String name, String? sessionId, String? wordId, int expectedWrites})
      >[
        (
          name: 'neither learning id',
          sessionId: null,
          wordId: null,
          expectedWrites: 0,
        ),
        (
          name: 'only session id',
          sessionId: 'session-1',
          wordId: null,
          expectedWrites: 0,
        ),
        (
          name: 'only word id',
          sessionId: null,
          wordId: 'word-1',
          expectedWrites: 0,
        ),
        (
          name: 'both learning ids',
          sessionId: 'session-1',
          wordId: 'word-1',
          expectedWrites: 1,
        ),
      ]) {
    testWidgets('learning write guard accepts ${idCase.name}', (tester) async {
      final repository = _CountingLearningRepository();
      final learning = LearningUseCases(
        owners: _LearningOwnerRepository(),
        repository: repository,
        generateId: () => 'attempt-1',
        nowUtc: () => DateTime.utc(2026, 8, 11),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SpeakToTextScreen(
            correctWord: 'cat',
            voice: VoiceUseCases(
              provider: FakeVoiceProvider(),
              disposeProvider: () async {},
            ),
            speechPractice: SpeechPracticeUseCases(_EvidenceSpeechGateway()),
            learning: learning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
            sessionId: idCase.sessionId,
            wordId: idCase.wordId,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
      await tester.pumpAndSettle();

      expect(repository.recordCalls, idCase.expectedWrites);
      if (idCase.expectedWrites == 1) {
        expect(repository.lastCommand?.sessionId, 'session-1');
        expect(repository.lastCommand?.wordId, 'word-1');
        expect(
          repository.lastCommand?.providerProvenance,
          'device-stt|en-US|transcript-edit-distance-v1',
        );
      }
    });
  }

  testWidgets(
    'correct speech stays locked through failure and retries one response',
    (tester) async {
      final firstRecordRelease = Completer<void>();
      addTearDown(() {
        if (!firstRecordRelease.isCompleted) firstRecordRelease.complete();
      });
      final repository = _CountingLearningRepository(
        failFirstRecord: true,
        firstRecordRelease: firstRecordRelease,
      );
      final speechGateway = _EvidenceSpeechGateway();
      var nextId = 0;
      final learning = LearningUseCases(
        owners: _LearningOwnerRepository(),
        repository: repository,
        generateId: () => 'speech-${++nextId}',
        nowUtc: () => DateTime.utc(2026, 8, 11, 10, 0, nextId),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      final voice = VoiceUseCases(
        provider: FakeVoiceProvider(),
        disposeProvider: () async {},
      );
      addTearDown(voice.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SpeakToTextScreen(
            correctWord: 'cat',
            voice: voice,
            speechPractice: SpeechPracticeUseCases(speechGateway),
            learning: learning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
            sessionId: 'session-1',
            wordId: 'word-1',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final listen = find.byKey(const ValueKey('speech-listen-button'));
      await tester.tap(listen);
      await tester.pumpAndSettle();
      final action = find.byType(OutlinedButton);
      final pendingAdvanceWasLocked =
          tester.widget<OutlinedButton>(action).onPressed == null;
      final pendingListenWasLocked =
          tester.widget<FilledButton>(listen).onPressed == null;

      speechGateway.emitPartial('dog');
      await tester.pump();
      final pendingTranscriptAfterStaleCallback = tester
          .widget<Text>(find.byKey(const ValueKey<String>('speech-transcript')))
          .data;
      final pendingStaleNavigationStayedLocked =
          tester.widget<OutlinedButton>(action).onPressed == null;
      final commandsWhilePending = repository.commands.length;

      firstRecordRelease.complete();
      await tester.pumpAndSettle();
      final retryButton = find.byKey(
        const ValueKey<String>('current-evidence-retry'),
      );
      final retryWasShown = retryButton.evaluate().length == 1;
      final failedAdvanceStayedLocked =
          tester.widget<OutlinedButton>(action).onPressed == null;

      speechGateway.emitFinal('bird');
      speechGateway.emitPartial('fox');
      await tester.pump();
      final failedTranscriptAfterStaleCallbacks = tester
          .widget<Text>(find.byKey(const ValueKey<String>('speech-transcript')))
          .data;
      final failedStaleNavigationStayedLocked =
          tester.widget<OutlinedButton>(action).onPressed == null;
      final commandsBeforeRetry = repository.commands.length;

      await tester.tap(retryButton);
      await tester.pumpAndSettle();
      final committedAdvanceIsEnabled =
          tester.widget<OutlinedButton>(action).onPressed != null;
      final committedActionIsSuccess = find
          .widgetWithText(OutlinedButton, 'ไปเกมเรียงคำ')
          .evaluate()
          .isNotEmpty;

      expect(pendingAdvanceWasLocked, isTrue);
      expect(pendingListenWasLocked, isTrue);
      expect(pendingStaleNavigationStayedLocked, isTrue);
      expect(pendingTranscriptAfterStaleCallback, 'cat');
      expect(commandsWhilePending, 1);
      expect(retryWasShown, isTrue);
      expect(failedAdvanceStayedLocked, isTrue);
      expect(failedStaleNavigationStayedLocked, isTrue);
      expect(failedTranscriptAfterStaleCallbacks, 'cat');
      expect(commandsBeforeRetry, 1);
      expect(repository.commands, hasLength(2));
      expect(repository.successfulRecordCalls, 1);
      expect(committedAdvanceIsEnabled, isTrue);
      expect(committedActionIsSuccess, isTrue);
      final first = repository.commands.first;
      final retry = repository.commands.last;
      expect(retry.id, first.id);
      expect(retry.occurredAtUtc, first.occurredAtUtc);
      expect(retry.responseTimeMs, first.responseTimeMs);
      expect(retry.evidenceContext.toJson(), first.evidenceContext.toJson());
      expect(retry.evidenceContext.evidenceClass, EvidenceClass.pronunciation);
    },
  );

  testWidgets(
    'canonical evidence locks pronunciation playback until persistence succeeds',
    (tester) async {
      final firstRecordRelease = Completer<void>();
      addTearDown(() {
        if (!firstRecordRelease.isCompleted) firstRecordRelease.complete();
      });
      final repository = _CountingLearningRepository(
        failFirstRecord: true,
        firstRecordRelease: firstRecordRelease,
      );
      final learning = LearningUseCases(
        owners: _LearningOwnerRepository(),
        repository: repository,
        generateId: () => 'speech-audio-lock',
        nowUtc: () => DateTime.utc(2026, 8, 11, 10),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      final provider = FakeVoiceProvider();
      final voice = VoiceUseCases(
        provider: provider,
        disposeProvider: () async {},
      );
      addTearDown(voice.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SpeakToTextScreen(
            correctWord: 'cat',
            voice: voice,
            speechPractice: SpeechPracticeUseCases(_EvidenceSpeechGateway()),
            learning: learning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
            sessionId: 'session-1',
            wordId: 'word-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final playback = find.ancestor(
        of: find.byIcon(Icons.volume_up),
        matching: find.byType(InkWell),
      );
      final stalePlaybackHandler = tester.widget<InkWell>(playback).onTap!;
      expect(provider.spokenRequests, hasLength(1));

      await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
      await tester.pump();

      expect(tester.widget<InkWell>(playback).onTap, isNull);
      stalePlaybackHandler();
      await tester.pump();
      expect(
        provider.spokenRequests,
        hasLength(1),
        reason: 'a stale playback callback must honor the evidence lock',
      );

      firstRecordRelease.complete();
      await tester.pumpAndSettle();
      final retry = find.byKey(
        const ValueKey<String>('current-evidence-retry'),
      );
      expect(retry, findsOneWidget);
      expect(tester.widget<InkWell>(playback).onTap, isNull);
      stalePlaybackHandler();
      await tester.pump();
      expect(provider.spokenRequests, hasLength(1));

      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(tester.widget<InkWell>(playback).onTap, isNotNull);
      await tester.tap(playback);
      await tester.pumpAndSettle();
      expect(provider.spokenRequests, hasLength(2));
    },
  );

  for (final resultCase in <({String name, String correctWord})>[
    (name: 'correct', correctWord: 'cat'),
    (name: 'incorrect', correctWord: 'dog'),
  ]) {
    testWidgets(
      '${resultCase.name} evidence blocks result and system back until retry',
      (tester) async {
        final firstRecordRelease = Completer<void>();
        addTearDown(() {
          if (!firstRecordRelease.isCompleted) firstRecordRelease.complete();
        });
        final repository = _CountingLearningRepository(
          failFirstRecord: true,
          firstRecordRelease: firstRecordRelease,
        );
        var nextId = 0;
        final learning = LearningUseCases(
          owners: _LearningOwnerRepository(),
          repository: repository,
          generateId: () => 'speech-route-${++nextId}',
          nowUtc: () => DateTime.utc(2026, 8, 11, 11, 0, nextId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
        );
        final voice = VoiceUseCases(
          provider: FakeVoiceProvider(),
          disposeProvider: () async {},
        );
        addTearDown(voice.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  key: const ValueKey<String>('open-speech-route'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => SpeakToTextScreen(
                        correctWord: resultCase.correctWord,
                        voice: voice,
                        speechPractice: SpeechPracticeUseCases(
                          _EvidenceSpeechGateway(),
                        ),
                        learning: learning,
                        evidenceAdapter: CurrentActivityEvidenceAdapter(
                          learning: learning,
                        ),
                        sessionId: 'session-1',
                        wordId: 'word-1',
                      ),
                    ),
                  ),
                  child: const Text('Open speech practice'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('open-speech-route')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('speech-listen-button')),
        );
        await tester.pump();

        final resultAction = find.byType(OutlinedButton);
        expect(
          tester.widget<OutlinedButton>(resultAction).onPressed,
          isNull,
          reason: 'pending canonical evidence must lock the result action',
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          find.byType(SpeakToTextScreen),
          findsOneWidget,
          reason: 'pending canonical evidence must block system back',
        );

        firstRecordRelease.complete();
        await tester.pumpAndSettle();
        final retry = find.byKey(
          const ValueKey<String>('current-evidence-retry'),
        );
        expect(retry, findsOneWidget);
        expect(
          tester.widget<OutlinedButton>(resultAction).onPressed,
          isNull,
          reason: 'failed canonical evidence must lock the result action',
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          find.byType(SpeakToTextScreen),
          findsOneWidget,
          reason: 'failed canonical evidence must preserve its retry route',
        );

        await tester.tap(retry);
        await tester.pumpAndSettle();

        expect(repository.commands, hasLength(2));
        expect(repository.successfulRecordCalls, 1);
        final first = repository.commands.first;
        final retried = repository.commands.last;
        expect(retried.id, first.id);
        expect(retried.occurredAtUtc, first.occurredAtUtc);
        expect(retried.responseTimeMs, first.responseTimeMs);
        expect(
          retried.evidenceContext.toJson(),
          first.evidenceContext.toJson(),
        );
        expect(
          tester.widget<OutlinedButton>(resultAction).onPressed,
          isNotNull,
        );

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(SpeakToTextScreen), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('open-speech-route')),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('one utterance epoch accepts only its first final transcript', (
    tester,
  ) async {
    final repository = _CountingLearningRepository();
    final learning = LearningUseCases(
      owners: _LearningOwnerRepository(),
      repository: repository,
      generateId: () => 'speech-first-final',
      nowUtc: () => DateTime.utc(2026, 8, 11),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );
    final voice = VoiceUseCases(
      provider: FakeVoiceProvider(),
      disposeProvider: () async {},
    );
    addTearDown(voice.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SpeakToTextScreen(
          correctWord: 'cat',
          voice: voice,
          speechPractice: SpeechPracticeUseCases(
            _EvidenceSpeechGateway(duplicateFinal: true),
          ),
          learning: learning,
          evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
          sessionId: 'session-1',
          wordId: 'word-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
    await tester.pumpAndSettle();

    expect(repository.commands, hasLength(1));
  });

  for (final throwsAfterFinal in <bool>[false, true]) {
    testWidgets(
      'accepted final fences late callbacks and ${throwsAfterFinal ? 'start failure' : 'start completion'}',
      (tester) async {
        final repository = _CountingLearningRepository();
        final learning = LearningUseCases(
          owners: _LearningOwnerRepository(),
          repository: repository,
          generateId: () => 'speech-final-before-return',
          nowUtc: () => DateTime.utc(2026, 8, 15),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
        );
        final gateway = _FinalBeforeReturnSpeechGateway(
          throwsAfterFinal: throwsAfterFinal,
        );
        final voice = VoiceUseCases(
          provider: FakeVoiceProvider(),
          disposeProvider: () async {},
        );
        addTearDown(voice.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: SpeakToTextScreen(
              correctWord: 'cat',
              voice: voice,
              speechPractice: SpeechPracticeUseCases(gateway),
              learning: learning,
              evidenceAdapter: CurrentActivityEvidenceAdapter(
                learning: learning,
              ),
              sessionId: 'session-1',
              wordId: 'word-1',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('speech-listen-button')),
        );
        await tester.pumpAndSettle();

        expect(repository.commands, hasLength(1));
        expect(find.text('cat', findRichText: true), findsWidgets);
        expect(
          find.text('ไม่ได้ยินคำพูดที่ชัดเจน กรุณาลองอีกครั้ง'),
          findsNothing,
        );
        expect(find.text('ระบบรู้จำเสียงไม่พร้อมใช้งาน'), findsNothing);
        expect(find.text('หยุดฟัง'), findsNothing);
        expect(find.text('เริ่มพูด'), findsOneWidget);
        expect(gateway.stopCalls, 1);
      },
    );
  }
}

final class _LearningOwnerRepository implements LocalOwnerRepository {
  static final owner = LocalOwner(
    id: 'owner-1',
    createdAtUtc: DateTime.utc(2026, 8, 1),
  );

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => owner;

  @override
  Future<LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) async => owner;
}

final class _CountingLearningRepository implements LearningRepository {
  _CountingLearningRepository({
    this.failFirstRecord = false,
    this.firstRecordRelease,
  });

  final bool failFirstRecord;
  final Completer<void>? firstRecordRelease;
  int recordCalls = 0;
  int successfulRecordCalls = 0;
  RecordAnswerCommand? lastCommand;
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    recordCalls += 1;
    lastCommand = command;
    commands.add(command);
    if (recordCalls == 1) {
      await firstRecordRelease?.future;
      if (failFirstRecord) throw StateError('simulated local failure');
    }
    successfulRecordCalls += 1;
    return AnswerRecordResult(
      inserted: true,
      isCorrect: command.isCorrect,
      srs: SrsSnapshot(
        intervalDays: 1,
        repetitions: 1,
        lapses: 0,
        stability: 1,
        difficulty: 5,
        lastReviewAtUtc: null,
        dueAtUtc: null,
        algorithmVersion: 1,
      ),
    );
  }

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) async => const [];

  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) async => const [];

  @override
  Future<void> startSession(LearningSessionDraft session) async {}

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) => throw UnimplementedError();

  @override
  Future<LearningSessionSummary?> getActiveSession({
    required String ownerId,
  }) async => null;

  @override
  Future<void> abandonActiveSessions({required String ownerId}) async {}

  @override
  Future<List<LearningSessionSummary>> listSessionHistory({
    required String ownerId,
    required int limit,
  }) async => const [];

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) async => null;

  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) => throw UnimplementedError();
}

final class _EvidenceSpeechGateway implements SpeechRecognitionGateway {
  _EvidenceSpeechGateway({this.duplicateFinal = false});

  final bool duplicateFinal;
  SpeechEventCallback? _onEvent;
  String? _locale;

  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
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
    isListening = true;
    _onEvent = onEvent;
    _locale = locale;
    emitFinal('cat');
    if (duplicateFinal) emitFinal('cat');
    isListening = false;
  }

  void emitFinal(String transcript) => _emit(transcript, isFinal: true);

  void emitPartial(String transcript) => _emit(transcript, isFinal: false);

  void _emit(String transcript, {required bool isFinal}) {
    final onEvent = _onEvent;
    final locale = _locale;
    if (onEvent == null || locale == null) {
      throw StateError('speech recognition has not started');
    }
    onEvent(
      SpeechRecognitionEvent(
        transcript: transcript,
        isFinal: isFinal,
        recognizedAtUtc: DateTime.utc(2026, 8, 11),
        engine: 'device-stt',
        locale: locale,
      ),
    );
  }

  @override
  Future<void> stop() async {
    isListening = false;
  }
}

final class _FinalBeforeReturnSpeechGateway
    implements SpeechRecognitionGateway {
  _FinalBeforeReturnSpeechGateway({required this.throwsAfterFinal});

  final bool throwsAfterFinal;
  SpeechFailureCallback? _onFailure;
  void Function(String status)? _onStatus;
  int stopCalls = 0;

  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    isListening = false;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {
    _onFailure = onFailure;
    _onStatus = onStatus;
  }

  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.granted;

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    isListening = true;
    onEvent(
      SpeechRecognitionEvent(
        transcript: 'cat',
        isFinal: true,
        recognizedAtUtc: DateTime.utc(2026, 8, 15),
        engine: 'device-stt',
        locale: locale,
      ),
    );
    _onStatus!('listening');
    _onFailure!(SpeechFailureCode.noMatch);
    if (throwsAfterFinal) {
      throw const SpeechPracticeException(SpeechFailureCode.engine);
    }
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    isListening = false;
  }
}

final class _LifecycleSpeechGateway implements SpeechRecognitionGateway {
  _LifecycleSpeechGateway({this.cancelError});

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
  }

  @override
  Future<void> stop() async {
    isListening = false;
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

final class _SharedSpeechGateway implements SpeechRecognitionGateway {
  final Completer<void> allowCancel = Completer<void>();
  int cancelCalls = 0;

  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    await allowCancel.future;
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
