import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/screens/ai_tutor_screen.dart';
import 'package:vocab_learning_app/screens/ai_tutor_settings_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  testWidgets(
    'BYOK disclosure states bounded Gemini retry and no provider fallback',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: AiTutorSettingsScreen(aiTutor: _FakeAiTutor())),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('up to 3 total attempts'), findsOneWidget);
      expect(
        find.textContaining('never fall back to a different provider'),
        findsOneWidget,
      );
      expect(
        find.textContaining('no automatic fallback or retry'),
        findsNothing,
      );
    },
  );

  testWidgets('shows only live provider reply and model provenance', (
    tester,
  ) async {
    final tutor = _FakeAiTutor();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
          aiTutor: tutor,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Welcome to the interview'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('ai-tutor-input')),
      'My name is Phet and I am a developer',
    );
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pumpAndSettle();

    expect(tutor.messages, ['My name is Phet and I am a developer']);
    expect(find.text('Live Gemini reply'), findsOneWidget);
    expect(find.text('ผู้ให้บริการ: gemini-test'), findsOneWidget);
    expect(find.textContaining('Grammar:'), findsNothing);
  });

  testWidgets('provider failure is explicit and never becomes canned success', (
    tester,
  ) async {
    final tutor = _FakeAiTutor()
      ..replyFailure = const AiTutorException(
        AiFailureCode.providerUnavailable,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
          aiTutor: tutor,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('ai-tutor-input')),
      'Hello',
    );
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ai-tutor-error')), findsOneWidget);
    expect(
      find.textContaining('greatest strength in team collaboration'),
      findsNothing,
    );
    expect(find.text('Live Gemini reply'), findsNothing);
  });

  testWidgets('microphone transcript comes from speech adapter', (
    tester,
  ) async {
    final speechGateway = _FakeSpeechGateway();
    final tutor = _FakeAiTutor();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
          aiTutor: tutor,
          speechPractice: SpeechPracticeUseCases(speechGateway),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
    await tester.pumpAndSettle();

    expect(tutor.messages, ['I have real project experience']);
    expect(find.text('Live Gemini reply'), findsOneWidget);
  });

  testWidgets('backgrounding cancels microphone', (tester) async {
    final speechGateway = _FakeSpeechGateway()..emitResult = false;
    final voice = VoiceUseCases(
      provider: _FakeVoice(),
      disposeProvider: () async {},
    );
    final speech = SpeechPracticeUseCases(speechGateway);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: AiTutorScreen(
            voice: voice,
            aiTutor: _FakeAiTutor(),
            speechPractice: speech,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(speechGateway.cancelCalls, 1);
      await tester.runAsync(() async {
        await speechGateway.cancelCompleted.future.timeout(
          const Duration(milliseconds: 250),
        );
        await Future<void>.delayed(Duration.zero);
      });
    } finally {
      if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() async {
        await Future.wait<void>([
          voice.dispose(),
          speech.dispose(),
        ]).timeout(const Duration(seconds: 2));
      });
    }
  });

  testWidgets(
    'lifecycle cleanup attempts voice stop after speech cancel failure',
    (tester) async {
      final speechGateway = _FakeSpeechGateway(
        emitResult: false,
        cancelError: StateError('recognizer cancel failed'),
      );
      final voiceProvider = _FakeVoice();
      final voice = VoiceUseCases(
        provider: voiceProvider,
        disposeProvider: () async {},
      );
      final speech = SpeechPracticeUseCases(speechGateway);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: AiTutorScreen(
              voice: voice,
              aiTutor: _FakeAiTutor(),
              speechPractice: speech,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.enterText(
          find.byKey(const ValueKey('ai-tutor-input')),
          'Please reply',
        );
        await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
        await tester.pump();
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
        await tester.pump();

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        await tester.runAsync(
          () => voiceProvider.stopEntered.future.timeout(
            const Duration(milliseconds: 250),
          ),
        );

        expect(speechGateway.cancelCalls, 1);
        expect(voiceProvider.stopCalls, 1);
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
    },
  );

  testWidgets('background cancels and fences an in-flight AI generation', (
    tester,
  ) async {
    final replyGate = Completer<void>();
    final tutor = _FakeAiTutor()
      ..replyGate = replyGate
      ..ignoreCancellation = true;
    final provider = _FakeVoice();
    final voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: AiTutorScreen(voice: voice, aiTutor: tutor),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('ai-tutor-input')),
        'late request',
      );
      await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
      await tester.pump();
      expect(tutor.lastCancellation, isNotNull);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(tutor.lastCancellation!.isCancelled, isTrue);
      replyGate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Live Gemini reply'), findsNothing);
      expect(provider.requests, isEmpty);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      if (!replyGate.isCompleted) replyGate.complete();
      if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(
        () => voice.dispose().timeout(const Duration(seconds: 1)),
      );
    }
  });

  testWidgets('unmount consumes a speech-session release failure', (
    tester,
  ) async {
    final speechGateway = _FakeSpeechGateway(
      emitResult: false,
      cancelError: StateError('recognizer release failed'),
    );
    final voice = VoiceUseCases(
      provider: _FakeVoice(),
      disposeProvider: () async {},
    );
    final speech = SpeechPracticeUseCases(speechGateway);
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: voice,
          aiTutor: _FakeAiTutor(),
          speechPractice: speech,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(
      () => speechGateway.cancelEntered.future.timeout(
        const Duration(milliseconds: 250),
      ),
    );

    expect(speechGateway.cancelCalls, 1);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      await voice.dispose().timeout(const Duration(seconds: 1));
      try {
        await speech.dispose().timeout(const Duration(seconds: 1));
      } on Object {
        // The recognizer cleanup failure is deliberately injected.
      }
    });
  });

  testWidgets(
    'speech facade rebind releases old session and uses replacement',
    (tester) async {
      final oldGateway = _FakeSpeechGateway()..emitResult = false;
      final newGateway = _FakeSpeechGateway()..emitResult = false;
      final voice = VoiceUseCases(
        provider: _FakeVoice(),
        disposeProvider: () async {},
      );
      Future<void> pump(SpeechPracticeUseCases speech) => tester.pumpWidget(
        MaterialApp(
          home: AiTutorScreen(
            voice: voice,
            aiTutor: _FakeAiTutor(),
            speechPractice: speech,
          ),
        ),
      );

      await pump(SpeechPracticeUseCases(oldGateway));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
      await tester.pump();
      expect(oldGateway.startCalls, 1);

      await pump(SpeechPracticeUseCases(newGateway));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
      await tester.pump();

      expect(oldGateway.cancelCalls, 1);
      expect(newGateway.startCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opening AI provider settings cancels active microphone', (
    tester,
  ) async {
    final speechGateway = _FakeSpeechGateway()..emitResult = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
          aiTutor: _FakeAiTutor(),
          speechPractice: SpeechPracticeUseCases(speechGateway),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
    await tester.pump();

    await tester.tap(find.byTooltip('AI provider settings'));
    await tester.pumpAndSettle();

    expect(speechGateway.cancelCalls, 1);
    final unavailableFinder = find.byType(ProductionFeatureUnavailable);
    expect(unavailableFinder, findsOneWidget);
    expect(
      tester.widget<ProductionFeatureUnavailable>(unavailableFinder).reason,
      ProductionFeatureUnavailableReason.missingRegistry,
    );
    expect(
      ModalRoute.of(tester.element(unavailableFinder))?.settings.name,
      'ai-tutor/settings',
    );
  });

  testWidgets('opening settings invalidates delayed reply and prevents TTS', (
    tester,
  ) async {
    final gate = Completer<void>();
    final tutor = _FakeAiTutor()..replyGate = gate;
    final voice = _FakeVoice();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(provider: voice, disposeProvider: () async {}),
          aiTutor: tutor,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-tutor-input')),
      'A delayed message',
    );
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pump();

    await tester.tap(find.byTooltip('AI provider settings'));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();

    expect(voice.requests, isEmpty);
    expect(find.text('Live Gemini reply'), findsNothing);
  });
}

