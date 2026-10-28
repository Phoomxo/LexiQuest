import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/sentence_scramble_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

class FakeVoiceProvider implements VoiceProvider {
  final List<VoiceRequest> spokenRequests = [];

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    spokenRequests.add(request);
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
  testWidgets(
    'SentenceScrambleScreen allows word selection and sentence checking',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: SentenceScrambleScreen(
            targetSentence: 'cat is sleeping',
            voiceProvider: fakeVoice,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('เรียงประโยคภาษาอังกฤษ'), findsOneWidget);
      expect(fakeVoice.spokenRequests.length, 1);
    },
  );
}
