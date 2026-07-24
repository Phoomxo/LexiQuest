import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/shadowing_challenge_screen.dart';
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
    'ShadowingChallengeScreen plays AI reference and toggles recording',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ShadowingChallengeScreen(
            referenceSentence: 'Practice makes perfect',
            voiceProvider: fakeVoice,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Practice makes perfect'), findsOneWidget);

      await tester.tap(find.text('ฟังเสียง AI (1.0x)'));
      await tester.pumpAndSettle();

      expect(fakeVoice.spokenRequests.length, 1);
      expect(fakeVoice.spokenRequests.first.text, 'Practice makes perfect');

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.stop), findsOneWidget);
    },
  );
}
