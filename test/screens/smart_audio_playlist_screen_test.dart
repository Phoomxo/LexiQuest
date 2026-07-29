import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/smart_audio_playlist_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

class FakeVoiceProvider implements VoiceProvider {
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
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
    'SmartAudioPlaylistScreen renders word and toggles play/pause button',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();
      final wordList = [
        {'word': 'apple', 'translation': 'แอปเปิ้ล', 'example': 'Red apple'},
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: SmartAudioPlaylistScreen(
            wordList: wordList,
            voiceProvider: fakeVoice,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('apple'), findsOneWidget);
      expect(find.text('เริ่มเล่นต่อเนื่อง'), findsOneWidget);

      await tester.tap(find.text('เริ่มเล่นต่อเนื่อง'));
      await tester.pump();

      expect(find.text('หยุดเล่น'), findsOneWidget);

      // Stop to cancel timer
      await tester.tap(find.text('หยุดเล่น'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
