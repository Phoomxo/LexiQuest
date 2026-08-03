import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/screens/ai_tutor_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  testWidgets('shows only live provider reply and model provenance', (
    tester,
  ) async {
    final tutor = _FakeGeminiTutor();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(voice: VoiceUseCases(_FakeVoice()), geminiTutor: tutor),
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
    final tutor = _FakeGeminiTutor()
      ..replyFailure = const GeminiException(
        GeminiFailureCode.providerUnavailable,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(voice: VoiceUseCases(_FakeVoice()), geminiTutor: tutor),
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
    final tutor = _FakeGeminiTutor();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: tutor,
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
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: _FakeGeminiTutor(),
          speechPractice: SpeechPracticeUseCases(speechGateway),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(speechGateway.cancelCalls, 1);
  });

  testWidgets('opening Gemini settings cancels active microphone', (
    tester,
  ) async {
    final speechGateway = _FakeSpeechGateway()..emitResult = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: _FakeGeminiTutor(),
          speechPractice: SpeechPracticeUseCases(speechGateway),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
    await tester.pump();

    await tester.tap(find.byTooltip('ตั้งค่า Gemini'));
    await tester.pumpAndSettle();

    expect(speechGateway.cancelCalls, 1);
    expect(find.text('Gemini BYOK'), findsOneWidget);
  });

  testWidgets('opening settings invalidates delayed reply and prevents TTS', (
    tester,
  ) async {
    final gate = Completer<void>();
    final tutor = _FakeGeminiTutor()..replyGate = gate;
    final voice = _FakeVoice();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(voice: VoiceUseCases(voice), geminiTutor: tutor),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-tutor-input')),
      'A delayed message',
    );
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pump();

    await tester.tap(find.byTooltip('ตั้งค่า Gemini'));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();

    expect(voice.requests, isEmpty);
    expect(find.text('Live Gemini reply'), findsNothing);
  });
}

final class _FakeGeminiTutor implements GeminiTutorController {
  final List<String> messages = [];
  GeminiException? replyFailure;
  Completer<void>? replyGate;
  bool hasKey = true;

  @override
  Future<void> configure({
    required String key,
    required bool providerConsent,
    required bool shareLearningSummary,
    GeminiCancellation? cancellation,
  }) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<GeminiSettingsStatus> loadSettings() async => GeminiSettingsStatus(
    hasKey: hasKey,
    providerConsent: true,
    shareLearningSummary: false,
  );

  @override
  Future<void> removeKey() async {}

  @override
  Future<GeminiTutorReply> reply({
    required String scenario,
    required String learnerMessage,
    GeminiCancellation? cancellation,
  }) async {
    messages.add(learnerMessage);
    await replyGate?.future;
    final failure = replyFailure;
    if (failure != null) throw failure;
    return GeminiTutorReply(
      text: 'Live Gemini reply',
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
  bool emitResult = true;
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
  Future<void> stop() async {}
}