final class _FakeAiTutor implements AiTutorController {
  final List<String> messages = [];
  AiTutorException? replyFailure;
  Completer<void>? replyGate;
  AiCancellation? lastCancellation;
  bool ignoreCancellation = false;
  bool hasKey = true;

  @override
  Future<void> configure({
    required String key,
    required bool providerConsent,
    required bool shareLearningSummary,
    required AiProviderId providerId,
    required String model,
    String? customBaseUrl,
    AiCancellation? cancellation,
  }) async {}

  @override
  Future<void> configureActiveModel({
    required String model,
    required bool shareLearningSummary,
    AiCancellation? cancellation,
  }) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<AiTutorSettingsStatus> loadSettings() async => AiTutorSettingsStatus(
    hasKey: hasKey,
    providerConsent: true,
    shareLearningSummary: false,
    providerId: AiProviderId.gemini,
    model: 'gemini-test',
  );

  @override
  Future<List<AiModel>> listModels({
    required AiProviderId providerId,
    required String key,
    String? customBaseUrl,
    AiCancellation? cancellation,
  }) async => const [AiModel(id: 'gemini-test')];

  @override
  Future<List<AiModel>> listModelsForActiveCredential({
    AiCancellation? cancellation,
  }) async => const [AiModel(id: 'gemini-test')];

  @override
  Future<void> removeKey() async {}

  @override
  Future<List<AiUsageSummary>> loadUsage() async => const [];

  @override
  Future<void> clearUsage() async {}

  @override
  Future<AiTutorReply> reply({
    required String scenario,
    required String learnerMessage,
    AiCancellation? cancellation,
  }) async {
    messages.add(learnerMessage);
    lastCancellation = cancellation;
    await replyGate?.future;
    if (!ignoreCancellation && cancellation?.isCancelled == true) {
      throw const AiTutorException(AiFailureCode.cancelled);
    }
    final failure = replyFailure;
    if (failure != null) throw failure;
    return AiTutorReply(
      text: 'Live Gemini reply',
      providerId: AiProviderId.gemini,
      model: 'gemini-test',
      generatedAtUtc: DateTime.utc(2026, 7, 30),
    );
  }

  @override
  Future<void> updateConsents({
    required bool providerConsent,
    required bool shareLearningSummary,
  }) async {}
}

final class _FakeSpeechGateway implements SpeechRecognitionGateway {
  _FakeSpeechGateway({this.emitResult = true, this.cancelError});

  bool emitResult;
  final Object? cancelError;
  final Completer<void> cancelEntered = Completer<void>();
  final Completer<void> cancelCompleted = Completer<void>();
  int cancelCalls = 0;
  int startCalls = 0;

  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    if (!cancelEntered.isCompleted) cancelEntered.complete();
    isListening = false;
    final error = cancelError;
    if (!cancelCompleted.isCompleted) cancelCompleted.complete();
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
    startCalls += 1;
    isListening = true;
    if (!emitResult) return;
    onEvent(
      SpeechRecognitionEvent(
        transcript: 'I have real project experience',
        isFinal: true,
        recognizedAtUtc: DateTime.utc(2026, 7, 30),
        engine: 'platform-speech-recognizer',
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
