import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  testWidgets('AiTutorScreen renders scenario selector and sends messages', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();

    await tester.pumpWidget(
      MaterialApp(home: AiTutorScreen(voiceProvider: fakeVoice)),
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
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.textContaining('My name is Phet'), findsOneWidget);
    expect(find.textContaining('Grammar:'), findsOneWidget);
  });

  testWidgets('AiTutorScreen handles mic button tap for voice input', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();

    await tester.pumpWidget(
      MaterialApp(home: AiTutorScreen(voiceProvider: fakeVoice)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pump();

    expect(find.textContaining('กำลังฟังเสียงพูดของคุณ'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.textContaining('three years of experience'), findsOneWidget);
  });
}
