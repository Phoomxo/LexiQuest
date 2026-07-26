import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/ai/content_provider.dart';
import 'package:vocab_learning_app/screens/ai_tutor_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

class FakeVoiceProvider implements VoiceProvider {
  final List<VoiceRequest> requests = [];

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests.add(request);
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.omniVoice,
      actualEngine: VoiceEngine.omniVoice,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {}
}

/// Deterministic fake content provider that returns a fixed reply, so the
/// screen's message flow is testable without AppConfig/HTTP.
class FakeContentProvider implements ContentProvider {
  final List<ContentRequest> requests = [];
  final String reply;

  FakeContentProvider({
    this.reply = 'Tell me more about your project experience.',
  });

  @override
  Future<ContentResponse> generate(ContentRequest request) async {
    requests.add(request);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return ContentResponse(
      text: reply,
      kind: request.kind,
      cefr: request.cefr,
      language: request.language,
      modelVersion: 'fake',
      cached: false,
    );
  }
}

void main() {
  testWidgets('AiTutorScreen renders scenario selector and sends messages', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();
    final fakeContent = FakeContentProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voiceProvider: fakeVoice,
          contentProvider: fakeContent,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('จำลองบทสนทนา AI Tutor'), findsOneWidget);
    expect(find.textContaining('Welcome to the interview'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'My name is Phet and I am a developer',
    );
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('My name is Phet'), findsOneWidget);
    expect(find.textContaining('Grammar:'), findsOneWidget);
    // The injected provider was actually called for the AI reply.
    expect(fakeContent.requests, hasLength(1));
  });

  testWidgets('AiTutorScreen falls back to canned reply when provider fails', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();
    final failingContent = _ThrowingContentProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voiceProvider: fakeVoice,
          contentProvider: failingContent,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    // The canned Job Interview fallback must appear so the screen never hangs.
    expect(
      find.textContaining('greatest strength in team collaboration'),
      findsOneWidget,
    );
  });

  testWidgets('AiTutorScreen handles mic button tap for voice input', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();
    final fakeContent = FakeContentProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voiceProvider: fakeVoice,
          contentProvider: fakeContent,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pump();

    expect(find.textContaining('กำลังฟังเสียงพูดของคุณ'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    expect(find.textContaining('three years of experience'), findsOneWidget);
  });
}

class _ThrowingContentProvider implements ContentProvider {
  @override
  Future<ContentResponse> generate(ContentRequest request) async {
    throw const AiFailure(
      category: AiFailureCategory.providerUnavailable,
      message: 'forced failure for test',
    );
  }
}
